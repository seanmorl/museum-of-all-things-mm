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

# Difficulty UI — created in code, only visible to host
var _difficulty_row: HBoxContainer = null
var _difficulty_buttons: Dictionary = {}
var _cancel_vote_button: Button = null   # "easy"|"medium"|"hard" -> Button

# Category override UI
var _category_row: VBoxContainer = null
var _category_input: LineEdit = null
var _category_results: VBoxContainer = null
var _category_active_label: Label = null
var _category_search_timer: float = 0.0
var _category_search_pending: String = ""

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

	RaceManager.difficulty_changed.connect(_on_difficulty_changed)
	RaceManager.category_override_changed.connect(_on_category_override_changed)
	RaceManager.vote_cancelled.connect(_on_vote_cancelled)

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


func _process(delta: float) -> void:
	if not visible or not RaceManager.is_vote_active():
		# Still tick the category debounce even when vote display is idle
		if _category_search_pending != "":
			_category_search_timer -= delta
			if _category_search_timer <= 0.0:
				var query := _category_search_pending
				_category_search_pending = ""
				ExhibitFetcher.fetch_category_search(query, null)
		return
	_countdown_label.text = "Time remaining: %d" % int(ceil(RaceManager.get_vote_time_remaining()))
	# Category search debounce
	if _category_search_pending != "":
		_category_search_timer -= delta
		if _category_search_timer <= 0.0:
			var query := _category_search_pending
			_category_search_pending = ""
			ExhibitFetcher.fetch_category_search(query, null)


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

	# Build difficulty row lazily on first vote (network state is valid here)
	if NetworkManager.is_server():
		if _difficulty_row == null:
			_build_difficulty_row()
		_difficulty_row.visible = true
		if _category_row == null:
			_build_category_row()
		_category_row.visible = true
		if _cancel_vote_button == null:
			_build_cancel_vote_button()
		_cancel_vote_button.visible = true
		_cancel_vote_button.disabled = false
	elif _difficulty_row:
		_difficulty_row.visible = false
		if _category_row:
			_category_row.visible = false

	_bounce_in()


func _on_candidate_pressed(index: int) -> void:
	_my_vote = index
	RaceManager.cast_vote(index)
	for i in _candidate_buttons.size():
		_candidate_buttons[i].disabled = (i != index)
	_status_label.text = "Voted for: " + RaceManager.get_vote_candidates()[index]


func _build_difficulty_row() -> void:
	var content := _reroll_button.get_parent()

	_difficulty_row = HBoxContainer.new()
	_difficulty_row.add_theme_constant_override("separation", 4)
	# Insert above the reroll button
	content.add_child(_difficulty_row)
	content.move_child(_difficulty_row, _reroll_button.get_index())

	var lbl := Label.new()
	lbl.text = "Difficulty:"
	lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_difficulty_row.add_child(lbl)

	for diff in ["Very Easy", "Easy", "Medium", "Hard", "Random 🎲"]:
		var btn := Button.new()
		btn.text = diff
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		var key: String = diff.to_lower().replace(" 🎲", "").replace(" ", "_")
		btn.pressed.connect(_on_difficulty_btn_pressed.bind(key))
		_difficulty_row.add_child(btn)
		_difficulty_buttons[key] = btn

	_refresh_difficulty_buttons(RaceManager.get_difficulty())


func _refresh_difficulty_buttons(difficulty: String) -> void:
	for key in _difficulty_buttons:
		var btn: Button = _difficulty_buttons[key]
		btn.button_pressed = (key == difficulty)


func _on_difficulty_btn_pressed(difficulty: String) -> void:
	RaceManager.set_difficulty(difficulty)


func _on_difficulty_changed(difficulty: String) -> void:
	if _difficulty_row:
		_refresh_difficulty_buttons(difficulty)


