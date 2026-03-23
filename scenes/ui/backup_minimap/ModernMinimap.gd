extends Control
## ModernMinimap
## Clean floating card. Full-colour SubViewport texture, single player
## direction arrow at centre, fixed compass rose in the top-right corner.

var _player      : Node         = null
var _tex_rect    : TextureRect  = null
var _overlay     : Control      = null
var _panel_sb    : StyleBoxFlat = null
var _bar_sb      : StyleBoxFlat = null
var _room_label  : Label        = null
var _zoom_label  : Label        = null
var _zoom_fill   : ColorRect    = null
var _zoom_bg     : ColorRect    = null
var _zoom        : float        = 1.0
var _font        : Font         = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeManager.get_reading_font()

	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left     = -268.0
	offset_top      = -268.0
	offset_right    = -18.0
	offset_bottom   = -18.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical   = Control.GROW_DIRECTION_BEGIN

	# Outer card panel
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_sb = StyleBoxFlat.new()
	panel.add_theme_stylebox_override("panel", _panel_sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# Texture area
	var clip := Control.new()
	clip.clip_contents         = true
	clip.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(clip)

	_tex_rect = TextureRect.new()
	_tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	clip.add_child(_tex_rect)

	# Arrow + compass overlay
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	clip.add_child(_overlay)

	# Bottom info bar
	var bar := PanelContainer.new()
	_bar_sb = StyleBoxFlat.new()
	_bar_sb.content_margin_left   = 10
	_bar_sb.content_margin_right  = 10
	_bar_sb.content_margin_top    = 5
	_bar_sb.content_margin_bottom = 5
	bar.add_theme_stylebox_override("panel", _bar_sb)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	bar.add_child(hbox)

	_room_label = Label.new()
	_room_label.text                  = "Museum"
	_room_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_label.clip_text             = true
	hbox.add_child(_room_label)

	# Zoom bar track
	var zw := Control.new()
	zw.custom_minimum_size = Vector2(42, 5)
	zw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(zw)

	_zoom_bg = ColorRect.new()
	_zoom_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	zw.add_child(_zoom_bg)

	_zoom_fill = ColorRect.new()
	_zoom_fill.anchor_top    = 0.0; _zoom_fill.anchor_bottom = 1.0
	_zoom_fill.anchor_left   = 0.0; _zoom_fill.anchor_right  = 0.4
	_zoom_fill.offset_top    = 0;   _zoom_fill.offset_bottom = 0
	_zoom_fill.offset_left   = 0;   _zoom_fill.offset_right  = 0
	zw.add_child(_zoom_fill)

	_zoom_label = Label.new()
	_zoom_label.text = "100%"
	_zoom_label.add_theme_font_size_override("font_size", 9)
	hbox.add_child(_zoom_label)

	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f): _font = f; _apply_theme())
	_apply_theme()


func _apply_theme() -> void:
	var dark   : bool  = ThemeManager.is_dark_mode
	var accent : Color = Color(0.28, 0.52, 1.00) if dark else Color(0.14, 0.38, 0.88)

	if _panel_sb:
		_panel_sb.bg_color     = Color(0.08, 0.09, 0.13, 0.90) if dark \
		                       else Color(1.0, 1.0, 1.0, 0.96)
		_panel_sb.border_color = Color(accent, 0.38)
		_panel_sb.set_border_width_all(2)
		_panel_sb.set_corner_radius_all(14)
		_panel_sb.shadow_color  = Color(0, 0, 0, 0.38 if dark else 0.13)
		_panel_sb.shadow_size   = 16
		_panel_sb.shadow_offset = Vector2(0, 4)

	if _bar_sb:
		_bar_sb.bg_color = Color(0.05, 0.06, 0.10, 0.68) if dark \
		                 else Color(0.94, 0.95, 0.97, 0.88)
		_bar_sb.corner_radius_bottom_left  = 12
		_bar_sb.corner_radius_bottom_right = 12

	if _room_label:
		if _font: _room_label.add_theme_font_override("font", _font)
		_room_label.add_theme_font_size_override("font_size", 11)
		_room_label.add_theme_color_override("font_color",
			Color(1,1,1,0.88) if dark else Color(0.10,0.10,0.14,0.88))
	if _zoom_label:
		if _font: _zoom_label.add_theme_font_override("font", _font)
		_zoom_label.add_theme_color_override("font_color",
			Color(1,1,1,0.42) if dark else Color(0.30,0.30,0.38,0.50))
	if _zoom_bg:
		_zoom_bg.color = Color(1,1,1,0.10) if dark else Color(0,0,0,0.07)
	if _zoom_fill:
		_zoom_fill.color = accent
	if _overlay:
		_overlay.queue_redraw()


