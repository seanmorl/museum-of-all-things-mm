extends Node
class_name PlayerPointingSystem
## Pointing system — laser beam, endpoint dot, and reaction bar.
##
## PUBLIC API (unchanged from original):
##   init(player)                              — call once on spawn
##   process_pointing()                        — call every _physics_process
##   apply_network_pointing(bool, Vector3)     — network sync for remote players
##   signal reaction_fired(index, target)      — emitted when player fires
##   var is_pointing : bool                    — read by network sync
##   var point_target : Vector3                — read by network sync

signal reaction_fired(reaction_index: int, point_target: Vector3)

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

const BEAM_LENGTH         : float = 100.0
const BEAM_COLOR          : Color = Color(1.0, 1.0, 0.7, 0.4)
const HIGHLIGHT_ENERGY    : float = 0.8
const HIGHLIGHT_RANGE     : float = 2.0
const RAY_COLLISION_MASK  : int   = 0xFFFFFFFF

const REACTION_NAMES      : Array[String] = ["!", "?", "star", "heart"]

# Reaction bar UI
const BAR_PIP_SIZE        : float = 28.0
const BAR_PIP_GAP         : float = 8.0
const BAR_PADDING         : float = 10.0
const BAR_ABOVE_CENTRE    : float = 60.0   # px above screen centre
const BAR_FADE_SPEED      : float = 12.0

const REACTION_DISPLAY    : Array[String] = ["!", "?", "★", "♥"]
const REACTION_COLORS     : Array[Color]  = [
	Color(1.00, 0.82, 0.20),   # gold  — !
	Color(0.28, 0.62, 1.00),   # blue  — ?
	Color(0.52, 0.88, 0.42),   # green — ★
	Color(1.00, 0.38, 0.42),   # red   — ♥
]

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

# Reaction bar HUD (local player only)
var _bar_root         : Control = null   # CanvasLayer child
var _bar_panel        : Control = null   # the drawn pill
var _bar_alpha        : float   = 0.0    # 0→1 animated
var _bar_selection    : int     = -1     # highlighted pip (-1 = none)

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

	# ── Reaction bar (local only) ─────────────────────────────────────────────
	if player.is_local:
		_build_reaction_bar()


# ─────────────────────────────────────────────────────────────────────────────
# REACTION BAR — built entirely in code
# ─────────────────────────────────────────────────────────────────────────────

func _build_reaction_bar() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 10
	_player.add_child(cl)

	# Full-screen transparent root
	_bar_root = Control.new()
	_bar_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_root.visible = false
	cl.add_child(_bar_root)

	# Pill panel — centred horizontally, above the crosshair
	var n       : int   = REACTION_DISPLAY.size()
	var pill_w  : float = BAR_PADDING * 2.0 + n * BAR_PIP_SIZE + (n - 1) * BAR_PIP_GAP
	var pill_h  : float = BAR_PIP_SIZE + BAR_PADDING * 2.0

	_bar_panel = Control.new()
	_bar_panel.custom_minimum_size = Vector2(pill_w, pill_h)
	_bar_panel.anchor_left   = 0.5
	_bar_panel.anchor_top    = 0.5
	_bar_panel.anchor_right  = 0.5
	_bar_panel.anchor_bottom = 0.5
	_bar_panel.offset_left   = -pill_w * 0.5
	_bar_panel.offset_right  =  pill_w * 0.5
	_bar_panel.offset_top    = -(BAR_ABOVE_CENTRE + pill_h)
	_bar_panel.offset_bottom = -BAR_ABOVE_CENTRE
	_bar_panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_bar_panel.draw.connect(_draw_bar)
	_bar_root.add_child(_bar_panel)


