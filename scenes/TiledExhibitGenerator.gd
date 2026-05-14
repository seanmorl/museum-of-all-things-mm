extends Node3D
## Procedurally generates tiled exhibit rooms with walls, floors, and item slots.

signal exit_added(exit: Hall)

# Use GridConstants for cell types
const FLOOR_WOOD: int = GridConstants.FLOOR_WOOD
const RESERVED_VAL: int = GridConstants.RESERVED_VAL
const FLOOR_CARPET: int = GridConstants.FLOOR_CARPET
const FLOOR_MARBLE: int = GridConstants.FLOOR_MARBLE

const WALL: int = GridConstants.WALL
const CEILING: int = GridConstants.CEILING
const INTERNAL_HALL: int = GridConstants.INTERNAL_HALL
const INTERNAL_HALL_TURN: int = GridConstants.INTERNAL_HALL_TURN
const HALL_STAIRS_UP: int = GridConstants.HALL_STAIRS_UP
const HALL_STAIRS_DOWN: int = GridConstants.HALL_STAIRS_DOWN
const HALL_STAIRS_TURN: int = GridConstants.HALL_STAIRS_TURN
const MARKER: int = GridConstants.MARKER
const BENCH: int = GridConstants.BENCH
const FREE_WALL: int = GridConstants.FREE_WALL

const DIRECTIONS: Array[Vector3] = GridConstants.DIRECTIONS
const _GROUP_SCENERY := &"Scenery"

const _POOL_SCENE: PackedScene = preload("res://scenes/items/Pool.tscn")
const _PLANTER_SCENE: PackedScene = preload("res://scenes/items/Planter.tscn")
const _SMALL_PLANTER_SCENE: PackedScene = preload("res://scenes/items/SmallPlanter.tscn")
const _BENCH_SCENE: PackedScene = preload("res://scenes/items/Bench.tscn")
const _HALL_SCENE: PackedScene = preload("res://scenes/Hall.tscn")
const _GRID_WRAPPER: PackedScene = preload("res://scenes/util/GridWrapper.tscn")

var _rng: RandomNumberGenerator = null
var title: String = ""
var _prev_title: String = ""

var entry: Hall = null
var exits: Array[Hall] = []

var _room_count: int:
	get:
		return _room_list.size()
	set(_v):
		pass

var _item_slot_map: Dictionary = {}
var _item_slots: Array = []
var _item_slot_idx: int = 0

var _y: int = 0
var _room_list: Dictionary = {}
var _next_room_candidates: Array = []

var _raw_grid: GridMap = null
var _grid: Node = null
var _floor: int = FLOOR_WOOD
var _no_props: bool = false
var _exit_limit: int = 1000000
var _min_room_dimension: int = 2
var _max_room_dimension: int = 5
var _orig_min_room_dimension: int = 2
var _orig_max_room_dimension: int = 5
var _min_rooms: int = 2
var _debug_mode: bool = false
var _debug_meshes: Array[MeshInstance3D] = []
var _mood: int = ExhibitMood.Mood.DEFAULT
var _secret_room_count: int = 0
var _secret_item_slots: Array = []


func _ready() -> void:
	pass


func _rand_dim() -> int:
	return _rng.randi_range(_min_room_dimension, _max_room_dimension)


func rand_dir() -> Vector3:
	return DIRECTIONS[_rng.randi() % DIRECTIONS.size()]


func vlt(v1: Vector3, v2: Vector3) -> Vector3:
	return v1 if v1.x < v2.x or v1.z < v2.z else v2


func vgt(v1: Vector3, v2: Vector3) -> Vector3:
	return v1 if v1.x > v2.x or v1.z > v2.z else v2


func vec_key(v: Vector3) -> Vector3i:
	return Vector3i(int(v.x), int(v.y), int(v.z))


func add_item_slot(s: Array) -> void:
	var k: Vector3i = vec_key(s[0])
	if not _item_slot_map.has(k):
		_item_slot_map[vec_key(s[0])] = s
		_item_slots.append(s)


func has_item_slot() -> bool:
	return _item_slot_idx < _item_slots.size()


func get_item_slot() -> Variant:
	if has_item_slot():
		var slot: Array = _item_slots[_item_slot_idx]
		_item_slot_idx += 1
		return slot
	else:
		return null


