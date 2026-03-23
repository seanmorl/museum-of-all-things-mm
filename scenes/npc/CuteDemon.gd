extends CharacterBody3D
class_name CuteDemon
## CuteDemon - A tiny friendly demon that appears randomly to tell you lovely facts
## Spawns occasionally in exhibits and shares wholesome trivia with visitors.

const LOVELY_FACTS: Array[String] = [
	# Animals
	"Sea otters hold hands when they sleep to keep from drifting apart! 🦦",
	"Cows have best friends and get stressed when separated! 🐄",
	"Octopuses have three hearts and blue blood! 🐙",
	"Penguins propose to their partners with a pebble! 🐧",
	"Dolphins give each other names! 🐬",
	"Elephants can recognize themselves in mirrors! 🐘",
	"Ravens can remember faces for years! 🐦",
	# Nature
	"Trees communicate through underground fungal networks! 🌳",
	"A single oak tree can support over 2,000 species! 🌿",
	"Flowers bloom at different times to help pollinators! 🌸",
	"Mushrooms can clean up oil spills! 🍄",
	# Science
	"Honey never spoils - 3000 year old honey is still edible! 🍯",
	"Your body replaces 33 million cells every second! ✨",
	"The universe is mostly made of things we can't see! 🌌",
	"Water can boil and freeze at the same time! 💧",
	# Wholesome
	"Someone smiled today because of something you did! 💕",
	"You've survived 100% of your worst days! 💪",
	"Every atom in your body came from a star! ⭐",
	"There are more stars than grains of sand on Earth! 🌠",
]

var _fact_index: int = 0
var _despawn_timer: float = 30.0  # Despawn after 30 seconds
var _chat_timer: float = 0.0
var _chat_interval: float = 8.0  # Share a fact every 8 seconds
var _has_spoken: bool = false

@onready var _mesh: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var _label: Label3D = $Label3D if has_node("Label3D") else null
@onready var _audio: AudioStreamPlayer3D = $AudioStreamPlayer3D if has_node("AudioStreamPlayer3D") else null


func _ready() -> void:
	# Set up collision for interaction
	if has_node("CollisionShape3D"):
		var shape = get_node("CollisionShape3D").shape as CapsuleShape3D
		if shape:
			shape.radius = 0.4
			shape.height = 0.8

	# Make cute demon appearance
	_setup_appearance()

	# Show initial greeting
	_show_label("✨ A cute demon appeared! ✨")


func _setup_appearance() -> void:
	"""Set up the cute demon's visual appearance"""
	if _mesh:
		# Create a cute red capsule body
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.8, 0.2, 0.2)  # Cute red
		material.roughness = 0.4
		_mesh.material_override = material
		_mesh.layers = 4194304  # Layer 22 (matches NPC collision layer)
	
	# Add tiny horns if we have a more complex model
	# (This would require a proper 3D model, but the red capsule is cute enough!)


func _process(delta: float) -> void:
	if not is_inside_tree():
		return

	# Despawn timer
	_despawn_timer -= delta
	if _despawn_timer <= 0:
		_fade_out()
		return

	# Look at nearest player
	_look_at_player()

	# Share facts periodically
	if not _has_spoken:
		_chat_timer += delta
		if _chat_timer >= _chat_interval:
			_chat_timer = 0.0
			_share_lovely_fact()


func _look_at_player() -> void:
	"""Rotate to face the nearest player"""
	var nearest_player: Node3D = null
	var nearest_dist: float = INF
	
	for player in get_tree().get_nodes_in_group("Player"):
		if not is_instance_valid(player):
			continue
		var dist = global_position.distance_to(player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_player = player
	
	if nearest_player:
		look_at(nearest_player.global_position)


func _share_lovely_fact() -> void:
	"""Share a lovely fact with nearby players"""
	if LOVELY_FACTS.is_empty():
		return
	
	# Pick a random fact we haven't said yet
	var available_facts = LOVELY_FACTS.duplicate()
	if _fact_index < LOVELY_FACTS.size():
		# Cycle through facts in order
		var fact = LOVELY_FACTS[_fact_index % LOVELY_FACTS.size()]
		_fact_index += 1
		_show_label(fact)
		_has_spoken = true
		
		# Play a cute sound if we have audio
		if _audio and _audio.stream:
			_audio.play()


func _show_label(text: String) -> void:
	"""Display text in the label above the demon"""
	if _label:
		_label.text = text
		_label.visible = true
		
		# Auto-hide after 5 seconds
		await get_tree().create_timer(5.0).timeout
		if is_instance_valid(_label):
			_label.text = ""


func _fade_out() -> void:
	"""Fade out and despawn"""
	if _label:
		_show_label("Bye! 💕")
	
	await get_tree().create_timer(2.0).timeout
	queue_free()


func interact() -> void:
	"""Called when player interacts with the demon"""
	_share_lovely_fact()
	_despawn_timer = 10.0  # Give them 10 seconds after interaction


func get_interaction_text() -> String:
	return "Talk to cute demon"
