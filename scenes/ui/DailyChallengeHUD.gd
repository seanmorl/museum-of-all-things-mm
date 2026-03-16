extends Control
class_name DailyChallengeHUD
## Daily Challenge HUD — three modes:
##   MODAL   : pre-race info panel (target article, best time, start button)
##   STRIP   : compact top-centre live timer bar shown while racing
##   RESULTS : completion popup with grade, final time, and global leaderboard

signal challenge_started
signal challenge_closed

const ACCENT := Color(0.35, 0.75, 1.00)   ## gold
const ACCENT_LIGHT := Color(0.10, 0.52, 0.85)  ## darker gold for light mode readability
const GREEN  := Color(0.35, 0.85, 0.45)   ## personal best
const MEDAL  := ["🥇", "🥈", "🥉"]

var _manager:     DailyChallengeManager = null
var _leaderboard: Node                  = null   ## DailyChallengeLeaderboard (optional)
var _font: Font   = null
var _is_open:     bool = false
var _closing:     bool = false
var _closing_results: bool = false
var _strip_active: bool = false
var _should_intercept_esc: bool = false  # Only intercept ESC when modal/results showing

# ── Modal nodes ───────────────────────────────────────────────────────────────
var _modal_root:        Control         = null
var _panel:             PanelContainer  = null
var _panel_style:       StyleBoxFlat    = null
var _title_lbl:         Label           = null
var _date_lbl:          Label           = null
var _streak_lbl:        Label           = null
var _target_header_lbl: Label           = null
var _target_lbl:        Label           = null
var _best_lbl:          Label           = null
var _status_lbl:        Label           = null
var _start_btn:         Button          = null
var _close_btn:         Button          = null
var _info_btn:          Button          = null
var _help_popup:        Control         = null
var _help_panel:        PanelContainer  = null
var _help_closing:      bool            = false
var _help_title_lbl:    Label           = null
var _help_rules_lbls:   Array[Label]    = []

# ── Strip nodes ───────────────────────────────────────────────────────────────
var _strip:             PanelContainer  = null
var _strip_style:       StyleBoxFlat    = null
var _strip_target_lbl:  Label           = null
var _strip_timer_lbl:   Label           = null
var _strip_best_lbl:    Label           = null

# ── Results popup nodes ───────────────────────────────────────────────────────
var _results_root:       Control        = null
var _results_panel:      PanelContainer = null
var _results_style:      StyleBoxFlat   = null
var _res_grade_lbl:      Label          = null   ## big emoji — speed grade
var _res_time_lbl:       Label          = null   ## final time, large
var _res_best_lbl:       Label          = null   ## "New personal best!"
var _res_lb_header:      Label          = null
var _res_lb_loading:     Label          = null
var _res_lb_list:        VBoxContainer  = null
var _res_play_again_btn: Button         = null
var _res_close_btn:      Button         = null

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true
	set_process_unhandled_input(false)  # Start with input disabled
	_font = ThemeManager.get_reading_font()
	_build_modal()
	_build_strip()
	_build_results()
	_refresh_theme()
	_modal_root.visible   = false
	_strip.visible        = false
	_results_root.visible = false
	ThemeManager.dark_mode_changed.connect(func(_d): _refresh_theme())
	ThemeManager.reading_font_changed.connect(func(f): _font = f; _refresh_theme())

func init(manager: DailyChallengeManager, leaderboard: Node = null) -> void:
	_manager     = manager
	_leaderboard = leaderboard
	_manager.challenge_ready.connect(_on_challenge_ready)
	_manager.challenge_failed.connect(_on_challenge_failed)
	_manager.challenge_completed.connect(_on_challenge_completed)
	if _leaderboard and _leaderboard.has_signal("scores_updated"):
		_leaderboard.scores_updated.connect(_on_scores_updated)

# ── Build modal ───────────────────────────────────────────────────────────────

