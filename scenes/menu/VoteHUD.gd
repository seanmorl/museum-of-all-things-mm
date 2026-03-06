extends Control
## In-world HUD overlay for voting on the race target article.

@onready var _countdown_label: Label = $MarginContainer/CenterContainer/Panel/Content/CountdownLabel
@onready var _candidates_container: VBoxContainer = $MarginContainer/CenterContainer/Panel/Content/CandidatesContainer
@onready var _status_label: Label = $MarginContainer/CenterContainer/Panel/Content/StatusLabel
@onready var _reroll_button: Button = $MarginContainer/CenterContainer/Panel/Content/RerollButton
@onready var _panel: PanelContainer = $MarginContainer/CenterContainer/Panel
@onready var _loading_overlay: Control = $LoadingOverlay

var _my_vote: int = -1
var _candidate_buttons: Array[Button] = []
var _panel_style: StyleBoxFlat
var _is_animating: bool = false


func _ready() -> void:
	visible = false
	var orig := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if orig:
		_panel_style = orig.duplicate()
		_panel.add_theme_stylebox_override("panel", _panel_style)

	RaceManager.vote_started.connect(_on_vote_started)
	RaceManager.vote_ended.connect(_on_vote_ended)
	RaceManager.race_started.connect(_on_race_started)
	ThemeManager.dark_mode_changed.connect(_apply_theme)
	_apply_theme(ThemeManager.is_dark_mode)

	_reroll_button.visible = NetworkManager.is_server()

	if RaceManager.is_vote_active():
		_on_vote_started(RaceManager.get_vote_candidates())


func _apply_theme(_dark: bool) -> void:
	ThemeManager.update_panel_style(_panel_style)
	if _countdown_label:
		_countdown_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	if _status_label:
		_status_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	if _reroll_button:
		_reroll_button.add_theme_color_override("font_color", ThemeManager.subtext_color)
	for btn in _candidate_buttons:
		btn.add_theme_color_override("font_color", ThemeManager.text_color)


func show_loading() -> void:
	visible = true
	_loading_overlay.visible = true
	_loading_overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_loading_overlay, "modulate:a", 1.0, 0.2)


func hide_loading() -> void:
	var tw := create_tween()
	tw.tween_property(_loading_overlay, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func(): _loading_overlay.visible = false)


func _process(_delta: float) -> void:
	if not visible or not RaceManager.is_vote_active():
		return
	_countdown_label.text = "Time remaining: %d" % int(ceil(RaceManager.get_vote_time_remaining()))


func _bounce_in() -> void:
	_is_animating = false
	visible = true
	# Show cursor for all players so they can click vote buttons
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)


func _bounce_out() -> void:
	if _is_animating:
		return
	_is_animating = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2(0.85, 0.85), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(func():
		_is_animating = false
		visible = false
		_panel.scale = Vector2(1.0, 1.0)
		_panel.modulate.a = 1.0
		# Recapture mouse once voting UI is gone
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	)


func _on_vote_started(candidates: Array) -> void:
	_my_vote = -1
	_status_label.text = "Vote for the race target!"
	hide_loading()

	for child in _candidates_container.get_children():
		child.queue_free()
	_candidate_buttons.clear()

	for i in candidates.size():
		var btn := Button.new()
		btn.text = candidates[i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color", ThemeManager.text_color)
		btn.pressed.connect(_on_candidate_pressed.bind(i))
		_candidates_container.add_child(btn)
		_candidate_buttons.append(btn)

	_reroll_button.visible = NetworkManager.is_server()
	_bounce_in()


func _on_candidate_pressed(index: int) -> void:
	_my_vote = index
	RaceManager.cast_vote(index)
	for i in _candidate_buttons.size():
		_candidate_buttons[i].disabled = (i != index)
	_status_label.text = "Voted for: " + RaceManager.get_vote_candidates()[index]


func _on_reroll_pressed() -> void:
	if not NetworkManager.is_server():
		return
	_reroll_button.disabled = true
	_reroll_button.text = "↺  Fetching..."
	show_loading()
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("reroll_vote"):
		main.reroll_vote()
	else:
		push_error("VoteHUD: could not find Main in group 'main'")


func on_reroll_ready() -> void:
	_reroll_button.disabled = false
	_reroll_button.text = "↺  Reroll options (host only)"


func _on_close_pressed() -> void:
	_bounce_out()


func _on_vote_ended(winner: String) -> void:
	_countdown_label.text = "Race starting!"
	_status_label.text = "Target: " + winner
	for btn in _candidate_buttons:
		btn.disabled = true
	_reroll_button.visible = false


func _on_race_started(_target: String, _start: String) -> void:
	await get_tree().create_timer(1.5).timeout
	_bounce_out()
