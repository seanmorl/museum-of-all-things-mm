extends Node
## Persistent explorer's journal. Auto-logs exhibit visits, supports pinning,
## tagging, notes, and race records.
##
## Visit entry shape:
##   title:        String
##   type:         "visit"
##   snippet:      String
##   timestamp:    int      (unix, first visit)
##   last_visited: int      (unix, most recent visit)
##   visit_count:  int
##   pinned_items: Array    [{type, caption, url?, excerpt?}]
##   note:         String
##   tags:         Array[String]
##
## Race entry shape:
##   title:        String   (target article)
##   type:         "race"
##   timestamp:    int      (first race against this target)
##   last_visited: int      (most recent race)
##   note:         String
##   tags:         Array[String]
##   pinned_items: Array
##   runs:         Array    [{won, time_secs, timestamp, start_article, hops}]
##   pb_secs:      int      (personal best time, -1 if no wins)

signal entry_added(entry: Dictionary)
signal entry_updated(title: String)
signal item_pinned(title: String, item: Dictionary)

const MAX_ENTRIES: int     = 500
const JOURNAL_NS: String   = "journal"
const JOURNAL_FILE: String = "user://journal.json"

var _entries: Array        = []   # newest-first
var _entry_map: Dictionary = {}   # title -> index (rebuilt after mutations)


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
	var won: bool        = (winner_peer_id == NetworkManager.get_unique_id())
	var target: String   = RaceManager.get_target_article()
	var elapsed: int     = int(RaceManager.get_final_time())
	var start: String    = RaceManager.get_start_article() if RaceManager.has_method("get_start_article") else ""
	if target != "":
		record_race(target, won, elapsed, start)


# ─── Public API ───────────────────────────────────────────────────────────────

func add_visit(title: String) -> void:
	if _entry_map.has(title):
		var idx: int = _entry_map[title]
		var e: Dictionary = _entries[idx]
		# Don't update visit stats on race-only entries; promote to shared entry
		if e.get("type", "visit") == "visit":
			e.visit_count  = e.get("visit_count", 1) + 1
			e.last_visited = Time.get_unix_time_from_system()
			if e.get("snippet", "") == "":
				_try_fill_snippet(e)
			_save()
			entry_updated.emit(title)
			return
		# If existing entry is a race entry, convert to visit and preserve runs
		e["type"]         = "visit"
		e["visit_count"]  = 1
		e["last_visited"] = Time.get_unix_time_from_system()
		if e.get("snippet", "") == "":
			_try_fill_snippet(e)
		_save()
		entry_updated.emit(title)
		return

	var entry: Dictionary = {
		"title":        title,
		"type":         "visit",
		"snippet":      "",
		"timestamp":    Time.get_unix_time_from_system(),
		"last_visited": Time.get_unix_time_from_system(),
		"visit_count":  1,
		"pinned_items": [],
		"note":         "",
		"tags":         [],
	}
	_try_fill_snippet(entry)
	_entries.push_front(entry)
	_rebuild_map()
	_prune()
	_save()
	entry_added.emit(entry)


