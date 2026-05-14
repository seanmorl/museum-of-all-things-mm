extends Control
## TournamentBracketHUD — visual bracket showing per-round results.
## Toggled via Tab key during a tournament. Shows rounds as columns with
## players listed by finish position (1st, 2nd, 3rd, DNF).

var _serif_font:   Font           = null
var _panel:        PanelContainer = null
var _panel_style:  StyleBoxFlat   = null
var _title_label:  Label          = null
var _scroll:       ScrollContainer = null
var _bracket_hbox: HBoxContainer  = null
var _hint_label:   Label          = null
var _dark_mode_lambda: Callable = Callable()

const COL_WIDTH: int = 140
const ROW_HEIGHT: int = 28


func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	visible = false
	_build_ui()
	_apply_theme()
	_dark_mode_lambda = func(_d): _apply_theme()
	ThemeManager.dark_mode_changed.connect(_dark_mode_lambda)
	TournamentManager.tournament_started.connect(_on_tournament_started)
	TournamentManager.round_history_updated.connect(_on_history_updated)
	TournamentManager.tournament_ended.connect(_on_tournament_ended)
	TournamentManager.tournament_cancelled.connect(_on_cancelled)


func _exit_tree() -> void:
	if _dark_mode_lambda.is_valid():
		ThemeManager.dark_mode_changed.disconnect(_dark_mode_lambda)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Dim backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel_style = StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_panel.anchor_left   = 0.5; _panel.anchor_top    = 0.5
	_panel.anchor_right  = 0.5; _panel.anchor_bottom = 0.5
	_panel.offset_left   = -400; _panel.offset_top    = -280
	_panel.offset_right  =  400; _panel.offset_bottom =  280
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var mc := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		mc.add_theme_constant_override(side, 20)
	_panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	mc.add_child(vbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "Tournament Bracket"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	vbox.add_child(_divider())

	# Scrollable bracket area (horizontal for rounds, vertical for players)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.custom_minimum_size = Vector2(0, 300)
	vbox.add_child(_scroll)

	_bracket_hbox = HBoxContainer.new()
	_bracket_hbox.add_theme_constant_override("separation", 12)
	_scroll.add_child(_bracket_hbox)

	vbox.add_child(_divider())

	# Hint
	_hint_label = Label.new()
	_hint_label.text = "Tab to close  ·  Scroll to navigate"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_hint_label, 11, ThemeManager.subtext_color)
	vbox.add_child(_hint_label)


func _divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.color = ThemeManager.border_color
	return d


func _style_label(lbl: Label, size: int, color: Color) -> void:
	if _serif_font: lbl.add_theme_font_override("font", _serif_font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)


func _apply_theme() -> void:
	var dark: bool = ThemeManager.is_dark_mode
	var gold   := Color(1.00, 0.82, 0.25) if dark else Color(0.85, 0.62, 0.05)
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)

	if _panel_style:
		_panel_style.bg_color     = ThemeManager.bg_color
		_panel_style.border_color = Color(gold, 0.55)
		_panel_style.set_border_width_all(1)
		_panel_style.set_corner_radius_all(14)
		_panel_style.shadow_color  = Color(gold, 0.22)
		_panel_style.shadow_size   = 24
		_panel_style.shadow_offset = Vector2(0, 6)

	_style_label(_title_label, 18, ThemeManager.text_color)
	_style_label(_hint_label, 11, ThemeManager.subtext_color)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		hide()


func _build_bracket(history: Array) -> void:
	# Clear existing
	for c in _bracket_hbox.get_children():
		c.queue_free()

	if history.is_empty():
		var placeholder := Label.new()
		placeholder.text = "No rounds completed yet"
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bracket_hbox.add_child(placeholder)
		return

	var dark: bool = ThemeManager.is_dark_mode
	var gold   := Color(1.00, 0.82, 0.25) if dark else Color(0.75, 0.52, 0.00)
	var silver := Color(0.78, 0.88, 1.00) if dark else Color(0.35, 0.55, 0.85)
	var bronze := Color(0.82, 0.62, 0.38)
	var dnf_color := Color(0.6, 0.3, 0.3) if dark else Color(0.7, 0.3, 0.3)

	for round_data in history:
		var round_num: int = round_data.get("round_num", 0)
		var results: Array = round_data.get("results", [])

		# Sort by position
		results.sort_custom(func(a, b):
			return a.get("position", 99) < b.get("position", 99)
		)

		# Column for this round
		var col_vbox := VBoxContainer.new()
		col_vbox.custom_minimum_size.x = COL_WIDTH
		col_vbox.add_theme_constant_override("separation", 2)
		_bracket_hbox.add_child(col_vbox)

		# Round header
		var header := Label.new()
		header.text = "Round %d" % round_num
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_style_label(header, 13, ThemeManager.text_color)
		header.add_theme_font_size_override("font_size", 14)
		col_vbox.add_child(header)

		col_vbox.add_child(_divider())

		# Player rows
		for r in results:
			var pos: int = r.get("position", 0)
			var name: String = r.get("name", "?")
			var color: Color = r.get("color", Color.WHITE)
			var pts: int = r.get("points_earned", 0)

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			col_vbox.add_child(row)

			# Position badge
			var pos_lbl := Label.new()
			pos_lbl.custom_minimum_size.x = 24
			pos_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pos_lbl.add_theme_font_size_override("font_size", 11)

			if pos == 1:
				pos_lbl.text = "🥇"
				_style_label(pos_lbl, 11, gold)
			elif pos == 2:
				pos_lbl.text = "🥈"
				_style_label(pos_lbl, 11, silver)
			elif pos == 3:
				pos_lbl.text = "🥉"
				_style_label(pos_lbl, 11, bronze)
			else:
				pos_lbl.text = str(pos)
				_style_label(pos_lbl, 11, dnf_color)
			row.add_child(pos_lbl)

			# Player name with color dot
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(8, 8)
			dot.color = color
			row.add_child(dot)

			var name_lbl := Label.new()
			name_lbl.text = name
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_label(name_lbl, 11, ThemeManager.text_color)
			row.add_child(name_lbl)

			# Points earned
			var pts_lbl := Label.new()
			pts_lbl.text = "+%d" % pts if pts > 0 else "—"
			pts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			pts_lbl.custom_minimum_size.x = 28
			var pts_color: Color = gold if pos == 1 else ThemeManager.subtext_color
			_style_label(pts_lbl, 10, pts_color)
			row.add_child(pts_lbl)


func _on_tournament_started(_config: Dictionary) -> void:
	# Bracket shows empty until first round ends
	pass


func _on_history_updated(_history: Array) -> void:
	_build_bracket(_history)


func _on_tournament_ended(_champion: String, _standings: Array) -> void:
	# Keep bracket visible after tournament ends
	pass


func _on_cancelled() -> void:
	close_bracket()


func show_bracket() -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var history := TournamentManager.get_round_history()
	_build_bracket(history)
	_panel.grab_focus()


func close_bracket() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
