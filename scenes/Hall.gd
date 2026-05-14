extends Node3D
class_name Hall
## A hallway connecting two exhibit areas with entry/exit doors.

signal on_player_toward_exit
signal on_player_toward_entry

# Use GridConstants for cell types
const WALL: int = GridConstants.WALL
const INTERNAL_HALL: int = GridConstants.INTERNAL_HALL
const INTERNAL_HALL_TURN: int = GridConstants.INTERNAL_HALL_TURN
const HALL_STAIRS_UP: int = GridConstants.HALL_STAIRS_UP
const HALL_STAIRS_DOWN: int = GridConstants.HALL_STAIRS_DOWN
const HALL_STAIRS_TURN: int = GridConstants.HALL_STAIRS_TURN

const UP: int = GridConstants.LEVEL_UP
const FLAT: int = GridConstants.LEVEL_FLAT
const DOWN: int = GridConstants.LEVEL_DOWN

const _GRID_WRAPPER: PackedScene = preload("res://scenes/util/GridWrapper.tscn")

@onready var loader: Area3D = $LoaderTrigger
@onready var entry_door: Node3D = $EntryDoor
@onready var exit_door: Node3D = $ExitDoor
@onready var entry_marker: MeshInstance3D = $EntryMarker
@onready var exit_marker: MeshInstance3D = $ExitMarker
@onready var entry_label: Label3D = $EntryLabel
@onready var exit_label: Label3D = $ExitLabel
@onready var _detector: Area3D = $HallDirectionDetector
@onready var from_sign: Node3D = $FromSign
@onready var to_sign: Node3D = $ToSign
@onready var light: OmniLight3D = $HallLight

var _disco_hue: float = randf()

func _ready() -> void:
	ThemeManager.disco_mode_changed.connect(_on_disco_mode_changed)
	ThemeManager.reading_font_changed.connect(_on_font_changed)
	_on_dark_mode_changed(ThemeManager.is_dark_mode)
	_on_font_changed(ThemeManager.get_reading_font())
	# Ensure markers are invisible (they're for minimap only)
	_hide_markers()

func _process(delta: float) -> void:
	if ThemeManager.disco_mode and light:
		_disco_hue = fmod(_disco_hue + delta * 0.8, 1.0)
		light.light_color = Color.from_hsv(_disco_hue, 0.9, 1.0)
		light.light_energy = 1.5 # Pump it up

func _on_disco_mode_changed(enabled: bool) -> void:
	if not enabled:
		# Reset once when disco ends
		_on_dark_mode_changed(ThemeManager.is_dark_mode)

func _on_dark_mode_changed(is_dark: bool) -> void:
	# Dim the hallway light in dark mode for atmosphere
	if light:
		light.light_energy = 0.05 if is_dark else 0.4
		light.light_color = Color.WHITE

func _on_font_changed(font: Font) -> void:
	if entry_label:
		entry_label.font = font
		entry_label.hide()
	if exit_label:
		exit_label.font = font
		exit_label.hide()


func _hide_markers() -> void:
	# Entry/Exit markers are for minimap rendering only - keep them invisible in 3D world
	if entry_marker:
		entry_marker.visible = false
	if exit_marker:
		exit_marker.visible = false
	# Hall light should also stay invisible (only provides illumination)
	if light:
		light.visible = false

var _grid: Node = null
var hall_type: Array = [true, FLAT]
var floor_type: int = 0
var player_direction: String = ""

var from_pos: Vector3 = Vector3.ZERO
var from_dir: Vector3 = Vector3.ZERO
var to_pos: Vector3 = Vector3.ZERO
var to_dir: Vector3 = Vector3.ZERO
var linked_hall: Hall = null
var passable: bool = true

func set_passable(v: bool) -> void:
	passable = v

	# Lock/unlock doors using the door's lock/unlock methods
	if not v:
		if entry_door and entry_door.has_method("lock"): entry_door.lock()
		if exit_door and exit_door.has_method("lock"): exit_door.lock()
	else:
		if entry_door and entry_door.has_method("unlock"): entry_door.unlock()
		if exit_door and exit_door.has_method("unlock"): exit_door.unlock()

var player_in_hall: bool:
	get:
		return _detector.player != null
	set(_value):
		pass

