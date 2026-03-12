extends Node
## Autoload: PowerupManager
## Manages powerup state, spawning, and distribution across all players.

signal powerup_collected(player_id: int, powerup_type: PowerupType)
signal powerup_activated(player_id: int, powerup_type: PowerupType)
signal powerup_expired(player_id: int, powerup_type: PowerupType)
signal powerup_used(player_id: int, powerup_type: PowerupType)
## Network signals for multiplayer sync
signal powerup_collected_network(player_id: int, powerup_type: PowerupType)
signal powerup_used_network(player_id: int, powerup_type: PowerupType)
## Gameplay effect signals — consumed by Main.gd / room systems
signal trap_placed(caster_id: int, position: Vector3)
signal magnet_pull_triggered(caster_id: int, target_room: String)

enum PowerupType {
	SPEED_BOOST,
	PERFECT_KNOWLEDGE,
	GUN,
	TRAP,
	TOWER_OF_BABEL,
	LIGHTS_OUT,
	MAGNET,
	GRAPPLE,
	OMNISCIENCE
}

const POWERUP_NAMES := {
	PowerupType.SPEED_BOOST: "Speed Boost",
	PowerupType.PERFECT_KNOWLEDGE: "Perfect Knowledge",
	PowerupType.GUN: "Teleport Gun",
	PowerupType.TRAP: "Teleport Trap",
	PowerupType.TOWER_OF_BABEL: "Tower of Babel",
	PowerupType.LIGHTS_OUT: "Lights Out",
	PowerupType.MAGNET: "Magnet",
	PowerupType.GRAPPLE: "Spider Grapple",
	PowerupType.OMNISCIENCE: "Omniscience"
}

const POWERUP_COLORS := {
	PowerupType.SPEED_BOOST: Color(1.0, 0.8, 0.0),
	PowerupType.PERFECT_KNOWLEDGE: Color(0.0, 1.0, 1.0),
	PowerupType.GUN: Color(1.0, 0.2, 0.2),
	PowerupType.TRAP: Color(0.2, 1.0, 0.2),
	PowerupType.TOWER_OF_BABEL: Color(0.6, 0.4, 0.9),
	PowerupType.LIGHTS_OUT: Color(0.1, 0.1, 0.2),
	PowerupType.MAGNET: Color(0.8, 0.2, 0.5),
	PowerupType.GRAPPLE: Color(0.9, 0.9, 0.9),
	PowerupType.OMNISCIENCE: Color(1.0, 0.75, 0.2)
}

const POWERUP_DURATIONS := {
	PowerupType.SPEED_BOOST: 15.0,
	PowerupType.PERFECT_KNOWLEDGE: 10.0,
	PowerupType.GUN: -1.0,
	PowerupType.TRAP: -1.0,
	PowerupType.TOWER_OF_BABEL: -1.0,
	PowerupType.LIGHTS_OUT: 120.0,
	PowerupType.MAGNET: -1.0,
	PowerupType.GRAPPLE: 60.0,
	PowerupType.OMNISCIENCE: 30.0
}

const SPEED_BOOST_MULTIPLIER: float = 2.0
const GUN_DAMAGE: int = 1
const TOWER_OF_BABEL_ROOMS: int = 5
const LIGHTS_OUT_DURATION: float = 120.0

const TOWER_LANGUAGES := ["de", "fr", "es", "it", "ja", "zh", "ru", "pt"]

var _active_powerups: Dictionary = {}
var _powerup_timers: Dictionary = {}
var _spawned_pickups: Array[Node] = []

var _tower_of_babel_rooms: Dictionary = {}
var _tower_of_babel_language: Dictionary = {}
var _lights_out_victims: Dictionary = {}  # player_id -> true (affected by lights out)
var _magnet_target_room: String = ""  # room that magnet pulls to

var _spawn_timer: float = 0.0
var _spawn_interval: float = 120.0
var _max_powerups: int = 4
var _powerups_enabled: bool = true  # Can be toggled by host in VoteHUD
var _random_drops_enabled: bool = false  # Random powerup drops during race (host option)
var _random_drop_timer: float = 0.0
var _random_drop_interval: float = 30.0  # Random drop every 30 seconds by default

func set_spawn_interval(seconds: float) -> void:
	if not multiplayer.is_server():
		_request_set_spawn_interval.rpc_id(1, seconds)
		return
	_spawn_interval = seconds
	_broadcast_spawn_interval.rpc(seconds)

