extends CanvasLayer
## DebugConsole - In-game developer console for testing and debugging
## Only active in debug builds, automatically removed on export

var _console_visible: bool = false
var _input_line: LineEdit = null
var _output_label: RichTextLabel = null
var _panel: PanelContainer = null
var _tween: Tween = null
var _history: Array[String] = []
var _history_index: int = -1
var _toggle_cooldown: bool = false

func is_active() -> bool:
	return _console_visible
const HEIGHT: float = 450.0

var _bg_overlay: ColorRect = null
var _tab_container: TabContainer = null
var _events_list: VBoxContainer = null
var _stats_grid: GridContainer = null

# Commands registry
var _commands: Dictionary = {}


func _ready() -> void:
	# Only activate in debug builds
	if not OS.is_debug_build():
		queue_free()
		return

	_build_console()
	_register_commands()

	# Initial state: hidden off-screen
	visible = false
	_panel.offset_top    = 0
	_panel.offset_bottom = HEIGHT
	_bg_overlay.color    = Color(0, 0, 0, 0)

	# Topmost layer, above everything
	layer = 1000

	# Theme integration
	if ThemeManager:
		ThemeManager.dark_mode_changed.connect(func(_d): _apply_full_theme())

	# Startup message using theme-consistent BBCode colours
	if _output_label:
		_output_label.text = "[color=#5599ff]System ready.[/color] Type [color=#aaccff]help[/color] for commands.\n"

	print("[DebugConsole] Console initialized")