func _build_category_row() -> void:
	var content := _reroll_button.get_parent()

	_category_row = VBoxContainer.new()
	_category_row.add_theme_constant_override("separation", 4)
	content.add_child(_category_row)
	content.move_child(_category_row, _reroll_button.get_index())

	# Header row: label + clear button
	var header := HBoxContainer.new()
	_category_row.add_child(header)

	var lbl := Label.new()
	lbl.text = "Category filter:"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
	header.add_child(lbl)

	var clear_btn := Button.new()
	clear_btn.text = "✕ Clear"
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(_on_category_clear_pressed)
	header.add_child(clear_btn)

	# Search input
	_category_input = LineEdit.new()
	_category_input.placeholder_text = "Search a Wikipedia category..."
	_category_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_input.text_changed.connect(_on_category_input_changed)
	_category_row.add_child(_category_input)

	# Results list (filled dynamically)
	_category_results = VBoxContainer.new()
	_category_results.add_theme_constant_override("separation", 2)
	_category_row.add_child(_category_results)

	# Active category display
	_category_active_label = Label.new()
	_category_active_label.text = ""
	_category_active_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_category_active_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	_category_active_label.add_theme_font_size_override("font_size", 12)
	_category_row.add_child(_category_active_label)

	ExhibitFetcher.category_search_complete.connect(_on_category_search_results)


func _on_category_input_changed(text: String) -> void:
	# Clear results immediately on empty
	if text.strip_edges() == "":
		_category_search_pending = ""
		for child in _category_results.get_children():
			child.queue_free()
		return
	# Debounce: wait 0.5s after last keystroke before searching
	_category_search_pending = text.strip_edges()
	_category_search_timer = 0.5


func _on_category_search_results(categories: Array, _ctx: Variant) -> void:
	if not is_instance_valid(_category_results):
		return
	for child in _category_results.get_children():
		child.queue_free()
	for cat_name in categories:
		var display: String = cat_name.replace("Category:", "")
		var btn := Button.new()
		btn.text = display
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_category_selected.bind(cat_name))
		_category_results.add_child(btn)


func _on_category_selected(cat_name: String) -> void:
	RaceManager.set_category_override(cat_name)
	# Clear input and results, resume timer
	_category_input.text = ""
	for child in _category_results.get_children():
		child.queue_free()
	RaceManager.set_vote_timer_paused(false)


func _on_category_clear_pressed() -> void:
	RaceManager.set_category_override("")
	_category_input.text = ""
	for child in _category_results.get_children():
		child.queue_free()
	RaceManager.set_vote_timer_paused(false)


func _on_category_override_changed(category_name: String) -> void:
	if not is_instance_valid(_category_active_label):
		return
	if category_name == "":
		_category_active_label.text = ""
	else:
		var display: String = category_name.replace("Category:", "")
		_category_active_label.text = "Active: %s" % display


func _build_cancel_vote_button() -> void:
	var content := _reroll_button.get_parent()
	_cancel_vote_button = Button.new()
	_cancel_vote_button.text = "✕  Cancel race"
	_cancel_vote_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_cancel_vote_button.focus_mode = Control.FOCUS_NONE
	_cancel_vote_button.add_theme_color_override("font_color", Color(0.85, 0.25, 0.25))
	_cancel_vote_button.pressed.connect(_on_cancel_vote_pressed)
	content.add_child(_cancel_vote_button)
	# Place below reroll button
	content.move_child(_cancel_vote_button, _reroll_button.get_index() + 1)


func _on_cancel_vote_pressed() -> void:
	if not NetworkManager.is_server():
		return
	_cancel_vote_button.disabled = true
	RaceManager.cancel_vote()


func _on_vote_cancelled() -> void:
	_bounce_out()


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
	RaceManager.set_vote_timer_paused(false)
	_countdown_label.text = "Race starting!"
	_status_label.text = "Target: " + winner
	for btn in _candidate_buttons:
		btn.disabled = true
	_reroll_button.visible = false
	if _difficulty_row:
		_difficulty_row.visible = false
	if _category_row:
		_category_row.visible = false
	if _cancel_vote_button:
		_cancel_vote_button.visible = false


func _on_race_started(_target: String, _start: String) -> void:
	await get_tree().create_timer(1.5).timeout
	_bounce_out()
