extends Node

signal race_started(target_article: String, start_article: String)
signal race_countdown_started()  # Emitted when countdown begins
signal race_countdown(number: int)  # 3, 2, 1, 0 (GO!)
signal race_won(winner_name: String, final_time: float)
signal race_ended(winner_peer_id: int, winner_name: String)
signal race_cancelled
## Emitted every second while a race is active. Connect to update a HUD timer.
signal race_timer_updated(elapsed_seconds: float)

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
var _winner_path: Array[String] = []  ## Path taken by the winner, sent from their client

## Global speed modifier for events (1.0 = normal, 1.5 = 50% faster, 0.6 = 40% slower)
var _global_speed_modifier: float = 1.0
## Timer scale for events (1.0 = normal, 0.5 = half speed, 2.0 = double speed)
var _timer_scale: float = 1.0
## Whether dashing is enabled (can be disabled by events)
var _dash_enabled: bool = true
var _hill_zone: Area3D = null
var _hill_pos: Vector3 = Vector3.ZERO
var _hill_radius: float = 0.0

func set_hill_zone(zone: Area3D, pos: Vector3, radius: float) -> void:
	_hill_zone = zone
	_hill_pos = pos
	_hill_radius = radius
	print("[RaceManager] Hill zone set at %s (radius %.1f)" % [pos, radius])

func clear_hill_zone() -> void:
	_hill_zone = null
	_hill_pos = Vector3.ZERO
	_hill_radius = 0.0
	print("[RaceManager] Hill zone cleared")

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

var _sudden_death: bool = false

## Target difficulty: "easy" | "medium" | "hard". Set by host, synced to all clients.
var _difficulty: String = "medium"
## When non-empty, target is drawn from this Wikipedia category instead of difficulty pool.
var _category_override: String = ""
## Seeded shuffle for vote candidates (same order for all players)
var _seeded_shuffle_enabled: bool = false
var _vote_seed: int = 0  # Random seed for vote shuffling

## Local path this client has walked during the current race.
## Sent to the server when the target article is reached.
var _local_visited_pages: Array[String] = []

## Server-side: tracks room history for each peer (anti-cheat)
var _player_room_history: Dictionary = {}  # peer_id -> Array[String]

func _ready() -> void:
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.peer_connected.connect(_on_peer_connected)
	SettingsEvents.set_current_room.connect(_on_local_room_changed)

	# Track player rooms for anti-cheat (server-side)
	if NetworkManager.is_server():
		NetworkManager.player_room_changed.connect(_on_player_room_changed)

	# Connect to EventBus for countdown state tracking
	if EventBus:
		EventBus.event_published.connect(_on_event_published)


func _on_event_published(event: EventBus.GameEvent) -> void:
	"""Listen for countdown events to track countdown state"""
	if event is EventBus.CountdownStartedEvent:
		_countdown_active = true
	elif event is EventBus.CountdownTickEvent:
		var tick_event = event as EventBus.CountdownTickEvent
		if tick_event.number < 0:
			_countdown_active = false
	elif event is EventBus.StateChangedEvent:
		# Reset countdown state when race starts
		var state_event = event as EventBus.StateChangedEvent
		if state_event.new_state == GameState.State.RACE_ACTIVE:
			_countdown_active = false


func _on_local_room_changed(room: String) -> void:
	if not is_race_active() or room == "Lobby":
		return
	_local_visited_pages.append(room)


func _on_player_room_changed(peer_id: int, room: String) -> void:
	"""Server-side: track player room transitions for anti-cheat"""
	if not NetworkManager.is_server() or not is_race_active():
		return
	if room == "Lobby":
		return  # Don't track lobby
	
	if not _player_room_history.has(peer_id):
		_player_room_history[peer_id] = []
	_player_room_history[peer_id].append(room)


func _process(delta: float) -> void:
	if _vote_active:
		if not _vote_timer_paused:
			_vote_timer -= delta
		if _vote_timer <= 0.0 and NetworkManager.is_server():
			_finish_vote()
		return

	if _state != State.ACTIVE:
		return

	# Apply timer scale modifier for events like Time Dilation and Double Time
	var time_delta = delta * _timer_scale
	
	# King of the Hill logic: Pause timer if player is outside the zone
	if _hill_zone and is_instance_valid(_hill_zone):
		var local_player = get_tree().get_first_node_in_group("local_player")
		if local_player:
			var dist = local_player.global_position.distance_to(_hill_pos)
			if dist > _hill_radius:
				# Outside zone: timer doesn't advance (or could advance faster as penalty)
				# Let's make it not advance to "maintain progress"
				time_delta = 0.0
	
	_elapsed_time += time_delta

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

