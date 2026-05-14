extends Node
class_name InputManager
## Centralized input action registration and keybind management.
## Reduces Main.gd complexity by extracting all InputMap action creation.

# ── Public API ────────────────────────────────────────────────────────────────

static func register_all() -> void:
	register_trivia_keybind()
	register_daily_challenge_keybind()
	register_host_menu_keybind()
	register_spectator_keybind()
	register_ui_scale_shortcuts()
	register_screenshot_keybind()


static func register_trivia_keybind() -> void:
	if not InputMap.has_action("toggle_trivia"):
		InputMap.add_action("toggle_trivia")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_K
		InputMap.action_add_event("toggle_trivia", ev)


static func register_daily_challenge_keybind() -> void:
	if not InputMap.has_action("open_daily_challenge"):
		InputMap.add_action("open_daily_challenge")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_G
		InputMap.action_add_event("open_daily_challenge", ev)


static func register_host_menu_keybind() -> void:
	if not InputMap.has_action("toggle_host_menu"):
		InputMap.add_action("toggle_host_menu")
		# Ctrl+H as primary (avoids F1 conflicts with browser/debugger)
		var ev_ctrl_h := InputEventKey.new()
		ev_ctrl_h.physical_keycode = KEY_H
		ev_ctrl_h.ctrl_pressed = true
		InputMap.action_add_event("toggle_host_menu", ev_ctrl_h)


static func register_spectator_keybind() -> void:
	if not InputMap.has_action("toggle_spectator"):
		InputMap.add_action("toggle_spectator")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F
		InputMap.action_add_event("toggle_spectator", ev)


static func register_ui_scale_shortcuts() -> void:
	for action_name in ["ui_scale_in", "ui_scale_out", "ui_scale_reset"]:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
	
	# Ctrl+= zoom in (also KP_ADD)
	var ev_in := InputEventKey.new()
	ev_in.physical_keycode = KEY_EQUAL
	ev_in.ctrl_pressed = true
	InputMap.action_add_event("ui_scale_in", ev_in)
	
	var ev_in2 := InputEventKey.new()
	ev_in2.physical_keycode = KEY_KP_ADD
	ev_in2.ctrl_pressed = true
	InputMap.action_add_event("ui_scale_in", ev_in2)
	
	# Ctrl+- zoom out (also KP_SUBTRACT)
	var ev_out := InputEventKey.new()
	ev_out.physical_keycode = KEY_MINUS
	ev_out.ctrl_pressed = true
	InputMap.action_add_event("ui_scale_out", ev_out)
	
	var ev_out2 := InputEventKey.new()
	ev_out2.physical_keycode = KEY_KP_SUBTRACT
	ev_out2.ctrl_pressed = true
	InputMap.action_add_event("ui_scale_out", ev_out2)
	
	# Ctrl+0 reset
	var ev_reset := InputEventKey.new()
	ev_reset.physical_keycode = KEY_0
	ev_reset.ctrl_pressed = true
	InputMap.action_add_event("ui_scale_reset", ev_reset)


static func register_screenshot_keybind() -> void:
	if not InputMap.has_action("take_screenshot"):
		InputMap.add_action("take_screenshot")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F12
		InputMap.action_add_event("take_screenshot", ev)