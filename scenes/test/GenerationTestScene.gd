extends Node3D
## Automated Procedural Generation Test Scene
## Run with F6 to test exhibit generation automatically

const ExhibitMood = preload("res://scenes/util/ExhibitMood.gd")
const TiledExhibitGenerator = preload("res://scenes/TiledExhibitGenerator.gd")

var test_results: Array[Dictionary] = []
var tests_passed: int = 0
var tests_failed: int = 0

const TEST_CONFIGS: Array[Dictionary] = [
	{
		"name": "HISTORY - Grand Halls & Atriums",
		"title": "Ancient Rome",
		"mood": ExhibitMood.Mood.HISTORY,
		"min_rooms": 3,
	},
	{
		"name": "SCIENCE - Modular Layout",
		"title": "Quantum Physics",
		"mood": ExhibitMood.Mood.SCIENCE,
		"min_rooms": 4,
	},
	{
		"name": "NATURE - Organic Layout",
		"title": "Rainforest Ecosystem",
		"mood": ExhibitMood.Mood.NATURE,
		"min_rooms": 3,
	},
	{
		"name": "ASTRO - Complex Layout",
		"title": "Deep Space Exploration",
		"mood": ExhibitMood.Mood.ASTRO,
		"min_rooms": 4,
	},
	{
		"name": "MEDIA - Vertical Focus",
		"title": "Film History",
		"mood": ExhibitMood.Mood.MEDIA,
		"min_rooms": 3,
	},
]


func _ready() -> void:
	print("\n")
	print("╔═══════════════════════════════════════════════════════════╗")
	print("║      PROCEDURAL GENERATION - AUTOMATED TEST SCENE        ║")
	print("╚═══════════════════════════════════════════════════════════╝")
	print("\n")
	
	# Run all generation tests
	await _run_generation_tests()
	
	# Print summary
	_print_summary()
	
	# Keep scene open for manual inspection if debug build
	if OS.is_debug_build():
		print("\nTests complete. Scene remains open for inspection.")
	else:
		get_tree().quit(0 if tests_failed == 0 else 1)


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


func _run_generation_tests() -> void:
	print("\n┌─────────────────────────────────────────────────────────────┐")
	print("│ Running Procedural Generation Tests                        │")
	print("└─────────────────────────────────────────────────────────────┘\n")
	
	for i: int in range(TEST_CONFIGS.size()):
		var config: Dictionary = TEST_CONFIGS[i]
		print("\n── Test %d/%d: %s ──" % [i + 1, TEST_CONFIGS.size(), config.name])
		
		# Generate exhibit
		var generator: Node3D = TiledExhibitGenerator.new()
		add_child(generator)
		
		generator.generate({
			"title": config.title,
			"prev_title": "Lobby",
			"start_pos": Vector3(0, 0, 0),
			"min_room_dimension": 2,
			"max_room_dimension": 5,
			"exit_limit": 10,
			"mood": config.mood,
			"min_rooms": config.min_rooms,
			"debug_mode": false,
			"no_props": true,  # Skip props for faster testing
		})
		
		# Wait for generation to complete
		await get_tree().create_timer(0.5).timeout
		
		# Run validation tests
		await _test_minimum_rooms(generator, config)
		await _test_entry_point_exists(generator)
		await _test_exits_valid(generator)
		await _test_no_overlapping_rooms(generator)
		await _test_item_slots_valid(generator)
		
		# Cleanup
		generator.queue_free()
		await get_tree().create_timer(0.2).timeout


func _test_minimum_rooms(generator: Node3D, config: Dictionary) -> void:
	var room_count: int = generator._room_count if generator.has_method("_room_count") else 0
	var min_rooms: int = config.min_rooms
	
	if room_count >= min_rooms:
		_log_pass("Minimum rooms (%d/%d): %s" % [room_count, min_rooms, config.title])
	else:
		_log_fail("Minimum rooms (%d/%d): %s" % [room_count, min_rooms, config.title], 
			"Only %d rooms generated, expected %d" % [room_count, min_rooms])


func _test_entry_point_exists(generator: Node3D) -> void:
	if generator.entry == null:
		_log_fail("Entry point exists", "No entry hall created")
		return
	
	if not generator.entry is Node:
		_log_fail("Entry point exists", "Entry is not a valid Node")
		return
	
	_log_pass("Entry point exists")


