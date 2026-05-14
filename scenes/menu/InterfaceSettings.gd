extends VBoxContainer

var _chat_rebinding: bool = false

@onready var _scale_slider: HSlider = %ScaleSlider
@onready var _scale_value: Label = %ScaleValue
@onready var _reset_btn: Button = %ResetScale
@onready var _show_chat: CheckBox = %ShowChat
@onready var _typing_sound: CheckBox = %TypingSound
@onready var _chat_key_btn: Button = %ChatKeyButton
@onready var _key_hint: Label = %KeyHint
@onready var _language_option: OptionButton = %LanguageOption

func _ready() -> void:
	_load_settings()
	_apply_theme()

func _load_settings() -> void:
	var ui_settings: Dictionary = SettingsManager.get_settings("ui") if SettingsManager.get_settings("ui") else {}
	var scale: float = ui_settings.get("scale", 1.0)
	_scale_slider.value = scale
	_update_scale_label(scale)

	var chat_settings: Dictionary = SettingsManager.get_settings("chat") if SettingsManager.get_settings("chat") else {}
	_show_chat.button_pressed = chat_settings.get("enabled", true)
	_typing_sound.button_pressed = chat_settings.get("typing_sound", true)

	_populate_language_options()

func _populate_language_options() -> void:
	_language_option.clear()
	var languages := LanguageManager.get_available_languages()
	for i in languages.size():
		_language_option.add_item(languages[i].display_name, i)
		if languages[i].code == LanguageManager.current_language:
			_language_option.selected = i

func _on_scale_changed(value: float) -> void:
	_update_scale_label(value)
	var data: Dictionary = SettingsManager.get_settings("ui") if SettingsManager.get_settings("ui") else {}
	data["scale"] = value
	SettingsManager.save_settings("ui", data)
	SettingsEvents.emit_ui_scale_changed(value)
	_apply_scale_tween(value)

func _update_scale_label(value: float) -> void:
	_scale_value.text = "%.0f%%" % (value * 100)

func _apply_scale_tween(target_scale: float) -> void:
	var root := get_tree().root
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "content_scale_factor", target_scale, 0.3)

func _on_reset_scale_pressed() -> void:
	_scale_slider.value = 1.0
	_on_scale_changed(1.0)

func _on_show_chat_toggled(toggled_on: bool) -> void:
	var data: Dictionary = SettingsManager.get_settings("chat") if SettingsManager.get_settings("chat") else {}
	data["enabled"] = toggled_on
	SettingsManager.save_settings("chat", data)
	SettingsEvents.emit_chat_enabled_changed(toggled_on)

func _on_typing_sound_toggled(toggled_on: bool) -> void:
	var data: Dictionary = SettingsManager.get_settings("chat") if SettingsManager.get_settings("chat") else {}
	data["typing_sound"] = toggled_on
	SettingsManager.save_settings("chat", data)
	SettingsEvents.emit_chat_typing_sound_changed(toggled_on)

func _on_chat_key_pressed() -> void:
	if _chat_rebinding:
		return
	_chat_rebinding = true
	_chat_key_btn.text = "Press any key..."
	var binding: Variant = await _capture_key()
	_chat_rebinding = false
	if binding != null:
		InputMap.action_erase_events("chat")
		InputMap.action_add_event("chat", binding)
		SettingsEvents.emit_chat_key_changed("")
	_chat_key_btn.text = "Press to rebind"

func _capture_key() -> Variant:
	var viewport := get_viewport()
	var timer := get_tree().create_timer(5.0)
	while timer.time_left > 0:
		await get_tree().process_frame
		var event: InputEvent = viewport.gui_get_event()
		if event is InputEventKey and event.pressed and not event.echo:
			return event
		if event is InputEventJoypadButton and event.pressed:
			return event
	return null

func _on_language_selected(index: int) -> void:
	var languages := LanguageManager.get_available_languages()
	if index >= 0 and index < languages.size():
		LanguageManager.set_language(languages[index].code)

func _apply_theme() -> void:
	var text := ThemeManager.text_color
	var sub := ThemeManager.subtext_color

	for label in get_tree().get_nodes_in_group("settings_label"):
		if label is Label:
			label.add_theme_color_override("font_color", text)

	_key_hint.add_theme_color_override("font_color", sub)
	_key_hint.add_theme_font_size_override("font_size", 11)