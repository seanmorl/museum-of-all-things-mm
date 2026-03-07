extends Node
## Persistent explorer's journal. Auto-logs exhibit visits, supports pinning,
## tagging, notes, and race records.
##
## Entry shape:
##   title:        String
##   type:         String   "visit" | "race"  (absent on old data → treated as "visit")
##   snippet:      String   (first ~200 chars of article extract)
##   timestamp:    int      (unix, first visit)
##   last_visited: int      (unix, most recent visit)
##   visit_count:  int
##   pinned_items: Array    [{type, caption, url?, excerpt?}]
##   note:         String   (free-text player note)
##   tags:         Array[String]
##   race:         Dictionary  (only on type=="race")
##                   { won:bool, target:String, time_secs:int }

signal entry_added(entry: Dictionary)
signal entry_updated(title: String)
signal item_pinned(title: String, item: Dictionary)

const MAX_ENTRIES: int     = 500
const JOURNAL_NS: String   = "journal"        # legacy SettingsManager key
const JOURNAL_FILE: String = "user://journal.json"

var _entries: Array      = []   # newest-first
var _entry_map: Dictionary = {} # title -> index (rebuilt after any mutation)


func _ready() -> void:
	_load()
	SettingsEvents.set_current_room.connect(_on_room_changed)
	RaceManager.race_ended.connect(_on_race_ended)


# ─── Auto-hooks ───────────────────────────────────────────────────────────────

func _on_room_changed(title: String) -> void:
	if title == "Lobby" or title.is_empty():
		return
	add_visit(title)


func _on_race_ended(winner_peer_id: int, _winner_name: String) -> void:
	var won: bool      = (winner_peer_id == NetworkManager.get_unique_id())
	var target: String = RaceManager.get_target_article()
	var elapsed: int   = int(RaceManager.get_final_time())  # preserved after race ends
	if target != "":
		record_race(target, won, elapsed)


# ─── Public API ───────────────────────────────────────────────────────────────

func add_visit(title: String) -> void:
	if _entry_map.has(title):
		var idx: int = _entry_map[title]
		_entries[idx].visit_count = _entries[idx].get("visit_count", 1) + 1
		_entries[idx].last_visited = Time.get_unix_time_from_system()
		# Refresh empty snippet now that the exhibit may be loaded
		if _entries[idx].get("snippet", "") == "":
			var result: Variant = ExhibitFetcher.get_result(title)
			if result and result.has("extract"):
				_entries[idx].snippet = result.extract.substr(0, 200)
		_save()
		entry_updated.emit(title)
		return

	var snippet: String = ""
	var result: Variant = ExhibitFetcher.get_result(title)
	if result and result.has("extract"):
		snippet = result.extract.substr(0, 200)

	var entry: Dictionary = {
		"title":        title,
		"type":         "visit",
		"snippet":      snippet,
		"timestamp":    Time.get_unix_time_from_system(),
		"last_visited": Time.get_unix_time_from_system(),
		"visit_count":  1,
		"pinned_items": [],
		"note":         "",
		"tags":         [],
	}

	_entries.push_front(entry)
	_rebuild_map()
	_prune()
	_save()
	entry_added.emit(entry)


func record_race(target: String, won: bool, time_secs: int) -> void:
	var entry: Dictionary = {
		"title":        target,
		"type":         "race",
		"snippet":      "",
		"timestamp":    Time.get_unix_time_from_system(),
		"last_visited": Time.get_unix_time_from_system(),
		"visit_count":  1,
		"pinned_items": [],
		"note":         "",
		"tags":         [],
		"race":         {"won": won, "target": target, "time_secs": time_secs},
	}
	_entries.push_front(entry)
	_rebuild_map()
	_prune()
	_save()
	entry_added.emit(entry)


func pin_item(exhibit_title: String, item_type: String, item_data: Dictionary) -> void:
	if not _entry_map.has(exhibit_title):
		add_visit(exhibit_title)
	var idx: int = _entry_map[exhibit_title]
	var pinned: Dictionary = {
		"type":    item_type,
		"caption": item_data.get("caption", ""),
	}
	if item_type == "image":
		pinned["url"] = item_data.get("url", "")
	elif item_type == "text":
		pinned["excerpt"] = item_data.get("excerpt", "").substr(0, 300)
	_entries[idx].pinned_items.append(pinned)
	if _entries[idx].pinned_items.size() > 20:
		_entries[idx].pinned_items = _entries[idx].pinned_items.slice(-20)
	_save()
	item_pinned.emit(exhibit_title, pinned)


