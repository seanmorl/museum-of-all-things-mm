extends Control
## WikiGraphMinimap — article connection graph minimap.
## Each visited Wikipedia article is a node. Corridors (links between
## articles) are edges. Shows the player's knowledge exploration as a
## growing web — unique to MoAT's Wikipedia-as-museum concept.
##
## Nodes are positioned using the player's actual walking direction when
## entering a new room, so the layout naturally mirrors the museum floor plan.
## Current room is highlighted. Press scroll to zoom.

const NODE_R_IDLE : float = 4.5
const NODE_R_CUR  : float = 6.5
const EDGE_COL    : Color = Color(0.55, 0.58, 0.62, 0.35)
const EDGE_COL_DK : Color = Color(0.35, 0.38, 0.44, 0.35)
const LABEL_MAX   : int   = 15   # chars before truncation
const SPACING     : float = 38.0 # world units between graph nodes

var _player      : Node       = null
var _serif_font  : Font       = null
var _panel_style : StyleBoxFlat = null
var _draw_area   : Control    = null
var _footer_lbl  : Label      = null
var _zoom_level  : float      = 1.0

# Graph data: title → { pos: Vector2, connections: Array[String] }
var _nodes       : Dictionary = {}
var _prev_room   : String     = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_serif_font  = ThemeManager.get_reading_font()

	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left   = -270.0; offset_top    = -270.0
	offset_right  = -20.0;  offset_bottom = -20.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical   = Control.GROW_DIRECTION_BEGIN

	# Outer panel
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_style = StyleBoxFlat.new()
	panel.add_theme_stylebox_override("panel", _panel_style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# Draw area fills the panel, footer at bottom
	_draw_area = Control.new()
	_draw_area.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_draw_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_draw_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_area.draw.connect(_on_draw)
	vbox.add_child(_draw_area)

	# Footer
	var footer_panel := PanelContainer.new()
	var footer_sb := StyleBoxFlat.new()
	footer_sb.content_margin_left   = 10
	footer_sb.content_margin_right  = 10
	footer_sb.content_margin_top    = 5
	footer_sb.content_margin_bottom = 5
	footer_panel.add_theme_stylebox_override("panel", footer_sb)
	footer_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(footer_panel)

	_footer_lbl = Label.new()
	_footer_lbl.text = "Articles visited: 0"
	_footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if _serif_font:
		_footer_lbl.add_theme_font_override("font", _serif_font)
	_footer_lbl.add_theme_font_size_override("font_size", 10)
	footer_panel.add_child(_footer_lbl)

	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f):
		_serif_font = f
		_apply_theme()
	)
	_apply_theme()


func _apply_theme() -> void:
	var dark   : bool  = ThemeManager.is_dark_mode
	var accent : Color = Color(0.30, 0.55, 1.00) if dark \
	                   else Color(0.15, 0.40, 0.90)

	if _panel_style:
		_panel_style.bg_color     = Color(0.08, 0.09, 0.14, 0.88) if dark \
		                          else Color(1.0, 1.0, 1.0, 0.95)
		_panel_style.border_color = Color(accent, 0.35)
		_panel_style.set_border_width_all(2)
		_panel_style.set_corner_radius_all(16)
		_panel_style.shadow_color  = Color(0, 0, 0, 0.35 if dark else 0.12)
		_panel_style.shadow_size   = 16
		_panel_style.shadow_offset = Vector2(0, 5)

	if _footer_lbl:
		if _serif_font:
			_footer_lbl.add_theme_font_override("font", _serif_font)
		_footer_lbl.add_theme_color_override("font_color",
			Color(1, 1, 1, 0.45) if dark else Color(0.3, 0.3, 0.4, 0.5))

	if _draw_area:
		_draw_area.queue_redraw()


