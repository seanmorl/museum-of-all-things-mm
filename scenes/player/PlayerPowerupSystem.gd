extends Node
class_name PlayerPowerupSystem
## Subsystem for managing player powerups and their effects.

signal powerup_state_changed(powerups: Array, timers: Dictionary)

const SPEED_BOOST_MULTIPLIER: float = 2.0
const GUN_PROJECTILE_SPEED: float = 50.0
const TRAP_TRIGGER_RADIUS: float = 1.5

var _player: CharacterBody3D = null
var _is_local: bool = false

var _active_powerups: Array = []
var _powerup_timers: Dictionary = {}

var _has_speed_boost: bool = false
var _has_perfect_knowledge: bool = false
var _has_gun: bool = false
var _has_trap: bool = false
var _has_lights_out: bool = false
var _has_magnet: bool = false
var _has_grapple: bool = false

var _original_walk_speed: float = 0.0
var _original_dash_speed: float = 0.0

var _gun_fired: bool = false
var _trap_placed: bool = false
var _grapple_active: bool = false
var _grapple_point: Vector3 = Vector3.ZERO
var _grapple_rope: CSGBox3D = null

var _trap_scene: PackedScene = null
var _placed_trap: Node3D = null

var _lights_out_original_energy: float = 1.0

const GRAPPLE_RANGE: float = 30.0
const GRAPPLE_SPEED: float = 80.0
const SWING_FORCE: float = 15.0

func init(player: CharacterBody3D) -> void:
	_player = player
	_is_local = player.is_local

	# Always connect to signals and cache speeds - all players need powerup effects
	_connect_signals()
	_cache_original_speeds()
	if _is_local:
		_load_trap_scene()

func _connect_signals() -> void:
	PowerupManager.powerup_collected.connect(_on_powerup_collected)
	PowerupManager.powerup_expired.connect(_on_powerup_expired)

func _cache_original_speeds() -> void:
	if _player.has_method("get_max_speed_walk"):
		_original_walk_speed = _player.max_speed_walk if "max_speed_walk" in _player else 5.0
		_original_dash_speed = _player.max_speed_dash if "max_speed_dash" in _player else 10.0
	else:
		_original_walk_speed = 5.0
		_original_dash_speed = 10.0

func _load_trap_scene() -> void:
	var trap_path := "res://scenes/items/PowerupTrap.tscn"
	if ResourceLoader.exists(trap_path):
		_trap_scene = load(trap_path)
		# Suppress SSR-in-transparent-viewport warning: instantiate briefly to
		# find any SubViewport and disable screen-space reflections on it.
		var tmp: Node = _trap_scene.instantiate()
		for vp in _find_subviewports(tmp):
			vp.use_debanding = false
		tmp.queue_free()

func _find_subviewports(node: Node) -> Array:
	var result: Array = []
	if node is SubViewport:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_subviewports(child))
	return result

func process_powerups(_delta: float) -> void:
	# All players process their own powerups (each client checks their own player_id)
	_update_timers()
	_apply_powerup_effects()


func _update_timers() -> void:
	var player_id = NetworkManager.get_unique_id()
	_active_powerups.clear()
	
	for powerup_type in PowerupManager.PowerupType.values():
		if PowerupManager.has_powerup(player_id, powerup_type):
			_active_powerups.append(powerup_type)
			var remaining = PowerupManager.get_remaining_time(player_id, powerup_type)
			if remaining > 0:
				_powerup_timers[powerup_type] = remaining

func _apply_powerup_effects() -> void:
	var player_id = NetworkManager.get_unique_id()

	_has_speed_boost = PowerupManager.has_powerup(player_id, PowerupManager.PowerupType.SPEED_BOOST)
	_has_perfect_knowledge = PowerupManager.has_powerup(player_id, PowerupManager.PowerupType.PERFECT_KNOWLEDGE)
	_has_gun = PowerupManager.has_powerup(player_id, PowerupManager.PowerupType.GUN) and not _gun_fired
	_has_trap = PowerupManager.has_powerup(player_id, PowerupManager.PowerupType.TRAP) and not _trap_placed
	_has_lights_out = PowerupManager.is_lights_out_victim(player_id)
	_has_magnet = PowerupManager.has_powerup(player_id, PowerupManager.PowerupType.MAGNET)
	_has_grapple = PowerupManager.has_powerup(player_id, PowerupManager.PowerupType.GRAPPLE)

	if _has_speed_boost:
		_apply_speed_boost()
	else:
		_restore_normal_speed()

	_update_perfect_knowledge()
	_update_lights_out()

	if _has_grapple:
		_process_grapple()

	powerup_state_changed.emit(_active_powerups, _powerup_timers)

