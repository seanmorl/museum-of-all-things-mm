extends Control
## GraphMinimap — reimagined 2D connection graph with radial layout,
## bezier edges, glowing current room, and multiplayer player dots.

const NODE_RADIUS := 7.0
const LABEL_FONT_SIZE := 9
const GLOW_RADIUS := 14.0

var _time: float = 0.0
var _player: Node = null
var _font: Font = null
var _panel_style: StyleBoxFlat = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left   = -270.0
	offset_top    = -270.0
	offset_right  = -20.0
	offset_bottom = -20.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical   = Control.GROW_DIRECTION_BEGIN

	_font = ThemeManager.get_reading_font()
	if not _font:
		_font = ThemeDB.fallback_font
	ThemeManager.reading_font_changed.connect(func(f): _font = f if f else ThemeDB.fallback_font)
	ThemeManager.dark_mode_changed.connect(func(_d): queue_redraw())
	ExhibitGraph.graph_changed.connect(queue_redraw)
	NetworkManager.player_room_changed.connect(func(_id, _room): queue_redraw())

func init(player: Node) -> void:
	_player = player

func set_zoom(_level: float) -> void:
	pass  # Graph doesn't use zoom


func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()


func _draw() -> void:
	if not visible:
		return

	var dark := ThemeManager.is_dark_mode
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5

	# Background: subtle radial gradient
	var bg_center := Color(0.08, 0.10, 0.18, 0.88) if dark else Color(0.94, 0.95, 0.97, 0.85)
	var bg_edge := Color(0.05, 0.06, 0.12, 0.92) if dark else Color(0.88, 0.89, 0.93, 0.85)
	_draw_radial_bg(center, radius, bg_center, bg_edge)

	# Border ring
	var ring_color := Color(0.25, 0.45, 0.85, 0.5) if dark else Color(0.4, 0.55, 0.8, 0.4)
	draw_arc(center, radius, 0, TAU, 64, ring_color, 2.0, true)
	draw_arc(center, radius - 3, 0, TAU, 64, Color(ring_color, 0.15), 1.0, true)

	var layout: Dictionary = ExhibitGraph.get_layout()
	if layout.is_empty():
		# Draw "Explore to reveal" text
		var msg_color := Color(1, 1, 1, 0.4) if dark else Color(0, 0, 0, 0.3)
		draw_string(_font, center + Vector2(-40, 4), "Explore to reveal", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, msg_color)
		return

	var nodes: Dictionary = ExhibitGraph.get_nodes()
	var edges: Array = ExhibitGraph.get_edges()
	var history: Array[String] = ExhibitGraph.get_visit_history()
	var current: String = ExhibitGraph.get_current_room()
	var current_pos: Vector2 = layout.get(current, Vector2.ZERO)
	var scale_factor: float = 80.0

	# Build path set for highlighting traversed edges
	var path_edges: Dictionary = {}
	for i: int in range(1, history.size()):
		var ka: String = history[i - 1] + "|" + history[i]
		var kb: String = history[i] + "|" + history[i - 1]
		path_edges[ka] = true
		path_edges[kb] = true

	# colours
	var edge_color := Color(0.4, 0.5, 0.7, 0.35) if dark else Color(0.5, 0.55, 0.7, 0.3)
	var path_color := Color(0.3, 0.55, 1.0, 0.7) if dark else Color(0.15, 0.35, 0.85, 0.6)
	var visited_color := Color(0.5, 0.4, 0.75) if dark else Color(0.42, 0.30, 0.63)
	var unvisited_color := Color(0.5, 0.55, 0.65, 0.4) if dark else Color(0.7, 0.72, 0.78, 0.5)
	var current_color := Color(0.3, 0.6, 1.0) if dark else Color(0.15, 0.40, 0.90)
	var text_color := Color(1, 1, 1, 0.7) if dark else Color(0.1, 0.1, 0.2, 0.7)

	# Draw edges as bezier curves
	for edge: Array in edges:
		var from: String = edge[0]
		var to: String = edge[1]
		if not layout.has(from) or not layout.has(to):
			continue
		var p1: Vector2 = _to_screen(layout[from], current_pos, scale_factor, center)
		var p2: Vector2 = _to_screen(layout[to], current_pos, scale_factor, center)

		# Skip if both points outside circle
		if p1.distance_to(center) > radius + 20 and p2.distance_to(center) > radius + 20:
			continue

		var key: String = from + "|" + to
		var is_path: bool = path_edges.has(key)
		var ec: Color = path_color if is_path else edge_color
		var ew: float = 2.5 if is_path else 1.0

		# Draw bezier curve
		var mid: Vector2 = (p1 + p2) * 0.5
		var perp: Vector2 = (p2 - p1).orthogonal().normalized() * (p1.distance_to(p2) * 0.15)
		var cp: Vector2 = mid + perp
		_draw_bezier(p1, cp, p2, ec, ew)

	# Draw nodes
	for title: String in layout:
		if not nodes.has(title):
			continue
		var sp: Vector2 = _to_screen(layout[title], current_pos, scale_factor, center)
		if sp.distance_to(center) > radius - NODE_RADIUS:
			continue

		if title == current:
			# Glowing halo
			var pulse: float = 0.5 + 0.5 * sin(_time * 3.0)
			draw_circle(sp, GLOW_RADIUS, Color(current_color, 0.12 + 0.08 * pulse))
			draw_circle(sp, GLOW_RADIUS * 0.7, Color(current_color, 0.08 + 0.06 * pulse))
			draw_circle(sp, NODE_RADIUS, current_color)
			# Room label
			var lbl := _truncate(title, 18)
			draw_string(_font, sp + Vector2(NODE_RADIUS + 5, 4), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, text_color)
		elif nodes[title].visited:
			draw_circle(sp, NODE_RADIUS, visited_color)
		else:
			# Outline ring for unvisited
			draw_arc(sp, NODE_RADIUS, 0, TAU, 16, unvisited_color, 1.5, true)

	# Multiplayer player dots
	if NetworkManager.is_multiplayer_active():
		var local_id: int = NetworkManager.get_unique_id()
		var peers: Array = NetworkManager.get_player_list()
		var idx: int = 0
		for pid: int in peers:
			if pid == local_id:
				continue
			var room: String = NetworkManager.get_player_room(pid)
			if not layout.has(room):
				continue
			var base: Vector2 = _to_screen(layout[room], current_pos, scale_factor, center)
			var angle: float = _time * 1.5 + idx * TAU / maxf(peers.size() - 1, 1)
			var orb: Vector2 = Vector2(cos(angle), sin(angle)) * (NODE_RADIUS + 7)
			var dot: Vector2 = base + orb
			if dot.distance_to(center) < radius - 4.0:
				draw_circle(dot, 4.0, NetworkManager.get_player_color(pid))
			idx += 1

	# Title label
	var title_color := Color(1, 1, 1, 0.35) if dark else Color(0, 0, 0, 0.2)
	draw_string(_font, Vector2(14, 20), "Museum Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, title_color)


func _to_screen(graph_pos: Vector2, cam_center: Vector2, scale_val: float, screen_center: Vector2) -> Vector2:
	return (graph_pos - cam_center) * scale_val + screen_center


func _draw_radial_bg(center: Vector2, radius: float, inner: Color, outer: Color) -> void:
	var steps := 20
	for i in range(steps, 0, -1):
		var t: float = float(i) / float(steps)
		var r: float = radius * t
		var c: Color = inner.lerp(outer, t)
		draw_circle(center, r, c)


func _draw_bezier(p0: Vector2, cp: Vector2, p1: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	var segs := 12
	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var a := p0.lerp(cp, t)
		var b := cp.lerp(p1, t)
		points.append(a.lerp(b, t))
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, width, true)


func _truncate(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.left(max_len - 1) + "…"
