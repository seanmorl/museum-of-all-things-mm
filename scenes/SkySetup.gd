extends Node
## SkySetup — drop this anywhere in Museum.tscn (e.g. as a child of WorldEnvironment).
## On _ready() it automatically:
##   1. Creates the three sky gradient textures in memory (no files needed)
##   2. Creates the skybox shader material
##   3. Applies it to the Museum's WorldEnvironment sky
##   4. Adds a Sun DirectionalLight3D and Moon Node3D as siblings if not present
##   5. Starts animating time of day
##
## NO files to create, NO inspector steps, NO gradient textures to assign.
## Just add this node and it works.

@export_range(0.0, 24.0, 0.1) var time_of_day: float = 10.0
@export var animate: bool = true
@export var day_duration_seconds: float = 180.0

var _sun:  DirectionalLight3D = null
var _moon: Node3D = null
var _mat:  ShaderMaterial = null

const SKY_SHADER_CODE := """
shader_type sky;

uniform vec3 sun_dir  = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform sampler2D sun_zenith_gradient  : source_color, repeat_disable, filter_linear;
uniform sampler2D view_zenith_gradient : source_color, repeat_disable, filter_linear;
uniform sampler2D sun_view_gradient    : source_color, repeat_disable, filter_linear;
uniform float sun_radius   : hint_range(0.0, 1.0) = 0.05;
uniform float star_density : hint_range(0.0, 1.0) = 0.018;

float sphere_intersect(vec3 ray_dir, vec3 sphere_pos, float radius) {
	vec3 oc = -sphere_pos;
	float b = dot(oc, ray_dir);
	float c = dot(oc, oc) - radius * radius;
	float h = b * b - c;
	if (h < 0.0) return -1.0;
	return -b - sqrt(h);
}

float hash_stars(vec3 dir) {
	vec3 q = floor(dir * 160.0);
	float h = fract(sin(dot(q, vec3(127.1, 311.7, 74.7))) * 43758.5453);
	return h > (1.0 - star_density) ? pow(h, 5.0) : 0.0;
}

void sky() {
	vec3 view_dir = EYEDIR;
	float sun_view_dot    = dot(sun_dir, view_dir);
	float sun_zenith_dot  = sun_dir.y;
	float view_zenith_dot = view_dir.y;
	float sun_view_dot01   = (sun_view_dot   + 1.0) * 0.5;
	float sun_zenith_dot01 = (sun_zenith_dot + 1.0) * 0.5;

	vec2 uv = vec2(sun_zenith_dot01, 0.5);
	vec3 sky_col  = texture(sun_zenith_gradient,  uv).rgb;
	vec3 haze_col = texture(view_zenith_gradient, uv).rgb;
	vec3 bloom_col = texture(sun_view_gradient,   uv).rgb;

	float vz_mask = pow(clamp(1.0 - view_zenith_dot, 0.0, 1.0), 4.0);
	float sv_mask = pow(clamp(sun_view_dot, 0.0, 1.0), 4.0);
	vec3 sky_output = sky_col + vz_mask * haze_col + sv_mask * bloom_col;

	float sun_mask = step(1.0 - sun_radius * sun_radius, sun_view_dot);
	vec3 sun_output = vec3(1.0, 0.98, 0.92) * sun_mask;

	float moon_i = sphere_intersect(view_dir, moon_dir, 0.06);
	float moon_mask = moon_i > -1.0 ? 1.0 : 0.0;
	vec3 moon_n = normalize(view_dir * moon_i - moon_dir);
	float moon_ndotl = clamp(dot(moon_n, normalize(sun_dir - moon_dir)), 0.0, 1.0);
	vec3 moon_output = vec3(0.92, 0.93, 0.95) * moon_mask * (moon_ndotl * 0.8 + 0.2);

	float night = clamp(-sun_zenith_dot * 3.0, 0.0, 1.0);
	vec3 stars = vec3(hash_stars(normalize(view_dir)) * night * 1.2);

	float no_sun = clamp(1.0 - sun_mask * 10.0, 0.0, 1.0);
	COLOR = sky_output + sun_output + moon_output * no_sun + stars * no_sun;
}
"""


