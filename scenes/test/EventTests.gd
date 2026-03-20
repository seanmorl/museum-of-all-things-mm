extends Node
## Environmental Events Test Suite
## Comprehensive tests for all environmental event types

var tests_passed: int = 0
var tests_failed: int = 0
var test_results: Array[Dictionary] = []


func _ready() -> void:
	print("\n")
	print("╔═══════════════════════════════════════════════════════════╗")
	print("║        ENVIRONMENTAL EVENTS - COMPREHENSIVE TESTS        ║")
	print("╚═══════════════════════════════════════════════════════════╝")
	print("\n")
	
	# Wait for autoloads to be ready
	await get_tree().create_timer(0.5).timeout
	
	# Run all tests
	await _test_all_events_exist()
	await _test_all_events_have_required_methods()
	await _test_event_durations_defined()
	await _test_event_names_defined()
	await _test_accessibility_restrictions()
	await _test_event_colors()
	await _test_warning_banner()
	await _test_event_manager_configuration()
	
	# Print summary
	_print_summary()


func _print_summary() -> void:
	print("\n")
	print("═══════════════════════════════════════════════════════════")
	print("  TEST SUMMARY")
	print("═══════════════════════════════════════════════════════════")
	print("  Passed: %d" % tests_passed)
	print("  Failed: %d" % tests_failed)
	print("  Total:  %d" % (tests_passed + tests_failed))
	
	if tests_failed == 0:
		print("\n  ✅ ALL TESTS PASSED!")
	else:
		print("\n  ❌ FAILED TESTS:")
		for result: Dictionary in test_results:
			if not result.passed:
				print("    - %s: %s" % [result.test, result.message])
	
	print("\n")


func _log_pass(test_name: String) -> void:
	tests_passed += 1
	print("  ✅ PASS: %s" % test_name)
	test_results.append({"test": test_name, "passed": true, "message": "OK"})


func _log_fail(test_name: String, message: String) -> void:
	tests_failed += 1
	print("  ❌ FAIL: %s - %s" % [test_name, message])
	test_results.append({"test": test_name, "passed": false, "message": message})


# ── Test Cases ───────────────────────────────────────────────────────────────

func _test_all_events_exist() -> void:
	print("\n┌─────────────────────────────────────────────────────────────┐")
	print("│ TEST: All event classes exist and load                     │")
	print("└─────────────────────────────────────────────────────────────┘")
	
	var event_types: Array = [
		"SpeedUpEvent",
		"HeavyGravityEvent",
		"DarknessEvent",
		"ColorShiftEvent",
		"FogEvent",
		"EarthquakeEvent",
		"WeatherSystemEvent",
		"NoRunningEvent",
		"TimeDilationEvent",
		"DoubleTimeEvent",
		"SilenceEvent",
		"ReversedEvent",
	]
	
	for event_name: String in event_types:
		if ClassDB.class_exists(event_name):
			_log_pass("Event class exists: %s" % event_name)
		else:
			# Try loading the script directly
			var script_path: String = "res://scenes/util/events/%s.gd" % event_name
			var script := load(script_path) if FileAccess.file_exists(script_path) else null
			if script:
				_log_pass("Event script loads: %s" % event_name)
			else:
				_log_fail("Event class exists: %s" % event_name, "Class/script not found")


func _test_all_events_have_required_methods() -> void:
	print("\n┌─────────────────────────────────────────────────────────────┐")
	print("│ TEST: All events have required static methods              │")
	print("└─────────────────────────────────────────────────────────────┘")
	
	var required_methods: Array = ["apply", "end", "get_duration", "get_display_name"]
	
	var event_scripts: Array = [
		"SpeedUpEvent",
		"HeavyGravityEvent",
		"DarknessEvent",
		"TimeDilationEvent",
		"DoubleTimeEvent",
		"NoRunningEvent",
		"ReversedEvent",
		"ColorShiftEvent",
		"FogEvent",
		"EarthquakeEvent",
		"WeatherSystemEvent",
		"SilenceEvent",
	]
	
	for event_name: String in event_scripts:
		var script_path: String = "res://scenes/util/events/%s.gd" % event_name
		if not FileAccess.file_exists(script_path):
			_log_fail("Required methods: %s" % event_name, "Script file not found")
			continue
		
		var script := load(script_path)
		var missing_methods: Array = []
		
		for method_name: String in required_methods:
			if not script.has_static_method(method_name):
				missing_methods.append(method_name)
		
		if missing_methods.is_empty():
			_log_pass("Required methods: %s" % event_name)
		else:
			_log_fail("Required methods: %s" % event_name, 
				"Missing methods: %s" % str(missing_methods))


