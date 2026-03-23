extends Control
## CompassMinimap — Proximity compass with real door bearings.
##
## Shows a compass ring with N/E/S/W ticks that counter-rotate with the
## player's heading (north = always up on screen relative to world).
## Blips on the ring represent every real exit Hall in the current exhibit,
## placed at their true compass bearing from the player.
##
## Data wiring — exact, verified against source files:
##   Museum node (found via get_tree().current_scene.get_node("%Museum"))
##     → _exhibits dict (via get_exhibits() on ExhibitLoader, exposed as
##       Museum._exhibits property)
##     → each entry: { "exhibit": TiledExhibitGenerator, ... }
##     → exhibit.exits : Array[Hall]
##     → Hall.global_position : Vector3  (world position of the door)
##     → Hall.to_title : String          (destination article)
##   Player.rotation.y          → heading for compass rotation
##   Player.global_position     → origin for bearing calculation
##   SettingsEvents.set_current_room → triggers re-scan of exits
##   RaceManager.get_target_article()→ highlight the exit that leads toward target
##
## No synthetic fallback blips — if exits can't be read the compass still
## shows the heading arrow and cardinal ticks, which is useful on its own.

const PANEL_SIZE : float = 250.0
const RING_INSET : float = 12.0   # gap between canvas edge and ring
const TICK_LONG  : float = 10.0
const TICK_SHORT : float = 5.0
const BLIP_R     : float = 5.5
const SCAN_RATE  : float = 0.30   # seconds between exit re-scans

var _player      : Node   = null
var _museum      : Node   = null
var _font        : Font   = null
var _time        : float  = 0.0
var _scan_timer  : float  = 0.0

## Live blips: Array[{ bearing:float, dist:float, to_title:String, ping_age:float }]
var _blips       : Array[Dictionary] = []
var _current_room : String = ""
var _target       : String = ""

var _panel_sb    : StyleBoxFlat = null
var _canvas      : Control      = null
var _room_lbl    : Label        = null
var _footer_sb   : StyleBoxFlat = null


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
	mc.add_theme_constant_override("margin_top",    10)
	mc.add_theme_constant_override("margin_bottom",  8)
	panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	mc.add_child(vbox)

	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_compass)
	vbox.add_child(_canvas)

	vbox.add_child(_make_divider())

	var fw := PanelContainer.new()
	_footer_sb = StyleBoxFlat.new()
	_footer_sb.content_margin_left   = 6
	_footer_sb.content_margin_right  = 6
	_footer_sb.content_margin_top    = 3
	_footer_sb.content_margin_bottom = 3
	fw.add_theme_stylebox_override("panel", _footer_sb)
	fw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(fw)

	_room_lbl = Label.new()
	_room_lbl.text = "Lobby"
	fw.add_child(_room_lbl)

	SettingsEvents.set_current_room.connect(_on_room_changed)
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_ended.connect(_on_race_ended)
	RaceManager.race_cancelled.connect(_on_race_cancelled)

	if RaceManager.is_race_active():
		_target = RaceManager.get_target_article()

	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f): _font = f; _apply_theme())
	_apply_theme()


# ── Signal handlers ────────────────────────────────────────────────────────────

func _on_room_changed(room: Variant) -> void:
	var r : String = str(room)
	_current_room = r
	if _room_lbl:
		_room_lbl.text = r if r != "" else "Lobby"
		_room_lbl.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_room_lbl, "modulate:a", 1.0, 0.30) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_blips.clear()
	_scan_timer = SCAN_RATE  # trigger immediate re-scan


func _on_race_started(target_article: String, _start: String) -> void:
	_target = target_article

func _on_race_ended(_peer: int, _name: String) -> void:
	_target = ""

func _on_race_cancelled() -> void:
	_target = ""


# ── Theme ──────────────────────────────────────────────────────────────────────

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

	if _footer_sb:
		_footer_sb.bg_color = Color(accent, 0.07 if dark else 0.04)
		_footer_sb.set_corner_radius_all(5)

	if _room_lbl:
		if _font: _room_lbl.add_theme_font_override("font", _font)
		_room_lbl.add_theme_font_size_override("font_size", 11)
		_room_lbl.add_theme_color_override("font_color", ThemeManager.text_color)

	if _canvas: _canvas.queue_redraw()


# ── Exit scanning ──────────────────────────────────────────────────────────────

func _get_museum() -> Node:
	if is_instance_valid(_museum): return _museum
	# Museum is %Museum in Main scene — find via current scene unique name
	var root := get_tree().current_scene
	if root:
		_museum = root.get_node_or_null("%Museum")
	return _museum


