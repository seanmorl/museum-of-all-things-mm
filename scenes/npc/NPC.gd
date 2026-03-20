class_name ExhibitNPC
extends CharacterBody3D
## ExhibitNPC — Overhauled visitor AI.
## Behaviour is driven by a lightweight Behaviour Tree (BT) with
## four leaf tasks: Wander, ViewExhibit, Socialise, Rest.
## Each task is scored by a Utility layer before selection.
## Perception uses an Area3D sensor so we never iterate the whole tree.
## Visual representation: capsule body + sphere head, archetype-coloured.
## Dialogue floats in world-space via Label3D with entrance/exit tweens.

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

const GRAVITY            := 20.0
const BOB_FREQ           := 9.0
const BOB_AMP            := 0.035
const DEST_THRESHOLD     := 0.28
const STUCK_THRESHOLD    := 1.8      # seconds before unstick
const STUCK_DIST         := 0.08     # movement below this counts as stuck

const SOCIAL_RANGE       := 4.0
const WALL_LOOK_DIST     := 1.8

const LABEL_FADE_IN_T    := 0.25
const LABEL_FADE_OUT_T   := 0.40
const LABEL_LINGER_T     := 3.5

# ─────────────────────────────────────────────────────────────────────────────
# ENUMS
# ─────────────────────────────────────────────────────────────────────────────

enum Archetype { TOURIST, EXPERT, CRITIC, ENTHUSIAST, CASUAL }

# ─────────────────────────────────────────────────────────────────────────────
# ARCHETYPE DATA TABLE
# ─────────────────────────────────────────────────────────────────────────────

const ARCH_DATA: Dictionary = {
	Archetype.TOURIST:    {speed=1.80, pause_min=1.0, pause_max=2.5, dlg_chance=0.50,
	                       util_weights={wander=1.4, view=1.3, social=0.6, rest=0.4}},
	Archetype.EXPERT:     {speed=1.20, pause_min=3.0, pause_max=6.5, dlg_chance=0.55,
	                       util_weights={wander=0.7, view=1.8, social=0.5, rest=0.9}},
	Archetype.CRITIC:     {speed=1.40, pause_min=1.5, pause_max=3.5, dlg_chance=0.45,
	                       util_weights={wander=1.1, view=1.1, social=0.4, rest=0.8}},
	Archetype.ENTHUSIAST: {speed=2.00, pause_min=0.8, pause_max=2.0, dlg_chance=0.70,
	                       util_weights={wander=1.2, view=1.4, social=1.0, rest=0.3}},
	Archetype.CASUAL:     {speed=1.50, pause_min=1.5, pause_max=4.0, dlg_chance=0.30,
	                       util_weights={wander=1.3, view=0.8, social=0.9, rest=1.1}},
}

# ─────────────────────────────────────────────────────────────────────────────
# DIALOGUE
# ─────────────────────────────────────────────────────────────────────────────

const DIALOGUE: Dictionary = {
	Archetype.TOURIST:    ["Oh, this is beautiful!", "Let me take a mental picture!",
	                       "I've always wanted to see this!", "Wow, look at this!",
	                       "So this is what it looks like in person!"],
	Archetype.EXPERT:     ["Notice the subtle use of light here…", "The technique is quite remarkable.",
	                       "Observe the intricate details.", "A masterful execution.",
	                       "The historical context is fascinating."],
	Archetype.CRITIC:     ["Hmm, interesting choice…", "The composition could be better.",
	                       "I've seen more compelling work.", "The execution is adequate.",
	                       "Derivative, yet somehow fresh?"],
	Archetype.ENTHUSIAST: ["INCREDIBLE!", "This is WHY I love museums!",
	                       "Absolutely mind-blowing!", "I could stare at this forever!", "Pure genius!"],
	Archetype.CASUAL:     ["Nice.", "That's cool.", "Huh, interesting.",
	                       "Pretty neat.", "Wonder what this is about?"],
}

