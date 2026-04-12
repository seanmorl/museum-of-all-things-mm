extends Node

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed
signal connection_succeeded
signal server_disconnected
signal player_info_updated(id: int)
signal player_room_changed(id: int, room: String)

# Extended disconnect signal with reason for better UI feedback
signal disconnected_with_reason(reason: String)

const DEFAULT_PORT := Constants.DEFAULT_PORT
const MAX_PLAYERS := Constants.MAX_PLAYERS

# ── CHANGED: ENetMultiplayerPeer instead of WebSocketMultiplayerPeer ──────
# WebSocketMultiplayerPeer uses TCP/WebSocket and cannot travel over a UDP
# tunnel such as playit.gg. ENetMultiplayerPeer uses UDP natively and works
# with playit.gg out of the box.
var peer: ENetMultiplayerPeer = null
var _host_port: int = DEFAULT_PORT  # Track the port we're hosting on

var player_info: Dictionary = {}
var local_player_name: String = "Player"
var local_player_color: Color = Color(0.2, 0.5, 0.8, 1.0)
var local_player_skin: String = ""
var local_player_pronouns: String = ""
var is_hosting: bool = false
var is_dedicated_server: bool = false
var show_nameplates: bool = true  # Toggle for showing player nameplates/pronouns

# Persistent player identity (saved between sessions)
var _saved_player_names: Dictionary = {}  # peer_id -> last known name

# RPC throttling - only sync player positions every 100ms instead of every frame
var _position_sync_timer: float = 0.0
const _POSITION_SYNC_INTERVAL: float = 0.1  # 100ms between syncs

# Keepalive to prevent playit.gg from dropping the UDP session during its
# ~19 second re-auth cycle. We ping every 5 seconds so ENet never goes silent
# long enough for playit to consider the channel dead.
var _keepalive_timer: float = 0.0
const _KEEPALIVE_INTERVAL: float = 5.0

# Game state validation
var _state_check_timer: float = 0.0
const _STATE_CHECK_INTERVAL: float = 10.0  # Check every 10 seconds
var _local_state_hash: String = ""
var _last_migration_time: int = 0  # Rate limiting for host migration
var _migration_pending: bool = false  # Track if migration is in progress
var _migration_timer: float = 0.0  # Timeout for migration
const _MIGRATION_TIMEOUT: float = 15.0  # Seconds before migration fails

# Connection attempt watchdog — ENet doesn't fire connection_failed if the
# server is completely unreachable (no route / firewall drop). We need our
# own timeout so the UI isn't left hanging forever.
var _connecting: bool = false
var _connection_watchdog_timer: float = 0.0
const _CONNECTION_TIMEOUT: float = 15.0  # Seconds before we give up connecting


