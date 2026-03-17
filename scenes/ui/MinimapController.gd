extends Control
## MinimapController — manages three minimap styles that cycle with M.
## Mode 0 = hidden, 1 = parchment, 2 = modern card, 3 = connection graph.

const MODE_COUNT := 4

var _mode: int = 0
var _player: Node = null
var _zoom_level: float = 1.0
var _min_zoom: float = 0.5
var _max_zoom: float = 3.0
var _zoom_step: float = 0.25

var _views: Array[Control] = []
var _active: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var parchment := load("res://scenes/ui/ParchmentMinimap.gd").new() as Control
	parchment.name = "ParchmentMinimap"
	add_child(parchment)

	var modern := load("res://scenes/ui/ModernMinimap.gd").new() as Control
	modern.name = "ModernMinimap"
	add_child(modern)

	var graph := load("res://scenes/ui/GraphMinimap.gd").new() as Control
	graph.name = "GraphMinimap"
	add_child(graph)

	_views = [parchment, modern, graph]
	for v in _views:
		v.visible = false


func init(player: Node) -> void:
	_player = player
	for v in _views:
		if v.has_method("init"):
			v.init(player)


func cycle() -> void:
	_mode = (_mode + 1) % MODE_COUNT
	_update_visibility()


func show_hud() -> void:
	if not _active:
		_active = true
		if _mode == 0:
			_mode = 1
		_update_visibility()


func set_hidden() -> void:
	_active = false
	_mode = 0
	for v in _views:
		v.visible = false
	visible = false


func restore_after_pause() -> void:
	if _active:
		visible = true
		_update_visibility()


func _update_visibility() -> void:
	if _mode == 0:
		_active = false
		for v in _views:
			if v.visible:
				_slide_out(v)
		return

	_active = true
	visible = true

	for i in _views.size():
		var v := _views[i]
		if i == _mode - 1:
			if not v.visible:
				v.visible = true
				_slide_in(v)
			# Pass zoom and player
			if v.has_method("set_zoom"):
				v.set_zoom(_zoom_level)
		else:
			if v.visible:
				v.visible = false


func _input(event: InputEvent) -> void:
	if not visible or _mode == 0:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_level = min(_zoom_level + _zoom_step, _max_zoom)
			_apply_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_level = max(_zoom_level - _zoom_step, _min_zoom)
			_apply_zoom()


func _apply_zoom() -> void:
	var active_view := _get_active_view()
	if active_view and active_view.has_method("set_zoom"):
		active_view.set_zoom(_zoom_level)
	# Update camera
	if _player and _player.has_node("MapCameraContainer/MapViewport/MapCamera"):
		var cam = _player.get_node("MapCameraContainer/MapViewport/MapCamera")
		if cam is Camera3D:
			cam.position.y = clamp(40.0 / _zoom_level, 10.0, 200.0)
			cam.keep_aspect = Camera3D.KEEP_HEIGHT


func _get_active_view() -> Control:
	if _mode >= 1 and _mode <= _views.size():
		return _views[_mode - 1]
	return null


func _process(_delta: float) -> void:
	if not visible or _mode == 0:
		return
	var active := _get_active_view()
	if active and active.has_method("update_texture") and _player:
		if _player.has_method("get_minimap_texture"):
			active.update_texture(_player.get_minimap_texture())


# ── Slide animations (save original position to avoid accumulation) ───────────

var _orig_positions: Dictionary = {}

func _get_orig_pos(v: Control) -> Vector2:
	if not _orig_positions.has(v):
		_orig_positions[v] = v.position
	return _orig_positions[v]

func _slide_in(v: Control) -> void:
	var orig: Vector2 = _get_orig_pos(v)
	v.modulate.a = 0.0
	v.position.y = orig.y + 12.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(v, "modulate:a", 1.0, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "position:y", orig.y, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _slide_out(v: Control) -> void:
	var orig: Vector2 = _get_orig_pos(v)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(v, "modulate:a", 0.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(v, "position:y", orig.y + 10.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		v.visible = false
		v.modulate.a = 1.0
		v.position = orig
	)


func reset_zoom() -> void:
	_zoom_level = 1.0
	_apply_zoom()
