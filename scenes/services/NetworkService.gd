extends Node
class_name NetworkService
## Abstracts network operations and provides a clean API for multiplayer features.
## Handles peer connections, state synchronization, and player position updates.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_disconnected()

var _local_peer_id: int = 1
var _connected_peers: Array[int] = []

func _ready() -> void:
	# Connect to NetworkManager signals
	if NetworkManager:
		NetworkManager.peer_connected.connect(_on_peer_connected)
		NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
		NetworkManager.server_disconnected.connect(_on_server_disconnected)
		NetworkManager.connection_succeeded.connect(_on_connection_succeeded)

# --- Initialization ---

func initialize() -> void:
	"""Initialize network service. Call from Main.gd."""
	_local_peer_id = NetworkManager.get_unique_id() if NetworkManager.is_multiplayer_active() else 1
	_update_connected_peers()
	print("NetworkService: Initialized, local peer ID = ", _local_peer_id)

# --- Queries ---

func is_server() -> bool:
	return NetworkManager.is_server() if NetworkManager else true

func is_multiplayer_active() -> bool:
	return NetworkManager.is_multiplayer_active() if NetworkManager else false

func get_local_peer_id() -> int:
	return _local_peer_id

func get_connected_peers() -> Array[int]:
	return _connected_peers.duplicate()

func get_peer_count() -> int:
	return _connected_peers.size()

func has_peer(peer_id: int) -> bool:
	return _connected_peers.has(peer_id)

func get_player_name(peer_id: int) -> String:
	if NetworkManager:
		return NetworkManager.get_player_name(peer_id)
	return "Player " + str(peer_id)

# --- State Synchronization ---

func broadcast_game_state(state: GameState) -> void:
	"""Broadcast game state to all clients."""
	if not is_multiplayer_active() or not is_server():
		return
	
	_sync_game_state.rpc(state.to_dict())

@rpc("authority", "call_local", "reliable")
func _sync_game_state(state_dict: Dictionary) -> void:
	"""Receive game state from server."""
	var state = GameState.from_dict(state_dict)
	# Update local game state through Services
	if Services.game_state:
		Services.game_state.current_state = state.current_state
		Services.game_state.sub_state = state.sub_state
		Services.game_state.race_target = state.race_target
		Services.game_state.race_start = state.race_start

# --- Player Position Sync ---

func sync_player_position(position: Vector3, rotation: Vector3, room: String) -> void:
	"""Send player position to server (called by local player)."""
	if not is_multiplayer_active():
		return
	
	if is_server():
		# Server updates locally
		_on_player_position_updated(_local_peer_id, position, rotation, room)
	else:
		# Client sends to server
		_sync_player_position.rpc_id(1, _local_peer_id, position, rotation, room)

@rpc("any_peer", "call_local", "reliable")
func _sync_player_position(peer_id: int, position: Vector3, rotation: Vector3, room: String) -> void:
	"""Receive player position update (server only)."""
	if is_server():
		_on_player_position_updated(peer_id, position, rotation, room)

func _on_player_position_updated(peer_id: int, position: Vector3, rotation: Vector3, room: String) -> void:
	"""Handle player position update (broadcast to all clients)."""
	# Broadcast to all other peers
	for other_peer in _connected_peers:
		if other_peer != peer_id:
			_broadcast_player_position.rpc_id(other_peer, peer_id, position, rotation, room)
	
	# Update local player list
	EventBus.publish_player_moved(peer_id, room, position)

@rpc("authority", "call_local", "reliable")
func _broadcast_player_position(peer_id: int, position: Vector3, rotation: Vector3, room: String) -> void:
	"""Receive broadcasted player position (clients only)."""
	# Could update a player ghost/marker here
	EventBus.publish_player_moved(peer_id, room, position)

# --- Room Sync ---

func sync_room_change(peer_id: int, room: String) -> void:
	"""Sync room change to all peers."""
	if not is_multiplayer_active():
		return
	
	if is_server():
		_broadcast_room_change.rpc(peer_id, room)
	else:
		_sync_room_change.rpc_id(1, peer_id, room)

@rpc("any_peer", "call_local", "reliable")
func _sync_room_change(peer_id: int, room: String) -> void:
	if is_server():
		_broadcast_room_change.rpc(peer_id, room)

@rpc("authority", "call_local", "reliable")
func _broadcast_room_change(peer_id: int, room: String) -> void:
	# Update room tracking
	EventBus.publish_player_moved(peer_id, room, Vector3.ZERO)

# --- Event Handlers ---

func _on_peer_connected(peer_id: int) -> void:
	print("NetworkService: Peer connected: ", peer_id)
	_connected_peers.append(peer_id)
	peer_connected.emit(peer_id)
	EventBus.publish(EventBus.NetworkPeerConnectedEvent.new(peer_id))

func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkService: Peer disconnected: ", peer_id)
	_connected_peers.erase(peer_id)
	peer_disconnected.emit(peer_id)
	EventBus.publish(EventBus.NetworkPeerDisconnectedEvent.new(peer_id))

func _on_server_disconnected() -> void:
	print("NetworkService: Server disconnected")
	server_disconnected.emit()
	_connected_peers.clear()

func _on_connection_succeeded() -> void:
	_local_peer_id = NetworkManager.get_unique_id()
	_update_connected_peers()

func _update_connected_peers() -> void:
	if NetworkManager and NetworkManager.is_multiplayer_active():
		_connected_peers = NetworkManager.get_player_list()
		if not _connected_peers.has(_local_peer_id):
			_connected_peers.append(_local_peer_id)

# --- Cleanup ---

func _exit_tree() -> void:
	_connected_peers.clear()
