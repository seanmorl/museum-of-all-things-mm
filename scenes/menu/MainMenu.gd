extends Control

signal start
signal settings
signal start_multiplayer
signal start_dedicated_host

const _FONT_PATH := "res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf"

const FACTS := [
	"Did you know? Wikipedia has over 60 million articles in more than 300 languages.",
	"The Museum generates rooms from real Wikipedia articles - no two visits are the same!",
	"Each room door leads to another Wikipedia article, creating an infinite museum.",
	"Every painting in the museum comes from Wikimedia Commons.",
	"The multiplayer mode supports up to 16 players exploring together.",
	"You can customize your player with skins from any Wikimedia image URL.",
	"Wikipedia contains more than 40 billion words - enough to fill millions of books.",
	"The race mode lets you and friends vote on a target and race to find it first!",
	"You can climb on top of other players and ride around the museum together.",
	"The daily challenge gives you a fresh target article every day.",
	"🗳️ Take the Dr Plem Hot or Not 2026 survey: linktr.ee/hot_or_not",
	"Wikimedia Commons has over 100 million free-to-use images and media files.",
	"The shortest Wikipedia article is only 4 bytes - just a redirect!",
	"You can change your player color in the settings menu.",
	"The museum uses a random seed for each race to ensure fair gameplay.",
	"Press J to open your journal and track which articles you've visited.",
	"Tournament mode lets hosts run elimination brackets with multiple rounds.",
	"Secret rooms can be hidden in some exhibits - keep an eye out!",
	"The museum supports voice chat in multiplayer mode.",
	"You can place paintings on walls once you've collected them.",
]

var _serif_font: Font = null
var _panel_style: StyleBoxFlat = null
var _button_container: VBoxContainer = null
var _patch_notes_popup: Control = null
var _patch_notes_panel: PanelContainer = null
var _fact_label: Label = null
var _fact_timer: Timer = null
var _current_fact_index: int = 0
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
	_setup_fact_label()

	ThemeManager.dark_mode_changed.connect(_on_dark_mode_changed)
	ThemeManager.reading_font_changed.connect(_on_reading_font_changed)

	if Platform.is_web():
		var q = _button_container.get_node_or_null("Quit") if _button_container else null
		if q: q.visible = false

	call_deferred("_entrance_animation")


func _on_dark_mode_changed(_d: bool) -> void:
	_update_dark_mode_text()
	_apply_theme()


func _on_reading_font_changed(f: Font) -> void:
	_serif_font = f
	_apply_theme()

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
	margin.add_theme_constant_override("margin_left", int(UIStyle.MARGIN_LARGE))
	margin.add_theme_constant_override("margin_right", int(UIStyle.MARGIN_LARGE))
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	_button_container = VBoxContainer.new()
	_button_container.name = "ButtonContainer"
	_button_container.add_theme_constant_override("separation", int(UIStyle.SPACING_TIGHT))
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
		spacer.custom_minimum_size = Vector2(0, UIStyle.SPACING_STANDARD)
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
	btn.mouse_entered.connect(_hover_in.bind(btn))
	btn.mouse_exited.connect(_hover_out.bind(btn))
	btn.focus_entered.connect(_hover_in.bind(btn))
	btn.focus_exited.connect(_hover_out.bind(btn))


func _hover_in(btn: Button) -> void:
	if not is_instance_valid(btn): return
	UIStyle.animate_hover_enter(btn)


func _hover_out(btn: Button) -> void:
	if not is_instance_valid(btn): return
	UIStyle.animate_hover_exit(btn)


# ── Style ─────────────────────────────────────────────────────────────────────

func _style_button(btn: Button, primary: bool = false) -> void:
	btn.set_meta("_primary", primary)
	var dark := ThemeManager.is_dark_mode
	
	# Apply font
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 17)
	
	# Apply font colors
	var text_color := ThemeManager.text_color
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, text_color)
	btn.add_theme_color_override("font_disabled_color", ThemeManager.subtext_color)
	
	# Create and apply state styles
	var states := UIStyle.create_button_states(dark, primary, true)
	btn.add_theme_stylebox_override("normal", states.normal)
	btn.add_theme_stylebox_override("hover", states.hover)
	btn.add_theme_stylebox_override("pressed", states.pressed)
	btn.add_theme_stylebox_override("focus", states.focus)
	btn.add_theme_stylebox_override("disabled", states.disabled)


