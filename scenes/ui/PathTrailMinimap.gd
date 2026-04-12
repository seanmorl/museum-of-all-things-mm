extends Control
## PathTrailMinimap — Article path as a metro / tube line.
##
## Semantically correct for a Wikipedia racing game: shows the journey
## from start article → every room visited → target article.
##
## Data wiring — all exact, verified against source files:
##   SettingsEvents.set_current_room  → same signal RaceManager uses to build
##                                      its own _local_visited_pages; we mirror it
##   RaceManager.race_started(target, start) → reset + store target/start
##   RaceManager.race_ended(peer_id, name)   → lock trail (race over)
##   RaceManager.race_cancelled              → clear everything
##   RaceManager.race_timer_updated(secs)    → drive the live elapsed timer
##
## Layout (top = goal, bottom = start):
##   ★  TARGET           pinned top, accent glow, pulses
##      ··· N earlier    clipped indicator
##   ●  Previous rooms   muted dots + labels
##   ◉  CURRENT ROOM     accent, large pulse ring, bold
##   ▶  START            green
##      [MM:SS · N hops] footer

const PANEL_W     : float = 240.0
const PANEL_H     : float = 260.0
const LINE_X      : float = 22.0
const DOT_R       : float = 5.0
const ROW_H_MAX   : float = 30.0
const MAX_VISIBLE : int   = 7
const LBL_OFF     : float = 13.0

var _player      : Node    = null
var _font        : Font    = null
var _time        : float   = 0.0

var _visited     : Array[String] = []
var _last_room   : String        = ""
var _target      : String        = ""
var _start       : String        = ""
var _race_active : bool          = false
var _elapsed_str : String        = "00:00"

var _panel_sb    : StyleBoxFlat = null
var _canvas      : Control      = null
var _footer_lbl  : Label        = null
var _footer_sb   : StyleBoxFlat = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font        = ThemeManager.get_reading_font()

	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left     = -(PANEL_W + 18.0)
	offset_top      = -(PANEL_H + 18.0)
	offset_right    = -18.0
	offset_bottom   = -18.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical   = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_sb = StyleBoxFlat.new()
	panel.add_theme_stylebox_override("panel", _panel_sb)
	add_child(panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   12)
	mc.add_theme_constant_override("margin_right",   8)
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
	_canvas.draw.connect(_draw_trail)
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

	_footer_lbl = Label.new()
	_footer_lbl.text                 = "No active race"
	_footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fw.add_child(_footer_lbl)

	SettingsEvents.set_current_room.connect(_on_room_changed)
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_ended.connect(_on_race_ended)
	RaceManager.race_cancelled.connect(_on_race_cancelled)
	RaceManager.race_timer_updated.connect(_on_timer_updated)

	# Catch a race already in progress when this node is created
	if RaceManager.is_race_active():
		_target      = RaceManager.get_target_article()
		_start       = RaceManager.get_start_article()
		_race_active = true

	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f): _font = f; _apply_theme())
	_apply_theme()


# ── Signal handlers ────────────────────────────────────────────────────────────

func _on_race_started(target_article: String, start_article: String) -> void:
	_target      = target_article
	_start       = start_article
	_race_active = true
	# Don't clear _visited — keep exploration trail as the race starting context.
	_last_room   = ""
	_elapsed_str = "00:00"
	_update_footer()


func _on_race_ended(_winner_peer_id: int, _winner_name: String) -> void:
	_race_active = false
	_update_footer()


func _on_race_cancelled() -> void:
	_race_active = false
	_visited.clear()
	_target      = ""
	_start       = ""
	_elapsed_str = "00:00"
	_update_footer()


func _on_timer_updated(elapsed_seconds: float) -> void:
	var secs     := int(elapsed_seconds)
	_elapsed_str  = "%02d:%02d" % [secs / 60, secs % 60]
	_update_footer()


func _on_room_changed(room: Variant) -> void:
	var r : String = str(room)
	if r == "" or r == "Lobby" or r == _last_room:
		return
	# Track all visits — not just during races — so the trail is always populated.
	_last_room = r
	if not _visited.has(r):
		_visited.append(r)
		_update_footer()


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

	if _footer_lbl:
		if _font: _footer_lbl.add_theme_font_override("font", _font)
		_footer_lbl.add_theme_font_size_override("font_size", 10)
		_footer_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _canvas: _canvas.queue_redraw()


func _update_footer() -> void:
	if not _footer_lbl: return
	if _race_active:
		var hops := _visited.size()
		_footer_lbl.text = "%s  ·  %d hop%s" % [
			_elapsed_str, hops, "s" if hops != 1 else ""]
	else:
		var n := _visited.size()
		_footer_lbl.text = "Exploring  ·  %d room%s" % [n, "s" if n != 1 else ""]


# ── Draw ───────────────────────────────────────────────────────────────────────

