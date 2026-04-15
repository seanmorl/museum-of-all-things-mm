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
	_build_accessibility_settings(),
]

var _serif_font: Font = null
var _content_panel_style: StyleBoxFlat = null
var _current_tab: int = 0

## Stored lambdas for signal cleanup
var _dark_mode_lambda: Callable = Callable()
var _reading_font_lambda: Callable = Callable()

func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	add_to_group("mouse_overlay")
	UIEvents.ui_cancel_pressed.connect(_on_resume)
	for i in range(_tab_scenes.size()):
		if _tab_scenes[i] == null:
			_tab_bar.set_tab_disabled(i, true)
			_tab_bar.set_tab_hidden(i, true)
	_apply_theme()
	_dark_mode_lambda = func(_d): _apply_theme()
	_reading_font_lambda = func(f): _serif_font = f; _apply_theme()
	ThemeManager.dark_mode_changed.connect(_dark_mode_lambda)
	ThemeManager.reading_font_changed.connect(_reading_font_lambda)


func _exit_tree() -> void:
	UIEvents.ui_cancel_pressed.disconnect(_on_resume)
	if _dark_mode_lambda.is_valid():
		ThemeManager.dark_mode_changed.disconnect(_dark_mode_lambda)
	if _reading_font_lambda.is_valid():
		ThemeManager.reading_font_changed.disconnect(_reading_font_lambda)

func _apply_theme() -> void:
	## Apply ThemeManager colors to the settings panel and tab bar.
	var dark := ThemeManager.is_dark_mode
	
	# Create panel style using centralized helper
	var bg := UIStyle.create_panel_style(
		ThemeManager.bg_color,
		ThemeManager.border_color,
		dark,
		UIStyle.CORNER_RADIUS_PANEL,
		UIStyle.PANEL_PADDING
	)
	# Adjust for settings-specific padding
	bg.content_margin_left = 20
	bg.content_margin_right = 20
	bg.content_margin_top = 16
	bg.content_margin_bottom = 16
	
	var panel := get_node_or_null("ScrollContainer/MarginContainer/Panel")
	if panel:
		panel.add_theme_stylebox_override("panel", bg)

	# Fallback for ScrollContainer itself if no Panel is found
	if not panel and get_node_or_null("ScrollContainer") is ScrollContainer:
		get_node("ScrollContainer").add_theme_stylebox_override("panel", bg)

	if _tab_bar:
		_tab_bar.add_theme_color_override("font_selected_color", ThemeManager.text_color)
		_tab_bar.add_theme_color_override("font_unselected_color", ThemeManager.subtext_color)
		_tab_bar.add_theme_color_override("font_hovered_color", ThemeManager.text_color)
		if _serif_font:
			_tab_bar.add_theme_font_override("font", _serif_font)
		_tab_bar.add_theme_font_size_override("font_size", 14)

		# Use centralized tab styles
		var tab_styles := UIStyle.create_tab_style(
			ThemeManager.text_color,
			ThemeManager.subtext_color,
			UIStyle.get_accent_color(dark),
			dark,
			_serif_font
		)
		_tab_bar.add_theme_stylebox_override("tab_selected", tab_styles.selected)
		_tab_bar.add_theme_stylebox_override("tab_unselected", tab_styles.unselected)
		_tab_bar.add_theme_stylebox_override("tab_hovered", tab_styles.hovered)
		_tab_bar.add_theme_constant_override("h_separation", 45)
		_tab_bar.clip_tabs = false

	# Style the Back button
	var back_btn := get_node_or_null("ScrollContainer/MarginContainer/VBoxContainer/HBoxContainer/BackButton") as Button
	if back_btn:
		_style_top_button(back_btn)

	# Style separators using centralized helper
	var h_sep := get_node_or_null("ScrollContainer/MarginContainer/VBoxContainer/HSeparator") as HSeparator
	if h_sep:
		h_sep.add_theme_stylebox_override("separator", UIStyle.create_divider_style(ThemeManager.border_color))

	_theme_control_tree(_vbox)
	for scene in _tab_scenes:
		if scene is Control:
			_theme_control_tree(scene)

