extends CanvasLayer
class_name HostMenu
## Dedicated host menu accessible via keybind during gameplay.
## Provides quick access to host controls without opening VoteHUD.
## "Swiss Army Knife" version with all host features.

signal host_menu_closed

var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _vbox: VBoxContainer = null

var _main: Node = null
var _visible: bool = false
var _menu_theme: Theme = null
var _serif_font: Font = null
var _animating: bool = false
var _backdrop: ColorRect = null

# Feature toggles (persist during session)
var _powerups_enabled: bool = true
var _paintings_enabled: bool = true
var _mounting_enabled: bool = true
var _speed_mode: bool = false
var _dark_mode_race: bool = false
var _disco_mode: bool = false
var _handicap_enabled: bool = false
var _race_commentary: bool = false

# Player speed modifiers
var _base_player_speed: float = 6.0
var _speed_multiplier: float = 1.0

# UI Sound Effects
const _UI_CRYSTAL_SOUND: AudioStream = preload("res://assets/sound/UI/UI Crystal 1.ogg")

func _ready() -> void:
	layer = 50  # Below pause menu (which is at layer 100)
	process_mode = Node.PROCESS_MODE_DISABLED  # Don't process when hidden
	visible = false  # Ensure completely hidden
	
	# Hide when race starts
	if has_node("/root/RaceManager"):
		var race_manager = get_node("/root/RaceManager")
		if race_manager.has_signal("race_started"):
			race_manager.race_started.connect(_on_race_started)

func _on_race_started(_target: String, _start: String) -> void:
	"""Hide host menu when race starts."""
	if _visible:
		hide_menu()
	set_process_input(false)
	set_process_unhandled_input(false)
	
	# Load the menu theme and serif font
	_menu_theme = load("res://assets/resources/menu_theme.tres")
	_serif_font = ThemeManager.get_reading_font()
	
	_create_ui_structure()
	add_to_group("mouse_overlay")
	_apply_theme()
	# Connect to dark mode changes for theme updates
	if not ThemeManager.dark_mode_changed.is_connected(_on_theme_changed):
		ThemeManager.dark_mode_changed.connect(_on_theme_changed)
	
	# Ensure we're completely inert when hidden
	visible = false
	_panel.visible = false
	_panel.modulate.a = 0.0
	_panel.position.y = 10.0

func _exit_tree() -> void:
	# Clean up signal connection
	if ThemeManager.dark_mode_changed.is_connected(_on_theme_changed):
		ThemeManager.dark_mode_changed.disconnect(_on_theme_changed)

func _on_theme_changed(_is_dark: bool = false) -> void:
	_apply_theme()
	if _visible:
		_rebuild_menu()  # Rebuild to update colors

func _animate_in() -> void:
	if _animating or not _panel:
		return
	_animating = true
	
	# Play open sound
	var player := AudioStreamPlayer.new()
	player.stream = _UI_CRYSTAL_SOUND
	player.volume_db = -5.0
	add_child(player)
	player.play()
	player.finished.connect(func(): player.queue_free())
	
	_panel.visible = true
	_backdrop.visible = true
	
	var tw := create_tween().set_parallel(true)
	# Backdrop fade in
	tw.tween_property(_backdrop, "color:a", 0.6, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Panel fade and slide
	tw.tween_property(_panel, "modulate:a", 1.0, 0.40).set_delay(0.10)
	tw.tween_property(_panel, "position:y", 0.0, 0.40) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.10)
	tw.tween_callback(func(): _animating = false)

