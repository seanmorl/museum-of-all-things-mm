extends VBoxContainer

const ACCESSIBILITY_NAMESPACE := "accessibility"

@onready var _text_size_slider: HSlider = %TextSizeSlider
@onready var _text_size_value: Label = %TextSizeValue
@onready var _reading_font_check: CheckBox = %ReadingFontCheck
@onready var _high_contrast_check: CheckBox = %HighContrastCheck
@onready var _color_blind_option: OptionButton = %ColorBlindOption
@onready var _reduce_motion_check: CheckBox = %ReduceMotionCheck
@onready var _disable_particles_check: CheckBox = %DisableParticlesCheck
@onready var _hold_to_click_check: CheckBox = %HoldToClickCheck
@onready var _double_tap_check: CheckBox = %DoubleTapCheck

func _ready() -> void:
	_populate_color_blind_options()
	_load_settings()
	_apply_theme()

func _populate_color_blind_options() -> void:
	_color_blind_option.clear()
	_color_blind_option.add_item("None", 0)
	_color_blind_option.add_item("Protanopia (Red-blind)", 1)
	_color_blind_option.add_item("Deuteranopia (Green-blind)", 2)
	_color_blind_option.add_item("Tritanopia (Blue-blind)", 3)

func _load_settings() -> void:
	var settings: Dictionary = SettingsManager.get_settings(ACCESSIBILITY_NAMESPACE) if SettingsManager.get_settings(ACCESSIBILITY_NAMESPACE) else {}

	var text_size: float = settings.get("text_size", 1.0)
	_text_size_slider.value = text_size
	_update_text_size_label(text_size)

	_reading_font_check.button_pressed = settings.get("reading_font", false)
	_high_contrast_check.button_pressed = settings.get("high_contrast", false)
	_color_blind_option.selected = settings.get("color_blind_mode", 0)
	_reduce_motion_check.button_pressed = settings.get("reduce_motion", false)
	_disable_particles_check.button_pressed = settings.get("disable_particles", false)
	_hold_to_click_check.button_pressed = settings.get("hold_to_click", false)
	_double_tap_check.button_pressed = settings.get("double_tap_jump", false)

func _save_settings() -> void:
	var settings := {
		"text_size": _text_size_slider.value,
		"reading_font": _reading_font_check.button_pressed,
		"high_contrast": _high_contrast_check.button_pressed,
		"color_blind_mode": _color_blind_option.selected,
		"reduce_motion": _reduce_motion_check.button_pressed,
		"disable_particles": _disable_particles_check.button_pressed,
		"hold_to_click": _hold_to_click_check.button_pressed,
		"double_tap_jump": _double_tap_check.button_pressed,
	}
	SettingsManager.save_settings(ACCESSIBILITY_NAMESPACE, settings)

func _update_text_size_label(value: float) -> void:
	_text_size_value.text = "%.0f%%" % (value * 100)

func _on_text_size_changed(value: float) -> void:
	_update_text_size_label(value)
	_apply_text_size(value)
	_save_settings()

func _apply_text_size(scale: float) -> void:
	ThemeManager.set_text_scale(scale)

func _on_reading_font_toggled(toggled_on: bool) -> void:
	ThemeManager.set_reading_font_enabled(toggled_on)
	_save_settings()

func _on_high_contrast_toggled(toggled_on: bool) -> void:
	ThemeManager.set_high_contrast(toggled_on)
	_save_settings()

func _on_color_blind_selected(index: int) -> void:
	_apply_color_blind_filter(index)
	_save_settings()

func _apply_color_blind_filter(mode: int) -> void:
	GraphicsManager.set_color_blind_mode(mode)

func _on_reduce_motion_toggled(toggled_on: bool) -> void:
	GraphicsManager.set_reduce_motion(toggled_on)
	_save_settings()

func _on_disable_particles_toggled(toggled_on: bool) -> void:
	GraphicsManager.set_particles_disabled(toggled_on)
	_save_settings()

func _on_hold_to_click_toggled(toggled_on: bool) -> void:
	var input_settings: Dictionary = SettingsManager.get_settings("input") if SettingsManager.get_settings("input") else {}
	input_settings["hold_to_click"] = toggled_on
	SettingsManager.save_settings("input", input_settings)
	SettingsEvents.emit_hold_to_click_changed(toggled_on)

func _on_double_tap_toggled(toggled_on: bool) -> void:
	var input_settings: Dictionary = SettingsManager.get_settings("input") if SettingsManager.get_settings("input") else {}
	input_settings["double_tap_jump"] = toggled_on
	SettingsManager.save_settings("input", input_settings)
	SettingsEvents.emit_double_tap_changed(toggled_on)

func _on_restore_defaults_pressed() -> void:
	_text_size_slider.value = 1.0
	_reading_font_check.button_pressed = false
	_high_contrast_check.button_pressed = false
	_color_blind_option.selected = 0
	_reduce_motion_check.button_pressed = false
	_disable_particles_check.button_pressed = false
	_hold_to_click_check.button_pressed = false
	_double_tap_check.button_pressed = false
	_save_settings()
	_apply_all_settings()

func _apply_all_settings() -> void:
	_apply_text_size(_text_size_slider.value)
	ThemeManager.set_reading_font_enabled(_reading_font_check.button_pressed)
	ThemeManager.set_high_contrast(_high_contrast_check.button_pressed)
	_apply_color_blind_filter(_color_blind_option.selected)
	GraphicsManager.set_reduce_motion(_reduce_motion_check.button_pressed)
	GraphicsManager.set_particles_disabled(_disable_particles_check.button_pressed)

func _apply_theme() -> void:
	var text := ThemeManager.text_color
	var sub := ThemeManager.subtext_color

	for node in get_children():
		_apply_theme_recursive(node, text, sub)

func _apply_theme_recursive(node: Node, text: Color, sub: Color) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", text)
	elif node is CheckBox or node is CheckButton:
		node.add_theme_color_override("font_color", text)
	elif node is Button:
		node.add_theme_color_override("font_color", text)
	for child in node.get_children():
		_apply_theme_recursive(child, text, sub)