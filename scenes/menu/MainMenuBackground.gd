@tool
extends Control
## Main menu background — "The Orrery" with cycling variants
##
## A living cosmic catalogue mechanism: concentric orbital rings rotate around
## a central focal node like a planetarium armillary sphere.  A vanishing-point
## grid suggests infinite depth.  Floating archive frames drift like museum
## index cards.  Vertical light pillars illuminate streaming dust.
##
## ─── Variant system ──────────────────────────────────────────────────────────
## Six visual "moods" cycle on each game launch (or return-to-menu), persisted
## via user://bg_variant.json so you never see the same one twice in a row.
##
##   0  The Orrery      — classic cool blue/indigo, balanced motion
##   1  The Archive      — warm amber/gold, slower drift, more frames
##   2  The Observatory  — deep teal/cyan, bright pillars, tighter rings
##   3  The Catalogue    — rose/mauve, many small frames, no grid
##   4  The Nexus        — high-contrast, fast spin, extra pillars
##   5  The Sanctum      — deep violet, minimal rings, heavy vignette, glacial

const VARIANT_FILE: String = "user://bg_variant.json"
const VARIANT_COUNT: int   = 6

# ── Base counts (overridden per-variant) ───────────────────────────────────────

const MAX_RINGS:   int = 9
const MAX_FRAMES:  int = 14
const MAX_PILLARS: int = 7
const MAX_MOTES:   int = 60
const GRID_ROWS:   int = 14
const GRID_COLS:   int = 22
const GRAD_PERIOD: float = 45.0

# ── Internal classes ───────────────────────────────────────────────────────────

class _OrbitalRing:
		var semi_a:     float
		var semi_b:     float
		var tilt:       float
		var tilt_speed: float
		var phase:      float
		var spin_speed: float
		var alpha:      float
		var has_node:   bool
		var node_phase: float
		var colour_id:  int

class _ArchiveFrame:
		var pos:       Vector2
		var size:      Vector2
		var rotation:  float
		var rot_speed: float
		var drift:     Vector2
		var alpha:     float
		var depth:     float
		var has_icon:  bool
		var icon_type: int

class _LightPillar:
		var x_frac:     float
		var width:      float
		var alpha:      float
		var drift_speed: float
		var phase:      float

class _Mote:
		var pos:        Vector2
		var radius:     float
		var speed:      Vector2
		var phase:      float
		var alpha:      float
		var pillar_idx: int

# ── Variant definition ─────────────────────────────────────────────────────────

class _Variant:
		var name:           String
		var ring_count:     int
		var frame_count:    int
		var pillar_count:   int
		var mote_count:     int
		var show_grid:      bool
		# Background gradient stops (dark mode) — top, mid, bottom
		var dark_a:         Color
		var dark_b:         Color
		var dark_c:         Color
		# Background gradient stops (light mode)
		var light_a:        Color
		var light_b:        Color
		var light_c:        Color
		# Ring palette (dark, light) — up to 9 entries each
		var ring_dark_pal:  Array[Color]
		var ring_light_pal: Array[Color]
		# Accent colours
		var accent_dark:    Color
		var accent_light:   Color
		var accent2_dark:   Color
		var accent2_light:  Color
		# Grid
		var grid_dark:      Color
		var grid_light:     Color
		var grid_alpha:     float
		# Pillar
		var pillar_dark:    Color
		var pillar_light:   Color
		var pillar_alpha:   float
		# Frame
		var frame_dark:     Color
		var frame_light:    Color
		var icon_dark:      Color
		var icon_light:     Color
		# Ring speed multiplier
		var ring_speed_mul: float
		# Ring eccentricity range (how elliptical)
		var eccentricity_min: float
		var eccentricity_max: float
		# Node chance (0..1)
		var node_chance:    float
		# Vignette
		var vignette_alpha: float
		# Central node position offset (fraction)
		var node_y_frac:    float

# ── State ──────────────────────────────────────────────────────────────────────

var _time: float = 0.0
var _vp_size: Vector2 = Vector2.ZERO
var _theme_t: float = 0.0
var _target_theme_t: float = 0.0
var _theme_tw: Tween = null
var _variant_idx: int = 0
var _v: _Variant = null   # active variant

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

		_variant_idx = _load_next_variant()
		_v = _build_variant(_variant_idx)
		_spawn_all()

		ThemeManager.dark_mode_changed.connect(_on_theme_changed)
		get_viewport().size_changed.connect(_resized)