func generate(params: Dictionary) -> void:
	var total_start = Time.get_ticks_msec()
	Log.info("TiledExhibitGenerator", "=== Starting generation for '%s' ===" % title)
	
	# set initial fields
	var step_start = Time.get_ticks_msec()
	_min_room_dimension = params.min_room_dimension
	_max_room_dimension = params.max_room_dimension
	_orig_min_room_dimension = _min_room_dimension
	_orig_max_room_dimension = _max_room_dimension
	_min_rooms = params.get("min_rooms", 2)
	_debug_mode = params.get("debug_mode", false)

	var start_pos: Vector3 = params.start_pos
	title = params.title
	var prev_title: String = params.prev_title
	var hall_type: Array = params.hall_type if params.has("hall_type") else [true, 0]
	_y = int(start_pos.y)

	_no_props = params.has("no_props") and params.no_props
	_exit_limit = params.exit_limit if params.has("exit_limit") else 1000000
	_mood = params.get("mood", ExhibitMood.Mood.DEFAULT)
	Log.info("TiledExhibitGenerator", "Step 1 - Parse params: %dms" % (Time.get_ticks_msec() - step_start))

	# init rng
	step_start = Time.get_ticks_msec()
	_rng = RandomNumberGenerator.new()
	# Session-based seed: same article varies each play session
	var session_seed = Time.get_ticks_usec()
	_rng.seed = hash(title) ^ session_seed
	_prev_title = prev_title
	_floor = ExhibitStyle.gen_floor_mooded(title, _mood)
	Log.info("TiledExhibitGenerator", "Step 2 - Init RNG/style: %dms" % (Time.get_ticks_msec() - step_start))

	# init grid
	step_start = Time.get_ticks_msec()
	_grid = _GRID_WRAPPER.instantiate()
	add_child(_grid)
	_raw_grid = _grid._grid
	Log.info("TiledExhibitGenerator", "Step 3 - Create grid: %dms" % (Time.get_ticks_msec() - step_start))

	# init starting hall
	step_start = Time.get_ticks_msec()
	var starting_hall: Hall = _HALL_SCENE.instantiate()
	add_child(starting_hall)
	starting_hall.init(
		_grid,
		prev_title,
		title,
		start_pos + (Vector3.DOWN * hall_type[1]),
		Vector3(1, 0, 0),
		hall_type,
	)

	starting_hall.entry_door.set_open(false, true)
	starting_hall.from_sign.visible = true

	# initialize public fields
	entry = starting_hall
	Log.info("TiledExhibitGenerator", "Step 4 - Create starting hall: %dms" % (Time.get_ticks_msec() - step_start))

	# now we create the first room
	var room_step_start = Time.get_ticks_msec()
	var room_width: int = _rand_dim()
	var room_length: int = _rand_dim()
	var room_center: Vector3 = Vector3(
		starting_hall.to_pos.x + starting_hall.to_dir.x * (2 + room_width / 2),
		_y,
		starting_hall.to_pos.z + starting_hall.to_dir.z * (2 + room_length / 2),
	) - (starting_hall.to_dir if hall_type[0] else Vector3.ZERO)

	var room_obj: Dictionary = _add_to_room_list(room_center, room_width, room_length)
	var bounds: Array = _room_to_bounds(room_center, room_width, room_length)
	_carve_room(bounds[0], bounds[1], _y)
	_create_next_room_candidate(room_obj)
	_decorate_entry(starting_hall, room_obj)
	_decorate_room(room_obj)
	Log.info("TiledExhibitGenerator", "Step 5 - Create first room: %dms" % (Time.get_ticks_msec() - room_step_start))

	# Ensure minimum room count
	_validate_generation_progress()

	# Final validation (just checks rooms exist, no structural analysis)
	if _room_list.is_empty():
		Log.error("TiledExhibitGenerator", "Final validation FAILED: No rooms generated")
	elif entry == null:
		Log.error("TiledExhibitGenerator", "Final validation FAILED: No entry hall")
	else:
		Log.info("TiledExhibitGenerator", "Validation PASSED: %d rooms generated" % _room_list.size())

	Log.info("TiledExhibitGenerator", "=== Generation complete: %d rooms, %dms ===" % [
		_room_list.size(), Time.get_ticks_msec() - total_start])


func _create_next_room_candidate(last_room: Dictionary) -> void:
	var room_width: int = _rand_dim()
	var room_length: int = _rand_dim()

	# Mood-biased dimensions
	if ExhibitMood.prefers_symmetry(_mood) and _rng.randf() < 0.15:
		room_width = _rng.randi_range(5, 7)
		room_length = _rng.randi_range(4, 6)

	var room_center: Vector3
	var room_bounds: Array
	var next_room_dir: Vector3

	# prepare directions to try
	var try_dirs: Array = DIRECTIONS.duplicate()
	CollectionUtils.shuffle(_rng, try_dirs)

	var failed: bool = true
	for dir: Vector3 in try_dirs:
		# project where the next room will be based on random direction
		room_center = last_room.center + Vector3(
			dir.x * (last_room.width / 2 + room_width / 2 + 3),
			0,
			dir.z * (last_room.length / 2 + room_length / 2 + 3)
		)

		# check if we found a valid room placement
		room_bounds = _room_to_bounds(room_center, room_width, room_length)
		if not _overlaps_room(room_bounds[0], room_bounds[1], _y):
			next_room_dir = dir
			failed = false
			break

	if failed:
		return

	var room_obj: Dictionary = {
		"center": room_center,
		"width": room_width,
		"length": room_length,
	}
	var hall_bounds: Array = _create_hall_bounds(last_room, room_obj)

	_decorate_reserved_walls(last_room, hall_bounds, next_room_dir)

	_grid.reserve_zone(hall_bounds)
	_grid.reserve_zone(room_bounds)
	room_obj.bounds = room_bounds
	room_obj.hall = hall_bounds
	_next_room_candidates.append(room_obj)


func _validate_generation_progress() -> void:
	## Monitors room count and ensures minimum rooms are generated
	var attempts: int = 0
	var max_attempts: int = 3
	
	while _room_list.size() < _min_rooms and attempts < max_attempts:
		if _next_room_candidates.is_empty():
			Log.warn("TiledExhibitGenerator", "No candidates left, attempting fallback (attempt %d/%d)" % [attempts + 1, max_attempts])
			_try_fallback_generation()
			attempts += 1
			continue
		
		add_room()
	
	if _room_list.size() < _min_rooms:
		Log.error("TiledExhibitGenerator", "Failed to reach min_rooms (%d/%d) after %d fallback attempts" % [
			_room_list.size(), _min_rooms, attempts])


