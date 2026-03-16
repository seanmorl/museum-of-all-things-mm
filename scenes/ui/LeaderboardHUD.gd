extends Control
## LeaderboardHUD — session leaderboard overlay, toggled with Tab (or bound action).
## All UI built in code. Reads from LeaderboardManager autoload.
## Add as a child of the in-game HUD layer (same parent as RaceHUD).
##
## Keybinding: add an InputMap action named "toggle_leaderboard" (default: Tab).
## The HUD registers a fallback Tab binding automatically if the action doesn't exist.

# ── Node refs ─────────────────────────────────────────────────────────────────
var _serif_font:    Font           = null
var _panel:         PanelContainer = null
var _panel_style:   StyleBoxFlat   = null
var _title_label:   Label          = null
var _list_vbox:     VBoxContainer  = null
var _empty_label:   Label          = null
var _hint_label:    Label          = null

const ACTION := "toggle_leaderboard"


func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	visible = false
	_ensure_input_action()
	_build_ui()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f): _serif_font = f; _apply_theme())
	LeaderboardManager.leaderboard_updated.connect(_refresh)
	set_process_unhandled_input(true)


func _ensure_input_action() -> void:
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.keycode = KEY_TAB
		InputMap.action_add_event(ACTION, ev)


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-rect mouse blocker when open
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Compact panel — top-centre
	_panel = PanelContainer.new()
	_panel_style = StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_panel.anchor_left   = 0.5
	_panel.anchor_top    = 0.0
	_panel.anchor_right  = 0.5
	_panel.anchor_bottom = 0.0
	_panel.offset_left   = -200
	_panel.offset_top    =  16
	_panel.offset_right  =  200
	_panel.offset_bottom =  16   # grows with content
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_END
	add_child(_panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   16)
	mc.add_theme_constant_override("margin_right",  16)
	mc.add_theme_constant_override("margin_top",    12)
	mc.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	mc.add_child(vbox)

	# Header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Session Leaderboard"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	# Clear button
	var clear_btn := Button.new()
	clear_btn.text = "✕"
	clear_btn.flat = true
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(func(): LeaderboardManager.clear())
	header.add_child(clear_btn)
	# Style clear btn inline
	clear_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

	vbox.add_child(_make_divider())

	# Column headers
	var col_header := _make_row_container()
	vbox.add_child(col_header)
	for txt in ["#", "Player", "Target", "Time"]:
		var lbl := Label.new()
		lbl.text = txt
		lbl.add_theme_font_size_override("font_size", 10)
		if txt == "Player" or txt == "Target":
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_header.add_child(lbl)

	vbox.add_child(_make_divider())

	# Scrollable list
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 0)
	vbox.add_child(scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 2)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_vbox)

	# Empty state
	_empty_label = Label.new()
	_empty_label.text = "No races yet this session."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = true
	_list_vbox.add_child(_empty_label)

	vbox.add_child(_make_divider())

	# Hint
	_hint_label = Label.new()
	_hint_label.text = "Tab  —  toggle"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_hint_label)


func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.color = Color(1, 1, 1, 0.12)
	return d


func _make_row_container() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	return h


# ── Theme ─────────────────────────────────────────────────────────────────────

func _apply_theme() -> void:
	var dark: bool = ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)

	if _panel_style:
		_panel_style.bg_color     = Color(ThemeManager.bg_color, 0.95)
		_panel_style.border_color = ThemeManager.border_color
		_panel_style.set_border_width_all(1)
		_panel_style.set_corner_radius_all(10)
		_panel_style.shadow_color  = Color(0, 0, 0, 0.28 if dark else 0.10)
		_panel_style.shadow_size   = 14
		_panel_style.shadow_offset = Vector2(0, 4)

	if _title_label:
		if _serif_font: _title_label.add_theme_font_override("font", _serif_font)
		_title_label.add_theme_font_size_override("font_size", 15)
		_title_label.add_theme_color_override("font_color", ThemeManager.text_color)

	if _empty_label:
		if _serif_font: _empty_label.add_theme_font_override("font", _serif_font)
		_empty_label.add_theme_font_size_override("font_size", 12)
		_empty_label.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _hint_label:
		if _serif_font: _hint_label.add_theme_font_override("font", _serif_font)
		_hint_label.add_theme_font_size_override("font_size", 11)
		_hint_label.add_theme_color_override("font_color", ThemeManager.subtext_color)

	# Refresh dividers
	if _panel:
		for cr in _panel.find_children("*", "ColorRect", true, false):
			if cr is ColorRect and cr.custom_minimum_size.y == 1:
				cr.color = ThemeManager.border_color

	_restyle_rows()


