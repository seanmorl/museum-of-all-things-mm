extends Node
## Dedicated Server Configuration and RCON Protocol
## Allows remote administration of dedicated servers

class RCONCommand:
	var command: String
	var args: Array
	var client_id: int
	
	func _init(cmd: String, arguments: Array, client: int):
		self.command = cmd
		self.args = arguments
		self.client_id = client

class RCONClient:
	var peer_id: int
	var authenticated: bool = false
	var last_activity: float = 0.0
	var command_count: int = 0  # Rate limiting

# Server configuration
var _server_config: Dictionary = {
	"server_name": "Museum Racing Server",
	"max_players": 16,
	"port": 7777,
	"password": "",
	"rcon_port": 7778,
	"rcon_password": "",
	"auto_kick_cheaters": true,
	"public_listing": true,
	"region": "us-east",
	"race_mode": "standard",
	"events_enabled": true,
	"friendly_fire": false
}

# RCON clients
var _rcon_clients: Array[RCONClient] = []
var _rcon_server: ENetMultiplayerPeer = null

# Server stats
var _server_stats: Dictionary = {
	"total_players": 0,
	"total_races": 0,
	"uptime_seconds": 0,
	"start_time": 0
}

# Config file path
const CONFIG_PATH := "user://server_config.json"

signal rcon_command_received(command: String, args: Array, client_id: int)
signal config_changed(key: String, value: Variant)

func _ready() -> void:
	_load_config()
	_server_stats["start_time"] = Time.get_unix_time_from_system()
	
	# Start RCON server if configured
	if _server_config.get("rcon_password", "") != "":
		_start_rcon_server()

func _process(delta: float) -> void:
	_server_stats["uptime_seconds"] += delta
	
	# Clean up inactive RCON clients
	_cleanup_rcon_clients()

func _start_rcon_server() -> void:
	"""Start the RCON administration server"""
	var port = _server_config.get("rcon_port", 7778)
	_rcon_server = ENetMultiplayerPeer.new()
	var error = _rcon_server.create_server(port, 4)  # Max 4 RCON admins

	if error != OK:
		Log.error("ServerConfig", "Failed to start RCON server on port %d: %s" % [port, error_string(error)])
		return

	Log.info("ServerConfig", "RCON server started on port %d" % port)

func _cleanup_rcon_clients() -> void:
	"""Remove inactive RCON clients"""
	var now = Time.get_ticks_msec() / 1000.0
	var timeout = 300.0  # 5 minutes
	
	for i in range(_rcon_clients.size() - 1, -1, -1):
		var client: RCONClient = _rcon_clients[i]
		if now - client.last_activity > timeout:
			_rcon_clients.remove_at(i)

func authenticate_rcon(peer_id: int, password: String) -> bool:
	"""Authenticate an RCON client"""
	var correct_password = _server_config.get("rcon_password", "")
	
	if password == correct_password and correct_password != "":
		var client = RCONClient.new()
		client.peer_id = peer_id
		client.authenticated = true
		client.last_activity = Time.get_ticks_msec() / 1000.0
		_rcon_clients.append(client)
		return true
	
	return false

func is_rcon_authenticated(peer_id: int) -> bool:
	"""Check if a peer is authenticated as RCON admin"""
	for client in _rcon_clients:
		if client.peer_id == peer_id and client.authenticated:
			return true
	return false

func process_rcon_command(peer_id: int, command_string: String) -> String:
	"""Process an RCON command from an authenticated client"""
	if not is_rcon_authenticated(peer_id):
		return "ERROR: Not authenticated"
	
	# Update client activity
	for client in _rcon_clients:
		if client.peer_id == peer_id:
			client.last_activity = Time.get_ticks_msec() / 1000.0
			client.command_count += 1
			
			# Rate limiting
			if client.command_count > 100:
				return "ERROR: Rate limit exceeded"
			break
	
	# Parse command
	var parts = command_string.split(" ", false)
	if parts.is_empty():
		return "ERROR: Empty command"
	
	var command = parts[0].to_lower()
	var args = parts.slice(1)
	
	return _execute_rcon_command(command, args, peer_id)

func _execute_rcon_command(command: String, args: Array, client_id: int) -> String:
	"""Execute an RCON command"""
	match command:
		"help":
			return _cmd_help()
		"status":
			return _cmd_status()
		"kick":
			return _cmd_kick(args)
		"ban":
			return _cmd_ban(args)
		"changemap":
			return _cmd_changemap(args)
		"setconfig":
			return _cmd_setconfig(args)
		"getconfig":
			return _cmd_getconfig(args)
		"broadcast":
			return _cmd_broadcast(args)
		"endrace":
			return _cmd_endrace()
		"forcerestart":
			return _cmd_forcerestart()
		"players":
			return _cmd_players()
		"stats":
			return _cmd_stats()
		_:
			return "ERROR: Unknown command '%s'. Type 'help' for commands." % command

func _cmd_help() -> String:
	return """Available commands:
  help - Show this help
  status - Show server status
  players - List all players
  kick <player_id> [reason] - Kick a player
  ban <player_id> [reason] - Ban a player
  broadcast <message> - Send message to all players
  endrace - End current race
  forcerestart - Restart the server
  setconfig <key> <value> - Set a config value
  getconfig <key> - Get a config value
  stats - Show server statistics"""

