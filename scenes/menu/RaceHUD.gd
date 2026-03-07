extends Control

const FONT_PATH := "res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf"
var _serif_font: FontFile = null

const TIMELINE_MODE := 0

var _race_panel: Control
var _timer_label: Label
var _target_label: Label
var _timeline_scroll: ScrollContainer
var _timeline_list: VBoxContainer
var _win_popup: Control
var _win_label: Label
var _time_label: Label
var _win_timeline: VBoxContainer
var _sub_label: Label

var _race_style: StyleBoxFlat
var _win_style: StyleBoxFlat

var _dismiss_timer: float = 0.0
const AUTO_DISMISS: float = 8.0

var _visited_pages: Array[String] = []
var _revealed_hints: Array[Dictionary] = []  ## {number, article} — persists across timeline rebuilds
var _hint_overlay: VBoxContainer = null      ## bottom-left overlay, separate from timeline


func _ready() -> void:
	_serif_font = load(FONT_PATH) as FontFile

	_race_panel      = _find("RacePanel")
	_timer_label     = _find("TimerLabel")
	_target_label    = _find("TargetLabel")
	_timeline_scroll = _find("TimelineScroll")
	_timeline_list   = _find("TimelineList")
	_win_popup       = _find("WinPopup")
	_win_label       = _find("WinLabel")
	_time_label      = _find("TimeLabel")
	_win_timeline    = _find("WinTimeline")
	_sub_label       = _find("SubLabel")

	if not _race_panel or not _win_popup or not _win_label:
		push_error("RaceHUD: missing nodes.")
		return

	# Insert hint container into the panel between TargetLabel and TimelineDivider
	if _target_label:
		var panel_content := _target_label.get_parent()
		var divider := _find("TimelineDivider")
		_hint_overlay = VBoxContainer.new()
		_hint_overlay.name = "HintOverlay"
		_hint_overlay.add_theme_constant_override("separation", 2)
		_hint_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel_content.add_child(_hint_overlay)
		# Place it after TargetLabel, before TimelineDivider
		var insert_idx: int
		if divider:
			insert_idx = divider.get_index()
		else:
			insert_idx = _target_label.get_index() + 1
		panel_content.move_child(_hint_overlay, insert_idx)

	var orig_race := _race_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var orig_win  := _win_popup.get_theme_stylebox("panel") as StyleBoxFlat
	if orig_race:
		_race_style = orig_race.duplicate()
		_race_panel.add_theme_stylebox_override("panel", _race_style)
	if orig_win:
		_win_style = orig_win.duplicate()
		_win_popup.add_theme_stylebox_override("panel", _win_style)

	visible = false
	_race_panel.visible = false
	_win_popup.visible  = false

	if _timeline_scroll:
		_timeline_scroll.custom_minimum_size = Vector2(0, 0)

	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_ended.connect(_on_race_ended)
	RaceManager.race_cancelled.connect(_on_race_cancelled)
	RaceManager.race_timer_updated.connect(_on_race_timer_updated)
	RaceManager.race_hint_revealed.connect(_on_race_hint_revealed)
	SettingsEvents.set_current_room.connect(_on_room_changed)
	ThemeManager.dark_mode_changed.connect(_apply_theme)
	_apply_theme(ThemeManager.is_dark_mode)


func _find(n: String) -> Node:
	return _search(self, n)