func _build_modal() -> void:
	_modal_root = Control.new()
	_modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.50)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -300.0
	_panel.offset_top    = -220.0
	_panel.offset_right  = 300.0
	_panel.offset_bottom = 220.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_modal_root.add_child(_panel)

	_panel_style = StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   30)
	margin.add_theme_constant_override("margin_right",  30)
	margin.add_theme_constant_override("margin_top",    24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	_title_lbl = Label.new()
	_title_lbl.text = "📅  Daily Challenge"
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_lbl)
	_info_btn = Button.new()
	_info_btn.text = "ⓘ"
	_info_btn.custom_minimum_size = Vector2(36, 36)
	_info_btn.pressed.connect(_show_help)
	header.add_child(_info_btn)
	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.custom_minimum_size = Vector2(36, 36)
	_close_btn.pressed.connect(close)
	header.add_child(_close_btn)

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 16)
	vbox.add_child(meta)
	_date_lbl = Label.new()
	_date_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(_date_lbl)
	_streak_lbl = Label.new()
	meta.add_child(_streak_lbl)

	vbox.add_child(HSeparator.new())

	_target_header_lbl = Label.new()
	_target_header_lbl.text = "TODAY'S TARGET"
	vbox.add_child(_target_header_lbl)

	_target_lbl = Label.new()
	_target_lbl.text = "Loading..."
	_target_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_target_lbl)

	_best_lbl = Label.new()
	vbox.add_child(_best_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.visible = false
	vbox.add_child(_status_lbl)

	_start_btn = Button.new()
	_start_btn.text = "Enter the Museum  →"
	_start_btn.pressed.connect(_on_start_pressed)
	vbox.add_child(_start_btn)

	_build_help_popup()

# ── Build help popup ──────────────────────────────────────────────────────────

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
	_help_panel.offset_left   = -280.0
	_help_panel.offset_top    = -200.0
	_help_panel.offset_right  = 280.0
	_help_panel.offset_bottom = 200.0
	_help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_help_popup.add_child(_help_panel)

	var panel_style := StyleBoxFlat.new()
	_help_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   24)
	margin.add_theme_constant_override("margin_right",  24)
	margin.add_theme_constant_override("margin_top",    20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_help_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "📅 Daily Challenge Rules"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_title_lbl = title
	if _font: title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	var rules := [
		"• Find the target article before time runs out",
		"• Navigate using only Wikipedia links",
		"• ⌨️ Terminal is disabled during the challenge",
		"• Complete it once per day for your streak",
		"• Beat your best time for a personal record!"
	]

	for rule in rules:
		var lbl := Label.new()
		lbl.text = rule
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		if _font: lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 14)
		_help_rules_lbls.append(lbl)
		vbox.add_child(lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Got it!"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.pressed.connect(_hide_help)
	if _font: close_btn.add_theme_font_override("font", _font)
	vbox.add_child(close_btn)

	# Style the panel
	panel_style.bg_color = ThemeManager.bg_color
	panel_style.border_color = ThemeManager.border_color
	for s in ["left", "right", "top", "bottom"]:
		panel_style.set("border_width_" + s, 1)
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		panel_style.set("corner_radius_" + c, 10)
	panel_style.shadow_color = Color(0, 0, 0, 0.35 if ThemeManager.is_dark_mode else 0.12)
	panel_style.shadow_size = 16
	panel_style.shadow_offset = Vector2(0, 6)

	_style_btn(close_btn, true)

func _animate_help_in() -> void:
	if _help_panel:
		_help_panel.modulate.a = 0.0
		_help_panel.position.y = 14.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_help_panel, "modulate:a", 1.0, 0.35).set_delay(0.05)
		tw.tween_property(_help_panel, "position:y", 0.0, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.05)

