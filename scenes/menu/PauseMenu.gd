extends Control

signal resume
signal settings
signal vr_controls
signal return_to_lobby
signal return_to_main
signal start_race

# ── WCAG 2.4.7 Focus Indicator Constants ─────────────────────────────────────
const FOCUS_BORDER_WIDTH := 3
const FOCUS_CORNER_RADIUS := 8
const FOCUS_COLOR_DARK  := Color(0.31, 0.55, 1.0)
const FOCUS_COLOR_LIGHT := Color(0.11, 0.34, 0.73)

# Accent colours for the Resume hero button
const RESUME_ACCENT_DARK  := Color(0.22, 0.50, 0.38)
const RESUME_ACCENT_LIGHT := Color(0.16, 0.42, 0.32)

# Danger colours for Quit / Return buttons
const DANGER_COLOR_DARK  := Color(0.65, 0.22, 0.22)
const DANGER_COLOR_LIGHT := Color(0.55, 0.16, 0.16)

var _serif_font: Font = null
var _sans_font: Font = null
var _closing: bool = false
var _race_control_override: bool = false
var _quit_confirming: bool = false
var current_room: String = "Lobby"

var _reading_font_lambda: Callable = Callable()

# ── Node references (unique names from tscn) ─────────────────────────────────
@onready var _paused_label: Label = %PausedLabel
@onready var _room_label: Label = %RoomLabel
@onready var _header_divider: ColorRect = %HeaderDivider

@onready var _resume_btn: Button = %ResumeBtn

@onready var _exhibit_section: Label = %ExhibitSectionLabel
@onready var _open_btn: Button = %OpenBtn
@onready var _race_btn: Button = %RaceBtn
@onready var _cancel_race_btn: Button = %CancelRaceBtn
@onready var _actions_divider: ColorRect = %ActionsDivider

@onready var _nav_section: Label = %NavSectionLabel
@onready var _lobby_btn: Button = %LobbyBtn
@onready var _settings_btn: Button = %SettingsBtn
@onready var _dark_mode_btn: Button = %DarkModeBtn
@onready var _nav_divider: ColorRect = %NavDivider

@onready var _return_btn: Button = %ReturnBtn
@onready var _quit_btn: Button = %QuitBtn
@onready var _quit_confirm_row: HBoxContainer = %QuitConfirmRow
@onready var _quit_confirm_label: Label = %ConfirmLabel
@onready var _quit_no: Button = %NoBtn
@onready var _quit_yes: Button = %YesBtn

@onready var _loading_overlay: Control = $LoadingOverlay
@onready var _loading_label: Label = %LoadingLabel

@onready var _card: PanelContainer = %Card
@onready var _backdrop: ColorRect = $Backdrop


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_serif_font = load("res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf")
	_sans_font = ThemeManager.get_reading_font()
	add_to_group("mouse_overlay")

	# All buttons are focusable (WCAG 2.4.7)
	var all_buttons := _get_all_buttons()
	for btn in all_buttons:
		btn.focus_mode = Control.FOCUS_ALL
		# Hover → focus sync: mouse hover also grabs keyboard focus so the
		# focus indicator follows the pointer (WCAG 2.4.7 / 1.4.11).
		btn.mouse_entered.connect(btn.grab_focus)

	_setup_focus_chain()
	_apply_theme()

	SettingsEvents.set_current_room.connect(set_current_room)
	UIEvents.ui_cancel_pressed.connect(ui_cancel_pressed)
	MultiplayerEvents.multiplayer_started.connect(_update_race_button_visibility)
	MultiplayerEvents.multiplayer_ended.connect(_update_race_button_visibility)
	RaceManager.race_started.connect(_on_race_state_changed)
	RaceManager.race_ended.connect(_on_race_state_changed)
	RaceManager.race_cancelled.connect(_on_race_state_changed)
	RaceManager.vote_started.connect(_on_vote_started)
	RaceManager.vote_cancelled.connect(_on_vote_cancelled)

	ThemeManager.dark_mode_changed.connect(_on_dark_mode_changed)
	_reading_font_lambda = func(f): _serif_font = f; _apply_theme()
	ThemeManager.reading_font_changed.connect(_reading_font_lambda)

	if Platform.is_web():
		_quit_btn.visible = false

	_update_race_button_visibility()
	_hide_quit_confirm()
	_loading_overlay.visible = false


