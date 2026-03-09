extends Node
signal change_post_processing(post_processing: String)
const _settings_ns = "graphics"
const _GROUP_MANAGED_LIGHT := &"managed_light"
const _GROUP_MANAGED_LIGHT_SKIP := &"managed_light_skip_direction_test"
const _GROUP_RENDER_DISTANCE := &"render_distance"

## Deprecated: use Constants.MANAGED_LIGHTS_* instead
const MANAGED_LIGHTS_MAX := Constants.MANAGED_LIGHTS_MAX
const MANAGED_LIGHTS_DIRECTION_THRESHOLD := Constants.MANAGED_LIGHTS_DIRECTION_THRESHOLD
const MANAGED_LIGHTS_FREQUENCY := Constants.MANAGED_LIGHTS_FREQUENCY

var _env: WorldEnvironment
var limit_fps: bool = false
var fps_limit: int = 60
var _default_settings_obj: Dictionary
var fullscreen: bool = false
var render_scale: float = 1.0
var scale_mode: int = 0
var fsr_quality: int = 5
var fsr_sharpness: float = 0.2
var post_processing: String = "none"
var render_distance_multiplier: float = 2.5
var vsync_enabled: bool = true
var msaa_3d: int = Viewport.MSAA_DISABLED
var use_fxaa: bool = false
var use_taa: bool = false
var anisotropy_level: int = 4
var light_timer: Timer
var _light_tweens: Dictionary = {}

func _exit_tree() -> void:
	if light_timer:
		light_timer.stop()
	for tween in _light_tweens.values():
		if tween.is_valid():
			tween.kill()
	_light_tweens.clear()

## ── Shadow quality ─────────────────────────────────────────────────────────────
## 0=Low(512) 1=Medium(1024) 2=High(2048) 3=Ultra(4096)
var shadow_quality: int = 2

## ── Depth of Field ─────────────────────────────────────────────────────────────
var dof_enabled: bool = false
var dof_blur_amount: float = 0.1
var dof_focus_distance: float = 10.0
var dof_focus_range: float = 10.0

## ── Resolution ────────────────────────────────────────────────────────────────
var resolution: Vector2i = Vector2i(-1, -1)
const RESOLUTION_PRESETS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(3840, 2160),
	Vector2i(2560, 1440),
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
	Vector2i(1024, 576),
	Vector2i(854, 480),
]

func init() -> void:
	_env = get_tree().get_nodes_in_group("Environment")[0]
	if not _env:
		Log.error("GraphicsManager", "could not load environment node")
		return

	_default_settings_obj = _create_settings_obj()
	var loaded_settings: Variant = SettingsManager.get_settings(_settings_ns)
	if loaded_settings:
		_apply_settings(loaded_settings, _default_settings_obj)

func set_fps_limit(value: float) -> void:
	fps_limit = int(value)
	if limit_fps:
		Engine.set_max_fps(fps_limit)

func set_fullscreen(_fullscreen: bool) -> void:
	fullscreen = _fullscreen
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func set_render_scale(scale: float) -> void:
	render_scale = scale
	get_viewport().scaling_3d_scale = scale

func set_scale_mode(mode: int) -> void:
	scale_mode = mode
	var vp = get_viewport()
	
	if mode == 3: # Nearest (Retro/Pixelated)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		# FIXED: Viewports use canvas_item_default_texture_filter in Godot 4
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	else:
		vp.scaling_3d_mode = mode as Viewport.Scaling3DMode
		# Default back to Linear for standard modes (FSR/Bilinear)
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		
	if mode == 2: # FSR2 has its own AA
		vp.msaa_3d = Viewport.MSAA_DISABLED
	else:
		vp.msaa_3d = msaa_3d as Viewport.MSAA

func set_msaa_3d(value: int) -> void:
	msaa_3d = value
	if scale_mode != 2:
		get_viewport().msaa_3d = value as Viewport.MSAA