func _animate_help_out(then: Callable) -> void:
	if _help_closing:
		return
	_help_closing = true
	if _help_panel:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_help_panel, "modulate:a", 0.0, 0.16)
		tw.tween_property(_help_panel, "position:y", 10.0, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(func():
			_help_closing = false
			then.call()
		)
	else:
		_help_closing = false
		then.call()

func _show_help() -> void:
	_help_popup.visible = true
	_animate_help_in()

func _hide_help() -> void:
	_animate_help_out(func(): _help_popup.visible = false)

# ── Build strip ───────────────────────────────────────────────────────────────

func _build_strip() -> void:
	_strip = PanelContainer.new()
	_strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_strip.offset_top    = 0.0
	_strip.offset_bottom = 44.0
	_strip.offset_left   = 0.0
	_strip.offset_right  = 0.0
	_strip.grow_vertical = Control.GROW_DIRECTION_END
	_strip.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)

	_strip_style = StyleBoxFlat.new()
	_strip.add_theme_stylebox_override("panel", _strip_style)

	var strip_margin := MarginContainer.new()
	strip_margin.add_theme_constant_override("margin_left",   16)
	strip_margin.add_theme_constant_override("margin_right",  16)
	strip_margin.add_theme_constant_override("margin_top",     6)
	strip_margin.add_theme_constant_override("margin_bottom",  6)
	strip_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(strip_margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_margin.add_child(row)

	var icon := Label.new()
	icon.text = "📅"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	_strip_target_lbl = Label.new()
	_strip_target_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_strip_target_lbl)

	var div := Label.new()
	div.text = "│"
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(div)

	_strip_timer_lbl = Label.new()
	_strip_timer_lbl.text = "0:00"
	_strip_timer_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_strip_timer_lbl)

	_strip_best_lbl = Label.new()
	_strip_best_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_strip_best_lbl)

# ── Build results popup ───────────────────────────────────────────────────────

func _build_results() -> void:
	_results_root = Control.new()
	_results_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_results_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_root.add_child(dim)

	_results_panel = PanelContainer.new()
	_results_panel.set_anchors_preset(Control.PRESET_CENTER)
	_results_panel.offset_left   = -300.0
	_results_panel.offset_top    = -320.0
	_results_panel.offset_right  = 300.0
	_results_panel.offset_bottom = 320.0
	_results_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_results_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_results_root.add_child(_results_panel)

	_results_style = StyleBoxFlat.new()
	_results_panel.add_theme_stylebox_override("panel", _results_style)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left",   28)
	outer.add_theme_constant_override("margin_right",  28)
	outer.add_theme_constant_override("margin_top",    22)
	outer.add_theme_constant_override("margin_bottom", 22)
	_results_panel.add_child(outer)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	outer.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var res_title := Label.new()
	res_title.text = "📅  Daily Challenge — Complete!"
	res_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(res_title)
	_res_close_btn = Button.new()
	_res_close_btn.text = "✕"
	_res_close_btn.custom_minimum_size = Vector2(36, 36)
	_res_close_btn.pressed.connect(_close_results)
	header.add_child(_res_close_btn)

	vbox.add_child(HSeparator.new())

	# Grade + time
	_res_grade_lbl = Label.new()
	_res_grade_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_res_grade_lbl.text = "🎉"
	vbox.add_child(_res_grade_lbl)

	_res_time_lbl = Label.new()
	_res_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_res_time_lbl.text = "0:00"
	vbox.add_child(_res_time_lbl)

	_res_best_lbl = Label.new()
	_res_best_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_res_best_lbl.text = "🏆 New personal best!"
	_res_best_lbl.visible = false
	vbox.add_child(_res_best_lbl)

	vbox.add_child(HSeparator.new())

	# Leaderboard header
	_res_lb_header = Label.new()
	_res_lb_header.text = "TODAY'S TOP TIMES"
	vbox.add_child(_res_lb_header)

	_res_lb_loading = Label.new()
	_res_lb_loading.text = "Loading leaderboard…"
	_res_lb_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_res_lb_loading)

	# Scrollable leaderboard
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 100)
	vbox.add_child(scroll)

	_res_lb_list = VBoxContainer.new()
	_res_lb_list.add_theme_constant_override("separation", 5)
	_res_lb_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_res_lb_list)

	vbox.add_child(HSeparator.new())

	# Play again
	_res_play_again_btn = Button.new()
	_res_play_again_btn.text = "Play Again  →"
	_res_play_again_btn.pressed.connect(_on_play_again_pressed)
	vbox.add_child(_res_play_again_btn)

