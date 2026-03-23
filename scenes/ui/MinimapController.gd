extends Control
## MinimapController — redesigned minimap HUD.
##
## Architecture:
##   A rounded square panel sits in the top-right corner.
##   Inside: a SubViewport texture (top-down orthographic camera from Player.tscn),
##   overlaid with a compass rose, a pulsing player-dot, the current room label,
##   and +/- zoom buttons.
##
## Player.tscn requirements (unchanged from original):
##   MapCameraContainer  (Node3D, top_level=true)
##     MapViewport       (SubViewport, world_3d shared with main scene)
##       MapCamera       (Camera3D, orthographic, looks straight down)
##   MapMarker           (MeshInstance3D on render layer 24 — player dot)
##
## Public API:
##   init(player)         — call once after the player is spawned
##   cycle()              — toggle off → on (M key)
##   show_hud()           — force on
##   set_hidden()         — force off
##   restore_after_pause()
##   reset_zoom()
##   set_zoom(z)
##   set_room_label(text) — update the room name shown on the minimap

# ── Constants ──────────────────────────────────────────────────────────────────

const CAM_HEIGHT  : float = 40.0
const CAM_SIZE_1X : float = 22.0
const ZOOM_MIN    : float = 0.5
const ZOOM_MAX    : float = 4.0
const ZOOM_STEP   : float = 0.25

## Panel geometry
const PANEL_SIZE   : float = 220.0
const PANEL_MARGIN : float = 16.0
const PANEL_RADIUS : float = 14.0

## Player-dot pulse
const DOT_RADIUS_BASE  : float = 6.0
const DOT_PULSE_RANGE  : float = 3.0
const DOT_PULSE_SPEED  : float = 2.2

## Colors — these respond to ThemeManager dark/light via _apply_theme()
var _col_panel_bg   : Color = Color(0.08, 0.08, 0.10, 0.82)
var _col_panel_rim  : Color = Color(0.30, 0.32, 0.38, 0.90)
var _col_dot        : Color = Color(0.25, 0.70, 1.00, 1.00)
var _col_dot_ring   : Color = Color(1.00, 1.00, 1.00, 0.55)
var _col_compass    : Color = Color(1.00, 1.00, 1.00, 0.55)
var _col_north      : Color = Color(1.00, 0.35, 0.35, 0.90)
var _col_label_bg   : Color = Color(0.00, 0.00, 0.00, 0.50)
var _col_label_text : Color = Color(1.00, 1.00, 1.00, 0.90)
var _col_btn_bg     : Color = Color(0.18, 0.18, 0.22, 0.85)
var _col_btn_text   : Color = Color(0.85, 0.85, 0.90, 1.00)

# ── State ──────────────────────────────────────────────────────────────────────

var _mode   : int   = 0   # 0 = off, 1 = on
var _zoom   : float = 1.0
var _player : Node  = null
var _pulse  : float = 0.0
var _room_label : String = ""

var _container : Node3D      = null
var _viewport  : SubViewport = null
var _cam       : Camera3D    = null

# ── Sub-nodes (built in _build_ui) ────────────────────────────────────────────

var _panel        : Panel           = null   # outer rounded card
var _map_rect     : TextureRect     = null   # SubViewport texture display
var _overlay      : Control         = null   # transparent layer for canvas drawing
var _label_bg     : PanelContainer  = null   # room-name pill at bottom
var _label        : Label           = null
var _zoom_in_btn  : Button          = null
var _zoom_out_btn : Button          = null
var _zoom_label   : Label           = null


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_e): _apply_theme())
	_set_panel_visible(false)


func _process(delta: float) -> void:
	if _mode == 0 or not is_instance_valid(_player):
		return

	# Advance pulse timer
	_pulse = fmod(_pulse + delta * DOT_PULSE_SPEED, TAU)

	# Keep camera above player
	if _cam and is_instance_valid(_cam):
		var p : Vector3 = _player.global_position
		_cam.global_position = Vector3(p.x, CAM_HEIGHT, p.z)

	# Push viewport texture into the TextureRect
	if _viewport:
		_map_rect.texture = _viewport.get_texture()

	# Redraw canvas overlay (dot + compass)
	_overlay.queue_redraw()


