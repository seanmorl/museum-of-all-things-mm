extends VBoxContainer

signal resume

enum ScaleMode { BILINEAR, FSR1, FSR2 }

var post_processing_options: Array[String] = ["none", "crt"]

# Display options
@onready var scale_mode: OptionButton = %ScaleMode
@onready var fsr_quality: OptionButton = %FSRQuality
@onready var sharpness_scale: HSlider = %SharpnessScale
@onready var sharpness_scale_value: Label = %SharpnessScaleValue
@onready var render_scale: HSlider = %RenderScale
@onready var render_scale_value: Label = %RenderScaleValue
@onready var fullscreen: Button = %Fullscreen

# Light options
@onready var ambient_light: HSlider = %AmbientLight
@onready var ambient_light_value: Label = %AmbientLightValue
@onready var enable_ssil: CheckBox = %EnableSSIL

# Reflection options
@onready var reflection_quality: HSlider = %ReflectionQuality
@onready var reflection_quality_value: Label = %ReflectionQualityValue
@onready var enable_reflections: CheckBox = %EnableReflections

# Fog options
@onready var enable_fog: CheckBox = %EnableFog

# FPS options
@onready var max_fps: HSlider = %MaxFPS
@onready var max_fps_value: Label = %MaxFPSValue
@onready var vsync: CheckBox = %VSync

# Render distance options
@onready var render_distance: HSlider = %RenderDistance
@onready var render_distance_value: Label = %RenderDistanceValue

# Post-processing options
@onready var post_processing_effect: OptionButton = %PostProcessingEffect

var _loaded_settings: bool = false

# ── SSR (Screen-Space Reflections) runtime nodes — built in _ready ────────────
var _ssr_section: VBoxContainer = null
var _ssr_enabled_check: CheckBox = null
var _ssr_steps_slider: HSlider = null
var _ssr_steps_label: Label = null
var _ssr_fade_in_slider: HSlider = null
var _ssr_fade_in_label: Label = null
var _ssr_fade_out_slider: HSlider = null
var _ssr_fade_out_label: Label = null
var _ssr_depth_tolerance_slider: HSlider = null
var _ssr_depth_tolerance_label: Label = null
var _ssr_roughness_check: CheckBox = null

func _ready() -> void:
	UIEvents.fullscreen_toggled.connect(_on_fullscreen_toggled)
	_build_ssr_section()
	_style_all_option_buttons()
	_load_settings()

	if scale_mode.selected == ScaleMode.BILINEAR:
		get_tree().set_group("fsr_options", "visible", false)
	else:
		render_scale.hide()

# =============================================================================
# DROPDOWN STYLING — consistent modern look across all OptionButtons
# =============================================================================

func _style_option_button(btn: OptionButton) -> void:
	## Applies a consistent flat/modern style to a single OptionButton.
	## Rounded corners, border, subtle shadow, readable font size.
	if not btn:
		return

	var normal := StyleBoxFlat.new()
	normal.bg_color         = Color(0.97, 0.97, 0.97, 1.0)
	normal.border_color     = Color(0.72, 0.72, 0.72, 1.0)
	for s in ["left","right","top","bottom"]:
		normal.set("border_width_" + s, 1)
	for c in ["top_left","top_right","bottom_left","bottom_right"]:
		normal.set("corner_radius_" + c, 5)
	normal.content_margin_left  = 10
	normal.content_margin_right = 28
	normal.content_margin_top   = 5
	normal.content_margin_bottom = 5

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color     = Color(0.92, 0.93, 0.98, 1.0)
	hover.border_color = Color(0.50, 0.55, 0.85, 1.0)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color     = Color(0.88, 0.90, 0.97, 1.0)
	pressed.border_color = Color(0.40, 0.45, 0.80, 1.0)

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.40, 0.45, 0.80, 1.0)
	for s in ["left","right","top","bottom"]:
		focus.set("border_width_" + s, 2)

	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus",   focus)
	btn.add_theme_font_size_override("font_size", 13)

	# Style the popup panel too
	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color     = Color(0.98, 0.98, 0.98, 1.0)
	popup_style.border_color = Color(0.70, 0.70, 0.70, 1.0)
	for s in ["left","right","top","bottom"]:
		popup_style.set("border_width_" + s, 1)
	for c in ["top_left","top_right","bottom_left","bottom_right"]:
		popup_style.set("corner_radius_" + c, 5)
	popup_style.shadow_color  = Color(0, 0, 0, 0.12)
	popup_style.shadow_size   = 8
	popup_style.shadow_offset = Vector2(0, 3)
	btn.get_popup().add_theme_stylebox_override("panel", popup_style)
	btn.get_popup().add_theme_font_size_override("font_size", 13)


