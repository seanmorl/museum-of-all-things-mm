extends Control
## Redesigned minimap — three display modes with rich navigation info.
##
## M key cycles: OFF → COMPACT → EXPANDED → OFF
##
## COMPACT:  Small corner panel — current room, exits, player direction, distance to target.
## EXPANDED: Larger panel — full exhibit graph, BFS shortest path highlighted,
##           room labels, player arrow, distance readout.
##
## Visual design mirrors the "Orrery" main-menu background — orbital-themed
## graph nodes with pulsing accents.  Theme-aware (dark/light).  Accessible:
## font sizes respect accessibility settings, high-contrast mode supported.

enum Mode { OFF, COMPACT, EXPANDED }

# ── Layout constants ───────────────────────────────────────────────────────────

const COMPACT_W: float = 220.0
const COMPACT_H: float = 180.0
const EXPANDED_W: float = 360.0
const EXPANDED_H: float = 320.0
const MARGIN: float = 16.0
const NODE_RADIUS: float = 4.0
const NODE_RADIUS_CURRENT: float = 6.0
const NODE_RADIUS_TARGET: float = 5.0
const PULSE_SPEED: float = 3.0
const ARROW_SIZE: float = 8.0

# ── State ──────────────────────────────────────────────────────────────────────

var _mode: Mode = Mode.OFF
var _player: Node3D = null
var _current_room: String = "Lobby"
var _fade_tw: Tween = null
var _pulse_time: float = 0.0
var _player_yaw: float = 0.0
var _large_hud: bool = false

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        visible = false
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        SettingsEvents.set_current_room.connect(_on_room_changed)
        ExhibitGraph.graph_changed.connect(queue_redraw)
        # Accessibility
        if SettingsEvents.has_signal("accessibility_changed"):
                SettingsEvents.accessibility_changed.connect(_on_accessibility_changed)
        _load_accessibility()


func init(player: Node3D) -> void:
        _player = player


func cycle_mode() -> void:
        var prev := _mode
        match _mode:
                Mode.OFF:     _mode = Mode.COMPACT
                Mode.COMPACT: _mode = Mode.EXPANDED
                Mode.EXPANDED: _mode = Mode.OFF
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


func _on_accessibility_changed(key: String, value: Variant) -> void:
        if key == "large_hud_text":
                _large_hud = value
                queue_redraw()