const SOCIAL_LINES: Array[String] = [
	"Beautiful piece, isn't it?", "What do you think?",
	"Have you seen the other rooms?", "Amazing, truly amazing.", "*nods appreciatively*",
]

const FIRST_NAMES: Array[String] = [
	"Margaret","Robert","Susan","Michael","Patricia","James","Linda","John",
	"Barbara","William","Elizabeth","David","Jennifer","Richard","Mary","Thomas",
	"Dorothy","Charles","Lisa","Joseph","Nancy","Christopher","Karen","Daniel",
]
const LAST_NAMES: Array[String] = [
	"Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis",
	"Rodriguez","Martinez","Hernandez","Lopez","Wilson","Anderson","Thomas",
	"Taylor","Moore","Jackson","Martin","Lee","Perez","Thompson","White",
]
const ORIGINS: Array[String] = [
	"Ohio","Paris","Tokyo","London","Berlin","Sydney","Toronto","New York",
	"California","Italy","Spain","Brazil","India","Sweden","Norway",
]

# ─────────────────────────────────────────────────────────────────────────────
# IDENTITY / CONFIG
# ─────────────────────────────────────────────────────────────────────────────

var _name      : String    = ""
var _origin    : String    = ""
var _archetype : Archetype = Archetype.CASUAL
var _arch_cfg  : Dictionary = {}
var _walk_speed: float     = 1.5

# ─────────────────────────────────────────────────────────────────────────────
# NAVIGATION / PHYSICS
# ─────────────────────────────────────────────────────────────────────────────

var _room_bounds      : Array      = []      # [Vector3 min, Vector3 max]
var _destination      : Vector3    = Vector3.ZERO
var _bob_time         : float      = 0.0
var _stuck_timer      : float      = 0.0
var _last_pos         : Vector3    = Vector3.ZERO
var _avoidance_vel    : Vector3    = Vector3.ZERO
var _avoidance_timer  : float      = 0.0

# ─────────────────────────────────────────────────────────────────────────────
# BEHAVIOUR TREE STATE
# ─────────────────────────────────────────────────────────────────────────────

enum BTState { WANDER, VIEW_EXHIBIT, SOCIALISE, REST }
var _bt_state         : BTState    = BTState.REST
var _pause_timer      : float      = 0.0
var _view_timer       : float      = 0.0
var _view_target      : Vector3    = Vector3.ZERO
var _social_target    : ExhibitNPC = null

# ─────────────────────────────────────────────────────────────────────────────
# PERCEPTION (Area3D sensor)
# ─────────────────────────────────────────────────────────────────────────────

var _nearby_npcs      : Array[ExhibitNPC] = []
var _perception_area  : Area3D            = null

# ─────────────────────────────────────────────────────────────────────────────
# DIALOGUE DISPLAY
# ─────────────────────────────────────────────────────────────────────────────

var _name_label3d     : Label3D = null
var _dlg_label3d      : Label3D = null
var _dlg_tween        : Tween   = null
var _dlg_active       : bool    = false

# ─────────────────────────────────────────────────────────────────────────────
# AUDIO
# ─────────────────────────────────────────────────────────────────────────────

var _audio_player     : AudioStreamPlayer3D = null
var _ambient_sounds   : Array[AudioStream]  = []
var _sound_cooldown   : float               = 0.0

# ─────────────────────────────────────────────────────────────────────────────
# MESH REFS
# ─────────────────────────────────────────────────────────────────────────────

@onready var _body_mesh    : MeshInstance3D  = $BodyMesh
@onready var _head_mesh    : MeshInstance3D  = $HeadMesh
@onready var _obstacle_ray : RayCast3D       = $ObstacleRay

const BODY_BASE_Y := 0.85
const HEAD_BASE_Y := 1.55

# ─────────────────────────────────────────────────────────────────────────────
# RNG
# ─────────────────────────────────────────────────────────────────────────────

var _rng : RandomNumberGenerator = RandomNumberGenerator.new()

