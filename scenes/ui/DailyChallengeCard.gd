extends Control
class_name DailyChallengeCard
## Compact lobby panel card for the Daily Challenge.

const ACCENT_COLOR  := Color(0.35, 0.75, 1.00)
const CARD_WIDTH    := 230.0

var _manager: Node     = null
var _hud: Node         = null
var _leaderboard: Node = null
var _player: Node      = null
var _menu_layer: Node  = null
var _start_game_fn: Callable
var _font: Font        = null
var _inited: bool      = false

var _card: PanelContainer      = null
var _card_style: StyleBoxFlat  = null
var _header_lbl: Label         = null
var _date_lbl: Label           = null
var _streak_lbl: Label         = null
var _target_caption: Label     = null
var _target_lbl: Label         = null
var _meta_lbl: Label           = null
var _done_lbl: Label           = null
var _play_btn: Button          = null
var _lb_caption: Label         = null
var _lb_list: VBoxContainer    = null
var _sep1: HSeparator          = null
var _sep2: HSeparator          = null
var _info_btn: Button          = null
var _help_popup: Control       = null

var _is_card_visible: bool = false
var _last_room: String     = ""
var _is_multiplayer: bool  = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_build_card()
	
	if ThemeManager:
		ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
		ThemeManager.reading_font_changed.connect(func(f): _font = f; _apply_theme())
		_font = ThemeManager.get_reading_font()

	_apply_theme()
	_card.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _help_popup and _help_popup.visible and not _help_closing and event.is_action_pressed("ui_cancel"):
		_hide_help()
		get_viewport().set_input_as_handled()


func init_for_main_menu(manager: Node, hud: Node, leaderboard: Node = null, menu_layer: Node = null) -> void:
	_manager      = manager
	_hud          = hud
	_leaderboard  = leaderboard
	_menu_layer   = menu_layer
	_is_multiplayer = false
	if not _inited:
		_inited = true
		if _manager.has_signal("challenge_ready"):
			_manager.challenge_ready.connect(_on_challenge_ready)
		if _manager.has_signal("challenge_completed"):
			_manager.challenge_completed.connect(_on_challenge_completed)
		if _leaderboard and _leaderboard.has_signal("scores_updated"):
			_leaderboard.scores_updated.connect(_on_scores_updated)
	if menu_layer and not menu_layer.visibility_changed.is_connected(_on_menu_layer_visibility_changed):
		menu_layer.visibility_changed.connect(_on_menu_layer_visibility_changed.bind(menu_layer))
	_refresh_content()
	_last_room = "FORCE_RECHECK"


func set_multiplayer_mode(enabled: bool) -> void:
	_is_multiplayer = enabled
	if enabled and _is_card_visible:
		_hide_card()
	elif not enabled:
		_last_room = "FORCE_RECHECK"


func init(manager: Node, hud: Node, player: Node, leaderboard: Node = null, start_game_fn: Callable = Callable(), menu_layer: Node = null) -> void:
	_manager       = manager
	_hud           = hud
	_leaderboard   = leaderboard
	_player        = player
	_menu_layer    = menu_layer
	_start_game_fn = start_game_fn
	_is_multiplayer = false

	if menu_layer and not menu_layer.visibility_changed.is_connected(_on_menu_layer_visibility_changed):
		menu_layer.visibility_changed.connect(_on_menu_layer_visibility_changed.bind(menu_layer))

	if not _inited:
		_inited = true
		if _manager.has_signal("challenge_ready"):
			_manager.challenge_ready.connect(_on_challenge_ready)
		if _manager.has_signal("challenge_completed"):
			_manager.challenge_completed.connect(_on_challenge_completed)
		if _leaderboard and _leaderboard.has_signal("scores_updated"):
			_leaderboard.scores_updated.connect(_on_scores_updated)
		_refresh_content()

	_last_room = "FORCE_RECHECK"


func set_player(player: Node) -> void:
	_player    = player
	_last_room = "FORCE_RECHECK"