func _cmd_status() -> String:
	var uptime = _server_stats["uptime_seconds"]
	var hours = int(uptime / 3600)
	var minutes = int((uptime % 3600) / 60)
	var seconds = int(uptime % 60)
	
	return """Server: %s
Players: %d/%d
Uptime: %02d:%02d:%02d
Port: %d
RCON Port: %d
Region: %s
Mode: %s""" % [
		_server_config["server_name"],
		NetworkManager.get_player_list().size() if NetworkManager else 0,
		_server_config["max_players"],
		hours, minutes, seconds,
		_server_config["port"],
		_server_config["rcon_port"],
		_server_config["region"],
		_server_config["race_mode"]
	]

func _cmd_players() -> String:
	if not NetworkManager:
		return "ERROR: Network not available"
	
	var players = NetworkManager.get_player_list()
	if players.is_empty():
		return "No players connected"
	
	var result = "Connected players:\n"
	for peer_id in players:
		var name = NetworkManager.get_player_name(peer_id)
		var room = NetworkManager.get_player_room(peer_id)
		result += "  [%d] %s (Room: %s)\n" % [peer_id, name, room]
	
	return result.strip_edges()

func _cmd_kick(args: Array) -> String:
	if args.is_empty():
		return "ERROR: Usage: kick <player_id> [reason]"
	
	var player_id = int(args[0])
	var reason = "Kicked by admin" if args.size() < 2 else " ".join(args.slice(1))
	
	if NetworkManager and NetworkManager.is_server():
		NetworkManager.kick_peer(player_id)
		return "Kicked player %d: %s" % [player_id, reason]
	
	return "ERROR: Not server or NetworkManager unavailable"

func _cmd_ban(args: Array) -> String:
	# Simplified - in production you'd maintain a ban list
	if args.is_empty():
		return "ERROR: Usage: ban <player_id> [reason]"
	
	var player_id = int(args[0])
	var reason = "Banned by admin" if args.size() < 2 else " ".join(args.slice(1))
	
	if NetworkManager and NetworkManager.is_server():
		NetworkManager.kick_peer(player_id)
		# TODO: Add to persistent ban list
		return "Banned player %d: %s" % [player_id, reason]
	
	return "ERROR: Not server or NetworkManager unavailable"

func _cmd_broadcast(args: Array) -> String:
	if args.is_empty():
		return "ERROR: Usage: broadcast <message>"
	
	var message = " ".join(args)
	# TODO: Send broadcast to all players via chat system
	return "Broadcast: %s" % message

func _cmd_endrace() -> String:
	if RaceManager and RaceManager.is_race_active():
		RaceManager.cancel_race()
		return "Race ended by admin"
	return "No race active"

func _cmd_forcerestart() -> String:
	# TODO: Implement server restart
	return "Restart initiated..."

func _cmd_setconfig(args: Array) -> String:
	if args.size() < 2:
		return "ERROR: Usage: setconfig <key> <value>"
	
	var key = args[0]
	var value = args[1]
	
	if _server_config.has(key):
		# Type conversion
		if typeof(_server_config[key]) == TYPE_INT:
			value = int(value)
		elif typeof(_server_config[key]) == TYPE_BOOL:
			value = value.to_lower() == "true"
		
		_server_config[key] = value
		config_changed.emit(key, value)
		_save_config()
		return "Set %s = %s" % [key, str(value)]
	
	return "ERROR: Unknown config key '%s'" % key

func _cmd_getconfig(args: Array) -> String:
	if args.is_empty():
		return "ERROR: Usage: getconfig <key>"
	
	var key = args[0]
	if _server_config.has(key):
		return "%s = %s" % [key, str(_server_config[key])]
	
	return "ERROR: Unknown config key '%s'" % key

func _cmd_changemap(args: Array) -> String:
	# TODO: Implement map/museum changing
	return "Map change not implemented"

func _cmd_stats() -> String:
	return """Server Statistics:
  Total Players: %d
  Total Races: %d
  Uptime: %.1f hours""" % [
		_server_stats["total_players"],
		_server_stats["total_races"],
		_server_stats["uptime_seconds"] / 3600.0
	]

func _save_config() -> void:
	"""Save configuration to file"""
	var file = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_server_config, "  "))
		file.close()
		Log.debug("ServerConfig", "Config saved to %s" % CONFIG_PATH)

func _load_config() -> void:
	"""Load configuration from file"""
	if not FileAccess.file_exists(CONFIG_PATH):
		Log.debug("ServerConfig", "No config file found, using defaults")
		return

	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file:
		var json = file.get_as_text()
		file.close()

		var parsed = JSON.parse_string(json)
		if parsed is Dictionary:
			for key in parsed:
				if _server_config.has(key):
					_server_config[key] = parsed[key]
			Log.debug("ServerConfig", "Config loaded from %s" % CONFIG_PATH)

func get_config_value(key: String) -> Variant:
	"""Get a configuration value"""
	return _server_config.get(key)

func set_config_value(key: String, value: Variant) -> void:
	"""Set a configuration value"""
	if _server_config.has(key):
		_server_config[key] = value
		config_changed.emit(key, value)
		_save_config()

func get_full_config() -> Dictionary:
	"""Get full server configuration"""
	return _server_config.duplicate()

func get_server_stats() -> Dictionary:
	"""Get server statistics"""
	return _server_stats.duplicate()