func _animate_out(then: Callable) -> void:
	if _animating or not _panel:
		then.call()
		return
	_animating = true
	
	var tw := create_tween().set_parallel(true)
	# Backdrop fade out
	tw.tween_property(_backdrop, "color:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Panel fade and slide
	tw.tween_property(_panel, "modulate:a", 0.0, 0.16)
	tw.tween_property(_panel, "position:y", 10.0, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		_animating = false
		then.call()
	)

func _input(event: InputEvent) -> void:
	# Only process input when menu is visible
	if not _visible:
		return
	
	# ESC to close
	if event.is_action_pressed("ui_cancel"):
		hide_menu()
		get_viewport().set_input_as_handled()
	
	# Keep mouse visible while menu is open
	if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_backdrop_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hide_menu()

func _create_ui_structure() -> void:
	if _panel != null:
		return  # Already created
	
	# Create backdrop (semi-transparent dark overlay)
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0, 0, 0, 0.0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_clicked)
	add_child(_backdrop)
	
	# Create margin container
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	
	# Create center container for centered panel
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(center)
	
	# Create panel
	_panel = PanelContainer.new()
	_panel.name = "PausePanel"
	_panel.theme = _menu_theme
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(350, 400)  # Much narrower
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel.add_theme_constant_override("margin_left", 20)
	_panel.add_theme_constant_override("margin_top", 16)
	_panel.add_theme_constant_override("margin_right", 20)
	_panel.add_theme_constant_override("margin_bottom", 16)
	center.add_child(_panel)
	
	# Create content vbox
	var content := VBoxContainer.new()
	content.name = "PauseContent"
	content.add_theme_constant_override("separation", 8)
	_panel.add_child(content)
	
	# Create scroll container for content
	_scroll = ScrollContainer.new()
	_scroll.name = "ScrollContainer"
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(280, 300)  # Match narrower panel
	_scroll.add_theme_constant_override("margin_right", 8)
	content.add_child(_scroll)
	
	# Create inner margin container for content padding
	var inner_margin := MarginContainer.new()
	inner_margin.add_theme_constant_override("margin_left", 8)
	inner_margin.add_theme_constant_override("margin_right", 8)
	inner_margin.add_theme_constant_override("margin_top", 8)
	inner_margin.add_theme_constant_override("margin_bottom", 8)
	_scroll.add_child(inner_margin)
	
	# Create vbox inside inner margin
	_vbox = VBoxContainer.new()
	_vbox.name = "VBoxContainer"
	_vbox.add_theme_constant_override("separation", 8)
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.size_flags_vertical = Control.SIZE_FILL
	inner_margin.add_child(_vbox)
	
	# Set initial visibility
	_panel.visible = false
	_backdrop.visible = false

func init(main: Node) -> void:
	_main = main

func _apply_theme() -> void:
	if not _panel or not _menu_theme:
		return
	_panel.theme = _menu_theme

	# Mirror PauseMenu's panel style exactly
	var dark := ThemeManager.is_dark_mode
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if not style:
		style = StyleBoxFlat.new()
		_panel.add_theme_stylebox_override("panel", style)

	# Use ThemeManager's bg_color directly (it already has correct alpha)
	style.bg_color     = ThemeManager.bg_color
	style.border_color = ThemeManager.border_color
	for side in [0, 1, 2, 3]:
		style.set("border_width_" + ["left", "right", "top", "bottom"][side], 1)
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style.set("corner_radius_" + corner, 10)
	style.shadow_color  = Color(0, 0, 0, 0.35 if dark else 0.12)
	style.shadow_size   = 16
	style.shadow_offset = Vector2(0, 6)
	style.content_margin_left   = 30
	style.content_margin_right  = 30
	style.content_margin_top    = 24
	style.content_margin_bottom = 24
	
	# Force update the panel
	_panel.add_theme_stylebox_override("panel", style)

	# Re-style all live buttons and labels if menu is open
	if _visible and is_instance_valid(_vbox):
		_restyle_vbox(_vbox)

func _restyle_vbox(container: Control) -> void:
	for child in container.get_children():
		if child is CheckButton:
			_style_check_button(child)
		elif child is Button:
			_style_button(child)
		elif child is LineEdit:
			_style_line_edit(child)
		elif child is Label:
			child.add_theme_color_override("font_color", ThemeManager.text_color)
		elif child is ColorRect:
			child.color = ThemeManager.subtext_color
		elif child is HBoxContainer or child is VBoxContainer:
			_restyle_vbox(child)

func _get_text_color() -> Color:
	return ThemeManager.text_color

func _get_subtext_color() -> Color:
	return ThemeManager.subtext_color

func _get_accent_color() -> Color:
	return Color(0.024, 0.271, 0.678, 1)  # Theme blue (same for light/dark)

func toggle() -> void:
	if _visible:
		hide_menu()
	else:
		show_menu()

