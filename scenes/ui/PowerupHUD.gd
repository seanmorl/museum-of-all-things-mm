extends Control
class_name PowerupHUD
## HUD displaying active powerups with timers.
## Compact pill-style cards anchored to the bottom-left of the screen.

const ICONS := {
	PowerupManager.PowerupType.SPEED_BOOST: "⚡",
	PowerupManager.PowerupType.PERFECT_KNOWLEDGE: "👁",
	PowerupManager.PowerupType.GUN: "🔫",
	PowerupManager.PowerupType.TRAP: "💣",
	PowerupManager.PowerupType.TOWER_OF_BABEL: "🗼",
	PowerupManager.PowerupType.LIGHTS_OUT: "🌑",
	PowerupManager.PowerupType.MAGNET: "🧲",
	PowerupManager.PowerupType.GRAPPLE: "🕸️",
	PowerupManager.PowerupType.OMNISCIENCE: "🔮"
}

const COLORS := {
	PowerupManager.PowerupType.SPEED_BOOST:       Color(1.0,  0.85, 0.0),
	PowerupManager.PowerupType.PERFECT_KNOWLEDGE: Color(0.0,  0.9,  1.0),
	PowerupManager.PowerupType.GUN:               Color(1.0,  0.25, 0.25),
	PowerupManager.PowerupType.TRAP:              Color(0.2,  1.0,  0.35),
	PowerupManager.PowerupType.TOWER_OF_BABEL:    Color(0.65, 0.45, 1.0),
	PowerupManager.PowerupType.LIGHTS_OUT:        Color(0.55, 0.55, 0.85),
	PowerupManager.PowerupType.MAGNET:            Color(1.0,  0.35, 0.65),
	PowerupManager.PowerupType.GRAPPLE:           Color(0.9,  0.9,  0.9),
	PowerupManager.PowerupType.OMNISCIENCE:       Color(1.0,  0.75, 0.2)
}

const DESCRIPTIONS := {
	PowerupManager.PowerupType.SPEED_BOOST:
		"You move twice as fast for 15 seconds.",
	PowerupManager.PowerupType.PERFECT_KNOWLEDGE:
		"Door labels are revealed in every room for 10 seconds.",
	PowerupManager.PowerupType.GUN:
		"Press [Use] to shoot a beam — the first player it hits is teleported back to the Lobby.",
	PowerupManager.PowerupType.TRAP:
		"Press [Use] to place a trap on the floor ahead of you. The next player to walk into it gets sent to the Lobby.",
	PowerupManager.PowerupType.TOWER_OF_BABEL:
		"Forces all other players to see the next 5 rooms they enter in a random foreign language.",
	PowerupManager.PowerupType.LIGHTS_OUT:
		"All other players' screens go dark for 2 minutes — only you can see clearly.",
	PowerupManager.PowerupType.MAGNET:
		"Press [Use] to pull every other player into your current room.",
	PowerupManager.PowerupType.GRAPPLE:
		"Press [Use] to fire a grappling hook at the ceiling and swing across gaps. Lasts 60 seconds.",
	PowerupManager.PowerupType.OMNISCIENCE:
		"See all other players' active and stashed powerups for 30 seconds.",
}

# Card background opacity (applied over ThemeManager.bg_color)
const CARD_BG_ALPHA := 0.92

@onready var _stack: VBoxContainer = $Stack

var _powerup_cards: Dictionary = {}   # powerup_type -> { card, timer_label, bar, style }
var _hud_visible: bool = false
var _player: Node = null
var _font: Font = null
var _banner: Control = null   # bottom-center collection toast

# Omniscience spy overlay — shown top-right while OMNISCIENCE is active
var _spy_panel: PanelContainer = null
var _spy_list: VBoxContainer = null

func init(player: Node) -> void:
	_player = player
	_font = ThemeManager.get_reading_font()

func _ready() -> void:
	visible = false
	_stack.modulate.a = 0.0

	# Bottom-centre anchor for collection toasts.
	_banner = Control.new()
	_banner.name = "BannerAnchor"
	_banner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)

	PowerupManager.powerup_collected.connect(_on_powerup_collected)
	PowerupManager.powerup_collected_network.connect(_on_powerup_collected_network)
	PowerupManager.powerup_expired.connect(_on_powerup_expired)

	ThemeManager.dark_mode_changed.connect(_on_theme_changed)
	ThemeManager.reading_font_changed.connect(_on_reading_font_changed)

	_build_spy_panel()

