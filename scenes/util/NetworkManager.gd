extends Node

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed
signal connection_succeeded
signal server_disconnected
signal player_info_updated(id: int)
signal player_room_changed(id: int, room: String)

const DEFAULT_PORT := Constants.DEFAULT_PORT
const MAX_PLAYERS := Constants.MAX_PLAYERS

# ── CHANGED: ENetMultiplayerPeer instead of WebSocketMultiplayerPeer ──────
# WebSocketMultiplayerPeer uses TCP/WebSocket and cannot travel over a UDP
# tunnel such as playit.gg. ENetMultiplayerPeer uses UDP natively and works
# with playit.gg out of the box.
var peer: ENetMultiplayerPeer = null

var player_info: Dictionary = {}
var local_player_name: String = "Player"
var local_player_color: Color = Color(0.2, 0.5, 0.8, 1.0)
var local_player_skin: String = ""
var is_hosting: bool = false
var is_dedicated_server: bool = false

# Keepalive to prevent playit.gg from dropping the UDP session during its
# ~19 second re-auth cycle. We ping every 5 seconds so ENet never goes silent
# long enough for playit to consider the channel dead.
var _keepalive_timer: float = 0.0
const _KEEPALIVE_INTERVAL: float = 5.0


func _process(delta: float) -> void:
	if not is_multiplayer_active():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_keepalive_timer += delta
	if _keepalive_timer >= _KEEPALIVE_INTERVAL:
		_keepalive_timer = 0.0
		_send_keepalive.rpc()


@rpc("any_peer", "call_local", "reliable")
func _send_keepalive() -> void:
	pass  # No-op — the arriving packet resets playit.gg's UDP session timer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(port: int = DEFAULT_PORT, dedicated: bool = false) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		peer = null
		return error

	multiplayer.multiplayer_peer = peer
	is_hosting = true
	is_dedicated_server = dedicated

	if not dedicated:
		player_info[1] = {
			"name": local_player_name,
			"color": local_player_color,
			"skin_url": local_player_skin,
			"current_room": "Lobby"
		}

	Log.debug("Network", "Hosting game on port %d (dedicated: %s)" % [port, str(dedicated)])
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	# ENet's create_client requires a raw IP address — it cannot resolve
	# hostnames (including playit.gg tunnel addresses) on its own.
	# We resolve the hostname first using Godot's IP class, then connect.

	var resolved_ip := address

	# Only resolve if it's not already a plain IP address
	if not _is_ip_address(address):
		Log.debug("Network", "Resolving hostname: %s" % address)

		# Start async DNS resolution
		var queue_id := IP.resolve_hostname_queue_item(address)
		if queue_id == IP.RESOLVER_INVALID_ID:
			Log.warn("Network", "DNS resolution failed to start for: %s" % address)
			connection_failed.emit()
			return ERR_CANT_RESOLVE

		# Poll until resolved or timeout (~5 seconds at 20 polls/sec)
		var attempts := 0
		var status := IP.ResolverStatus.RESOLVER_STATUS_WAITING
		while status == IP.RESOLVER_STATUS_WAITING and attempts < 100:
			await get_tree().create_timer(0.05).timeout
			status = IP.get_resolve_item_status(queue_id)
			attempts += 1

		if status != IP.RESOLVER_STATUS_DONE:
			IP.erase_resolve_item(queue_id)
			Log.warn("Network", "DNS resolution timed out for: %s" % address)
			connection_failed.emit()
			return ERR_CANT_RESOLVE

		resolved_ip = IP.get_resolve_item_address(queue_id)
		IP.erase_resolve_item(queue_id)

		if resolved_ip == "" or resolved_ip == "0.0.0.0":
			Log.warn("Network", "DNS resolved to invalid IP for: %s" % address)
			connection_failed.emit()
			return ERR_CANT_RESOLVE

		Log.debug("Network", "Resolved %s → %s" % [address, resolved_ip])

	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(resolved_ip, port)
	if error != OK:
		peer = null
		Log.warn("Network", "ENet create_client failed: %s" % error_string(error))
		return error

	multiplayer.multiplayer_peer = peer
	is_hosting = false

	Log.debug("Network", "Joining game at %s:%d (resolved: %s)" % [address, port, resolved_ip])
	return OK


func _is_ip_address(s: String) -> bool:
	# Godot 4 has no IP.is_ipv4_address() — check with a regex instead.
	# IPv4: four groups of 1-3 digits separated by dots
	var ipv4 := RegEx.new()
	ipv4.compile("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$")
	if ipv4.search(s):
		return true
	# IPv6: contains colons
	return ":" in s


func disconnect_from_game() -> void:
	if peer:
		peer.close()
		peer = null

	multiplayer.multiplayer_peer = null
	player_info.clear()
	is_hosting = false
	is_dedicated_server = false

	Log.debug("Network", "Disconnected from game")


func is_multiplayer_active() -> bool:
	return peer != null and multiplayer.multiplayer_peer != null

func is_server() -> bool:
	return is_multiplayer_active() and multiplayer.is_server()

func get_unique_id() -> int:
	if is_multiplayer_active():
		return multiplayer.get_unique_id()
	return 1

func get_player_list() -> Array:
	return player_info.keys()

func get_player_name(peer_id: int) -> String:
	if player_info.has(peer_id):
		return player_info[peer_id].name
	return "Unknown"

func get_player_color(peer_id: int) -> Color:
	if player_info.has(peer_id) and player_info[peer_id].has("color"):
		return player_info[peer_id].color
	return Color(0.2, 0.5, 0.8, 1.0)

func get_player_skin(peer_id: int) -> String:
	if player_info.has(peer_id) and player_info[peer_id].has("skin_url"):
		return player_info[peer_id].skin_url
	return ""

