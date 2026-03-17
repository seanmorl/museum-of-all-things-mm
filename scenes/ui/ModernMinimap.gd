extends Control
## ModernMinimap — sleek glassmorphism floating card with full-colour 3D view.
## Visually distinct from ParchmentMinimap: rounded corners, frosted glass bar,
## no sepia tint, clean modern typography.

var _player: Node = null
var _texture_rect: TextureRect = null
var _panel_style: StyleBoxFlat = null
var _bar_style: StyleBoxFlat = null
var _room_label: Label = null
var _zoom_label: Label = null
var _zoom_bar: ColorRect = null
var _zoom_bg: ColorRect = null
var _zoom_level: float = 1.0
var _serif_font: Font = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_serif_font = ThemeManager.get_reading_font()

	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left  = -270.0; offset_top    = -270.0
	offset_right = -20.0;  offset_bottom = -20.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical   = Control.GROW_DIRECTION_BEGIN

	# Main card panel
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_style = StyleBoxFlat.new()
	panel.add_theme_stylebox_override("panel", _panel_style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# ── Map texture area (no sepia — full vivid color) ──
	var tex_clip := Control.new()
	tex_clip.clip_contents = true
	tex_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tex_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tex_clip)

	_texture_rect = TextureRect.new()
	_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# No modulate — full colour, this is the key visual difference
	tex_clip.add_child(_texture_rect)

	# ── Bottom info bar (frosted glass effect) ──
	var bar := PanelContainer.new()
	_bar_style = StyleBoxFlat.new()
	_bar_style.content_margin_left = 10
	_bar_style.content_margin_right = 10
	_bar_style.content_margin_top = 6
	_bar_style.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", _bar_style)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	bar.add_child(hbox)

	# Room name
	_room_label = Label.new()
	_room_label.text = "Museum"
	_room_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _serif_font: _room_label.add_theme_font_override("font", _serif_font)
	_room_label.add_theme_font_size_override("font_size", 11)
	hbox.add_child(_room_label)

	# Zoom bar visual
	var zoom_container := HBoxContainer.new()
	zoom_container.add_theme_constant_override("separation", 4)
	hbox.add_child(zoom_container)

	# Zoom bar background
	var zoom_wrap := Control.new()
	zoom_wrap.custom_minimum_size = Vector2(40, 6)
	zoom_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zoom_container.add_child(zoom_wrap)

	_zoom_bg = ColorRect.new()
	_zoom_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	zoom_wrap.add_child(_zoom_bg)

	_zoom_bar = ColorRect.new()
	_zoom_bar.anchor_top = 0; _zoom_bar.anchor_bottom = 1
	_zoom_bar.anchor_left = 0; _zoom_bar.anchor_right = 0.5
	_zoom_bar.offset_top = 0; _zoom_bar.offset_bottom = 0
	_zoom_bar.offset_left = 0; _zoom_bar.offset_right = 0
	zoom_wrap.add_child(_zoom_bar)

	_zoom_label = Label.new()
	_zoom_label.text = "100%"
	_zoom_label.add_theme_font_size_override("font_size", 9)
	if _serif_font: _zoom_label.add_theme_font_override("font", _serif_font)
	zoom_container.add_child(_zoom_label)

	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f):
		_serif_font = f
		_apply_theme()
	)
	_apply_theme()


func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.15, 0.40, 0.90)

	if _panel_style:
		_panel_style.bg_color = Color(0.08, 0.09, 0.14, 0.88) if dark else Color(1.0, 1.0, 1.0, 0.95)
		_panel_style.border_color = Color(accent, 0.40)
		_panel_style.set_border_width_all(2)
		_panel_style.set_corner_radius_all(16)
		_panel_style.shadow_color = Color(0, 0, 0, 0.40 if dark else 0.15)
		_panel_style.shadow_size = 18
		_panel_style.shadow_offset = Vector2(0, 5)

	if _bar_style:
		_bar_style.bg_color = Color(0.05, 0.06, 0.10, 0.60) if dark else Color(0.95, 0.96, 0.98, 0.80)
		_bar_style.corner_radius_bottom_left = 14
		_bar_style.corner_radius_bottom_right = 14

	if _room_label:
		_room_label.add_theme_color_override("font_color",
			Color(1, 1, 1, 0.9) if dark else Color(0.1, 0.1, 0.15, 0.9))
	if _zoom_label:
		_zoom_label.add_theme_color_override("font_color",
			Color(1, 1, 1, 0.5) if dark else Color(0.3, 0.3, 0.4, 0.5))
	if _zoom_bg:
		_zoom_bg.color = Color(1, 1, 1, 0.12) if dark else Color(0, 0, 0, 0.08)
	if _zoom_bar:
		_zoom_bar.color = accent


func init(player: Node) -> void:
	_player = player

func update_texture(tex: Texture2D) -> void:
	if _texture_rect and tex:
		_texture_rect.texture = tex

func set_zoom(level: float) -> void:
	_zoom_level = level
	if _zoom_label:
		_zoom_label.text = "%d%%" % int(level * 100)
	if _zoom_bar:
		# Map 0.5-3.0 range to 0-1 for bar width
		var t: float = clamp((level - 0.5) / 2.5, 0.0, 1.0)
		_zoom_bar.anchor_right = t

func _process(_delta: float) -> void:
	if visible and _player and "current_room" in _player:
		var room: String = _player.current_room if _player.current_room else "Museum"
		if _room_label and _room_label.text != room:
			_room_label.text = room
