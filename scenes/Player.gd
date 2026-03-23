extends CharacterBody3D
## Player controller with movement, crouching, mounting, and network interpolation support.
## Uses subsystems for crouch, mount, and skin functionality.

const INTERPOLATION_SPEED: float = 15.0
const TELEPORT_SNAP_THRESHOLD: float = 5.0
const BOB_FREQUENCY: float = 12.0
const BOB_AMPLITUDE: float = 0.05
const DEFAULT_PIVOT_Y: float = 1.35
const PITCH_CLAMP: float = 1.2

signal interactable_target_changed(target: Node)

var _gravity: float = -30.0
var _bob_time: float = 0.0
var _body_mesh_base_y: float = 0.667
var _crouch_move_speed: float = 4.0
var _mouse_sensitivity: float = 0.002
var _joy_sensitivity: float = 0.025
var _joy_deadzone: float = 0.05

@export var jump_impulse: float = 13.0
@export var is_local: bool = true
@export var smooth_movement: bool = false
@export var dampening: float = 0.01
@export var max_speed_walk: float = 5.0
@export var max_speed_dash: float = 10.0
@export var max_speed: float = 5.0

var player_name: String = "Player"
var _original_name: String = ""  # Stored when mounting to restore later
var current_room: String = "Lobby"
var in_hall: bool = false
var _enabled: bool = false
var _invert_y: bool = false
var _mouse_sensitivity_factor: float = 1.0
var _camera_v: Vector2 = Vector2.ZERO

var _joy_right_x: int = JOY_AXIS_RIGHT_X
var _joy_right_y: int = JOY_AXIS_RIGHT_Y

# Environmental event modifiers
var _double_jump_enabled: bool = false
var _triple_jump_enabled: bool = false
var _controls_inverted: bool = false
var _gravity_modifier: float = 1.0  # 1.0 = normal, 0.3 = moon gravity
var _jump_count: int = 0
var _max_jumps: int = 1

# Network interpolation for remote players
var _target_position: Vector3 = Vector3.ZERO
var _target_rotation_y: float = 0.0
var _target_pivot_rot_x: float = 0.0
var _target_pivot_pos_y: float = DEFAULT_PIVOT_Y
var _has_network_target: bool = false

var _last_interactable_target: Node = null

# Subsystems
var _crouch_system: PlayerCrouchSystem = null
var _mount_system: PlayerMountSystem = null
var _skin_system: PlayerSkinSystem = null
var _painting_system: PlayerPaintingSystem = null
var _pointing_system: PlayerPointingSystem = null
var _journal_system: PlayerJournalSystem = null
var _footprint_system: PlayerFootprintSystem = null
# ── ARCHIVED v0.5.0 - Powerups replaced with Environmental Events
# var _powerup_system: PlayerPowerupSystem = null

## Void detection - teleport player back to safety if they fall too far
var _void_check_timer: float = 0.0
var _last_valid_position: Vector3 = Vector3.ZERO  # Track last safe position
const VOID_Y_THRESHOLD: float = -50.0  # Below this = fallen into void
const VOID_CHECK_INTERVAL: float = 0.5  # Check every 0.5 seconds
const VOID_SPAWN_Y: float = 5.0  # Safe spawn height
const VOID_SPAWN_XZ: Vector2 = Vector2(0, 23)  # Start line XZ position

@onready var camera: Camera3D = $Pivot/Camera3D
@onready var _pivot: Node3D = $Pivot
@onready var _footstep_player: Node = $FootstepPlayer
@onready var _map_camera: Camera3D = get_node_or_null("MapCameraContainer/MapViewport/MapCamera")
@onready var _map_viewport: SubViewport = get_node_or_null("MapCameraContainer/MapViewport")
@onready var _raycast: RayCast3D = $Pivot/Camera3D/RayCast3D
@onready var _floor_raycast: RayCast3D = get_node_or_null("Pivot/Camera3D/FloorRayCast")
@onready var _multiplayer_sync: MultiplayerSynchronizer = get_node_or_null("MultiplayerSynchronizer")
@onready var _name_label: Label3D = get_node_or_null("NameLabel")
var _pronoun_label: Label3D = null
@onready var _body_mesh: MeshInstance3D = get_node_or_null("BodyMesh")
@onready var _head_mesh: MeshInstance3D = get_node_or_null("Pivot/HeadMesh")

var _owned_body_material: Material = null
var _owned_head_material: Material = null


