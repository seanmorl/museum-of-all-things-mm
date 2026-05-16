extends Node
class_name MuseumMultiplayerSync
## Handles multiplayer transition requests and synchronization between peers.

signal transition_requested(to_title: String, from_title: String, hall_info: Dictionary)

var _museum: Node3D = null
var _transition_in_progress: bool = false


func init(museum: Node3D) -> void:
	_museum = museum


func is_transition_in_progress() -> bool:
	return _transition_in_progress


func request_multiplayer_transition(hall: Hall, backlink: bool) -> void:
	if _transition_in_progress:
		return

	# Safeguard: Clients must receive session_seed before generating any exhibit
	if NetworkManager.is_multiplayer_active() and not NetworkManager.is_server():
		if NetworkManager.session_seed == 0:
			Log.debug("MuseumSync", "Transition blocked — waiting for session seed")
			return

	var hall_info: Dictionary = {
		"to_title": hall.to_title,
		"from_title": hall.from_title,
		"backlink": backlink
	}
	# Execute locally - don't broadcast to other clients
	_execute_multiplayer_transition(hall.to_title, hall.from_title, hall_info)


func handle_transition_request(to_title: String, hall_info: Dictionary) -> void:
	# Only the server processes transition requests
	if not NetworkManager.is_server():
		return

	if _transition_in_progress:
		return

	# Validate sender — only accept transitions for the requesting peer
	var sender_id = multiplayer.get_remote_sender_id()
	var to_peer_id = hall_info.get("peer_id", sender_id)
	if sender_id != to_peer_id:
		Log.warn("MuseumSync", "Transition rejected — sender %d does not match peer_id %d" % [sender_id, to_peer_id])
		return

	var from_title: String = hall_info.get("from_title", _museum._current_room_title)

	# Authorize and broadcast the transition to all clients
	_museum.execute_transition.rpc(to_title, from_title, hall_info)


func execute_transition(to_title: String, from_title: String, hall_info: Dictionary) -> void:
	_execute_multiplayer_transition(to_title, from_title, hall_info)


func _execute_multiplayer_transition(to_title: String, from_title: String, hall_info: Dictionary) -> void:
	if _transition_in_progress:
		return

	# Final fail‑safe: Clients must have the session seed before generating exhibits
	if NetworkManager.is_multiplayer_active() and not NetworkManager.is_server():
		if NetworkManager.session_seed == 0:
			Log.warn("MuseumSync", "Transition aborted — session seed not yet received")
			return

	_transition_in_progress = true

	var backlink: bool = hall_info.get("backlink", false)

	Log.info("MuseumSync", "Executing multiplayer transition to %s backlink=%s" % [to_title, str(backlink)])

	# Find the hall that matches this transition
	var hall: Hall = _find_hall_for_transition(to_title, from_title, backlink)

	if hall:
		if backlink:
			_museum._load_exhibit_from_entry(hall)
		else:
			_museum._load_exhibit_from_exit(hall)

	# Clear the transition lock after a delay
	_museum.get_tree().create_timer(0.5).timeout.connect(func(): _transition_in_progress = false)


func _find_hall_for_transition(to_title: String, from_title: String, _backlink: bool) -> Hall:
	# Search through exhibits to find the matching hall
	if _museum._exhibits.has(from_title):
		var exhibit_data: Dictionary = _museum._exhibits[from_title]
		var exhibit: Node = exhibit_data.get("exhibit")
		if is_instance_valid(exhibit) and "exits" in exhibit:
			for exit: Hall in exhibit.exits:
				if exit.to_title == to_title:
					return exit

	# Check the lobby
	if from_title == "Lobby" and is_instance_valid(_museum.get_node_or_null("Lobby")):
		for exit: Hall in _museum.get_node("Lobby").exits:
			if exit.to_title == to_title:
				return exit

	return null


func sync_to_exhibit(exhibit_title: String) -> void:
	# Called when a late-joining player needs to sync to the current exhibit
	if exhibit_title == "Lobby" or exhibit_title == _museum._current_room_title:
		return
	
	# Safeguard: Clients must have session seed before generating any exhibit
	if NetworkManager.is_multiplayer_active() and not NetworkManager.is_server():
		if NetworkManager.session_seed == 0:
			Log.debug("MuseumSync", "Sync blocked — waiting for session seed")
			return
	
	Log.info("MuseumSync", "Syncing to exhibit %s" % exhibit_title)

	# The exhibit will be generated locally since generation is deterministic
	_museum._set_current_room_title(exhibit_title)


func is_local_player(body: Node) -> bool:
	if body.has_method("is_local"):
		return body.is_local
	# Check if it's the local player by checking is_local property
	if "is_local" in body:
		return body.is_local
	# If it's in the Player group and we can't determine, assume local for single-player
	return true
