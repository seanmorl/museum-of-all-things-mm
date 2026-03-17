extends Control

signal start
signal settings
signal start_multiplayer
signal start_dedicated_host

const _FONT_PATH := "res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf"

var _serif_font: Font = null
var _panel_style: StyleBoxFlat = null
var _button_container: VBoxContainer = null
var _patch_notes_popup: Control = null
var _patch_notes_panel: PanelContainer = null

# Original positions for repeatable entrance animation
var _vbox_orig_pos: Vector2 = Vector2.ZERO
var _logo_orig_y: float = 0.0
var _panel_orig_y: float = 0.0
var _positions_saved: bool = false

## Registry — every menu item described as a dict.
## To add a future feature, just add one register_item() call.
var _menu_items: Array[Dictionary] = []

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	_spawn_background()
	_register_default_items()
	_build_menu()
	_build_patch_notes_popup()
	_apply_theme()

	ThemeManager.dark_mode_changed.connect(func(_d):
		_update_dark_mode_text()
		_apply_theme()
	)
	ThemeManager.reading_font_changed.connect(func(f):
		_serif_font = f
		_apply_theme()
	)

	if Platform.is_web():
		var q = _button_container.get_node_or_null("Quit") if _button_container else null
		if q: q.visible = false

	call_deferred("_entrance_animation")

# ── Registry ──────────────────────────────────────────────────────────────────

func register_section(label: String) -> void:
	_menu_items.append({"type": "section", "label": label})

func register_item(icon: String, label: String, id: String, callback: Callable, primary: bool = false) -> void:
	_menu_items.append({
		"type": "button", "icon": icon, "label": label,
		"id": id, "callback": callback, "primary": primary,
	})

func register_widget(id: String, node: Control) -> void:
	_menu_items.append({"type": "widget", "id": id, "node": node})

func _register_default_items() -> void:
	register_section("PLAY")
	register_item("🏛", "Enter the Museum", "Start", _on_start_pressed, true)
	register_item("🌐", "Multiplayer", "Multiplayer", _on_multiplayer_pressed)

	register_section("OPTIONS")
	var dm_icon := "☀" if ThemeManager.is_dark_mode else "☾"
	register_item(dm_icon, _dark_mode_label(), "DarkMode", _on_dark_mode_pressed)
	register_item("⚙", "Settings", "Settings", _on_settings_pressed)
	register_item("📋", "Latest Changes", "PatchNotes", _show_patch_notes)

	register_section("SYSTEM")
	register_item("🖥", "Host Server", "DedicatedHost", _on_dedicated_host_pressed)
	var lang := load("res://scenes/menu/LanguageSelection.tscn").instantiate() as Control
	register_widget("Language", lang)
	register_item("✕", "Quit", "Quit", _on_quit_pressed)

# ── Build ─────────────────────────────────────────────────────────────────────

func _build_menu() -> void:
	var panel := get_node_or_null(
		"MarginContainer/CenterContainer/VBoxContainer/PanelContainer") as PanelContainer
	if not panel:
		return
	for c in panel.get_children():
		c.queue_free()

	# ScrollContainer so the menu can scroll if it overflows
	var scroll := ScrollContainer.new()
	scroll.name = "MenuScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	_button_container = VBoxContainer.new()
	_button_container.name = "ButtonContainer"
	_button_container.add_theme_constant_override("separation", 2)
	_button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_button_container)

	for item in _menu_items:
		match item["type"]:
			"section":
				_build_section(item["label"])
			"button":
				_build_button(item)
			"widget":
				if item.get("node"):
					_button_container.add_child(item["node"])


func _build_section(label_text: String) -> void:
	if _button_container.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 4)
		_button_container.add_child(spacer)

	var hdr := Label.new()
	hdr.name = "Section_" + label_text
	hdr.text = label_text
	hdr.add_theme_font_size_override("font_size", 10)
	hdr.add_theme_color_override("font_color", ThemeManager.subtext_color)
	if _serif_font:
		hdr.add_theme_font_override("font", _serif_font)
	_button_container.add_child(hdr)

	var sep := HSeparator.new()
	_button_container.add_child(sep)