func _build_console() -> void:
	# Background overlay — semi-transparent dim matching other overlays
	_bg_overlay = ColorRect.new()
	_bg_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_overlay.color = Color(0, 0, 0, 0)
	_bg_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_overlay)

	# Main panel — slides in from bottom, consistent with other game panels
	_panel = PanelContainer.new()
	_panel.name = "ConsolePanel"
	_panel.anchor_left   = 0.0
	_panel.anchor_top    = 1.0
	_panel.anchor_right  = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top    = 0
	_panel.offset_bottom = HEIGHT
	_panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	_panel.focus_mode    = Control.FOCUS_ALL

	var panel_style := StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)
	_apply_panel_style(panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   20)
	margin.add_theme_constant_override("margin_right",  20)
	margin.add_theme_constant_override("margin_top",    14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(main_vbox)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	main_vbox.add_child(header)

	var title := Label.new()
	title.text = "Developer Console"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label(title, 13, true)
	header.add_child(title)

	var hint := Label.new()
	hint.text = "~ / F12 to toggle   ESC to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_label(hint, 11, false)
	header.add_child(hint)

	var header_div := _make_divider()
	main_vbox.add_child(header_div)

	# Tab container
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.tabs_visible = true
	_tab_container.clip_contents = true
	var tab_style := StyleBoxEmpty.new()
	_tab_container.add_theme_stylebox_override("panel", tab_style)
	_tab_container.add_theme_font_size_override("font_size", 12)
	main_vbox.add_child(_tab_container)

	# ── TAB 1: LOGS ───────────────────────────────────────────────────────────
	var logs_page := VBoxContainer.new()
	logs_page.name = "Logs"
	_tab_container.add_child(logs_page)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	logs_page.add_child(scroll)

	_output_label = RichTextLabel.new()
	_output_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output_label.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_output_label.bbcode_enabled     = true
	_output_label.scroll_following   = true
	_output_label.selection_enabled  = true
	_output_label.add_theme_font_size_override("normal_font_size", 13)

	var reading_font := ThemeManager.get_reading_font() if ThemeManager else null
	if reading_font:
		_output_label.add_theme_font_override("normal_font", reading_font)

	scroll.add_child(_output_label)

	# ── TAB 2: EVENTS ─────────────────────────────────────────────────────────
	var events_page := ScrollContainer.new()
	events_page.name = "Events"
	events_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_container.add_child(events_page)

	var events_margin := MarginContainer.new()
	events_margin.add_theme_constant_override("margin_top",    10)
	events_margin.add_theme_constant_override("margin_bottom", 10)
	events_page.add_child(events_margin)

	_events_list = VBoxContainer.new()
	_events_list.add_theme_constant_override("separation", 6)
	events_margin.add_child(_events_list)

	# ── TAB 3: STATS ──────────────────────────────────────────────────────────
	var stats_page := ScrollContainer.new()
	stats_page.name = "Stats"
	_tab_container.add_child(stats_page)

	_stats_grid = GridContainer.new()
	_stats_grid.columns = 2
	_stats_grid.add_theme_constant_override("h_separation", 40)
	_stats_grid.add_theme_constant_override("v_separation", 10)
	stats_page.add_child(_stats_grid)

	# ── Input row ─────────────────────────────────────────────────────────────
	main_vbox.add_child(_make_divider())

	var input_hbox := HBoxContainer.new()
	input_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(input_hbox)

	var prompt := Label.new()
	prompt.text = "❯"
	_style_label(prompt, 14, true)
	input_hbox.add_child(prompt)

	_input_line = LineEdit.new()
	_input_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_line.placeholder_text = "Enter command (try 'help')…"
	_input_line.flat = true
	_input_line.add_theme_font_size_override("font_size", 13)
	if reading_font:
		_input_line.add_theme_font_override("font", reading_font)
	_input_line.text_submitted.connect(_on_command_submitted)
	input_hbox.add_child(_input_line)

	_build_events_list()
	_update_stats()
	_apply_full_theme()


func _apply_panel_style(style: StyleBoxFlat) -> void:
	var dark: bool = ThemeManager.is_dark_mode if ThemeManager else true
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	style.bg_color     = Color(ThemeManager.bg_color if ThemeManager else Color(0.09, 0.10, 0.13), 0.97)
	style.border_color = Color(accent, 0.45)
	style.border_width_top    = 2
	style.border_width_left   = 0
	style.border_width_right  = 0
	style.border_width_bottom = 0
	style.set_corner_radius_all(0)
	style.shadow_color  = Color(0, 0, 0, 0.45 if dark else 0.18)
	style.shadow_size   = 20
	style.shadow_offset = Vector2(0, -4)


func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.color = ThemeManager.border_color if ThemeManager else Color(1, 1, 1, 0.12)
	return d


func _style_label(lbl: Label, size: int, primary: bool) -> void:
	var font := ThemeManager.get_reading_font() if ThemeManager else null
	if font: lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", size)
	var col: Color
	if primary:
		col = ThemeManager.text_color if ThemeManager else Color(0.95, 0.95, 0.95)
	else:
		col = ThemeManager.subtext_color if ThemeManager else Color(0.55, 0.55, 0.60)
	lbl.add_theme_color_override("font_color", col)


func _apply_full_theme() -> void:
	if not ThemeManager: return
	var dark:  bool  = ThemeManager.is_dark_mode
	var accent        := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)

	# Re-apply panel style
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style: _apply_panel_style(style)

	# Output label colours — use theme text, accent for system messages
	if _output_label:
		_output_label.add_theme_color_override("default_color",  ThemeManager.text_color)
		_output_label.add_theme_color_override("font_color",     ThemeManager.text_color)

	# Input line
	if _input_line:
		_input_line.add_theme_color_override("font_color",            ThemeManager.text_color)
		_input_line.add_theme_color_override("font_placeholder_color", ThemeManager.subtext_color)

	# Refresh dividers
	if _panel:
		for cr in _panel.find_children("*", "ColorRect", true, false):
			if cr is ColorRect and cr.custom_minimum_size.y == 1:
				cr.color = ThemeManager.border_color

	# Refresh event buttons
	_build_events_list()
	_update_stats()