func _process(delta: float) -> void:
		_time += delta
		var vp := _vp_size
		if vp == Vector2.ZERO:
				return

		var spd: float = _v.ring_speed_mul

		for r in _rings:
				r.tilt += r.tilt_speed * spd * delta
				r.phase += r.spin_speed * spd * delta
				if r.has_node:
						r.node_phase += r.spin_speed * spd * 1.8 * delta

		for f in _frames:
				f.pos += f.drift * delta * (0.3 + f.depth * 0.7)
				f.rotation += f.rot_speed * delta
				var pad := maxf(f.size.x, f.size.y) * 0.5 + 60.0
				if f.pos.x < -pad:     f.pos.x = vp.x + pad * 0.5
				elif f.pos.x > vp.x + pad: f.pos.x = -pad * 0.5
				if f.pos.y < -pad:     f.pos.y = vp.y + pad * 0.5
				elif f.pos.y > vp.y + pad: f.pos.y = -pad * 0.5

		for p in _pillars:
				p.x_frac += p.drift_speed * delta
				if p.x_frac < -0.05:   p.x_frac = 1.05
				elif p.x_frac > 1.05:  p.x_frac = -0.05
				p.alpha = _v.pillar_alpha + sin(_time * 0.18 + p.phase) * 0.006

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
# ║  Variant persistence                                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _load_next_variant() -> int:
		# Read the last-used index from disk, increment + wrap, save back.
		var last := -1
		var f := FileAccess.open(VARIANT_FILE, FileAccess.READ)
		if f:
				var txt := f.get_as_text()
				f.close()
				var parsed = JSON.parse_string(txt)
				if parsed is Dictionary and parsed.has("idx"):
						last = int(parsed.idx)
		# Cycle to the next variant (never repeat)
		var next := (last + 1) % VARIANT_COUNT
		# Persist
		var save_f := FileAccess.open(VARIANT_FILE, FileAccess.WRITE)
		if save_f:
				save_f.store_string(JSON.stringify({"idx": next}))
				save_f.close()
		return next


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Variant definitions                                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _build_variant(idx: int) -> _Variant:
		var v := _Variant.new()
		match idx:
				0:  _preset_orrery(v)
				1:  _preset_archive(v)
				2:  _preset_observatory(v)
				3:  _preset_catalogue(v)
				4:  _preset_nexus(v)
				5:  _preset_sanctum(v)
				_:  _preset_orrery(v)
		return v


func _preset_orrery(v: _Variant) -> void:
		# ── The Orrery: classic cool blue/indigo, balanced motion ─────────────
		v.name = "The Orrery"
		v.ring_count = 7;  v.frame_count = 8;  v.pillar_count = 4;  v.mote_count = 50
		v.show_grid = true
		v.dark_a  = Color(0.035, 0.040, 0.080); v.dark_b  = Color(0.025, 0.028, 0.055); v.dark_c  = Color(0.015, 0.018, 0.035)
		v.light_a = Color(0.950, 0.953, 0.970); v.light_b = Color(0.895, 0.905, 0.935); v.light_c = Color(0.840, 0.850, 0.895)
		v.ring_dark_pal  = [Color(0.25,0.50,0.85), Color(0.40,0.30,0.75), Color(0.80,0.65,0.25), Color(0.18,0.65,0.55), Color(0.60,0.35,0.50), Color(0.30,0.55,0.70), Color(0.55,0.50,0.30)]
		v.ring_light_pal = [Color(0.22,0.42,0.70), Color(0.35,0.25,0.62), Color(0.65,0.52,0.22), Color(0.14,0.52,0.44), Color(0.48,0.28,0.40), Color(0.26,0.45,0.58), Color(0.44,0.40,0.26)]
		v.accent_dark = Color(0.30, 0.55, 0.90);  v.accent_light = Color(0.45, 0.55, 0.75)
		v.accent2_dark = Color(0.85, 0.70, 0.30); v.accent2_light = Color(0.65, 0.55, 0.28)
		v.grid_dark = Color(0.15, 0.22, 0.40); v.grid_light = Color(0.60, 0.65, 0.78); v.grid_alpha = 0.04
		v.pillar_dark = Color(0.25, 0.45, 0.80); v.pillar_light = Color(0.50, 0.60, 0.80); v.pillar_alpha = 0.015
		v.frame_dark = Color(0.20, 0.40, 0.65);  v.frame_light = Color(0.45, 0.50, 0.65)
		v.icon_dark  = Color(0.25, 0.45, 0.70);  v.icon_light  = Color(0.40, 0.48, 0.62)
		v.ring_speed_mul = 1.0;  v.eccentricity_min = 0.25; v.eccentricity_max = 0.55; v.node_chance = 0.6
		v.vignette_alpha = 0.30;  v.node_y_frac = 0.45


