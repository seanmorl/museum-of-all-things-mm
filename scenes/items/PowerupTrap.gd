extends Node3D
class_name PowerupTrap
## Placeable trap that teleports players to lobby when triggered.

signal triggered(trap: Node3D, victim: CharacterBody3D)

@onready var _area: Area3D = $Area3D
@onready var _mesh: MeshInstance3D = $Area3D/MeshInstance3D

var _owner_player: CharacterBody3D = null
var _armed: bool = false
var _arm_delay: float = 1.0
var _arm_timer: float = 0.0
var _is_local_owner: bool = false  ## true only on the client who placed this trap

func _ready() -> void:
	_setup_trap()
	# Signal connection handled by scene file, don't double-connect

func _setup_trap() -> void:
	if not _area:
		var area = Area3D.new()
		area.name = "Area3D"
		add_child(area)
		_area = area
		
		var collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var cylinder = CylinderShape3D.new()
		cylinder.radius = 1.5
		cylinder.height = 0.5
		collision.shape = cylinder
		area.add_child(collision)
		
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "MeshInstance3D"
		var cylinder_mesh = CylinderMesh.new()
		cylinder_mesh.top_radius = 1.5
		cylinder_mesh.bottom_radius = 1.5
		cylinder_mesh.height = 0.1
		mesh_inst.mesh = cylinder_mesh
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.8, 0.2, 0.3)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 1.0, 0.2)
		mat.emission_energy_multiplier = 0.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_inst.material_override = mat
		
		area.add_child(mesh_inst)
		_mesh = mesh_inst
		
		_mesh.visible = false

func set_owner_player(player: CharacterBody3D) -> void:
	_owner_player = player
	# The mesh starts hidden (set in _setup_trap).
	# Visibility is granted only to the owner once armed — see _process.
	# On all other clients this node exists but the mesh stays invisible,
	# so victims can't see the trap coming.
	var local_id: int = NetworkManager.get_unique_id()
	var owner_id: int = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else -1
	_is_local_owner = (owner_id == local_id) or ("is_local" in player and player.is_local)

func _process(delta: float) -> void:
	if not _armed:
		_arm_timer += delta
		if _arm_timer >= _arm_delay:
			_armed = true
			# Only the owner sees the trap — victims stay in the dark
			if _is_local_owner and _mesh:
				_mesh.visible = true
				_animate_armed()

func _animate_armed() -> void:
	var mat = _mesh.get_surface_override_material(0)
	if mat:
		var tween = create_tween().set_loops()
		tween.tween_property(mat, "emission_energy_multiplier", 1.5, 0.5)
		tween.tween_property(mat, "emission_energy_multiplier", 0.5, 0.5)

func _on_body_entered(body: Node3D) -> void:
	if not _armed:
		return
	
	if body == _owner_player:
		return
	
	if body.name != "Player":
		return
	
	var victim = body as CharacterBody3D
	if victim:
		triggered.emit(self, victim)
