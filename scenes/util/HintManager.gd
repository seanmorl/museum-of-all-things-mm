extends Node
class_name HintManagerClass
## Manages backlink hints for the race system.
## Shows articles that link TO the target (validated to exclude navbox/template links).

signal hints_loaded(target: String)
signal hint_revealed(hint: String, hint_type: String)

# Hint caches
var _backlink_cache: Dictionary = {}  # target String -> Array[String] of backlinks

# Current race target
var _current_target: String = ""

# Hints given tracking
var _hints_given: Array[String] = []
var _max_hints: int = 5

func _ready() -> void:
	add_to_group("main")

# --- Target Management ---

func set_current_target(target: String) -> void:
	"""Set the current race target and clear hint tracking."""
	_current_target = target
	_hints_given.clear()
	if not _backlink_cache.has(target):
		_backlink_cache[target] = []

func set_backlinks(target: String, backlinks: Array[String]) -> void:
	"""Store validated backlinks for a target article."""
	_backlink_cache[target] = backlinks
	_current_target = target
	print("HintManager: Emitting hints_loaded for '%s' with %d backlinks" % [target, backlinks.size()])
	hints_loaded.emit(_current_target)
	Log.info("HintManager", "Stored %d backlinks for '%s'" % [backlinks.size(), target])

func get_backlinks(target: String) -> Array:
	if _backlink_cache.has(target):
		return _backlink_cache[target]
	return []

func get_current_target() -> String:
	return _current_target

func has_hints() -> bool:
	"""Check if any hints are available."""
	var backlinks = _backlink_cache.get(_current_target, [])
	return backlinks.size() > 0

func clear_all_hints() -> void:
	"""Clear all cached hints."""
	_backlink_cache.clear()
	_current_target = ""
	_hints_given.clear()

# --- Hint Queries ---

func get_next_hint() -> Array:  # Returns [hint_text, hint_type]
	"""Get the next backlink hint."""
	if _current_target == "":
		return ["", ""]

	var backlinks: Array[String] = _backlink_cache.get(_current_target, [])
	
	if backlinks.size() == 0:
		return ["", ""]
	
	# Find next unused backlink
	for backlink in backlinks:
		if not _hints_given.has(backlink):
			if _hints_given.size() >= _max_hints:
				return ["", ""]
			_hints_given.append(backlink)
			return [backlink, "backlink"]
	
	return ["", ""]

func get_hints_given_count() -> int:
	return _hints_given.size()

func get_hints_remaining_count() -> int:
	if _current_target == "":
		return 0
	var backlinks: Array[String] = _backlink_cache.get(_current_target, [])
	return max(0, backlinks.size() - _hints_given.size())

# --- Network Sync (Multiplayer) ---

func reveal_hint_to_all(hint: String, hint_type: String = "backlink") -> void:
	"""Reveal a hint to all players (called by server)."""
	if not NetworkManager.is_server():
		return

	if hint == "":
		return

	_reveal_hint.rpc(hint, hint_type)
	hint_revealed.emit(hint, hint_type)

@rpc("authority", "call_local", "reliable")
func _reveal_hint(hint: String, hint_type: String) -> void:
	"""RPC handler - all clients receive hint."""
	Log.info("HintManager", "Hint revealed: '%s' (%s)" % [hint, hint_type])
	
	# Show hint to player via chat HUD
	var main = get_node_or_null("/root/Main")
	if main and main.has_node("TabMenu/ChatHUD"):
		main.get_node("TabMenu/ChatHUD")._show_system_message("💡 Hint: Try visiting '%s'" % hint)
	else:
		# Fallback: show as a one-shot message
		var hud = get_tree().root.find_child("ChatHUD", true, false)
		if hud and hud.has_method("_show_system_message"):
			hud._show_system_message("💡 Hint: Try visiting '%s'" % hint)

# --- Utility ---

func is_hint_system_ready() -> bool:
	"""Check if hint system is ready to provide hints."""
	return _current_target != "" and has_hints()

# --- Debug ---

func _to_string() -> String:
	var bl = _backlink_cache.get(_current_target, []).size()
	return "HintManager(target=%s, backlinks=%d, hints_given=%d)" % [
		_current_target,
		bl,
		_hints_given.size()
	]
