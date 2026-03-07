extends Node

signal race_started(target_article: String, start_article: String)
signal race_ended(winner_peer_id: int, winner_name: String)
signal race_cancelled
## Emitted every second while a race is active. Connect to update a HUD timer.
signal race_timer_updated(elapsed_seconds: float)
## Emitted on all peers when a backlink hint is revealed during a race.
signal race_hint_revealed(hint_article: String, hint_number: int)
## Emitted on all peers when hint interval/mode is changed by the host.
signal hint_settings_changed(interval: float, manual: bool)

## Emitted on all peers when the host cancels the vote.
signal vote_cancelled
## Emitted on all peers when a vote round begins.
signal vote_started(candidates: Array)
## Emitted on all peers when vote results are in, just before race_started.
signal vote_ended(winner: String)
## Emitted on all peers when the host changes target difficulty.
signal difficulty_changed(difficulty: String)
## Emitted on all peers when the host sets or clears a category override.
signal category_override_changed(category_name: String)  ## empty string = no override

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
var _final_time: float = 0.0   ## preserved after race ends for journal recording

## Accumulated time for the once-per-second signal emit.
var _timer_signal_accumulator: float = 0.0

# --- Voting ---
## Candidate articles shown to players to vote for start exhibit.
var _vote_candidates: Array = []
## peer_id -> candidate index voted for.
var _votes: Dictionary = {}
## Seconds remaining in the vote window.
var _vote_timer: float = 0.0
var _vote_timer_paused: bool = false
var _vote_active: bool = false
const VOTE_DURATION: float = 20.0
const CANDIDATE_COUNT: int = 5

## Target difficulty: "easy" | "medium" | "hard". Set by host, synced to all clients.
var _difficulty: String = "medium"
## When non-empty, target is drawn from this Wikipedia category instead of difficulty pool.
var _category_override: String = ""

## Backlink hints — revealed to all players on a timer during the race.
var _hint_pool: Array = []         ## shuffled backlinks of the target
var _hints_revealed: Array = []    ## hints already shown (index 0 = first)
var _hint_timer: float = 0.0       ## counts up; hint drops every _hint_interval seconds
var _hint_interval: float = 600.0  ## default: 10 minutes
var _hint_manual: bool = false     ## if true, host triggers hints manually only
const MAX_HINTS: int = 5           ## cap so we don't spoil everything

func _ready() -> void:
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.peer_connected.connect(_on_peer_connected)


func _process(delta: float) -> void:
	if _vote_active:
		if not _vote_timer_paused:
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

	# Reveal a backlink hint every _hint_interval seconds (server only — synced via RPC)
	if NetworkManager.is_server() and _hint_pool.size() > 0 and not _hint_manual:
		_hint_timer += delta
		if _hint_timer >= _hint_interval and _hints_revealed.size() < MAX_HINTS:
			_hint_timer = 0.0
			var hint: String = _hint_pool.pop_front()
			_reveal_hint.rpc(hint, _hints_revealed.size() + 1)


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


func get_final_time() -> float:
	## The elapsed time of the last completed race (preserved after end).
	return _final_time


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
	_vote_timer_paused = false  # always clear pause on new/rerolled vote
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
		print("RaceManager: Vote ended, winning target: ", winning_article)
	_sync_vote_end.rpc(winning_idx)
	## winning_article = what players voted for = the race target
	## _vote_start_article = random article = where the door opens
	start_race(winning_article, _vote_start_article)

func get_vote_candidates() -> Array:
	return _vote_candidates

func get_vote_time_remaining() -> float:
	return _vote_timer

func set_vote_timer_paused(paused: bool) -> void:
	if NetworkManager.is_server():
		_vote_timer_paused = paused
	else:
		_rpc_set_vote_timer_paused.rpc_id(1, paused)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_vote_timer_paused(paused: bool) -> void:
	_vote_timer_paused = paused

## Host only. Cancels the active vote and notifies all peers.
func cancel_vote() -> void:
	if not NetworkManager.is_server():
		return
	if not _vote_active:
		return
	_sync_vote_cancel.rpc()

