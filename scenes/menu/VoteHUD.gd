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

# Host-only controls panel — difficulty, hints, category, cancel
var _host_panel: VBoxContainer = null
var _cancel_vote_button: Button = null
# Difficulty
var _difficulty_row: HBoxContainer = null
var _difficulty_buttons: Dictionary = {}
# Category
var _category_toggle_btn: Button = null
var _category_section: VBoxContainer = null
var _category_input: LineEdit = null
var _category_results: VBoxContainer = null
var _category_active_label: Label = null
var _category_search_timer: float = 0.0
var _category_search_pending: String = ""
# Hints
var _hint_buttons: Dictionary = {}
var _hint_reveal_btn: Button = null
var _hint_custom_edit: LineEdit = null

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
	RaceManager.hint_settings_changed.connect(_on_hint_settings_changed)
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
	hide_loading()
	_candidates_container.visible = true

	for child in _candidates_container.get_children():
		child.queue_free()
	_candidate_buttons.clear()

	if NetworkManager.is_server():
		_status_label.text = "Pick a starting room — vote will begin"

		for i in candidates.size():
			var btn := Button.new()
			btn.text = candidates[i]
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_color_override("font_color", ThemeManager.text_color)
			btn.pressed.connect(_on_candidate_pressed.bind(i))
			_candidates_container.add_child(btn)
			_candidate_buttons.append(btn)

		_reroll_button.visible = true
		if _host_panel == null:
			_build_host_panel()
		_host_panel.visible = true
	else:
		_status_label.text = "Waiting for host to start the race..."
		_candidates_container.visible = false
		_reroll_button.visible = false
		if _host_panel:
			_host_panel.visible = false

	_bounce_in()


func _on_candidate_pressed(index: int) -> void:
	_my_vote = index
	RaceManager.cast_vote(index)
	for i in _candidate_buttons.size():
		_candidate_buttons[i].disabled = (i != index)
	_status_label.text = "Voted for: " + RaceManager.get_vote_candidates()[index]


## Builds one compact host panel inserted above the reroll button.
## Row 1: Difficulty buttons
## Row 2: Hints mode buttons + custom input / reveal button
## Collapsible: Category filter
## Bottom: Cancel vote button
func _build_host_panel() -> void:
	var content := _reroll_button.get_parent()

	_host_panel = VBoxContainer.new()
	_host_panel.add_theme_constant_override("separation", 3)
	content.add_child(_host_panel)
	content.move_child(_host_panel, _reroll_button.get_index())

	## — Row 1: Difficulty —
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.add_theme_constant_override("separation", 3)
	_host_panel.add_child(_difficulty_row)

	var diff_lbl := Label.new()
	diff_lbl.text = "Diff:"
	diff_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
	diff_lbl.custom_minimum_size.x = 32
	_difficulty_row.add_child(diff_lbl)

	for diff in ["Very Easy", "Easy", "Medium", "Hard", "Random 🎲"]:
		var btn := Button.new()
		btn.text = diff
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = diff.to_lower().replace(" 🎲", "").replace(" ", "_")
		btn.pressed.connect(_on_difficulty_btn_pressed.bind(key))
		_difficulty_row.add_child(btn)
		_difficulty_buttons[key] = btn

	_refresh_difficulty_buttons(RaceManager.get_difficulty())

	## — Row 2: Hints —
	var hint_row := HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 3)
	_host_panel.add_child(hint_row)

	var hint_lbl := Label.new()
	hint_lbl.text = "Hints:"
	hint_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
	hint_lbl.custom_minimum_size.x = 32
	hint_row.add_child(hint_lbl)

	for opt in [
		{"label": "Off",    "interval": -1.0,  "manual": false},
		{"label": "10m",    "interval": 600.0, "manual": false},
		{"label": "5m",     "interval": 300.0, "manual": false},
		{"label": "Manual", "interval": -1.0,  "manual": true},
		{"label": "Custom", "interval": 0.0,   "manual": false},
	]:
		var btn := Button.new()
		btn.text = opt.label
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_hint_btn_pressed.bind(opt.interval, opt.manual, opt.label == "Custom"))
		hint_row.add_child(btn)
		_hint_buttons[opt.label] = btn

	# Custom minutes textbox
	_hint_custom_edit = LineEdit.new()
	_hint_custom_edit.placeholder_text = "min"
	_hint_custom_edit.custom_minimum_size.x = 48
	_hint_custom_edit.max_length = 3
	_hint_custom_edit.visible = false
	_hint_custom_edit.focus_mode = Control.FOCUS_CLICK
	_hint_custom_edit.text_submitted.connect(_on_hint_custom_submitted)
	hint_row.add_child(_hint_custom_edit)

	# Reveal now button (manual mode)
	_hint_reveal_btn = Button.new()
	_hint_reveal_btn.text = "💡 Now"
	_hint_reveal_btn.focus_mode = Control.FOCUS_NONE
	_hint_reveal_btn.visible = false
	_hint_reveal_btn.pressed.connect(_on_hint_reveal_pressed)
	hint_row.add_child(_hint_reveal_btn)

	_refresh_hint_buttons(RaceManager.get_hint_interval(), RaceManager.get_hint_manual())

	## — Category filter (collapsible) —
	_category_toggle_btn = Button.new()
	_category_toggle_btn.text = "▶ Category filter"
	_category_toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_category_toggle_btn.focus_mode = Control.FOCUS_NONE
	_category_toggle_btn.flat = true
	_category_toggle_btn.add_theme_color_override("font_color", ThemeManager.subtext_color)
	_category_toggle_btn.pressed.connect(_on_category_toggle)
	_host_panel.add_child(_category_toggle_btn)

	_category_section = VBoxContainer.new()
	_category_section.add_theme_constant_override("separation", 3)
	_category_section.visible = false
	_host_panel.add_child(_category_section)

	var cat_header := HBoxContainer.new()
	_category_section.add_child(cat_header)

	_category_input = LineEdit.new()
	_category_input.placeholder_text = "Search Wikipedia category..."
	_category_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_input.text_changed.connect(_on_category_input_changed)
	cat_header.add_child(_category_input)

	var clear_btn := Button.new()
	clear_btn.text = "✕"
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(_on_category_clear_pressed)
	cat_header.add_child(clear_btn)

	_category_results = VBoxContainer.new()
	_category_results.add_theme_constant_override("separation", 2)
	_category_section.add_child(_category_results)

	_category_active_label = Label.new()
	_category_active_label.text = ""
	_category_active_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_category_active_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	_category_active_label.add_theme_font_size_override("font_size", 11)
	_category_section.add_child(_category_active_label)

	ExhibitFetcher.category_search_complete.connect(_on_category_search_results)

	## — Cancel button —
	_cancel_vote_button = Button.new()
	_cancel_vote_button.text = "✕  Cancel vote"
	_cancel_vote_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_cancel_vote_button.focus_mode = Control.FOCUS_NONE
	_cancel_vote_button.flat = true
	_cancel_vote_button.add_theme_color_override("font_color", Color(0.85, 0.25, 0.25))
	_cancel_vote_button.pressed.connect(_on_cancel_vote_pressed)
	_host_panel.add_child(_cancel_vote_button)


