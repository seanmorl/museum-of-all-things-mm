extends Control
## A center-bottom prompt that shows "Press E to [Action]" for interactables.

const FADE_IN := 0.2
const FADE_OUT := 0.15

var _target: Node = null
var _player: Node = null
var _font: Font = null
var _is_visible: bool = false
var _anim_tw: Tween = null

@onready var _panel: PanelContainer = $PanelContainer
@onready var _label: RichTextLabel = $PanelContainer/RichTextLabel

func _ready() -> void:
	_font = ThemeManager.get_reading_font()
	ThemeManager.reading_font_changed.connect(_on_font_changed)
	ThemeManager.dark_mode_changed.connect(func(_d): _refresh_theme())

	if not _panel or not _label:
		return

	modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	visible = false
	_refresh_theme()

	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	if _font:
		_label.add_theme_font_override("normal_font", _font)
		_label.add_theme_font_override("bold_font", _font)
	_label.add_theme_font_size_override("normal_font_size", 18)

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
	_target = new_target
	_update_prompt()

var _showing_text: bool = false
var _pending_prompt_update: bool = false

func show_text(content: String) -> void:
	_kill_all_tweens()
	var display := content.substr(0, 500)
	if content.length() > 500:
		display += "..."
	_label.text = "[center]%s[/center]" % [display]
	_is_visible = true
	visible = true
	_showing_text = true
	_pending_prompt_update = true
	modulate.a = 1.0
	_panel.scale = Vector2(1.0, 1.0)
	_panel.offset_top = -120.0
	await get_tree().create_timer(6.0).timeout
	_showing_text = false
	if _pending_prompt_update:
		_update_prompt()

func _process(_delta: float) -> void:
	if _showing_text:
		return
	if _target and is_instance_valid(_target):
		_update_prompt()
	elif _is_visible:
		_fade_out()

func _update_prompt() -> void:
	var interactable: Node = null
	var node: Node = _target
	while node:
		if node.has_method("interact") or node.has_method("get_interaction_text"):
			interactable = node
			break
		node = node.get_parent()

	if interactable:
		var action_text := "Interact"
		if interactable.has_method("get_interaction_text"):
			action_text = interactable.get_interaction_text()
		var key_text := "[b][color=#FFCC00]E[/color][/b]"
		_label.text = "[center]Press %s to %s[/center]" % [key_text, action_text]
		_fade_in()
	else:
		_fade_out()

func _fade_in() -> void:
	if _is_visible:
		return
	_kill_all_tweens()
	_is_visible = true
	visible = true

	_panel.scale = Vector2(0.92, 0.92)

	_anim_tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_anim_tw.tween_property(self, "modulate:a", 1.0, FADE_IN)
	_anim_tw.parallel().tween_property(_panel, "scale", Vector2(1.0, 1.0), FADE_IN)
	_anim_tw.parallel().tween_property(_panel, "offset_top", -120.0, FADE_IN)

func _fade_out() -> void:
	if not _is_visible:
		return
	_kill_all_tweens()
	_is_visible = false

	_anim_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_anim_tw.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	_anim_tw.parallel().tween_property(_panel, "scale", Vector2(0.92, 0.92), FADE_OUT)
	_anim_tw.parallel().tween_property(_panel, "offset_top", -120.0, FADE_OUT)
	_anim_tw.tween_callback(func():
		if not _is_visible:
			visible = false
	)

func _kill_all_tweens() -> void:
	if _anim_tw and _anim_tw.is_valid():
		_anim_tw.kill()
		_anim_tw = null

func _refresh_theme() -> void:
	if not _panel:
		return
	var dark := ThemeManager.is_dark_mode
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.08, 0.1, 0.85) if dark else Color(1, 1, 1, 0.88)
	s.set_corner_radius_all(10)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = Color(1, 1, 1, 0.1) if dark else Color(0, 0, 0, 0.06)
	s.shadow_color = Color(0, 0, 0, 0.3 if dark else 0.08)
	s.shadow_size = 16
	s.shadow_offset = Vector2(0, 4)
	_panel.add_theme_stylebox_override("panel", s)
	_label.add_theme_color_override("default_color", ThemeManager.text_color)

func _exit_tree() -> void:
	_kill_all_tweens()
