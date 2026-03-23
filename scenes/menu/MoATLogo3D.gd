extends Control
## MoATLogo3D — animated pseudo-3D logo for the MoAT main menu.
##
## Draws the M•AT wordmark in a pseudo-3D style:
##   • Extruded letter faces with isometric depth shadows
##   • The central bullet "•" slowly orbits in 3D (sinusoidal depth shift)
##   • Subtle parallax: letters shift slightly as the mouse moves
##   • Idle breathing: letters gently rise and fall out-of-phase
##   • The subtitle "The Museum of All Things" fades in below
##   • On hover the whole mark tilts forward (perspective skew tween)
##   • Brand colours from the funky logo used for extrusion faces
##
## Drop this into your VBox in place of (or alongside) the TextureRect logo.
## Call reset_animation() to replay the entrance.
##
## Size: set custom_minimum_size = Vector2(460, 120) and it will scale.

# ── Tunables ──────────────────────────────────────────────────────────────────

const EXTRUDE_DEPTH  : float = 6.0    # px depth of the 3D extrusion
const BREATH_AMP     : float = 3.0    # px vertical breathing amplitude
const BREATH_PERIOD  : float = 3.8    # seconds per breath cycle
const ORBIT_PERIOD   : float = 4.2    # seconds per bullet orbit
const PARALLAX_STR   : float = 10.0   # px max parallax from mouse
const TILT_ANGLE     : float = 0.04   # radians of hover tilt (skew)
const IDLE_SKEW_AMP  : float = 0.012  # tiny idle skew
const IDLE_SKEW_PERIOD: float = 8.0

# Extrusion brand colours (left-face / right-face alternated per letter)
const BRAND_COLS : Array[Color] = [
	Color("#8B2286"),  # purple — M
	Color("#3BBCD4"),  # teal   — bullet
	Color("#E91F8C"),  # pink   — A
	Color("#7CC242"),  # green  — T
]

# ── State ─────────────────────────────────────────────────────────────────────

var _time          : float   = 0.0
var _hover         : bool    = false
var _hover_tween   : Tween   = null
var _tilt          : float   = 0.0     # current tilt (hover skew)
var _entrance_alpha: float   = 0.0     # 0→1 during entrance
var _entrance_done : bool    = false
var _mouse_off     : Vector2 = Vector2.ZERO  # normalised -1..1 from centre
var _font          : Font    = null

# Letter geometry — populated in _update_geometry() every draw
# Each letter: { x, y, w, h, depth_col, top_col }
var _letters       : Array[Dictionary] = []
var _subtitle_alpha: float = 0.0


# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	mouse_filter    = Control.MOUSE_FILTER_STOP  # receive hover
	_font           = ThemeManager.get_reading_font()
	_entrance_alpha = 0.0
	_entrance_done  = false
	ThemeManager.dark_mode_changed.connect(func(_d): queue_redraw())
	ThemeManager.reading_font_changed.connect(func(f): _font = f; queue_redraw())
	call_deferred("_start_entrance")


func _start_entrance() -> void:
	var tw := create_tween()
	tw.tween_property(self, "_entrance_alpha", 1.0, 1.10) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_entrance_done = true
		# Subtitle fades in 0.4s after letters finish
		var stw := create_tween()
		stw.tween_property(self, "_subtitle_alpha", 1.0, 0.60) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	)


func reset_animation() -> void:
	_entrance_alpha  = 0.0
	_entrance_done   = false
	_subtitle_alpha  = 0.0
	call_deferred("_start_entrance")


# ── Process ────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := size * 0.5
		_mouse_off = Vector2(
			clampf((event.position.x - c.x) / c.x, -1.0, 1.0),
			clampf((event.position.y - c.y) / c.y, -1.0, 1.0)
		)


func _mouse_enter_handler() -> void:
	_hover = true
	_animate_tilt(TILT_ANGLE)


func _mouse_exit_handler() -> void:
	_hover = false
	_mouse_off = Vector2.ZERO
	_animate_tilt(0.0)


func _animate_tilt(target: float) -> void:
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "_tilt", target, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER: _mouse_enter_handler()
		NOTIFICATION_MOUSE_EXIT:  _mouse_exit_handler()


