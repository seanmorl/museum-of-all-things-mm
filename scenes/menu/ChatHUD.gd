extends Control
class_name ChatHUD
## Top-right chat overlay. Messages appear as toast cards and fade after a timeout.
## T (rebindable) opens the input box. Enter sends, Escape cancels.

const FONT_PATH        := "res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf"
const TYPING_SOUND_PATH := "res://assets/sound/UI/UI Crystal 1.ogg"
const MAX_TOASTS           := 20
const MESSAGE_DISPLAY_TIME := 10.0
const FADE_TIME            := 2.0
const MAX_MESSAGE_LENGTH   := 200

const PANEL_BG     := Color(1.0,  1.0,  1.0,  0.95)
const PANEL_BORDER := Color(0.635, 0.663, 0.694, 1.0)
const SYSTEM_BG    := Color(0.96, 0.96, 0.96, 0.90)
const INPUT_BG     := Color(1.0,  1.0,  1.0,  0.98)
const TEXT_DARK    := Color(0.12, 0.12, 0.12, 1.0)
const TEXT_SUBTLE  := Color(0.45, 0.45, 0.45, 1.0)

var _chat_system: ChatSystem = null
var _font: FontFile = null
var _typing_player: AudioStreamPlayer = null
var _typing_sound_enabled: bool = false
var _rebinding: bool = false
var _input_open: bool = false

# Toast nodes — Array of {panel, time, fading}
var _toasts: Array = []

# Node refs
var _messages_container: VBoxContainer
var _input_panel: PanelContainer
var _input_field: LineEdit
var _char_counter: Label
var _hint_label: Label


func init(chat_system: ChatSystem, _unused: Node = null) -> void:
	_chat_system = chat_system


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)

	# Root — fixed 420px wide, anchored top-right, so it doesn't stretch on widescreen
	anchor_left   = 1.0
	anchor_right  = 1.0
	anchor_top    = 0.0
	anchor_bottom = 0.55
	offset_left   = -434   # 420px wide + 14px margin
	offset_right  = -14
	offset_top    = 12
	mouse_filter  = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	# Messages stack — bottom-aligned toasts
	_messages_container = VBoxContainer.new()
	_messages_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_messages_container.alignment = BoxContainer.ALIGNMENT_END
	_messages_container.add_theme_constant_override("separation", 3)
	_messages_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_messages_container)

	# Input panel
	_input_panel = PanelContainer.new()
	_input_panel.visible = false
	_input_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_panel.add_theme_stylebox_override("panel", _make_card_style(INPUT_BG))
	vbox.add_child(_input_panel)

	var input_hbox := HBoxContainer.new()
	input_hbox.add_theme_constant_override("separation", 6)
	_input_panel.add_child(input_hbox)

	_input_field = LineEdit.new()
	_input_field.placeholder_text = "Say something..."
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.max_length = MAX_MESSAGE_LENGTH
	var empty := StyleBoxEmpty.new()
	_input_field.add_theme_stylebox_override("normal", empty)
	_input_field.add_theme_stylebox_override("focus", empty)
	_input_field.add_theme_stylebox_override("read_only", empty)
	_input_field.add_theme_color_override("font_color", TEXT_DARK)
	_input_field.add_theme_color_override("font_placeholder_color", TEXT_SUBTLE)
	_input_field.add_theme_color_override("caret_color", TEXT_DARK)
	if _font:
		_input_field.add_theme_font_override("font", _font)
	_input_field.add_theme_font_size_override("font_size", 20)
	_input_field.text_submitted.connect(_on_text_submitted)
	_input_field.text_changed.connect(_on_input_changed)
	input_hbox.add_child(_input_field)

	_char_counter = Label.new()
	_char_counter.text = "0/%d" % MAX_MESSAGE_LENGTH
	_char_counter.add_theme_color_override("font_color", TEXT_SUBTLE)
	if _font:
		_char_counter.add_theme_font_override("font", _font)
	_char_counter.add_theme_font_size_override("font_size", 13)
	_char_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	input_hbox.add_child(_char_counter)

	_hint_label = Label.new()
	_hint_label.text = "Enter to send  •  Esc to close"
	_hint_label.add_theme_color_override("font_color", TEXT_SUBTLE)
	if _font:
		_hint_label.add_theme_font_override("font", _font)
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.visible = false
	vbox.add_child(_hint_label)

	# Typing sound
	_typing_player = AudioStreamPlayer.new()
	_typing_player.bus = "UI"
	_typing_player.volume_db = -8.0
	if ResourceLoader.exists(TYPING_SOUND_PATH):
		_typing_player.stream = load(TYPING_SOUND_PATH)
	add_child(_typing_player)

	MultiplayerEvents.chat_message_received.connect(_on_chat_message_received)
	MultiplayerEvents.player_joined.connect(_on_player_joined)
	MultiplayerEvents.player_left.connect(_on_player_left)
	SettingsEvents.chat_enabled_changed.connect(func(e): visible = e)
	SettingsEvents.chat_typing_sound_changed.connect(func(e): _typing_sound_enabled = e)
	_apply_chat_enabled_setting()
	_apply_typing_sound_setting()
	_apply_saved_chat_key()