func _on_visibility_changed() -> void:
	if not visible:
		return
	if visible and is_inside_tree():
		_closing = false
		_hide_quit_confirm()
		_loading_overlay.visible = false
		_update_race_button_visibility()
		_animate_in()


# ── All Buttons Helper ────────────────────────────────────────────────────────

func _get_all_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	buttons.append(_resume_btn)
	buttons.append(_open_btn)
	buttons.append(_race_btn)
	buttons.append(_cancel_race_btn)
	buttons.append(_lobby_btn)
	buttons.append(_settings_btn)
	buttons.append(_dark_mode_btn)
	buttons.append(_return_btn)
	buttons.append(_quit_btn)
	buttons.append(_quit_no)
	buttons.append(_quit_yes)
	return buttons


func _get_menu_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	buttons.append(_resume_btn)
	if _open_btn.visible:
		buttons.append(_open_btn)
	if _race_btn.visible:
		buttons.append(_race_btn)
	if _cancel_race_btn.visible:
		buttons.append(_cancel_race_btn)
	buttons.append(_lobby_btn)
	buttons.append(_settings_btn)
	buttons.append(_dark_mode_btn)
	buttons.append(_return_btn)
	if _quit_btn.visible:
		buttons.append(_quit_btn)
	return buttons


# ── WCAG 2.4.7: Focus Chain ──────────────────────────────────────────────────

func _setup_focus_chain() -> void:
	var buttons := _get_menu_buttons()
	for i in range(buttons.size()):
		var btn = buttons[i]
		var prev_btn = buttons[posmod(i - 1, buttons.size())]
		var next_btn = buttons[posmod(i + 1, buttons.size())]
		btn.focus_neighbor_top    = prev_btn.get_path()
		btn.focus_neighbor_bottom = next_btn.get_path()
		btn.focus_neighbor_left   = btn.get_path()
		btn.focus_neighbor_right  = btn.get_path()
		btn.focus_previous = prev_btn.get_path()
		btn.focus_next     = next_btn.get_path()

	# Quit confirm buttons chain between themselves
	if _quit_no and _quit_yes:
		_quit_no.focus_neighbor_top    = _quit_yes.get_path()
		_quit_no.focus_neighbor_bottom = _quit_yes.get_path()
		_quit_no.focus_neighbor_left   = _quit_no.get_path()
		_quit_no.focus_neighbor_right  = _quit_yes.get_path()
		_quit_no.focus_previous = _quit_yes.get_path()
		_quit_no.focus_next     = _quit_yes.get_path()

		_quit_yes.focus_neighbor_top    = _quit_no.get_path()
		_quit_yes.focus_neighbor_bottom = _quit_no.get_path()
		_quit_yes.focus_neighbor_left   = _quit_no.get_path()
		_quit_yes.focus_neighbor_right  = _quit_yes.get_path()
		_quit_yes.focus_previous = _quit_no.get_path()
		_quit_yes.focus_next     = _quit_no.get_path()


# ── Button Styling ────────────────────────────────────────────────────────────

