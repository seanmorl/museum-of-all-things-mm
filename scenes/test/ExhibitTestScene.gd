extends Node3D
## Test scene for exhibit generation features
## Press 1-5 to test different configurations

const ExhibitMood = preload("res://scenes/util/ExhibitMood.gd")
const TiledExhibitGenerator = preload("res://scenes/TiledExhibitGenerator.gd")

var _generator: Node3D = null
var _current_test: int = 0

const TEST_CONFIGS: Array[Dictionary] = [
	{
		"name": "HISTORY - With Grand Halls & Atriums",
		"title": "Ancient Rome",
		"mood": ExhibitMood.Mood.HISTORY,
		"debug": true,
		"min_rooms": 3,
	},
	{
		"name": "SCIENCE - Modular Layout",
		"title": "Quantum Physics",
		"mood": ExhibitMood.Mood.SCIENCE,
		"debug": true,
		"min_rooms": 4,
	},
	{
		"name": "NATURE - Organic Shapes",
		"title": "Rainforest Ecosystem",
		"mood": ExhibitMood.Mood.NATURE,
		"debug": true,
		"min_rooms": 3,
	},
	{
		"name": "ASTRO - Complex Layout",
		"title": "Deep Space Exploration",
		"mood": ExhibitMood.Mood.ASTRO,
		"debug": true,
		"min_rooms": 4,
	},
	{
		"name": "MEDIA - Vertical Focus",
		"title": "Film History",
		"mood": ExhibitMood.Mood.MEDIA,
		"debug": true,
		"min_rooms": 3,
	},
]


func _ready() -> void:
	print("\n=== EXHIBIT TEST SCENE ===")
	print("Press 1-5 to test different exhibit configurations")
	print("Press R to regenerate current config")
	print("Press C to clear and regenerate\n")
	_generate_current_test()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.scancode >= KEY_1 and event.scancode <= KEY_5:
			_current_test = event.scancode - KEY_1
			_generate_current_test()
		elif event.scancode == KEY_R:
			_generate_current_test()
		elif event.scancode == KEY_C:
			_clear_and_regenerate()


func _clear_and_regenerate() -> void:
	# Remove old generator
	if is_instance_valid(_generator):
		_generator.queue_free()
	
	# Create new generator
	_generator = TiledExhibitGenerator.new()
	add_child(_generator)
	_generate_current_test()


func _generate_current_test() -> void:
	var config: Dictionary = TEST_CONFIGS[_current_test]
	
	print("\n=== TEST %d: %s ===" % [_current_test + 1, config.name])
	
	# Clear old generator
	if is_instance_valid(_generator):
		_generator.queue_free()
	
	# Create new generator
	_generator = TiledExhibitGenerator.new()
	add_child(_generator)
	
	# Generate with config
	_generator.generate({
		"title": config.title,
		"prev_title": "Lobby",
		"start_pos": Vector3(0, 0, 0),
		"min_room_dimension": 2,
		"max_room_dimension": 5,
		"exit_limit": 10,
		"mood": config.mood,
		"min_rooms": config.min_rooms,
		"debug_mode": config.debug,
		"no_props": false,
	})
	
	print("Generating '%s' with mood=%s, min_rooms=%d, debug=%s" % [
		config.title,
		ExhibitMood.Mood.keys()[config.mood],
		config.min_rooms,
		config.debug
	])
	
	# Validate after a short delay
	await get_tree().create_timer(0.5).timeout
	if _generator.has_method("validate_final_generation"):
		var valid: bool = _generator.validate_final_generation()
		print("Validation: %s" % ("PASSED" if valid else "FAILED"))