# ── Signal handlers ────────────────────────────────────────────────────────────

func _on_powerup_collected(player_id: int, _powerup_type: int) -> void:
	if player_id == NetworkManager.get_unique_id():
		if not _hud_visible:
			_show()
		_sync_cards()
		_show_collect_banner(_powerup_type)

func _on_powerup_collected_network(player_id: int, _powerup_type: int) -> void:
	if player_id == NetworkManager.get_unique_id():
		if not _hud_visible:
			_show()
		_sync_cards()
		_flash_stack()

func _on_powerup_expired(player_id: int, _powerup_type: int) -> void:
	if player_id == NetworkManager.get_unique_id():
		_sync_cards()

func _on_theme_changed(_dark: bool) -> void:
	for data in _powerup_cards.values():
		_apply_card_style(data)

func _on_reading_font_changed(f: Font) -> void:
	_font = f
	for data in _powerup_cards.values():
		_apply_card_fonts(data)

# ── Per-frame update ───────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_update_spy_overlay()

	if not _hud_visible:
		return
	var player_id := NetworkManager.get_unique_id()

	var any_active := false
	for powerup_type in PowerupManager.PowerupType.values():
		if PowerupManager.has_powerup(player_id, powerup_type):
			any_active = true
			break
	if not any_active:
		_hide()
		return

	# Update timers and remove stale cards
	var to_remove: Array = []
	for powerup_type in _powerup_cards.keys():
		if not PowerupManager.has_powerup(player_id, powerup_type):
			to_remove.append(powerup_type)
			continue
		var data: Dictionary = _powerup_cards[powerup_type]
		var remaining := PowerupManager.get_remaining_time(player_id, powerup_type)
		_update_card_timer(data, remaining)

	for t in to_remove:
		_remove_card(t)

	# Add cards for newly gained powerups
	for powerup_type in PowerupManager.PowerupType.values():
		if PowerupManager.has_powerup(player_id, powerup_type):
			if not _powerup_cards.has(powerup_type):
				_add_card(powerup_type)

# ── Card management ────────────────────────────────────────────────────────────

func _sync_cards() -> void:
	var player_id := NetworkManager.get_unique_id()
	# Add missing
	for powerup_type in PowerupManager.PowerupType.values():
		if PowerupManager.has_powerup(player_id, powerup_type):
			if not _powerup_cards.has(powerup_type):
				_add_card(powerup_type)
	# Remove stale
	var to_remove: Array = []
	for powerup_type in _powerup_cards.keys():
		if not PowerupManager.has_powerup(player_id, powerup_type):
			to_remove.append(powerup_type)
	for t in to_remove:
		_remove_card(t)

