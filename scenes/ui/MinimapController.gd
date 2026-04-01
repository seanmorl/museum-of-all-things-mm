extends Control
## MinimapController — redesigned minimap HUD (matches moat-ui.html design).
##
## A clean topological map showing visited rooms as dots with connection lines.
## Features:
##   - Pulsing player dot at center
##   - Room nodes positioned relative to player
##   - Connection lines showing paths between rooms
##   - Compass rose with north indicator
##   - Room name label at bottom
##   - Zoom controls (+/- buttons and scroll wheel)
##   - Theme-aware colors (dark/light mode)

# ── Constants ──────────────────────────────────────────────────────────────────

const PANEL_SIZE      : float = 160.0
const PANEL_MARGIN    : float = 12.0
const PANEL_RADIUS    : float = 12.0
const DOT_RADIUS      : float = 5.0
const ROOM_DOT_RADIUS : float = 4.0
const LINE_WIDTH      : float = 1.5
const COMPASS_RADIUS  : float = 10.0

# Zoom settings
const ZOOM_MIN : float = 0.5
const ZOOM_MAX : float = 3.0
const ZOOM_STEP: float = 0.25

# Pulse animation
const PULSE_SPEED : float = 2.0
const PULSE_RANGE : float = 3.0

# ── State ──────────────────────────────────────────────────────────────────────

var _player        : Node   = null
var _pulse         : float  = 0.0
var _room_label    : String = ""
var _zoom          : float  = 1.0
var _visited_rooms : Array[String] = []  # List of visited room names
var _connections   : Array[Dictionary] = []  # [{from, to}, ...]

# ── Colors (theme-aware) ───────────────────────────────────────────────────────

var _col_bg         : Color = Color(0.08, 0.08, 0.10, 0.85)
var _col_border     : Color = Color(0.30, 0.32, 0.38, 0.90)
var _col_player     : Color = Color(0.23, 0.58, 0.85, 1.00)
var _col_player_ring: Color = Color(0.23, 0.58, 0.85, 0.30)
var _col_room       : Color = Color(0.40, 0.42, 0.48, 0.80)
var _col_line       : Color = Color(0.50, 0.52, 0.58, 0.50)
var _col_compass    : Color = Color(1.00, 1.00, 1.00, 0.50)
var _col_north      : Color = Color(0.95, 0.30, 0.30, 0.90)
var _col_label_bg   : Color = Color(0.00, 0.00, 0.00, 0.50)
var _col_label_text : Color = Color(1.00, 1.00, 1.00, 0.90)
var _col_btn_bg     : Color = Color(0.18, 0.18, 0.22, 0.85)
var _col_btn_text   : Color = Color(0.85, 0.85, 0.90, 1.00)

# ── Sub-nodes ──────────────────────────────────────────────────────────────────

var _panel        : Panel          = null
var _overlay      : Control        = null
var _label_bg     : PanelContainer = null
var _label        : Label          = null
var _zoom_in_btn  : Button         = null
var _zoom_out_btn : Button         = null
var _zoom_label   : Label          = null

# ── Visibility state ───────────────────────────────────────────────────────────

var _mode : int = 0  # 0 = off, 1 = on


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_e): _apply_theme())
	_set_visible(false)


func _process(delta: float) -> void:
	if _mode == 0:
		return
	
	_pulse += delta * PULSE_SPEED
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
	_player = player


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


func add_visited_room(room_name: String) -> void:
	if room_name not in _visited_rooms:
		_visited_rooms.append(room_name)
		_overlay.queue_redraw()


func add_connection(from_room: String, to_room: String) -> void:
	_connections.append({"from": from_room, "to": to_room})
	_overlay.queue_redraw()