func _preset_archive(v: _Variant) -> void:
		# ── The Archive: warm amber/gold, slower drift, more frames ───────────
		v.name = "The Archive"
		v.ring_count = 5;  v.frame_count = 14; v.pillar_count = 3;  v.mote_count = 40
		v.show_grid = true
		v.dark_a  = Color(0.070, 0.045, 0.025); v.dark_b  = Color(0.055, 0.035, 0.018); v.dark_c  = Color(0.035, 0.022, 0.012)
		v.light_a = Color(0.965, 0.955, 0.940); v.light_b = Color(0.925, 0.910, 0.885); v.light_c = Color(0.880, 0.860, 0.830)
		v.ring_dark_pal  = [Color(0.75,0.55,0.20), Color(0.65,0.45,0.18), Color(0.55,0.40,0.22), Color(0.80,0.60,0.25), Color(0.50,0.35,0.15)]
		v.ring_light_pal = [Color(0.60,0.45,0.18), Color(0.52,0.38,0.16), Color(0.44,0.33,0.18), Color(0.65,0.48,0.22), Color(0.40,0.28,0.12)]
		v.accent_dark = Color(0.80, 0.60, 0.22);  v.accent_light = Color(0.65, 0.48, 0.20)
		v.accent2_dark = Color(0.60, 0.40, 0.18); v.accent2_light = Color(0.48, 0.32, 0.15)
		v.grid_dark = Color(0.30, 0.22, 0.12); v.grid_light = Color(0.72, 0.65, 0.55); v.grid_alpha = 0.03
		v.pillar_dark = Color(0.60, 0.45, 0.20); v.pillar_light = Color(0.70, 0.55, 0.35); v.pillar_alpha = 0.018
		v.frame_dark = Color(0.55, 0.40, 0.22);  v.frame_light = Color(0.65, 0.52, 0.35)
		v.icon_dark  = Color(0.60, 0.42, 0.18);  v.icon_light  = Color(0.55, 0.42, 0.25)
		v.ring_speed_mul = 0.55; v.eccentricity_min = 0.30; v.eccentricity_max = 0.50; v.node_chance = 0.4
		v.vignette_alpha = 0.35; v.node_y_frac = 0.48


func _preset_observatory(v: _Variant) -> void:
		# ── The Observatory: deep teal/cyan, bright pillars, tighter rings ────
		v.name = "The Observatory"
		v.ring_count = 9;  v.frame_count = 5;  v.pillar_count = 6;  v.mote_count = 55
		v.show_grid = true
		v.dark_a  = Color(0.020, 0.045, 0.065); v.dark_b  = Color(0.015, 0.035, 0.050); v.dark_c  = Color(0.010, 0.022, 0.035)
		v.light_a = Color(0.940, 0.960, 0.970); v.light_b = Color(0.885, 0.910, 0.935); v.light_c = Color(0.830, 0.860, 0.900)
		v.ring_dark_pal  = [Color(0.15,0.55,0.60), Color(0.10,0.50,0.65), Color(0.20,0.60,0.55), Color(0.12,0.45,0.58), Color(0.18,0.58,0.50), Color(0.22,0.52,0.62), Color(0.14,0.48,0.55), Color(0.25,0.55,0.45), Color(0.10,0.42,0.52)]
		v.ring_light_pal = [Color(0.12,0.45,0.50), Color(0.08,0.40,0.52), Color(0.16,0.48,0.44), Color(0.10,0.36,0.46), Color(0.14,0.46,0.40), Color(0.18,0.42,0.50), Color(0.11,0.38,0.44), Color(0.20,0.44,0.36), Color(0.08,0.34,0.42)]
		v.accent_dark = Color(0.15, 0.60, 0.65);  v.accent_light = Color(0.25, 0.55, 0.60)
		v.accent2_dark = Color(0.20, 0.65, 0.55); v.accent2_light = Color(0.30, 0.55, 0.48)
		v.grid_dark = Color(0.10, 0.28, 0.38); v.grid_light = Color(0.55, 0.70, 0.75); v.grid_alpha = 0.05
		v.pillar_dark = Color(0.15, 0.50, 0.60); v.pillar_light = Color(0.40, 0.60, 0.65); v.pillar_alpha = 0.022
		v.frame_dark = Color(0.15, 0.40, 0.50);  v.frame_light = Color(0.35, 0.52, 0.58)
		v.icon_dark  = Color(0.18, 0.45, 0.52);  v.icon_light  = Color(0.30, 0.50, 0.55)
		v.ring_speed_mul = 0.8; v.eccentricity_min = 0.20; v.eccentricity_max = 0.45; v.node_chance = 0.7
		v.vignette_alpha = 0.28; v.node_y_frac = 0.42