# ── StyleBox helper ──────────────────────────────────────────────────────────

func _make_card_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left   = 1
	s.border_width_top    = 1
	s.border_width_right  = 1
	s.border_width_bottom = 1
	s.border_color = PANEL_BORDER
	s.corner_radius_top_left     = 2
	s.corner_radius_top_right    = 2
	s.corner_radius_bottom_right = 2
	s.corner_radius_bottom_left  = 2
	s.content_margin_left   = 10.0
	s.content_margin_right  = 10.0
	s.content_margin_top    = 6.0
	s.content_margin_bottom = 6.0
	return s


# ── Animations ───────────────────────────────────────────────────────────────

func _animate_in(node: Control) -> void:
	node.scale = Vector2(0.88, 0.88)
	node.modulate.a = 0.0
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "scale", Vector2(1.0, 1.0), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, 0.25)


func _animate_out(node: Control, on_done: Callable) -> void:
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "scale", Vector2(0.88, 0.88), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(func():
		node.scale = Vector2(1.0, 1.0)
		node.modulate.a = 1.0
		on_done.call()
	)


# ── Public accessors ─────────────────────────────────────────────────────────

func is_input_open() -> bool:
	return _input_open


# ── Rebind ───────────────────────────────────────────────────────────────────

func start_chat_rebind() -> void:
	_rebinding = true


# ── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# If chat is disabled in settings, don't process any chat input
	if not visible:
		return

	# Rebind capture — intercept next keypress
	if _rebinding:
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			_rebinding = false
			InputMap.action_erase_events("chat")
			InputMap.action_add_event("chat", event)
			var saved = SettingsManager.get_settings("multiplayer_ui")
			var data: Dictionary = saved if saved else {}
			data["chat_key"] = event.physical_keycode
			SettingsManager.save_settings("multiplayer_ui", data)
			SettingsEvents.emit_chat_key_changed(OS.get_keycode_string(event.physical_keycode))
		return

	if not NetworkManager.is_multiplayer_active():
		return

	if not _input_open:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.is_action_pressed("chat") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				get_viewport().set_input_as_handled()
				_open_input()
	else:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_close_input()


# ── Open / close ─────────────────────────────────────────────────────────────

func _open_input() -> void:
	_input_open = true
	_input_panel.visible = true
	_hint_label.visible = true
	_input_field.text = ""
	_char_counter.text = "0/%d" % MAX_MESSAGE_LENGTH
	_animate_in(_input_panel)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var player := _get_local_player()
	if player:
		player.pause()
	_input_field.grab_focus()


func _close_input() -> void:
	_input_open = false
	_input_field.text = ""
	var player := _get_local_player()
	if player:
		player.start()
	_animate_out(_input_panel, func():
		_input_panel.visible = false
		_hint_label.visible = false
		_input_panel.scale = Vector2(1.0, 1.0)
		_input_panel.modulate.a = 1.0
	)
	_hint_label.visible = false
	var vote_open := false
	var main_node := get_tree().get_first_node_in_group("main")
	if main_node:
		var vh := main_node.get_node_or_null("TabMenu/VoteHUD")
		vote_open = vh != null and vh.visible
	if not vote_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ── Messages ─────────────────────────────────────────────────────────────────

