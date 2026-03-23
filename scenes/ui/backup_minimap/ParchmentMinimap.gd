extends Control
## ParchmentMinimap
## Aged paper minimap. Shows the SubViewport 3D texture tinted sepia,
## with ornate border, compass rose, and player direction arrow.

const PARCHMENT_BG   := Color(0.91, 0.85, 0.72)
const PARCHMENT_DARK := Color(0.74, 0.67, 0.53)
const BORDER_INK     := Color(0.42, 0.33, 0.21)
const INK            := Color(0.26, 0.20, 0.14)
const SEPIA          := Color(0.62, 0.47, 0.28, 0.88)

var _player  : Node        = null
var _tex_rect: TextureRect = null
var _overlay : Control     = null
var _zoom    : float       = 1.0
var _font    : Font        = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeManager.get_reading_font()
	if not _font:
		_font = ThemeDB.fallback_font

	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left     = -268.0
	offset_top      = -268.0
	offset_right    = -18.0
	offset_bottom   = -18.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical   = Control.GROW_DIRECTION_BEGIN
	clip_contents   = true

	# Paper background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = PARCHMENT_BG
	add_child(bg)

	# Viewport texture — sepia tinted
	_tex_rect = TextureRect.new()
	_tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex_rect.offset_left   =  12
	_tex_rect.offset_top    =  12
	_tex_rect.offset_right  = -12
	_tex_rect.offset_bottom = -26
	_tex_rect.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tex_rect.modulate      = SEPIA
	add_child(_tex_rect)

	# Overlay draws everything on top
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_overlay.clip_contents = true
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	ThemeManager.reading_font_changed.connect(func(f):
		_font = f if f else ThemeDB.fallback_font
		_overlay.queue_redraw()
	)


func init(player: Node) -> void:
	_player = player


func update_texture(tex: Texture2D) -> void:
	if _tex_rect and tex:
		_tex_rect.texture = tex


func set_zoom(level: float) -> void:
	_zoom = level
	if _overlay:
		_overlay.queue_redraw()


func _process(_delta: float) -> void:
	if visible and _overlay:
		_overlay.queue_redraw()