func _ready() -> void:
	SettingsEvents.set_invert_y.connect(_set_invert_y)
	SettingsEvents.set_mouse_sensitivity.connect(_set_mouse_sensitivity)
	SettingsEvents.set_joypad_deadzone.connect(_set_joy_deadzone)

	# Override nameplate font to match the rest of the HUD
	if _name_label:
		_name_label.font = ThemeManager.get_reading_font()

	ThemeManager.reading_font_changed.connect(func(f):
		if _name_label: _name_label.font = f
		if _pronoun_label: _pronoun_label.font = f
	)

	if _body_mesh:
		_body_mesh_base_y = _body_mesh.position.y

	if is_local:
		add_to_group("local_player")
		# Ensure host player is visible to other clients in multiplayer
		set_body_visible(true)

	# Initialize subsystems
	_crouch_system = PlayerCrouchSystem.new()
	_crouch_system.init(self)
	add_child(_crouch_system)

	_mount_system = PlayerMountSystem.new()
	_mount_system.init(self, _crouch_system)
	_mount_system.mount_requested.connect(_on_mount_requested)
	_mount_system.dismount_requested.connect(_on_dismount_requested)
	add_child(_mount_system)

	_skin_system = PlayerSkinSystem.new()
	_skin_system.init(self)
	add_child(_skin_system)

	_painting_system = PlayerPaintingSystem.new()
	_painting_system.init(self)
	_painting_system.steal_requested.connect(_on_steal_requested)
	_painting_system.place_requested.connect(_on_place_requested)
	_painting_system.eat_requested.connect(_on_eat_requested)
	_painting_system.eat_anim_started.connect(_on_eat_anim_started)
	_painting_system.eat_anim_cancelled.connect(_on_eat_anim_cancelled)
	add_child(_painting_system)

	_pointing_system = PlayerPointingSystem.new()
	_pointing_system.init(self)
	_pointing_system.reaction_fired.connect(_on_reaction_fired)
	add_child(_pointing_system)

	_journal_system = PlayerJournalSystem.new()
	_journal_system.init(self)
	add_child(_journal_system)

	_footprint_system = PlayerFootprintSystem.new()
	_footprint_system.init(self)
	add_child(_footprint_system)
	_footstep_player.footstep_played.connect(_on_footstep_played)

	# ── ARCHIVED v0.5.0 - Powerups replaced with Environmental Events
	# _powerup_system = PlayerPowerupSystem.new()
	# _powerup_system.init(self)
	# add_child(_powerup_system)


# =============================================================================
# PUBLIC API - Facade methods that delegate to subsystems
# =============================================================================

# Mounting API (delegates to PlayerMountSystem)
var mounted_on: Node:
	get: return _mount_system.mounted_on if _mount_system else null
var mounted_by: Node:
	get: return _mount_system.mounted_by if _mount_system else null
var is_mounted: bool:
	get: return _mount_system.is_mounted() if _mount_system else false
var has_rider: bool:
	get: return _mount_system.has_rider() if _mount_system else false
var mount_peer_id: int:
	get: return _mount_system.mount_peer_id if _mount_system else -1

# Skin API (delegates to PlayerSkinSystem)
var skin_url: String:
	get: return _skin_system.get_skin_url() if _skin_system else ""

# Painting API (delegates to PlayerPaintingSystem)
var is_carrying_painting: bool:
	get: return _painting_system.is_carrying() if _painting_system else false

# Pointing API (delegates to PlayerPointingSystem)
var is_pointing: bool:
	get: return _pointing_system.is_pointing if _pointing_system else false
var point_target: Vector3:
	get: return _pointing_system.point_target if _pointing_system else Vector3.ZERO

# Crouch API (delegates to PlayerCrouchSystem)
var starting_height: float:
	get: return _crouch_system.get_starting_height() if _crouch_system else DEFAULT_PIVOT_Y
var crouching_height: float:
	get: return _crouch_system.get_crouching_height() if _crouch_system else 0.45

# ── ARCHIVED v0.5.0 - Powerups replaced with Environmental Events
# Powerup API (delegates to PlayerPowerupSystem)
# var has_gun: bool:
# 	get: return _powerup_system.has_gun() if _powerup_system else false
# var has_trap: bool:
# 	get: return _powerup_system.has_trap() if _powerup_system else false
# var has_perfect_knowledge: bool:
# 	get: return _powerup_system.has_perfect_knowledge() if _powerup_system else false
# var has_magnet: bool:
# 	get: return _powerup_system.has_magnet() if _powerup_system else false


func pause() -> void:
	_enabled = false


func start() -> void:
	_enabled = true

func set_gravity(gravity: float) -> void:
	"""Set player gravity (positive value, will be negated internally)"""
	_gravity = -abs(gravity)

func get_gravity_magnitude() -> float:
	"""Get current gravity magnitude"""
	return abs(_gravity)


func _set_invert_y(enabled: bool) -> void:
	_invert_y = enabled


func _set_mouse_sensitivity(factor: float) -> void:
	_mouse_sensitivity_factor = factor


