extends Control

signal resume
signal settings
signal vr_controls
signal return_to_lobby
signal start_race

const _FONT_PATH := "res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf"

# ── Node references (matched to actual PauseMenu.tscn structure) ──────────────
@onready var vbox             = get_node_or_null("MarginContainer/CenterContainer/VBoxContainer/PausePanel/PauseContent")
@onready var race_button      = get_node_or_null("MarginContainer/CenterContainer/VBoxContainer/PausePanel/PauseContent/Race")
@onready var cancel_race_button = get_node_or_null("MarginContainer/CenterContainer/VBoxContainer/PausePanel/PauseContent/CancelRace")
@onready var _dark_mode_btn   = get_node_or_null("MarginContainer/CenterContainer/VBoxContainer/PausePanel/PauseContent/DarkMode")
@onready var _panel           = get_node_or_null("MarginContainer/CenterContainer/VBoxContainer")
@onready var _pause_panel     = get_node_or_null("MarginContainer/CenterContainer/VBoxContainer/PausePanel")
# The confirmation panel shown when the player presses Quit.
@onready var _quit_container  = get_node_or_null("MarginContainer/CenterContainer/QuitContainer")

var _serif_font: Font = null
var _panel_style: StyleBoxFlat = null
var _closing: bool = false
var _race_control_override: bool = false
var current_room: String = "Lobby"

# Thin 1px ColorRect dividers parented to _pause_panel so they don't affect
# VBoxContainer spacing at all.
var _dividers: Array[Dictionary] = []

# Fullscreen loading overlay shown while fetching race articles.
var _loading_overlay: Control = null

# Group leaders: a divider line is placed just above each of these nodes.
# Names matched to the actual tscn — "Lobby" is the Return to Lobby button,
# "AskQuit" is the Quit button visible in the pause panel.
const _GROUP_LEADERS := ["Lobby", "Settings", "DarkMode"]

func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()

	# Hide the spacer Labels that cause excessive gaps between button groups.
	# These are empty Labels used as crude spacers in the scene; we replace
	# them visually with thin divider lines instead.
	if vbox:
		for child in vbox.get_children():
			if child is Label and child.text == "":
				child.visible = false
				child.custom_minimum_size = Vector2.ZERO

	# Ensure quit confirmation panel starts hidden.
	if _quit_container:
		_quit_container.visible = false

	SettingsEvents.set_current_room.connect(set_current_room)
	UIEvents.ui_cancel_pressed.connect(ui_cancel_pressed)
	MultiplayerEvents.multiplayer_started.connect(_update_race_button_visibility)
	MultiplayerEvents.multiplayer_ended.connect(_update_race_button_visibility)
	RaceManager.race_started.connect(_on_race_state_changed)
	RaceManager.race_ended.connect(_on_race_state_changed)
	RaceManager.race_cancelled.connect(_on_race_state_changed)

	_apply_theme()
	ThemeManager.dark_mode_changed.connect(_on_dark_mode_changed)
	ThemeManager.reading_font_changed.connect(func(f): _serif_font = f; _apply_theme())

	if Platform.is_web():
		var aq = get_node_or_null("%AskQuit")
		if aq: aq.visible = false

	# Dark mode button label — do NOT connect pressed here; the scene already
	# wires it to _on_dark_mode_pressed (see tscn connections).
	if _dark_mode_btn:
		_dark_mode_btn.text = "☾  Dark Mode" if not ThemeManager.is_dark_mode else "☀  Light Mode"
		_dark_mode_btn.disabled = false

	_update_race_button_visibility()
	call_deferred("_build_dividers")
	# Fix z-order: reparent QuitContainer to the root Control so it always
	# renders on top of the pause panel, regardless of scene tree order.
	if _quit_container:
		var qc_parent := _quit_container.get_parent()
		if qc_parent and qc_parent != self:
			qc_parent.remove_child(_quit_container)
			add_child(_quit_container)
			# Make it fill the whole PauseMenu Control
			_quit_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_loading_overlay()

func _on_visibility_changed() -> void:
	if not visible:
		hide_loading_overlay()
	if visible and is_inside_tree():
		_closing = false
		hide_loading_overlay()
		# Always hide the quit confirmation when the pause menu re-opens.
		if _quit_container:
			_quit_container.visible = false
		if vbox:
			var res_btn = vbox.get_node_or_null("Resume")
			if res_btn:
				res_btn.call_deferred("grab_focus")
		_update_race_button_visibility()
		_animate_in()

