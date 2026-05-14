extends Node
## Environmental Particle Effects Manager
## Creates atmospheric particles programmatically per exhibit mood.

# Active particle instances
var _active_particles: Array = []

# Shared mesh for particles (billboard quads)
var _particle_mesh: QuadMesh = null

# Cached materials per particle type (avoids reallocating every room transition)
var _material_cache: Dictionary = {}

# Shared curve resources
var _fade_curve: CurveTexture = null
var _alpha_fade_curve: CurveTexture = null

# Mood-based particle presets
const MOOD_PARTICLES: Dictionary = {
	ExhibitMood.Mood.HISTORY: ["dust"],
	ExhibitMood.Mood.SCIENCE: ["light_dust"],
	ExhibitMood.Mood.NATURE: ["spores"],
	ExhibitMood.Mood.ASTRO: ["sparkles"],
	ExhibitMood.Mood.MEDIA: ["film_grain"],
	ExhibitMood.Mood.ART: ["paint_mote"],
	ExhibitMood.Mood.GEOGRAPHY: ["mist"],
	ExhibitMood.Mood.PHILOSOPHY: ["wisp"],
	ExhibitMood.Mood.SPORTS: ["confetti"],
	ExhibitMood.Mood.FOOD: ["steam"],
	ExhibitMood.Mood.POLITICS: ["dust"],
	ExhibitMood.Mood.ECONOMY: ["gold_mote"],
	ExhibitMood.Mood.MYSTERY: ["smoke"],
	ExhibitMood.Mood.DEFAULT: ["dust"]  # Changed from [] so all exhibits get particles
}

class ParticleConfig:
	var amount: int
	var lifetime: float
	var emission_shape: int
	var box_extents: Vector3
	var sphere_radius: float
	var direction: Vector3
	var spread: float
	var flatness: float = 0.0
	var gravity: Vector3
	var vel_min: float
	var vel_max: float
	var scale_min: float
	var scale_max: float
	var ang_vel_min: float
	var ang_vel_max: float
	var color_start: Color
	var color_end: Color
	var turbulence: bool
	var lifetime_randomness: float = 0.0
	var hue_variation: float = 0.0
	var damping_min: float = 0.2
	var damping_max: float = 0.5

	func _init(p_amount: int, p_lifetime: float, p_shape: int, p_extents: Vector3, p_radius: float, p_dir: Vector3, p_spread: float, p_grav: Vector3, p_vmin: float, p_vmax: float, p_smin: float, p_smax: float, p_amin: float, p_amax: float, p_c1: Color, p_c2: Color, p_turb: bool) -> void:
		amount = p_amount
		lifetime = p_lifetime
		emission_shape = p_shape
		box_extents = p_extents
		sphere_radius = p_radius
		direction = p_dir
		spread = p_spread
		gravity = p_grav
		vel_min = p_vmin
		vel_max = p_vmax
		scale_min = p_smin
		scale_max = p_smax
		ang_vel_min = p_amin
		ang_vel_max = p_amax
		color_start = p_c1
		color_end = p_c2
		turbulence = p_turb

var CONFIGS: Dictionary = {}

signal particle_effect_spawned(name: String, position: Vector3)
signal particle_effect_removed(name: String)


func _ready() -> void:
	_build_particle_mesh()
	_build_shared_curves()
	_build_config_table()
	_build_material_cache()


