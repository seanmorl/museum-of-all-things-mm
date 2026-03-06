extends Node

signal race_started(target_article: String, start_article: String)
signal race_ended(winner_peer_id: int, winner_name: String)
signal race_cancelled
## Emitted every second while a race is active. Connect to update a HUD timer.
signal race_timer_updated(elapsed_seconds: float)
## Emitted on all peers when a vote round begins.
signal vote_started(candidates: Array)
## Emitted on all peers when vote results are in, just before race_started.
signal vote_ended(winner: String)

enum State { IDLE, ACTIVE }

var _state: State = State.IDLE
var _target_article: String = ""
var _start_article: String = ""
var _vote_start_article: String = ""
var _winner_peer_id: int = -1
var _winner_name: String = ""

## Time (Unix seconds) when the race started, set on every peer for accuracy.
var _race_start_time: float = 0.0

## Elapsed seconds since race start. Updated every frame while ACTIVE.
var _elapsed_time: float = 0.0

## Accumulated time for the once-per-second signal emit.
var _timer_signal_accumulator: float = 0.0

# --- Voting ---
## Candidate articles shown to players to vote for start exhibit.
var _vote_candidates: Array = []
## peer_id -> candidate index voted for.
var _votes: Dictionary = {}
## Seconds remaining in the vote window.
var _vote_timer: float = 0.0
var _vote_active: bool = false
const VOTE_DURATION: float = 20.0
const CANDIDATE_COUNT: int = 5

func _ready() -> void:
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.peer_connected.connect(_on_peer_connected)


func _process(delta: float) -> void:
	if _vote_active:
		_vote_timer -= delta
		if _vote_timer <= 0.0 and NetworkManager.is_server():
			_finish_vote()
		return

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

func get_start_article() -> String:
	return _start_article

func get_state() -> State:
	return _state


## Returns elapsed race time in seconds (0.0 if no race is active).
func get_elapsed_time() -> float:
	return _elapsed_time


## Returns elapsed time formatted as "MM:SS" for display in a HUD label.
func get_elapsed_time_string() -> String:
	var secs: int = int(_elapsed_time)
	return "%02d:%02d" % [secs / 60, secs % 60]

## Called by server once candidates are ready. Winner becomes the race target.
func begin_vote(candidates: Array, start_article: String = "") -> void:
	if not NetworkManager.is_server():
		return
	_vote_candidates = candidates
	_vote_start_article = start_article
	_votes.clear()
	_vote_active = true
	_vote_timer = VOTE_DURATION
	_sync_vote_start.rpc(candidates)

## Called by any peer to cast or change their vote (index into candidates array).
func cast_vote(candidate_index: int) -> void:
	if not _vote_active:
		return
	if NetworkManager.is_server():
		_receive_vote(multiplayer.get_unique_id(), candidate_index)
	else:
		_send_vote.rpc_id(1, candidate_index)

func _finish_vote() -> void:
	if not _vote_active:
		return
	_vote_active = false
	# Tally votes
	var tally: Dictionary = {}
	for idx in range(_vote_candidates.size()):
		tally[idx] = 0
	for pid in _votes:
		var v: int = _votes[pid]
		if tally.has(v):
			tally[v] += 1
	# Find winner (random tiebreak)
	var max_votes: int = 0
	for idx in tally:
		if tally[idx] > max_votes:
			max_votes = tally[idx]
	var winners: Array = []
	for idx in tally:
		if tally[idx] == max_votes:
			winners.append(idx)
	winners.shuffle()
	var winning_idx: int = winners[0]
	var winning_article: String = _vote_candidates[winning_idx]
	if OS.is_debug_build():
		print("RaceManager: Vote ended, target: ", winning_article)
	_sync_vote_end.rpc(winning_idx)
	start_race(winning_article, _vote_start_article)

func get_vote_candidates() -> Array:
	return _vote_candidates

func get_vote_time_remaining() -> float:
	return _vote_timer

func is_vote_active() -> bool:
	return _vote_active

@rpc("authority", "call_local", "reliable")
func _sync_vote_start(candidates: Array) -> void:
	_vote_candidates = candidates
	_votes.clear()
	_vote_active = true
	_vote_timer = VOTE_DURATION
	vote_started.emit(candidates)

@rpc("authority", "call_local", "reliable")
func _sync_vote_end(winning_idx: int) -> void:
	_vote_active = false
	vote_ended.emit(_vote_candidates[winning_idx])

@rpc("any_peer", "call_remote", "reliable")
func _send_vote(candidate_index: int) -> void:
	if not NetworkManager.is_server():
		return
	_receive_vote(multiplayer.get_remote_sender_id(), candidate_index)

func _receive_vote(peer_id: int, candidate_index: int) -> void:
	if candidate_index < 0 or candidate_index >= _vote_candidates.size():
		return
	_votes[peer_id] = candidate_index
	if OS.is_debug_build():
		print("RaceManager: Vote from peer ", peer_id, " for ", _vote_candidates[candidate_index])

func start_race(target_article: String, start_article: String) -> void:
	if not NetworkManager.is_server():
		Log.error("RaceManager", "Only the host can start a race")
		return

	if _state == State.ACTIVE:
		Log.error("RaceManager", "Race already active")
		return

	_target_article = target_article
	_start_article = start_article
	_state = State.ACTIVE
	_winner_peer_id = -1
	_winner_name = ""
	_race_start_time = Time.get_unix_time_from_system()
	_elapsed_time = 0.0
	_timer_signal_accumulator = 0.0

	if OS.is_debug_build():
		print("RaceManager: Starting race to find '", target_article, "'")

	_sync_race_start.rpc(target_article, start_article, _race_start_time)
	race_started.emit(target_article, start_article)

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
	_start_article = ""

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
		_start_article = ""
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
		_sync_race_state_to_peer.rpc_id(peer_id, _target_article, _start_article, _race_start_time)

@rpc("authority", "call_local", "reliable")
func _sync_race_start(target_article: String, start_article: String, start_time: float) -> void:
	_target_article = target_article
	_start_article = start_article
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
		race_started.emit(target_article, start_article)

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
	_start_article = ""
	_winner_peer_id = -1
	_winner_name = ""
	_elapsed_time = 0.0
	_timer_signal_accumulator = 0.0

	if not NetworkManager.is_server():
		race_cancelled.emit()

@rpc("authority", "call_remote", "reliable")
func _sync_race_state_to_peer(target_article: String, start_article: String, start_time: float) -> void:
	_target_article = target_article
	_start_article = start_article
	_state = State.ACTIVE
	_winner_peer_id = -1
	_winner_name = ""
	# Restore the original start time so late joiners see the real elapsed time
	_race_start_time = start_time
	_elapsed_time = Time.get_unix_time_from_system() - start_time
	_timer_signal_accumulator = 0.0

	if OS.is_debug_build():
		print("RaceManager: Late join - synced to race for '", target_article, "' (already ", "%.1f" % _elapsed_time, "s in)")

	race_started.emit(target_article, start_article)

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
