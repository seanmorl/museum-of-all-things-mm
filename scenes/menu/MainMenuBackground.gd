extends Control
## MainMenuBackground — animated tranquil background for the main menu.
##
## Attach this script to the existing "Background" ColorRect in MainMenu.tscn
## (replace its script, or add a child Control node with this script instead).
##
## The background draws:
##   • A soft two-tone gradient wash that shifts slowly over time
##   • ~40 floating "exhibit card" rectangles drifting upward very slowly,
##     each with a faint border — evoking rooms and doorways in the museum
##   • ~70 tiny dust motes (small circles) that drift and pulse
##   • A very subtle radial vignette that draws the eye to the centre
##
## Everything reacts to ThemeManager dark/light mode instantly.

# ── Tunables ──────────────────────────────────────────────────────────────────

const CARD_COUNT:    int   = 36
const MOTE_COUNT:    int   = 65
const CARD_SPEED:    float = 8.0    # px/sec upward drift
const MOTE_SPEED:    float = 14.0   # px/sec
const GRAD_PERIOD:   float = 18.0   # seconds for one gradient cycle
const SWAY_STRENGTH: float = 18.0   # horizontal sway amplitude px
const SWAY_PERIOD:   float = 12.0   # seconds per sway cycle

# ── Internal state ────────────────────────────────────────────────────────────

var _time: float = 0.0

class _Card:
	var pos:     Vector2
	var size:    Vector2
	var speed:   float
	var phase:   float   # for sway
	var alpha:   float
	var rot:     float   # very slight tilt, radians

class _Mote:
	var pos:     Vector2
	var radius:  float
	var speed:   float
	var phase:   float
	var alpha:   float

var _cards: Array[_Card] = []
var _motes: Array[_Mote] = []
var _vp_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp_size = get_viewport_rect().size
	_spawn_all()
	ThemeManager.dark_mode_changed.connect(func(_d): queue_redraw())
	get_viewport().size_changed.connect(_on_viewport_resized)


func _process(delta: float) -> void:
	_time += delta
	var h: float = _vp_size.y if _vp_size.y > 0.0 else 800.0

	for c in _cards:
		c.pos.y -= c.speed * delta
		c.pos.x += sin(_time / SWAY_PERIOD * TAU + c.phase) * SWAY_STRENGTH * delta / SWAY_PERIOD
		if c.pos.y + c.size.y < -20.0:
			_reset_card(c, true)

	for m in _motes:
		m.pos.y -= m.speed * delta
		m.pos.x += sin(_time * 0.4 + m.phase) * 6.0 * delta
		if m.pos.y + m.radius < -10.0:
			_reset_mote(m, true)

	queue_redraw()


