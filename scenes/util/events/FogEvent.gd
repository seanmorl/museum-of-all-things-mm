class_name FogEvent
extends RefCounted
## Fog - Dense fog reduces visibility for 30-50 seconds

static var _original_fog_density: float = 0.0
static var _original_fog_enabled: bool = false
static var _world_env: WorldEnvironment = null

static func _find_world_environment() -> void:
	## Find the WorldEnvironment node (usually in Museum or Main scene)
	if _world_env and is_instance_valid(_world_env):
		return

	# Try to find via Museum node
	var museum = Engine.get_main_loop().current_scene.get_node_or_null("Museum")
	if museum and museum.has_node("WorldEnvironment"):
		_world_env = museum.get_node("WorldEnvironment")
		return

	# Fallback: search for any WorldEnvironment in the scene tree
	for node in Engine.get_main_loop().current_scene.get_tree().get_nodes_in_group("world_environment"):
		if node is WorldEnvironment:
			_world_env = node
			return

static func apply() -> void:
	_find_world_environment()

	if not _world_env or not is_instance_valid(_world_env):
		Log.error("FogEvent", "Failed to apply: WorldEnvironment not found")
		return

	var env = _world_env.environment
	if not env:
		Log.error("FogEvent", "Failed to apply: No environment in WorldEnvironment")
		return

	# Store original fog settings
	_original_fog_enabled = env.fog_enabled
	_original_fog_density = env.fog_density

	# Enable fog with VERY visible settings
	env.fog_enabled = true
	env.fog_density = 0.3  # Very dense fog (was 0.15 - too subtle)
	env.fog_light_color = Color(0.8, 0.8, 0.85)  # Light gray fog
	env.fog_light_energy = 1.0  # Make fog visible

	Log.info("FogEvent", "Applied: Dense fog enabled (density=%f)" % env.fog_density)

static func end() -> void:
	if not _world_env or not is_instance_valid(_world_env):
		return

	var env = _world_env.environment
	if not env:
		return

	# Restore original fog settings
	env.fog_enabled = _original_fog_enabled
	env.fog_density = _original_fog_density

	Log.info("FogEvent", "Fog restored")

static func get_duration() -> float:
	return randf_range(30.0, 50.0)

static func get_display_name() -> String:
	return "Fog"

static func get_description() -> String:
	return "Dense fog reduces visibility!"