func _style_all_option_buttons() -> void:
	## Walk the whole scene tree under this node and style every OptionButton.
	_walk_and_style(self)


func _walk_and_style(node: Node) -> void:
	if node is OptionButton:
		_style_option_button(node as OptionButton)
	for child in node.get_children():
		_walk_and_style(child)

# =============================================================================
# SSR (Screen-Space Reflections) SECTION — built at runtime
# =============================================================================

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


func _build_ssr_section() -> void:
	## Builds a comprehensive SSR control block and inserts it into RCol/ReflectionOptions.
	## All controls read from and write to the current Environment via GraphicsManager.get_env().
	var ref_options := get_node_or_null("%ReflectionOptions") as VBoxContainer
	if not ref_options:
		push_warning("GraphicsSettings: Could not find ReflectionOptions node for SSR section.")
		return

	var e: Environment = GraphicsManager.get_env()

	# ── Master enable (already in scene as %EnableReflections + %ReflectionQuality) ──
	# We add richer controls below the existing ones.

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	ref_options.add_child(sep)

	var heading := Label.new()
	heading.text = "SSR Fine Tuning"
	heading.add_theme_font_size_override("font_size", 12)
	heading.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1.0))
	ref_options.add_child(heading)

	# ── Max Steps (already exposed as ReflectionQuality — we keep it) ──

	# ── Fade-In Distance ──────────────────────────────────────────────────────
	_ssr_fade_in_label = Label.new()
	var fade_in_row := _make_slider_row(
		"Fade-in dist", 0.0, 3.0, 0.05, e.ssr_fade_in,
		_ssr_fade_in_label, "%.2f",
		func(v: float): GraphicsManager.get_env().ssr_fade_in = v
	)
	ref_options.add_child(fade_in_row)

	# ── Fade-Out Distance ─────────────────────────────────────────────────────
	_ssr_fade_out_label = Label.new()
	var fade_out_row := _make_slider_row(
		"Fade-out dist", 0.0, 30.0, 0.5, e.ssr_fade_out,
		_ssr_fade_out_label, "%.1f",
		func(v: float): GraphicsManager.get_env().ssr_fade_out = v
	)
	ref_options.add_child(fade_out_row)

	# ── Depth Tolerance ───────────────────────────────────────────────────────
	_ssr_depth_tolerance_label = Label.new()
	var depth_row := _make_slider_row(
		"Depth tolerance", 0.01, 1.0, 0.01, e.ssr_depth_tolerance,
		_ssr_depth_tolerance_label, "%.2f",
		func(v: float): GraphicsManager.get_env().ssr_depth_tolerance = v
	)
	ref_options.add_child(depth_row)

	# ── Roughness ─────────────────────────────────────────────────────────────
	_ssr_roughness_check = CheckBox.new()
	_ssr_roughness_check.text = "Roughness-aware SSR"
	_ssr_roughness_check.button_pressed = e.ssr_roughness
	_ssr_roughness_check.toggled.connect(func(on: bool):
		GraphicsManager.get_env().ssr_roughness = on
	)
	ref_options.add_child(_ssr_roughness_check)

	# ── SSAO Section ─────────────────────────────────────────────────────────
	var ssao_sep := HSeparator.new()
	ssao_sep.add_theme_constant_override("separation", 6)
	ref_options.add_child(ssao_sep)

	var ssao_heading := Label.new()
	ssao_heading.text = "SSAO (Ambient Occlusion)"
	ssao_heading.add_theme_font_size_override("font_size", 12)
	ssao_heading.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1.0))
	ref_options.add_child(ssao_heading)

	var ssao_check := CheckBox.new()
	ssao_check.text = "Enable SSAO"
	ssao_check.button_pressed = e.ssao_enabled
	ssao_check.toggled.connect(func(on: bool): GraphicsManager.get_env().ssao_enabled = on)
	ref_options.add_child(ssao_check)

	var ssao_radius_lbl := Label.new()
	var ssao_radius_row := _make_slider_row(
		"Radius", 0.1, 4.0, 0.1, e.ssao_radius,
		ssao_radius_lbl, "%.1f",
		func(v: float): GraphicsManager.get_env().ssao_radius = v
	)
	ref_options.add_child(ssao_radius_row)

	var ssao_intensity_lbl := Label.new()
	var ssao_intensity_row := _make_slider_row(
		"Intensity", 0.0, 4.0, 0.1, e.ssao_intensity,
		ssao_intensity_lbl, "%.1f",
		func(v: float): GraphicsManager.get_env().ssao_intensity = v
	)
	ref_options.add_child(ssao_intensity_row)

	var ssao_power_lbl := Label.new()
	var ssao_power_row := _make_slider_row(
		"Power", 0.5, 4.0, 0.1, e.ssao_power,
		ssao_power_lbl, "%.1f",
		func(v: float): GraphicsManager.get_env().ssao_power = v
	)
	ref_options.add_child(ssao_power_row)

	var ssao_detail_lbl := Label.new()
	var ssao_detail_row := _make_slider_row(
		"Detail", 0.0, 1.0, 0.05, e.ssao_detail,
		ssao_detail_lbl, "%.2f",
		func(v: float): GraphicsManager.get_env().ssao_detail = v
	)
	ref_options.add_child(ssao_detail_row)

	# ── SDFGI Section ─────────────────────────────────────────────────────────
	var sdfgi_sep := HSeparator.new()
	sdfgi_sep.add_theme_constant_override("separation", 6)
	ref_options.add_child(sdfgi_sep)

	var sdfgi_heading := Label.new()
	sdfgi_heading.text = "SDFGI (Global Illumination)"
	sdfgi_heading.add_theme_font_size_override("font_size", 12)
	sdfgi_heading.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1.0))
	ref_options.add_child(sdfgi_heading)

	var sdfgi_check := CheckBox.new()
	sdfgi_check.text = "Enable SDFGI"
	sdfgi_check.button_pressed = e.sdfgi_enabled
	sdfgi_check.toggled.connect(func(on: bool): GraphicsManager.get_env().sdfgi_enabled = on)
	ref_options.add_child(sdfgi_check)

	var sdfgi_hint := Label.new()
	sdfgi_hint.text = "High quality GI — significantly impacts performance on lower-end hardware."
	sdfgi_hint.add_theme_font_size_override("font_size", 10)
	sdfgi_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	sdfgi_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	ref_options.add_child(sdfgi_hint)

	var sdfgi_bounces_lbl := Label.new()
	var sdfgi_bounces_row := _make_slider_row(
		"Bounces", 1.0, 8.0, 1.0, float(e.sdfgi_bounces),
		sdfgi_bounces_lbl, "%.0f",
		func(v: float): GraphicsManager.get_env().sdfgi_bounces = int(v)
	)
	ref_options.add_child(sdfgi_bounces_row)

	# ── Glow Section ──────────────────────────────────────────────────────────
	var glow_sep := HSeparator.new()
	glow_sep.add_theme_constant_override("separation", 6)
	ref_options.add_child(glow_sep)

	var glow_heading := Label.new()
	glow_heading.text = "Glow"
	glow_heading.add_theme_font_size_override("font_size", 12)
	glow_heading.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1.0))
	ref_options.add_child(glow_heading)

	var glow_check := CheckBox.new()
	glow_check.text = "Enable Glow"
	glow_check.button_pressed = e.glow_enabled
	glow_check.toggled.connect(func(on: bool): GraphicsManager.get_env().glow_enabled = on)
	ref_options.add_child(glow_check)

	var glow_intensity_lbl := Label.new()
	var glow_intensity_row := _make_slider_row(
		"Intensity", 0.0, 2.0, 0.05, e.glow_intensity,
		glow_intensity_lbl, "%.2f",
		func(v: float): GraphicsManager.get_env().glow_intensity = v
	)
	ref_options.add_child(glow_intensity_row)

	var glow_bloom_lbl := Label.new()
	var glow_bloom_row := _make_slider_row(
		"Bloom threshold", 0.0, 4.0, 0.05, e.glow_bloom,
		glow_bloom_lbl, "%.2f",
		func(v: float): GraphicsManager.get_env().glow_bloom = v
	)
	ref_options.add_child(glow_bloom_row)

	# ── Tone Mapping ──────────────────────────────────────────────────────────
	var tm_sep := HSeparator.new()
	tm_sep.add_theme_constant_override("separation", 6)
	ref_options.add_child(tm_sep)

	var tm_heading := Label.new()
	tm_heading.text = "Tone Mapping"
	tm_heading.add_theme_font_size_override("font_size", 12)
	tm_heading.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1.0))
	ref_options.add_child(tm_heading)

	var tm_mode_btn := OptionButton.new()
	tm_mode_btn.add_item("Linear",     Environment.TONE_MAPPER_LINEAR)
	tm_mode_btn.add_item("Reinhard",   Environment.TONE_MAPPER_REINHARDT)
	tm_mode_btn.add_item("Filmic",     Environment.TONE_MAPPER_FILMIC)
	tm_mode_btn.add_item("ACES",       Environment.TONE_MAPPER_ACES)
	# Select the item whose id matches current tone_mapper
	for i in tm_mode_btn.item_count:
		if tm_mode_btn.get_item_id(i) == e.tonemap_mode:
			tm_mode_btn.selected = i
			break
	tm_mode_btn.item_selected.connect(func(idx: int):
		GraphicsManager.get_env().tonemap_mode = tm_mode_btn.get_item_id(idx)
	)
	_style_option_button(tm_mode_btn)
	var tm_row := _make_row("Tone mapper", tm_mode_btn)
	ref_options.add_child(tm_row)

	var tm_exposure_lbl := Label.new()
	var tm_exposure_row := _make_slider_row(
		"Exposure", 0.1, 4.0, 0.05, e.tonemap_exposure,
		tm_exposure_lbl, "%.2f",
		func(v: float): GraphicsManager.get_env().tonemap_exposure = v
	)
	ref_options.add_child(tm_exposure_row)

	var tm_white_lbl := Label.new()
	var tm_white_row := _make_slider_row(
		"White point", 0.1, 16.0, 0.1, e.tonemap_white,
		tm_white_lbl, "%.1f",
		func(v: float): GraphicsManager.get_env().tonemap_white = v
	)
	ref_options.add_child(tm_white_row)

	# Style any OptionButtons we just added
	_walk_and_style(ref_options)



