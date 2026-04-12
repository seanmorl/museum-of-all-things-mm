extends Camera3D
## Enhanced Spectator Camera System
## Provides free-fly, follow, and cinematic camera modes for spectating races

enum SpectatorMode { FREE_FLY, FOLLOW_PLAYER, CINEMATIC, TOP_DOWN }

var _mode: SpectatorMode = SpectatorMode.FREE_FLY
var _enabled: bool = false
var _target_player: Node3D = null
var _follow_offset: Vector3 = Vector3(0, 3, 8)
var _follow_smoothness: float = 5.0

# Free fly controls
var _fly_speed: float = 10.0
var _fly_speed_boost: float = 30.0
var _mouse_sensitivity: float = 0.002
var _rotation_x: float = 0.0
var _rotation_y: float = 0.0

# Cinematic mode
var _cinematic_path: Array[Vector3] = []
var _cinematic_index: int = 0
var _cinematic_timer: float = 0.0
var _cinematic_duration: float = 5.0

# Top-down mode
var _top_down_height: float = 20.0
var _top_down_zoom: float = 1.0

# UI
var _spectator_ui: Control = null
var _player_list: ItemList = null
var _mode_label: Label = null

signal mode_changed(mode: SpectatorMode)
signal target_changed(target: Node3D)

func _ready() -> void:
	set_process_input(false)
	set_process(true)
	
	# Initialize rotation from current camera rotation
	_rotation_y = rotation.y
	_rotation_x = rotation.x

func _process(delta: float) -> void:
	if not _enabled:
		return
	
	match _mode:
		SpectatorMode.FREE_FLY:
			_process_free_fly(delta)
		SpectatorMode.FOLLOW_PLAYER:
			_process_follow(delta)
		SpectatorMode.CINEMATIC:
			_process_cinematic(delta)
		SpectatorMode.TOP_DOWN:
			_process_top_down(delta)

func _process_free_fly(delta: float) -> void:
	"""Free-fly camera movement"""
	var movement = Vector3.ZERO
	var speed = _fly_speed
	
	# Boost with shift
	if Input.is_key_pressed(KEY_SHIFT):
		speed = _fly_speed_boost
	
	# WASD movement
	if Input.is_key_pressed(KEY_W):
		movement.z -= 1
	if Input.is_key_pressed(KEY_S):
		movement.z += 1
	if Input.is_key_pressed(KEY_A):
		movement.x -= 1
	if Input.is_key_pressed(KEY_D):
		movement.x += 1
	
	# Q/E for up/down
	if Input.is_key_pressed(KEY_Q):
		movement.y -= 1
	if Input.is_key_pressed(KEY_E):
		movement.y += 1
	
	# Apply movement in camera direction
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	var up = Vector3.UP
	
	var move_dir = forward * movement.z + right * movement.x + up * movement.y
	if move_dir.length() > 0:
		move_dir = move_dir.normalized()
		global_position += move_dir * speed * delta

func _process_follow(delta: float) -> void:
	"""Follow a specific player"""
	if not _target_player or not is_instance_valid(_target_player):
		return
	
	var target_pos = _target_player.global_position + _follow_offset
	
	# Smooth follow
	global_position = global_position.lerp(target_pos, _follow_smoothness * delta)
	
	# Always look at player
	look_at(_target_player.global_position)

func _process_cinematic(delta: float) -> void:
	"""Cinematic camera path following"""
	if _cinematic_path.is_empty():
		return
	
	_cinematic_timer += delta
	var t = _cinematic_timer / _cinematic_duration
	
	if t >= 1.0:
		_cinematic_index = (_cinematic_index + 1) % _cinematic_path.size()
		_cinematic_timer = 0.0
		t = 0.0
	
	var current_point = _cinematic_path[_cinematic_index]
	var next_point = _cinematic_path[(_cinematic_index + 1) % _cinematic_path.size()]
	
	global_position = current_point.lerp(next_point, t)
	
	# Look at race center or target
	if _target_player and is_instance_valid(_target_player):
		look_at(_target_player.global_position)

func _process_top_down(delta: float) -> void:
	"""Top-down orthographic view"""
	if _target_player and is_instance_valid(_target_player):
		var target_pos = _target_player.global_position
		target_pos.y += _top_down_height * _top_down_zoom
		global_position = global_position.lerp(target_pos, _follow_smoothness * delta)
	
	# Look straight down
	var look_target = global_position
	look_target.y -= 1
	look_at(look_target)