func _ready() -> void:
	var world_env := _find_world_environment()
	if not world_env:
		push_error("[SkySetup] No WorldEnvironment found in scene tree")
		return

	_build_sky(world_env)
	_ensure_sun_moon(world_env)
	_update_sun(time_of_day)
	print("[SkySetup] Sky shader applied successfully")


func _process(delta: float) -> void:
	if animate:
		time_of_day = fmod(time_of_day + delta * (24.0 / day_duration_seconds), 24.0)
		_update_sun(time_of_day)
	elif _mat:
		_push_directions()


func _find_world_environment() -> WorldEnvironment:
	# Walk up to root then search the whole tree
	var root := get_tree().root
	return _find_we(root)


func _find_we(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child in node.get_children():
		var result := _find_we(child)
		if result:
			return result
	return null


func _build_sky(we: WorldEnvironment) -> void:
	var env := we.environment
	if not env:
		env = Environment.new()
		we.environment = env

	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	env.sky = sky

	var shader := Shader.new()
	shader.code = SKY_SHADER_CODE

	_mat = ShaderMaterial.new()
	_mat.shader = shader
	sky.sky_material = _mat

	# Build gradient textures in memory — no files needed
	_mat.set_shader_parameter("sun_zenith_gradient",  _make_sun_zenith_gradient())
	_mat.set_shader_parameter("view_zenith_gradient", _make_view_zenith_gradient())
	_mat.set_shader_parameter("sun_view_gradient",    _make_sun_view_gradient())

	# Keep existing glow/ambient settings if they exist — just enable glow
	env.glow_enabled = true


func _ensure_sun_moon(we: WorldEnvironment) -> void:
	_sun = we.get_node_or_null("Sun") as DirectionalLight3D
	if not _sun:
		_sun = DirectionalLight3D.new()
		_sun.name = "Sun"
		_sun.light_energy = 1.2
		_sun.shadow_enabled = true
		we.add_child(_sun)

	_moon = we.get_node_or_null("Moon") as Node3D
	if not _moon:
		_moon = Node3D.new()
		_moon.name = "Moon"
		we.add_child(_moon)


func _update_sun(t: float) -> void:
	if not _sun: return
	var angle := (t / 24.0) * 360.0 - 90.0
	_sun.rotation_degrees.x  = angle
	if _moon:
		_moon.rotation_degrees.x = angle + 180.0
	_push_directions()


func _push_directions() -> void:
	if not _mat: return
	if _sun and is_inside_tree():
		_mat.set_shader_parameter("sun_dir",  _sun.global_transform.basis.z)
	if _moon and is_inside_tree():
		_mat.set_shader_parameter("moon_dir", _moon.global_transform.basis.z)


# ── Gradient builders — all colours defined in code, nothing to assign ────────

func _make_sun_zenith_gradient() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.00, 0.25, 0.46, 0.52, 0.65, 0.82, 1.00])
	g.colors  = PackedColorArray([
		Color(0.00, 0.00, 0.02),  # midnight
		Color(0.01, 0.02, 0.08),  # night
		Color(0.58, 0.32, 0.18),  # sunrise red
		Color(0.85, 0.65, 0.38),  # sunrise gold
		Color(0.42, 0.66, 0.94),  # morning blue
		Color(0.32, 0.56, 0.90),  # afternoon blue
		Color(0.26, 0.50, 0.86),  # noon deep blue
	])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


func _make_view_zenith_gradient() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.00, 0.30, 0.47, 0.54, 0.72, 1.00])
	g.colors  = PackedColorArray([
		Color(0.00, 0.00, 0.00, 0.0),
		Color(0.02, 0.03, 0.08, 0.3),
		Color(0.90, 0.50, 0.20, 0.8),
		Color(0.95, 0.75, 0.50, 0.6),
		Color(0.68, 0.80, 0.95, 0.4),
		Color(0.58, 0.72, 0.92, 0.2),
	])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


func _make_sun_view_gradient() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.00, 0.44, 0.50, 0.60, 0.82, 1.00])
	g.colors  = PackedColorArray([
		Color(0.00, 0.00, 0.00, 0.0),
		Color(0.40, 0.14, 0.04, 0.5),
		Color(0.90, 0.52, 0.18, 0.9),
		Color(0.98, 0.84, 0.52, 0.6),
		Color(0.95, 0.90, 0.72, 0.3),
		Color(0.90, 0.90, 0.88, 0.1),
	])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t