func _set_joy_deadzone(value: float) -> void:
	_joy_deadzone = value


func _unhandled_input(event: InputEvent) -> void:
	# Mount/dismount handling - always process E key for dismount even when _enabled is false
	# BUT not if the debug console is open (typing 'e' would dismount)
	if event.is_action_pressed("mount") and is_local and not DebugConsole.is_active():
		if _mount_system.is_mounted():
			# Always allow dismount regardless of _enabled or mouse mode
			print("Player: Dismount requested (E key pressed while seated)")
			request_dismount()
			get_viewport().set_input_as_handled()
			return
	# Block other input when disabled
	if not _enabled or not is_local:
		return

	# Mount/dismount/steal/place handling (E key) - only reaches here if not mounted
	if event.is_action_pressed("mount") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if _painting_system and _painting_system.is_carrying():
			_painting_system.try_place_item()
		elif _painting_system and _painting_system.try_steal_target():
			pass  # Steal initiated
		else:
			var collider: Node = _get_interactable_collider()
			if collider:
				if collider.has_method("interact"):
					collider.interact()
				elif collider.get_parent() and collider.get_parent().has_method("interact"):
					collider.get_parent().interact()
				else:
					_mount_system.try_mount_target()
			else:
				_mount_system.try_mount_target()

	# Interact handling (equip skin, etc.) — skip if carrying a painting (right-click is eat)
	if event.is_action_pressed("interact") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if _painting_system and _painting_system.is_carrying():
			pass  # Eat is handled in _process via process_eat()
		else:
			var collider: Node = _get_interactable_collider()
			if collider:
				if collider.has_method("interact"):
					collider.interact()
				elif collider.get_parent() and collider.get_parent().has_method("interact"):
					collider.get_parent().interact()

	# ── ARCHIVED v0.5.0 - Powerups replaced with Environmental Events
	# Powerup handling - Gun fire and Trap placement
	# if event.is_action_pressed("point") and (Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or Input.get_connected_joypads().size() > 0):
	# 	if _powerup_system and _powerup_system.has_gun():
	# 		_powerup_system.fire_gun()
	# 	elif _powerup_system and _powerup_system.has_trap():
	# 		_powerup_system.place_trap()
	# 	elif _powerup_system and _powerup_system.has_magnet():
	# 		_powerup_system.activate_magnet()
	# 	elif _powerup_system and _powerup_system.has_grapple():
	# 		_powerup_system.fire_grapple()

	var is_mouse: bool = event is InputEventMouseMotion
	if is_mouse and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and _enabled:
		var delta_x: float = -event.relative.x * _mouse_sensitivity * _mouse_sensitivity_factor
		var delta_y: float = -event.relative.y * _mouse_sensitivity * _mouse_sensitivity_factor * (-1 if _invert_y else 1)

		if not smooth_movement:
			rotate_y(delta_x)
			_pivot.rotate_x(delta_y)
			_pivot.rotation.x = clamp(_pivot.rotation.x, -PITCH_CLAMP, PITCH_CLAMP)
		else:
			_camera_v += Vector2(
				clamp(delta_y, -dampening, dampening),
				clamp(delta_x, -dampening, dampening)
			)


func _exit_tree() -> void:
	"""Clean up signal connections to prevent memory leaks"""
	# SettingsEvents
	if SettingsEvents.set_invert_y.is_connected(_set_invert_y):
		SettingsEvents.set_invert_y.disconnect(_set_invert_y)
	if SettingsEvents.set_mouse_sensitivity.is_connected(_set_mouse_sensitivity):
		SettingsEvents.set_mouse_sensitivity.disconnect(_set_mouse_sensitivity)
	if SettingsEvents.set_joypad_deadzone.is_connected(_set_joy_deadzone):
		SettingsEvents.set_joypad_deadzone.disconnect(_set_joy_deadzone)

	# Note: ThemeManager.reading_font_changed uses inline lambda,
	# Godot auto-cleans up lambdas when the object is freed

	# Subsystems - disconnect before cleanup
	if _mount_system:
		if _mount_system.mount_requested.is_connected(_on_mount_requested):
			_mount_system.mount_requested.disconnect(_on_mount_requested)
		if _mount_system.dismount_requested.is_connected(_on_dismount_requested):
			_mount_system.dismount_requested.disconnect(_on_dismount_requested)

	if _painting_system:
		if _painting_system.steal_requested.is_connected(_on_steal_requested):
			_painting_system.steal_requested.disconnect(_on_steal_requested)
		if _painting_system.place_requested.is_connected(_on_place_requested):
			_painting_system.place_requested.disconnect(_on_place_requested)
		if _painting_system.eat_requested.is_connected(_on_eat_requested):
			_painting_system.eat_requested.disconnect(_on_eat_requested)
		if _painting_system.eat_anim_started.is_connected(_on_eat_anim_started):
			_painting_system.eat_anim_started.disconnect(_on_eat_anim_started)
		if _painting_system.eat_anim_cancelled.is_connected(_on_eat_anim_cancelled):
			_painting_system.eat_anim_cancelled.disconnect(_on_eat_anim_cancelled)

	if _pointing_system:
		if _pointing_system.reaction_fired.is_connected(_on_reaction_fired):
			_pointing_system.reaction_fired.disconnect(_on_reaction_fired)

	if _footstep_player:
		if _footstep_player.footstep_played.is_connected(_on_footstep_played):
			_footstep_player.footstep_played.disconnect(_on_footstep_played)


