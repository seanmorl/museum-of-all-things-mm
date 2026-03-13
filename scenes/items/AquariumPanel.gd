extends Node3D
class_name AquariumPanel
## Wall-mounted aquarium panel with animated fish and water caustics.
## Provides relaxing ambient visual for the lobby.

@onready var _fish_nodes: Array = [$Fish1, $Fish2, $Fish3] if has_node("Fish1") and has_node("Fish2") and has_node("Fish3") else []
@onready var _backlight: OmniLight3D = $Backlight if has_node("Backlight") else null

var _swim_speeds: Array = []
var _swim_directions: Array = []
var _fish_offsets: Array = []
var _time: float = 0.0

func _ready() -> void:
	add_to_group("ExhibitItem")
	# Initialize random swim parameters for each fish
	for fish in _fish_nodes:
		_swim_speeds.append(randf_range(0.3, 0.8))
		_swim_directions.append(randf() > 0.5)
		_fish_offsets.append(randf() * 10.0)
		# Store initial Y position
		if fish:
			fish.set_meta("initial_y", fish.position.y)
	
	# Randomize backlight hue slightly
	if _backlight:
		var hue: float = randf_range(0.5, 0.65)  # Blue to cyan range
		_backlight.light_color = Color.from_hsv(hue, 0.5, 0.9, 0.7)

func _process(delta: float) -> void:
	_time += delta
	
	# Animate each fish swimming back and forth
	for i in range(_fish_nodes.size()):
		if i >= _fish_nodes.size() or not is_instance_valid(_fish_nodes[i]):
			continue
		
		var fish: MeshInstance3D = _fish_nodes[i]
		var time: float = _time + _fish_offsets[i]
		var speed: float = _swim_speeds[i]
		var initial_y: float = fish.get_meta("initial_y") if fish.has_meta("initial_y") else fish.position.y
		
		# Horizontal swimming motion (sine wave)
		var swim_x: float = sin(time * speed) * 0.7
		# Vertical bobbing motion
		var swim_y: float = initial_y + cos(time * speed * 1.5) * 0.3
		
		# Face direction of movement
		var scale_x: float = -1.0 if _swim_directions[i] else 1.0
		if sin(time * speed) < 0:
			scale_x = -scale_x
		
		fish.position.x = swim_x
		fish.position.y = swim_y
		fish.scale.x = abs(scale_x) * 0.3  # Flatten fish sprite
		fish.scale.z = abs(scale_x)  # Face direction
	
	# Subtle backlight pulse
	if _backlight:
		var pulse: float = sin(_time * 0.5) * 0.2 + 0.8
		_backlight.light_energy = 1.8 * pulse

func interact() -> void:
	# Optional: Make fish swim faster briefly when interacted with
	for i in range(_swim_speeds.size()):
		_swim_speeds[i] *= 3.0
	await get_tree().create_timer(3.0).timeout
	for i in range(_swim_speeds.size()):
		_swim_speeds[i] /= 3.0

func get_interaction_text() -> String:
	return "Watch Fish"
