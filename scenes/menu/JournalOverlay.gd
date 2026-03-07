extends Control
class_name JournalOverlay
## Wikipedia-style overlay showing journal entries, search, filter tabs, and stats.

signal closed

const ENTRIES_PER_PAGE: int = 5
const WIKI_BLUE: String  = "#0645ad"
const WIKI_GRAY: String  = "#54595d"
const WIKI_GREEN: String = "#006400"
const WIKI_RED: String   = "#8b0000"
const HEADING_RULE: String = "[color=#a2a9b1]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]"

# Filter modes
enum Filter { ALL, VISITS, PINNED, RACES }

var _current_page: int   = 0
var _is_open: bool       = false
var _current_filter: int = Filter.ALL
var _search_query: String = ""
var _active_entries: Array = []  # entries currently shown (post-filter/search)

# Scene nodes (paths match JournalOverlay.tscn exactly)
@onready var _panel:      PanelContainer = $PanelContainer
@onready var _content:    RichTextLabel  = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/ContentLabel
@onready var _page_label: Label          = $PanelContainer/MarginContainer/VBoxContainer/NavHBox/PageLabel
@onready var _prev_btn:   Button         = $PanelContainer/MarginContainer/VBoxContainer/NavHBox/PrevBtn
@onready var _next_btn:   Button         = $PanelContainer/MarginContainer/VBoxContainer/NavHBox/NextBtn
@onready var _close_btn:  Button         = $PanelContainer/MarginContainer/VBoxContainer/HeaderHBox/CloseBtn

# Built in code — added to existing containers
var _search_field:  LineEdit     = null
var _filter_bar:    HBoxContainer = null
var _filter_btns:   Array        = []
var _stats_label:   Label        = null


func _ready() -> void:
	visible = false
	_prev_btn.pressed.connect(_prev_page)
	_next_btn.pressed.connect(_next_page)
	_close_btn.pressed.connect(close)

	_build_search_bar()
	_build_filter_bar()
	_build_stats_label()

	JournalManager.entry_added.connect(_on_journal_changed)
	JournalManager.entry_updated.connect(_on_journal_changed)


# ─── Layout helpers (injected into existing scene containers) ─────────────────

func _build_search_bar() -> void:
	## Insert a search LineEdit into the HeaderHBox, left of the CloseBtn.
	var header: HBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/HeaderHBox
	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Search journal…"
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_field.clear_button_enabled = true
	# Insert before CloseBtn (which is the last child)
	header.add_child(_search_field)
	header.move_child(_search_field, header.get_child_count() - 2)  # before CloseBtn
	_search_field.text_changed.connect(_on_search_changed)
	_search_field.text_submitted.connect(_on_search_changed)


func _build_filter_bar() -> void:
	## Insert a filter tab row between SubtitleLabel and HSeparator.
	var vbox: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer
	var sep_idx: int = -1
	for i: int in vbox.get_child_count():
		if vbox.get_child(i).name == "HSeparator":
			sep_idx = i
			break

	_filter_bar = HBoxContainer.new()
	_filter_bar.name = "FilterBar"
	_filter_bar.add_theme_constant_override("separation", 4)
	vbox.add_child(_filter_bar)
	if sep_idx >= 0:
		vbox.move_child(_filter_bar, sep_idx + 1)

	var labels: Array = ["All", "Visits", "Pinned", "Races"]
	for i: int in labels.size():
		var btn: Button = Button.new()
		btn.text = labels[i]
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)
		btn.custom_minimum_size = Vector2(70, 0)
		btn.pressed.connect(_on_filter_pressed.bind(i, btn))
		_filter_bar.add_child(btn)
		_filter_btns.append(btn)


func _build_stats_label() -> void:
	## Small stats summary above the content, after the filter bar.
	var vbox: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer
	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	_stats_label.add_theme_font_size_override("font_size", 12)
	_stats_label.add_theme_color_override("font_color", Color(0.33, 0.35, 0.37))
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Insert just after the filter bar
	var filter_idx: int = _filter_bar.get_index()
	vbox.add_child(_stats_label)
	vbox.move_child(_stats_label, filter_idx + 1)


# ─── Open / close ─────────────────────────────────────────────────────────────

func toggle() -> void:
	if _is_open: close()
	else:        open()


