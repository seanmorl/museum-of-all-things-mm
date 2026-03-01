extends Node

signal race_started(target_article: String)
signal race_ended(winner_peer_id: int, winner_name: String)
signal race_cancelled
## Emitted every second while a race is active. Connect to update a HUD timer.
signal race_timer_updated(elapsed_seconds: float)

enum State { IDLE, ACTIVE }

var _state: State = State.IDLE
var _target_article: String = ""
var _winner_peer_id: int = -1
var _winner_name: String = ""

## Time (Unix seconds) when the race started, set on every peer for accuracy.
var _race_start_time: float = 0.0

## Elapsed seconds since race start. Updated every frame while ACTIVE.
var _elapsed_time: float = 0.0

## Accumulated time for the once-per-second signal emit.
var _timer_signal_accumulator: float = 0.0

func _ready() -> void:
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.peer_connected.connect(_on_peer_connected)


func _process(delta: float) -> void:
	if _state != State.ACTIVE:
		return

	_elapsed_time = Time.get_unix_time_from_system() - _race_start_time

	# Emit once per second so HUD updates without hammering every frame
	_timer_signal_accumulator += delta
	if _timer_signal_accumulator >= 1.0:
		_timer_signal_accumulator -= 1.0
		race_timer_updated.emit(_elapsed_time)


func is_race_active() -> bool:
	return _state == State.ACTIVE

func get_target_article() -> String:
	return _target_article

func get_state() -> State:
	return _state


## Returns elapsed race time in seconds (0.0 if no race is active).
func get_elapsed_time() -> float:
	return _elapsed_time


## Returns elapsed time formatted as "MM:SS" for display in a HUD label.
func get_elapsed_time_string() -> String:
	var secs: int = int(_elapsed_time)
	return "%02d:%02d" % [secs / 60, secs % 60]

func start_race(target_article: String) -> void:
	if not NetworkManager.is_server():
		Log.error("RaceManager", "Only the host can start a race")
		return

	if _state == State.ACTIVE:
		Log.error("RaceManager", "Race already active")
		return

	_target_article = target_article
	_state = State.ACTIVE
	_winner_peer_id = -1
	_winner_name = ""
	_race_start_time = Time.get_unix_time_from_system()
	_elapsed_time = 0.0
	_timer_signal_accumulator = 0.0

	if OS.is_debug_build():
		print("RaceManager: Starting race to find '", target_article, "'")

	_sync_race_start.rpc(target_article, _race_start_time)
	race_started.emit(target_article)

func notify_article_reached(peer_id: int, article_title: String) -> void:
	if _state != State.ACTIVE:
		return

	if article_title != _target_article:
		return

	if NetworkManager.is_server():
		_handle_win(peer_id)
	else:
		_request_win_validation.rpc_id(1, peer_id, article_title)

func _handle_win(peer_id: int) -> void:
	if _state != State.ACTIVE:
		return

	_state = State.IDLE
	_winner_peer_id = peer_id
	_winner_name = NetworkManager.get_player_name(peer_id)

	var final_time: float = _elapsed_time
	_elapsed_time = 0.0
	_timer_signal_accumulator = 0.0

	if OS.is_debug_build():
		print("RaceManager: Winner is ", _winner_name, " (peer ", peer_id, ") in ", "%.1f" % final_time, "s")

	_sync_race_end.rpc(peer_id, _winner_name, final_time)
	race_ended.emit(peer_id, _winner_name)

func cancel_race() -> void:
	if _state != State.ACTIVE:
		return

	if NetworkManager.is_server():
		_state = State.IDLE
		_target_article = ""
		_winner_peer_id = -1
		_winner_name = ""
		_elapsed_time = 0.0
		_timer_signal_accumulator = 0.0
		_sync_race_cancel.rpc()
		race_cancelled.emit()
	else:
		_request_race_cancel.rpc_id(1)

func _on_server_disconnected() -> void:
	if _state == State.ACTIVE:
		cancel_race()

func _on_peer_connected(peer_id: int) -> void:
	if NetworkManager.is_server() and _state == State.ACTIVE:
		_sync_race_state_to_peer.rpc_id(peer_id, _target_article, _race_start_time)

@rpc("authority", "call_local", "reliable")
func _sync_race_start(target_article: String, start_time: float) -> void:
	_target_article = target_article
	_state = State.ACTIVE
	_winner_peer_id = -1
	_winner_name = ""
	# Use the server's timestamp so all peers share the same clock reference
	_race_start_time = start_time
	_elapsed_time = 0.0
	_timer_signal_accumulator = 0.0

	if OS.is_debug_build():
		print("RaceManager: Race started, target: ", target_article)

	if not NetworkManager.is_server():
		race_started.emit(target_article)

@rpc("authority", "call_local", "reliable")
func _sync_race_end(winner_peer_id: int, winner_name: String, final_time: float) -> void:
	_state = State.IDLE
	_winner_peer_id = winner_peer_id
	_winner_name = winner_name
	_elapsed_time = final_time
	_timer_signal_accumulator = 0.0

	if OS.is_debug_build():
		print("RaceManager: Race ended, winner: ", winner_name, " in ", "%.1f" % final_time, "s")

	if not NetworkManager.is_server():
		race_ended.emit(winner_peer_id, winner_name)

@rpc("authority", "call_local", "reliable")
func _sync_race_cancel() -> void:
	_state = State.IDLE
	_target_article = ""
	_winner_peer_id = -1
	_winner_name = ""
	_elapsed_time = 0.0
	_timer_signal_accumulator = 0.0

	if not NetworkManager.is_server():
		race_cancelled.emit()

@rpc("authority", "call_remote", "reliable")
func _sync_race_state_to_peer(target_article: String, start_time: float) -> void:
	_target_article = target_article
	_state = State.ACTIVE
	_winner_peer_id = -1
	_winner_name = ""
	# Restore the original start time so late joiners see the real elapsed time
	_race_start_time = start_time
	_elapsed_time = Time.get_unix_time_from_system() - start_time
	_timer_signal_accumulator = 0.0

	if OS.is_debug_build():
		print("RaceManager: Late join - synced to race for '", target_article, "' (already ", "%.1f" % _elapsed_time, "s in)")

	race_started.emit(target_article)

@rpc("any_peer", "call_remote", "reliable")
func _request_win_validation(peer_id: int, article_title: String) -> void:
	if not NetworkManager.is_server():
		return

	if _state != State.ACTIVE:
		return

	if article_title != _target_article:
		return

	_handle_win(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_race_cancel() -> void:
	if not NetworkManager.is_server():
		return

	cancel_race()