func _add_card(powerup_type: int) -> void:
	var color: Color = COLORS[powerup_type]
	var duration: float = PowerupManager.POWERUP_DURATIONS[powerup_type]
	var is_timed: bool = duration > 0.0

	# ── Outer pill container ─────────────────────────────────────────────────
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(200, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var style := StyleBoxFlat.new()
	var bg: Color = ThemeManager.bg_color
	bg.a = CARD_BG_ALPHA
	style.bg_color = bg
	# Left accent bar via left border, others very thin
	style.border_width_left   = 4
	style.border_width_top    = 1
	style.border_width_right  = 1
	style.border_width_bottom = 1
	style.border_color = color
	style.set_corner_radius_all(8)
	style.shadow_color  = Color(color.r, color.g, color.b, 0.25)
	style.shadow_size   = 10
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left   = 10
	style.content_margin_right  = 10
	style.content_margin_top    = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)

	# ── Inner layout ─────────────────────────────────────────────────────────
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	#  Top row: icon + name + timer
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	top_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_child(top_row)

	var icon_lbl := Label.new()
	icon_lbl.text = ICONS[powerup_type]
	icon_lbl.add_theme_font_size_override("font_size", 18)
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.text = PowerupManager.get_powerup_name(powerup_type)
	name_lbl.add_theme_color_override("font_color", ThemeManager.text_color)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font:
		name_lbl.add_theme_font_override("font", _font)
	top_row.add_child(name_lbl)

	var timer_lbl := Label.new()
	timer_lbl.name = "TimerLabel"
	# In light mode the card bg is light so use a darkened version of the accent color.
	# In dark mode lighten it slightly. This keeps timers readable in both themes.
	var timer_color: Color = color.darkened(0.25) if not ThemeManager.is_dark_mode else color.lightened(0.15)
	timer_lbl.add_theme_color_override("font_color", timer_color)
	timer_lbl.add_theme_font_size_override("font_size", 14)
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font:
		timer_lbl.add_theme_font_override("font", _font)
	timer_lbl.visible = is_timed
	if not is_timed:
		timer_lbl.text = "READY"
		timer_lbl.visible = true
	top_row.add_child(timer_lbl)

	# Progress bar (timed powerups only)
	var bar: ProgressBar = null
	if is_timed:
		bar = ProgressBar.new()
		bar.max_value = duration
		bar.value = duration
		bar.custom_minimum_size = Vector2(0, 3)
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Style the bar track
		var bar_bg := StyleBoxFlat.new()
		bar_bg.bg_color = Color(1, 1, 1, 0.1)
		bar_bg.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", bar_bg)

		var bar_fill := StyleBoxFlat.new()
		bar_fill.bg_color = color
		bar_fill.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", bar_fill)

		vbox.add_child(bar)

	_stack.add_child(card)

	# Store card data
	var data := {
		"card": card,
		"type": powerup_type,
		"timer_label": timer_lbl,
		"bar": bar,
		"style": style,
		"duration": duration
	}
	_powerup_cards[powerup_type] = data

	# Slide in from left
	card.modulate.a = 0.0
	card.position.x = -24.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.22)
	tw.tween_property(card, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _remove_card(powerup_type: int) -> void:
	if not _powerup_cards.has(powerup_type):
		return
	var data: Dictionary = _powerup_cards[powerup_type]
	var card: Control = data["card"]
	_powerup_cards.erase(powerup_type)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 0.0, 0.18)
	tw.tween_property(card, "position:x", -24.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(card.queue_free)

func _update_card_timer(data: Dictionary, remaining: float) -> void:
	var timer_lbl: Label = data["timer_label"]
	var bar: ProgressBar = data["bar"]
	var duration: float = data["duration"]
	var color: Color = COLORS[data["type"]]

	if duration > 0.0:
		if is_instance_valid(timer_lbl):
			timer_lbl.text = _format_time(remaining)
		if is_instance_valid(bar):
			bar.value = remaining
			# Pulse to red in the last 30% of the duration (min 3s, max 10s window)
			var urgent_threshold := clampf(duration * 0.3, 3.0, 10.0)
			var t := clampf(remaining / urgent_threshold, 0.0, 1.0)
			var urgent := Color(1.0, 0.2, 0.2)
			var fill_style = bar.get_theme_stylebox("fill") as StyleBoxFlat
			if fill_style:
				fill_style.bg_color = color.lerp(urgent, 1.0 - t)

func _apply_card_style(data: Dictionary) -> void:
	var style: StyleBoxFlat = data["style"]
	var color: Color = COLORS[data["type"]]
	if style:
		var bg: Color = ThemeManager.bg_color
		bg.a = CARD_BG_ALPHA
		style.bg_color = bg
		style.border_color = color
		style.shadow_color = Color(color.r, color.g, color.b, 0.25)
	# Re-apply timer label color when theme changes
	var timer_lbl: Label = data["card"].find_child("TimerLabel", true, false)
	if timer_lbl:
		var timer_color: Color = color.darkened(0.25) if not ThemeManager.is_dark_mode else color.lightened(0.15)
		timer_lbl.add_theme_color_override("font_color", timer_color)

func _apply_card_fonts(data: Dictionary) -> void:
	if not _font:
		return
	var card: Control = data["card"]
	for lbl in _get_all_labels(card):
		lbl.add_theme_font_override("font", _font)

func _get_all_labels(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is Label:
			result.append(child)
		result.append_array(_get_all_labels(child))
	return result

# ── Collection banner ──────────────────────────────────────────────────────────
# Shown at the bottom-centre of the screen when the local player picks up a powerup.
# Uses identical StyleBoxFlat parameters to the HUD cards so it looks native.

func _show_collect_banner(powerup_type: int) -> void:
	if not is_instance_valid(_banner):
		return

	var color: Color  = COLORS[powerup_type]
	var icon:  String = ICONS[powerup_type]
	var name_str: String = PowerupManager.get_powerup_name(powerup_type)
	var desc: String = DESCRIPTIONS.get(powerup_type, "")

	# ── Card panel — same StyleBoxFlat as HUD cards ───────────────────────────
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size   = Vector2(340, 0)

	var style := StyleBoxFlat.new()
	var bg: Color = ThemeManager.bg_color
	bg.a = CARD_BG_ALPHA
	style.bg_color            = bg
	style.border_width_left   = 4
	style.border_width_top    = 1
	style.border_width_right  = 1
	style.border_width_bottom = 1
	style.border_color        = color
	style.set_corner_radius_all(8)
	style.shadow_color        = Color(color.r, color.g, color.b, 0.35)
	style.shadow_size         = 14
	style.shadow_offset       = Vector2(0, -3)   # shadow goes up since banner is at bottom
	style.content_margin_left   = 12
	style.content_margin_right  = 12
	style.content_margin_top    = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)

	# ── Inner VBox ────────────────────────────────────────────────────────────
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Top row: icon + name (matches HUD card top row)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	vbox.add_child(top_row)

	var icon_lbl := Label.new()
	icon_lbl.text = icon
	icon_lbl.add_theme_font_size_override("font_size", 22)
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.text = name_str
	name_lbl.add_theme_color_override("font_color", ThemeManager.text_color)
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font:
		name_lbl.add_theme_font_override("font", _font)
	top_row.add_child(name_lbl)

	var collected_lbl := Label.new()
	collected_lbl.text = "Collected!"
	var timer_color: Color = color.darkened(0.25) if not ThemeManager.is_dark_mode else color.lightened(0.15)
	collected_lbl.add_theme_color_override("font_color", timer_color)
	collected_lbl.add_theme_font_size_override("font_size", 13)
	collected_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font:
		collected_lbl.add_theme_font_override("font", _font)
	top_row.add_child(collected_lbl)

	# Thin accent divider (same colour as progress bar fill in HUD cards)
	var sep := PanelContainer.new()
	sep.custom_minimum_size = Vector2(0, 1)
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(color.r, color.g, color.b, 0.35)
	sep.add_theme_stylebox_override("panel", sep_style)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# Description row
	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _font:
		desc_lbl.add_theme_font_override("font", _font)
	vbox.add_child(desc_lbl)

	# ── Position at bottom centre, slightly above screen edge ─────────────────
	# We add to _banner (PRESET_BOTTOM_WIDE) and centre it horizontally.
	_banner.add_child(card)
	# Wait one frame so the card has a valid size before positioning.
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	var vp_size := get_viewport_rect().size
	card.position = Vector2(
		(vp_size.x - card.size.x) * 0.5,
		-card.size.y - 16.0
	)

	# ── Animate in from below ─────────────────────────────────────────────────
	card.modulate.a = 0.0
	var start_y := card.position.y + 20.0
	card.position.y = start_y
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.22)
	tw.tween_property(card, "position:y", card.position.y - 20.0, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# ── Hold then fade out ────────────────────────────────────────────────────
	await get_tree().create_timer(4.0).timeout
	if not is_instance_valid(card):
		return
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(card, "modulate:a", 0.0, 0.3)
	tw2.tween_property(card, "position:y", card.position.y + 12.0, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw2.chain().tween_callback(card.queue_free)

# ── Omniscience spy overlay ────────────────────────────────────────────────────
# Shown anchored to the top-right while the local player has OMNISCIENCE active.
# Lists every OTHER player with their name and active powerup icons + timers.

func _build_spy_panel() -> void:
	_spy_panel = PanelContainer.new()
	_spy_panel.name = "SpyPanel"
	_spy_panel.visible = false
	_spy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spy_panel.size_flags_horizontal = Control.SIZE_SHRINK_END

	# Anchor top-right
	_spy_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_spy_panel.offset_left   = -260.0
	_spy_panel.offset_top    = 12.0
	_spy_panel.offset_right  = -12.0
	_spy_panel.offset_bottom = 12.0  # grows downward with content

	var style := StyleBoxFlat.new()
	var bg: Color = ThemeManager.bg_color
	bg.a = 0.92
	style.bg_color = bg
	style.border_width_left   = 3
	style.border_width_top    = 1
	style.border_width_right  = 1
	style.border_width_bottom = 1
	style.border_color = Color(1.0, 0.75, 0.2)
	style.set_corner_radius_all(8)
	style.shadow_color  = Color(1.0, 0.75, 0.2, 0.2)
	style.shadow_size   = 10
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left   = 10
	style.content_margin_right  = 10
	style.content_margin_top    = 8
	style.content_margin_bottom = 8
	_spy_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_spy_panel.add_child(vbox)

	# Header row
	var header := Label.new()
	header.text = "🔮 Omniscience"
	header.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	header.add_theme_font_size_override("font_size", 12)
	if _font:
		header.add_theme_font_override("font", _font)
	vbox.add_child(header)

	_spy_list = VBoxContainer.new()
	_spy_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_spy_list)

	add_child(_spy_panel)

func _update_spy_overlay() -> void:
	var local_id := NetworkManager.get_unique_id()
	var active := PowerupManager.has_powerup(local_id, PowerupManager.PowerupType.OMNISCIENCE)

	if not active:
		if _spy_panel.visible:
			_spy_panel.visible = false
		return

	_spy_panel.visible = true

	# Rebuild list every frame (cheap for small player counts)
	for child in _spy_list.get_children():
		child.queue_free()

	var peers: Array = NetworkManager.get_player_list()
	peers = peers.filter(func(pid): return pid != local_id)
	if peers.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No other players"
		empty_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
		empty_lbl.add_theme_font_size_override("font_size", 11)
		if _font:
			empty_lbl.add_theme_font_override("font", _font)
		_spy_list.add_child(empty_lbl)
		return

	for pid in peers:
		var player_name := NetworkManager.get_player_name(pid)
		var player_color := NetworkManager.get_player_color(pid)

		# Row: player name
		var name_lbl := Label.new()
		name_lbl.text = player_name
		name_lbl.add_theme_color_override("font_color", player_color)
		name_lbl.add_theme_font_size_override("font_size", 12)
		if _font:
			name_lbl.add_theme_font_override("font", _font)
		_spy_list.add_child(name_lbl)

		# Their powerups
		var their_powerups := PowerupManager.get_player_powerups(pid)
		if their_powerups.is_empty():
			var none_lbl := Label.new()
			none_lbl.text = "  (no powerups)"
			none_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
			none_lbl.add_theme_font_size_override("font_size", 11)
			if _font:
				none_lbl.add_theme_font_override("font", _font)
			_spy_list.add_child(none_lbl)
		else:
			for pt in their_powerups:
				var icon: String = ICONS.get(pt, "?")
				var pname: String = PowerupManager.get_powerup_name(pt)
				var duration: float = PowerupManager.POWERUP_DURATIONS[pt]
				var remaining := PowerupManager.get_remaining_time(pid, pt)
				var timer_str := ""
				if duration > 0 and remaining > 0:
					timer_str = "  %s" % _format_time(remaining)
				elif duration < 0:
					timer_str = "  READY"

				var row := Label.new()
				row.text = "  %s %s%s" % [icon, pname, timer_str]
				row.add_theme_color_override("font_color", COLORS.get(pt, ThemeManager.text_color))
				row.add_theme_font_size_override("font_size", 11)
				if _font:
					row.add_theme_font_override("font", _font)
				_spy_list.add_child(row)

# ── Visibility ─────────────────────────────────────────────────────────────────

func _show() -> void:
	_hud_visible = true
	visible = true
	_stack.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_stack, "modulate:a", 1.0, 0.25)

func _hide() -> void:
	_hud_visible = false
	var tw := create_tween()
	tw.tween_property(_stack, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(func(): visible = false)

func _flash_stack() -> void:
	var tw := create_tween()
	tw.tween_property(_stack, "modulate:a", 0.5, 0.07)
	tw.tween_property(_stack, "modulate:a", 1.0, 0.15)

# ── Helpers ────────────────────────────────────────────────────────────────────

func _format_time(seconds: float) -> String:
	var s := int(seconds)
	var m := s / 60
	if m > 0:
		return "%d:%02d" % [m, s % 60]
	return "%d" % s

# ── Public API (called by Main.gd) ─────────────────────────────────────────────

## Show HUD if the local player has any active powerups.
func show_hud() -> void:
	var player_id := NetworkManager.get_unique_id()
	for pt in PowerupManager.PowerupType.values():
		if PowerupManager.has_powerup(player_id, pt):
			if not _hud_visible:
				_show()
			return

## Hide the HUD unconditionally (e.g. when minimap mode switches to hidden).
func hide_hud() -> void:
	_hide()

## Toggle HUD visibility (bound to P key in Main.gd).
func toggle() -> void:
	if _hud_visible:
		_hide()
	else:
		show_hud()