# ── Theme ─────────────────────────────────────────────────────────────────────

func _refresh_theme() -> void:
	if _panel_style:
		_panel_style.bg_color     = ThemeManager.bg_color
		_panel_style.border_color = ThemeManager.border_color
		for s in ["left","right","top","bottom"]:
			_panel_style.set("border_width_" + s, 1)
		for c in ["top_left","top_right","bottom_left","bottom_right"]:
			_panel_style.set("corner_radius_" + c, 10)
		_panel_style.shadow_color  = Color(0,0,0, 0.35 if ThemeManager.is_dark_mode else 0.12)
		_panel_style.shadow_size   = 16
		_panel_style.shadow_offset = Vector2(0, 6)

	if _results_style:
		_results_style.bg_color    = ThemeManager.bg_color
		for s in ["left","right","top","bottom"]:
			_results_style.set("border_width_" + s, 1)
		for c in ["top_left","top_right","bottom_left","bottom_right"]:
			_results_style.set("corner_radius_" + c, 12)
		_results_style.shadow_color  = Color(0,0,0, 0.5)
		_results_style.shadow_size   = 28
		_results_style.shadow_offset = Vector2(0, 8)
		# Gold top accent
		_results_style.border_color     = ThemeManager.border_color
		_results_style.border_width_top = 3

	if _help_panel:
		var style := _help_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.bg_color = ThemeManager.bg_color
			style.border_color = ThemeManager.border_color
			style.shadow_color = Color(0,0,0, 0.35 if ThemeManager.is_dark_mode else 0.12)
	
	# Theme help popup labels
	var help_text_clr := ThemeManager.text_color
	var help_subtext_clr := ThemeManager.subtext_color
	if not ThemeManager.is_dark_mode:
		help_subtext_clr = Color(0.3, 0.3, 0.3, 1.0)
	if _help_title_lbl:
		_slbl(_help_title_lbl, help_text_clr, 18)
	for lbl in _help_rules_lbls:
		_slbl(lbl, help_subtext_clr, 14)

	if _strip_style:
		_strip_style.bg_color            = Color(0.06, 0.06, 0.08, 0.88)
		_strip_style.border_width_bottom = 2
		_strip_style.border_color        = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6)

	# Use darker colors in light mode for better readability
	var accent_color := ACCENT_LIGHT if not ThemeManager.is_dark_mode else ACCENT
	var text_clr := ThemeManager.text_color
	var subtext_clr := ThemeManager.subtext_color
	
	# In light mode, make subtext darker
	if not ThemeManager.is_dark_mode:
		subtext_clr = Color(0.3, 0.3, 0.3, 1.0)

	_slbl(_title_lbl,         text_clr,    26)
	_slbl(_date_lbl,          subtext_clr, 13)
	_slbl(_streak_lbl,        subtext_clr, 13)
	_slbl(_target_header_lbl, Color(accent_color.r, accent_color.g, accent_color.b, 0.9), 10)
	_slbl(_target_lbl,        text_clr,    22)
	_slbl(_best_lbl,          subtext_clr, 13)
	_slbl(_status_lbl,        subtext_clr, 14)

	_slbl(_res_grade_lbl,  accent_color,                52)
	_slbl(_res_time_lbl,   text_clr,    42)
	_slbl(_res_best_lbl,   GREEN,                      14)
	_slbl(_res_lb_header,  Color(accent_color.r, accent_color.g, accent_color.b, 0.9), 10)
	_slbl(_res_lb_loading, subtext_clr, 13)

	_slbl(_strip_target_lbl, subtext_clr, 13)
	_slbl(_strip_timer_lbl,  accent_color, 16)
	_slbl(_strip_best_lbl,   subtext_clr, 12)

	_style_btn(_close_btn,          false)
	_style_btn(_info_btn,           false)
	_style_btn(_res_close_btn,      false)
	_style_btn(_start_btn,          true)
	_style_btn(_res_play_again_btn, true)

