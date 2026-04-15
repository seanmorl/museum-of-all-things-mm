extends Control
## VoteHUD — elegant in-world voting overlay. All UI built in code.
## No @onready tscn node dependencies. Preserves all original functionality:
##   candidates, timer, host panel (difficulty/category/player mgmt/reroll),
##   seeded shuffle, force start, cancel, kick, loading screen integration.

# ── Node refs ─────────────────────────────────────────────────────────────────
var _serif_font:   Font           = null
var _panel:        PanelContainer = null
var _panel_style:  StyleBoxFlat   = null
var _title_label:  Label          = null
var _timer_label:  Label          = null
var _status_label: Label          = null
var _candidates_container: VBoxContainer = null
var _reroll_btn:   Button         = null
var _host_panel:   VBoxContainer  = null

# ── Loading overlay (fallback when LoadingScreen autoload unavailable) ────────
var _loading_overlay:  Control    = null
var _loading_label:    Label      = null
var _loading_sublabel: Label      = null
var _spinner_angle:    float      = 0.0
var _spinner_canvas:   Control    = null
var _using_new_loading_screen: bool = false

# ── Vote state ────────────────────────────────────────────────────────────────
var _my_vote:             int            = -1
var _candidate_buttons:   Array[Button]  = []
var _is_animating:        bool           = false
var _chat_system:         Node           = null

# ── Signal connections for cleanup ──────────────────────────────────────────
var _dark_mode_lambda: Callable          = Callable()
var _reading_font_lambda: Callable       = Callable()

# ── Host panel refs ───────────────────────────────────────────────────────────
var _cancel_vote_button:   Button        = null
var _difficulty_row:       HBoxContainer = null
var _difficulty_buttons:   Dictionary   = {}
var _category_toggle_btn:  Button        = null
var _category_section:     VBoxContainer = null
var _category_input:       LineEdit      = null
var _category_results:     VBoxContainer = null
var _category_active_label: Label        = null
var _category_search_timer: float        = 0.0
var _category_search_pending: String     = ""


func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	visible = false
	_build_ui()
	add_to_group("mouse_overlay")
	_apply_theme(ThemeManager.is_dark_mode)
	_dark_mode_lambda = func(_d): _apply_theme(ThemeManager.is_dark_mode)
	_reading_font_lambda = func(f): _serif_font = f; _apply_theme(ThemeManager.is_dark_mode)
	ThemeManager.dark_mode_changed.connect(_dark_mode_lambda)
	ThemeManager.reading_font_changed.connect(_reading_font_lambda)
	RaceManager.vote_started.connect(_on_vote_started)
	RaceManager.vote_ended.connect(_on_vote_ended)
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_countdown_started.connect(_on_race_countdown_started)
	RaceManager.difficulty_changed.connect(_on_difficulty_changed)
	RaceManager.category_override_changed.connect(_on_category_override_changed)
	RaceManager.vote_cancelled.connect(_on_vote_cancelled)
	EventBus.subscribe(EventBus.CountdownStartedEvent, _on_event_countdown_started)
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_node("ChatSystem"):
		_chat_system = main.get_node("ChatSystem")
	if RaceManager.is_vote_active():
		_on_vote_started(RaceManager.get_vote_candidates())


