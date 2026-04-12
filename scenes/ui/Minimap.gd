extends Control
## Minimap — single, clean 2D topological map of visited exhibits.
##
## Shows rooms as nodes and connections as lines in the upper-right HUD.
## Uses ExhibitGraph as the single authoritative data source.
##
## Lifecycle:
##   Minimap.new() → add to tree → show() / hide() / toggle()
## No .tscn scene file needed — builds all UI in code.

# ── Colours ────────────────────────────────────────────────────────────────

var _dark: bool = true

func _get_bg_color() -> Color:
	return Color(0.06, 0.05, 0.04, 0.88) if _dark else Color(0.92, 0.90, 0.87, 0.88)

func _get_border_color() -> Color:
	return Color(0.25, 0.22, 0.19) if _dark else Color(0.55, 0.50, 0.45)

func _get_node_color() -> Color:
	return Color(0.50, 0.50, 0.50)

func _get_visited_color() -> Color:
	return Color(0.35, 0.55, 0.90) if _dark else Color(0.20, 0.45, 0.80)

func _get_edge_color() -> Color:
	return Color(0.30, 0.30, 0.30, 0.5) if _dark else Color(0.60, 0.60, 0.60, 0.4)

func _get_path_color() -> Color:
	return Color(0.40, 0.70, 1.0, 0.7) if _dark else Color(0.20, 0.55, 0.90, 0.5)

func _get_text_color() -> Color:
	return Color(0.90, 0.88, 0.85) if _dark else Color(0.12, 0.10, 0.08)

const COLOR_NODE_CURRENT: Color = Color(1.0, 0.85, 0.15)

const NODE_RADIUS: float = 4.0
const CURRENT_RADIUS: float = 6.0
const LINE_WIDTH: float = 2.0
const PATH_LINE_WIDTH: float = 2.5
const PULSE_SPEED: float = 3.0
const PULSE_RADIUS: float = 12.0

const PANEL_W: float = 180.0
const PANEL_H: float = 180.0
const LABEL_H: float = 28.0

# ── State ──────────────────────────────────────────────────────────────────

var _visible: bool = false
var _current_room: String = ""
var _zoom: float = 1.0
var _pulse: float = 0.0

# ── Player reference (optional — unused by graph view but satisfies MinimapController API)
var _player: Node = null

# ── Node references ───────────────────────────────────────────────────────

var _panel: PanelContainer
var _draw_area: Control
var _label: Label
var _zoom_in_btn: Button
var _zoom_out_btn: Button

# ── Lifecycle ──────────────────────────────────────────────────────────────

func _init() -> void:
	# Anchor to top-right corner
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -(PANEL_W + 16)
	offset_top = 16
	offset_right = -16
	offset_bottom = PANEL_H + 16
	# Start hidden
	visible = false

func _ready() -> void:
	_dark = ThemeManager.is_dark_mode
	_build_ui()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(_on_dark_mode_changed)

	# Listen to room changes
	SettingsEvents.set_current_room.connect(_on_room_changed)

	# Listen to graph redraw requests
	ExhibitGraph.graph_changed.connect(_on_graph_changed)

func _process(delta: float) -> void:
	_pulse += delta
	if visible and _draw_area:
		_draw_area.queue_redraw()

# ── Public API ─────────────────────────────────────────────────────────────

func show_map() -> void:
	_visible = true
	_animate_in()

func hide_map() -> void:
	_visible = false
	_animate_out()

func toggle() -> void:
	if _visible:
		hide_map()
	else:
		show_map()

## Called by MinimapController after every player (re-)spawn.
func init(player: Node) -> void:
	_player = player

func set_current_room(title: String) -> void:
	_current_room = title
	_update_label()

# ── UI Construction ───────────────────────────────────────────────────────

func _build_ui() -> void:
	# Main panel
	_panel = PanelContainer.new()
	_panel.name = "MinimapPanel"
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_panel)

	# Container for everything inside the panel
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(vbox)

	# Drawing area
	_draw_area = Control.new()
	_draw_area.name = "MinimapDrawArea"
	_draw_area.custom_minimum_size = Vector2(PANEL_W, PANEL_H - LABEL_H)
	_draw_area.draw.connect(_on_draw)
	vbox.add_child(_draw_area)

	# Room label
	_label = Label.new()
	_label.name = "MinimapLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(_label)

	# Zoom controls — horizontal row below label
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	_zoom_out_btn = Button.new()
	_zoom_out_btn.text = "−"
	_zoom_out_btn.custom_minimum_size = Vector2(32, 24)
	_zoom_out_btn.pressed.connect(_on_zoom_out)
	hbox.add_child(_zoom_out_btn)

	_zoom_in_btn = Button.new()
	_zoom_in_btn.text = "+"
	_zoom_in_btn.custom_minimum_size = Vector2(32, 24)
	_zoom_in_btn.pressed.connect(_on_zoom_in)
	hbox.add_child(_zoom_in_btn)

