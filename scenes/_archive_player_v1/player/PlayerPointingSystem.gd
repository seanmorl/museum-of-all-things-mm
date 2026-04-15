extends Node
class_name PlayerPointingSystem
## Pointing system — laser beam, endpoint dot, and modern radial reaction wheel.
## 
## This system allows players to point at objects in the 3D world and fire
## quick reactions (emojis/symbols) via a premium radial selection menu.

signal reaction_fired(reaction_index: int, point_target: Vector3)

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

const BEAM_LENGTH         : float = 100.0
const BEAM_COLOR          : Color = Color(1.0, 1.0, 0.7, 0.4)
const HIGHLIGHT_ENERGY    : float = 0.8
const HIGHLIGHT_RANGE     : float = 2.0
const RAY_COLLISION_MASK  : int   = 0xFFFFFFFF

# Reaction Catalogue (Synced with PointingController)
const REACTION_NAMES      : Array[String] = ["alert", "curious", "music", "heart", "star", "ok", "no", "look"]
const REACTION_DISPLAY    : Array[String] = ["!", "?", "♪", "❤", "★", "✓", "✗", "👁"]
const REACTION_COLORS     : Array[Color]  = [
	Color(1.00, 0.82, 0.20),   # gold    — !
	Color(0.35, 0.72, 1.00),   # blue    — ?
	Color(0.70, 0.45, 1.00),   # purple  — ♪
	Color(1.00, 0.30, 0.50),   # pink    — ❤
	Color(1.00, 0.95, 0.30),   # yellow  — ★
	Color(0.30, 0.90, 0.55),   # green   — ✓
	Color(1.00, 0.40, 0.30),   # red     — ✗
	Color(0.60, 0.90, 1.00),   # cyan    — 👁
]

# Wheel HUD Styling
const WHEEL_RADIUS_INNER  : float = 64.0
const WHEEL_RADIUS_OUTER  : float = 94.0
const WHEEL_RADIUS_CENTER : float = 44.0
const WHEEL_FADE_SPEED    : float = 16.0
const WHEEL_ROTATION_OFFSET : float = -PI / 2.0 # Start at top
const STEER_THRESHOLD     : float = 12.0 # px moved before selection starts
const STEER_MAX_LEN       : float = 120.0 # clamp mouse growth

# Theme Colors (Fallbacks if ThemeManager is missing)
const PANEL_BG_COLOR      : Color = Color(0, 0, 0, 0.8)
const PANEL_BORDER_COLOR  : Color = Color(0.635, 0.663, 0.694, 1.0)

# ─────────────────────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────────────────────

var _player           : CharacterBody3D = null

# 3D world nodes
var _beam_mesh        : MeshInstance3D  = null
var _highlight_light  : OmniLight3D     = null
var _endpoint_dot     : MeshInstance3D  = null

# Public — read by network sync
var is_pointing       : bool    = false
var point_target      : Vector3 = Vector3.ZERO

var _reaction_index   : int     = -1

# Radial HUD (local player only)
var _bar_root         : Control = null   # CanvasLayer child
var _bar_panel        : Control = null   # Drawing surface
var _bar_alpha        : float   = 0.0    # 0→1 animated
var _bar_selection    : int     = -1     # highlighted index (-1 = none)
var _mouse_accum      : Vector2 = Vector2.ZERO # Tracks relative motion

# ─────────────────────────────────────────────────────────────────────────────
# INIT
# ─────────────────────────────────────────────────────────────────────────────