# ─────────────────────────────────────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_rng.randomize()
	_generate_identity()
	_arch_cfg   = ARCH_DATA[_archetype]
	_walk_speed = _arch_cfg.speed
	_build_labels()
	_build_audio()
	_build_perception_area()
	_last_pos   = global_position
	_select_bt_task()


# ─────────────────────────────────────────────────────────────────────────────
# PHYSICS PROCESS
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	# Dialogue timer
	if _dlg_active and _dlg_tween == null:
		pass  # managed by tween callbacks

	# Avoid other NPCs
	_avoidance_timer += delta
	if _avoidance_timer > 0.35 and _bt_state == BTState.WANDER:
		_update_avoidance()
		_avoidance_timer = 0.0

	# Stuck detection
	if _bt_state == BTState.WANDER:
		if global_position.distance_to(_last_pos) < STUCK_DIST:
			_stuck_timer += delta
			if _stuck_timer > STUCK_THRESHOLD:
				_pick_new_destination()
				_stuck_timer = 0.0
		else:
			_stuck_timer = 0.0
		_last_pos = global_position

	# Audio cooldown
	_sound_cooldown -= delta

	# ── Behaviour dispatch ───────────────────────────────────────────────────
	match _bt_state:
		BTState.REST:
			_tick_rest(delta)
		BTState.WANDER:
			_tick_wander(delta)
		BTState.VIEW_EXHIBIT:
			_tick_view(delta)
		BTState.SOCIALISE:
			_tick_socialise(delta)

	move_and_slide()


# ─────────────────────────────────────────────────────────────────────────────
# BEHAVIOUR TREE TASKS
# ─────────────────────────────────────────────────────────────────────────────

func _tick_rest(delta: float) -> void:
	_damp_velocity()
	_pause_timer -= delta
	if _pause_timer <= 0.0:
		_select_bt_task()


func _tick_wander(delta: float) -> void:
	var to_dest := _destination - global_position
	to_dest.y   = 0.0
	var dist    := to_dest.length()

	if dist < DEST_THRESHOLD or (_obstacle_ray and _obstacle_ray.is_colliding()):
		_enter_rest()
		return

	var dir := (to_dest.normalized() + _avoidance_vel).normalized()
	velocity.x = dir.x * _walk_speed
	velocity.z = dir.z * _walk_speed

	if dir.length_squared() > 0.01:
		_smooth_look_at(dir)
		if _obstacle_ray:
			_obstacle_ray.target_position = dir * 2.0

	# Head/body bob
	_bob_time += delta * BOB_FREQ
	var bob := sin(_bob_time) * BOB_AMP
	_body_mesh.position.y = BODY_BASE_Y + bob
	if _head_mesh:
		_head_mesh.position.y = HEAD_BASE_Y + bob


func _tick_view(delta: float) -> void:
	_damp_velocity()
	if _view_target != Vector3.ZERO:
		_smooth_look_at_pos(_view_target)
	_view_timer -= delta
	if _view_timer <= 0.0:
		_enter_rest()


func _tick_socialise(delta: float) -> void:
	_damp_velocity()
	if is_instance_valid(_social_target):
		_smooth_look_at_pos(_social_target.global_position)
	_pause_timer -= delta
	if _pause_timer <= 0.0:
		_enter_rest()


# ─────────────────────────────────────────────────────────────────────────────
# BT TRANSITIONS
# ─────────────────────────────────────────────────────────────────────────────

func _select_bt_task() -> void:
	var scores := _compute_utility_scores()
	var best_task := BTState.REST
	var best_score := -1.0
	for task: int in scores:
		if scores[task] > best_score:
			best_score = scores[task]
			best_task  = task

	match best_task:
		BTState.WANDER:
			_pick_new_destination()
			_bt_state = BTState.WANDER
		BTState.VIEW_EXHIBIT:
			_start_view_exhibit()
		BTState.SOCIALISE:
			_start_socialise()
		BTState.REST:
			_enter_rest()

	# Possibly say something
	if _rng.randf() < _arch_cfg.dlg_chance:
		_say_random()