func _physics_process(delta: float) -> void:
	# Track last valid position (above void threshold)
	if is_local and global_position.y > VOID_Y_THRESHOLD:
		_last_valid_position = global_position

	# Void detection for local player - prevent falling forever
	if is_local and _void_check_timer >= VOID_CHECK_INTERVAL:
		_void_check_timer = 0.0
		if global_position.y < VOID_Y_THRESHOLD:
			_teleport_to_safety()
	_void_check_timer += delta

	# If mounted, let mount system handle position
	if _mount_system and _mount_system.is_mounted():
		_mount_system.process_mount(delta)
		return

	# Interpolate remote player positions
	if not is_local and _has_network_target:
		var horizontal_dist: float = Vector2(global_position.x - _target_position.x, global_position.z - _target_position.z).length()
		global_position = global_position.lerp(_target_position, INTERPOLATION_SPEED * delta)
		rotation.y = lerp_angle(rotation.y, _target_rotation_y, INTERPOLATION_SPEED * delta)
		_pivot.rotation.x = lerp_angle(_pivot.rotation.x, _target_pivot_rot_x, INTERPOLATION_SPEED * delta)
		_pivot.position.y = lerp(_pivot.position.y, _target_pivot_pos_y, INTERPOLATION_SPEED * delta)
		_crouch_system.update_crouch_body()
		# Apply body bob based on interpolation movement
		if _body_mesh:
			if horizontal_dist > 0.01:
				_bob_time += delta * BOB_FREQUENCY
				var bob_offset: float = sin(_bob_time) * BOB_AMPLITUDE
				_body_mesh.position.y = _body_mesh_base_y + bob_offset
			else:
				_bob_time = 0.0
				_body_mesh.position.y = _body_mesh_base_y

	# Apply gravity to local player (always, even when paused)
	# Pause only blocks input, not physics - player should fall naturally
	if is_local:
		velocity.y += _gravity * _gravity_modifier * delta

	# Process movement input only when enabled
	if _enabled and is_local:
		var fully_standing: bool = _crouch_system.is_fully_standing()

		if fully_standing and Input.is_action_pressed("dash") and RaceManager.is_dash_enabled():
			max_speed = max_speed_dash
		else:
			max_speed = max_speed_walk

		var speed: float = max_speed if fully_standing else _crouch_move_speed
		# Apply global speed modifier from EventManager
		speed *= RaceManager.get_global_speed_modifier()

		# Get movement direction (with inversion support)
		var input: Vector2 = Input.get_vector("strafe_left", "strafe_right", "move_forward", "move_back")

		# Invert input if controls are reversed (forwards/backwards AND left/right)
		if _controls_inverted:
			input = -input  # Flip both axes

		var desired_velocity: Vector3 = transform.basis * Vector3(input.x, 0, input.y) * speed

		velocity.x = desired_velocity.x
		velocity.z = desired_velocity.z
		
		# Process crouch input only when enabled
		_crouch_system.process_crouch(delta)
	else:
		# When paused, zero out horizontal velocity (no movement input)
		velocity.x = 0.0
		velocity.z = 0.0

	# Always call move_and_slide() for local players (even when paused)
	# This ensures gravity is applied and player falls naturally
	if is_local and not (_mount_system and _mount_system.is_mounted()):
		set_up_direction(Vector3.UP)
		set_floor_stop_on_slope_enabled(true)
		move_and_slide()
		
		# Handle joystick rotation even when paused (for camera control)
		var delta_vec: Vector2 = Vector2(-Input.get_joy_axis(0, _joy_right_x), -Input.get_joy_axis(0, _joy_right_y))
		if delta_vec.length() > _joy_deadzone and _enabled:
			rotate_y(delta_vec.x * _joy_sensitivity)

		# Sync position to network (every frame for smooth movement)
		if Services.network_service and Services.network_service.is_multiplayer_active():
			Services.network_service.sync_player_position(global_position, Vector3(0, rotation.y, 0), current_room)
			if _enabled:
				_pivot.rotate_x(delta_vec.y * _joy_sensitivity)
				_pivot.rotation.x = clamp(_pivot.rotation.x, -PITCH_CLAMP, PITCH_CLAMP)

		# Camera smoothing (only when enabled)
		if smooth_movement and _enabled:
			rotation.y = lerp_angle(rotation.y, rotation.y - _camera_v.y, delta * 30.0)
			_pivot.rotation.x = clamp(lerp_angle(_pivot.rotation.x, _pivot.rotation.x - _camera_v.x, delta * 30.0), -PITCH_CLAMP, PITCH_CLAMP)
			_camera_v = _camera_v.lerp(Vector2.ZERO, delta * 20.0)

		# MapCamera position and configuration is now handled by MinimapController.gd

		_footstep_player.set_on_floor(is_on_floor())

		# Reset jump count when on floor
		if is_on_floor():
			_jump_count = 0

		# Jump logic with double/triple jump support (only when enabled)
		if _enabled and Input.is_action_just_pressed("jump"):
			if is_on_floor():
				# First jump (always allowed)
				velocity.y = jump_impulse
				_jump_count = 1
			elif _jump_count < _max_jumps:
				# Additional jumps (double/triple)
				velocity.y = jump_impulse
				_jump_count += 1
				print("[Player] Jump %d/%d" % [_jump_count, _max_jumps])

		# Process remaining systems only when enabled
		if _enabled:
			# Process painting eat
			if _painting_system:
				_painting_system.process_eat(delta)

			# Process pointing
			if _pointing_system:
				_pointing_system.process_pointing()

			# Process stillness for ghost placement
			if _footprint_system:
				_footprint_system.process_stillness(delta)

		# Update interactable target tracking - check both forward and floor raycasts
		var current_collider: Node = _get_interactable_collider()
		if current_collider != _last_interactable_target:
			_last_interactable_target = current_collider
			interactable_target_changed.emit(current_collider)

		if Input.is_action_just_pressed("pin_to_journal") and _journal_system:
			_journal_system.try_pin_item()

		if Input.is_action_just_pressed("reset_skin") and _enabled:
			MultiplayerEvents.emit_skin_reset()