func _add_message(sender: String, message: String, sender_color: Color, is_system: bool) -> void:
	var bg := SYSTEM_BG if is_system else PANEL_BG
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_card_style(bg))

	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font:
		lbl.add_theme_font_override("normal_font", _font)
		lbl.add_theme_font_override("bold_font",   _font)
	lbl.add_theme_font_size_override("normal_font_size", 20)
	lbl.add_theme_color_override("default_color", TEXT_DARK)

	if is_system:
		lbl.text = "[color=#777777][i]%s[/i][/color]" % sender
	else:
		var hex := sender_color.darkened(0.2).to_html(false)
		lbl.text = "[color=#%s][b]%s[/b][/color]  [color=#1e1e1e]%s[/color]" \
			% [hex, sender, message]

	panel.add_child(lbl)
	_messages_container.add_child(panel)

	if _messages_container.get_child_count() > MAX_TOASTS:
		_messages_container.get_child(0).queue_free()
		_toasts.remove_at(0)

	_animate_in(panel)
	_toasts.append({"panel": panel, "time": MESSAGE_DISPLAY_TIME, "fading": false})


func _on_chat_message_received(sender_name: String, pronouns: String, message: String, color: Color) -> void:
	var pronoun_str := " (%s)" % pronouns if pronouns != "" else ""
	_add_message("%s%s" % [sender_name, pronoun_str], message, color, false)


func _on_player_joined(peer_id: int, _pname: String) -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	var n := NetworkManager.get_player_name(peer_id)
	var p := NetworkManager.get_player_pronouns(peer_id)
	_add_message("%s%s joined the museum" % [n, " (%s)" % p if p != "" else ""], "", Color.WHITE, true)


func _on_player_left(peer_id: int) -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	var n := NetworkManager.get_player_name(peer_id)
	var p := NetworkManager.get_player_pronouns(peer_id)
	_add_message("%s%s left the museum" % [n, " (%s)" % p if p != "" else ""], "", Color.WHITE, true)


# ── Input field callbacks ────────────────────────────────────────────────────

func _on_input_changed(new_text: String) -> void:
	_char_counter.text = "%d/%d" % [new_text.length(), MAX_MESSAGE_LENGTH]
	if _typing_sound_enabled and _typing_player and _typing_player.stream:
		_typing_player.pitch_scale = randf_range(0.95, 1.05)
		_typing_player.play()


func _on_text_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		_close_input()
		return
	if _chat_system:
		_chat_system.send_message(trimmed)
	_close_input()


# ── Toast fade ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	for i in range(_toasts.size() - 1, -1, -1):
		var entry: Dictionary = _toasts[i]
		if not is_instance_valid(entry.panel):
			_toasts.remove_at(i)
			continue
		entry.time -= delta
		if entry.time <= 0.0 and not entry.fading:
			entry.fading = true
			var panel: PanelContainer = entry.panel
			var idx: int = i
			_animate_out(panel, func():
				if is_instance_valid(panel):
					panel.queue_free()
				if idx < _toasts.size():
					_toasts.remove_at(idx)
			)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _get_local_player() -> Node:
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("get_local_player"):
		return main.get_local_player()
	return null


func _apply_saved_chat_key() -> void:
	var saved = SettingsManager.get_settings("multiplayer_ui")
	if saved and saved.has("chat_key"):
		var ev := InputEventKey.new()
		ev.physical_keycode = saved.chat_key
		InputMap.action_erase_events("chat")
		InputMap.action_add_event("chat", ev)


func _apply_chat_enabled_setting() -> void:
	var saved = SettingsManager.get_settings("multiplayer_ui")
	var enabled: bool = true
	if saved and saved.has("chat_enabled"):
		enabled = saved.chat_enabled
	visible = enabled


func _apply_typing_sound_setting() -> void:
	var saved = SettingsManager.get_settings("multiplayer_ui")
	if saved and saved.has("typing_sound_enabled"):
		_typing_sound_enabled = saved.typing_sound_enabled
