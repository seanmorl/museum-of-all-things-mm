extends Node
## Server-side anti-cheat detection system.
## Detects speed hacks, teleportation, and impossible navigation.

# Speed detection thresholds
const MAX_WALK_SPEED: float = 6.0  # Slightly above normal walk speed
const MAX_DASH_SPEED: float = 12.0  # Slightly above dash speed
const MAX_GRAVITY_SPEED: float = 30.0  # Maximum falling speed
const SPEED_CHECK_WINDOW: float = 0.5  # Check average speed over this window

# Teleport detection
const MAX_TELEPORT_DISTANCE: float = 10.0  # Max distance between position updates
const VALID_PATH_THRESHOLD: float = 15.0  # Max deviation from valid path

# Position tracking
var _player_position_history: Dictionary = {}  # peer_id -> Array of {position, timestamp}
var _player_speed_violations: Dictionary = {}  # peer_id -> violation count
var _player_teleport_violations: Dictionary = {}  # peer_id -> violation count

# Configuration
var _auto_kick_enabled: bool = true
var _max_speed_violations: int = 5
var _max_teleport_violations: int = 3
var _violation_decay_time: float = 60.0  # Violations decay after this many seconds

signal speed_hack_detected(peer_id: int, speed: float)
signal teleport_detected(peer_id: int, distance: float)
signal invalid_path_detected(peer_id: int, path: Array)
signal player_flagged(peer_id: int, reason: String)
signal player_kicked(peer_id: int, reason: String)

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	# Decay old violations
	_decay_violations(delta)

func track_position(peer_id: int, position: Vector3, timestamp: float) -> void:
	"""Track player position for anti-cheat analysis"""
	if not _player_position_history.has(peer_id):
		_player_position_history[peer_id] = []
	
	var history: Array = _player_position_history[peer_id]
	history.append({"position": position, "timestamp": timestamp})
	
	# Keep last 10 seconds of history
	var cutoff = timestamp - 10.0
	while history.size() > 0 and history[0]["timestamp"] < cutoff:
		history.pop_front()
	
	# Check for violations
	_check_speed_violations(peer_id)
	_check_teleport_violations(peer_id)

func _check_speed_violations(peer_id: int) -> void:
	"""Check if player is moving too fast"""
	var history: Array = _player_position_history.get(peer_id, [])
	if history.size() < 2:
		return
	
	# Calculate speed over last few positions
	var recent = history.slice(-10)
	if recent.size() < 2:
		return
	
	var first = recent[0]
	var last = recent[-1]
	var time_diff = last["timestamp"] - first["timestamp"]
	
	if time_diff <= 0:
		return
	
	var distance = first["position"].distance_to(last["position"])
	var speed = distance / time_diff
	
	# Allow for dash speed with some tolerance
	var max_allowed_speed = MAX_DASH_SPEED * 1.2  # 20% tolerance
	
	if speed > max_allowed_speed:
		_record_speed_violation(peer_id, speed)

func _record_speed_violation(peer_id: int, speed: float) -> void:
	"""Record a speed violation"""
	if not _player_speed_violations.has(peer_id):
		_player_speed_violations[peer_id] = 0
	
	_player_speed_violations[peer_id] += 1
	speed_hack_detected.emit(peer_id, speed)

	Log.warn("AntiCheat", "Player %d speed violation: %.2f units/s (count: %d)" % [peer_id, speed, _player_speed_violations[peer_id]])
	
	if _auto_kick_enabled and _player_speed_violations[peer_id] >= _max_speed_violations:
		_kick_player(peer_id, "Speed hacking detected")

func _check_teleport_violations(peer_id: int) -> void:
	"""Check if player teleported"""
	var history: Array = _player_position_history.get(peer_id, [])
	if history.size() < 2:
		return
	
	var last = history[-1]
	var second_last = history[-2]
	
	var distance = last["position"].distance_to(second_last["position"])
	var time_diff = last["timestamp"] - second_last["timestamp"]
	
	# Allow for very fast movement if enough time passed
	var max_instant_distance = MAX_TELEPORT_DISTANCE
	if time_diff > 0.5:
		max_instant_distance = MAX_DASH_SPEED * time_diff * 1.5
	
	if distance > max_instant_distance:
		_record_teleport_violation(peer_id, distance)

func _record_teleport_violation(peer_id: int, distance: float) -> void:
	"""Record a teleport violation"""
	if not _player_teleport_violations.has(peer_id):
		_player_teleport_violations[peer_id] = 0
	
	_player_teleport_violations[peer_id] += 1
	teleport_detected.emit(peer_id, distance)

	Log.warn("AntiCheat", "Player %d teleport violation: %.2f units (count: %d)" % [peer_id, distance, _player_teleport_violations[peer_id]])
	
	if _auto_kick_enabled and _player_teleport_violations[peer_id] >= _max_teleport_violations:
		_kick_player(peer_id, "Teleportation detected")

func validate_path(peer_id: int, path: Array[String]) -> bool:
	"""Validate that a player's path is physically possible"""
	if path.size() < 2:
		return true  # Can't validate with less than 2 points
	
	var history: Array = _player_position_history.get(peer_id, [])
	if history.size() < path.size():
		return true  # Don't have enough history to validate
	
	# Check that path length matches approximate distance traveled
	var total_path_length = 0
	for i in range(1, path.size()):
		# Simplified validation - in production, you'd check actual room connectivity
		total_path_length += 1  # Assume each room is ~1 unit apart
	
	# Compare with actual distance traveled in same timeframe
	if history.size() > 0:
		var first_pos = history[0]["position"]
		var last_pos = history[-1]["position"]
		var actual_distance = first_pos.distance_to(last_pos)
		
		# Path should be at least as long as direct distance
		if total_path_length < actual_distance * 0.5:
			invalid_path_detected.emit(peer_id, path)
			return false
	
	return true

func _decay_violations(delta: float) -> void:
	"""Decay violation counts over time"""
	# This is simplified - in production you'd track timestamps per violation
	for peer_id in _player_speed_violations.keys():
		_player_speed_violations[peer_id] = max(0, _player_speed_violations[peer_id] - delta * 0.1)
	
	for peer_id in _player_teleport_violations.keys():
		_player_teleport_violations[peer_id] = max(0, _player_teleport_violations[peer_id] - delta * 0.1)

func _kick_player(peer_id: int, reason: String) -> void:
	"""Kick a player for cheating"""
	player_flagged.emit(peer_id, reason)
	player_kicked.emit(peer_id, reason)

	Log.warn("AntiCheat", "Kicking player %d: %s" % [peer_id, reason])
	
	# Use NetworkManager to kick
	if NetworkManager and NetworkManager.is_server():
		NetworkManager.kick_peer(peer_id)

func clear_player(peer_id: int) -> void:
	"""Clear all tracking data for a player"""
	_player_position_history.erase(peer_id)
	_player_speed_violations.erase(peer_id)
	_player_teleport_violations.erase(peer_id)

func get_violation_count(peer_id: int) -> Dictionary:
	"""Get violation counts for a player"""
	return {
		"speed": _player_speed_violations.get(peer_id, 0),
		"teleport": _player_teleport_violations.get(peer_id, 0)
	}

func set_auto_kick_enabled(enabled: bool) -> void:
	_auto_kick_enabled = enabled

func is_auto_kick_enabled() -> bool:
	return _auto_kick_enabled

func reset() -> void:
	"""Reset all tracking data"""
	_player_position_history.clear()
	_player_speed_violations.clear()
	_player_teleport_violations.clear()
