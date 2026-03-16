extends Control
## MinimapHUD — styled minimap panel. Keeps the original tscn node structure.
## Adds theme-aware styling and slide animations on top of the original logic.

@onready var texture_rect: TextureRect = $Panel/TextureRect
@onready var zoom_label: Label = $Panel/ZoomIndicator if has_node("Panel/ZoomIndicator") else null

var _active: bool = false
var _player: Node = null
var _zoom_level: float = 1.0
var _min_zoom: float = 0.5
var _max_zoom: float = 3.0
var _zoom_step: float = 0.25
var _panel_style: StyleBoxFlat = null


func _ready() -> void:
	visible = false
	_active = false
	_setup_style()
	_apply_zoom()
	ThemeManager.dark_mode_changed.connect(func(_d): _setup_style())


func _setup_style() -> void:
	var panel := get_node_or_null("Panel") as Panel
	if not panel:
		return
	var dark: bool = ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	if not _panel_style:
		_panel_style = StyleBoxFlat.new()
		panel.add_theme_stylebox_override("panel", _panel_style)
	_panel_style.bg_color     = Color(0.06, 0.07, 0.10, 0.82) if dark \
		else Color(0.93, 0.94, 0.97, 0.88)
	_panel_style.border_color = Color(accent, 0.60)
	_panel_style.set_border_width_all(2)
	_panel_style.corner_radius_top_left     = 12
	_panel_style.corner_radius_top_right    = 12
	_panel_style.corner_radius_bottom_left  = 12
	_panel_style.corner_radius_bottom_right = 12
	_panel_style.shadow_color  = Color(0, 0, 0, 0.30 if dark else 0.10)
	_panel_style.shadow_size   = 10
	_panel_style.shadow_offset = Vector2(0, 3)
	# Style zoom label
	if zoom_label:
		zoom_label.add_theme_color_override("font_color",
			Color(1, 1, 1, 0.75) if dark else Color(0, 0, 0, 0.55))
		zoom_label.add_theme_font_size_override("font_size", 11)
		var sf := ThemeManager.get_reading_font()
		if sf:
			zoom_label.add_theme_font_override("font", sf)


func init(player: Node) -> void:
	_player = player


func _process(_delta: float) -> void:
	if visible and _player and _player.has_method("get_minimap_texture"):
		texture_rect.texture = _player.get_minimap_texture()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_out()


func _zoom_in() -> void:
	_zoom_level = min(_zoom_level + _zoom_step, _max_zoom)
	_apply_zoom()


func _zoom_out() -> void:
	_zoom_level = max(_zoom_level - _zoom_step, _min_zoom)
	_apply_zoom()


func _apply_zoom() -> void:
	if texture_rect:
		texture_rect.scale = Vector2(_zoom_level, _zoom_level)
	if zoom_label:
		zoom_label.text = "Zoom: %d%%" % int(_zoom_level * 100)
	var map_overlay = get_tree().get_first_node_in_group("exhibit_map_overlay")
	if map_overlay and "_zoom_level" in map_overlay:
		map_overlay._zoom_level = _zoom_level
	var player = get_tree().get_first_node_in_group("local_player")
	if player and player.has_node("MapCameraContainer/MapViewport/MapCamera"):
		var map_camera = player.get_node("MapCameraContainer/MapViewport/MapCamera")
		if map_camera is Camera3D:
			map_camera.position.y  = clamp(40.0 / _zoom_level, 10.0, 200.0)
			map_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	if _zoom_level < 1.0 and player:
		_try_trigger_exhibit_generation(player)


func _try_trigger_exhibit_generation(player: Node) -> void:
	var museum := get_tree().get_first_node_in_group("museum")
	if not museum:
		return
	var extra_radius: float = (1.0 / _zoom_level - 1.0) * 20.0
	if museum.has_method("hint_preload_nearby_exhibits"):
		museum.hint_preload_nearby_exhibits(player.global_position, extra_radius)


func reset_zoom() -> void:
	_zoom_level = 1.0
	_apply_zoom()


func toggle() -> void:
	if _active:
		_active = false
		_slide_out()
	else:
		_active = true
		_slide_in()


func show_hud() -> void:
	if not _active:
		_active = true
		_slide_in()


func set_hidden() -> void:
	_active = false
	visible = false
	modulate.a = 1.0


func restore_after_pause() -> void:
	if _active:
		visible = true


func _slide_in() -> void:
	visible    = true
	modulate.a = 0.0
	position.y += 12.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", position.y - 12.0, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _slide_out() -> void:
	var start_y: float = position.y
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", start_y + 10.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		visible    = false
		modulate.a = 1.0
		position.y = start_y
	)


func is_perfect_knowledge_active() -> bool:
	var player_id := NetworkManager.get_unique_id()
	return PowerupManager.has_powerup(player_id, PowerupManager.PowerupType.PERFECT_KNOWLEDGE)