func _build_events_list() -> void:
	if not _events_list: return
	for c in _events_list.get_children(): c.queue_free()

	var dark:  bool  = ThemeManager.is_dark_mode if ThemeManager else true
	var accent        := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	var font  := ThemeManager.get_reading_font() if ThemeManager else null

	# Section header
	var section := Label.new()
	section.text = "Quick Triggers"
	_style_label(section, 11, false)
	_events_list.add_child(section)

	var events := [
		{"name": "Darkness",        "cmd": "event darkness"},
		{"name": "Speed Up",        "cmd": "event speed_up"},
		{"name": "Fog",             "cmd": "event fog"},
		{"name": "Low Gravity",     "cmd": "event low_gravity"},
		{"name": "Weather System",  "cmd": "event weather_system"},
		{"name": "Earthquake",      "cmd": "event earthquake"},
		{"name": "Backwards Controls", "cmd": "event backwards_controls"},
		{"name": "Clear All Events","cmd": "event all_clear"},
		{"name": "Test Banner",     "cmd": "banner"},
	]

	for evt: Dictionary in events:
		var btn := Button.new()
		btn.text = evt.name
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(200, 32)
		btn.focus_mode = Control.FOCUS_NONE
		if font: btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func(): _on_command_submitted(evt.cmd))

		var sn := StyleBoxFlat.new()
		sn.bg_color = Color(accent, 0.07)
		sn.border_color = Color(accent, 0.25)
		sn.set_border_width_all(1)
		sn.set_corner_radius_all(6)
		sn.content_margin_left = 10
		btn.add_theme_stylebox_override("normal", sn)

		var sh := sn.duplicate() as StyleBoxFlat
		sh.bg_color    = Color(accent, 0.18)
		sh.border_color = Color(accent, 0.55)
		btn.add_theme_stylebox_override("hover", sh)

		var sp := sh.duplicate() as StyleBoxFlat
		sp.bg_color = Color(accent, 0.28)
		btn.add_theme_stylebox_override("pressed", sp)

		btn.add_theme_color_override("font_color",         ThemeManager.text_color if ThemeManager else Color.WHITE)
		btn.add_theme_color_override("font_hover_color",   ThemeManager.text_color if ThemeManager else Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", ThemeManager.text_color if ThemeManager else Color.WHITE)

		_events_list.add_child(btn)


func _update_stats() -> void:
	if not _stats_grid: return
	for child in _stats_grid.get_children(): child.queue_free()

	var dark:  bool  = ThemeManager.is_dark_mode if ThemeManager else true
	var accent        := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	var font  := ThemeManager.get_reading_font() if ThemeManager else null

	var stats := [
		["FPS",          str(Engine.get_frames_per_second())],
		["Memory",       String.humanize_size(OS.get_static_memory_usage())],
		["Objects",      str(int(Performance.get_monitor(Performance.OBJECT_COUNT)))],
		["Nodes",        str(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))],
		["Draw Calls",   str(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))],
		["Orphan Nodes", str(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))],
	]

	for stat: Array in stats:
		var key_lbl := Label.new()
		key_lbl.text = stat[0]
		if font: key_lbl.add_theme_font_override("font", font)
		key_lbl.add_theme_font_size_override("font_size", 12)
		key_lbl.add_theme_color_override("font_color",
			ThemeManager.subtext_color if ThemeManager else Color(0.55, 0.55, 0.60))
		_stats_grid.add_child(key_lbl)

		var val_lbl := Label.new()
		val_lbl.text = stat[1]
		if font: val_lbl.add_theme_font_override("font", font)
		val_lbl.add_theme_font_size_override("font_size", 12)
		val_lbl.add_theme_color_override("font_color", Color(accent, 0.90))
		_stats_grid.add_child(val_lbl)


func _register_commands() -> void:
	# Built-in commands
	_commands["help"] = Callable(self, "_cmd_help")
	_commands["clear"] = Callable(self, "_cmd_clear")
	_commands["cls"] = Callable(self, "_cmd_clear")
	_commands["exit"] = Callable(self, "_cmd_exit")
	_commands["quit"] = Callable(self, "_cmd_exit")
	_commands["toggle"] = Callable(self, "_cmd_toggle")
	
	# Event testing
	_commands["event"] = Callable(self, "_cmd_event")
	_commands["events"] = Callable(self, "_cmd_events")
	_commands["banner"] = Callable(self, "_cmd_banner")
	
	# Game state
	_commands["race"] = Callable(self, "_cmd_race")
	_commands["time"] = Callable(self, "_cmd_time")
	_commands["speed"] = Callable(self, "_cmd_speed")
	
	# Teleport/debug
	_commands["goto"] = Callable(self, "_cmd_goto")
	_commands["fps"] = Callable(self, "_cmd_fps")


func _process(_delta: float) -> void:
	# Toggle console with ~ or F12 (with cooldown to prevent spam)
	if not _toggle_cooldown:
		if Input.is_key_pressed(KEY_QUOTELEFT) or Input.is_key_pressed(KEY_F12):
			_toggle_cooldown = true
			toggle_console()
			return
	
	# Cooldown prevents rapid toggle
	if _toggle_cooldown and not Input.is_key_pressed(KEY_QUOTELEFT) and not Input.is_key_pressed(KEY_F12):
		_toggle_cooldown = false
	
	# Update stats if visible and on stats tab
	if _console_visible and _tab_container and _tab_container.current_tab == 2:
		_update_stats()


