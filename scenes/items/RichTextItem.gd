extends Node3D

static var margin_top := 100
const MAX_LAYOUT_RETRIES := 10
const MAX_TRIM_RETRIES := 20

var _layout_retries := 0
var _trim_retries := 0

func init(text: String) -> void:
	_layout_retries = 0
	_trim_retries = 0
	var label: RichTextLabel = $SubViewport/Control/RichTextLabel
	var t: String = TextUtils.strip_markup(text)
	
	t = _apply_accessibility(t, label)
	
	label.text = t
	# Disable auto-render; _center_vertically will trigger it once positioning is done
	$SubViewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	call_deferred("_center_vertically", label)

func _apply_accessibility(text_content: String, label: RichTextLabel) -> String:
	var acc: Dictionary = SettingsManager.get_settings("accessibility") if SettingsManager.get_settings("accessibility") else {}
	
	# Handle High Contrast
	var hc: bool = acc.get("high_contrast_text", false)
	if hc:
		# Enforce black text and white background for readability
		# RichTextItem renders onto a viewport, so we can change the viewport background
		# Using color tags to force black text
		text_content = "[color=black]" + text_content + "[/color]"
		# Background is managed by the SubViewport or we can add a ColorRect behind the label
		var bg_rect = $SubViewport/Control.get_node_or_null("BackgroundRect")
		if not bg_rect:
			bg_rect = ColorRect.new()
			bg_rect.name = "BackgroundRect"
			bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			bg_rect.color = Color(1, 1, 1, 1)
			$SubViewport/Control.add_child(bg_rect)
			$SubViewport/Control.move_child(bg_rect, 0) # Move behind label
		bg_rect.visible = true
	else:
		var bg_rect = $SubViewport/Control.get_node_or_null("BackgroundRect")
		if bg_rect:
			bg_rect.visible = false

	var font := ThemeManager.get_reading_font()
	var font_size: int = 18
	var acc_settings = SettingsManager.get_settings("accessibility")
	if acc_settings and acc_settings.get("reading_font", 0) == 1:
		font_size = 14 # OpenDyslexic is natively larger
	
	if font:
		label.add_theme_font_override("normal_font", font)
		label.add_theme_font_override("bold_font", font)
		label.add_theme_font_override("italics_font", font)
		label.add_theme_font_override("bold_italics_font", font)
		label.add_theme_font_override("mono_font", font)

	# Handle Exhibit Text Size
	var scale_factor: float = acc.get("exhibit_text_size", 1.0)
	label.add_theme_font_size_override("normal_font_size", int(font_size * scale_factor))
	label.add_theme_font_size_override("bold_font_size", int(font_size * scale_factor))
	label.add_theme_font_size_override("italics_font_size", int(font_size * scale_factor))
	label.add_theme_font_size_override("bold_italics_font_size", int(font_size * scale_factor))
	label.add_theme_font_size_override("mono_font_size", int(font_size * scale_factor))
	
	return text_content


func _center_vertically(label: RichTextLabel) -> void:
	var vp: SubViewport = $SubViewport
	var viewport_size: Vector2i = vp.size
	var content_height: float = label.get_content_height()

	# Layout not ready yet — wait a frame, but give up after MAX_LAYOUT_RETRIES
	if content_height <= 0:
		_layout_retries += 1
		if _layout_retries < MAX_LAYOUT_RETRIES:
			call_deferred("_center_vertically", label)
			return
		# Give up waiting — render as-is

	if content_height > viewport_size.y - 2 * margin_top:
		_trim_retries += 1
		if _trim_retries < MAX_TRIM_RETRIES and len(label.text) > 10:
			var text_len: int = len(label.text)
			var new_len: float = text_len * (float(viewport_size.y - 2 * margin_top) / float(content_height))
			label.text = TextUtils.trim_to_length_sentence(label.text, min(text_len - 1, new_len))
			call_deferred("_center_vertically", label)
			return

	# Calculate the centered Y position
	if content_height > 0:
		var y_position: float = max((viewport_size.y - content_height) / 2, margin_top)
		label.position.y = y_position

	# Wait one frame so the position change is committed to the rendering
	# pipeline before the SubViewport renders — without this, the compatibility
	# renderer (web) captures the texture before the position update is visible.
	await get_tree().process_frame
	if not is_instance_valid(vp):
		return

	# Text is positioned — render once and capture the texture
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if Platform.is_compatibility_renderer():
		# Skip MipmapThread entirely — grab viewport texture directly
		await RenderingServer.frame_post_draw
		if not is_instance_valid(vp):
			return
		var image: Image = vp.get_texture().get_image()
		image.flip_y()
		var texture: ImageTexture = ImageTexture.create_from_image(image)
		if is_instance_valid(self):
			$Sprite3D.texture = texture
		vp.queue_free()
	else:
		MipmapThread.get_viewport_texture_with_mipmaps(vp, func(texture: Variant) -> void:
			if is_instance_valid(self):
				$Sprite3D.texture = texture
			vp.queue_free()
		)
