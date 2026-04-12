class_name DarknessEvent
extends RefCounted
## Darkness - All lights dim to 15% brightness for 20-35 seconds
## Also reduces ambient light for true darkness

static var _original_light_states: Dictionary = {}
static var _original_ambient_energy: float = 1.0
static var _world_env: WorldEnvironment = null

static func _find_world_env() -> void:
	## Find the WorldEnvironment node
	if _world_env and is_instance_valid(_world_env):
		return
	
	# Try to find via Museum node
	var museum = Engine.get_main_loop().current_scene.get_node_or_null("Museum")
	if museum and museum.has_node("WorldEnvironment"):
		_world_env = museum.get_node("WorldEnvironment")
		return
	
	# Fallback: search for any WorldEnvironment
	for node in Engine.get_main_loop().current_scene.get_tree().get_nodes_in_group("world_environment"):
		if node is WorldEnvironment:
			_world_env = node
			return

static func apply() -> void:
	# Store original states and dim all lights
	_original_light_states.clear()

	var lights_found = 0
	for light in Engine.get_main_loop().get_nodes_in_group("managed_light"):
		lights_found += 1
		if light is OmniLight3D or light is SpotLight3D:
			# Store original energy
			_original_light_states[light] = light.light_energy
			# Fade to 5% over 1 second (VERY dark)
			var tween = light.create_tween()
			tween.tween_property(light, "light_energy", 0.05, 1.0)

	# Also reduce ambient light from WorldEnvironment
	_find_world_env()
	if _world_env:
		_original_ambient_energy = _world_env.environment.ambient_light_energy
		var tween = _world_env.create_tween()
		tween.tween_property(_world_env.environment, "ambient_light_energy", 0.02, 1.0)  # VERY dark

	Log.info("DarknessEvent", "Applied: Lights dimmed to 5%%, ambient reduced to 2%% (found %d managed lights)" % lights_found)

static func end() -> void:
	# Restore original light energies
	for light in _original_light_states:
		if is_instance_valid(light):
			var original_energy = _original_light_states[light]
			var tween = light.create_tween()
			tween.tween_property(light, "light_energy", original_energy, 1.0)

	# Restore ambient light
	if _world_env:
		var tween = _world_env.create_tween()
		tween.tween_property(_world_env.environment, "ambient_light_energy", _original_ambient_energy, 1.0)

	_original_light_states.clear()
	Log.info("DarknessEvent", "Lights restored")

static func get_duration() -> float:
	return randf_range(20.0, 35.0)

static func get_display_name() -> String:
	return "Darkness"

static func get_description() -> String:
	return "All lights dim to near darkness!"