func _exit_tree() -> void:
	if _dark_mode_lambda.is_valid():
		ThemeManager.dark_mode_changed.disconnect(_dark_mode_lambda)
	if _reading_font_lambda.is_valid():
		ThemeManager.reading_font_changed.disconnect(_reading_font_lambda)
	RaceManager.vote_started.disconnect(_on_vote_started)
	RaceManager.vote_ended.disconnect(_on_vote_ended)
	RaceManager.race_started.disconnect(_on_race_started)
	RaceManager.race_countdown_started.disconnect(_on_race_countdown_started)
	RaceManager.difficulty_changed.disconnect(_on_difficulty_changed)
	RaceManager.category_override_changed.disconnect(_on_category_override_changed)
	RaceManager.vote_cancelled.disconnect(_on_vote_cancelled)
	EventBus.unsubscribe(EventBus.CountdownStartedEvent, _on_event_countdown_started)


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ── Main voting panel ─────────────────────────────────────────────────────
	_panel = PanelContainer.new()
	_panel_style = StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_panel.anchor_left   = 0.5
	_panel.anchor_top    = 0.5
	_panel.anchor_right  = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left   = -230
	_panel.offset_top    = -220
	_panel.offset_right  =  230
	_panel.offset_bottom =  220
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   20)
	mc.add_theme_constant_override("margin_right",  20)
	mc.add_theme_constant_override("margin_top",    16)
	mc.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(mc)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mc.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	_title_label = Label.new()
	_title_label.text = "Race Target Vote"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_on_close_pressed)
	title_row.add_child(close_btn)

	# Timer
	_timer_label = Label.new()
	_timer_label.text = "Time remaining: 30"
	vbox.add_child(_timer_label)

	vbox.add_child(_make_divider())

	# Candidates
	_candidates_container = VBoxContainer.new()
	_candidates_container.add_theme_constant_override("separation", 4)
	vbox.add_child(_candidates_container)

	# Status
	_status_label = Label.new()
	_status_label.text = "Vote for the race target!"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	vbox.add_child(_make_divider())

	# Reroll (host only)
	_reroll_btn = Button.new()
	_reroll_btn.text = "↺  Reroll options"
	_reroll_btn.visible = NetworkManager.is_server()
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	vbox.add_child(_reroll_btn)

	# Seeded shuffle (host only)
	if NetworkManager.is_server():
		var shuffle_row := HBoxContainer.new()
		shuffle_row.add_theme_constant_override("separation", 6)
		shuffle_row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(shuffle_row)

		var shuffle_lbl := Label.new()
		shuffle_lbl.text = "🎲 Seeded Shuffle:"
		shuffle_row.add_child(shuffle_lbl)

		var shuffle_toggle := CheckButton.new()
		shuffle_toggle.button_pressed = false
		shuffle_toggle.focus_mode = Control.FOCUS_NONE
		shuffle_toggle.toggled.connect(_on_seeded_shuffle_toggled)
		shuffle_row.add_child(shuffle_toggle)

		var shuffle_status := Label.new()
		shuffle_status.text = "Off"
		shuffle_row.add_child(shuffle_status)

	# ── Loading overlay (built last, floats above everything) ─────────────────
	_build_loading_overlay()


func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _build_loading_overlay() -> void:
	_loading_overlay = Control.new()
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.visible = false
	add_child(_loading_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.45)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(centre)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	centre.add_child(inner)

	_spinner_canvas = Control.new()
	_spinner_canvas.custom_minimum_size = Vector2(48, 48)
	_spinner_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spinner_canvas.draw.connect(_draw_spinner)
	inner.add_child(_spinner_canvas)

	_loading_label = Label.new()
	_loading_label.text = "Fetching articles…"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(_loading_label)

	_loading_sublabel = Label.new()
	_loading_sublabel.text = ""
	_loading_sublabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(_loading_sublabel)


func _draw_spinner() -> void:
	if not _spinner_canvas: return
	var dark: bool = ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	var cx: float = _spinner_canvas.size.x * 0.5
	var cy: float = _spinner_canvas.size.y * 0.5
	var r:  float = min(cx, cy) - 3.0
	var segs := 8
	for i in segs:
		var a: float = _spinner_angle + float(i) / segs * TAU
		var alpha: float = float(i) / segs
		var p0 := Vector2(cx + cos(a) * r * 0.55, cy + sin(a) * r * 0.55)
		var p1 := Vector2(cx + cos(a) * r,        cy + sin(a) * r)
		_spinner_canvas.draw_line(p0, p1, Color(accent, alpha * 0.9), 2.5, true)


# ── Theme ─────────────────────────────────────────────────────────────────────

func _apply_theme(_dark: bool) -> void:
	var dark: bool = ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)

	if _panel_style:
		_panel_style.bg_color     = ThemeManager.bg_color
		_panel_style.border_color = ThemeManager.border_color
		_panel_style.set_border_width_all(1)
		_panel_style.set_corner_radius_all(12)
		_panel_style.shadow_color  = Color(0, 0, 0, 0.35 if dark else 0.12)
		_panel_style.shadow_size   = 18
		_panel_style.shadow_offset = Vector2(0, 6)

	_style_label(_title_label, ThemeManager.text_color, 22)
	_style_label(_timer_label, ThemeManager.subtext_color, 12)
	_style_label(_status_label, ThemeManager.subtext_color, 13)

	if _panel:
		for cr in _panel.find_children("*", "ColorRect", true, false):
			if cr is ColorRect and cr.custom_minimum_size.y == 1:
				cr.color = ThemeManager.border_color

	for btn in _candidate_buttons:
		_style_vote_button(btn)

	if _reroll_btn:
		_style_vote_button(_reroll_btn)

	_style_loading_overlay()

	if _host_panel:
		_style_host_panel(_host_panel)


