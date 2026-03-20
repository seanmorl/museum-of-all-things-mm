extends Control
## BaseParchmentMap — Unified parchment view for all minimap modes.
## 
## Consistency-first design: everything renders on the same aged paper.

enum MapMode { MAP_2D, MAP_3D, GRAPH }

const PARCHMENT_BG   := Color(0.91, 0.85, 0.72)
const PARCHMENT_DARK := Color(0.78, 0.72, 0.58)
const BORDER_INK     := Color(0.45, 0.36, 0.24)
const INK            := Color(0.28, 0.22, 0.16)
const INK_HIGHLIGHT  := Color(0.30, 0.55, 1.00)
const SEPIA          := Color(0.60, 0.45, 0.25, 1.0)

# Graph constants
const NODE_R_IDLE : float = 4.5
const NODE_R_CUR  : float = 6.5
const SPACING     : float = 38.0
const LABEL_MAX   : int   = 15

var _mode : MapMode = MapMode.MAP_2D
var _player : Node3D  = null
var _texture_rect : TextureRect = null
var _overlay : Control = null
var _zoom_level : float = 1.0
var _serif_font : Font = null

# WikiGraph state
var _nodes : Dictionary = {} # title → { pos: Vector2, connections: Array[String] }
var _prev_room : String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_serif_font = ThemeManager.get_reading_font()
	if not _serif_font: _serif_font = ThemeDB.fallback_font

	# Layout mirroring original minimap
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -270.0; offset_top = -270.0
	offset_right = -20.0; offset_bottom = -20.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	clip_contents = true

	# Paper background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = PARCHMENT_BG
	add_child(bg)

	# 3D Viewport Texture
	_texture_rect = TextureRect.new()
	_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texture_rect.offset_left = 14; _texture_rect.offset_top = 14
	_texture_rect.offset_right = -14; _texture_rect.offset_bottom = -28
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_texture_rect.modulate = SEPIA
	add_child(_texture_rect)

	# Drawing Overlay
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_on_overlay_draw)
	add_child(_overlay)

	ThemeManager.reading_font_changed.connect(func(f):
		_serif_font = f if f else ThemeDB.fallback_font
		_overlay.queue_redraw()
	)

func init(player: Node3D) -> void:
	_player = player

func set_mode(m: int) -> void:
	_mode = m as MapMode
	_texture_rect.visible = (_mode != MapMode.GRAPH)
	_overlay.queue_redraw()

func update_texture(tex: Texture2D) -> void:
	if _texture_rect and tex:
		_texture_rect.texture = tex

func set_zoom(level: float) -> void:
	_zoom_level = level
	_overlay.queue_redraw()

func _process(_delta: float) -> void:
	if not visible: return
	
	# Track room changes for graph mode even when not visible? 
	# (Better to keep it updated so it works immediately upon switching)
	var cur := _get_current_room()
	if cur != "" and cur != _prev_room:
		_on_room_changed(cur)
		_prev_room = cur
	
	_overlay.queue_redraw()