@rpc("authority", "call_local", "reliable")
func _sync_vote_cancel() -> void:
	_vote_active = false
	_vote_candidates.clear()
	_votes.clear()
	_vote_timer = 0.0
	vote_cancelled.emit()

func get_difficulty() -> String:
	return _difficulty

## Called by host only. Syncs the new difficulty to all peers.
func set_difficulty(difficulty: String) -> void:
	if not NetworkManager.is_server():
		return
	_sync_difficulty.rpc(difficulty)

@rpc("authority", "call_local", "reliable")
func _sync_difficulty(difficulty: String) -> void:
	_difficulty = difficulty
	difficulty_changed.emit(difficulty)

func get_category_override() -> String:
	return _category_override

## Set a Wikipedia category name to draw the target from. Empty string clears the override.
func set_category_override(category_name: String) -> void:
	if not NetworkManager.is_server():
		return
	_sync_category_override.rpc(category_name)

@rpc("authority", "call_local", "reliable")
func _sync_category_override(category_name: String) -> void:
	_category_override = category_name
	category_override_changed.emit(category_name)

## Called by Main after fetching backlinks for the target article.
## Only the server calls this; hints are revealed via RPC at _hint_interval.
func set_hint_pool(titles: Array) -> void:
	_hint_pool = titles.duplicate()
	_hint_pool.shuffle()
	_hint_pool = _hint_pool.slice(0, MAX_HINTS + 2)
	_hints_revealed.clear()
	_hint_timer = 0.0

## Host sets hint interval (seconds) and whether hints are manual-only.
## interval <= 0 means hints are disabled entirely.
func set_hint_settings(interval: float, manual: bool) -> void:
	if not NetworkManager.is_server():
		return
	_sync_hint_settings.rpc(interval, manual)

## Host manually reveals the next hint immediately.
func reveal_hint_now() -> bool:
	## Reveal next hint to all players. Returns false if no hints available.
	if not NetworkManager.is_server():
		return false
	if _hint_pool.is_empty() or _hints_revealed.size() >= MAX_HINTS:
		return false
	_hint_timer = 0.0
	var hint: String = _hint_pool.pop_front()
	_reveal_hint.rpc(hint, _hints_revealed.size() + 1)
	return true

func reveal_hint_to_peer(peer_id: int) -> void:
	## Reveal next hint privately to a specific peer only.
	if not NetworkManager.is_server():
		return
	if _hint_pool.is_empty() or _hints_revealed.size() >= MAX_HINTS:
		return
	var hint: String = _hint_pool[0]  # peek, don't consume — still available for everyone later
	var number: int = _hints_revealed.size() + 1
	if peer_id == multiplayer.get_unique_id():
		race_hint_revealed.emit(hint, number)
	else:
		_reveal_hint_private.rpc_id(peer_id, hint, number)

@rpc("authority", "call_local", "reliable")
func _sync_hint_settings(interval: float, manual: bool) -> void:
	_hint_interval = interval
	_hint_manual = manual
	hint_settings_changed.emit(interval, manual)

func get_hint_interval() -> float:
	return _hint_interval

func get_hint_manual() -> bool:
	return _hint_manual

func get_hints_revealed() -> Array:
	return _hints_revealed.duplicate()

@rpc("authority", "call_local", "reliable")
func _reveal_hint(hint_article: String, hint_number: int) -> void:
	_hints_revealed.append(hint_article)
	race_hint_revealed.emit(hint_article, hint_number)

@rpc("authority", "call_remote", "reliable")
func _reveal_hint_private(hint_article: String, hint_number: int) -> void:
	## Private hint — only the receiving peer sees this; not added to _hints_revealed.
	race_hint_revealed.emit(hint_article, hint_number)

func is_vote_active() -> bool:
	return _vote_active

@rpc("authority", "call_local", "reliable")
func _sync_vote_start(candidates: Array) -> void:
	_vote_candidates = candidates
	_votes.clear()
	_vote_active = true
	_vote_timer = VOTE_DURATION
	_vote_timer_paused = false  # clear on all peers, not just server
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
	_hint_timer = 0.0  # reset hint timer for new race

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
	_final_time = final_time
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
