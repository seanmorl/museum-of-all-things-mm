extends Control
## TournamentVictoryScreen — full-screen champion announcement at tournament end.
## Reuses the VictoryScreen aesthetic: gold starburst, serif typography.
## Auto-dismisses after 20s.

signal dismissed

var _serif_font:   Font           = null
var _backdrop:     ColorRect      = null
var _panel:        PanelContainer = null
var _panel_style:  StyleBoxFlat   = null
var _crown_canvas: Control        = null
var _champion_lbl: Label          = null
var _subtitle_lbl: Label          = null
var _podium_list:  VBoxContainer  = null
var _dismiss_btn:  Button         = null
var _timer_lbl:    Label          = null

var _burst_scale: float = 0.0
var _burst_alpha: float = 0.0
var _burst_time:  float = 0.0
var _dismiss_timer: float = 20.0
const AUTO_DISMISS: float = 20.0


func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	visible = false
	_build_ui()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	TournamentManager.tournament_ended.connect(_on_tournament_ended)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel_style = StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_panel.anchor_left   = 0.5; _panel.anchor_top    = 0.5
	_panel.anchor_right  = 0.5; _panel.anchor_bottom = 0.5
	_panel.offset_left   = -260; _panel.offset_top    = -240
	_panel.offset_right  =  260; _panel.offset_bottom =  240
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var mc := MarginContainer.new()
	for k in ["margin_left","margin_right","margin_top","margin_bottom"]:
		mc.add_theme_constant_override(k, 32)
	_panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	mc.add_child(vbox)

	# Crown starburst
	_crown_canvas = Control.new()
	_crown_canvas.custom_minimum_size = Vector2(0, 72)
	_crown_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crown_canvas.draw.connect(_draw_crown)
	vbox.add_child(_crown_canvas)

	# Champion name
	_champion_lbl = Label.new()
	_champion_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_champion_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_champion_lbl)

	# Wiki Races wordmark (compact)
	var logo_script := load("res://scenes/tournament/WikiRacesLogo.gd")
	if logo_script:
		var logo := Control.new()
		logo.set_script(logo_script)
		logo.custom_minimum_size = Vector2(0, 32)
		logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if logo.has_method("set") :
			logo.set("compact", true)
		vbox.add_child(logo)

	# Subtitle
	_subtitle_lbl = Label.new()
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_lbl.text = "Wiki Races Champion"
	vbox.add_child(_subtitle_lbl)

	vbox.add_child(_divider())

	# Podium (top 3)
	_podium_list = VBoxContainer.new()
	_podium_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_podium_list)

	vbox.add_child(_divider())

	# Timer + dismiss
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_timer_lbl = Label.new()
	_timer_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(_timer_lbl)

	_dismiss_btn = Button.new()
	_dismiss_btn.text = "Close"
	_dismiss_btn.pressed.connect(_dismiss)
	btn_row.add_child(_dismiss_btn)


func _divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _apply_theme() -> void:
	var dark: bool = ThemeManager.is_dark_mode
	var gold   := Color(1.00, 0.82, 0.25) if dark else Color(0.85, 0.62, 0.05)
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)

	if _backdrop:
		_backdrop.color = Color(0.04, 0.04, 0.07, 0.82) if dark \
			else Color(0.88, 0.90, 0.95, 0.85)

	if _panel_style:
		_panel_style.bg_color     = ThemeManager.bg_color
		_panel_style.border_color = Color(gold, 0.55)
		_panel_style.set_border_width_all(1)
		_panel_style.set_corner_radius_all(14)
		_panel_style.shadow_color  = Color(gold, 0.22)
		_panel_style.shadow_size   = 24
		_panel_style.shadow_offset = Vector2(0, 6)

	if _champion_lbl:
		if _serif_font: _champion_lbl.add_theme_font_override("font", _serif_font)
		_champion_lbl.add_theme_font_size_override("font_size", 36)
		_champion_lbl.add_theme_color_override("font_color", ThemeManager.text_color)

	if _subtitle_lbl:
		if _serif_font: _subtitle_lbl.add_theme_font_override("font", _serif_font)
		_subtitle_lbl.add_theme_font_size_override("font_size", 14)
		_subtitle_lbl.add_theme_color_override("font_color", Color(gold, 0.80))

	if _timer_lbl:
		if _serif_font: _timer_lbl.add_theme_font_override("font", _serif_font)
		_timer_lbl.add_theme_font_size_override("font_size", 12)
		_timer_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _crown_canvas: _crown_canvas.queue_redraw()


