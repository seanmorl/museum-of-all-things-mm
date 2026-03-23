extends Control
## RaceStatusHUD — Live race standings overlay.
##
## Shows every player's current article, hop count, and a mini trail.
## Styled identically to RaceHUD.gd (same ThemeManager wiring, Cormorant Garamond,
## StyleBoxFlat, text_color / subtext_color / border_color palette).
##
## Position: bottom-left, so it doesn't clash with:
##   • RaceHUD    — top-left
##   • Minimap    — bottom-right
##   • PlayerList — full-screen hold overlay
##
## Hotkey: R  (Tab is already show_player_list — hold to show)
## Auto-shows on race_started; auto-hides 5s after race_ended.
## R key only works while a race is active or the panel is already open.
##
## Spawning: Main.gd creates this with add_child() and we sit as a direct
## child of Main (a Node, not a Control). We create our own PanelContainer
## as a child with PRESET_BOTTOM_LEFT anchoring.  We do NOT re-add self
## to any other parent.

const PANEL_W   : float = 300.0
const ROW_H     : float = 58.0
const MAX_TRAIL : int   = 3
const MAX_PEERS : int   = 8

# ── Node refs (all built in _build_ui) ────────────────────────────────────────
var _serif_font : Font = null

var _panel      : PanelContainer = null
var _race_style : StyleBoxFlat   = null
var _header_sb  : StyleBoxFlat   = null

var _title_lbl  : Label = null
var _hint_lbl   : Label = null
var _timer_lbl  : Label = null
var _canvas     : Control = null
var _target_lbl : Label = null

# ── State ─────────────────────────────────────────────────────────────────────
var _time           : float       = 0.0
var _race_active    : bool        = false
var _winner_peer    : int         = -1
var _target         : String      = ""
var _elapsed_str    : String      = "00:00"
var _auto_hide_timer: float       = 0.0
var _manual_toggle  : bool        = false
var _update_timer   : float       = 0.0

var _players        : Dictionary  = {}

var _local_hops     : int         = 0
var _local_trail    : Array[String] = []
var _local_last_room: String      = ""


# ── Ready ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()

	# We extend Control but we're a child of Main (Node).
	# Don't set anchors on self — just build a free PanelContainer.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_ui()
	_apply_theme(ThemeManager.is_dark_mode)

	ThemeManager.dark_mode_changed.connect(_apply_theme)
	ThemeManager.reading_font_changed.connect(
		func(f: Font): _serif_font = f; _apply_theme(ThemeManager.is_dark_mode))

	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_ended.connect(_on_race_ended)
	RaceManager.race_cancelled.connect(_on_race_cancelled)
	RaceManager.race_timer_updated.connect(_on_timer_updated)
	SettingsEvents.set_current_room.connect(_on_local_room_changed)
	MultiplayerEvents.player_joined.connect(_on_player_joined)
	MultiplayerEvents.player_left.connect(_on_player_left)

	# Register hotkey R (Tab is taken by player-list)
	if not InputMap.has_action("toggle_race_status"):
		InputMap.add_action("toggle_race_status")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_R
		InputMap.action_add_event("toggle_race_status", ev)

	if RaceManager.is_race_active():
		_race_active = true
		_target      = RaceManager.get_target_article()
		_elapsed_str = RaceManager.get_elapsed_time_string()
		_refresh_player_list()
		_show_panel()


# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "RaceStatusPanel"
	_race_style = StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _race_style)

	# Bottom-left, grows upward and to the right
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left   = 12
	_panel.offset_bottom = -12
	_panel.offset_right  = 12 + PANEL_W
	_panel.offset_top    = -12   # will be overridden by content height

	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	add_child(_panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   10)
	mc.add_theme_constant_override("margin_right",  10)
	mc.add_theme_constant_override("margin_top",     8)
	mc.add_theme_constant_override("margin_bottom",  8)
	_panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mc.add_child(vbox)

	# ── Header row ────────────────────────────────────────────────────────────
	var header_wrap := PanelContainer.new()
	_header_sb = StyleBoxFlat.new()
	_header_sb.content_margin_left   = 6
	_header_sb.content_margin_right  = 6
	_header_sb.content_margin_top    = 3
	_header_sb.content_margin_bottom = 3
	header_wrap.add_theme_stylebox_override("panel", _header_sb)
	header_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header_wrap)

	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 6)
	header_wrap.add_child(hrow)

	_title_lbl = Label.new()
	_title_lbl.text                  = "Race Status"
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(_title_lbl)

	_hint_lbl = Label.new()
	_hint_lbl.text = "[R]"
	hrow.add_child(_hint_lbl)

	_timer_lbl = Label.new()
	_timer_lbl.text = "00:00"
	hrow.add_child(_timer_lbl)

	# ── Player rows canvas ────────────────────────────────────────────────────
	_canvas = Control.new()
	_canvas.custom_minimum_size   = Vector2(PANEL_W - 24.0, ROW_H)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_players)
	vbox.add_child(_canvas)

	vbox.add_child(_make_divider())

	# ── Target / winner footer ────────────────────────────────────────────────
	_target_lbl = Label.new()
	_target_lbl.text           = "No active race"
	_target_lbl.autowrap_mode  = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_target_lbl)


