extends Control
## LocalAreaMinimap — 3D isometric view of immediate surroundings.
##
## Renders the MapViewport SubViewport texture (same hardware render all other
## minimaps share) but requests MinimapController tilt MapCamera to ~50° pitch
## via the wants_isometric_camera() callback, giving a genuine 3D perspective.
##
## The overlay drawn on top adds: room title header, radial vignette,
## race-target badge, north tick, and zoom%.

const PANEL_SIZE : float = 260.0

var _player    : Node       = null
var _font      : Font       = null
var _time      : float      = 0.0
var _zoom      : float      = 1.0

var _panel_sb  : StyleBoxFlat = null
var _header_sb : StyleBoxFlat = null
var _footer_sb : StyleBoxFlat = null
var _tex_rect  : TextureRect  = null
var _overlay   : Control      = null
var _header_lbl: Label        = null
var _footer_lbl: Label        = null

var _current_room : String = ""
var _target       : String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font        = ThemeManager.get_reading_font()

	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left     = -(PANEL_SIZE + 18.0)
	offset_top      = -(PANEL_SIZE + 18.0)
	offset_right    = -18.0
	offset_bottom   = -18.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical   = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(PANEL_SIZE, PANEL_SIZE)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_sb = StyleBoxFlat.new()
	panel.add_theme_stylebox_override("panel", _panel_sb)
	add_child(panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   10)
	mc.add_theme_constant_override("margin_right",  10)
	mc.add_theme_constant_override("margin_top",     8)
	mc.add_theme_constant_override("margin_bottom",  6)
	panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	mc.add_child(vbox)

	# Header
	var hw := PanelContainer.new()
	_header_sb = StyleBoxFlat.new()
	_header_sb.content_margin_left   = 7
	_header_sb.content_margin_right  = 7
	_header_sb.content_margin_top    = 3
	_header_sb.content_margin_bottom = 3
	hw.add_theme_stylebox_override("panel", _header_sb)
	hw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(hw)

	_header_lbl = Label.new()
	_header_lbl.text      = "Lobby"
	_header_lbl.clip_text = true
	hw.add_child(_header_lbl)

	# Viewport texture area
	var clip := Control.new()
	clip.clip_contents         = true
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	vbox.add_child(clip)

	_tex_rect = TextureRect.new()
	_tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	clip.add_child(_tex_rect)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	clip.add_child(_overlay)

	vbox.add_child(_make_divider())

	# Footer
	var fw := PanelContainer.new()
	_footer_sb = StyleBoxFlat.new()
	_footer_sb.content_margin_left   = 7
	_footer_sb.content_margin_right  = 7
	_footer_sb.content_margin_top    = 3
	_footer_sb.content_margin_bottom = 3
	fw.add_theme_stylebox_override("panel", _footer_sb)
	fw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(fw)

	_footer_lbl = Label.new()
	_footer_lbl.text                 = "3D View"
	_footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fw.add_child(_footer_lbl)

	SettingsEvents.set_current_room.connect(_on_room_changed)
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_ended.connect(_on_race_ended)
	RaceManager.race_cancelled.connect(_on_race_cancelled)

	if RaceManager.is_race_active():
		_target = RaceManager.get_target_article()

	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f): _font = f; _apply_theme())
	_apply_theme()


