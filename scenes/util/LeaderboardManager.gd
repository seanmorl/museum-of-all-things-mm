extends Node
## Tracks race winners for the current session (in-memory, resets on quit).
## Autoload as "LeaderboardManager" in Project Settings > Autoload.
##
## Each entry stores: winner_name, target_article, time_seconds, timestamp.
## Connect to leaderboard_updated to refresh any UI.

signal leaderboard_updated

const MAX_ENTRIES: int = 50

var _entries: Array[Dictionary] = []


func _ready() -> void:
	RaceManager.race_ended.connect(_on_race_ended)


func _on_race_ended(winner_peer_id: int, winner_name: String) -> void:
	add_entry(winner_name, RaceManager.get_target_article(), RaceManager.get_elapsed_time())


func add_entry(winner_name: String, target_article: String, time_seconds: float) -> void:
	var entry: Dictionary = {
		"winner_name": winner_name,
		"target_article": target_article,
		"time_seconds": time_seconds,
		"time_string": _format_time(time_seconds),
		"timestamp": Time.get_unix_time_from_system(),
	}
	_entries.push_front(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.resize(MAX_ENTRIES)
	leaderboard_updated.emit()


## Returns all entries, most recent first.
func get_entries() -> Array[Dictionary]:
	return _entries


## Returns the top N entries sorted by fastest time.
func get_top_entries(count: int = 10) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = _entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["time_seconds"] < b["time_seconds"]
	)
	return sorted.slice(0, count)


func get_win_counts() -> Dictionary:
	var counts: Dictionary = {}
	for entry: Dictionary in _entries:
		var name: String = entry["winner_name"]
		counts[name] = counts.get(name, 0) + 1
	return counts


func clear() -> void:
	_entries.clear()
	leaderboard_updated.emit()


func _format_time(seconds: float) -> String:
	var s: int = int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]