func get_winner_path() -> Array[String]:
	## Returns the path the winner navigated, as received from their client.
	## Empty array until a race ends.
	return _winner_path

func get_state() -> State:
	return _state


## Returns elapsed race time in seconds (0.0 if no race is active).
func get_elapsed_time() -> float:
	return _elapsed_time

func get_race_time() -> float:
	"""Get current race time in seconds (for EventManager)"""
	return _elapsed_time

var _countdown_active: bool = false  # Track countdown state

func is_countdown_active() -> bool:
	"""Check if race countdown is currently active (3-2-1-GO)"""
	return _countdown_active

func _set_countdown_active(active: bool) -> void:
	"""Internal: Set countdown state (called by EventBus listener)"""
	_countdown_active = active

func leader_is_near_finish() -> bool:
	"""Check if race leader is close to finishing (for event suppression)"""
	# Simplified: return true if race time > 2 minutes
	return _elapsed_time > 120.0


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

	_vote_candidates = candidates.duplicate()

	# Apply seeded shuffle if enabled (same order for all players)
	if _seeded_shuffle_enabled and _vote_seed != 0:
		seed(_vote_seed)
		_vote_candidates.shuffle()
		seed(Time.get_ticks_msec())  # Re-seed random to avoid affecting other RNG

	_vote_start_article = start_article
	_votes.clear()
	_vote_active = true
	_vote_timer = VOTE_DURATION
	_vote_timer_paused = false  # always clear pause on new/rerolled vote
	_sync_vote_start.rpc(_vote_candidates)

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
	# Player votes
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

## Host enables/disables seeded shuffle for vote candidates
func set_seeded_shuffle_enabled(enabled: bool) -> void:
	_seeded_shuffle_enabled = enabled
	# Always generate a new seed when the setting changes (on or off)
	# This ensures all clients have the same seed for reproducible shuffling
	_vote_seed = randi()
	_sync_vote_settings.rpc(_difficulty, _category_override, _seeded_shuffle_enabled, _vote_seed)

func get_seeded_shuffle_enabled() -> bool:
	return _seeded_shuffle_enabled

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

@rpc("authority", "call_local", "reliable")
func _sync_vote_settings(difficulty: String, category: String, seeded_shuffle: bool, seed: int) -> void:
	"""Sync vote settings from server to all clients."""
	_difficulty = difficulty
	_category_override = category
	_seeded_shuffle_enabled = seeded_shuffle
	_vote_seed = seed

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
	_winner_peer_id = -1
	_winner_name = ""
	_winner_path.clear()
	_local_visited_pages.clear()
	_player_room_history.clear()  # Clear server-side tracking for new race
	_elapsed_time = 0.0
	_timer_signal_accumulator = 0.0

	# Pre-fetch backlinks for hint system (non-blocking, improves hint success rate)
	# Note: Backlinks are now fetched by Main.gd at race start, not here

	if OS.is_debug_build():
		print("RaceManager: Starting countdown to race...")
		print("RaceManager: Pre-fetching backlinks for hints...")

	# Start countdown on server
	_start_countdown(target_article, start_article)

func _start_countdown(target_article: String, start_article: String) -> void:
	## Run a 3-2-1-GO countdown before the race starts
	## Sync countdown to all clients so everyone sees it
	var countdown = 3
	const interval = 0.7  # 0.7 seconds between each number (faster)

	# Signal that countdown is starting (VoteHUD should hide)
	race_countdown_started.emit()
	EventBus.publish_countdown_started()
	print("RaceManager: Starting countdown: 3...")

	while countdown >= 0:
		# Always emit locally so single-player and the server itself receive the signal.
		race_countdown.emit(countdown)
		EventBus.publish_countdown_tick(countdown)
		if OS.is_debug_build():
			print("RaceManager: Countdown emit: ", countdown)
		# Only RPC to clients when multiplayer is actually running.
		# (Previously race_countdown.emit + _sync_countdown.rpc(call_local) fired twice
		# on the server in multiplayer — now we guard the rpc behind is_multiplayer_active.)
		if NetworkManager.is_multiplayer_active():
			_sync_countdown.rpc_id(0, countdown)

		await get_tree().create_timer(interval).timeout
		if countdown == 0:
			break
		countdown -= 1

	# Now start the actual race
	_state = State.ACTIVE
	_race_start_time = Time.get_unix_time_from_system()

	print("RaceManager: GO! Race started to '", target_article, "'")

	_sync_race_start.rpc(target_article, start_article, _race_start_time)
	race_started.emit(target_article, start_article)
	EventBus.publish_race_started(target_article, start_article)