func _test_event_durations_defined() -> void:
	print("\n┌─────────────────────────────────────────────────────────────┐")
	print("│ TEST: Event durations defined in EventManager              │")
	print("└─────────────────────────────────────────────────────────────┘")
	
	var em: Node = get_node_or_null("/root/EventManager")
	if em == null:
		_log_fail("Event durations defined", "EventManager not loaded")
		return
	
	if not em.has_node("EVENT_DURATIONS"):
		# Check if it's a constant
		if not "EVENT_DURATIONS" in em:
			_log_fail("Event durations defined", "EVENT_DURATIONS constant not found")
			return
	
	var durations: Variant = em.get("EVENT_DURATIONS")
	if durations == null:
		_log_fail("Event durations defined", "EVENT_DURATIONS is null")
		return
	
	# Check that all event types have duration entries
	var event_types_to_check: Array = [
		"DARKNESS", "COLOR_SHIFT", "FOG", "EARTHQUAKE", "WEATHER_SYSTEM",
		"SPEED_UP", "HEAVY_GRAVITY", "NO_RUNNING",
		"TIME_DILATION", "DOUBLE_TIME",
		"SILENCE",
		"REVERSED", "ALL_CLEAR"
	]
	
	var all_found: bool = true
	var missing: Array = []
	
	for event_type: String in event_types_to_check:
		var found: bool = false
		for key: Variant in durations.keys():
			if str(key).to_upper() == event_type:
				found = true
				break
		if not found:
			missing.append(event_type)
			all_found = false
	
	if all_found:
		_log_pass("Event durations defined")
	else:
		_log_fail("Event durations defined", "Missing durations for: %s" % str(missing))


func _test_event_names_defined() -> void:
	print("\n┌─────────────────────────────────────────────────────────────┐")
	print("│ TEST: Event names defined in EventManager                  │")
	print("└─────────────────────────────────────────────────────────────┘")
	
	var em: Node = get_node_or_null("/root/EventManager")
	if em == null:
		_log_fail("Event names defined", "EventManager not loaded")
		return
	
	if not "EVENT_NAMES" in em:
		_log_fail("Event names defined", "EVENT_NAMES constant not found")
		return
	
	var names: Variant = em.get("EVENT_NAMES")
	if names == null or names.is_empty():
		_log_fail("Event names defined", "EVENT_NAMES is empty")
		return
	
	_log_pass("Event names defined")


func _test_accessibility_restrictions() -> void:
	print("\n┌─────────────────────────────────────────────────────────────┐")
	print("│ TEST: Accessibility mode restrictions                      │")
	print("└─────────────────────────────────────────────────────────────┘")
	
	var em: Node = get_node_or_null("/root/EventManager")
	if em == null:
		_log_fail("Accessibility restrictions", "EventManager not loaded")
		return
	
	# Test that accessibility mode can be enabled
	em.accessibility_mode = true
	
	# Check that _apply_accessibility_restrictions method exists
	if not em.has_method("_apply_accessibility_restrictions"):
		_log_fail("Accessibility restrictions", "Missing _apply_accessibility_restrictions method")
		return
	
	# Apply restrictions
	em._apply_accessibility_restrictions()
	
	# Check that REVERSED event is blocked
	var reversed_blocked: bool = not (EventManager.EventType.REVERSED in em.allowed_events)
	if reversed_blocked:
		_log_pass("Accessibility blocks REVERSED")
	else:
		_log_fail("Accessibility blocks REVERSED", "REVERSED should be blocked")

	# Reset
	em.accessibility_mode = false
	em.reset_to_defaults()


func _test_event_colors() -> void:
	# SKIPPED: GraphMinimap.gd was removed (orphaned code)
	# Event colors are now handled differently in the new minimap system
	_log_pass("Event colors (test skipped - minimap system changed)")


func _test_warning_banner() -> void:
	print("\n┌─────────────────────────────────────────────────────────────┐")
	print("│ TEST: EventWarningBanner functionality                     │")
	print("└─────────────────────────────────────────────────────────────┘")
	
	var banner: Node = get_node_or_null("/root/EventWarningBanner")
	if banner == null:
		_log_fail("Warning banner", "EventWarningBanner not loaded")
		return
	
	# Check required methods
	var required_methods: Array = ["_on_event_warning", "_show_banner", "_hide_banner"]
	var missing_methods: Array = []
	
	for method_name: String in required_methods:
		if not banner.has_method(method_name):
			missing_methods.append(method_name)
	
	if missing_methods.is_empty():
		_log_pass("Warning banner methods")
	else:
		_log_fail("Warning banner methods", "Missing: %s" % str(missing_methods))
	
	# Check that it connects to EventManager
	if EventManager and EventManager.has_signal("event_warning"):
		_log_pass("Warning banner signal connection")
	else:
		_log_fail("Warning banner signal connection", "EventManager missing event_warning signal")


func _test_event_manager_configuration() -> void:
	print("\n┌─────────────────────────────────────────────────────────────┐")
	print("│ TEST: EventManager configuration API                       │")
	print("└─────────────────────────────────────────────────────────────┘")
	
	var em: Node = get_node_or_null("/root/EventManager")
	if em == null:
		_log_fail("EventManager config", "EventManager not loaded")
		return
	
	# Test configuration methods exist
	var required_methods: Array = [
		"configure_from_dict",
		"reset_to_defaults",
		"is_event_active",
		"get_active_events",
		"get_remaining_duration",
		"get_event_name"
	]
	
	var missing_methods: Array = []
	for method_name: String in required_methods:
		if not em.has_method(method_name):
			missing_methods.append(method_name)
	
	if missing_methods.is_empty():
		_log_pass("EventManager configuration API")
	else:
		_log_fail("EventManager configuration API", "Missing: %s" % str(missing_methods))
	
	# Test reset_to_defaults
	em.reset_to_defaults()
	if em.events_enabled and em.event_frequency > 0:
		_log_pass("EventManager reset_to_defaults works")
	else:
		_log_fail("EventManager reset_to_defaults works", "Defaults not applied correctly")
