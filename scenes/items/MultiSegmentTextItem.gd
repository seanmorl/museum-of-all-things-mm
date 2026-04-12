extends Node3D
## Text item that can be part of a multi-segment wall text display.
## Shows continuation markers (...) when text continues to/from another segment.

static var max_chars_per_segment := 400

var _text: String = ""
var _segment_index: int = 0
var _total_segments: int = 1
var _is_first_segment: bool = false
var _is_last_segment: bool = false

func _ready() -> void:
	SettingsEvents.accessibility_changed.connect(_on_accessibility_changed)

func init(full_text: String, segment_idx: int, total_segments: int) -> void:
	_text = full_text
	_segment_index = segment_idx
	_total_segments = total_segments
	_is_first_segment = (segment_idx == 0)
	_is_last_segment = (segment_idx == total_segments - 1)
	
	# Calculate which portion of text this segment should display
	var full_text_stripped: String = TextUtils.strip_markup(full_text)
	var total_chars: int = full_text_stripped.length()
	var chars_per_segment: int = ceil(float(total_chars) / float(total_segments))
	
	var start_idx: int = segment_idx * chars_per_segment
	var end_idx: int = min(start_idx + chars_per_segment, total_chars)
	
	var segment_text: String = full_text_stripped.substr(start_idx, end_idx - start_idx)
	
	# Add continuation markers
	if not _is_first_segment:
		segment_text = "… " + segment_text
	if not _is_last_segment:
		segment_text = segment_text + " …"
	
	$Label.text = segment_text
	_apply_accessibility()

func set_segment_info(segment_idx: int, total_segments: int) -> void:
	"""Update segment info and refresh display."""
	init(_text, segment_idx, total_segments)

func interact() -> void:
	if TTSManager:
		var plain_text: String = TextUtils.strip_markup(_text)
		TTSManager.toggle_narration(plain_text)

func _apply_accessibility() -> void:
	var acc: Dictionary = SettingsManager.get_settings("accessibility") if SettingsManager.get_settings("accessibility") else {}

	# Handle Reading Font
	var font := ThemeManager.get_reading_font()
	if font:
		$Label.font = font

	# Handle High Contrast
	var hc: bool = acc.get("high_contrast_text", false)
	if hc:
		$Label.modulate = Color(0, 0, 0, 1)
		$Label.outline_size = 2
		$Label.outline_modulate = Color(1, 1, 1, 1)
	else:
		$Label.modulate = Color(1, 1, 1, 1)
		$Label.outline_size = 0

	var scale_factor: float = acc.get("exhibit_text_size", 1.0)
	$Label.font_size = int(60 * scale_factor)

func _on_accessibility_changed(key: String, _value: Variant) -> void:
	if key in ["reading_font", "high_contrast_text", "exhibit_text_size"]:
		_apply_accessibility()
