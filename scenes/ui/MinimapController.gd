extends Control
## Single clean minimap — replaces all old minimap variants.
## M key toggles OFF -> MINIMAP -> OFF.
## Shows a compact radial graph of the current exhibit and nearby exits.

enum Mode { OFF, MINIMAP }

var _mode: Mode = Mode.OFF
var _player: Node3D = null
var _current_room: String = "Lobby"
var _fade_tw: Tween = null
var _pulse_time: float = 0.0

const PANEL_W: float = 240.0
const PANEL_H: float = 280.0
const MARGIN: float = 16.0
const NODE_RADIUS: float = 4.0
const PULSE_RADIUS: float = 12.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SettingsEvents.set_current_room.connect(_on_room_changed)
	ExhibitGraph.graph_changed.connect(queue_redraw)

func init(player: Node3D) -> void:
	_player = player

func cycle_mode() -> void:
	var prev := _mode
	_mode = Mode.OFF if _mode == Mode.MINIMAP else Mode.MINIMAP
	_apply_mode(prev, _mode)

func toggle() -> void:
	cycle_mode()

func save_mode() -> Mode:
	return _mode

func restore_mode(saved: Mode) -> void:
	var prev := _mode
	_mode = saved
	_apply_mode(prev, _mode)

func set_current_room(room: String) -> void:
	_current_room = room
	queue_redraw()

func _on_room_changed(room: Variant) -> void:
	_current_room = str(room)
	queue_redraw()

func _apply_mode(prev: Mode, next: Mode) -> void:
	if _fade_tw and _fade_tw.is_valid():
		_fade_tw.kill()
	if next == Mode.OFF:
		_fade_tw = create_tween()
		_fade_tw.tween_property(self, "modulate:a", 0.0, 0.15)
		_fade_tw.tween_callback(func(): visible = false)
	else:
		modulate.a = 0.0
		visible = true
		_fade_tw = create_tween()
		_fade_tw.tween_property(self, "modulate:a", 1.0, 0.2)
	queue_redraw()

func _process(delta: float) -> void:
	if _mode != Mode.MINIMAP:
		return
	_pulse_time += delta
	queue_redraw()