func _try_fallback_generation() -> void:
	## Relaxes constraints to find new room candidates when stuck
	# Save current reduced values so we know what we changed
	var prev_min := _min_room_dimension
	var prev_max := _max_room_dimension

	# 1. Try smaller dimensions (but never go below 1)
	_min_room_dimension = maxi(1, _min_room_dimension - 1)
	_max_room_dimension = maxi(2, _max_room_dimension - 1)

	# 2. Try creating candidates from all existing rooms
	var existing_rooms: Array = _room_list.values()
	CollectionUtils.shuffle(_rng, existing_rooms)

	for room: Dictionary in existing_rooms:
		_create_next_room_candidate(room)
		if not _next_room_candidates.is_empty():
			break

	Log.info("TiledExhibitGenerator", "Fallback: Reduced dimensions to %d-%d (was %d-%d)" % [
		_min_room_dimension, _max_room_dimension, prev_min, prev_max])

	# Restore originals after this exhibit so next exhibits start fresh
	_min_room_dimension = _orig_min_room_dimension
	_max_room_dimension = _orig_max_room_dimension


func validate_final_generation() -> bool:
	## Performs post-generation checks
	if _room_list.is_empty():
		Log.error("TiledExhibitGenerator", "Final validation FAILED: No rooms generated")
		return false

	if entry == null:
		Log.error("TiledExhibitGenerator", "Final validation FAILED: No entry hall")
		return false

	Log.info("TiledExhibitGenerator", "Validation PASSED: %d rooms generated" % _room_list.size())
	return true