func show_menu() -> void:
	if _visible or _animating:
		return
	_create_ui_structure()  # Create UI on first show
	_apply_theme()  # Ensure theme is applied
	_visible = true
	visible = true  # Enable CanvasLayer
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_INHERIT  # Enable processing
	set_process_input(true)
	set_process_unhandled_input(true)
	set_process_unhandled_key_input(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_rebuild_menu()
	_animate_in()
	
	# Hide RaceHUD and RaceStatusHUD while menu is open
	if has_node("/root/RaceHUD"):
		get_node("/root/RaceHUD").visible = false
	if has_node("/root/RaceStatusHUD"):
		get_node("/root/RaceStatusHUD").visible = false

func hide_menu() -> void:
	if not _visible or _animating:
		return
	_animate_out(func():
		_visible = false
		_panel.visible = false
		_backdrop.visible = false
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_DISABLED  # Disable processing
		set_process_input(false)
		set_process_unhandled_input(false)
		set_process_unhandled_key_input(false)
		visible = false  # Disable CanvasLayer
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
		# Show RaceHUD again
		if has_node("/root/RaceHUD"):
			get_node("/root/RaceHUD").visible = true
		
		host_menu_closed.emit()
	)

func _rebuild_menu() -> void:
	# Clear existing
	for child in _vbox.get_children():
		child.queue_free()

	# Title with serif font
	var title := _create_label("Host Menu", 24)
	if _serif_font:
		title.add_theme_font_override("font", _serif_font)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_vbox.add_child(title)
	_vbox.add_child(_create_divider())

	# Player Management Section
	_vbox.add_child(_create_section_header("Player Management"))
	_vbox.add_child(_build_player_list())
	_vbox.add_child(_create_divider())

	# Race Control Section
	_vbox.add_child(_create_section_header("Race Control"))
	_vbox.add_child(_build_race_control())
	_vbox.add_child(_create_divider())

	# Game Modifiers Section
	_vbox.add_child(_create_section_header("Game Modifiers"))
	_vbox.add_child(_build_game_modifiers())
	_vbox.add_child(_create_divider())

	# Map Control Section
	_vbox.add_child(_create_section_header("Map Control"))
	_vbox.add_child(_build_map_control())
	_vbox.add_child(_create_divider())

	# Fun/Chaos Mode Section
	_vbox.add_child(_create_section_header("Fun & Chaos"))
	_vbox.add_child(_build_fun_chaos())
	_vbox.add_child(_create_divider())

	# Statistics Section
	_vbox.add_child(_create_section_header("Statistics"))
	_vbox.add_child(_build_statistics())
	_vbox.add_child(_create_divider())

	# Close button with extra spacing
	var spacer := Label.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_vbox.add_child(spacer)
	
	var close_btn := _create_button("Close (ESC)", hide_menu)
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(close_btn)

func _create_label(text: String, font_size: int = 17, color: Color = Color(0, 0, 0, 0)) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if color.a == 0:
		color = _get_text_color()
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	# Apply serif font to match PauseMenu
	if _serif_font:
		lbl.add_theme_font_override("font", _serif_font)
	return lbl

func _create_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.theme = _menu_theme
	btn.focus_mode = Control.FOCUS_CLICK
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	_style_button(btn)
	return btn

func _style_button(btn: Button) -> void:
	var dark := ThemeManager.is_dark_mode
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 17)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ThemeManager.text_color)
	btn.add_theme_color_override("font_disabled_color", ThemeManager.subtext_color)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0)
	sn.content_margin_left   = 16
	sn.content_margin_right  = 16
	sn.content_margin_top    = 10
	sn.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", sn)

	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(1, 1, 1, 0.06) if dark else Color(ThemeManager.border_color, 0.5)
	sh.set_corner_radius_all(5)
	sh.content_margin_left   = 16
	sh.content_margin_right  = 16
	sh.content_margin_top    = 10
	sh.content_margin_bottom = 10
	btn.add_theme_stylebox_override("hover", sh)

	var sp := sh.duplicate() as StyleBoxFlat
	sp.bg_color = Color(1, 1, 1, 0.12) if dark else Color(ThemeManager.border_color, 0.85)
	btn.add_theme_stylebox_override("pressed", sp)

	var sf := sh.duplicate() as StyleBoxFlat
	sf.border_color      = ThemeManager.text_color
	sf.border_width_left = 2
	btn.add_theme_stylebox_override("focus", sf)

	var sd := sn.duplicate() as StyleBoxFlat
	sd.bg_color = Color(1, 1, 1, 0.02) if dark else Color(0, 0, 0, 0.02)
	btn.add_theme_stylebox_override("disabled", sd)

