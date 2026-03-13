extends Node
class_name ExhibitService
## Manages exhibit lifecycle: loading, unloading, caching, and preloading.
## Provides a clean API for exhibit operations without coupling to Museum.

signal exhibit_loaded(title: String)
signal exhibit_unloaded(title: String)
signal exhibit_load_failed(title: String, error: String)

var _loaded_exhibits: Dictionary = {}  # title -> exhibit_node
var _loading_queue: Array[String] = []
var _max_loaded_exhibits: int = 10
var _museum: Node = null
var _exhibit_loader: Node = null

func _ready() -> void:
	pass

func initialize(museum: Node, exhibit_loader: Node) -> void:
	"""Initialize with museum and exhibit loader references."""
	_museum = museum
	_exhibit_loader = exhibit_loader
	print("ExhibitService: Initialized with max ", _max_loaded_exhibits, " exhibits")

# --- Loading ---

func load_exhibit(title: String, from_room: String = "Lobby") -> void:
	"""Load an exhibit asynchronously."""
	if not _museum or not _exhibit_loader:
		print("ExhibitService: ERROR - Not initialized!")
		return
	
	if _loaded_exhibits.has(title):
		print("ExhibitService: Exhibit '", title, "' already loaded")
		exhibit_loaded.emit(title)
		return
	
	if _loading_queue.has(title):
		print("ExhibitService: Exhibit '", title, "' already loading")
		return
	
	print("ExhibitService: Loading exhibit '", title, "'")
	_loading_queue.append(title)
	
	# Use exhibit loader
	_exhibit_loader.load_exhibit_for_rider(from_room, title)
	
	# Note: exhibit_loaded will be emitted when Museum signals exhibit creation

func unload_exhibit(title: String) -> void:
	"""Unload an exhibit to free memory."""
	if not _loaded_exhibits.has(title):
		return
	
	print("ExhibitService: Unloading exhibit '", title, "'")
	
	var exhibit = _loaded_exhibits[title]
	if is_instance_valid(exhibit):
		exhibit.queue_free()
	
	_loaded_exhibits.erase(title)
	exhibit_unloaded.emit(title)

# --- Preloading ---

func preload_adjacent_exhibits(current_room: String) -> void:
	"""Preload exhibits adjacent to current room for smoother transitions."""
	if not _exhibit_loader or not _exhibit_loader.has_method("get_adjacent_exhibits"):
		return
	
	var adjacent: Array[String] = _exhibit_loader.get_adjacent_exhibits(current_room)
	for title in adjacent:
		if not _loaded_exhibits.has(title) and not _loading_queue.has(title):
			load_exhibit(title, current_room)

func preload_from_backlinks(backlinks: Array[String]) -> void:
	"""Preload exhibits from backlink list."""
	for title in backlinks:
		if not _loaded_exhibits.has(title) and not _loading_queue.has(title):
			load_exhibit(title)

# --- Queries ---

func is_exhibit_loaded(title: String) -> bool:
	return _loaded_exhibits.has(title)

func is_exhibit_loading(title: String) -> bool:
	return _loading_queue.has(title)

func get_loaded_exhibits() -> Array[String]:
	return _loaded_exhibits.keys()

func get_loaded_exhibit_count() -> int:
	return _loaded_exhibits.size()

func get_loading_count() -> int:
	return _loading_queue.size()

# --- Cache Management ---

func clear_cache() -> void:
	"""Unload all exhibits except the current room."""
	for title in _loaded_exhibits.keys():
		unload_exhibit(title)
	_loading_queue.clear()

func trim_cache(max_count: int = -1) -> void:
	"""Unload oldest exhibits if over limit."""
	var limit = max_count if max_count > 0 else _max_loaded_exhibits
	
	while _loaded_exhibits.size() > limit:
		var oldest_title = _loaded_exhibits.keys()[0]
		unload_exhibit(oldest_title)

# --- Event Handlers ---

func _on_exhibit_created(title: String, exhibit_node: Node) -> void:
	"""Called by Museum when an exhibit is created."""
	_loaded_exhibits[title] = exhibit_node
	_loading_queue.erase(title)
	print("ExhibitService: Exhibit '", title, "' created")
	exhibit_loaded.emit(title)
	
	# Trim cache if needed
	call_deferred("trim_cache")

func _on_exhibit_load_failed(title: String, error: String) -> void:
	"""Called when exhibit loading fails."""
	_loading_queue.erase(title)
	print("ExhibitService: Failed to load '", title, "': ", error)
	exhibit_load_failed.emit(title, error)

# --- Cleanup ---

func _exit_tree() -> void:
	clear_cache()