func _debug_draw_box(c1: Vector3, c2: Vector3, y: int, height: int, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	
	# Calculate size and center in world coordinates
	var size := (c2 - c1) + Vector3(1, 0, 1)
	size.y = height
	
	var center := (c1 + c2) / 2.0
	center.y = y + (height / 2.0) - 0.5
	
	box_mesh.size = size * Constants.GRID_CELL_SIZE
	mesh_instance.mesh = box_mesh
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_color.a = 0.3
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	
	add_child(mesh_instance)
	mesh_instance.global_position = GridUtils.grid_to_world(center)
	_debug_meshes.append(mesh_instance)


func clear_debug_meshes() -> void:
	for mesh in _debug_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_debug_meshes.clear()


func _add_to_room_list(c: Vector3, w: int, l: int) -> Dictionary:
	var room_obj: Dictionary = {
		"center": c,
		"width": w,
		"length": l,
	}
	_room_list[vec_key(c)] = room_obj
	return room_obj


func add_room() -> void:
	var step_start = Time.get_ticks_msec()
	if _next_room_candidates.size() == 0:
		Log.error("ExhibitGenerator", "no room candidate to create")
		return
	if _item_slots.size() > Platform.get_max_slots_per_exhibit():
		return

	var idx: int = _rng.randi() % _next_room_candidates.size()
	var room: Dictionary = _next_room_candidates.pop_at(idx)

	_grid.free_reserved_zone(room.center)

	_add_to_room_list(room.center, room.width, room.length)

	# Determine room type and height
	var room_type: String = "ROOM"
	var height: int = 2
	var debug_color: Color = Color.GREEN

	if _room_count > 2:
		if ExhibitMood.prefers_verticality(_mood) and _rng.randf() < 0.15:
			room_type = "ATRIUM"
			height = 3
			debug_color = Color.PURPLE
			Log.info("TiledExhibitGenerator", "Created ATRIUM at %s" % str(room.center))
		elif ExhibitMood.prefers_symmetry(_mood) and (room.width >= 5 or room.length >= 5):
			room_type = "GRAND_HALL"
			debug_color = Color.GOLD
			Log.info("TiledExhibitGenerator", "Created GRAND_HALL at %s" % str(room.center))
		elif room.width > room.length * 1.5 or room.length > room.width * 1.5:
			debug_color = Color.BLUE # Rectangular
		elif room.width == room.length:
			debug_color = Color.GREEN # Square
		else:
			debug_color = Color.ORANGE # Hallway-ish

	_carve_room(room.hall[0], room.hall[1], _y)
	_carve_room(room.bounds[0], room.bounds[1], _y, height)

	if _debug_mode:
		_debug_draw_box(room.bounds[0], room.bounds[1], _y, height, debug_color)

	_create_next_room_candidate(room)

	# branch sometimes
	if _rng.randi() % 2 == 0:
		_create_next_room_candidate(room)

	_decorate_room(room)
	Log.info("TiledExhibitGenerator", "  add_room(): %dms (total rooms: %d, type: %s)" % [
		Time.get_ticks_msec() - step_start, _room_list.size(), room_type])


func _clear_scenery_in_area(h1: Vector3, h2: Vector3) -> void:
	var wh1: Vector3 = GridUtils.grid_to_world(h1)
	var wh2: Vector3 = GridUtils.grid_to_world(h2)
	for c: Node in get_children():
		if c.is_in_group(_GROUP_SCENERY):
			var p: Vector3 = c.global_position
			if p.x >= wh1.x and p.x <= wh2.x and p.z >= wh1.z and p.z <= wh2.z:
				c.queue_free()


func _create_hall_bounds(last_room: Dictionary, next_room: Dictionary) -> Array:
	var start_hall: Vector3 = vlt(last_room.center, next_room.center)
	var end_hall: Vector3 = vgt(last_room.center, next_room.center)
	var hall_width: int

	if (start_hall - end_hall).x != 0:
		hall_width = _rng.randi_range(1, mini(last_room.length, next_room.length))
		start_hall -= Vector3(0, 0, hall_width / 2)
		end_hall += Vector3(0, 0, (hall_width - 1) / 2)
	else:
		hall_width = _rng.randi_range(1, mini(last_room.width, next_room.width))
		start_hall -= Vector3(hall_width / 2, 0, 0)
		end_hall += Vector3((hall_width - 1) / 2, 0, 0)

	return [start_hall, end_hall]


func _decorate_entry(starting_hall: Hall, _room_obj: Dictionary) -> void:
	var free_wall_pos: Vector3 = starting_hall.to_pos + 2 * starting_hall.to_dir
	var free_wall_ori: int = GridUtils.vec_to_orientation(_grid, starting_hall.to_dir.rotated(Vector3.UP, PI / 2))
	_grid.set_cell_item(free_wall_pos, FREE_WALL, free_wall_ori)
	add_item_slot([free_wall_pos - starting_hall.to_dir * 0.075, starting_hall.to_dir])
	add_item_slot([free_wall_pos + starting_hall.to_dir * 0.075, -starting_hall.to_dir])


func _decorate_room(room: Dictionary) -> void:
	var step_start = Time.get_ticks_msec()
	var center: Vector3 = room.center
	var width: int = room.width
	var length: int = room.length

	var bounds: Array = _room_to_bounds(center, width, length)
	var c1: Vector3 = bounds[0]
	var c2: Vector3 = bounds[1]
	var y: int = int(center.y)

	# walk border of room to place wall objects
	for z: int in [int(c1.z), int(c2.z)]:
		for x: int in range(int(c1.x), int(c2.x) + 1):
			_decorate_wall_tile(Vector3(x, y, z))
	for x: int in [int(c1.x), int(c2.x)]:
		for z: int in range(int(c1.z), int(c2.z) + 1):
			_decorate_wall_tile(Vector3(x, y, z))

	if !Engine.is_editor_hint() and not _no_props:
		_decorate_room_center(center, width, length)
		_try_place_secret_room(room)
	
	Log.info("TiledExhibitGenerator", "  _decorate_room(): %dms" % (Time.get_ticks_msec() - step_start))


func _decorate_reserved_walls(last_room: Dictionary, hall_bounds: Array, dir: Vector3) -> void:
	var hall_bounds_width: float = hall_bounds[1].x - hall_bounds[0].x
	var hall_bounds_length: float = hall_bounds[1].z - hall_bounds[0].z
	var planter_pos: Vector3
	var planter_rot: Vector3 = Vector3(0, 0, 0)

	if abs(dir.x) > 0:
		if abs(hall_bounds_length) < 1:
			return
		planter_pos = Vector3(
			last_room.center.x + (last_room.width / 2) * dir.x,
			_y,
			(hall_bounds[1].z + hall_bounds[0].z) / 2.0
		)
	else:
		if abs(hall_bounds_width) < 1:
			return
		planter_rot.y = PI / 2
		planter_pos = Vector3(
			(hall_bounds[1].x + hall_bounds[0].x) / 2.0,
			_y,
			last_room.center.z + (last_room.length / 2 + 1) * dir.z,
		)

	var planter: Node3D = _SMALL_PLANTER_SCENE.instantiate()
	planter.rotation = planter_rot
	planter.position = GridUtils.grid_to_world(planter_pos) + dir
	add_child(planter)


func _decorate_room_center(center: Vector3, width: int, length: int) -> void:
	if _try_place_large_decoration(center, width, length):
		return
	_place_benches_and_walls(center, width, length)


func _try_place_large_decoration(center: Vector3, width: int, length: int) -> bool:
	if width <= 3 or length <= 3:
		return false
	var bounds: Array = _room_to_bounds(center, width, length)
	var true_center: Vector3 = (bounds[0] + bounds[1]) / 2

	# Safety: verify the center cell is floor (not wall, hall, or empty)
	var center_grid := Vector3(round(true_center.x), _y, round(true_center.z))
	var cell_val: int = _raw_grid.get_cell_item(center_grid)
	if cell_val == -1:
		return false  # No floor here

	# 60% chance: mood-specific centerpiece, 40%: standard
	if _rng.randi_range(0, 99) >= 40:
		if _try_place_mood_centerpiece(true_center, width, length, bounds):
			return true

	# Standard decoration (pool, planter, skylight)
	var pool_weight: int = 2 if ExhibitMood.prefers_pool(_mood) else 1
	var planter_weight: int = 2 if ExhibitMood.prefers_planter(_mood) else 1
	var skylight_weight: int = 2 if _mood == ExhibitMood.Mood.ASTRO or _mood == ExhibitMood.Mood.NATURE else 1
	var empty_weight: int = 2
	var total: int = pool_weight + planter_weight + skylight_weight + empty_weight
	var r: int = _rng.randi_range(0, total - 1)

	if r < pool_weight:
		var pool: Node3D = _POOL_SCENE.instantiate()
		pool.position = GridUtils.grid_to_world(true_center)
		add_child(pool)
		return true
	elif r < pool_weight + planter_weight:
		var planter: Node3D = _PLANTER_SCENE.instantiate()
		planter.position = GridUtils.grid_to_world(true_center)
		planter.rotation.y = PI / 2 if length > width else 0.0
		add_child(planter)
		return true
	elif r < pool_weight + planter_weight + skylight_weight:
		var skylight: Node3D = _create_skylight()
		skylight.position = GridUtils.grid_to_world(true_center) + Vector3(0, 2.5, 0)
		add_child(skylight)
		return true
	return false


# ── Mood-specific centerpieces ──────────────────────────────────────────────
## All placements are bounds-checked and use world-space nodes (no grid writes)
func _try_place_mood_centerpiece(pos: Vector3, width: int, length: int, _bounds: Array) -> bool:
	if width < 4 or length < 4:
		return false

	match _mood:
		ExhibitMood.Mood.ART:        return _place_art_statue(pos)
		ExhibitMood.Mood.GEOGRAPHY:  return _place_globe(pos)
		ExhibitMood.Mood.SPORTS:     return _place_trophy(pos)
		ExhibitMood.Mood.FOOD:       return _place_dining_table(pos)
		ExhibitMood.Mood.POLITICS:   return _place_rostrum(pos)
		ExhibitMood.Mood.ECONOMY:    return _place_vault(pos)
		ExhibitMood.Mood.MYSTERY:    return _place_crystal_ball(pos)
		ExhibitMood.Mood.PHILOSOPHY: return _place_thinkers_chair(pos)
		ExhibitMood.Mood.HISTORY:    return _place_artifact(pos)
		ExhibitMood.Mood.SCIENCE:    return _place_hologram(pos)

	return false


func _place_art_statue(pos: Vector3) -> bool:
	var g := Node3D.new(); g.name = "ArtStatue"
	var ped := MeshInstance3D.new()
	var pb := BoxMesh.new(); pb.size = Vector3(0.8, 1.2, 0.8); ped.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.92, 0.90, 0.87); pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ped.material_override = pm; ped.position = Vector3(0, 0.6, 0); g.add_child(ped)
	var st := MeshInstance3D.new()
	var ss := SphereMesh.new(); ss.radius = 0.4; ss.height = 0.8; st.mesh = ss
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.75, 0.65, 0.5); sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	st.material_override = sm; st.position = Vector3(0, 1.6, 0); g.add_child(st)
	var sp := SpotLight3D.new()
	sp.light_energy = 2.0; sp.light_color = Color(1.0, 0.95, 0.85)
	sp.range = 4.0; sp.spot_angle = 30; sp.position = Vector3(0, 3.0, 0)
	sp.basis = Basis.looking_at(Vector3.DOWN); g.add_child(sp)
	g.position = GridUtils.grid_to_world(pos); add_child(g); return true

