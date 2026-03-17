extends Control
## RaceHUD — in-race overlay showing timer, target, and breadcrumb trail.
## All UI built in code so no tscn node structure is required.
## Countdown is handled by the RaceCountdown autoload — not here.

# ── Constants ─────────────────────────────────────────────────────────────────
const TIMELINE_MAX_ROWS: int = 4

## HUD corner positions matching GraphicsSettings cycle order:
## 0=Top Left  1=Top Right  2=Bottom Left  3=Bottom Right
const HUD_POSITIONS: Array[Dictionary] = [
	{"preset": Control.PRESET_TOP_LEFT,    "grow_h": Control.GROW_DIRECTION_END,   "grow_v": Control.GROW_DIRECTION_END,   "ol": 16,   "ot": 16, "or_": 256,  "ob": 16},
	{"preset": Control.PRESET_TOP_RIGHT,   "grow_h": Control.GROW_DIRECTION_BEGIN, "grow_v": Control.GROW_DIRECTION_END,   "ol": -256, "ot": 16, "or_": -16,  "ob": 16},
	{"preset": Control.PRESET_BOTTOM_LEFT, "grow_h": Control.GROW_DIRECTION_END,   "grow_v": Control.GROW_DIRECTION_BEGIN, "ol": 16,   "ot": -16,"or_": 256,  "ob": -16},
	{"preset": Control.PRESET_BOTTOM_RIGHT,"grow_h": Control.GROW_DIRECTION_BEGIN, "grow_v": Control.GROW_DIRECTION_BEGIN, "ol": -256, "ot": -16,"or_": -16,  "ob": -16},
]

# ── Node refs (all built in _build_ui) ────────────────────────────────────────
var _serif_font: Font = null

## Race panel — anchored top-left
var _race_panel:      PanelContainer = null
var _race_style:      StyleBoxFlat   = null
var _timer_label:     Label          = null
var _target_label:    Label          = null
var _timeline_scroll: ScrollContainer = null
var _timeline_list:   VBoxContainer  = null

## Animated timer pulse ring drawn via a custom Control
var _timer_ring:      Control        = null
var _ring_pulse:      float          = 0.0   # 0→1, drives scale/alpha of ring
var _last_timer_secs: int            = -1


# ── State ─────────────────────────────────────────────────────────────────────
var _visited_pages:   Array[String]  = []


func _ready() -> void:
	add_to_group("race_hud")
	_serif_font = ThemeManager.get_reading_font()
	visible = false
	_build_ui()
	_apply_theme(ThemeManager.is_dark_mode)
	ThemeManager.dark_mode_changed.connect(_apply_theme)
	ThemeManager.reading_font_changed.connect(func(f): _serif_font = f; _apply_theme(ThemeManager.is_dark_mode))
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_cancelled.connect(_on_race_cancelled)
	RaceManager.race_timer_updated.connect(_on_race_timer_updated)
	SettingsEvents.set_current_room.connect(_on_room_changed)
	SettingsEvents.accessibility_changed.connect(_on_accessibility_changed)
	_apply_initial_accessibility_settings()
	# Apply saved HUD position
	var hud_s: Variant = SettingsManager.get_settings("hud")
	if hud_s is Dictionary:
		set_hud_position(hud_s.get("race_hud_position", 0))


# ── Accessibility ─────────────────────────────────────────────────────────────

func _apply_initial_accessibility_settings() -> void:
	var acc: Dictionary = SettingsManager.get_settings("accessibility") if SettingsManager.get_settings("accessibility") else {}
	if acc.get("large_hud_text", false):
		_apply_large_hud_text(true)

func _on_accessibility_changed(key: String, value: Variant) -> void:
	if key == "large_hud_text":
		_apply_large_hud_text(value as bool)

func _apply_large_hud_text(enabled: bool) -> void:
	if _timer_label:  _timer_label.add_theme_font_size_override("font_size",  30 if enabled else 20)
	if _target_label: _target_label.add_theme_font_size_override("font_size", 16 if enabled else 11)


