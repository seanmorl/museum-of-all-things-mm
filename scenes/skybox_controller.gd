@tool
extends WorldEnvironment
## SkyboxController — attach to Museum.tscn's "WorldEnvironment" node.
## Rotates the Sun child node based on time_of_day and pushes sun/moon
## directions to the skybox.gdshader each frame.
##
## Required children of WorldEnvironment:
##   "Sun"  — DirectionalLight3D
##   "Moon" — Node3D

@export_range(0.0, 24.0, 0.1) var time_of_day: float = 10.0:
	set(v):
		time_of_day = v
		_update_sun_position()

@export var animate_day_cycle: bool = false
@export var day_duration_seconds: float = 120.0


func _ready() -> void:
	_update_sun_position()


func _process(delta: float) -> void:
	if animate_day_cycle:
		time_of_day = fmod(time_of_day + delta * (24.0 / day_duration_seconds), 24.0)
		_update_sun_position()
	_push_to_shader()


func _update_sun_position() -> void:
	var sun := get_node_or_null("Sun") as Node3D
	if not sun:
		return
	# 6am = sun at horizon rising, 12pm = overhead, 18pm = setting
	var angle := (time_of_day / 24.0) * 360.0 - 90.0
	sun.rotation_degrees.x = angle

	# Keep Moon opposite the Sun
	var moon := get_node_or_null("Moon") as Node3D
	if moon:
		moon.rotation_degrees.x = angle + 180.0


func _push_to_shader() -> void:
	var mat := _get_sky_mat()
	if not mat:
		return
	var sun := get_node_or_null("Sun") as Node3D
	if sun:
		mat.set_shader_parameter("sun_dir", sun.global_transform.basis.z)
	var moon := get_node_or_null("Moon") as Node3D
	if moon:
		mat.set_shader_parameter("moon_dir", moon.global_transform.basis.z)


func _get_sky_mat() -> ShaderMaterial:
	if not environment or not environment.sky:
		return null
	return environment.sky.sky_material as ShaderMaterial