# =============================================================================
# INTERACTION HELPERS
# =============================================================================

func _get_interactable_collider() -> Node:
	# Check forward raycast first (for benches, items at eye level)
	if _raycast.is_colliding():
		return _raycast.get_collider()
	# Fall back to floor raycast (for plaques on floor/wall)
	if _floor_raycast and _floor_raycast.is_colliding():
		return _floor_raycast.get_collider()
	return null


# =============================================================================
# MOUNT SYSTEM DELEGATION
# =============================================================================

func _on_mount_requested(target: Node) -> void:
	request_mount(target)


func _on_dismount_requested() -> void:
	request_dismount()


func request_mount(target: Node) -> void:
	var main_node: Node = get_tree().current_scene
	if main_node and main_node.has_method("_request_mount"):
		main_node._request_mount(target)


func request_dismount() -> void:
	var main_node: Node = get_tree().current_scene
	print("Player.request_dismount() called, main_node=", main_node)
	if main_node and main_node.has_method("_request_dismount"):
		print("Player: Calling main._request_dismount()")
		main_node._request_dismount()


func execute_mount(target: Node, target_peer_id: int = -1) -> void:
	_mount_system.execute_mount(target, target_peer_id)
	# Note: Don't set _enabled = false here - camera control should remain active while mounted
	# Movement is already disabled by _physics_process returning early when mounted
	# Update rider's name to show "hat" format
	_original_name = player_name
	if _name_label and "player_name" in target:
		_name_label.text = target.player_name + " wearing\n" + player_name + " as a hat"


func execute_dismount() -> void:
	print("Player.execute_dismount() called, _mount_system=", _mount_system)
	_mount_system.execute_dismount()
	if is_local:
		_enabled = true
	# Restore rider's original name
	if _original_name != "" and _name_label:
		_name_label.text = _original_name
		_original_name = ""


func _accept_rider(rider: Node) -> void:
	_mount_system.accept_rider(rider)
	# Hide mount's name when ridden
	if _name_label:
		_name_label.visible = false


func _remove_rider(rider: Node) -> void:
	_mount_system.remove_rider(rider)
	# Restore mount's name visibility when rider leaves
	if _name_label:
		_name_label.visible = true