func init(player: CharacterBody3D) -> void:
	_player = player

	# ── Beam ──────────────────────────────────────────────────────────────────
	_beam_mesh = MeshInstance3D.new()
	_beam_mesh.visible    = false
	_beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat : StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color               = BEAM_COLOR
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 1.0, 0.7)
	mat.emission_energy_multiplier = 1.0
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test              = false
	_beam_mesh.material_override   = mat
	player.add_child(_beam_mesh)

	# ── Highlight light ───────────────────────────────────────────────────────
	_highlight_light = OmniLight3D.new()
	_highlight_light.light_energy  = HIGHLIGHT_ENERGY
	_highlight_light.omni_range    = HIGHLIGHT_RANGE
	_highlight_light.light_color   = Color(1.0, 1.0, 0.8)
	_highlight_light.visible       = false
	_highlight_light.shadow_enabled = false
	player.add_child(_highlight_light)

	# ── Endpoint dot ──────────────────────────────────────────────────────────
	_endpoint_dot = MeshInstance3D.new()
	_endpoint_dot.visible    = false
	_endpoint_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dot_mesh : SphereMesh = SphereMesh.new()
	dot_mesh.radius = 0.02
	dot_mesh.height = 0.04
	_endpoint_dot.mesh = dot_mesh
	var dot_mat : StandardMaterial3D = StandardMaterial3D.new()
	dot_mat.albedo_color               = Color(1.0, 1.0, 0.7)
	dot_mat.emission_enabled           = true
	dot_mat.emission                   = Color(1.0, 1.0, 0.7)
	dot_mat.emission_energy_multiplier = 1.5
	dot_mat.no_depth_test              = false
	_endpoint_dot.material_override    = dot_mat
	player.add_child(_endpoint_dot)

	# ── Radial HUD (local only) ──────────────────────────────────────────────
	if player.is_local:
		_build_hud()


func _build_hud() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 12 # Above most other UI
	_player.add_child(cl)

	_bar_root = Control.new()
	_bar_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_root.visible = false
	cl.add_child(_bar_root)

	_bar_panel = Control.new()
	_bar_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_panel.draw.connect(_draw_hud)
	_bar_root.add_child(_bar_panel)
	
	if ThemeManager:
		ThemeManager.reading_font_changed.connect(func(_f): _bar_panel.queue_redraw())


# ─────────────────────────────────────────────────────────────────────────────
# HUD DRAWING
# ─────────────────────────────────────────────────────────────────────────────

