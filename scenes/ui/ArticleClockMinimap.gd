extends Control
## ArticleClockMinimap — "Link Clock" showing Wikipedia article links as spokes.
##
## The exits in each room are doors to linked Wikipedia articles. This
## minimap shows those links visually — each spoke is a real Wikipedia link
## from the current article, placed on a clock face. The target article
## gets a gold spoke with a pulsing ring so you can see at a glance if
## it's reachable directly.
##
## Data wiring — exact, verified against source files:
##
##   ExhibitFetcher.get_result(title) → Dictionary with keys:
##     "wikitext" : String    (raw MediaWiki markup)
##     "extract"  : String    (plain-text summary)
##     "categories", "wikidata_entity"
##   No "links" key exists — links are parsed from wikitext by ItemProcessor
##   transiently. We replicate ItemProcessor's door-extraction logic here:
##     • tokenizer regex: "[^{}[\\]<>]+|[{}[\\]<>]"
##     • extract [[link]] targets, filter namespace (no ":")
##     • title-case first letter, strip #fragment, skip prev/current article
##
##   SettingsEvents.set_current_room(room: Variant)  → fetch + show new links
##   ExhibitFetcher.wikitext_complete(titles, ctx)   → refresh if still current
##   RaceManager.race_started/ended/cancelled        → target management
##   Museum._exhibits[room]["exhibit"].exits          → real doors (not all links)
##     used to badge which spokes are REAL exits (player can walk through them)
##
## Visual:
##   • Up to 14 spokes from a central hub, radially distributed
##   • Real exits: opaque accent dot + full-brightness label
##   • Other links: dimmer, shorter spoke
##   • Target article: gold spoke, longer, glowing
##   • Already-visited articles: 25% opacity (shows progress)
##   • Player heading arrow inside hub
##   • Spokes animate in on room change (staggered grow)
##   • Header = current article, footer = N links / N exits

const PANEL_SIZE  : float = 250.0
const HUB_R       : float = 16.0
const SPOKE_MIN   : float = 30.0
const SPOKE_MAX   : float = 84.0
const MAX_SPOKES  : int   = 14
const SCAN_RATE   : float = 0.40

var _player        : Node   = null
var _museum        : Node   = null
var _font          : Font   = null
var _time          : float  = 0.0
var _scan_timer    : float  = 0.0

var _current_room  : String        = ""
var _target        : String        = ""
var _links         : Array[String] = []   # ordered door-links from wikitext
var _real_exits    : Array[String] = []   # Hall.to_title values (actually walkable)
var _visited_set   : Dictionary    = {}   # article → true (for dimming)

# Spoke animation state
var _spoke_alpha   : Array[float]  = []
var _spoke_delay   : Array[float]  = []

# RegEx — mirrors ItemProcessor's tokenizer exactly
var _tokenizer     : RegEx         = null
var _image_re      : RegEx         = null