func apply_network_mount_state(is_mounted_state: bool, peer_id: int, mount_node: Node) -> void:
	# Track previous mount before updating state
	var previous_mount: Node = _mount_system.mounted_on if _mount_system else null

	_mount_system.apply_network_mount_state(is_mounted_state, peer_id, mount_node)

	# Handle name changes for network-synced mount state
	if is_mounted_state and is_instance_valid(mount_node):
		if _original_name == "":  # Only save if not already mounted
			_original_name = player_name
		if _name_label and "player_name" in mount_node:
			_name_label.text = mount_node.player_name + " wearing\n" + player_name + " as a hat"
		# Set mount's rider state so visibility checks work correctly
		if "_mount_system" in mount_node and mount_node._mount_system:
			mount_node._mount_system._has_rider = true
			mount_node._mount_system.mounted_by = self
		# Hide mount's name when ridden
		if "_name_label" in mount_node and mount_node._name_label:
			mount_node._name_label.visible = false
	elif not is_mounted_state:
		# Restore rider's name
		if _original_name != "" and _name_label:
			_name_label.text = _original_name
			_original_name = ""
		# Clear previous mount's rider state
		if is_instance_valid(previous_mount) and "_mount_system" in previous_mount and previous_mount._mount_system:
			previous_mount._mount_system._has_rider = false
			previous_mount._mount_system.mounted_by = null
		# Restore previous mount's name visibility
		if is_instance_valid(previous_mount) and "_name_label" in previous_mount and previous_mount._name_label:
			previous_mount._name_label.visible = true


# =============================================================================
# SKIN SYSTEM DELEGATION
# =============================================================================

func set_player_skin(url: String, texture: ImageTexture = null) -> void:
	_skin_system.set_player_skin(url, texture)


func clear_player_skin() -> void:
	_skin_system.clear_player_skin()


# =============================================================================
# NETWORK AND DISPLAY
# =============================================================================

func set_player_authority(peer_id: int) -> void:
	if _multiplayer_sync:
		_multiplayer_sync.set_multiplayer_authority(peer_id)
	is_local = (peer_id == multiplayer.get_unique_id())
	if is_local:
		add_to_group("local_player")
		if camera:
			camera.make_current()


func set_player_name(new_name: String) -> void:
	player_name = new_name
	if _name_label:
		_name_label.text = new_name


func set_player_pronouns(pronouns: String) -> void:
	if pronouns == "":
		# Hide and clear if no pronouns set
		if _pronoun_label and is_instance_valid(_pronoun_label):
			_pronoun_label.visible = false
		return
	var lbl := _get_or_create_pronoun_label()
	lbl.text = pronouns
	lbl.visible = NetworkManager.show_nameplates and pronouns != ""

func get_minimap_texture() -> Texture2D:
	if _map_viewport:
		return _map_viewport.get_texture()
	return null


func _get_or_create_pronoun_label() -> Label3D:
	if _pronoun_label and is_instance_valid(_pronoun_label):
		return _pronoun_label
	_pronoun_label = Label3D.new()
	_pronoun_label.name = "PronounLabel"
	# Copy billboard/render settings from NameLabel if available
	if _name_label and is_instance_valid(_name_label):
		_pronoun_label.billboard = _name_label.billboard
		_pronoun_label.no_depth_test = _name_label.no_depth_test
		_pronoun_label.render_priority = _name_label.render_priority
		_pronoun_label.modulate = _name_label.modulate
		_pronoun_label.pixel_size = _name_label.pixel_size
		_pronoun_label.font = ThemeManager.get_reading_font()
		# Smaller font — roughly half the name size, min 10px
		_pronoun_label.font_size = max(int(_name_label.font_size * 0.5), 10)
		_pronoun_label.outline_size = max(int(_name_label.outline_size * 0.5), 2)
		_pronoun_label.outline_modulate = _name_label.outline_modulate
		# NameLabel uses vertical_alignment BOTTOM, so text hangs downward from its Y position.
		# Offset upward enough to clear the full name text height plus a generous gap.
		var name_height: float = _name_label.font_size * _name_label.pixel_size
		var gap: float = name_height * 0.6
		_pronoun_label.position = _name_label.position + Vector3(0, name_height + gap, 0)
	else:
		_pronoun_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_pronoun_label.no_depth_test = true
		_pronoun_label.font = ThemeManager.get_reading_font()
		_pronoun_label.font_size = 10
		_pronoun_label.position = Vector3(0, 2.1, 0)
	add_child(_pronoun_label)
	return _pronoun_label


func set_body_visible(is_visible: bool) -> void:
	if _body_mesh:
		_body_mesh.visible = is_visible
	if _head_mesh:
		_head_mesh.visible = is_visible
	if _name_label:
		# Keep nameplate hidden if being ridden by another player
		if is_visible and has_rider:
			_name_label.visible = false
		else:
			_name_label.visible = is_visible
	if _pronoun_label and is_instance_valid(_pronoun_label):
		if is_visible and has_rider:
			_pronoun_label.visible = false
		else:
			_pronoun_label.visible = is_visible and _pronoun_label.text != ""