func _on_draw() -> void:
	if not _draw_area or _nodes.is_empty():
		return

	var dark   : bool  = ThemeManager.is_dark_mode
	var font   : Font  = _serif_font
	var accent : Color = Color(0.30, 0.55, 1.00) if dark \
	                   else Color(0.15, 0.40, 0.90)
	var txt    : Color = Color(0.88, 0.88, 0.90) if dark \
	                   else Color(0.10, 0.10, 0.12)
	var sub    : Color = Color(0.55, 0.55, 0.60) if dark \
	                   else Color(0.45, 0.45, 0.48)
	var edge_c : Color = EDGE_COL_DK if dark else EDGE_COL
	var sz     : Vector2 = _draw_area.size
	var pad    : float   = 12.0
	var cur    : String  = _get_current_room()

	# Compute bounding box of all node positions
	var bmin : Vector2 = Vector2(INF, INF)
	var bmax : Vector2 = Vector2(-INF, -INF)
	for title : String in _nodes:
		var p : Vector2 = _nodes[title].pos
		bmin.x = min(bmin.x, p.x); bmax.x = max(bmax.x, p.x)
		bmin.y = min(bmin.y, p.y); bmax.y = max(bmax.y, p.y)

	var span : Vector2 = bmax - bmin
	if span.x < 1.0: span.x = 1.0
	if span.y < 1.0: span.y = 1.0

	var usable : Vector2 = Vector2(sz.x - pad * 2.0, sz.y - pad * 2.0)
	var scale  : float   = min(usable.x / span.x, usable.y / span.y) * _zoom_level
	var sw     : float   = span.x * scale
	var sh     : float   = span.y * scale
	var ox     : float   = pad + (usable.x - sw) * 0.5
	var oy     : float   = pad + (usable.y - sh) * 0.5

	var g2s : Callable = func(p: Vector2) -> Vector2:
		return Vector2(ox + (p.x - bmin.x) * scale,
		               oy + (p.y - bmin.y) * scale)

	# ── Edges ─────────────────────────────────────────────────────────────────
	for title : String in _nodes:
		var n  : Dictionary = _nodes[title]
		var sp : Vector2    = g2s.call(n.pos)
		for conn : String in n.connections:
			if not _nodes.has(conn):
				continue
			# Only draw each edge once (lower alphabetical order draws it)
			if title > conn:
				continue
			var cp : Vector2 = g2s.call(_nodes[conn].pos)
			_draw_area.draw_line(sp, cp, edge_c, 1.0)

	# ── Nodes ─────────────────────────────────────────────────────────────────
	for title : String in _nodes:
		var sp     : Vector2 = g2s.call(_nodes[title].pos)
		var is_cur : bool    = (title == cur)
		var r      : float   = NODE_R_CUR if is_cur else NODE_R_IDLE

		# White backing circle for readability on any background
		_draw_area.draw_circle(sp, r + 1.5, Color(1, 1, 1, 0.70 if dark else 0.85))
		# Filled node
		_draw_area.draw_circle(sp, r,
			accent if is_cur else Color(accent, 0.38))
		# Outer ring for current
		if is_cur:
			_draw_area.draw_arc(sp, r + 4.0, 0.0, TAU, 24,
				Color(accent, 0.28), 1.5)

		# Label below node
		if font:
			var lbl : String = title
			if lbl.length() > LABEL_MAX:
				lbl = lbl.substr(0, LABEL_MAX - 1) + "…"
			var tw : float = font.get_string_size(
				lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			_draw_area.draw_string(font,
				Vector2(sp.x - tw * 0.5, sp.y + r + 10.0),
				lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(txt if is_cur else sub, 0.88))


func init(player: Node) -> void:
	_player = player


func update_texture(_tex: Texture2D) -> void:
	pass  # Graph mode doesn't use viewport texture


func set_zoom(level: float) -> void:
	_zoom_level = level
	if _draw_area:
		_draw_area.queue_redraw()


func _process(_delta: float) -> void:
	if not visible:
		return

	var cur : String = _get_current_room()
	if cur != "" and cur != _prev_room:
		_on_room_changed(cur)
		_prev_room = cur

	if _draw_area:
		_draw_area.queue_redraw()


func _on_room_changed(new_room: String) -> void:
	# Add node if first visit
	if not _nodes.has(new_room):
		var pos : Vector2 = _pick_position(new_room)
		_nodes[new_room] = {
			"pos":         pos,
			"connections": [],
		}

	# Connect to previous room
	if _prev_room != "" and _nodes.has(_prev_room):
		var prev_node : Dictionary = _nodes[_prev_room]
		var cur_node  : Dictionary = _nodes[new_room]
		if not prev_node.connections.has(new_room):
			prev_node.connections.append(new_room)
		if not cur_node.connections.has(_prev_room):
			cur_node.connections.append(_prev_room)

	# Update footer count
	if _footer_lbl:
		_footer_lbl.text = "Articles visited: %d" % _nodes.size()


func _pick_position(new_title: String) -> Vector2:
	if _nodes.is_empty():
		return Vector2.ZERO

	if _prev_room != "" and _nodes.has(_prev_room):
		var base : Vector2 = _nodes[_prev_room].pos
		if is_instance_valid(_player):
			var a : float = _player.rotation.y
			return base + Vector2(sin(a), -cos(a)) * SPACING
		return base + Vector2(SPACING, 0.0)

	# Fallback: place near centroid
	var cx : float = 0.0; var cy : float = 0.0
	for t : String in _nodes:
		cx += _nodes[t].pos.x; cy += _nodes[t].pos.y
	cx /= _nodes.size(); cy /= _nodes.size()
	var a : float = randf() * TAU
	return Vector2(cx + cos(a) * SPACING, cy + sin(a) * SPACING)


func _get_current_room() -> String:
	if is_instance_valid(_player) and "current_room" in _player:
		return str(_player.current_room)
	return ""