func _apply_speed_boost() -> void:
	if not _is_local:
		return
	if "max_speed_walk" in _player:
		_player.max_speed_walk = _original_walk_speed * SPEED_BOOST_MULTIPLIER
	if "max_speed_dash" in _player:
		_player.max_speed_dash = _original_dash_speed * SPEED_BOOST_MULTIPLIER

func _restore_normal_speed() -> void:
	if not _is_local:
		return
	if "max_speed_walk" in _player:
		_player.max_speed_walk = _original_walk_speed
	if "max_speed_dash" in _player:
		_player.max_speed_dash = _original_dash_speed

func _update_perfect_knowledge() -> void:
	var all_halls = _player.get_tree().get_nodes_in_group("hall")
	for hall in all_halls:
		if hall.has_node("EntryLabel"):
			var label: Label3D = hall.get_node("EntryLabel")
			if label:
				label.visible = _has_perfect_knowledge
		if hall.has_node("ExitLabel"):
			var label: Label3D = hall.get_node("ExitLabel")
			if label:
				label.visible = _has_perfect_knowledge
		if hall.has_node("FromSign"):
			var sign = hall.get_node("FromSign")
			if sign and sign.has_node("Label3D"):
				sign.get_node("Label3D").visible = _has_perfect_knowledge
		if hall.has_node("ToSign"):
			var sign = hall.get_node("ToSign")
			if sign and sign.has_node("Label3D"):
				sign.get_node("Label3D").visible = _has_perfect_knowledge

func _update_lights_out() -> void:
	if not _is_local:
		return
	
	# Lights out affects the local player if they're a victim
	# Dim all lights in the current exhibit
	var museum = _player.get_tree().get_first_node_in_group("museum")
	if not museum:
		return
	
	# Find all lights in the current room and dim them
	var light_index = 0
	for light in museum.get_tree().get_nodes_in_group("managed_light"):
		if light is OmniLight3D or light is SpotLight3D:
			if _has_lights_out:
				# Keep only ~10% of lights on at reduced energy
				if light_index % 10 == 0:
					light.light_energy = 0.3
				else:
					light.light_energy = 0.02
				light_index += 1
			else:
				# Restore normal lighting
				light.light_energy = 1.0 if not ThemeManager.is_dark_mode else 0.4

func has_gun() -> bool:
	return _has_gun

func has_trap() -> bool:
	return _has_trap

func has_perfect_knowledge() -> bool:
	return _has_perfect_knowledge

func fire_gun() -> bool:
	if not _has_gun or _gun_fired:
		return false

	var player_id = NetworkManager.get_unique_id()
	var camera = _player.get_node_or_null("Pivot/Camera3D")
	if not camera:
		return false
	
	var from = camera.global_transform.origin
	var to = from + -camera.global_transform.basis.z * 100.0
	
	var space_state = _player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return false
	
	var collider = result.get("collider")
	var hit_position = result.get("position", to)
	
	var hit_player = _find_player_from_collider(collider)
	if hit_player:
		_teleport_player_to_lobby(hit_player)
	
	_gun_fired = true
	PowerupManager.use_powerup(player_id, PowerupManager.PowerupType.GUN)
	
	_spawn_gun_projectile_effect(from, hit_position)
	
	return true

func place_trap() -> bool:
	if not _has_trap or _trap_placed:
		return false
	
	var camera = _player.get_node_or_null("Pivot/Camera3D")
	if not camera:
		return false
	
	var from = camera.global_transform.origin
	var to = from + -camera.global_transform.basis.z * 10.0
	
	var space_state = _player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return false
	
	var hit_position = result.get("position", to)
	var hit_normal = result.get("normal", Vector3.UP)
	
	var trap_position = hit_position + hit_normal * 0.1

	if _trap_scene:
		_placed_trap = _trap_scene.instantiate()
		_player.get_tree().current_scene.add_child(_placed_trap)
		_placed_trap.global_transform.origin = trap_position
		_placed_trap.set_owner_player(_player)
		_placed_trap.triggered.connect(_on_trap_triggered)

	_trap_placed = true
	var player_id = NetworkManager.get_unique_id()
	PowerupManager.use_powerup(player_id, PowerupManager.PowerupType.TRAP)

	return true

func activate_magnet() -> bool:
	if not _has_magnet:
		return false
	
	var player_id = NetworkManager.get_unique_id()
	var current_room = _player.current_room if "current_room" in _player else "Lobby"
	
	if current_room == "" or current_room == "Lobby":
		return false
	
	# Activate magnet - pulls all players to current room
	PowerupManager.activate_magnet(player_id, current_room)
	_pull_all_players_to_room(current_room)
	
	# Consume the powerup
	PowerupManager.use_powerup(player_id, PowerupManager.PowerupType.MAGNET)
	
	return true