func _preset_catalogue(v: _Variant) -> void:
		# ── The Catalogue: rose/mauve, many small frames, no grid ─────────────
		v.name = "The Catalogue"
		v.ring_count = 5;  v.frame_count = 12; v.pillar_count = 3;  v.mote_count = 45
		v.show_grid = false
		v.dark_a  = Color(0.055, 0.030, 0.055); v.dark_b  = Color(0.042, 0.022, 0.042); v.dark_c  = Color(0.028, 0.015, 0.028)
		v.light_a = Color(0.960, 0.945, 0.955); v.light_b = Color(0.920, 0.900, 0.915); v.light_c = Color(0.875, 0.850, 0.870)
		v.ring_dark_pal  = [Color(0.60,0.30,0.50), Color(0.55,0.25,0.55), Color(0.50,0.35,0.45), Color(0.65,0.28,0.42), Color(0.45,0.30,0.52)]
		v.ring_light_pal = [Color(0.48,0.25,0.40), Color(0.44,0.20,0.44), Color(0.40,0.28,0.36), Color(0.52,0.22,0.34), Color(0.36,0.24,0.42)]
		v.accent_dark = Color(0.65, 0.30, 0.50);  v.accent_light = Color(0.52, 0.28, 0.42)
		v.accent2_dark = Color(0.55, 0.25, 0.55); v.accent2_light = Color(0.44, 0.22, 0.44)
		v.grid_dark = Color(0.20, 0.15, 0.20); v.grid_light = Color(0.65, 0.55, 0.62); v.grid_alpha = 0.0
		v.pillar_dark = Color(0.50, 0.25, 0.45); v.pillar_light = Color(0.60, 0.38, 0.52); v.pillar_alpha = 0.012
		v.frame_dark = Color(0.45, 0.25, 0.40);  v.frame_light = Color(0.55, 0.35, 0.48)
		v.icon_dark  = Color(0.50, 0.28, 0.42);  v.icon_light  = Color(0.48, 0.32, 0.40)
		v.ring_speed_mul = 0.7; v.eccentricity_min = 0.30; v.eccentricity_max = 0.55; v.node_chance = 0.5
		v.vignette_alpha = 0.32; v.node_y_frac = 0.46


func _preset_nexus(v: _Variant) -> void:
		# ── The Nexus: high-contrast, faster spin, extra pillars ──────────────
		v.name = "The Nexus"
		v.ring_count = 8;  v.frame_count = 6;  v.pillar_count = 7;  v.mote_count = 60
		v.show_grid = true
		v.dark_a  = Color(0.050, 0.055, 0.090); v.dark_b  = Color(0.038, 0.042, 0.070); v.dark_c  = Color(0.025, 0.028, 0.048)
		v.light_a = Color(0.945, 0.950, 0.968); v.light_b = Color(0.888, 0.898, 0.930); v.light_c = Color(0.832, 0.845, 0.890)
		v.ring_dark_pal  = [Color(0.30,0.55,0.90), Color(0.50,0.35,0.85), Color(0.85,0.70,0.25), Color(0.20,0.70,0.60), Color(0.70,0.35,0.50), Color(0.35,0.60,0.75), Color(0.60,0.50,0.30), Color(0.40,0.30,0.70)]
		v.ring_light_pal = [Color(0.25,0.45,0.75), Color(0.40,0.28,0.68), Color(0.68,0.55,0.22), Color(0.16,0.55,0.48), Color(0.55,0.28,0.40), Color(0.28,0.48,0.60), Color(0.48,0.40,0.25), Color(0.32,0.24,0.56)]
		v.accent_dark = Color(0.40, 0.60, 0.95);  v.accent_light = Color(0.50, 0.58, 0.78)
		v.accent2_dark = Color(0.90, 0.75, 0.30); v.accent2_light = Color(0.70, 0.58, 0.25)
		v.grid_dark = Color(0.18, 0.25, 0.45); v.grid_light = Color(0.62, 0.68, 0.80); v.grid_alpha = 0.05
		v.pillar_dark = Color(0.30, 0.50, 0.85); v.pillar_light = Color(0.55, 0.62, 0.82); v.pillar_alpha = 0.020
		v.frame_dark = Color(0.25, 0.42, 0.68);  v.frame_light = Color(0.48, 0.52, 0.68)
		v.icon_dark  = Color(0.28, 0.48, 0.72);  v.icon_light  = Color(0.42, 0.50, 0.65)
		v.ring_speed_mul = 1.6; v.eccentricity_min = 0.20; v.eccentricity_max = 0.50; v.node_chance = 0.75
		v.vignette_alpha = 0.25; v.node_y_frac = 0.43