func _test_exits_valid(generator: Node3D) -> void:
	if not generator.has_method("get_exits") and not "exits" in generator:
		_log_fail("Exits valid", "Generator has no exits property")
		return
	
	var exits: Array = generator.exits if "exits" in generator else []
	
	if exits.is_empty():
		_log_fail("Exits valid", "No exits generated")
		return
	
	# Check that all exits have destinations
	var invalid_exits: int = 0
	for exit_hall in exits:
		if not "to_title" in exit_hall or exit_hall.to_title == "":
			invalid_exits += 1
	
	if invalid_exits == 0:
		_log_pass("Exits valid (%d exits)" % exits.size())
	else:
		_log_fail("Exits valid", "%d exits have no destination" % invalid_exits)


func _test_no_overlapping_rooms(generator: Node3D) -> void:
	# Get all room bounds
	if not generator.has_method("get_rooms_for_npcs"):
		_log_fail("No overlapping rooms", "Cannot get room data")
		return
	
	var rooms: Array = generator.get_rooms_for_npcs()
	if rooms.size() < 2:
		_log_pass("No overlapping rooms (only 1 room)")
		return
	
	# Check for overlaps
	var overlaps_found: bool = false
	for i: int in range(rooms.size()):
		for j: int in range(i + 1, rooms.size()):
			var bounds1: Array = rooms[i].bounds
			var bounds2: Array = rooms[j].bounds
			
			if _bounds_overlap(bounds1, bounds2):
				overlaps_found = true
				break
		if overlaps_found:
			break
	
	if not overlaps_found:
		_log_pass("No overlapping rooms")
	else:
		_log_fail("No overlapping rooms", "Room overlaps detected")


func _bounds_overlap(bounds1: Array, bounds2: Array) -> bool:
	## Check if two room bounds overlap
	var min1: Vector3 = bounds1[0]
	var max1: Vector3 = bounds1[1]
	var min2: Vector3 = bounds2[0]
	var max2: Vector3 = bounds2[1]
	
	# Simple AABB overlap test
	return not (
		max1.x < min2.x or max2.x < min1.x or
		max1.z < min2.z or max2.z < min1.z
	)


func _test_item_slots_valid(generator: Node3D) -> void:
	if not generator.has_method("get_item_slot"):
		_log_fail("Item slots valid", "Generator has no item slots")
		return
	
	# Check that item slots have valid positions
	var total_slots: int = generator._item_slots.size() if "_item_slots" in generator else 0
	
	if total_slots == 0:
		_log_fail("Item slots valid", "No item slots generated")
		return
	
	# Sample a few slots to check validity
	var valid_slots: int = 0
	for i: int in range(min(5, total_slots)):
		if not generator.has_item_slot():
			break
		var slot: Variant = generator.get_item_slot()
		if slot is Array and slot.size() >= 2:
			var pos: Variant = slot[0]
			var dir: Variant = slot[1]
			if pos is Vector3 and dir is Vector3:
				valid_slots += 1
	
	if valid_slots > 0:
		_log_pass("Item slots valid (%d/%d valid)" % [valid_slots, min(5, total_slots)])
	else:
		_log_fail("Item slots valid", "Item slots have invalid format")


# ── Manual Test Controls ─────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.scancode:
			KEY_1:
				_run_single_test(0)
			KEY_2:
				_run_single_test(1)
			KEY_3:
				_run_single_test(2)
			KEY_4:
				_run_single_test(3)
			KEY_5:
				_run_single_test(4)
			KEY_R:
				# Regenerate all tests
				await _run_generation_tests()
				_print_summary()


func _run_single_test(index: int) -> void:
	if index < 0 or index >= TEST_CONFIGS.size():
		return
	
	var config: Dictionary = TEST_CONFIGS[index]
	print("\n── Manual Test: %s ──" % config.name)
	
	# Clear existing generators
	for child in get_children():
		if child is TiledExhibitGenerator:
			child.queue_free()
	
	# Generate
	var generator: Node3D = TiledExhibitGenerator.new()
	add_child(generator)
	
	generator.generate({
		"title": config.title,
		"prev_title": "Lobby",
		"start_pos": Vector3(0, 0, 0),
		"min_room_dimension": 2,
		"max_room_dimension": 5,
		"exit_limit": 10,
		"mood": config.mood,
		"min_rooms": config.min_rooms,
		"debug_mode": true,  # Enable debug visualization
		"no_props": false,
	})
	
	print("Generated '%s' - inspect in scene" % config.title)