func _search(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for child in node.get_children():
		var r := _search(child, target)
		if r:
			return r
	return null


func _apply_theme(_dark: bool) -> void:
	ThemeManager.update_panel_style(_race_style)
	ThemeManager.update_panel_style(_win_style)

	for sep_name: String in ["TimelineDivider", "WinDivider"]:
		var sep := _find(sep_name)
		if sep:
			sep.modulate = Color(1,1,1,0.25) if ThemeManager.is_dark_mode else Color(0.7,0.7,0.7,1)

	for node_name: String in ["TimerLabel", "WinLabel"]:
		var lbl := _find(node_name) as Label
		if lbl:
			lbl.add_theme_color_override("font_color", ThemeManager.text_color)
			if _serif_font: lbl.add_theme_font_override("font", _serif_font)

	for node_name: String in ["TargetLabel", "TimeLabel", "SubLabel", "TimelineLabel", "PathLabel"]:
		var lbl := _find(node_name) as Label
		if lbl:
			lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
			if _serif_font: lbl.add_theme_font_override("font", _serif_font)

	_refresh_timeline_colors()


func _refresh_timeline_colors() -> void:
	for container in [_timeline_list, _win_timeline]:
		if not container:
			continue
		for child in container.get_children():
			if child is Label:
				match child.get_meta("role", "mid"):
					"start", "current", "target":
						child.add_theme_color_override("font_color", ThemeManager.text_color)
					_:
						child.add_theme_color_override("font_color", ThemeManager.subtext_color)


func _make_label(text: String, role: String, size: int = 12) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.set_meta("role", role)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	if _serif_font:
		lbl.add_theme_font_override("font", _serif_font)
	match role:
		"start", "current", "target":
			lbl.add_theme_color_override("font_color", ThemeManager.text_color)
		_:
			lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
	return lbl


func _scroll_to_bottom() -> void:
	if _timeline_scroll:
		await get_tree().process_frame
		_timeline_scroll.scroll_vertical = _timeline_scroll.get_v_scroll_bar().max_value


func _refresh_timeline_mode_a() -> void:
	if not _timeline_list:
		return
	for child in _timeline_list.get_children():
		child.queue_free()

	var target := RaceManager.get_target_article()
	var total  := _visited_pages.size()

	for i in total:
		var page       := _visited_pages[i]
		var is_first:  bool = i == 0
		var is_last:   bool = i == total - 1
		var is_target: bool = page == target
		var prefix: String
		var role: String
		if is_target:
			prefix = "★ "; role = "target"
		elif is_first:
			prefix = "▶ "; role = "start"
		elif is_last:
			prefix = "◉ "; role = "current"
		else:
			prefix = "· "; role = "mid"
		_timeline_list.add_child(_make_label(prefix + page, role))

	var row_h    := 18
	var max_rows := 5
	if _timeline_scroll:
		_timeline_scroll.custom_minimum_size.y = min(total * row_h, row_h * max_rows)
	_scroll_to_bottom()


func _refresh_timeline_mode_b() -> void:
	if not _timeline_list:
		return
	for child in _timeline_list.get_children():
		child.queue_free()

	var target := RaceManager.get_target_article()
	var total  := _visited_pages.size()
	if total == 0:
		return

	var show_indices: Array = [0]
	var window_start := int(max(1, total - 2))
	if window_start > 1:
		show_indices.append(-1)
	for i in range(window_start, total):
		show_indices.append(i)

	for idx in show_indices:
		if idx == -1:
			_timeline_list.add_child(_make_label("  ···", "mid", 10))
			continue
		var page       := _visited_pages[idx]
		var is_first:  bool = idx == 0
		var is_last:   bool = idx == total - 1
		var is_target: bool = page == target
		var prefix: String; var role: String
		if is_target:   prefix = "★ "; role = "target"
		elif is_first:  prefix = "▶ "; role = "start"
		elif is_last:   prefix = "◉ "; role = "current"
		else:           prefix = "· "; role = "mid"
		_timeline_list.add_child(_make_label(prefix + page, role))


func _refresh_timeline_display() -> void:
	if TIMELINE_MODE == 0: _refresh_timeline_mode_a()
	else:                  _refresh_timeline_mode_b()


func _populate_win_timeline() -> void:
	if not _win_timeline:
		return
	for child in _win_timeline.get_children():
		child.queue_free()
	var target := RaceManager.get_target_article()
	for i in _visited_pages.size():
		var page     := _visited_pages[i]
		var is_tgt:  bool = page == target
		var is_first:bool = i == 0
		var arrow: String = " ↓" if i < _visited_pages.size() - 1 else ""
		var prefix: String = "★ " if is_tgt else ("▶ " if is_first else "")
		var role: String   = "target" if is_tgt else ("start" if is_first else "mid")
		_win_timeline.add_child(_make_label(prefix + page + arrow, role))
	# Cap height so it doesn't overflow the screen
	var row_h: float = 22.0
	var max_rows: int = 16
	_win_timeline.custom_minimum_size.y = 0
	if _visited_pages.size() > max_rows:
		_win_timeline.custom_minimum_size.y = row_h * max_rows


func _slide_in(panel: Control, from_top: bool) -> void:
	if not panel: return
	panel.visible = true
	panel.modulate.a = 0.0
	panel.position.y = -50.0 if from_top else 50.0  # always start from clean offset
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)