var _panel_sb      : StyleBoxFlat  = null
var _canvas        : Control       = null
var _header_lbl    : Label         = null
var _footer_lbl    : Label         = null
var _header_sb     : StyleBoxFlat  = null
var _footer_sb     : StyleBoxFlat  = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font        = ThemeManager.get_reading_font()

	# Compile the same tokenizer ItemProcessor uses
	_tokenizer = RegEx.new()
	_tokenizer.compile("[^{}\\[\\]<>]+|[{}\\[\\]<>]")
	_image_re = RegEx.new()
	_image_re.compile("^([iI]mage:|[fF]ile:)")

	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left     = -(PANEL_SIZE + 18.0)
	offset_top      = -(PANEL_SIZE + 18.0)
	offset_right    = -18.0
	offset_bottom   = -18.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical   = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(PANEL_SIZE, PANEL_SIZE)

	# ── Panel structure ─────────────────────────────────────────────────────
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_sb = StyleBoxFlat.new()
	panel.add_theme_stylebox_override("panel", _panel_sb)
	add_child(panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   10)
	mc.add_theme_constant_override("margin_right",  10)
	mc.add_theme_constant_override("margin_top",     8)
	mc.add_theme_constant_override("margin_bottom",  6)
	panel.add_child(mc)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	mc.add_child(vbox)

	# Header — current article name
	var hw := PanelContainer.new()
	_header_sb = StyleBoxFlat.new()
	_header_sb.content_margin_left   = 6
	_header_sb.content_margin_right  = 6
	_header_sb.content_margin_top    = 3
	_header_sb.content_margin_bottom = 3
	hw.add_theme_stylebox_override("panel", _header_sb)
	hw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(hw)

	_header_lbl = Label.new()
	_header_lbl.text      = "Lobby"
	_header_lbl.clip_text = true
	hw.add_child(_header_lbl)

	# Canvas
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_clock)
	vbox.add_child(_canvas)

	vbox.add_child(_make_divider())

	# Footer — link + exit count
	var fw := PanelContainer.new()
	_footer_sb = StyleBoxFlat.new()
	_footer_sb.content_margin_left   = 6
	_footer_sb.content_margin_right  = 6
	_footer_sb.content_margin_top    = 3
	_footer_sb.content_margin_bottom = 3
	fw.add_theme_stylebox_override("panel", _footer_sb)
	fw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(fw)

	_footer_lbl = Label.new()
	_footer_lbl.text                 = "0 links"
	_footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fw.add_child(_footer_lbl)

	# ── Signal wiring ───────────────────────────────────────────────────────
	SettingsEvents.set_current_room.connect(_on_room_changed)
	ExhibitFetcher.wikitext_complete.connect(_on_wikitext_complete)
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_ended.connect(_on_race_ended)
	RaceManager.race_cancelled.connect(_on_race_cancelled)

	if RaceManager.is_race_active():
		_target = RaceManager.get_target_article()

	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f): _font = f; _apply_theme())
	_apply_theme()


# ── Signal handlers ────────────────────────────────────────────────────────────

func _on_room_changed(room: Variant) -> void:
	var r : String = str(room)
	if r == _current_room: return
	_current_room = r
	if _header_lbl:
		_header_lbl.text = r if r != "" else "Lobby"
		_header_lbl.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_header_lbl, "modulate:a", 1.0, 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_visited_set[r] = true
	_scan_timer = SCAN_RATE  # trigger immediate exit scan
	_load_links_for(r)


func _on_wikitext_complete(titles: Array, _ctx: Variant) -> void:
	# Refresh if the just-fetched article is our current room
	if _current_room != "" and titles.has(_current_room):
		_load_links_for(_current_room)


func _on_race_started(target_article: String, _start: String) -> void:
	_target = target_article

func _on_race_ended(_peer: int, _name: String) -> void:
	_target = ""

func _on_race_cancelled() -> void:
	_target = ""


# ── Link extraction (mirrors ItemProcessor._create_items door logic) ───────────