func _style_label(lbl: Label, color: Color, size: int) -> void:
	if not lbl: return
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	if _serif_font: lbl.add_theme_font_override("font", _serif_font)


func _style_vote_button(btn: Button) -> void:
	if not btn: return
	var dark: bool = ThemeManager.is_dark_mode
	if _serif_font: btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 15)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		btn.add_theme_color_override(state, ThemeManager.text_color)
	btn.add_theme_color_override("font_disabled_color", ThemeManager.subtext_color)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0)
	sn.content_margin_left = 12; sn.content_margin_right  = 12
	sn.content_margin_top  =  8; sn.content_margin_bottom =  8
	btn.add_theme_stylebox_override("normal", sn)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(1,1,1,0.06) if dark else Color(ThemeManager.border_color, 0.5)
	sh.set_corner_radius_all(5)
	sh.content_margin_left = 12; sh.content_margin_right  = 12
	sh.content_margin_top  =  8; sh.content_margin_bottom =  8
	btn.add_theme_stylebox_override("hover", sh)
	var sp := sh.duplicate() as StyleBoxFlat
	sp.bg_color = Color(1,1,1,0.12) if dark else Color(ThemeManager.border_color, 0.85)
	btn.add_theme_stylebox_override("pressed", sp)
	var sf := sh.duplicate() as StyleBoxFlat
	sf.border_color = ThemeManager.text_color
	sf.border_width_left = 2
	btn.add_theme_stylebox_override("focus", sf)
	var sd := sn.duplicate() as StyleBoxFlat
	sd.bg_color = Color(1,1,1,0.02) if dark else Color(0,0,0,0.02)
	btn.add_theme_stylebox_override("disabled", sd)


func _style_line_edit(edit: LineEdit) -> void:
	if not edit: return
	var dark: bool = ThemeManager.is_dark_mode
	if _serif_font: edit.add_theme_font_override("font", _serif_font)
	edit.add_theme_font_size_override("font_size", 13)
	edit.add_theme_color_override("font_color", ThemeManager.text_color)
	edit.add_theme_color_override("font_placeholder_color", ThemeManager.subtext_color)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0,0,0,0.03) if dark else Color(ThemeManager.border_color, 0.3)
	sn.border_color = ThemeManager.border_color
	sn.set_border_width_all(1); sn.set_corner_radius_all(5)
	sn.content_margin_left = 10; sn.content_margin_right  = 10
	sn.content_margin_top  =  6; sn.content_margin_bottom =  6
	edit.add_theme_stylebox_override("normal", sn)
	var sf := sn.duplicate() as StyleBoxFlat
	sf.border_color = ThemeManager.text_color; sf.set_border_width_all(2)
	edit.add_theme_stylebox_override("focus", sf)


func _style_option_button(btn: OptionButton) -> void:
	ThemeManager.style_option_button(btn)
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
		btn.get_popup().add_theme_font_override("font", _serif_font)


func _style_host_panel(panel: Control) -> void:
	if not panel: return
	for child in panel.get_children():
		if child is Button:        _style_vote_button(child)
		elif child is LineEdit:    _style_line_edit(child)
		elif child is OptionButton: _style_option_button(child)
		elif child is Label:
			child.label_settings = null
			child.add_theme_color_override("font_color", ThemeManager.subtext_color)
			if _serif_font: child.add_theme_font_override("font", _serif_font)
		elif child is Control:     _style_host_panel(child)


func _style_loading_overlay() -> void:
	var dark: bool = ThemeManager.is_dark_mode
	if _loading_label:
		if _serif_font: _loading_label.add_theme_font_override("font", _serif_font)
		_loading_label.add_theme_font_size_override("font_size", 16)
		_loading_label.add_theme_color_override("font_color", ThemeManager.text_color)
	if _loading_sublabel:
		if _serif_font: _loading_sublabel.add_theme_font_override("font", _serif_font)
		_loading_sublabel.add_theme_font_size_override("font_size", 13)
		_loading_sublabel.add_theme_color_override("font_color", ThemeManager.subtext_color)


