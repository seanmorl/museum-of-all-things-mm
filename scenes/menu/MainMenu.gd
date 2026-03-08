extends Control

signal start
signal settings
signal start_multiplayer
signal start_dedicated_host

const _BTN_PATH := "MarginContainer/CenterContainer/VBoxContainer/PanelContainer/ButtonContainer/"
const _FONT_PATH := "res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf"

var _serif_font: FontFile = null
var _panel_style: StyleBoxFlat = null
var _dedicated_host_btn: Button = null


func _ready() -> void:
	_serif_font = load(_FONT_PATH) as FontFile
	_build_dedicated_host_button()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	if Platform.is_web():
		var q = get_node_or_null("%Quit")
		if q: q.visible = false
	call_deferred("_entrance_animation")


func _on_visibility_changed() -> void:
	if visible and is_inside_tree():
		var s := get_node_or_null(_BTN_PATH + "Start")
		if s:
			s.call_deferred("grab_focus")
			
		var vbox := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer") as Control
		if vbox:
			var tw := create_tween().set_parallel(true)
			tw.tween_property(vbox, "modulate:a", 1.0, 0.2)
			tw.tween_property(vbox, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ── Theme ─────────────────────────────────────────────────────────────────────

func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode

	var panel := get_node_or_null(
		"MarginContainer/CenterContainer/VBoxContainer/PanelContainer") as PanelContainer
	if panel:
		if not _panel_style:
			var orig := panel.get_theme_stylebox("panel") as StyleBoxFlat
			_panel_style = orig.duplicate() if orig else StyleBoxFlat.new()
			panel.add_theme_stylebox_override("panel", _panel_style)
		_panel_style.bg_color     = ThemeManager.bg_color
		_panel_style.border_color = ThemeManager.border_color
		for side in [0,1,2,3]:
			_panel_style.set("border_width_" + ["left","right","top","bottom"][side], 1)
		for corner in ["top_left","top_right","bottom_left","bottom_right"]:
			_panel_style.set("corner_radius_" + corner, 10)
		_panel_style.shadow_color  = Color(0, 0, 0, 0.35 if dark else 0.12)
		_panel_style.shadow_size   = 16
		_panel_style.shadow_offset = Vector2(0, 6)

	_style_label("MarginContainer/CenterContainer/VBoxContainer/Title",
		ThemeManager.text_color, 42)
	_style_label("MarginContainer/CenterContainer/VBoxContainer/Subtitle",
		ThemeManager.subtext_color, 13)

	var container := get_node_or_null(_BTN_PATH.trim_suffix("/"))
	if container:
		for child in container.get_children():
			if child is Button:
				_style_button(child)


func _style_label(path: String, color: Color, size: int) -> void:
	var lbl := get_node_or_null(path) as Label
	if not lbl:
		return
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	if _serif_font:
		lbl.add_theme_font_override("font", _serif_font)


func _style_button(btn: Button) -> void:
	var dark := ThemeManager.is_dark_mode
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 17)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		btn.add_theme_color_override(state, ThemeManager.text_color)
	btn.add_theme_color_override("font_disabled_color", ThemeManager.subtext_color)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0,0,0,0)
	sn.content_margin_left = 16; sn.content_margin_right  = 16
	sn.content_margin_top  =  9; sn.content_margin_bottom =  9
	btn.add_theme_stylebox_override("normal", sn)

	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(1,1,1,0.06) if dark else Color(ThemeManager.border_color, 0.5)
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		sh.set("corner_radius_" + corner, 5)
	sh.content_margin_left = 16; sh.content_margin_right  = 16
	sh.content_margin_top  =  9; sh.content_margin_bottom =  9
	btn.add_theme_stylebox_override("hover", sh)

	var sp := sh.duplicate() as StyleBoxFlat
	sp.bg_color = Color(1,1,1,0.12) if dark else Color(ThemeManager.border_color, 0.85)
	btn.add_theme_stylebox_override("pressed", sp)

	var sf := sh.duplicate() as StyleBoxFlat
	sf.border_color      = ThemeManager.text_color
	sf.border_width_left = 2
	btn.add_theme_stylebox_override("focus", sf)


# ── Animations ────────────────────────────────────────────────────────────────

func _entrance_animation() -> void:
	var vbox := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer") as Control
	if vbox:
		vbox.modulate.a  = 0.0
		vbox.position.y  = 14.0
		var ptw := create_tween().set_parallel(true)
		ptw.tween_property(vbox, "modulate:a",  1.0,   0.40).set_delay(0.10)
		ptw.tween_property(vbox, "position:y",  0.0,   0.40) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.10)

	var container := get_node_or_null(_BTN_PATH.trim_suffix("/"))
	if container:
		var delay := 0.22
		for child in container.get_children():
			if child is Button:
				child.modulate.a = 0.0
				var btw := create_tween()
				btw.tween_property(child, "modulate:a", 1.0, 0.28).set_delay(delay)
				delay += 0.06

	_start_fade_in()


func _start_fade_in() -> void:
	var col := Color(0.973, 0.976, 0.98)
	for n in ["FadeIn", "FadeInStage2"]:
		var cr := get_node_or_null(n)
		if cr:
			cr.color = col
			create_tween().tween_property(cr, "color", Color(col, 0.0), 0.85) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _animate_out(then: Callable) -> void:
	var vbox := get_node_or_null("MarginContainer/CenterContainer/VBoxContainer") as Control
	if vbox:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(vbox, "modulate:a", 0.0, 0.16)
		tw.tween_property(vbox, "position:y", 10.0, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(then)
	else:
		then.call()


# ── Dedicated host button ──────────────────────────────────────────────────────

func _build_dedicated_host_button() -> void:
	var container := get_node_or_null(_BTN_PATH.trim_suffix("/"))
	if not container:
		return
	_dedicated_host_btn = Button.new()
	_dedicated_host_btn.text = "Host Server"
	_dedicated_host_btn.name = "DedicatedHost"
	_dedicated_host_btn.pressed.connect(_on_dedicated_host_pressed)
	container.add_child(_dedicated_host_btn)
	var quit := container.get_node_or_null("Quit")
	if quit:
		container.move_child(_dedicated_host_btn, quit.get_index())


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_start_pressed() -> void:
	_animate_out(func(): start.emit())

func _on_settings_pressed() -> void:
	_animate_out(func(): settings.emit())

func _on_multiplayer_pressed() -> void:
	_animate_out(func(): start_multiplayer.emit())

func _on_dedicated_host_pressed() -> void:
	_animate_out(func(): start_dedicated_host.emit())

func _on_quit_button_pressed() -> void:
	_animate_out(func(): get_tree().quit())
