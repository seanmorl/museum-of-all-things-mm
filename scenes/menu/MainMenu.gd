extends Control

signal start
signal settings
signal start_multiplayer
signal start_dedicated_host

const _BTN_PATH := "MarginContainer/CenterContainer/VBoxContainer/PanelContainer/ButtonContainer/"
const _FONT_PATH := "res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf"

var _serif_font: Font = null
var _panel_style: StyleBoxFlat = null
var _dedicated_host_btn: Button = null
var _dark_mode_toggle: Button = null
var _patch_notes_popup: Control = null
var _patch_notes_panel: PanelContainer = null

# Thin 1px divider lines placed above specific buttons, matching PauseMenu style.
# A divider is drawn just above each button named here.
const _DIVIDER_BEFORE := ["Multiplayer", "DarkMode", "Settings", "DedicatedHost", "Quit", "Language"]
var _dividers: Array[Dictionary] = []


func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	_build_dedicated_host_button()
	_build_dark_mode_toggle()
	_build_patch_notes_popup()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_d):
		_update_dark_mode_text()
		_apply_theme()
	)
	ThemeManager.reading_font_changed.connect(func(f): _serif_font = f; _apply_theme())
	if Platform.is_web():
		var q = get_node_or_null("%Quit")
		if q: q.visible = false
	call_deferred("_entrance_animation")
	call_deferred("_build_dividers")