func _draw() -> void:
	var dark: bool = ThemeManager.is_dark_mode
	var vp := _vp_size
	if vp == Vector2.ZERO:
		return

	# ── Background gradient ───────────────────────────────────────────────────
	# Two colours that slowly cycle, giving a gentle breathing quality.
	var t: float = (sin(_time / GRAD_PERIOD * TAU) + 1.0) * 0.5

	var col_a: Color
	var col_b: Color
	if dark:
		col_a = Color(0.08, 0.09, 0.12, 1.0).lerp(Color(0.10, 0.11, 0.16, 1.0), t)
		col_b = Color(0.05, 0.06, 0.09, 1.0).lerp(Color(0.07, 0.08, 0.12, 1.0), t)
	else:
		col_a = Color(0.95, 0.96, 0.98, 1.0).lerp(Color(0.96, 0.97, 1.00, 1.0), t)
		col_b = Color(0.88, 0.90, 0.94, 1.0).lerp(Color(0.90, 0.92, 0.97, 1.0), t)

	# Vertical gradient via a series of horizontal rects
	var steps: int = 32
	for i in steps:
		var y0: float = vp.y * float(i)     / steps
		var y1: float = vp.y * float(i + 1) / steps
		var f: float  = float(i) / (steps - 1)
		var c: Color  = col_a.lerp(col_b, f)
		draw_rect(Rect2(0.0, y0, vp.x, y1 - y0 + 1.0), c)

	# ── Floating exhibit cards ────────────────────────────────────────────────
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.15, 0.35, 0.85)
	var card_border := Color(accent, 0.10 if dark else 0.08)
	var card_fill   := Color(1.0 if dark else 0.0, 1.0 if dark else 0.0, 1.0 if dark else 0.0,
							 0.03 if dark else 0.04)

	for c in _cards:
		var a_scale: float = c.alpha * _edge_fade(c.pos, c.size, vp)
		if a_scale < 0.005:
			continue
		var r := Rect2(c.pos, c.size)
		# Slight rotation via polygon
		var cx: float = c.pos.x + c.size.x * 0.5
		var cy: float = c.pos.y + c.size.y * 0.5
		var corners := PackedVector2Array([
			_rot_pt(Vector2(c.pos.x,              c.pos.y             ), cx, cy, c.rot),
			_rot_pt(Vector2(c.pos.x + c.size.x,   c.pos.y             ), cx, cy, c.rot),
			_rot_pt(Vector2(c.pos.x + c.size.x,   c.pos.y + c.size.y  ), cx, cy, c.rot),
			_rot_pt(Vector2(c.pos.x,               c.pos.y + c.size.y  ), cx, cy, c.rot),
		])
		draw_colored_polygon(corners, Color(card_fill, card_fill.a * a_scale))
		# Border as four line segments
		var bc := Color(card_border, card_border.a * a_scale)
		for i in 4:
			draw_line(corners[i], corners[(i + 1) % 4], bc, 1.0, true)

		# Small inner doorway mark — a centred rect ~30% of card size
		var door_w: float = c.size.x * 0.28
		var door_h: float = c.size.y * 0.42
		var door_cx: float = cx
		var door_cy: float = c.pos.y + c.size.y - door_h * 0.5 - c.size.y * 0.08
		var door_corners := PackedVector2Array([
			_rot_pt(Vector2(door_cx - door_w * 0.5, door_cy - door_h * 0.5), cx, cy, c.rot),
			_rot_pt(Vector2(door_cx + door_w * 0.5, door_cy - door_h * 0.5), cx, cy, c.rot),
			_rot_pt(Vector2(door_cx + door_w * 0.5, door_cy + door_h * 0.5), cx, cy, c.rot),
			_rot_pt(Vector2(door_cx - door_w * 0.5, door_cy + door_h * 0.5), cx, cy, c.rot),
		])
		var dc := Color(card_border, card_border.a * a_scale * 0.7)
		for i in 4:
			draw_line(door_corners[i], door_corners[(i + 1) % 4], dc, 0.8, true)

	# ── Dust motes ────────────────────────────────────────────────────────────
	var mote_col := Color(accent, 0.0)
	for m in _motes:
		var pulse: float = (sin(_time * 1.2 + m.phase * 3.7) + 1.0) * 0.5
		var a: float = m.alpha * (0.6 + pulse * 0.4) * _edge_fade_point(m.pos, vp)
		if a < 0.005:
			continue
		draw_circle(m.pos, m.radius, Color(accent, a))

	# ── Vignette ──────────────────────────────────────────────────────────────
	# Drawn as a ring of dark transparent polys around the edge
	var vig_col := Color(0.0, 0.0, 0.0, 0.22 if dark else 0.08)
	var vig_col0 := Color(vig_col, 0.0)
	var cx2: float = vp.x * 0.5
	var cy2: float = vp.y * 0.5
	var vig_steps: int = 64
	var r_outer: float = vp.length() * 0.52
	var r_inner: float = vp.length() * 0.30
	for i in vig_steps:
		var a0: float = float(i)     / vig_steps * TAU
		var a1: float = float(i + 1) / vig_steps * TAU
		var pts := PackedVector2Array([
			Vector2(cx2 + cos(a0) * r_inner, cy2 + sin(a0) * r_inner),
			Vector2(cx2 + cos(a0) * r_outer, cy2 + sin(a0) * r_outer),
			Vector2(cx2 + cos(a1) * r_outer, cy2 + sin(a1) * r_outer),
			Vector2(cx2 + cos(a1) * r_inner, cy2 + sin(a1) * r_inner),
		])
		draw_colored_polygon(pts, vig_col)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _rot_pt(p: Vector2, cx: float, cy: float, angle: float) -> Vector2:
	var dx: float = p.x - cx
	var dy: float = p.y - cy
	return Vector2(cx + dx * cos(angle) - dy * sin(angle),
				   cy + dx * sin(angle) + dy * cos(angle))