# ── Theme ──────────────────────────────────────────────────────────────────────

func _apply_theme(_dark: bool) -> void:
	var dark   := ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)

	if _race_style:
		_race_style.bg_color     = Color(ThemeManager.bg_color, 0.95)
		_race_style.border_color = ThemeManager.border_color
		_race_style.set_border_width_all(1)
		_race_style.set_corner_radius_all(10)
		_race_style.shadow_color  = Color(0, 0, 0, 0.30 if dark else 0.10)
		_race_style.shadow_size   = 14
		_race_style.shadow_offset = Vector2(0, -4)   # shadow above, since panel grows up

	if _header_sb:
		_header_sb.bg_color = Color(accent, 0.07 if dark else 0.04)
		_header_sb.set_corner_radius_all(5)

	if _title_lbl:
		if _serif_font: _title_lbl.add_theme_font_override("font", _serif_font)
		_title_lbl.add_theme_font_size_override("font_size", 11)
		_title_lbl.add_theme_color_override("font_color", ThemeManager.text_color)

	if _hint_lbl:
		if _serif_font: _hint_lbl.add_theme_font_override("font", _serif_font)
		_hint_lbl.add_theme_font_size_override("font_size", 9)
		_hint_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _timer_lbl:
		if _serif_font: _timer_lbl.add_theme_font_override("font", _serif_font)
		_timer_lbl.add_theme_font_size_override("font_size", 11)
		_timer_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _target_lbl:
		if _serif_font: _target_lbl.add_theme_font_override("font", _serif_font)
		_target_lbl.add_theme_font_size_override("font_size", 11)
		# colour is set dynamically in _update_target_lbl()
		_update_target_lbl()

	_refresh_divider_colors()
	if _canvas: _canvas.queue_redraw()


func _refresh_divider_colors() -> void:
	if not _panel: return
	for cr in _panel.find_children("*", "ColorRect", true, false):
		if cr is ColorRect and cr.custom_minimum_size.y == 1:
			cr.color = ThemeManager.border_color


# ── Signal handlers ────────────────────────────────────────────────────────────

func _on_race_started(target_article: String, _start: String) -> void:
	_race_active      = true
	_target           = target_article
	_winner_peer      = -1
	_elapsed_str      = "00:00"
	_local_hops       = 0
	_local_trail.clear()
	_local_last_room  = ""
	_auto_hide_timer  = 0.0
	_refresh_player_list()
	_update_target_lbl()
	_show_panel()


func _on_race_ended(winner_peer_id: int, _winner_name: String) -> void:
	_race_active = false
	_winner_peer = winner_peer_id
	_update_target_lbl()
	if _canvas: _canvas.queue_redraw()
	if not _manual_toggle:
		_auto_hide_timer = 5.0


func _on_race_cancelled() -> void:
	_race_active    = false
	_winner_peer    = -1
	_target         = ""
	_players.clear()
	_update_target_lbl()
	_hide_panel()


func _on_timer_updated(elapsed_seconds: float) -> void:
	var secs      := int(elapsed_seconds)
	_elapsed_str   = "%02d:%02d" % [secs / 60, secs % 60]
	if _timer_lbl: _timer_lbl.text = _elapsed_str


func _on_local_room_changed(room: Variant) -> void:
	var r : String = str(room)
	if r == "" or r == "Lobby" or r == _local_last_room or not _race_active: return
	_local_last_room = r
	_local_hops     += 1
	if not _local_trail.has(r): _local_trail.append(r)
	var my_id := NetworkManager.get_unique_id()
	if _players.has(my_id):
		_players[my_id].current_room = r
		_players[my_id].hops         = _local_hops
		_players[my_id].trail        = _local_trail.slice(
			maxi(0, _local_trail.size() - MAX_TRAIL - 5))


