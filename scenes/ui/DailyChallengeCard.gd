extends Control
class_name DailyChallengeCard
## Compact lobby panel card for the Daily Challenge.

const ACCENT_COLOR  := Color(0.35, 0.75, 1.00)
const CARD_WIDTH    := 220.0

var _manager: Node     = null
var _hud: Node         = null
var _leaderboard: Node = null
var _player: Node      = null
var _menu_layer: Node  = null
var _start_game_fn: Callable
var _font: Font        = null
var _serif_font: Font  = null
var _inited: bool      = false

var _card: PanelContainer      = null
var _card_style: StyleBoxFlat  = null
var _header_lbl: Label         = null
var _date_lbl: Label           = null
var _target_lbl: Label         = null
var _time_val_lbl: Label       = null
var _rank_val_lbl: Label       = null
var _play_btn: Button          = null
var _help_popup: Control       = null

var _is_card_visible: bool = false
var _last_room: String     = ""
var _is_multiplayer: bool  = false
var _is_on_main_menu: bool = true  # Track if we're on main menu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_serif_font = load("res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf")
	_build_card()
	
	if ThemeManager:
		ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
		ThemeManager.reading_font_changed.connect(func(f): _font = f; _apply_theme())
		_font = ThemeManager.get_reading_font()

	_apply_theme()
	_card.visible = false


func init_for_main_menu(manager: Node, hud: Node, leaderboard: Node = null, menu_layer: Node = null) -> void:
	_manager      = manager
	_hud          = hud
	_leaderboard  = leaderboard
	_menu_layer   = menu_layer
	_is_multiplayer = false
	_is_on_main_menu = true
	_player = null  # No player on main menu
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
	# Fetch leaderboard scores for main menu display
	if _leaderboard and _leaderboard.has_method("fetch_scores") and _manager:
		_leaderboard.fetch_scores(_manager.get_today_key())
	# Show the card immediately since we're on main menu with no player
	if not _is_card_visible:
		_show_card()


func set_multiplayer_mode(enabled: bool) -> void:
	_is_multiplayer = enabled
	if enabled and _is_card_visible:
		_hide_card()
	elif not enabled:
		_last_room = "FORCE_RECHECK"


func set_main_menu_mode() -> void:
	_is_on_main_menu = true
	_player = null
	_last_room = "FORCE_RECHECK"
	# Fetch fresh leaderboard data
	if _leaderboard and _leaderboard.has_method("fetch_scores") and _manager:
		_leaderboard.fetch_scores(_manager.get_today_key())
	# Show the card
	if not _is_card_visible:
		_show_card()


func init(manager: Node, hud: Node, player: Node, leaderboard: Node = null, start_game_fn: Callable = Callable(), menu_layer: Node = null) -> void:
	_manager       = manager
	_hud           = hud
	_leaderboard   = leaderboard
	_player        = player
	_menu_layer    = menu_layer
	_start_game_fn = start_game_fn
	_is_multiplayer = false
	_is_on_main_menu = false  # No longer on main menu

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
	add_child(_card)

	_card_style = StyleBoxFlat.new()
	_card_style.bg_color = Color(0.08, 0.08, 0.1, 0.8)
	_card_style.border_width_left = 1
	_card_style.border_width_top = 1
	_card_style.border_width_right = 1
	_card_style.border_width_bottom = 1
	_card_style.border_color = Color(1, 1, 1, 0.1)
	_card_style.corner_radius_top_left = 14
	_card_style.corner_radius_top_right = 14
	_card_style.corner_radius_bottom_right = 14
	_card_style.corner_radius_bottom_left = 14
	_card.add_theme_stylebox_override("panel", _card_style)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 0)
	_card.add_child(outer_vbox)

	# Rainbow Bar
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(0.12, 0.32, 0.8))
	gradient.add_point(0.2, Color(0.62, 0.23, 0.07))
	gradient.add_point(0.4, Color(0.78, 0.48, 0.08))
	gradient.add_point(0.6, Color(0.12, 0.48, 0.23))
	gradient.add_point(0.8, Color(0.64, 0.08, 0.38))
	gradient.add_point(1.0, Color(0.42, 0.12, 0.63))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = gradient
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(1, 0)
	
	var rainbow_tex := TextureRect.new()
	rainbow_tex.texture = grad_tex
	rainbow_tex.custom_minimum_size.y = 4
	rainbow_tex.stretch_mode = TextureRect.STRETCH_SCALE
	outer_vbox.add_child(rainbow_tex)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   12)
	margin.add_theme_constant_override("margin_right",  12)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	outer_vbox.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_header_lbl = Label.new()
	_header_lbl.text = "DAILY CHALLENGE"
	_header_lbl.add_theme_font_size_override("font_size", 9)
	_header_lbl.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	vbox.add_child(_header_lbl)

	_date_lbl = Label.new()
	_date_lbl.text = ""
	_date_lbl.add_theme_font_size_override("font_size", 9)
	_date_lbl.modulate.a = 0.4
	vbox.add_child(_date_lbl)

	_target_lbl = Label.new()
	_target_lbl.text = "Fetching..."
	_target_lbl.add_theme_font_override("font", _serif_font)
	_target_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_target_lbl)

	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 8)
	stats_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(stats_grid)

	_time_val_lbl = _build_stat_box(stats_grid, "Best Time", "---")
	_rank_val_lbl = _build_stat_box(stats_grid, "Rank", "---")

	_play_btn = Button.new()
	_play_btn.text = "Enter →"
	_play_btn.custom_minimum_size.y = 32
	_play_btn.pressed.connect(_on_play_pressed)
	vbox.add_child(_play_btn)