var from_title: String:
	get:
		return from_sign.text
	set(v):
		from_sign.text = v
		if is_instance_valid(entry_label):
			entry_label.text = v

var to_title: String:
	get:
		return to_sign.text
	set(v):
		to_sign.text = v
		if is_instance_valid(exit_label):
			exit_label.text = v


static func valid_hall_types(grid: Node, hall_start: Vector3, hall_dir: Vector3) -> Array:
	var hall_corner: Vector3 = hall_start + hall_dir

	var hall_dir_right: Vector3 = hall_dir.rotated(Vector3.UP, 3 * PI / 2)
	var hall_exit_right: Vector3 = hall_corner + hall_dir_right
	var past_hall_exit_right: Vector3 = hall_corner + 2 * hall_dir_right

	var corner_empty_neighbors: Array = GridUtils.cell_neighbors(grid, hall_corner - Vector3.UP, -1)

	if (
		not GridUtils.safe_overwrite(grid, hall_corner) or
		corner_empty_neighbors.size() != 4
	):
		return []

	var valid_halls: Array = []

	# DISABLED: UP/DOWN stairs are not functional — the exhibit generator
	# operates on a single Y level and there is no multi-floor connectivity.
	# Stairs would lead to void space above/below the generated rooms.
	# Re-enable these if a multi-level generation system is added.
	if (
		not (
			grid.get_cell_item(past_hall_exit_right - Vector3.UP) != -1 and
			grid.get_cell_item(past_hall_exit_right) == -1
		) and
		not (
			grid.get_cell_item(past_hall_exit_right - Vector3.UP) == 1 and
			grid.get_cell_item(past_hall_exit_right) == 1
		) and
		GridUtils.safe_overwrite(grid, hall_exit_right)
	):
		valid_halls.append([true, FLAT])

	return valid_halls


func init(grid: Variant, p_from_title: String, p_to_title: String, hall_start: Vector3, hall_dir: Vector3, _hall_type: Array = [true, FLAT]) -> void:
	floor_type = ExhibitStyle.gen_floor(p_from_title)
	position = GridUtils.grid_to_world(hall_start)
	loader.monitoring = true

	if grid is GridMap:
		_grid = _GRID_WRAPPER.instantiate()
		_grid.init(grid)
		add_child(_grid)
	else:
		_grid = grid

	hall_type = _hall_type
	_create_curve_hall(hall_start, hall_dir, hall_type[0], hall_type[1])

	from_dir = hall_dir
	from_pos = hall_start

	from_sign.position = GridUtils.grid_to_world(to_pos + to_dir * 0.65) - position
	from_sign.position += to_dir.rotated(Vector3.UP, PI / 2).normalized() * 1.5
	from_sign.rotation.y = GridUtils.vec_to_rot(to_dir) + PI
	from_sign.text = p_from_title
	from_sign.visible = false

	to_sign.position = GridUtils.grid_to_world(hall_start - hall_dir * 0.60) - position
	to_sign.position -= hall_dir.rotated(Vector3.UP, PI / 2).normalized() * 1.5
	to_sign.rotation.y = GridUtils.vec_to_rot(hall_dir)
	to_sign.text = p_to_title

	entry_door.position = GridUtils.grid_to_world(from_pos) - 1.9 * from_dir - position
	entry_door.rotation.y = GridUtils.vec_to_rot(from_dir) + PI
	exit_door.position = GridUtils.grid_to_world(to_pos) + 1.9 * to_dir - position
	exit_door.rotation.y = GridUtils.vec_to_rot(to_dir)
	entry_door.set_open(true, true)
	exit_door.set_open(false, true)
	
	entry_marker.position = entry_door.position
	entry_marker.position.y = 0.5
	exit_marker.position = exit_door.position
	exit_marker.position.y = 0.5
	
	entry_label.position = entry_marker.position + Vector3(0, 1.5, 0)
	entry_label.text = p_from_title
	exit_label.position = exit_marker.position + Vector3(0, 1.5, 0)
	exit_label.text = p_to_title

	var center_pos: Vector3 = GridUtils.grid_to_world((from_pos + to_pos) / 2) + Vector3(0, 4, 0) - position

	_detector.position = center_pos
	_detector.monitoring = true
	_detector.direction_changed.connect(_on_direction_changed)
	_detector.init(GridUtils.grid_to_world(from_pos), GridUtils.grid_to_world(to_pos))

	loader.position = center_pos

	ExhibitFetcher.wikitext_failed.connect(_on_fetch_failed)

	# Add mood-based hallway decorations (columns, arches) — purely visual
	_try_add_hallway_decor(hall_start, hall_dir)