func _on_room_changed(room: Variant) -> void:
	var r : String = str(room)
	if r == _current_room: return
	_current_room = r
	if _header_lbl:
		_header_lbl.text = r if r != "" else "Lobby"
		_header_lbl.modulate.a = 0.0
		create_tween().tween_property(_header_lbl, "modulate:a", 1.0, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_race_started(t: String, _s: String) -> void: _target = t
func _on_race_ended(_p: int, _n: String)      -> void: _target = ""
func _on_race_cancelled()                      -> void: _target = ""


func _draw_overlay() -> void:
	if not _overlay: return
	var dark   := ThemeManager.is_dark_mode
	var accent := _accent()
	var sz     := _overlay.size

	# Radial vignette
	var cx   : float = sz.x * 0.5
	var cy   : float = sz.y * 0.5
	var r_out: float = sz.length() * 0.52
	var r_in : float = sz.length() * 0.28
	for i in 48:
		var a0 := float(i)     / 48.0 * TAU
		var a1 := float(i + 1) / 48.0 * TAU
		_overlay.draw_colored_polygon(PackedVector2Array([
			Vector2(cx + cos(a0)*r_in,  cy + sin(a0)*r_in),
			Vector2(cx + cos(a0)*r_out, cy + sin(a0)*r_out),
			Vector2(cx + cos(a1)*r_out, cy + sin(a1)*r_out),
			Vector2(cx + cos(a1)*r_in,  cy + sin(a1)*r_in),
		]), Color(0, 0, 0, 0.38 if dark else 0.20))

	# Race target badge
	if _target != "" and _font:
		var txt : String = "★  " + _target.replace("_", " ")
		if txt.length() > 28: txt = txt.substr(0, 27) + "…"
		var tw2 : float = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_overlay.draw_rect(
			Rect2(cx - tw2*0.5 - 6, sz.y - 22, tw2 + 12, 16),
			Color(_gold(), 0.78 if dark else 0.85))
		_overlay.draw_string(_font, Vector2(cx - tw2*0.5, sz.y - 9),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.10, 0.06, 0.0, 0.95))

	# North tick
	if _font:
		_overlay.draw_string(_font, Vector2(cx - 4.5, 14),
			"N", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(accent, 0.72))
		_overlay.draw_line(Vector2(cx, 17), Vector2(cx, 10),
			Color(accent, 0.42), 1.0, true)

	# Zoom %
	if _font:
		_overlay.draw_string(_font, Vector2(5, sz.y - 5),
			"%d%%" % int(_zoom * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(accent, 0.52))


func _apply_theme() -> void:
	var dark   := ThemeManager.is_dark_mode
	var accent := _accent()

	if _panel_sb:
		_panel_sb.bg_color     = Color(ThemeManager.bg_color, 0.93)
		_panel_sb.border_color = ThemeManager.border_color
		_panel_sb.set_border_width_all(1)
		_panel_sb.set_corner_radius_all(10)
		_panel_sb.shadow_color  = Color(0, 0, 0, 0.30 if dark else 0.10)
		_panel_sb.shadow_size   = 14
		_panel_sb.shadow_offset = Vector2(0, 4)

	for sb in [_header_sb, _footer_sb]:
		if not sb: continue
		sb.bg_color = Color(accent, 0.07 if dark else 0.04)
		sb.set_corner_radius_all(5)

	for lbl in [_header_lbl, _footer_lbl]:
		if not lbl: continue
		if _font: lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 10)

	if _header_lbl:
		_header_lbl.add_theme_color_override("font_color", ThemeManager.text_color)
	if _footer_lbl:
		_footer_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _overlay: _overlay.queue_redraw()


func _accent() -> Color:
	return Color(0.30, 0.55, 1.00) if ThemeManager.is_dark_mode \
		 else Color(0.12, 0.32, 0.82)

func _gold() -> Color:
	return Color(1.00, 0.80, 0.22) if ThemeManager.is_dark_mode \
		 else Color(0.78, 0.52, 0.05)

func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	d.color               = ThemeManager.border_color
	# Use CONNECT_DEFERRED to avoid lambda capture issues
	ThemeManager.dark_mode_changed.connect(_on_theme_changed.bind(d), CONNECT_DEFERRED)
	return d

func _on_theme_changed(_dk: bool, rect: ColorRect) -> void:
	if is_instance_valid(rect):
		rect.color = ThemeManager.border_color


# ── Public API ─────────────────────────────────────────────────────────────────

func init(player: Node) -> void:
	_player       = player
	_current_room = "Lobby"
	if _header_lbl: _header_lbl.text = "Lobby"

func update_texture(tex: Texture2D) -> void:
	if _tex_rect and tex: _tex_rect.texture = tex

func set_zoom(level: float) -> void:
	_zoom = level
	if _footer_lbl: _footer_lbl.text = "3D View · %d%%" % int(_zoom * 100)
	if _overlay: _overlay.queue_redraw()

## MinimapController reads this to know it should tilt the camera to isometric.
func wants_isometric_camera() -> bool:
	return true

func _process(delta: float) -> void:
	if not visible: return
	_time += delta
	if _overlay: _overlay.queue_redraw()
