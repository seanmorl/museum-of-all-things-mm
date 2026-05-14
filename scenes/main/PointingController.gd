extends Node
class_name PointingController
## PointingController — redesigned reaction & pointing system.
##
## Improvements over the original:
##   • 8 reaction types with distinct icons, colours, and scale animations.
##   • Per-player cooldown so reactions can't be spammed.
##   • Optional 3D directional beam that draws a brief line from the pointer
##     to the pointed-at position (useful for multiplayer "look here" moments).
##   • Layered animation: pop-in scale, rise, colour-fade, pop-out.
##   • Chime pitch is varied per reaction type for audio variety.
##   • spawn_reaction() is safe to call from the network (just pass world_pos).

# ── Reaction catalogue ────────────────────────────────────────────────────────

## Each entry: [display_text, Color, pitch_scale, pop_scale]
const REACTIONS: Array = [
	["!",   Color(1.00, 0.82, 0.20, 1.0), 1.20, 1.5],   # 0 — alert / gold
	["?",   Color(0.35, 0.72, 1.00, 1.0), 0.95, 1.3],   # 1 — curious / blue
	["♪",   Color(0.70, 0.45, 1.00, 1.0), 1.05, 1.4],   # 2 — music / purple
	["❤",   Color(1.00, 0.30, 0.50, 1.0), 1.10, 1.6],   # 3 — heart / pink
	["★",   Color(1.00, 0.95, 0.30, 1.0), 1.30, 1.8],   # 4 — star / yellow
	["✓",   Color(0.30, 0.90, 0.55, 1.0), 1.15, 1.3],   # 5 — ok / green
	["✗",   Color(1.00, 0.40, 0.30, 1.0), 0.80, 1.3],   # 6 — no / red
	["👁",  Color(0.60, 0.90, 1.00, 1.0), 1.00, 1.4],   # 7 — look here / cyan
]

## Animation constants
const RISE_DISTANCE  : float = 3.2   ## world units risen over lifetime
const LIFETIME       : float = 2.4   ## seconds before the label disappears
const FONT_SIZE_BASE : int   = 88
const CHIME_VOL_DB   : float = -8.0

## Per-sender cooldown (seconds).  Prevents reaction flooding.
const COOLDOWN_SECS  : float = 0.6

## Beam (pointer line) — drawn when pointing at something in the world
const BEAM_LIFETIME  : float = 0.9
const BEAM_WIDTH     : float = 0.06  ## cylinder radius in world units
const BEAM_COLOR     : Color = Color(1.0, 1.0, 1.0, 0.45)

const CHIME_SOUND: String = "res://assets/sound/UI/UI Crystal 1.ogg"

# ── State ─────────────────────────────────────────────────────────────────────

var _main         : Node         = null
var _chime        : AudioStream  = null
var _beam_cyl     : CylinderMesh = null
var _beam_mat     : StandardMaterial3D = null

## peer_id → Time.get_unix_time_from_system() of last reaction
var _cooldowns    : Dictionary   = {}

# =============================================================================
# Init
# =============================================================================

func init(main: Node) -> void:
	_main = main
	_load_chime_sound()
	_init_beam_cache()


func _load_chime_sound() -> void:
	if not ResourceLoader.exists(CHIME_SOUND):
		Log.error("PointingController", "Chime sound not found: %s" % CHIME_SOUND)
		return
	var res: Resource = ResourceLoader.load(CHIME_SOUND, "AudioStream", ResourceLoader.CACHE_MODE_REUSE)
	if res is AudioStream:
		_chime = res
	else:
		Log.error("PointingController", "Resource is not an AudioStream: %s" % CHIME_SOUND)


func _init_beam_cache() -> void:
	_beam_cyl = CylinderMesh.new()
	_beam_cyl.top_radius = BEAM_WIDTH
	_beam_cyl.bottom_radius = BEAM_WIDTH

	_beam_mat = StandardMaterial3D.new()
	_beam_mat.albedo_color      = BEAM_COLOR
	_beam_mat.flags_transparent = true
	_beam_mat.shading_mode      = BaseMaterial3D.SHADING_MODE_UNSHADED


# =============================================================================
# Public API
# =============================================================================