func _style_line_edit(edit: LineEdit) -> void:
	var dark := ThemeManager.is_dark_mode
	if _serif_font:
		edit.add_theme_font_override("font", _serif_font)
	edit.add_theme_font_size_override("font_size", 15)
	edit.add_theme_color_override("font_color", ThemeManager.text_color)
	edit.add_theme_color_override("font_placeholder_color", ThemeManager.subtext_color)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0.03) if dark else Color(ThemeManager.border_color, 0.3)
	sn.border_color = ThemeManager.border_color
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(5)
	sn.content_margin_left   = 10
	sn.content_margin_right  = 10
	sn.content_margin_top    = 6
	sn.content_margin_bottom = 6
	edit.add_theme_stylebox_override("normal", sn)

	var sf := sn.duplicate() as StyleBoxFlat
	sf.border_color = ThemeManager.text_color
	sf.set_border_width_all(2)
	edit.add_theme_stylebox_override("focus", sf)

func _style_check_button(btn: CheckButton) -> void:
	var dark := ThemeManager.is_dark_mode

	# Font / text colours
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 17)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ThemeManager.text_color)
	btn.add_theme_color_override("font_disabled_color", ThemeManager.subtext_color)

	# Row backgrounds — transparent normal, subtle hover
	var s_clear := StyleBoxFlat.new()
	s_clear.bg_color = Color(0, 0, 0, 0)
	s_clear.content_margin_left   = 4
	s_clear.content_margin_right  = 4
	s_clear.content_margin_top    = 6
	s_clear.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", s_clear)
	btn.add_theme_stylebox_override("focus",  s_clear)
	btn.add_theme_stylebox_override("pressed", s_clear)

	var s_hover := s_clear.duplicate() as StyleBoxFlat
	s_hover.bg_color = Color(1, 1, 1, 0.06) if dark else Color(ThemeManager.border_color, 0.4)
	s_hover.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("hover", s_hover)
	btn.add_theme_stylebox_override("hover_pressed", s_hover)

	# Replace built-in CheckButton pill icons with hand-drawn ones so they are
	# always visible regardless of which theme .tres is loaded.
	# The icon slots Godot 4 uses are: "checked", "unchecked",
	# "checked_disabled", "unchecked_disabled", "radio_checked", "radio_unchecked"
	var accent  := Color(0.35, 0.55, 1.00) if dark else Color(0.024, 0.271, 0.678)
	var track_off := Color(0.40, 0.40, 0.45) if dark else Color(0.70, 0.70, 0.72)
	var thumb_col := Color(0.92, 0.92, 0.92) if dark else Color(1.0, 1.0, 1.0)

	btn.add_theme_icon_override("checked",          _make_toggle_icon(true,  accent,    thumb_col))
	btn.add_theme_icon_override("unchecked",         _make_toggle_icon(false, track_off, thumb_col))
	btn.add_theme_icon_override("checked_disabled",  _make_toggle_icon(true,  Color(accent, 0.4),    thumb_col))
	btn.add_theme_icon_override("unchecked_disabled",_make_toggle_icon(false, Color(track_off, 0.4), thumb_col))


func _make_toggle_icon(is_on: bool, track_col: Color, thumb_col: Color) -> ImageTexture:
	## Draws a 36×20 pill toggle icon into an ImageTexture.
	const W := 36
	const H := 20
	const R := 10   # pill corner radius = H/2
	const TR := 8   # thumb radius

	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Draw pill track (filled rounded rectangle)
	for y in H:
		for x in W:
			# Left cap circle
			var in_left  := (Vector2(x, y) - Vector2(R, R)).length() <= R
			# Right cap circle
			var in_right := (Vector2(x, y) - Vector2(W - R, R)).length() <= R
			# Middle rect
			var in_mid   := (x >= R and x <= W - R and y >= 0 and y < H)
			if in_left or in_right or in_mid:
				img.set_pixel(x, y, track_col)

	# Draw thumb circle (white dot)
	var cx: float = (W - R - 2) if is_on else (R + 2)
	var cy: float = R
	for y in H:
		for x in W:
			if (Vector2(x, y) - Vector2(cx, cy)).length() <= TR - 1:
				img.set_pixel(x, y, thumb_col)

	return ImageTexture.create_from_image(img)

func _create_toggle(text: String, default_value: bool, callback: Callable) -> HBoxContainer:
	var toggle := CheckButton.new()
	toggle.theme = _menu_theme
	toggle.button_pressed = default_value
	toggle.toggled.connect(callback)
	# Prevent toggle from capturing mouse
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_check_button(toggle)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", _get_text_color())
	lbl.add_theme_font_size_override("font_size", 17)
	# Apply serif font to match PauseMenu
	if _serif_font:
		lbl.add_theme_font_override("font", _serif_font)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Label doesn't block clicks
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.add_child(toggle)
	hbox.add_child(lbl)
	return hbox

