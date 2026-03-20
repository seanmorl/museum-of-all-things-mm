extends CanvasLayer
## EventWarningBanner - Elegant, themed warning banner for environmental events


var _banner: PanelContainer = null
var _header_label: Label = null
var _main_label: Label = null
var _base_tween: Tween = null
var _pulse_tween: Tween = null


func _ready() -> void:
	layer = 100
	visible = false

	_build_ui()
	
	if ThemeManager:
		ThemeManager.dark_mode_changed.connect(_on_dark_mode_changed)
		ThemeManager.reading_font_changed.connect(_on_font_changed)
		_update_theme_styles()

	call_deferred("_connect_to_event_manager")


func _connect_to_event_manager() -> void:
	if EventManager:
		EventManager.event_warning.connect(_on_event_warning)


func _build_ui() -> void:
	_banner = PanelContainer.new()
	_banner.name = "BannerPill"
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = -120
	_banner.custom_minimum_size = Vector2(320, 0)
	add_child(_banner)

	# Standard StyleBoxFlat matching the rest of the game UI — no shader needed
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.content_margin_left   = 24
	style.content_margin_right  = 24
	style.content_margin_top    = 10
	style.content_margin_bottom = 10
	style.shadow_size   = 14
	style.shadow_offset = Vector2(0, 4)
	_banner.add_theme_stylebox_override("panel", style)

	var vbc := VBoxContainer.new()
	vbc.alignment = BoxContainer.ALIGNMENT_CENTER
	vbc.add_theme_constant_override("separation", 2)
	_banner.add_child(vbc)

	_header_label = Label.new()
	_header_label.text = "ENVIRONMENTAL EVENT"
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 10)
	vbc.add_child(_header_label)

	_main_label = Label.new()
	_main_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_label.add_theme_font_size_override("font_size", 26)
	vbc.add_child(_main_label)

	_on_font_changed(ThemeManager.get_reading_font() if ThemeManager else null)
	_update_theme_styles()


func _update_theme_styles() -> void:
	if not ThemeManager or not _banner: return
	var dark: bool  = ThemeManager.is_dark_mode
	var accent      := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	var style       := _banner.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.bg_color     = Color(ThemeManager.bg_color, 0.96)
		style.border_color = Color(accent, 0.55)
		style.shadow_color = Color(0, 0, 0, 0.30 if dark else 0.10)
	if _header_label:
		_header_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	if _main_label:
		_main_label.add_theme_color_override("font_color", ThemeManager.text_color)


func _on_dark_mode_changed(_enabled: bool) -> void:
	_update_theme_styles()


func _on_font_changed(font: Font) -> void:
	if not font: return
	_header_label.add_theme_font_override("font", font)
	_main_label.add_theme_font_override("font", font)


func _on_event_warning(event_type: int) -> void:
	var event_name = EventManager.get_event_name(event_type)
	_show_banner(event_name)


func _show_banner(text: String) -> void:
	_main_label.text = text.to_upper()
	self.visible = true
	
	if _base_tween: _base_tween.kill()
	_base_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	_banner.offset_top = -120
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.9, 0.9)
	_banner.pivot_offset = _banner.size / 2.0
	
	_base_tween.tween_property(_banner, "offset_top", 40, 0.6)
	_base_tween.tween_property(_banner, "modulate:a", 1.0, 0.4)
	_base_tween.tween_property(_banner, "scale", Vector2.ONE, 0.6)
	
	_start_pulse()
	
	await get_tree().create_timer(3.0).timeout
	_hide_banner()


func _start_pulse() -> void:
	if _pulse_tween: _pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_banner, "scale", Vector2(1.02, 1.02), 1.0).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(_banner, "scale", Vector2.ONE, 1.0).set_trans(Tween.TRANS_SINE)


func _hide_banner() -> void:
	if _pulse_tween: _pulse_tween.kill()
	if _base_tween: _base_tween.kill()
	
	_base_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_base_tween.tween_property(_banner, "offset_top", -120, 0.4)
	_base_tween.tween_property(_banner, "modulate:a", 0.0, 0.3)
	_base_tween.chain().tween_callback(func(): self.visible = false)


func test_banner() -> void:
	_show_banner("Gravity Shift")
