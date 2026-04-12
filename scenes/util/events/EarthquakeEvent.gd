class_name EarthquakeEvent
extends RefCounted
## Earthquake - Camera and objects shake violently for 20-35 seconds

static var _original_shake_intensity: float = 0.0
static var _shake_active: bool = false
static var _shake_nodes: Array = []
static var _shake_timer: float = 0.0
static var _original_positions: Dictionary = {}

static func apply() -> void:
	_shake_active = true
	_shake_timer = 0.0
	_shake_nodes.clear()
	_original_positions.clear()

	# Add camera shake
	var camera = Engine.get_main_loop().root.get_viewport().get_camera_3d()
	if camera:
		_shake_nodes.append(camera)
		_original_positions[camera] = camera.transform
		Log.debug("EarthquakeEvent", "Found camera, adding to shake nodes")
	else:
		Log.warn("EarthquakeEvent", "No camera found!")

	# Mark all physics objects for shaking
	var shakeable_count = 0
	for body in Engine.get_main_loop().get_nodes_in_group("shakeable"):
		if body is RigidBody3D:
			_shake_nodes.append(body)
			_original_positions[body] = body.transform
			shakeable_count += 1

	Log.info("EarthquakeEvent", "Applied: Earthquake started (shaking %d nodes)" % _shake_nodes.size())

static func _process_shake(_delta: float) -> void:
	if not _shake_active:
		return

	_shake_timer += _delta

	# Shake all nodes
	for node in _shake_nodes:
		if not is_instance_valid(node):
			continue

		if node is Camera3D:
			# Camera shake - offset position (MORE VISIBLE)
			var original = _original_positions.get(node, Transform3D())
			var shake_offset = Vector3(
				sin(_shake_timer * 50) * 0.3,  # Stronger X shake
				cos(_shake_timer * 40) * 0.3,  # Stronger Y shake
				sin(_shake_timer * 30) * 0.15   # Stronger Z shake
			)
			node.transform = original
			node.transform.origin += shake_offset

		elif node is RigidBody3D:
			# Physics body shake - apply STRONGER random impulses
			if _shake_timer > _shake_timer - _delta:  # Every frame
				node.apply_central_impulse(Vector3(
					randf_range(-10, 10),  # Stronger X impulse
					randf_range(2, 5),     # Stronger Y impulse (upward)
					randf_range(-10, 10)   # Stronger Z impulse
				))

static func end() -> void:
	_shake_active = false

	# Restore all nodes to original positions
	for node in _original_positions:
		if is_instance_valid(node):
			if node is Camera3D or node is RigidBody3D:
				node.transform = _original_positions[node]

	# Restore camera
	var camera = Engine.get_main_loop().root.get_viewport().get_camera_3d()
	if camera:
		camera.set_meta("shake_intensity", _original_shake_intensity)

	_shake_nodes.clear()
	_shake_timer = 0.0
	_original_positions.clear()
	Log.info("EarthquakeEvent", "Earthquake stopped")

static func get_duration() -> float:
	return randf_range(20.0, 35.0)

static func get_display_name() -> String:
	return "Earthquake"

static func get_description() -> String:
	return "The ground shakes violently!"