func toggle_console() -> void:
	_console_visible = not _console_visible
	
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	var player = get_tree().get_first_node_in_group("local_player")
	
	if _console_visible:
		visible = true
		_bg_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

		if player and player.has_method("pause"):
			player.pause()

		_input_line.grab_focus()

		var overlay_col := Color(0, 0, 0, 0.50) if (ThemeManager and ThemeManager.is_dark_mode) \
			else Color(0.05, 0.05, 0.08, 0.40)

		_tween.tween_property(_panel, "offset_top",    -HEIGHT, 0.28)
		_tween.tween_property(_panel, "offset_bottom",       0, 0.28)
		_tween.tween_property(_bg_overlay, "color", overlay_col, 0.28)

		_update_stats()
	else:
		_input_line.text = ""
		_input_line.release_focus()
		_bg_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var mouse_overlay_open := get_tree().get_nodes_in_group("mouse_overlay").any(
			func(n: Node) -> bool: return is_instance_valid(n) and n.visible
		)
		var main := get_tree().get_first_node_in_group("main")
		var menu_visible: bool = false
		if main and "_menu_layer" in main:
			menu_visible = main._menu_layer.visible

		if not mouse_overlay_open and not menu_visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

		if player and player.has_method("start"):
			player.start()

		_tween.tween_property(_panel, "offset_top",    0,      0.22)
		_tween.tween_property(_panel, "offset_bottom", HEIGHT, 0.22)
		_tween.tween_property(_bg_overlay, "color", Color(0, 0, 0, 0), 0.20)
		_tween.chain().tween_callback(func(): visible = false)


func _input(event: InputEvent) -> void:
	# Block all game input when console is open, BUT only if it's not and event for the LineEdit
	if _console_visible:
		if event is InputEventKey:
			# Allow ESC to close console even if LineEdit has focus
			if event.pressed and event.keycode == KEY_ESCAPE:
				toggle_console()
				get_viewport().set_input_as_handled()
				return
		
		# If the LineEdit has focus, let it handle the input
		if _input_line.has_focus():
			return
			
		get_viewport().set_input_as_handled()


func _on_command_submitted(command: String) -> void:
	if command.is_empty():
		return
	
	# Add to history
	_history.append(command)
	_history_index = _history.size()
	
	# Display command
	_print_log("[color=#44aaaa]❯ %s[/color]" % command)
	
	# Parse and execute
	var parts = command.split(" ", false)
	var cmd = parts[0].to_lower()
	var args = parts.slice(1) if parts.size() > 1 else []
	
	if _commands.has(cmd):
		_commands[cmd].call(args)
	else:
		# Try as GDScript expression
		_execute_gdscript(command)
	
	_input_line.text = ""
	_scroll_to_bottom()


func _execute_gdscript(code: String) -> void:
	# Try to execute as GDScript
	var result = _safe_eval(code)
	if result != null:
		_print_log("[color=#aaddff]= %s[/color]" % str(result))


func _safe_eval(code: String) -> Variant:
	# Simple command evaluator - executes code in a safe context
	var result: Variant = null
	
	# Check for common patterns
	if code.begins_with("print("):
		var msg = code.substr(6, code.length() - 7)
		_print_log(msg)
		return null
	
	# Try to access autoloads
	if code.begins_with("EventManager"):
		result = _exec_autoload("EventManager", code)
	elif code.begins_with("EventWarningBanner"):
		result = _exec_autoload("EventWarningBanner", code)
	elif code.begins_with("RaceManager"):
		result = _exec_autoload("RaceManager", code)
	else:
		_print_log("[color=#ff6666]Unknown command or expression: %s[/color]" % code)
		_print_log("[color=#888888]Type 'help' for available commands[/color]")
	
	return result


func _exec_autoload(autoload_name: String, code: String) -> Variant:
	var autoload = get_node_or_null("/root/" + autoload_name)
	if not autoload:
		_print_log("[color=red]Autoload '%s' not found[/color]" % autoload_name)
		return null
	
	# Parse method call
	if "." in code:
		var parts = code.split(".", true, 1)
		var method = parts[1].split("(")[0]
		
		# Extract arguments
		var args_start = code.find("(")
		var args_end = code.find(")")
		var args_str = ""
		if args_start > 0 and args_end > args_start:
			args_str = code.substr(args_start + 1, args_end - args_start - 1)
		
		# Call the method
		if autoload.has_method(method):
			var args = []
			if not args_str.is_empty():
				args = [args_str]  # Pass as string for now
			return autoload.callv(method, args)
		else:
			_print_log("[color=#ff6666]Method '%s' not found on %s[/color]" % [method, autoload_name])
	
	return null


func _print_log(text: String) -> void:
	if _output_label:
		_output_label.text += text + "\n"
		# Limit history
		var lines = _output_label.text.split("\n")
		if lines.size() > 100:
			_output_label.text = "\n".join(lines.slice(-100))


func _scroll_to_bottom() -> void:
	if _output_label:
		await get_tree().process_frame
		_output_label.scroll_following = true


