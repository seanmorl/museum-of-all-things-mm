extends Control
## PlayerListOverlay — compact multiplayer player list.
## All UI built in code. Anchored top-right, matches RaceHUD aesthetic.
## Refreshes on peer connect/disconnect/info-update and on visibility change.

# ── Node refs ─────────────────────────────────────────────────────────────────
var _serif_font:    Font           = null
var _panel:         PanelContainer = null
var _panel_style:   StyleBoxFlat   = null
var _title_label:   Label          = null
var _player_list:   VBoxContainer  = null


func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	_build_ui()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f): _serif_font = f; _apply_theme())
	NetworkManager.peer_connected.connect(_on_network_changed)
	NetworkManager.peer_disconnected.connect(_on_network_changed)
	NetworkManager.player_info_updated.connect(_on_network_changed)
	visibility_changed.connect(func():
		if visible: _refresh()
	)


func _on_network_changed(_id: Variant = null) -> void:
	if visible: _refresh()


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel_style = StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _panel_style)

	# Top-right anchor, 220px wide, grows downward
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical   = Control.GROW_DIRECTION_END
	_panel.offset_left   = -220
	_panel.offset_top    =   16
	_panel.offset_right  =  -16
	_panel.offset_bottom =   16
	add_child(_panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   14)
	mc.add_theme_constant_override("margin_right",  14)
	mc.add_theme_constant_override("margin_top",    10)
	mc.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	mc.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	_title_label = Label.new()
	_title_label.text = "Players Online"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_label)

	vbox.add_child(_make_divider())

	# Player list
	_player_list = VBoxContainer.new()
	_player_list.add_theme_constant_override("separation", 5)
	vbox.add_child(_player_list)


func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


# ── Theme ─────────────────────────────────────────────────────────────────────

func _apply_theme() -> void:
	var dark: bool = ThemeManager.is_dark_mode

	if _panel_style:
		_panel_style.bg_color     = Color(ThemeManager.bg_color, 0.93)
		_panel_style.border_color = ThemeManager.border_color
		_panel_style.set_border_width_all(1)
		_panel_style.set_corner_radius_all(10)
		_panel_style.shadow_color  = Color(0, 0, 0, 0.28 if dark else 0.10)
		_panel_style.shadow_size   = 12
		_panel_style.shadow_offset = Vector2(0, 3)

	if _title_label:
		if _serif_font: _title_label.add_theme_font_override("font", _serif_font)
		_title_label.add_theme_font_size_override("font_size", 13)
		_title_label.add_theme_color_override("font_color", ThemeManager.text_color)

	# Refresh dividers
	if _panel:
		for cr in _panel.find_children("*", "ColorRect", true, false):
			if cr is ColorRect and cr.custom_minimum_size.y == 1:
				cr.color = ThemeManager.border_color

	_restyle_players()


func _restyle_players() -> void:
	if not _player_list: return
	for entry in _player_list.get_children():
		if not entry is VBoxContainer: continue
		var name_lbl := entry.get_node_or_null("NameLabel") as Label
		var room_lbl := entry.get_node_or_null("RoomLabel") as Label
		var dot      := entry.get_node_or_null("ColorDot")  as ColorRect
		if name_lbl:
			if _serif_font: name_lbl.add_theme_font_override("font", _serif_font)
			name_lbl.add_theme_font_size_override("font_size", 13)
		if room_lbl:
			if _serif_font: room_lbl.add_theme_font_override("font", _serif_font)
			room_lbl.add_theme_font_size_override("font_size", 10)
			room_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)


# ── Data refresh ──────────────────────────────────────────────────────────────

func _refresh(_id: Variant = null) -> void:
	if not _player_list: return
	for c in _player_list.get_children(): c.queue_free()

	for peer_id in NetworkManager.get_player_list():
		var player_name: String = NetworkManager.get_player_name(peer_id)
		var player_color: Color = NetworkManager.get_player_color(peer_id)
		var room_name:   String = NetworkManager.get_player_room(peer_id)
		var is_you:      bool   = peer_id == NetworkManager.get_unique_id()
		var is_host:     bool   = peer_id == 1

		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 1)
		_player_list.add_child(entry)

		# Name row: colour dot + name + badges
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 6)
		entry.add_child(name_row)

		# Colour dot
		var dot := ColorRect.new()
		dot.name = "ColorDot"
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size = Vector2(8, 8)
		dot.color = player_color
		# Centre the dot vertically via a CenterContainer
		var dot_wrap := CenterContainer.new()
		dot_wrap.custom_minimum_size = Vector2(8, 0)
		dot_wrap.add_child(dot)
		name_row.add_child(dot_wrap)

		# Name label
		var name_lbl := Label.new()
		name_lbl.name = "NameLabel"
		var suffix := ""
		if is_host: suffix += "  ·  Host"
		if is_you:  suffix += "  ·  You"
		name_lbl.text = player_name + suffix
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_color_override("font_color", ThemeManager.text_color)
		if _serif_font: name_lbl.add_theme_font_override("font", _serif_font)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_row.add_child(name_lbl)

		# Room sub-line
		var room_lbl := Label.new()
		room_lbl.name = "RoomLabel"
		room_lbl.text = "  " + room_name
		room_lbl.add_theme_font_size_override("font_size", 10)
		room_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
		if _serif_font: room_lbl.add_theme_font_override("font", _serif_font)
		entry.add_child(room_lbl)

		# Fade each entry in
		entry.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(entry, "modulate:a", 1.0, 0.20) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ── Slide animation ───────────────────────────────────────────────────────────

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible:
			_slide_in()

func _slide_in() -> void:
	if not _panel: return
	_panel.modulate.a  = 0.0
	_panel.offset_top  = 26
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "offset_top", 16, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

