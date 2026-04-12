extends Control
## Renders the exhibit connectivity graph as a persistent HUD element.

const NODE_RADIUS := 6.0
const COLOR_CURRENT := Color(0.024, 0.271, 0.678)  # Wikipedia blue
const COLOR_VISITED := Color(0.420, 0.294, 0.631)  # Wikipedia purple
const COLOR_UNVISITED := Color(0.784, 0.800, 0.820, 0.5)  # Light gray
const COLOR_EDGE := Color(0.635, 0.663, 0.694, 0.6)
const COLOR_PATH := Color(0.024, 0.271, 0.678, 0.8)

var _time: float = 0.0
var _active: bool = false
var _font: Font = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	visible = false
	ExhibitGraph.graph_changed.connect(queue_redraw)
	NetworkManager.player_room_changed.connect(func(_id, _room): queue_redraw())
	_font = ThemeManager.get_reading_font()
	ThemeManager.dark_mode_changed.connect(func(_d): queue_redraw())
	ThemeManager.reading_font_changed.connect(func(f): _font = f; queue_redraw())

func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()

func toggle() -> void:
	_active = !_active
	visible = _active
	queue_redraw()

func show_hud() -> void:
	_active = true
	visible = true
	queue_redraw()

func set_hidden() -> void:
	_active = false
	visible = false

func restore_after_pause() -> void:
	if _active:
		visible = true

func _draw() -> void:
	if not visible:
		return

	var layout: Dictionary = ExhibitGraph.get_layout()
	if layout.is_empty():
		return

	var nodes: Dictionary = ExhibitGraph.get_nodes()
	var edges: Array = ExhibitGraph.get_edges()
	var history: Array[String] = ExhibitGraph.get_visit_history()
	var current: String = ExhibitGraph.get_current_room()

	var map_center: Vector2 = size * 0.5
	var map_radius: float = minf(size.x, size.y) * 0.5
	
	# Draw circular background
	var bg := ThemeManager.bg_color
	bg.a = 0.78 if ThemeManager.is_dark_mode else 0.65
	draw_circle(map_center, map_radius, bg)
	draw_arc(map_center, map_radius, 0, TAU, 64, Color(ThemeManager.border_color, 0.6), 1.5, true)

	# Compute transform from graph space to local screen space
	# Keep the current room centered
	var current_pos: Vector2 = layout.get(current, Vector2.ZERO)
	var graph_bounds := _get_graph_bounds(layout)
	var graph_size: Vector2 = graph_bounds.size
	
	var padding: float = NODE_RADIUS * 3
	var usable_size: Vector2 = size - Vector2(padding * 2, padding * 2)
	
	# We want a consistent scale but enough to see immediate neighbors
	var scale_factor: float = 80.0 

	# Build traversal path set
	var path_edges: Dictionary = {}
	for i: int in range(1, history.size()):
		var key_a: String = history[i - 1] + "|" + history[i]
		var key_b: String = history[i] + "|" + history[i - 1]
		path_edges[key_a] = true
		path_edges[key_b] = true

	# Draw edges
	for edge: Array in edges:
		var from: String = edge[0]
		var to: String = edge[1]
		if not layout.has(from) or not layout.has(to): continue
		
		var p1: Vector2 = _graph_to_screen(layout[from], current_pos, scale_factor, map_center)
		var p2: Vector2 = _graph_to_screen(layout[to], current_pos, scale_factor, map_center)

		var clipped: Array = _clip_line_to_circle(p1, p2, map_center, map_radius)
		if clipped.is_empty(): continue
		
		var key: String = from + "|" + to
		var is_path: bool = path_edges.has(key)
		var edge_color: Color = COLOR_PATH if is_path else Color(ThemeManager.border_color, 0.7)
		var edge_width: float = 3.0 if is_path else 1.5
		draw_line(clipped[0], clipped[1], edge_color, edge_width, true)

	# Draw nodes
	for title: String in layout:
		if not nodes.has(title): continue
		var screen_pos: Vector2 = _graph_to_screen(layout[title], current_pos, scale_factor, map_center)

		if screen_pos.distance_to(map_center) > map_radius - NODE_RADIUS:
			continue

		var color: Color
		if title == current:
			var pulse: float = 0.7 + 0.3 * sin(_time * 3.0)
			color = COLOR_CURRENT
			color.a = pulse
		elif nodes[title].visited:
			color = COLOR_VISITED
		else:
			color = COLOR_UNVISITED

		draw_circle(screen_pos, NODE_RADIUS, color)
		
		# Label for current room
		if title == current:
			var label_text: String = _truncate(title, 20)
			var label_pos: Vector2 = screen_pos + Vector2(NODE_RADIUS + 4, 5)
			draw_string(_font, label_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_CURRENT)

	# Draw player dots
	if NetworkManager.is_multiplayer_active():
		var local_id: int = NetworkManager.get_unique_id()
		var player_list: Array = NetworkManager.get_player_list()
		var peer_index: int = 0
		for peer_id: int in player_list:
			if peer_id == local_id: continue
			var room: String = NetworkManager.get_player_room(peer_id)
			if not layout.has(room): continue
			
			var base_pos: Vector2 = _graph_to_screen(layout[room], current_pos, scale_factor, map_center)
			var orbit_angle: float = _time * 1.5 + peer_index * TAU / maxf(player_list.size() - 1, 1)
			var orbit_offset: Vector2 = Vector2(cos(orbit_angle), sin(orbit_angle)) * (NODE_RADIUS + 6)
			var dot_pos: Vector2 = base_pos + orbit_offset
			
			if dot_pos.distance_to(map_center) < map_radius - 4.0:
				draw_circle(dot_pos, 4.0, NetworkManager.get_player_color(peer_id))
			peer_index += 1

	# (Border is drawn near the start so it frames everything.)

func _graph_to_screen(graph_pos: Vector2, camera_center: Vector2, scale_val: float, screen_center: Vector2) -> Vector2:
	return (graph_pos - camera_center) * scale_val + screen_center

func _get_graph_bounds(layout: Dictionary) -> Rect2:
	if layout.is_empty(): return Rect2(Vector2.ZERO, Vector2.ONE)
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for pos: Vector2 in layout.values():
		min_pos = min_pos.min(pos)
		max_pos = max_pos.max(pos)
	return Rect2(min_pos, max_pos - min_pos)

func _clip_line_to_circle(p1: Vector2, p2: Vector2, center: Vector2, radius: float) -> Array:
	var d1: float = p1.distance_to(center)
	var d2: float = p2.distance_to(center)
	if d1 <= radius and d2 <= radius: return [p1, p2]
	var dir: Vector2 = p2 - p1
	var f: Vector2 = p1 - center
	var a: float = dir.dot(dir)
	var b: float = 2.0 * f.dot(dir)
	var c: float = f.dot(f) - radius * radius
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0: return []
	var sqrt_disc: float = sqrt(discriminant)
	var t1: float = (-b - sqrt_disc) / (2.0 * a)
	var t2: float = (-b + sqrt_disc) / (2.0 * a)
	var enter: float = maxf(t1, 0.0)
	var exit_t: float = minf(t2, 1.0)
	if enter > exit_t: return []
	return [p1 + dir * enter, p1 + dir * exit_t]

func _truncate(text: String, max_len: int) -> String:
	if text.length() <= max_len: return text
	return text.left(max_len - 1) + "..."
