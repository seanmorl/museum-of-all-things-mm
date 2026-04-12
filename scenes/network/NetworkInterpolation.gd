extends Node
## Network interpolation for smooth remote player movement.
## Receives position updates at 60Hz and interpolates between them.

class NetworkState:
	var position: Vector3
	var rotation: Vector3
	var pivot_rotation_x: float
	var pivot_position_y: float
	var timestamp: float
	var is_crouching: bool
	
	func _init(pos: Vector3, rot: Vector3, pivot_rot_x: float, pivot_pos_y: float, time: float, crouching: bool):
		self.position = pos
		self.rotation = rot
		self.pivot_rotation_x = pivot_rot_x
		self.pivot_position_y = pivot_pos_y
		self.timestamp = time
		self.is_crouching = crouching

# State buffer for interpolation
var _state_buffer: Array[NetworkState] = []
var _buffer_size: int = 2  # Number of states to buffer
var _interpolation_delay: float = 0.05  # 50ms delay for smooth interpolation

# Current interpolation state
var _current_state: NetworkState = null
var _target_state: NetworkState = null
var _interpolation_t: float = 0.0

# Settings
var _interpolation_speed: float = 15.0
var _snap_distance: float = 5.0  # Teleport if farther than this
var _update_rate: float = 60.0  # Target 60 updates per second

signal state_updated(position: Vector3, rotation: Vector3)

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if _current_state == null or _target_state == null:
		return
	
	# Advance interpolation
	_interpolation_t += delta * _interpolation_speed
	
	if _interpolation_t >= 1.0:
		# Reached target - shift buffer
		_shift_buffer()
	
	# Interpolate position
	if _current_state and _target_state:
		var t = _interpolation_t
		var lerp_pos = _current_state.position.lerp(_target_state.position, t)
		var lerp_rot = Vector2(
			lerp_angle(_current_state.rotation.x, _target_state.rotation.x, t),
			lerp_angle(_current_state.rotation.y, _target_state.rotation.y, t)
		)
		
		state_updated.emit(lerp_pos, Vector3(0, lerp_rot.y, 0))

func receive_state(position: Vector3, rotation: Vector3, pivot_rot_x: float, pivot_pos_y: float, is_crouching: bool) -> void:
	"""Receive a new network state from a remote player"""
	var new_state = NetworkState.new(
		position,
		rotation,
		pivot_rot_x,
		pivot_pos_y,
		Time.get_ticks_msec() / 1000.0,
		is_crouching
	)
	
	_state_buffer.append(new_state)
	
	# Initialize if first state
	if _current_state == null:
		_current_state = new_state
		_target_state = new_state
		_interpolation_t = 1.0
		return
	
	# Maintain buffer size
	while _state_buffer.size() > _buffer_size + 2:
		_state_buffer.pop_front()
	
	# Check for snap (teleportation)
	if _should_snap(position):
		_snap_to_position(position, rotation)
		return

func _shift_buffer() -> void:
	"""Shift the interpolation buffer forward"""
	if _state_buffer.size() >= 2:
		_state_buffer.pop_front()
		_current_state = _state_buffer[0]
		_target_state = _state_buffer[1] if _state_buffer.size() > 1 else _current_state
		_interpolation_t = 0.0
	elif _state_buffer.size() == 1:
		_current_state = _state_buffer[0]
		_target_state = _current_state
		_interpolation_t = 1.0

func _should_snap(new_position: Vector3) -> bool:
	"""Check if we should snap to new position instead of interpolating"""
	if _current_state == null:
		return true
	
	var distance = _current_state.position.distance_to(new_position)
	return distance > _snap_distance

func _snap_to_position(position: Vector3, rotation: Vector3) -> void:
	"""Instantly snap to position"""
	_state_buffer.clear()
	_current_state = NetworkState.new(position, rotation, 0, 1.35, Time.get_ticks_msec() / 1000.0, false)
	_target_state = _current_state
	_interpolation_t = 1.0
	state_updated.emit(position, rotation)

func get_interpolated_state() -> Dictionary:
	"""Get current interpolated state"""
	if _current_state == null:
		return {}
	
	return {
		"position": _current_state.position,
		"rotation": _current_state.rotation,
		"pivot_rotation_x": _current_state.pivot_rotation_x,
		"pivot_position_y": _current_state.pivot_position_y,
		"is_crouching": _current_state.is_crouching
	}

func clear() -> void:
	"""Clear all buffered state"""
	_state_buffer.clear()
	_current_state = null
	_target_state = null
	_interpolation_t = 0.0

func set_interpolation_speed(speed: float) -> void:
	_interpolation_speed = speed

func set_snap_distance(distance: float) -> void:
	_snap_distance = distance

func get_update_rate() -> float:
	return _update_rate