func _theme_control_tree(node: Node) -> void:
	if node is Label:
		node.label_settings = null # Ensure theme overrides work
		node.add_theme_color_override("font_color", ThemeManager.text_color)
		if node.get_meta("settings_role", "") == "hint":
			node.add_theme_color_override("font_color", ThemeManager.subtext_color)
		if _serif_font:
			node.add_theme_font_override("font", _serif_font)
	elif node is Button:
		_style_top_button(node)
	elif node is OptionButton:
		ThemeManager.style_option_button(node)
		if _serif_font:
			node.add_theme_font_override("font", _serif_font)
			node.get_popup().add_theme_font_override("font", _serif_font)
	elif node is CheckBox:
		node.add_theme_color_override("font_color", ThemeManager.text_color)
		node.add_theme_color_override("font_hover_color", ThemeManager.text_color)
		node.add_theme_color_override("font_pressed_color", ThemeManager.text_color)
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "pressed", "disabled", "hover", "focus"]:
			node.add_theme_stylebox_override(state, empty)
	elif node is Separator:
		var sep_style := StyleBoxLine.new()
		sep_style.color = ThemeManager.border_color
		sep_style.thickness = 1
		node.add_theme_stylebox_override("separator", sep_style)
	elif node is PanelContainer:
		var panel_style := StyleBoxEmpty.new()
		node.add_theme_stylebox_override("panel", panel_style)
	elif node is CheckButton:
		var btn := node as BaseButton
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			btn.add_theme_color_override(state, ThemeManager.text_color)
		if _serif_font:
			btn.add_theme_font_override("font", _serif_font)
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "pressed", "disabled", "hover", "focus"]:
			btn.add_theme_stylebox_override(state, empty)
	elif node is LineEdit:
		_style_line_edit(node)
	elif node is SpinBox:
		var edit: LineEdit = node.get_line_edit()
		if edit:
			_style_line_edit(edit)
	
	for child in node.get_children():
		_theme_control_tree(child)


func _style_top_button(btn: Button) -> void:
	## Styles smaller utility buttons like 'Back' or 'Restore'
	if not btn: return
	var dark := ThemeManager.is_dark_mode
	
	# Apply font
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 14)
	
	# Apply font colors
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ThemeManager.text_color)
	
	# Use centralized button style helper with border
	var normal := UIStyle.create_button_style(
		Color.TRANSPARENT,
		ThemeManager.border_color,
		UIStyle.CORNER_RADIUS_SMALL,
		8.0
	)
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1,1,1,0.05) if dark else Color(0,0,0,0.05)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1,1,1,0.1) if dark else Color(0,0,0,0.1)
	btn.add_theme_stylebox_override("pressed", pressed)


func _style_line_edit(edit: LineEdit) -> void:
	var dark := ThemeManager.is_dark_mode
	
	# Apply font
	if _serif_font:
		edit.add_theme_font_override("font", _serif_font)
	edit.add_theme_font_size_override("font_size", 14)

	# Apply colors
	edit.add_theme_color_override("font_color", ThemeManager.text_color)
	edit.add_theme_color_override("font_placeholder_color", ThemeManager.subtext_color)
	
	# Use centralized input style helper
	var styles := UIStyle.create_input_style(
		Color.TRANSPARENT,
		ThemeManager.border_color,
		ThemeManager.text_color,
		ThemeManager.subtext_color,
		dark,
		_serif_font
	)
	edit.add_theme_stylebox_override("normal", styles.normal)
	edit.add_theme_stylebox_override("focus", styles.focus)

func _on_visibility_changed() -> void:
	if visible:
		# Hide all tab scenes initially to prevent layout overlap/borking
		for scene in _tab_scenes:
			if scene:
				scene.visible = false

		_apply_theme()
		_tab_bar.set_current_tab(0)
		_on_tab_bar_tab_changed(0) # Explicitly show first tab
		_tab_bar.grab_focus()
		var scroll := get_node_or_null("ScrollContainer") as Control
		if scroll:
			scroll.modulate.a = 0.0
			scroll.position.y = 10.0
			var tw: Tween = scroll.create_tween()
			tw.set_parallel(true)
			tw.tween_property(scroll, "modulate:a", 1.0, UIStyle.FADE_DURATION)
			tw.tween_property(scroll, "position:y", 0.0, UIStyle.SLIDE_DURATION) \
				.set_trans(UIStyle.TRANS_BOUNCE).set_ease(UIStyle.EASE_BOUNCE)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_resume()

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
	tw.tween_property(next_scene, "modulate:a", 1.0, UIStyle.FADE_QUICK)
	tw.tween_property(next_scene, "position:y", 0.0, UIStyle.FADE_QUICK) \
		.set_trans(UIStyle.TRANS_EXIT).set_ease(UIStyle.EASE_EXIT)
	_theme_control_tree(next_scene)