func _process(delta: float) -> void:
	# Connection watchdog — runs even when multiplayer isn't fully active
	if _connecting:
		_connection_watchdog_timer += delta
		if _connection_watchdog_timer >= _CONNECTION_TIMEOUT:
			Log.error("Network", "Connection attempt timed out after %.0fs" % _connection_watchdog_timer)
			_connecting = false
			_connection_watchdog_timer = 0.0
			_cleanup_connection()
			disconnected_with_reason.emit("Connection timed out — server unreachable")
			if not connection_failed.is_connected(_noop):
				connection_failed.emit()

	if not is_multiplayer_active():
		return
	
	# RPC throttling - limit position syncs
	_position_sync_timer += delta
	if _position_sync_timer >= _POSITION_SYNC_INTERVAL:
		_position_sync_timer = 0.0
		# Position sync logic would go here (called by Player.gd)
	
	_keepalive_timer += delta
	if _keepalive_timer >= _KEEPALIVE_INTERVAL:
		_keepalive_timer = 0.0
		if multiplayer.has_multiplayer_peer() and peer:
			_send_keepalive.rpc()

	# Game state validation (server only)
	if is_hosting:
		_state_check_timer += delta
		if _state_check_timer >= _STATE_CHECK_INTERVAL:
			_validate_game_state()
			_state_check_timer = 0.0
	
	# Migration timeout check (clients waiting for new host)
	if _migration_pending and not is_hosting:
		_migration_timer += delta
		if _migration_timer >= _MIGRATION_TIMEOUT:
			Log.error("Network", "Host migration timed out (%.0fs)" % _migration_timer)
			_migration_pending = false
			_migration_timer = 0.0
			_cleanup_connection()


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
	_host_port = port  # Store the port we're hosting on

	if not dedicated:
		player_info[1] = {
			"name": local_player_name,
			"color": local_player_color,
			"skin_url": local_player_skin,
			"pronouns": local_player_pronouns,
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

	# Start the connection watchdog — ENet won't fire connection_failed if
	# the server never responds (firewall drop, wrong IP, etc.)
	_connecting = true
	_connection_watchdog_timer = 0.0

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
	_connecting = false
	_connection_watchdog_timer = 0.0
	if peer:
		peer.close()
		peer = null

	multiplayer.multiplayer_peer = null
	player_info.clear()
	is_hosting = false
	is_dedicated_server = false

	Log.debug("Network", "Disconnected from game")

func get_server_address() -> String:
	## Returns the local server address for the host to share with players.
	## Format: "hostname:port" or "IP:port"
	if not is_hosting and not is_dedicated_server:
		return ""
	
	var port := _get_host_port()
	# Use local IP directly - hostname resolution is unreliable across networks
	var ip := _get_local_ip()
	return "%s:%d" % [ip, port]

func _get_host_port() -> int:
	## Get the port we're hosting on
	return _host_port

func _get_local_ip() -> String:
	## Get the local IP address of this machine (LAN IP, not public IP)
	var interfaces := IP.get_local_interfaces()
	if interfaces.is_empty():
		return "localhost"

	# Prefer IPv4 addresses
	for interface in interfaces:
		var addresses: Dictionary = interface.get("addresses", {})
		if addresses.has("IPv4"):
			return addresses["IPv4"]["address"]

	# Fallback to first available address
	for interface in interfaces:
		var addresses: Dictionary = interface.get("addresses", {})
		for addr_type in addresses:
			if addr_type != "IPv6":
				return addresses[addr_type]["address"]

	return "localhost"


func is_multiplayer_active() -> bool:
	return peer != null and multiplayer.multiplayer_peer != null

func is_server() -> bool:
	return is_multiplayer_active() and multiplayer.is_server()

func kick_peer(peer_id: int) -> void:
	"""Kick a player from the game (server only)."""
	if not is_server():
		Log.warn("Network", "Cannot kick peer - not server")
		return

	if peer_id == 1:
		Log.warn("Network", "Cannot kick host")
		return

	if peer and peer is ENetMultiplayerPeer:
		Log.info("Network", "Kicking peer %d" % peer_id)
		peer.disconnect_peer(peer_id)
	else:
		Log.warn("Network", "Cannot kick peer - invalid multiplayer peer")

func get_unique_id() -> int:
	if is_multiplayer_active():
		return multiplayer.get_unique_id()
	return 1

func get_player_list() -> Array:
	return player_info.keys()

func get_player_name(peer_id: int) -> String:
	if player_info.has(peer_id):
		return player_info[peer_id].name
	# Fallback to saved name if player disconnected
	if _saved_player_names.has(peer_id):
		return _saved_player_names[peer_id]
	return "Unknown"

func get_player_color(peer_id: int) -> Color:
	if player_info.has(peer_id) and player_info[peer_id].has("color"):
		return player_info[peer_id].color
	return Color(0.2, 0.5, 0.8, 1.0)

func get_player_skin(peer_id: int) -> String:
	if player_info.has(peer_id) and player_info[peer_id].has("skin_url"):
		return player_info[peer_id].skin_url
	return ""

func get_player_pronouns(peer_id: int) -> String:
	if player_info.has(peer_id) and player_info[peer_id].has("pronouns"):
		return player_info[peer_id].pronouns
	return ""

func remember_player_name(peer_id: int, name: String) -> void:
	## Remember a player's name for future sessions
	_saved_player_names[peer_id] = name

func get_remembered_name(peer_id: int) -> String:
	## Get a previously saved player name
	return _saved_player_names.get(peer_id, "")

func clear_remembered_name(peer_id: int) -> void:
	## Clear a saved name when player fully disconnects
	_saved_player_names.erase(peer_id)


func set_local_player_pronouns(pronouns: String) -> void:
	local_player_pronouns = pronouns
	var my_id = get_unique_id()
	if player_info.has(my_id):
		player_info[my_id].pronouns = pronouns
		if is_multiplayer_active():
			_broadcast_player_info.rpc(my_id, local_player_name, local_player_color.to_html(), local_player_skin, local_player_pronouns)


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
	# Validate sender identity — peer_id must match the actual sender
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != peer_id:
		Log.warn("Network", "Rejected spoofed room update: sender=%d claimed=%d" % [sender_id, peer_id])
		return
	# Sanitize room name length
	if room.length() > 256:
		room = room.substr(0, 256)

	if player_info.has(peer_id):
		player_info[peer_id].current_room = room
	player_room_changed.emit(peer_id, room)

func set_local_player_name(player_name: String) -> void:
	local_player_name = player_name
	var my_id = get_unique_id()
	if player_info.has(my_id):
		player_info[my_id].name = player_name
		if is_multiplayer_active():
			_broadcast_player_info.rpc(my_id, player_name, local_player_color.to_html(), local_player_skin, local_player_pronouns)

func set_local_player_color(color: Color) -> void:
	local_player_color = color
	var my_id = get_unique_id()
	if player_info.has(my_id):
		player_info[my_id].color = color
		if is_multiplayer_active():
			_broadcast_player_info.rpc(my_id, local_player_name, color.to_html(), local_player_skin, local_player_pronouns)

func set_local_player_skin(skin_url: String) -> void:
	local_player_skin = skin_url
	var my_id = get_unique_id()
	if player_info.has(my_id):
		player_info[my_id].skin_url = skin_url
		if is_multiplayer_active():
			_broadcast_player_info.rpc(my_id, local_player_name, local_player_color.to_html(), skin_url, local_player_pronouns)

@rpc("any_peer", "call_local", "reliable")
func _broadcast_player_info(peer_id: int, player_name: String, color_html: String, skin_url: String = "", pronouns: String = "") -> void:
	# Validate sender identity — peer_id must match the actual sender
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != peer_id:
		Log.warn("Network", "Rejected spoofed player info: sender=%d claimed=%d" % [sender_id, peer_id])
		return
	# Sanitize inputs
	if player_name.length() > 32:
		player_name = player_name.substr(0, 32)
	if pronouns.length() > 32:
		pronouns = pronouns.substr(0, 32)
	if color_html.length() > 8:
		color_html = "3380ccff"

	var current_room: String = "Lobby"
	if player_info.has(peer_id) and player_info[peer_id].has("current_room"):
		current_room = player_info[peer_id].current_room
	player_info[peer_id] = {
		"name": player_name,
		"color": Color.html(color_html),
		"skin_url": skin_url,
		"pronouns": pronouns,
		"current_room": current_room
	}
	player_info_updated.emit(peer_id)

@rpc("any_peer", "reliable")
func _request_player_info(from_peer: int) -> void:
	if is_dedicated_server:
		return
	_receive_player_info.rpc_id(from_peer, multiplayer.get_unique_id(), local_player_name, local_player_color.to_html(), local_player_skin, local_player_pronouns)

@rpc("any_peer", "reliable")
func _receive_player_info(peer_id: int, player_name: String, color_html: String, skin_url: String = "", pronouns: String = "") -> void:
	# Validate sender identity — peer_id must match the actual sender
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != peer_id:
		Log.warn("Network", "Rejected spoofed player info receive: sender=%d claimed=%d" % [sender_id, peer_id])
		return
	# Sanitize inputs
	if player_name.length() > 32:
		player_name = player_name.substr(0, 32)
	if pronouns.length() > 32:
		pronouns = pronouns.substr(0, 32)

	var current_room: String = "Lobby"
	if player_info.has(peer_id) and player_info[peer_id].has("current_room"):
		current_room = player_info[peer_id].current_room
	player_info[peer_id] = {
		"name": player_name,
		"color": Color.html(color_html),
		"skin_url": skin_url,
		"pronouns": pronouns,
		"current_room": current_room
	}
	player_info_updated.emit(peer_id)


func _on_peer_connected(id: int) -> void:
	Log.info("Network", "Peer connected: %d, player_info before=%s" % [id, str(player_info.keys())])

	# Set timeout immediately on connection — must happen here (not just in Main.gd)
	# because Main.gd's peer_connected handler skips setup when game hasn't started yet.
	# Without this, playit.gg's ~19s UDP re-auth cycle drops the lobby connection.
	var enet_peer := peer.get_peer(id) if peer else null
	if enet_peer:
		enet_peer.set_timeout(32, 20000, 60000)

	# Defer the RPC burst by one frame so ENet fully registers the peer before
	# we send to them. Sending RPCs before the peer is in ENet's peer table
	# produces "Condition !peers.has(p_id) is true" errors and packet loss.
	call_deferred("_send_peer_info_rpcs", id)
	peer_connected.emit(id)


func _send_peer_info_rpcs(id: int) -> void:
	# Guard: peer may have disconnected in the frame we waited.
	if not peer or not multiplayer.get_peers().has(id):
		return
	_request_player_info.rpc_id(id, multiplayer.get_unique_id())
	if not is_dedicated_server:
		_receive_player_info.rpc_id(id, multiplayer.get_unique_id(), local_player_name, local_player_color.to_html(), local_player_skin, local_player_pronouns)
		var my_id := multiplayer.get_unique_id()
		var my_room := get_player_room(my_id)
		_broadcast_player_room.rpc_id(id, my_id, my_room)
	if is_server():
		# Broadcast all existing players to the new peer (including host if host is player 1)
		for existing_id in player_info.keys():
			if existing_id != id:
				var info = player_info[existing_id]
				var color_html = info.color.to_html() if info.has("color") else Color(0.2, 0.5, 0.8, 1.0).to_html()
				var skin = info.skin_url if info.has("skin_url") else ""
				var pronouns: String = info.pronouns if info.has("pronouns") else ""
				_receive_player_info.rpc_id(id, existing_id, info.name, color_html, skin, pronouns)
				var room: String = info.current_room if info.has("current_room") else "Lobby"
				_broadcast_player_room.rpc_id(id, existing_id, room)

func _on_peer_disconnected(id: int) -> void:
	Log.info("Network", "Peer disconnected: %d" % id)
	# Remember the player's name before clearing
	if player_info.has(id):
		remember_player_name(id, player_info[id].name)
	player_info.erase(id)
	peer_disconnected.emit(id)

func _on_connected_to_server() -> void:
	Log.debug("Network", "Connected to server")
	_connecting = false
	_connection_watchdog_timer = 0.0

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
		"pronouns": local_player_pronouns,
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
	_connecting = false
	_connection_watchdog_timer = 0.0
	peer = null
	multiplayer.multiplayer_peer = null
	disconnected_with_reason.emit("Connection failed")
	connection_failed.emit()

func _on_server_disconnected() -> void:
	Log.info("Network", "Server disconnected")
	_connecting = false
	_connection_watchdog_timer = 0.0

	# Clients should NOT attempt self-migration — this is insecure.
	# Host migration is only initiated by the server via _request_host_migration.
	# When the server disconnects, clients just clean up.

	peer = null
	multiplayer.multiplayer_peer = null
	player_info.clear()
	is_hosting = false
	is_dedicated_server = false
	disconnected_with_reason.emit("Host disconnected")
	server_disconnected.emit()

func _elect_and_migrate_host(connected_peers: Array) -> void:
	"""Elect a new host from connected peers and migrate"""
	if connected_peers.is_empty():
		Log.error("Network", "No peers available for host migration")
		_cleanup_connection()
		return
	
	# Elect new host (peer with lowest ID = longest connected)
	var new_host_id = connected_peers[0]
	Log.info("Network", "Electing peer %d as new host" % new_host_id)
	
	# Request host migration from the new host
	_request_host_migration.rpc_id(new_host_id)

func _get_connected_peers() -> Array:
	"""Get array of connected peer IDs"""
	var peers: Array = []
	if multiplayer.has_multiplayer_peer():
		for peer_id in multiplayer.get_peers():
			peers.append(peer_id)
	return peers

func _cleanup_connection() -> void:
	"""Clean up connection and emit disconnect with reason"""
	_connecting = false
	_connection_watchdog_timer = 0.0
	peer = null
	multiplayer.multiplayer_peer = null
	player_info.clear()
	is_hosting = false
	is_dedicated_server = false
	disconnected_with_reason.emit("Connection cleaned up")
	server_disconnected.emit()

@rpc("any_peer", "call_local", "reliable")
func _request_host_migration() -> void:
	"""Called by clients to request becoming the new host.
	Uses call_local so the HOST (not the sender) processes the migration."""
	if not is_hosting:
		return  # Only current host processes migration requests

	var requesting_peer = multiplayer.get_remote_sender_id()

	# Validate: only accept migration requests from the elected peer (lowest ID)
	var connected_peers = _get_connected_peers()
	if connected_peers.is_empty():
		return
	var expected_host = connected_peers[0]  # lowest ID = longest connected
	if requesting_peer != expected_host:
		Log.warn("Network", "Rejected host migration from non-elected peer %d (expected %d)" % [requesting_peer, expected_host])
		return

	# Rate limiting: reject if last migration was < 30 seconds ago
	var now := Time.get_ticks_msec()
	if now - _last_migration_time < 30000:
		Log.warn("Network", "Host migration rate limited (last was %d ms ago)" % (now - _last_migration_time))
		return
	_last_migration_time = now
	
	# Mark migration as pending with timeout
	_migration_pending = true
	_migration_timer = 0.0

	Log.info("Network", "Transferring host to peer %d" % requesting_peer)

	# Transfer all game state to new host
	var game_state = _serialize_game_state()
	_transfer_host_state.rpc_id(requesting_peer, game_state)

	# Make them the new host
	_make_peer_host.rpc_id(requesting_peer)

	# We become a client now
	is_hosting = false

@rpc("any_peer", "call_local", "reliable")
func _transfer_host_state(game_state: Dictionary) -> void:
	"""New host receives all game state.
	Uses any_peer because the old host (not authority) sends this to the new host."""
	Log.info("Network", "Received host state, becoming host...")
	_deserialize_game_state(game_state)

@rpc("authority", "call_local", "reliable")
func _make_peer_host(peer_id: int) -> void:
	"""Tell a peer they are now the host"""
	_migration_pending = false
	_migration_timer = 0.0
	is_hosting = true
	Log.info("Network", "Now hosting! Peer ID: %d" % peer_id)

	# Close old peer before creating new one to prevent resource leaks
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()

	# Reinitialize as server
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(_host_port, MAX_PLAYERS)
	if err != OK:
		Log.error("Network", "Failed to create server on port %d: error %d" % [_host_port, err])
		is_hosting = false
		peer = null
		return
	multiplayer.multiplayer_peer = peer

func _serialize_game_state() -> Dictionary:
	"""Serialize current game state for host migration"""
	return {
		"player_info": player_info.duplicate(true),
		"race_state": _get_race_state(),
		"timestamp": Time.get_ticks_msec()
	}

func _deserialize_game_state(state: Dictionary) -> void:
	"""Restore game state from host migration"""
	if state.has("player_info"):
		player_info = state.player_info.duplicate(true)
	if state.has("race_state"):
		_set_race_state(state.race_state)

func _get_race_state() -> Dictionary:
	"""Get current race state for serialization"""
	if not RaceManager or not RaceManager.has_method("get_state"):
		return {}
	return {
		"state": RaceManager.get_state(),
		"target": RaceManager.get_target_article() if RaceManager.has_method("get_target_article") else "",
		"start": RaceManager.get_start_article() if RaceManager.has_method("get_start_article") else ""
	}

func _set_race_state(state: Dictionary) -> void:
	"""Restore race state"""
	if not RaceManager:
		return
	# Race state restoration would go here
	# For now, just log it
	Log.info("Network", "Restored race state: %s" % str(state))


func _validate_game_state() -> void:
	"""Validate game state across all clients"""
	if not is_hosting:
		return
	
	# Calculate our local state hash
	_local_state_hash = _calculate_state_hash()
	
	# Request state hashes from all clients
	for peer_id in _get_connected_peers():
		_request_state_hash.rpc_id(peer_id)

func _calculate_state_hash() -> String:
	"""Calculate hash of current game state"""
	var state := {
		"player_count": player_info.size(),
		"race_state": RaceManager.get_state() if RaceManager and RaceManager.has_method("get_state") else 0,
		"race_target": RaceManager.get_target_article() if RaceManager and RaceManager.has_method("get_target_article") else "",
		"timestamp": int(Time.get_ticks_msec() / 1000)  # Round to seconds
	}
	return str(state.hash())

@rpc("any_peer", "call_local", "reliable")
func _request_state_hash() -> void:
	"""Request state hash from a client"""
	var client_hash = _calculate_state_hash()
	_send_state_hash.rpc_id(1, multiplayer.get_remote_sender_id(), client_hash)

@rpc("any_peer", "call_local", "reliable")
func _send_state_hash(peer_id: int, client_hash: String) -> void:
	"""Receive state hash from client and compare"""
	# Only server processes state hashes
	if not is_server():
		return
	if client_hash != _local_state_hash:
		Log.warn("Network", "State desync detected for peer %d! Resyncing..." % peer_id)
		_resync_client(peer_id)

func _resync_client(peer_id: int) -> void:
	"""Resync a desynchronized client"""
	# Don't try to resync the server itself
	if peer_id == 1 or peer_id == get_unique_id():
		Log.warn("Network", "Skipping resync for server/local peer")
		return
	
	var game_state = _serialize_game_state()
	_send_full_state.rpc_id(peer_id, game_state)
	Log.info("Network", "Sent full state to peer %d for resync" % peer_id)

@rpc("authority", "call_local", "reliable")
func _send_full_state(peer_id: int, game_state: Dictionary) -> void:
	"""Receive full state from server and resync.
	Uses call_local so the RECEIVING client deserializes the state."""
	_deserialize_game_state(game_state)
	Log.info("Network", "Client resync complete")


func _noop() -> void:
	pass  # Placeholder for signal connection checks
