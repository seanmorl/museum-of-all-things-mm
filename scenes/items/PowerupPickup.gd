extends Node3D
class_name PowerupPickup
## Collectible powerup item that spawns in exhibits.

const COLORS := {
	PowerupManager.PowerupType.SPEED_BOOST: Color(1.0, 0.8, 0.0),
	PowerupManager.PowerupType.PERFECT_KNOWLEDGE: Color(0.0, 1.0, 1.0),
	PowerupManager.PowerupType.GUN: Color(1.0, 0.2, 0.2),
	PowerupManager.PowerupType.TRAP: Color(0.2, 1.0, 0.2),
	PowerupManager.PowerupType.TOWER_OF_BABEL: Color(0.6, 0.4, 0.9),
	PowerupManager.PowerupType.LIGHTS_OUT: Color(0.1, 0.1, 0.3),
	PowerupManager.PowerupType.MAGNET: Color(0.8, 0.2, 0.5),
	PowerupManager.PowerupType.GRAPPLE: Color(0.95, 0.95, 0.95)
}

@onready var _area: Area3D = $Area3D
@onready var _mesh: MeshInstance3D = $Area3D/MeshInstance3D
@onready var _particles: GPUParticles3D = $Area3D/GPUParticles3D
@onready var _light: OmniLight3D = $Area3D/OmniLight3D

var _powerup_type: PowerupManager.PowerupType = PowerupManager.PowerupType.SPEED_BOOST
var _collected: bool = false
var _bob_timer: float = 0.0
var _rot_speed: float = 2.0

func _ready() -> void:
	_setup_pickup()
	_area.body_entered.connect(_on_body_entered)

	await get_tree().process_frame
	_update_visuals()

	if _mesh:
		var mat = _mesh.get_surface_override_material(0)
		if mat:
			mat.emission = _get_color()
			mat.emission_energy_multiplier = 2.0

	if _light:
		_light.light_color = _get_color()
		_light.light_energy = 2.0

func _setup_pickup() -> void:
	if not _mesh:
		var area = Area3D.new()
		area.name = "Area3D"
		add_child(area)
		_area = area

		var collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var sphere = SphereShape3D.new()
		sphere.radius = 0.5
		collision.shape = sphere
		area.add_child(collision)

		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "MeshInstance3D"
		var box = BoxMesh.new()
		box.size = Vector3(0.4, 0.4, 0.4)
		mesh_inst.mesh = box

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.2, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 1.0, 1.0)
		mat.emission_energy_multiplier = 1.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = false
		mesh_inst.material_override = mat

		area.add_child(mesh_inst)
		_mesh = mesh_inst

		var light = OmniLight3D.new()
		light.name = "OmniLight3D"
		light.light_color = Color(1.0, 1.0, 1.0)
		light.light_energy = 1.0
		light.omni_range = 3.0
		area.add_child(light)
		_light = light

func set_powerup_type(type: PowerupManager.PowerupType) -> void:
	_powerup_type = type
	_update_visuals()

func _update_visuals() -> void:
	var color = _get_color()
	if _mesh:
		var mat = _mesh.get_surface_override_material(0)
		if not mat:
			mat = StandardMaterial3D.new()
			_mesh.set_surface_override_material(0, mat)
		mat.albedo_color = color * 0.5
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
	if _light:
		_light.light_color = color
		_light.light_energy = 3.0
		# Keep range tight so the light doesn't bleed through walls into other rooms
		_light.omni_range = 2.0

func _get_color() -> Color:
	return COLORS.get(_powerup_type, Color.WHITE)

func _process(delta: float) -> void:
	if _collected:
		return
	_bob_timer += delta
	_mesh.position.y = sin(_bob_timer * 3.0) * 0.15
	_mesh.rotation.y += _rot_speed * delta
	_mesh.rotation.x += _rot_speed * 0.5 * delta

func _on_body_entered(body: Node3D) -> void:
	if _collected:
		return
	# Match the same player-detection pattern used by Hall loaders in Museum.gd.
	if not body.is_in_group("Player"):
		return
	# In multiplayer only the local player triggers collection on their client.
	var is_local: bool = body.get("is_local") if "is_local" in body else true
	if not is_local:
		return

	_collected = true
	var player_id: int = body.get_multiplayer_authority()

	if multiplayer.is_server():
		_server_collect(player_id, _powerup_type)
	else:
		_request_collect_rpc.rpc_id(1, player_id, _powerup_type)

# ── Server-side: receive collection request from a client ─────────────────────

@rpc("any_peer", "call_local", "reliable")
func _request_collect_rpc(player_id: int, powerup_type: int) -> void:
	if not multiplayer.is_server():
		return
	_server_collect(player_id, powerup_type)

func _server_collect(player_id: int, powerup_type: int) -> void:
	# Use PowerupManager's proper API — this fires all signals and starts timers.
	PowerupManager.add_powerup(player_id, powerup_type)
	# Tell all clients (including server itself) to animate the pickup away.
	_do_collect_rpc.rpc(player_id, powerup_type)

# ── Broadcast: animate pickup removal on every client ─────────────────────────

@rpc("authority", "call_local", "reliable")
func _do_collect_rpc(player_id: int, powerup_type: int) -> void:
	_collected = true
	_animate_collection()

# ── Visuals ────────────────────────────────────────────────────────────────────

func _animate_collection() -> void:
	# Stop particles immediately so they don't keep emitting after collection.
	# NOTE: GPUParticles3D.amount minimum is 1 — never set it to 0.
	if _particles and is_instance_valid(_particles):
		_particles.emitting = false
	# Shrink the whole pickup node (not just mesh) so nothing lingers.
	var tween = create_tween().set_parallel(true)
	if _mesh and is_instance_valid(_mesh):
		tween.tween_property(_mesh, "scale", Vector3(0.05, 0.05, 0.05), 0.12)
	if _light and is_instance_valid(_light):
		tween.tween_property(_light, "light_energy", 0.0, 0.12)
	# queue_free the root Node3D (self), which cleans up all children atomically.
	tween.chain().tween_callback(queue_free)