func _process(_delta: float) -> void:
	if _is_multiplayer:
		if _is_card_visible: _hide_card()
		return

	if _menu_layer and _menu_layer.visible:
		var is_non_main_open: bool = false
		for other: String in ["PauseMenu", "Settings", "MultiplayerMenu", "PopupTerminalMenu"]:
			var n := _menu_layer.get_node_or_null(other)
			if n != null and n.visible:
				is_non_main_open = true
				break
		if is_non_main_open:
			if _is_card_visible: _hide_card()
			return

	if not _player or not is_instance_valid(_player):
		if not _is_card_visible: _show_card()
		return

	var room: String = _player.get("current_room") if "current_room" in _player else ""
	if room == _last_room:
		return
	_last_room = room

	if room == "Lobby" or room == "":
		_show_card()
	else:
		_hide_card()


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "DailyChallengeCard"
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_card.offset_left   = 16.0
	_card.offset_bottom = -16.0
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.mouse_filter  = Control.MOUSE_FILTER_PASS
	add_child(_card)

	_card_style = StyleBoxFlat.new()
	_card.add_theme_stylebox_override("panel", _card_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	vbox.add_child(header_row)

	var icon_lbl := Label.new()
	icon_lbl.text = "📅"
	icon_lbl.add_theme_font_size_override("font_size", 14)
	header_row.add_child(icon_lbl)

	_header_lbl = Label.new()
	_header_lbl.text = "DAILY CHALLENGE"
	_header_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_header_lbl)

	_info_btn = Button.new()
	_info_btn.text = "ⓘ"
	_info_btn.custom_minimum_size = Vector2(28, 28)
	_info_btn.pressed.connect(_show_help)
	header_row.add_child(_info_btn)

	_build_help_popup()

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 8)
	vbox.add_child(meta_row)

	_date_lbl = Label.new()
	_date_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_row.add_child(_date_lbl)

	_streak_lbl = Label.new()
	meta_row.add_child(_streak_lbl)

	_sep1 = HSeparator.new()
	vbox.add_child(_sep1)

	_target_caption = Label.new()
	_target_caption.text = "TODAY'S TARGET"
	vbox.add_child(_target_caption)

	_target_lbl = Label.new()
	_target_lbl.text = "Loading..."
	_target_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_lbl.custom_minimum_size = Vector2(CARD_WIDTH - 32.0, 0)
	vbox.add_child(_target_lbl)

	_meta_lbl = Label.new()
	_meta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_meta_lbl)

	_done_lbl = Label.new()
	_done_lbl.text = "Completed today!"
	_done_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_done_lbl.visible = false
	vbox.add_child(_done_lbl)

	_play_btn = Button.new()
	_play_btn.text = "ENTER THE MUSEUM  →"
	_play_btn.pressed.connect(_on_play_pressed)
	vbox.add_child(_play_btn)

	_sep2 = HSeparator.new()
	vbox.add_child(_sep2)

	_lb_caption = Label.new()
	_lb_caption.text = "TOP SCORES"
	vbox.add_child(_lb_caption)

	_lb_list = VBoxContainer.new()
	_lb_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_lb_list)


var _help_panel: PanelContainer = null
var _help_closing: bool = false
var _help_title_lbl: Label = null
var _help_rules_lbls: Array[Label] = []

func _build_help_popup() -> void:
	_help_popup = Control.new()
	_help_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_popup.visible = false
	add_child(_help_popup)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.60)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_popup.add_child(dim)

	_help_panel = PanelContainer.new()
	_help_panel.set_anchors_preset(Control.PRESET_CENTER)
	_help_panel.size = Vector2(300, 260)
	_help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_help_popup.add_child(_help_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	panel_style.set_corner_radius_all(12)
	_help_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   20)
	margin.add_theme_constant_override("margin_right",  20)
	margin.add_theme_constant_override("margin_top",    16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_help_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_help_title_lbl = Label.new()
	_help_title_lbl.text = "DAILY CHALLENGE"
	_help_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_help_title_lbl)

	vbox.add_child(HSeparator.new())

	var rules := [
		"• Find the target article",
		"• Use only Wikipedia links",
		"• ⌨️ Terminal disabled",
		"• One attempt per day",
		"• Beat your best time!"
	]

	for rule in rules:
		var lbl := Label.new()
		lbl.text = rule
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		_help_rules_lbls.append(lbl)
		vbox.add_child(lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Got it!"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.pressed.connect(_hide_help)
	vbox.add_child(close_btn)


func _animate_help_in() -> void:
	_help_panel.modulate.a = 0.0
	_help_panel.scale = Vector2(0.9, 0.9)
	_help_panel.pivot_offset = _help_panel.size / 2.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_help_panel, "modulate:a", 1.0, 0.3)
	tw.tween_property(_help_panel, "scale", Vector2.ONE, 0.3)


