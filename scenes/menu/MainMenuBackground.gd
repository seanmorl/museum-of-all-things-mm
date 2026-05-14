@tool
extends Control
## Main menu background — "The Orrery"
##
## A living cosmic catalogue mechanism: concentric orbital rings rotate around
## a central focal node like a planetarium armillary sphere.  A vanishing-point
## grid suggests infinite depth.  Floating archive frames drift like museum
## index cards.  Vertical light pillars illuminate streaming dust.  The whole
## scene breathes — colours shift, rings precess, particles flow — evoking the
## quiet grandeur of an infinite museum of all things.

# ── Configuration ──────────────────────────────────────────────────────────────

const RING_COUNT:      int   = 7
const FRAME_COUNT:     int   = 8
const PILLAR_COUNT:    int   = 4
const MOTE_COUNT:      int   = 50
const GRID_ROWS:       int   = 14
const GRID_COLS:       int   = 22
const GRAD_PERIOD:     float = 45.0

# ── Internal classes ───────────────────────────────────────────────────────────

class _OrbitalRing:
	var semi_a:    float       # horizontal radius
	var semi_b:    float       # vertical radius  (elliptical)
	var tilt:      float       # rotation of the ellipse itself (radians)
	var tilt_speed: float      # how fast the ellipse precesses
	var phase:     float       # current angle offset
	var spin_speed: float      # how fast a marker dot orbits
	var alpha:     float
	var has_node:  bool        # does this ring carry a visible dot?
	var node_phase: float      # angle of the marker dot
	var colour_id: int

class _ArchiveFrame:
	var pos:       Vector2
	var size:      Vector2     # width, height of the rectangle
	var rotation:  float       # slight tilt
	var rot_speed: float
	var drift:     Vector2
	var alpha:     float
	var depth:     float       # 0..1 parallax
	var has_icon:  bool        # draw a small symbol inside?
	var icon_type: int         # 0=circle, 1=triangle, 2=diamond, 3=cross

class _LightPillar:
	var x_frac:    float       # 0..1 position across viewport
	var width:     float
	var alpha:     float
	var drift_speed: float     # horizontal drift
	var phase:     float

class _Mote:
	var pos:       Vector2
	var radius:    float
	var speed:     Vector2
	var phase:     float
	var alpha:     float
	var pillar_idx: int        # which pillar this mote belongs to (-1 = free)

# ── State ──────────────────────────────────────────────────────────────────────

var _time: float = 0.0
var _vp_size: Vector2 = Vector2.ZERO
var _theme_t: float = 0.0
var _target_theme_t: float = 0.0
var _theme_tw: Tween = null

var _rings: Array[_OrbitalRing] = []
var _frames: Array[_ArchiveFrame] = []
var _pillars: Array[_LightPillar] = []
var _motes: Array[_Mote] = []

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp_size = get_viewport_rect().size
	_theme_t = 0.0 if ThemeManager.is_dark_mode else 1.0
	_target_theme_t = _theme_t
	_spawn_all()
	ThemeManager.dark_mode_changed.connect(_on_theme_changed)
	get_viewport().size_changed.connect(_resized)


func _process(delta: float) -> void:
	_time += delta
	var vp := _vp_size
	if vp == Vector2.ZERO:
		return

	# Precess orbital rings
	for r in _rings:
		r.tilt += r.tilt_speed * delta
		r.phase += r.spin_speed * delta
		if r.has_node:
			r.node_phase += r.spin_speed * 1.8 * delta

	# Drift archive frames
	for f in _frames:
		f.pos += f.drift * delta * (0.3 + f.depth * 0.7)
		f.rotation += f.rot_speed * delta
		var pad := maxf(f.size.x, f.size.y) * 0.5 + 60.0
		if f.pos.x < -pad:
			f.pos.x = vp.x + pad * 0.5
		elif f.pos.x > vp.x + pad:
			f.pos.x = -pad * 0.5
		if f.pos.y < -pad:
			f.pos.y = vp.y + pad * 0.5
		elif f.pos.y > vp.y + pad:
			f.pos.y = -pad * 0.5

	# Drift light pillars
	for p in _pillars:
		p.x_frac += p.drift_speed * delta
		if p.x_frac < -0.05:
			p.x_frac = 1.05
		elif p.x_frac > 1.05:
			p.x_frac = -0.05
		p.alpha = (0.015 + sin(_time * 0.18 + p.phase) * 0.008)

	# Update motes
	for m in _motes:
		m.pos += m.speed * delta
		m.pos.x += sin(_time * 0.4 + m.phase) * 1.5 * delta
		if m.pos.y < -20.0 or m.pos.x < -20.0 or m.pos.x > vp.x + 20.0 or m.pos.y > vp.y + 20.0:
			_reset_mote(m, vp)

	queue_redraw()