# ── Dividers ──────────────────────────────────────────────────────────────────

func _build_dividers() -> void:
	if not vbox or not _pause_panel:
		return
	for leader_name in _GROUP_LEADERS:
		var leader := vbox.get_node_or_null(leader_name)
		if not leader:
			continue
		var line := ColorRect.new()
		line.name = "Div_" + leader_name
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.color = ThemeManager.border_color
		_pause_panel.add_child(line)
		_dividers.append({"leader": leader, "line": line})
	_update_dividers()

func _update_dividers() -> void:
	if not _pause_panel:
		return
	for entry in _dividers:
		var leader: Control = entry["leader"]
		var line: ColorRect  = entry["line"]
		if not is_instance_valid(leader) or not is_instance_valid(line):
			continue
		if not leader.visible:
			line.visible = false
			continue
		line.visible = true
		var y: float = leader.global_position.y - _pause_panel.global_position.y - 7.0
		line.position = Vector2(16.0, y)
		line.size     = Vector2(_pause_panel.size.x - 32.0, 1.0)

func _process(_delta: float) -> void:
	if visible and not _dividers.is_empty():
		_update_dividers()

# ── Loading overlay ───────────────────────────────────────────────────────────

func _build_loading_overlay() -> void:
	# Semi-transparent full-screen backdrop with a centred spinner label.
	# Parented to self so it's always drawn above everything else.
	_loading_overlay = Control.new()
	_loading_overlay.name = "LoadingOverlay"
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.visible = false
	add_child(_loading_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.55)
	_loading_overlay.add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.add_child(centre)

	var lbl := Label.new()
	lbl.text = "Fetching articles…"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _serif_font:
		lbl.add_theme_font_override("font", _serif_font)
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	centre.add_child(lbl)

func show_loading_overlay() -> void:
	if _loading_overlay:
		_loading_overlay.visible = true

func hide_loading_overlay() -> void:
	if _loading_overlay:
		_loading_overlay.visible = false

# ── Theme ─────────────────────────────────────────────────────────────────────

func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode

	if _pause_panel:
		if not _panel_style:
			var orig = _pause_panel.get_theme_stylebox("panel")
			_panel_style = orig.duplicate() if orig is StyleBoxFlat else StyleBoxFlat.new()
			_pause_panel.add_theme_stylebox_override("panel", _panel_style)

		_panel_style.bg_color     = ThemeManager.bg_color
		_panel_style.border_color = ThemeManager.border_color
		for side in [0, 1, 2, 3]:
			_panel_style.set("border_width_" + ["left", "right", "top", "bottom"][side], 1)
		for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
			_panel_style.set("corner_radius_" + corner, 10)
		_panel_style.shadow_color  = Color(0, 0, 0, 0.35 if dark else 0.12)
		_panel_style.shadow_size   = 16
		_panel_style.shadow_offset = Vector2(0, 6)

	if vbox:
		var title = vbox.get_node_or_null("Title")
		if title:
			# Clear LabelSettings (set in .tscn with hardcoded black font_color)
			# so that add_theme_color_override can actually take effect.
			title.label_settings = null
			title.add_theme_color_override("font_color", ThemeManager.text_color)
			title.add_theme_font_size_override("font_size", 48)
			if _serif_font:
				title.add_theme_font_override("font", _serif_font)
		for child in vbox.get_children():
			if child is Button:
				_style_button(child)
			elif child is Label:
				child.add_theme_color_override("font_color", ThemeManager.text_color)

	for entry in _dividers:
		var line: ColorRect = entry["line"]
		if is_instance_valid(line):
			line.color = ThemeManager.border_color

func _on_dark_mode_changed(dark: bool) -> void:
	if _dark_mode_btn:
		_dark_mode_btn.text = "☾  Dark Mode" if not dark else "☀  Light Mode"
	_apply_theme()