func get_owned_body_material() -> Material:
	if not _owned_body_material and _body_mesh and _body_mesh.mesh and _body_mesh.mesh.get_surface_count() > 0:
		var material: Material = _body_mesh.get_surface_override_material(0)
		if material:
			_owned_body_material = material.duplicate()
			_body_mesh.set_surface_override_material(0, _owned_body_material)
	return _owned_body_material


func get_owned_head_material() -> Material:
	if not _owned_head_material and _head_mesh and _head_mesh.mesh and _head_mesh.mesh.get_surface_count() > 0:
		var material: Material = _head_mesh.get_surface_override_material(0)
		if material:
			_owned_head_material = material.duplicate()
			_head_mesh.set_surface_override_material(0, _owned_head_material)
	return _owned_head_material


func set_player_color(color: Color) -> void:
	var body_mat: Material = get_owned_body_material()
	if body_mat:
		if body_mat is ShaderMaterial:
			body_mat.set_shader_parameter("fallback_color", color)
		elif body_mat is StandardMaterial3D:
			body_mat.albedo_color = color
			# Add outline effect for multiplayer visibility (visible through walls)
			_add_outline_effect(body_mat, color)
	var head_mat: Material = get_owned_head_material()
	if head_mat and head_mat is StandardMaterial3D:
		head_mat.albedo_color = color.lightened(0.15)


func _add_outline_effect(base_material: StandardMaterial3D, player_color: Color) -> void:
	## Creates an outline material using stencil buffer for multiplayer visibility
	## This makes players visible through walls, improving multiplayer awareness
	
	# Check if outline already exists (avoid duplicates)
	if _body_mesh and _body_mesh.get_surface_override_material(1):
		return  # Outline already added
	
	# Create outline material using stencil buffer (Godot 4.5+ feature)
	var outline_mat := StandardMaterial3D.new()
	outline_mat.stencil_mode = StandardMaterial3D.STENCIL_MODE_OUTLINE
	outline_mat.stencil_outline_thickness = 2.0
	outline_mat.stencil_effect_color = player_color.lightened(0.2)  # Slightly brighter than player color
	outline_mat.render_priority = 100  # Render on top of other geometry
	outline_mat.disable_receive_shadows = true
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Always visible, not affected by lighting
	
	# Apply outline to second surface (index 1)
	if _body_mesh:
		_body_mesh.set_surface_override_material(1, outline_mat)


# =============================================================================
# ENVIRONMENTAL EVENT MODIFIERS
# =============================================================================

func set_double_jump_enabled(enabled: bool) -> void:
	_double_jump_enabled = enabled
	_update_max_jumps()
	print("[Player] Double jump: %s" % ["ENABLED" if enabled else "DISABLED"])

func set_triple_jump_enabled(enabled: bool) -> void:
	_triple_jump_enabled = enabled
	_update_max_jumps()
	print("[Player] Triple jump: %s" % ["ENABLED" if enabled else "DISABLED"])

func set_controls_inverted(enabled: bool) -> void:
	_controls_inverted = enabled
	print("[Player] Controls: %s" % ["INVERTED" if enabled else "NORMAL"])

func set_gravity_modifier(modifier: float) -> void:
	_gravity_modifier = modifier
	print("[Player] Gravity modifier: %.1f%% (0.3 = moon gravity!)" % (modifier * 100))

func _update_max_jumps() -> void:
	if _triple_jump_enabled:
		_max_jumps = 3
	elif _double_jump_enabled:
		_max_jumps = 2
	else:
		_max_jumps = 1
	_jump_count = 0  # Reset jump count when max changes

func _get_movement_direction() -> Vector3:
	var dir := Vector3.ZERO
	var forward_input = Input.get_axis("move_back", "move_forward")
	var right_input = Input.get_axis("strafe_left", "strafe_right")
	
	# Invert controls if enabled
	if _controls_inverted:
		forward_input = -forward_input
		right_input = -right_input
	
	dir = (transform.basis * Vector3(right_input, 0, forward_input)).normalized()
	return dir


func apply_network_position(pos: Vector3, rot_y: float, pivot_rot_x: float, pivot_pos_y: float = DEFAULT_PIVOT_Y) -> void:
	var should_snap: bool = false

	if not _has_network_target:
		should_snap = true
	else:
		# Detect teleport (large position change) and snap instead of interpolate
		var delta_distance: float = global_position.distance_to(pos)
		if delta_distance > TELEPORT_SNAP_THRESHOLD:
			should_snap = true

	if should_snap:
		global_position = pos
		_pivot.position.y = pivot_pos_y

	_has_network_target = true
	_target_position = pos
	_target_rotation_y = rot_y
	_target_pivot_rot_x = pivot_rot_x
	_target_pivot_pos_y = pivot_pos_y