func _on_theme_changed(_d: bool) -> void:
	if _theme_tw and _theme_tw.is_valid():
		_theme_tw.kill()
	_target_theme_t = 1.0 if not ThemeManager.is_dark_mode else 0.0
	_theme_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_theme_tw.tween_method(func(v): _theme_t = v, _theme_t, _target_theme_t, 0.6)


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Drawing — 8 layers, back to front                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _draw() -> void:
	var vp := _vp_size
	if vp == Vector2.ZERO:
		return

	var t: float = (sin(_time / GRAD_PERIOD * TAU) + 1.0) * 0.5
	var tr: float = clampf(_theme_t, 0.0, 1.0)

	_draw_background(vp, t, tr)
	_draw_depth_grid(vp, tr)
	_draw_light_pillars(vp, tr)
	_draw_pillar_motes(vp, tr)
	_draw_orbital_rings(vp, tr)
	_draw_central_node(vp, tr)
	_draw_archive_frames(vp, tr)
	_draw_free_motes(vp, tr)
	_draw_vignette(vp, tr)


# ── Layer 0: Background gradient ───────────────────────────────────────────────

func _draw_background(vp: Vector2, t: float, tr: float) -> void:
	# Deep indigo → near-black vertical gradient with slow breathing
	var dark_a := Color(0.035, 0.040, 0.080, 1.0).lerp(Color(0.050, 0.055, 0.095, 1.0), t)
	var dark_b := Color(0.025, 0.028, 0.055, 1.0).lerp(Color(0.035, 0.038, 0.068, 1.0), t)
	var dark_c := Color(0.015, 0.018, 0.035, 1.0).lerp(Color(0.020, 0.022, 0.042, 1.0), t)
	var light_a := Color(0.950, 0.953, 0.970, 1.0).lerp(Color(0.960, 0.963, 0.978, 1.0), t)
	var light_b := Color(0.895, 0.905, 0.935, 1.0).lerp(Color(0.915, 0.922, 0.948, 1.0), t)
	var light_c := Color(0.840, 0.850, 0.895, 1.0).lerp(Color(0.855, 0.865, 0.910, 1.0), t)
	var col_a := dark_a.lerp(light_a, tr)
	var col_b := dark_b.lerp(light_b, tr)
	var col_c := dark_c.lerp(light_c, tr)

	var steps := 48
	for i in steps:
		var y0: float = vp.y * float(i) / steps
		var y1: float = vp.y * float(i + 1) / steps
		var f: float = float(i) / (steps - 1)
		var c: Color = col_a.lerp(col_b, f * 2.0) if f < 0.5 else col_b.lerp(col_c, (f - 0.5) * 2.0)
		draw_rect(Rect2(0.0, y0, vp.x, y1 - y0 + 1.0), c)


# ── Layer 1: Vanishing-point depth grid ────────────────────────────────────────

func _draw_depth_grid(vp: Vector2, tr: float) -> void:
	# A perspective floor grid that converges on the centre, suggesting
	# infinite museum corridors stretching into the distance.
	var dark_grid := Color(0.15, 0.22, 0.40)
	var light_grid := Color(0.60, 0.65, 0.78)
	var grid_col := dark_grid.lerp(light_grid, tr)
	var base_alpha := 0.04 * (1.0 - tr * 0.6)

	var cx := vp.x * 0.5
	var cy := vp.y * 0.48  # vanishing point slightly above centre
	var horizon_y := vp.y * 0.55

	# Horizontal lines — exponentially spaced below the horizon
	for i in GRID_ROWS:
		var frac := float(i) / float(GRID_ROWS)
		# Exponential spacing makes lines denser near the horizon
		var exp_f := pow(frac, 2.2)
		var y := horizon_y + (vp.y - horizon_y) * exp_f
		var a := base_alpha * (1.0 - exp_f * 0.7)
		# Fade in from horizon
		a *= smoothstep(0.0, 0.15, frac)
		if a > 0.001:
			draw_line(Vector2(0.0, y), Vector2(vp.x, y), Color(grid_col, a), 1.0)

	# Vertical lines — converge toward the vanishing point
	for i in GRID_COLS:
		var frac := float(i) / float(GRID_COLS - 1)
		var bottom_x := vp.x * frac
		# Each line goes from bottom of screen toward vanishing point
		var top_x := cx + (bottom_x - cx) * 0.05  # converge near centre
		var a := base_alpha * 0.6
		# Fade out lines near the edges
		var edge_fade: float = 1.0 - abs(frac - 0.5) * 2.0
		edge_fade = clampf(edge_fade, 0.0, 1.0)
		a *= edge_fade
		if a > 0.001:
			draw_line(
				Vector2(top_x, horizon_y),
				Vector2(bottom_x, vp.y),
				Color(grid_col, a), 1.0
			)