func _preset_sanctum(v: _Variant) -> void:
		# ── The Sanctum: deep violet, minimal rings, heavy vignette, glacial ──
		v.name = "The Sanctum"
		v.ring_count = 3;  v.frame_count = 4;  v.pillar_count = 2;  v.mote_count = 30
		v.show_grid = false
		v.dark_a  = Color(0.040, 0.020, 0.060); v.dark_b  = Color(0.030, 0.015, 0.045); v.dark_c  = Color(0.020, 0.010, 0.030)
		v.light_a = Color(0.948, 0.942, 0.960); v.light_b = Color(0.890, 0.880, 0.910); v.light_c = Color(0.835, 0.822, 0.860)
		v.ring_dark_pal  = [Color(0.40,0.20,0.60), Color(0.50,0.25,0.55), Color(0.35,0.18,0.55)]
		v.ring_light_pal = [Color(0.32,0.16,0.48), Color(0.40,0.20,0.44), Color(0.28,0.14,0.44)]
		v.accent_dark = Color(0.45, 0.22, 0.62);  v.accent_light = Color(0.38, 0.22, 0.52)
		v.accent2_dark = Color(0.55, 0.20, 0.50); v.accent2_light = Color(0.44, 0.18, 0.42)
		v.grid_dark = Color(0.15, 0.10, 0.22); v.grid_light = Color(0.58, 0.52, 0.68); v.grid_alpha = 0.0
		v.pillar_dark = Color(0.35, 0.18, 0.55); v.pillar_light = Color(0.48, 0.32, 0.58); v.pillar_alpha = 0.010
		v.frame_dark = Color(0.30, 0.18, 0.45);  v.frame_light = Color(0.42, 0.30, 0.50)
		v.icon_dark  = Color(0.35, 0.20, 0.48);  v.icon_light  = Color(0.38, 0.25, 0.45)
		v.ring_speed_mul = 0.3; v.eccentricity_min = 0.35; v.eccentricity_max = 0.55; v.node_chance = 0.33
		v.vignette_alpha = 0.42; v.node_y_frac = 0.50


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Drawing — all layers read from active variant                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _draw() -> void:
		var vp := _vp_size
		if vp == Vector2.ZERO:
				return
		var t: float = (sin(_time / GRAD_PERIOD * TAU) + 1.0) * 0.5
		var tr: float = clampf(_theme_t, 0.0, 1.0)

		_draw_background(vp, t, tr)
		if _v.show_grid:
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
		var col_a: Color = _v.dark_a.lerp(_v.light_a, tr).lerp(_v.dark_a.lerp(_v.light_a, tr), t * 0.15)
		var col_b: Color = _v.dark_b.lerp(_v.light_b, tr).lerp(_v.dark_b.lerp(_v.light_b, tr), t * 0.15)
		var col_c: Color = _v.dark_c.lerp(_v.light_c, tr).lerp(_v.dark_c.lerp(_v.light_c, tr), t * 0.15)

		var steps := 48
		for i in steps:
				var y0: float = vp.y * float(i) / steps
				var y1: float = vp.y * float(i + 1) / steps
				var f: float = float(i) / (steps - 1)
				var c: Color = col_a.lerp(col_b, f * 2.0) if f < 0.5 else col_b.lerp(col_c, (f - 0.5) * 2.0)
				draw_rect(Rect2(0.0, y0, vp.x, y1 - y0 + 1.0), c)


# ── Layer 1: Depth grid ────────────────────────────────────────────────────────

func _draw_depth_grid(vp: Vector2, tr: float) -> void:
		var grid_col: Color = _v.grid_dark.lerp(_v.grid_light, tr)
		var base_alpha: float = _v.grid_alpha * (1.0 - tr * 0.6)
		var cx := vp.x * 0.5
		var horizon_y := vp.y * 0.55

		for i in GRID_ROWS:
				var frac := float(i) / float(GRID_ROWS)
				var exp_f := pow(frac, 2.2)
				var y := horizon_y + (vp.y - horizon_y) * exp_f
				var a := base_alpha * (1.0 - exp_f * 0.7) * smoothstep(0.0, 0.15, frac)
				if a > 0.001:
						draw_line(Vector2(0.0, y), Vector2(vp.x, y), Color(grid_col, a), 1.0)

		for i in GRID_COLS:
				var frac := float(i) / float(GRID_COLS - 1)
				var bottom_x := vp.x * frac
				var top_x := cx + (bottom_x - cx) * 0.05
				var a := base_alpha * 0.6 * clampf(1.0 - abs(frac - 0.5) * 2.0, 0.0, 1.0)
				if a > 0.001:
						draw_line(Vector2(top_x, horizon_y), Vector2(bottom_x, vp.y), Color(grid_col, a), 1.0)