# ── Draw ───────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if size == Vector2.ZERO:
		return

	var dark   : bool  = ThemeManager.is_dark_mode
	var accent : Color = Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	var face_c : Color = Color(0.0, 0.0, 0.0) if not dark else Color(0.95, 0.95, 0.95)

	var vp     : Vector2 = size
	var cx     : float   = vp.x * 0.5
	var cy     : float   = vp.y * 0.5

	# Idle skew
	var idle_skew : float = sin(_time / IDLE_SKEW_PERIOD * TAU) * IDLE_SKEW_AMP

	# Parallax shift from mouse
	var par_x : float = _mouse_off.x * PARALLAX_STR
	var par_y : float = _mouse_off.y * PARALLAX_STR * 0.5

	# ── Layout ──────────────────────────────────────────────────────────────
	# Letters: M  •  A  T  — arranged horizontally, centred
	# We draw them as thick polygon shapes (serifs approximated) with extrusion.

	var logo_h   : float = vp.y * 0.58
	var letter_w : float = logo_h * 0.62   # approx width of each capital
	var bullet_r : float = logo_h * 0.20
	var gap      : float = logo_h * 0.04
	var total_w  : float = letter_w * 3.0 + bullet_r * 2.0 + gap * 3.0
	var start_x  : float = cx - total_w * 0.5
	var base_y   : float = cy - logo_h * 0.15

	# Per-letter breathing offsets (out-of-phase)
	var breath_phases : Array[float] = [0.0, 1.2, 2.4, 3.6]

	# ── Draw extrusion + face per letter ─────────────────────────────────────

	# --- M ---
	var mx : float = start_x
	var my : float = base_y + _breath(0) + par_y
	_draw_letter_M(mx, my, letter_w, logo_h, BRAND_COLS[0], face_c,
	               idle_skew + _tilt, _entrance_alpha, par_x * 0.6)

	# --- bullet ---
	var bx : float = mx + letter_w + gap + bullet_r
	var by : float = my + logo_h * 0.22 + _breath(1)
	_draw_bullet(bx, by, bullet_r, BRAND_COLS[1], face_c,
	             idle_skew + _tilt, _entrance_alpha, par_x * 1.0)

	# --- A ---
	var ax : float = bx + bullet_r + gap
	var ay : float = base_y + _breath(2) + par_y
	_draw_letter_A(ax, ay, letter_w, logo_h, BRAND_COLS[2], face_c,
	               idle_skew + _tilt, _entrance_alpha, par_x * 1.4)

	# --- T ---
	var tx : float = ax + letter_w + gap * 0.5
	var ty : float = base_y + _breath(3) + par_y
	_draw_letter_T(tx, ty, letter_w * 0.95, logo_h, BRAND_COLS[3], face_c,
	               idle_skew + _tilt, _entrance_alpha, par_x * 1.8)

	# ── Subtitle ─────────────────────────────────────────────────────────────
	if _subtitle_alpha > 0.01 and _font:
		var sub_text : String = "The Museum of All Things"
		var sub_size : int    = int(logo_h * 0.18)
		var sub_y    : float  = base_y + logo_h + logo_h * 0.10 + par_y * 0.5
		var sub_col  : Color  = Color(face_c, _subtitle_alpha)
		draw_string(_font,
			Vector2(cx - total_w * 0.5, sub_y),
			sub_text, HORIZONTAL_ALIGNMENT_LEFT,
			total_w, sub_size, sub_col)


func _breath(phase_idx: int) -> float:
	var phase := float(phase_idx) * TAU / 4.0
	return sin(_time / BREATH_PERIOD * TAU + phase) * BREATH_AMP


# ── Letter drawing ─────────────────────────────────────────────────────────────
# Each letter is approximated as a set of thick strokes (filled polygons).
# Extrusion is drawn first (offset shadow-style), then the face on top.

func _draw_letter_M(
		x: float, y: float, w: float, h: float,
		depth_col: Color, face_col: Color,
		skew: float, alpha: float, px: float) -> void:

	var sw : float = w * 0.18   # stroke width
	var a  : float = alpha

	# M has 4 vertical/diagonal strokes
	# Left upright, left diagonal down, right diagonal up, right upright
	var pts_left_up := _rect_pts(x + px, y, sw, h, skew)
	var pts_right_up := _rect_pts(x + w - sw + px, y, sw, h, skew)

	# Diagonals — approximated as parallelograms
	var mid_x : float = x + w * 0.5 + px
	var mid_y : float = y + h * 0.42
	var pts_diag_L := PackedVector2Array([
		_sk(Vector2(x + sw + px,       y),        skew, y + h * 0.5),
		_sk(Vector2(x + sw + px + sw,  y),        skew, y + h * 0.5),
		_sk(Vector2(mid_x + sw * 0.5,  mid_y),    skew, y + h * 0.5),
		_sk(Vector2(mid_x - sw * 0.5,  mid_y),    skew, y + h * 0.5),
	])
	var pts_diag_R := PackedVector2Array([
		_sk(Vector2(x + w - sw*2 + px, y),        skew, y + h * 0.5),
		_sk(Vector2(x + w - sw + px,   y),        skew, y + h * 0.5),
		_sk(Vector2(mid_x + sw * 0.5,  mid_y),    skew, y + h * 0.5),
		_sk(Vector2(mid_x - sw * 0.5,  mid_y),    skew, y + h * 0.5),
	])

	var depth : float = EXTRUDE_DEPTH
	var dc    : Color = Color(depth_col, depth_col.a * a * 0.80)
	var fc    : Color = Color(face_col, a)

	for pts in [pts_left_up, pts_right_up, pts_diag_L, pts_diag_R]:
		_draw_extruded_poly(pts, depth, dc, fc)


