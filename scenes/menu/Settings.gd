extends Control

signal resume

@onready var _vbox = $ScrollContainer/MarginContainer/VBoxContainer/MarginContainer
@onready var _tab_bar = %SettingsTabs
@onready var _tab_scenes = [
	_vbox.get_node("GraphicsSettings"),
	_vbox.get_node("AudioSettings"),
	_vbox.get_node("ControlSettings"),
	_vbox.get_node("DataSettings") if not Platform.is_web() else null,
	_build_multiplayer_settings(),
]

func _ready() -> void:
	UIEvents.ui_cancel_pressed.connect(_on_resume)
	for i in range(_tab_scenes.size()):
		if _tab_scenes[i] == null:
			_tab_bar.set_tab_disabled(i, true)
			_tab_bar.set_tab_hidden(i, true)

func _on_visibility_changed() -> void:
	if visible:
		_tab_bar.set_current_tab(0)
		_tab_bar.grab_focus()

func _on_tab_bar_tab_changed(tab: int) -> void:
	for i in range(_tab_scenes.size()):
		if _tab_scenes[i] == null:
			continue
		elif i == tab:
			_tab_scenes[i].visible = true
		else:
			_tab_scenes[i].visible = false

func _build_multiplayer_settings() -> Control:
	## Builds the Multiplayer settings panel in code — no scene changes needed.
	var container := VBoxContainer.new()
	container.name = "MultiplayerSettings"
	container.add_theme_constant_override("separation", 12)
	_vbox.add_child(container)

	# Section heading
	var heading := Label.new()
	heading.text = "Multiplayer"
	heading.add_theme_font_size_override("font_size", 18)
	container.add_child(heading)

	# Chat toggle row
	var row := HBoxContainer.new()
	container.add_child(row)

	var lbl := Label.new()
	lbl.text = "Show chat"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var saved = SettingsManager.get_settings("multiplayer_ui")
	var chat_on: bool = true
	if saved and saved.has("chat_enabled"):
		chat_on = saved.chat_enabled

	var check := CheckButton.new()
	check.button_pressed = chat_on
	check.toggled.connect(_on_chat_toggle)
	row.add_child(check)

	var hint := Label.new()
	hint.text = "Hides the chat overlay while playing."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	container.add_child(hint)

	# Typing sound toggle row
	var sound_row := HBoxContainer.new()
	container.add_child(sound_row)

	var sound_lbl := Label.new()
	sound_lbl.text = "Typing sound"
	sound_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_row.add_child(sound_lbl)

	var sound_on: bool = true
	if saved and saved.has("typing_sound_enabled"):
		sound_on = saved.typing_sound_enabled

	var sound_check := CheckButton.new()
	sound_check.button_pressed = sound_on
	sound_check.toggled.connect(_on_typing_sound_toggle)
	sound_row.add_child(sound_check)

	var sound_hint := Label.new()
	sound_hint.text = "Plays a subtle sound on each keypress in the chat box."
	sound_hint.add_theme_font_size_override("font_size", 12)
	sound_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	container.add_child(sound_hint)

	# Chat key rebind row
	var keybind_row := HBoxContainer.new()
	container.add_child(keybind_row)

	var key_lbl := Label.new()
	key_lbl.text = "Open chat"
	key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keybind_row.add_child(key_lbl)

	# Show current binding
	var current_key := _get_chat_key_name()
	var rebind_btn := Button.new()
	rebind_btn.text = current_key
	rebind_btn.custom_minimum_size = Vector2(80, 0)
	rebind_btn.pressed.connect(_on_rebind_chat_pressed.bind(rebind_btn))
	keybind_row.add_child(rebind_btn)

	SettingsEvents.chat_key_changed.connect(func(name): rebind_btn.text = name)

	var key_hint := Label.new()
	key_hint.text = "Press the button then press any key to rebind."
	key_hint.add_theme_font_size_override("font_size", 12)
	key_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	container.add_child(key_hint)

	# Add Multiplayer tab to the tab bar
	_tab_bar.add_tab("Multiplayer")

	return container


func _on_chat_toggle(enabled: bool) -> void:
	var saved = SettingsManager.get_settings("multiplayer_ui")
	var data: Dictionary = saved if saved else {}
	data["chat_enabled"] = enabled
	SettingsManager.save_settings("multiplayer_ui", data)
	SettingsEvents.emit_chat_enabled_changed(enabled)


func _on_typing_sound_toggle(enabled: bool) -> void:
	var saved = SettingsManager.get_settings("multiplayer_ui")
	var data: Dictionary = saved if saved else {}
	data["typing_sound_enabled"] = enabled
	SettingsManager.save_settings("multiplayer_ui", data)
	SettingsEvents.emit_chat_typing_sound_changed(enabled)


func _get_chat_key_name() -> String:
	var events := InputMap.action_get_events("chat")
	if events.is_empty():
		return "T"
	var ev := events[0]
	if ev is InputEventKey:
		return OS.get_keycode_string(ev.physical_keycode)
	return "T"


func _on_rebind_chat_pressed(btn: Button) -> void:
	btn.text = "..."
	# Tell ChatHUD to capture the next keypress
	var main := get_tree().get_first_node_in_group("main")
	if main:
		var chat_hud := main.get_node_or_null("ChatHUD")
		if chat_hud and chat_hud.has_method("start_chat_rebind"):
			chat_hud.start_chat_rebind()


func _on_tab_left() -> void:
	if visible:
		_tab_bar.select_next_available()

func _on_tab_right() -> void:
	if visible:
		_tab_bar.select_previous_available()

func _on_resume() -> void:
	if visible:
		resume.emit()