func _build_multiplayer_settings() -> Control:
	var container := VBoxContainer.new()
	container.name = "MultiplayerSettings"
	container.add_theme_constant_override("separation", 14)
	_vbox.add_child(container)
	
	var iface_heading := Label.new()
	iface_heading.text = tr("Interface")
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
	reset_btn.text = tr("Reset")
	reset_btn.custom_minimum_size = Vector2(54, 0)
	reset_btn.tooltip_text = tr("Reset to 100%")
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
	scale_lbl.text = tr("UI Scale")
	scale_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(scale_lbl)
	scale_row.add_child(scale_slider)
	scale_row.add_child(scale_val_lbl)
	scale_row.add_child(reset_btn)
	container.add_child(scale_row)

	var scale_hint := Label.new()
	scale_hint.text = tr("Scales all menus, HUD, and overlays. Shortcuts: Ctrl+= / Ctrl+- / Ctrl+0")
	scale_hint.set_meta("settings_role", "hint")
	scale_hint.add_theme_font_size_override("font_size", 11)
	scale_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	container.add_child(scale_hint)

	var mp_heading := Label.new()
	mp_heading.text = tr("Multiplayer")
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
	lbl.text = tr("Show chat")
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_row.add_child(lbl)
	var check := CheckButton.new()
	check.button_pressed = chat_on
	check.toggled.connect(_on_chat_toggle)
	chat_row.add_child(check)

	var hint := Label.new()
	hint.text = tr("Hides the chat overlay while playing.")
	hint.set_meta("settings_role", "hint")
	container.add_child(hint)

	var sound_on: bool = true
	if saved and saved.has("typing_sound_enabled"):
		sound_on = saved.typing_sound_enabled

	var sound_row := HBoxContainer.new()
	container.add_child(sound_row)
	var sound_lbl := Label.new()
	sound_lbl.text = tr("Typing sound")
	sound_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_row.add_child(sound_lbl)
	var sound_check := CheckButton.new()
	sound_check.button_pressed = sound_on
	sound_check.toggled.connect(_on_typing_sound_toggle)
	sound_row.add_child(sound_check)

	var sound_hint := Label.new()
	sound_hint.text = tr("Plays a subtle sound on each keypress in the chat box.")
	sound_hint.set_meta("settings_role", "hint")
	container.add_child(sound_hint)

	var keybind_row := HBoxContainer.new()
	container.add_child(keybind_row)
	var key_lbl := Label.new()
	key_lbl.text = tr("Open chat")
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
	key_hint.text = tr("Press the button then press any key to rebind.")
	key_hint.set_meta("settings_role", "hint")
	container.add_child(key_hint)

	_tab_bar.add_tab(tr("Interface"))

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

func _style_option_button(btn: OptionButton) -> void:
	ThemeManager.style_option_button(btn)