func _scan_exits() -> void:
	if not is_instance_valid(_player): return
	var museum := _get_museum()
	if not museum: return

	var exhibits : Dictionary = museum._exhibits
	var exhibit_data : Variant = exhibits.get(_current_room)
	if not exhibit_data is Dictionary: return

	var exhibit : Node = exhibit_data.get("exhibit")
	if not is_instance_valid(exhibit): return
	if not "exits" in exhibit: return

	var pp  : Vector3 = _player.global_position
	var new_blips : Array[Dictionary] = []

	for hall in exhibit.exits:
		if not is_instance_valid(hall): continue
		if not "to_title" in hall or not "global_position" in hall: continue
		var dp      : Vector3 = hall.global_position - pp
		var bearing : float   = atan2(dp.x, dp.z)  # world-space angle
		var dist    : float   = dp.length()
		# Preserve ping_age if this blip was already tracked
		var old_age : float = 1.0
		for ob in _blips:
			if abs(ob.bearing - bearing) < 0.20:
				old_age = ob.ping_age
				break
		var is_tgt : bool = (hall.to_title == _target and _target != "")
		new_blips.append({
			"bearing"  : bearing,
			"dist"     : dist,
			"to_title" : str(hall.to_title),
			"ping_age" : minf(old_age + SCAN_RATE * 0.5, 1.0),
			"is_target": is_tgt,
		})

	# Ping new blips that weren't there before
	for nb in new_blips:
		var found := false
		for ob in _blips:
			if abs(ob.bearing - nb.bearing) < 0.20:
				found = true; break
		if not found:
			nb.ping_age = 0.0

	_blips = new_blips


# ── Draw ───────────────────────────────────────────────────────────────────────

