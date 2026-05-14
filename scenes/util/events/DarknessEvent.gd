class_name DarknessEvent
extends EventBase
## Darkness - All lights dim to 15%% brightness for 20-35 seconds

static var _original_light_states: Dictionary = {}
static var _original_ambient_energy: float = 1.0
static var _world_env: WorldEnvironment = null

static func _find_world_env() -> void:
	if _world_env and is_instance_valid(_world_env):
		return
	var museum := get_museum()
	if museum and museum.has_node("WorldEnvironment"):
		_world_env = museum.get_node("WorldEnvironment")
		return
	for node in get_scene().get_tree().get_nodes_in_group("world_environment"):
		if node is WorldEnvironment:
			_world_env = node
			return

static func apply() -> void:
	_original_light_states.clear()
	for light in get_group_nodes("managed_light"):
		if light is OmniLight3D or light is SpotLight3D:
			_original_light_states[light] = light.light_energy
			light.create_tween().tween_property(light, "light_energy", 0.05, 1.0)

	_find_world_env()
	if _world_env:
		_original_ambient_energy = _world_env.environment.ambient_light_energy
		_world_env.create_tween().tween_property(_world_env.environment, "ambient_light_energy", 0.02, 1.0)

	Log.info("DarknessEvent", "Applied: Lights dimmed to 5%%, ambient reduced to 2%%")

static func end() -> void:
	for light in _original_light_states:
		if is_instance_valid(light):
			light.create_tween().tween_property(light, "light_energy", _original_light_states[light], 1.0)
	if _world_env:
		_world_env.create_tween().tween_property(_world_env.environment, "ambient_light_energy", _original_ambient_energy, 1.0)
	_original_light_states.clear()
	Log.info("DarknessEvent", "Lights restored")

static func get_duration() -> float:
	return randf_range(20.0, 35.0)

static func get_display_name() -> String:
	return "Darkness"

static func get_description() -> String:
	return "All lights dim to near darkness!"
