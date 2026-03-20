extends Control
## FullMapMinimap — Fog-of-war floor plan that reveals rooms as you visit them.
##
## How it works:
##   Each time the player enters a room, we store its world-space bounds and
##   title permanently. On draw, all stored rooms are rendered as a schematic
##   floor plan scaled to fit the panel — exactly like a museum handout that
##   fills in as you explore.
##
##   Room data comes from museum.get_rooms_for_npcs() per exhibit, called once
##   per exhibit load. Rooms not yet visited are not shown (fog of war).
##
##   The player dot is drawn at the correct world position scaled into the map.

var _player     : Node        = null
var _museum     : Node        = null
var _font       : Font        = null
var _panel_sb   : StyleBoxFlat = null
var _bar_sb     : StyleBoxFlat = null
var _draw_area  : Control     = null
var _header_lbl : Label       = null
var _zoom       : float       = 1.0

# Revealed rooms: { id: { wmin: Vector2, wmax: Vector2, title: String } }
var _rooms         : Dictionary = {}
# World extents across all revealed rooms
var _world_min     : Vector2    = Vector2(INF, INF)
var _world_max     : Vector2    = Vector2(-INF, -INF)
# Last seen exhibit title — re-fetch rooms when exhibit changes
var _last_exhibit  : String     = ""
var _last_room     : String     = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeManager.get_reading_font()

	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left     = -268.0
	offset_top      = -268.0
	offset_right    = -18.0
	offset_bottom   = -18.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical   = Control.GROW_DIRECTION_BEGIN

	# Outer panel
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_sb = StyleBoxFlat.new()
	panel.add_theme_stylebox_override("panel", _panel_sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# Header — exhibit/room name
	var header_wrap := PanelContainer.new()
	_bar_sb = StyleBoxFlat.new()
	_bar_sb.content_margin_left   = 10
	_bar_sb.content_margin_right  = 10
	_bar_sb.content_margin_top    = 5
	_bar_sb.content_margin_bottom = 5
	header_wrap.add_theme_stylebox_override("panel", _bar_sb)
	header_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header_wrap)

	_header_lbl = Label.new()
	_header_lbl.text                 = "Map"
	_header_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_wrap.add_child(_header_lbl)

	# Map draw area
	_draw_area = Control.new()
	_draw_area.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_draw_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_draw_area.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_draw_area.draw.connect(_draw_map)
	vbox.add_child(_draw_area)

	# Footer — zoom + room count
	var footer_wrap := PanelContainer.new()
	var footer_sb := _bar_sb.duplicate() as StyleBoxFlat
	footer_wrap.add_theme_stylebox_override("panel", footer_sb)
	footer_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(footer_wrap)

	var footer_lbl := Label.new()
	footer_lbl.name                 = "FooterLabel"
	footer_lbl.text                 = "0 rooms"
	footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_wrap.add_child(footer_lbl)

	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f): _font = f; _apply_theme())
	_apply_theme()


func _apply_theme() -> void:
	var dark   : bool  = ThemeManager.is_dark_mode
	var accent : Color = Color(0.28, 0.52, 1.00) if dark else Color(0.14, 0.38, 0.88)

	if _panel_sb:
		_panel_sb.bg_color     = Color(0.08, 0.09, 0.13, 0.92) if dark \
		                       else Color(1.0, 1.0, 1.0, 0.97)
		_panel_sb.border_color = Color(accent, 0.35)
		_panel_sb.set_border_width_all(1)
		_panel_sb.set_corner_radius_all(3)
		_panel_sb.shadow_color  = Color(0, 0, 0, 0.28 if dark else 0.09)
		_panel_sb.shadow_size   = 10
		_panel_sb.shadow_offset = Vector2(0, 3)

	# Style the header/footer bars the same way RaceHUD does it
	for bar_node in ["FooterLabel"]:
		pass  # footer label styled via theme

	if _header_lbl:
		if _font: _header_lbl.add_theme_font_override("font", _font)
		_header_lbl.add_theme_font_size_override("font_size", 11)
		_header_lbl.add_theme_color_override("font_color",
			Color(1,1,1,0.85) if dark else Color(0.10,0.10,0.14,0.85))

	var footer := get_node_or_null("../../FooterLabel")  # doesn't exist at this path
	# Just style via font override on any Label children
	if _draw_area:
		for child in _draw_area.get_children():
			if child is Label:
				if _font: child.add_theme_font_override("font", _font)
				child.add_theme_font_size_override("font_size", 10)
				child.add_theme_color_override("font_color",
					Color(1,1,1,0.42) if dark else Color(0.30,0.30,0.38,0.50))

	if _draw_area:
		_draw_area.queue_redraw()