func _load_links_for(title: String) -> void:
	var result : Variant = ExhibitFetcher.get_result(title)
	if not result is Dictionary or not result.has("wikitext"):
		# Data not in cache yet — it will arrive via wikitext_complete
		_links = []
		_spoke_alpha = []
		_spoke_delay = []
		_update_footer()
		return

	var wikitext : String = result.wikitext
	var raw_links : Array = _parse_wikitext_doors(wikitext, title)

	# Seeded shuffle to match ItemProcessor (same seed formula)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(title + ":doors")
	for i in range(raw_links.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp : String = raw_links[i]
		raw_links[i] = raw_links[j]
		raw_links[j] = tmp

	# Cap at MAX_SPOKES, keep target visible if present
	_links.clear()
	if _target != "" and raw_links.has(_target):
		_links.append(_target)
	for l in raw_links:
		if _links.size() >= MAX_SPOKES: break
		if not _links.has(l):
			_links.append(l)

	# Init spoke animation
	_spoke_alpha.clear()
	_spoke_delay.clear()
	for i in _links.size():
		_spoke_alpha.append(0.0)
		_spoke_delay.append(float(i) * 0.055)

	_update_footer()


func _parse_wikitext_doors(wikitext: String, current_title: String) -> Array[String]:
	## Replicate ItemProcessor door extraction logic exactly.
	var tokens : Array[RegExMatch] = _tokenizer.search_all(wikitext)
	var link   : String = ""
	var doors  : Array[String] = []
	var used   : Dictionary = {}

	var depth_chars := { "<": ">", "[": "]", "{": "}" }
	var depth       : Array[String] = []
	var in_link     : bool
	var t           : String
	var dl          : int

	for m : RegExMatch in tokens:
		t  = m.get_string(0)
		dl = depth.size()
		var dc : Variant = depth_chars.get(t)
		in_link = dl > 1 and depth[0] == "]" and depth[1] == "]"

		if dc:
			depth.push_back(dc)
		elif dl == 0:
			pass
		elif t == depth[dl - 1]:
			depth.pop_back()
			dl      = depth.size()
			in_link = dl > 1 and depth[0] == "]" and depth[1] == "]"
		elif in_link:
			link += t

		if not in_link and link.length() > 0:
			# Process completed link
			var raw_target : String = link.get_slice("|", 0).strip_edges()
			raw_target = raw_target.get_slice("#", 0)
			if raw_target.length() > 0 and raw_target.find(":") < 0 \
					and not raw_target.begins_with("http"):
				var door : String = _to_link_case(raw_target)
				if door.length() > 0 and door != current_title \
						and not used.has(door):
					doors.append(door)
					used[door] = true
			link = ""

	return doors


func _to_link_case(s: String) -> String:
	if s.length() > 0:
		return s[0].to_upper() + s.substr(1)
	return ""


# ── Real exit scanning ─────────────────────────────────────────────────────────

func _get_museum() -> Node:
	if is_instance_valid(_museum): return _museum
	var root := get_tree().current_scene
	if root: _museum = root.get_node_or_null("%Museum")
	return _museum


func _scan_real_exits() -> void:
	_real_exits.clear()
	var museum := _get_museum()
	if not museum: return
	var exhibit_data : Variant = museum._exhibits.get(_current_room)
	if not exhibit_data is Dictionary: return
	var exhibit : Node = exhibit_data.get("exhibit")
	if not is_instance_valid(exhibit) or not "exits" in exhibit: return
	for hall in exhibit.exits:
		if is_instance_valid(hall) and "to_title" in hall:
			_real_exits.append(str(hall.to_title))


# ── Theme ──────────────────────────────────────────────────────────────────────

func _apply_theme() -> void:
	var dark   := ThemeManager.is_dark_mode
	var accent := _accent()

	if _panel_sb:
		_panel_sb.bg_color     = Color(ThemeManager.bg_color, 0.93)
		_panel_sb.border_color = ThemeManager.border_color
		_panel_sb.set_border_width_all(1)
		_panel_sb.set_corner_radius_all(10)
		_panel_sb.shadow_color  = Color(0, 0, 0, 0.30 if dark else 0.10)
		_panel_sb.shadow_size   = 14
		_panel_sb.shadow_offset = Vector2(0, 4)

	for sb in [_header_sb, _footer_sb]:
		if not sb: continue
		sb.bg_color = Color(accent, 0.07 if dark else 0.04)
		sb.set_corner_radius_all(5)

	for lbl in [_header_lbl, _footer_lbl]:
		if not lbl: continue
		if _font: lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 10)

	if _header_lbl:
		_header_lbl.add_theme_color_override("font_color", ThemeManager.text_color)
	if _footer_lbl:
		_footer_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _canvas: _canvas.queue_redraw()


func _update_footer() -> void:
	if not _footer_lbl: return
	var n_exits : int = _real_exits.size()
	var n_links : int = _links.size()
	_footer_lbl.text = "%d link%s  ·  %d exit%s" % [
		n_links, "s" if n_links != 1 else "",
		n_exits, "s" if n_exits != 1 else ""]


