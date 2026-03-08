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

var _serif_font: FontFile = null
const _FONT_PATH := "res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf"
var _content_panel_style: StyleBoxFlat = null
var _current_tab: int = 0

func _ready() -> void:
	_serif_font = load(_FONT_PATH) as FontFile
	UIEvents.ui_cancel_pressed.connect(_on_resume)
	for i in range(_tab_scenes.size()):
		if _tab_scenes[i] == null:
			_tab_bar.set_tab_disabled(i, true)
			_tab_bar.set_tab_hidden(i, true)
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())

func _apply_theme() -> void:
	## Apply ThemeManager colors to the settings panel and tab bar.
	var bg := StyleBoxFlat.new()
	bg.bg_color = ThemeManager.bg_color
	bg.border_color = ThemeManager.border_color
	bg.border_width_bottom = 1
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		bg.set("corner_radius_" + corner, 8)
	bg.shadow_color = Color(0, 0, 0, 0.30 if ThemeManager.is_dark_mode else 0.10)
	bg.shadow_size = 14
	bg.shadow_offset = Vector2(0, 5)
	if get_node_or_null("ScrollContainer") is ScrollContainer:
		get_node("ScrollContainer").add_theme_stylebox_override("panel", bg)
	
	if _tab_bar:
		_tab_bar.add_theme_color_override("font_selected_color", ThemeManager.text_color)
		_tab_bar.add_theme_color_override("font_unselected_color", ThemeManager.subtext_color)
		_tab_bar.add_theme_color_override("font_hovered_color", ThemeManager.text_color)
		if _serif_font:
			_tab_bar.add_theme_font_override("font", _serif_font)
		_tab_bar.add_theme_font_size_override("font_size", 14)

	for scene in _tab_scenes:
		if scene is Control:
			_theme_control_tree(scene)

func _theme_control_tree(node: Node) -> void:
	if node is Label:
		var lbl := node as Label
		var role := lbl.get_meta("settings_role", "body") as String
		match role:
			"heading":
				lbl.add_theme_color_override("font_color", ThemeManager.text_color)
				lbl.add_theme_font_size_override("font_size", 18)
			"hint":
				lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
			_:
				lbl.add_theme_color_override("font_color", ThemeManager.text_color)
		if _serif_font:
			lbl.add_theme_font_override("font", _serif_font)
	elif node is Button or node is CheckButton:
		var btn := node as BaseButton
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			btn.add_theme_color_override(state, ThemeManager.text_color)
		if _serif_font:
			btn.add_theme_font_override("font", _serif_font)
		for child in node.get_children():
			_theme_control_tree(child)