# ── Layer 2: Light pillars ─────────────────────────────────────────────────────

func _draw_light_pillars(vp: Vector2, tr: float) -> void:
	var dark_pillar := Color(0.25, 0.45, 0.80)
	var light_pillar := Color(0.50, 0.60, 0.80)
	var pillar_col := dark_pillar.lerp(light_pillar, tr)

	for p in _pillars:
		if p.alpha < 0.001:
			continue
		var px := p.x_frac * vp.x
		var hw := p.width * 0.5
		# Soft vertical column — wider at the top, narrower at the base
		var top_w := hw * 1.2
		var bot_w := hw * 0.6
		var pts := PackedVector2Array([
			Vector2(px - top_w, 0.0),
			Vector2(px + top_w, 0.0),
			Vector2(px + bot_w, vp.y),
			Vector2(px - bot_w, vp.y),
		])
		draw_colored_polygon(pts, Color(pillar_col, p.alpha))


# ── Layer 3: Motes streaming through light pillars ─────────────────────────────

func _draw_pillar_motes(vp: Vector2, tr: float) -> void:
	var dark_acc := Color(0.35, 0.55, 0.90)
	var light_acc := Color(0.45, 0.55, 0.75)
	var acc := dark_acc.lerp(light_acc, tr)

	for m in _motes:
		if m.pillar_idx < 0:
			continue
		var p := _pillars[m.pillar_idx]
		# Brightness boost when near the pillar's x position
		var px := p.x_frac * vp.x
		var dist_x := absf(m.pos.x - px)
		var in_beam := dist_x < p.width * 0.8
		if not in_beam:
			continue
		var pulse := (sin(_time * 2.0 + m.phase) + 1.0) * 0.5
		var beam_bright := 1.0 - (dist_x / (p.width * 0.8))
		var a := m.alpha * (0.4 + pulse * 0.6) * beam_bright * (1.0 - tr * 0.3)
		if a > 0.003:
			draw_circle(m.pos, m.radius * 2.0, Color(acc, a * 0.3))
			draw_circle(m.pos, m.radius, Color(acc, a))


# ── Layer 4: Orbital rings (the armillary / orrery) ───────────────────────────