func _create_section_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_color_override("font_color", _get_accent_color())
	lbl.add_theme_font_size_override("font_size", 12)
	if _serif_font:
		lbl.add_theme_font_override("font", _serif_font)
	lbl.add_theme_constant_override("outline_size", 0)
	return lbl

func _create_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.theme = _menu_theme
	sep.add_theme_constant_override("separation", 16)
	return sep

func _create_divider() -> ColorRect:
	# Thin 1px divider line like PauseMenu uses
	var divider := ColorRect.new()
	divider.color = _get_subtext_color()
	divider.custom_minimum_size = Vector2(0, 1)
	return divider

func _build_player_list() -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 5)

	# Player list
	var player_ids: Array = []
	if NetworkManager.is_multiplayer_active():
		player_ids = NetworkManager.get_player_list()

	for peer_id in player_ids:
		var player_name: String = NetworkManager.get_player_name(peer_id)
		var is_host = (peer_id == 1)
		var is_self = (peer_id == NetworkManager.get_unique_id())

		var player_row := HBoxContainer.new()
		player_row.add_theme_constant_override("separation", 5)

		var status_icon := Label.new()
		status_icon.text = "👑" if is_host else "👤"
		status_icon.add_theme_font_size_override("font_size", 16)
		player_row.add_child(status_icon)

		var name_lbl := Label.new()
		name_lbl.text = player_name + (" (You)" if is_self else "")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_color_override("font_color", ThemeManager.text_color)
		player_row.add_child(name_lbl)

		# Host controls (not for self or other hosts)
		if not is_self and not is_host and NetworkManager.is_server():
			var kick_btn := Button.new()
			kick_btn.text = "👢"
			kick_btn.tooltip_text = "Kick player"
			kick_btn.focus_mode = Control.FOCUS_CLICK
			kick_btn.custom_minimum_size.x = 40
			kick_btn.pressed.connect(_on_kick_pressed.bind(peer_id, player_name))
			player_row.add_child(kick_btn)

			var teleport_btn := Button.new()
			teleport_btn.text = "🔄"
			teleport_btn.tooltip_text = "Teleport to lobby"
			teleport_btn.focus_mode = Control.FOCUS_CLICK
			teleport_btn.custom_minimum_size.x = 40
			teleport_btn.pressed.connect(_on_teleport_player_pressed.bind(peer_id, player_name))
			player_row.add_child(teleport_btn)

		container.add_child(player_row)

	# Player count
	var count_lbl := _create_label("Players: %d" % player_ids.size(), 12, ThemeManager.subtext_color)
	container.add_child(count_lbl)

	return container

func _build_race_control() -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 5)

	# Force Start
	container.add_child(_create_button("▶ Force Start Race", _on_force_start_pressed))

	# Cancel Race
	container.add_child(_create_button("⏹ Cancel Race", _on_cancel_race_pressed))

	# Restart Race
	container.add_child(_create_button("🔄 Restart Race", _on_restart_race_pressed))

	# Skip Countdown
	container.add_child(_create_button("⏩ Skip Countdown", _on_skip_countdown_pressed))

	# Extend Vote Timer
	container.add_child(_create_button("⏱️ Extend Vote Timer (+30s)", _on_extend_vote_pressed))

	# Force Vote
	container.add_child(_create_button("✅ Force Vote End", _on_force_vote_pressed))

	# Set Custom Target
	var custom_target_row := HBoxContainer.new()
	custom_target_row.add_theme_constant_override("separation", 5)
	var target_input := LineEdit.new()
	target_input.placeholder_text = "Custom target article"
	target_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_input.name = "CustomTargetInput"
	_style_line_edit(target_input)
	custom_target_row.add_child(target_input)
	var set_target_btn := Button.new()
	set_target_btn.text = "🎯 Set Target"
	set_target_btn.pressed.connect(_on_set_custom_target_pressed.bind(target_input))
	_style_button(set_target_btn)
	custom_target_row.add_child(set_target_btn)
	container.add_child(custom_target_row)

	return container