func _animate_help_out(then: Callable) -> void:
	if _help_closing: return
	_help_closing = true
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_help_panel, "modulate:a", 0.0, 0.2)
	tw.tween_property(_help_panel, "scale", Vector2(0.9, 0.9), 0.2)
	tw.chain().tween_callback(func():
		_help_closing = false
		then.call()
	)


func _show_help() -> void:
	_help_popup.visible = true
	_animate_help_in()


func _hide_help() -> void:
	_animate_help_out(func(): _help_popup.visible = false)


func _apply_theme() -> void:
	if not _card or not ThemeManager: return
	
	_font = ThemeManager.get_reading_font()
	
	# Update Card Background
	if _card_style:
		_card_style.bg_color = ThemeManager.bg_color
		_card_style.border_width_left = 4
		_card_style.border_width_top = 1
		_card_style.border_width_right = 1
		_card_style.border_width_bottom = 1
		_card_style.border_color = ACCENT_COLOR
		_card_style.set_corner_radius_all(10)
		_card_style.shadow_color = Color(0, 0, 0, 0.3 if ThemeManager.is_dark_mode else 0.1)
		_card_style.shadow_size = 8
		_card_style.shadow_offset = Vector2(0, 4)

	var accent := ACCENT_COLOR
	var text := ThemeManager.text_color
	var subtext := ThemeManager.subtext_color
	
	_style_lbl(_header_lbl,     accent,  12)
	_style_lbl(_date_lbl,       subtext, 11)
	_streak_lbl.text = _manager.get_streak_string() if _manager and _manager.has_method("get_streak_string") else ""
	_style_lbl(_streak_lbl,     subtext, 11)
	_style_lbl(_target_caption, accent.lerp(text, 0.3), 10)
	_style_lbl(_target_lbl,     text,    18)
	_style_lbl(_meta_lbl,       subtext, 12)
	_style_lbl(_done_lbl,       Color(0.4, 0.9, 0.5), 14)
	_style_lbl(_lb_caption,     accent.lerp(text, 0.3), 10)

	_style_btn(_info_btn, false)
	_style_play_btn()
	_restyle_leaderboard_rows()

	# Help popup
	if _help_panel:
		var hstyle = _help_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if hstyle:
			hstyle.bg_color = ThemeManager.bg_color
			hstyle.border_color = accent
			hstyle.border_width_top = 2
	
	_style_lbl(_help_title_lbl, text, 18)
	for lbl in _help_rules_lbls:
		_style_lbl(lbl, subtext, 14)

func _style_lbl(lbl: Label, color: Color, size: int) -> void:
	if not lbl: return
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	if _font: lbl.add_theme_font_override("font", _font)


func _style_play_btn() -> void:
	if not _play_btn: return
	if _font: _play_btn.add_theme_font_override("font", _font)
	_play_btn.add_theme_font_size_override("font_size", 13)
	
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(ACCENT_COLOR, 0.1)
	sn.border_width_bottom = 2
	sn.border_color = ACCENT_COLOR
	sn.content_margin_top = 8
	sn.content_margin_bottom = 8
	_play_btn.add_theme_stylebox_override("normal", sn)

	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(ACCENT_COLOR, 0.2)
	_play_btn.add_theme_stylebox_override("hover", sh)


func _style_btn(btn: Button, _primary: bool) -> void:
	if not btn: return
	btn.add_theme_color_override("font_color", ThemeManager.subtext_color)
	var s := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)


func _show_card() -> void:
	if _is_card_visible: return
	_is_card_visible = true
	_refresh_content()
	if _leaderboard and _manager:
		_leaderboard.fetch_scores(_manager.get_today_key() if _manager.has_method("get_today_key") else "")
	_card.visible = true
	_card.modulate.a = 0.0
	_card.position.x = -20
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "modulate:a", 1.0, 0.4)
	tw.tween_property(_card, "position:x", 0.0, 0.4)