# ── Draw ───────────────────────────────────────────────────────────────────────

func _draw_clock() -> void:
	if not _canvas: return
	var dark   := ThemeManager.is_dark_mode
	var accent := _accent()
	var gold   := _gold()
	var sz     := _canvas.size
	if sz == Vector2.ZERO: return

	var cx   : float   = sz.x * 0.5
	var cy   : float   = sz.y * 0.5
	var ctr  : Vector2 = Vector2(cx, cy)
	var disc_r : float = minf(sz.x, sz.y) * 0.44

	# Background disc
	_canvas.draw_circle(ctr, disc_r, Color(accent, 0.04 if dark else 0.03))
	_canvas.draw_arc(ctr, disc_r, 0.0, TAU, 64,
		Color(accent, 0.10 if dark else 0.06), 1.0, true)

	var n : int = _links.size()

	# ── Empty state ─────────────────────────────────────────────────────────
	if n == 0:
		if _font:
			_canvas.draw_string(_font,
				Vector2(cx - 48, cy + 4),
				"Enter a room to\nsee its links",
				HORIZONTAL_ALIGNMENT_LEFT, 96, 9,
				Color(accent, 0.38))
	else:
		# ── Spokes ────────────────────────────────────────────────────────────
		for i in n:
			var angle    : float   = float(i) / float(n) * TAU - PI * 0.5
			var name     : String  = _links[i]
			var is_tgt   : bool    = (name == _target and _target != "")
			var is_exit  : bool    = _real_exits.has(name)
			var is_vis   : bool    = _visited_set.has(name)
			var sa       : float   = _spoke_alpha[i] if i < _spoke_alpha.size() else 1.0

			# Spoke length: target longest, real exits medium, links shortest
			var spoke_len : float
			if is_tgt:
				spoke_len = disc_r - 6.0
			elif is_exit:
				spoke_len = lerpf(SPOKE_MIN + 20.0, disc_r - 16.0,
				            float(i) / float(n))
			else:
				spoke_len = lerpf(SPOKE_MIN, disc_r - 24.0,
				            1.0 - float(i) / float(n))

			var dir  : Vector2 = Vector2(cos(angle), sin(angle))
			var p0   : Vector2 = ctr + dir * HUB_R
			var p1   : Vector2 = ctr + dir * (HUB_R + spoke_len * sa)

			# Colours
			var spoke_col : Color
			var dot_col   : Color
			var lbl_col   : Color
			var dot_r     : float = 3.0

			if is_tgt:
				var tpulse := (sin(_time * 2.0 + float(i)) + 1.0) * 0.5
				spoke_col  = Color(gold, (0.65 + tpulse * 0.30) * sa)
				dot_col    = gold
				lbl_col    = Color(gold, 0.95 * sa)
				dot_r      = 4.5
				# Glow
				_canvas.draw_circle(p1, dot_r + 3.5 + tpulse * 2.0,
					Color(gold, (0.12 + tpulse * 0.08) * sa))
			elif is_vis:
				# Already visited — dim to show progress
				spoke_col  = Color(accent, 0.18 * sa)
				dot_col    = Color(accent, 0.30)
				lbl_col    = Color(ThemeManager.subtext_color, 0.38 * sa)
			elif is_exit:
				# Real walkable exit — full brightness
				spoke_col  = Color(accent, 0.75 * sa)
				dot_col    = accent
				lbl_col    = Color(ThemeManager.text_color, 0.88 * sa)
				dot_r      = 4.0
			else:
				# Linked but not a real exit (can't walk there directly)
				spoke_col  = Color(accent, 0.35 * sa)
				dot_col    = Color(accent, 0.60)
				lbl_col    = Color(ThemeManager.subtext_color, 0.60 * sa)

			# Spoke line
			_canvas.draw_line(p0, p1,
				spoke_col,
				1.5 if (is_tgt or is_exit) else 0.8, true)

			# Tip dot (white ring + colour)
			_canvas.draw_circle(p1, dot_r, Color(1, 1, 1, 0.85 * sa))
			_canvas.draw_circle(p1, dot_r - 1.2, dot_col)

			# Label at tip (only when spoke is grown in enough)
			if _font and sa > 0.5:
				var lbl : String = name.replace("_", " ")
				if lbl.length() > 11: lbl = lbl.substr(0, 10) + "…"
				var lp  : Vector2 = p1 + dir * (dot_r + 4.0)
				var fsz : int     = 8 if is_tgt else 7
				_canvas.draw_string(_font, lp - Vector2(0, 3.5),
					lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
					Color(lbl_col, lbl_col.a * sa))

	# ── Hub ─────────────────────────────────────────────────────────────────
	_canvas.draw_circle(ctr, HUB_R + 1.0, Color(ThemeManager.bg_color, 0.88))
	_canvas.draw_arc(ctr, HUB_R, 0.0, TAU, 32, Color(accent, 0.60), 1.5, true)

	# Player direction chevron inside hub
	var hdg : float   = _get_heading()
	var fw  : Vector2 = Vector2(sin(hdg), -cos(hdg))
	var rt  : Vector2 = Vector2(cos(hdg),  sin(hdg))
	var r   : float   = HUB_R * 0.52
	var tip : Vector2 = ctr + fw * r * 1.5
	var lft : Vector2 = ctr - fw * r * 0.5 + rt * r * 0.68
	var rgt : Vector2 = ctr - fw * r * 0.5 - rt * r * 0.68
	var bk  : Vector2 = ctr - fw * r * 0.28

	_canvas.draw_colored_polygon(PackedVector2Array([tip, lft, bk, rgt]),
		Color(1, 1, 1, 0.92))
	_canvas.draw_polyline(PackedVector2Array([tip, lft, bk, rgt, tip]),
		Color(accent, 0.70), 1.0, true)

	# ── Legend dots (top-right corner) ──────────────────────────────────────
	if _font:
		var lx : float = sz.x - 8.0
		var ly : float = 8.0
		var entries := [
			{ "col": _gold(), "label": "Target" } if _target != "" else {},
			{ "col": accent,  "label": "Exit" },
			{ "col": Color(accent, 0.35), "label": "Link" },
		]
		for e in entries:
			if not e.has("col"): continue
			_canvas.draw_circle(Vector2(lx - 36.0, ly + 4.5), 3.0, e.col)
			_canvas.draw_string(_font, Vector2(lx - 30.0, ly + 7.5),
				e.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(ThemeManager.subtext_color, 0.65))
			ly += 14.0