func _compute_utility_scores() -> Dictionary:
	var weights: Dictionary = _arch_cfg.util_weights
	var scores  : Dictionary = {}

	scores[BTState.WANDER]       = weights.wander * _rng.randf_range(0.85, 1.25)
	scores[BTState.VIEW_EXHIBIT] = weights.view   * _rng.randf_range(0.85, 1.25)
	scores[BTState.SOCIALISE]    = weights.social * _rng.randf_range(0.85, 1.25)
	scores[BTState.REST]         = weights.rest   * _rng.randf_range(0.85, 1.25)

	# Context modifiers
	# Socialise bonus when others nearby
	if _nearby_npcs.size() > 0:
		scores[BTState.SOCIALISE] += float(_nearby_npcs.size()) * 0.25
	# View exhibit bonus when near a wall
	if _near_wall():
		scores[BTState.VIEW_EXHIBIT] += 0.40

	return scores


func _enter_rest() -> void:
	_bt_state   = BTState.REST
	var cfg     := _arch_cfg
	_pause_timer = _rng.randf_range(cfg.pause_min, cfg.pause_max)
	_damp_velocity()
	_reset_bob()


func _start_view_exhibit() -> void:
	if _room_bounds.size() < 2:
		_enter_rest()
		return
	_bt_state   = BTState.VIEW_EXHIBIT
	_view_timer  = _rng.randf_range(2.5, 5.5)
	_view_target = _pick_wall_point()
	_damp_velocity()


func _start_socialise() -> void:
	_social_target = _find_nearest_npc()
	if not is_instance_valid(_social_target):
		_enter_rest()
		return
	_bt_state   = BTState.SOCIALISE
	_pause_timer = _rng.randf_range(1.5, 3.5)
	if _rng.randf() < 0.60:
		_say_social()
	_damp_velocity()


# ─────────────────────────────────────────────────────────────────────────────
# NAVIGATION HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func _pick_new_destination() -> void:
	if _room_bounds.size() < 2:
		return
	var bmin: Vector3 = _room_bounds[0]
	var bmax: Vector3 = _room_bounds[1]
	var margin := 0.9
	var min_x  := bmin.x + margin;  var max_x := bmax.x - margin
	var min_z  := bmin.z + margin;  var max_z := bmax.z - margin
	if min_x >= max_x: min_x = (bmin.x + bmax.x) * 0.5; max_x = min_x + 0.5
	if min_z >= max_z: min_z = (bmin.z + bmax.z) * 0.5; max_z = min_z + 0.5

	var dest := Vector3(
		_rng.randf_range(min_x, max_x),
		global_position.y,
		_rng.randf_range(min_z, max_z)
	)
	# Ensure min travel distance
	if dest.distance_to(global_position) < 1.2:
		var angle    := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(1.5, 3.5)
		dest.x = clamp(global_position.x + cos(angle) * distance, min_x, max_x)
		dest.z = clamp(global_position.z + sin(angle) * distance, min_z, max_z)
	_destination   = dest
	_avoidance_vel = Vector3.ZERO


func _pick_wall_point() -> Vector3:
	var bmin: Vector3 = _room_bounds[0]
	var bmax: Vector3 = _room_bounds[1]
	match _rng.randi() % 4:
		0: return Vector3(_rng.randf_range(bmin.x, bmax.x), 1.5, bmin.z)
		1: return Vector3(_rng.randf_range(bmin.x, bmax.x), 1.5, bmax.z)
		2: return Vector3(bmax.x, 1.5, _rng.randf_range(bmin.z, bmax.z))
		_: return Vector3(bmin.x, 1.5, _rng.randf_range(bmin.z, bmax.z))