# ── Layer 2: Light pillars ─────────────────────────────────────────────────────

func _draw_light_pillars(vp: Vector2, tr: float) -> void:
		var pillar_col: Color = _v.pillar_dark.lerp(_v.pillar_light, tr)
		for p in _pillars:
				if p.alpha < 0.001:
						continue
				var px := p.x_frac * vp.x
				var hw := p.width * 0.5
				var pts := PackedVector2Array([
						Vector2(px - hw * 1.2, 0.0),  Vector2(px + hw * 1.2, 0.0),
						Vector2(px + hw * 0.6, vp.y), Vector2(px - hw * 0.6, vp.y),
				])
				draw_colored_polygon(pts, Color(pillar_col, p.alpha))


# ── Layer 3: Motes streaming through pillars ───────────────────────────────────

func _draw_pillar_motes(vp: Vector2, tr: float) -> void:
		var acc: Color = _v.accent_dark.lerp(_v.accent_light, tr)
		for m in _motes:
				if m.pillar_idx < 0:
						continue
				var p := _pillars[m.pillar_idx]
				var px := p.x_frac * vp.x
				var dist_x := absf(m.pos.x - px)
				if dist_x >= p.width * 0.8:
						continue
				var pulse := (sin(_time * 2.0 + m.phase) + 1.0) * 0.5
				var beam_bright := 1.0 - dist_x / (p.width * 0.8)
				var a := m.alpha * (0.4 + pulse * 0.6) * beam_bright * (1.0 - tr * 0.3)
				if a > 0.003:
						draw_circle(m.pos, m.radius * 2.0, Color(acc, a * 0.3))
						draw_circle(m.pos, m.radius, Color(acc, a))


# ── Layer 4: Orbital rings ────────────────────────────────────────────────────

func _draw_orbital_rings(vp: Vector2, tr: float) -> void:
		var cx := vp.x * 0.5
		var cy: float = vp.y * _v.node_y_frac
		var scale_base: float = min(vp.x, vp.y) * 0.35
		var segs := 80

		for r in _rings:
				var pal_idx: int = r.colour_id % _v.ring_dark_pal.size()
				var ring_col: Color = _v.ring_dark_pal[pal_idx].lerp(_v.ring_light_pal[pal_idx], tr)
				var ring_alpha: float = r.alpha * (1.0 - tr * 0.35)

				var pts := PackedVector2Array()
				var cos_t: float = cos(r.tilt)
				var sin_t: float = sin(r.tilt)
				var sa: float = scale_base * r.semi_a
				var sb: float = scale_base * r.semi_b

				for i in segs + 1:
						var angle: float = r.phase + (TAU * float(i) / float(segs))
						var ex: float = cos(angle) * sa
						var ey: float = sin(angle) * sb
						var rx: float = ex * cos_t - ey * sin_t
						var ry: float = ex * sin_t + ey * cos_t
						pts.append(Vector2(cx + rx, cy + ry))

				for i in pts.size() - 1:
						var angle: float = r.phase + (TAU * float(i) / float(segs))
						var depth_fade: float = 0.5 + 0.5 * sin(angle + r.tilt)
						var seg_a := ring_alpha * (0.3 + depth_fade * 0.7)
						draw_line(pts[i], pts[i + 1], Color(ring_col, seg_a), 1.2, true)

				if r.has_node:
						var na: float = r.node_phase
						var nex: float = cos(na) * sa
						var ney: float = sin(na) * sb
						var nrx: float = nex * cos_t - ney * sin_t
						var nry: float = nex * sin_t + ney * cos_t
						var node_pos := Vector2(cx + nrx, cy + nry)
						var node_alpha: float = ring_alpha * 1.5 * (0.5 + 0.5 * sin(na + r.tilt))
						draw_circle(node_pos, 6.0, Color(ring_col, node_alpha * 0.3))
						draw_circle(node_pos, 3.0, Color(ring_col, node_alpha * 0.6))
						draw_circle(node_pos, 1.5, Color(ring_col, node_alpha))


# ── Layer 5: Central node ─────────────────────────────────────────────────────

