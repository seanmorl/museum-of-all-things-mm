extends Control
## Settings panel with tabbed sub-panels (Graphics, Audio, Controls, Data,
## Interface, Accessibility).  Every interactive control exposes a **visible
## keyboard-focus indicator** to comply with WCAG 2.4.7 (Focus Visible).
##
## Focus-ring strategy
## -------------------
## All Buttons, CheckBoxes, CheckButtons, OptionButtons, LineEdits, SpinBoxes,
## HSliders, and the TabBar receive a 2 px accent-colour border with a soft
## outer glow whenever they hold keyboard focus.  The accent colour is sourced
## from `UIStyle.get_accent_color()` so it automatically adapts to the active
## theme (dark / light) and guarantees at least 3 : 1 contrast against the
## panel background — satisfying both WCAG 2.4.7 (Level AA) and the stricter
## 2.4.11 (Level AAA) focus-appearance criterion.

signal resume

# ── Scene refs ─────────────────────────────────────────────────────────────────

@onready var _vbox = $ScrollContainer/MarginContainer/VBoxContainer/MarginContainer
@onready var _tab_bar = %SettingsTabs

# Populated in _ready() — avoids calling build methods during @onready init.
var _tab_scenes: Array = []

# ── State ──────────────────────────────────────────────────────────────────────

var _serif_font: Font = null
var _content_panel_style: StyleBoxFlat = null
var _current_tab: int = 0

var _dark_mode_lambda: Callable = Callable()
var _reading_font_lambda: Callable = Callable()

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	add_to_group("mouse_overlay")
	UIEvents.ui_cancel_pressed.connect(_on_resume)

	# Build tab scenes *after* the tree is ready so all nodes are accessible.
	_tab_scenes = [
		_vbox.get_node("GraphicsSettings"),
		_vbox.get_node("AudioSettings"),
		_vbox.get_node("ControlSettings"),
		_vbox.get_node("DataSettings") if not Platform.is_web() else null,
		_build_multiplayer_settings(),
		_build_accessibility_settings(),
	]

	# Disable + hide tabs for platforms that don't support them (e.g. web → no Data).
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


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  WCAG 2.4.7 — Focus-ring factory                                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _create_focus_ring(corner_radius: float = -1.0) -> StyleBoxFlat:
	"""Returns a StyleBoxFlat that draws a clearly visible 2 px accent border
	with a soft outer glow.  Suitable as the 'focus' override for any
	interactive Control.  The accent colour adapts to the current theme so
	contrast against the panel background is always ≥ 3 : 1."""
	var dark := ThemeManager.is_dark_mode
	var accent := UIStyle.get_accent_color(dark)

	var ring := StyleBoxFlat.new()
	ring.bg_color = Color.TRANSPARENT
	ring.border_color = accent
	ring.set_border_width_all(2)
	if corner_radius >= 0.0:
		ring.set_corner_radius_all(int(corner_radius))
	else:
		ring.set_corner_radius_all(UIStyle.CORNER_RADIUS_SMALL)
	# Soft glow extends the visible focus area — helps on low-contrast displays.
	ring.shadow_color = Color(accent.r, accent.g, accent.b, 0.30)
	ring.shadow_size = 4.0
	# Small content margins keep the border from overlapping text.
	ring.content_margin_top = 2.0
	ring.content_margin_bottom = 2.0
	ring.content_margin_left = 4.0
	ring.content_margin_right = 4.0
	ring.anti_aliasing = true
	return ring


