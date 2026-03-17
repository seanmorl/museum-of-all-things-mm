extends Control
## ParchmentMinimap — heavily styled aged-paper minimap with strong visual identity.

var _player: Node = null
var _texture_rect: TextureRect = null
var _overlay: Control = null
var _zoom_level: float = 1.0
var _serif_font: Font = null

const PARCHMENT_BG := Color(0.91, 0.85, 0.72)
const PARCHMENT_DARK := Color(0.78, 0.72, 0.58)
const BORDER_INK := Color(0.45, 0.36, 0.24)
const INK := Color(0.28, 0.22, 0.16)
const SEPIA := Color(0.60, 0.45, 0.25, 0.9)  # Stronger sepia for blending

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_serif_font = ThemeManager.get_reading_font()
	if not _serif_font:
		_serif_font = ThemeDB.fallback_font

	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left  = -270.0; offset_top    = -270.0
	offset_right = -20.0;  offset_bottom = -20.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical   = Control.GROW_DIRECTION_BEGIN

	clip_contents = true

	# Background paper
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = PARCHMENT_BG
	add_child(bg)

	# The texture
	_texture_rect = TextureRect.new()
	_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texture_rect.offset_left = 14; _texture_rect.offset_top = 14
	_texture_rect.offset_right = -14; _texture_rect.offset_bottom = -28
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# Heavy sepia tint so the 3D map looks like ink/stains
	_texture_rect.modulate = SEPIA
	add_child(_texture_rect)

	# Overlay (draws borders, grain, compass ON TOP of the texture)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.clip_contents = true
	_overlay.draw.connect(_on_overlay_draw)
	add_child(_overlay)

	ThemeManager.reading_font_changed.connect(func(f):
		_serif_font = f if f else ThemeDB.fallback_font
		_overlay.queue_redraw()
	)


func init(player: Node) -> void:
	_player = player


func update_texture(tex: Texture2D) -> void:
	if _texture_rect and tex:
		_texture_rect.texture = tex


func set_zoom(level: float) -> void:
	_zoom_level = level
	if _overlay:
		_overlay.queue_redraw()


func _on_overlay_draw() -> void:
	var s := size
	var m := 4.0  # outer margin

	# ── Fake paper grain OVER the map ──
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for y in range(0, int(s.y), 3):
		var alpha := rng.randf_range(0.04, 0.12)
		_overlay.draw_line(Vector2(0, y), Vector2(s.x, y), Color(0.5, 0.4, 0.3, alpha), 1.0)

	# ── Heavy vignette / stains in corners to frame it ──
	var stain1 := Color(0.35, 0.25, 0.15, 0.08)
	var stain2 := Color(0.35, 0.25, 0.15, 0.15)
	
	# Outer soft layer
	_overlay.draw_circle(Vector2(0, 0), 120.0, stain1)
	_overlay.draw_circle(Vector2(s.x, s.y), 130.0, stain1)
	_overlay.draw_circle(Vector2(s.x, 0), 110.0, stain1)
	_overlay.draw_circle(Vector2(0, s.y), 120.0, stain1)
	
	# Inner darker layer right at the corners
	_overlay.draw_circle(Vector2(0, 0), 60.0, stain2)
	_overlay.draw_circle(Vector2(s.x, s.y), 65.0, stain2)
	_overlay.draw_circle(Vector2(s.x, 0), 55.0, stain2)
	_overlay.draw_circle(Vector2(0, s.y), 60.0, stain2)

	# ── Double-line ornate border ──
	var outer := Rect2(Vector2(m, m), s - Vector2(m * 2, m * 2))
	var inner := Rect2(Vector2(m + 5, m + 5), s - Vector2((m + 5) * 2, (m + 5) * 2))
	_overlay.draw_rect(outer, BORDER_INK, false, 2.0)
	_overlay.draw_rect(inner, Color(BORDER_INK, 0.8), false, 1.0)

	# ── Corner ornaments (small diamond shapes) ──
	for corner in [Vector2(m + 2, m + 2), Vector2(s.x - m - 2, m + 2),
				   Vector2(m + 2, s.y - m - 2), Vector2(s.x - m - 2, s.y - m - 2)]:
		_draw_diamond(corner, 5.0, BORDER_INK)

	# ── Compass rose (top-right area, pushed in) ──
	var cx := s.x - 38.0
	var cy := 38.0
	var cr := 16.0
	# Clean background for compass
	_overlay.draw_circle(Vector2(cx, cy), cr + 4, Color(PARCHMENT_BG, 0.85))
	_overlay.draw_arc(Vector2(cx, cy), cr, 0, TAU, 24, Color(BORDER_INK, 0.6), 1.0, true)
	_overlay.draw_line(Vector2(cx, cy - cr), Vector2(cx, cy + cr), BORDER_INK, 2.0)
	_overlay.draw_line(Vector2(cx - cr, cy), Vector2(cx + cr, cy), BORDER_INK, 2.0)
	var diag := cr * 0.5
	for a in [PI/4, 3*PI/4, 5*PI/4, 7*PI/4]:
		var d := Vector2(cos(a), sin(a))
		_overlay.draw_line(Vector2(cx, cy) + d * (diag - 3), Vector2(cx, cy) + d * diag, Color(BORDER_INK, 0.7), 1.0)
	
	_overlay.draw_string(_serif_font, Vector2(cx - 4, cy - cr - 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.15, 0.1))
	_overlay.draw_string(_serif_font, Vector2(cx - 3, cy + cr + 14), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(BORDER_INK, 0.7))
	_overlay.draw_string(_serif_font, Vector2(cx + cr + 5, cy + 4), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(BORDER_INK, 0.7))
	_overlay.draw_string(_serif_font, Vector2(cx - cr - 13, cy + 4), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(BORDER_INK, 0.7))

	# ── Center crosshair ──
	var center := s * 0.5
	# Erase map texture under text for readability
	_overlay.draw_rect(Rect2(center + Vector2(-36, 6), Vector2(72, 14)), Color(PARCHMENT_BG, 0.7))
	_overlay.draw_string(_serif_font, center + Vector2(-32, 18), "You Are Here", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)
	_overlay.draw_line(center + Vector2(-6, 0), center + Vector2(6, 0), INK, 1.0)
	_overlay.draw_line(center + Vector2(0, -6), center + Vector2(0, 6), INK, 1.0)

	# ── Bottom bar background ──
	var bar_y := s.y - 28.0
	_overlay.draw_rect(Rect2(m + 1, bar_y, s.x - (m + 1) * 2, 24), Color(PARCHMENT_DARK, 0.85))
	_overlay.draw_line(Vector2(m + 1, bar_y), Vector2(s.x - m - 1, bar_y), BORDER_INK, 1.0)
	_overlay.draw_string(_serif_font, Vector2(m + 12, bar_y + 17), "Museum Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	var zoom_text := "%d%%" % int(_zoom_level * 100)
	_overlay.draw_string(_serif_font, Vector2(s.x - m - 45, bar_y + 17), zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, 0.8))


func _draw_diamond(center: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r, 0),
		center + Vector2(0, r), center + Vector2(-r, 0),
	])
	_overlay.draw_colored_polygon(pts, color)