func _edge_fade(pos: Vector2, sz: Vector2, vp: Vector2) -> float:
	## Returns 0–1 fade based on how close the card is to the top/bottom edges.
	var margin: float = 80.0
	var top_f:  float = clampf((pos.y + sz.y) / margin, 0.0, 1.0)
	var bot_f:  float = clampf((vp.y - pos.y) / margin, 0.0, 1.0)
	return top_f * bot_f


func _edge_fade_point(pos: Vector2, vp: Vector2) -> float:
	var margin: float = 60.0
	var top_f:  float = clampf(pos.y / margin, 0.0, 1.0)
	var bot_f:  float = clampf((vp.y - pos.y) / margin, 0.0, 1.0)
	var lft_f:  float = clampf(pos.x / margin, 0.0, 1.0)
	var rgt_f:  float = clampf((vp.x - pos.x) / margin, 0.0, 1.0)
	return top_f * bot_f * lft_f * rgt_f


func _spawn_all() -> void:
	var vp := _vp_size
	if vp == Vector2.ZERO:
		vp = Vector2(1280, 720)

	for i in CARD_COUNT:
		var c := _Card.new()
		_reset_card(c, false)
		# Spread initial positions across the full height
		c.pos.y = randf() * (vp.y + 200.0) - 100.0
		_cards.append(c)

	for i in MOTE_COUNT:
		var m := _Mote.new()
		_reset_mote(m, false)
		m.pos.y = randf() * (vp.y + 100.0) - 50.0
		_motes.append(m)


func _reset_card(c: _Card, from_bottom: bool) -> void:
	var vp := _vp_size
	if vp == Vector2.ZERO:
		vp = Vector2(1280, 720)
	var w: float = randf_range(55.0, 140.0)
	var h: float = w * randf_range(1.1, 1.7)
	c.size  = Vector2(w, h)
	c.pos   = Vector2(randf() * (vp.x + 60.0) - 30.0,
					  vp.y + h + randf_range(0.0, 200.0) if from_bottom else vp.y + h)
	c.speed = randf_range(CARD_SPEED * 0.5, CARD_SPEED * 1.5)
	c.phase = randf() * TAU
	c.alpha = randf_range(0.25, 0.70)
	c.rot   = randf_range(-0.06, 0.06)


func _reset_mote(m: _Mote, from_bottom: bool) -> void:
	var vp := _vp_size
	if vp == Vector2.ZERO:
		vp = Vector2(1280, 720)
	m.radius = randf_range(1.0, 3.5)
	m.pos    = Vector2(randf() * vp.x,
					   vp.y + m.radius + randf_range(0.0, 120.0) if from_bottom else vp.y + m.radius)
	m.speed  = randf_range(MOTE_SPEED * 0.5, MOTE_SPEED * 1.6)
	m.phase  = randf() * TAU
	m.alpha  = randf_range(0.12, 0.55)


func _on_viewport_resized() -> void:
	_vp_size = get_viewport_rect().size
	queue_redraw()