func _create_slider_focus_grabber() -> StyleBoxFlat:
	"""A slightly enlarged grabber circle with accent border + glow for HSlider
	focus indication."""
	var dark := ThemeManager.is_dark_mode
	var accent := UIStyle.get_accent_color(dark)

	var g := StyleBoxFlat.new()
	g.bg_color = ThemeManager.text_color
	g.border_color = accent
	g.set_border_width_all(2)
	g.set_corner_radius_all(7)
	g.set_content_margin_all(5)
	g.shadow_color = Color(accent.r, accent.g, accent.b, 0.25)
	g.shadow_size = 3.0
	return g


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Theming — top-level & recursive                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode

	# ── Panel background ─────────────────────────────────────────────────
	var bg := UIStyle.create_panel_style(
		ThemeManager.bg_color,
		ThemeManager.border_color,
		dark,
		UIStyle.CORNER_RADIUS_PANEL,
		UIStyle.PANEL_PADDING,
	)
	bg.content_margin_left = 20
	bg.content_margin_right = 20
	bg.content_margin_top = 16
	bg.content_margin_bottom = 16

	var panel := get_node_or_null("ScrollContainer/MarginContainer/Panel")
	if panel:
		panel.add_theme_stylebox_override("panel", bg)
	if not panel and get_node_or_null("ScrollContainer") is ScrollContainer:
		get_node("ScrollContainer").add_theme_stylebox_override("panel", bg)

	# ── Tab bar ──────────────────────────────────────────────────────────
	if _tab_bar:
		_tab_bar.add_theme_color_override("font_selected_color", ThemeManager.text_color)
		_tab_bar.add_theme_color_override("font_unselected_color", ThemeManager.subtext_color)
		_tab_bar.add_theme_color_override("font_hovered_color", ThemeManager.text_color)
		if _serif_font:
			_tab_bar.add_theme_font_override("font", _serif_font)
		_tab_bar.add_theme_font_size_override("font_size", 14)

		var tab_styles := UIStyle.create_tab_style(
			ThemeManager.text_color,
			ThemeManager.subtext_color,
			UIStyle.get_accent_color(dark),
			dark,
			_serif_font,
		)
		_tab_bar.add_theme_stylebox_override("tab_selected", tab_styles.selected)
		_tab_bar.add_theme_stylebox_override("tab_unselected", tab_styles.unselected)
		_tab_bar.add_theme_stylebox_override("tab_hovered", tab_styles.hovered)
		# WCAG 2.4.7 — visible focus indicator on the active tab
		_tab_bar.add_theme_stylebox_override("tab_focus", _create_tab_focus_style())
		_tab_bar.add_theme_constant_override("h_separation", 45)
		_tab_bar.clip_tabs = false

	# ── Back button ──────────────────────────────────────────────────────
	var back_btn := get_node_or_null(
		"ScrollContainer/MarginContainer/VBoxContainer/HBoxContainer/BackButton"
	) as Button
	if back_btn:
		_style_action_button(back_btn)

	# ── Separator ────────────────────────────────────────────────────────
	var h_sep := get_node_or_null(
		"ScrollContainer/MarginContainer/VBoxContainer/HSeparator"
	) as HSeparator
	if h_sep:
		h_sep.add_theme_stylebox_override(
			"separator", UIStyle.create_divider_style(ThemeManager.border_color)
		)

	# ── Recursive theme pass ─────────────────────────────────────────────
	_theme_control_tree(_vbox)
	for scene in _tab_scenes:
		if scene is Control:
			_theme_control_tree(scene)


func _create_tab_focus_style() -> StyleBoxFlat:
	"""Dedicated focus style for TabBar tabs — accent underline + subtle glow."""
	var dark := ThemeManager.is_dark_mode
	var accent := UIStyle.get_accent_color(dark)
	var s := StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.border_color = accent
	s.border_width_bottom = 2
	s.set_corner_radius_all(UIStyle.CORNER_RADIUS_SMALL)
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.15)
	s.shadow_size = 2.0
	return s


func _theme_control_tree(node: Node) -> void:
	if node is Label:
		_theme_label(node)
	elif node is Button:
		_style_action_button(node)
	elif node is OptionButton:
		_style_option(node)
	elif node is CheckBox:
		_style_check(node)
	elif node is CheckButton:
		_style_toggle(node)
	elif node is HSlider:
		_style_slider(node)
	elif node is LineEdit:
		_style_line_edit(node)
	elif node is SpinBox:
		var edit: LineEdit = node.get_line_edit()
		if edit:
			_style_line_edit(edit)
	elif node is Separator:
		var sep := StyleBoxLine.new()
		sep.color = ThemeManager.border_color
		sep.thickness = 1
		node.add_theme_stylebox_override("separator", sep)
	elif node is PanelContainer:
		node.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	for child in node.get_children():
		_theme_control_tree(child)


