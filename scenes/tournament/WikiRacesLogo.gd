extends Control
## WikiRacesLogo — procedurally drawn "Wiki Races" logo matching the SVG reference.
## Add as a child anywhere you need the logo. Set `size` to control scale.
## Fully theme-aware (dark / light mode).
##
## Usage:
##   var logo := preload("res://scenes/tournament/WikiRacesLogo.gd").new()
##   logo.custom_minimum_size = Vector2(340, 170)
##   add_child(logo)

@export var compact: bool = false   ## true = globe only, no wordmark

var _serif_font: Font = null


func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	ThemeManager.dark_mode_changed.connect(func(_d): queue_redraw())
	ThemeManager.reading_font_changed.connect(func(f): _serif_font = f; queue_redraw())


func _draw() -> void:
	var dark:   bool  = ThemeManager.is_dark_mode
	var accent        := Color(0.30, 0.55, 1.00) if dark else Color(0.20, 0.38, 0.85)
	var gold          := Color(1.00, 0.82, 0.25) if dark else Color(0.80, 0.60, 0.04)
	var bg_col        := Color(0.10, 0.11, 0.14, 1.0) if dark else Color(0.95, 0.96, 0.97, 1.0)
	var text_col      := ThemeManager.text_color
	var sub_col       := ThemeManager.subtext_color

	var w: float = size.x
	var h: float = size.y
	var scale_f: float = minf(w, h) / 170.0   # design unit is 170px tall

	var globe_cx: float = 55.0 * scale_f
	var globe_cy: float = h * 0.5
	var r:        float = 44.0 * scale_f

	# ── Globe background ──────────────────────────────────────────────────────
	draw_circle(Vector2(globe_cx, globe_cy), r, bg_col)

	# ── Latitude ellipses (3) ─────────────────────────────────────────────────
	var grid_col := Color(accent, 0.18 if dark else 0.13)
	for rx_frac in [0.25, 0.57, 0.84]:
		_draw_ellipse_outline(Vector2(globe_cx, globe_cy), r, r * rx_frac, grid_col, 0.6 * scale_f)

	# ── Longitude verticals (3) ───────────────────────────────────────────────
	for ry_frac in [0.25, 0.57, 0.84]:
		_draw_ellipse_outline(Vector2(globe_cx, globe_cy), r * ry_frac, r, grid_col, 0.6 * scale_f)

	# ── Puzzle piece arc (top-right quadrant) ─────────────────────────────────
	var piece_fill   := Color(accent, 0.15 if dark else 0.10)
	var piece_stroke := Color(accent, 0.65 if dark else 0.55)
	_draw_arc_wedge(globe_cx, globe_cy, r, deg_to_rad(-90), deg_to_rad(-45), piece_fill, piece_stroke, scale_f)
	_draw_arc_wedge(globe_cx, globe_cy, r, deg_to_rad(-45), deg_to_rad(0),   piece_fill, piece_stroke, scale_f)

	# Puzzle nubs
	var nub1 := Vector2(globe_cx + cos(deg_to_rad(-67)) * r * 0.88,
	                    globe_cy + sin(deg_to_rad(-67)) * r * 0.88)
	var nub2 := Vector2(globe_cx + cos(deg_to_rad(-22)) * r * 0.88,
	                    globe_cy + sin(deg_to_rad(-22)) * r * 0.88)
	draw_circle(nub1, 2.5 * scale_f, piece_fill)
	draw_arc(nub1, 2.5 * scale_f, 0, TAU, 16, piece_stroke, 0.8 * scale_f)
	draw_circle(nub2, 2.5 * scale_f, piece_fill)
	draw_arc(nub2, 2.5 * scale_f, 0, TAU, 16, piece_stroke, 0.8 * scale_f)

	# ── Speed arc (racing motion line through lower globe) ────────────────────
	var speed_col := Color(accent, 0.65)
	# Simple curved approximation using multiple line segments
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 12:
		var t:  float = float(i) / 11.0
		var sx: float = globe_cx - r * 0.75 + t * r * 1.5
		var sy: float = globe_cy + r * 0.25 + sin(t * PI) * r * 0.12
		pts.append(Vector2(sx, sy))
	draw_polyline(pts, speed_col, 1.5 * scale_f, true)
	# Arrowhead
	var tip := pts[pts.size() - 1]
	var arrow_pts := PackedVector2Array([
		tip + Vector2(-6 * scale_f, -4 * scale_f),
		tip,
		tip + Vector2(-6 * scale_f,  4 * scale_f),
	])
	draw_polyline(arrow_pts, speed_col, 1.2 * scale_f, true)

	# ── Globe outer ring ──────────────────────────────────────────────────────
	draw_arc(Vector2(globe_cx, globe_cy), r, 0, TAU, 64, Color(accent, 0.65), 1.5 * scale_f)

	# Cardinal dots
	for angle_deg in [0.0, 90.0, 180.0, 270.0]:
		var dp := Vector2(globe_cx + cos(deg_to_rad(angle_deg)) * r,
		                  globe_cy + sin(deg_to_rad(angle_deg)) * r)
		draw_circle(dp, 2.0 * scale_f, accent)

	if compact:
		return

	# ── Vertical divider ──────────────────────────────────────────────────────
	var div_x: float = globe_cx + r + 18.0 * scale_f
	draw_line(Vector2(div_x, globe_cy - r * 0.72),
	          Vector2(div_x, globe_cy + r * 0.72),
	          Color(accent, 0.28), 0.8 * scale_f)

	# ── Wordmark ──────────────────────────────────────────────────────────────
	if _serif_font:
		var tx: float = div_x + 14.0 * scale_f
		var title_size: int = int(28.0 * scale_f)
		draw_string(_serif_font, Vector2(tx, globe_cy - 6.0 * scale_f),
			"Wiki", HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, text_col)
		draw_string(_serif_font, Vector2(tx, globe_cy + title_size * 0.95),
			"Races", HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, text_col)

		var sub_size: int = int(8.0 * scale_f)
		draw_string(_serif_font, Vector2(tx, globe_cy + title_size * 1.80),
			"MUSEUM OF ALL THINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size,
			Color(sub_col, 0.70))
		draw_line(Vector2(tx, globe_cy + title_size * 1.90),
		          Vector2(tx + 140.0 * scale_f, globe_cy + title_size * 1.90),
		          Color(accent, 0.22), 0.7 * scale_f)
		draw_string(_serif_font, Vector2(tx, globe_cy + title_size * 2.08),
			"Multiplayer Tournament Edition", HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(6.5 * scale_f), Color(sub_col, 0.50))

	# ── Trophy glyph (top-right) ──────────────────────────────────────────────
	var tr_cx: float = w - 22.0 * scale_f
	var tr_cy: float = globe_cy - r * 0.30
	var tr_r:  float = 11.0 * scale_f
	# Cup body (simplified as arc + filled polygon)
	var cup_pts := PackedVector2Array()
	for i in 16:
		var a: float = deg_to_rad(180.0 + float(i) / 15.0 * 180.0)
		cup_pts.append(Vector2(tr_cx + cos(a) * tr_r, tr_cy + sin(a) * tr_r * 0.85))
	cup_pts.append(Vector2(tr_cx + tr_r, tr_cy))
	cup_pts.append(Vector2(tr_cx - tr_r, tr_cy))
	draw_colored_polygon(cup_pts, Color(gold, 0.85))
	# Handles
	draw_arc(Vector2(tr_cx - tr_r - 3 * scale_f, tr_cy + 2 * scale_f),
	         4.0 * scale_f, deg_to_rad(-60), deg_to_rad(200),
	         12, Color(accent, 0.60), 1.2 * scale_f)
	draw_arc(Vector2(tr_cx + tr_r + 3 * scale_f, tr_cy + 2 * scale_f),
	         4.0 * scale_f, deg_to_rad(-120), deg_to_rad(380),
	         12, Color(accent, 0.60), 1.2 * scale_f)
	# Stem + base
	draw_rect(Rect2(tr_cx - 2 * scale_f, tr_cy + tr_r * 0.85,
	               4 * scale_f, 5 * scale_f), Color(gold, 0.80))
	draw_rect(Rect2(tr_cx - 7 * scale_f, tr_cy + tr_r * 0.85 + 5 * scale_f,
	               14 * scale_f, 3 * scale_f), Color(gold, 0.80))


# ── Helpers ───────────────────────────────────────────────────────────────────

func _draw_ellipse_outline(centre: Vector2, rx: float, ry: float,
		color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var segs := 48
	for i in segs + 1:
		var a: float = float(i) / segs * TAU
		pts.append(Vector2(centre.x + cos(a) * rx, centre.y + sin(a) * ry))
	draw_polyline(pts, color, width, true)


func _draw_arc_wedge(cx: float, cy: float, r: float,
		a_start: float, a_end: float,
		fill_col: Color, stroke_col: Color, sf: float) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(cx, cy))
	var segs := 20
	for i in segs + 1:
		var a: float = a_start + (a_end - a_start) * float(i) / segs
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	pts.append(Vector2(cx, cy))
	draw_colored_polygon(pts, fill_col)
	draw_polyline(pts, stroke_col, 0.8 * sf, true)