func _hide_card() -> void:
	if not _is_card_visible: return
	_is_card_visible = false
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_card, "modulate:a", 0.0, 0.2)
	tw.tween_property(_card, "position:x", -20, 0.2)
	tw.chain().tween_callback(func(): _card.visible = false)


func _refresh_content() -> void:
	if not _manager: return
	_date_lbl.text = _manager.get_today_key() if _manager.has_method("get_today_key") else ""
	var target: String = _manager.get_target_article() if _manager.has_method("get_target_article") else ""
	_target_lbl.text = target if target != "" else "Loading..."
	var streak: int  = _manager.get_streak() if _manager.has_method("get_streak") else 0
	var best: float  = _manager.get_best_time() if _manager.has_method("get_best_time") else 0.0
	_streak_lbl.text = "🔥 %d" % streak if streak > 0 else ""
	_meta_lbl.text   = "Personal Best: %d:%02d" % [int(best) / 60, int(best) % 60] if best > 0.0 else ""
	var done: bool = _manager.already_completed_today() if _manager.has_method("already_completed_today") else false
	_done_lbl.visible  = done
	_play_btn.visible  = not done
	_play_btn.disabled = target == ""


func _on_challenge_ready(target: String, _start: String) -> void:
	_target_lbl.text   = target
	_play_btn.disabled = false


func _on_challenge_completed(_time_sec: float, _is_best: bool) -> void:
	_refresh_content()


func _on_scores_updated(entries: Array) -> void:
	_rebuild_leaderboard(entries)


func _rebuild_leaderboard(entries: Array) -> void:
	if not _lb_list: return
	for child in _lb_list.get_children(): child.queue_free()
	
	if entries.is_empty():
		var empty = Label.new()
		empty.text = "No scores yet..."
		_style_lbl(empty, ThemeManager.subtext_color, 11)
		_lb_list.add_child(empty)
		return

	for i in min(entries.size(), 3):
		var row := HBoxContainer.new()
		_lb_list.add_child(row)
		var rank := Label.new()
		rank.text = "%d." % (i+1)
		_style_lbl(rank, ThemeManager.subtext_color, 11)
		row.add_child(rank)
		var name := Label.new()
		name.text = str(entries[i].get("name", "?"))
		name.size_flags_horizontal = SIZE_EXPAND_FILL
		_style_lbl(name, ThemeManager.text_color, 11)
		row.add_child(name)
		var score := Label.new()
		var t := float(entries[i].get("time_seconds", 0))
		score.text = "%d:%02d" % [int(t)/60, int(t)%60]
		_style_lbl(score, ACCENT_COLOR, 11)
		row.add_child(score)


func _restyle_leaderboard_rows() -> void:
	_rebuild_leaderboard([]) # Easiest way to force restyle with new font


func _on_menu_layer_visibility_changed(menu_layer: Node) -> void:
	if not menu_layer.visible:
		_last_room = "FORCE_RECHECK"
		return
	var main_menu := menu_layer.get_node_or_null("MainMenu")
	var only_main_menu_open: bool = main_menu != null and main_menu.visible
	for other in ["PauseMenu", "Settings", "MultiplayerMenu", "PopupTerminalMenu"]:
		var n := menu_layer.get_node_or_null(other)
		if n != null and n.visible:
			only_main_menu_open = false
			break
	if only_main_menu_open:
		_last_room = "FORCE_RECHECK"
	else:
		_hide_card()


func animate_out(then: Callable = Callable()) -> void:
	if not _is_card_visible:
		if then.is_valid(): then.call()
		return
	_is_card_visible = false
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_card, "modulate:a", 0.0, 0.16)
	tw.tween_property(_card, "position:x", -20, 0.16)
	if then.is_valid(): tw.chain().tween_callback(then)


func _on_play_pressed() -> void:
	animate_out()
	if _start_game_fn.is_valid(): _start_game_fn.call()
	if _manager and not _manager.already_completed_today():
		if _hud and _hud.has_signal("challenge_started"):
			_hud.challenge_started.emit()