func _pull_all_players_to_room(target_room: String) -> void:
	# Get all players and teleport them to the target room
	var all_players = _player.get_tree().get_nodes_in_group("Player")
	for p in all_players:
		if p == _player:
			continue  # Don't teleport self
		
		var peer_id = p.get_multiplayer_authority() if p.has_method("get_multiplayer_authority") else 1
		if peer_id != NetworkManager.get_unique_id():
			_teleport_player_to_room(p, target_room)

func _teleport_player_to_room(target_player: CharacterBody3D, target_room: String) -> void:
	# Find a spawn point in the target room
	var museum = _player.get_tree().get_first_node_in_group("museum")
	if not museum:
		return
	
	# Find the exhibit for the target room
	var target_exhibit = null
	if museum.has_method("get_exhibits"):
		var exhibits = museum.get_exhibits()
		if exhibits.has(target_room):
			target_exhibit = exhibits[target_room].exhibit
	
	if target_exhibit and target_exhibit.has_node("EntryMarker"):
		var entry_marker = target_exhibit.get_node("EntryMarker")
		var teleport_pos = entry_marker.global_transform.origin + Vector3(0, 1, 0)

		if target_player.is_local:
			target_player.global_transform.origin = teleport_pos
			if "current_room" in target_player:
				target_player.current_room = target_room
		else:
			# Network player - would need RPC to teleport
			pass

func fire_grapple() -> bool:
	if not _has_grapple or _grapple_active:
		return false
	
	var camera = _player.get_node_or_null("Pivot/Camera3D")
	if not camera:
		return false
	
	var from = camera.global_transform.origin
	# Cast in the direction the camera is looking
	var to = from + -camera.global_transform.basis.z * GRAPPLE_RANGE
	
	var space_state = _player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	query.collision_mask = 1
	
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return false
	
	var hit_position: Vector3 = result.get("position", to)
	var hit_normal: Vector3 = result.get("normal", Vector3.UP)
	
	# Accept ceilings (normal.y < -0.3) and steep walls (normal.y between -0.3 and 0.3)
	# Reject floors (normal.y > 0.5) — you can't grapple the floor
	if hit_normal.y > 0.5:
		return false
	
	_grapple_active = true
	_grapple_point = hit_position
	_create_grapple_rope(from, hit_position)
	
	# Give an immediate upward + forward impulse toward the anchor so the player
	# actually swings rather than just dangling from a standing position.
	var to_anchor := (_grapple_point - _player.global_position).normalized()
	_player.velocity += to_anchor * SWING_FORCE * 1.5
	if _player.velocity.y < 4.0:
		_player.velocity.y = max(_player.velocity.y, 8.0)  # ensure upward arc
	
	return true

func _process_grapple() -> void:
	if not _grapple_active:
		return
	
	var player_pos := _player.global_position + Vector3(0, 0.5, 0)
	
	# Update visual rope
	if _grapple_rope and is_instance_valid(_grapple_rope):
		_update_grapple_rope(_grapple_point, player_pos)
	
	var to_anchor := _grapple_point - player_pos
	var distance := to_anchor.length()
	
	if distance > 1.5:
		# Pull toward anchor — scale force by distance so it eases near the top
		var pull: Vector3 = to_anchor.normalized() * SWING_FORCE * clamp(distance / 5.0, 0.5, 2.0)
		# delta is unavailable here; _apply_powerup_effects is called from process_powerups(_delta)
		# but we don't receive delta. Use get_physics_process_delta_time() instead.
		var dt := _player.get_physics_process_delta_time()
		_player.velocity += pull * dt
	else:
		_release_grapple()

func _create_grapple_rope(from: Vector3, to: Vector3) -> void:
	_grapple_rope = CSGBox3D.new()
	_grapple_rope.size = Vector3(0.05, from.distance_to(to), 0.05)
	_grapple_rope.material = StandardMaterial3D.new()
	(_grapple_rope.material as StandardMaterial3D).albedo_color = Color(0.9, 0.9, 0.9, 0.8)
	(_grapple_rope.material as StandardMaterial3D).emission_enabled = true
	(_grapple_rope.material as StandardMaterial3D).emission = Color(0.9, 0.9, 0.9)
	_grapple_rope.add_to_group("grapple_rope")
	_player.get_tree().current_scene.add_child(_grapple_rope)
	_update_grapple_rope(from, to)

func _update_grapple_rope(from: Vector3, to: Vector3) -> void:
	if not _grapple_rope or not is_instance_valid(_grapple_rope):
		return
	
	var mid_point = (from + to) / 2.0
	_grapple_rope.global_position = mid_point
	_grapple_rope.size.y = from.distance_to(to)
	_grapple_rope.look_at(to, Vector3.UP)
	_grapple_rope.rotate_x(deg_to_rad(90))

