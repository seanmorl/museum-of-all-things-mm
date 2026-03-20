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
	# ── ARCHIVED v0.5.0 - Powerups replaced with Environmental Events
	# Apply perfect knowledge visibility if powerup is active
	# _apply_perfect_knowledge()
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

# ── ARCHIVED v0.5.0 - Powerups replaced with Environmental Events
# func _apply_perfect_knowledge() -> void:
# 	# Check if any player has perfect knowledge powerup
# 	var powerup_manager = get_node_or_null("/root/Main/PowerupManager")
# 	if not powerup_manager:
# 		return
# 	var local_player_id = NetworkManager.get_unique_id()
# 	var has_pk = powerup_manager.has_powerup(local_player_id, PowerupManager.PowerupType.PERFECT_KNOWLEDGE)
# 	if entry_label:
# 		entry_label.visible = has_pk
# 	if exit_label:
# 		exit_label.visible = has_pk
# 	if from_sign:
# 		var label = from_sign.get_node_or_null("Label3D")
# 		if label:
# 			label.visible = has_pk
# 	if to_sign:
# 		var label = to_sign.get_node_or_null("Label3D")
# 		if label:
# 			label.visible = has_pk

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
	if entry_door and entry_door.has_method("set_locked"): # Wait, I named it lock/unlock
		pass
	
	# Let's use the new methods
	if not v:
		if entry_door.has_method("lock"): entry_door.lock()
		if exit_door.has_method("lock"): exit_door.lock()
	else:
		if entry_door.has_method("unlock"): entry_door.unlock()
		if exit_door.has_method("unlock"): exit_door.unlock()

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
		valid_halls.append([true, UP])
		valid_halls.append([true, DOWN])

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