func _apply_button_style(btn: Button, style_type: String = "normal") -> void:
	var dark := ThemeManager.is_dark_mode

	# Pick colours based on style type
	var accent_color: Color
	var accent_bg: Color
	match style_type:
		"resume":
			accent_color = RESUME_ACCENT_DARK if dark else RESUME_ACCENT_LIGHT
			accent_bg = Color(0.22, 0.50, 0.38, 0.15) if dark else Color(0.16, 0.42, 0.32, 0.08)
		"danger":
			accent_color = DANGER_COLOR_DARK if dark else DANGER_COLOR_LIGHT
			accent_bg = Color(0.65, 0.22, 0.22, 0.10) if dark else Color(0.55, 0.16, 0.16, 0.05)
		_, "normal":
			accent_color = FOCUS_COLOR_DARK if dark else FOCUS_COLOR_LIGHT
			accent_bg = Color(1, 1, 1, 0.04) if dark else Color(0, 0, 0, 0.02)

	# ── Normal ─────────────────────────────────────────────────────────
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent_bg
	normal.border_color = Color(1, 1, 1, 0.06) if dark else Color(0, 0, 0, 0.04)
	normal.border_width_left   = 1
	normal.border_width_top    = 1
	normal.border_width_right  = 1
	normal.border_width_bottom = 1
	normal.set_corner_radius_all(FOCUS_CORNER_RADIUS)
	normal.content_margin_left   = 16
	normal.content_margin_right  = 16
	normal.content_margin_top    = 10
	normal.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", normal)

	# ── Hover ──────────────────────────────────────────────────────────
	var hover := normal.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.10) if dark else Color(0, 0, 0, 0.06)
	hover.border_color = Color(1, 1, 1, 0.14) if dark else Color(0, 0, 0, 0.10)
	btn.add_theme_stylebox_override("hover", hover)

	# ── Focus (WCAG 2.4.7) ────────────────────────────────────────────
	var focus := normal.duplicate()
	focus.border_width_left   = FOCUS_BORDER_WIDTH
	focus.border_width_top    = FOCUS_BORDER_WIDTH
	focus.border_width_right  = FOCUS_BORDER_WIDTH
	focus.border_width_bottom = FOCUS_BORDER_WIDTH
	focus.border_color = accent_color
	focus.bg_color = Color(1, 1, 1, 0.07) if dark else Color(0, 0, 0, 0.04)
	focus.shadow_color   = accent_color
	focus.shadow_color.a = 0.25 if dark else 0.18
	focus.shadow_size    = 4
	focus.shadow_offset  = Vector2.ZERO
	btn.add_theme_stylebox_override("focus", focus)

	# ── Pressed ────────────────────────────────────────────────────────
	var pressed := normal.duplicate()
	pressed.bg_color     = Color(1, 1, 1, 0.16) if dark else Color(0, 0, 0, 0.09)
	pressed.border_color = accent_color
	pressed.border_width_left   = FOCUS_BORDER_WIDTH
	pressed.border_width_top    = FOCUS_BORDER_WIDTH
	pressed.border_width_right  = FOCUS_BORDER_WIDTH
	pressed.border_width_bottom = FOCUS_BORDER_WIDTH
	btn.add_theme_stylebox_override("pressed", pressed)

	# ── Hover + Pressed ────────────────────────────────────────────────
	var hover_pressed := pressed.duplicate()
	hover_pressed.bg_color = Color(1, 1, 1, 0.18) if dark else Color(0, 0, 0, 0.11)
	btn.add_theme_stylebox_override("hover_pressed", hover_pressed)

	# ── Disabled ───────────────────────────────────────────────────────
	var disabled := normal.duplicate()
	disabled.bg_color = Color(1, 1, 1, 0.02) if dark else Color(0, 0, 0, 0.01)
	btn.add_theme_stylebox_override("disabled", disabled)

	# ── Font ───────────────────────────────────────────────────────────
	btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 17 if style_type != "resume" else 19)
	btn.add_theme_color_override("font_color",             ThemeManager.text_color)
	btn.add_theme_color_override("font_hover_color",       ThemeManager.text_color)
	btn.add_theme_color_override("font_focus_color",       ThemeManager.text_color)
	btn.add_theme_color_override("font_pressed_color",     ThemeManager.text_color)
	btn.add_theme_color_override("font_hover_pressed_color", ThemeManager.text_color)
	btn.add_theme_color_override("font_disabled_color",    ThemeManager.subtext_color)


# ── Theme ─────────────────────────────────────────────────────────────────────

