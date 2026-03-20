class_name WeatherSystemEvent
extends RefCounted
## Weather System - Rain/snow particles appear for 60-120 seconds

static var _weather_particles: GPUParticles3D = null
static var _original_weather_active: bool = false

static func apply() -> void:
	# Create weather particle system
	_weather_particles = GPUParticles3D.new()
	_weather_particles.name = "WeatherParticles"
	_weather_particles.amount = 5000  # LOTS of particles!
	_weather_particles.lifetime = 2.0
	_weather_particles.emitting = true
	_weather_particles.one_shot = false
	_weather_particles.local_coords = false  # World-space particles
	
	# Position ABOVE the player but INSIDE the room (not above ceiling!)
	var museum = Engine.get_main_loop().current_scene.get_node_or_null("Museum")
	var spawn_pos = Vector3(0, 6, 0)  # Default: 6m high (below most ceilings)
	
	# Try MULTIPLE ways to find player position
	var player_found: bool = false
	
	# Method 1: Try to get player from Museum
	if museum:
		var player = museum.get_node_or_null("Player")
		if player:
			# Spawn rain at player head height + 2m (so it falls ON them)
			spawn_pos = Vector3(player.global_position.x, player.global_position.y + 2.0, player.global_position.z)
			player_found = true
			print("[WeatherSystemEvent] ✓ Found player via Museum.Player: %s" % player.global_position)
	
	# Method 2: Search for local_player group
	if not player_found:
		var players = Engine.get_main_loop().get_nodes_in_group("local_player")
		if players.size() > 0:
			var player = players[0]
			spawn_pos = Vector3(player.global_position.x, player.global_position.y + 2.0, player.global_position.z)
			player_found = true
			print("[WeatherSystemEvent] ✓ Found player via local_player: %s" % player.global_position)
	
	# Method 3: Search for Player group
	if not player_found:
		var players = Engine.get_main_loop().get_nodes_in_group("Player")
		if players.size() > 0:
			var player = players[0]
			spawn_pos = Vector3(player.global_position.x, player.global_position.y + 2.0, player.global_position.z)
			player_found = true
			print("[WeatherSystemEvent] ✓ Found player via Player group: %s" % player.global_position)
	
	if not player_found:
		print("[WeatherSystemEvent] ✗ WARNING: Could not find player! Spawning at origin!")
	
	_weather_particles.position = spawn_pos
	
	print("[WeatherSystemEvent] Rain spawning at: %s (2m above player head!)" % spawn_pos)
	print("[WeatherSystemEvent] Look up - rain should be falling on you!")
	
	# Configure for rain
	var process_material = ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(60, 5, 60)  # HUGE area
	process_material.direction = Vector3(0, -1, 0)  # Fall down
	process_material.spread = 10.0
	process_material.initial_velocity_min = 20.0
	process_material.initial_velocity_max = 40.0
	process_material.gravity = Vector3(0, -30.0, 0)  # VERY strong gravity
	
	# Make particles VERY visible as raindrops
	process_material.color = Color(1.0, 1.0, 1.0, 1.0)  # BRIGHT white rain
	
	# Particle size - make them LARGER
	process_material.scale_min = 0.3
	process_material.scale_max = 0.8
	
	_weather_particles.process_material = process_material

	# Add to scene root
	Engine.get_main_loop().root.add_child(_weather_particles)
	
	# Also add a VERY visible marker so you can SEE where the rain is spawning
	var marker = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(5, 10, 5)  # HUGE box
	marker.mesh = box
	var marker_mat = StandardMaterial3D.new()
	marker_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.8)  # BRIGHT RED
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(1.0, 0.0, 0.0, 1.0)  # GLOWING RED
	marker.material_override = marker_mat
	marker.position = spawn_pos
	Engine.get_main_loop().root.add_child(marker)
	
	print("[WeatherSystemEvent] SPAWNED at: %s" % spawn_pos)
	print("[WeatherSystemEvent] Look for the HUGE GLOWING RED BOX!")
	print("[WeatherSystemEvent] Player position was: %s" % (museum.get_node_or_null("Player").global_position if museum and museum.get_node_or_null("Player") else "Unknown"))
	
	# Remove marker after 10 seconds
	marker.create_tween().tween_property(marker, "scale", Vector3.ZERO, 5.0).set_delay(5.0)
	marker.call_deferred("queue_free")  # No arguments!

	_original_weather_active = true
	print("[WeatherSystemEvent] Applied: HEAVY RAIN at %s (5000 particles!)" % spawn_pos)

static func end() -> void:
	# Remove weather particles
	if _weather_particles and is_instance_valid(_weather_particles):
		_weather_particles.emitting = false
		# Give it a moment to fade, then remove
		_weather_particles.call_deferred("queue_free")
		_weather_particles = null

	_original_weather_active = false
	print("[WeatherSystemEvent] Ended: Weather cleared")

static func get_duration() -> float:
	return randf_range(60.0, 120.0)

static func get_display_name() -> String:
	return "Weather System"

static func get_description() -> String:
	return "Rain begins to fall!"