func _draw_crown() -> void:
	if not _crown_canvas or _burst_alpha < 0.005: return
	var dark: bool = ThemeManager.is_dark_mode
	var gold  := Color(1.00, 0.82, 0.25) if dark else Color(0.85, 0.62, 0.05)
	var cx: float = _crown_canvas.size.x * 0.5
	var cy: float = _crown_canvas.size.y * 0.65
	var r:  float = _crown_canvas.size.y * 0.38 * _burst_scale
	for i in 8:
		var angle: float     = float(i) / 8.0 * TAU + _burst_time * 0.10
		var len_outer: float = r * (1.0 + 0.25 * (1.0 if i % 2 == 0 else 0.5))
		var len_inner: float = r * 0.35
		var p0 := Vector2(cx + cos(angle)*len_inner, cy + sin(angle)*len_inner)
		var p1 := Vector2(cx + cos(angle)*len_outer, cy + sin(angle)*len_outer)
		_crown_canvas.draw_line(p0, p1, Color(gold, _burst_alpha*0.65),
			2.5 if i % 2 == 0 else 1.5, true)
	_crown_canvas.draw_arc(Vector2(cx,cy), r*0.55, 0.0, TAU, 48, Color(gold,_burst_alpha*0.25), 3.0, true)
	var sr_out: float = r*0.30; var sr_in: float = r*0.12
	var pts := PackedVector2Array()
	for i in 10:
		var a: float = float(i)/10.0*TAU - PI*0.5
		var sr: float = sr_out if i%2==0 else sr_in
		pts.append(Vector2(cx+cos(a)*sr, cy+sin(a)*sr))
	_crown_canvas.draw_colored_polygon(pts, Color(gold, _burst_alpha*0.90))


func _process(delta: float) -> void:
	if not visible: return
	_burst_time += delta
	if _crown_canvas: _crown_canvas.queue_redraw()
	_dismiss_timer -= delta
	if _dismiss_timer <= 0.0:
		_dismiss()
	elif _timer_lbl:
		_timer_lbl.text = "Closing in %ds…" % int(ceil(_dismiss_timer))


func _on_tournament_ended(champion: String, standings: Array) -> void:
	_champion_lbl.text = champion + "  ✦  wins!"
	_dismiss_timer = AUTO_DISMISS
	_build_podium(standings)
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_animate_in()


func _build_podium(standings: Array) -> void:
	for c in _podium_list.get_children(): c.queue_free()
	var dark: bool = ThemeManager.is_dark_mode
	var medals := [
		["🥇", Color(1.00, 0.82, 0.25) if dark else Color(0.75,0.52,0.00)],
		["🥈", Color(0.78, 0.88, 1.00) if dark else Color(0.35,0.55,0.85)],
		["🥉", Color(0.82, 0.62, 0.38)],
	]
	for i in min(standings.size(), 3):
		var s: Dictionary = standings[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_podium_list.add_child(row)
		var medal_lbl := Label.new()
		medal_lbl.text = medals[i][0]
		medal_lbl.add_theme_font_size_override("font_size", 18)
		row.add_child(medal_lbl)
		var name_lbl := Label.new()
		name_lbl.text = s.get("name", "?")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _serif_font: name_lbl.add_theme_font_override("font", _serif_font)
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.add_theme_color_override("font_color", medals[i][1])
		row.add_child(name_lbl)
		var stat_lbl := Label.new()
		stat_lbl.text = "%dpt  %dW" % [s.get("points",0), s.get("wins",0)]
		if _serif_font: stat_lbl.add_theme_font_override("font", _serif_font)
		stat_lbl.add_theme_font_size_override("font_size", 12)
		stat_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
		row.add_child(stat_lbl)


func _animate_in() -> void:
	if not _panel: return
	_panel.modulate.a  = 0.0
	_panel.scale       = Vector2(0.88, 0.88)
	_panel.pivot_offset = _panel.size * 0.5
	_burst_scale = 0.0; _burst_alpha = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "scale", Vector2(1.0,1.0), 0.50).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): _burst_scale = v; _burst_alpha = v,
		0.0, 1.0, 0.40).set_delay(0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _dismiss() -> void:
	visible = false
	_dismiss_timer = AUTO_DISMISS
	if _dismiss_btn: _dismiss_btn.text = "Close"
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	dismissed.emit()