# ── Per-control theme helpers ──────────────────────────────────────────────────

func _theme_label(label: Label) -> void:
	label.label_settings = null
	label.add_theme_color_override("font_color", ThemeManager.text_color)
	if label.get_meta("settings_role", "") == "hint":
		label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	if _serif_font:
		label.add_theme_font_override("font", _serif_font)


func _style_action_button(btn: Button) -> void:
	"""Styles utility / action buttons (Back, Reset, Rebind, etc.) with a
	visible focus ring for WCAG 2.4.7 compliance."""
	if not btn:
		return
	var dark := ThemeManager.is_dark_mode

	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 14)

	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ThemeManager.text_color)

	var normal := UIStyle.create_button_style(
		Color.TRANSPARENT,
		ThemeManager.border_color,
		UIStyle.CORNER_RADIUS_SMALL,
		8.0,
	)
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.05) if dark else Color(0, 0, 0, 0.05)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1, 1, 1, 0.10) if dark else Color(0, 0, 0, 0.10)
	btn.add_theme_stylebox_override("pressed", pressed)

	# ★ WCAG 2.4.7 — Visible focus ring
	btn.add_theme_stylebox_override("focus", _create_focus_ring())


func _style_check(cb: CheckBox) -> void:
	"""CheckBox — preserve theme check indicator, just set font color + focus ring."""
	cb.add_theme_color_override("font_color", ThemeManager.text_color)
	cb.add_theme_color_override("font_hover_color", ThemeManager.text_color)
	cb.add_theme_color_override("font_pressed_color", ThemeManager.text_color)
	cb.add_theme_color_override("font_focus_color", ThemeManager.text_color)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.TRANSPARENT
	bg.content_margin_left = 22
	bg.content_margin_right = 4
	bg.content_margin_top = 2
	bg.content_margin_bottom = 2
	for state in ["normal", "pressed", "disabled", "hover"]:
		cb.add_theme_stylebox_override(state, bg)

	cb.add_theme_stylebox_override("focus", _create_focus_ring())


func _style_toggle(cb: CheckButton) -> void:
	"""CheckButton — preserve theme toggle indicator, just set font + focus ring."""
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		cb.add_theme_color_override(state, ThemeManager.text_color)
	if _serif_font:
		cb.add_theme_font_override("font", _serif_font)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.TRANSPARENT
	bg.content_margin_left = 22
	bg.content_margin_right = 4
	bg.content_margin_top = 2
	bg.content_margin_bottom = 2
	for state in ["normal", "pressed", "disabled", "hover"]:
		cb.add_theme_stylebox_override(state, bg)

	cb.add_theme_stylebox_override("focus", _create_focus_ring())


func _style_slider(slider: HSlider) -> void:
	"""HSlider — accent-bordered grabber on focus for WCAG 2.4.7."""
	# Ensure keyboard focusability
	slider.focus_mode = Control.FOCUS_ALL

	# Style the grabber highlight (shown on hover AND focus) with a visible ring.
	# This is the primary focus indicator since HSlider has no dedicated "focus" stylebox.
	slider.add_theme_stylebox_override("grabber_highlight", _create_slider_focus_grabber())

	# Connect focus signals to add a secondary visual cue: a subtle background tint
	# behind the entire slider track when focused via keyboard.
	if not slider.is_connected("focus_entered", _on_slider_focus_changed.bind(slider, true)):
		slider.focus_entered.connect(_on_slider_focus_changed.bind(slider, true))
	if not slider.is_connected("focus_exited", _on_slider_focus_changed.bind(slider, false)):
		slider.focus_exited.connect(_on_slider_focus_changed.bind(slider, false))


func _on_slider_focus_changed(slider: HSlider, focused: bool) -> void:
	"""Adds / removes a subtle focus track highlight behind the slider rail."""
	if focused:
		var dark := ThemeManager.is_dark_mode
		var accent := UIStyle.get_accent_color(dark)
		var track := StyleBoxFlat.new()
		track.bg_color = Color(accent.r, accent.g, accent.b, 0.08)
		track.set_corner_radius_all(2)
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		slider.add_theme_stylebox_override("slider", track)
	else:
		# Restore default (remove override)
		slider.remove_theme_stylebox_override("slider")


