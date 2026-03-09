extends Node3D

static var max_chars := 2500

var _text: String = ""

func _ready() -> void:
	SettingsEvents.accessibility_changed.connect(_on_accessibility_changed)

func init(text: String) -> void:
	_text = text
	var t : String = TextUtils.strip_markup(text).substr(0, max_chars)
	$Label.text = t if len(t) < max_chars else t + "..."
	_apply_accessibility()

func interact() -> void:
	if TTSManager:
		TTSManager.toggle_narration(_text)

func _apply_accessibility() -> void:
	var acc: Dictionary = SettingsManager.get_settings("accessibility") if SettingsManager.get_settings("accessibility") else {}
	
	# Handle Reading Font
	var font := ThemeManager.get_reading_font()
	if font:
		$Label.font = font
		
	# Handle High Contrast
	var hc: bool = acc.get("high_contrast_text", false)
	if hc:
		$Label.modulate = Color(0, 0, 0, 1) # Black text
		# Ensure background is white. Assuming visual background is handled by WallItem's plaque.
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 1)
		# Label doesn't have a background but we can add an outline for readability
		$Label.outline_size = 2
		$Label.outline_modulate = Color(1, 1, 1, 1)
	else:
		$Label.modulate = Color(1, 1, 1, 1)
		$Label.outline_size = 0
		
	var scale_factor: float = acc.get("exhibit_text_size", 1.0)
	$Label.font_size = int(60 * scale_factor) # Default label3d font size is usually 32-60, maybe assume base relative to scale

func _on_accessibility_changed(key: String, _value: Variant) -> void:
	if key in ["reading_font", "high_contrast_text", "exhibit_text_size"]:
		_apply_accessibility()

