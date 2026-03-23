extends Control
## MinimapController
##
## Manages the player's existing MapViewport SubViewport camera and
## cycles minimap display styles with the M key.
##
## HOW THE CAMERA WORKS (important):
##   Player.tscn has:
##     MapCameraContainer  (Node3D, top_level=true — NOT parented to player transform)
##       MapViewport       (SubViewport, world_3d shared with main scene via Main.gd)
##         MapCamera       (Camera3D, orthographic, looks straight down)
##     MapMarker           (MeshInstance3D on render layer 24 — the player dot)
##
##   MapCamera cull_mask = layers 1+24 → sees main geometry + MapMarker
##   Main.gd already sets:  map_viewport.world_3d = get_viewport().find_world_3d()
##
##   Because MapCameraContainer is top_level, WE must move it every frame.
##   The camera is already oriented correctly (looking down). We just need to:
##     1. Enable UPDATE_ALWAYS on the SubViewport
##     2. Move the container XZ to match the player every frame
##     3. Keep camera height so near/far covers the scene
##
## MODES (M key cycles):
##   0 = OFF

# ── Constants ─────────────────────────────────────────────────────────────────

const MODE_COUNT  : int   = 1
const CAM_HEIGHT  : float = 40.0   # units above player floor level
const CAM_SIZE_1X : float = 22.0   # orthographic world-units visible at zoom 1×

const ZOOM_MIN    : float = 0.5
const ZOOM_MAX    : float = 3.0
const ZOOM_STEP   : float = 0.25

# ── State ─────────────────────────────────────────────────────────────────────

var _mode   : int   = 0
var _zoom   : float = 1.0
var _player : Node  = null

# Cached node refs set in init() — avoid get_node every frame
var _container : Node3D     = null
var _viewport  : SubViewport = null
var _cam       : Camera3D   = null

var _views          : Array[Control] = []
var _orig_positions : Dictionary     = {}

# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	visible      = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_views = []

# ── Init (called by Main.gd after player is spawned) ─────────────────────────

func init(player: Node) -> void:
	_player = player

	# Cache the camera nodes
	_container = player.get_node_or_null("MapCameraContainer")
	_viewport  = player.get_node_or_null("MapCameraContainer/MapViewport")
	_cam       = player.get_node_or_null("MapCameraContainer/MapViewport/MapCamera")

	# Fix 1: Enable rendering — SubViewport ships with UPDATE_DISABLED (=0)
	if _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	if _cam:
		# Fix 2: The tscn transform has the camera looking UPWARD (+Y).
		# We need it looking straight DOWN (-Y). Set the full transform explicitly.
		# Looking down: forward = -Y, right = +X, up = +Z (north)
		#   basis X col = (1, 0, 0)   right
		#   basis Y col = (0, 0, 1)   camera-up = world +Z
		#   basis Z col = (0, 1, 0)   camera -forward = world +Y → looks down
		_cam.transform = Transform3D(
			Vector3(1, 0, 0),   # X axis (right)
			Vector3(0, 0, 1),   # Y axis (camera up = world +Z / north)
			Vector3(0, 1, 0),   # Z axis (camera back = world +Y, so looks DOWN)
			Vector3(0, CAM_HEIGHT, 0)  # position: above origin
		)

		# Fix 3: Frustum — near/far must bracket the floor from above
		# Camera at Y=40, looking down. Floor ~Y=0. near=35, far=45 → sees Y=5 to Y=-5
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.near       = CAM_HEIGHT - 10.0   # 30 — safely above floor
		_cam.far        = CAM_HEIGHT + 15.0   # 55 — covers rooms up to 15 units tall
		_cam.size       = CAM_SIZE_1X
		_cam.keep_aspect = Camera3D.KEEP_HEIGHT

	# Init all view scripts with the player reference
	for v : Control in _views:
		if v.has_method("init"):
			v.init(player)

# ── Process ───────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# The SubViewport does NOT propagate its parent Node3D transform to the
	# Camera3D inside it. The camera's transform is in the shared world_3d space.
	# So we move the CAMERA directly to hover above the player, not the container.
	if _cam and is_instance_valid(_cam):
		var p : Vector3 = _player.global_position
		_cam.global_position = Vector3(p.x, CAM_HEIGHT, p.z)

	if _mode == 0:
		return

	# Push the latest texture to whichever view is showing
	var active : Control = _active_view()
	if active and active.has_method("update_texture") and _player.has_method("get_minimap_texture"):
		var tex : Texture2D = _player.get_minimap_texture()
		if tex:
			active.update_texture(tex)

# ── Input (scroll to zoom) ────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _mode == 0:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
				_apply_zoom()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
				_apply_zoom()

# ── Public API ────────────────────────────────────────────────────────────────

func cycle() -> void:
	_mode = (_mode + 1) % MODE_COUNT
	_refresh_visibility()

func show_hud() -> void:
	if _mode == 0:
		_mode = 1
	_refresh_visibility()

func set_hidden() -> void:
	_mode = 0
	for v : Control in _views:
		v.visible = false

func restore_after_pause() -> void:
	if _mode > 0:
		_refresh_visibility()

func reset_zoom() -> void:
	_zoom = 1.0
	_apply_zoom()

func set_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_apply_zoom()

# ── Internals ─────────────────────────────────────────────────────────────────

func _refresh_visibility() -> void:
	if _mode == 0:
		for v : Control in _views:
			if v.visible:
				_slide_out(v)
		return
	for i in _views.size():
		var v : Control = _views[i]
		if i == _mode - 1:
			if not v.visible:
				v.visible = true
				_slide_in(v)
			if v.has_method("set_zoom"):
				v.set_zoom(_zoom)
		else:
			if v.visible:
				_slide_out(v)
	_apply_zoom()

func _apply_zoom() -> void:
	var active : Control = _active_view()
	if active and active.has_method("set_zoom"):
		active.set_zoom(_zoom)
	# Zoom by shrinking the orthographic size (smaller = more zoomed in)
	if _cam:
		_cam.size = CAM_SIZE_1X / _zoom

func _active_view() -> Control:
	if _mode >= 1 and _mode <= _views.size():
		return _views[_mode - 1]
	return null

func _orig_pos(v: Control) -> Vector2:
	if not _orig_positions.has(v):
		_orig_positions[v] = v.position
	return _orig_positions[v]

func _slide_in(v: Control) -> void:
	var orig : Vector2 = _orig_pos(v)
	v.modulate.a = 0.0
	v.position.y = orig.y + 12.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(v, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "position:y", orig.y, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _slide_out(v: Control) -> void:
	var orig : Vector2 = _orig_pos(v)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(v, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(v, "position:y", orig.y + 10.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		v.visible    = false
		v.modulate.a = 1.0
		v.position   = orig
	)