func _slbl(lbl: Label, color: Color, size: int) -> void:
	if not lbl: return
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	if _font: lbl.add_theme_font_override("font", _font)

func _style_btn(btn: Button, primary: bool) -> void:
	if not btn: return
	if _font: btn.add_theme_font_override("font", _font)
	if not primary:
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color",       ThemeManager.subtext_color)
		btn.add_theme_color_override("font_hover_color", Color(0.85, 0.3, 0.3))
		for state in ["normal","hover","pressed"]:
			var s := StyleBoxFlat.new()
			s.bg_color = Color(0,0,0,0) if state == "normal" else \
				(Color(0.7,0.2,0.2,0.15) if state == "hover" else Color(0.7,0.2,0.2,0.25))
			s.set_corner_radius_all(4)
			btn.add_theme_stylebox_override(state, s)
		return
	btn.add_theme_font_size_override("font_size", 17)
	for c in ["font_color","font_hover_color","font_pressed_color"]:
		btn.add_theme_color_override(c, ThemeManager.text_color)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0,0,0,0)
	sn.content_margin_left = 16; sn.content_margin_right  = 16
	sn.content_margin_top  = 9;  sn.content_margin_bottom = 9
	btn.add_theme_stylebox_override("normal", sn)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(1,1,1,0.06) if ThemeManager.is_dark_mode \
		else Color(ThemeManager.border_color, 0.5)
	sh.set_corner_radius_all(5)
	sh.content_margin_left = 16; sh.content_margin_right  = 16
	sh.content_margin_top  = 9;  sh.content_margin_bottom = 9
	btn.add_theme_stylebox_override("hover", sh)
	var sp: StyleBoxFlat = sh.duplicate()
	sp.bg_color = Color(1,1,1,0.12) if ThemeManager.is_dark_mode \
		else Color(ThemeManager.border_color, 0.85)
	btn.add_theme_stylebox_override("pressed", sp)

# ── Open / Close (pre-race modal) ─────────────────────────────────────────────

func open() -> void:
	if _is_open: return
	_is_open = true
	_closing = false
	_should_intercept_esc = true  # Enable ESC to close modal
	set_process_unhandled_input(true)
	_modal_root.visible = true
	_populate_meta()
	_animate_in(_panel)
	if not _manager or _manager.get_target_article() == "":
		_target_lbl.text    = "Loading..."
		_start_btn.disabled = true
		_set_status("Fetching today's challenge…")
		if _manager: _manager.start_challenge()
	else:
		_target_lbl.text = _manager.get_target_article()
		_update_start_btn_state()

func close() -> void:
	if _closing: return
	_closing = true
	_should_intercept_esc = false  # Don't intercept ESC while closing
	set_process_unhandled_input(false)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_root.visible = false  # Hide immediately so ESC passes through
	_animate_out(_panel, func():
		_is_open = false
		_closing = false
		challenge_closed.emit()
	)

func is_open() -> bool:
	return _is_open

# ── Results popup ─────────────────────────────────────────────────────────────