func _near_wall() -> bool:
	if _room_bounds.size() < 2:
		return false
	var bmin: Vector3 = _room_bounds[0]
	var bmax: Vector3 = _room_bounds[1]
	var p := global_position
	return (p.x - bmin.x < WALL_LOOK_DIST or bmax.x - p.x < WALL_LOOK_DIST or
	        p.z - bmin.z < WALL_LOOK_DIST or bmax.z - p.z < WALL_LOOK_DIST)


func _update_avoidance() -> void:
	var sep := Vector3.ZERO
	var n   := 0
	var sep_dist := 1.3
	for npc: ExhibitNPC in _nearby_npcs:
		if not is_instance_valid(npc): continue
		var d := global_position.distance_to(npc.global_position)
		if d < sep_dist and d > 0.01:
			sep += (global_position - npc.global_position).normalized() / d
			n   += 1
	if n > 0:
		_avoidance_vel = (sep / n) * 1.8


func _damp_velocity() -> void:
	velocity.x = 0.0;  velocity.z = 0.0


func _reset_bob() -> void:
	_bob_time = 0.0
	_body_mesh.position.y = BODY_BASE_Y
	if _head_mesh:
		_head_mesh.position.y = HEAD_BASE_Y


func _smooth_look_at(dir: Vector3) -> void:
	if dir.length_squared() < 0.01: return
	var target := atan2(dir.x, dir.z)
	rotation.y  = lerp_angle(rotation.y, target, 0.18)


func _smooth_look_at_pos(target_pos: Vector3) -> void:
	var dir := (target_pos - global_position)
	dir.y = 0.0
	_smooth_look_at(dir)


# ─────────────────────────────────────────────────────────────────────────────
# PERCEPTION (Area3D)
# ─────────────────────────────────────────────────────────────────────────────

func _build_perception_area() -> void:
	_perception_area = Area3D.new()
	var shape  := SphereShape3D.new()
	shape.radius = SOCIAL_RANGE
	var coll   := CollisionShape3D.new()
	coll.shape  = shape
	# Use a dedicated detection layer so we don't collide with world geometry
	_perception_area.collision_layer = 0
	_perception_area.collision_mask  = 1 << 19   # Player Body layer
	_perception_area.monitorable     = false
	_perception_area.add_child(coll)
	add_child(_perception_area)
	_perception_area.body_entered.connect(_on_body_entered)
	_perception_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is ExhibitNPC and body != self:
		if not _nearby_npcs.has(body):
			_nearby_npcs.append(body)


func _on_body_exited(body: Node3D) -> void:
	if body is ExhibitNPC:
		_nearby_npcs.erase(body)


func _find_nearest_npc() -> ExhibitNPC:
	var closest   : ExhibitNPC = null
	var best_dist : float      = SOCIAL_RANGE
	for npc: ExhibitNPC in _nearby_npcs:
		if not is_instance_valid(npc): continue
		var d := global_position.distance_to(npc.global_position)
		if d < best_dist:
			best_dist = d
			closest   = npc
	return closest


# ─────────────────────────────────────────────────────────────────────────────
# DIALOGUE / LABELS
# ─────────────────────────────────────────────────────────────────────────────

func _build_labels() -> void:
	_name_label3d = Label3D.new()
	_name_label3d.text               = "%s\n%s" % [_name, _origin]
	_name_label3d.font_size          = 11
	_name_label3d.billboard          = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label3d.no_depth_test      = false
	_name_label3d.modulate.a         = 0.65
	_name_label3d.position           = Vector3(0, 2.10, 0)
	_name_label3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label3d.outline_size       = 4
	_name_label3d.outline_modulate   = Color(0, 0, 0, 0.55)
	add_child(_name_label3d)

	_dlg_label3d = Label3D.new()
	_dlg_label3d.text                = ""
	_dlg_label3d.font_size           = 13
	_dlg_label3d.billboard           = BaseMaterial3D.BILLBOARD_ENABLED
	_dlg_label3d.no_depth_test       = false
	_dlg_label3d.modulate.a          = 0.0
	_dlg_label3d.position            = Vector3(0, 2.55, 0)
	_dlg_label3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dlg_label3d.outline_size        = 5
	_dlg_label3d.outline_modulate    = Color(0, 0, 0, 0.70)
	add_child(_dlg_label3d)


