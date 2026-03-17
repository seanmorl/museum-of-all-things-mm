extends Control
## TournamentHUD — compact in-game standings panel shown during a tournament.
## Anchors top-centre. Shows round progress and live standings.
## Slides in when tournament starts, updates live, slides out when done.

var _serif_font:    Font           = null
var _panel:         PanelContainer = null
var _panel_style:   StyleBoxFlat   = null
var _round_label:   Label          = null
var _name_label:    Label          = null   # tournament name sub-line
var _list_vbox:     VBoxContainer  = null
var _between_label: Label          = null


func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	visible = false
	_build_ui()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	TournamentManager.tournament_started.connect(_on_tournament_started)
	TournamentManager.tournament_round_started.connect(_on_round_started)
	TournamentManager.tournament_round_ended.connect(_on_round_ended)
	TournamentManager.standings_updated.connect(_on_standings_updated)
	TournamentManager.tournament_ended.connect(_on_tournament_ended)
	TournamentManager.tournament_cancelled.connect(_on_cancelled)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel_style = StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _panel_style)
	# Top-centre anchor
	_panel.anchor_left   = 0.5; _panel.anchor_top    = 0.0
	_panel.anchor_right  = 0.5; _panel.anchor_bottom = 0.0
	_panel.offset_left   = -170; _panel.offset_top   = 12
	_panel.offset_right  =  170; _panel.offset_bottom = 12
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_END
	add_child(_panel)

	var mc := MarginContainer.new()
	for k in ["margin_left","margin_right","margin_top","margin_bottom"]:
		mc.add_theme_constant_override(k, 10)
	_panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	mc.add_child(vbox)

	# Header row: compact logo + round
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	var logo_script := load("res://scenes/tournament/WikiRacesLogo.gd")
	if logo_script:
		var logo := Control.new()
		logo.set_script(logo_script)
		logo.custom_minimum_size = Vector2(80, 22)
		logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if logo.has_method("set"):
			logo.set("compact", true)
		header.add_child(logo)
	else:
		_name_label = Label.new()
		_name_label.text = "Wiki Races"
		_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(_name_label)

	_round_label = Label.new()
	_round_label.text = "R1/5"
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_round_label)

	vbox.add_child(_make_divider())

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 2)
	vbox.add_child(_list_vbox)

	_between_label = Label.new()
	_between_label.text = "Next round starting…"
	_between_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_between_label.visible = false
	vbox.add_child(_between_label)


func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _apply_theme() -> void:
	var dark: bool = ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	if _panel_style:
		_panel_style.bg_color     = Color(ThemeManager.bg_color, 0.93)
		_panel_style.border_color = Color(accent, 0.50)
		_panel_style.set_border_width_all(1)
		_panel_style.set_corner_radius_all(10)
		_panel_style.shadow_color  = Color(0, 0, 0, 0.28 if dark else 0.10)
		_panel_style.shadow_size   = 12
		_panel_style.shadow_offset = Vector2(0, 3)
	_style_lbl(_name_label, 12, ThemeManager.subtext_color)
	_style_lbl(_round_label, 13, ThemeManager.text_color)
	_style_lbl(_between_label, 11, ThemeManager.subtext_color)
	if _panel:
		for cr in _panel.find_children("*", "ColorRect", true, false):
			if cr is ColorRect and cr.custom_minimum_size.y == 1:
				cr.color = ThemeManager.border_color
	_refresh_list_colors()


func _style_lbl(lbl: Label, size: int, color: Color) -> void:
	if not lbl: return
	if _serif_font: lbl.add_theme_font_override("font", _serif_font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)


func _refresh_list_colors() -> void:
	if not _list_vbox: return
	var dark: bool = ThemeManager.is_dark_mode
	var gold   := Color(1.00, 0.82, 0.25) if dark else Color(0.75, 0.52, 0.00)
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	for row in _list_vbox.get_children():
		if not row is HBoxContainer: continue
		var rank: int = row.get_meta("rank", 99)
		var col: Color
		if rank == 1:
			col = gold
		elif rank == 2:
			col = Color(0.78, 0.88, 1.00) if dark else Color(0.25, 0.45, 0.75)
		elif rank == 3:
			col = Color(0.82, 0.62, 0.38)
		else:
			col = ThemeManager.subtext_color
		for lbl in row.get_children():
			if lbl is Label:
				lbl.add_theme_color_override("font_color", col)


func _rebuild_list(standings: Array) -> void:
	if not _list_vbox: return
	for c in _list_vbox.get_children(): c.queue_free()

	var dark: bool = ThemeManager.is_dark_mode
	var gold   := Color(1.00, 0.82, 0.25) if dark else Color(0.75, 0.52, 0.00)
	var local_id := NetworkManager.get_unique_id()
	const MAX: int = 8

	for i in min(standings.size(), MAX):
		var s: Dictionary = standings[i]
		var rank: int = i + 1
		var is_local: bool = s.get("peer_id", -1) == local_id
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.set_meta("rank", rank)
		_list_vbox.add_child(row)

		var rank_lbl := Label.new()
		rank_lbl.text = str(rank) + "."
		rank_lbl.custom_minimum_size.x = 18
		_style_lbl(rank_lbl, 11, ThemeManager.subtext_color)
		row.add_child(rank_lbl)

		var name_lbl := Label.new()
		var display: String = s.get("name", "?")
		if is_local: display += " ◀"
		name_lbl.text = display
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_lbl(name_lbl, 12, gold if rank == 1 else ThemeManager.text_color)
		row.add_child(name_lbl)

		var pts_lbl := Label.new()
		pts_lbl.text = str(s.get("points", 0)) + "pt"
		_style_lbl(pts_lbl, 11, ThemeManager.subtext_color)
		row.add_child(pts_lbl)

		# New entry animation
		row.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(row, "modulate:a", 1.0, 0.20) \
			.set_delay(i * 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_tournament_started(config: Dictionary) -> void:
	if _name_label:
		_name_label.text = config.get("name", "Wiki Races")
	_update_round_label()
	if _between_label: _between_label.visible = false
	_slide_in()


func _on_round_started(round_num: int, total: int) -> void:
	if _round_label:
		_round_label.text = "R%d/%d" % [round_num, total]
	if _between_label: _between_label.visible = false


func _on_round_ended(_round_num: int, _winner: String, standings: Array) -> void:
	_rebuild_list(standings)
	if _between_label:
		_between_label.visible = true
		_between_label.text = "Next round soon…"
	_pulse()


func _on_standings_updated(standings: Array) -> void:
	_rebuild_list(standings)


func _on_tournament_ended(_champion: String, standings: Array) -> void:
	_rebuild_list(standings)
	if _between_label:
		_between_label.visible = false
	await get_tree().create_timer(12.0).timeout
	_slide_out()


func _on_cancelled() -> void:
	_slide_out()


func _update_round_label() -> void:
	if _round_label:
		_round_label.text = "R%d/%d" % [
			TournamentManager.get_current_round(),
			TournamentManager.get_total_rounds()
		]


func _pulse() -> void:
	if not _panel: return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2(1.03, 1.03), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func _slide_in() -> void:
	visible    = true
	modulate.a = 0.0
	if _panel: _panel.position.y -= 10.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _panel:
		tw.tween_property(_panel, "position:y", _panel.position.y + 10.0, 0.32) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _slide_out() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _panel:
		tw.tween_property(_panel, "position:y", _panel.position.y - 8.0, 0.22)
	tw.chain().tween_callback(func():
		visible    = false
		modulate.a = 1.0
		if _panel: _panel.position.y += 8.0
	)