func _build_accessibility_settings() -> Control:
	var saved: Dictionary = SettingsManager.get_settings("accessibility") if SettingsManager.get_settings("accessibility") else {}

	var container := VBoxContainer.new()
	container.name = "AccessibilitySettings"
	container.add_theme_constant_override("separation", 14)
	_vbox.add_child(container)

	# ── inline helpers ────────────────────────────────────────────────────────

	var _h := func(text: String) -> Label:
		var h := Label.new()
		h.text = text
		h.set_meta("settings_role", "heading")
		h.add_theme_font_size_override("font_size", 18)
		return h

	var _hint := func(text: String) -> Label:
		var h := Label.new()
		h.text = text
		h.set_meta("settings_role", "hint")
		h.add_theme_font_size_override("font_size", 11)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD
		return h

	var _toggle := func(label_text: String, current_val: bool, cb: Callable) -> HBoxContainer:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = label_text
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var check := CheckButton.new()
		check.button_pressed = current_val
		check.toggled.connect(cb)
		row.add_child(check)
		return row

	# ── Screen Reader (AccessKit) ─────────────────────────────────────────────
	container.add_child(_h.call(tr("Screen Reader")))

	var sr_on: bool = saved.get("screen_reader", false)
	container.add_child(_toggle.call(tr("Enable screen reader (AccessKit)"), sr_on,
		func(on: bool):
			_save_accessibility("screen_reader", on)
			_apply_screen_reader(on)
	))
	container.add_child(_hint.call(
		tr("Exposes UI elements to OS screen readers via AccessKit. ") +
		tr("Requires Godot's DisplayServer accessibility API (4.3+). ") +
		tr("Changes take effect immediately — no restart needed.")
	))

	var sr_verbosity_row := HBoxContainer.new()
	var sr_v_lbl := Label.new()
	sr_v_lbl.text = tr("Verbosity")
	sr_v_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr_verbosity_row.add_child(sr_v_lbl)
	var sr_option := OptionButton.new()
	sr_option.add_item(tr("All controls"))
	sr_option.add_item(tr("Focused only"))
	sr_option.add_item(tr("Off"))
	var sr_verbosity: int = saved.get("screen_reader_verbosity", 0)
	sr_option.selected = sr_verbosity
	sr_option.item_selected.connect(func(idx: int):
		_save_accessibility("screen_reader_verbosity", idx)
		_apply_screen_reader(saved.get("screen_reader", false))
	)
	ThemeManager.style_option_button(sr_option)
	sr_verbosity_row.add_child(sr_option)
	container.add_child(sr_verbosity_row)

	# ── Vision ────────────────────────────────────────────────────────────────
	container.add_child(_h.call(tr("Vision")))

	# Readable font selector
	var font_row := HBoxContainer.new()
	font_row.add_theme_constant_override("separation", 8)
	var font_lbl := Label.new()
	font_lbl.text = tr("Reading font")
	font_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	font_row.add_child(font_lbl)
	var font_option := OptionButton.new()
	font_option.add_item(tr("Default (Cormorant Garamond)"))
	font_option.add_item(tr("DM Sans"))
	font_option.add_item(tr("OpenDyslexic"))
	font_option.add_item(tr("Atkinson Hyperlegible"))
	# Additional fonts disabled - Godot 4.x font rendering issues
	# font_option.add_item("Spectral")
	# font_option.add_item("Satoshi")
	# font_option.add_item("MonaSans")
	var font_choice: int = saved.get("reading_font", 0)
	font_option.selected = font_choice
	font_option.item_selected.connect(func(idx: int):
		_save_accessibility("reading_font", idx)
		ThemeManager.set_reading_font(idx)
		_emit_accessibility_event("reading_font", idx)
	)
	ThemeManager.style_option_button(font_option)
	font_row.add_child(font_option)
	container.add_child(font_row)
	container.add_child(_hint.call(
		tr("OpenDyslexic and Atkinson Hyperlegible are designed for improved legibility. ") +
		tr("Fonts must be present at:") + "\n" +
		"• res://assets/fonts/OpenDyslexic/OpenDyslexic-Regular.otf\n" +
		"• res://assets/fonts/AtkinsonHyperlegible/AtkinsonHyperlegible-Regular.ttf"
	))

	# High-contrast exhibit text
	var hc_on: bool = saved.get("high_contrast_text", false)
	container.add_child(_toggle.call(tr("High-contrast exhibit text"), hc_on,
		func(on: bool):
			_save_accessibility("high_contrast_text", on)
			_emit_accessibility_event("high_contrast_text", on)
	))
	container.add_child(_hint.call(
		tr("Renders article wall-card text as black-on-white regardless of dark mode.")))

	# Exhibit text size
	var ts: float = saved.get("exhibit_text_size", 1.0)
	var ts_val := Label.new()
	ts_val.custom_minimum_size = Vector2(44, 0)
	ts_val.text = "%.0f%%" % (ts * 100.0)
	var ts_slider := HSlider.new()
	ts_slider.min_value = 0.5; ts_slider.max_value = 2.0; ts_slider.step = 0.1
	ts_slider.value = ts; ts_slider.custom_minimum_size = Vector2(180, 0)
	var ts_reset := Button.new()
	ts_reset.text = tr("Reset"); ts_reset.custom_minimum_size = Vector2(54, 0)
	ts_reset.pressed.connect(func(): ts_slider.value = 1.0)
	ts_slider.value_changed.connect(func(v: float):
		ts_val.text = "%.0f%%" % (v * 100.0)
		_save_accessibility("exhibit_text_size", v)
		_emit_accessibility_event("exhibit_text_size", v)
	)
	var ts_row := HBoxContainer.new()
	ts_row.add_theme_constant_override("separation", 8)
	var ts_lbl := Label.new(); ts_lbl.text = tr("Exhibit text size")
	ts_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ts_row.add_child(ts_lbl); ts_row.add_child(ts_slider)
	ts_row.add_child(ts_val); ts_row.add_child(ts_reset)
	container.add_child(ts_row)
	container.add_child(_hint.call(tr("Scales the font size of Wikipedia article text on exhibit walls.")))

	# Floating exhibit signs (race-friendly mode)
	var fs_on: bool = saved.get("floating_signs", false)
	container.add_child(_toggle.call(tr("Floating exhibit signs"), fs_on,
		func(on: bool):
			_save_accessibility("floating_signs", on)
			_emit_accessibility_event("floating_signs", on)
	))
	container.add_child(_hint.call(
		tr("Replaces physical sign boards with floating text. ") +
		tr("Text remains visible but the board mesh is hidden. ") +
		tr("Makes exhibit names easier to read during races.")))

	# ── Colour & Contrast ─────────────────────────────────────────────────────
	container.add_child(_h.call(tr("Colour & Contrast")))

	var cb_row := HBoxContainer.new()
	cb_row.add_theme_constant_override("separation", 8)
	var cb_lbl := Label.new()
	cb_lbl.text = tr("Colourblind filter")
	cb_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb_row.add_child(cb_lbl)
	var cb_option := OptionButton.new()
	cb_option.add_item(tr("None"))
	cb_option.add_item(tr("Protanopia  (red-blind)"))
	cb_option.add_item(tr("Deuteranopia  (green-blind)"))
	cb_option.add_item(tr("Tritanopia  (blue-blind)"))
	var cb_mode: int = saved.get("colorblind_mode", 0)
	cb_option.selected = cb_mode
	cb_option.item_selected.connect(func(idx: int):
		_save_accessibility("colorblind_mode", idx)
		_apply_colorblind_filter(idx)
	)
	ThemeManager.style_option_button(cb_option)
	cb_row.add_child(cb_option)
	container.add_child(cb_row)
	container.add_child(_hint.call(
		tr("Applies a full-screen post-processing shader to correct for colour vision deficiency. ") +
		tr("Requires the shader at res://assets/shaders/colorblind_correction.gdshader and a ") +
		tr("CanvasLayer + ColorRect named ColorblindOverlay in your main scene.")
	))

	# Apply saved colorblind filter on load
	if cb_mode > 0:
		_apply_colorblind_filter(cb_mode)

	# ── Motion ────────────────────────────────────────────────────────────────
	container.add_child(_h.call(tr("Motion")))

	var rm_on: bool = saved.get("reduce_motion", false)
	container.add_child(_toggle.call(tr("Reduce motion"), rm_on,
		func(on: bool):
			_save_accessibility("reduce_motion", on)
			_emit_accessibility_event("reduce_motion", on)
	))
	container.add_child(_hint.call(
		tr("Disables slide/fade animations on menus and the race HUD. Fog transitions remain.")))

	# ── HUD & Hints ───────────────────────────────────────────────────────────
	container.add_child(_h.call(tr("HUD & Hints")))

	var lh_on: bool = saved.get("large_hud_text", false)
	container.add_child(_toggle.call(tr("Large HUD text"), lh_on,
		func(on: bool):
			_save_accessibility("large_hud_text", on)
			_emit_accessibility_event("large_hud_text", on)
	))
	container.add_child(_hint.call(tr("Increases font size of the race timer, target name, and hint banners.")))

	var ph_on: bool = saved.get("persistent_hints", false)
	container.add_child(_toggle.call(tr("Keep hints visible"), ph_on,
		func(on: bool):
			_save_accessibility("persistent_hints", on)
			_emit_accessibility_event("persistent_hints", on)
	))
	container.add_child(_hint.call(
		tr("Hint banners stay on screen until the race ends instead of fading after a few seconds.")))

	# ── Audio & Visual ─────────────────────────────────────────────────────────
	container.add_child(_h.call(tr("Audio & Visual")))

	var avi_on: bool = saved.get("audio_visual_indicator", false)
	container.add_child(_toggle.call(tr("Show playing audio indicator"), avi_on,
		func(on: bool):
			_save_accessibility("audio_visual_indicator", on)
			_emit_accessibility_event("audio_visual_indicator", on)
	))
	container.add_child(_hint.call(
		tr("Displays a visual icon when audio items are playing. Helps deaf/hard-of-hearing players.")))

	var psw_on: bool = saved.get("photosensitivity_warning", true)
	container.add_child(_toggle.call(tr("Photosensitivity warning"), psw_on,
		func(on: bool):
			_save_accessibility("photosensitivity_warning", on)
			_emit_accessibility_event("photosensitivity_warning", on)
	))
	container.add_child(_hint.call(
		tr("Shows a warning before exhibits with flashing or strobing content.")))

	# HUD Opacity
	var ho: float = saved.get("hud_opacity", 1.0)
	var ho_val := Label.new()
	ho_val.custom_minimum_size = Vector2(44, 0)
	ho_val.text = "%.0f%%" % (ho * 100.0)
	var ho_slider := HSlider.new()
	ho_slider.min_value = 0.3; ho_slider.max_value = 1.0; ho_slider.step = 0.1
	ho_slider.value = ho; ho_slider.custom_minimum_size = Vector2(180, 0)
	var ho_reset := Button.new()
	ho_reset.text = tr("Reset"); ho_reset.custom_minimum_size = Vector2(54, 0)
	ho_reset.pressed.connect(func(): ho_slider.value = 1.0)
	ho_slider.value_changed.connect(func(v: float):
		ho_val.text = "%.0f%%" % (v * 100.0)
		_save_accessibility("hud_opacity", v)
		_emit_accessibility_event("hud_opacity", v)
	)
	var ho_row := HBoxContainer.new()
	ho_row.add_theme_constant_override("separation", 8)
	var ho_lbl := Label.new(); ho_lbl.text = tr("HUD opacity")
	ho_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ho_row.add_child(ho_lbl); ho_row.add_child(ho_slider)
	ho_row.add_child(ho_val); ho_row.add_child(ho_reset)
	container.add_child(ho_row)
	container.add_child(_hint.call(tr("Makes the race HUD more transparent to see more of the game world.")))

	# ── Motor ────────────────────────────────────────────────────────────────────
	container.add_child(_h.call(tr("Motor")))

	var htc_on: bool = saved.get("hold_to_click", false)
	container.add_child(_toggle.call(tr("Hold to activate buttons"), htc_on,
		func(on: bool):
			_save_accessibility("hold_to_click", on)
			_emit_accessibility_event("hold_to_click", on)
	))
	container.add_child(_hint.call(
		tr("Buttons require holding for 0.5s instead of clicking. Helps with motor control issues.")))

	# Secret Disco Button
	var disco_row := HBoxContainer.new()
	disco_row.alignment = BoxContainer.ALIGNMENT_END
	var disco_btn := Button.new()
	disco_btn.text = "°" # Very tiny secret
	disco_btn.flat = true
	disco_btn.modulate.a = 0.2
	disco_btn.pressed.connect(func():
		ThemeManager.set_disco_mode(not ThemeManager.disco_mode)
		Log.info("Settings", "🕺 Disco Mode: %s" % ThemeManager.disco_mode)
	)
	disco_row.add_child(disco_btn)
	container.add_child(disco_row)

	_tab_bar.add_tab(tr("Accessibility"))
	return container