func _build_game_modifiers() -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 5)

	# Powerups toggle
	container.add_child(_create_toggle("⚡ Powerups Enabled", _powerups_enabled, _on_powerups_toggled))

	# Paintings toggle
	container.add_child(_create_toggle("🖼️ Paintings Enabled", _paintings_enabled, _on_paintings_toggled))

	# Mounting toggle
	container.add_child(_create_toggle("🐎 Mounting Enabled", _mounting_enabled, _on_mounting_toggled))

	# Speed mode
	container.add_child(_create_toggle("⚡ Speed Mode (2x)", _speed_mode, _on_speed_mode_toggled))

	# Dark mode race
	container.add_child(_create_toggle("🌙 Dark Mode Race", _dark_mode_race, _on_dark_mode_race_toggled))

	# Race commentary
	container.add_child(_create_toggle("🎙️ Race Commentary", _race_commentary, _on_race_commentary_toggled))

	# Handicap system
	container.add_child(_create_toggle("⚖️ Handicap System", _handicap_enabled, _on_handicap_toggled))

	return container

func _build_map_control() -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 5)

	# Force room regeneration
	container.add_child(_create_button("🔨 Regenerate Current Room", _on_regenerate_room_pressed))

	# Set custom start
	var custom_start_row := HBoxContainer.new()
	custom_start_row.add_theme_constant_override("separation", 5)
	var start_input := LineEdit.new()
	start_input.placeholder_text = "Custom start article"
	start_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_input.name = "CustomStartInput"
	_style_line_edit(start_input)
	custom_start_row.add_child(start_input)
	var set_start_btn := Button.new()
	set_start_btn.text = "🚪 Set Start"
	set_start_btn.pressed.connect(_on_set_custom_start_pressed.bind(start_input))
	_style_button(set_start_btn)
	custom_start_row.add_child(set_start_btn)
	container.add_child(custom_start_row)

	# Teleport all to lobby
	container.add_child(_create_button("🔄 Teleport All to Lobby", _on_teleport_all_pressed))

	# Force follow host
	container.add_child(_create_button("👥 Force Follow Host", _on_force_follow_pressed))

	return container

func _build_fun_chaos() -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 5)

	# Disco mode
	container.add_child(_create_toggle("🪩 Disco Mode", _disco_mode, _on_disco_mode_toggled))

	# Random powerup drop
	container.add_child(_create_button("🎲 Random Powerup Drop", _on_random_powerup_pressed))

	# Tiny players
	container.add_child(_create_button("🐜 Tiny Players", _on_tiny_players_pressed))

	# Giant players
	container.add_child(_create_button("🦕 Giant Players", _on_giant_players_pressed))

	# Low gravity
	container.add_child(_create_button("🌙 Low Gravity", _on_low_gravity_pressed))

	return container

func _build_statistics() -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 5)

	# Show race stats
	container.add_child(_create_button("📊 Show Race Stats", _on_show_race_stats_pressed))

	# View player paths
	container.add_child(_create_button("🗺️ View Player Paths", _on_view_player_paths_pressed))

	# Room generation info
	container.add_child(_create_button("🏠 Room Generation Info", _on_room_info_pressed))

	# Network quality
	container.add_child(_create_button("📶 Network Quality", _on_network_quality_pressed))

	return container

# === Event Handlers ===

func _on_kick_pressed(peer_id: int, player_name: String) -> void:
	if not NetworkManager.is_server():
		return
	_kick_player.rpc_id(1, peer_id)
	_rebuild_menu()
	_show_host_message("👢 Kicked %s" % player_name)

func _on_teleport_player_pressed(peer_id: int, player_name: String) -> void:
	if not NetworkManager.is_server():
		return
	_teleport_player_to_lobby.rpc_id(peer_id)
	_show_host_message("🔄 Teleported %s to lobby" % player_name)
	_rebuild_menu()

func _on_force_start_pressed() -> void:
	if not NetworkManager.is_server():
		return
	if _main and _main.has_method("_on_start_race_pressed"):
		_main._on_start_race_pressed()
	hide_menu()
	_show_host_message("▶ Race forced to start!")

func _on_cancel_race_pressed() -> void:
	if not NetworkManager.is_server():
		return
	if RaceManager.has_method("cancel_race"):
		RaceManager.cancel_race()
	hide_menu()
	_show_host_message("⏹ Race cancelled")

