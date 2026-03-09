extends Control
## A center-bottom prompt that shows "Press E to [Action]" for interactables.

const FADE_TIME := 0.2
const PANEL_COLOR := Color(0, 0, 0, 0.6)
const TEXT_COLOR := Color(1, 1, 1, 0.9)

var _target: Node = null
var _player: Node = null
var _font: Font = null
var _is_visible: bool = false

@onready var _panel: PanelContainer = $PanelContainer
@onready var _label: RichTextLabel = $PanelContainer/RichTextLabel

func _ready() -> void:
	_font = ThemeManager.get_reading_font()
	ThemeManager.reading_font_changed.connect(_on_font_changed)
	ThemeManager.is_dark_mode # Ensure theme manager is active
	
	modulate.a = 0.0
	visible = false
	_refresh_theme()
	
	# Initial setup of label
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	if _font:
		_label.add_theme_font_override("normal_font", _font)
		_label.add_theme_font_override("bold_font", _font)
	_label.add_theme_font_size_override("normal_font_size", 20)

func init(player: Node) -> void:
	_player = player
	if _player and _player.has_signal("interactable_target_changed"):
		_player.interactable_target_changed.connect(_on_target_changed)

func _on_font_changed(new_font: Font) -> void:
	_font = new_font
	if _label:
		_label.add_theme_font_override("normal_font", _font)
		_label.add_theme_font_override("bold_font", _font)

func _on_target_changed(new_target: Node) -> void:
	Log.debug("PromptHUD", "Target changed: %s" % str(new_target))
	_target = new_target
	_update_prompt()

func _process(_delta: float) -> void:
	if _target and is_instance_valid(_target):
		_update_prompt() # Refresh text in case state changed (e.g. music started)
	elif _is_visible:
		_fade_out()

func _update_prompt() -> void:
	var interactable: Node = null
	if _target:
		if _target.has_method("interact") or _target.has_method("get_interaction_text"):
			interactable = _target
		elif _target.get_parent() and (_target.get_parent().has_method("interact") or _target.get_parent().has_method("get_interaction_text")):
			interactable = _target.get_parent()
	
	if interactable:
		var action_text := "Interact"
		if interactable.has_method("get_interaction_text"):
			action_text = interactable.get_interaction_text()
		
		# Show prompt
		var key_text := "[b][color=#FFCC00]E[/color][/b]"
		_label.text = "[center]Press %s to %s[/center]" % [key_text, action_text]
		_fade_in()
	else:
		_fade_out()

func _fade_in() -> void:
	if _is_visible: return
	_is_visible = true
	visible = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	# Slide PanelContainer from bottom
	tw.parallel().tween_property(_panel, "position:y", size.y - 120, FADE_TIME).from(size.y - 0)

func _fade_out() -> void:
	if not _is_visible: return
	_is_visible = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	# Slide PanelContainer out
	tw.parallel().tween_property(_panel, "position:y", size.y - 0, FADE_TIME)
	tw.tween_callback(func(): if not _is_visible: visible = false)

func _refresh_theme() -> void:
	if not _panel: return
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.1, 0.1, 0.7) if ThemeManager.is_dark_mode else Color(0.9, 0.9, 0.9, 0.7)
	s.set_corner_radius_all(4)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = ThemeManager.border_color
	_panel.add_theme_stylebox_override("panel", s)
	_label.add_theme_color_override("default_color", ThemeManager.text_color)
