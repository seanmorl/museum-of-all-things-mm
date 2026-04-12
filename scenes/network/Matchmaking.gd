extends Node
## Matchmaking and Server Browser System
## Allows players to find and join servers based on region, mode, and skill

class ServerInfo:
	var address: String
	var port: int
	var name: String
	var players: int
	var max_players: int
	var region: String
	var race_mode: String
	var ping: int = 0
	var password_protected: bool = false
	var events_enabled: bool = true
	var avg_skill: int = 0  # Average player skill rating
	
	func _init():
		pass
	
	func to_dict() -> Dictionary:
		return {
			"address": address,
			"port": port,
			"name": name,
			"players": players,
			"max_players": max_players,
			"region": region,
			"race_mode": race_mode,
			"ping": ping,
			"password_protected": password_protected,
			"events_enabled": events_enabled,
			"avg_skill": avg_skill
		}
	
	static func from_dict(data: Dictionary) -> ServerInfo:
		var info = ServerInfo.new()
		info.address = data.get("address", "")
		info.port = data.get("port", 7777)
		info.name = data.get("name", "Unknown Server")
		info.players = data.get("players", 0)
		info.max_players = data.get("max_players", 16)
		info.region = data.get("region", "unknown")
		info.race_mode = data.get("race_mode", "standard")
		info.ping = data.get("ping", 999)
		info.password_protected = data.get("password_protected", false)
		info.events_enabled = data.get("events_enabled", true)
		info.avg_skill = data.get("avg_skill", 0)
		return info

# Matchmaking state
enum MatchmakingState { IDLE, SEARCHING, FOUND, JOINING, FAILED }
var _matchmaking_state: MatchmakingState = MatchmakingState.IDLE

# Server browser
var _server_list: Array[ServerInfo] = []
var _filtered_server_list: Array[ServerInfo] = []
var _selected_server: ServerInfo = null

# Matchmaking preferences
var _preferred_region: String = "any"
var _preferred_mode: String = "any"
var _skill_based_matchmaking: bool = true
var _max_ping: int = 150

# Player skill rating (simplified ELO)
var _player_skill: int = 1000
var _player_stats: Dictionary = {
	"wins": 0,
	"losses": 0,
	"total_races": 0,
	"best_time": 0.0,
	"average_position": 0.0
}

# Local storage paths
const STATS_PATH := "user://player_stats.json"

signal matchmaking_state_changed(state: MatchmakingState)
signal server_list_updated(servers: Array)
signal server_ping_completed(server: ServerInfo)
signal matchmaking_found_server(server: ServerInfo)
signal matchmaking_failed(reason: String)

func _ready() -> void:
	_load_player_stats()

func _process(delta: float) -> void:
	if _matchmaking_state == MatchmakingState.SEARCHING:
		# Auto-join best server if found
		if _server_list.size() > 0:
			var best_server = _find_best_server()
			if best_server:
				_matchmaking_state = MatchmakingState.FOUND
				matchmaking_found_server.emit(best_server)
				_selected_server = best_server

func _find_best_server() -> ServerInfo:
	"""Find the best server based on preferences"""
	if _server_list.is_empty():
		return null
	
	var candidates = _filtered_server_list if _filtered_server_list.size() > 0 else _server_list
	
	# Score each server
	var best_score = -1
	var best_server: ServerInfo = null
	
	for server in candidates:
		var score = _calculate_server_score(server)
		if score > best_score:
			best_score = score
			best_server = server
	
	return best_server

func _calculate_server_score(server: ServerInfo) -> float:
	"""Calculate a score for a server based on preferences"""
	var score = 0.0
	
	# Region preference (higher score for preferred region)
	if _preferred_region != "any" and server.region == _preferred_region:
		score += 100
	
	# Ping score (lower ping = higher score)
	var ping_score = max(0, 100 - server.ping)
	score += ping_score
	
	# Player count (prefer servers with some players but not full)
	var fill_ratio = float(server.players) / float(server.max_players)
	if fill_ratio > 0.3 and fill_ratio < 0.9:
		score += 50
	elif fill_ratio > 0 and fill_ratio <= 0.3:
		score += 30
	
	# Skill-based matching
	if _skill_based_matchmaking:
		var skill_diff = abs(server.avg_skill - _player_skill)
		score += max(0, 50 - skill_diff / 100)
	
	# Mode preference
	if _preferred_mode != "any" and server.race_mode == _preferred_mode:
		score += 75
	
	return score

func search_for_servers() -> void:
	"""Start searching for servers"""
	_matchmaking_state = MatchmakingState.SEARCHING
	matchmaking_state_changed.emit(_matchmaking_state)
	_server_list.clear()
	_filtered_server_list.clear()
	
	# In production, you would query a master server here
	# For now, we'll simulate finding servers
	_simulate_server_discovery()

func _simulate_server_discovery() -> void:
	"""Simulate discovering servers (replace with real master server queries)"""
	# This is placeholder code - in production you'd HTTP request a master server
	await get_tree().create_timer(2.0).timeout
	
	# Add some dummy servers for testing
	var test_servers = [
		_create_test_server("US East #1", "us-east", 12, 16, 45),
		_create_test_server("US West Racing", "us-west", 8, 16, 80),
		_create_test_server("EU Central", "eu-central", 10, 16, 120),
		_create_test_server("Asia Tokyo", "asia-tokyo", 6, 16, 150),
	]
	
	for server in test_servers:
		_add_server(server)
	
	_apply_filters()
	server_list_updated.emit(_filtered_server_list)