func _place_globe(pos: Vector3) -> bool:
	var g := Node3D.new(); g.name = "GlobeDisplay"
	var st := MeshInstance3D.new()
	var sc := CylinderMesh.new(); sc.top_radius = 0.1; sc.bottom_radius = 0.3; sc.height = 1.0
	st.mesh = sc
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.3, 0.2); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	st.material_override = m; st.position = Vector3(0, 0.5, 0); g.add_child(st)
	var gb := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = 0.5; s.height = 1.0; gb.mesh = s
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.5, 0.8); gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gb.material_override = gm; gb.position = Vector3(0, 1.5, 0); g.add_child(gb)
	var l := OmniLight3D.new()
	l.light_energy = 1.5; l.light_color = Color(0.8, 0.9, 1.0); l.omni_range = 4.0
	l.position = Vector3(0, 2.5, 0); g.add_child(l)
	g.position = GridUtils.grid_to_world(pos); add_child(g); return true

func _place_trophy(pos: Vector3) -> bool:
	var g := Node3D.new(); g.name = "TrophyDisplay"
	var b := MeshInstance3D.new()
	var bx := BoxMesh.new(); bx.size = Vector3(1.2, 0.6, 1.2); b.mesh = bx
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.25, 0.15); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.material_override = m; b.position = Vector3(0, 0.3, 0); g.add_child(b)
	var tr := MeshInstance3D.new()
	var cy := CylinderMesh.new(); cy.top_radius = 0.25; cy.bottom_radius = 0.15; cy.height = 0.8
	tr.mesh = cy
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(1.0, 0.85, 0.3); tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tr.material_override = tm; tr.position = Vector3(0, 1.0, 0); g.add_child(tr)
	var l := OmniLight3D.new()
	l.light_energy = 2.0; l.light_color = Color(1.0, 0.95, 0.7); l.omni_range = 4.0
	l.position = Vector3(0, 2.0, 0); g.add_child(l)
	g.position = GridUtils.grid_to_world(pos); add_child(g); return true

func _place_dining_table(pos: Vector3) -> bool:
	var g := Node3D.new(); g.name = "DiningTable"
	var t := MeshInstance3D.new()
	var tb := BoxMesh.new(); tb.size = Vector3(1.8, 0.1, 1.2); t.mesh = tb
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.4, 0.25); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t.material_override = m; t.position = Vector3(0, 0.9, 0); g.add_child(t)
	for dx in [-0.7, 0.7]:
		for dz in [-0.4, 0.4]:
			var lg := MeshInstance3D.new()
			var lb := BoxMesh.new(); lb.size = Vector3(0.1, 0.9, 0.1); lg.mesh = lb
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(0.4, 0.25, 0.15); lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lg.material_override = lm; lg.position = Vector3(dx, 0.45, dz); g.add_child(lg)
	var w := OmniLight3D.new()
	w.light_energy = 1.5; w.light_color = Color(1.0, 0.85, 0.6); w.omni_range = 5.0
	w.position = Vector3(0, 2.0, 0); g.add_child(w)
	g.position = GridUtils.grid_to_world(pos); add_child(g); return true

func _place_rostrum(pos: Vector3) -> bool:
	var g := Node3D.new(); g.name = "Rostrum"
	var p := MeshInstance3D.new()
	var pb := BoxMesh.new(); pb.size = Vector3(2.0, 0.4, 1.5); p.mesh = pb
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.35, 0.25); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = m; p.position = Vector3(0, 0.2, 0); g.add_child(p)
	var pd := MeshInstance3D.new()
	var pdb := BoxMesh.new(); pdb.size = Vector3(0.8, 1.2, 0.5); pd.mesh = pdb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.35, 0.25, 0.15); pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pd.material_override = pm; pd.position = Vector3(0, 1.0, -0.3); g.add_child(pd)
	var l := OmniLight3D.new()
	l.light_energy = 2.0; l.light_color = Color.WHITE; l.omni_range = 5.0
	l.position = Vector3(0, 2.5, 0); g.add_child(l)
	g.position = GridUtils.grid_to_world(pos); add_child(g); return true