func show_results(time_sec: float, is_best: bool) -> void:
	hide_strip()

	# Grade emoji based on time
	_res_grade_lbl.text = _grade_emoji(time_sec)

	# Big time display
	_res_time_lbl.text = "%d:%02d" % [int(time_sec) / 60, int(time_sec) % 60]

	# Personal best banner
	_res_best_lbl.visible = is_best

	# Hide Play Again if already completed (challenge only counts once per day)
	if _res_play_again_btn:
		_res_play_again_btn.visible = not (_manager and _manager.already_completed_today())

	# Leaderboard — show cached entries immediately, refresh in background
	_clear_lb_list()
	_res_lb_loading.visible = true
	if _leaderboard:
		var cached: Array = _leaderboard.get_cached_entries()
		if cached.size() > 0:
			_populate_lb(cached)
		_leaderboard.fetch_scores(_manager.get_today_key(), true)
	else:
		_res_lb_loading.text = "Leaderboard unavailable — configure ENDPOINT in DailyChallengeLeaderboard.gd"

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_results_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_should_intercept_esc = true  # Enable ESC to close results
	set_process_unhandled_input(true)
	_results_root.visible = true
	_animate_in(_results_panel)

func _close_results() -> void:
	_closing_results = true
	_should_intercept_esc = false  # Don't intercept ESC while closing
	set_process_unhandled_input(false)
	_results_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_root.visible = false  # Hide immediately so ESC passes through
	_animate_out(_results_panel, func():
		_closing_results = false
		challenge_closed.emit()
	)

func _on_play_again_pressed() -> void:
	_closing_results = true
	_should_intercept_esc = false  # Don't intercept ESC while closing
	set_process_unhandled_input(false)
	_results_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_root.visible = false  # Hide immediately
	_animate_out(_results_panel, func():
		challenge_started.emit()
	)

func _grade_emoji(secs: float) -> String:
	if   secs < 60:  return "⚡"   ## under 1 min — lightning
	elif secs < 120: return "🌟"   ## under 2 min — excellent
	elif secs < 240: return "🎉"   ## under 4 min — great
	elif secs < 480: return "👍"   ## under 8 min — good
	else:            return "🏁"   ## completed

func _populate_lb(entries: Array) -> void:
	_clear_lb_list()
	_res_lb_loading.visible = false
	var accent_color := ACCENT_LIGHT if not ThemeManager.is_dark_mode else ACCENT
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var rank_lbl := Label.new()
		rank_lbl.text = MEDAL[i] if i < MEDAL.size() else "%d." % (i + 1)
		rank_lbl.custom_minimum_size = Vector2(28, 0)
		_slbl(rank_lbl, ThemeManager.subtext_color, 13)
		row.add_child(rank_lbl)

		var name_lbl := Label.new()
		name_lbl.text = str(e.get("name", "Anonymous"))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_contents = true
		_slbl(name_lbl, ThemeManager.text_color, 13)
		row.add_child(name_lbl)

		var t: float = float(e.get("time_seconds", 0))
		var time_lbl := Label.new()
		time_lbl.text = "%d:%02d" % [int(t) / 60, int(t) % 60]
		_slbl(time_lbl, accent_color, 13)
		row.add_child(time_lbl)

		_res_lb_list.add_child(row)

func _clear_lb_list() -> void:
	if not _res_lb_list: return
	for c in _res_lb_list.get_children():
		c.queue_free()

# ── Strip ────────────────────────────────────────────────────────────────────

func show_strip() -> void:
	if _strip_active: return
	_strip_active = true
	_should_intercept_esc = false  # Don't intercept ESC during race
	set_process_unhandled_input(false)  # Disable _unhandled_input entirely
	if _manager:
		var target := _manager.get_target_article()
		_strip_target_lbl.text = "→ " + target if target != "" else "Daily Challenge"
		var best := _manager.get_best_time()
		_strip_best_lbl.text = "  Best: %d:%02d" % [int(best)/60, int(best)%60] if best > 0.0 else ""
	_strip.modulate.a = 0.0
	_strip.visible = true
	create_tween().tween_property(_strip, "modulate:a", 1.0, 0.3)

func hide_strip() -> void:
	if not _strip_active: return
	_strip_active = false
	_should_intercept_esc = true  # Re-enable for results/modal
	set_process_unhandled_input(true)  # Re-enable _unhandled_input
	var tw := create_tween()
	tw.tween_property(_strip, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): _strip.visible = false)