func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode

	# ── Card panel ─────────────────────────────────────────────────────
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = ThemeManager.bg_color
	card_style.border_color = ThemeManager.border_color
	card_style.border_width_left   = 1
	card_style.border_width_top    = 1
	card_style.border_width_right  = 1
	card_style.border_width_bottom = 1
	card_style.set_corner_radius_all(20)
	card_style.content_margin_left   = 0
	card_style.content_margin_right  = 0
	card_style.content_margin_top    = 0
	card_style.content_margin_bottom = 0
	card_style.shadow_color   = Color(0, 0, 0, 0.35 if dark else 0.12)
	card_style.shadow_size    = 30
	card_style.shadow_offset  = Vector2(0, 8)
	_card.add_theme_stylebox_override("panel", card_style)

	# ── Backdrop ───────────────────────────────────────────────────────
	_backdrop.color = Color(0, 0, 0, 0.60) if dark else Color(0, 0, 0, 0.30)

	# ── Header ─────────────────────────────────────────────────────────
	_paused_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	_paused_label.add_theme_font_override("font", _sans_font)
	_room_label.add_theme_color_override("font_color", ThemeManager.text_color)
	_room_label.add_theme_font_override("font", _serif_font)
	_header_divider.color = ThemeManager.border_color

	# ── Section labels ─────────────────────────────────────────────────
	_exhibit_section.add_theme_color_override("font_color", ThemeManager.subtext_color)
	if _nav_section:
		_nav_section.add_theme_color_override("font_color", ThemeManager.subtext_color)

	# ── Dividers ───────────────────────────────────────────────────────
	_actions_divider.color = ThemeManager.border_color
	_nav_divider.color = ThemeManager.border_color

	# ── Buttons ────────────────────────────────────────────────────────
	_apply_button_style(_resume_btn, "resume")
	_apply_button_style(_open_btn, "normal")
	_apply_button_style(_race_btn, "normal")
	_apply_button_style(_cancel_race_btn, "normal")
	_apply_button_style(_lobby_btn, "normal")
	_apply_button_style(_settings_btn, "normal")
	_apply_button_style(_dark_mode_btn, "normal")
	_apply_button_style(_return_btn, "danger")
	_apply_button_style(_quit_btn, "danger")
	_apply_button_style(_quit_no, "normal")
	_apply_button_style(_quit_yes, "danger")

	# Quit confirm text
	if _quit_confirm_label:
		_quit_confirm_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
		_quit_confirm_label.add_theme_font_override("font", _serif_font)
		_quit_confirm_label.add_theme_font_size_override("font_size", 15)

	# Dark mode button text
	if _dark_mode_btn:
		_dark_mode_btn.text = "☾  Dark Mode" if not ThemeManager.is_dark_mode else "☀  Light Mode"

	# Loading overlay
	if _loading_label:
		_loading_label.add_theme_color_override("font_color", Color.WHITE)
		_loading_label.add_theme_font_override("font", _serif_font)
		_loading_label.add_theme_font_size_override("font_size", 24)


func _on_dark_mode_changed(dark: bool) -> void:
	if _dark_mode_btn:
		_dark_mode_btn.text = "☾  Dark Mode" if not dark else "☀  Light Mode"
	_apply_theme()


# ── Animations ────────────────────────────────────────────────────────────────

func _animate_in() -> void:
	_card.modulate.a = 0.0
	_card.position.y = 20.0
	_backdrop.color.a = 0.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_backdrop, "color:a", Color(0, 0, 0, 0.60).a if ThemeManager.is_dark_mode else Color(0, 0, 0, 0.30).a, 0.25)
	tw.tween_property(_card, "modulate:a", 1.0, 0.30).set_delay(0.05)
	tw.tween_property(_card, "position:y", 0.0, 0.40) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.05)

	# ── WCAG 2.4.7: Auto-focus Resume after animation ─────────────────
	var focus_tw := create_tween()
	focus_tw.tween_callback(_grab_resume_focus).set_delay(0.45)


func _grab_resume_focus() -> void:
	if _resume_btn and _resume_btn.visible:
		_resume_btn.grab_focus()
		return
	# Fallback: first visible button
	for btn in _get_menu_buttons():
		if btn.visible:
			btn.grab_focus()
			return


func _animate_out(then: Callable) -> void:
	if _closing:
		return
	_closing = true

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_backdrop, "color:a", 0.0, 0.18)
	tw.tween_property(_card, "modulate:a", 0.0, 0.15)
	tw.tween_property(_card, "position:y", 12.0, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		_closing = false
		then.call()
	)


# ── Quit Confirmation (Inline) ───────────────────────────────────────────────

func _show_quit_confirm() -> void:
	_quit_confirming = true
	_quit_btn.visible = false
	_quit_confirm_row.visible = true
	# ── WCAG 2.4.7: Focus "No" by default (safer option) ──────────────
	if _quit_no:
		_quit_no.grab_focus()