func _build_button(item: Dictionary) -> void:
	var icon_str: String = item.get("icon", "")
	var label_str: String = item.get("label", "")
	var display_text := icon_str + "   " + label_str if icon_str != "" else label_str

	var btn := Button.new()
	btn.name = item["id"]
	btn.text = display_text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 42)

	btn.pressed.connect(item["callback"])
	_button_container.add_child(btn)
	_style_button(btn, item.get("primary", false))
	_wire_hover(btn)


# ── Hover ─────────────────────────────────────────────────────────────────────

func _wire_hover(btn: Button) -> void:
	btn.set_meta("_htw", null)  # initialize so get_meta never fails
	btn.mouse_entered.connect(_hover_in.bind(btn))
	btn.mouse_exited.connect(_hover_out.bind(btn))
	btn.focus_entered.connect(_hover_in.bind(btn))
	btn.focus_exited.connect(_hover_out.bind(btn))


func _hover_in(btn: Button) -> void:
	if not is_instance_valid(btn): return
	if btn.has_meta("_htw"):
		var old = btn.get_meta("_htw")
		if old is Tween and old.is_valid(): old.kill()
	var tw := create_tween().set_parallel(true)
	btn.set_meta("_htw", tw)
	tw.tween_property(btn, "position:x", 6.0, 0.15) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _hover_out(btn: Button) -> void:
	if not is_instance_valid(btn): return
	if btn.has_meta("_htw"):
		var old = btn.get_meta("_htw")
		if old is Tween and old.is_valid(): old.kill()
	var tw := create_tween().set_parallel(true)
	btn.set_meta("_htw", tw)
	tw.tween_property(btn, "position:x", 0.0, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ── Style ─────────────────────────────────────────────────────────────────────

func _style_button(btn: Button, primary: bool = false) -> void:
	btn.set_meta("_primary", primary)
	var dark := ThemeManager.is_dark_mode
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 17)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ThemeManager.text_color)
	btn.add_theme_color_override("font_disabled_color", ThemeManager.subtext_color)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0)
	sn.content_margin_left = 14; sn.content_margin_right = 14
	sn.content_margin_top = 8; sn.content_margin_bottom = 8
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		sn.set("corner_radius_" + c, 8)
	btn.add_theme_stylebox_override("normal", sn)

	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(1, 1, 1, 0.07) if dark else Color(0.15, 0.35, 0.85, 0.07)
	btn.add_theme_stylebox_override("hover", sh)

	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = Color(1, 1, 1, 0.14) if dark else Color(0.15, 0.35, 0.85, 0.14)
	btn.add_theme_stylebox_override("pressed", sp)

	var sf := sh.duplicate() as StyleBoxFlat
	sf.border_color = ThemeManager.text_color if dark else Color(0.15, 0.35, 0.85, 0.8)
	for s in ["left", "right", "top", "bottom"]:
		sf.set("border_width_" + s, 2)
	btn.add_theme_stylebox_override("focus", sf)

	if primary:
		var pn := sn.duplicate() as StyleBoxFlat
		pn.bg_color = Color(0.15, 0.35, 0.85, 0.10) if dark else Color(0.15, 0.35, 0.85, 0.06)
		pn.border_color = Color(0.15, 0.35, 0.85, 0.35)
		for s in ["left", "right", "top", "bottom"]:
			pn.set("border_width_" + s, 1)
		btn.add_theme_stylebox_override("normal", pn)
		var ph := pn.duplicate() as StyleBoxFlat
		ph.bg_color = Color(0.15, 0.35, 0.85, 0.20) if dark else Color(0.15, 0.35, 0.85, 0.14)
		ph.border_color = Color(0.15, 0.35, 0.85, 0.60)
		btn.add_theme_stylebox_override("hover", ph)


func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode
	var panel := get_node_or_null(
		"MarginContainer/CenterContainer/VBoxContainer/PanelContainer") as PanelContainer
	if panel:
		if not _panel_style:
			var orig := panel.get_theme_stylebox("panel") as StyleBoxFlat
			_panel_style = orig.duplicate() if orig else StyleBoxFlat.new()
			panel.add_theme_stylebox_override("panel", _panel_style)
		_panel_style.bg_color = ThemeManager.bg_color
		_panel_style.border_color = ThemeManager.border_color
		for s in [0, 1, 2, 3]:
			_panel_style.set("border_width_" + ["left", "right", "top", "bottom"][s], 1)
		for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
			_panel_style.set("corner_radius_" + c, 12)
		_panel_style.shadow_color = Color(0, 0, 0, 0.30 if dark else 0.10)
		_panel_style.shadow_size = 16
		_panel_style.shadow_offset = Vector2(0, 6)

	if _button_container:
		for child in _button_container.get_children():
			if child is Button:
				_style_button(child, child.get_meta("_primary", false))
			elif child is Label and child.name.begins_with("Section"):
				child.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _patch_notes_panel:
		var style := _patch_notes_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.bg_color = ThemeManager.bg_color
			style.border_color = ThemeManager.border_color
			style.shadow_color = Color(0, 0, 0, 0.30 if dark else 0.10)