func _create_curve_hall(hall_start: Vector3, hall_dir: Vector3, is_right: bool = true, level: int = FLAT) -> void:
	var ori: int = GridUtils.vec_to_orientation(_grid, hall_dir)
	var ori_turn: int = GridUtils.vec_to_orientation(_grid, hall_dir.rotated(Vector3.UP, 3 * PI / 2))
	var corner_ori: int = ori if is_right else ori_turn
	var hall_corner: Vector3 = hall_start + hall_dir

	if level == FLAT:
		_grid.set_cell_item(hall_start, INTERNAL_HALL, ori)
		_grid.set_cell_item(hall_start - Vector3.UP, floor_type, 0)
		_grid.set_cell_item(hall_start + Vector3.UP, WALL, 0)
		_grid.set_cell_item(hall_corner, INTERNAL_HALL_TURN, corner_ori)
		_grid.set_cell_item(hall_corner - Vector3.UP, floor_type, 0)
		_grid.set_cell_item(hall_corner + Vector3.UP, WALL, 0)
		light.global_position = GridUtils.grid_to_world(hall_corner) + Vector3.UP * 4
		light.rotation_degrees = Vector3(180, 0, 0)
	elif level == UP:
		_grid.set_cell_item(hall_start, HALL_STAIRS_UP, ori)
		if _grid.get_cell_item(hall_start + Vector3.UP) != -1:
			_grid.set_cell_item(hall_start + Vector3.UP, -1, ori)
		if _grid.get_cell_item(hall_corner + Vector3.UP) != -1:
			_grid.set_cell_item(hall_corner + Vector3.UP, -1, ori)
		_grid.set_cell_item(hall_corner, HALL_STAIRS_TURN, corner_ori)
		light.global_position = GridUtils.grid_to_world(hall_corner) + Vector3.UP * 8
		light.rotation_degrees = Vector3(180, 0, 0)
	elif level == DOWN:
		_grid.set_cell_item(hall_start, HALL_STAIRS_DOWN, ori)
		if _grid.get_cell_item(hall_start + Vector3.UP) != -1:
			_grid.set_cell_item(hall_start + Vector3.UP, -1, ori)
		if _grid.get_cell_item(hall_corner) != -1:
			_grid.set_cell_item(hall_corner, -1, ori)
		_grid.set_cell_item(hall_corner - Vector3.UP, HALL_STAIRS_TURN, corner_ori)
		light.global_position = GridUtils.grid_to_world(hall_corner) + Vector3.UP * 4
		light.rotation_degrees = Vector3(180, 0, 0)

	var exit_hall_dir: Vector3 = hall_dir.rotated(Vector3.UP, (3 if is_right else 1) * PI / 2)
	var exit_hall: Vector3 = hall_corner + exit_hall_dir
	var exit_ori: int = GridUtils.vec_to_orientation(_grid, exit_hall_dir)
	var exit_ori_neg: int = GridUtils.vec_to_orientation(_grid, -exit_hall_dir)

	to_dir = exit_hall_dir

	if level == FLAT:
		_grid.set_cell_item(exit_hall, INTERNAL_HALL, exit_ori)
		_grid.set_cell_item(exit_hall - Vector3.UP, floor_type, 0)
		_grid.set_cell_item(exit_hall + Vector3.UP, WALL, 0)
		to_dir = exit_hall_dir
		to_pos = exit_hall
	elif level == UP:
		_grid.set_cell_item(exit_hall + Vector3.UP, HALL_STAIRS_DOWN, exit_ori_neg)
		if _grid.get_cell_item(exit_hall + 2 * Vector3.UP) != -1:
			_grid.set_cell_item(exit_hall + 2 * Vector3.UP, -1, 0)
		if _grid.get_cell_item(exit_hall) != -1:
			_grid.set_cell_item(exit_hall, -1, 0)
		if _grid.get_cell_item(exit_hall - Vector3.UP) != -1:
			_grid.set_cell_item(exit_hall - Vector3.UP, -1, 0)
		to_pos = exit_hall + Vector3.UP
	elif level == DOWN:
		_grid.set_cell_item(exit_hall - Vector3.UP, HALL_STAIRS_UP, exit_ori_neg)
		if _grid.get_cell_item(exit_hall) != -1:
			_grid.set_cell_item(exit_hall, -1, 0)
		if _grid.get_cell_item(exit_hall + Vector3.UP) != -1:
			_grid.set_cell_item(exit_hall + Vector3.UP, -1, 0)
		to_pos = exit_hall - Vector3.UP