# ── Command Implementations ───────────────────────────────────────────────────

func _cmd_help(_args: Array) -> void:
	_print_log("\n[color=#ffaa55]SYSTEM HELP[/color]")
	_print_log("  [color=cyan]help[/color]       - Show this help")
	_print_log("  [color=cyan]clear[/color]      - Clear console history")
	_print_log("  [color=cyan]exit[/color]       - Close console window")
	_print_log("\n[color=#ffaa55]COMMANDS[/color]")
	_print_log("  [color=cyan]event <name>[/color]  - Trigger specific event")
	_print_log("  [color=cyan]events[/color]     - List all available events")
	_print_log("  [color=cyan]banner[/color]     - Test warning banner display")
	_print_log("  [color=cyan]race[/color]       - Show current race status")
	_print_log("  [color=cyan]fps[/color]        - Show current performance")
	_print_log("  [color=cyan]goto <room>[/color] - Teleport to specified room\n")


func _cmd_clear(_args: Array) -> void:
	if _output_label:
		_output_label.text = "[color=yellow]History cleared.[/color]\n\n"


func _cmd_exit(_args: Array) -> void:
	toggle_console()


func _cmd_toggle(_args: Array) -> void:
	toggle_console()


func _cmd_banner(_args: Array) -> void:
	if EventWarningBanner and EventWarningBanner.has_method("test_banner"):
		EventWarningBanner.test_banner()
		_print_log("[color=green]Banner test triggered[/color]")
	else:
		_print_log("[color=red]EventWarningBanner not available[/color]")


func _cmd_event(args: Array) -> void:
	if args.is_empty():
		_print_log("Usage: event <name>")
		_print_log("Examples: event darkness, event speed_up, event fog")
		return
	
	var event_name = args[0].to_lower().replace(" ", "_").replace("-", "_")
	
	if not EventManager:
		_print_log("[color=red]EventManager not available[/color]")
		return
	
	# Find matching event type
	for event_type in EventManager.EventType.values():
		var name = EventManager.EVENT_NAMES.get(event_type, "").to_lower().replace(" ", "_")
		if name == event_name:
			if EventManager.has_method("debug_trigger_event"):
				EventManager.debug_trigger_event(event_type)
				_print_log("[color=green]Triggering event: %s[/color]" % EventManager.EVENT_NAMES.get(event_type))
				return
	
	_print_log("[color=red]Unknown event: %s[/color]" % args[0])
	_print_log("Type 'events' to see all available events")


func _cmd_events(_args: Array) -> void:
	if not EventManager:
		_print_log("[color=red]EventManager not available[/color]")
		return
	
	_print_log("\n[color=yellow]Available Events:[/color]")
	for event_type in EventManager.EventType.values():
		if event_type != EventManager.EventType.NONE and event_type != EventManager.EventType.ALL_CLEAR:
			var name = EventManager.EVENT_NAMES.get(event_type, "Unknown")
			_print_log("  - [color=cyan]%s[/color]" % name.to_lower().replace(" ", "_"))
	_print_log("")


func _cmd_race(_args: Array) -> void:
	if not RaceManager:
		_print_log("[color=red]RaceManager not available[/color]")
		return
	
	var active = RaceManager.is_race_active()
	_print_log("Race Active: [color=%s]%s[/color]" % ["green" if active else "red", active])
	if active:
		_print_log("Target: %s" % RaceManager.get_target_article())
		_print_log("Start: %s" % RaceManager.get_start_article())


func _cmd_time(_args: Array) -> void:
	if not RaceManager:
		_print_log("[color=red]RaceManager not available[/color]")
		return
	
	var time = RaceManager.get_elapsed_time()
	_print_log("Race Time: [color=cyan]%.1f[/color] seconds" % time)
	
	if RaceManager.has_method("get_timer_scale"):
		var scale = RaceManager.get_timer_scale()
		_print_log("Timer Scale: [color=cyan]%.2f[/color]x" % scale)


func _cmd_speed(_args: Array) -> void:
	if not RaceManager:
		_print_log("[color=red]RaceManager not available[/color]")
		return
	
	_print_log("Timer Scale: [color=cyan]%.2f[/color]x" % RaceManager.get_timer_scale())


func _cmd_fps(_args: Array) -> void:
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	_print_log("FPS: [color=cyan]%d[/color]" % fps)


func _cmd_goto(args: Array) -> void:
	if args.is_empty():
		_print_log("Usage: goto <room_name>")
		return

	_print_log("[color=yellow]Teleport not yet implemented[/color]")