func set_hud_position(idx: int) -> void:
	## Moves both panels to the chosen corner. idx: 0=TL 1=TR 2=BL 3=BR
	idx = clampi(idx, 0, HUD_POSITIONS.size() - 1)
	var p: Dictionary = HUD_POSITIONS[idx]
	for panel in [_race_panel]:
		if not panel: continue
		panel.set_anchors_preset(p.preset)
		panel.grow_horizontal = p.grow_h
		panel.grow_vertical   = p.grow_v
		panel.offset_left     = p.ol
		panel.offset_top      = p.ot
		panel.offset_right    = p.or_
		panel.offset_bottom   = p.ob


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	_build_race_panel()


func _build_race_panel() -> void:
	_race_panel = PanelContainer.new()
	_race_panel.name = "RacePanel"
	_race_style = StyleBoxFlat.new()
	_race_panel.add_theme_stylebox_override("panel", _race_style)
	_race_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_race_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # Don't grow horizontally
	_race_panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN  # Don't grow vertically
	_race_panel.offset_left   =  12
	_race_panel.offset_top    =  12
	_race_panel.offset_right  = 212   # 200px wide
	_race_panel.offset_bottom = 200   # Fixed height (188px content area)
	_race_panel.custom_minimum_size = Vector2(200, 188)  # Enforce fixed size
	_race_panel.visible = false
	add_child(_race_panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   10)
	mc.add_theme_constant_override("margin_right",  10)
	mc.add_theme_constant_override("margin_top",     8)
	mc.add_theme_constant_override("margin_bottom",  8)
	_race_panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mc.add_child(vbox)

	# ── Timer row: ring + clock ───────────────────────────────────────────────
	var timer_row := HBoxContainer.new()
	timer_row.add_theme_constant_override("separation", 8)
	timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(timer_row)

	_timer_ring = Control.new()
	_timer_ring.custom_minimum_size = Vector2(16, 16)
	_timer_ring.size = Vector2(16, 16)
	_timer_ring.draw.connect(_draw_timer_ring)
	_timer_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_row.add_child(_timer_ring)

	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.text = "00:00"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timer_row.add_child(_timer_label)

	# Thin divider
	vbox.add_child(_make_divider())

	# ── Target ────────────────────────────────────────────────────────────────
	_target_label = Label.new()
	_target_label.name = "TargetLabel"
	_target_label.text = "Find:"
	_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_target_label)

	# Thin divider
	vbox.add_child(_make_divider())

	# ── Breadcrumb trail — fixed-height scroll, fills remaining panel space ───
	_timeline_scroll = ScrollContainer.new()
	_timeline_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_timeline_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_timeline_scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	# Fix maximum height to prevent panel from growing
	_timeline_scroll.custom_minimum_size = Vector2(0, 80)  # Fixed height for timeline
	# Never let the scroll bar itself be interactive (auto-scroll only)
	_timeline_scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_timeline_scroll)

	_timeline_list = VBoxContainer.new()
	_timeline_list.add_theme_constant_override("separation", 1)
	_timeline_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_scroll.add_child(_timeline_list)



func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	d.color               = Color(1, 1, 1, 0.12)
	return d


# ── Theme ─────────────────────────────────────────────────────────────────────

func _apply_theme(_dark: bool) -> void:
	var dark := ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)

	# Panel backgrounds — slightly more opaque than menus to stay readable in-world
	if _race_style:
		_race_style.bg_color     = Color(ThemeManager.bg_color, 0.93)
		_race_style.border_color = ThemeManager.border_color
		_race_style.set_border_width_all(1)
		_race_style.set_corner_radius_all(10)
		_race_style.shadow_color  = Color(0, 0, 0, 0.30 if dark else 0.10)
		_race_style.shadow_size   = 14
		_race_style.shadow_offset = Vector2(0, 4)

	if _timer_label:
		if _serif_font: _timer_label.add_theme_font_override("font", _serif_font)
		_timer_label.add_theme_font_size_override("font_size", 20)
		_timer_label.add_theme_color_override("font_color", ThemeManager.text_color)

	if _target_label:
		if _serif_font: _target_label.add_theme_font_override("font", _serif_font)
		_target_label.add_theme_font_size_override("font_size", 11)
		_target_label.add_theme_color_override("font_color", ThemeManager.subtext_color)

	_refresh_timeline_colors()
	_refresh_divider_colors()

	if _timer_ring:
		_timer_ring.queue_redraw()