# ── Dark mode toggle ─────────────────────────────────────────────────────────

func _dark_mode_label() -> String:
	return "Light Mode" if ThemeManager.is_dark_mode else "Dark Mode"

func _update_dark_mode_text() -> void:
	if not _button_container: return
	var btn := _button_container.get_node_or_null("DarkMode") as Button
	if btn:
		var icon := "☀" if ThemeManager.is_dark_mode else "☾"
		btn.text = icon + "   " + _dark_mode_label()


# ── Background ────────────────────────────────────────────────────────────────

func _spawn_background() -> void:
	var old_bg := get_node_or_null("Background")
	if old_bg: old_bg.queue_free()
	var bg_script := load("res://scenes/menu/MainMenuBackground.gd")
	if not bg_script: return
	var bg := Control.new()
	bg.name = "Background"
	bg.set_script(bg_script)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)


# ── Patch Notes ───────────────────────────────────────────────────────────────

func _build_patch_notes_popup() -> void:
	_patch_notes_popup = Control.new()
	_patch_notes_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_patch_notes_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_patch_notes_popup.visible = false
	_patch_notes_popup.z_index = 100
	add_child(_patch_notes_popup)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.60)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_patch_notes_popup.add_child(dim)

	_patch_notes_panel = PanelContainer.new()
	_patch_notes_panel.set_anchors_preset(Control.PRESET_CENTER)
	_patch_notes_panel.offset_left = -340.0; _patch_notes_panel.offset_right = 340.0
	_patch_notes_panel.offset_top = -260.0; _patch_notes_panel.offset_bottom = 260.0
	_patch_notes_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_patch_notes_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_patch_notes_panel.z_index = 1
	_patch_notes_popup.add_child(_patch_notes_panel)

	var ps := StyleBoxFlat.new()
	ps.bg_color = ThemeManager.bg_color; ps.border_color = ThemeManager.border_color
	for s in ["left", "right", "top", "bottom"]: ps.set("border_width_" + s, 1)
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		ps.set("corner_radius_" + c, 12)
	ps.shadow_color = Color(0, 0, 0, 0.30); ps.shadow_size = 16
	ps.shadow_offset = Vector2(0, 6)
	_patch_notes_panel.add_theme_stylebox_override("panel", ps)

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 24)
	mg.add_theme_constant_override("margin_right", 24)
	mg.add_theme_constant_override("margin_top", 20)
	mg.add_theme_constant_override("margin_bottom", 20)
	_patch_notes_panel.add_child(mg)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mg.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "🎉 Latest Changes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _serif_font: title.add_theme_font_override("font", _serif_font)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ThemeManager.text_color)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var content := [
		{"text": "🏗️ Major Refactoring Complete!", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• New service-based architecture", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• EventBus for clean communication", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "🌐 Multiplayer Room Sync", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• Server generates rooms once", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• All clients see identical rooms", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "🎯 Recent Improvements", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• Fixed raceline spawn, bench dismount", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Light mode readability fixes", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "⚡ Performance", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• LRU cache, faster network queue", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "🎮 Host Controls (Multiplayer)", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• Player management, force start, seeded shuffle", "size": 13, "color": ThemeManager.subtext_color},
	]
	for entry in content:
		var lbl := Label.new()
		lbl.text = entry.text
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _serif_font: lbl.add_theme_font_override("font", _serif_font)
		lbl.add_theme_font_size_override("font_size", entry.size)
		lbl.add_theme_color_override("font_color", entry.color)
		vbox.add_child(lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Got it!"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.pressed.connect(_hide_patch_notes)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _serif_font: close_btn.add_theme_font_override("font", _serif_font)
	_style_button(close_btn, true)
	vbox.add_child(close_btn)


func _show_patch_notes() -> void:
	if _patch_notes_popup:
		_patch_notes_popup.visible = true
		if _patch_notes_panel:
			_patch_notes_panel.modulate.a = 0.0
			_patch_notes_panel.position.y = 14.0
			var tw := create_tween().set_parallel(true)
			tw.tween_property(_patch_notes_panel, "modulate:a", 1.0, 0.35).set_delay(0.05)
			tw.tween_property(_patch_notes_panel, "position:y", 0.0, 0.35) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.05)