func _load_accessibility() -> void:
        var saved: Dictionary = SettingsManager.get_settings("accessibility") \
                if SettingsManager.get_settings("accessibility") else {}
        _large_hud = saved.get("large_hud_text", false)


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
        if _mode == Mode.OFF:
                return
        _pulse_time += delta
        # Track player facing direction
        if _player and is_instance_valid(_player):
                _player_yaw = _player.rotation.y
        queue_redraw()


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Drawing                                                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _draw() -> void:
        if _mode == Mode.OFF or not _player:
                return

        var dark := ThemeManager.is_dark_mode
        var hc := _large_hud  # high-contrast / large text mode

        # ── Colour palette ────────────────────────────────────────────────────
        var bg: Color = Color(0.04, 0.05, 0.09, 0.92) if dark else Color(1.0, 1.0, 1.0, 0.90)
        var border: Color = Color(1, 1, 1, 0.10) if dark else Color(0, 0, 0, 0.08)
        var text_col: Color = Color(0.94, 0.93, 0.91) if dark else Color(0.1, 0.09, 0.08)
        var sub_col: Color = Color(0.66, 0.64, 0.61) if dark else Color(0.35, 0.34, 0.31)
        var accent: Color = Color(0.30, 0.55, 0.95)
        var gold: Color = Color(1.0, 0.84, 0.0)
        var path_col: Color = Color(0.20, 0.70, 0.55) if not hc else Color(0.10, 0.90, 0.60)
        var edge_col: Color = Color(sub_col, 0.25) if not hc else Color(sub_col, 0.55)
        var dim_edge_col: Color = Color(sub_col, 0.10) if not hc else Color(sub_col, 0.25)

        # Font sizes scale with accessibility
        var font: Font = ThemeManager.get_reading_font()
        var title_size: int = 13 if not _large_hud else 16
        var label_size: int = 8 if not _large_hud else 10
        var info_size: int = 9 if not _large_hud else 11
        var mode_label_size: int = 7 if not _large_hud else 9

        # ── Panel dimensions ──────────────────────────────────────────────────
        var is_expanded := _mode == Mode.EXPANDED
        var pw: float = EXPANDED_W if is_expanded else COMPACT_W
        var ph: float = EXPANDED_H if is_expanded else COMPACT_H
        if _large_hud:
                pw *= 1.15;  ph *= 1.15

        var vp := get_viewport_rect().size
        var px: float = vp.x - pw - MARGIN
        var py: float = vp.y - ph - MARGIN
        var panel_rect := Rect2(px, py, pw, ph)

        # ── Panel background ──────────────────────────────────────────────────
        draw_rect(panel_rect, bg, true)
        draw_rect(panel_rect, border, false, 1.0)

        # ── Data sources ──────────────────────────────────────────────────────
        var layout: Dictionary = ExhibitGraph.get_layout()
        var nodes: Dictionary = ExhibitGraph.get_nodes()
        var edges: Array = ExhibitGraph.get_edges()
        var target: String = ""
        if RaceManager and RaceManager.has_method("get_target_article"):
                target = RaceManager.get_target_article()

        # BFS shortest path from current room to target
        var path: Array = []  # ordered list of room names
        if target != "" and target != _current_room:
                path = _bfs_path(_current_room, target, edges)

        # ── Graph centre & scale ──────────────────────────────────────────────
        var graph_cx: float = px + pw * 0.5
        var graph_cy: float = py + ph * 0.5 + 18.0
        var graph_r: float = (min(pw, ph) * 0.38) if is_expanded else 55.0

        # In compact mode, current room is always at centre.
        # In expanded mode, we show the full graph with the current room highlighted.
        var current_pos: Vector2 = Vector2(graph_cx, graph_cy)

        # ── Compute screen positions for all visible nodes ────────────────────
        var screen_pos: Dictionary = {}  # room_name -> Vector2

        if is_expanded:
                # Expanded: lay out all nodes using ExhibitGraph layout, scaled to fit
                var bounds := _compute_layout_bounds(layout)
                var scale: float = min(pw * 0.7 / maxf(bounds.size.x, 1.0), (ph - 60.0) * 0.7 / maxf(bounds.size.y, 1.0))
                scale = minf(scale, graph_r * 2.0 / maxf(maxf(bounds.size.x, bounds.size.y), 1.0))
                for title: String in layout:
                        var pos: Variant = layout[title]
                        if pos == null:
                                continue
                        var sx: float = graph_cx + (pos.x - bounds.center.x) * scale
                        var sy: float = graph_cy + (pos.y - bounds.center.y) * scale
                        screen_pos[title] = Vector2(sx, sy)
                # Override current room to be at its graph position
                if screen_pos.has(_current_room):
                        current_pos = screen_pos[_current_room]
        else:
                # Compact: current room at centre, neighbours placed radially
                screen_pos[_current_room] = current_pos
                for edge in edges:
                        var from: String = edge[0]
                        var to: String = edge[1]
                        var other: String = to if from == _current_room else from
                        if from != _current_room and to != _current_room:
                                continue
                        var other_p: Variant = layout.get(other)
                        if other_p == null:
                                continue
                        var dir: Vector2 = Vector2(other_p.x, other_p.y).normalized() \
                                if Vector2(other_p.x, other_p.y).length_squared() > 0.001 else Vector2.UP
                        screen_pos[other] = current_pos + dir * graph_r

        # ── Draw edges ────────────────────────────────────────────────────────
        # First pass: dim edges (not on path)
        for edge in edges:
                var from: String = edge[0]
                var to: String = edge[1]
                var fp: Variant = screen_pos.get(from)
                var tp: Variant = screen_pos.get(to)
                if fp == null or tp == null:
                        continue
                # Check if this edge is on the path
                var on_path: bool = _edge_on_path(from, to, path)
                if on_path:
                        continue  # drawn in second pass
                if not is_expanded and from != _current_room and to != _current_room:
                        continue
                draw_line(fp, tp, dim_edge_col, 1.0, true)

        # Second pass: path edges (highlighted)
        if path.size() >= 2:
                for i in range(path.size() - 1):
                        var fp: Variant = screen_pos.get(path[i])
                        var tp: Variant = screen_pos.get(path[i + 1])
                        if fp == null or tp == null:
                                continue
                        draw_line(fp, tp, Color(path_col, 0.7), 2.5 if not hc else 3.5, true)
                        # Direction chevrons along path
                        _draw_path_chevrons(fp, tp, path_col, 0.4)

        # ── Draw nodes ────────────────────────────────────────────────────────
        for title: String in screen_pos:
                var np: Vector2 = screen_pos[title]
                var is_current: bool = title == _current_room
                var is_target: bool = title == target
                var on_path: bool = title in path

                var col: Color = gold if is_target else (accent if is_current else (path_col if on_path else sub_col))
                var alpha: float = 1.0 if (is_current or is_target or on_path) else (0.6 if is_expanded else 0.4)
                var nr: float = NODE_RADIUS_CURRENT if is_current else (NODE_RADIUS_TARGET if is_target else NODE_RADIUS)

                # Pulse for current room
                if is_current:
                        var pulse: float = sin(_pulse_time * PULSE_SPEED) * 0.5 + 0.5
                        draw_circle(np, nr + 8.0 + pulse * 3.0, Color(col, 0.10))
                        draw_circle(np, nr + 4.0 + pulse * 2.0, Color(col, 0.15))

                # Glow for target
                if is_target:
                        var pulse: float = sin(_pulse_time * PULSE_SPEED * 1.2) * 0.5 + 0.5
                        draw_circle(np, nr + 6.0 + pulse * 2.0, Color(col, 0.12))

                draw_circle(np, nr, Color(col, alpha))

                # Room labels (expanded mode only, or for current/target in compact)
                if is_expanded or is_current or is_target:
                        var lbl: String = title
                        var max_len: int = 14 if is_expanded else 18
                        if lbl.length() > max_len:
                                lbl = lbl.left(max_len - 2) + ".."
                        var lbl_alpha: float = 0.85 if (is_current or is_target or on_path) else 0.5
                        var lbl_col: Color = Color(col, lbl_alpha) if (is_current or is_target) else Color(sub_col, lbl_alpha)
                        var font_sz: int = label_size if not is_current else (label_size + 1)
                        draw_string(font, np + Vector2(nr + 3.0, 3.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, lbl_col)

        # ── Player direction arrow ────────────────────────────────────────────
        _draw_direction_arrow(current_pos, _player_yaw, accent, 0.8)

        # ── Exit indicators (physical exits from current room) ────────────────
        var museum := _find_museum()
        var exits: Array = _get_exits(museum)
        for hall in exits:
                if not is_instance_valid(hall):
                        continue
                var dp := Vector2.ZERO
                if hall.has_method("get_global_position") or "global_position" in hall:
                        var hp: Vector3 = hall.global_position
                        var pp: Vector3 = _player.global_position
                        dp = Vector2(hp.x - pp.x, hp.z - pp.z)
                var dir: Vector2 = dp.normalized() if dp.length_squared() > 0.001 else Vector2.ZERO
                var ep: Vector2 = current_pos + dir * (graph_r + 10.0)
                var is_target_exit: bool = target != "" and hall.has_method("get") and hall.get("to_title") == target
                var ecol: Color = gold if is_target_exit else accent
                draw_circle(ep, 2.5, Color(ecol, 0.6))
                # Exit label
                var title_label: String = ""
                if "to_title" in hall:
                        title_label = str(hall.to_title)
                        if title_label.length() > 14:
                                title_label = title_label.left(12) + ".."
                if title_label != "":
                        var lbl_col: Color = Color(gold, 0.7) if is_target_exit else Color(sub_col, 0.5)
                        draw_string(font, ep + dir * 6.0, title_label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, lbl_col)

        # ── Header: room name ─────────────────────────────────────────────────
        var title_text: String = _current_room
        if title_text.length() > 22:
                title_text = title_text.left(20) + ".."
        draw_string(font, Vector2(px + 12, py + 20), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, text_col)

        # ── Target info ───────────────────────────────────────────────────────
        if target != "" and target != _current_room:
                var tgt_text: String = "→ " + target
                if tgt_text.length() > 26:
                        tgt_text = tgt_text.left(24) + ".."
                draw_string(font, Vector2(px + 12, py + 36), tgt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, info_size, gold)

                # Hop count
                var hops: int = path.size() - 1 if path.size() > 1 else _count_hops(target)
                if hops > 0:
                        draw_string(font, Vector2(px + pw - 12, py + 20), str(hops) + " hops", HORIZONTAL_ALIGNMENT_RIGHT, -1, info_size, sub_col)

        # ── Mode label ────────────────────────────────────────────────────────
        var mode_text: String = "COMPACT" if _mode == Mode.COMPACT else "EXPANDED"
        draw_string(font, Vector2(px + 12, py + ph - 8), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, mode_label_size, Color(sub_col, 0.5))

        # ── Compass hint (expanded only) ──────────────────────────────────────
        if is_expanded:
                draw_string(font, Vector2(px + pw - 12, py + ph - 8), "M to cycle", HORIZONTAL_ALIGNMENT_RIGHT, -1, mode_label_size, Color(sub_col, 0.35))


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Drawing helpers                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _draw_direction_arrow(pos: Vector2, yaw: float, col: Color, alpha: float) -> void:
        # Draws a small triangle arrow pointing in the player's facing direction.
        # yaw is the Y rotation in radians; in Godot's top-down view, -yaw maps
        # to screen rotation because +Z is "into screen" and +Y rotation is CCW.
        var screen_angle: float = -yaw - PI * 0.5  # rotate so 0 = up
        var tip: Vector2 = pos + Vector2(cos(screen_angle), sin(screen_angle)) * 14.0
        var left: Vector2 = pos + Vector2(cos(screen_angle + 2.4), sin(screen_angle + 2.4)) * 7.0
        var right: Vector2 = pos + Vector2(cos(screen_angle - 2.4), sin(screen_angle - 2.4)) * 7.0
        var pts := PackedVector2Array([tip, left, right])
        draw_colored_polygon(pts, Color(col, alpha))


func _draw_path_chevrons(from: Vector2, to: Vector2, col: Color, alpha: float) -> void:
        # Draw small directional chevrons along a path segment.
        var dir: Vector2 = (to - from).normalized()
        var length: float = from.distance_to(to)
        if length < 30.0:
                return  # too short for chevrons
        var perp := Vector2(-dir.y, dir.x)
        var count: int = int(length / 25.0)
        for i in range(count):
                var t: float = (float(i) + 0.5) / float(count)
                var centre: Vector2 = from.lerp(to, t)
                var size: float = 3.0
                var p1: Vector2 = centre - dir * size + perp * size * 0.6
                var p2: Vector2 = centre + dir * size
                var p3: Vector2 = centre - dir * size - perp * size * 0.6
                draw_line(p1, p2, Color(col, alpha), 1.0, true)
                draw_line(p2, p3, Color(col, alpha), 1.0, true)


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  BFS pathfinding                                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _bfs_path(from_room: String, to_room: String, edges: Array) -> Array:
        # Returns an ordered Array of room names representing the shortest path,
        # or an empty Array if no path exists.
        if from_room == to_room:
                return [from_room]

        # Build adjacency list
        var adj: Dictionary = {}  # room -> Array of connected rooms
        for edge in edges:
                var a: String = edge[0]
                var b: String = edge[1]
                if not adj.has(a):
                        adj[a] = []
                if not adj.has(b):
                        adj[b] = []
                adj[a].append(b)
                adj[b].append(a)

        if not adj.has(from_room) or not adj.has(to_room):
                return []

        # BFS
        var queue: Array = [from_room]
        var visited: Dictionary = { from_room: true }
        var parent: Dictionary = {}  # child -> parent

        while queue.size() > 0:
                var current: String = queue.pop_front()
                if current == to_room:
                        break
                if not adj.has(current):
                        continue
                for neighbour: String in adj[current]:
                        if visited.has(neighbour):
                                continue
                        visited[neighbour] = true
                        parent[neighbour] = current
                        queue.append(neighbour)

        # Reconstruct path
        if not parent.has(to_room) and from_room != to_room:
                # No path found — but maybe they're directly connected and BFS skipped?
                # Check adjacency
                if adj.has(from_room) and to_room in adj[from_room]:
                        return [from_room, to_room]
                return []

        var result: Array = [to_room]
        var step: String = to_room
        while parent.has(step):
                step = parent[step]
                result.append(step)
        result.reverse()
        return result


func _edge_on_path(from: String, to: String, path: Array) -> bool:
        # Check if an edge (undirected) is part of the given path.
        if path.size() < 2:
                return false
        for i in range(path.size() - 1):
                if (path[i] == from and path[i + 1] == to) or (path[i] == to and path[i + 1] == from):
                        return true
        return false


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Layout helpers                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

class _LayoutBounds:
        var min_x: float = 0.0
        var min_y: float = 0.0
        var max_x: float = 0.0
        var max_y: float = 0.0
        var size: Vector2 = Vector2.ZERO
        var center: Vector2 = Vector2.ZERO

func _compute_layout_bounds(layout: Dictionary) -> _LayoutBounds:
        var b := _LayoutBounds.new()
        var first := true
        for title: String in layout:
                var pos: Variant = layout[title]
                if pos == null:
                        continue
                if first:
                        b.min_x = pos.x; b.max_x = pos.x
                        b.min_y = pos.y; b.max_y = pos.y
                        first = false
                else:
                        b.min_x = minf(b.min_x, pos.x)
                        b.max_x = maxf(b.max_x, pos.x)
                        b.min_y = minf(b.min_y, pos.y)
                        b.max_y = maxf(b.max_y, pos.y)
        b.size = Vector2(b.max_x - b.min_x, b.max_y - b.min_y)
        b.center = Vector2((b.min_x + b.max_x) * 0.5, (b.min_y + b.max_y) * 0.5)
        return b


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Museum / exit helpers (same interface as original)                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

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
        if pos == null or pos.length_squared() < 0.001:
                return 0
        return maxi(1, int(pos.length()))
