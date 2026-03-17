extends Control
## TournamentSetupMenu — host-only panel to configure and start a tournament.
## Attach to a Control node shown from the MultiplayerMenu or PauseMenu.
## Emits tournament_started when host confirms; dismissed on cancel.

signal tournament_started
signal cancelled

var _serif_font:   Font          = null
var _panel:        PanelContainer = null
var _panel_style:  StyleBoxFlat  = null

# Form refs
var _name_input:       LineEdit    = null
var _format_btn:       Button      = null
var _rounds_row:       HBoxContainer = null
var _rounds_spin:      HSlider     = null
var _rounds_value_lbl: Label       = null
var _firstton_row:     HBoxContainer = null
var _firstton_spin:    HSlider     = null
var _firstton_value_lbl: Label     = null
var _points_btn:       Button      = null
var _twitch_toggle:    CheckButton = null
var _start_btn:        Button      = null
var _player_count_lbl: Label       = null

var _format_idx:     int = 0   # TournamentManager.Format
var _points_idx:     int = 1   # TournamentManager.PointsMode (default PODIUM)

const FORMAT_LABELS := ["Fixed Rounds", "First to N Wins"]
const POINTS_LABELS := ["Win Only (1pt)", "Podium (3/2/1)", "Speed Bonus"]


func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	visible = false
	_build_ui()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Dim backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.color = Color(0, 0, 0, 0.55)

	# Centred panel
	_panel = PanelContainer.new()
	_panel_style = StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_panel.anchor_left   = 0.5; _panel.anchor_top    = 0.5
	_panel.anchor_right  = 0.5; _panel.anchor_bottom = 0.5
	_panel.offset_left   = -240; _panel.offset_top    = -260
	_panel.offset_right  =  240; _panel.offset_bottom =  260
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var mc := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		mc.add_theme_constant_override(side, 24)
	_panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	mc.add_child(vbox)

	# Title
	# Wiki Races logo
	var logo_script := load("res://scenes/tournament/WikiRacesLogo.gd")
	if logo_script:
		var logo := Control.new()
		logo.set_script(logo_script)
		logo.custom_minimum_size = Vector2(0, 80)
		logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(logo)
	else:
		var title := Label.new()
		title.text = "Wiki Races"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(title)
		_style_label(title, 22, true)

	vbox.add_child(_divider())

	# Player count
	_player_count_lbl = Label.new()
	_player_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_player_count_lbl)
	_style_label(_player_count_lbl, 12, false)

	# Tournament name
	vbox.add_child(_row_label("Series Name"))
	_name_input = LineEdit.new()
	_name_input.text = "MoAT Tournament"
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_name_input)

	# Format
	vbox.add_child(_row_label("Format"))
	_format_btn = _cycle_button(FORMAT_LABELS, _format_idx, func(i):
		_format_idx = i
		_update_format_visibility()
	)
	vbox.add_child(_format_btn)

	# Rounds (for ROUNDS mode)
	_rounds_row = _slider_row("Rounds:", 1, TournamentManager.MAX_ROUNDS,
		TournamentManager.DEFAULT_ROUNDS,
		func(v): _rounds_value_lbl.text = str(int(v)))
	_rounds_spin = _rounds_row.get_meta("slider")
	_rounds_value_lbl = _rounds_row.get_meta("val_lbl")
	vbox.add_child(_rounds_row)

	# First-to-N (for FIRST_TO_N mode)
	_firstton_row = _slider_row("First to N wins:", 1, 10,
		TournamentManager.DEFAULT_FIRST_TO_N,
		func(v): _firstton_value_lbl.text = str(int(v)))
	_firstton_spin = _firstton_row.get_meta("slider")
	_firstton_value_lbl = _firstton_row.get_meta("val_lbl")
	_firstton_row.visible = false
	vbox.add_child(_firstton_row)

	# Points mode
	vbox.add_child(_row_label("Points Mode"))
	_points_btn = _cycle_button(POINTS_LABELS, _points_idx, func(i):
		_points_idx = i
	)
	vbox.add_child(_points_btn)

	# Twitch overlay
	var twitch_row := HBoxContainer.new()
	twitch_row.add_theme_constant_override("separation", 8)
	vbox.add_child(twitch_row)
	var twitch_lbl := Label.new()
	twitch_lbl.text = "Twitch / OBS Overlay"
	twitch_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label(twitch_lbl, 13, false)
	twitch_row.add_child(twitch_lbl)
	_twitch_toggle = CheckButton.new()
	_twitch_toggle.button_pressed = true
	_twitch_toggle.focus_mode = Control.FOCUS_NONE
	twitch_row.add_child(_twitch_toggle)

	var twitch_hint := Label.new()
	twitch_hint.text = "OBS source → http://localhost:%d/overlay" % TournamentManager.TWITCH_PORT
	twitch_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(twitch_hint, 10, false)
	vbox.add_child(twitch_hint)

	vbox.add_child(_divider())

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	_start_btn = Button.new()
	_start_btn.text = "Start Tournament  →"
	_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_btn.pressed.connect(_on_start)
	btn_row.add_child(_start_btn)

	_update_player_count()