func clear_visited() -> void:
	_visited_rooms.clear()
	_connections.clear()
	_overlay.queue_redraw()


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
	_panel.offset_left   = -PANEL_SIZE - PANEL_MARGIN
	_panel.offset_right  = -PANEL_MARGIN
	_panel.offset_top    =  PANEL_MARGIN
	_panel.offset_bottom =  PANEL_SIZE + PANEL_MARGIN
	add_child(_panel)
	_style_panel(_panel)

	# Canvas overlay (all drawing)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	_panel.add_child(_overlay)

	# Room-name label pill at the bottom
	_label_bg = PanelContainer.new()
	_label_bg.name = "LabelBg"
	_label_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_bg.visible = false
	_label_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label_bg.offset_top    = -28
	_label_bg.offset_bottom = -6
	_label_bg.offset_left   =  6
	_label_bg.offset_right  = -6
	_style_pill(_label_bg)
	_panel.add_child(_label_bg)

	_label = Label.new()
	_label.name = "RoomLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 10)
	_label_bg.add_child(_label)

	# Zoom buttons
	_zoom_in_btn  = _make_zoom_btn("+", Vector2(-6, 6))
	_zoom_out_btn = _make_zoom_btn("−", Vector2(-6, 28))
	_panel.add_child(_zoom_in_btn)
	_panel.add_child(_zoom_out_btn)
	_zoom_in_btn.pressed.connect(func(): _set_zoom(_zoom + ZOOM_STEP))
	_zoom_out_btn.pressed.connect(func(): _set_zoom(_zoom - ZOOM_STEP))

	# Zoom-level readout
	_zoom_label = Label.new()
	_zoom_label.name = "ZoomLabel"
	_zoom_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_label.text = "1.0×"
	_zoom_label.add_theme_font_size_override("font_size", 9)
	_zoom_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_zoom_label.offset_left = 6
	_zoom_label.offset_top  = 6
	_panel.add_child(_zoom_label)


func _make_zoom_btn(icon: String, offset_from_tr: Vector2) -> Button:
	var btn := Button.new()
	btn.text = icon
	btn.custom_minimum_size = Vector2(18, 18)
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_right  = -offset_from_tr.x
	btn.offset_left   = -offset_from_tr.x - 18
	btn.offset_top    =  offset_from_tr.y
	btn.offset_bottom =  offset_from_tr.y + 18
	_style_zoom_btn(btn)
	return btn


# =============================================================================
# Drawing
# =============================================================================

func _draw_overlay() -> void:
	var size : Vector2 = _overlay.size * _zoom
	var center : Vector2 = size * 0.5

	# --- Draw connection lines first (behind dots) ---
	for conn in _connections:
		var from_idx = _visited_rooms.find(conn.from)
		var to_idx = _visited_rooms.find(conn.to)
		if from_idx >= 0 and to_idx >= 0:
			var from_pos = _get_room_position(from_idx, center)
			var to_pos = _get_room_position(to_idx, center)
			_overlay.draw_line(from_pos, to_pos, _col_line, LINE_WIDTH * _zoom)

	# --- Draw room dots ---
	for i in range(_visited_rooms.size()):
		var pos = _get_room_position(i, center)
		var radius = ROOM_DOT_RADIUS * _zoom
		_overlay.draw_circle(pos, radius, _col_room)

	# --- Player dot with pulse ring at center ---
	var pulse_t = (sin(_pulse) + 1.0) * 0.5
	var ring_r = (DOT_RADIUS + PULSE_RANGE) * pulse_t * _zoom
	var ring_a = (1.0 - pulse_t) * 0.5
	var ring_col = Color(_col_player_ring.r, _col_player_ring.g, _col_player_ring.b, ring_a)
	
	# Pulse ring
	_overlay.draw_circle(center, ring_r, ring_col)
	# Player dot
	_overlay.draw_circle(center, DOT_RADIUS * _zoom, _col_player)

	# --- Compass rose ---
	var heading : float = _player.rotation.y if _player else 0.0
	var compass_pos := Vector2(center.x, 18.0 * _zoom)
	
	# Draw 8 compass points
	for i in 8:
		var angle : float = heading + i * (TAU / 8.0)
		var outer_r = COMPASS_RADIUS * _zoom
		var inner_r = (COMPASS_RADIUS - 5) * _zoom
		var outer : Vector2 = compass_pos + Vector2(sin(angle), -cos(angle)) * outer_r
		var inner : Vector2 = compass_pos + Vector2(sin(angle), -cos(angle)) * inner_r
		var col : Color = _col_north if i == 0 else _col_compass
		var width : float = 1.5 if i % 2 == 0 else 1.0
		_overlay.draw_line(inner, outer, col, width)

	# "N" label
	var north_tip := compass_pos + Vector2(sin(heading), -cos(heading)) * (outer_r + 6 * _zoom)
	_overlay.draw_string(
		_overlay.get_theme_default_font(),
		north_tip - Vector2(4 * _zoom, 4 * _zoom),
		"N", HORIZONTAL_ALIGNMENT_CENTER, -1, int(10 * _zoom), _col_north
	)