func set_use_fxaa(enabled: bool) -> void:
	use_fxaa = enabled
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if enabled else Viewport.SCREEN_SPACE_AA_DISABLED

func set_use_taa(enabled: bool) -> void:
	use_taa = enabled
	get_viewport().use_taa = enabled

func set_anisotropy_level(level: int) -> void:
	anisotropy_level = level
	ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", level)

func set_fsr_quality(quality: int) -> void:
	fsr_quality = quality
	match quality:
		0: get_viewport().scaling_3d_scale = 1.0 / 1.3
		1: get_viewport().scaling_3d_scale = 1.0 / 1.5
		2: get_viewport().scaling_3d_scale = 1.0 / 1.7
		3: get_viewport().scaling_3d_scale = 1.0 / 2.0
		4: get_viewport().scaling_3d_scale = 1.0 / 3.0

func set_fsr_sharpness(sharpness: float) -> void:
	fsr_sharpness = sharpness
	get_viewport().fsr_sharpness = sharpness

func set_post_processing(_post_processing: String) -> void:
	post_processing = _post_processing
	change_post_processing.emit(post_processing)

func enable_fps_limit(enabled: bool) -> void:
	limit_fps = enabled
	if limit_fps:
		Engine.set_max_fps(fps_limit)

func set_render_distance_multiplier(value: float) -> void:
	var last_distance := render_distance_multiplier
	render_distance_multiplier = value
	if not is_equal_approx(last_distance, render_distance_multiplier):
		for node in get_tree().get_nodes_in_group(_GROUP_RENDER_DISTANCE):
			node.visibility_range_end *= render_distance_multiplier / last_distance

func set_vsync_enabled(_vsync_enabled: bool) -> void:
	vsync_enabled = _vsync_enabled
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)

func set_resolution(res: Vector2i) -> void:
	resolution = res
	if fullscreen:
		return
	if res == Vector2i(-1, -1):
		DisplayServer.window_set_size(DisplayServer.screen_get_size())
	else:
		DisplayServer.window_set_size(res)
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i((screen.x - res.x) / 2, (screen.y - res.y) / 2))

## ── Shadow quality ─────────────────────────────────────────────────────────────
func set_shadow_quality(quality: int) -> void:
	shadow_quality = quality
	var size: int
	match quality:
		0: size = 512
		1: size = 1024
		2: size = 2048
		3: size = 4096
		_: size = 2048
	RenderingServer.directional_shadow_atlas_set_size(size, true)

## ── Depth of Field ─────────────────────────────────────────────────────────────
func set_dof_enabled(enabled: bool) -> void:
	dof_enabled = enabled

func set_dof_blur_amount(amount: float) -> void:
	dof_blur_amount = amount

func set_dof_focus_distance(distance: float) -> void:
	dof_focus_distance = distance

func set_dof_focus_range(range_val: float) -> void:
	dof_focus_range = range_val

func set_ssao_enabled(enabled: bool) -> void:
	_env.environment.ssao_enabled = enabled

func set_ssil_enabled(enabled: bool) -> void:
	_env.environment.ssil_enabled = enabled


func set_ssr_enabled(enabled: bool) -> void:
	_env.environment.ssr_enabled = enabled

func set_glow_enabled(enabled: bool) -> void:
	_env.environment.glow_enabled = enabled

func set_volumetric_fog_enabled(enabled: bool) -> void:
	_env.environment.volumetric_fog_enabled = enabled

## ── Environment accessor ───────────────────────────────────────────────────────
func _on_node_added(node: Node) -> void:
	if not is_equal_approx(render_distance_multiplier, 1.0):
		if node.is_in_group(_GROUP_RENDER_DISTANCE):
			node.visibility_range_end *= render_distance_multiplier

func get_env() -> Environment:
	if not _env:
		init()
	return _env.environment