# ── Candidate cards ───────────────────────────────────────────────────────────

func _build_candidate_btn(text: String, index: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(_on_candidate_pressed.bind(index))
	_style_vote_button(btn)
	# Slide in from the left
	btn.modulate.a  = 0.0
	btn.position.x -= 12.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(btn, "modulate:a", 1.0, 0.25).set_delay(index * 0.05)
	tw.tween_property(btn, "position:x", btn.position.x + 12.0, 0.25) \
		.set_delay(index * 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return btn


# ── Loading screen ────────────────────────────────────────────────────────────

func show_loading() -> void:
	var loading_screen := get_node_or_null("/root/LoadingScreen")
	if loading_screen:
		_using_new_loading_screen = true
		loading_screen.show_loading("Fetching articles…", "Finding race candidates")
		return
	_using_new_loading_screen = false
	visible = true
	_loading_overlay.visible = true
	_loading_overlay.modulate.a = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_style_loading_overlay()
	create_tween().tween_property(_loading_overlay, "modulate:a", 1.0, 0.3)


func hide_loading() -> void:
	if _using_new_loading_screen:
		var loading_screen := get_node_or_null("/root/LoadingScreen")
		if loading_screen and loading_screen.visible:
			_using_new_loading_screen = false
			loading_screen.hidden.connect(func(): pass, CONNECT_ONE_SHOT)
			loading_screen.hide_loading()
			return
		_using_new_loading_screen = false
	if not is_instance_valid(_loading_overlay) or not _loading_overlay.visible:
		return
	var tw := create_tween()
	tw.tween_property(_loading_overlay, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): _loading_overlay.visible = false)


# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Spinner
	if _loading_overlay and _loading_overlay.visible and _spinner_canvas:
		_spinner_angle += delta * 3.2
		_spinner_canvas.queue_redraw()

	if not visible or not RaceManager.is_vote_active():
		if _category_search_pending != "":
			_category_search_timer -= delta
			if _category_search_timer <= 0.0:
				var q := _category_search_pending; _category_search_pending = ""
				ExhibitFetcher.fetch_category_search(q, null)
		return
	_timer_label.text = "Time remaining: %d" % int(ceil(RaceManager.get_vote_time_remaining()))
	if _category_search_pending != "":
		_category_search_timer -= delta
		if _category_search_timer <= 0.0:
			var q := _category_search_pending; _category_search_pending = ""
			ExhibitFetcher.fetch_category_search(q, null)


# ── Entry / exit animations ───────────────────────────────────────────────────

func _bounce_in() -> void:
	_is_animating = false
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_panel.scale     = Vector2(0.92, 0.92)
	_panel.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale",      Vector2(1.0,1.0), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)


func _bounce_out() -> void:
	if _is_animating: return
	_is_animating = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale",      Vector2(0.92,0.92), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(func():
		_is_animating = false
		visible = false
		_panel.scale      = Vector2(1.0,1.0)
		_panel.modulate.a = 1.0
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_vote_started(candidates: Array) -> void:
	_my_vote = -1
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	hide_loading()

	for c in _candidates_container.get_children(): c.queue_free()
	_candidate_buttons.clear()

	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("hide_pause_menu"):
		main.hide_pause_menu()

	if NetworkManager.is_server():
		_status_label.text = "Pick a starting room — vote will begin"
		for i in candidates.size():
			var btn := _build_candidate_btn(candidates[i], i)
			_candidates_container.add_child(btn)
			_candidate_buttons.append(btn)
		_reroll_btn.visible = true
		if _host_panel == null:
			_build_host_panel()
		_style_host_panel(_host_panel)
		_host_panel.visible = true
	else:
		_status_label.text = "Waiting for host — vote for your preferred target"
		for i in candidates.size():
			var btn := _build_candidate_btn(candidates[i], i)
			_candidates_container.add_child(btn)
			_candidate_buttons.append(btn)
		_reroll_btn.visible = false
		if _host_panel: _host_panel.visible = false

	_bounce_in()


func _on_candidate_pressed(index: int) -> void:
	_my_vote = index
	RaceManager.cast_vote(index)
	for i in _candidate_buttons.size():
		_candidate_buttons[i].disabled = (i != index)
	_status_label.text = "Voted for: " + RaceManager.get_vote_candidates()[index]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_vote_ended(winner: String) -> void:
	RaceManager.set_vote_timer_paused(false)
	_timer_label.text  = "Race starting!"
	_status_label.text = "Target: " + winner
	for btn in _candidate_buttons: btn.disabled = true
	_reroll_btn.visible = false
	if _host_panel: _host_panel.visible = false
	# Auto-close vote menu when vote ends (race is about to start)
	# Give a brief moment for players to see the winner, then close
	await get_tree().create_timer(2.0).timeout
	visible = false


func _on_race_started(_target: String, _start: String) -> void:
	hide_loading()
	var pm := get_node_or_null("../PauseMenu")
	if pm and pm.has_method("hide_loading_overlay"): pm.hide_loading_overlay()


func _on_race_countdown_started() -> void:
	visible = false


func _on_vote_cancelled() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_close_pressed() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_reroll_pressed() -> void:
	if not NetworkManager.is_server(): return
	_reroll_btn.disabled = true
	_reroll_btn.text = "↺  Fetching…"
	show_loading()
	var main := get_node_or_null("/root/Main")
	if main and main.has_method("reroll_vote"):
		main.reroll_vote()
	else:
		push_error("VoteHUD: could not find Main node")


func on_reroll_ready() -> void:
	_reroll_btn.disabled = false
	_reroll_btn.text = "↺  Reroll options"


# ── Host panel ────────────────────────────────────────────────────────────────

func _build_host_panel() -> void:
	_host_panel = VBoxContainer.new()
	_host_panel.add_theme_constant_override("separation", 4)
	# Insert above the reroll button
	var content := _reroll_btn.get_parent()
	content.add_child(_host_panel)
	content.move_child(_host_panel, _reroll_btn.get_index())

	# Difficulty row
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.add_theme_constant_override("separation", 3)
	_host_panel.add_child(_difficulty_row)

	var diff_lbl := Label.new()
	diff_lbl.text = "Difficulty:"
	diff_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
	if _serif_font: diff_lbl.add_theme_font_override("font", _serif_font)
	diff_lbl.add_theme_font_size_override("font_size", 12)
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

	_host_panel.add_child(_make_divider())

	# Player management
	_build_player_management_section()

	_host_panel.add_child(_make_divider())

	# Category filter (collapsible)
	_category_toggle_btn = Button.new()
	_category_toggle_btn.text = "▶  Category filter"
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

	var cat_row := HBoxContainer.new()
	_category_section.add_child(cat_row)

	_category_input = LineEdit.new()
	_category_input.placeholder_text = "Search Wikipedia category…"
	_category_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_input.text_changed.connect(_on_category_input_changed)
	cat_row.add_child(_category_input)
	_style_line_edit(_category_input)

	var cat_clear := Button.new()
	cat_clear.text = "✕"
	cat_clear.focus_mode = Control.FOCUS_NONE
	cat_clear.pressed.connect(_on_category_clear_pressed)
	cat_row.add_child(cat_clear)

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

	_host_panel.add_child(_make_divider())

	# Race controls
	var race_row := HBoxContainer.new()
	race_row.add_theme_constant_override("separation", 4)
	_host_panel.add_child(race_row)

	var force_start := Button.new()
	force_start.text = "▶  Force Start"
	force_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	force_start.focus_mode = Control.FOCUS_NONE
	force_start.pressed.connect(_on_force_start_pressed)
	race_row.add_child(force_start)

	var cancel_race := Button.new()
	cancel_race.text = "⏹  Cancel Race"
	cancel_race.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_race.focus_mode = Control.FOCUS_NONE
	cancel_race.pressed.connect(_on_cancel_race_pressed)
	race_row.add_child(cancel_race)

	# Cancel vote
	_cancel_vote_button = Button.new()
	_cancel_vote_button.text = "✕  Cancel vote"
	_cancel_vote_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_cancel_vote_button.focus_mode = Control.FOCUS_NONE
	_cancel_vote_button.flat = true
	_cancel_vote_button.add_theme_color_override("font_color", Color(0.85, 0.25, 0.25))
	_cancel_vote_button.pressed.connect(_on_cancel_vote_pressed)
	_host_panel.add_child(_cancel_vote_button)

	# ── Environmental Events Section ────────────────────────────────────────
	_build_events_section()


func _build_events_section() -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 3)
	_host_panel.add_child(section)

	# Header
	var hdr := Label.new()
	hdr.text = "🎭 Environmental Events"
	hdr.add_theme_font_size_override("font_size", 13)
	if _serif_font: hdr.add_theme_font_override("font", _serif_font)
	section.add_child(hdr)

	var sep := HSeparator.new()
	section.add_child(sep)

	# Enable toggle
	var enable_check := CheckButton.new()
	enable_check.button_pressed = true
	enable_check.toggled.connect(_on_events_enabled_toggled)
	var enable_row := HBoxContainer.new()
	enable_row.add_child(enable_check)
	var enable_lbl := Label.new()
	enable_lbl.text = "Enable Events"
	enable_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enable_row.add_child(enable_lbl)
	section.add_child(enable_row)

	# Frequency slider
	var freq_row := HBoxContainer.new()
	var freq_lbl := Label.new()
	freq_lbl.text = "Frequency:"
	freq_lbl.custom_minimum_size.x = 70
	freq_row.add_child(freq_lbl)

	var freq_slider := HSlider.new()
	freq_slider.min_value = 30
	freq_slider.max_value = 180
	freq_slider.step = 15
	freq_slider.value = 90
	freq_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	freq_slider.value_changed.connect(_on_event_frequency_changed)
	freq_row.add_child(freq_slider)

	var freq_value := Label.new()
	freq_value.text = "90s"
	freq_value.custom_minimum_size.x = 40
	freq_row.add_child(freq_value)
	section.add_child(freq_row)

	# Preset buttons
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 2)
	for preset in ["Standard", "Chaos", "Chill"]:
		var btn := Button.new()
		btn.text = preset
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_event_preset_pressed.bind(preset))
		preset_row.add_child(btn)
	section.add_child(preset_row)