func _draw_compass() -> void:
	if not _canvas: return
	var dark   := ThemeManager.is_dark_mode
	var accent := _accent()
	var sz     := _canvas.size
	if sz == Vector2.ZERO: return

	var cx   : float = sz.x * 0.5
	var cy   : float = sz.y * 0.5
	var R    : float = minf(cx, cy) - RING_INSET
	var ctr  : Vector2 = Vector2(cx, cy)
	var hdg  : float   = _get_heading()

	# ── Background disc ─────────────────────────────────────────────────────
	_canvas.draw_circle(ctr, R, Color(accent, 0.04 if dark else 0.03))
	_canvas.draw_arc(ctr, R, 0.0, TAU, 80, Color(accent, 0.15 if dark else 0.10), 1.0, true)

	# ── Cardinal ticks + labels ─────────────────────────────────────────────
	var cardinal_labels := ["N", "E", "S", "W"]
	for i in 4:
		var world_angle  : float   = float(i) * PI * 0.5
		var screen_angle : float   = world_angle - hdg
		var dx           : float   = sin(screen_angle)
		var dy           : float   = -cos(screen_angle)
		var is_n         : bool    = (i == 0)
		var tick_len     : float   = TICK_LONG if is_n else TICK_SHORT

		var p_inner : Vector2 = ctr + Vector2(dx, dy) * (R - tick_len)
		var p_outer : Vector2 = ctr + Vector2(dx, dy) * (R + 1.0)
		_canvas.draw_line(p_inner, p_outer,
			Color(accent, 0.90 if is_n else 0.42),
			2.0 if is_n else 1.0, true)

		if _font:
			var lp : Vector2 = ctr + Vector2(dx, dy) * (R - tick_len - 10.0)
			_canvas.draw_string(_font,
				lp - Vector2(4.5, -4.5),
				cardinal_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(accent, 0.95 if is_n else 0.55))

	# Sub-cardinal dashes
	for i in 4:
		var world_angle  : float = float(i) * PI * 0.5 + PI * 0.25
		var screen_angle : float = world_angle - hdg
		var dx : float = sin(screen_angle)
		var dy : float = -cos(screen_angle)
		_canvas.draw_line(
			ctr + Vector2(dx, dy) * (R - 3.0),
			ctr + Vector2(dx, dy) * (R + 1.0),
			Color(accent, 0.18), 1.0, true)

	# ── Exit blips ──────────────────────────────────────────────────────────
	for blip in _blips:
		var screen_angle : float   = blip.bearing - hdg
		var bx           : float   = cx + sin(screen_angle) * R
		var by           : float   = cy - cos(screen_angle) * R
		var bpos         : Vector2 = Vector2(bx, by)
		var age          : float   = blip.ping_age
		var is_tgt       : bool    = blip.is_target

		# Ping ripple (fades out over ~0.8s)
		if age < 0.8:
			var pr : float = BLIP_R + age * 20.0
			var pa : float = (1.0 - age / 0.8) * 0.55
			_canvas.draw_circle(bpos, pr, Color(accent, pa))

		# Target gets a gold colour and extra glow
		var blip_col : Color
		if is_tgt:
			blip_col = _gold()
			var tpulse := (sin(_time * 2.0) + 1.0) * 0.5
			_canvas.draw_circle(bpos, BLIP_R + 4.0 + tpulse * 2.5,
				Color(_gold(), 0.14 + tpulse * 0.08))
		else:
			blip_col = accent

		_canvas.draw_circle(bpos, BLIP_R,       Color(1, 1, 1, 0.90))
		_canvas.draw_circle(bpos, BLIP_R - 1.5, blip_col)

		# Article name label on hover-sized blips
		if _font and blip.to_title != "":
			var lbl : String = blip.to_title.replace("_", " ")
			if lbl.length() > 14: lbl = lbl.substr(0, 13) + "…"
			# Offset label away from centre
			var dir : Vector2 = (bpos - ctr).normalized()
			var lp  : Vector2 = bpos + dir * (BLIP_R + 4.0)
			_canvas.draw_string(_font, lp - Vector2(0, 3),
				lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(blip_col if is_tgt else ThemeManager.subtext_color, 0.80))

	# ── Heading arrow (always faces screen-up = player forward) ─────────────
	var arrow_r : float = R * 0.38
	var tip     : Vector2 = ctr + Vector2(0, -arrow_r * 1.5)
	var lft     : Vector2 = ctr + Vector2(-arrow_r * 0.22,  arrow_r * 0.18)
	var rgt     : Vector2 = ctr + Vector2( arrow_r * 0.22,  arrow_r * 0.18)
	var bk      : Vector2 = ctr + Vector2(0, arrow_r * 0.08)

	# Shadow
	_canvas.draw_colored_polygon(
		PackedVector2Array([tip+Vector2(0.7,0.9), lft+Vector2(0.7,0.9),
		                    bk+Vector2(0.7,0.9),  rgt+Vector2(0.7,0.9)]),
		Color(0, 0, 0, 0.25))
	# Fill
	_canvas.draw_colored_polygon(PackedVector2Array([tip, lft, bk, rgt]),
		Color(1, 1, 1, 0.95))
	# Accent outline
	_canvas.draw_polyline(PackedVector2Array([tip, lft, bk, rgt, tip]),
		Color(accent, 0.78), 1.2, true)

	# Centre dot
	_canvas.draw_circle(ctr, 3.0, Color(accent, 0.60))

	# ── Outer border ring ────────────────────────────────────────────────────
	_canvas.draw_arc(ctr, R, 0.0, TAU, 80, ThemeManager.border_color, 1.5, true)
	# Inner accent ring
	_canvas.draw_arc(ctr, R - 3.0, 0.0, TAU, 80,
		Color(accent, 0.14 if dark else 0.08), 1.0, true)

	# ── Blip count when no exits found ──────────────────────────────────────
	if _blips.is_empty() and _font:
		_canvas.draw_string(_font,
			Vector2(cx - 44.0, cy + R * 0.70),
			"No exits detected", HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(accent, 0.35))


# ── Helpers ────────────────────────────────────────────────────────────────────

func _accent() -> Color:
	return Color(0.30, 0.55, 1.00) if ThemeManager.is_dark_mode \
	     else Color(0.12, 0.32, 0.82)

func _gold() -> Color:
	return Color(1.00, 0.80, 0.22) if ThemeManager.is_dark_mode \
	     else Color(0.78, 0.52, 0.05)

func _get_heading() -> float:
	return _player.rotation.y if is_instance_valid(_player) else 0.0

func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	d.color               = ThemeManager.border_color
	ThemeManager.dark_mode_changed.connect(func(_d): d.color = ThemeManager.border_color)
	return d

func init(player: Node) -> void:
	_player = player
	_museum = null   # will be fetched lazily

func update_texture(_tex: Texture2D) -> void:
	pass

func set_zoom(_z: float) -> void:
	pass

func _process(delta: float) -> void:
	if not visible: return
	_time       += delta
	_scan_timer += delta
	# Age blip ping timers
	for blip in _blips:
		blip.ping_age = minf(blip.ping_age + delta * 0.5, 1.0)
	if _scan_timer >= SCAN_RATE:
		_scan_timer = 0.0
		_scan_exits()
	if _canvas: _canvas.queue_redraw()