func _place_vault(pos: Vector3) -> bool:
	var g := Node3D.new(); g.name = "VaultDisplay"
	var v := MeshInstance3D.new()
	var vb := BoxMesh.new(); vb.size = Vector3(1.5, 1.5, 1.5); v.mesh = vb
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.55, 0.5); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	v.material_override = m; v.position = Vector3(0, 0.75, 0); g.add_child(v)
	var gd := MeshInstance3D.new()
	var gc := CylinderMesh.new(); gc.top_radius = 0.3; gc.bottom_radius = 0.3; gc.height = 0.2
	gd.mesh = gc
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(1.0, 0.85, 0.2); gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gd.material_override = gm; gd.position = Vector3(0, 1.6, 0); g.add_child(gd)
	var l := OmniLight3D.new()
	l.light_energy = 2.5; l.light_color = Color(1.0, 0.95, 0.7); l.omni_range = 4.0
	l.position = Vector3(0, 2.5, 0); g.add_child(l)
	g.position = GridUtils.grid_to_world(pos); add_child(g); return true

func _place_crystal_ball(pos: Vector3) -> bool:
	var g := Node3D.new(); g.name = "CrystalBall"
	var st := MeshInstance3D.new()
	var sc := CylinderMesh.new(); sc.top_radius = 0.15; sc.bottom_radius = 0.25; sc.height = 0.6
	st.mesh = sc
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.2, 0.35); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	st.material_override = m; st.position = Vector3(0, 0.3, 0); g.add_child(st)
	var b := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = 0.35; s.height = 0.7; b.mesh = s
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.7, 0.6, 0.8)
	bm.emission_enabled = true; bm.emission = Color(0.5, 0.3, 0.7, 0.5)
	bm.emission_energy_multiplier = 1.5; bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.material_override = bm; b.position = Vector3(0, 1.0, 0); g.add_child(b)
	var gl := OmniLight3D.new()
	gl.light_energy = 1.5; gl.light_color = Color(0.6, 0.4, 0.8); gl.omni_range = 4.0
	gl.position = Vector3(0, 1.0, 0); g.add_child(gl)
	g.position = GridUtils.grid_to_world(pos); add_child(g); return true

func _place_thinkers_chair(pos: Vector3) -> bool:
	var g := Node3D.new(); g.name = "ThinkersChair"
	var s := MeshInstance3D.new()
	var sb := BoxMesh.new(); sb.size = Vector3(0.8, 0.1, 0.8); s.mesh = sb
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.3, 0.2); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.material_override = m; s.position = Vector3(0, 0.6, 0); g.add_child(s)
	var bk := MeshInstance3D.new()
	var bb := BoxMesh.new(); bb.size = Vector3(0.8, 1.0, 0.1); bk.mesh = bb
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.45, 0.28, 0.18); bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bk.material_override = bm; bk.position = Vector3(0, 1.1, -0.35); g.add_child(bk)
	var w := OmniLight3D.new()
	w.light_energy = 1.0; w.light_color = Color(1.0, 0.9, 0.7); w.omni_range = 4.0
	w.position = Vector3(0, 2.0, 0); g.add_child(w)
	g.position = GridUtils.grid_to_world(pos); add_child(g); return true

func _place_artifact(pos: Vector3) -> bool:
	var g := Node3D.new(); g.name = "ArtifactDisplay"
	var p := MeshInstance3D.new()
	var pc := CylinderMesh.new(); pc.top_radius = 0.5; pc.bottom_radius = 0.5; pc.height = 1.0
	p.mesh = pc
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.8, 0.7); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = m; p.position = Vector3(0, 0.5, 0); g.add_child(p)
	var r := MeshInstance3D.new()
	var tr := TorusMesh.new()
	tr.inner_radius = 0.15; tr.outer_radius = 0.25; tr.rings = 16; tr.sides = 8
	r.mesh = tr
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.9, 0.75, 0.4)
	rm.emission_enabled = true; rm.emission = Color(0.8, 0.6, 0.3, 0.6)
	rm.emission_energy_multiplier = 1.0; rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r.material_override = rm; r.position = Vector3(0, 1.2, 0); r.rotation.x = PI / 4
	g.add_child(r)
	var l := OmniLight3D.new()
	l.light_energy = 1.5; l.light_color = Color(1.0, 0.9, 0.7); l.omni_range = 4.0
	l.position = Vector3(0, 2.0, 0); g.add_child(l)
	g.position = GridUtils.grid_to_world(pos); add_child(g); return true

func _place_hologram(pos: Vector3) -> bool:
	var g := Node3D.new(); g.name = "TechDisplay"
	var b := MeshInstance3D.new()
	var bb := BoxMesh.new(); bb.size = Vector3(1.0, 0.2, 1.0); b.mesh = bb
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.35, 0.4); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.material_override = m; b.position = Vector3(0, 0.1, 0); g.add_child(b)
	var h := MeshInstance3D.new()
	var hs := SphereMesh.new(); hs.radius = 0.4; hs.height = 0.8; h.mesh = hs
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.4, 0.8, 1.0)
	hm.emission_enabled = true; hm.emission = Color(0.3, 0.7, 1.0, 0.4)
	hm.emission_energy_multiplier = 2.0; hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	h.material_override = hm; h.position = Vector3(0, 1.2, 0); g.add_child(h)
	var l := OmniLight3D.new()
	l.light_energy = 2.0; l.light_color = Color(0.6, 0.8, 1.0); l.omni_range = 5.0
	l.position = Vector3(0, 2.0, 0); g.add_child(l)
	g.position = GridUtils.grid_to_world(pos); add_child(g); return true