func _on_player_joined(_peer_id: int, _name: String) -> void:
	_refresh_player_list()

func _on_player_left(peer_id: int) -> void:
	_players.erase(peer_id)
	_resize_canvas()


# ── Player management ──────────────────────────────────────────────────────────

func _refresh_player_list() -> void:
	_players.clear()
	var my_id := NetworkManager.get_unique_id()
	var local  := _make_entry(my_id)
	local.hops  = _local_hops
	local.trail = _local_trail.duplicate()
	_players[my_id] = local
	for pid : int in NetworkManager.get_player_list():
		if pid != my_id:
			_players[pid] = _make_entry(pid)
	_resize_canvas()
	_update_target_lbl()


func _make_entry(peer_id: int) -> Dictionary:
	return {
		"name"        : NetworkManager.get_player_name(peer_id),
		"color"       : NetworkManager.get_player_color(peer_id),
		"current_room": NetworkManager.get_player_room(peer_id),
		"hops"        : 0,
		"trail"       : [],
		"is_local"    : peer_id == NetworkManager.get_unique_id(),
		"peer_id"     : peer_id,
	}


func _resize_canvas() -> void:
	var n : int = mini(_players.size(), MAX_PEERS)
	if _canvas:
		_canvas.custom_minimum_size = Vector2(PANEL_W - 24.0, maxf(float(n), 1.0) * ROW_H)


func _update_target_lbl() -> void:
	if not _target_lbl: return
	var dark   := ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	var gold   := Color(1.00, 0.82, 0.25) if dark else Color(0.85, 0.62, 0.05)
	if _serif_font: _target_lbl.add_theme_font_override("font", _serif_font)
	_target_lbl.add_theme_font_size_override("font_size", 11)
	if _winner_peer >= 0:
		var wname : String = NetworkManager.get_player_name(_winner_peer)
		_target_lbl.text = "★  %s wins!" % wname
		_target_lbl.add_theme_color_override("font_color", gold)
	elif _target != "":
		_target_lbl.text = "→  " + _target.replace("_", " ")
		_target_lbl.add_theme_color_override("font_color", accent)
	else:
		_target_lbl.text = "No active race"
		_target_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)


func _get_live_room(peer_id: int) -> String:
	if peer_id == NetworkManager.get_unique_id():
		return _local_last_room
	if NetworkManager.player_info.has(peer_id):
		var info : Dictionary = NetworkManager.player_info[peer_id]
		if info.has("current_room"):
			return str(info.current_room)
	return NetworkManager.get_player_room(peer_id)


# ── Draw ───────────────────────────────────────────────────────────────────────

func _draw_players() -> void:
	if not _canvas: return
	var dark   := ThemeManager.is_dark_mode
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.12, 0.32, 0.82)
	var sz     := _canvas.size
	if sz == Vector2.ZERO: return

	var peers : Array = _players.keys()
	peers.sort_custom(func(a, b):
		if _players[a].is_local: return true
		if _players[b].is_local: return false
		return _players[a].hops > _players[b].hops)

	var y : float = 0.0
	for pid : int in peers:
		if y + ROW_H > sz.y + 1.0: break
		_draw_row(_players[pid], y, sz.x, accent, dark)
		y += ROW_H