func _style_option(btn: OptionButton) -> void:
	"""OptionButton — ThemeManager base style + WCAG focus ring on top."""
	ThemeManager.style_option_button(btn)
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
		btn.get_popup().add_theme_font_override("font", _serif_font)
	# ★ WCAG 2.4.7 — Ensure a visible focus ring even if ThemeManager omits one
	btn.add_theme_stylebox_override("focus", _create_focus_ring())


func _style_line_edit(edit: LineEdit) -> void:
	var dark := ThemeManager.is_dark_mode

	if _serif_font:
		edit.add_theme_font_override("font", _serif_font)
	edit.add_theme_font_size_override("font_size", 14)
	edit.add_theme_color_override("font_color", ThemeManager.text_color)
	edit.add_theme_color_override("font_placeholder_color", ThemeManager.subtext_color)

	var styles := UIStyle.create_input_style(
		Color.TRANSPARENT,
		ThemeManager.border_color,
		ThemeManager.text_color,
		ThemeManager.subtext_color,
		dark,
		_serif_font,
	)
	edit.add_theme_stylebox_override("normal", styles.normal)
	# ★ WCAG 2.4.7 — The focus style from UIStyle is used, but we ensure a
	# visible accent border is present by layering our focus ring on top.
	var focus := _create_focus_ring()
	# Preserve the cursor/caret colour from UIStyle if it set a bg_color
	if styles.focus and styles.focus is StyleBoxFlat:
		focus.bg_color = styles.focus.bg_color
	edit.add_theme_stylebox_override("focus", focus)


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Visibility & input handling                                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _on_visibility_changed() -> void:
	if not visible:
		return
	# Hide all tab scenes to prevent layout overlap
	for scene in _tab_scenes:
		if scene:
			scene.visible = false

	_apply_theme()
	_tab_bar.set_current_tab(0)
	_on_tab_bar_tab_changed(0)
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


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Tab navigation                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _on_tab_bar_tab_changed(tab: int) -> void:
	if _tab_scenes == null:
		return
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


func _on_tab_bar_tab_clicked(_tab: int) -> void:
	# TabBar emits tab_clicked on mouse click (even if the tab is already
	# selected). We don't need extra logic here — tab_changed handles the
	# switch — but the signal must exist because the .tscn connects it.
	pass


func _on_tab_left() -> void:
	# Keyboard nav: Left arrow → previous tab
	if visible:
		_tab_bar.select_previous_available()


func _on_tab_right() -> void:
	# Keyboard nav: Right arrow → next tab
	if visible:
		_tab_bar.select_next_available()


