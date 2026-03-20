extends VBoxContainer
signal resume

enum ScaleMode { BILINEAR, FSR, NEAREST }
var post_processing_options: Array[String] = ["none", "crt", "soft", "vhs", "ps1"]

## Display options
@onready var scale_mode: OptionButton = %ScaleMode
@onready var fsr_quality: OptionButton = %FSRQuality
@onready var sharpness_scale: HSlider = %SharpnessScale
@onready var sharpness_scale_value: Label = %SharpnessScaleValue
@onready var render_scale: HSlider = %RenderScale
@onready var render_scale_value: Label = %RenderScaleValue
@onready var fullscreen: Button = %Fullscreen

## Resolution dropdown — built at runtime
var _resolution_option: OptionButton = null

## Light options
@onready var ambient_light: HSlider = %AmbientLight
@onready var ambient_light_value: Label = %AmbientLightValue
@onready var enable_ssil: CheckBox = %EnableSSIL
@onready var enable_ssao: CheckBox = %EnableSSAO

## Reflection options
@onready var reflection_quality: HSlider = %ReflectionQuality
@onready var reflection_quality_value: Label = %ReflectionQualityValue
@onready var enable_reflections: CheckBox = %EnableReflections

## Fog options
@onready var enable_fog: CheckBox = %EnableFog
@onready var enable_volumetric_fog: CheckBox = %EnableVolumetricFog

## FPS options
@onready var max_fps: HSlider = %MaxFPS
@onready var max_fps_value: Label = %MaxFPSValue
@onready var vsync: CheckBox = %VSync

## Render distance options
@onready var render_distance: HSlider = %RenderDistance
@onready var render_distance_value: Label = %RenderDistanceValue

## Post-processing options
@onready var post_processing_effect: OptionButton = %PostProcessingEffect
@onready var enable_glow: CheckBox = %EnableGlow

## Anti-Aliasing options
@onready var msaa_option: OptionButton = %MSAAOption
@onready var use_fxaa_check: CheckBox = %UseFXAACheck
@onready var use_taa_check: CheckBox = %UseTAACheck

## Texture Filtering
@onready var anisotropy_option: OptionButton = %AnisotropyOption

## Shadow quality
@onready var shadow_quality_option: OptionButton = %ShadowQualityOption

var _loaded_settings: bool = false

## ── SSR (Screen-Space Reflections) runtime nodes
var _ssr_roughness_check: CheckBox = null

## ── SDFGI runtime nodes
var _sdfgi_enabled_check: CheckBox = null
var _sdfgi_occlusion_check: CheckBox = null
var _sdfgi_sky_check: CheckBox = null
var _sdfgi_bounces_slider: HSlider = null
var _sdfgi_bounces_label: Label = null
var _sdfgi_cascades_option: OptionButton = null
var _sdfgi_cell_size_slider: HSlider = null
var _sdfgi_cell_size_label: Label = null
var _sdfgi_details_container: VBoxContainer = null

## ── FOV / LOD runtime nodes
var _fov_label: Label = null
var _lod_label: Label = null

## ── Brightness / contrast runtime nodes
var _brightness_label: Label = null
var _contrast_label: Label = null

## ── Reduce motion runtime node
var _reduce_motion_check: CheckBox = null

## ── Overall quality preset ────────────────────────────────────────────────────
## 0=Low  1=Medium  2=High  3=Ultra
const QUALITY_LABELS: Array[String] = ["Low", "Medium", "High", "Ultra"]
var _quality_level: int = 2   # default High
var _quality_btn: Button = null

## ── Tonemapping preset ────────────────────────────────────────────────────────
## Preset index drives both the mapper and sensible exposure/white defaults.
const TONEMAP_PRESETS: Array[Dictionary] = [
	{"label": "Linear",        "mode": 0, "exposure": 1.0,  "white": 1.0},
	{"label": "Reinhard",      "mode": 1, "exposure": 1.0,  "white": 4.0},
	{"label": "Filmic",        "mode": 2, "exposure": 1.0,  "white": 8.0},
	{"label": "Filmic Bright", "mode": 2, "exposure": 1.2,  "white": 6.0},
]
var _tonemap_preset_idx: int = 2   # default Filmic
var _tonemap_cycle_btn: Button = null

## ── SSAO quality preset ───────────────────────────────────────────────────────
const SSAO_PRESETS: Array[Dictionary] = [
	{"label": "Low",    "radius": 0.5,  "intensity": 1.0, "power": 1.5, "detail": 0.5, "sharpness": 0.7,  "horizon": 0.06, "light_affect": 0.0},
	{"label": "Medium", "radius": 1.0,  "intensity": 2.0, "power": 1.5, "detail": 1.0, "sharpness": 0.85, "horizon": 0.06, "light_affect": 0.0},
	{"label": "High",   "radius": 1.5,  "intensity": 3.0, "power": 1.5, "detail": 2.0, "sharpness": 0.98, "horizon": 0.08, "light_affect": 0.0},
	{"label": "Ultra",  "radius": 2.0,  "intensity": 4.0, "power": 1.5, "detail": 4.0, "sharpness": 0.98, "horizon": 0.10, "light_affect": 0.0},
]
var _ssao_preset_idx: int = 2   # default High
var _ssao_cycle_btn: Button = null