func _draw_central_node(vp: Vector2, tr: float) -> void:
		var cx := vp.x * 0.5
		var cy: float = vp.y * _v.node_y_frac
		var accent: Color = _v.accent_dark.lerp(_v.accent_light, tr)
		var pulse := (sin(_time * 0.6) + 1.0) * 0.5
		var base_a := (0.04 + pulse * 0.015) * (1.0 - tr * 0.4)
		var r_base: float = min(vp.x, vp.y) * 0.02

		for i in range(5):
				var r: float = r_base * (1.0 + i * 1.8) + sin(_time * 0.3 + i) * 3.0
				draw_circle(Vector2(cx, cy), r, Color(accent, base_a * (1.0 - float(i) * 0.18)))

		draw_circle(Vector2(cx, cy), r_base * 0.6, Color(accent, base_a * 2.5))

		var ch_len: float = r_base * 1.5
		var ch_a := base_a * 1.8
		draw_line(Vector2(cx - ch_len, cy), Vector2(cx + ch_len, cy), Color(accent, ch_a), 1.0, true)
		draw_line(Vector2(cx, cy - ch_len), Vector2(cx, cy + ch_len), Color(accent, ch_a), 1.0, true)


# ── Layer 6: Archive frames ────────────────────────────────────────────────────

func _draw_archive_frames(vp: Vector2, tr: float) -> void:
		var frame_col: Color = _v.frame_dark.lerp(_v.frame_light, tr)
		var icon_col: Color = _v.icon_dark.lerp(_v.icon_light, tr)

		for f in _frames:
				var edge := _edge_fade_point(f.pos, vp)
				var a := f.alpha * edge * (0.12 + f.depth * 0.08) * (1.0 - tr * 0.35)
				if a < 0.003:
						continue

				var hw := f.size.x * 0.5;  var hh := f.size.y * 0.5
				var cos_r := cos(f.rotation);  var sin_r := sin(f.rotation)
				var corners := [Vector2(-hw,-hh), Vector2(hw,-hh), Vector2(hw,hh), Vector2(-hw,hh)]
				var world := PackedVector2Array()
				for c in corners:
						world.append(f.pos + Vector2(c.x*cos_r - c.y*sin_r, c.x*sin_r + c.y*cos_r))

				for i in 4:
						draw_line(world[i], world[(i+1)%4], Color(frame_col, a), 1.0, true)
				for w in world:
						draw_circle(w, 1.5, Color(frame_col, a * 1.3))

				if f.has_icon:
						var icon_a := a * 0.8
						match f.icon_type:
								0:  draw_circle(f.pos, 4.0, Color(icon_col, icon_a * 0.5))
								1:
										var tri := PackedVector2Array()
										for v in 3:
												var angle := f.rotation + TAU*float(v)/3.0 - TAU/4.0
												tri.append(f.pos + Vector2(cos(angle),sin(angle))*5.0)
										for v in 3:
												draw_line(tri[v], tri[(v+1)%3], Color(icon_col, icon_a), 1.0, true)
								2:
										var d := 5.0
										var dm := [f.pos+Vector2(0,-d), f.pos+Vector2(d*0.6,0), f.pos+Vector2(0,d), f.pos+Vector2(-d*0.6,0)]
										for v in 4:
												draw_line(dm[v], dm[(v+1)%4], Color(icon_col, icon_a), 1.0, true)
								3:
										var d := 4.0
										draw_line(f.pos+Vector2(-d,0), f.pos+Vector2(d,0), Color(icon_col, icon_a), 1.0, true)
										draw_line(f.pos+Vector2(0,-d), f.pos+Vector2(0,d), Color(icon_col, icon_a), 1.0, true)


# ── Layer 7: Free motes ────────────────────────────────────────────────────────

func _draw_free_motes(vp: Vector2, tr: float) -> void:
		var acc: Color = _v.accent_dark.lerp(_v.accent_light, tr)
		var acc2: Color = _v.accent2_dark.lerp(_v.accent2_light, tr)

		for m in _motes:
				if m.pillar_idx >= 0:
						continue
				var pulse := (sin(_time * 1.5 + m.phase) + 1.0) * 0.5
				var a := m.alpha * (0.3 + pulse * 0.7) * _edge_fade_point(m.pos, vp) * (1.0 - tr * 0.3)
				if a < 0.003:
						continue
				var col := acc if m.phase < 4.0 else acc2
				draw_circle(m.pos, m.radius * 2.5, Color(col, a * 0.15))
				draw_circle(m.pos, m.radius, Color(col, a))


# ── Layer 8: Vignette ─────────────────────────────────────────────────────────