func _draw_overlay() -> void:
	if not _overlay:
		return
	var s      : Vector2 = _overlay.size
	var cx     : float   = s.x * 0.5
	var cy     : float   = s.y * 0.5
	var dark   : bool    = ThemeManager.is_dark_mode
	var accent : Color   = Color(0.28, 0.52, 1.00) if dark else Color(0.14, 0.38, 0.88)
	var angle  : float   = _get_angle()

	# ── Player direction arrow ────────────────────────────────────────────────
	var r     : float   = 9.0
	var tip   : Vector2 = Vector2(cx + sin(angle)*r*1.5,    cy + cos(angle)*r*1.5)
	var lft   : Vector2 = Vector2(cx + sin(angle+2.2)*r,    cy + cos(angle+2.2)*r)
	var rgt   : Vector2 = Vector2(cx + sin(angle-2.2)*r,    cy + cos(angle-2.2)*r)
	var back  : Vector2 = Vector2(cx + sin(angle+PI)*r*0.4, cy + cos(angle+PI)*r*0.4)
	# Drop shadow
	_overlay.draw_colored_polygon(
		PackedVector2Array([tip+Vector2(1,1), lft+Vector2(1,1),
		                    back+Vector2(1,1), rgt+Vector2(1,1)]),
		Color(0,0,0,0.42))
	# Fill
	_overlay.draw_colored_polygon(
		PackedVector2Array([tip, lft, back, rgt]),
		Color(1.0, 1.0, 1.0, 0.95))
	# Accent outline
	_overlay.draw_polyline(
		PackedVector2Array([tip, lft, back, rgt, tip]),
		Color(accent, 0.75), 1.0)

	# ── Fixed compass rose (top-right corner) — does NOT rotate ───────────────
	var cr  : float   = 13.0
	var ccx : float   = s.x - cr - 9.0
	var ccy : float   = cr + 9.0
	var cc  : Vector2 = Vector2(ccx, ccy)
	_overlay.draw_circle(cc, cr + 3.0,
		Color(0.06, 0.07, 0.11, 0.68) if dark else Color(0.94, 0.95, 0.97, 0.78))
	_overlay.draw_arc(cc, cr, 0.0, TAU, 24, Color(accent, 0.32), 1.0)
	_overlay.draw_line(cc + Vector2(0, -cr*0.8), cc + Vector2(0,  cr*0.8), Color(accent, 0.25), 1.0)
	_overlay.draw_line(cc + Vector2(-cr*0.8, 0), cc + Vector2(cr*0.8, 0),  Color(accent, 0.25), 1.0)
	if _font:
		_overlay.draw_string(_font, cc + Vector2(-3.0, -cr*0.78 - 2.0),
			"N", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(accent, 0.92))

	# ── Subtle circular vignette around the map edge ──────────────────────────
	_overlay.draw_arc(Vector2(cx, cy), min(cx, cy) - 1.5, 0.0, TAU, 64,
		Color(0,0,0, 0.25 if dark else 0.08), 5.0, true)


func init(player: Node) -> void:
	_player = player


func update_texture(tex: Texture2D) -> void:
	if _tex_rect and tex:
		_tex_rect.texture = tex


func set_zoom(level: float) -> void:
	_zoom = level
	if _zoom_label:
		_zoom_label.text = "%d%%" % int(level * 100)
	if _zoom_fill:
		_zoom_fill.anchor_right = clampf((level - 0.5) / 2.5, 0.0, 1.0)


func _process(_delta: float) -> void:
	if not visible:
		return
	if is_instance_valid(_player) and "current_room" in _player and _room_label:
		var r : String = str(_player.current_room) if _player.current_room else "Museum"
		if _room_label.text != r:
			_room_label.text = r
	if _overlay:
		_overlay.queue_redraw()


func _get_angle() -> float:
	return _player.rotation.y if is_instance_valid(_player) else 0.0