func _draw_orbital_rings(vp: Vector2, tr: float) -> void:
	var cx := vp.x * 0.5
	var cy := vp.y * 0.45
	var scale_base: float = min(vp.x, vp.y) * 0.35

	var dark_pal := [
		Color(0.25, 0.50, 0.85),   # blue
		Color(0.40, 0.30, 0.75),   # purple
		Color(0.80, 0.65, 0.25),   # gold
		Color(0.18, 0.65, 0.55),   # teal
		Color(0.60, 0.35, 0.50),   # rose
		Color(0.30, 0.55, 0.70),   # steel blue
		Color(0.55, 0.50, 0.30),   # bronze
	]
	var light_pal := [
		Color(0.22, 0.42, 0.70),
		Color(0.35, 0.25, 0.62),
		Color(0.65, 0.52, 0.22),
		Color(0.14, 0.52, 0.44),
		Color(0.48, 0.28, 0.40),
		Color(0.26, 0.45, 0.58),
		Color(0.44, 0.40, 0.26),
	]

	var segs := 80  # segments per ellipse

	for r in _rings:
		var ring_col: Color = dark_pal[r.colour_id].lerp(light_pal[r.colour_id], tr)
		var ring_alpha := r.alpha * (1.0 - tr * 0.35)

		# Build the ellipse as a series of line segments, rotated by r.tilt
		var pts := PackedVector2Array()
		var cos_t: float = cos(r.tilt)
		var sin_t: float = sin(r.tilt)
		var sa: float = scale_base * r.semi_a
		var sb: float = scale_base * r.semi_b

		for i in segs + 1:
			var angle: float = r.phase + (TAU * float(i) / float(segs))
			var ex: float = cos(angle) * sa
			var ey: float = sin(angle) * sb
			# Rotate by tilt
			var rx: float = ex * cos_t - ey * sin_t
			var ry: float = ex * sin_t + ey * cos_t
			pts.append(Vector2(cx + rx, cy + ry))

		# Draw the ring
		for i in pts.size() - 1:
			# Depth fade: segments near the "back" of the ring are fainter
			var angle := r.phase + (TAU * float(i) / float(segs))
			var depth_fade := 0.5 + 0.5 * sin(angle + r.tilt)
			var seg_a := ring_alpha * (0.3 + depth_fade * 0.7)
			draw_line(pts[i], pts[i + 1], Color(ring_col, seg_a), 1.2, true)

		# Draw marker node on ring
		if r.has_node:
			var na: float = r.node_phase
			var nex: float = cos(na) * sa
			var ney: float = sin(na) * sb
			var nrx: float = nex * cos_t - ney * sin_t
			var nry: float = nex * sin_t + ney * cos_t
			var node_pos := Vector2(cx + nrx, cy + nry)
			var node_alpha: float = ring_alpha * 1.5 * (0.5 + 0.5 * sin(na + r.tilt))
			# Glow
			draw_circle(node_pos, 6.0, Color(ring_col, node_alpha * 0.3))
			draw_circle(node_pos, 3.0, Color(ring_col, node_alpha * 0.6))
			draw_circle(node_pos, 1.5, Color(ring_col, node_alpha))


# ── Layer 5: Central focal node ───────────────────────────────────────────────

func _draw_central_node(vp: Vector2, tr: float) -> void:
	# A bright point at the centre of the orrery — the "catalogue index"
	var cx := vp.x * 0.5
	var cy := vp.y * 0.45
	var dark_acc := Color(0.30, 0.55, 0.90)
	var light_acc := Color(0.45, 0.55, 0.75)
	var accent := dark_acc.lerp(light_acc, tr)

	var pulse: float = (sin(_time * 0.6) + 1.0) * 0.5
	var base_a: float = (0.04 + pulse * 0.015) * (1.0 - tr * 0.4)
	var r_base: float = min(vp.x, vp.y) * 0.02

	# Outer glow rings
	for i in range(5):
		var r: float = r_base * (1.0 + i * 1.8) + sin(_time * 0.3 + i) * 3.0
		draw_circle(Vector2(cx, cy), r, Color(accent, base_a * (1.0 - float(i) * 0.18)))

	# Core
	draw_circle(Vector2(cx, cy), r_base * 0.6, Color(accent, base_a * 2.5))

	# Tiny cross-hair
	var ch_len: float = r_base * 1.5
	var ch_a := base_a * 1.8
	draw_line(Vector2(cx - ch_len, cy), Vector2(cx + ch_len, cy), Color(accent, ch_a), 1.0, true)
	draw_line(Vector2(cx, cy - ch_len), Vector2(cx, cy + ch_len), Color(accent, ch_a), 1.0, true)


# ── Layer 6: Floating archive frames ──────────────────────────────────────────

