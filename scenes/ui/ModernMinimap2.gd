@tool
extends Control
## ModernMinimap - Clean, minimalist minimap redesign
##
## Features:
## - Clean circular design with smooth animations
## - Matches game's UI theme (dark/light mode aware)
## - Shows player position and orientation
## - Displays current room name
## - Zoom levels with smooth transitions
## - North indicator
## - Race target indicator

signal mode_changed(mode: int)
signal zoom_changed(zoom: float)

const MODE_OFF := 0
const MODE_LOCAL := 1

const CIRCLE_SIZE := 280.0
const BORDER_WIDTH := 3.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5
const ZOOM_STEP := 0.25

var _player: Node = null
var _font: Font = null
var _mode: int = MODE_OFF
var _zoom: float = 1.0
var _time: float = 0.0

var _viewport_texture: Texture2D = null
var _current_room: String = "Lobby"
var _target_room: String = ""

# Theme colors
var _bg_color: Color = Color(0, 0, 0, 0.7)
var _border_color: Color = Color(0.635, 0.663, 0.694, 1.0)
var _text_color: Color = Color(1, 1, 1, 0.9)
var _accent_color: Color = Color(0.28, 0.62, 1.0, 1.0)

# Animation
var _fade_alpha: float = 0.0
var _fade_target: float = 0.0
var _zoom_anim: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -(CIRCLE_SIZE + 20.0)
	offset_top = -(CIRCLE_SIZE + 20.0)
	offset_right = -20.0
	offset_bottom = -20.0
	
	# Connect to theme manager
	if ThemeManager:
		ThemeManager.dark_mode_changed.connect(_on_theme_changed)
		ThemeManager.reading_font_changed.connect(_on_font_changed)
		_on_theme_changed(ThemeManager.is_dark_mode)
		_font = ThemeManager.get_reading_font()
	
	# Initial setup
	_update_colors()


func init(player: Node) -> void:
	_player = player
	if _player:
		if _player.has_signal("current_room_changed"):
			_player.current_room_changed.connect(_on_room_changed)
		_current_room = _player.current_room if _player.has_method("get") or "current_room" in _player else "Lobby"
	
	# Get viewport texture from player
	if _player and _player.has_node("MapCameraContainer/MapViewport"):
		var vp = _player.get_node("MapCameraContainer/MapViewport") as SubViewport
		if vp:
			_viewport_texture = vp.get_texture()


func _process(delta: float) -> void:
	_time += delta
	
	# Fade animation
	_fade_alpha = move_toward(_fade_alpha, _fade_target, delta * 8.0)
	
	# Zoom animation
	_zoom_anim = move_toward(_zoom_anim, _zoom, delta * 6.0)
	
	if _fade_alpha > 0.01:
		queue_redraw()


func _draw() -> void:
	if _fade_alpha < 0.01 or _mode == MODE_OFF:
		return
	
	var center = size / 2.0
	var radius = (CIRCLE_SIZE / 2.0) * _zoom_anim
	
	# Draw circular background
	draw_circle(center, radius, _bg_color * Color(1, 1, 1, _fade_alpha))
	
	# Draw border
	draw_arc(center, radius, 0, TAU, 32, _border_color * Color(1, 1, 1, _fade_alpha), BORDER_WIDTH)
	draw_arc(center, radius - BORDER_WIDTH, 0, TAU, 32, _border_color * Color(1, 1, 1, _fade_alpha * 0.3), 1.0)
	
	# Draw viewport texture (the actual minimap view)
	if _viewport_texture:
		var tex_size = Vector2(radius * 2 - 20, radius * 2 - 20)
		var tex_pos = center - tex_size / 2.0
		draw_texture_rect(_viewport_texture, Rect2(tex_pos, tex_size), false, _fade_alpha * Color(1, 1, 1, 0.9))
	
	# Draw north indicator
	_draw_north_indicator(center, radius)
	
	# Draw room name at top
	_draw_room_label(center, radius)
	
	# Draw zoom level at bottom
	_draw_zoom_label(center, radius)
	
	# Draw player direction indicator (center dot with arrow)
	_draw_player_indicator(center, radius * 0.15)
	
	# Draw target indicator if set
	if _target_room and _target_room != _current_room:
		_draw_target_indicator(center, radius)