func _draw_hud() -> void:
	if not _bar_panel or _bar_alpha < 0.01:
		return

	var font    : Font    = ThemeManager.get_reading_font() if ThemeManager else null
	var center  : Vector2 = _bar_panel.size * 0.5
	var a       : float   = _bar_alpha
	var n       : int     = REACTION_DISPLAY.size()
	
	# Current Palette
	var bg_col   : Color = (ThemeManager.bg_color if ThemeManager else PANEL_BG_COLOR) * Color(1, 1, 1, a)
	var bord_col : Color = (ThemeManager.border_color if ThemeManager else PANEL_BORDER_COLOR) * Color(1, 1, 1, a * 0.4)
	
	# ── Background Ring ───────────────────────────────────────────────────────
	var ring_r   : float = (WHEEL_RADIUS_INNER + WHEEL_RADIUS_OUTER) * 0.5
	var ring_th  : float = (WHEEL_RADIUS_OUTER - WHEEL_RADIUS_INNER)
	
	# Drawing the "glassy" donut
	_bar_panel.draw_arc(center, ring_r, 0, TAU, 120, bg_col, ring_th, true)
	_bar_panel.draw_arc(center, WHEEL_RADIUS_INNER, 0, TAU, 120, bord_col, 1.0, true)
	_bar_panel.draw_arc(center, WHEEL_RADIUS_OUTER, 0, TAU, 120, bord_col, 1.0, true)

	# ── Central Preview Hub ───────────────────────────────────────────────────
	_bar_panel.draw_circle(center, WHEEL_RADIUS_CENTER, bg_col)
	_bar_panel.draw_arc(center, WHEEL_RADIUS_CENTER, 0, TAU, 64, bord_col, 1.0, true)
	
	if _bar_selection >= 0:
		var sel_col : Color = REACTION_COLORS[_bar_selection]
		# Active selection ring
		_bar_panel.draw_arc(center, WHEEL_RADIUS_CENTER + 2.0, 0, TAU, 64, sel_col * Color(1, 1, 1, 0.4 * a), 2.0, true)
		
		# Big symbol in center
		if font:
			var sym : String = REACTION_DISPLAY[_bar_selection]
			var f_size : int = 36
			var s_size : Vector2 = font.get_string_size(sym, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size)
			_bar_panel.draw_string(font, center - s_size * 0.5 + Vector2(0, f_size * 0.38), 
				sym, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size, sel_col * Color(1, 1, 1, a))

	# ── Segments & Symbols ────────────────────────────────────────────────────
	var arc_step : float = TAU / n
	for i in n:
		var start : float = WHEEL_ROTATION_OFFSET + i * arc_step
		var end   : float = start + arc_step
		var mid   : float = (start + end) * 0.5
		var is_sel: bool  = (i == _bar_selection)
		var col   : Color = REACTION_COLORS[i]
		
		if is_sel:
			# Glow behind selected segment
			var g_pts : PackedVector2Array = []
			var res : int = 8
			for j in res + 1:
				var ang : float = start + (arc_step * j / res)
				g_pts.append(center + Vector2.from_angle(ang) * (WHEEL_RADIUS_OUTER + 5.0))
			for j in res + 1:
				var ang : float = end - (arc_step * j / res)
				g_pts.append(center + Vector2.from_angle(ang) * (WHEEL_RADIUS_INNER - 2.0))
			_bar_panel.draw_polygon(g_pts, PackedColorArray([col * Color(1, 1, 1, 0.15 * a)]))
			
			# Outer edge vivid line
			_bar_panel.draw_arc(center, WHEEL_RADIUS_OUTER + 4.0, start, end, 12, col * Color(1, 1, 1, a), 3.0, true)

		# Symbol
		var dist : float = (WHEEL_RADIUS_INNER + WHEEL_RADIUS_OUTER) * 0.5
		var pos  : Vector2 = center + Vector2.from_angle(mid) * dist
		
		if font:
			var sym : String = REACTION_DISPLAY[i]
			var f_size : int = 22 if is_sel else 16
			var s_size : Vector2 = font.get_string_size(sym, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size)
			var s_col  : Color = Color(1, 1, 1, (1.0 if is_sel else 0.5) * a)
			_bar_panel.draw_string(font, pos - s_size * 0.5 + Vector2(0, f_size * 0.38), 
				sym, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size, s_col)

		# Separator
		_bar_panel.draw_line(center + Vector2.from_angle(start) * (WHEEL_RADIUS_INNER + 4.0),
			center + Vector2.from_angle(start) * (WHEEL_RADIUS_OUTER - 4.0), bord_col * Color(1, 1, 1, 0.5), 1.0)


# ─────────────────────────────────────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not is_pointing or not _player or not _player.is_local:
		return
	
	if event is InputEventMouseMotion:
		_mouse_accum += event.relative
		_mouse_accum = _mouse_accum.limit_length(STEER_MAX_LEN)
		
		# Steering selection
		if _mouse_accum.length() > STEER_THRESHOLD:
			var n : int = REACTION_DISPLAY.size()
			var arc_step : float = TAU / n
			var angle : float = _mouse_accum.angle()
			var norm_angle := fposmod(angle - WHEEL_ROTATION_OFFSET, TAU)
			_bar_selection = int(norm_angle / arc_step) % n
		
		if _bar_panel:
			_bar_panel.queue_redraw()