func hide_all() -> void:
	## Hide the entire HUD (called when entering museum without starting challenge)
	_force_hide_strip()
	if _modal_root: _modal_root.visible = false
	if _results_root: _results_root.visible = false
	visible = false
	_strip_active = false  # Ensure strip won't show even if manager is active

func _force_hide_strip() -> void:
	## Force hide the strip regardless of _strip_active state
	_strip_active = false
	_should_intercept_esc = false
	if _strip:
		_strip.visible = false
		_strip.modulate.a = 0.0

func show_all() -> void:
	## Show the HUD again
	visible = true

# ── Process ───────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not _manager or not _strip_active or not _strip_timer_lbl: return
	var elapsed := _manager.get_elapsed()
	_strip_timer_lbl.text = "%d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]

# ── Signal callbacks ──────────────────────────────────────────────────────────

func _on_challenge_ready(target: String, _start: String) -> void:
	if _target_lbl:        _target_lbl.text = target
	if _strip_target_lbl:  _strip_target_lbl.text = "→ " + target
	if _is_open:
		_status_lbl.visible = false
		_update_start_btn_state()

func _on_challenge_failed(error: String) -> void:
	_set_status("⚠ " + error)
	if _start_btn: _start_btn.disabled = true

func _on_challenge_completed(time_sec: float, is_best: bool) -> void:
	show_results(time_sec, is_best)

func _on_scores_updated(entries: Array) -> void:
	if _results_root and _results_root.visible:
		_populate_lb(entries)

func _on_start_pressed() -> void:
	if not _manager or _manager.already_completed_today(): return
	_start_btn.visible  = false
	_status_lbl.visible = false
	challenge_started.emit()
	close()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _populate_meta() -> void:
	if not _manager: return
	if _date_lbl:   _date_lbl.text = _manager.get_today_key()
	var streak := _manager.get_streak()
	if _streak_lbl: _streak_lbl.text = "🔥 %d day streak" % streak if streak > 0 else ""
	var best := _manager.get_best_time()
	if _best_lbl:
		_best_lbl.text = "Best: %d:%02d" % [int(best)/60, int(best)%60] \
			if best > 0.0 else "No best time yet"

func _update_start_btn_state() -> void:
	if not _start_btn: return
	if _manager.already_completed_today():
		_start_btn.text     = "Already completed today!"
		_start_btn.disabled = true
		_set_status("Come back tomorrow for a new challenge 🌙")
	else:
		_start_btn.text     = "Enter the Museum  →"
		_start_btn.disabled = false
		_status_lbl.visible = false

func _set_status(msg: String) -> void:
	if _status_lbl:
		_status_lbl.text    = msg
		_status_lbl.visible = true

func _animate_in(panel: Control) -> void:
	panel.modulate.a = 0.0
	panel.position.y = 20.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.35).set_delay(0.05)
	tw.tween_property(panel, "position:y", 0.0, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.05)

func _animate_out(panel: Control, then: Callable) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 0.0, 0.16)
	tw.tween_property(panel, "position:y", 10.0, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(then)


# Input handling for modal/results close and help popup
func _unhandled_input(event: InputEvent) -> void:
	# Close help popup with ESC
	if _help_popup and _help_popup.visible and not _help_closing and event.is_action_pressed("ui_cancel"):
		_hide_help()
		get_viewport().set_input_as_handled()
		return
	# Only intercept ESC when modal or results are actively showing
	if not _should_intercept_esc: return
	if not event.is_action_pressed("ui_cancel"): return
	if _closing or _closing_results: return
	if _results_root and _results_root.visible and not _closing_results:
		_close_results()
		get_viewport().set_input_as_handled()
	elif _modal_root and _modal_root.visible and not _closing:
		close()
		get_viewport().set_input_as_handled()