func _on_visibility_changed() -> void:
	if visible and is_inside_tree():
		var s := get_node_or_null(_BTN_PATH + "Start")
		if s:
			s.call_deferred("grab_focus")
			
		var vbox := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer") as Control
		if vbox:
			var tw := create_tween().set_parallel(true)
			tw.tween_property(vbox, "modulate:a", 1.0, 0.2)
			tw.tween_property(vbox, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ── Theme ─────────────────────────────────────────────────────────────────────

func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode

	var panel := get_node_or_null(
		"MarginContainer/CenterContainer/VBoxContainer/PanelContainer") as PanelContainer
	if panel:
		if not _panel_style:
			var orig := panel.get_theme_stylebox("panel") as StyleBoxFlat
			_panel_style = orig.duplicate() if orig else StyleBoxFlat.new()
			panel.add_theme_stylebox_override("panel", _panel_style)
		_panel_style.bg_color     = ThemeManager.bg_color
		_panel_style.border_color = ThemeManager.border_color
		for side in [0,1,2,3]:
			_panel_style.set("border_width_" + ["left","right","top","bottom"][side], 1)
		for corner in ["top_left","top_right","bottom_left","bottom_right"]:
			_panel_style.set("corner_radius_" + corner, 10)
		_panel_style.shadow_color  = Color(0, 0, 0, 0.35 if dark else 0.12)
		_panel_style.shadow_size   = 16
		_panel_style.shadow_offset = Vector2(0, 6)

	_style_label("MarginContainer/CenterContainer/VBoxContainer/Title",
		ThemeManager.text_color, 42)
	_style_label("MarginContainer/CenterContainer/VBoxContainer/Subtitle",
		ThemeManager.subtext_color, 13)

	var container := get_node_or_null(_BTN_PATH.trim_suffix("/"))
	if container:
		for child in container.get_children():
			if child is Button:
				_style_button(child)

	for entry in _dividers:
		var line: ColorRect = entry["line"]
		if is_instance_valid(line):
			line.color = ThemeManager.border_color

	# Update patch notes popup theme
	if _patch_notes_panel:
		var style := _patch_notes_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.bg_color = ThemeManager.bg_color
			style.border_color = ThemeManager.border_color
			style.shadow_color = Color(0, 0, 0, 0.35 if dark else 0.12)


# ── Dividers ──────────────────────────────────────────────────────────────────

func _build_dividers() -> void:
	var panel := get_node_or_null(
		"MarginContainer/CenterContainer/VBoxContainer/PanelContainer") as PanelContainer
	var container := get_node_or_null(_BTN_PATH.trim_suffix("/"))
	if not panel or not container:
		return
	for btn_name in _DIVIDER_BEFORE:
		var btn := container.get_node_or_null(btn_name)
		if not btn:
			continue
		var line := ColorRect.new()
		line.name = "Div_" + btn_name
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.color = ThemeManager.border_color
		panel.add_child(line)
		_dividers.append({"leader": btn, "line": line, "panel": panel})
	_update_dividers()


func _update_dividers() -> void:
	for entry in _dividers:
		var leader: Control = entry["leader"]
		var line: ColorRect  = entry["line"]
		var panel: Control   = entry["panel"]
		if not is_instance_valid(leader) or not is_instance_valid(line):
			continue
		if not leader.visible:
			line.visible = false
			continue
		line.visible = true
		var y: float = leader.global_position.y - panel.global_position.y - 6.0
		line.position = Vector2(16.0, y)
		line.size     = Vector2(panel.size.x - 32.0, 1.0)


func _process(_delta: float) -> void:
	if not _dividers.is_empty():
		_update_dividers()


func _style_label(path: String, color: Color, size: int) -> void:
	var lbl := get_node_or_null(path) as Label
	if not lbl:
		return
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	if _serif_font:
		lbl.add_theme_font_override("font", _serif_font)


func _style_button(btn: Button, primary: bool = false) -> void:
	var dark := ThemeManager.is_dark_mode
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 17)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		btn.add_theme_color_override(state, ThemeManager.text_color)
	btn.add_theme_color_override("font_disabled_color", ThemeManager.subtext_color)

	var sn: StyleBox
	sn = StyleBoxFlat.new()
	(sn as StyleBoxFlat).bg_color = Color(0,0,0,0)

	sn.content_margin_left = 16; sn.content_margin_right  = 16
	sn.content_margin_top  =  9; sn.content_margin_bottom =  9
	btn.add_theme_stylebox_override("normal", sn)

	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(1,1,1,0.06) if dark else Color(ThemeManager.border_color, 0.5)
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		sh.set("corner_radius_" + corner, 5)
	sh.content_margin_left = 16; sh.content_margin_right  = 16
	sh.content_margin_top  =  9; sh.content_margin_bottom =  9
	btn.add_theme_stylebox_override("hover", sh)

	var sp: StyleBox
	sp = sh.duplicate()
	(sp as StyleBoxFlat).bg_color = Color(1,1,1,0.12) if dark else Color(ThemeManager.border_color, 0.85)
	btn.add_theme_stylebox_override("pressed", sp)

	var sf: StyleBox
	sf = sh.duplicate()
	(sf as StyleBoxFlat).border_color      = ThemeManager.text_color
	(sf as StyleBoxFlat).border_width_left = 2
	btn.add_theme_stylebox_override("focus", sf)

	if not primary:
		return
	# Primary button styling (optional emphasis)
	var sh_primary := StyleBoxFlat.new()
	sh_primary.bg_color = ThemeManager.border_color
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		sh_primary.set("corner_radius_" + corner, 5)
	sh_primary.content_margin_left = 16
	sh_primary.content_margin_right = 16
	sh_primary.content_margin_top = 9
	sh_primary.content_margin_bottom = 9
	btn.add_theme_stylebox_override("hover", sh_primary)


func _build_dark_mode_toggle() -> void:
	var container := get_node_or_null(_BTN_PATH.trim_suffix("/"))
	if not container: return
	
	_dark_mode_toggle = Button.new()
	_dark_mode_toggle.name = "DarkMode"
	_dark_mode_toggle.pressed.connect(ThemeManager.toggle)
	
	container.add_child(_dark_mode_toggle)
	var settings_btn := container.get_node_or_null("Settings")
	if settings_btn:
		container.move_child(_dark_mode_toggle, settings_btn.get_index()) # Place before Settings
	
	_update_dark_mode_text()
	_style_button(_dark_mode_toggle)


func _update_dark_mode_text() -> void:
	if _dark_mode_toggle:
		_dark_mode_toggle.text = "☾  Dark Mode" if not ThemeManager.is_dark_mode else "☀  Light Mode"