func _say(text: String) -> void:
	if not _dlg_label3d: return

	# Kill any existing tween
	if _dlg_tween and _dlg_tween.is_valid():
		_dlg_tween.kill()
	_dlg_active = true
	_dlg_label3d.text     = text
	_dlg_label3d.position = Vector3(0, 2.55, 0)
	_dlg_label3d.modulate.a = 0.0

	_dlg_tween = create_tween()
	# Fade + float in
	_dlg_tween.set_parallel(true)
	_dlg_tween.tween_property(_dlg_label3d, "modulate:a", 1.0, LABEL_FADE_IN_T) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dlg_tween.tween_property(_dlg_label3d, "position:y", 2.70, LABEL_FADE_IN_T) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Wait, then fade out
	_dlg_tween.chain().tween_interval(LABEL_LINGER_T)
	_dlg_tween.chain().set_parallel(true)
	_dlg_tween.tween_property(_dlg_label3d, "modulate:a", 0.0, LABEL_FADE_OUT_T) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_dlg_tween.tween_property(_dlg_label3d, "position:y", 2.80, LABEL_FADE_OUT_T) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_dlg_tween.chain().tween_callback(func():
		_dlg_active = false
		_dlg_label3d.text = ""
	)


func _say_random() -> void:
	var lines: Array = DIALOGUE[_archetype]
	_say(lines[_rng.randi() % lines.size()])
	_maybe_play_sound()


func _say_social() -> void:
	_say(SOCIAL_LINES[_rng.randi() % SOCIAL_LINES.size()])


# ─────────────────────────────────────────────────────────────────────────────
# AUDIO
# ─────────────────────────────────────────────────────────────────────────────

func _build_audio() -> void:
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.max_distance = 12.0
	_audio_player.attenuation_filter_cutoff_hz = 800.0
	add_child(_audio_player)

	var paths := [
		"res://assets/sound/Easter Eggs/Random Ambience 1.ogg",
		"res://assets/sound/Easter Eggs/Random Ambience 2.ogg",
		"res://assets/sound/Easter Eggs/Random Ambience 3.ogg",
		"res://assets/sound/Easter Eggs/Random Ambience 4.ogg",
	]
	for p: String in paths:
		if ResourceLoader.exists(p):
			var s: AudioStream = ResourceLoader.load(p)
			if s: _ambient_sounds.append(s)


func _maybe_play_sound() -> void:
	if _sound_cooldown > 0.0 or _ambient_sounds.is_empty(): return
	_audio_player.stream     = _ambient_sounds[_rng.randi() % _ambient_sounds.size()]
	_audio_player.volume_db  = _rng.randf_range(-16.0, -10.0)
	_audio_player.play()
	_sound_cooldown = _rng.randf_range(12.0, 28.0)


# ─────────────────────────────────────────────────────────────────────────────
# IDENTITY
# ─────────────────────────────────────────────────────────────────────────────

func _generate_identity() -> void:
	_name      = "%s %s" % [FIRST_NAMES[_rng.randi() % FIRST_NAMES.size()],
	                         LAST_NAMES[_rng.randi() % LAST_NAMES.size()]]
	_origin    = ORIGINS[_rng.randi() % ORIGINS.size()]
	_archetype = _rng.randi() % Archetype.size() as Archetype


# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

func init(spawn_pos: Vector3, room_bounds: Array) -> void:
	position    = spawn_pos
	_room_bounds = room_bounds
	_destination = spawn_pos
	_last_pos    = spawn_pos


func set_npc_color(color: Color) -> void:
	if _body_mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness    = 0.65
		_body_mesh.material_override = mat
	if _head_mesh:
		var hm := StandardMaterial3D.new()
		hm.albedo_color = color.lightened(0.15)
		hm.roughness    = 0.50
		_head_mesh.material_override = hm
