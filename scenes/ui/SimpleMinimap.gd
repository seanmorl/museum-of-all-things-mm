extends Control
## SimpleMinimap - A clean, reliable minimap implementation.
##
## Uses the player's MapViewport/MapCamera to render a top-down view.
## Toggle with M key. Shows player position and heading.

var _player: Node = null
var _map_viewport: SubViewport = null
var _map_camera: Camera3D = null
var _visible: bool = false
var _zoom: float = 1.0
var _player_marker: TextureRect = null
var _container: PanelContainer = null

const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 3.0
const PANEL_SIZE: float = 200.0
const CAM_HEIGHT: float = 35.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	visible = false

func _build_ui() -> void:
	# Container panel - top right corner
	_container = PanelContainer.new()
	_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_container.custom_minimum_size = Vector2(PANEL_SIZE, PANEL_SIZE)
	_container.offset_left = -PANEL_SIZE - 16
	_container.offset_right = -16
	_container.offset_top = 16
	_container.offset_bottom = PANEL_SIZE + 16
	add_child(_container)
	print("[SimpleMinimap] Created container: ", _container, " visible: ", _container.visible)
	_style_panel()

	# Viewport texture
	var tex_rect := TextureRect.new()
	tex_rect.name = "MinimapTexture"
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_rect.offset_left = 4
	tex_rect.offset_right = -4
	tex_rect.offset_top = 4
	tex_rect.offset_bottom = -4
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(tex_rect)

	# Player direction arrow
	var arrow := Polygon2D.new()
	arrow.name = "PlayerArrow"
	arrow.polygon = PackedVector2Array([
		Vector2(0, -8),
		Vector2(-5, 6),
		Vector2(0, 3),
		Vector2(5, 6),
	])
	arrow.color = Color(0.2, 0.7, 1.0, 1.0)
	arrow.position = Vector2(PANEL_SIZE / 2, PANEL_SIZE / 2)
	_container.add_child(arrow)


func _style_panel() -> void:
	var dark := ThemeManager.is_dark_mode
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.9) if dark else Color(0.95, 0.96, 0.98, 0.9)
	sb.border_color = Color(0.3, 0.32, 0.38, 0.9) if dark else Color(0.6, 0.62, 0.68, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 8
	_container.add_theme_stylebox_override("panel", sb)


func init(player: Node) -> void:
	_player = player
	
	# Create our own viewport and camera for the minimap
	_map_viewport = SubViewport.new()
	_map_viewport.name = "MinimapViewport"
	_map_viewport.size = Vector2i(256, 256)
	_map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_map_viewport.transparent_bg = true
	add_child(_map_viewport)
	print("[SimpleMinimap] Viewport created: ", _map_viewport)
	
	# Create camera for minimap
	_map_camera = Camera3D.new()
	_map_camera.name = "MinimapCamera"
	_map_viewport.add_child(_map_camera)
	print("[SimpleMinimap] Camera created: ", _map_camera)
	
	# Get world from main viewport
	var main_viewport := get_viewport()
	if main_viewport:
		_map_viewport.world_3d = main_viewport.find_world_3d()
		print("[SimpleMinimap] World set: ", _map_viewport.world_3d)
	
	# Configure camera
	_configure_camera()
	
	# Set texture on startup
	_update_texture()


func _update_texture() -> void:
	var tex_rect := _container.get_node_or_null("MinimapTexture") as TextureRect
	if tex_rect and _map_viewport:
		tex_rect.texture = _map_viewport.get_texture()
		print("[SimpleMinimap] Texture set: ", tex_rect.texture)


func _configure_camera() -> void:
	if not _map_camera:
		return
	
	# Reset camera to look straight down
	_map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_map_camera.size = 22.0
	_map_camera.near = 1.0
	_map_camera.far = 100.0
	# Look straight down (forward = -Y, up = +Z)
	_map_camera.transform = Transform3D(Basis.from_euler(Vector3(-PI/2, 0, 0)), Vector3(0, CAM_HEIGHT, 0))
	# Include layer 1 (default), layer 24 (Hall/geometry)
	_map_camera.cull_mask = 1 | (1 << 23)


func _process(_delta: float) -> void:
	if not _visible or not is_instance_valid(_player):
		return
	
	# Keep camera above player
	if _map_camera and is_instance_valid(_map_camera):
		var p: Vector3 = _player.global_position
		_map_camera.global_position = Vector3(p.x, CAM_HEIGHT, p.z)
	
	# Update viewport texture
	var tex_rect := _container.get_node_or_null("MinimapTexture") as TextureRect
	if tex_rect and _map_viewport:
		tex_rect.texture = _map_viewport.get_texture()
	
	# Update player arrow rotation
	var arrow := _container.get_node_or_null("PlayerArrow") as Polygon2D
	if arrow:
		arrow.rotation = -_player.rotation.y


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		toggle()


func toggle() -> void:
	_visible = not _visible
	visible = _visible
	if _container:
		_container.visible = _visible
		if _visible:
			_update_texture()
	print("[SimpleMinimap] Toggle - visible: ", _visible)


func cycle() -> void:
	toggle()


func set_hidden() -> void:
	_visible = false
	visible = false


func show_minimap() -> void:
	if not _visible:
		toggle()


func hide_minimap() -> void:
	if _visible:
		toggle()


func set_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	if _map_camera:
		_map_camera.size = 22.0 / _zoom


func zoom_in() -> void:
	set_zoom(_zoom + 0.25)


func zoom_out() -> void:
	set_zoom(_zoom - 0.25)


func restore_after_pause() -> void:
	if _visible:
		_configure_camera()