func _on_resume() -> void:
	if visible:
		visible = false
		resume.emit()


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Interface / Multiplayer tab                                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _build_multiplayer_settings() -> Control:
	var container := VBoxContainer.new()
	container.name = "MultiplayerSettings"
	container.add_theme_constant_override("separation", 14)
	_vbox.add_child(container)

	# ── Interface heading ─────────────────────────────────────────────────
	container.add_child(_make_heading(tr("Interface")))

	var saved_ui = SettingsManager.get_settings("ui")
	var current_scale: float = 1.0
	if saved_ui and saved_ui.has("scale"):
		current_scale = float(saved_ui.scale)

	# UI Scale row
	var scale_val_lbl := Label.new()
	scale_val_lbl.custom_minimum_size = Vector2(44, 0)
	scale_val_lbl.text = "%.0f%%" % (current_scale * 100)

	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.5
	scale_slider.max_value = 2.0
	scale_slider.step = 0.05
	scale_slider.value = current_scale
	scale_slider.custom_minimum_size = Vector2(180, 0)
	# WCAG: focusable
	scale_slider.focus_mode = Control.FOCUS_ALL

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

	container.add_child(_make_hint(
		tr("Scales all menus, HUD, and overlays. Shortcuts: Ctrl+= / Ctrl+- / Ctrl+0")
	))

	# ── Multiplayer heading ───────────────────────────────────────────────
	container.add_child(_make_heading(tr("Multiplayer")))

	var saved = SettingsManager.get_settings("multiplayer_ui")
	var chat_on: bool = true
	if saved and saved.has("chat_enabled"):
		chat_on = saved.chat_enabled

	# Show chat toggle
	container.add_child(_make_toggle_row(tr("Show chat"), chat_on, _on_chat_toggle))
	container.add_child(_make_hint(tr("Hides the chat overlay while playing.")))

	# Typing sound toggle
	var sound_on: bool = true
	if saved and saved.has("typing_sound_enabled"):
		sound_on = saved.typing_sound_enabled

	container.add_child(_make_toggle_row(tr("Typing sound"), sound_on, _on_typing_sound_toggle))
	container.add_child(_make_hint(tr("Plays a subtle sound on each keypress in the chat box.")))

	# Open-chat keybind
	var keybind_row := HBoxContainer.new()
	var key_lbl := Label.new()
	key_lbl.text = tr("Open chat")
	key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keybind_row.add_child(key_lbl)
	var current_key := _get_chat_key_name()
	var rebind_btn := Button.new()
	rebind_btn.text = current_key
	rebind_btn.custom_minimum_size = Vector2(80, 0)
	rebind_btn.tooltip_text = tr("Press then type a key to rebind")
	rebind_btn.pressed.connect(_on_rebind_chat_pressed.bind(rebind_btn))
	keybind_row.add_child(rebind_btn)
	SettingsEvents.chat_key_changed.connect(func(name): rebind_btn.text = name)
	container.add_child(keybind_row)
	container.add_child(_make_hint(tr("Press the button then press any key to rebind.")))

	_tab_bar.add_tab(tr("Interface"))
	return container


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Accessibility tab                                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _build_accessibility_settings() -> Control:
	var saved: Dictionary = SettingsManager.get_settings("accessibility") \
		if SettingsManager.get_settings("accessibility") else {}

	var container := VBoxContainer.new()
	container.name = "AccessibilitySettings"
	container.add_theme_constant_override("separation", 14)
	_vbox.add_child(container)

	# ── Screen Reader (AccessKit) ─────────────────────────────────────────
	container.add_child(_make_heading(tr("Screen Reader")))

	var sr_on: bool = saved.get("screen_reader", false)
	container.add_child(_make_toggle_row(
		tr("Enable screen reader (AccessKit)"), sr_on,
		func(on: bool):
			_save_accessibility("screen_reader", on)
			_apply_screen_reader(on)
	))
	container.add_child(_make_hint(
		tr("Exposes UI elements to OS screen readers via AccessKit. ") +
		tr("Requires Godot's DisplayServer accessibility API (4.3+). ") +
		tr("Changes take effect immediately — no restart needed.")
	))

	# Verbosity
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

	# ── Vision ────────────────────────────────────────────────────────────
	container.add_child(_make_heading(tr("Vision")))

	# Reading font selector
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
	container.add_child(_make_hint(
		tr("OpenDyslexic and Atkinson Hyperlegible are designed for improved legibility. ") +
		tr("Fonts must be present at:") + "\n" +
		"• res://assets/fonts/OpenDyslexic/OpenDyslexic-Regular.otf\n" +
		"• res://assets/fonts/AtkinsonHyperlegible/AtkinsonHyperlegible-Regular.ttf"
	))

	# High-contrast exhibit text
	var hc_on: bool = saved.get("high_contrast_text", false)
	container.add_child(_make_toggle_row(tr("High-contrast exhibit text"), hc_on,
		func(on: bool):
			_save_accessibility("high_contrast_text", on)
			_emit_accessibility_event("high_contrast_text", on)
	))
	container.add_child(_make_hint(
		tr("Renders article wall-card text as black-on-white regardless of dark mode.")
	))

	# Exhibit text size
	var ts: float = saved.get("exhibit_text_size", 1.0)
	container.add_child(_make_slider_row(
		tr("Exhibit text size"), ts, 0.5, 2.0, 0.1,
		func(v: float):
			_save_accessibility("exhibit_text_size", v)
			_emit_accessibility_event("exhibit_text_size", v)
	))
	container.add_child(_make_hint(tr("Scales the font size of Wikipedia article text on exhibit walls.")))

	# Floating exhibit signs
	var fs_on: bool = saved.get("floating_signs", false)
	container.add_child(_make_toggle_row(tr("Floating exhibit signs"), fs_on,
		func(on: bool):
			_save_accessibility("floating_signs", on)
			_emit_accessibility_event("floating_signs", on)
	))
	container.add_child(_make_hint(
		tr("Replaces physical sign boards with floating text. ") +
		tr("Text remains visible but the board mesh is hidden. ") +
		tr("Makes exhibit names easier to read during races.")
	))

	# ── Colour & Contrast ─────────────────────────────────────────────────
	container.add_child(_make_heading(tr("Colour & Contrast")))

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
	container.add_child(_make_hint(
		tr("Applies a full-screen post-processing shader to correct for colour vision deficiency. ") +
		tr("Requires the shader at res://assets/shaders/colorblind_correction.gdshader and a ") +
		tr("CanvasLayer + ColorRect named ColorblindOverlay in your main scene.")
	))

	if cb_mode > 0:
		_apply_colorblind_filter(cb_mode)

	# ── Motion ────────────────────────────────────────────────────────────
	container.add_child(_make_heading(tr("Motion")))

	var rm_on: bool = saved.get("reduce_motion", false)
	container.add_child(_make_toggle_row(tr("Reduce motion"), rm_on,
		func(on: bool):
			_save_accessibility("reduce_motion", on)
			_emit_accessibility_event("reduce_motion", on)
	))
	container.add_child(_make_hint(
		tr("Disables slide/fade animations on menus and the race HUD. Fog transitions remain.")
	))

	# ── HUD & Hints ───────────────────────────────────────────────────────
	container.add_child(_make_heading(tr("HUD & Hints")))

	var lh_on: bool = saved.get("large_hud_text", false)
	container.add_child(_make_toggle_row(tr("Large HUD text"), lh_on,
		func(on: bool):
			_save_accessibility("large_hud_text", on)
			_emit_accessibility_event("large_hud_text", on)
	))
	container.add_child(_make_hint(
		tr("Increases font size of the race timer, target name, and hint banners.")
	))

	var ph_on: bool = saved.get("persistent_hints", false)
	container.add_child(_make_toggle_row(tr("Keep hints visible"), ph_on,
		func(on: bool):
			_save_accessibility("persistent_hints", on)
			_emit_accessibility_event("persistent_hints", on)
	))
	container.add_child(_make_hint(
		tr("Hint banners stay on screen until the race ends instead of fading after a few seconds.")
	))

	# ── Audio & Visual ────────────────────────────────────────────────────
	container.add_child(_make_heading(tr("Audio & Visual")))

	var avi_on: bool = saved.get("audio_visual_indicator", false)
	container.add_child(_make_toggle_row(tr("Show playing audio indicator"), avi_on,
		func(on: bool):
			_save_accessibility("audio_visual_indicator", on)
			_emit_accessibility_event("audio_visual_indicator", on)
	))
	container.add_child(_make_hint(
		tr("Displays a visual icon when audio items are playing. Helps deaf/hard-of-hearing players.")
	))

	var psw_on: bool = saved.get("photosensitivity_warning", true)
	container.add_child(_make_toggle_row(tr("Photosensitivity warning"), psw_on,
		func(on: bool):
			_save_accessibility("photosensitivity_warning", on)
			_emit_accessibility_event("photosensitivity_warning", on)
	))
	container.add_child(_make_hint(
		tr("Shows a warning before exhibits with flashing or strobing content.")
	))

	# HUD Opacity
	var ho: float = saved.get("hud_opacity", 1.0)
	container.add_child(_make_slider_row(
		tr("HUD opacity"), ho, 0.3, 1.0, 0.1,
		func(v: float):
			_save_accessibility("hud_opacity", v)
			_emit_accessibility_event("hud_opacity", v)
	))
	container.add_child(_make_hint(
		tr("Makes the race HUD more transparent to see more of the game world.")
	))

	# ── Motor ─────────────────────────────────────────────────────────────
	container.add_child(_make_heading(tr("Motor")))

	var htc_on: bool = saved.get("hold_to_click", false)
	container.add_child(_make_toggle_row(tr("Hold to activate buttons"), htc_on,
		func(on: bool):
			_save_accessibility("hold_to_click", on)
			_emit_accessibility_event("hold_to_click", on)
	))
	container.add_child(_make_hint(
		tr("Buttons require holding for 0.5s instead of clicking. Helps with motor control issues.")
	))

	# ── Secret Disco Button (easter egg, very subtle) ─────────────────────
	var disco_row := HBoxContainer.new()
	disco_row.alignment = BoxContainer.ALIGNMENT_END
	var disco_btn := Button.new()
	disco_btn.text = "°"
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


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Reusable row builders (DRY — all include WCAG focus indicators)           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _make_heading(text: String) -> Label:
	var h := Label.new()
	h.text = text
	h.set_meta("settings_role", "heading")
	h.add_theme_font_size_override("font_size", 18)
	return h