func _build_player_management_section() -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 2)
	_host_panel.add_child(section)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 4)
	section.add_child(hdr)

	var lbl := Label.new()
	lbl.text = "👥  Players"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
	if _serif_font: lbl.add_theme_font_override("font", _serif_font)
	lbl.add_theme_font_size_override("font_size", 12)
	hdr.add_child(lbl)

	var refresh_btn := Button.new()
	refresh_btn.text = "🔄"
	refresh_btn.focus_mode = Control.FOCUS_NONE
	refresh_btn.pressed.connect(_refresh_player_list.bind(section))
	hdr.add_child(refresh_btn)

	var player_list := VBoxContainer.new()
	player_list.name = "PlayerList"
	player_list.add_theme_constant_override("separation", 2)
	section.add_child(player_list)
	_refresh_player_list(section)


func _refresh_player_list(section: VBoxContainer) -> void:
	var list := section.get_node_or_null("PlayerList") as VBoxContainer
	if not list: return
	for c in list.get_children(): c.queue_free()
	if not NetworkManager.is_multiplayer_active(): return
	for peer_id in NetworkManager.get_player_list():
		var pname: String = NetworkManager.get_player_name(peer_id)
		if peer_id == NetworkManager.get_unique_id(): pname += " (You)"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var name_lbl := Label.new()
		name_lbl.text = pname
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_color_override("font_color", ThemeManager.text_color)
		if _serif_font: name_lbl.add_theme_font_override("font", _serif_font)
		row.add_child(name_lbl)
		if peer_id != 1 and NetworkManager.is_server():
			var kick_btn := Button.new()
			kick_btn.text = "👢"
			kick_btn.focus_mode = Control.FOCUS_NONE
			kick_btn.custom_minimum_size.x = 36
			kick_btn.pressed.connect(_on_kick_player_pressed.bind(peer_id, pname))
			row.add_child(kick_btn)
		list.add_child(row)