func _draw_archive_frames(vp: Vector2, tr: float) -> void:
	# Thin rectangular outlines that drift across the scene, like museum
	# information cards or catalogue entries floating in zero gravity.
	var dark_frame := Color(0.20, 0.40, 0.65)
	var light_frame := Color(0.45, 0.50, 0.65)
	var frame_col := dark_frame.lerp(light_frame, tr)

	var dark_icon := Color(0.25, 0.45, 0.70)
	var light_icon := Color(0.40, 0.48, 0.62)
	var icon_col := dark_icon.lerp(light_icon, tr)

	for f in _frames:
		var edge := _edge_fade_point(f.pos, vp)
		var a := f.alpha * edge * (0.12 + f.depth * 0.08) * (1.0 - tr * 0.35)
		if a < 0.003:
			continue

		# Build rotated rectangle
		var hw := f.size.x * 0.5
		var hh := f.size.y * 0.5
		var cos_r := cos(f.rotation)
		var sin_r := sin(f.rotation)
		var corners := [
			Vector2(-hw, -hh), Vector2(hw, -hh),
			Vector2(hw, hh), Vector2(-hw, hh),
		]
		var world := PackedVector2Array()
		for c in corners:
			world.append(f.pos + Vector2(c.x * cos_r - c.y * sin_r, c.x * sin_r + c.y * cos_r))

		# Draw frame outline
		for i in 4:
			draw_line(world[i], world[(i + 1) % 4], Color(frame_col, a), 1.0, true)

		# Corner dots
		for w in world:
			draw_circle(w, 1.5, Color(frame_col, a * 1.3))

		# Small icon inside
		if f.has_icon:
			var icon_a := a * 0.8
			match f.icon_type:
				0:  # circle
					draw_circle(f.pos, 4.0, Color(icon_col, icon_a * 0.5))
				1:  # triangle
					var tri := PackedVector2Array()
					for v in 3:
						var angle := f.rotation + TAU * float(v) / 3.0 - TAU / 4.0
						tri.append(f.pos + Vector2(cos(angle), sin(angle)) * 5.0)
					for v in 3:
						draw_line(tri[v], tri[(v + 1) % 3], Color(icon_col, icon_a), 1.0, true)
				2:  # diamond
					var d := 5.0
					var diamond := [
						f.pos + Vector2(0, -d), f.pos + Vector2(d * 0.6, 0),
						f.pos + Vector2(0, d), f.pos + Vector2(-d * 0.6, 0),
					]
					for v in 4:
						draw_line(diamond[v], diamond[(v + 1) % 4], Color(icon_col, icon_a), 1.0, true)
				3:  # cross
					var d := 4.0
					draw_line(f.pos + Vector2(-d, 0), f.pos + Vector2(d, 0), Color(icon_col, icon_a), 1.0, true)
					draw_line(f.pos + Vector2(0, -d), f.pos + Vector2(0, d), Color(icon_col, icon_a), 1.0, true)


# ── Layer 7: Free-floating motes ───────────────────────────────────────────────

func _draw_free_motes(vp: Vector2, tr: float) -> void:
	var dark_acc := Color(0.35, 0.55, 0.90)
	var light_acc := Color(0.45, 0.55, 0.75)
	var acc := dark_acc.lerp(light_acc, tr)
	var dark_acc2 := Color(0.85, 0.70, 0.30)
	var light_acc2 := Color(0.65, 0.55, 0.28)
	var acc2 := dark_acc2.lerp(light_acc2, tr)

	for m in _motes:
		if m.pillar_idx >= 0:
			continue  # drawn in pillar pass
		var pulse := (sin(_time * 1.5 + m.phase) + 1.0) * 0.5
		var a := m.alpha * (0.3 + pulse * 0.7) * _edge_fade_point(m.pos, vp) * (1.0 - tr * 0.3)
		if a < 0.003:
			continue
		var col := acc if m.phase < 4.0 else acc2
		draw_circle(m.pos, m.radius * 2.5, Color(col, a * 0.15))
		draw_circle(m.pos, m.radius, Color(col, a))


# ── Layer 8: Vignette ─────────────────────────────────────────────────────────

func _draw_vignette(vp: Vector2, tr: float) -> void:
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	var vig_alpha := 0.30 * (1.0 - tr * 0.8)
	var vig_col := Color(0.0, 0.0, 0.0, vig_alpha)
	var r_outer := vp.length() * 0.55
	var r_inner := vp.length() * 0.20
	var segs := 64

	for i in segs:
		var a0 := float(i) / segs * TAU
		var a1 := float(i + 1) / segs * TAU
		var pts := PackedVector2Array([
			Vector2(cx + cos(a0) * r_inner, cy + sin(a0) * r_inner),
			Vector2(cx + cos(a0) * r_outer, cy + sin(a0) * r_outer),
			Vector2(cx + cos(a1) * r_outer, cy + sin(a1) * r_outer),
			Vector2(cx + cos(a1) * r_inner, cy + sin(a1) * r_inner),
		])
		draw_colored_polygon(pts, vig_col)


# ── Helpers ────────────────────────────────────────────────────────────────────