# =============================================================================
# BODY BOB
# =============================================================================

func _update_body_bob(delta: float) -> void:
	if not _body_mesh:
		return

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.5 and is_on_floor():
		_bob_time += delta * BOB_FREQUENCY
		var bob_offset: float = sin(_bob_time) * BOB_AMPLITUDE
		_body_mesh.position.y = _body_mesh_base_y + bob_offset
	else:
		_bob_time = 0.0
		_body_mesh.position.y = _body_mesh_base_y


# =============================================================================
# CROUCH SYSTEM DELEGATION
# =============================================================================

func _get_crouch_factor() -> float:
	return _crouch_system.get_crouch_factor() if _crouch_system else 0.0


func _update_crouch_body() -> void:
	if _crouch_system:
		_crouch_system.update_crouch_body()


# =============================================================================
# PAINTING SYSTEM DELEGATION
# =============================================================================

func _on_steal_requested(exhibit_title: String, image_title: String, image_url: String, image_size: Vector2, is_audio: bool = false) -> void:
	var main_node: Node = get_tree().current_scene
	if main_node and main_node.has_method("_request_steal_painting"):
		main_node._request_steal_painting(exhibit_title, image_title, image_url, image_size, is_audio)


func _on_place_requested(exhibit_title: String, image_title: String, image_url: String, wall_position: Vector3, wall_normal: Vector3, image_size: Vector2, is_audio: bool = false) -> void:
	var main_node: Node = get_tree().current_scene
	if main_node and main_node.has_method("_request_place_painting"):
		main_node._request_place_painting(exhibit_title, image_title, image_url, wall_position, wall_normal, image_size, is_audio)


func _on_eat_requested(exhibit_title: String, image_title: String) -> void:
	var main_node: Node = get_tree().current_scene
	if main_node and main_node.has_method("_request_eat_painting"):
		main_node._request_eat_painting(exhibit_title, image_title)


func _on_eat_anim_started() -> void:
	var main_node: Node = get_tree().current_scene
	if main_node and main_node.has_method("_broadcast_eat_anim_start"):
		main_node._broadcast_eat_anim_start()


func _on_eat_anim_cancelled() -> void:
	var main_node: Node = get_tree().current_scene
	if main_node and main_node.has_method("_broadcast_eat_anim_cancel"):
		main_node._broadcast_eat_anim_cancel()


func execute_steal_painting(texture: Texture2D, url: String, title: String, exhibit_title: String, size: Vector2) -> void:
	if _painting_system:
		_painting_system.execute_steal(texture, url, title, exhibit_title, size)


func execute_drop_painting() -> void:
	if _painting_system:
		_painting_system.execute_drop()


# =============================================================================
# POINTING SYSTEM DELEGATION
# =============================================================================

func _on_reaction_fired(reaction_index: int, target: Vector3) -> void:
	var main_node: Node = get_tree().current_scene
	if main_node and main_node.has_method("_on_local_reaction"):
		main_node._on_local_reaction(reaction_index, target)


func _on_footstep_played() -> void:
	if _footprint_system and is_local:
		_footprint_system.place_footprint()


func apply_network_pointing(pointing: bool, target: Vector3) -> void:
	if _pointing_system:
		_pointing_system.apply_network_pointing(pointing, target)


func _teleport_to_safety() -> void:
	"""Teleport player back to their last valid position when they fall into void."""
	print("Player: Fell into void! Teleporting to safety...")
	
	# Determine where to teleport player
	var teleport_pos: Vector3
	if _last_valid_position.y > VOID_Y_THRESHOLD:
		# Use last valid position with small Y offset to prevent immediate re-fall
		teleport_pos = Vector3(_last_valid_position.x, _last_valid_position.y + 2.0, _last_valid_position.z)
		print("Player: Returning to last valid position: ", teleport_pos)
	else:
		# Fallback to start line if no valid position tracked
		teleport_pos = Vector3(VOID_SPAWN_XZ.x, VOID_SPAWN_Y, VOID_SPAWN_XZ.y)
		print("Player: No valid position tracked, using start line: ", teleport_pos)
	
	# Teleport to safe position
	global_position = teleport_pos
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	
	# Reset current room to lobby if using fallback
	if _last_valid_position.y <= VOID_Y_THRESHOLD:
		if "current_room" in self:
			current_room = "Lobby"
	
	# Show message to player
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("_show_error_message"):
		if _last_valid_position.y > VOID_Y_THRESHOLD:
			main._show_error_message("You fell through the floor!\n\nTeleported back to where you were.")
		else:
			main._show_error_message("You fell into the void!\n\nTeleported back to start line.")