func _build_particle_mesh() -> void:
	_particle_mesh = QuadMesh.new()
	_particle_mesh.size = Vector2(0.8, 0.8)
	var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var center = 64.0
	for x in 128:
		for y in 128:
			var dist = sqrt(pow(x - center, 2) + pow(y - center, 2)) / center
			var alpha = exp(-dist * dist * 3.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	var tex = ImageTexture.create_from_image(img)
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Use MIX blend for atmospheric particles that blend naturally
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	# Billboard so particles always face camera
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_particle_mesh.material = mat


func _build_config_table() -> void:
	CONFIGS = {
		"dust": ParticleConfig.new(
			50, 15.0,
			ParticleProcessMaterial.EMISSION_SHAPE_BOX, Vector3(10, 5, 10), 0.0,
			Vector3(0, 0.3, 0), 0.2, Vector3(0, -0.01, 0),
			0.02, 0.08, 0.12, 0.3, -0.02, 0.02,
			Color(0.85, 0.82, 0.75, 0.5), Color(0.75, 0.72, 0.65, 0.15),
			false
		),
		"light_dust": ParticleConfig.new(
			40, 16.0,
			ParticleProcessMaterial.EMISSION_SHAPE_BOX, Vector3(12, 6, 12), 0.0,
			Vector3(0, 0.2, 0), 0.15, Vector3.ZERO,
			0.01, 0.06, 0.1, 0.25, -0.01, 0.01,
			Color(0.85, 0.88, 0.95, 0.45), Color(0.75, 0.8, 0.9, 0.12),
			false
		),
		"spores": ParticleConfig.new(
			30, 12.0,
			ParticleProcessMaterial.EMISSION_SHAPE_BOX, Vector3(8, 4, 8), 0.0,
			Vector3(0, 0.4, 0), 0.15, Vector3(0, -0.02, 0),
			0.02, 0.08, 0.08, 0.2, 0.0, 0.0,
			Color(0.55, 0.8, 0.55, 0.55), Color(0.4, 0.65, 0.4, 0.15),
			true
		),
		"leaves": ParticleConfig.new(
			20, 8.0,
			ParticleProcessMaterial.EMISSION_SHAPE_BOX, Vector3(10, 1, 10), 0.0,
			Vector3(0, -0.5, 0), 0.4, Vector3(0, -0.2, 0),
			0.06, 0.15, 0.15, 0.3, -0.2, 0.2,
			Color(0.6, 0.4, 0.2, 0.55), Color(0.5, 0.3, 0.1, 0.15),
			true
		),
		"sparkles": ParticleConfig.new(
			25, 8.0,
			ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, Vector3.ZERO, 8.0,
			Vector3(0, 0.5, 0), 0.15, Vector3.ZERO,
			0.01, 0.04, 0.03, 0.06, 0.0, 0.0,
			Color(0.9, 0.93, 1.0, 0.7), Color(0.7, 0.8, 0.95, 0.2),
			false
		),
		"film_grain": ParticleConfig.new(
			80, 2.0,
			ParticleProcessMaterial.EMISSION_SHAPE_BOX, Vector3(10, 5, 10), 0.0,
			Vector3(0, 0, 0), 1.0, Vector3.ZERO,
			0.005, 0.02, 0.02, 0.06, 0.0, 0.0,
			Color(0.6, 0.6, 0.6, 0.2), Color(0.4, 0.4, 0.4, 0.04),
			false
		),
		"paint_mote": ParticleConfig.new(
			25, 12.0,
			ParticleProcessMaterial.EMISSION_SHAPE_BOX, Vector3(8, 4, 8), 0.0,
			Vector3(0, 0.3, 0), 0.2, Vector3(0, -0.02, 0),
			0.02, 0.08, 0.1, 0.25, 0.0, 0.0,
			Color(0.85, 0.6, 0.7, 0.55), Color(0.65, 0.45, 0.75, 0.15),
			true
		),
		"mist": ParticleConfig.new(
			30, 20.0,
			ParticleProcessMaterial.EMISSION_SHAPE_BOX, Vector3(12, 2, 12), 0.0,
			Vector3(0, 0.15, 0), 0.08, Vector3.ZERO,
			0.005, 0.02, 0.4, 0.8, 0.0, 0.0,
			Color(0.72, 0.82, 0.78, 0.3), Color(0.65, 0.75, 0.72, 0.06),
			true
		),
		"wisp": ParticleConfig.new(
			15, 16.0,
			ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, Vector3.ZERO, 6.0,
			Vector3(0, 0.3, 0), 0.1, Vector3(0, 0.01, 0),
			0.008, 0.03, 0.2, 0.4, 0.0, 0.0,
			Color(0.85, 0.8, 0.7, 0.45), Color(0.75, 0.7, 0.55, 0.08),
			true
		),
		"confetti": ParticleConfig.new(
			50, 5.0,
			ParticleProcessMaterial.EMISSION_SHAPE_BOX, Vector3(10, 1, 10), 0.0,
			Vector3(0, -0.8, 0), 0.6, Vector3(0, -0.6, 0),
			0.15, 0.4, 0.1, 0.25, 1.0, 3.0,
			Color(0.9, 0.75, 0.3, 0.8), Color(0.3, 0.7, 0.9, 0.3),
			true
		),
		"steam": ParticleConfig.new(
			40, 7.0,
			ParticleProcessMaterial.EMISSION_SHAPE_BOX, Vector3(6, 3, 6), 0.0,
			Vector3(0, 0.6, 0), 0.25, Vector3(0, 0.2, 0),
			0.08, 0.25, 0.35, 0.75, 0.0, 0.0,
			Color(0.92, 0.9, 0.85, 0.55), Color(0.88, 0.85, 0.78, 0.08),
			true
		),
		"gold_mote": ParticleConfig.new(
			30, 8.0,
			ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, Vector3.ZERO, 7.0,
			Vector3(0, 0.3, 0), 0.1, Vector3.ZERO,
			0.02, 0.06, 0.1, 0.25, 0.0, 0.0,
			Color(0.9, 0.78, 0.3, 0.7), Color(0.7, 0.58, 0.18, 0.15),
			false
		),
		"smoke": ParticleConfig.new(
			60, 12.0,
			ParticleProcessMaterial.EMISSION_SHAPE_BOX, Vector3(8, 3, 8), 0.0,
			Vector3(0, 0.4, 0), 0.15, Vector3(0, 0.08, 0),
			0.03, 0.1, 0.4, 0.8, 0.0, 0.0,
			Color(0.35, 0.3, 0.38, 0.55), Color(0.2, 0.18, 0.25, 0.08),
			true
		),
	}

	# Per-type enhancements
	for type_name in ["spores", "leaves", "paint_mote", "confetti", "smoke", "steam"]:
		var c: ParticleConfig = CONFIGS[type_name]
		c.hue_variation = 0.15
		c.lifetime_randomness = 0.3
		c.flatness = 0.2

	for type_name in ["mist", "wisp"]:
		var c: ParticleConfig = CONFIGS[type_name]
		c.lifetime_randomness = 0.4
		c.damping_min = 0.05
		c.damping_max = 0.15

	for type_name in ["sparkles", "gold_mote"]:
		var c: ParticleConfig = CONFIGS[type_name]
		c.lifetime_randomness = 0.5

	for type_name in ["dust", "light_dust", "film_grain"]:
		var c: ParticleConfig = CONFIGS[type_name]
		c.lifetime_randomness = 0.2


func _build_shared_curves() -> void:
	var fade = Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.1, 1.0))
	fade.add_point(Vector2(0.9, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	_fade_curve = CurveTexture.new()
	_fade_curve.curve = fade

	var alpha_fade = Curve.new()
	alpha_fade.add_point(Vector2(0.0, 0.0))
	alpha_fade.add_point(Vector2(0.15, 1.0))
	alpha_fade.add_point(Vector2(0.85, 1.0))
	alpha_fade.add_point(Vector2(1.0, 0.0))
	_alpha_fade_curve = CurveTexture.new()
	_alpha_fade_curve.curve = alpha_fade


func _build_material_cache() -> void:
	for type_name in CONFIGS:
		_material_cache[type_name] = _build_material(type_name)


func _build_material(type_name: String) -> ParticleProcessMaterial:
	var cfg: ParticleConfig = CONFIGS[type_name]
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = cfg.emission_shape
	if cfg.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX:
		mat.emission_box_extents = cfg.box_extents
	else:
		mat.emission_sphere_radius = cfg.sphere_radius
	mat.direction = cfg.direction
	mat.spread = cfg.spread
	mat.flatness = cfg.flatness
	mat.gravity = cfg.gravity
	mat.initial_velocity_min = cfg.vel_min
	mat.initial_velocity_max = cfg.vel_max
	mat.scale_min = cfg.scale_min
	mat.scale_max = cfg.scale_max
	mat.angular_velocity_min = cfg.ang_vel_min
	mat.angular_velocity_max = cfg.ang_vel_max
	mat.lifetime_randomness = cfg.lifetime_randomness
	mat.hue_variation_min = cfg.hue_variation
	mat.hue_variation_max = cfg.hue_variation * 0.5

	var grad = Gradient.new()
	grad.set_color(0, cfg.color_start)
	grad.set_color(1, cfg.color_end)
	var ramp = GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp

	mat.scale_curve = _fade_curve
	mat.alpha_curve = _alpha_fade_curve

	if cfg.turbulence:
		mat.turbulence_enabled = true
		mat.turbulence_noise_strength = 0.4
		mat.turbulence_noise_scale = 4.0
		mat.turbulence_noise_speed = Vector3(0.1, 0.15, 0.1)
		mat.turbulence_influence_min = 0.05
		mat.turbulence_influence_max = 0.25

	mat.damping_min = cfg.damping_min
	mat.damping_max = cfg.damping_max

	return mat


func clear_all_effects() -> void:
	for p in _active_particles:
		if is_instance_valid(p):
			p.emitting = false
			p.queue_free()
	_active_particles.clear()


func apply_mood_particles(parent: Node3D, mood: int, intensity: float = 1.0) -> void:
	clear_all_effects()
	if not GraphicsManager.particles_enabled:
		Log.debug("ParticleEffectsManager", "Particles disabled in GraphicsManager")
		return
	var effects: Array = MOOD_PARTICLES.get(mood, ["dust"])
	Log.debug("ParticleEffectsManager", "Spawning particles for mood: %s effects: %s" % [ExhibitMood.Mood.keys()[mood], effects])
	for effect in effects:
		_spawn_particles(parent, effect, intensity)


func _spawn_particles(parent: Node3D, type_name: String, intensity: float) -> Node3D:
	var cfg: ParticleConfig = CONFIGS.get(type_name)
	if cfg == null:
		push_warning("ParticleEffectsManager: unknown type '%s'" % type_name)
		return null

	var mat: ParticleProcessMaterial = _material_cache.get(type_name)
	if mat == null:
		push_warning("ParticleEffectsManager: no cached material for '%s'" % type_name)
		return null

	var use_gpu := not Platform.is_compatibility_renderer()
	var particles: Node3D = GPUParticles3D.new() if use_gpu else CPUParticles3D.new()
	particles.name = type_name.capitalize().replace(" ", "")
	particles.set("draw_pass_1", _particle_mesh)
	particles.set("amount", maxi(1, int(cfg.amount * intensity)))
	particles.set("lifetime", cfg.lifetime)
	particles.set("one_shot", false)
	particles.set("explosiveness", 0.0)
	particles.set("randomness", 0.5)
	particles.set("process_material", mat)

	if use_gpu:
		var gpu = particles as GPUParticles3D
		gpu.local_coords = true
		gpu.visibility_range_end = 150.0
		gpu.visibility_range_fade_mode = GPUParticles3D.VISIBILITY_RANGE_FADE_DISABLED

	particles.position = Vector3(0, 4, 0)

	particles.restart()
	particles.emitting = true

	parent.add_child(particles)
	_active_particles.append(particles)
	Log.debug("ParticleEffectsManager", "Spawned '%s' with %d particles at %s" % [type_name, particles.get("amount"), particles.global_position])
	return particles


func get_active_effects() -> Array:
	var effects = []
	for p in _active_particles:
		if is_instance_valid(p):
			effects.append({
				"name": p.name,
				"position": p.global_position,
				"emitting": p.emitting
			})
	return effects


func get_particle_count() -> int:
	return _active_particles.size()