func open() -> void:
	_is_open = true
	visible  = true
	_search_field.text = ""
	_search_query      = ""
	_current_filter    = Filter.ALL
	_set_filter_btn(Filter.ALL)
	_current_page = 0
	_refresh()
	_search_field.grab_focus()
	_panel.scale      = Vector2(0.88, 0.88)
	_panel.modulate.a = 0.0
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale",      Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0,               0.25)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale",      Vector2(0.88, 0.88), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "modulate:a", 0.0,                 0.18)
	tw.chain().tween_callback(func():
		_panel.scale      = Vector2(1.0, 1.0)
		_panel.modulate.a = 1.0
		visible           = false
		closed.emit()
	)


func is_open() -> bool:
	return _is_open


# ─── Event handlers ───────────────────────────────────────────────────────────

func _on_search_changed(text: String) -> void:
	_search_query = text.strip_edges()
	_current_page = 0
	_refresh()


func _on_filter_pressed(filter_idx: int, btn: Button) -> void:
	_current_filter = filter_idx
	_set_filter_btn(filter_idx)
	_current_page = 0
	_refresh()


func _set_filter_btn(active: int) -> void:
	for i: int in _filter_btns.size():
		_filter_btns[i].button_pressed = (i == active)


func _on_journal_changed(_arg = null) -> void:
	if _is_open:
		_refresh()


# ─── Pagination ───────────────────────────────────────────────────────────────

func _max_page() -> int:
	if _active_entries.is_empty():
		return 0
	return maxi(0, (_active_entries.size() - 1) / ENTRIES_PER_PAGE)


func _prev_page() -> void:
	_current_page = maxi(0, _current_page - 1)
	_refresh()


func _next_page() -> void:
	_current_page = mini(_max_page(), _current_page + 1)
	_refresh()


# ─── Content refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	# 1. Get filtered + searched entries
	var base: Array
	match _current_filter:
		Filter.VISITS:  base = JournalManager.get_entries_filtered("visit")
		Filter.RACES:   base = JournalManager.get_entries_filtered("race")
		Filter.PINNED:
			base = JournalManager.get_entries().filter(
				func(e): return e.get("pinned_items", []).size() > 0
			)
		_:
			base = JournalManager.get_entries()

	if _search_query != "":
		var q: String = _search_query.to_lower()
		base = base.filter(func(e: Dictionary) -> bool:
			if q in e.get("title",   "").to_lower(): return true
			if q in e.get("snippet", "").to_lower(): return true
			if q in e.get("note",    "").to_lower(): return true
			for tag: String in e.get("tags", []):
				if q in tag: return true
			return false
		)

	_active_entries = base
	_current_page   = mini(_current_page, _max_page())

	# 2. Stats bar
	var stats: Dictionary = JournalManager.get_stats()
	_stats_label.text = "%d visits · %d pinned · %d races (%dW/%dL)" % [
		stats.visits, stats.pins,
		stats.races_won + stats.races_lost, stats.races_won, stats.races_lost
	]

	# 3. Pagination controls
	var total: int = _active_entries.size()
	var start: int = _current_page * ENTRIES_PER_PAGE
	var end:   int = mini(start + ENTRIES_PER_PAGE, total)
	_page_label.text = "Page %d of %d" % [_current_page + 1, _max_page() + 1]
	_prev_btn.disabled = (_current_page <= 0)
	_next_btn.disabled = (_current_page >= _max_page())

	# 4. Body text
	var text: String = ""
	if total == 0:
		if _search_query != "":
			text += "[i][color=%s]No entries match \"%s\".[/color][/i]\n" % [WIKI_GRAY, _search_query]
		else:
			text += "[i][color=%s]No entries yet. Visit an exhibit to begin your journal.[/color][/i]\n" % WIKI_GRAY
	else:
		# Intro line
		var filter_word: String = ["entries", "visits", "pinned entries", "races"][_current_filter]
		text += "[color=%s][i]%d %s" % [WIKI_GRAY, total, filter_word]
		if _search_query != "":
			text += " matching \"%s\"" % _search_query
		text += ". Showing %d–%d.[/i][/color]\n\n" % [start + 1, end]

		# Contents box
		if end - start > 1:
			text += "[font_size=18][b]Contents[/b][/font_size]\n"
			for i: int in range(start, end):
				var entry: Dictionary = _active_entries[i]
				var icon: String = "★ " if entry.get("type","visit") == "race" else ""
				text += "  %d  [color=%s]%s%s[/color]\n" % [i - start + 1, WIKI_BLUE, icon, entry.title]
			text += "\n"

		# Entries
		for i: int in range(start, end):
			text += _format_entry(_active_entries[i])

	_content.text = ""
	_content.append_text(text)
	# Scroll back to top on page change
	await get_tree().process_frame
	if is_instance_valid(_content):
		var sc: ScrollContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer
		sc.scroll_vertical = 0