func _on_category_toggle() -> void:
	if not _category_section:
		return
	_category_section.visible = not _category_section.visible
	_category_toggle_btn.text = ("▼ Category filter" if _category_section.visible else "▶ Category filter")


func _refresh_difficulty_buttons(difficulty: String) -> void:
	for key in _difficulty_buttons:
		_difficulty_buttons[key].button_pressed = (key == difficulty)


func _on_difficulty_btn_pressed(difficulty: String) -> void:
	RaceManager.set_difficulty(difficulty)


func _on_difficulty_changed(difficulty: String) -> void:
	_refresh_difficulty_buttons(difficulty)


func _on_category_input_changed(text: String) -> void:
	if text.strip_edges() == "":
		_category_search_pending = ""
		for child in _category_results.get_children():
			child.queue_free()
		return
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
	_category_active_label.text = ("Active: %s" % category_name.replace("Category:", "")) if category_name != "" else ""
	if _category_toggle_btn and category_name != "":
		_category_toggle_btn.text = "▼ Category filter"
		if _category_section:
			_category_section.visible = true


func _refresh_hint_buttons(interval: float, manual: bool) -> void:
	if _hint_buttons.is_empty():
		return
	var active: String
	if manual:
		active = "Manual"
	elif interval <= 0.0:
		active = "Off"
	elif interval >= 600.0:
		active = "10m"
	elif interval >= 300.0:
		active = "5m"
	else:
		active = "Custom"
	for lbl in _hint_buttons:
		_hint_buttons[lbl].button_pressed = (lbl == active)
	if _hint_reveal_btn:
		_hint_reveal_btn.visible = manual
	if _hint_custom_edit:
		_hint_custom_edit.visible = (active == "Custom")
		if active == "Custom" and interval > 0.0:
			_hint_custom_edit.text = str(int(round(interval / 60.0)))


func _on_hint_btn_pressed(interval: float, manual: bool, is_custom: bool) -> void:
	if is_custom:
		if _hint_custom_edit:
			_hint_custom_edit.visible = true
			_hint_custom_edit.grab_focus()
			var mins := _hint_custom_edit.text.to_int()
			if mins > 0:
				RaceManager.set_hint_settings(mins * 60.0, false)
	else:
		if _hint_custom_edit:
			_hint_custom_edit.visible = false
		RaceManager.set_hint_settings(interval, manual)


func _on_hint_custom_submitted(text: String) -> void:
	var mins := text.to_int()
	if mins > 0:
		RaceManager.set_hint_settings(mins * 60.0, false)
		_hint_custom_edit.release_focus()


func _on_hint_settings_changed(interval: float, manual: bool) -> void:
	_refresh_hint_buttons(interval, manual)


func _on_hint_reveal_pressed() -> void:
	RaceManager.reveal_hint_now()


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
	if _host_panel:
		_host_panel.visible = false


func _on_race_started(_target: String, _start: String) -> void:
	await get_tree().create_timer(1.5).timeout
	_bounce_out()