func _input(event: InputEvent) -> void:
	if _mode == 0:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(_zoom + ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(_zoom - ZOOM_STEP)


# =============================================================================
# Public API
# =============================================================================

func init(player: Node) -> void:
	_player    = player
	_container = player.get_node_or_null("MapCameraContainer")
	_viewport  = player.get_node_or_null("MapCameraContainer/MapViewport")
	_cam       = player.get_node_or_null("MapCameraContainer/MapViewport/MapCamera")

	if _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	_configure_camera()


func cycle() -> void:
	_mode = 1 if _mode == 0 else 0
	_refresh_visibility()


func show_hud() -> void:
	if _mode == 0:
		_mode = 1
	_refresh_visibility()


func set_hidden() -> void:
	_mode = 0
	_refresh_visibility()


func restore_after_pause() -> void:
	if _mode > 0:
		_refresh_visibility()


func reset_zoom() -> void:
	_set_zoom(1.0)


func set_zoom(z: float) -> void:
	_set_zoom(z)


func set_room_label(text: String) -> void:
	_room_label = text
	if _label:
		_label.text = text
		_label_bg.visible = text != ""


# =============================================================================
# UI Construction
# =============================================================================

func _build_ui() -> void:
	# Outer panel — anchored top-right
	_panel = Panel.new()
	_panel.name = "MinimapPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(PANEL_SIZE, PANEL_SIZE)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left   = -PANEL_SIZE  - PANEL_MARGIN
	_panel.offset_right  = -PANEL_MARGIN
	_panel.offset_top    =  PANEL_MARGIN
	_panel.offset_bottom =  PANEL_SIZE  + PANEL_MARGIN
	add_child(_panel)

	_style_panel(_panel)

	# Viewport texture — fills panel with a small inset
	const INSET : float = 8.0
	_map_rect = TextureRect.new()
	_map_rect.name = "MapRect"
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_map_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_rect.offset_left   =  INSET
	_map_rect.offset_right  = -INSET
	_map_rect.offset_top    =  INSET
	_map_rect.offset_bottom = -INSET
	_panel.add_child(_map_rect)

	# Canvas overlay (compass + dot) — same size as panel
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	_panel.add_child(_overlay)

	# Room-name label pill at the bottom of the panel
	_label_bg = PanelContainer.new()
	_label_bg.name = "LabelBg"
	_label_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_bg.visible = false
	_label_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label_bg.offset_top    = -30
	_label_bg.offset_bottom = -6
	_label_bg.offset_left   =  6
	_label_bg.offset_right  = -6
	_style_pill(_label_bg)
	_panel.add_child(_label_bg)

	_label = Label.new()
	_label.name = "RoomLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 11)
	_label_bg.add_child(_label)

	# Zoom buttons — top-right corner of the panel
	_zoom_in_btn  = _make_zoom_btn("+", Vector2(-6, 6))
	_zoom_out_btn = _make_zoom_btn("−", Vector2(-6, 30))
	_panel.add_child(_zoom_in_btn)
	_panel.add_child(_zoom_out_btn)
	_zoom_in_btn.pressed.connect(func(): _set_zoom(_zoom + ZOOM_STEP))
	_zoom_out_btn.pressed.connect(func(): _set_zoom(_zoom - ZOOM_STEP))

	# Zoom-level readout (tiny text top-left corner)
	_zoom_label = Label.new()
	_zoom_label.name = "ZoomLabel"
	_zoom_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_label.text = "1.0×"
	_zoom_label.add_theme_font_size_override("font_size", 10)
	_zoom_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_zoom_label.offset_left = 8
	_zoom_label.offset_top  = 8
	_panel.add_child(_zoom_label)


func _make_zoom_btn(icon: String, offset_from_tr: Vector2) -> Button:
	var btn := Button.new()
	btn.text = icon
	btn.custom_minimum_size = Vector2(20, 20)
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_right  = -offset_from_tr.x
	btn.offset_left   = -offset_from_tr.x - 20
	btn.offset_top    =  offset_from_tr.y
	btn.offset_bottom =  offset_from_tr.y + 20
	_style_zoom_btn(btn)
	return btn


# =============================================================================
# Drawing
# =============================================================================

func _draw_overlay() -> void:
	var sz  : Vector2 = _overlay.size
	var ctr : Vector2 = sz * 0.5

	# --- Compass rose ---
	const COMPASS_R  : float = 10.0
	const TICK_OUTER : float = 9.0
	const TICK_INNER : float = 5.0
	const N_SIZE     : float = 13.0
	var compass_pos := Vector2(ctr.x, 18.0)

	# Player heading (yaw), so north marker rotates with map
	var heading : float = _player.rotation.y if is_instance_valid(_player) else 0.0

	for i in 8:
		var angle : float = heading + i * (TAU / 8.0)
		var outer : Vector2 = compass_pos + Vector2(sin(angle), -cos(angle)) * TICK_OUTER
		var inner : Vector2 = compass_pos + Vector2(sin(angle), -cos(angle)) * TICK_INNER
		var col   : Color   = _col_north if i == 0 else _col_compass
		_overlay.draw_line(inner, outer, col, 1.5 if i % 2 == 0 else 1.0)

	# "N" label
	var north_tip := compass_pos + Vector2(sin(heading), -cos(heading)) * (TICK_OUTER + 5.0)
	_overlay.draw_string(
		_overlay.get_theme_default_font(),
		north_tip - Vector2(4, 5),
		"N", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, _col_north
	)

	# --- Panel rim circle (inner crop indicator) ---
	var rim_r : float = (sz.x * 0.5) - 8.0
	_overlay.draw_arc(ctr, rim_r, 0, TAU, 64, _col_panel_rim, 1.0)

	# --- Player dot + pulse ring ---
	var pulse_t  : float = (sin(_pulse) + 1.0) * 0.5                 # 0..1
	var dot_r    : float = DOT_RADIUS_BASE + pulse_t * DOT_PULSE_RANGE
	var ring_r   : float = dot_r + 4.0
	var ring_a   : float = (1.0 - pulse_t) * 0.6

	var ring_col := Color(_col_dot_ring.r, _col_dot_ring.g, _col_dot_ring.b, ring_a)
	_overlay.draw_circle(ctr, ring_r, ring_col)
	_overlay.draw_circle(ctr, DOT_RADIUS_BASE, _col_dot)

	# Heading arrow on dot
	var arrow_tip  := ctr + Vector2(sin(-heading), -cos(-heading)) * (DOT_RADIUS_BASE + 5.0)
	var arrow_col  := Color(1.0, 1.0, 1.0, 0.9)
	_overlay.draw_line(ctr, arrow_tip, arrow_col, 2.0)


# =============================================================================
# Theming
# =============================================================================

func _apply_theme() -> void:
	if ThemeManager.is_dark_mode:
		_col_panel_bg   = Color(0.08, 0.08, 0.10, 0.85)
		_col_panel_rim  = Color(0.30, 0.32, 0.38, 0.90)
		_col_label_bg   = Color(0.00, 0.00, 0.00, 0.55)
		_col_label_text = Color(1.00, 1.00, 1.00, 0.90)
		_col_btn_bg     = Color(0.18, 0.18, 0.22, 0.90)
		_col_btn_text   = Color(0.85, 0.85, 0.90, 1.00)
		_col_compass    = Color(1.00, 1.00, 1.00, 0.45)
		_col_dot        = Color(0.25, 0.70, 1.00, 1.00)
	else:
		_col_panel_bg   = Color(0.95, 0.96, 0.98, 0.88)
		_col_panel_rim  = Color(0.60, 0.62, 0.68, 0.80)
		_col_label_bg   = Color(0.90, 0.91, 0.95, 0.80)
		_col_label_text = Color(0.10, 0.10, 0.15, 0.90)
		_col_btn_bg     = Color(0.88, 0.89, 0.93, 0.90)
		_col_btn_text   = Color(0.15, 0.15, 0.20, 1.00)
		_col_compass    = Color(0.20, 0.20, 0.25, 0.60)
		_col_dot        = Color(0.10, 0.50, 0.90, 1.00)

	if _panel:
		_style_panel(_panel)
	if _label_bg:
		_style_pill(_label_bg)
	if _label:
		_label.add_theme_color_override("font_color", _col_label_text)
	if _zoom_label:
		_zoom_label.add_theme_color_override("font_color", _col_compass)
	if _zoom_in_btn:
		_style_zoom_btn(_zoom_in_btn)
	if _zoom_out_btn:
		_style_zoom_btn(_zoom_out_btn)


func _style_panel(p: Panel) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color              = _col_panel_bg
	sb.border_color          = _col_panel_rim
	for s in ["left", "right", "top", "bottom"]:
		sb.set("border_width_" + s, 1)
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		sb.set("corner_radius_" + c, int(PANEL_RADIUS))
	sb.shadow_color  = Color(0, 0, 0, 0.35)
	sb.shadow_size   = 10
	sb.shadow_offset = Vector2(0, 4)
	p.add_theme_stylebox_override("panel", sb)


func _style_pill(pc: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _col_label_bg
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		sb.set("corner_radius_" + c, 8)
	pc.add_theme_stylebox_override("panel", sb)


func _style_zoom_btn(btn: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _col_btn_bg
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		sb.set("corner_radius_" + c, 4)
	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("hover",   sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", _col_btn_text)
	btn.add_theme_font_size_override("font_size", 13)


# =============================================================================
# Visibility / animation
# =============================================================================

func _refresh_visibility() -> void:
	if _mode == 0:
		_animate_out()
	else:
		_set_panel_visible(true)
		_animate_in()
		_apply_zoom()


func _set_panel_visible(v: bool) -> void:
	if _panel:
		_panel.visible = v


func _animate_in() -> void:
	if not _panel: return
	_panel.modulate.a = 0.0
	_panel.scale      = Vector2(0.88, 0.88)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "scale",      Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _animate_out() -> void:
	if not _panel: return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 0.0,              0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "scale",      Vector2(0.88, 0.88), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func(): _set_panel_visible(false); _panel.modulate.a = 1.0; _panel.scale = Vector2.ONE)


# =============================================================================
# Camera + zoom
# =============================================================================

func _configure_camera() -> void:
	if not _cam: return
	_cam.transform = Transform3D(
		Vector3(1, 0, 0),
		Vector3(0, 0, 1),
		Vector3(0, 1, 0),
		Vector3(0, CAM_HEIGHT, 0))
	_cam.projection  = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near        = CAM_HEIGHT - 10.0
	_cam.far         = CAM_HEIGHT + 15.0
	_cam.size        = CAM_SIZE_1X
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT


func _set_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_apply_zoom()


func _apply_zoom() -> void:
	if _cam:
		_cam.size = CAM_SIZE_1X / _zoom
	if _zoom_label:
		_zoom_label.text = "%.1f×" % _zoom