func set_note(title: String, note_text: String) -> void:
	if not _entry_map.has(title):
		add_visit(title)
	_entries[_entry_map[title]]["note"] = note_text
	_save()
	entry_updated.emit(title)


func add_tag(title: String, tag: String) -> void:
	if not _entry_map.has(title):
		add_visit(title)
	var idx: int = _entry_map[title]
	var t: String = tag.strip_edges().to_lower()
	var tags: Array = _entries[idx].get("tags", [])
	if t != "" and not t in tags:
		tags.append(t)
		_entries[idx]["tags"] = tags
		_save()
		entry_updated.emit(title)


func remove_tag(title: String, tag: String) -> void:
	if not _entry_map.has(title):
		return
	var idx: int = _entry_map[title]
	var tags: Array = _entries[idx].get("tags", [])
	tags.erase(tag.strip_edges().to_lower())
	_entries[idx]["tags"] = tags
	_save()
	entry_updated.emit(title)


# ─── Query ────────────────────────────────────────────────────────────────────

func get_entries() -> Array:
	return _entries.duplicate()


func get_entries_filtered(type_filter: String = "") -> Array:
	if type_filter == "":
		return _entries.duplicate()
	return _entries.filter(func(e): return e.get("type", "visit") == type_filter)


func search(query: String) -> Array:
	var q: String = query.to_lower().strip_edges()
	if q == "":
		return _entries.duplicate()
	return _entries.filter(func(e: Dictionary) -> bool:
		if q in e.get("title",   "").to_lower(): return true
		if q in e.get("snippet", "").to_lower(): return true
		if q in e.get("note",    "").to_lower(): return true
		for tag: String in e.get("tags", []):
			if q in tag: return true
		return false
	)


func get_entry(title: String) -> Variant:
	if _entry_map.has(title):
		return _entries[_entry_map[title]]
	return null


func get_entry_count() -> int:
	return _entries.size()


func get_all_tags() -> Array:
	var tag_set: Dictionary = {}
	for e: Dictionary in _entries:
		for tag: String in e.get("tags", []):
			tag_set[tag] = true
	var tags: Array = tag_set.keys()
	tags.sort()
	return tags


func get_stats() -> Dictionary:
	var visits: int     = 0
	var pins:   int     = 0
	var notes:  int     = 0
	var won:    int     = 0
	var lost:   int     = 0
	for e: Dictionary in _entries:
		match e.get("type", "visit"):
			"visit":
				visits += 1
				pins   += e.get("pinned_items", []).size()
				if e.get("note", "") != "": notes += 1
			"race":
				if e.get("race", {}).get("won", false): won  += 1
				else:                                   lost += 1
	return {"visits": visits, "pins": pins, "notes": notes, "races_won": won, "races_lost": lost}


# ─── Private ──────────────────────────────────────────────────────────────────

func _rebuild_map() -> void:
	_entry_map.clear()
	for i: int in _entries.size():
		# Map points to first (newest) occurrence of each title
		if not _entry_map.has(_entries[i].title):
			_entry_map[_entries[i].title] = i


func _prune() -> void:
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_back()
	_rebuild_map()


func _load() -> void:
	if FileAccess.file_exists(JOURNAL_FILE):
		_load_from_file()
	else:
		_migrate_from_settings()


func _load_from_file() -> void:
	var file: FileAccess = FileAccess.open(JOURNAL_FILE, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_entries.clear()
	for e: Variant in parsed.get("entries", []):
		if not e is Dictionary:
			continue
		if not e.has("type"):         e["type"]         = "visit"
		if not e.has("note"):         e["note"]         = ""
		if not e.has("tags"):         e["tags"]         = []
		if not e.has("pinned_items"): e["pinned_items"] = []
		_entries.append(e)
	_rebuild_map()


func _migrate_from_settings() -> void:
	## One-time migration: SettingsManager → dedicated file.
	var data: Variant = SettingsManager.get_settings(JOURNAL_NS)
	if not data is Dictionary or not data.has("entries"):
		return
	_entries.clear()
	for e: Variant in data.entries:
		if not e is Dictionary:
			continue
		if not e.has("type"):         e["type"]         = "visit"
		if not e.has("note"):         e["note"]         = ""
		if not e.has("tags"):         e["tags"]         = []
		if not e.has("pinned_items"): e["pinned_items"] = []
		_entries.append(e)
	# Old data was oldest-first; reverse to newest-first
	_entries.reverse()
	_rebuild_map()
	_save()


func _save() -> void:
	var file: FileAccess = FileAccess.open(JOURNAL_FILE, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify({"entries": _entries}, "\t"))
	file.close()