func _draw_overlay() -> void:
	var s : Vector2 = size
	var m : float   = 5.0

	# ── Paper grain ───────────────────────────────────────────────────────────
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for y in range(0, int(s.y), 3):
		_overlay.draw_line(
			Vector2(0, y), Vector2(s.x, y),
			Color(0.48, 0.38, 0.28, rng.randf_range(0.025, 0.075)), 1.0)

	# ── Edge vignette (arcs, not circles — stays near corners) ────────────────
	var vc := Color(0.30, 0.20, 0.10, 0.20)
	var vr : float = 55.0
	_overlay.draw_arc(Vector2(0,   0  ), vr, 0.0,        PI * 0.5, 12, vc, vr * 0.55)
	_overlay.draw_arc(Vector2(s.x, 0  ), vr, PI * 0.5,   PI,       12, vc, vr * 0.55)
	_overlay.draw_arc(Vector2(s.x, s.y), vr, PI,         PI * 1.5, 12, vc, vr * 0.55)
	_overlay.draw_arc(Vector2(0,   s.y), vr, PI * 1.5,   TAU,      12, vc, vr * 0.55)

	# ── Double ornate border ──────────────────────────────────────────────────
	_overlay.draw_rect(Rect2(Vector2(m, m), s - Vector2(m*2, m*2)),
		BORDER_INK, false, 2.0)
	_overlay.draw_rect(Rect2(Vector2(m+4, m+4), s - Vector2((m+4)*2, (m+4)*2)),
		Color(BORDER_INK, 0.55), false, 1.0)

	# Corner diamond ornaments
	for c : Vector2 in [Vector2(m+1,m+1), Vector2(s.x-m-1,m+1),
	                     Vector2(m+1,s.y-m-1), Vector2(s.x-m-1,s.y-m-1)]:
		_overlay.draw_colored_polygon(PackedVector2Array([
			c+Vector2(0,-4), c+Vector2(4,0), c+Vector2(0,4), c+Vector2(-4,0)
		]), BORDER_INK)

	# ── Compass rose (top-right) ───────────────────────────────────────────────
	var angle : float  = _get_angle()
	var cx    : float  = s.x - 35.0
	var cy    : float  = 35.0
	var cr    : float  = 16.0
	_overlay.draw_circle(Vector2(cx, cy), cr + 4.0, Color(PARCHMENT_BG, 0.88))
	_overlay.draw_arc(Vector2(cx, cy), cr, 0.0, TAU, 24, Color(BORDER_INK, 0.50), 1.0)
	_overlay.draw_line(Vector2(cx, cy-cr), Vector2(cx, cy+cr), BORDER_INK, 1.5)
	_overlay.draw_line(Vector2(cx-cr, cy), Vector2(cx+cr, cy), BORDER_INK, 1.5)
	# Cardinal labels
	if _font:
		_overlay.draw_string(_font, Vector2(cx-4, cy-cr-4),
			"N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.62, 0.10, 0.06))
		_overlay.draw_string(_font, Vector2(cx-3, cy+cr+12),
			"S", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(BORDER_INK, 0.55))
		_overlay.draw_string(_font, Vector2(cx+cr+3, cy+3),
			"E", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(BORDER_INK, 0.55))
		_overlay.draw_string(_font, Vector2(cx-cr-10, cy+3),
			"W", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(BORDER_INK, 0.55))
	# Rotating needle pointing player direction
	var nt := Vector2(cx + sin(angle)*(cr-2), cy + cos(angle)*(cr-2))
	var nl := Vector2(cx + sin(angle+2.5)*4,  cy + cos(angle+2.5)*4)
	var nr := Vector2(cx + sin(angle-2.5)*4,  cy + cos(angle-2.5)*4)
	_overlay.draw_colored_polygon(PackedVector2Array([nt, nl, nr]),
		Color(0.62, 0.10, 0.06))

	# ── Player arrow (map centre) ─────────────────────────────────────────────
	var map_bottom : float  = s.y - 26.0
	var pcx        : float  = s.x * 0.5
	var pcy        : float  = (map_bottom) * 0.5 + 12.0
	var ar         : float  = 9.0
	var tip   := Vector2(pcx + sin(angle)*ar*1.5, pcy + cos(angle)*ar*1.5)
	var left  := Vector2(pcx + sin(angle+2.3)*ar, pcy + cos(angle+2.3)*ar)
	var right := Vector2(pcx + sin(angle-2.3)*ar, pcy + cos(angle-2.3)*ar)
	var back  := Vector2(pcx + sin(angle+PI)*ar*0.4, pcy + cos(angle+PI)*ar*0.4)
	# Shadow
	_overlay.draw_colored_polygon(
		PackedVector2Array([tip+Vector2(1,1), left+Vector2(1,1),
		                    back+Vector2(1,1), right+Vector2(1,1)]),
		Color(PARCHMENT_DARK, 0.60))
	# Arrow
	_overlay.draw_colored_polygon(PackedVector2Array([tip, left, back, right]), INK)

	# ── Bottom bar ────────────────────────────────────────────────────────────
	var bar_y : float = s.y - 26.0
	_overlay.draw_rect(Rect2(m+1, bar_y, s.x-(m+1)*2, 22),
		Color(PARCHMENT_DARK, 0.88))
	_overlay.draw_line(Vector2(m+1, bar_y), Vector2(s.x-m-1, bar_y),
		BORDER_INK, 1.0)
	if _font:
		var room : String = _get_room()
		if room.length() > 22:
			room = room.substr(0, 21) + "…"
		_overlay.draw_string(_font, Vector2(m+10, bar_y+16),
			room, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
		_overlay.draw_string(_font, Vector2(s.x-m-42, bar_y+16),
			"%d%%" % int(_zoom * 100),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, 0.65))


func _get_angle() -> float:
	return _player.rotation.y if is_instance_valid(_player) else 0.0


func _get_room() -> String:
	if is_instance_valid(_player) and "current_room" in _player:
		var r : String = str(_player.current_room)
		return r if r != "" else "Lobby"
	return "Museum"