func _draw_trail() -> void:
	if not _canvas: return
	var accent := _accent()
	var green  := _green()
	var sz     := _canvas.size
	if sz == Vector2.ZERO: return

	if not _race_active or _visited.is_empty():
		if _font:
			_canvas.draw_string(_font,
				Vector2(LINE_X + 14.0, sz.y * 0.48),
				"Move around to\nsee your trail here",
				HORIZONTAL_ALIGNMENT_LEFT, sz.x - LINE_X - 20.0, 10,
				Color(accent, 0.38))
		return

	var clipped   : int    = maxi(0, _visited.size() - MAX_VISIBLE)
	var window    := _visited.slice(clipped)
	var has_clip  : bool   = clipped > 0
	var has_tgt   : bool   = _target != ""

	var total_rows : int = window.size() + (1 if has_clip else 0) + (1 if has_tgt else 0)
	var row_h     : float  = clampf(sz.y / maxf(total_rows, 1), 14.0, ROW_H_MAX)

	# Metro spine
	if total_rows >= 2:
		_canvas.draw_line(
			Vector2(LINE_X, row_h * 0.5),
			Vector2(LINE_X, sz.y - row_h * 0.5),
			Color(accent, 0.22), 3.0, true)

	var y : float = sz.y - row_h * 0.5

	# ── Window stations (newest at bottom) ─────────────────────────────────
	for i in range(window.size() - 1, -1, -1):
		var name    : String = window[i]
		var abs_i   : int    = clipped + i
		var is_cur  : bool   = (i == window.size() - 1)
		var is_strt : bool   = (abs_i == 0)

		var dot_col  : Color
		var txt_col  : Color
		var r2       : float = DOT_R

		if is_strt:
			dot_col = green
			txt_col = Color(green, 0.88)
		elif is_cur:
			dot_col = accent
			txt_col = ThemeManager.text_color
			r2      = DOT_R + 1.5
			var pulse := (sin(_time * 2.2) + 1.0) * 0.5
			_canvas.draw_circle(Vector2(LINE_X, y),
				r2 + 3.5 + pulse * 3.0,
				Color(accent, 0.13 + pulse * 0.08))
		else:
			dot_col = Color(accent, 0.45)
			txt_col = ThemeManager.subtext_color

		_canvas.draw_circle(Vector2(LINE_X, y), r2,       Color(1, 1, 1, 0.90))
		_canvas.draw_circle(Vector2(LINE_X, y), r2 - 1.5, dot_col)

		if _font:
			var lbl : String = name.replace("_", " ")
			if lbl.length() > 20: lbl = lbl.substr(0, 19) + "…"
			_canvas.draw_string(_font,
				Vector2(LINE_X + LBL_OFF, y + 4.5),
				lbl, HORIZONTAL_ALIGNMENT_LEFT,
				sz.x - LINE_X - LBL_OFF - 4.0,
				11 if (is_cur or is_strt) else 10,
				Color(txt_col, 0.92 if (is_cur or is_strt) else 0.72))

		y -= row_h

	# ── Clipped ellipsis ────────────────────────────────────────────────────
	if has_clip and _font:
		_canvas.draw_string(_font,
			Vector2(LINE_X + LBL_OFF, y + 4.5),
			"···  %d earlier" % clipped,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(ThemeManager.subtext_color, 0.48))
		y -= row_h

	# ── Target pinned at top ────────────────────────────────────────────────
	if has_tgt:
		var ty : float = row_h * 0.5
		var tp : float = (sin(_time * 1.5) + 1.0) * 0.5
		_canvas.draw_circle(Vector2(LINE_X, ty),
			DOT_R + 4.5 + tp * 3.0, Color(accent, 0.09 + tp * 0.07))
		_canvas.draw_circle(Vector2(LINE_X, ty), DOT_R + 1.0, Color(1, 1, 1, 0.95))
		_canvas.draw_circle(Vector2(LINE_X, ty), DOT_R - 0.5, accent)
		if _font:
			var tlbl : String = "★  " + _target.replace("_", " ")
			if tlbl.length() > 22: tlbl = tlbl.substr(0, 21) + "…"
			_canvas.draw_string(_font,
				Vector2(LINE_X + LBL_OFF, ty + 4.5),
				tlbl, HORIZONTAL_ALIGNMENT_LEFT,
				sz.x - LINE_X - LBL_OFF - 4.0, 11,
				Color(accent, 0.96))


# ── Helpers ────────────────────────────────────────────────────────────────────

func _accent() -> Color:
	return Color(0.30, 0.55, 1.00) if ThemeManager.is_dark_mode \
	     else Color(0.12, 0.32, 0.82)

func _green() -> Color:
	return Color(0.22, 0.72, 0.40) if ThemeManager.is_dark_mode \
	     else Color(0.05, 0.50, 0.20)

func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	d.color               = ThemeManager.border_color
	ThemeManager.dark_mode_changed.connect(func(_d): d.color = ThemeManager.border_color)
	return d

func init(player: Node) -> void:
	_player = player

func update_texture(_tex: Texture2D) -> void:
	pass

func set_zoom(_z: float) -> void:
	pass

func _process(delta: float) -> void:
	if not visible: return
	_time += delta
	if _canvas: _canvas.queue_redraw()