func _edge_fade_point(pos: Vector2, vp: Vector2) -> float:
	var m := 100.0
	return clampf(pos.y / m, 0.0, 1.0) * clampf((vp.y - pos.y) / m, 0.0, 1.0) \
		 * clampf(pos.x / m, 0.0, 1.0) * clampf((vp.x - pos.x) / m, 0.0, 1.0)


func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ── Spawning ───────────────────────────────────────────────────────────────────

func _spawn_all() -> void:
	var vp := _vp_size
	if vp == Vector2.ZERO:
		vp = Vector2(1280, 720)

	# Orbital rings — concentric ellipses with varying sizes and speeds
	for i in RING_COUNT:
		var r := _OrbitalRing.new()
		r.semi_a = randf_range(0.35, 1.15)
		r.semi_b = r.semi_a * randf_range(0.25, 0.55)  # flatten to ellipse
		r.tilt = randf() * TAU
		r.tilt_speed = randf_range(-0.03, 0.03)  # slow precession
		r.phase = randf() * TAU
		r.spin_speed = randf_range(-0.08, 0.08)  # rotation of the ring itself
		r.alpha = randf_range(0.15, 0.45)
		r.has_node = randf() < 0.6  # 60% chance of having a marker dot
		r.node_phase = randf() * TAU
		r.colour_id = i % 7
		_rings.append(r)

	# Archive frames — thin floating rectangles
	for i in FRAME_COUNT:
		var f := _ArchiveFrame.new()
		f.depth = randf()
		f.size = Vector2(
			randf_range(30.0, 70.0) * (0.6 + f.depth * 0.4),
			randf_range(20.0, 50.0) * (0.6 + f.depth * 0.4),
		)
		f.pos = Vector2(randf() * vp.x, randf() * vp.y)
		f.rotation = randf_range(-0.15, 0.15)
		f.rot_speed = randf_range(-0.02, 0.02)
		var angle := randf() * TAU
		var speed := randf_range(2.0, 8.0) * (0.3 + f.depth * 0.7)
		f.drift = Vector2(cos(angle), sin(angle)) * speed
		f.alpha = randf_range(0.3, 0.8)
		f.has_icon = randf() < 0.55
		f.icon_type = randi() % 4
		_frames.append(f)

	# Light pillars
	for i in PILLAR_COUNT:
		var p := _LightPillar.new()
		p.x_frac = randf_range(0.1, 0.9)
		p.width = randf_range(60.0, 150.0)
		p.alpha = 0.015
		p.drift_speed = randf_range(-0.003, 0.003)
		p.phase = randf() * TAU
		_pillars.append(p)

	# Motes — some belong to pillars, some are free-floating
	for i in MOTE_COUNT:
		var m := _Mote.new()
		_reset_mote(m, vp)
		m.pos.y = randf() * (vp.y + 50.0) - 25.0
		m.pos.x = randf() * (vp.x + 50.0) - 25.0
		# Assign ~60% of motes to a pillar
		if randf() < 0.6 and _pillars.size() > 0:
			m.pillar_idx = randi() % _pillars.size()
			# Spawn near the pillar
			var px := _pillars[m.pillar_idx].x_frac * vp.x
			m.pos.x = px + randf_range(-30.0, 30.0)
			m.speed = Vector2(randf_range(-2.0, 2.0), randf_range(-15.0, -5.0))
		else:
			m.pillar_idx = -1
		_motes.append(m)


func _reset_mote(m: _Mote, vp: Vector2) -> void:
	m.radius = randf_range(1.0, 2.5)
	if m.pillar_idx >= 0 and m.pillar_idx < _pillars.size():
		# Respawn near the pillar
		var px := _pillars[m.pillar_idx].x_frac * vp.x
		m.pos = Vector2(px + randf_range(-40.0, 40.0), vp.y + m.radius + randf_range(0.0, 40.0))
		m.speed = Vector2(randf_range(-2.0, 2.0), randf_range(-15.0, -5.0))
	else:
		if randf() < 0.7:
			m.pos = Vector2(randf() * (vp.x + 40.0) - 20.0, vp.y + m.radius + randf_range(0.0, 60.0))
		else:
			m.pos = Vector2(randf_range(-10.0, vp.x + 10.0), randf() * vp.y)
		m.speed = Vector2(randf_range(-4.0, 4.0), randf_range(-10.0, -3.0))
	m.phase = randf() * TAU
	m.alpha = randf_range(0.1, 0.4)


func _resized() -> void:
	_vp_size = get_viewport_rect().size
	queue_redraw()