## ── Settings persistence ───────────────────────────────────────────────────────
func _apply_settings(s: Dictionary, default: Dictionary = {}) -> void:
	var e: Environment = _env.environment
	# All Environment fields that are saved/loaded directly
	for field in [
		"ssr_enabled", "ssr_max_steps", "ssr_fade_in", "ssr_fade_out",
		"ssr_depth_tolerance",
		"fog_enabled", "volumetric_fog_enabled", "ssil_enabled", "ambient_light_energy",
		"ssao_enabled", "ssao_radius", "ssao_intensity", "ssao_power", "ssao_detail",
		"glow_enabled", "glow_intensity", "glow_bloom",
		"tonemap_mode", "tonemap_exposure", "tonemap_white"]:
		if s.has(field):
			e[field] = s[field]
		elif default.has(field):
			e[field] = default[field]

	# ssr_roughness was removed in Godot 4.x — only set it if the property exists
	if "ssr_roughness" in e:
		if s.has("ssr_roughness"):
			e.ssr_roughness = s["ssr_roughness"]
		elif default.has("ssr_roughness"):
			e.ssr_roughness = default["ssr_roughness"]

	set_vsync_enabled(s.get("vsync_enabled", default.get("vsync_enabled", true)))
	set_fps_limit(s.get("fps_limit", default.get("fps_limit", 60)))
	enable_fps_limit(s.get("limit_fps", default.get("limit_fps", false)))
	set_fullscreen(s.get("fullscreen", default.get("fullscreen", false)))
	set_fsr_sharpness(s.get("fsr_sharpness", default.get("fsr_sharpness", 0.2)))
	set_post_processing(s.get("post_processing", default.get("post_processing", "none")))
	set_msaa_3d(s.get("msaa_3d", default.get("msaa_3d", Viewport.MSAA_DISABLED)))
	set_use_fxaa(s.get("use_fxaa", default.get("use_fxaa", false)))
	set_use_taa(s.get("use_taa", default.get("use_taa", false)))
	set_anisotropy_level(s.get("anisotropy_level", default.get("anisotropy_level", 4)))
	set_shadow_quality(s.get("shadow_quality", default.get("shadow_quality", 2)))
	set_render_distance_multiplier(s.get("render_distance_multiplier", default.get("render_distance_multiplier", 2.5)))
	set_resolution(s.get("resolution", default.get("resolution", Vector2i(-1, -1))))

	# DOF convenience vars (mirrored from env fields above, kept for UI use)
	dof_enabled = s.get("dof_enabled", default.get("dof_enabled", false))
	dof_blur_amount = s.get("dof_blur_amount", default.get("dof_blur_amount", 0.1))
	dof_focus_distance = s.get("dof_focus_distance", default.get("dof_focus_distance", 10.0))
	dof_focus_range = s.get("dof_focus_range", default.get("dof_focus_range", 10.0))

	var mode: int = s.get("scale_mode", default.get("scale_mode", 0))
	set_scale_mode(mode)
	if mode > 0:
		set_fsr_quality(s.get("fsr_quality", default.get("fsr_quality", 5)))
	else:
		set_render_scale(s.get("render_scale", default.get("render_scale", 1.0)))
	