# ── Host controls callbacks ───────────────────────────────────────────────────

func _on_force_start_pressed() -> void:
	if not NetworkManager.is_server(): return
	RaceManager.force_start_race()
	if _chat_system: _chat_system._show_system_message("⏱️ Race started by host!")

func _on_cancel_race_pressed() -> void:
	if not NetworkManager.is_server(): return
	RaceManager.cancel_race()
	if _chat_system: _chat_system._show_system_message("⏹ Race cancelled by host!")

func _on_cancel_vote_pressed() -> void:
	if not NetworkManager.is_server(): return
	_cancel_vote_button.disabled = true
	RaceManager.cancel_vote()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_difficulty_btn_pressed(difficulty: String) -> void:
	RaceManager.set_difficulty(difficulty)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_difficulty_changed(difficulty: String) -> void:
	_refresh_difficulty_buttons(difficulty)

func _refresh_difficulty_buttons(difficulty: String) -> void:
	for key in _difficulty_buttons:
		_difficulty_buttons[key].button_pressed = (key == difficulty)

func _on_category_toggle() -> void:
	if not _category_section: return
	_category_section.visible = not _category_section.visible
	_category_toggle_btn.text = ("▼  Category filter" if _category_section.visible else "▶  Category filter")

# ── Event Configuration Handlers ──────────────────────────────────────────────