func _slide_out(panel: Control, to_top: bool, then_hide: bool = true) -> void:
	if not panel or not panel.visible: return
	var offset := -35.0 if to_top else 35.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "position:y", offset, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(panel, "modulate:a", 0.0, 0.2)
	if then_hide:
		tw.chain().tween_callback(func():
			panel.visible = false
			panel.modulate.a = 1.0
			panel.position.y = 0.0  # always reset cleanly
		)


func _process(delta: float) -> void:
	if not _win_popup or not _win_popup.visible: return
	_dismiss_timer -= delta
	if _dismiss_timer <= 0.0:
		_dismiss()
	elif _sub_label:
		_sub_label.text = "Returning in %ds..." % int(ceil(_dismiss_timer))


func _unhandled_input(event: InputEvent) -> void:
	if _win_popup and _win_popup.visible and event.is_action_pressed("ui_accept"):
		_dismiss()


func _on_room_changed(room: String) -> void:
	if not RaceManager.is_race_active() or room == "Lobby": return
	_visited_pages.append(room)
	_refresh_timeline_display()


func _on_race_started(target_article: String, _start_article: String) -> void:
	_visited_pages.clear()
	_revealed_hints.clear()
	if _hint_overlay:
		for child in _hint_overlay.get_children():
			child.queue_free()
	if _timer_label:  _timer_label.text  = "00:00"
	if _target_label: _target_label.text = "Find: " + target_article
	if _win_popup and _win_popup.visible:
		_slide_out(_win_popup, false)
	if _timeline_list:
		for child in _timeline_list.get_children(): child.queue_free()
	visible = true
	_slide_in(_race_panel, true)


func _on_race_timer_updated(elapsed_seconds: float) -> void:
	if _timer_label:
		var secs := int(elapsed_seconds)
		_timer_label.text = "%02d:%02d" % [secs / 60, secs % 60]


func _on_race_ended(_winner_peer_id: int, winner_name: String) -> void:
	if _win_label: _win_label.text = winner_name + " wins!"
	if _time_label: _time_label.text = "Time: " + RaceManager.get_elapsed_time_string()
	_populate_win_timeline()
	_dismiss_timer = AUTO_DISMISS
	_slide_in(_win_popup, false)


func _on_race_cancelled() -> void:
	_dismiss()


func _dismiss() -> void:
	_slide_out(_win_popup, false)
	_slide_out(_race_panel, true, false)
	await get_tree().create_timer(0.25).timeout
	visible = false
	_visited_pages.clear()
	_revealed_hints.clear()
	if _hint_overlay:
		for child in _hint_overlay.get_children():
			child.queue_free()
	if _race_panel: _race_panel.visible = false


func _on_race_hint_revealed(hint_article: String, hint_number: int) -> void:
	_revealed_hints.append({"number": hint_number, "article": hint_article})
	if not _hint_overlay:
		return
	var lbl := _make_label("💡 Hint %d: \"%s\" links here" % [hint_number, hint_article], "hint")
	lbl.add_theme_color_override("font_color", Color(0.35, 0.65, 0.6) if not ThemeManager.is_dark_mode else Color(0.45, 0.75, 0.7))
	_hint_overlay.add_child(lbl)
