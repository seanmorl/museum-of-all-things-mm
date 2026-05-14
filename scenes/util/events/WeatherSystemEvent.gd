class_name WeatherSystemEvent
extends EventBase
## Weather System - Rain/snow particles appear for 60-120 seconds

static var _weather_particles: GPUParticles3D = null
static var _original_weather_active: bool = false

static func apply() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "WeatherParticles"
	particles.amount = 5000
	particles.lifetime = 2.0
	particles.emitting = true
	particles.one_shot = false
	particles.local_coords = false
	_weather_particles = particles

	var spawn_pos := Vector3(0, 6, 0)
	var player_found := false

	var player := get_local_player()
	if player:
		spawn_pos = Vector3(player.global_position.x, player.global_position.y + 2.0, player.global_position.z)
		player_found = true
		Log.debug("WeatherSystemEvent", "Found player via local_player: %s" % player.global_position)

	if not player_found:
		var players := get_group_nodes("Player")
		if not players.is_empty():
			player = players[0]
			spawn_pos = Vector3(player.global_position.x, player.global_position.y + 2.0, player.global_position.z)
			player_found = true
			Log.debug("WeatherSystemEvent", "Found player via Player group")

	if not player_found:
		Log.warn("WeatherSystemEvent", "Could not find player! Spawning at origin!")

	particles.position = spawn_pos
	Log.info("WeatherSystemEvent", "Rain spawning at: %s" % spawn_pos)

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(60, 5, 60)
	process_material.direction = Vector3(0, -1, 0)
	process_material.spread = 10.0
	process_material.initial_velocity_min = 20.0
	process_material.initial_velocity_max = 40.0
	process_material.gravity = Vector3(0, -30.0, 0)
	process_material.color = Color(1.0, 1.0, 1.0, 1.0)
	process_material.scale_min = 0.3
	process_material.scale_max = 0.8
	particles.process_material = process_material

	get_scene().get_tree().root.add_child(particles)

	var marker := MeshInstance3D.new()
	marker.mesh = BoxMesh.new()
	marker.mesh.size = Vector3(5, 10, 5)
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.8)
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(1.0, 0.0, 0.0, 1.0)
	marker.material_override = marker_mat
	marker.position = spawn_pos
	get_scene().get_tree().root.add_child(marker)

	marker.create_tween().tween_property(marker, "scale", Vector3.ZERO, 5.0).set_delay(5.0)
	marker.call_deferred("queue_free")

	_original_weather_active = true
	Log.info("WeatherSystemEvent", "Applied: HEAVY RAIN at %s (5000 particles!)" % spawn_pos)

static func end() -> void:
	if _weather_particles and is_instance_valid(_weather_particles):
		_weather_particles.emitting = false
		_weather_particles.call_deferred("queue_free")
		_weather_particles = null
	_original_weather_active = false

static func get_duration() -> float:
	return randf_range(60.0, 120.0)

static func get_display_name() -> String:
	return "Weather System"

static func get_description() -> String:
	return "Rain begins to fall!"