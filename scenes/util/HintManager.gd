extends Node
class_name HintManagerClass
## Manages backlink hints for the race system.
## Tracks which rooms link to the target and provides hint functionality.

signal backlinks_loaded(target: String, backlinks: Array[String])
signal hint_revealed(hint: String)

# Backlink cache: target -> [rooms that link to target]
var _backlink_cache: Dictionary = {}

# Current race target
var _current_target: String = ""

# Hints given tracking
var _hints_given: Array[String] = []
var _max_hints: int = 5

func _ready() -> void:
	add_to_group("main")  # So ItemProcessor can find us

# --- Backlink Management ---

func set_current_target(target: String) -> void:
	"""Set the current race target and clear hint tracking."""
	_current_target = target
	_hints_given.clear()
	
	if not _backlink_cache.has(target):
		_backlink_cache[target] = []

func set_backlinks(target: String, backlinks: Array[String]) -> void:
	"""Store backlinks for a target article."""
	_backlink_cache[target] = backlinks
	_current_target = target
	backlinks_loaded.emit(target, backlinks)
	Log.info("HintManager", "Stored %d backlinks for '%s'" % [backlinks.size(), target])

func get_backlinks(target: String) -> Array[String]:
	"""Get cached backlinks for a target."""
	return _backlink_cache.get(target, [])

func has_backlinks(target: String) -> bool:
	"""Check if backlinks are cached for a target."""
	return _backlink_cache.has(target) and _backlink_cache[target].size() > 0

func clear_backlinks(target: String) -> void:
	"""Clear backlinks for a specific target."""
	_backlink_cache.erase(target)

func clear_all_backlinks() -> void:
	"""Clear all cached backlinks."""
	_backlink_cache.clear()
	_current_target = ""
	_hints_given.clear()

# --- Hint Queries ---

func is_backlink_of(target: String, door: String) -> bool:
	"""
	Check if a door (room) is a backlink of the target.
	Returns true if 'door' article links to 'target' article.
	
	This is the key function for door injection - if a room is a backlink
	of the target, we prioritize it during door generation.
	"""
	if not _backlink_cache.has(target):
		return false
	
	var backlinks: Array[String] = _backlink_cache[target]
	return backlinks.has(door)

func get_next_hint() -> String:
	"""
	Get the next hint for the current target.
	Returns a room name that links to the target.
	Returns empty string if no hints available or max hints reached.
	"""
	if _current_target == "":
		return ""
	
	if not _backlink_cache.has(_current_target):
		return ""
	
	var backlinks: Array[String] = _backlink_cache[_current_target]
	if backlinks.size() == 0:
		return ""
	
	# Filter out already-given hints
	var available_hints: Array[String] = []
	for backlink in backlinks:
		if not _hints_given.has(backlink):
			available_hints.append(backlink)
	
	if available_hints.size() == 0:
		return ""
	
	# Check max hints
	if _hints_given.size() >= _max_hints:
		return ""
	
	# Pick next hint (could be random or sequential)
	var hint: String = available_hints[0]
	_hints_given.append(hint)
	
	return hint

func get_all_hints() -> Array[String]:
	"""Get all available hints for current target (up to max)."""
	if _current_target == "":
		return []
	
	if not _backlink_cache.has(_current_target):
		return []
	
	var backlinks: Array[String] = _backlink_cache[_current_target]
	var hints: Array[String] = []
	
	for i in range(min(backlinks.size(), _max_hints)):
		hints.append(backlinks[i])
	
	return hints

func get_hints_given_count() -> int:
	"""Return number of hints already given."""
	return _hints_given.size()

func get_hints_remaining_count() -> int:
	"""Return number of hints remaining."""
	if _current_target == "":
		return 0
	if not _backlink_cache.has(_current_target):
		return 0
	var backlinks: Array[String] = _backlink_cache[_current_target]
	return max(0, backlinks.size() - _hints_given.size())

# --- Network Sync (Multiplayer) ---

func reveal_hint_to_all(hint: String) -> void:
	"""Reveal a hint to all players (called by server)."""
	if not NetworkManager.is_server():
		return
	
	if hint == "":
		return
	
	_reveal_hint.rpc(hint)
	hint_revealed.emit(hint)

@rpc("authority", "call_local", "reliable")
func _reveal_hint(hint: String) -> void:
	"""RPC handler - all clients receive hint."""
	Log.info("HintManager", "Hint revealed: '%s'" % hint)
	# Hint is shown via chat/system message in Main.gd

# --- Utility ---

func get_current_target() -> String:
	"""Get the current race target."""
	return _current_target

func is_hint_system_ready() -> bool:
	"""Check if hint system is ready to provide hints."""
	return _current_target != "" and has_backlinks(_current_target)

# --- Debug ---

func _to_string() -> String:
	return "HintManager(target=%s, backlinks=%d, hints_given=%d)" % [
		_current_target,
		_backlink_cache.size(),
		_hints_given.size()
	]