func _draw_letter_A(
		x: float, y: float, w: float, h: float,
		depth_col: Color, face_col: Color,
		skew: float, alpha: float, px: float) -> void:

	var sw : float = w * 0.17
	var a  : float = alpha
	var apex_x : float = x + w * 0.5 + px

	# Left diagonal stroke
	var pts_L := PackedVector2Array([
		_sk(Vector2(apex_x - sw * 0.5, y),          skew, y + h * 0.5),
		_sk(Vector2(apex_x + sw * 0.5, y),          skew, y + h * 0.5),
		_sk(Vector2(x + w + px,        y + h),      skew, y + h * 0.5),
		_sk(Vector2(x + w - sw + px,   y + h),      skew, y + h * 0.5),
	])
	# Right diagonal stroke
	var pts_R := PackedVector2Array([
		_sk(Vector2(apex_x - sw * 0.5, y),          skew, y + h * 0.5),
		_sk(Vector2(apex_x + sw * 0.5, y),          skew, y + h * 0.5),
		_sk(Vector2(x + sw + px,       y + h),      skew, y + h * 0.5),
		_sk(Vector2(x + px,            y + h),      skew, y + h * 0.5),
	])
	# Crossbar
	var cb_y   : float = y + h * 0.58
	var cb_x0  : float = x + px + (w * 0.5 - sw * 0.5) * (1.0 - (y + h - cb_y) / h)
	var pts_CB := _rect_pts(cb_x0, cb_y - sw * 0.35, w * 0.55, sw * 0.7, skew)

	var depth : float = EXTRUDE_DEPTH
	var dc    : Color = Color(depth_col, depth_col.a * a * 0.80)
	var fc    : Color = Color(face_col, a)

	for pts in [pts_L, pts_R, pts_CB]:
		_draw_extruded_poly(pts, depth, dc, fc)


func _draw_letter_T(
		x: float, y: float, w: float, h: float,
		depth_col: Color, face_col: Color,
		skew: float, alpha: float, px: float) -> void:

	var sw : float = w * 0.18
	var a  : float = alpha

	# Top bar
	var pts_top  := _rect_pts(x + px, y, w, sw * 0.9, skew)
	# Vertical stem
	var stem_x : float = x + w * 0.5 - sw * 0.5 + px
	var pts_stem := _rect_pts(stem_x, y, sw, h, skew)

	var depth : float = EXTRUDE_DEPTH
	var dc    : Color = Color(depth_col, depth_col.a * a * 0.80)
	var fc    : Color = Color(face_col, a)

	for pts in [pts_top, pts_stem]:
		_draw_extruded_poly(pts, depth, dc, fc)


func _draw_bullet(
		cx: float, cy: float, r: float,
		depth_col: Color, face_col: Color,
		skew: float, alpha: float, px: float) -> void:

	var a     : float = alpha
	var depth : float = EXTRUDE_DEPTH * 0.8
	var angle : float = _time / ORBIT_PERIOD * TAU

	# Orbit: the bullet shifts x/y slightly in a circle
	var orb_x : float = cos(angle) * r * 0.18
	var orb_y : float = sin(angle) * r * 0.12
	var ox    : float = cx + px + orb_x
	var oy    : float = cy      + orb_y

	# Depth shadow (extruded disc, approximated as offset circle)
	var dc : Color = Color(depth_col, depth_col.a * a * 0.70)
	draw_circle(Vector2(ox + depth, oy + depth * 0.5), r, dc)
	# Face
	draw_circle(Vector2(ox, oy), r, Color(face_col, a))
	# Shine highlight
	draw_circle(Vector2(ox - r * 0.28, oy - r * 0.28), r * 0.22,
	            Color(1, 1, 1, a * 0.55))


# ── Geometry helpers ───────────────────────────────────────────────────────────

func _rect_pts(x: float, y: float, w: float, h: float, skew: float) -> PackedVector2Array:
	## 4-corner rect with horizontal skew applied at vertical midpoint.
	var my : float = y + h * 0.5
	return PackedVector2Array([
		_sk(Vector2(x,   y),   skew, my),
		_sk(Vector2(x+w, y),   skew, my),
		_sk(Vector2(x+w, y+h), skew, my),
		_sk(Vector2(x,   y+h), skew, my),
	])


func _sk(p: Vector2, skew: float, pivot_y: float) -> Vector2:
	## Apply horizontal skew relative to a pivot y.
	return Vector2(p.x + (p.y - pivot_y) * skew, p.y)


func _draw_extruded_poly(
		pts: PackedVector2Array,
		depth: float,
		depth_col: Color,
		face_col: Color) -> void:
	## Draw an extruded polygon: first the depth offset copy, then the face.
	var off : Vector2 = Vector2(depth, depth * 0.5)
	var back := PackedVector2Array()
	for p in pts:
		back.append(p + off)
	draw_colored_polygon(back, depth_col)
	# Side quads connecting face to back
	for i in pts.size():
		var j : int = (i + 1) % pts.size()
		draw_colored_polygon(PackedVector2Array([
			pts[i], pts[j], back[j], back[i]
		]), Color(depth_col, depth_col.a * 0.55))
	# Face
	draw_colored_polygon(pts, face_col)