func _on_visibility_changed() -> void:
	if visible:
		_apply_theme()
		_tab_bar.set_current_tab(0)
		_tab_bar.grab_focus()
		var scroll := get_node_or_null("ScrollContainer") as Control
		if scroll:
			scroll.modulate.a = 0.0
			scroll.position.y = 10.0
			var tw: Tween = scroll.create_tween()
			tw.set_parallel(true)
			tw.tween_property(scroll, "modulate:a", 1.0, 0.30)
			tw.tween_property(scroll, "position:y", 0.0, 0.30) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_tab_bar_tab_changed(tab: int) -> void:
	var prev_scene: Control = _tab_scenes[_current_tab] if _current_tab < _tab_scenes.size() else null
	_current_tab = tab
	var next_scene: Control = _tab_scenes[tab] if tab < _tab_scenes.size() else null
	
	for i in range(_tab_scenes.size()):
		if _tab_scenes[i] != null and _tab_scenes[i] != next_scene:
			_tab_scenes[i].visible = false

	if not next_scene:
		return

	next_scene.visible = true
	next_scene.modulate.a = 0.0
	next_scene.position.y = 8.0
	var tw: Tween = next_scene.create_tween()
	tw.set_parallel(true)
	tw.tween_property(next_scene, "modulate:a", 1.0, 0.18)
	tw.tween_property(next_scene, "position:y", 0.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_theme_control_tree(next_scene)

func _build_multiplayer_settings() -> Control:
	var container := VBoxContainer.new()
	container.name = "MultiplayerSettings"
	container.add_theme_constant_override("separation", 14)
	_vbox.add_child(container)
	
	var iface_heading := Label.new()
	iface_heading.text = "Interface"
	iface_heading.set_meta("settings_role", "heading")
	iface_heading.add_theme_font_size_override("font_size", 18)
	container.add_child(iface_heading)

	var saved_ui = SettingsManager.get_settings("ui")
	var current_scale: float = 1.0
	if saved_ui and saved_ui.has("scale"):
		current_scale = float(saved_ui.scale)

	var scale_val_lbl := Label.new()
	scale_val_lbl.custom_minimum_size = Vector2(44, 0)
	scale_val_lbl.text = "%.0f%%" % (current_scale * 100)

	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.5
	scale_slider.max_value = 2.0
	scale_slider.step = 0.05
	scale_slider.value = current_scale
	scale_slider.custom_minimum_size = Vector2(180, 0)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.custom_minimum_size = Vector2(54, 0)
	reset_btn.tooltip_text = "Reset to 100%"
	reset_btn.pressed.connect(func():
		scale_slider.value = 1.0
		scale_val_lbl.text = "100%"
		_on_ui_scale_changed(1.0)
	)

	scale_slider.value_changed.connect(func(v: float):
		scale_val_lbl.text = "%.0f%%" % (v * 100)
		_on_ui_scale_changed(v)
	)

	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 8)
	var scale_lbl := Label.new()
	scale_lbl.text = "UI Scale"
	scale_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(scale_lbl)
	scale_row.add_child(scale_slider)
	scale_row.add_child(scale_val_lbl)
	scale_row.add_child(reset_btn)
	container.add_child(scale_row)

	var scale_hint := Label.new()
	scale_hint.text = "Scales all menus, HUD, and overlays. Shortcuts: Ctrl+= / Ctrl+- / Ctrl+0"
	scale_hint.set_meta("settings_role", "hint")
	scale_hint.add_theme_font_size_override("font_size", 11)
	scale_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	container.add_child(scale_hint)

	var mp_heading := Label.new()
	mp_heading.text = "Multiplayer"
	mp_heading.set_meta("settings_role", "heading")
	mp_heading.add_theme_font_size_override("font_size", 18)
	container.add_child(mp_heading)

	var saved = SettingsManager.get_settings("multiplayer_ui")
	var chat_on: bool = true
	if saved and saved.has("chat_enabled"):
		chat_on = saved.chat_enabled

	var chat_row := HBoxContainer.new()
	container.add_child(chat_row)
	var lbl := Label.new()
	lbl.text = "Show chat"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_row.add_child(lbl)
	var check := CheckButton.new()
	check.button_pressed = chat_on
	check.toggled.connect(_on_chat_toggle)
	chat_row.add_child(check)

	var hint := Label.new()
	hint.text = "Hides the chat overlay while playing."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	container.add_child(hint)

	var sound_on: bool = true
	if saved and saved.has("typing_sound_enabled"):
		sound_on = saved.typing_sound_enabled

	var sound_row := HBoxContainer.new()
	container.add_child(sound_row)
	var sound_lbl := Label.new()
	sound_lbl.text = "Typing sound"
	sound_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_row.add_child(sound_lbl)
	var sound_check := CheckButton.new()
	sound_check.button_pressed = sound_on
	sound_check.toggled.connect(_on_typing_sound_toggle)
	sound_row.add_child(sound_check)

	var sound_hint := Label.new()
	sound_hint.text = "Plays a subtle sound on each keypress in the chat box."
	sound_hint.add_theme_font_size_override("font_size", 11)
	sound_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	container.add_child(sound_hint)

	var keybind_row := HBoxContainer.new()
	container.add_child(keybind_row)
	var key_lbl := Label.new()
	key_lbl.text = "Open chat"
	key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keybind_row.add_child(key_lbl)
	var current_key := _get_chat_key_name()
	var rebind_btn := Button.new()
	rebind_btn.text = current_key
	rebind_btn.custom_minimum_size = Vector2(80, 0)
	rebind_btn.pressed.connect(_on_rebind_chat_pressed.bind(rebind_btn))
	keybind_row.add_child(rebind_btn)
	SettingsEvents.chat_key_changed.connect(func(name): rebind_btn.text = name)

	var key_hint := Label.new()
	key_hint.text = "Press the button then press any key to rebind."
	key_hint.add_theme_font_size_override("font_size", 11)
	key_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	container.add_child(key_hint)

	_tab_bar.add_tab("Interface")

	return container

func _on_ui_scale_changed(scale: float) -> void:
	var data: Dictionary = SettingsManager.get_settings("ui") if SettingsManager.get_settings("ui") else {}
	data["scale"] = scale
	SettingsManager.save_settings("ui", data)
	SettingsEvents.emit_ui_scale_changed(scale)
	_apply_ui_scale_tween(scale)

func _apply_ui_scale_tween(target_scale: float) -> void:
	var root := get_tree().root
	var tw := create_tween()
	tw.tween_method(func(v: float): root.content_scale_factor = v,
		root.content_scale_factor, target_scale, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
		visible = false
		resume.emit()