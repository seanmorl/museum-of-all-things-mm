extends Control
## VictoryScreen — elegant full-screen victory overlay.
## All UI built in code. Connects directly to RaceManager.race_ended.
## Replaces the old tscn-node-dependent version.

signal continue_pressed

# ── Node refs ─────────────────────────────────────────────────────────────────
var _serif_font:     Font            = null
var _backdrop:       ColorRect       = null
var _panel:          PanelContainer  = null
var _panel_style:    StyleBoxFlat    = null
var _crown_canvas:   Control         = null
var _winner_label:   Label           = null
var _time_label:     Label           = null
var _path_label:     Label           = null
var _path_list:      VBoxContainer   = null
var _continue_btn:   Button          = null
var _path_scroll:    ScrollContainer = null
var _dismiss_timer:  float           = 0.0

# ── Starburst draw state ──────────────────────────────────────────────────────
var _burst_scale:    float           = 0.0
var _burst_alpha:    float           = 0.0
var _burst_time:     float           = 0.0

const AUTO_DISMISS: float = 12.0


func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	visible = false
	_build_ui()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f): _serif_font = f; _apply_theme())
	RaceManager.race_ended.connect(_on_race_ended)


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel_style = StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_panel.anchor_left   = 0.5
	_panel.anchor_top    = 0.5
	_panel.anchor_right  = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left   = -240
	_panel.offset_top    = -200
	_panel.offset_right  =  240
	_panel.offset_bottom =  200
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   36)
	mc.add_theme_constant_override("margin_right",  36)
	mc.add_theme_constant_override("margin_top",    28)
	mc.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	mc.add_child(vbox)

	_crown_canvas = Control.new()
	_crown_canvas.custom_minimum_size = Vector2(0, 64)
	_crown_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crown_canvas.draw.connect(_draw_crown)
	vbox.add_child(_crown_canvas)

	_winner_label = Label.new()
	_winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_winner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_winner_label)

	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_time_label)

	vbox.add_child(_make_divider())

	_path_label = Label.new()
	_path_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_path_label)

	_path_scroll = ScrollContainer.new()
	_path_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_path_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_path_scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	_path_scroll.custom_minimum_size    = Vector2(0, 60)   # at least one entry tall
	_path_scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_path_scroll)

	_path_list = VBoxContainer.new()
	_path_list.add_theme_constant_override("separation", 1)
	_path_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_scroll.add_child(_path_list)

	vbox.add_child(_make_divider())

	_continue_btn = Button.new()
	_continue_btn.text = "Continue  →"
	_continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_btn.custom_minimum_size = Vector2(160, 0)
	_continue_btn.pressed.connect(_on_continue_pressed)
	vbox.add_child(_continue_btn)


func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.color = Color(1, 1, 1, 0.15)
	return d