# ─── Entry formatter ──────────────────────────────────────────────────────────

func _format_entry(entry: Dictionary) -> String:
	var type: String = entry.get("type", "visit")
	var out:  String = ""

	if type == "race":
		return _format_race_entry(entry)

	# ── Visit entry ──
	var date_str: String  = Time.get_datetime_string_from_unix_time(int(entry.get("timestamp", 0)))
	var visit_count: int  = entry.get("visit_count", 1)

	out += "[font_size=22][color=#000000]%s[/color][/font_size]\n" % entry.title
	out += HEADING_RULE + "\n"

	# Metadata
	var meta: PackedStringArray = PackedStringArray()
	meta.append("First visited: %s" % date_str.substr(0, 10))
	if visit_count > 1:
		meta.append("Visited %d×" % visit_count)
		var last_str: String = Time.get_datetime_string_from_unix_time(int(entry.get("last_visited", 0)))
		meta.append("Last: %s" % last_str.substr(0, 10))
	var tags: Array = entry.get("tags", [])
	if not tags.is_empty():
		meta.append("Tags: " + ", ".join(tags))
	out += "[font_size=14][color=%s]%s[/color][/font_size]\n" % [WIKI_GRAY, " · ".join(meta)]

	# Snippet (highlight search query)
	var snippet: String = entry.get("snippet", "")
	if snippet != "":
		out += "\n"
		var display: String = snippet.substr(0, 200) + ("..." if snippet.length() > 200 else "")
		if _search_query != "":
			display = _highlight(display, _search_query)
		out += display + "\n"

	# Player note
	var note: String = entry.get("note", "")
	if note != "":
		out += "\n[font_size=14][color=%s][i]📝 %s[/i][/color][/font_size]\n" % [WIKI_GRAY, note]

	# Pinned items
	var pins: Array = entry.get("pinned_items", [])
	if not pins.is_empty():
		out += "\n[font_size=16][b]Pinned items (%d)[/b][/font_size]\n" % pins.size()
		for pin: Dictionary in pins:
			if pin.type == "image":
				var caption: String = pin.get("caption", "untitled")
				out += "  [color=%s]🖼 Image[/color] — %s\n" % [WIKI_BLUE, caption]
			elif pin.type == "text":
				var excerpt: String = pin.get("excerpt", "")
				if excerpt.length() > 120:
					excerpt = excerpt.substr(0, 120) + "..."
				out += "  [color=%s]📄 Text[/color] — %s\n" % [WIKI_BLUE, excerpt]

	out += "\n"
	return out


func _format_race_entry(entry: Dictionary) -> String:
	var race: Dictionary = entry.get("race", {})
	var won: bool        = race.get("won", false)
	var secs: int        = race.get("time_secs", 0)
	var time_str: String = "%02d:%02d" % [secs / 60, secs % 60]
	var date_str: String = Time.get_datetime_string_from_unix_time(int(entry.get("timestamp", 0)))
	var result_color: String = WIKI_GREEN if won else WIKI_RED
	var result_word:  String = "Victory" if won else "Defeat"

	var out: String = ""
	out += "[font_size=22][color=#000000]%s[/color][/font_size]\n" % entry.title
	out += HEADING_RULE + "\n"
	out += "[font_size=14][color=%s]%s[/color][/font_size]\n" % [WIKI_GRAY, date_str.substr(0, 10)]
	out += "\n"
	out += "[font_size=18][color=%s][b]%s[/b][/color][/font_size]" % [result_color, result_word]
	out += "  [color=%s]Time: %s[/color]\n" % [WIKI_GRAY, time_str]
	out += "\n"
	return out


func _highlight(text: String, query: String) -> String:
	## Wraps first occurrence of query (case-insensitive) in bold blue.
	var lower: String = text.to_lower()
	var q: String     = query.to_lower()
	var idx: int      = lower.find(q)
	if idx < 0:
		return text
	var before: String = text.substr(0, idx)
	var match:  String = text.substr(idx, query.length())
	var after:  String = text.substr(idx + query.length())
	return "%s[color=%s][b]%s[/b][/color]%s" % [before, WIKI_BLUE, match, after]


# ─── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	# Don't intercept typing when search field is focused
	if _search_field and _search_field.has_focus():
		if event.is_action_pressed("ui_cancel"):
			_search_field.release_focus()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("strafe_left") or event.is_action_pressed("move_forward"):
		_prev_page()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("strafe_right") or event.is_action_pressed("move_back"):
		_next_page()
		get_viewport().set_input_as_handled()
