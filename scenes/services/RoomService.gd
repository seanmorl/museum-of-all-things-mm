extends Node
class_name RoomService
## Manages room generation, caching, and network synchronization.
## Server generates rooms once and broadcasts to all clients.
## Clients receive and load identical rooms from serialized data.

signal room_generated(data: RoomData)
signal room_loaded(title: String)
signal room_sync_started(title: String)
signal room_sync_completed(title: String)

var _room_cache: Dictionary = {}  # title -> RoomData
var _loading_rooms: Dictionary = {}  # title -> true (currently loading)
var _exhibit_loader: Node = null
var _museum: Node = null

func _ready() -> void:
	# Will be initialized by Main.gd
	pass

func initialize(museum: Node, exhibit_loader: Node) -> void:
	"""Initialize with references to Museum and ExhibitLoader."""
	_museum = museum
	_exhibit_loader = exhibit_loader

# --- Server: Generate Room ---

func generate_room(title: String) -> RoomData:
	"""Generate a room on the server. Returns RoomData for broadcasting."""
	print("RoomService: Generating room '", title, "'")

	var data = RoomData.create(title, hash(title))

	# Store in cache
	_room_cache[title] = data

	room_generated.emit(data)
	return data

func populate_room_data(data: RoomData, wikipedia_data: Dictionary, _backlinks: Array = []) -> void:
	"""Populate RoomData with fetched Wikipedia data."""
	data.wikipedia_data = wikipedia_data
	# Note: Backlinks are no longer used for door injection - they're only for hints
	print("RoomService: Populated room data for '", data.title, "'")

# --- Server: Broadcast Room ---

func broadcast_room(data: RoomData) -> void:
	"""Broadcast room data to all clients via RPC."""
	if not NetworkManager.is_multiplayer_active():
		return

	print("RoomService: Broadcasting room '", data.title, "' to all clients")
	_sync_room_data.rpc(data.to_var())

	# Load locally on server (don't wait for RPC)
	load_room_from_data(data)

@rpc("authority", "call_local", "reliable")
func _sync_room_data(data_var: Variant) -> void:
	"""RPC handler - clients receive room data from server."""
	var data = RoomData.from_var(data_var)
	print("RoomService: Received room data for '", data.title, "'")

	load_room_from_data(data)

# --- Client: Load Room from Data ---

func load_room_from_data(data: RoomData) -> void:
	"""Load a room from serialized RoomData (called on clients)."""
	if data.title in _loading_rooms:
		print("RoomService: Room '", data.title, "' already loading")
		return

	# Check if museum is initialized
	if not _museum:
		print("RoomService: ERROR - Museum not initialized!")
		return

	if _museum.has_exhibit(data.title):
		print("RoomService: Room '", data.title, "' already loaded")
		room_loaded.emit(data.title)
		return

	_loading_rooms[data.title] = true
	room_sync_started.emit(data.title)

	# Store room data in cache for exhibit loader to use
	_room_cache[data.title] = data

	# Trigger exhibit loading
	# The exhibit loader will check _room_cache for pre-loaded data
	if _exhibit_loader and _exhibit_loader.has_method("load_exhibit_from_room_data"):
		_exhibit_loader.load_exhibit_from_room_data(data)
	else:
		# Fallback to normal loading (will use cached data)
		_museum.load_exhibit_for_rider("Lobby", data.title)

# --- Queries ---

func has_room_data(title: String) -> bool:
	return _room_cache.has(title)

func get_room_data(title: String) -> RoomData:
	return _room_cache.get(title, null)

func clear_cache() -> void:
	_room_cache.clear()
	_loading_rooms.clear()

func get_cache_size() -> int:
	return _room_cache.size()

# --- Cleanup ---

func _exit_tree() -> void:
	clear_cache()