func _draw() -> void:
	if _mode != Mode.MINIMAP or not _player:
		return
	var dark := ThemeManager.is_dark_mode
	var bg := Color(0.06, 0.06, 0.08, 0.88) if dark else Color(1, 1, 1, 0.85)
	var border := Color(1, 1, 1, 0.08) if dark else Color(0, 0, 0, 0.06)
	var text_col := Color(0.94, 0.93, 0.91) if dark else Color(0.1, 0.09, 0.08)
	var sub_col := Color(0.66, 0.64, 0.61) if dark else Color(0.35, 0.34, 0.31)
	var accent := Color(0.3, 0.55, 0.95)
	var gold := Color(1.0, 0.84, 0.0)

	var vp := get_viewport_rect().size
	var px := vp.x - PANEL_W - MARGIN
	var py := vp.y - PANEL_H - MARGIN
	var r := Rect2(px, py, PANEL_W, PANEL_H)

	draw_rect(r, bg)
	draw_rect(r, border, false, 1.0)

	var cx := px + PANEL_W * 0.5
	var cy := py + PANEL_H * 0.5 + 30.0
	var graph_r := 70.0

	var museum := _find_museum()
	var exits: Array = _get_exits(museum)
	var layout: Dictionary = ExhibitGraph.get_layout()
	var nodes: Dictionary = ExhibitGraph.get_nodes()
	var target: String = ""
	if RaceManager and RaceManager.has_method("get_target_article"):
		target = RaceManager.get_target_article()

	var current_pos: Vector2 = Vector2(cx, cy)

	for edge in ExhibitGraph.get_edges():
		var from: String = edge[0]
		var to: String = edge[1]
		var from_p: Variant = layout.get(from)
		var to_p: Variant = layout.get(to)
		if from_p == null or to_p == null:
			continue
		var centered := from == _current_room or to == _current_room
		if not centered:
			continue
		var other_p: Variant = to_p if from == _current_room else from_p
		var dir := Vector2(other_p.x, other_p.y).normalized() if other_p.length_squared() > 0.001 else Vector2.ZERO
		var ep := current_pos + dir * graph_r
		draw_line(current_pos, ep, Color(sub_col, 0.3), 1.0)

	for edge in ExhibitGraph.get_edges():
		var from: String = edge[0]
		var to: String = edge[1]
		var from_p: Variant = layout.get(from)
		var to_p: Variant = layout.get(to)
		if from_p == null or to_p == null:
			continue
		if from == _current_room or to == _current_room:
			continue
		draw_line(
			Vector2(cx + from_p.x * 0.4, cy + from_p.y * 0.4),
			Vector2(cx + to_p.x * 0.4, cy + to_p.y * 0.4),
			Color(sub_col, 0.12), 0.5
		)

	for title: String in nodes:
		var pos: Variant = layout.get(title)
		if pos == null:
			continue
		var np := current_pos + Vector2(pos.x, pos.y) * 0.4
		if (np - current_pos).length() > 80.0:
			continue
		var is_current := title == _current_room
		var is_target := title == target
		var col := gold if is_target else (accent if is_current else sub_col)
		var alpha := 1.0 if (is_current or is_target) else 0.5
		var nr := NODE_RADIUS * 1.5 if is_current else NODE_RADIUS
		if is_current:
			var pulse := sin(_pulse_time * 3.0) * 0.5 + 0.5
			draw_circle(np, PULSE_RADIUS + pulse * 3.0, Color(col, 0.12))
		draw_circle(np, nr, Color(col, alpha))

	draw_circle(current_pos, NODE_RADIUS * 2.0, accent)
	var pulse2 := sin(_pulse_time * 3.0) * 0.5 + 0.5
	draw_circle(current_pos, PULSE_RADIUS + pulse2 * 3.0, Color(accent, 0.15))

	for hall in exits:
		if not is_instance_valid(hall):
			continue
		var dp := Vector2.ZERO
		if hall.has_method("get_global_position") or "global_position" in hall:
			var hp: Vector3 = hall.global_position
			var pp: Vector3 = _player.global_position
			dp = Vector2(hp.x - pp.x, hp.z - pp.z)
		var dir := dp.normalized() if dp.length_squared() > 0.001 else Vector2.ZERO
		var ep := current_pos + dir * graph_r
		var is_target_exit: bool = target != "" and hall.has_method("get") and hall.get("to_title") == target
		var col := gold if is_target_exit else accent
		draw_circle(ep, 3.0, Color(col, 0.7))
		var title_label: String = ""
		if "to_title" in hall:
			title_label = str(hall.to_title)
			if title_label.length() > 18:
				title_label = title_label.left(16) + ".."
		if title_label != "":
			var lbl_pos := ep + dir * 10.0
			var label_col := Color(gold, 0.8) if is_target_exit else Color(sub_col, 0.6)
			draw_string(ThemeManager.get_reading_font(), lbl_pos, title_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, label_col)

	var title_text: String = _current_room
	if title_text.length() > 22:
		title_text = title_text.left(20) + ".."
	draw_string(ThemeManager.get_reading_font(), Vector2(px + 14, py + 22), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)

	if target != "" and target != _current_room:
		var tgt_text := "→ " + target
		if tgt_text.length() > 24:
			tgt_text = tgt_text.left(22) + ".."
		draw_string(ThemeManager.get_reading_font(), Vector2(px + 14, py + 38), tgt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, gold)

	var mode_text := "MINIMAP"
	draw_string(ThemeManager.get_reading_font(), Vector2(px + 14, py + PANEL_H - 10), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, sub_col)

	if target != "":
		var hops := _count_hops(target)
		if hops > 0:
			draw_string(ThemeManager.get_reading_font(), Vector2(px + PANEL_W - 14, py + 22), str(hops) + " hops", HORIZONTAL_ALIGNMENT_RIGHT, -1, 8, sub_col)

func _find_museum() -> Node:
	var scene := get_tree().current_scene
	if not scene:
		return null
	return scene.get_node_or_null("%Museum")

func _get_exits(museum: Node) -> Array:
	if not museum:
		return []
	var exhibits: Dictionary = {}
	if "get_exhibits" in museum:
		exhibits = museum.get_exhibits()
	elif "_exhibits" in museum:
		exhibits = museum._exhibits
	if not exhibits.has(_current_room):
		return []
	var data = exhibits[_current_room]
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var exhibit: Node = data.get("exhibit")
	if not is_instance_valid(exhibit) or not "exits" in exhibit:
		return []
	return exhibit.exits

func _count_hops(target: String) -> int:
	var layout: Dictionary = ExhibitGraph.get_layout()
	if not layout.has(target):
		return 0
	var pos: Variant = layout[target]
	if pos.length_squared() < 0.001:
		return 0
	return maxi(1, int(pos.length()))