func _on_restart_race_pressed() -> void:
	if not NetworkManager.is_server():
		return
	if RaceManager.has_method("cancel_race"):
		RaceManager.cancel_race()
	# Small delay then start vote
	await get_tree().create_timer(0.5).timeout
	if _main and _main.has_method("_on_start_race_pressed"):
		_main._on_start_race_pressed()
	hide_menu()
	_show_host_message("🔄 Race restarted")

func _on_skip_countdown_pressed() -> void:
	if not NetworkManager.is_server():
		return
	if RaceManager.has_method("skip_countdown"):
		RaceManager.skip_countdown()
	hide_menu()
	_show_host_message("⏩ Countdown skipped!")

func _on_extend_vote_pressed() -> void:
	if not NetworkManager.is_server():
		return
	if RaceManager.has_method("extend_vote_timer"):
		RaceManager.extend_vote_timer(30)
	hide_menu()
	_show_host_message("⏱️ Vote timer extended by 30s")

func _on_force_vote_pressed() -> void:
	if not NetworkManager.is_server():
		return
	if RaceManager.has_method("force_vote_end"):
		RaceManager.force_vote_end()
	hide_menu()
	_show_host_message("✅ Vote ended early")

func _on_set_custom_target_pressed(input: LineEdit) -> void:
	if not NetworkManager.is_server():
		return
	var target = input.text.strip_edges()
	if target != "":
		if RaceManager.has_method("set_custom_target"):
			RaceManager.set_custom_target(target)
			_show_host_message("🎯 Custom target set: %s" % target)
			input.text = ""
	hide_menu()

func _on_powerups_toggled(enabled: bool) -> void:
	_powerups_enabled = enabled
	_show_host_message("⚡ Powerups %s" % ("enabled" if enabled else "disabled"))

func _on_paintings_toggled(enabled: bool) -> void:
	_paintings_enabled = enabled
	_show_host_message("🖼️ Paintings %s" % ("enabled" if enabled else "disabled"))

func _on_mounting_toggled(enabled: bool) -> void:
	_mounting_enabled = enabled
	_show_host_message("🐎 Mounting %s" % ("enabled" if enabled else "disabled"))

func _on_speed_mode_toggled(enabled: bool) -> void:
	_speed_mode = enabled
	_speed_multiplier = 2.0 if enabled else 1.0
	_apply_speed_to_all_players()
	_show_host_message("⚡ Speed mode %s" % ("enabled (2x)" if enabled else "disabled"))

func _on_dark_mode_race_toggled(enabled: bool) -> void:
	_dark_mode_race = enabled
	_apply_dark_mode()
	_show_host_message("🌙 Dark mode race %s" % ("enabled" if enabled else "disabled"))

func _on_race_commentary_toggled(enabled: bool) -> void:
	_race_commentary = enabled
	_show_host_message("🎙️ Race commentary %s" % ("enabled" if enabled else "disabled"))

func _on_handicap_toggled(enabled: bool) -> void:
	_handicap_enabled = enabled
	_apply_handicap()
	_show_host_message("⚖️ Handicap system %s" % ("enabled" if enabled else "disabled"))

func _on_disco_mode_toggled(enabled: bool) -> void:
	_disco_mode = enabled
	if ThemeManager.has_method("set_disco_mode"):
		ThemeManager.set_disco_mode(enabled)
	_show_host_message("🪩 Disco mode %s" % ("enabled" if enabled else "disabled"))

func _on_random_powerup_pressed() -> void:
	if not NetworkManager.is_server():
		return
	# Spawn random powerup at random player
	var player_ids = NetworkManager.get_player_list()
	if player_ids.size() > 0:
		var random_peer = player_ids[randi() % player_ids.size()]
		_spawn_powerup_at_player.rpc(random_peer)
		_show_host_message("🎲 Random powerup dropped!")
	hide_menu()

func _on_tiny_players_pressed() -> void:
	if not NetworkManager.is_server():
		_show_host_message("⚠️ Only host can change player size!")
		return
	_set_player_scale.rpc(0.5)
	_show_host_message("🐜 Players are now TINY!")
	hide_menu()

func _on_giant_players_pressed() -> void:
	if not NetworkManager.is_server():
		_show_host_message("⚠️ Only host can change player size!")
		return
	_set_player_scale.rpc(2.0)
	_show_host_message("🦕 Players are now GIANTS!")
	hide_menu()