func _update_format_visibility() -> void:
	if _rounds_row:
		_rounds_row.visible = (_format_idx == TournamentManager.Format.ROUNDS)
	if _firstton_row:
		_firstton_row.visible = (_format_idx == TournamentManager.Format.FIRST_TO_N)
	# Reset slider values when switching formats to avoid confusion
	if _rounds_spin and _rounds_value_lbl:
		_rounds_spin.value = TournamentManager.DEFAULT_ROUNDS
		_rounds_value_lbl.text = str(TournamentManager.DEFAULT_ROUNDS)
	if _firstton_spin and _firstton_value_lbl:
		_firstton_spin.value = TournamentManager.DEFAULT_FIRST_TO_N
		_firstton_value_lbl.text = str(TournamentManager.DEFAULT_FIRST_TO_N)


func _update_player_count() -> void:
	if not _player_count_lbl:
		return
	var count := NetworkManager.get_player_list().size()
	_player_count_lbl.text = "%d player%s registered" % [count, "s" if count != 1 else ""]


# ── Helpers ───────────────────────────────────────────────────────────────────

func _row_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	_style_label(lbl, 11, false)
	return lbl


func _cycle_button(labels: Array, initial: int, on_change: Callable) -> Button:
	var btn := Button.new()
	btn.text = labels[initial] + "  ▶"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var idx := initial
	btn.pressed.connect(func():
		idx = (idx + 1) % labels.size()
		btn.text = labels[idx] + "  ▶"
		on_change.call(idx)
	)
	return btn


func _slider_row(label_text: String, min_v: float, max_v: float, default_v: float,
		on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 110
	_style_label(lbl, 12, false)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.value     = default_v
	slider.step      = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = str(int(default_v))
	val_lbl.custom_minimum_size.x = 24
	_style_label(val_lbl, 12, false)
	row.add_child(val_lbl)

	slider.value_changed.connect(func(v: float):
		val_lbl.text = str(int(v))
		on_change.call(v)
	)

	# Store slider and label in meta for later retrieval
	row.set_meta("slider", slider)
	row.set_meta("val_lbl", val_lbl)
	return row


func _divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.color = ThemeManager.border_color
	return d


func _style_label(lbl: Label, size: int, bold: bool) -> void:
	if _serif_font: lbl.add_theme_font_override("font", _serif_font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color",
		ThemeManager.text_color if bold else ThemeManager.subtext_color)


func _apply_theme() -> void:
	var dark: bool = ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	if _panel_style:
		_panel_style.bg_color     = ThemeManager.bg_color
		_panel_style.border_color = ThemeManager.border_color
		_panel_style.set_border_width_all(1)
		_panel_style.set_corner_radius_all(12)
		_panel_style.shadow_color  = Color(0, 0, 0, 0.35 if dark else 0.12)
		_panel_style.shadow_size   = 18
		_panel_style.shadow_offset = Vector2(0, 6)
	if _name_input:
		_name_input.add_theme_color_override("font_color", ThemeManager.text_color)
	if _start_btn and _serif_font:
		_start_btn.add_theme_font_override("font", _serif_font)
		_start_btn.add_theme_font_size_override("font_size", 15)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_start() -> void:
	if not NetworkManager.is_server():
		return
	var config := {
		"name":         _name_input.text.strip_edges() if _name_input else "Wiki Races",
		"format":       _format_idx,
		"points_mode":  _points_idx,
		"total_rounds": int(_rounds_spin.value) if _rounds_spin else TournamentManager.DEFAULT_ROUNDS,
		"first_to_n":   int(_firstton_spin.value) if _firstton_spin else TournamentManager.DEFAULT_FIRST_TO_N,
	}
	if _twitch_toggle and _twitch_toggle.button_pressed:
		TournamentManager.start_twitch_server()
	TournamentManager.host_start_tournament(config)
	visible = false
	tournament_started.emit()


func _on_cancel() -> void:
	visible = false
	cancelled.emit()


func open() -> void:
	_update_player_count()
	visible = true
	if _name_input:
		_name_input.grab_focus()