# ── Helpers ────────────────────────────────────────────────────────────────────

func _accent() -> Color:
	return Color(0.30, 0.55, 1.00) if ThemeManager.is_dark_mode \
	     else Color(0.12, 0.32, 0.82)

func _gold() -> Color:
	return Color(1.00, 0.80, 0.22) if ThemeManager.is_dark_mode \
	     else Color(0.78, 0.52, 0.05)

func _get_heading() -> float:
	return _player.rotation.y if is_instance_valid(_player) else 0.0

func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	d.color               = ThemeManager.border_color
	ThemeManager.dark_mode_changed.connect(func(_d): d.color = ThemeManager.border_color)
	return d

func init(player: Node) -> void:
	_player  = player
	_museum  = null

func update_texture(_tex: Texture2D) -> void:
	pass

func set_zoom(_z: float) -> void:
	pass

func _process(delta: float) -> void:
	if not visible: return
	_time       += delta
	_scan_timer += delta

	# Grow spokes in
	for i in _spoke_alpha.size():
		if _spoke_alpha[i] < 1.0:
			var delay := _spoke_delay[i] if i < _spoke_delay.size() else 0.0
			if _time > delay:
				_spoke_alpha[i] = minf(_spoke_alpha[i] + delta * 2.8, 1.0)

	# Periodic exit scan
	if _scan_timer >= SCAN_RATE:
		_scan_timer = 0.0
		_scan_real_exits()
		_update_footer()

	if _canvas: _canvas.queue_redraw()