func _restyle_rows() -> void:
	if not _list_vbox: return
	var dark: bool = ThemeManager.is_dark_mode
	var gold := Color(1.00, 0.82, 0.25) if dark else Color(0.75, 0.52, 0.00)
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	var i := 0
	for child in _list_vbox.get_children():
		if child == _empty_label: continue
		if child is HBoxContainer:
			for lbl in child.get_children():
				if lbl is Label:
					var role: String = lbl.get_meta("role", "")
					match role:
						"rank_1": lbl.add_theme_color_override("font_color", gold)
						"winner": lbl.add_theme_color_override("font_color", ThemeManager.text_color)
						"target": lbl.add_theme_color_override("font_color", accent)
						_:        lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
			i += 1


# ── Data refresh ──────────────────────────────────────────────────────────────

func _refresh() -> void:
	if not _list_vbox: return
	for c in _list_vbox.get_children():
		if c != _empty_label: c.queue_free()

	var entries := LeaderboardManager.get_entries()
	_empty_label.visible = entries.is_empty()
	if entries.is_empty(): return

	var dark: bool  = ThemeManager.is_dark_mode
	var gold        := Color(1.00, 0.82, 0.25) if dark else Color(0.75, 0.52, 0.00)
	var accent      := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	const MAX: int  = 20

	for i in range(min(entries.size(), MAX)):
		var e:        Dictionary = entries[i]
		var is_top:   bool       = i == 0
		var row := _make_row_container()
		_list_vbox.add_child(row)

		# Rank
		var rank_lbl := _make_cell(str(i + 1) + ".", 11)
		rank_lbl.custom_minimum_size.x = 22
		rank_lbl.set_meta("role", "rank_1" if is_top else "rank")
		rank_lbl.add_theme_color_override("font_color", gold if is_top else ThemeManager.subtext_color)
		row.add_child(rank_lbl)

		# Winner name
		var name_lbl := _make_cell(e.get("winner_name", "?"), 12)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.set_meta("role", "winner")
		name_lbl.add_theme_color_override("font_color", ThemeManager.text_color)
		if is_top and _serif_font:
			# Bold the top entry via a slightly larger size
			name_lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(name_lbl)

		# Target article (truncated)
		var target: String = e.get("target_article", "")
		if target.length() > 22: target = target.substr(0, 20) + "…"
		var tgt_lbl := _make_cell(target, 11)
		tgt_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tgt_lbl.set_meta("role", "target")
		tgt_lbl.add_theme_color_override("font_color", accent)
		row.add_child(tgt_lbl)

		# Time
		var time_lbl := _make_cell(e.get("time_string", "--:--"), 12)
		time_lbl.custom_minimum_size.x = 44
		time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		time_lbl.set_meta("role", "time")
		time_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
		row.add_child(time_lbl)

		# Animate new top entry
		if is_top and visible:
			row.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(row, "modulate:a", 1.0, 0.30) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Size the scroll area to show up to 8 rows before scrolling
	var row_h: int = 20
	var shown: int = min(entries.size(), MAX)
	var scroll: ScrollContainer = _list_vbox.get_parent() as ScrollContainer
	if scroll:
		scroll.custom_minimum_size.y = int(min(shown, 8)) * row_h


func _make_cell(text: String, size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	if _serif_font: lbl.add_theme_font_override("font", _serif_font)
	lbl.clip_text = true
	return lbl


# ── Toggle / animation ────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		_hide()
	else:
		_show()


func _show() -> void:
	_refresh()
	visible = true
	if _panel:
		_panel.modulate.a  = 0.0
		_panel.position.y -= 8.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_panel, "position:y", _panel.position.y + 8.0, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide() -> void:
	if not _panel:
		visible = false
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "position:y", _panel.position.y - 6.0, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		visible = false
		if _panel: _panel.position.y += 6.0
		if _panel: _panel.modulate.a = 1.0
	)
