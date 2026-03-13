extends Node
## Service locator pattern - centralized access to game services.
## Replaces deep node access like get_node("/root/Main/Museum/ExhibitLoader")

# Service references (set in Main.gd _ready())
var game_state: GameState = null
var exhibit_service: Node = null
var race_service: Node = null
var network_service: Node = null
var room_service: Node = null

func _ready() -> void:
	# Services are initialized by Main.gd
	pass

# --- Initialization ---

func initialize() -> void:
	"""Initialize all services. Call from Main.gd _ready()."""
	game_state = GameState.new()
	
	# Create room service (will be fully initialized later)
	room_service = preload("res://scenes/services/RoomService.gd").new()
	room_service.name = "RoomService"
	add_child(room_service)
	
	# Create network service
	network_service = preload("res://scenes/services/NetworkService.gd").new()
	network_service.name = "NetworkService"
	add_child(network_service)
	network_service.initialize()
	
	# Create exhibit service (will be initialized with museum reference)
	exhibit_service = preload("res://scenes/services/ExhibitService.gd").new()
	exhibit_service.name = "ExhibitService"
	add_child(exhibit_service)
	
	# Create race service
	race_service = preload("res://scenes/services/RaceService.gd").new()
	race_service.name = "RaceService"
	add_child(race_service)
	race_service.initialize()

# --- Convenience Accessors ---

func get_state() -> GameState:
	return game_state

func get_exhibit() -> Node:
	return exhibit_service

func get_race() -> Node:
	return race_service

func get_network() -> Node:
	return network_service

func get_room() -> Node:
	return room_service

# --- Service Queries ---

func is_server() -> bool:
	if network_service:
		return network_service.is_server()
	return false

func is_multiplayer_active() -> bool:
	if network_service:
		return network_service.is_multiplayer_active()
	return false

func get_local_peer_id() -> int:
	if network_service:
		return network_service.get_local_peer_id()
	return 1
