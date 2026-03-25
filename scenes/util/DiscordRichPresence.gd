# extends Node

# const DISCORD_APPLICATION_ID: int = 1486070721292669099

# var _current_state: String = "In Menu"
# var _current_details: String = ""
# var _current_room: String = ""
# var _race_target: String = ""
# var _session_start: int = 0
# var _presence_dirty: bool = false

# func _ready() -> void:
# 	DiscordRPC.app_id = DISCORD_APPLICATION_ID
# 	_session_start = int(Time.get_unix_time_from_system())
    
# 	print("[Discord] Initialization started, waiting for authorization...")
    
# 	if DiscordRPC.get_is_discord_working():
# 		print("[Discord] INFO: Discord is working")
# 	else:
# 		print("[Discord] WARNING: Discord not detected")
    
# 	set_in_menu()
# 	_connect_signals()

# func _connect_signals() -> void:
# 	if RaceManager:
# 		RaceManager.race_started.connect(_on_race_started)
# 		RaceManager.race_ended.connect(_on_race_ended)
# 		RaceManager.race_cancelled.connect(_on_race_cancelled)
# 		RaceManager.vote_started.connect(_on_vote_started)
# 		RaceManager.vote_cancelled.connect(_on_vote_cancelled)
    
# 	if SettingsEvents:
# 		SettingsEvents.set_current_room.connect(_on_room_changed)

# func _on_vote_started(_candidates: Array) -> void:
# 	set_in_lobby()

# func _on_vote_cancelled() -> void:
# 	set_in_lobby()

# func _on_race_started(target_article: String, _start_article: String) -> void:
# 	start_race(target_article)

# func _on_race_ended(_winner_peer_id: int, _winner_name: String) -> void:
# 	end_race()

# func _on_race_cancelled() -> void:
# 	cancel_race()

# func _on_room_changed(room_name: Variant) -> void:
# 	if room_name is String:
# 		set_room(room_name)

# func _process(_delta: float) -> void:
# 	DiscordRPC.run_callbacks()
    
# 	if _presence_dirty and DiscordRPC.get_is_discord_working():
# 		_update_presence()
# 		_presence_dirty = false

# func _update_presence() -> void:
# 	if not DiscordRPC.get_is_discord_working():
# 		return
    
# 	var state = _current_state
# 	var details = _current_details
    
# 	match state:
# 		"In Menu":
# 			details = "Session: " + _get_elapsed_time()
# 		"In Lobby":
# 			details = "Exploring: " + _current_room if _current_room else "In Lobby"
# 		"Racing":
# 			details = "Target: " + _race_target if _race_target else "Racing"
# 			DiscordRPC.start_timestamp = _session_start
# 		"Race Finished":
# 			details = "Finished race to: " + _race_target if _race_target else "Race Complete"
    
# 	DiscordRPC.state = state
# 	DiscordRPC.details = details
# 	DiscordRPC.large_image = "game_icon"
# 	DiscordRPC.large_image_text = "Museum of All Things"
# 	DiscordRPC.refresh()

# func _get_elapsed_time() -> String:
# 	var elapsed = Time.get_unix_time_from_system() - _session_start
# 	var minutes = int(elapsed) / 60
# 	var seconds = int(elapsed) % 60
# 	return "%02d:%02d" % [minutes, seconds]

# func set_in_menu() -> void:
# 	_current_state = "In Menu"
# 	_current_details = ""
# 	_race_target = ""
# 	_current_room = ""
# 	_session_start = int(Time.get_unix_time_from_system())
# 	_presence_dirty = true
# 	print("[Discord] Set to menu")

# func set_in_lobby(room_name: String = "Lobby") -> void:
# 	_current_state = "In Lobby"
# 	_current_room = room_name
# 	_race_target = ""
# 	_presence_dirty = true
# 	print("[Discord] Set to lobby: ", room_name)

# func set_room(room_name: String) -> void:
# 	_current_room = room_name
# 	_presence_dirty = true

# func start_race(target: String) -> void:
# 	_current_state = "Racing"
# 	_race_target = target
# 	_session_start = int(Time.get_unix_time_from_system())
# 	_presence_dirty = true
# 	print("[Discord] Race started to: ", target)

# func end_race() -> void:
# 	_current_state = "Race Finished"
# 	_presence_dirty = true
# 	print("[Discord] Race ended")

# func cancel_race() -> void:
# 	_current_state = "In Lobby"
# 	_race_target = ""
# 	_presence_dirty = true
# 	print("[Discord] Race cancelled")