func _hide_patch_notes() -> void:
	if not _patch_notes_panel:
		if _patch_notes_popup: _patch_notes_popup.visible = false
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_patch_notes_panel, "modulate:a", 0.0, 0.16)
	tw.tween_property(_patch_notes_panel, "position:y", 10.0, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func(): _patch_notes_popup.visible = false)

func _unhandled_input(event: InputEvent) -> void:
	if _patch_notes_popup and _patch_notes_popup.visible and event.is_action_pressed("ui_cancel"):
		_hide_patch_notes()
		get_viewport().set_input_as_handled()


# ── Animations ────────────────────────────────────────────────────────────────

func _entrance_animation() -> void:
	var vbox := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer") as Control
	var logo := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer/TextureRect") as TextureRect
	var subtitle := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer/Label3") as Label
	var panel := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer/PanelContainer") as PanelContainer

	# Save original positions on first call so we can always restore them
	if not _positions_saved:
		if vbox: _vbox_orig_pos = vbox.position
		if logo: _logo_orig_y = logo.position.y
		if panel: _panel_orig_y = panel.position.y
		_positions_saved = true

	# ▸ CRITICAL: reset VBox state from any prior _animate_out call
	if vbox:
		vbox.modulate.a = 1.0
		vbox.position = _vbox_orig_pos

	# Logo: fade in from slightly above
	if logo:
		logo.pivot_offset = logo.size * 0.5
		logo.modulate.a = 0.0
		logo.position.y = _logo_orig_y - 18.0
		var ltw := create_tween().set_parallel(true)
		ltw.tween_property(logo, "modulate:a", 1.0, 0.80) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ltw.tween_property(logo, "position:y", _logo_orig_y, 0.80) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Subtitle: gentle fade
	if subtitle:
		subtitle.modulate.a = 0.0
		var stw := create_tween()
		stw.tween_property(subtitle, "modulate:a", 1.0, 0.70) \
			.set_delay(0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Panel: drift up
	if panel:
		panel.modulate.a = 0.0
		panel.position.y = _panel_orig_y + 10.0
		var ptw := create_tween().set_parallel(true)
		ptw.tween_property(panel, "modulate:a", 1.0, 0.45).set_delay(0.65)
		ptw.tween_property(panel, "position:y", _panel_orig_y, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.65)

	# Button stagger
	if _button_container:
		var delay := 0.78
		for child in _button_container.get_children():
			if child is Button:
				child.modulate.a = 0.0
				var btw := create_tween()
				btw.tween_property(child, "modulate:a", 1.0, 0.32).set_delay(delay)
				delay += 0.04

	_start_fade_in()


func _start_fade_in() -> void:
	var col := Color(0.973, 0.976, 0.98)
	for n in ["FadeIn", "FadeInStage2"]:
		var cr := get_node_or_null(n)
		if cr:
			cr.color = col
			create_tween().tween_property(cr, "color", Color(col, 0.0), 0.85) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _animate_out(then: Callable) -> void:
	var vbox := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer") as Control
	if vbox:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(vbox, "modulate:a", 0.0, 0.16)
		tw.tween_property(vbox, "position:y", _vbox_orig_pos.y + 10.0, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(then)
	else:
		then.call()


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_start_pressed() -> void:
	_animate_out(func(): start.emit())

func _on_settings_pressed() -> void:
	_animate_out(func(): settings.emit())

func _on_multiplayer_pressed() -> void:
	_animate_out(func(): start_multiplayer.emit())

func _on_dedicated_host_pressed() -> void:
	_animate_out(func(): start_dedicated_host.emit())

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_dark_mode_pressed() -> void:
	ThemeManager.set_dark_mode(not ThemeManager.is_dark_mode)
	_update_dark_mode_text()
	_apply_theme()