func _style_button(btn: Button) -> void:
	var dark := ThemeManager.is_dark_mode
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 17)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ThemeManager.text_color)
	btn.add_theme_color_override("font_disabled_color", ThemeManager.subtext_color)

	var sn := StyleBoxFlat.new()
	sn.bg_color          = Color(0, 0, 0, 0)
	sn.content_margin_left   = 16
	sn.content_margin_right  = 16
	sn.content_margin_top    = 9
	sn.content_margin_bottom = 9
	btn.add_theme_stylebox_override("normal", sn)

	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(1, 1, 1, 0.06) if dark else Color(ThemeManager.border_color, 0.5)
	sh.set_corner_radius_all(5)
	sh.content_margin_left   = 16
	sh.content_margin_right  = 16
	sh.content_margin_top    = 9
	sh.content_margin_bottom = 9
	btn.add_theme_stylebox_override("hover", sh)

	var sp := sh.duplicate() as StyleBoxFlat
	sp.bg_color = Color(1, 1, 1, 0.12) if dark else Color(ThemeManager.border_color, 0.85)
	btn.add_theme_stylebox_override("pressed", sp)

	var sf := sh.duplicate() as StyleBoxFlat
	sf.border_color      = ThemeManager.text_color
	sf.border_width_left = 2
	btn.add_theme_stylebox_override("focus", sf)

# ── Animations ────────────────────────────────────────────────────────────────

func _animate_in() -> void:
	if _panel:
		_panel.modulate.a = 0.0
		_panel.position.y = 14.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.40).set_delay(0.10)
		tw.tween_property(_panel, "position:y", 0.0, 0.40) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.10)

func _animate_out(then: Callable) -> void:
	if _closing:
		return
	_closing = true
	if _panel:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_panel, "modulate:a", 0.0, 0.16)
		tw.tween_property(_panel, "position:y", 10.0, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(func():
			_closing = false
			then.call()
		)
	else:
		_closing = false
		then.call()

# ── Handlers — names MUST match PauseMenu.tscn [connection] entries ───────────

func set_current_room(room: String) -> void:
	current_room = room
	if vbox:
		var title_node = vbox.get_node_or_null("Title")
		if title_node:
			title_node.text = current_room + (" - " + tr("Paused"))
		var open_node = vbox.get_node_or_null("Open")
		if open_node:
			open_node.disabled = (current_room == "Lobby")
		var lang_node = vbox.get_node_or_null("Language")
		if lang_node:
			lang_node.visible = (current_room == "Lobby")

func ui_cancel_pressed() -> void:
	# If the quit confirmation is showing, cancel it instead of resuming.
	if _quit_container and _quit_container.visible:
		_on_cancel_quit_pressed()
		return
	if visible and not _closing:
		_on_resume_pressed()

func _on_resume_pressed() -> void:
	_animate_out(func(): resume.emit())

func _on_settings_pressed() -> void:
	_animate_out(func(): settings.emit())

# Called by the scene's "Lobby" button (node name in tscn is "Lobby").
func _on_lobby_pressed() -> void:
	_animate_out(func(): return_to_lobby.emit())

# Called by the scene's "AskQuit" button — shows the confirmation panel.
func _on_ask_quit_pressed() -> void:
	if _quit_container:
		_quit_container.visible = true

# Called by the "Yes" button inside QuitContainer.
func _on_quit_pressed() -> void:
	_animate_out(func(): get_tree().quit())

# Called by the "No" button inside QuitContainer.
func _on_cancel_quit_pressed() -> void:
	if _quit_container:
		_quit_container.visible = false

func _on_open_pressed() -> void:
	OS.shell_open("https://" + TranslationServer.get_locale() + ".wikipedia.org/wiki/" + current_room)

func _on_vr_controls_pressed() -> void:
	vr_controls.emit()

func _on_race_pressed() -> void:
	show_loading_overlay()
	start_race.emit()

func _on_cancel_race_pressed() -> void:
	RaceManager.cancel_race()

# Called by the scene's DarkMode button (scene wires to _on_dark_mode_pressed).
func _on_dark_mode_pressed() -> void:
	ThemeManager.toggle()

# Alias kept for any legacy code connections.
func _on_dark_mode_toggled() -> void:
	ThemeManager.toggle()

func _on_race_state_changed(_arg1 = null, _arg2 = null) -> void:
	hide_loading_overlay()
	_update_race_button_visibility()

func _update_race_button_visibility() -> void:
	if not race_button:
		return
	var in_mp_as_host := NetworkManager.is_multiplayer_active() and (NetworkManager.is_server() or _race_control_override)
	race_button.visible = in_mp_as_host and not RaceManager.is_race_active()
	if cancel_race_button:
		cancel_race_button.visible = in_mp_as_host and RaceManager.is_race_active()

func set_race_control_override(enabled: bool) -> void:
	_race_control_override = enabled
	_update_race_button_visibility()