@rpc("authority", "call_remote", "reliable")
func _sync_countdown(number: int) -> void:
	## Clients receive countdown ticks via this RPC.
	race_countdown.emit(number)

func notify_article_reached(peer_id: int, article_title: String, visited_path: Array = []) -> void:
	if _state != State.ACTIVE:
		return

	if article_title != _target_article:
		return

	# Server-side: validate path against tracked room history
	if NetworkManager.is_server():
		# Dictionary.get() returns untyped Array — assign via explicit typed local
		var raw_server_path: Array = _player_room_history.get(peer_id, [])
		var server_path: Array[String] = []
		for item in raw_server_path:
			server_path.append(str(item))

		var path: Array[String] = []

		if server_path.size() > 0:
			# Best case: server has tracked this peer's rooms (multiplayer anti-cheat path)
			for item in server_path:
				path.append(item)
		elif visited_path.size() > 0:
			# Client provided a path (multiplayer client win RPC)
			for item in visited_path:
				path.append(str(item))
			if OS.is_debug_build():
				print("RaceManager: Using client-provided path (server tracking unavailable)")
		else:
			# Single player: NetworkManager.is_multiplayer_active() is false so
			# set_local_player_room is never called and _player_room_history stays empty.
			# Use _local_visited_pages which is populated via SettingsEvents.set_current_room.
			for item in _local_visited_pages:
				path.append(item)
			if OS.is_debug_build():
				print("RaceManager: Using local visited pages (single player path)")

		# Require at least one room visited to prevent teleport/void exploits.
		if path.is_empty():
			if OS.is_debug_build():
				print("RaceManager: Blocked win — empty path for '%s'" % article_title)
			return

		var winner_path_copy: Array[String] = []
		for item in path:
			winner_path_copy.append(item)
		_winner_path = winner_path_copy
		_handle_win(peer_id)
	else:
		# Client: send path to server for validation
		_request_win_validation.rpc_id(1, peer_id, article_title, visited_path)

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

	# Emit race_won signal for victory sound
	race_won.emit(_winner_name, final_time)

	_sync_race_end.rpc(peer_id, _winner_name, final_time, _winner_path)
	race_ended.emit(peer_id, _winner_name)