func _hide_quit_confirm() -> void:
	_quit_confirming = false
	_quit_confirm_row.visible = false
	if _quit_btn and not Platform.is_web():
		_quit_btn.visible = true
	_setup_focus_chain()


# ── Handlers ──────────────────────────────────────────────────────────────────

func set_current_room(room: String) -> void:
	current_room = room
	if _room_label:
		_room_label.text = room
	if _open_btn:
		_open_btn.disabled = (current_room == "Lobby")
	_setup_focus_chain()


func ui_cancel_pressed() -> void:
	if _quit_confirming:
		_hide_quit_confirm()
		# Return focus to quit button
		if _quit_btn and _quit_btn.visible:
			_quit_btn.grab_focus()
		else:
			_grab_resume_focus()
		return
	if visible and not _closing:
		_on_resume_pressed()


func _on_resume_pressed() -> void:
	_animate_out(func(): resume.emit())


func _on_settings_pressed() -> void:
	_animate_out(func(): settings.emit())


func _on_lobby_pressed() -> void:
	_animate_out(func(): return_to_lobby.emit())


func _on_ask_quit_pressed() -> void:
	_show_quit_confirm()


func _on_quit_pressed() -> void:
	_animate_out(func(): get_tree().quit())


func _on_return_to_main_pressed() -> void:
	_animate_out(func():
		NetworkManager.disconnect_from_game()
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
	)


func _on_cancel_quit_pressed() -> void:
	_hide_quit_confirm()
	# ── WCAG 2.4.7: Return focus to the Quit button ───────────────────
	if _quit_btn and _quit_btn.visible:
		_quit_btn.grab_focus()
	else:
		_grab_resume_focus()


func _on_open_pressed() -> void:
	OS.shell_open("https://" + TranslationServer.get_locale() + ".wikipedia.org/wiki/" + current_room)


func _on_vr_controls_pressed() -> void:
	vr_controls.emit()


func _on_race_pressed() -> void:
	_loading_overlay.visible = true
	start_race.emit()


func _on_cancel_race_pressed() -> void:
	RaceManager.cancel_race()


func _on_dark_mode_pressed() -> void:
	ThemeManager.toggle()


func _on_race_state_changed(_arg1 = null, _arg2 = null) -> void:
	_loading_overlay.visible = false
	_update_race_button_visibility()


func _on_vote_started(_candidates: Array) -> void:
	_loading_overlay.visible = false


func _on_vote_cancelled() -> void:
	_loading_overlay.visible = false


func _update_race_button_visibility() -> void:
	var in_mp_as_host := NetworkManager.is_multiplayer_active() and (NetworkManager.is_server() or _race_control_override)

	if _race_btn:
		_race_btn.visible = in_mp_as_host and not RaceManager.is_race_active()
	if _cancel_race_btn:
		_cancel_race_btn.visible = in_mp_as_host and RaceManager.is_race_active()
	_setup_focus_chain()


func set_race_control_override(enabled: bool) -> void:
	_race_control_override = enabled
	_update_race_button_visibility()

func show_loading_overlay() -> void:
	_loading_overlay.visible = true

func hide_loading_overlay() -> void:
	_loading_overlay.visible = false


func _exit_tree() -> void:
	SettingsEvents.set_current_room.disconnect(set_current_room)
	UIEvents.ui_cancel_pressed.disconnect(ui_cancel_pressed)
	MultiplayerEvents.multiplayer_started.disconnect(_update_race_button_visibility)
	MultiplayerEvents.multiplayer_ended.disconnect(_update_race_button_visibility)
	RaceManager.race_started.disconnect(_on_race_state_changed)
	RaceManager.race_ended.disconnect(_on_race_state_changed)
	RaceManager.race_cancelled.disconnect(_on_race_state_changed)
	RaceManager.vote_started.disconnect(_on_vote_started)
	RaceManager.vote_cancelled.disconnect(_on_vote_cancelled)
	ThemeManager.dark_mode_changed.disconnect(_on_dark_mode_changed)
	if _reading_font_lambda.is_valid():
		ThemeManager.reading_font_changed.disconnect(_reading_font_lambda)