func _release_grapple() -> void:
	_grapple_active = false
	_grapple_point = Vector3.ZERO
	if _grapple_rope and is_instance_valid(_grapple_rope):
		_grapple_rope.queue_free()
		_grapple_rope = null

func has_magnet() -> bool:
	return _has_magnet

func has_grapple() -> bool:
	return _has_grapple

func _find_player_from_collider(collider: Object) -> CharacterBody3D:
	if not collider:
		return null

	var node = collider
	while node:
		if node is CharacterBody3D and node.name == "Player":
			return node
		node = node.get_parent()

	return null

func _teleport_player_to_lobby(target_player: CharacterBody3D) -> void:
	if not target_player:
		return
	
	var lobby = _player.get_tree().get_first_node_in_group("lobby_spawn")
	if not lobby:
		lobby = _player.get_tree().get_first_node_in_group("lobby")
	if not lobby:
		lobby = _player.get_tree().get_first_node_in_group("spawn_point")
	
	if lobby:
		var teleport_pos = lobby.global_transform.origin + Vector3(0, 1, 0)

		if target_player.is_local:
			target_player.global_transform.origin = teleport_pos
			if "current_room" in target_player:
				target_player.current_room = "Lobby"
		else:
			var peer_id = target_player.get_multiplayer_authority()
			if multiplayer.is_server():
				target_player.global_transform.origin = teleport_pos
				if "current_room" in target_player:
					target_player.current_room = "Lobby"
			else:
				_request_player_teleport(target_player, teleport_pos)

func _request_player_teleport(target_player: CharacterBody3D, position: Vector3) -> void:
	if not multiplayer.is_server():
		var peer_id = target_player.get_multiplayer_authority()
		var data = {
			"player_id": peer_id,
			"position": [position.x, position.y, position.z],
			"room": "Lobby"
		}
		if NetworkManager.multiplayer and NetworkManager.multiplayer.has_multiplayer_peer():
			NetworkManager.multiplayer.server.rpc("_rpc_teleport_player", data)

func _spawn_gun_projectile_effect(from: Vector3, to: Vector3) -> void:
	var effect := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.04
	cylinder.bottom_radius = 0.04
	cylinder.height = from.distance_to(to)
	effect.mesh = cylinder

	var effect_mat := StandardMaterial3D.new()
	effect_mat.albedo_color = Color(1.0, 0.2, 0.2, 1.0)
	effect_mat.emission_enabled = true
	effect_mat.emission = Color(1.0, 0.2, 0.2)
	effect_mat.emission_energy_multiplier = 2.0
	effect_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Assign as material_override so the tween can reach it reliably
	effect.material_override = effect_mat

	# Add to scene first, then position
	_player.get_tree().current_scene.add_child(effect)
	var mid := from + (to - from) * 0.5
	effect.global_transform.origin = mid
	effect.look_at(to, Vector3.UP)
	effect.rotate_x(deg_to_rad(90))

	# Fade out the material_override, then free the node
	var tween := effect.create_tween()
	tween.tween_property(effect_mat, "albedo_color:a", 0.0, 0.25)
	tween.tween_callback(effect.queue_free)

func _on_powerup_collected(player_id: int, powerup_type: PowerupManager.PowerupType) -> void:
	if player_id != NetworkManager.get_unique_id():
		return

	if powerup_type == PowerupManager.PowerupType.GUN:
		_gun_fired = false
	elif powerup_type == PowerupManager.PowerupType.TRAP:
		_trap_placed = false

func _on_powerup_expired(player_id: int, powerup_type: PowerupManager.PowerupType) -> void:
	if player_id != NetworkManager.get_unique_id():
		return

	if powerup_type == PowerupManager.PowerupType.SPEED_BOOST:
		_restore_normal_speed()
	elif powerup_type == PowerupManager.PowerupType.GUN:
		_gun_fired = false
	elif powerup_type == PowerupManager.PowerupType.TRAP:
		_trap_placed = false
		if _placed_trap:
			_placed_trap.queue_free()
			_placed_trap = null
	elif powerup_type == PowerupManager.PowerupType.GRAPPLE:
		_release_grapple()

func _on_trap_triggered(trap: Node3D, victim: CharacterBody3D) -> void:
	_teleport_player_to_lobby(victim)
	trap.queue_free()
	_placed_trap = null

func get_active_powerups() -> Array:
	return _active_powerups

func get_powerup_timer(powerup_type: int) -> float:
	return _powerup_timers.get(powerup_type, 0.0)