func _draw_map() -> void:
	if not _draw_area:
		return

	var dark    : bool    = ThemeManager.is_dark_mode
	var accent  : Color   = Color(0.28, 0.52, 1.00) if dark else Color(0.14, 0.38, 0.88)
	var sz      : Vector2 = _draw_area.size
	var pad     : float   = 10.0
	var cur     : String  = _get_room()

	# Empty state
	if _rooms.is_empty():
		if _font:
			var msg : String = "No rooms mapped yet.\nExplore to reveal the map."
			_draw_area.draw_string(_font,
				Vector2(pad, sz.y * 0.5),
				msg, HORIZONTAL_ALIGNMENT_LEFT, sz.x - pad*2, 10,
				Color(accent, 0.50))
		return

	# Compute scale to fit all revealed rooms
	var span  : Vector2 = _world_max - _world_min
	if span.x < 1.0: span.x = 1.0
	if span.y < 1.0: span.y = 1.0

	var usable : Vector2 = Vector2(sz.x - pad*2.0, sz.y - pad*2.0)
	var scale  : float   = min(usable.x / span.x, usable.y / span.y) * _zoom
	var sw     : float   = span.x * scale
	var sh     : float   = span.y * scale
	var ox     : float   = pad + (usable.x - sw) * 0.5
	var oy     : float   = pad + (usable.y - sh) * 0.5

	# World XZ → screen position
	var w2s : Callable = func(wx: float, wz: float) -> Vector2:
		return Vector2(
			ox + (wx - _world_min.x) * scale,
			oy + (wz - _world_min.y) * scale
		)

	# Colours
	var c_room_fill : Color = Color(0.15, 0.16, 0.20, 1.0) if dark \
	                        else Color(0.92, 0.93, 0.95, 1.0)
	var c_room_edge : Color = Color(0.32, 0.35, 0.42, 1.0) if dark \
	                        else Color(0.52, 0.55, 0.60, 1.0)
	var c_cur_fill  : Color = Color(accent, 0.15)
	var c_cur_edge  : Color = Color(accent, 0.88)
	var c_label     : Color = Color(0.55, 0.56, 0.60) if dark \
	                        else Color(0.42, 0.42, 0.46)

	# ── Draw rooms ────────────────────────────────────────────────────────────
	for room_id : String in _rooms:
		var room    : Dictionary = _rooms[room_id]
		var pmin    : Vector2    = w2s.call(room.wmin.x, room.wmin.y)
		var pmax    : Vector2    = w2s.call(room.wmax.x, room.wmax.y)
		var rect    : Rect2      = Rect2(pmin, pmax - pmin)

		if rect.size.x < 2.0 or rect.size.y < 2.0:
			continue

		var is_cur  : bool = (room_id == cur or room.title == cur)

		_draw_area.draw_rect(rect, c_cur_fill if is_cur else c_room_fill)
		_draw_area.draw_rect(rect, c_cur_edge if is_cur else c_room_edge,
			false, 1.5 if is_cur else 0.8)

		# Room label when big enough
		if _font and rect.size.x > 28.0 and rect.size.y > 14.0:
			var lbl : String = room.title
			if lbl.length() > 13:
				lbl = lbl.substr(0, 12) + "…"
			var tw : float = _font.get_string_size(
				lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
			_draw_area.draw_string(_font,
				Vector2(rect.position.x + rect.size.x*0.5 - tw*0.5,
				        rect.position.y + rect.size.y*0.5 + 4.0),
				lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
				Color(c_cur_edge if is_cur else c_label, 0.88))

	# ── Player dot ────────────────────────────────────────────────────────────
	if is_instance_valid(_player):
		var pp    : Vector2 = w2s.call(
			_player.global_position.x, _player.global_position.z)
		var angle : float   = _player.rotation.y

		# Direction tick
		var tick : Vector2 = pp + Vector2(sin(angle), cos(angle)) * 8.0
		_draw_area.draw_line(pp, tick, accent, 1.5)
		# Dot with white outline
		_draw_area.draw_circle(pp, 5.0, Color(1, 1, 1, 0.90))
		_draw_area.draw_circle(pp, 3.8, accent)


func init(player: Node) -> void:
	_player = player
	_museum = get_tree().get_first_node_in_group("museum")


func update_texture(_tex: Texture2D) -> void:
	pass  # This mode doesn't use the viewport texture


func set_zoom(level: float) -> void:
	_zoom = level
	if _draw_area:
		_draw_area.queue_redraw()


func _process(_delta: float) -> void:
	if not visible:
		return

	# Re-fetch room list when entering a new exhibit
	var cur : String = _get_room()
	if cur != _last_room:
		_last_room = cur
		if _header_lbl:
			_header_lbl.text = cur if cur != "" else "Lobby"
		_try_fetch_rooms()

	if _draw_area:
		_draw_area.queue_redraw()

	# Update footer count
	var footer := _find_footer_label()
	if footer:
		footer.text = "%d room%s" % [_rooms.size(), "s" if _rooms.size() != 1 else ""]


func _try_fetch_rooms() -> void:
	# Get museum node if not cached
	if not is_instance_valid(_museum):
		_museum = get_tree().get_first_node_in_group("museum")
	if not is_instance_valid(_museum):
		return
	if not _museum.has_method("get_rooms_for_npcs"):
		return

	var raw : Array = _museum.get_rooms_for_npcs()
	for room : Dictionary in raw:
		var bounds : Array = room.get("bounds", [])
		if bounds.size() < 2:
			continue

		var bmin3 : Vector3 = bounds[0]
		var bmax3 : Vector3 = bounds[1]
		var wmin  : Vector2 = Vector2(bmin3.x, bmin3.z)
		var wmax  : Vector2 = Vector2(bmax3.x, bmax3.z)

		var title : String = str(room.get("title", room.get("id", "")))
		var rid   : String = title

		if not _rooms.has(rid):
			_rooms[rid] = { "wmin": wmin, "wmax": wmax, "title": title }
			# Expand world extents
			_world_min.x = min(_world_min.x, wmin.x)
			_world_min.y = min(_world_min.y, wmin.y)
			_world_max.x = max(_world_max.x, wmax.x)
			_world_max.y = max(_world_max.y, wmax.y)

	if _world_min.x == INF:
		_world_min = Vector2.ZERO
		_world_max = Vector2(100, 100)


func _find_footer_label() -> Label:
	# Footer label is the Label inside the last PanelContainer child of panel's vbox
	var panel := get_child(0) if get_child_count() > 0 else null
	if not panel:
		return null
	var vbox := panel.get_child(0) if panel.get_child_count() > 0 else null
	if not vbox:
		return null
	var footer_wrap := vbox.get_child(vbox.get_child_count()-1) if vbox.get_child_count() > 0 else null
	if not footer_wrap:
		return null
	for child in footer_wrap.get_children():
		if child is Label:
			if _font: child.add_theme_font_override("font", _font)
			child.add_theme_font_size_override("font_size", 10)
			child.add_theme_color_override("font_color",
				Color(1,1,1,0.42) if ThemeManager.is_dark_mode \
				else Color(0.30,0.30,0.38,0.50))
			return child
	return null


func _get_room() -> String:
	if is_instance_valid(_player) and "current_room" in _player:
		return str(_player.current_room)
	return ""