func _on_low_gravity_pressed() -> void:
	if not NetworkManager.is_server():
		_show_host_message("⚠️ Only host can change gravity!")
		return
	_set_gravity.rpc(3.0)  # Moon-like gravity
	_show_host_message("🌙 Low gravity enabled!")
	hide_menu()

func _on_show_race_stats_pressed() -> void:
	if RaceManager.has_method("get_race_stats"):
		var stats = RaceManager.get_race_stats()
		_show_host_message("📊 Race Time: %.1fs | Players: %d" % [stats.get("time", 0), stats.get("players", 0)])
	hide_menu()

func _on_view_player_paths_pressed() -> void:
	_show_host_message("🗺️ Player paths feature - coming soon!")
	hide_menu()

func _on_room_info_pressed() -> void:
	_show_host_message("🏠 Room info feature - coming soon!")
	hide_menu()

func _on_network_quality_pressed() -> void:
	if NetworkManager.is_multiplayer_active():
		var pings = "📶 Network: "
		for peer_id in NetworkManager.get_player_list():
			var ping = NetworkManager.get_peer_ping(peer_id) if NetworkManager.has_method("get_peer_ping") else "?"
			pings += "P%d: %sms | " % [peer_id, ping]
		_show_host_message(pings)
	hide_menu()

func _on_regenerate_room_pressed() -> void:
	_show_host_message("🔨 Room regeneration - coming soon!")
	hide_menu()

func _on_set_custom_start_pressed(input: LineEdit) -> void:
	if not NetworkManager.is_server():
		return
	var start = input.text.strip_edges()
	if start != "":
		if _main and _main.has_method("set_custom_start"):
			_main.set_custom_start(start)
			_show_host_message("🚪 Custom start set: %s" % start)
			input.text = ""
	hide_menu()

func _on_teleport_all_pressed() -> void:
	if not NetworkManager.is_server():
		return
	_teleport_all_to_lobby.rpc()
	_show_host_message("🔄 All players teleported to lobby!")
	hide_menu()

func _on_force_follow_pressed() -> void:
	if not NetworkManager.is_server():
		return
	_force_follow_host.rpc()
	_show_host_message("👥 All players following host!")
	hide_menu()

# === RPC Methods ===

@rpc("any_peer", "call_local", "reliable")
func _kick_player(peer_id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if NetworkManager.is_server():
		NetworkManager.kick_peer(peer_id)

@rpc("authority", "call_local", "reliable")
func _teleport_player_to_lobby() -> void:
	if _main and _main.has_method("_teleport_player_to_lobby"):
		_main._teleport_player_to_lobby()

@rpc("authority", "call_local", "reliable")
func _teleport_all_to_lobby() -> void:
	if _main and _main.has_method("_teleport_player_to_lobby"):
		_main._teleport_player_to_lobby()

@rpc("authority", "call_local", "reliable")
func _force_follow_host() -> void:
	# Teleport all players to host position
	pass

@rpc("any_peer", "call_remote", "reliable")
func _spawn_powerup_at_player(peer_id: int) -> void:
	# Spawn powerup at player location
	pass

@rpc("authority", "call_local", "reliable")
func _set_player_scale(scale: float) -> void:
	"""Set all player models to specified scale"""
	if _main and _main.has_node("Player"):
		var player = _main.get_node("Player")
		if player:
			player.scale = Vector3(scale, scale, scale)
			_show_host_message("Player scale set to %.1fx" % scale)

@rpc("authority", "call_local", "reliable")
func _set_gravity(gravity: float) -> void:
	"""Set gravity for all players"""
	if _main and _main.has_node("Player"):
		var player = _main.get_node("Player")
		if player and player.has_method("set_gravity"):
			player.set_gravity(gravity)
			_show_host_message("Gravity set to %.1f" % gravity)

# === Helper Methods ===

func _apply_speed_to_all_players() -> void:
	if _main and _main.has_node("Player"):
		var player = _main.get_node("Player")
		if player and player.has_method("set_max_speed"):
			player.set_max_speed(_base_player_speed * _speed_multiplier)

func _apply_dark_mode() -> void:
	# Toggle environment lighting
	pass

func _apply_handicap() -> void:
	# Apply speed boosts to trailing players
	pass

func _show_host_message(msg: String) -> void:
	Log.info("HostMenu", msg)
	if _main and _main.has_node("ChatSystem"):
		_main.get_node("ChatSystem")._show_system_message("🎮 Host: " + msg)

# Note: _input removed - Main.gd handles toggle_host_menu action directly