func _on_events_enabled_toggled(enabled: bool) -> void:
	if Engine.has_singleton("EventManager"):
		EventManager.events_enabled = enabled

func _on_event_frequency_changed(value: float) -> void:
	if Engine.has_singleton("EventManager"):
		EventManager.event_frequency = value
		# Update the displayed value
		for child in _host_panel.get_children():
			if child is VBoxContainer:
				for row in child.get_children():
					if row is HBoxContainer and row.get_child(0) is Label and row.get_child(0).text == "Frequency:":
						var value_lbl = row.get_child(3) as Label
						if value_lbl:
							value_lbl.text = "%ds" % int(value)
						break

func _on_event_preset_pressed(preset: String) -> void:
	if not Engine.has_singleton("EventManager"):
		return
	
	match preset:
		"Standard":
			EventManager.event_frequency = 90
			EventManager.duration_modifier = 1.0
			EventManager.max_concurrent = 1
		"Chaos":
			EventManager.event_frequency = 45
			EventManager.duration_modifier = 1.5
			EventManager.max_concurrent = 2
		"Chill":
			EventManager.event_frequency = 180
			EventManager.duration_modifier = 0.75
			EventManager.max_concurrent = 1
	
	Log.debug("VoteHUD", "Event preset applied: %s" % preset)

func _on_category_input_changed(text: String) -> void:
	if text.strip_edges() == "":
		_category_search_pending = ""
		for c in _category_results.get_children(): c.queue_free()
		return
	_category_search_pending = text.strip_edges()
	_category_search_timer = 0.5

func _on_category_search_results(categories: Array, _ctx: Variant) -> void:
	if not is_instance_valid(_category_results): return
	for c in _category_results.get_children(): c.queue_free()
	for cat_name in categories:
		var btn := Button.new()
		btn.text = cat_name.replace("Category:", "")
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_category_selected.bind(cat_name))
		_category_results.add_child(btn)

func _on_category_selected(cat_name: String) -> void:
	RaceManager.set_category_override(cat_name)
	_category_input.text = ""
	for c in _category_results.get_children(): c.queue_free()
	RaceManager.set_vote_timer_paused(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_category_clear_pressed() -> void:
	RaceManager.set_category_override("")
	_category_input.text = ""
	for c in _category_results.get_children(): c.queue_free()
	RaceManager.set_vote_timer_paused(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_category_override_changed(category_name: String) -> void:
	if not is_instance_valid(_category_active_label): return
	_category_active_label.text = \
		("Active: %s" % category_name.replace("Category:", "")) if category_name != "" else ""
	if _category_toggle_btn and category_name != "":
		_category_toggle_btn.text = "▼  Category filter"
		if _category_section: _category_section.visible = true

func _on_seeded_shuffle_toggled(toggled_on: bool) -> void:
	if not NetworkManager.is_server(): return
	RaceManager.set_seeded_shuffle_enabled(toggled_on)
	# Find the status label sibling in the shuffle row
	var row := find_child("🎲 Seeded Shuffle:", true, false)
	if row and row.get_parent() is HBoxContainer:
		for child in row.get_parent().get_children():
			if child is Label and ("Off" in child.text or "On" in child.text):
				child.text = "On" if toggled_on else "Off"
				break

func _on_kick_player_pressed(peer_id: int, player_name: String) -> void:
	if not NetworkManager.is_server(): return
	_kick_player.rpc_id(1, peer_id)
	if _chat_system: _chat_system._show_system_message("👢 Kicked %s" % player_name)

@rpc("any_peer", "call_local", "reliable")
func _kick_player(peer_id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	if NetworkManager.is_server(): NetworkManager.kick_peer(peer_id)

# ── EventBus handlers ─────────────────────────────────────────────────────────

func _on_event_countdown_started(_event: EventBus.CountdownStartedEvent) -> void:
	visible = false