func _apply_theme() -> void:
	var dark: bool = ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	var gold   := Color(1.00, 0.82, 0.25) if dark else Color(0.85, 0.62, 0.05)

	if _backdrop:
		_backdrop.color = Color(0.04, 0.04, 0.07, 0.78) if dark \
			else Color(0.88, 0.90, 0.95, 0.82)

	if _panel_style:
		_panel_style.bg_color     = ThemeManager.bg_color
		_panel_style.border_color = Color(gold, 0.55)
		_panel_style.set_border_width_all(1)
		_panel_style.set_corner_radius_all(14)
		_panel_style.shadow_color  = Color(gold, 0.22)
		_panel_style.shadow_size   = 24
		_panel_style.shadow_offset = Vector2(0, 6)

	if _winner_label:
		if _serif_font: _winner_label.add_theme_font_override("font", _serif_font)
		_winner_label.add_theme_font_size_override("font_size", 32)
		_winner_label.add_theme_color_override("font_color", ThemeManager.text_color)

	if _time_label:
		if _serif_font: _time_label.add_theme_font_override("font", _serif_font)
		_time_label.add_theme_font_size_override("font_size", 15)
		_time_label.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _path_label:
		if _serif_font: _path_label.add_theme_font_override("font", _serif_font)
		_path_label.add_theme_font_size_override("font_size", 13)
		_path_label.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _continue_btn:
		if _serif_font: _continue_btn.add_theme_font_override("font", _serif_font)
		_continue_btn.add_theme_font_size_override("font_size", 16)
		# Light mode: dark text on transparent → readable against white panel
		# Dark mode: light text on transparent → readable against dark panel
		var btn_text_color := ThemeManager.text_color
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			_continue_btn.add_theme_color_override(state, btn_text_color)
		# Normal — transparent with a border matching the panel border
		var sn := StyleBoxFlat.new()
		sn.bg_color = Color(0, 0, 0, 0)
		sn.border_color = ThemeManager.border_color
		sn.set_border_width_all(1)
		sn.set_corner_radius_all(6)
		sn.content_margin_left = 20; sn.content_margin_right  = 20
		sn.content_margin_top  = 10; sn.content_margin_bottom = 10
		_continue_btn.add_theme_stylebox_override("normal", sn)
		# Hover — subtle accent tint so the button is clearly interactive
		var sh := sn.duplicate() as StyleBoxFlat
		sh.bg_color = Color(accent, 0.10)
		sh.border_color = accent
		_continue_btn.add_theme_stylebox_override("hover", sh)
		# Pressed
		var sp := sh.duplicate() as StyleBoxFlat
		sp.bg_color = Color(accent, 0.20)
		_continue_btn.add_theme_stylebox_override("pressed", sp)
		# Focus
		var sf := sh.duplicate() as StyleBoxFlat
		sf.set_border_width_all(2)
		_continue_btn.add_theme_stylebox_override("focus", sf)

	if _panel:
		for cr in _panel.find_children("*", "ColorRect", true, false):
			if cr is ColorRect and cr.custom_minimum_size.y == 1:
				cr.color = ThemeManager.border_color

	if _crown_canvas:
		_crown_canvas.queue_redraw()


func _draw_crown() -> void:
	if not _crown_canvas or _burst_alpha < 0.005:
		return
	var dark: bool = ThemeManager.is_dark_mode
	var gold  := Color(1.00, 0.82, 0.25) if dark else Color(0.85, 0.62, 0.05)
	var cx:   float = _crown_canvas.size.x * 0.5
	var cy:   float = _crown_canvas.size.y * 0.65
	var r:    float = _crown_canvas.size.y * 0.35 * _burst_scale

	for i in 8:
		var angle:     float = float(i) / 8.0 * TAU + _burst_time * 0.12
		var len_outer: float = r * (1.0 + 0.25 * (1.0 if i % 2 == 0 else 0.5))
		var len_inner: float = r * 0.35
		var p0 := Vector2(cx + cos(angle) * len_inner, cy + sin(angle) * len_inner)
		var p1 := Vector2(cx + cos(angle) * len_outer, cy + sin(angle) * len_outer)
		_crown_canvas.draw_line(p0, p1, Color(gold, _burst_alpha * 0.6),
			2.0 if i % 2 == 0 else 1.2, true)

	_crown_canvas.draw_arc(Vector2(cx, cy), r * 0.55, 0.0, TAU, 48,
		Color(gold, _burst_alpha * 0.25), 3.0, true)
	_crown_canvas.draw_arc(Vector2(cx, cy), r * 0.90, 0.0, TAU, 48,
		Color(gold, _burst_alpha * 0.12), 1.5, true)

	var star_r_out: float = r * 0.28
	var star_r_in:  float = r * 0.11
	var star_pts := PackedVector2Array()
	for i in 10:
		var a:  float = float(i) / 10.0 * TAU - PI * 0.5
		var sr: float = star_r_out if i % 2 == 0 else star_r_in
		star_pts.append(Vector2(cx + cos(a) * sr, cy + sin(a) * sr))
	_crown_canvas.draw_colored_polygon(star_pts, Color(gold, _burst_alpha * 0.9))