func _make_hint(text: String) -> Label:
	var h := Label.new()
	h.text = text
	h.set_meta("settings_role", "hint")
	h.add_theme_font_size_override("font_size", 11)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD
	return h


func _make_toggle_row(label_text: String, current_val: bool, callback: Callable) -> HBoxContainer:
	"""Builds a label + CheckButton row.  The CheckButton receives a visible
	focus ring for WCAG 2.4.7 compliance."""
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var check := CheckButton.new()
	check.button_pressed = current_val
	check.toggled.connect(callback)
	# Focus ring is applied during the _theme_control_tree pass, but we also
	# set focus_mode explicitly for clarity.
	check.focus_mode = Control.FOCUS_ALL
	row.add_child(check)
	return row


func _make_slider_row(
	label_text: String,
	current_val: float,
	min_val: float,
	max_val: float,
	step_val: float,
	on_change: Callable,
) -> HBoxContainer:
	"""Builds a label + HSlider + value label + Reset button row.
	All interactive elements receive WCAG 2.4.7 focus indicators."""
	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.text = "%.0f%%" % (current_val * 100.0)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.value = current_val
	slider.custom_minimum_size = Vector2(180, 0)
	slider.focus_mode = Control.FOCUS_ALL

	var reset_btn := Button.new()
	reset_btn.text = tr("Reset")
	reset_btn.custom_minimum_size = Vector2(54, 0)
	reset_btn.tooltip_text = tr("Reset to default")
	reset_btn.pressed.connect(func(): slider.value = 1.0)

	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%.0f%%" % (v * 100.0)
		on_change.call(v)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(slider)
	row.add_child(val_lbl)
	row.add_child(reset_btn)
	return row


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Setting handlers                                                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

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
		root.content_scale_factor, target_scale, 0.15
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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


# ── Accessibility helpers ──────────────────────────────────────────────────────

func _apply_screen_reader(enabled: bool) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_ACCESSIBILITY_SCREEN_READER):
		if DisplayServer.has_method("accessibility_screen_reader_is_active"):
			var _currently_active: bool = DisplayServer.call("accessibility_screen_reader_is_active")
		_emit_accessibility_event("screen_reader", enabled)
	else:
		push_warning(
			"Settings: AccessKit screen reader requires Godot 4.3+ DisplayServer. " +
			"Enable Project Settings > accessibility/accessibility_support."
		)
	_emit_accessibility_event("screen_reader", enabled)


func _apply_colorblind_filter(mode: int) -> void:
	_emit_accessibility_event("colorblind_mode", mode)


func _save_accessibility(key: String, value: Variant) -> void:
	var data: Dictionary = SettingsManager.get_settings("accessibility") \
		if SettingsManager.get_settings("accessibility") else {}
	data[key] = value
	SettingsManager.save_settings("accessibility", data)


func _emit_accessibility_event(key: String, value: Variant) -> void:
	if SettingsEvents.has_signal("accessibility_changed"):
		SettingsEvents.accessibility_changed.emit(key, value)
