extends Node
## Service locator pattern - centralized access to game services.
##
## ⚠️ ARCHITECTURE DECISION (2026-04-05):
## This service layer is ARCHIVED. We use autoload singletons directly instead.
##
## WHY:
## - Services are thin wrappers that just delegate to autoloads
## - Creates confusion: two ways to do the same thing
## - Adds indirection with no functional benefit
## - Autoloads are the standard Godot pattern
##
## WHAT TO USE INSTEAD:
##   NetworkManager.is_server()     # NOT Services.get_network().is_server()
##   RaceManager.start_race(...)    # NOT Services.get_race().start_race(...)
##   StickyNoteManager.create(...)  # NOT Services.get_sticky_notes().create(...)
##
## See: docs/ARCHITECTURE_DECISIONS.md for full rationale
##
## This file is kept for backward compatibility but should NOT be used in new code.
## Eventually move scenes/services/ to _archived_services_OLD/

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
	# NOTE: Services are archived - these preloads point to archived location for backward compatibility
	room_service = preload("res://scenes/_archived_services_OLD/RoomService.gd").new()
	room_service.name = "RoomService"
	add_child(room_service)

	# Create network service
	network_service = preload("res://scenes/_archived_services_OLD/NetworkService.gd").new()
	network_service.name = "NetworkService"
	add_child(network_service)
	network_service.initialize()

	# Create exhibit service (will be initialized with museum reference)
	exhibit_service = preload("res://scenes/_archived_services_OLD/ExhibitService.gd").new()
	exhibit_service.name = "ExhibitService"
	add_child(exhibit_service)

	# Create race service
	race_service = preload("res://scenes/_archived_services_OLD/RaceService.gd").new()
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
