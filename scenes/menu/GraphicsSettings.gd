extends VBoxContainer
signal resume

enum ScaleMode { BILINEAR, FSR1, FSR2, NEAREST }
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

## ── DOF runtime nodes
var _dof_enabled_check: CheckBox = null
var _dof_amount_slider: HSlider = null
var _dof_amount_label: Label = null
var _dof_distance_slider: HSlider = null
var _dof_distance_label: Label = null
var _dof_range_slider: HSlider = null
var _dof_range_label: Label = null


func _ready() -> void:
	UIEvents.fullscreen_toggled.connect(_on_fullscreen_toggled)
	_build_ssr_section()
	_build_dof_section()
	_build_resolution_dropdown()
	_style_all_option_buttons()
	_load_settings()
	_connect_new_signals()
	
	if scale_mode.selected == ScaleMode.BILINEAR:
		get_tree().set_group("fsr_options", "visible", false)
	else:
		render_scale.hide()


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
func _build_dof_section() -> void:
	var lcol := get_node_or_null("%LCol") as VBoxContainer
	if not lcol:
		return
	
	lcol.add_child(HSeparator.new())
	
	_dof_enabled_check = CheckBox.new()
	_dof_enabled_check.text = "Cinematic depth of field"
	_dof_enabled_check.button_pressed = GraphicsManager.dof_enabled
	_dof_enabled_check.toggled.connect(_on_dof_toggled)
	lcol.add_child(_dof_enabled_check)
	# Sliders are managed internally by GraphicsManager now – no extra UI rows needed.


func _on_dof_toggled(on: bool) -> void:
	GraphicsManager.set_dof_enabled(on)
	# Show/hide the slider rows based on the enabled state
	if _dof_amount_label and _dof_amount_label.get_parent() is HBoxContainer:
		_dof_amount_label.get_parent().visible = on
	if _dof_distance_label and _dof_distance_label.get_parent() is HBoxContainer:
		_dof_distance_label.get_parent().visible = on
	if _dof_range_label and _dof_range_label.get_parent() is HBoxContainer:
		_dof_range_label.get_parent().visible = on


# =============================================================================
# Resolution Dropdown
# =============================================================================
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
	
	_update_scaling()


func _on_resume_pressed() -> void:
	GraphicsManager.save_settings()
	resume.emit()


func _update_scaling() -> void:
	var mode: int = scale_mode.selected
	GraphicsManager.set_scale_mode(mode)
	
	# Show/hide FSR‑related controls
	var fsr_options_visible = (mode == ScaleMode.FSR1 or mode == ScaleMode.FSR2)
	
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