func _refresh_divider_colors() -> void:
	for panel in [_race_panel]:
		if not panel: continue
		for cr in panel.find_children("*", "ColorRect", true, false):
			if cr is ColorRect and cr.custom_minimum_size.y == 1:
				cr.color = ThemeManager.border_color


func _refresh_timeline_colors() -> void:
	for container in [_timeline_list]:
		if not container: continue
		for child in container.get_children():
			if child is Label:
				match child.get_meta("role", "mid"):
					"start":
						child.add_theme_color_override("font_color",
							Color(0.30, 0.75, 0.45) if ThemeManager.is_dark_mode else Color(0.0, 0.45, 0.15))
					"current":
						child.add_theme_color_override("font_color", ThemeManager.text_color)
					"target":
						child.add_theme_color_override("font_color",
							Color(0.30, 0.55, 1.00) if ThemeManager.is_dark_mode else Color(0.12, 0.32, 0.82))
					_:
						child.add_theme_color_override("font_color", ThemeManager.subtext_color)


# ── Timer ring draw ───────────────────────────────────────────────────────────

func _draw_timer_ring() -> void:
	if not _timer_ring: return
	var dark   := ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	var cx:    float = _timer_ring.size.x * 0.5
	var cy:    float = _timer_ring.size.y * 0.5
	var r:     float = min(cx, cy) - 1.5

	# Static background ring
	_timer_ring.draw_arc(Vector2(cx, cy), r, 0.0, TAU, 32,
		Color(accent, 0.18), 2.0, true)

	# Animated pulse ring — expands outward when the second ticks
	if _ring_pulse > 0.005:
		var pulse_r: float = r * (1.0 + _ring_pulse * 0.9)
		_timer_ring.draw_arc(Vector2(cx, cy), pulse_r, 0.0, TAU, 32,
			Color(accent, _ring_pulse * 0.6), 1.5, true)

	# Solid centre dot
	_timer_ring.draw_circle(Vector2(cx, cy), r * 0.28, Color(accent, 0.80))


# ── Timeline helpers ──────────────────────────────────────────────────────────

func _make_trail_label(text: String, role: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.set_meta("role", role)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 11)
	if _serif_font: lbl.add_theme_font_override("font", _serif_font)
	match role:
		"start":
			lbl.add_theme_color_override("font_color",
				Color(0.30, 0.75, 0.45) if ThemeManager.is_dark_mode else Color(0.0, 0.45, 0.15))
		"current":
			lbl.add_theme_color_override("font_color", ThemeManager.text_color)
		"target":
			lbl.add_theme_color_override("font_color",
				Color(0.30, 0.55, 1.00) if ThemeManager.is_dark_mode else Color(0.12, 0.32, 0.82))
		_:
			lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
	return lbl


func _refresh_timeline() -> void:
	if not _timeline_list: return
	for c in _timeline_list.get_children(): c.queue_free()

	var target := RaceManager.get_target_article()
	var total  := _visited_pages.size()
	if total == 0: return

	# Show start + last few pages + ellipsis if needed
	var show: Array = [0]
	var win_start := int(max(1, total - (TIMELINE_MAX_ROWS - 1)))
	if win_start > 1:
		show.append(-1)  # ellipsis
	for i in range(win_start, total):
		show.append(i)

	for idx in show:
		if idx == -1:
			_timeline_list.add_child(_make_trail_label("  ···", "mid"))
			continue
		var page:      String = _visited_pages[idx]
		var is_first:  bool   = idx == 0
		var is_last:   bool   = idx == total - 1
		var is_target: bool   = page == target
		var prefix: String
		var role: String
		if is_target:
			prefix = "★ "
			role = "target"
		elif is_first:
			prefix = "▶ "
			role = "start"
		elif is_last:
			prefix = "◉ "
			role = "current"
		else:
			prefix = "· "
			role = "mid"
		var lbl := _make_trail_label(prefix + page, role)
		_timeline_list.add_child(lbl)
		# Fade-slide new entries in
		if is_last and not is_first:
			lbl.modulate.a  = 0.0
			lbl.position.x  = 10.0
			var tw := create_tween().set_parallel(true)
			tw.tween_property(lbl, "modulate:a", 1.0, 0.25) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(lbl, "position:x", 0.0, 0.25) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Panel is fixed height — scroll container enforces max height
	_scroll_to_bottom()