## Spawn a floating reaction above world_pos.
## sender_id is the network peer_id of whoever triggered it (0 = local / no check).
func spawn_reaction(reaction_index: int, world_pos: Vector3, sender_id: int = 0) -> void:
	if reaction_index < 0 or reaction_index >= REACTIONS.size():
		push_warning("PointingController: invalid reaction_index %d" % reaction_index)
		return

	# Cooldown check
	if sender_id != 0:
		var now : float = Time.get_unix_time_from_system()
		if _cooldowns.get(sender_id, 0.0) + COOLDOWN_SECS > now:
			return
		_cooldowns[sender_id] = now

	var entry     : Array  = REACTIONS[reaction_index]
	var text      : String = entry[0]
	var col       : Color  = entry[1]
	var pitch     : float  = entry[2]
	var pop_scale : float  = entry[3]

	# --- Label3D ---
	var label := Label3D.new()
	label.text          = text
	label.font_size     = FONT_SIZE_BASE
	label.modulate      = col
	label.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 1
	_main.add_child(label)

	var start_pos : Vector3 = world_pos + Vector3.UP * 1.2
	var end_pos   : Vector3 = start_pos + Vector3.UP * RISE_DISTANCE
	label.global_position = start_pos
	label.scale           = Vector3.ZERO

	# Pop-in → rise → fade out
	var tw := label.create_tween()
	tw.set_parallel(false)

	# 1. Pop in (scale up quickly)
	tw.tween_property(label, "scale",
		Vector3.ONE * pop_scale, 0.12
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 2. Settle to 1× (brief)
	tw.tween_property(label, "scale",
		Vector3.ONE, 0.08
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 3. Rise + fade in parallel (restart parallel section)
	var rise_tw := label.create_tween().set_parallel(true)
	rise_tw.tween_property(label, "global_position", end_pos,    LIFETIME - 0.2 ).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rise_tw.tween_property(label, "modulate:a",      0.0,        LIFETIME * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(LIFETIME * 0.45)
	rise_tw.chain().tween_callback(label.queue_free)

	# --- Sparkle burst ---
	_spawn_sparkle_burst(world_pos, col)

	# --- Chime ---
	_play_chime(pitch)


## Draw a brief glowing beam between two world positions
## (e.g. from a player's hand to a point of interest).
func spawn_beam(from: Vector3, to: Vector3) -> void:
	var mid    : Vector3 = (from + to) * 0.5
	var length : float   = from.distance_to(to)
	if length < 0.1:
		return

	var mesh_inst := MeshInstance3D.new()
	_beam_cyl.height = length
	mesh_inst.mesh = _beam_cyl
	mesh_inst.material_override = _beam_mat
	_main.add_child(mesh_inst)
	mesh_inst.global_position = mid

	# Orient cylinder from→to
	var dir : Vector3 = (to - from).normalized()
	if dir.dot(Vector3.UP) < 0.999:
		mesh_inst.look_at(to, Vector3.UP)
		mesh_inst.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	# else it's perfectly vertical — leave default

	# Fade out and remove
	var tw := mesh_inst.create_tween()
	tw.tween_property(mesh_inst, "modulate:a", 0.0, BEAM_LIFETIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mesh_inst.queue_free)


## Convenience: point at a world position from an origin (combines beam + reaction).
## reaction_index 7 ("👁 look here") is used by default.
func point_at(origin: Vector3, target: Vector3, sender_id: int = 0, reaction: int = 7) -> void:
	spawn_beam(origin, target)
	spawn_reaction(reaction, target, sender_id)


## Clear the cooldown for a specific peer (call on disconnect, etc.)
func clear_cooldown(sender_id: int) -> void:
	_cooldowns.erase(sender_id)


# =============================================================================
# Internal helpers
# =============================================================================

func _spawn_sparkle_burst(pos: Vector3, color: Color) -> void:
	## Spawn a small burst of 4-6 spark particles that spread outward and fade.
	var spark_count := randi() % 3 + 4
	for i in spark_count:
		var spark := MeshInstance3D.new()
		spark.mesh = _make_spark_mesh()
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(color, 1.0)
		smat.emission_enabled = true
		smat.emission = color
		smat.emission_energy_multiplier = 2.0
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spark.material_override = smat
		_main.add_child(spark)

		var spread := Vector3(
			randf_range(-0.8, 0.8),
			randf_range(0.2, 1.2),
			randf_range(-0.8, 0.8)
		).normalized() * randf_range(0.4, 1.0)
		spark.global_position = pos + spread * 0.3
		spark.scale = Vector3(0.2, 0.2, 0.2)

		var tw := spark.create_tween().set_parallel(true)
		tw.tween_property(spark, "global_position", pos + spread * 1.5, 0.5)
		tw.tween_property(spark, "scale", Vector3.ZERO, 0.5)
		tw.tween_property(smat, "albedo_color:a", 0.0, 0.4)
		tw.chain().tween_callback(spark.queue_free)


func _make_spark_mesh() -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(0.04, 0.04, 0.04)
	return m


func _play_chime(pitch: float) -> void:
	if not _chime:
		return
	var audio := AudioStreamPlayer.new()
	audio.stream      = _chime
	audio.volume_db   = CHIME_VOL_DB
	audio.pitch_scale = pitch
	audio.bus         = &"SFX"
	_main.add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)