func ui_cancel_pressed() -> void:
	if visible:
		call_deferred("_on_resume_pressed")

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_load_settings()
	elif _loaded_settings:
		GraphicsManager.save_settings()

func _load_settings() -> void:
	var e = GraphicsManager.get_env()
	_loaded_settings = true

	render_distance.value = GraphicsManager.render_distance_multiplier
	if GraphicsManager.limit_fps:
		max_fps.value = GraphicsManager.fps_limit
	else:
		max_fps.value = max_fps.min_value
	_update_fps_label()
	vsync.button_pressed = GraphicsManager.vsync_enabled
	fullscreen.button_pressed = GraphicsManager.fullscreen
	render_scale.value = GraphicsManager.render_scale
	scale_mode.selected = GraphicsManager.scale_mode
	fsr_quality.selected = GraphicsManager.fsr_quality
	sharpness_scale.value = GraphicsManager.fsr_sharpness
	reflection_quality.value = e.ssr_max_steps
	enable_reflections.button_pressed = e.ssr_enabled
	ambient_light.value = e.ambient_light_energy
	enable_ssil.button_pressed = e.ssil_enabled
	enable_fog.button_pressed = e.fog_enabled
	var post_processing = GraphicsManager.post_processing
	var idx = post_processing_options.find(post_processing)
	post_processing_effect.select(idx if idx >= 0 else 0)

	# Refresh SSR fine-tuning sliders if they exist (built in _ready via _build_ssr_section)
	if _ssr_fade_in_label:
		_ssr_fade_in_label.text = "%.2f" % e.ssr_fade_in
	if _ssr_fade_out_label:
		_ssr_fade_out_label.text = "%.1f" % e.ssr_fade_out
	if _ssr_depth_tolerance_label:
		_ssr_depth_tolerance_label.text = "%.2f" % e.ssr_depth_tolerance
	if _ssr_roughness_check:
		_ssr_roughness_check.button_pressed = e.ssr_roughness

	_update_scaling()