func set_local_player_room(room: String) -> void:
	var my_id = get_unique_id()
	if player_info.has(my_id):
		player_info[my_id].current_room = room
		if is_multiplayer_active():
			_broadcast_player_room.rpc(my_id, room)

func get_player_room(peer_id: int) -> String:
	if player_info.has(peer_id) and player_info[peer_id].has("current_room"):
		return player_info[peer_id].current_room
	return "Lobby"

@rpc("any_peer", "call_local", "reliable")
func _broadcast_player_room(peer_id: int, room: String) -> void:
	if player_info.has(peer_id):
		player_info[peer_id].current_room = room
	player_room_changed.emit(peer_id, room)

func set_local_player_name(player_name: String) -> void:
	local_player_name = player_name
	var my_id = get_unique_id()
	if player_info.has(my_id):
		player_info[my_id].name = player_name
		if is_multiplayer_active():
			_broadcast_player_info.rpc(my_id, player_name, local_player_color.to_html(), local_player_skin)

func set_local_player_color(color: Color) -> void:
	local_player_color = color
	var my_id = get_unique_id()
	if player_info.has(my_id):
		player_info[my_id].color = color
		if is_multiplayer_active():
			_broadcast_player_info.rpc(my_id, local_player_name, color.to_html(), local_player_skin)

func set_local_player_skin(skin_url: String) -> void:
	local_player_skin = skin_url
	var my_id = get_unique_id()
	if player_info.has(my_id):
		player_info[my_id].skin_url = skin_url
		if is_multiplayer_active():
			_broadcast_player_info.rpc(my_id, local_player_name, local_player_color.to_html(), skin_url)

@rpc("any_peer", "call_local", "reliable")
func _broadcast_player_info(peer_id: int, player_name: String, color_html: String, skin_url: String = "") -> void:
	var current_room: String = "Lobby"
	if player_info.has(peer_id) and player_info[peer_id].has("current_room"):
		current_room = player_info[peer_id].current_room
	player_info[peer_id] = {
		"name": player_name,
		"color": Color.html(color_html),
		"skin_url": skin_url,
		"current_room": current_room
	}
	player_info_updated.emit(peer_id)

@rpc("any_peer", "reliable")
func _request_player_info(from_peer: int) -> void:
	if is_dedicated_server:
		return
	_receive_player_info.rpc_id(from_peer, multiplayer.get_unique_id(), local_player_name, local_player_color.to_html(), local_player_skin)

@rpc("any_peer", "reliable")
func _receive_player_info(peer_id: int, player_name: String, color_html: String, skin_url: String = "") -> void:
	var current_room: String = "Lobby"
	if player_info.has(peer_id) and player_info[peer_id].has("current_room"):
		current_room = player_info[peer_id].current_room
	player_info[peer_id] = {
		"name": player_name,
		"color": Color.html(color_html),
		"skin_url": skin_url,
		"current_room": current_room
	}
	player_info_updated.emit(peer_id)


func _on_peer_connected(id: int) -> void:
	Log.info("Network", "Peer connected: %d" % id)

	# Set timeout immediately on connection — must happen here (not just in Main.gd)
	# because Main.gd's peer_connected handler skips setup when game hasn't started yet.
	# Without this, playit.gg's ~19s UDP re-auth cycle drops the lobby connection.
	var enet_peer := peer.get_peer(id) if peer else null
	if enet_peer:
		enet_peer.set_timeout(32, 20000, 60000)

	_request_player_info.rpc_id(id, multiplayer.get_unique_id())
	if not is_dedicated_server:
		_receive_player_info.rpc_id(id, multiplayer.get_unique_id(), local_player_name, local_player_color.to_html(), local_player_skin)
		var my_id := multiplayer.get_unique_id()
		var my_room := get_player_room(my_id)
		_broadcast_player_room.rpc_id(id, my_id, my_room)
	if is_server():
		for existing_id in player_info.keys():
			if existing_id != id:
				var info = player_info[existing_id]
				var color_html = info.color.to_html() if info.has("color") else Color(0.2, 0.5, 0.8, 1.0).to_html()
				var skin = info.skin_url if info.has("skin_url") else ""
				_receive_player_info.rpc_id(id, existing_id, info.name, color_html, skin)
				var room: String = info.current_room if info.has("current_room") else "Lobby"
				_broadcast_player_room.rpc_id(id, existing_id, room)
	peer_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	Log.info("Network", "Peer disconnected: %d" % id)
	player_info.erase(id)
	peer_disconnected.emit(id)

func _on_connected_to_server() -> void:
	Log.debug("Network", "Connected to server")

	# Set timeout on the server peer (id=1) from the client side.
	# Call it immediately and also deferred — peer.get_peer(1) can return null
	# if the ENet peer object isn't ready yet at this exact moment.
	_apply_server_timeout()
	call_deferred("_apply_server_timeout")

	var my_id = multiplayer.get_unique_id()
	player_info[my_id] = {
		"name": local_player_name,
		"color": local_player_color,
		"skin_url": local_player_skin,
		"current_room": "Lobby"
	}
	connection_succeeded.emit()


func _apply_server_timeout() -> void:
	if not peer:
		return
	var server_peer := peer.get_peer(1)
	if server_peer:
		server_peer.set_timeout(32, 20000, 60000)
		Log.debug("Network", "Set timeout on server peer")

func _on_connection_failed() -> void:
	Log.warn("Network", "Connection failed")
	peer = null
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected() -> void:
	Log.info("Network", "Server disconnected")
	peer = null
	multiplayer.multiplayer_peer = null
	player_info.clear()
	is_hosting = false
	is_dedicated_server = false
	server_disconnected.emit()