func _on_overlay_draw() -> void:
	var s := size
	var m := 4.0
	var is_graph := (_mode == MapMode.GRAPH)

	# ── Paper grain ───────────────────────────────────────────────────────────
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for y in range(0, int(s.y), 3):
		_overlay.draw_line(Vector2(0, y), Vector2(s.x, y),
			Color(0.5, 0.4, 0.3, rng.randf_range(0.04, 0.10)), 1.0)

	# ── Corner vignette ───────────────────────────────────────────────────────
	var vc := Color(0.35, 0.25, 0.15, 0.18)
	var vr := 60.0
	_overlay.draw_arc(Vector2(0, 0),    vr, 0.0,    PI*0.5, 16, vc, vr*0.5, true)
	_overlay.draw_arc(Vector2(s.x, 0),  vr, PI*0.5, PI,     16, vc, vr*0.5, true)
	_overlay.draw_arc(Vector2(s.x, s.y),vr, PI,     PI*1.5, 16, vc, vr*0.5, true)
	_overlay.draw_arc(Vector2(0, s.y),  vr, PI*1.5, TAU,    16, vc, vr*0.5, true)

	# ── Borders ───────────────────────────────────────────────────────────────
	_overlay.draw_rect(Rect2(Vector2(m, m), s - Vector2(m*2, m*2)), BORDER_INK, false, 2.0)
	_overlay.draw_rect(Rect2(Vector2(m+5, m+5), s - Vector2((m+5)*2, (m+5)*2)), Color(BORDER_INK, 0.65), false, 1.0)
	
	# Mini diamonds in corners
	for c : Vector2 in [Vector2(m+2,m+2), Vector2(s.x-m-2,m+2), Vector2(m+2,s.y-m-2), Vector2(s.x-m-2,s.y-m-2)]:
		_draw_diamond(c, 5.0, BORDER_INK)

	# ── Content Drawing ───────────────────────────────────────────────────────
	if is_graph:
		_draw_wiki_graph()
	else:
		_draw_map_elements()

	# ── Bottom bar ────────────────────────────────────────────────────────────
	var bar_y := s.y - 28.0
	_overlay.draw_rect(Rect2(m+1, bar_y, s.x-(m+1)*2, 24), Color(PARCHMENT_DARK, 0.85))
	_overlay.draw_line(Vector2(m+1, bar_y), Vector2(s.x-m-1, bar_y), BORDER_INK, 1.0)

	var room_name := _get_current_room()
	if room_name == "": room_name = "Lobby"
	if room_name.length() > 22: room_name = room_name.substr(0, 21) + "…"
	
	if _serif_font:
		_overlay.draw_string(_serif_font, Vector2(m+12, bar_y+17), room_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
		var mode_label : String = ["MAP", "3D", "WEB"][_mode as int]
		_overlay.draw_string(_serif_font, Vector2(s.x-m-70, bar_y+17), 
			"%s  %d%%" % [mode_label, int(_zoom_level * 100)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(INK, 0.60))

func _draw_map_elements() -> void:
	var s := size
	var angle := _get_player_angle()
	
	# Compass Rose (top-right)
	var cx := s.x - 38.0
	var cy := 38.0
	var cr := 16.0
	_overlay.draw_circle(Vector2(cx, cy), cr + 4, Color(PARCHMENT_BG, 0.85))
	_overlay.draw_arc(Vector2(cx, cy), cr, 0.0, TAU, 24, Color(BORDER_INK, 0.55), 1.0)
	_overlay.draw_line(Vector2(cx, cy-cr), Vector2(cx, cy+cr), BORDER_INK, 1.5)
	_overlay.draw_line(Vector2(cx-cr, cy), Vector2(cx+cr, cy), BORDER_INK, 1.5)
	if _serif_font:
		_overlay.draw_string(_serif_font, Vector2(cx-4, cy-cr-5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.12, 0.08))
	
	var ntip := Vector2(cx + sin(angle)*(cr-3), cy - cos(angle)*(cr-3))
	var nl   := Vector2(cx + sin(angle+2.4)*4,  cy - cos(angle+2.4)*4)
	var nr   := Vector2(cx + sin(angle-2.4)*4,  cy - cos(angle-2.4)*4)
	_overlay.draw_colored_polygon(PackedVector2Array([ntip, nl, nr]), Color(0.65, 0.12, 0.08))

	# Player Arrow (centre)
	var centre := Vector2(s.x*0.5, (s.y-28.0)*0.5 + 14.0)
	var ar := 10.0
	var tip    := centre + Vector2(sin(angle), -cos(angle)) * ar * 1.5
	var left   := centre + Vector2(sin(angle+2.2), -cos(angle+2.2)) * ar
	var right  := centre + Vector2(sin(angle-2.2), -cos(angle-2.2)) * ar
	var back   := centre + Vector2(sin(angle+PI), -cos(angle+PI)) * ar * 0.4
	_overlay.draw_colored_polygon(PackedVector2Array([tip+Vector2(1,1), left+Vector2(1,1), back+Vector2(1,1), right+Vector2(1,1)]), Color(PARCHMENT_DARK, 0.55))
	_overlay.draw_colored_polygon(PackedVector2Array([tip, left, back, right]), INK)

func _draw_wiki_graph() -> void:
	if _nodes.is_empty(): return
	var s := size
	var pad := 24.0
	var cur := _get_current_room()

	# Calculate bounds
	var bmin := Vector2(INF, INF); var bmax := Vector2(-INF, -INF)
	for title in _nodes:
		var p : Vector2 = _nodes[title].pos
		bmin.x = min(bmin.x, p.x); bmax.x = max(bmax.x, p.x)
		bmin.y = min(bmin.y, p.y); bmax.y = max(bmax.y, p.y)
	
	var span := bmax - bmin
	if span.x < 1.0: span.x = 1.0; if span.y < 1.0: span.y = 1.0
	
	var usable : Vector2 = Vector2(s.x - pad*2.0, s.y - pad*2.0 - 14.0)
	var scale : float = min(usable.x / span.x, usable.y / span.y) * _zoom_level
	var sw : float = span.x * scale; var sh : float = span.y * scale
	var ox : float = pad + (usable.x - sw) * 0.5; var oy : float = pad + (usable.y - sh) * 0.5

	var g2s := func(p: Vector2) -> Vector2:
		return Vector2(ox + (p.x - bmin.x) * scale, oy + (p.y - bmin.y) * scale + 10.0)

	# Edges
	for title : String in _nodes:
		var sp : Vector2 = g2s.call(_nodes[title].pos)
		for conn in _nodes[title].connections:
			if not _nodes.has(conn) or title > conn: continue
			_overlay.draw_line(sp, g2s.call(_nodes[conn].pos), Color(INK, 0.35), 1.0)

	# Nodes
	for title : String in _nodes:
		var sp : Vector2 = g2s.call(_nodes[title].pos)
		var is_cur : bool = (title == cur)
		var r : float = NODE_R_CUR if is_cur else NODE_R_IDLE
		
		# Ink drop look
		_overlay.draw_circle(sp, r + 0.5, Color(INK, 0.15))
		_overlay.draw_circle(sp, r, INK_HIGHLIGHT if is_cur else INK)
		
		if _serif_font:
			var lbl : String = title
			if lbl.length() > LABEL_MAX: lbl = lbl.substr(0, LABEL_MAX-1) + "…"
			var tw := _serif_font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			_overlay.draw_string(_serif_font, Vector2(sp.x - tw*0.5, sp.y + r + 10.0), 
				lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(INK if is_cur else Color(INK, 0.6), 0.90))

func _on_room_changed(new_room: String) -> void:
	if not _nodes.has(new_room):
		_nodes[new_room] = { "pos": _pick_position(), "connections": [] }
	if _prev_room != "" and _nodes.has(_prev_room):
		var pn : Dictionary = _nodes[_prev_room]; var cn : Dictionary = _nodes[new_room]
		if not pn.connections.has(new_room): pn.connections.append(new_room)
		if not cn.connections.has(_prev_room): cn.connections.append(_prev_room)

func _pick_position() -> Vector2:
	if _nodes.is_empty(): return Vector2.ZERO
	if _prev_room != "" and _nodes.has(_prev_room):
		var base : Vector2 = _nodes[_prev_room].pos
		if is_instance_valid(_player):
			var a := _player.rotation.y
			return base + Vector2(sin(a), -cos(a)) * SPACING
		return base + Vector2(SPACING, 0.0)
	return Vector2(randf_range(-100, 100), randf_range(-100, 100))

func _draw_diamond(centre: Vector2, r: float, color: Color) -> void:
	_overlay.draw_colored_polygon(PackedVector2Array([centre+Vector2(0,-r), centre+Vector2(r,0), centre+Vector2(0, r), centre+Vector2(-r,0)]), color)

func _get_player_angle() -> float:
	return _player.rotation.y if is_instance_valid(_player) else 0.0

func _get_current_room() -> String:
	if is_instance_valid(_player) and "current_room" in _player:
		var r = str(_player.current_room)
		return r if r != "" else "Lobby"
	return ""