func _input(event: InputEvent) -> void:
	if not _enabled:
		return
	
	if _mode == SpectatorMode.FREE_FLY:
		_handle_free_fly_input(event)

func _handle_free_fly_input(event: InputEvent) -> void:
	"""Handle mouse look for free-fly mode"""
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_rotation_y -= event.relative.x * _mouse_sensitivity
		_rotation_x -= event.relative.y * _mouse_sensitivity
		_rotation_x = clamp(_rotation_x, -PI / 2, PI / 2)
		
		rotation = Vector3(_rotation_x, _rotation_y, 0)

# Public API

func enable_spectator() -> void:
	"""Enable spectator mode"""
	_enabled = true
	set_process_input(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Log.debug("Spectator", "Enabled")

func disable_spectator() -> void:
	"""Disable spectator mode"""
	_enabled = false
	set_process_input(false)
	Log.debug("Spectator", "Disabled")

func set_mode(mode: SpectatorMode) -> void:
	"""Set spectator camera mode"""
	_mode = mode
	mode_changed.emit(mode)

	match mode:
		SpectatorMode.FREE_FLY:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		SpectatorMode.FOLLOW_PLAYER, SpectatorMode.CINEMATIC, SpectatorMode.TOP_DOWN:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	Log.debug("Spectator", "Mode changed to: %s" % SpectatorMode.keys()[mode])

func get_mode() -> SpectatorMode:
	"""Get current spectator mode"""
	return _mode

func set_target(player: Node3D) -> void:
	"""Set the player to follow"""
	_target_player = player
	target_changed.emit(player)
	Log.debug("Spectator", "Target set to: %s" % [player.name if player else "None"])

func get_target() -> Node3D:
	"""Get current follow target"""
	return _target_player

func cycle_mode() -> void:
	"""Cycle to next spectator mode"""
	var next_mode = (_mode as int + 1) % 4
	set_mode(next_mode)

func set_follow_offset(offset: Vector3) -> void:
	"""Set follow camera offset"""
	_follow_offset = offset

func set_fly_speed(speed: float) -> void:
	"""Set free-fly speed"""
	_fly_speed = speed

func set_mouse_sensitivity(sensitivity: float) -> void:
	"""Set mouse sensitivity for free-fly mode"""
	_mouse_sensitivity = sensitivity

func add_cinematic_point(position: Vector3) -> void:
	"""Add a point to the cinematic camera path"""
	_cinematic_path.append(position)
	Log.debug("Spectator", "Added cinematic point: %s" % position)

func clear_cinematic_path() -> void:
	"""Clear the cinematic camera path"""
	_cinematic_path.clear()
	_cinematic_index = 0
	_cinematic_timer = 0.0

func set_top_down_height(height: float) -> void:
	"""Set top-down view height"""
	_top_down_height = height

func set_top_down_zoom(zoom: float) -> void:
	"""Set top-down view zoom level"""
	_top_down_zoom = clamp(zoom, 0.5, 3.0)

func teleport_to_player(player: Node3D) -> void:
	"""Instantly teleport camera to player"""
	if not player:
		return
	
	_target_player = player
	global_position = player.global_position + _follow_offset
	look_at(player.global_position)

func get_spectator_info() -> Dictionary:
	"""Get current spectator state"""
	return {
		"enabled": _enabled,
		"mode": SpectatorMode.keys()[_mode],
		"position": global_position,
		"rotation": rotation,
		"target": _target_player.name if _target_player else "None"
	}

# Next player for follow mode

func follow_next_player() -> void:
	"""Cycle to next player in follow mode"""
	var players = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return
	
	if not _target_player:
		_target_player = players[0]
		return
	
	var current_idx = players.find(_target_player)
	var next_idx = (current_idx + 1) % players.size()
	_target_player = players[next_idx]
	target_changed.emit(_target_player)

func follow_previous_player() -> void:
	"""Cycle to previous player in follow mode"""
	var players = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return
	
	if not _target_player:
		_target_player = players[0]
		return
	
	var current_idx = players.find(_target_player)
	var prev_idx = (current_idx - 1 + players.size()) % players.size()
	_target_player = players[prev_idx]
	target_changed.emit(_target_player)