func _exit_tree() -> void:
	# Disconnect signals to prevent lambda capture errors
	if is_instance_valid(self) and ExhibitFetcher.wikitext_failed.is_connected(_on_fetch_failed):
		ExhibitFetcher.wikitext_failed.disconnect(_on_fetch_failed)
	
	if is_instance_valid(_detector) and _detector.direction_changed.is_connected(_on_direction_changed):
		_detector.direction_changed.disconnect(_on_direction_changed)
	
	# Clean up ThemeManager signals
	if ThemeManager.disco_mode_changed.is_connected(_on_disco_mode_changed):
		ThemeManager.disco_mode_changed.disconnect(_on_disco_mode_changed)
	if ThemeManager.reading_font_changed.is_connected(_on_font_changed):
		ThemeManager.reading_font_changed.disconnect(_on_font_changed)


func _on_fetch_failed(titles: Array, message: String) -> void:
	for title: String in titles:
		if title == to_title:
			exit_door.set_message("Error Loading Exhibit: " + message)


func _on_direction_changed(direction: String) -> void:
	if not is_inside_tree():
		return
	player_direction = direction
	if direction == "exit":
		on_player_toward_exit.emit()
	else:
		on_player_toward_entry.emit()


## Add decorative columns to hallways based on exhibit mood.
## These are purely visual — they don't modify the grid or affect collision.
func _try_add_hallway_decor(_hall_start: Vector3, _hall_dir: Vector3) -> void:
	# Only 30% of hallways get decorative columns
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(to_title + str(to_pos))
	if rng.randi_range(0, 99) >= 30:
		return

	# Determine if this hallway qualifies based on mood
	var decor_mood: int = ExhibitMood.Mood.DEFAULT
	var main_node := get_tree().current_scene
	if main_node and main_node.has_node("Museum"):
		var museum := main_node.get_node("Museum")
		if museum.has_method("_get_exhibit_mood"):
			decor_mood = museum._get_exhibit_mood(to_title)

	# Only grand moods get columns
	var column_color := Color.WHITE
	var column_height := 3.5
	match decor_mood:
		ExhibitMood.Mood.HISTORY:
			column_color = Color(0.92, 0.88, 0.82)  # Marble
		ExhibitMood.Mood.ART:
			column_color = Color(0.95, 0.93, 0.9)   # White gallery
		ExhibitMood.Mood.POLITICS:
			column_color = Color(0.85, 0.82, 0.85)  # Granite
		ExhibitMood.Mood.ECONOMY:
			column_color = Color(0.9, 0.87, 0.75)   # Sandstone
		_:
			return  # Other moods: no columns

	# Place columns along the hallway center
	var hall_center := GridUtils.grid_to_world((from_pos + to_pos) / 2.0)
	var hall_vec := to_pos - from_pos
	var hall_len := hall_vec.length()
	if hall_len < 3.0:
		return  # Too short for columns

	var perp_dir := Vector3(-hall_vec.z, 0, hall_vec.x).normalized()

	# Two columns flanking the hallway
	for side_idx: int in range(2):
		var side: float = -1.0 if side_idx == 0 else 1.0
		var col := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.15
		cyl.bottom_radius = 0.2
		cyl.height = column_height
		col.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = column_color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		col.material_override = mat

		# Position column at hallway center, offset perpendicular
		var offset := perp_dir * side * 1.5
		col.position = offset + Vector3(0, column_height / 2.0 - 0.5, 0)
		add_child(col)

		# Column capital
		var cap := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(0.5, 0.15, 0.5)
		cap.mesh = cbox
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = column_color
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cap.material_override = cmat
		cap.position = offset + Vector3(0, column_height - 0.5, 0)
		add_child(cap)
