@tool
extends Node3D
## LobbySkylight — full-roof glass skylight covering the entire lobby.
##
## Reads the lobby's GridMap to find every ceiling tile (item 3) and places
## a matching glass panel + frame bar over each one, so the skylight exactly
## follows the lobby's footprint — no manual sizing needed.
##
## Place as a child of the Lobby Node3D. The script positions everything
## automatically in _build() via GridMap cell positions.
##
## Prerequisites:
##   • Lobby.gd hide_ceiling(true) has removed the ceiling tiles.
##   • A WorldEnvironment with skybox.gdshader is set up (sky is visible above).
##
## Usage:
##   1. Place LobbySkylight.tscn as a child of Lobby.
##   2. In the Inspector, assign grid_map_path to the GridMap node.
##   3. Hit "regenerate" to rebuild, or it auto-builds on _ready.

@export var grid_map_path: NodePath = NodePath("../GridMap")

## Visual settings
@export var frame_thickness: float = 0.14
@export var frame_height:    float = 0.18
@export var glass_thickness: float = 0.05
@export var glass_opacity:   float = 0.22   ## 0=invisible, 1=solid
@export var glass_tint:      Color = Color(0.88, 0.93, 1.00)
@export var brightness:      float = 1.4    ## emissive multiplier

@export var regenerate: bool = false:
	set(v):
		if v: _build()


func _ready() -> void:
	if get_child_count() == 0:
		call_deferred("_build")


func _build() -> void:
	for c in get_children(): c.queue_free()
	await get_tree().process_frame

	var grid: GridMap = get_node_or_null(grid_map_path)
	if not grid:
		push_error("LobbySkylight: GridMap not found at path '%s'" % grid_map_path)
		return

	var cell_size: Vector3 = grid.cell_size          # (4, 4, 4)
	var pw: float = cell_size.x
	var pd: float = cell_size.z

	var glass_mat := _make_glass_mat()
	var frame_mat := _make_frame_mat()

	# Shared glass mesh — one per cell, reused
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(pw - frame_thickness, glass_thickness, pd - frame_thickness)

	# Frame bar meshes
	var h_bar_mesh := BoxMesh.new()   ## runs along X (one per row boundary)
	h_bar_mesh.size = Vector3(pw, frame_height, frame_thickness)

	var v_bar_mesh := BoxMesh.new()   ## runs along Z (one per col boundary)
	v_bar_mesh.size = Vector3(frame_thickness, frame_height, pd)

	# ── Collect all ceiling tile positions ────────────────────────────────────
	# item 3 = "ceiling" in MeshLibrary (confirmed from MeshLibrary.tscn node order)
	const CEILING_ITEM: int    = 3
	const CEILING_YS:   Array[int] = [4, 5]

	var placed := 0
	for cell_pos: Vector3i in grid.get_used_cells():
		if cell_pos.y not in CEILING_YS:
			continue
		if grid.get_cell_item(cell_pos) != CEILING_ITEM:
			continue

		# World position of this cell's centre
		# GridMap map_to_local gives the local position of the cell
		var local_pos: Vector3 = grid.map_to_local(cell_pos)
		# Offset to parent (LobbySkylight is a child of Lobby's root Node3D)
		var world_pos: Vector3 = grid.to_global(local_pos)
		var self_pos:  Vector3 = to_local(world_pos)

		# Place glass panel at this cell, slightly below the ceiling tile's top
		var glass_mi := MeshInstance3D.new()
		glass_mi.name = "Glass_%d_%d_%d" % [cell_pos.x, cell_pos.y, cell_pos.z]
		glass_mi.mesh = glass_mesh
		glass_mi.position = Vector3(self_pos.x, self_pos.y + cell_size.y * 0.5 - glass_thickness, self_pos.z)
		glass_mi.set_surface_override_material(0, glass_mat)
		_add(glass_mi)

		# Frame bars — X-direction bar (south edge of cell)
		var hb := MeshInstance3D.new()
		hb.mesh = h_bar_mesh
		hb.position = glass_mi.position + Vector3(0.0, 0.0, pd * 0.5)
		hb.set_surface_override_material(0, frame_mat)
		_add(hb)

		# Frame bars — Z-direction bar (east edge of cell)
		var vb := MeshInstance3D.new()
		vb.mesh = v_bar_mesh
		vb.position = glass_mi.position + Vector3(pw * 0.5, 0.0, 0.0)
		vb.set_surface_override_material(0, frame_mat)
		_add(vb)

		placed += 1

	# ── Soft fill light below the skylight ───────────────────────────────────
	var fill := OmniLight3D.new()
	fill.name              = "SkylightFill"
	fill.light_color       = glass_tint
	fill.light_energy      = brightness * 0.55
	fill.omni_range        = 80.0
	fill.omni_attenuation  = 0.5
	fill.shadow_enabled    = false
	fill.position          = Vector3(0.0, 12.0, 8.0)  ## centre of lobby approx
	_add(fill)

	if OS.is_debug_build():
		print("[LobbySkylight] Built %d glass panels from GridMap ceiling tiles" % placed)


func _make_glass_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency          = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color          = Color(glass_tint.r, glass_tint.g, glass_tint.b, glass_opacity)
	mat.roughness             = 0.02
	mat.metallic_specular     = 1.0
	mat.emission_enabled      = true
	mat.emission              = glass_tint * brightness
	mat.emission_energy_multiplier = brightness * 0.5
	mat.cull_mode             = BaseMaterial3D.CULL_DISABLED
	return mat


func _make_frame_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color      = Color(0.18, 0.18, 0.20)
	mat.roughness         = 0.50
	mat.metallic          = 0.90
	mat.metallic_specular = 0.60
	return mat


func _add(node: Node) -> void:
	add_child(node)
	if Engine.is_editor_hint():
		node.owner = get_tree().edited_scene_root