func force_start_race() -> void:
	"""Host can force race to start immediately (skips remaining vote time)."""
	if not _vote_active:
		return  # Can only force start during voting
	
	if not NetworkManager.is_server():
		return
	
	# End vote immediately and start race
	_finish_vote()

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
func _sync_race_end(winner_peer_id: int, winner_name: String, final_time: float, winner_path: Array = []) -> void:
	_state = State.IDLE
	_winner_peer_id = winner_peer_id
	_winner_name = winner_name
	_winner_path.assign(winner_path)
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
func _request_win_validation(peer_id: int, article_title: String, visited_path: Array = []) -> void:
	if not NetworkManager.is_server():
		return

	if _state != State.ACTIVE:
		return

	if article_title != _target_article:
		Log.warn("RaceManager", "Win rejected - wrong target '%s' (expected '%s')" % [article_title, _target_article])
		return

	# Server-side: validate path against tracked room history
	var server_path: Array[String] = []
	var raw_server_path: Array = _player_room_history.get(peer_id, [])
	for item in raw_server_path:
		server_path.append(str(item))

	var path: Array[String] = []

	if server_path.size() > 0:
		# Use server-tracked path (anti-cheat)
		for item in server_path:
			path.append(item)
	elif visited_path.size() > 0:
		# Fallback: client provided path (server tracking unavailable)
		# This can happen if the player joined late or tracking failed
		for item in visited_path:
			path.append(str(item))
		Log.warn("RaceManager", "Using client-provided path for peer %d (server tracking unavailable)" % peer_id)
	else:
		# No path available - reject the win
		Log.warn("RaceManager", "Win rejected for peer %d - no path data available" % peer_id)
		return

	# Require at least one room visited to prevent teleport/void exploits
	if path.is_empty():
		Log.warn("RaceManager", "Win rejected for peer %d - empty path" % peer_id)
		return

	# Validate path connectivity (anti-cheat: detect impossible jumps)
	if not _validate_path_continuity(path):
		Log.warn("RaceManager", "Win rejected for peer %d - invalid path (teleport detected?)" % peer_id)
		return

	var winner_path_copy: Array[String] = []
	for item in path:
		winner_path_copy.append(item)
	_winner_path = winner_path_copy
	_handle_win(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_race_cancel() -> void:
	if not NetworkManager.is_server():
		return

	cancel_race()

# === Host Menu Support Methods ===

func skip_countdown() -> void:
	"""Skip countdown and start race immediately"""
	# Just emit race started directly to skip remaining countdown
	race_started.emit(_target_article, _start_article)

func extend_vote_timer(seconds: int) -> void:
	"""Extend vote timer by specified seconds"""
	if _vote_active and _vote_timer > 0:
		_vote_timer += seconds

func force_vote_end() -> void:
	"""End voting immediately with current results"""
	if not _vote_active:
		return
	# Call the existing finish vote method
	_finish_vote()

func set_custom_target(target: String) -> void:
	"""Set custom race target article"""
	if target != "":
		_target_article = target

# ── Event API ────────────────────────────────────────────────────────────────

func set_global_speed_modifier(modifier: float) -> void:
	"""Set global speed modifier for all players (1.0 = normal, 1.5 = 50% faster, 0.6 = 40% slower)"""
	_global_speed_modifier = modifier
	# Broadcast to all clients so they apply the same modifier
	_rpc_set_speed_modifier.rpc(modifier)
	print("[RaceManager] Global speed modifier set to: %.2fx" % modifier)

func get_global_speed_modifier() -> float:
	"""Get current global speed modifier"""
	return _global_speed_modifier

@rpc("authority", "call_local", "reliable")
func _rpc_set_speed_modifier(modifier: float) -> void:
	# All clients receive this and apply locally
	_global_speed_modifier = modifier

func set_gravity_modifier(modifier: float) -> void:
	"""Set gravity modifier for all players (1.0 = normal, 0.3 = moon gravity)"""
	_rpc_set_gravity_modifier.rpc(modifier)
	print("[RaceManager] Gravity modifier set to: %.2f (MOON GRAVITY!)" % modifier)

@rpc("authority", "call_local", "reliable")
func _rpc_set_gravity_modifier(modifier: float) -> void:
	# All clients receive this and apply to their player
	var local_player = get_tree().get_first_node_in_group("local_player")
	if local_player and local_player.has_method("set_gravity_modifier"):
		local_player.set_gravity_modifier(modifier)

func set_double_jump_enabled(enabled: bool) -> void:
	"""Enable double jump for all players"""
	_rpc_set_double_jump.rpc(enabled)
	print("[RaceManager] Double jump: %s" % ["ENABLED" if enabled else "DISABLED"])

@rpc("authority", "call_local", "reliable")
func _rpc_set_double_jump(enabled: bool) -> void:
	var local_player = get_tree().get_first_node_in_group("local_player")
	if local_player and local_player.has_method("set_double_jump_enabled"):
		local_player.set_double_jump_enabled(enabled)

func set_triple_jump_enabled(enabled: bool) -> void:
	"""Enable triple jump for all players"""
	_rpc_set_triple_jump.rpc(enabled)
	print("[RaceManager] Triple jump: %s" % ["ENABLED" if enabled else "DISABLED"])

@rpc("authority", "call_local", "reliable")
func _rpc_set_triple_jump(enabled: bool) -> void:
	var local_player = get_tree().get_first_node_in_group("local_player")
	if local_player and local_player.has_method("set_triple_jump_enabled"):
		local_player.set_triple_jump_enabled(enabled)

func set_timer_scale(scale: float) -> void:
	"""Set race timer scale (1.0 = normal, 0.5 = half speed, 2.0 = double speed)"""
	_timer_scale = scale
	_rpc_set_timer_scale.rpc(scale)
	print("[RaceManager] Timer scale set to: %.2fx" % scale)

func get_timer_scale() -> float:
	return _timer_scale

@rpc("authority", "call_local", "reliable")
func _rpc_set_timer_scale(scale: float) -> void:
	_timer_scale = scale

func set_dash_enabled(enabled: bool) -> void:
	"""Enable or disable dashing (for events)"""
	_dash_enabled = enabled
	_rpc_set_dash_enabled.rpc(enabled)
	print("[RaceManager] Dash %s" % ("disabled" if not enabled else "enabled"))

func is_dash_enabled() -> bool:
	return _dash_enabled

@rpc("authority", "call_local", "reliable")
func _rpc_set_dash_enabled(enabled: bool) -> void:
	_dash_enabled = enabled


func set_sudden_death(enabled: bool) -> void:
	_sudden_death = enabled
	print("[RaceManager] Sudden Death %s" % ("enabled" if enabled else "disabled"))

func is_sudden_death_active() -> bool:
	return _sudden_death

func get_race_stats() -> Dictionary:
	"""Get current race statistics"""
	return {
		"time": _elapsed_time,
		"players": _player_room_history.size() if NetworkManager.is_server() else 0,
		"target": _target_article,
		"start": _start_article,
		"state": "ACTIVE" if _state == State.ACTIVE else "IDLE",
		"event_modifiers": {
			"speed": _global_speed_modifier,
			"timer_scale": _timer_scale,
			"dash_enabled": _dash_enabled,
			"kot_h": _hill_zone != null,
			"sudden_death": _sudden_death
		}
	}


# ── Anti-Cheat: Path Validation ──────────────────────────────────────────────

func _validate_path_continuity(path: Array[String]) -> bool:
	"""Validate that a path through exhibits is continuous (no teleportation).
	
	Checks that each consecutive pair of rooms in the path are actually connected.
	This prevents players from teleporting directly to the target.
	
	Returns true if path is valid, false if teleportation is detected.
	"""
	if path.size() < 2:
		return true  # Single room or empty path is valid (no movement needed)

	# Get the museum node to check exhibit connectivity
	var museum = _get_museum_node()
	if not museum:
		# Can't validate without museum - allow the path (fallback)
		Log.warn("RaceManager", "Path validation skipped - museum not found")
		return true

	# Check each consecutive pair of rooms
	for i in range(path.size() - 1):
		var from_room = path[i]
		var to_room = path[i + 1]
		
		if not _are_rooms_connected(museum, from_room, to_room):
			Log.debug("RaceManager", "Path invalid: '%s' not connected to '%s'" % [from_room, to_room])
			return false

	return true


func _get_museum_node() -> Node:
	"""Get the Museum node for path validation"""
	var main = get_tree().current_scene
	if main and main.has_node("Museum"):
		return main.get_node("Museum")
	return null


func _are_rooms_connected(museum: Node, from_room: String, to_room: String) -> bool:
	"""Check if two rooms are directly connected (share a door/hallway)."""
	# Get exhibit nodes
	var from_exhibit = _get_exhibit_by_title(museum, from_room)
	var to_exhibit = _get_exhibit_by_title(museum, to_room)
	
	if not from_exhibit or not to_exhibit:
		# If we can't find the exhibits, allow the transition
		# (rooms might be dynamically generated)
		return true
	
	# Check if from_exhibit has an exit to to_exhibit
	if "exits" in from_exhibit:
		var exits: Array = from_exhibit.exits
		for exit_hall in exits:
			if exit_hall and "to_title" in exit_hall:
				if exit_hall.to_title == to_room:
					return true
	
	# Check reverse connection (doors work both ways)
	if "exits" in to_exhibit:
		var exits: Array = to_exhibit.exits
		for exit_hall in exits:
			if exit_hall and "to_title" in exit_hall:
				if exit_hall.to_title == from_room:
					return true
	
	return false


func _get_exhibit_by_title(museum: Node, title: String) -> Node:
	"""Find an exhibit node by its title"""
	if title == "Lobby":
		return museum.get_node_or_null("Lobby")
	
	# Search through museum children for matching exhibit
	for child in museum.get_children():
		if "page_title" in child and child.page_title == title:
			return child
	
	return null