func _on_restore_pressed() -> void:
	GraphicsManager.restore_default_settings()
	_load_settings()

func _on_resume_pressed() -> void:
	GraphicsManager.save_settings()
	resume.emit()

func _on_reflection_quality_value_changed(value: float) -> void:
	GraphicsManager.get_env().ssr_max_steps = int(value)
	reflection_quality_value.text = str(int(value))

func _on_enable_reflections_toggled(toggled_on: bool) -> void:
	GraphicsManager.get_env().ssr_enabled = toggled_on

func _on_enable_ssil_toggled(toggled_on: bool) -> void:
	GraphicsManager.get_env().ssil_enabled = toggled_on

func _on_ambient_light_value_changed(value: float) -> void:
	GraphicsManager.get_env().ambient_light_energy = value
	ambient_light_value.text = "%3.2f" % value

func _on_max_fps_value_changed(value: float) -> void:
	var is_unlimited = value <= max_fps.min_value
	GraphicsManager.enable_fps_limit(not is_unlimited)
	if not is_unlimited:
		GraphicsManager.set_fps_limit(value)
	_update_fps_label()

func _update_fps_label() -> void:
	if max_fps.value <= max_fps.min_value:
		max_fps_value.text = "Unlimited"
	else:
		max_fps_value.text = str(int(max_fps.value))