func _build_stat_box(parent: Control, label: String, val: String) -> Label:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.03)
	style.set_corner_radius_all(6)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.05)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	
	var val_lbl := Label.new()
	val_lbl.text = val
	val_lbl.add_theme_font_size_override("font_size", 14)
	val_lbl.add_theme_font_override("font", _serif_font)
	vbox.add_child(val_lbl)
	
	var lbl := Label.new()
	lbl.text = label.to_upper()
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.modulate.a = 0.4
	vbox.add_child(lbl)
	
	return val_lbl


func _refresh_content() -> void:
	if not _manager or not _inited: return
	
	var target: String = _manager.get_target_article() if _manager.has_method("get_target_article") else "???"
	_target_lbl.text = target
	
	# Date formatting
	var d = Time.get_datetime_dict_from_system()
	var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var date_str = "%s %d, %d" % [months[d.month-1], d.day, d.year]
	
	var streak = _manager.get_streak() if _manager.has_method("get_streak") else 0
	if streak > 0:
		_date_lbl.text = "%s • 🔥 %d day streak" % [date_str, streak]
	else:
		_date_lbl.text = date_str

	if _leaderboard:
		var scores = _leaderboard.get_scores() if _leaderboard.has_method("get_scores") else []
		if not scores.is_empty():
			# Find my rank
			var my_name = NetworkManager.local_player_name
			var rank = 0
			for i in range(scores.size()):
				if scores[i].name == my_name:
					rank = i + 1
					_time_val_lbl.text = scores[i].time_str
					break
			_rank_val_lbl.text = "#" + str(rank) if rank > 0 else "---"


func _show_card() -> void:
	if _is_card_visible: return
	_is_card_visible = true
	_refresh_content()
	
	_card.visible = true
	
	# Apply positioning based on whether it's in the main menu placeholder
	var is_in_placeholder = get_parent() and get_parent().name == "DCPlaceholder"
	
	if is_in_placeholder:
		# Keep natural card size, centered in placeholder
		_card.set_anchors_preset(Control.PRESET_CENTER)
		_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_card.offset_left   = 16.0
		_card.offset_bottom = -16.0
		_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	
	_card.modulate.a = 0.0
	if not is_in_placeholder:
		_card.position.x = -20
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "modulate:a", 1.0, 0.4)
	if not is_in_placeholder:
		tw.tween_property(_card, "position:x", 16.0, 0.4)


func _hide_card() -> void:
	if not _is_card_visible: return
	_is_card_visible = false
	
	var is_in_placeholder = get_parent() and get_parent().name == "DCPlaceholder"
	
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_card, "modulate:a", 0.0, 0.2)
	if not is_in_placeholder:
		tw.tween_property(_card, "position:x", -20, 0.2)
	tw.chain().tween_callback(func(): _card.visible = false)


func _apply_theme() -> void:
	if not _card: return
	var dark := ThemeManager.is_dark_mode
	
	_card_style.bg_color = ThemeManager.bg_color
	_card_style.bg_color.a = 0.8 if dark else 0.95
	_card_style.border_color = ThemeManager.border_color
	
	if _header_lbl:
		_header_lbl.add_theme_color_override("font_color", (ACCENT_COLOR if dark else Color(0.2, 0.4, 0.8)))
	
	if _date_lbl:
		_date_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
	
	if _target_lbl:
		_target_lbl.add_theme_color_override("font_color", ThemeManager.text_color)
		_target_lbl.add_theme_font_override("font", _serif_font)

	# Update stat boxes
	for panel in _card.find_children("", "PanelContainer", true, false):
		if panel == _card: continue
		var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.bg_color = ThemeManager.bg_color
			style.bg_color.a = 0.2
			style.border_color = ThemeManager.border_color
		
		for label in panel.find_children("", "Label", true, false):
			if label.name.ends_with("_val"):
				label.add_theme_color_override("font_color", ThemeManager.text_color)
			else:
				label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	
	if _play_btn:
		_play_btn.add_theme_color_override("font_color", ThemeManager.text_color)
		_play_btn.add_theme_color_override("font_hover_color", ThemeManager.text_color)
		_play_btn.add_theme_color_override("font_pressed_color", ThemeManager.text_color)
		
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(1, 1, 1, 0.1) if dark else Color(0, 0, 0, 0.05)
		btn_style.set_corner_radius_all(8)
		_play_btn.add_theme_stylebox_override("normal", btn_style)
		
		var hover_style = btn_style.duplicate() as StyleBoxFlat
		hover_style.bg_color.a = 0.2 if dark else 0.1
		_play_btn.add_theme_stylebox_override("hover", hover_style)


func _on_play_pressed() -> void:
	if _start_game_fn.is_valid():
		_start_game_fn.call()
	elif _hud:
		_hud.visible = true


func _on_challenge_ready(_target: String, _start: String) -> void:
	_refresh_content()


func _on_challenge_completed(_time: float, _is_best: bool) -> void:
	_refresh_content()


func _on_scores_updated(_entries: Array = []) -> void:
	_refresh_content()


func _on_menu_layer_visibility_changed(_node: Node) -> void:
	_last_room = "FORCE_RECHECK"