func process_pointing() -> void:
	if not _player or not _player.is_local:
		return

	var pointing_now : bool = (
		Input.is_action_pressed("point") and
		Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)

	# ── State Toggles ─────────────────────────────────────────────────────────
	if pointing_now != is_pointing:
		if not pointing_now and is_pointing:
			# Fire on release if selected
			if _bar_selection >= 0:
				_reaction_index = _bar_selection
				_fire_reaction()
		
		is_pointing = pointing_now
		_beam_mesh.visible       = is_pointing
		_highlight_light.visible = is_pointing
		_endpoint_dot.visible    = is_pointing
		
		if not is_pointing:
			_bar_selection = -1
			_mouse_accum   = Vector2.ZERO

	# ── Visual Animations ─────────────────────────────────────────────────────
	var dt : float = 1.0 / float(Engine.physics_ticks_per_second)
	var target_a : float = 1.0 if is_pointing else 0.0
	_bar_alpha = move_toward(_bar_alpha, target_a, WHEEL_FADE_SPEED * dt)

	if _bar_root:
		_bar_root.visible = (_bar_alpha > 0.01)
	if _bar_panel:
		_bar_panel.queue_redraw()

	if not is_pointing:
		return

	# ── 3D World Interaction ──────────────────────────────────────────────────
	var camera  : Camera3D = _player.camera
	var from    : Vector3  = camera.global_position
	var forward : Vector3  = -camera.global_basis.z
	var end     : Vector3

	var space_state : PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var query : PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + forward * BEAM_LENGTH, RAY_COLLISION_MASK, [_player.get_rid()]
	)
	var result : Dictionary = space_state.intersect_ray(query)

	if not result.is_empty():
		end = result["position"]
	else:
		end = from + forward * BEAM_LENGTH
	
	point_target = end
	_update_beam(from, end)
	_highlight_light.global_position = end
	_endpoint_dot.global_position    = end

	# ── Direct Input (Keys & Scroll) ──────────────────────────────────────────
	# Scroll Wheel
	if Input.is_action_just_pressed("scroll_up"):
		_bar_selection = posmod(_bar_selection - 1, REACTION_NAMES.size())
	elif Input.is_action_just_pressed("scroll_down"):
		_bar_selection = (_bar_selection + 1) % REACTION_NAMES.size()

	# Hotkeys 1-8
	for i in REACTION_NAMES.size():
		if Input.is_action_just_pressed("reaction_%d" % (i + 1)):
			_reaction_index = i
			_bar_selection  = i
			_fire_reaction()
			return

	# Confirm selection (Enter)
	if Input.is_action_just_pressed("ui_accept") and _bar_selection >= 0:
		_reaction_index = _bar_selection
		_fire_reaction()


# ─────────────────────────────────────────────────────────────────────────────
# INTERNALS
# ─────────────────────────────────────────────────────────────────────────────

func _fire_reaction() -> void:
	if _reaction_index >= 0:
		reaction_fired.emit(_reaction_index, point_target)
		_reaction_index = -1
		# We don't clear _bar_selection here if we want it to stay highlighted while Q is held


func _update_beam(from: Vector3, to: Vector3) -> void:
	var direction : Vector3 = to - from
	var length    : float   = direction.length()
	if length < 0.01:
		_beam_mesh.visible = false
		return
	_beam_mesh.visible = true

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.002
	cyl.bottom_radius = 0.002
	cyl.height = length
	_beam_mesh.mesh = cyl

	_beam_mesh.global_position = (from + to) / 2.0
	_beam_mesh.look_at(to, Vector3.UP)
	_beam_mesh.rotate_object_local(Vector3.RIGHT, PI / 2.0)


# ─────────────────────────────────────────────────────────────────────────────
# NETWORK API
# ─────────────────────────────────────────────────────────────────────────────

func apply_network_pointing(pointing: bool, target: Vector3) -> void:
	is_pointing  = pointing
	point_target = target
	_beam_mesh.visible       = pointing
	_highlight_light.visible = pointing
	_endpoint_dot.visible    = pointing

	if pointing and _player:
		var from : Vector3 = _player.global_position + Vector3.UP * 1.5
		_update_beam(from, target)
		_highlight_light.global_position = target
		_endpoint_dot.global_position    = target