func _create_settings_obj() -> Dictionary:
	var e: Environment = _env.environment
	return {
		# Display
		"render_scale": render_scale,
		"scale_mode": scale_mode,
		"fsr_quality": fsr_quality,
		"fsr_sharpness": fsr_sharpness,
		"fullscreen": fullscreen,
		"vsync_enabled": vsync_enabled,
		"fps_limit": fps_limit,
		"limit_fps": limit_fps,
		"render_distance_multiplier": render_distance_multiplier,
		"post_processing": post_processing,
		"resolution": resolution,
		# AA / filtering
		"msaa_3d": msaa_3d,
		"use_fxaa": use_fxaa,
		"use_taa": use_taa,
		"anisotropy_level": anisotropy_level,
		# Shadows
		"shadow_quality": shadow_quality,
		# Lighting
		"ambient_light_energy": e.ambient_light_energy,
		"ssil_enabled": e.ssil_enabled,
		"fog_enabled": e.fog_enabled,
		"volumetric_fog_enabled": e.volumetric_fog_enabled,
		# SSR
		"ssr_enabled": e.ssr_enabled,
		"ssr_max_steps": e.ssr_max_steps,
		"ssr_fade_in": e.ssr_fade_in,
		"ssr_fade_out": e.ssr_fade_out,
		"ssr_depth_tolerance": e.ssr_depth_tolerance,
		"ssr_roughness": e.get("ssr_roughness") if "ssr_roughness" in e else false,
		# SSAO
		"ssao_enabled": e.ssao_enabled,
		"ssao_radius": e.ssao_radius,
		"ssao_intensity": e.ssao_intensity,
		"ssao_power": e.ssao_power,
		"ssao_detail": e.ssao_detail,
		# Glow
		"glow_enabled": e.glow_enabled,
		"glow_intensity": e.glow_intensity,
		"glow_bloom": e.glow_bloom,
		# Tone mapping
		"tonemap_mode": e.tonemap_mode,
		"tonemap_exposure": e.tonemap_exposure,
		"tonemap_white": e.tonemap_white,
		# DOF - Uses local variables instead of Environment properties in Godot 4.x
		"dof_enabled": dof_enabled,
		"dof_blur_amount": dof_blur_amount,
		"dof_focus_distance": dof_focus_distance,
		"dof_focus_range": dof_focus_range,
	}

func restore_default_settings() -> void:
	_apply_settings(_default_settings_obj)

func save_settings() -> void:
	SettingsManager.save_settings(_settings_ns, _create_settings_obj())

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	if Platform.is_compatibility_renderer():
		light_timer = Timer.new()
		add_child(light_timer)
		light_timer.wait_time = MANAGED_LIGHTS_FREQUENCY
		light_timer.timeout.connect(_manage_lights)
		light_timer.start()

func _manage_lights() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var lights = get_tree().get_nodes_in_group(_GROUP_MANAGED_LIGHT)
	var light_data := []
	for light in lights:
		var p: Vector3 = light.global_position

		if light is SpotLight3D:
			p = p + (-light.global_transform.basis.z * (light.spot_range / 2.0))

		var v: Vector3 = p - camera.global_position

		if not light.is_in_group(_GROUP_MANAGED_LIGHT_SKIP):
			var camera_dot = v.normalized().dot(-camera.global_transform.basis.z)
			if camera_dot < MANAGED_LIGHTS_DIRECTION_THRESHOLD:
				_toggle_managed_light(light, false)
				continue

		var d := {
			'light': light,
			'distance': v.length(),
		}
		light_data.push_back(d)

	light_data.sort_custom(func(a, b): return a['distance'] < b['distance'])

	var enabled := 0
	for d in light_data:
		var light: Light3D = d['light']
		if enabled < MANAGED_LIGHTS_MAX:
			_toggle_managed_light(light, true)
			enabled += 1
		else:
			_toggle_managed_light(light, false)

	print_verbose("Enabled %s lights out of %s total" % [enabled, lights.size()])

func _toggle_managed_light(light: Light3D, enable: bool) -> void:
	if light.visible == enable:
		return
	var light_id: int = light.get_instance_id()
	if _light_tweens.has(light_id) and _light_tweens[light_id].is_valid():
		_light_tweens[light_id].kill()

	var tween := get_tree().create_tween().bind_node(light)
	_light_tweens[light_id] = tween
	var light_energy: float = light.light_energy

	if is_zero_approx(light_energy):
		light_energy = 3.0

	if enable:
		light.light_energy = 0.0
		light.visible = true

	tween.tween_property(light, "light_energy", light_energy if enable else 0.0, MANAGED_LIGHTS_FREQUENCY * 0.5)
	tween.tween_callback(func():
		_light_tweens.erase(light_id)
		if not is_instance_valid(light):
			return
		light.visible = enable
		light.light_energy = light_energy
	)