func _draw_north_indicator(center: Vector2, radius: float) -> void:
	var n_pos = center + Vector2(0, -radius + 25)
	
	# Draw small triangle pointing up
	var triangle_size = 8.0
	var points = [
		n_pos + Vector2(0, -triangle_size),
		n_pos + Vector2(-triangle_size * 0.7, triangle_size * 0.5),
		n_pos + Vector2(triangle_size * 0.7, triangle_size * 0.5)
	]
	draw_colored_polygon(points, _accent_color * Color(1, 1, 1, _fade_alpha))
	
	# Draw "N" label
	if _font:
		var n_size = _font.get_string_size("N", HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
		var n_pos_label = n_pos + Vector2(-n_size.x / 2, 4)
		_font.draw_string(self, n_pos_label, "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, _text_color * Color(1, 1, 1, _fade_alpha))


func _draw_room_label(center: Vector2, radius: float) -> void:
	if not _font or _current_room.is_empty():
		return
	
	var label_pos = center + Vector2(0, -radius + 50)
	var room_text = _current_room
	if room_text.length() > 20:
		room_text = room_text.left(17) + "..."
	
	var text_size = _font.get_string_size(room_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
	var text_pos = label_pos - Vector2(text_size.x / 2, 0)
	
	# Draw background pill for text
	var pill_size = Vector2(text_size.x + 20, 24)
	var pill_pos = label_pos - Vector2(pill_size.x / 2, pill_size.y / 2)
	draw_rounded_rect(Rect2(pill_pos, pill_size), 12, _bg_color * Color(1, 1, 1, _fade_alpha * 0.8))
	
	# Draw text
	_font.draw_string(self, text_pos, room_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, _text_color * Color(1, 1, 1, _fade_alpha))


func _draw_zoom_label(center: Vector2, radius: float) -> void:
	if not _font:
		return
	
	var zoom_text = "%d%%" % int(_zoom_anim * 100)
	var label_pos = center + Vector2(0, radius - 35)
	var text_size = _font.get_string_size(zoom_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
	var text_pos = label_pos - Vector2(text_size.x / 2, 0)
	
	_font.draw_string(self, text_pos, zoom_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, _text_color * Color(1, 1, 1, _fade_alpha * 0.7))


func _draw_player_indicator(center: Vector2, size: float) -> void:
	# Center dot
	draw_circle(center, size, _accent_color * Color(1, 1, 1, _fade_alpha))
	draw_arc(center, size + 3, 0, TAU, 16, _accent_color * Color(1, 1, 1, _fade_alpha * 0.5), 2.0)
	
	# Direction arrow (if we have player rotation)
	if _player and _player.has_node("Pivot"):
		var player_rot = _player.get_node("Pivot").rotation.y
		var arrow_dir = Vector2(sin(player_rot), cos(player_rot))
		var arrow_end = center + arrow_dir * (size * 2.5)
		draw_line(center, arrow_end, _accent_color * Color(1, 1, 1, _fade_alpha), 2.0)


func _draw_target_indicator(center: Vector2, radius: float) -> void:
	# Draw a star or marker indicating the target room direction
	# For now, just show a simple indicator at the top
	var target_pos = center + Vector2(0, -radius + 45)
	
	# Draw star shape
	var star_size = 10.0
	var star_color = Color(0.52, 0.88, 0.42, _fade_alpha)
	
	for i in range(5):
		var angle = deg_to_rad(-90 + i * 72)
		var outer = target_pos + Vector2(cos(angle), sin(angle)) * star_size
		var inner_angle = deg_to_rad(-90 + i * 72 + 36)
		var inner = target_pos + Vector2(cos(inner_angle), sin(inner_angle)) * (star_size * 0.5)
		
		if i == 0:
			draw_line(outer, inner, star_color, 2.0)
		else:
			draw_line(outer, inner, star_color, 2.0)
	
	# Draw "TARGET" label
	if _font:
		var label_pos = target_pos + Vector2(0, star_size + 12)
		var text_size = _font.get_string_size("TARGET", HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
		var text_pos = label_pos - Vector2(text_size.x / 2, 0)
		_font.draw_string(self, text_pos, "TARGET", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, star_color)


func _update_colors() -> void:
	if ThemeManager and ThemeManager.is_dark_mode:
		_bg_color = Color(0, 0, 0, 0.75)
		_border_color = Color(0.635, 0.663, 0.694, 1.0)
		_text_color = Color(0.92, 0.92, 0.92, 0.9)
		_accent_color = Color(0.28, 0.62, 1.0, 1.0)
	else:
		_bg_color = Color(1, 1, 1, 0.85)
		_border_color = Color(0.4, 0.4, 0.5, 1.0)
		_text_color = Color(0.1, 0.1, 0.1, 0.9)
		_accent_color = Color(0.2, 0.5, 0.9, 1.0)


func _on_theme_changed(is_dark: bool) -> void:
	_update_colors()
	queue_redraw()


func _on_font_changed(new_font: Font) -> void:
	_font = new_font
	queue_redraw()


func _on_room_changed(room: String) -> void:
	_current_room = room
	queue_redraw()


func set_mode(mode: int) -> void:
	if _mode == mode:
		return
	
	_mode = mode
	_fade_target = 1.0 if _mode != MODE_OFF else 0.0
	mode_changed.emit(_mode)


func set_zoom(zoom: float) -> void:
	_zoom = clamp(zoom, ZOOM_MIN, ZOOM_MAX)
	zoom_changed.emit(_zoom)


func cycle_mode() -> void:
	var new_mode = (_mode + 1) % 3  # OFF -> LOCAL -> OFF
	set_mode(new_mode)


func zoom_in() -> void:
	set_zoom(_zoom + ZOOM_STEP)


func zoom_out() -> void:
	set_zoom(_zoom - ZOOM_STEP)


func set_target_room(room: String) -> void:
	_target_room = room
	queue_redraw()


func draw_rounded_rect(rect: Rect2, radius: float, color: Color) -> void:
	# Draw rounded rectangle
	draw_arc(rect.position + Vector2(radius, radius), radius, PI, PI * 1.5, 8, color, 1.0)
	draw_arc(rect.position + Vector2(rect.size.x - radius, radius), radius, PI * 1.5, TAU, 8, color, 1.0)
	draw_arc(rect.position + Vector2(rect.size.x - radius, rect.size.y - radius), radius, 0, PI * 0.5, 8, color, 1.0)
	draw_arc(rect.position + Vector2(radius, rect.size.y - radius), radius, PI * 0.5, PI, 8, color, 1.0)
	
	draw_rect(Rect2(rect.position.x + radius, rect.position.y, rect.size.x - radius * 2, rect.size.y), color)
	draw_rect(Rect2(rect.position.x, rect.position.y + radius, rect.size.x, rect.size.y - radius * 2), color)