@rpc("any_peer", "call_local", "reliable")
func _request_set_spawn_interval(seconds: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	set_spawn_interval(seconds)

@rpc("authority", "call_local", "reliable")
func _broadcast_spawn_interval(seconds: float) -> void:
	_spawn_interval = seconds

func get_spawn_interval() -> float:
	return _spawn_interval

func set_powerups_enabled(enabled: bool) -> void:
	if not multiplayer.is_server():
		# Client requests change - send to server
		_request_set_powerups_enabled.rpc_id(1, enabled)
		return
	
	_powerups_enabled = enabled
	_broadcast_powerup_state.rpc(enabled)
	
	if not enabled:
		# Clear all existing powerups when disabled
		for pickup in _spawned_pickups:
			if is_instance_valid(pickup):
				pickup.queue_free()
		_spawned_pickups.clear()

@rpc("any_peer", "call_remote", "reliable")
func _request_set_powerups_enabled(enabled: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return  # Only server can set
	set_powerups_enabled(enabled)

@rpc("authority", "call_local", "reliable")
func _broadcast_powerup_state(enabled: bool) -> void:
	_powerups_enabled = enabled

func set_random_drops_enabled(enabled: bool) -> void:
	if not multiplayer.is_server():
		# Client requests change - send to server
		_request_set_random_drops.rpc_id(1, enabled)
		return

	_random_drops_enabled = enabled
	_broadcast_random_drop_state.rpc(enabled)

@rpc("any_peer", "call_remote", "reliable")
func _request_set_random_drops(enabled: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return  # Only server can set
	set_random_drops_enabled(enabled)

@rpc("authority", "call_local", "reliable")
func _broadcast_random_drop_state(enabled: bool) -> void:
	_random_drops_enabled = enabled

func is_random_drops_enabled() -> bool:
	return _random_drops_enabled

func _ready() -> void:
	_initialize_powerup_data()

func _process(delta: float) -> void:
	# Powerups only work in multiplayer
	if not NetworkManager.is_multiplayer_active():
		return

	_update_powerup_timers(delta)
	_spawn_timer += delta
	if _spawn_timer >= _spawn_interval:
		_spawn_timer = 0.0
		_try_spawn_powerup()

	# Random powerup drops during race
	if _random_drops_enabled and RaceManager.is_race_active():
		_random_drop_timer += delta
		if _random_drop_timer >= _random_drop_interval:
			_random_drop_timer = 0.0
			_spawn_random_powerup_drop()

func _initialize_powerup_data() -> void:
	_active_powerups.clear()
	_powerup_timers.clear()
	_tower_of_babel_rooms.clear()
	_tower_of_babel_language.clear()
	_lights_out_victims.clear()
	_magnet_target_room = ""

func get_player_powerups(player_id: int) -> Array:
	if not _active_powerups.has(player_id):
		_active_powerups[player_id] = []
	return _active_powerups[player_id]

func has_powerup(player_id: int, powerup_type: PowerupType) -> bool:
	var powerups = get_player_powerups(player_id)
	for p in powerups:
		if p == powerup_type:
			return true
	return false

func add_powerup(player_id: int, powerup_type: PowerupType) -> void:
	if not _active_powerups.has(player_id):
		_active_powerups[player_id] = []

	var duration = POWERUP_DURATIONS[powerup_type]

	if powerup_type in [PowerupType.GUN, PowerupType.TRAP, PowerupType.TOWER_OF_BABEL, PowerupType.MAGNET]:
		if not has_powerup(player_id, powerup_type):
			_active_powerups[player_id].append(powerup_type)
			powerup_collected.emit(player_id, powerup_type)
			# Broadcast to all clients - only server can broadcast
			if multiplayer.is_server():
				_broadcast_powerup_collection.rpc(player_id, powerup_type)
			if powerup_type == PowerupType.TOWER_OF_BABEL:
				_activate_tower_of_babel(player_id)
				# Broadcast the victim list + language to all clients so every
				# peer applies the language to the correct (victim) players.
				if multiplayer.is_server():
					var lang: String = _tower_of_babel_language.values()[0] if not _tower_of_babel_language.is_empty() else ""
					var victim_ids: Array = _tower_of_babel_rooms.keys()
					_broadcast_tower_of_babel.rpc(victim_ids, lang)
			elif powerup_type == PowerupType.MAGNET:
				pass  # Magnet activates on use
	else:
		if not has_powerup(player_id, powerup_type):
			_active_powerups[player_id].append(powerup_type)
			powerup_collected.emit(player_id, powerup_type)
			# Broadcast to all clients - only server can broadcast
			if multiplayer.is_server():
				_broadcast_powerup_collection.rpc(player_id, powerup_type)
			if duration > 0:
				_start_powerup_timer(player_id, powerup_type, duration)
			# LIGHTS_OUT activates immediately on collection — darken all other players.
			if powerup_type == PowerupType.LIGHTS_OUT:
				activate_lights_out(player_id)
				if multiplayer.is_server():
					_broadcast_lights_out_victims.rpc(player_id, _lights_out_victims.keys())

@rpc("authority", "call_remote", "reliable")
func _broadcast_powerup_collection(player_id: int, powerup_type: PowerupType) -> void:
	# Store the powerup and start its timer on this client
	if not _active_powerups.has(player_id):
		_active_powerups[player_id] = []
	if powerup_type not in _active_powerups[player_id]:
		_active_powerups[player_id].append(powerup_type)
		var duration: float = POWERUP_DURATIONS[powerup_type]
		if duration > 0:
			_start_powerup_timer(player_id, powerup_type, duration)
	# Emit signal for UI updates
	powerup_collected_network.emit(player_id, powerup_type)

## Syncs Tower of Babel state to all clients — victim_ids is every player
## who should see garbled rooms (everyone EXCEPT the caster).
@rpc("authority", "call_local", "reliable")
func _broadcast_tower_of_babel(victim_ids: Array, language: String) -> void:
	for vid in victim_ids:
		_tower_of_babel_rooms[vid] = TOWER_OF_BABEL_ROOMS
		_tower_of_babel_language[vid] = language

## Syncs the Lights Out victim list to all clients so affected players
## actually see their screen go dark.
@rpc("authority", "call_local", "reliable")
func _broadcast_lights_out_victims(caster_id: int, victim_ids: Array) -> void:
	_lights_out_victims.clear()
	for pid in victim_ids:
		_lights_out_victims[pid] = true
	# Let any local darkness overlay respond
	powerup_activated.emit(caster_id, PowerupType.LIGHTS_OUT)

func clear_player_powerups_on_disconnect(player_id: int) -> void:
	if _active_powerups.has(player_id):
		var powerups = _active_powerups[player_id].duplicate()
		for p in powerups:
			remove_powerup(player_id, p)
		_active_powerups.erase(player_id)
	# Notify all clients that this player's powerups are cleared
	_broadcast_powerup_clear.rpc(player_id)

@rpc("any_peer", "call_local", "reliable")
func _broadcast_powerup_clear(player_id: int) -> void:
	if _active_powerups.has(player_id):
		_active_powerups.erase(player_id)
	# Emit signal so HUDs can update
	powerup_expired.emit(player_id, -1)  # -1 indicates all powerups cleared

func remove_powerup(player_id: int, powerup_type: PowerupType) -> void:
	if not _active_powerups.has(player_id):
		return

	if powerup_type in _active_powerups[player_id]:
		_active_powerups[player_id].erase(powerup_type)
		_stop_powerup_timer(player_id, powerup_type)
		if powerup_type == PowerupType.TOWER_OF_BABEL:
			_deactivate_tower_of_babel(player_id)
		elif powerup_type == PowerupType.LIGHTS_OUT:
			clear_lights_out()
			if multiplayer.is_server():
				_broadcast_lights_out_clear.rpc()
		powerup_expired.emit(player_id, powerup_type)

func activate_powerup(player_id: int, powerup_type: PowerupType) -> void:
	powerup_activated.emit(player_id, powerup_type)

func use_powerup(player_id: int, powerup_type: PowerupType) -> void:
	if has_powerup(player_id, powerup_type):
		if POWERUP_DURATIONS[powerup_type] <= 0:
			remove_powerup(player_id, powerup_type)
		powerup_used.emit(player_id, powerup_type)
		# Broadcast usage to all clients (for gun, trap, magnet effects)
		_broadcast_powerup_usage.rpc(player_id, powerup_type)

@rpc("authority", "call_remote", "reliable")
func _broadcast_powerup_usage(player_id: int, powerup_type: PowerupType) -> void:
	powerup_used_network.emit(player_id, powerup_type)

func get_remaining_time(player_id: int, powerup_type: PowerupType) -> float:
	var key = "%d_%d" % [player_id, powerup_type]
	if _powerup_timers.has(key):
		return _powerup_timers[key]["remaining"]
	return 0.0

func _start_powerup_timer(player_id: int, powerup_type: PowerupType, duration: float) -> void:
	var key = "%d_%d" % [player_id, powerup_type]
	_powerup_timers[key] = {
		"remaining": duration,
		"total": duration,
		"player_id": player_id,
		"powerup_type": powerup_type
	}

func _stop_powerup_timer(player_id: int, powerup_type: PowerupType) -> void:
	var key = "%d_%d" % [player_id, powerup_type]
	if _powerup_timers.has(key):
		_powerup_timers.erase(key)

func _update_powerup_timers(delta: float) -> void:
	var keys_to_remove: Array = []
	
	for key in _powerup_timers.keys():
		var timer_data = _powerup_timers[key]
		timer_data["remaining"] -= delta
		
		if timer_data["remaining"] <= 0:
			remove_powerup(timer_data["player_id"], timer_data["powerup_type"])
			keys_to_remove.append(key)
	
	for key in keys_to_remove:
		if _powerup_timers.has(key):
			_powerup_timers.erase(key)

func _try_spawn_powerup() -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	if not _powerups_enabled:
		return
	if not RaceManager.is_race_active():
		return
	if not multiplayer.is_server():
		return
	if _spawned_pickups.size() >= _max_powerups:
		return

	# Use all players as anchors so powerups spread across occupied rooms.
	# Skip Lobby since the race is underway.
	var players := get_tree().get_nodes_in_group("Player")
	if players.is_empty():
		return
	players.shuffle()
	var anchor_player: Node3D = null
	for p in players:
		var room: String = p.current_room if "current_room" in p else "Lobby"
		if room != "Lobby":
			anchor_player = p
			break
	if not anchor_player:
		return

	var spawn_pos := _raycast_floor_spawn(anchor_player.global_position)
	if spawn_pos == Vector3.ZERO:
		return

	var powerup_type := _get_random_powerup_type()
	print("PowerupManager: Spawning %s at %s" % [get_powerup_name(powerup_type), str(spawn_pos)])
	_spawn_powerup_pickup(spawn_pos, powerup_type)

func _spawn_random_powerup_drop() -> void:
	## Spawn a random powerup at a random player's location during race
	if not NetworkManager.is_multiplayer_active():
		return
	if not _random_drops_enabled:
		return
	if not RaceManager.is_race_active():
		return
	if not multiplayer.is_server():
		return
	if _spawned_pickups.size() >= _max_powerups:
		return

	# Pick a random player (excluding Lobby) as the anchor
	var players := get_tree().get_nodes_in_group("Player")
	if players.is_empty():
		return
	
	var valid_players: Array = []
	for p in players:
		var room: String = p.current_room if "current_room" in p else "Lobby"
		if room != "Lobby":
			valid_players.append(p)
	
	if valid_players.is_empty():
		return
	
	var anchor_player: Node3D = valid_players[randi() % valid_players.size()]
	var spawn_pos := _raycast_floor_spawn(anchor_player.global_position)
	if spawn_pos == Vector3.ZERO:
		return

	var powerup_type := _get_random_powerup_type()
	print("PowerupManager [Random Drop]: Spawning %s at %s (near %s)" % [
		get_powerup_name(powerup_type), str(spawn_pos), anchor_player.name
	])
	_spawn_powerup_pickup(spawn_pos, powerup_type)

## Fire raycasts downward at several XZ offsets around [anchor] to find the floor.
## Returns the hit position raised 0.8 m above the surface, or Vector3.ZERO on failure.
func _raycast_floor_spawn(anchor: Vector3) -> Vector3:
	## Tight offsets keep spawns inside small rooms.
	var space := get_tree().root.get_world_3d().direct_space_state
	if not space:
		return Vector3.ZERO

	# Small offsets only — stays inside even the narrowest exhibit rooms.
	var offsets: Array = [
		Vector2(0, 0),
		Vector2(0.8, 0), Vector2(-0.8, 0), Vector2(0, 0.8), Vector2(0, -0.8),
		Vector2(0.8, 0.8), Vector2(-0.8, 0.8), Vector2(0.8, -0.8), Vector2(-0.8, -0.8),
	]
	offsets.shuffle()

	for off in offsets:
		var from := Vector3(anchor.x + off.x, anchor.y + 8.0, anchor.z + off.y)
		var to   := Vector3(anchor.x + off.x, anchor.y - 3.0, anchor.z + off.y)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		var result := space.intersect_ray(query)
		if not result or not result.has("position"):
			continue
		var hit := result["position"] as Vector3
		# Must land on a floor (normal points upward) not a wall or ceiling.
		var normal := result.get("normal", Vector3.UP) as Vector3
		if normal.y < 0.7:
			continue
		# Must be within 2 m horizontally of the anchor so we stay in the same room.
		if Vector2(hit.x - anchor.x, hit.z - anchor.z).length() > 2.5:
			continue
		return hit + Vector3(0.0, 0.8, 0.0)

	return Vector3.ZERO

func _get_random_powerup_type() -> PowerupType:
	# Weighted random selection - grapple is very rare (5% chance)
	var roll = randf()
	if roll < 0.05:
		return PowerupType.GRAPPLE  # 5% - Ultra rare!
	else:
		# Common powerups (95% chance, distributed evenly)
		var common_types = [
			PowerupType.SPEED_BOOST,
			PowerupType.PERFECT_KNOWLEDGE,
			PowerupType.GUN,
			PowerupType.TRAP,
			PowerupType.LIGHTS_OUT,
			PowerupType.MAGNET,
			PowerupType.TOWER_OF_BABEL,
			PowerupType.OMNISCIENCE
		]
		return common_types[randi() % common_types.size()]

func spawn_powerup_at(position: Vector3, powerup_type: PowerupType = -1) -> void:
	var type = powerup_type
	if type < 0 or type >= PowerupType.size():
		type = PowerupType.values()[randi() % PowerupType.size()]
	_spawn_powerup_pickup(position, type)

func debug_spawn_powerup_near_player() -> void:
	## Debug function to spawn a powerup near the local player for testing
	print("PowerupManager: debug_spawn_powerup_near_player called")
	if not _powerups_enabled:
		print("PowerupManager: Powerups are disabled by host!")
		return

	# Find the local player (the one controlled by this client)
	var player = get_tree().get_first_node_in_group("local_player")
	print("PowerupManager: local_player group search result: %s" % str(player))
	if not player:
		# Try finding any player with is_local = true
		for p in get_tree().get_nodes_in_group("Player"):
			print("PowerupManager: Checking player %s, is_local=%s" % [p, p.is_local if p.has_method("is_local") else "N/A"])
			if p.has_method("is_local") and p.is_local:
				player = p
				break
	if not player:
		print("PowerupManager: No local player found!")
		return

	var spawn_pos = player.global_position + player.global_transform.basis.z * 3.0 + Vector3(0, 1.0, 0)
	var powerup_type = _get_random_powerup_type()
	
	# Use the RPC spawn method so all clients see it
	_spawn_powerup_pickup(spawn_pos, powerup_type)

func _spawn_powerup_pickup(position: Vector3, powerup_type: PowerupType) -> void:
	# Spawn pickup on all clients via RPC for visibility
	if multiplayer.is_server():
		# Server spawns and broadcasts to all clients
		_spawn_powerup_pickup_rpc.rpc(position, powerup_type)
	else:
		# Client requests server to spawn - server will broadcast to everyone
		_spawn_powerup_pickup_request.rpc_id(1, position, powerup_type)

@rpc("any_peer", "call_local", "reliable")
func _spawn_powerup_pickup_request(position: Vector3, powerup_type: PowerupType) -> void:
	# Only server should process this
	if not multiplayer.is_server():
		return
	# Server spawns and broadcasts to ALL clients (including requester)
	_spawn_powerup_pickup_rpc.rpc(position, powerup_type)

@rpc("authority", "call_local", "reliable")
func _spawn_powerup_pickup_rpc(position: Vector3, powerup_type: PowerupType) -> void:
	var pickup_scene = load("res://scenes/items/PowerupPickup.tscn")
	if not pickup_scene:
		print("PowerupManager: Failed to load pickup scene!")
		return

	var pickup: Node3D = pickup_scene.instantiate()
	pickup.set_powerup_type(powerup_type)

	var current_scene = get_tree().current_scene
	if not current_scene:
		current_scene = get_tree().root
		print("PowerupManager: Using root as current_scene")

	current_scene.add_child(pickup)
	pickup.global_position = position
	_spawned_pickups.append(pickup)

	pickup.tree_exiting.connect(func():
		_spawned_pickups.erase(pickup)
	)

func get_powerup_name(powerup_type: PowerupType) -> String:
	return POWERUP_NAMES[powerup_type]

func get_powerup_color(powerup_type: PowerupType) -> Color:
	return POWERUP_COLORS[powerup_type]

func clear_player_powerups(player_id: int) -> void:
	if _active_powerups.has(player_id):
		var powerups = _active_powerups[player_id].duplicate()
		for p in powerups:
			remove_powerup(player_id, p)
		_active_powerups.erase(player_id)

func _activate_tower_of_babel(caster_id: int) -> void:
	# Apply to every connected player EXCEPT the caster.
	var lang_idx := randi() % TOWER_LANGUAGES.size()
	var language: String = TOWER_LANGUAGES[lang_idx]
	for pid in NetworkManager.get_player_list():
		if pid != caster_id:
			_tower_of_babel_rooms[pid] = TOWER_OF_BABEL_ROOMS
			_tower_of_babel_language[pid] = language

func _deactivate_tower_of_babel(_caster_id: int) -> void:
	## Clear all victim entries — the effect ends for everyone at once.
	_tower_of_babel_rooms.clear()
	_tower_of_babel_language.clear()

func tower_of_babel_enter_room(local_player_id: int) -> void:
	## Called when the LOCAL player enters a room — decrements their own counter.
	## Each victim independently tracks how many rooms they have left.
	if not _tower_of_babel_rooms.has(local_player_id):
		return
	_tower_of_babel_rooms[local_player_id] -= 1
	if _tower_of_babel_rooms[local_player_id] <= 0:
		_tower_of_babel_rooms.erase(local_player_id)
		_tower_of_babel_language.erase(local_player_id)
		# Tell server this victim is done so it can track overall expiry
		if not multiplayer.is_server():
			_notify_babel_victim_done.rpc_id(1, local_player_id)

@rpc("any_peer", "call_local", "reliable")
func _notify_babel_victim_done(victim_id: int) -> void:
	## Server receives this when a victim has used up all their babel rooms.
	_tower_of_babel_rooms.erase(victim_id)
	_tower_of_babel_language.erase(victim_id)
	# If no victims remain, the caster's powerup can be removed too
	if _tower_of_babel_rooms.is_empty():
		for pid in _active_powerups.keys():
			if has_powerup(pid, PowerupType.TOWER_OF_BABEL):
				remove_powerup(pid, PowerupType.TOWER_OF_BABEL)
				_broadcast_tower_of_babel_expired.rpc(pid)
				break

@rpc("authority", "call_local", "reliable")
func _broadcast_tower_of_babel_expired(caster_id: int) -> void:
	_deactivate_tower_of_babel(caster_id)

func get_tower_of_babel_language(player_id: int) -> String:
	return _tower_of_babel_language.get(player_id, "")

func is_tower_of_babel_active(player_id: int) -> bool:
	return _tower_of_babel_rooms.has(player_id) and _tower_of_babel_rooms[player_id] > 0

# Lights Out powerup functions
func activate_lights_out(caster_id: int) -> void:
	# Mark all connected players except the caster as victims.
	# Use NetworkManager's authoritative list — never guess peer IDs from node refs.
	_lights_out_victims.clear()
	for pid in NetworkManager.get_player_list():
		if pid != caster_id:
			_lights_out_victims[pid] = true
	# Also emit locally so a darkness overlay on the caster's machine can react.
	powerup_activated.emit(caster_id, PowerupType.LIGHTS_OUT)

func is_lights_out_victim(player_id: int) -> bool:
	return _lights_out_victims.has(player_id)

func clear_lights_out() -> void:
	_lights_out_victims.clear()

@rpc("authority", "call_local", "reliable")
func _broadcast_lights_out_clear() -> void:
	_lights_out_victims.clear()
	# Signal consumers (darkness overlay) to restore normal vision
	powerup_expired.emit(-1, PowerupType.LIGHTS_OUT)

# Magnet powerup functions
func activate_magnet(caster_id: int, target_room: String) -> void:
	_magnet_target_room = target_room
	# Magnet is instant - all players get pulled immediately
	magnet_pull_all_players(target_room)

func magnet_pull_all_players(target_room: String) -> void:
	# This will be handled by PlayerPowerupSystem
	pass

func get_magnet_target_room() -> String:
	return _magnet_target_room

func clear_magnet() -> void:
	_magnet_target_room = ""