func _process(delta: float) -> void:
	if not visible:
		return
	_burst_time += delta
	if _crown_canvas:
		_crown_canvas.queue_redraw()
	if _dismiss_timer > 0.0:
		_dismiss_timer -= delta
		if _dismiss_timer <= 0.0:
			_on_continue_pressed()
		elif _continue_btn:
			_continue_btn.text = "Continue  →  (%ds)" % int(ceil(_dismiss_timer))


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_accept"):
		_on_continue_pressed()


func _animate_in() -> void:
	if not _panel:
		return
	_panel.modulate.a   = 0.0
	_panel.scale        = Vector2(0.88, 0.88)
	_panel.pivot_offset = _panel.size * 0.5
	_burst_scale = 0.0
	_burst_alpha = 0.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.50) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): _burst_scale = v; _burst_alpha = v,
		0.0, 1.0, 0.40).set_delay(0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	for lbl: Label in [_winner_label, _time_label, _path_label]:
		if lbl:
			lbl.modulate.a = 0.0
	var delay := 0.30
	for lbl: Label in [_winner_label, _time_label, _path_label]:
		if lbl:
			tw.tween_property(lbl, "modulate:a", 1.0, 0.30).set_delay(delay)
			delay += 0.10

	if _continue_btn:
		_continue_btn.modulate.a = 0.0
		tw.tween_property(_continue_btn, "modulate:a", 1.0, 0.30).set_delay(0.70)

	tw.chain().tween_callback(func(): if is_instance_valid(_continue_btn): _continue_btn.grab_focus())


func _on_race_ended(winner_peer_id: int, winner_name: String) -> void:
	var display: String = winner_name
	if winner_peer_id == NetworkManager.get_unique_id():
		display += "  ✦"
	_winner_label.text = display + " wins!"
	_time_label.text   = RaceManager.get_elapsed_time_string()

	var path: Array[String] = RaceManager.get_winner_path()
	_path_label.text = "via %d room%s" % [path.size(), "s" if path.size() != 1 else ""]
	_populate_path(path)

	_dismiss_timer = AUTO_DISMISS
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_animate_in()


func _populate_path(path: Array[String]) -> void:
	for c in _path_list.get_children():
		c.queue_free()

	var dark:   bool  = ThemeManager.is_dark_mode
	var accent        := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	var gold          := Color(1.00, 0.82, 0.25) if dark else Color(0.85, 0.62, 0.05)
	var target: String = RaceManager.get_target_article()
	const MAX: int     = 12

	for i in min(path.size(), MAX):
		var page:     String = path[i]
		var is_first: bool   = i == 0
		var is_tgt:   bool   = page == target
		var lbl               := Label.new()
		lbl.text = ("★ " if is_tgt else ("▶ " if is_first else "  ")) + page
		lbl.add_theme_font_size_override("font_size", 11)
		if _serif_font: lbl.add_theme_font_override("font", _serif_font)
		lbl.add_theme_color_override("font_color",
			accent if is_tgt else (gold if is_first else ThemeManager.subtext_color))
		_path_list.add_child(lbl)

	if path.size() > MAX:
		var more := Label.new()
		more.text = "  … (%d more)" % (path.size() - MAX)
		more.add_theme_font_size_override("font_size", 10)
		more.add_theme_color_override("font_color", ThemeManager.subtext_color)
		_path_list.add_child(more)

	# Smooth scroll to show the target (last entries) after layout settles
	_scroll_path_to_bottom()


func _scroll_path_to_bottom() -> void:
	if not _path_scroll:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var bar := _path_scroll.get_v_scroll_bar()
	if bar.max_value <= bar.page:
		return
	var target_val: float = bar.max_value - bar.page
	var tw := create_tween()
	tw.tween_property(_path_scroll, "scroll_vertical",
		int(target_val), 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _on_continue_pressed() -> void:
	visible = false
	_dismiss_timer = 0.0
	if _continue_btn:
		_continue_btn.text = "Continue  →"
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	continue_pressed.emit()