func _on_vsync_toggled(toggled_on: bool) -> void:
	GraphicsManager.set_vsync_enabled(toggled_on)

func _on_enable_fog_toggled(toggled_on: bool) -> void:
	GraphicsManager.get_env().fog_enabled = toggled_on

func _on_fullscreen_toggled(toggled_on: bool) -> void:
	GraphicsManager.set_fullscreen(toggled_on)
	fullscreen.set_pressed_no_signal(toggled_on)

func _update_scaling() -> void:
	var selected_scale_mode: int = scale_mode.selected
	GraphicsManager.set_scale_mode(selected_scale_mode)

	# Show render scale if bilinear, FSR options otherwise
	render_scale.visible = (selected_scale_mode == ScaleMode.BILINEAR)
	get_tree().set_group("fsr_options", "visible", (selected_scale_mode != ScaleMode.BILINEAR))

	if selected_scale_mode == ScaleMode.BILINEAR:
		GraphicsManager.set_render_scale(render_scale.value)
		return

	# FSR
	if selected_scale_mode == ScaleMode.FSR1:  # FSR 1 has no "ultra performance"
		fsr_quality.set_item_disabled(0, false)
		fsr_quality.set_item_disabled(4, true)
	if selected_scale_mode == ScaleMode.FSR2:  # FSR 2 has no "ultra quality"
		fsr_quality.set_item_disabled(0, true)
		fsr_quality.set_item_disabled(4, false)

	GraphicsManager.set_fsr_quality(fsr_quality.selected)

	var current_scale = get_viewport().scaling_3d_scale
	render_scale.value = current_scale
	render_scale_value.text = "%.0f %%\n" % (current_scale * 100)

func _on_render_scale_value_changed(value: float) -> void:
	render_scale_value.text = "%d %%\n" % (value * 100)
	_update_scaling()

func _on_scale_mode_value_changed(value: int) -> void:
	match value:
		ScaleMode.FSR1:
			fsr_quality.select(0)
		ScaleMode.FSR2:
			fsr_quality.select(1)

	_update_scaling()

func _on_fsr_quality_item_selected(index: int) -> void:
	_update_scaling()

func _on_sharpness_scale_value_changed(value: float) -> void:
	GraphicsManager.set_fsr_sharpness(value)
	sharpness_scale_value.text = str(value)

func _on_post_processing_effect_item_selected(index: int) -> void:
	GraphicsManager.set_post_processing(post_processing_options[index])

func _on_render_distance_value_changed(value: float) -> void:
	render_distance_value.text = "%dm" % int(value * 30)
	GraphicsManager.set_render_distance_multiplier(value)