func record_race(target: String, won: bool, time_secs: int, start_article: String = "") -> void:
	var run: Dictionary = {
		"won":           won,
		"time_secs":     time_secs,
		"timestamp":     Time.get_unix_time_from_system(),
		"start_article": start_article,
	}

	if _entry_map.has(target):
		var idx: int       = _entry_map[target]
		var e: Dictionary  = _entries[idx]
		# Ensure runs array exists (migrate old race entries)
		if not e.has("runs"):
			if e.get("type") == "race" and e.has("race"):
				# Migrate legacy single-race format
				var old: Dictionary = e.race
				e["runs"] = [{
					"won":           old.get("won", false),
					"time_secs":     old.get("time_secs", 0),
					"timestamp":     e.get("timestamp", 0),
					"start_article": "",
				}]
				e.erase("race")
			else:
				e["runs"] = []
		e.runs.push_front(run)
		e.last_visited = run.timestamp
		e["type"]      = "race"
		_update_pb(e)
		_save()
		entry_updated.emit(target)
		return

	var entry: Dictionary = {
		"title":        target,
		"type":         "race",
		"snippet":      "",
		"timestamp":    Time.get_unix_time_from_system(),
		"last_visited": Time.get_unix_time_from_system(),
		"pinned_items": [],
		"note":         "",
		"tags":         [],
		"runs":         [run],
		"pb_secs":      time_secs if won else -1,
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
	var idx: int    = _entry_map[title]
	var t: String   = tag.strip_edges().to_lower()
	var tags: Array = _entries[idx].get("tags", [])
	if t != "" and not t in tags:
		tags.append(t)
		_entries[idx]["tags"] = tags
		_save()
		entry_updated.emit(title)


func remove_tag(title: String, tag: String) -> void:
	if not _entry_map.has(title):
		return
	var idx: int    = _entry_map[title]
	var tags: Array = _entries[idx].get("tags", [])
	tags.erase(tag.strip_edges().to_lower())
	_entries[idx]["tags"] = tags
	_save()
	entry_updated.emit(title)


func refresh_snippets() -> void:
	## Back-fills empty snippets AND upgrades previously truncated ones using
	## the ExhibitFetcher cache (no network call).
	var changed: bool = false
	for e: Dictionary in _entries:
		if e.get("type", "visit") != "visit":
			continue
		var result: Variant = ExhibitFetcher.get_result(e.get("title", ""))
		if not result or not result.has("extract") or result.extract == "":
			continue
		var current: String = e.get("snippet", "")
		var full: String = result.extract
		# Update if empty OR if cache has more text than what's stored
		if current == "" or full.length() > current.length():
			e["snippet"] = full
			changed = true
	if changed:
		_save()


# ─── Query ────────────────────────────────────────────────────────────────────

func get_entries() -> Array:
	return _entries.duplicate()


func get_entries_filtered(type_filter: String = "") -> Array:
	if type_filter == "":
		return _entries.duplicate()
	return _entries.filter(func(e): return e.get("type", "visit") == type_filter)


func get_entries_sorted(mode: String) -> Array:
	## mode: "recent" | "alpha" | "most_visited" | "pb"
	var arr: Array = _entries.duplicate()
	match mode:
		"alpha":
			arr.sort_custom(func(a, b): return a.title.to_lower() < b.title.to_lower())
		"most_visited":
			arr.sort_custom(func(a, b):
				return a.get("visit_count", 1) > b.get("visit_count", 1))
		"pb":
			arr.sort_custom(func(a, b):
				var ta: int = a.get("pb_secs", 999999)
				var tb: int = b.get("pb_secs", 999999)
				if ta == -1: ta = 999999
				if tb == -1: tb = 999999
				return ta < tb)
		_:  # "recent" — already newest-first
			pass
	return arr


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
	var visits: int = 0
	var pins:   int = 0
	var notes:  int = 0
	var won:    int = 0
	var lost:   int = 0
	var total_visit_count: int = 0
	for e: Dictionary in _entries:
		match e.get("type", "visit"):
			"visit":
				visits += 1
				total_visit_count += e.get("visit_count", 1)
				pins  += e.get("pinned_items", []).size()
				if e.get("note", "") != "": notes += 1
			"race":
				for run: Dictionary in e.get("runs", []):
					if run.get("won", false): won  += 1
					else:                     lost += 1
	return {
		"visits":            visits,
		"total_visit_count": total_visit_count,
		"pins":              pins,
		"notes":             notes,
		"races_won":         won,
		"races_lost":        lost,
	}


func export_markdown(entries: Array = []) -> String:
	## Serialises entries to Markdown. Pass a filtered subset or leave empty for all.
	if entries.is_empty():
		entries = _entries
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Explorer's Journal")
	lines.append("")
	var stats: Dictionary = get_stats()
	lines.append("> %d visits · %d races (%dW/%dL) · %d pins" % [
		stats.visits, stats.races_won + stats.races_lost,
		stats.races_won, stats.races_lost, stats.pins])
	lines.append("")
	for e: Dictionary in entries:
		lines.append("## %s" % e.title)
		if e.get("type", "visit") == "race":
			for run: Dictionary in e.get("runs", []):
				var result: String = "✅ Win" if run.get("won", false) else "❌ Loss"
				var secs: int = run.get("time_secs", 0)
				lines.append("- %s  %02d:%02d  %s" % [result, secs / 60, secs % 60,
					Time.get_date_string_from_unix_time(run.get("timestamp", 0))])
		else:
			var date_str: String = Time.get_date_string_from_unix_time(
				int(e.get("timestamp", 0)))
			lines.append("*First visited: %s · %d visits*" % [
				date_str, e.get("visit_count", 1)])
			if e.get("snippet", "") != "":
				lines.append("")
				lines.append(e.snippet.substr(0, 200))
			if e.get("note", "") != "":
				lines.append("")
				lines.append("> 📝 %s" % e.note)
			if not e.get("tags", []).is_empty():
				lines.append("")
				lines.append("Tags: " + ", ".join(e.tags))
		lines.append("")
	return "\n".join(lines)


# ─── Private ──────────────────────────────────────────────────────────────────

func _try_fill_snippet(entry: Dictionary) -> bool:
	var result: Variant = ExhibitFetcher.get_result(entry.get("title", ""))
	if result and result.has("extract") and result.extract != "":
		entry["snippet"] = result.extract  # full extract, no cap
		return true
	return false

func fetch_full_article_text(title: String) -> void:
	"""Fetch full article text for journal display (uses exlimit=max)"""
	var url: String = ExhibitFetcher.wikitext_endpoint + title.uri_encode() + "&exlimit=max"
	ExhibitFetcher._dispatch_request(url, {"title": title, "full_text": true}, null)


func _update_pb(entry: Dictionary) -> void:
	var best: int = -1
	for run: Dictionary in entry.get("runs", []):
		if run.get("won", false):
			var t: int = run.get("time_secs", 999999)
			if best == -1 or t < best:
				best = t
	entry["pb_secs"] = best


func _rebuild_map() -> void:
	_entry_map.clear()
	for i: int in _entries.size():
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
		_normalise_entry(e)
		_entries.append(e)
	_rebuild_map()


func _normalise_entry(e: Dictionary) -> void:
	if not e.has("type"):         e["type"]         = "visit"
	if not e.has("note"):         e["note"]         = ""
	if not e.has("tags"):         e["tags"]         = []
	if not e.has("pinned_items"): e["pinned_items"] = []
	if not e.has("snippet"):      e["snippet"]      = ""
	# Migrate legacy single-run race format
	if e.get("type") == "race" and e.has("race") and not e.has("runs"):
		var old: Dictionary = e.race
		e["runs"] = [{
			"won":           old.get("won", false),
			"time_secs":     old.get("time_secs", 0),
			"timestamp":     e.get("timestamp", 0),
			"start_article": "",
		}]
		e.erase("race")
	if not e.has("runs") and e.get("type") == "race":
		e["runs"] = []
	if not e.has("pb_secs") and e.get("type") == "race":
		_update_pb(e)


func _migrate_from_settings() -> void:
	var data: Variant = SettingsManager.get_settings(JOURNAL_NS)
	if not data is Dictionary or not data.has("entries"):
		return
	_entries.clear()
	for e: Variant in data.entries:
		if not e is Dictionary:
			continue
		_normalise_entry(e)
		_entries.append(e)
	_entries.reverse()
	_rebuild_map()
	_save()


func _save() -> void:
	var file: FileAccess = FileAccess.open(JOURNAL_FILE, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify({"entries": _entries}, "\t"))
	file.close()