func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode
	var panel := get_node_or_null(
		"MarginContainer/CenterContainer/VBoxContainer/PanelContainer") as PanelContainer
	if panel:
		if not _panel_style:
			var orig := panel.get_theme_stylebox("panel") as StyleBoxFlat
			_panel_style = orig.duplicate() if orig else StyleBoxFlat.new()
			panel.add_theme_stylebox_override("panel", _panel_style)
		
		# Use centralized panel style
		_panel_style = UIStyle.create_panel_style(
			ThemeManager.bg_color,
			ThemeManager.border_color,
			dark,
			UIStyle.CORNER_RADIUS_PANEL,
			UIStyle.PANEL_PADDING
		)
		panel.add_theme_stylebox_override("panel", _panel_style)

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

	# Use centralized panel style
	var ps := UIStyle.create_panel_style(
		ThemeManager.bg_color,
		ThemeManager.border_color,
		ThemeManager.is_dark_mode,
		UIStyle.CORNER_RADIUS_PANEL,
		UIStyle.PANEL_PADDING
	)
	_patch_notes_panel.add_theme_stylebox_override("panel", ps)

	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", int(UIStyle.MARGIN_LARGE))
	mg.add_theme_constant_override("margin_right", int(UIStyle.MARGIN_LARGE))
	mg.add_theme_constant_override("margin_top", int(UIStyle.MARGIN_LARGE) - 4)
	mg.add_theme_constant_override("margin_bottom", int(UIStyle.MARGIN_LARGE))
	_patch_notes_panel.add_child(mg)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mg.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(UIStyle.SPACING_LOOSE))
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
		{"text": "♿ New Accessibility Options", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• Audio visual indicators for hearing impaired", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• HUD opacity slider", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Photosensitivity warning toggle", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Hold-to-click for motor accessibility", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• TTS speed slider in audio settings", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "🗺️ New Hint System", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• Press I as host to reveal Wikipedia-based hints", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Hints appear in RaceHUD with 3-second cooldown", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "📜 Rotating Facts on Main Menu", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• 21 facts cycling every 10 seconds", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "• Includes survey link: linktr.ee/hot_or_not", "size": 13, "color": ThemeManager.subtext_color},
		{"text": "🎮 Discord Rich Presence", "size": 16, "color": Color(0.4, 0.8, 1.0)},
		{"text": "• Now shows current exhibit in singleplayer", "size": 13, "color": ThemeManager.subtext_color},
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
			tw.tween_property(_patch_notes_panel, "modulate:a", 1.0, UIStyle.FADE_DURATION).set_delay(0.05)
			tw.tween_property(_patch_notes_panel, "position:y", 0.0, UIStyle.SLIDE_DURATION) \
				.set_trans(UIStyle.TRANS_BOUNCE).set_ease(UIStyle.EASE_BOUNCE).set_delay(0.05)

func _hide_patch_notes() -> void:
	if not _patch_notes_panel:
		if _patch_notes_popup: _patch_notes_popup.visible = false
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_patch_notes_panel, "modulate:a", 0.0, UIStyle.FADE_QUICK)
	tw.tween_property(_patch_notes_panel, "position:y", 10.0, UIStyle.FADE_QUICK) \
		.set_trans(UIStyle.TRANS_EXIT).set_ease(UIStyle.EASE_EXIT)
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
		ptw.tween_property(panel, "modulate:a", 1.0, UIStyle.ENTRANCE_DURATION).set_delay(0.65)
		ptw.tween_property(panel, "position:y", _panel_orig_y, UIStyle.ENTRANCE_DURATION) \
			.set_trans(UIStyle.TRANS_STANDARD).set_ease(UIStyle.EASE_STANDARD).set_delay(0.65)

	# Button stagger
	if _button_container:
		var delay := 0.78
		for child in _button_container.get_children():
			if child is Button:
				child.modulate.a = 0.0
				var btw := create_tween()
				btw.tween_property(child, "modulate:a", 1.0, UIStyle.FADE_DURATION).set_delay(delay)
				delay += UIStyle.STAGGER_DELAY

	_start_fade_in()
	_update_fact_display()


func _setup_fact_label() -> void:
	_fact_label = Label.new()
	_fact_label.name = "FactLabel"
	_fact_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_fact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fact_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fact_label.custom_minimum_size = Vector2(0, 32)
	if _serif_font:
		_fact_label.add_theme_font_override("font", _serif_font)
	_fact_label.add_theme_font_size_override("font_size", 12)
	_fact_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	
	var vbox := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer") as VBoxContainer
	if vbox:
		vbox.add_child(_fact_label)
	
	_fact_timer = Timer.new()
	_fact_timer.name = "FactTimer"
	_fact_timer.wait_time = 10.0
	_fact_timer.one_shot = false
	_fact_timer.timeout.connect(_on_fact_timer_timeout)
	add_child(_fact_timer)


func _on_fact_timer_timeout() -> void:
	if not _fact_label:
		return
	var tw := create_tween()
	tw.tween_property(_fact_label, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(_cycle_fact)


func _cycle_fact() -> void:
	_current_fact_index = (_current_fact_index + 1) % FACTS.size()
	_fact_label.text = FACTS[_current_fact_index]
	var tw := create_tween()
	tw.tween_property(_fact_label, "modulate:a", 1.0, 0.5)


func _update_fact_display() -> void:
	if not _fact_label:
		return
	_current_fact_index = randi() % FACTS.size()
	_fact_label.text = FACTS[_current_fact_index]
	_fact_label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_fact_label, "modulate:a", 1.0, 0.5).set_delay(1.0)
	if _fact_timer:
		_fact_timer.start()


func _start_fade_in() -> void:
	var col := Color(0.973, 0.976, 0.98)
	for n in ["FadeIn", "FadeInStage2"]:
		var cr := get_node_or_null(n)
		if cr:
			cr.color = col
			create_tween().tween_property(cr, "color", Color(col, 0.0), 0.85) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _animate_out(then: Callable) -> void:
	if _fact_timer:
		_fact_timer.stop()
	var vbox := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer") as Control
	if vbox:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(vbox, "modulate:a", 0.0, UIStyle.FADE_QUICK)
		tw.tween_property(vbox, "position:y", _vbox_orig_pos.y + 10.0, UIStyle.FADE_QUICK) \
			.set_trans(UIStyle.TRANS_EXIT).set_ease(UIStyle.EASE_EXIT)
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