func _get_room_position(index: int, center: Vector2) -> Vector2:
	# Arrange rooms in a spiral pattern from center
	if index == 0:
		return center
	
	var angle = index * 0.8  # Radians between rooms
	var distance = 25 + (index * 8)  # Increasing distance from center
	var pos = center + Vector2(cos(angle), sin(angle)) * distance * _zoom
	return pos


# =============================================================================
# Theming
# =============================================================================

func _apply_theme() -> void:
	if ThemeManager.is_dark_mode:
		_col_bg         = Color(0.08, 0.08, 0.10, 0.88)
		_col_border     = Color(0.35, 0.38, 0.45, 0.85)
		_col_player     = Color(0.23, 0.58, 0.85, 1.00)
		_col_player_ring= Color(0.23, 0.58, 0.85, 0.30)
		_col_room       = Color(0.50, 0.52, 0.58, 0.70)
		_col_line       = Color(0.50, 0.52, 0.58, 0.40)
		_col_compass    = Color(1.00, 1.00, 1.00, 0.45)
		_col_north      = Color(0.95, 0.30, 0.30, 0.90)
		_col_label_bg   = Color(0.00, 0.00, 0.00, 0.55)
		_col_label_text = Color(1.00, 1.00, 1.00, 0.90)
		_col_btn_bg     = Color(0.18, 0.18, 0.22, 0.90)
		_col_btn_text   = Color(0.85, 0.85, 0.90, 1.00)
	else:
		_col_bg         = Color(0.96, 0.97, 0.98, 0.90)
		_col_border     = Color(0.65, 0.68, 0.72, 0.75)
		_col_player     = Color(0.15, 0.45, 0.75, 1.00)
		_col_player_ring= Color(0.15, 0.45, 0.75, 0.25)
		_col_room       = Color(0.60, 0.62, 0.68, 0.65)
		_col_line       = Color(0.60, 0.62, 0.68, 0.35)
		_col_compass    = Color(0.30, 0.30, 0.35, 0.55)
		_col_north      = Color(0.85, 0.20, 0.20, 0.90)
		_col_label_bg   = Color(0.92, 0.93, 0.96, 0.75)
		_col_label_text = Color(0.15, 0.15, 0.20, 0.90)
		_col_btn_bg     = Color(0.88, 0.89, 0.93, 0.85)
		_col_btn_text   = Color(0.20, 0.20, 0.25, 1.00)

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
	sb.bg_color = _col_bg
	sb.border_color = _col_border
	for s in ["left", "right", "top", "bottom"]:
		sb.set("border_width_" + s, 1)
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		sb.set("corner_radius_" + c, int(PANEL_RADIUS))
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_size = 10
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
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", _col_btn_text)
	btn.add_theme_font_size_override("font_size", 12)


# =============================================================================
# Visibility / Animation
# =============================================================================

func _refresh_visibility() -> void:
	if _mode == 0:
		_animate_out()
	else:
		_set_visible(true)
		_animate_in()


func _set_visible(v: bool) -> void:
	if _panel:
		_panel.visible = v


func _animate_in() -> void:
	if not _panel: return
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.88, 0.88)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _animate_out() -> void:
	if not _panel: return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "scale", Vector2(0.88, 0.88), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func(): _set_visible(false); _panel.modulate.a = 1.0; _panel.scale = Vector2.ONE)


# =============================================================================
# Zoom
# =============================================================================

func _set_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_apply_zoom()


func _apply_zoom() -> void:
	if _zoom_label:
		_zoom_label.text = "%.1f×" % _zoom
	_overlay.queue_redraw()