func _ready() -> void:
	UIEvents.fullscreen_toggled.connect(_on_fullscreen_toggled)

	# ── Hide the baked "Experimental: SDFGI" tscn node — it's non-functional.
	# Our _build_sdfgi_section() adds the proper working version instead.
	for child in find_children("*", "CheckBox", true, false):
		if child is CheckBox and "Experimental" in child.text:
			child.visible = false
			if child.get_parent():
				child.get_parent().visible = false
	# Also catch by exact label text in case it's a Label not a CheckBox
	for child in find_children("*", "Label", true, false):
		if child is Label and "Experimental" in child.text:
			child.visible = false

	# ── Overall quality preset row — injected before everything else ──────────
	_build_overall_quality_row()

	_build_ssr_section()
	_build_sdfgi_section()
	_build_camera_section()
	_build_tonemapping_section()
	_build_image_section()
	_build_resolution_dropdown()
	_style_all_option_buttons()
	_load_settings()
	_connect_new_signals()

	if scale_mode.selected == ScaleMode.BILINEAR:
		get_tree().set_group("fsr_options", "visible", false)
	else:
		render_scale.hide()


func _build_overall_quality_row() -> void:
	## Injects an "Overall Quality" cycle button at the very top of the settings,
	## above all other controls. Clicking it steps Low → Medium → High → Ultra
	## and applies sensible values to every tunable setting at once.
	var lcol := get_node_or_null("%LCol") as VBoxContainer
	var target: Control = lcol if lcol else self

	var sep := HSeparator.new()
	target.add_child(sep)
	target.move_child(sep, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	target.add_child(row)
	target.move_child(row, 0)

	var lbl := Label.new()
	lbl.text = "Overall Quality"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	_quality_btn = Button.new()
	_quality_btn.custom_minimum_size.x = 90
	_quality_btn.pressed.connect(_on_overall_quality_pressed)
	_update_quality_btn_label()
	row.add_child(_quality_btn)


func _update_quality_btn_label() -> void:
	if _quality_btn:
		_quality_btn.text = QUALITY_LABELS[_quality_level] + "  ▶"


func _on_overall_quality_pressed() -> void:
	_quality_level = (_quality_level + 1) % QUALITY_LABELS.size()
	_apply_overall_quality(_quality_level)
	_update_quality_btn_label()
	# Sync all other cycle buttons to match
	_ssao_preset_idx = _quality_level
	_tonemap_preset_idx = _quality_level
	_update_cycle_btn(_ssao_cycle_btn, SSAO_PRESETS, _ssao_preset_idx)
	_update_cycle_btn(_tonemap_cycle_btn, TONEMAP_PRESETS, _tonemap_preset_idx)


func _apply_overall_quality(level: int) -> void:
	## Applies a complete set of quality settings based on the chosen level.
	## level: 0=Low  1=Medium  2=High  3=Ultra
	var e: Environment = GraphicsManager.get_env()
	match level:
		0: # Low
			GraphicsManager.set_shadow_quality(0)
			GraphicsManager.set_msaa_3d(Viewport.MSAA_DISABLED)
			GraphicsManager.set_use_fxaa(true)
			GraphicsManager.set_use_taa(false)
			GraphicsManager.set_render_distance_multiplier(1.0)
			GraphicsManager.set_lod_bias(3.0)
			GraphicsManager.set_anisotropy_level(2)
			GraphicsManager.set_ssao_enabled(false)
			e.ssil_enabled = false
			e.ssr_enabled  = false
			e.glow_enabled = false
			e.volumetric_fog_enabled = false
			_apply_tonemap_preset(1)   # Reinhard — cheap
			_apply_ssao_preset(0)
		1: # Medium
			GraphicsManager.set_shadow_quality(1)
			GraphicsManager.set_msaa_3d(Viewport.MSAA_2X)
			GraphicsManager.set_use_fxaa(false)
			GraphicsManager.set_use_taa(false)
			GraphicsManager.set_render_distance_multiplier(2.0)
			GraphicsManager.set_lod_bias(1.5)
			GraphicsManager.set_anisotropy_level(4)
			GraphicsManager.set_ssao_enabled(true)
			e.ssil_enabled = false
			e.ssr_enabled  = false
			e.glow_enabled = true
			e.volumetric_fog_enabled = false
			_apply_tonemap_preset(1)   # Reinhard
			_apply_ssao_preset(1)
		2: # High
			GraphicsManager.set_shadow_quality(2)
			GraphicsManager.set_msaa_3d(Viewport.MSAA_4X)
			GraphicsManager.set_use_fxaa(false)
			GraphicsManager.set_use_taa(false)
			GraphicsManager.set_render_distance_multiplier(2.5)
			GraphicsManager.set_lod_bias(1.0)
			GraphicsManager.set_anisotropy_level(8)
			GraphicsManager.set_ssao_enabled(true)
			e.ssil_enabled = true
			e.ssr_enabled  = true
			e.glow_enabled = true
			e.volumetric_fog_enabled = false
			_apply_tonemap_preset(2)   # Filmic
			_apply_ssao_preset(2)
		3: # Ultra
			GraphicsManager.set_shadow_quality(3)
			GraphicsManager.set_msaa_3d(Viewport.MSAA_8X)
			GraphicsManager.set_use_fxaa(false)
			GraphicsManager.set_use_taa(false)   # TAA causes blurring — 8x MSAA is sufficient
			GraphicsManager.set_render_distance_multiplier(3.5)
			GraphicsManager.set_lod_bias(0.5)
			GraphicsManager.set_anisotropy_level(16)
			GraphicsManager.set_ssao_enabled(true)
			e.ssil_enabled = true
			e.ssr_enabled  = true
			e.glow_enabled = true
			e.volumetric_fog_enabled = true
			_apply_tonemap_preset(3)   # Filmic Bright
			_apply_ssao_preset(3)

	# Sync the tscn-bound controls to reflect new values
	shadow_quality_option.selected = GraphicsManager.shadow_quality
	msaa_option.selected           = GraphicsManager.msaa_3d
	use_fxaa_check.button_pressed  = GraphicsManager.use_fxaa
	use_taa_check.button_pressed   = GraphicsManager.use_taa
	render_distance.value          = GraphicsManager.render_distance_multiplier
	# anisotropy: level→index: 1→0, 2→1, 4→2, 8→3, 16→4 (log2 mapping)
	match GraphicsManager.anisotropy_level:
		1: anisotropy_option.selected = 0
		2: anisotropy_option.selected = 1
		4: anisotropy_option.selected = 2
		8: anisotropy_option.selected = 3
		16: anisotropy_option.selected = 4
		_: anisotropy_option.selected = 2  # Default to 4x
	enable_ssao.button_pressed     = e.ssao_enabled
	enable_ssil.button_pressed     = e.ssil_enabled
	enable_reflections.button_pressed = e.ssr_enabled
	enable_glow.button_pressed     = e.glow_enabled
	enable_volumetric_fog.button_pressed = e.volumetric_fog_enabled


func _style_option_button(btn: OptionButton) -> void:
	ThemeManager.style_option_button(btn)


func _style_all_option_buttons() -> void:
	_walk_and_style(self)


func _walk_and_style(node: Node) -> void:
	if node is OptionButton:
		_style_option_button(node as OptionButton)
	for child in node.get_children():
		_walk_and_style(child)


func _make_row(label_text: String, widget: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(widget)
	return row


func _make_slider_row(label_text: String, min_v: float, max_v: float, step_v: float, init_v: float,
		val_lbl: Label, val_fmt: String = "%.0f",
		on_changed: Callable = Callable()) -> HBoxContainer:
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = init_v
	slider.custom_minimum_size = Vector2(140, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.text = val_fmt % init_v
	val_lbl.custom_minimum_size = Vector2(40, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(v: float):
		val_lbl.text = val_fmt % v
		if on_changed.is_valid(): on_changed.call(v)
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(slider)
	row.add_child(val_lbl)
	return row


func _update_cycle_btn(btn: Button, presets: Array, idx: int) -> void:
	if btn:
		btn.text = presets[idx].label + "  ▶"


# =============================================================================
# SSR Section (Screen‑Space Reflections)
# =============================================================================
func _build_ssr_section() -> void:
	var ref_options := get_node_or_null("%ReflectionOptions") as VBoxContainer
	if not ref_options:
		return
	
	var e: Environment = GraphicsManager.get_env()
	var sep := HSeparator.new()
	ref_options.add_child(sep)

	# Fade-in slider
	var fade_in_lbl := Label.new()
	ref_options.add_child(_make_slider_row("Fade-in dist", 0.0, 3.0, 0.05, e.ssr_fade_in, fade_in_lbl, "%.2f", 
		func(v): e.ssr_fade_in = v))
	
	# Fade-out slider
	var fade_out_lbl := Label.new()
	ref_options.add_child(_make_slider_row("Fade-out dist", 0.0, 30.0, 0.5, e.ssr_fade_out, fade_out_lbl, "%.1f", 
		func(v): e.ssr_fade_out = v))

	# Roughness checkbox (only if the property exists)
	if "ssr_roughness" in e:
		_ssr_roughness_check = CheckBox.new()
		_ssr_roughness_check.text = "Roughness-aware SSR"
		_ssr_roughness_check.button_pressed = e.get("ssr_roughness")
		_ssr_roughness_check.toggled.connect(func(on): e.set("ssr_roughness", on))
		ref_options.add_child(_ssr_roughness_check)
	
	# Additional SSAO / Glow controls can be added here.


# =============================================================================
# Depth of Field Section
# =============================================================================
# =============================================================================
# Resolution Dropdown
# =============================================================================
func _build_sdfgi_section() -> void:
	## Adds an SDFGI block into the lighting column (%LCol).
	## Silently skipped on the Compatibility renderer (SDFGI not available).
	if Platform.is_compatibility_renderer():
		return

	var lcol := get_node_or_null("%LCol") as VBoxContainer
	if not lcol:
		return

	lcol.add_child(HSeparator.new())

	var header := Label.new()
	header.text = "GLOBAL ILLUMINATION (SDFGI)"
	header.add_theme_font_size_override("font_size", 11)
	lcol.add_child(header)

	# ── Master enable toggle ──────────────────────────────────────────────────
	_sdfgi_enabled_check = CheckBox.new()
	_sdfgi_enabled_check.text = "Enable SDFGI"
	_sdfgi_enabled_check.button_pressed = GraphicsManager.sdfgi_enabled
	_sdfgi_enabled_check.toggled.connect(_on_sdfgi_enabled_toggled)
	lcol.add_child(_sdfgi_enabled_check)

	# ── Detail controls (hidden when SDFGI is off) ────────────────────────────
	_sdfgi_details_container = VBoxContainer.new()
	_sdfgi_details_container.add_theme_constant_override("separation", 4)
	_sdfgi_details_container.visible = GraphicsManager.sdfgi_enabled
	lcol.add_child(_sdfgi_details_container)

	# Occlusion
	_sdfgi_occlusion_check = CheckBox.new()
	_sdfgi_occlusion_check.text = "Use Occlusion"
	_sdfgi_occlusion_check.button_pressed = GraphicsManager.sdfgi_use_occlusion
	_sdfgi_occlusion_check.toggled.connect(func(on): GraphicsManager.set_sdfgi_use_occlusion(on))
	_sdfgi_details_container.add_child(_sdfgi_occlusion_check)

	# Read sky light
	_sdfgi_sky_check = CheckBox.new()
	_sdfgi_sky_check.text = "Read Sky Light"
	_sdfgi_sky_check.button_pressed = GraphicsManager.sdfgi_read_sky_light
	_sdfgi_sky_check.toggled.connect(func(on): GraphicsManager.set_sdfgi_read_sky_light(on))
	_sdfgi_details_container.add_child(_sdfgi_sky_check)

	# Bounces slider
	_sdfgi_bounces_label = Label.new()
	_sdfgi_details_container.add_child(
		_make_slider_row("Bounces", 0, 4, 1, GraphicsManager.sdfgi_bounces,
			_sdfgi_bounces_label, "%.0f",
			func(v): GraphicsManager.set_sdfgi_bounces(int(v))))

	# Cascade count dropdown
	_sdfgi_cascades_option = OptionButton.new()
	_sdfgi_cascades_option.add_item("6 Cascades")
	_sdfgi_cascades_option.add_item("8 Cascades")
	_sdfgi_cascades_option.selected = 0 if GraphicsManager.sdfgi_cascade_count == 6 else 1
	_sdfgi_cascades_option.item_selected.connect(
		func(idx): GraphicsManager.set_sdfgi_cascade_count(6 if idx == 0 else 8))
	_sdfgi_details_container.add_child(_make_row("Cascades", _sdfgi_cascades_option))

	# Min cell size slider
	_sdfgi_cell_size_label = Label.new()
	_sdfgi_details_container.add_child(
		_make_slider_row("Min Cell Size", 0.05, 2.0, 0.05,
			GraphicsManager.sdfgi_min_cell_size,
			_sdfgi_cell_size_label, "%.2f",
			func(v): GraphicsManager.set_sdfgi_min_cell_size(v)))

	# Style the new option button
	if _sdfgi_cascades_option:
		ThemeManager.style_option_button(_sdfgi_cascades_option)


func _on_sdfgi_enabled_toggled(on: bool) -> void:
	GraphicsManager.set_sdfgi_enabled(on)
	if _sdfgi_details_container:
		_sdfgi_details_container.visible = on


func _build_camera_section() -> void:
	## FOV, DOF detail, motion blur, LOD bias — goes into %LCol (left column).
	var lcol := get_node_or_null("%LCol") as VBoxContainer
	if not lcol:
		return

	lcol.add_child(HSeparator.new())

	var header := Label.new()
	header.text = "CAMERA"
	header.add_theme_font_size_override("font_size", 11)
	lcol.add_child(header)

	# FOV slider
	_fov_label = Label.new()
	lcol.add_child(_make_slider_row(
		"Field of View", 50.0, 120.0, 1.0,
		GraphicsManager.camera_fov,
		_fov_label, "%.0f°",
		func(v): GraphicsManager.set_camera_fov(v)
	))

	# ── Depth of Field (proper working version with sliders) ─────────────────
	lcol.add_child(HSeparator.new())

	var dof_header := Label.new()
	dof_header.text = "DEPTH OF FIELD"
	dof_header.add_theme_font_size_override("font_size", 11)
	lcol.add_child(dof_header)

	var dof_check := CheckBox.new()
	dof_check.text = "Enable Depth of Field"
	dof_check.button_pressed = GraphicsManager.dof_enabled
	var dof_details := VBoxContainer.new()
	dof_details.add_theme_constant_override("separation", 4)
	dof_details.visible = GraphicsManager.dof_enabled
	dof_check.toggled.connect(func(on: bool):
		GraphicsManager.set_dof_enabled(on)
		dof_details.visible = on
	)
	lcol.add_child(dof_check)
	lcol.add_child(dof_details)

	var dof_amount_lbl := Label.new()
	dof_details.add_child(_make_slider_row(
		"  Blur Amount", 0.01, 1.0, 0.01,
		GraphicsManager.dof_blur_amount,
		dof_amount_lbl, "%.2f",
		func(v): GraphicsManager.set_dof_blur_amount(v)
	))

	var dof_dist_lbl := Label.new()
	dof_details.add_child(_make_slider_row(
		"  Focus Distance", 1.0, 50.0, 0.5,
		GraphicsManager.dof_focus_distance,
		dof_dist_lbl, "%.1f",
		func(v): GraphicsManager.set_dof_focus_distance(v)
	))

	var dof_range_lbl := Label.new()
	dof_details.add_child(_make_slider_row(
		"  Focus Range", 1.0, 30.0, 0.5,
		GraphicsManager.dof_focus_range,
		dof_range_lbl, "%.1f",
		func(v): GraphicsManager.set_dof_focus_range(v)
	))

	lcol.add_child(HSeparator.new())

	# LOD Bias
	_lod_label = Label.new()
	lcol.add_child(_make_slider_row(
		"LOD Bias", 0.1, 4.0, 0.1,
		GraphicsManager.lod_bias,
		_lod_label, "%.1f",
		func(v): GraphicsManager.set_lod_bias(v)
	))
	var lod_hint := Label.new()
	lod_hint.text = "Lower = more detail, higher = faster"
	lod_hint.add_theme_font_size_override("font_size", 11)
	lod_hint.set_meta("settings_role", "hint")
	lcol.add_child(lod_hint)

	# ── SSAO quality controls (right column) ─────────────────────────────────
	_build_ssao_quality_section()


func _build_ssao_quality_section() -> void:
	var rcol := get_node_or_null("%RCol") as VBoxContainer
	var target: VBoxContainer = rcol if rcol else self

	target.add_child(HSeparator.new())

	var header := Label.new()
	header.text = "SSAO QUALITY"
	header.add_theme_font_size_override("font_size", 11)
	target.add_child(header)

	# Cycle button — steps through SSAO_PRESETS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = "Preset"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	_ssao_cycle_btn = Button.new()
	_ssao_cycle_btn.custom_minimum_size.x = 110
	_ssao_cycle_btn.pressed.connect(_on_ssao_cycle_pressed)
	_update_cycle_btn(_ssao_cycle_btn, SSAO_PRESETS, _ssao_preset_idx)
	row.add_child(_ssao_cycle_btn)
	target.add_child(row)

	var hint := Label.new()
	hint.text = "Higher = better contact shadows, more GPU cost"
	hint.add_theme_font_size_override("font_size", 11)
	hint.set_meta("settings_role", "hint")
	target.add_child(hint)


func _on_ssao_cycle_pressed() -> void:
	_ssao_preset_idx = (_ssao_preset_idx + 1) % SSAO_PRESETS.size()
	_apply_ssao_preset(_ssao_preset_idx)
	_update_cycle_btn(_ssao_cycle_btn, SSAO_PRESETS, _ssao_preset_idx)


func _apply_ssao_preset(idx: int) -> void:
	_ssao_preset_idx = idx
	var p: Dictionary = SSAO_PRESETS[idx]
	var e: Environment = GraphicsManager.get_env()
	e.ssao_radius    = p.radius
	e.ssao_intensity = p.intensity
	e.ssao_power     = p.power
	e.ssao_detail    = p.detail
	if "ssao_sharpness"    in e: e.ssao_sharpness    = p.sharpness
	if "ssao_horizon"      in e: e.ssao_horizon      = p.horizon
	if "ssao_light_affect" in e: e.ssao_light_affect = p.light_affect


func _build_tonemapping_section() -> void:
	var rcol := get_node_or_null("%RCol") as VBoxContainer
	var target: VBoxContainer = rcol if rcol else self

	target.add_child(HSeparator.new())

	var header := Label.new()
	header.text = "TONE MAPPING"
	header.add_theme_font_size_override("font_size", 11)
	target.add_child(header)

	# Cycle button — steps through TONEMAP_PRESETS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = "Preset"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	_tonemap_cycle_btn = Button.new()
	_tonemap_cycle_btn.custom_minimum_size.x = 110
	_tonemap_cycle_btn.pressed.connect(_on_tonemap_cycle_pressed)
	_update_cycle_btn(_tonemap_cycle_btn, TONEMAP_PRESETS, _tonemap_preset_idx)
	row.add_child(_tonemap_cycle_btn)
	target.add_child(row)

	var hint := Label.new()
	hint.text = "Filmic gives natural film-like response"
	hint.add_theme_font_size_override("font_size", 11)
	hint.set_meta("settings_role", "hint")
	target.add_child(hint)


func _on_tonemap_cycle_pressed() -> void:
	_tonemap_preset_idx = (_tonemap_preset_idx + 1) % TONEMAP_PRESETS.size()
	_apply_tonemap_preset(_tonemap_preset_idx)
	_update_cycle_btn(_tonemap_cycle_btn, TONEMAP_PRESETS, _tonemap_preset_idx)


func _apply_tonemap_preset(idx: int) -> void:
	_tonemap_preset_idx = idx
	var p: Dictionary = TONEMAP_PRESETS[idx]
	GraphicsManager.set_tonemap_mode(p.mode)
	GraphicsManager.set_tonemap_exposure(p.exposure)
	GraphicsManager.set_tonemap_white(p.white)


func _build_image_section() -> void:
	## Brightness, contrast, reduce-motion, HUD position.
	var target: VBoxContainer = self
	var lcol := get_node_or_null("%LCol") as VBoxContainer
	if lcol:
		target = lcol

	target.add_child(HSeparator.new())

	var header := Label.new()
	header.text = "IMAGE & ACCESSIBILITY"
	header.add_theme_font_size_override("font_size", 11)
	target.add_child(header)

	# HUD position cycle
	var hud_row := HBoxContainer.new()
	hud_row.add_theme_constant_override("separation", 8)
	var hud_lbl := Label.new()
	hud_lbl.text = "Race HUD Position"
	hud_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_row.add_child(hud_lbl)
	var hud_btn := Button.new()
	hud_btn.custom_minimum_size.x = 130
	var hud_pos_idx: int = (SettingsManager.get_settings("hud") as Dictionary).get("race_hud_position", 0) \
		if SettingsManager.get_settings("hud") is Dictionary else 0
	const HUD_POS_LABELS: Array[String] = ["Top Left", "Top Right", "Bottom Left", "Bottom Right"]
	hud_btn.text = HUD_POS_LABELS[hud_pos_idx] + "  ▶"
	hud_btn.pressed.connect(func():
		var s: Dictionary = SettingsManager.get_settings("hud") if SettingsManager.get_settings("hud") is Dictionary else {}
		var cur: int = s.get("race_hud_position", 0)
		cur = (cur + 1) % HUD_POS_LABELS.size()
		s["race_hud_position"] = cur
		SettingsManager.save_settings("hud", s)
		hud_btn.text = HUD_POS_LABELS[cur] + "  ▶"
		var hud := get_tree().get_first_node_in_group("race_hud")
		if hud and hud.has_method("set_hud_position"):
			hud.set_hud_position(cur)
	)
	hud_row.add_child(hud_btn)
	target.add_child(hud_row)

	# Brightness
	_brightness_label = Label.new()
	target.add_child(_make_slider_row(
		"Brightness", -0.5, 0.5, 0.01,
		GraphicsManager.brightness,
		_brightness_label, "%+.2f",
		func(v): GraphicsManager.set_brightness(v)
	))

	# Contrast
	_contrast_label = Label.new()
	target.add_child(_make_slider_row(
		"Contrast", 0.5, 2.0, 0.05,
		GraphicsManager.contrast,
		_contrast_label, "%.2f",
		func(v): GraphicsManager.set_contrast(v)
	))

	# Reset button
	var reset_btn := Button.new()
	reset_btn.text = "Reset Image"
	reset_btn.pressed.connect(func():
		GraphicsManager.set_brightness(0.0)
		GraphicsManager.set_contrast(1.0)
		_load_image_settings()
	)
	target.add_child(reset_btn)

	target.add_child(HSeparator.new())

	# Reduce motion
	_reduce_motion_check = CheckBox.new()
	_reduce_motion_check.text = "Reduce Motion (disco / ambient cycling)"
	_reduce_motion_check.button_pressed = GraphicsManager.reduce_motion
	_reduce_motion_check.toggled.connect(func(on): GraphicsManager.set_reduce_motion(on))
	target.add_child(_reduce_motion_check)


func _load_image_settings() -> void:
	## Re-syncs the brightness/contrast sliders from GraphicsManager state.
	## Called after a reset.
	if not _brightness_label or not _contrast_label:
		return
	var b_row := _brightness_label.get_parent() as HBoxContainer
	var c_row := _contrast_label.get_parent() as HBoxContainer
	if b_row:
		for child in b_row.get_children():
			if child is HSlider:
				child.value = GraphicsManager.brightness
				break
	if c_row:
		for child in c_row.get_children():
			if child is HSlider:
				child.value = GraphicsManager.contrast
				break


func _build_resolution_dropdown() -> void:
	var fullscreen_parent := fullscreen.get_parent()
	_resolution_option = OptionButton.new()
	_resolution_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for res in GraphicsManager.RESOLUTION_PRESETS:
		var label = "Native" if res == Vector2i(-1, -1) else "%d × %d" % [res.x, res.y]
		_resolution_option.add_item(label)
	_resolution_option.item_selected.connect(func(idx):
		GraphicsManager.set_resolution(GraphicsManager.RESOLUTION_PRESETS[idx])
	)
	fullscreen_parent.add_child(_make_row("Resolution", _resolution_option))

func _connect_new_signals() -> void:
	enable_ssao.toggled.connect(_on_enable_ssao_toggled)
	enable_glow.toggled.connect(_on_enable_glow_toggled)
	enable_volumetric_fog.toggled.connect(_on_enable_volumetric_fog_toggled)


# =============================================================================
# Load / Save
# =============================================================================
func _load_settings() -> void:
	_loaded_settings = true
	var e = GraphicsManager.get_env()
	
	render_distance.value = GraphicsManager.render_distance_multiplier
	vsync.button_pressed = GraphicsManager.vsync_enabled
	fullscreen.button_pressed = GraphicsManager.fullscreen
	render_scale.value = GraphicsManager.render_scale
	scale_mode.selected = GraphicsManager.scale_mode
	fsr_quality.selected = GraphicsManager.fsr_quality
	sharpness_scale.value = GraphicsManager.fsr_sharpness
	# Safe selection for post_processing_effect
	var pp_index = post_processing_options.find(GraphicsManager.post_processing)
	if pp_index >= 0:
		post_processing_effect.selected = pp_index
	msaa_option.selected = GraphicsManager.msaa_3d
	use_fxaa_check.button_pressed = GraphicsManager.use_fxaa
	use_taa_check.button_pressed = GraphicsManager.use_taa
	# Convert anisotropy level (2,4,8,16) to option index 0..3
	anisotropy_option.selected = (GraphicsManager.anisotropy_level / 2) - 1
	shadow_quality_option.selected = GraphicsManager.shadow_quality
	ambient_light.value = e.ambient_light_energy
	enable_ssil.button_pressed = e.ssil_enabled
	enable_fog.button_pressed = e.fog_enabled
	enable_volumetric_fog.button_pressed = e.volumetric_fog_enabled
	enable_reflections.button_pressed = e.ssr_enabled
	# Initialize reflection quality slider and label from environment.
	if reflection_quality:
		reflection_quality.value = e.ssr_max_steps
	if reflection_quality_value:
		reflection_quality_value.text = "%d" % int(e.ssr_max_steps)
	enable_ssao.button_pressed = e.ssao_enabled
	enable_glow.button_pressed = e.glow_enabled
	
	if _ssr_roughness_check and "ssr_roughness" in e:
		_ssr_roughness_check.button_pressed = e.get("ssr_roughness")

	# SDFGI — only populated after _build_sdfgi_section runs (Forward+ only)
	if _sdfgi_enabled_check:
		_sdfgi_enabled_check.button_pressed = GraphicsManager.sdfgi_enabled
	if _sdfgi_details_container:
		_sdfgi_details_container.visible = GraphicsManager.sdfgi_enabled
	if _sdfgi_occlusion_check:
		_sdfgi_occlusion_check.button_pressed = GraphicsManager.sdfgi_use_occlusion
	if _sdfgi_sky_check:
		_sdfgi_sky_check.button_pressed = GraphicsManager.sdfgi_read_sky_light
	if _sdfgi_cascades_option:
		_sdfgi_cascades_option.selected = 0 if GraphicsManager.sdfgi_cascade_count == 6 else 1

	# Tonemapping — sync cycle button to current env state
	if _tonemap_cycle_btn:
		var e_mode: int = GraphicsManager.get_env().tonemap_mode
		for i in TONEMAP_PRESETS.size():
			if TONEMAP_PRESETS[i].mode == e_mode:
				_tonemap_preset_idx = i
				break
		_update_cycle_btn(_tonemap_cycle_btn, TONEMAP_PRESETS, _tonemap_preset_idx)

	# SSAO quality — sync cycle button label (preset idx starts at default High)
	if _ssao_cycle_btn:
		_update_cycle_btn(_ssao_cycle_btn, SSAO_PRESETS, _ssao_preset_idx)

	# Brightness / contrast
	_load_image_settings()

	# Reduce motion
	if _reduce_motion_check:
		_reduce_motion_check.button_pressed = GraphicsManager.reduce_motion

	_update_scaling()


func _on_resume_pressed() -> void:
	GraphicsManager.save_settings()
	resume.emit()


func _update_scaling() -> void:
	var mode: int = scale_mode.selected
	GraphicsManager.set_scale_mode(mode)
	
	# Show/hide FSR‑related controls
	var fsr_options_visible = (mode == ScaleMode.FSR)
	
	var fsr_quality_node = get_node_or_null("%FSRQuality")
	if fsr_quality_node:
		fsr_quality_node.visible = fsr_options_visible
	
	var sharpness_scale_node = get_node_or_null("%SharpnessScale")
	if sharpness_scale_node:
		sharpness_scale_node.visible = fsr_options_visible
	
	var sharpness_value_node = get_node_or_null("%SharpnessScaleValue")
	if sharpness_value_node:
		sharpness_value_node.visible = fsr_options_visible
	
	# Show/hide render scale slider (only in Bilinear mode)
	var render_scale_node = get_node_or_null("%RenderScale")
	if render_scale_node:
		render_scale_node.visible = (mode == ScaleMode.BILINEAR)
	
	var render_value_node = get_node_or_null("%RenderScaleValue")
	if render_value_node:
		render_value_node.visible = (mode == ScaleMode.BILINEAR)


# =============================================================================
# Signal Handlers
# =============================================================================
func _on_fullscreen_toggled(on: bool) -> void:
	fullscreen.button_pressed = on
	GraphicsManager.set_fullscreen(on)


func _on_scale_mode_item_selected(index: int) -> void:
	_update_scaling()


func _on_fsr_quality_item_selected(index: int) -> void:
	GraphicsManager.set_fsr_quality(index)


func _on_sharpness_scale_value_changed(value: float) -> void:
	sharpness_scale_value.text = "%.2f" % value
	GraphicsManager.set_fsr_sharpness(value)


func _on_render_scale_value_changed(value: float) -> void:
	render_scale_value.text = "%.2f" % value
	GraphicsManager.set_render_scale(value)


func _on_vsync_toggled(button_pressed: bool) -> void:
	GraphicsManager.set_vsync_enabled(button_pressed)


func _on_max_fps_value_changed(value: float) -> void:
	max_fps_value.text = "%d" % value
	GraphicsManager.set_fps_limit(value)


func _on_render_distance_value_changed(value: float) -> void:
	render_distance_value.text = "%.1f" % value
	GraphicsManager.set_render_distance_multiplier(value)


func _on_post_processing_effect_item_selected(index: int) -> void:
	GraphicsManager.set_post_processing(post_processing_options[index])


func _on_reflection_quality_value_changed(value: float) -> void:
	var steps := int(value)
	reflection_quality_value.text = "%d" % steps
	var e: Environment = GraphicsManager.get_env()
	e.ssr_max_steps = steps


func _on_msaa_option_item_selected(index: int) -> void:
	GraphicsManager.set_msaa_3d(index)


func _on_use_fxaa_check_toggled(button_pressed: bool) -> void:
	GraphicsManager.set_use_fxaa(button_pressed)


func _on_use_taa_check_toggled(button_pressed: bool) -> void:
	GraphicsManager.set_use_taa(button_pressed)


func _on_anisotropy_option_item_selected(index: int) -> void:
	# index 0 → 2, 1 → 4, 2 → 8, 3 → 16
	var level = (index + 1) * 2
	GraphicsManager.set_anisotropy_level(level)


func _on_shadow_quality_option_item_selected(index: int) -> void:
	GraphicsManager.set_shadow_quality(index)


func _on_ambient_light_value_changed(value: float) -> void:
	ambient_light_value.text = "%.2f" % value
	GraphicsManager.get_env().ambient_light_energy = value


func _on_enable_ssil_toggled(button_pressed: bool) -> void:
	GraphicsManager.get_env().ssil_enabled = button_pressed


func _on_enable_fog_toggled(button_pressed: bool) -> void:
	GraphicsManager.get_env().fog_enabled = button_pressed


func _on_enable_reflections_toggled(button_pressed: bool) -> void:
	GraphicsManager.get_env().ssr_enabled = button_pressed

func _on_enable_ssao_toggled(on: bool) -> void:
	GraphicsManager.set_ssao_enabled(on)


func _on_enable_glow_toggled(on: bool) -> void:
	GraphicsManager.set_glow_enabled(on)

func _on_enable_volumetric_fog_toggled(on: bool) -> void:
	GraphicsManager.set_volumetric_fog_enabled(on)