func _create_test_server(name: String, region: String, players: int, max_players: int, ping: int) -> ServerInfo:
	var server = ServerInfo.new()
	server.name = name
	server.region = region
	server.players = players
	server.max_players = max_players
	server.ping = ping
	server.address = "server.example.com"
	server.port = 7777
	server.race_mode = "standard"
	server.avg_skill = _player_skill + randi_range(-200, 200)
	return server

func _add_server(server: ServerInfo) -> void:
	"""Add a server to the list"""
	_server_list.append(server)
	server_ping_completed.emit(server)

func stop_search() -> void:
	"""Stop searching for servers"""
	_matchmaking_state = MatchmakingState.IDLE
	matchmaking_state_changed.emit(_matchmaking_state)

func join_server(server: ServerInfo) -> void:
	"""Join a selected server"""
	_selected_server = server
	_matchmaking_state = MatchmakingState.JOINING
	matchmaking_state_changed.emit(_matchmaking_state)

	# Attempt to join
	var error = await NetworkManager.join_game(server.address, server.port)
	if error != OK:
		_matchmaking_state = MatchmakingState.FAILED
		matchmaking_failed.emit("Failed to connect: %s" % error_string(error))
	else:
		# Success - state will be updated when connected
		pass

func quick_join() -> void:
	"""Quick join the best available server"""
	search_for_servers()
	# The _process function will auto-join the best server

func apply_filters(region: String = "", mode: String = "", max_ping: int = -1) -> void:
	"""Apply filters to server list"""
	if region != "":
		_preferred_region = region
	if mode != "":
		_preferred_mode = mode
	if max_ping >= 0:
		_max_ping = max_ping
	
	_apply_filters()

func _apply_filters() -> void:
	"""Apply current filters to server list"""
	_filtered_server_list.clear()
	
	for server in _server_list:
		if _preferred_region != "any" and server.region != _preferred_region:
			continue
		if _preferred_mode != "any" and server.race_mode != _preferred_mode:
			continue
		if server.ping > _max_ping:
			continue
		if server.players >= server.max_players:
			continue
		
		_filtered_server_list.append(server)
	
	server_list_updated.emit(_filtered_server_list)

func get_server_list() -> Array:
	"""Get the current server list"""
	return _filtered_server_list if _filtered_server_list.size() > 0 else _server_list

func get_selected_server() -> ServerInfo:
	"""Get the currently selected server"""
	return _selected_server

func get_matchmaking_state() -> MatchmakingState:
	"""Get current matchmaking state"""
	return _matchmaking_state

# Player stats and skill tracking

func record_race_result(position: int, total_players: int, time: float) -> void:
	"""Record a race result and update skill rating"""
	_player_stats["total_races"] += 1
	
	if position == 1:
		_player_stats["wins"] += 1
	else:
		_player_stats["losses"] += 1
	
	# Update average position
	var total = _player_stats["total_races"]
	var avg = _player_stats["average_position"]
	_player_stats["average_position"] = avg + (position - avg) / total
	
	# Update best time
	if _player_stats["best_time"] == 0.0 or time < _player_stats["best_time"]:
		_player_stats["best_time"] = time
	
	# Update skill rating (simplified ELO)
	var k_factor = 32
	var expected_score = 1.0 / (1.0 + pow(10, (position - 1) / 400))
	var actual_score = 1.0 if position == 1 else 0.0
	_player_skill += int(k_factor * (actual_score - expected_score))
	
	# Clamp skill rating
	_player_skill = clamp(_player_skill, 0, 3000)
	
	_save_player_stats()

func get_player_skill() -> int:
	"""Get current player skill rating"""
	return _player_skill

func get_player_stats() -> Dictionary:
	"""Get player statistics"""
	return _player_stats.duplicate()

func _save_player_stats() -> void:
	"""Save player stats to file"""
	var file = FileAccess.open(STATS_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"skill": _player_skill,
			"stats": _player_stats
		}
		file.store_string(JSON.stringify(data, "  "))
		file.close()

func _load_player_stats() -> void:
	"""Load player stats from file"""
	if not FileAccess.file_exists(STATS_PATH):
		return
	
	var file = FileAccess.open(STATS_PATH, FileAccess.READ)
	if file:
		var json = file.get_as_text()
		file.close()
		
		var parsed = JSON.parse_string(json)
		if parsed is Dictionary:
			_player_skill = parsed.get("skill", 1000)
			var stats = parsed.get("stats", {})
			for key in stats:
				_player_stats[key] = stats[key]

func reset_player_stats() -> void:
	"""Reset all player stats"""
	_player_skill = 1000
	_player_stats = {
		"wins": 0,
		"losses": 0,
		"total_races": 0,
		"best_time": 0.0,
		"average_position": 0.0
	}
	_save_player_stats()

func set_skill_based_matchmaking(enabled: bool) -> void:
	_skill_based_matchmaking = enabled

func get_skill_based_matchmaking() -> bool:
	return _skill_based_matchmaking

func set_preferred_region(region: String) -> void:
	_preferred_region = region

func get_preferred_region() -> String:
	return _preferred_region