func _apply_screen_reader(enabled: bool) -> void:
	## Activates AccessKit via Godot 4.3+ DisplayServer accessibility API.
	## Falls back gracefully on older builds.
	if DisplayServer.has_feature(DisplayServer.FEATURE_ACCESSIBILITY_SCREEN_READER):
		# Use call() to invoke the instance method on the DisplayServer singleton.
		# Direct static-style calls like DisplayServer.accessibility_screen_reader_is_active()
		# don't work because it's an instance method, not a static method.
		var _currently_active: bool = false
		if DisplayServer.has_method("accessibility_screen_reader_is_active"):
			_currently_active = DisplayServer.call("accessibility_screen_reader_is_active")
		# The standard way to toggle AccessKit in Godot 4.3+:
		# Project Settings > accessibility/accessibility_support must be "Always"
		# or "When Screen Reader Found". We emit the event so other nodes can
		# also respond (e.g. add aria-label equivalents to their controls).
		_emit_accessibility_event("screen_reader", enabled)
	else:
		push_warning("Settings: AccessKit screen reader requires Godot 4.3+ DisplayServer. " +
			"Enable Project Settings > accessibility/accessibility_support.")
	_emit_accessibility_event("screen_reader", enabled)


func _apply_colorblind_filter(mode: int) -> void:
	_emit_accessibility_event("colorblind_mode", mode)


func _save_accessibility(key: String, value: Variant) -> void:
	var data: Dictionary = SettingsManager.get_settings("accessibility") if SettingsManager.get_settings("accessibility") else {}
	data[key] = value
	SettingsManager.save_settings("accessibility", data)


func _emit_accessibility_event(key: String, value: Variant) -> void:
	## Fires SettingsEvents.accessibility_changed if the signal exists.
	## Add  `signal accessibility_changed(key: String, value: Variant)`
	if SettingsEvents.has_signal("accessibility_changed"):
		SettingsEvents.accessibility_changed.emit(key, value)
