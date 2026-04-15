extends Node
class_name RaceService
## Manages race lifecycle: starting, finishing, validation, and leaderboards.
## Provides a clean API for race operations without coupling to RaceManager.

signal race_started(target: String, start: String)
signal race_finished(winner: String, time: float)
signal race_cancelled()
signal race_validated(peer_id: int, valid: bool, reason: String)

var _race_active: bool = false
var _race_target: String = ""
var _race_start: String = ""
var _race_start_time: float = 0.0
var _race_elapsed: float = 0.0
var _race_winner: String = ""
var _race_winner_time: float = 0.0
var _player_paths: Dictionary = {}  # peer_id -> Array[String] (path taken)
var _leaderboard: Array[Dictionary] = []  # [{name, time, date}, ...]

func _ready() -> void:
	# @deprecated - This service is archived. Use RaceManager directly.
	push_warning("RaceService is deprecated. Use RaceManager directly.")
	pass

func initialize() -> void:
	"""Initialize race service."""
	_reset_race_state()
	print("RaceService: Initialized")

# --- Race Lifecycle ---

func start_race(target: String, start: String) -> void:
	"""Start a new race."""
	if _race_active:
		print("RaceService: Race already active!")
		return
	
	print("RaceService: Starting race to '", target, "' from '", start, "'")
	_reset_race_state()
	_race_active = true
	_race_target = target
	_race_start = start
	_race_start_time = Time.get_unix_time_from_system()
	_race_elapsed = 0.0
	
	race_started.emit(target, start)

func finish_race(winner_name: String, winner_time: float) -> void:
	"""Finish the race with a winner."""
	if not _race_active:
		return
	
	print("RaceService: Race finished! Winner: ", winner_name, " in ", winner_time, "s")
	_race_active = false
	_race_winner = winner_name
	_race_winner_time = winner_time
	
	# Add to leaderboard
	_add_to_leaderboard(winner_name, winner_time)
	
	race_finished.emit(winner_name, winner_time)

func cancel_race() -> void:
	"""Cancel the current race."""
	if not _race_active:
		return
	
	print("RaceService: Race cancelled")
	_reset_race_state()
	race_cancelled.emit()

# --- Validation ---

func validate_win(peer_id: int, path: Array[String]) -> bool:
	"""Validate if a player's path constitutes a valid win."""
	if not _race_active:
		return false
	
	# Store player's path
	_player_paths[peer_id] = path
	
	# Check if path ends at target
	if path.is_empty() or path[-1] != _race_target:
		print("RaceService: Invalid win - path doesn't end at target")
		race_validated.emit(peer_id, false, "Path doesn't end at target")
		return false
	
	# Check if path starts at start
	if path[0] != _race_start:
		print("RaceService: Invalid win - path doesn't start at start")
		race_validated.emit(peer_id, false, "Path doesn't start at start")
		return false
	
	# Check for valid transitions (each room should be reachable from previous)
	# This is a simplified check - full validation would check exhibit connectivity
	for i in range(1, path.size()):
		if not _is_valid_transition(path[i-1], path[i]):
			print("RaceService: Invalid win - invalid transition from ", path[i-1], " to ", path[i])
			race_validated.emit(peer_id, false, "Invalid room transition")
			return false
	
	print("RaceService: Valid win for peer ", peer_id)
	race_validated.emit(peer_id, true, "Valid")
	return true

func _is_valid_transition(from_room: String, to_room: String) -> bool:
	"""Check if transition between rooms is valid (simplified)."""
	# In a full implementation, this would check exhibit connectivity
	# For now, we allow any transition (could be tightened for anti-cheat)
	return true

# --- Leaderboard ---

func _add_to_leaderboard(name: String, time: float) -> void:
	"""Add a race result to the leaderboard."""
	var entry = {
		"name": name,
		"time": time,
		"date": Time.get_datetime_string_from_system()
	}
	_leaderboard.append(entry)
	
	# Sort by time (ascending)
	_leaderboard.sort_custom(func(a, b): return a.time < b.time)
	
	# Keep top 100
	if _leaderboard.size() > 100:
		_leaderboard.resize(100)

func get_leaderboard() -> Array[Dictionary]:
	"""Get the current leaderboard."""
	return _leaderboard.duplicate()

func get_personal_best() -> float:
	"""Get the local player's best time."""
	# In a full implementation, this would filter by local player name
	if _leaderboard.is_empty():
		return 0.0
	return _leaderboard[0].time

# --- Queries ---

func is_race_active() -> bool:
	return _race_active

func get_race_target() -> String:
	return _race_target

func get_race_start() -> String:
	return _race_start

func get_race_elapsed() -> float:
	if not _race_active:
		return 0.0
	return Time.get_unix_time_from_system() - _race_start_time

func get_race_winner() -> String:
	return _race_winner

func get_race_winner_time() -> float:
	return _race_winner_time

func get_player_path(peer_id: int) -> Array[String]:
	return _player_paths.get(peer_id, [])

# --- Helpers ---

func _reset_race_state() -> void:
	"""Reset all race state."""
	_race_active = false
	_race_target = ""
	_race_start = ""
	_race_start_time = 0.0
	_race_elapsed = 0.0
	_race_winner = ""
	_race_winner_time = 0.0
	_player_paths.clear()

# --- Cleanup ---

func _exit_tree() -> void:
	_reset_race_state()
	_leaderboard.clear()