func _draw_row(p: Dictionary, y: float, w: float, accent: Color, dark: bool) -> void:
	var is_winner : bool = _winner_peer == p.peer_id and _winner_peer >= 0
	var gold      : Color = Color(1.00, 0.82, 0.25) if dark else Color(0.85, 0.62, 0.05)

	# Row tint
	if is_winner:
		_canvas.draw_rect(Rect2(0, y + 1, w, ROW_H - 2), Color(gold, 0.10 if dark else 0.08))
	elif p.is_local:
		_canvas.draw_rect(Rect2(0, y + 1, w, ROW_H - 2), Color(accent, 0.08 if dark else 0.05))

	# Separator
	if y > 0.5:
		_canvas.draw_line(Vector2(6, y), Vector2(w - 6, y),
			Color(ThemeManager.border_color, 0.50), 0.5)

	var dot_y  : float = y + ROW_H * 0.27
	var lbl_x  : float = 22.0
	var p_col  : Color = p.color if p.color else accent

	# Colour dot
	_canvas.draw_circle(Vector2(10, dot_y), 5.0, Color(1, 1, 1, 0.85))
	_canvas.draw_circle(Vector2(10, dot_y), 3.8, p_col)

	if _serif_font:
		# Name + "(you)" / winner star
		var name_str : String = p.name
		if p.is_local:  name_str += "  (you)"
		if is_winner:   name_str += "  ★"
		if name_str.length() > 26: name_str = name_str.substr(0, 25) + "…"
		_canvas.draw_string(_serif_font, Vector2(lbl_x, dot_y + 5),
			name_str, HORIZONTAL_ALIGNMENT_LEFT,
			w - lbl_x - 60.0, 11,
			Color(gold if is_winner else ThemeManager.text_color, 0.96))

		# Hop count — right aligned
		var hop_str : String = "%d hop%s" % [p.hops, "s" if p.hops != 1 else ""]
		_canvas.draw_string(_serif_font, Vector2(w - 6, dot_y + 5),
			hop_str, HORIZONTAL_ALIGNMENT_RIGHT, 58.0, 10,
			Color(ThemeManager.subtext_color, 0.72))

		# Current room
		var room_y    : float  = y + ROW_H * 0.54
		var live_room : String = _get_live_room(p.peer_id)
		if live_room == "" or live_room == "Lobby": live_room = "Lobby"
		var is_tgt    : bool   = (live_room == _target and _target != "")
		var room_lbl  : String = ("★ " if is_tgt else "◉ ") + live_room.replace("_", " ")
		if room_lbl.length() > 34: room_lbl = room_lbl.substr(0, 33) + "…"
		_canvas.draw_string(_serif_font, Vector2(lbl_x, room_y + 4),
			room_lbl, HORIZONTAL_ALIGNMENT_LEFT,
			w - lbl_x - 8.0, 10,
			Color(gold if is_tgt else Color(accent, 0.82), 0.90))

		# Mini trail
		var trail_y : float = y + ROW_H * 0.81
		if p.trail.size() > 0:
			var show_trail : Array = p.trail.slice(maxi(0, p.trail.size() - MAX_TRAIL))
			var trail_str  : String = show_trail.map(
				func(s: String) -> String:
					var c := s.replace("_", " ")
					return c if c.length() <= 10 else c.substr(0, 9) + "…"
			).reduce(func(a, b): return a + "  ·  " + b, "")
			if trail_str.length() > 50: trail_str = trail_str.substr(0, 49) + "…"
			_canvas.draw_string(_serif_font, Vector2(lbl_x, trail_y + 3),
				trail_str, HORIZONTAL_ALIGNMENT_LEFT,
				w - lbl_x - 8.0, 9,
				Color(ThemeManager.subtext_color, 0.50))


# ── Show / hide ────────────────────────────────────────────────────────────────

func _show_panel() -> void:
	if not _panel or _panel.visible: return
	_panel.visible   = true
	_panel.modulate.a = 0.0
	_panel.position.y = 8.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "position:y", 0.0, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_panel() -> void:
	if not _panel or not _panel.visible: return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "position:y", 8.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		if _panel: _panel.visible = false; _panel.position.y = 0.0)


# ── Process ────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_time         += delta
	_update_timer += delta

	if _auto_hide_timer > 0.0:
		_auto_hide_timer -= delta
		if _auto_hide_timer <= 0.0:
			_manual_toggle = false
			_hide_panel()

	if _update_timer >= 0.5:
		_update_timer = 0.0
		_sync_remote_players()

	if _canvas and _panel and _panel.visible:
		_canvas.queue_redraw()


func _sync_remote_players() -> void:
	var my_id := NetworkManager.get_unique_id()
	for pid : int in _players.keys():
		if pid == my_id: continue
		var entry : Dictionary = _players[pid]
		var new_room : String = _get_live_room(pid)
		if new_room != "" and new_room != "Lobby" and new_room != entry.current_room:
			if not entry.trail.has(new_room):
				entry.trail.append(new_room)
				entry.hops += 1
			entry.current_room = new_room
		entry.name  = NetworkManager.get_player_name(pid)
		entry.color = NetworkManager.get_player_color(pid)


# ── Input ──────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action("toggle_race_status"): return
	if not event.is_action_pressed("toggle_race_status"): return
	if not _race_active and (not _panel or not _panel.visible): return
	_manual_toggle   = true
	_auto_hide_timer = 0.0
	if _panel and _panel.visible: _hide_panel()
	else:
		_refresh_player_list()
		_show_panel()
	get_viewport().set_input_as_handled()


# ── Helpers ────────────────────────────────────────────────────────────────────

func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	d.color               = ThemeManager.border_color
	return d