func _scroll_to_bottom() -> void:
	if not _timeline_scroll:
		return
	# Wait two frames so the new label has been laid out before measuring max scroll
	await get_tree().process_frame
	await get_tree().process_frame
	var bar := _timeline_scroll.get_v_scroll_bar()
	if bar.max_value <= bar.page:
		return   # nothing to scroll
	var target_scroll: float = bar.max_value - bar.page
	var tw := create_tween()
	tw.tween_property(_timeline_scroll, "scroll_vertical",
		int(target_scroll), 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ── Animation helpers ─────────────────────────────────────────────────────────

func _reduce_motion() -> bool:
	var acc: Dictionary = SettingsManager.get_settings("accessibility") if SettingsManager.get_settings("accessibility") else {}
	return acc.get("reduce_motion", false)


func _slide_in(panel: Control) -> void:
	if not panel: return
	panel.visible = true
	if _reduce_motion():
		panel.modulate.a = 1.0
		panel.position.y = 0.0
		return
	panel.modulate.a = 0.0
	panel.position.y = -24.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "position:y", 0.0, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _slide_out(panel: Control, then_hide: bool = true) -> void:
	if not panel or not panel.visible: return
	if _reduce_motion():
		if then_hide: panel.visible = false
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 0.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(panel, "position:y", -16.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if then_hide:
		tw.chain().tween_callback(func():
			panel.visible  = false
			panel.modulate.a = 1.0
			panel.position.y = 0.0
		)


# ── _process ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Timer ring pulse decay
	if _ring_pulse > 0.0:
		_ring_pulse = maxf(_ring_pulse - delta * 3.5, 0.0)
		if _timer_ring: _timer_ring.queue_redraw()

	# Win popup auto-dismiss


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_race_started(target_article: String, start_article: String) -> void:
	_visited_pages = [start_article]
	if _timer_label:  _timer_label.text  = "00:00"
	if _target_label:
		_target_label.text = target_article
		# Animate the target label in as a stagger after the race panel
		_target_label.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_target_label, "modulate:a", 1.0, 0.40) \
			.set_delay(0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if _timeline_list:
		for c in _timeline_list.get_children(): c.queue_free()
	if _timeline_scroll:
		_timeline_scroll.custom_minimum_size = Vector2(0, 0)
	visible = true
	_slide_in(_race_panel)


func _on_race_timer_updated(elapsed_seconds: float) -> void:
	var secs := int(elapsed_seconds)
	if _timer_label:
		_timer_label.text = "%02d:%02d" % [secs / 60, secs % 60]
	# Fire pulse ring on each new second
	if secs != _last_timer_secs:
		_last_timer_secs = secs
		_ring_pulse = 1.0
		if _timer_ring: _timer_ring.queue_redraw()


func _on_room_changed(room: String) -> void:
	if not RaceManager.is_race_active() or room == "Lobby": return
	if room == RaceManager.get_start_article(): return
	if _visited_pages.has(room): return
	_visited_pages.append(room)
	_refresh_timeline()




func _on_race_cancelled() -> void:
	_dismiss()


func _dismiss() -> void:
	_slide_out(_race_panel)
	await get_tree().create_timer(0.22).timeout
	visible = false
	_visited_pages.clear()
