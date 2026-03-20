extends Node3D
class_name HallDoor

const OPEN_POS_Y: float = 6.5
const CLOSED_POS_Y: float = 2.0
const ANIMATION_DURATION: float = 0.25

@onready var _door: Node3D = $Door
var _locked: bool = false
var _open_pos: Vector3 = Vector3(0, OPEN_POS_Y, 0)
var _closed_pos: Vector3 = Vector3(0, CLOSED_POS_Y, 0)

func lock() -> void:
	_locked = true
	close()

func unlock() -> void:
	_locked = false

func is_locked() -> bool:
	return _locked

func open() -> void:
	if not _locked:
		set_open(true)

func close() -> void:
	set_open(false)

func set_open(open: bool = true, instant: bool = false) -> void:
	if is_visible() and not instant:
		var tween: Tween = get_tree().create_tween()
		tween.tween_property(
			_door,
			"position",
			_open_pos if open else _closed_pos,
			ANIMATION_DURATION
		)
		tween.set_trans(Tween.TRANS_LINEAR)
		tween.set_ease(Tween.EASE_IN_OUT)
		if open:
			$OpenSound.play()
	else:
		_door.position = _open_pos if open else _closed_pos

@onready var label_pivot: Node3D = $Door/LabelPivot
@onready var top_label: Label3D = $Door/LabelPivot/Label1
@onready var bottom_label: Label3D = $Door/LabelPivot/Label2
var _label_tween: Tween = null

func set_message(msg: String, instant: bool = false) -> void:
	if _label_tween:
		_label_tween.kill()

	bottom_label.text = msg

	if is_visible() and not instant:
		_label_tween = get_tree().create_tween()
		_label_tween.tween_property(
			label_pivot,
			"rotation:z",
			label_pivot.rotation.z + PI,
			ANIMATION_DURATION
		)
	else:
		_label_tween = null
		label_pivot.rotation.z += PI

	var tmp: Label3D = top_label
	top_label = bottom_label
	bottom_label = tmp

func _ready() -> void:
	ThemeManager.dark_mode_changed.connect(_on_dark_mode_changed)
	_on_dark_mode_changed(ThemeManager.is_dark_mode)

func _on_dark_mode_changed(is_dark: bool) -> void:
	# "Illuminate" the signs in dark mode by switching from black to a bright cyan
	var color = Color(0.4, 0.9, 1.0) if is_dark else Color(0, 0, 0) # Slightly brighter
	if top_label:
		top_label.modulate = color
		top_label.outline_modulate = Color(0, 0.2, 0.4, 0.5) if is_dark else Color(1, 1, 1, 0)
	if bottom_label:
		bottom_label.modulate = color
		bottom_label.outline_modulate = Color(0, 0.2, 0.4, 0.5) if is_dark else Color(1, 1, 1, 0)