func _draw_bar() -> void:
	if not _bar_panel or _bar_alpha < 0.01:
		return

	var dark    : bool    = ThemeManager.is_dark_mode
	var font    : Font    = ThemeManager.get_reading_font()
	var sz      : Vector2 = _bar_panel.size
	var a       : float   = _bar_alpha

	# ── Pill background ───────────────────────────────────────────────────────
	var pill_r  : float = sz.y * 0.5
	var bg      : Color = Color(0.06, 0.07, 0.10, 0.80 * a) if dark \
						else Color(0.93, 0.94, 0.97, 0.90 * a)
	var border  : Color = Color(1.0, 1.0, 1.0, 0.14 * a) if dark \
						else Color(0.0, 0.0, 0.0, 0.10 * a)

	_bar_panel.draw_rect(
		Rect2(Vector2(pill_r, 0.0), Vector2(sz.x - pill_r * 2.0, sz.y)), bg)
	_bar_panel.draw_circle(Vector2(pill_r,          sz.y * 0.5), pill_r, bg)
	_bar_panel.draw_circle(Vector2(sz.x - pill_r,   sz.y * 0.5), pill_r, bg)
	_bar_panel.draw_arc(Vector2(pill_r,        sz.y * 0.5), pill_r - 0.5,
		PI * 0.5, PI * 1.5, 16, border, 1.0)
	_bar_panel.draw_arc(Vector2(sz.x - pill_r, sz.y * 0.5), pill_r - 0.5,
		-PI * 0.5, PI * 0.5, 16, border, 1.0)
	_bar_panel.draw_line(Vector2(pill_r, 0.5),       Vector2(sz.x - pill_r, 0.5),       border, 1.0)
	_bar_panel.draw_line(Vector2(pill_r, sz.y - 0.5),Vector2(sz.x - pill_r, sz.y - 0.5),border, 1.0)

	# ── Pips ──────────────────────────────────────────────────────────────────
	var n : int = REACTION_DISPLAY.size()
	for i in n:
		var selected  : bool  = (i == _bar_selection)
		var col       : Color = REACTION_COLORS[i]
		var cx        : float = BAR_PADDING + i * (BAR_PIP_SIZE + BAR_PIP_GAP) + BAR_PIP_SIZE * 0.5
		var cy        : float = sz.y * 0.5
		var r         : float = BAR_PIP_SIZE * 0.5

		# Pip fill — vivid when selected, subtle ring when idle
		_bar_panel.draw_circle(Vector2(cx, cy), r,
			Color(col, (0.88 if selected else 0.18) * a))
		_bar_panel.draw_arc(Vector2(cx, cy), r - 0.5, 0.0, TAU, 24,
			Color(col, (1.00 if selected else 0.50) * a), 1.4)

		# Outer glow when selected
		if selected:
			_bar_panel.draw_arc(Vector2(cx, cy), r + 4.0, 0.0, TAU, 24,
				Color(col, 0.30 * a), 2.0)

		# Reaction symbol
		if font:
			var sym  : String = REACTION_DISPLAY[i]
			var tw   : float  = font.get_string_size(
				sym, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var sc   : Color  = Color(1.0, 1.0, 1.0, (1.0 if selected else 0.70) * a)
			_bar_panel.draw_string(font,
				Vector2(cx - tw * 0.5, cy + 11.0 * 0.38),
				sym, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, sc)

		# Key hint (1/2/3/4) below pip
		if font:
			var hint : String = str(i + 1)
			var hw   : float  = font.get_string_size(
				hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			var hc   : Color  = Color(1.0, 1.0, 1.0, 0.28 * a) if dark \
							  else Color(0.0, 0.0, 0.0, 0.26 * a)
			_bar_panel.draw_string(font,
				Vector2(cx - hw * 0.5, cy + r + 9.0),
				hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, hc)


# ─────────────────────────────────────────────────────────────────────────────
# PROCESS  — signature matches original exactly (no delta argument)
# ─────────────────────────────────────────────────────────────────────────────

func process_pointing() -> void:
	if not _player or not _player.is_local:
		return

	var pointing_now : bool = (
		Input.is_action_pressed("point") and
		Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)

	# ── Toggle pointing state ─────────────────────────────────────────────────
	if pointing_now != is_pointing:
		is_pointing = pointing_now
		_beam_mesh.visible       = is_pointing
		_highlight_light.visible = is_pointing
		_endpoint_dot.visible    = is_pointing
		if not is_pointing:
			_reaction_index  = -1
			_bar_selection   = -1

	# ── Animate bar alpha (uses engine delta via process_frame time) ───────────
	# We approximate delta from Engine.get_process_frames since process_pointing
	# is called from _physics_process which has a fixed step
	var phys_dt : float = 1.0 / float(Engine.physics_ticks_per_second)
	var bar_target : float = 1.0 if is_pointing else 0.0
	_bar_alpha = move_toward(_bar_alpha, bar_target, BAR_FADE_SPEED * phys_dt)

	if _bar_panel:
		_bar_panel.queue_redraw()

	# Show/hide root control
	if _bar_root:
		if _bar_alpha > 0.01 and not _bar_root.visible:
			_bar_root.visible = true
		elif _bar_alpha < 0.01 and _bar_root.visible:
			_bar_root.visible = false

	if not is_pointing:
		return

	# ── Raycast ───────────────────────────────────────────────────────────────
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
		end          = result["position"]
		point_target = end
	else:
		end          = from + forward * BEAM_LENGTH
		point_target = end

	_update_beam(from, end)
	_highlight_light.global_position = end
	_endpoint_dot.global_position    = end

	# ── Reaction input ────────────────────────────────────────────────────────
	# Left/right arrow: preview-highlight a pip
	if Input.is_action_just_pressed("ui_left"):
		_bar_selection = posmod(_bar_selection - 1, REACTION_NAMES.size())
	elif Input.is_action_just_pressed("ui_right"):
		_bar_selection = (_bar_selection + 1) % REACTION_NAMES.size()

	# Keys 1-4: fire directly
	for i : int in REACTION_NAMES.size():
		if Input.is_action_just_pressed("reaction_%d" % (i + 1)):
			_reaction_index = i
			_bar_selection  = i
			_fire_reaction()
			return

	# Enter / ui_accept: fire highlighted selection
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
		_bar_selection  = -1


func _update_beam(from: Vector3, to: Vector3) -> void:
	var direction : Vector3 = to - from
	var length    : float   = direction.length()
	if length < 0.01:
		_beam_mesh.visible = false
		return
	_beam_mesh.visible = true

	var cylinder : CylinderMesh = CylinderMesh.new()
	cylinder.top_radius    = 0.002
	cylinder.bottom_radius = 0.002
	cylinder.height        = length
	_beam_mesh.mesh = cylinder

	_beam_mesh.global_position = (from + to) / 2.0
	_beam_mesh.look_at(to, Vector3.UP)
	_beam_mesh.rotate_object_local(Vector3.RIGHT, PI / 2.0)


# ─────────────────────────────────────────────────────────────────────────────
# NETWORK API  — signature unchanged
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