# ── Patch Notes Popup ─────────────────────────────────────────────────────────

func _build_patch_notes_popup() -> void:
	var container := get_node_or_null(_BTN_PATH.trim_suffix("/"))
	if not container: return

	# Add Patch Notes button
	var patch_btn := Button.new()
	patch_btn.name = "PatchNotes"
	patch_btn.text = "ⓘ  Latest Changes"
	patch_btn.pressed.connect(_show_patch_notes)
	container.add_child(patch_btn)
	
	# Place before Quit button
	var quit_btn := container.get_node_or_null("Quit")
	if quit_btn:
		container.move_child(patch_btn, quit_btn.get_index() - 1)
	_style_button(patch_btn)

	# Build popup
	_patch_notes_popup = Control.new()
	_patch_notes_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_patch_notes_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_patch_notes_popup.visible = false
	_patch_notes_popup.z_index = 100  # Render on top of everything
	add_child(_patch_notes_popup)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.60)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_patch_notes_popup.add_child(dim)

	_patch_notes_panel = PanelContainer.new()
	_patch_notes_panel.set_anchors_preset(Control.PRESET_CENTER)
	_patch_notes_panel.offset_left   = -350.0
	_patch_notes_panel.offset_top    = -280.0
	_patch_notes_panel.offset_right  = 350.0
	_patch_notes_panel.offset_bottom = 280.0
	_patch_notes_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_patch_notes_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_patch_notes_panel.z_index = 1  # Above the dim background
	_patch_notes_popup.add_child(_patch_notes_panel)

	var panel_style := StyleBoxFlat.new()
	_patch_notes_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   24)
	margin.add_theme_constant_override("margin_right",  24)
	margin.add_theme_constant_override("margin_top",    20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_patch_notes_panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "🎉 Latest Changes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _serif_font: title.add_theme_font_override("font", _serif_font)
	title.add_theme_font_size_override("font_size", 24)
	# Use dark color in light mode for readability
	title.add_theme_color_override("font_color", ThemeManager.text_color)
	vbox.add_child(title)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	var content := [
		{"text": "🏗️ Major Refactoring Complete!", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• New service-based architecture", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• EventBus for clean communication", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Proper state machine implementation", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "", "size": 0, "color": Color()},
		{"text": "🌐 Multiplayer Room Sync", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• Server generates rooms once", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• All clients see identical rooms", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• RoomData serialization for sync", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "", "size": 0, "color": Color()},
		{"text": "👥 Player Position Sync", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• Real-time player movement sync", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Smooth interpolation", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Network abstraction layer", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "", "size": 0, "color": Color()},
		{"text": "📋 New Services", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• RoomService - Room generation & sync", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• NetworkService - Network abstraction", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• ExhibitService - Exhibit lifecycle", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• RaceService - Race logic & validation", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "", "size": 0, "color": Color()},
		{"text": "🎮 Existing Features (Still Working!)", "size": 16, "color": ThemeManager.text_color},
		{"text": "• 📅 Daily Challenge System", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• 🔒 Anti-Cheat Measures", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• 🎮 All 9 Power-ups", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• ⏱️ Race Countdown (3-2-1-GO!)", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• 🚪 Search Corridor Door System", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "", "size": 0, "color": Color()},
		{"text": "🎯 Recent Improvements", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• 🏁 Fixed raceline spawn position", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• 🧭 Players now face search corridor", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• 👥 Multi-player spawn spread (no stacking)", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• 📋 Fixed timeline duplicate entries", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• 🎨 Light mode text readability fixes", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• 🪑 Fixed bench dismount issue", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "", "size": 0, "color": Color()},
		{"text": "⚡ Performance Optimizations", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• Debug logs stripped in release builds", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• LRU cache for article data (500 max)", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Memory leak prevention in long sessions", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Faster network queue processing", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "", "size": 0, "color": Color()},
		{"text": "🐛 Bug Fixes", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• Fixed race_won signal argument mismatch", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Fixed Daily Challenge HUD light mode", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Fixed mount system for static seats", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Added proper error handling throughout", "size": 13, "color": ThemeManager.subtext_color},
	]

	for entry in content:
		if entry.text == "":
			continue
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
	if _serif_font: close_btn.add_theme_font_override("font", _serif_font)
	vbox.add_child(close_btn)

	# Style panel
	panel_style.bg_color = ThemeManager.bg_color
	panel_style.border_color = ThemeManager.border_color
	for s in ["left", "right", "top", "bottom"]:
		panel_style.set("border_width_" + s, 1)
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		panel_style.set("corner_radius_" + c, 10)
	panel_style.shadow_color = Color(0, 0, 0, 0.35 if ThemeManager.is_dark_mode else 0.12)
	panel_style.shadow_size = 16
	panel_style.shadow_offset = Vector2(0, 6)

	_style_button(close_btn, true)

func _animate_patch_notes_in() -> void:
	if _patch_notes_panel:
		_patch_notes_panel.modulate.a = 0.0
		_patch_notes_panel.position.y = 14.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_patch_notes_panel, "modulate:a", 1.0, 0.35).set_delay(0.05)
		tw.tween_property(_patch_notes_panel, "position:y", 0.0, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.05)

func _animate_patch_notes_out(then: Callable) -> void:
	if _patch_notes_panel:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_patch_notes_panel, "modulate:a", 0.0, 0.16)
		tw.tween_property(_patch_notes_panel, "position:y", 10.0, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(then)
	else:
		then.call()

func _show_patch_notes() -> void:
	_patch_notes_popup.visible = true
	_animate_patch_notes_in()

func _hide_patch_notes() -> void:
	_animate_patch_notes_out(func(): _patch_notes_popup.visible = false)

func _unhandled_input(event: InputEvent) -> void:
	if _patch_notes_popup and _patch_notes_popup.visible and event.is_action_pressed("ui_cancel"):
		_hide_patch_notes()
		get_viewport().set_input_as_handled()


# ── Animations ────────────────────────────────────────────────────────────────

func _entrance_animation() -> void:
	var vbox := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer") as Control
	if vbox:
		vbox.modulate.a  = 0.0
		vbox.position.y  = 14.0
		var ptw := create_tween().set_parallel(true)
		ptw.tween_property(vbox, "modulate:a",  1.0,   0.40).set_delay(0.10)
		ptw.tween_property(vbox, "position:y",  0.0,   0.40) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.10)

	var container := get_node_or_null(_BTN_PATH.trim_suffix("/"))
	if container:
		var delay := 0.22
		for child in container.get_children():
			if child is Button:
				child.modulate.a = 0.0
				var btw := create_tween()
				btw.tween_property(child, "modulate:a", 1.0, 0.28).set_delay(delay)
				delay += 0.06

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
		tw.tween_property(vbox, "position:y", 10.0, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(then)
	else:
		then.call()


# ── Dedicated host button ──────────────────────────────────────────────────────

func _build_dedicated_host_button() -> void:
	var container := get_node_or_null(_BTN_PATH.trim_suffix("/"))
	if not container:
		return
	_dedicated_host_btn = Button.new()
	_dedicated_host_btn.text = "Host Server"
	_dedicated_host_btn.name = "DedicatedHost"
	_dedicated_host_btn.pressed.connect(_on_dedicated_host_pressed)
	container.add_child(_dedicated_host_btn)
	var quit := container.get_node_or_null("Quit")
	if quit:
		container.move_child(_dedicated_host_btn, quit.get_index())


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_start_pressed() -> void:
	_animate_out(func(): start.emit())

func _on_settings_pressed() -> void:
	_animate_out(func(): settings.emit())

func _on_multiplayer_pressed() -> void:
	_animate_out(func(): start_multiplayer.emit())

func _on_dedicated_host_pressed() -> void:
	_animate_out(func(): start_dedicated_host.emit())

func _on_quit_button_pressed() -> void:
	_animate_out(func(): get_tree().quit())