func _apply_theme() -> void:
	if not _panel or not _label or not _zoom_in_btn:
		return
	# Panel style
	var style_bg: StyleBoxFlat = StyleBoxFlat.new()
	style_bg.bg_color = _get_bg_color()
	style_bg.set_corner_radius_all(8)
	style_bg.set_border_width_all(1)
	style_bg.border_color = _get_border_color()
	style_bg.content_margin_left = 4
	style_bg.content_margin_right = 4
	style_bg.content_margin_top = 4
	style_bg.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", style_bg)

	# Zoom buttons
	var btn_style: StyleBoxFlat = StyleBoxFlat.new()
	btn_style.bg_color = Color.TRANSPARENT
	btn_style.set_corner_radius_all(4)
	_zoom_in_btn.add_theme_stylebox_override("normal", btn_style.duplicate())
	_zoom_out_btn.add_theme_stylebox_override("normal", btn_style.duplicate())
	_zoom_in_btn.add_theme_color_override("font_color", _get_text_color())
	_zoom_out_btn.add_theme_color_override("font_color", _get_text_color())

	# Label
	_label.add_theme_color_override("font_color", _get_text_color())

func _on_draw() -> void:
	var center: Vector2 = _draw_area.size / 2.0

	_draw_edges(center)
	_draw_path_edges(center)
	_draw_nodes(center)
	_draw_pulse(center)

func _draw_edges(center: Vector2) -> void:
	var edges: Array = ExhibitGraph.get_edges()
	var layout: Dictionary = ExhibitGraph.get_layout()

	for edge: Array in edges:
		var from: String = edge[0]
		var to: String = edge[1]

		if not layout.has(from) or not layout.has(to):
			continue

		var from_screen: Vector2 = _to_screen(layout[from], center)
		var to_screen: Vector2 = _to_screen(layout[to], center)

		_draw_area.draw_line(from_screen, to_screen, _get_edge_color(), LINE_WIDTH)

func _draw_path_edges(center: Vector2) -> void:
	var history: Array = ExhibitGraph.get_visit_history()
	var layout: Dictionary = ExhibitGraph.get_layout()

	if history.size() < 2:
		return

	var start_idx: int = maxi(history.size() - 10, 0)
	for i: int in range(start_idx, history.size() - 1):
		var from: String = history[i]
		var to: String = history[i + 1]

		if not layout.has(from) or not layout.has(to):
			continue

		var from_screen: Vector2 = _to_screen(layout[from], center)
		var to_screen: Vector2 = _to_screen(layout[to], center)

		_draw_area.draw_line(from_screen, to_screen, _get_path_color(), PATH_LINE_WIDTH)

func _draw_nodes(center: Vector2) -> void:
	var nodes: Dictionary = ExhibitGraph.get_nodes()
	var layout: Dictionary = ExhibitGraph.get_layout()

	for room: String in nodes:
		if not layout.has(room):
			continue

		var pos: Vector2 = _to_screen(layout[room], center)
		var is_current: bool = (room == _current_room)
		var is_visited: bool = nodes[room].get("visited", false)

		var radius: float = CURRENT_RADIUS if is_current else NODE_RADIUS
		var color: Color

		if is_current:
			color = COLOR_NODE_CURRENT
		elif is_visited:
			color = _get_visited_color()
		else:
			color = _get_node_color()

		_draw_area.draw_circle(pos, radius, color)

func _draw_pulse(center: Vector2) -> void:
	var layout: Dictionary = ExhibitGraph.get_layout()
	if not layout.has(_current_room):
		return

	var pos: Vector2 = _to_screen(layout[_current_room], center)
	var pulse_scale: float = 0.5 + 0.5 * sin(_pulse * PULSE_SPEED)
	var radius: float = PULSE_RADIUS * pulse_scale
	var alpha: float = 0.3 * (1.0 - pulse_scale)

	_draw_area.draw_circle(pos, radius, Color(1.0, 0.85, 0.15, alpha))

func _to_screen(graph_pos: Vector2, center: Vector2) -> Vector2:
	# Always centre the view on the current room so it stays in frame when zoomed.
	var current_layout_pos: Vector2 = ExhibitGraph.get_layout().get(_current_room, Vector2.ZERO)
	return center + (graph_pos - current_layout_pos) * _zoom

func _update_label() -> void:
	var display: String = _current_room
	if display == "":
		display = "Unknown"
	_label.text = display

# ── Animation ──────────────────────────────────────────────────────────────

func _animate_in() -> void:
	visible = true
	modulate.a = 0.0
	var tw: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)

func _animate_out() -> void:
	var tw: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func(): visible = false)

# ── Signal Handlers ────────────────────────────────────────────────────────

func _on_room_changed(room: String) -> void:
	_current_room = room
	_update_label()

func _on_dark_mode_changed(_v: bool) -> void:
	_dark = _v
	_apply_theme()
	queue_redraw()

func _on_graph_changed() -> void:
	if _draw_area:
		_draw_area.queue_redraw()

func _on_zoom_in() -> void:
	_zoom = minf(_zoom * 1.2, 3.0)

func _on_zoom_out() -> void:
	_zoom = maxf(_zoom / 1.2, 0.5)