func _draw_vignette(vp: Vector2, tr: float) -> void:
		var cx := vp.x * 0.5;  var cy := vp.y * 0.5
		var vig_alpha: float = _v.vignette_alpha * (1.0 - tr * 0.8)
		var vig_col := Color(0.0, 0.0, 0.0, vig_alpha)
		var r_outer := vp.length() * 0.55
		var r_inner := vp.length() * 0.20
		var segs := 64
		for i in segs:
				var a0 := float(i)/segs*TAU;  var a1 := float(i+1)/segs*TAU
				var pts := PackedVector2Array([
						Vector2(cx+cos(a0)*r_inner, cy+sin(a0)*r_inner),
						Vector2(cx+cos(a0)*r_outer, cy+sin(a0)*r_outer),
						Vector2(cx+cos(a1)*r_outer, cy+sin(a1)*r_outer),
						Vector2(cx+cos(a1)*r_inner, cy+sin(a1)*r_inner),
				])
				draw_colored_polygon(pts, vig_col)


# ── Helpers ────────────────────────────────────────────────────────────────────

func _edge_fade_point(pos: Vector2, vp: Vector2) -> float:
		var m := 100.0
		return clampf(pos.y/m, 0.0, 1.0) * clampf((vp.y-pos.y)/m, 0.0, 1.0) \
				 * clampf(pos.x/m, 0.0, 1.0) * clampf((vp.x-pos.x)/m, 0.0, 1.0)


func smoothstep(edge0: float, edge1: float, x: float) -> float:
		var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
		return t * t * (3.0 - 2.0 * t)


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Spawning — reads from active variant                                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

func _spawn_all() -> void:
		var vp := _vp_size
		if vp == Vector2.ZERO:
				vp = Vector2(1280, 720)

		_rings.clear();  _frames.clear();  _pillars.clear();  _motes.clear()

		for i in _v.ring_count:
				var r := _OrbitalRing.new()
				r.semi_a = randf_range(0.35, 1.15)
				r.semi_b = r.semi_a * randf_range(_v.eccentricity_min, _v.eccentricity_max)
				r.tilt = randf() * TAU
				r.tilt_speed = randf_range(-0.03, 0.03)
				r.phase = randf() * TAU
				r.spin_speed = randf_range(-0.08, 0.08)
				r.alpha = randf_range(0.15, 0.45)
				r.has_node = randf() < _v.node_chance
				r.node_phase = randf() * TAU
				r.colour_id = i
				_rings.append(r)

		for i in _v.frame_count:
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
				f.drift = Vector2(cos(angle), sin(angle)) * randf_range(2.0, 8.0) * (0.3 + f.depth * 0.7)
				f.alpha = randf_range(0.3, 0.8)
				f.has_icon = randf() < 0.55
				f.icon_type = randi() % 4
				_frames.append(f)

		for i in _v.pillar_count:
				var p := _LightPillar.new()
				p.x_frac = randf_range(0.1, 0.9)
				p.width = randf_range(60.0, 150.0)
				p.alpha = _v.pillar_alpha
				p.drift_speed = randf_range(-0.003, 0.003)
				p.phase = randf() * TAU
				_pillars.append(p)

		for i in _v.mote_count:
				var m := _Mote.new()
				_reset_mote(m, vp)
				m.pos.y = randf() * (vp.y + 50.0) - 25.0
				m.pos.x = randf() * (vp.x + 50.0) - 25.0
				if randf() < 0.6 and _pillars.size() > 0:
						m.pillar_idx = randi() % _pillars.size()
						m.pos.x = _pillars[m.pillar_idx].x_frac * vp.x + randf_range(-30.0, 30.0)
						m.speed = Vector2(randf_range(-2.0, 2.0), randf_range(-15.0, -5.0))
				else:
						m.pillar_idx = -1
				_motes.append(m)


func _reset_mote(m: _Mote, vp: Vector2) -> void:
		m.radius = randf_range(1.0, 2.5)
		if m.pillar_idx >= 0 and m.pillar_idx < _pillars.size():
				var px := _pillars[m.pillar_idx].x_frac * vp.x
				m.pos = Vector2(px + randf_range(-40.0, 40.0), vp.y + m.radius + randf_range(0.0, 40.0))
				m.speed = Vector2(randf_range(-2.0, 2.0), randf_range(-15.0, -5.0))
		else:
				if randf() < 0.7:
						m.pos = Vector2(randf()*(vp.x+40.0)-20.0, vp.y+m.radius+randf_range(0.0,60.0))
				else:
						m.pos = Vector2(randf_range(-10.0, vp.x+10.0), randf()*vp.y)
				m.speed = Vector2(randf_range(-4.0,4.0), randf_range(-10.0,-3.0))
		m.phase = randf() * TAU
		m.alpha = randf_range(0.1, 0.4)


func _resized() -> void:
		_vp_size = get_viewport_rect().size
		queue_redraw()


# ── Public API ────────────────────────────────────────────────────────────────

func get_variant_name() -> String:
		if _v:
				return _v.name
		return "The Orrery"