## Creates a skylight node procedurally (avoids preload issues)
func _create_skylight() -> Node3D:
	var skylight := Node3D.new()
	skylight.name = "Skylight"
	
	# Glowing panel
	var mesh := MeshInstance3D.new()
	mesh.name = "SkylightOpening"
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(3, 0.5, 2)
	mesh.mesh = box_mesh
	
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission = Color(1.0, 0.95, 0.9, 3.0)
	material.emission_energy_multiplier = 3.0
	mesh.set_surface_override_material(0, material)
	skylight.add_child(mesh)
	
	# Local fill light
	var light := OmniLight3D.new()
	light.name = "SkylightLight"
	light.light_energy = 1.0
	light.light_color = Color(1.0, 0.98, 0.9)
	light.light_indirect_energy = 0.5
	light.omni_range = 8.0
	light.shadow_enabled = false
	light.position = Vector3(0, 2.0, 0)
	skylight.add_child(light)
	
	return skylight


func _place_benches_and_walls(center: Vector3, width: int, length: int) -> void:
	var bench_area_bounds: Variant = null
	var bench_area_ori: int = 0

	if width > length and width > 2:
		bench_area_bounds = _room_to_bounds(center, width - 2, 1)
	elif length > width and length > 2:
		bench_area_ori = GridUtils.vec_to_orientation(_grid, Vector3(1, 0, 0))
		bench_area_bounds = _room_to_bounds(center, 1, length - 2)
	if not bench_area_bounds:
		return

	var c1: Vector3 = bench_area_bounds[0]
	var c2: Vector3 = bench_area_bounds[1]
	var y: int = int(center.y)
	for x: int in range(int(c1.x), int(c2.x) + 1):
		for z: int in range(int(c1.z), int(c2.z) + 1):
			var pos: Vector3 = Vector3(x, y, z)
			if _raw_grid.get_cell_item(pos) != -1:
				continue

			var valid_bench: bool = GridUtils.cell_neighbors(_raw_grid, pos, INTERNAL_HALL).size() == 0 and\
					GridUtils.cell_neighbors(_raw_grid, pos, HALL_STAIRS_UP).size() == 0 and\
					GridUtils.cell_neighbors(_raw_grid, pos, HALL_STAIRS_DOWN).size() == 0
			if valid_bench:
				var b: Node3D = _BENCH_SCENE.instantiate()
				b.position = GridUtils.grid_to_world(pos)
				if bench_area_ori != 0:
					b.rotation.y = PI / 2
				add_child(b)
				_grid.set_cell_item(pos, BENCH, bench_area_ori)


func _decorate_wall_tile(pos: Vector3) -> void:
	# we use the raw grid bc we want to ignore reservations here
	if _raw_grid.get_cell_item(pos) == FREE_WALL:
		return

	var wall_neighbors: Array = GridUtils.cell_neighbors(_grid, pos, WALL)
	for wall: Vector3 in wall_neighbors:
		var slot: Vector3 = (wall + pos) / 2
		var hall_dir: Vector3 = wall - pos
		var valid_halls: Array = Hall.valid_hall_types(_grid, wall, hall_dir)

		# put an exit everywhere it fits
		if valid_halls.size() > 0 and exits.size() < _exit_limit:
			var new_hall: Hall = _HALL_SCENE.instantiate()
			var hall_type: Array = valid_halls[_rng.randi() % valid_halls.size()]
			add_child(new_hall)
			new_hall.init(
				_grid,
				title,
				title,
				wall,
				hall_dir,
				hall_type
			)

			exits.append(new_hall)
			exit_added.emit(new_hall)
		# put exhibit items everywhere else
		else:
			add_item_slot([slot, hall_dir])
			# Mood-specific wall decorations: occasional sconces/banners/windows
			_try_place_wall_decoration(wall, slot, hall_dir)


## Place decorative wall elements (sconces, banners, plaques) based on mood.
## These are world-space nodes that don't modify the grid — completely safe.
func _try_place_wall_decoration(wall_pos: Vector3, slot_pos: Vector3, dir: Vector3) -> void:
	# Only place decorations occasionally (20% chance per wall tile)
	if _rng.randi_range(0, 99) >= 20:
		return

	# Don't place on hallway walls
	var cell_val: int = _raw_grid.get_cell_item(wall_pos)
	if cell_val == INTERNAL_HALL or cell_val == INTERNAL_HALL_TURN:
		return

	# Safety: verify the slot position is reasonable
	var world_pos := GridUtils.grid_to_world(slot_pos) - dir * 0.15

	pass


func _room_to_bounds(center: Vector3, width: int, length: int) -> Array:
	return [
		Vector3(center.x - width / 2, center.y, center.z - length / 2),
		Vector3(center.x + width / 2 - ((width + 1) % 2), center.y, center.z + length / 2 + ((length + 1) % 2))
	]


func _carve_room(corner1: Vector3, corner2: Vector3, y: int, height: int = 2) -> void:
	var step_start = Time.get_ticks_msec()
	var lx: int = int(corner1.x)
	var gx: int = int(corner2.x)
	var lz: int = int(corner1.z)
	var gz: int = int(corner2.z)

	_clear_scenery_in_area(Vector3(lx, 0, lz), Vector3(gx, 0, gz))

	for x: int in range(lx - 1, gx + 2):
		for z: int in range(lz - 1, gz + 2):
			var c: int = _grid.get_cell_item(Vector3(x, y, z))
			if x < lx or z < lz or x > gx or z > gz:
				if c == HALL_STAIRS_UP or c == HALL_STAIRS_DOWN or c == HALL_STAIRS_TURN:
					continue
				elif c == INTERNAL_HALL:
					_grid.set_cell_item(Vector3(x, y + 1, z), WALL, 0)
				elif _grid.get_cell_item(Vector3(x, y - 1, z)) == -1:
					_grid.set_cell_item(Vector3(x, y, z), WALL, 0)
					_grid.set_cell_item(Vector3(x, y + 1, z), WALL, 0)
					for i: int in range(2, height + 1):
						_grid.set_cell_item(Vector3(x, y + i, z), -1, 0)
			else:
				if c == WALL:
					for i: int in range(height):
						_grid.set_cell_item(Vector3(x, y + i, z), -1, 0)

				_grid.set_cell_item(Vector3(x, y + height, z), CEILING, 0)
				_grid.set_cell_item(Vector3(x, y - 1, z), _floor, 0)

	Log.info("TiledExhibitGenerator", "  _carve_room(): %dms (height: %d)" % [
		Time.get_ticks_msec() - step_start, height])


