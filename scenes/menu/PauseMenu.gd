extends Control

signal resume
signal settings
signal vr_controls
signal return_to_lobby
signal start_race

@onready var vbox = $MarginContainer/CenterContainer/VBoxContainer/PausePanel/PauseContent
@onready var race_button = $MarginContainer/CenterContainer/VBoxContainer/PausePanel/PauseContent/Race
@onready var cancel_race_button = $MarginContainer/CenterContainer/VBoxContainer/PausePanel/PauseContent/CancelRace
@onready var _dark_mode_btn: Button = $MarginContainer/CenterContainer/VBoxContainer/PausePanel/PauseContent/DarkMode
@onready var _panel: Control = $MarginContainer/CenterContainer/VBoxContainer
@onready var _pause_panel: PanelContainer = $MarginContainer/CenterContainer/VBoxContainer/PausePanel

var _panel_style: StyleBoxFlat
var _closing: bool = false


func _on_visibility_changed() -> void:
	if visible and vbox:
		_closing = false
		vbox.get_node("Resume").grab_focus()
		_update_race_button_visibility()
		_animate_in()


func _ready() -> void:
	SettingsEvents.set_current_room.connect(set_current_room)
	UIEvents.ui_cancel_pressed.connect(ui_cancel_pressed)
	MultiplayerEvents.multiplayer_started.connect(_update_race_button_visibility)
	MultiplayerEvents.multiplayer_ended.connect(_update_race_button_visibility)
	RaceManager.race_started.connect(_on_race_state_changed)
	RaceManager.race_ended.connect(_on_race_state_changed)
	RaceManager.race_cancelled.connect(_update_race_button_visibility)
	ThemeManager.dark_mode_changed.connect(_apply_theme)
	set_current_room(current_room)

	if Platform.is_web():
		%AskQuit.visible = false

	var orig := _pause_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if orig:
		_panel_style = orig.duplicate()
		_pause_panel.add_theme_stylebox_override("panel", _panel_style)

	# Dark mode disabled for now — button shows "coming soon"
	if _dark_mode_btn:
		_dark_mode_btn.text = "☾  Dark Mode (coming soon)"
		_dark_mode_btn.disabled = true

	_apply_theme(ThemeManager.is_dark_mode)
	_update_race_button_visibility()


func _apply_theme(_dark: bool) -> void:
	ThemeManager.update_panel_style(_panel_style)
	var text := ThemeManager.text_color
	if vbox:
		for child in vbox.get_children():
			if child is Label or child is Button:
				child.add_theme_color_override("font_color", text)
	# Keep dark mode btn styled as disabled
	if _dark_mode_btn:
		_dark_mode_btn.add_theme_color_override("font_color", ThemeManager.subtext_color)


func _animate_in() -> void:
	_panel.scale = Vector2(0.88, 0.88)
	_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)


func _animate_out(then: Callable) -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2(0.88, 0.88), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(func():
		_panel.scale = Vector2(1.0, 1.0)
		_panel.modulate.a = 1.0
		_closing = false
		then.call()
	)


func ui_cancel_pressed() -> void:
	if visible and not _closing:
		_animate_out(func(): resume.emit())


var current_room: String = "Lobby"
func set_current_room(room: String) -> void:
	current_room = room
	vbox.get_node("Title").text = current_room + (" - " + tr("Paused"))
	vbox.get_node("Open").disabled = current_room == "Lobby"
	$MarginContainer/CenterContainer/VBoxContainer/PausePanel/PauseContent/Language.visible = current_room == "Lobby"


func _on_resume_pressed() -> void:
	_animate_out(func(): resume.emit())

func _on_settings_pressed() -> void:
	_animate_out(func(): settings.emit())

func _on_lobby_pressed() -> void:
	_animate_out(func(): return_to_lobby.emit())

func _on_open_pressed() -> void:
	OS.shell_open("https://" + TranslationServer.get_locale() + ".wikipedia.org/wiki/" + current_room)

func _on_quit_pressed() -> void:
	UIEvents.emit_quit_requested()

func _on_ask_quit_pressed() -> void:
	_on_quit_pressed()

func _on_cancel_quit_pressed() -> void:
	$MarginContainer/CenterContainer/QuitContainer.visible = false
	$MarginContainer/CenterContainer/VBoxContainer.visible = true
	$MarginContainer/CenterContainer/VBoxContainer/PausePanel/PauseContent/Resume.grab_focus()

func _on_vr_controls_pressed() -> void:
	vr_controls.emit()

func _on_race_pressed() -> void:
	start_race.emit()

func _on_cancel_race_pressed() -> void:
	RaceManager.cancel_race()

func _on_dark_mode_pressed() -> void:
	pass  # Disabled — coming soon

func _on_race_state_changed(_arg1 = null, _arg2 = null) -> void:
	_update_race_button_visibility()

func _update_race_button_visibility() -> void:
	if not race_button:
		return
	race_button.visible = NetworkManager.is_multiplayer_active() and not RaceManager.is_race_active()
	if cancel_race_button:
		cancel_race_button.visible = NetworkManager.is_multiplayer_active() and RaceManager.is_race_active()