func _overlaps_room(corner1: Vector3, corner2: Vector3, y: int) -> bool:
	for x: int in range(int(corner1.x) - 1, int(corner2.x) + 2):
		for z: int in range(int(corner1.z) - 1, int(corner2.z) + 2):
			if not GridUtils.safe_overwrite(_grid, Vector3(x, y, z)):
				return true
	return false


func has_secret_room() -> bool:
	return _secret_room_count > 0


func get_secret_item_slots() -> Array:
	return _secret_item_slots


func _try_place_secret_room(room: Dictionary) -> void:
	if _secret_room_count > 0:
		return  # Only one secret room per exhibit
	if not SecretRoomContent.should_have_secret(title, _room_count):
		return

	var center: Vector3 = room.center
	var width: int = room.width
	var length: int = room.length
	if width < 3 and length < 3:
		return  # Room too small for a secret passage

	var bounds: Array = _room_to_bounds(center, width, length)
	var c1: Vector3 = bounds[0]
	var c2: Vector3 = bounds[1]
	var y: int = int(center.y)

	# Try each wall of the room for a secret passage
	var wall_candidates: Array = []

	# North wall (z = c1.z - 1)
	for x: int in range(int(c1.x) + 1, int(c2.x)):
		var wall_pos: Vector3 = Vector3(x, y, int(c1.z) - 1)
		if _raw_grid.get_cell_item(wall_pos) == WALL:
			wall_candidates.append({"pos": wall_pos, "dir": Vector3(0, 0, -1), "perp": Vector3(1, 0, 0)})
	# South wall
	for x: int in range(int(c1.x) + 1, int(c2.x)):
		var wall_pos: Vector3 = Vector3(x, y, int(c2.z) + 1)
		if _raw_grid.get_cell_item(wall_pos) == WALL:
			wall_candidates.append({"pos": wall_pos, "dir": Vector3(0, 0, 1), "perp": Vector3(1, 0, 0)})
	# West wall
	for z: int in range(int(c1.z) + 1, int(c2.z)):
		var wall_pos: Vector3 = Vector3(int(c1.x) - 1, y, z)
		if _raw_grid.get_cell_item(wall_pos) == WALL:
			wall_candidates.append({"pos": wall_pos, "dir": Vector3(-1, 0, 0), "perp": Vector3(0, 0, 1)})
	# East wall
	for z: int in range(int(c1.z) + 1, int(c2.z)):
		var wall_pos: Vector3 = Vector3(int(c2.x) + 1, y, z)
		if _raw_grid.get_cell_item(wall_pos) == WALL:
			wall_candidates.append({"pos": wall_pos, "dir": Vector3(1, 0, 0), "perp": Vector3(0, 0, 1)})

	if wall_candidates.is_empty():
		return

	CollectionUtils.shuffle(_rng, wall_candidates)

	for candidate: Dictionary in wall_candidates:
		var wall_pos: Vector3 = candidate.pos
		var dir: Vector3 = candidate.dir
		var perp: Vector3 = candidate.perp

		# Secret room: 2x2 behind the wall
		var secret_c1: Vector3 = wall_pos + dir - perp
		var secret_c2: Vector3 = wall_pos + dir * 2 + perp

		# Check overlap
		if _overlaps_room(secret_c1, secret_c2, y):
			continue

		# Carve the secret room
		_carve_room(secret_c1, secret_c2, y)

		# Clear the wall cell to create passage
		_grid.set_cell_item(wall_pos, -1, 0)
		_grid.set_cell_item(Vector3(wall_pos.x, wall_pos.y + 1, wall_pos.z), -1, 0)
		_grid.set_cell_item(Vector3(wall_pos.x, wall_pos.y + 2, wall_pos.z), CEILING, 0)
		_grid.set_cell_item(Vector3(wall_pos.x, wall_pos.y - 1, wall_pos.z), _floor, 0)

		# Place the SecretWall interactable
		var secret_wall: SecretWall = SecretWall.new()
		secret_wall.position = GridUtils.grid_to_world(wall_pos)
		secret_wall.rotation.y = GridUtils.vec_to_rot(dir)
		secret_wall.init(perp)
		add_child(secret_wall)

		# Add item slots inside secret room
		var slot_dir: Vector3 = -dir
		for sx: int in range(int(secret_c1.x), int(secret_c2.x) + 1):
			for sz: int in range(int(secret_c1.z), int(secret_c2.z) + 1):
				var slot_pos: Vector3 = Vector3(sx, y, sz)
				if _raw_grid.get_cell_item(slot_pos) != WALL:
					# Add slots facing walls
					for check_dir: Vector3 in DIRECTIONS:
						var neighbor: Vector3 = slot_pos + check_dir
						if _raw_grid.get_cell_item(neighbor) == WALL:
							var s: Array = [(slot_pos + neighbor) / 2.0, check_dir]
							_secret_item_slots.append(s)

		_secret_room_count += 1
		break


func get_rooms_for_npcs() -> Array:
	## Returns room data for NPC spawning.
	var result: Array = []
	for room_key: Vector3i in _room_list:
		var room: Dictionary = _room_list[room_key]
		var bounds: Array = _room_to_bounds(room.center, room.width, room.length)
		result.append({
			"center": room.center,
			"bounds": bounds
		})
	return result
