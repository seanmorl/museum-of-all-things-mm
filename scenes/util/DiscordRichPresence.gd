extends Node
## Discord Rich Presence integration using Discord Social SDK.
## Manages activity state for menus, lobby, races, and room changes.

const DISCORD_APPLICATION_ID: int = 1486070721292669099

var _client: DiscordClient = null
var _current_state: String = "In Menu"
var _current_details: String = ""
var _current_room: String = ""
var _race_target: String = ""
var _session_start: int = 0
var _client_ready: bool = false


func _ready() -> void:
	# Initialize Discord client
	_client = DiscordClient.new()
	_client.set_application_id(DISCORD_APPLICATION_ID)
	_client.set_status_changed_callback(_on_client_state_changed)
	_client.connect_discord()

	_session_start = int(Time.get_unix_time_from_system())

	Log.debug("Discord", "Initialization started, waiting for authorization...")

	set_in_menu()
	_connect_signals()


func _process(_delta: float) -> void:
	# Required for SDK callbacks to fire
	Discord.run_callbacks()


func _on_client_state_changed(status: DiscordClientStatus.Enum, error: DiscordClientError.Enum, _error_detail: int) -> void:
	if status == DiscordClientStatus.READY:
		_client_ready = true
		Log.debug("Discord", "Client READY - Rich Presence active")
		# Update presence now that we're ready
		_update_presence()
	elif error != DiscordClientError.NONE:
		_client_ready = false
		Log.warn("Discord", "Discord client error - not connected")


func _connect_signals() -> void:
	if RaceManager:
		RaceManager.race_started.connect(_on_race_started)
		RaceManager.race_ended.connect(_on_race_ended)
		RaceManager.race_cancelled.connect(_on_race_cancelled)
		RaceManager.vote_started.connect(_on_vote_started)
		RaceManager.vote_cancelled.connect(_on_vote_cancelled)

	if SettingsEvents:
		SettingsEvents.set_current_room.connect(_on_room_changed)


func _on_vote_started(_candidates: Array) -> void:
	set_in_lobby()


func _on_vote_cancelled() -> void:
	set_in_lobby()


func _on_race_started(target_article: String, _start_article: String) -> void:
	start_race(target_article)


func _on_race_ended(_winner_peer_id: int, _winner_name: String) -> void:
	end_race()


func _on_race_cancelled() -> void:
	cancel_race()


func _on_room_changed(room_name: Variant) -> void:
	if room_name is String:
		set_room(room_name)


func _update_presence() -> void:
	if not _client_ready or _client == null:
		return

	var activity := DiscordActivity.new()
	
	match _current_state:
		"In Menu":
			activity.set_type(DiscordActivityTypes.PLAYING)
			activity.set_state("In Menu")
			activity.set_details("Session: " + _get_elapsed_time())
		"In Lobby":
			activity.set_type(DiscordActivityTypes.PLAYING)
			activity.set_state("In Lobby")
			activity.set_details("Exploring: " + _current_room if _current_room else "In Lobby")
		"Racing":
			activity.set_type(DiscordActivityTypes.PLAYING)
			activity.set_state("Racing")
			activity.set_details("Target: " + _race_target if _race_target else "Racing")
			activity.set_start_timestamp(_session_start)
		"Race Finished":
			activity.set_type(DiscordActivityTypes.PLAYING)
			activity.set_state("Race Finished")
			activity.set_details("Finished race to: " + _race_target if _race_target else "Race Complete")

	# Set application assets (these should match keys in Discord Dev Portal)
	activity.set_large_image("game_icon")
	activity.set_large_image_text("Museum of All Things")

	_client.update_rich_presence(activity, _on_rich_presence_updated)


func _on_rich_presence_updated(result: DiscordClientResult) -> void:
	if not result.successful():
		Log.warn("Discord", "Rich presence update failed: %s" % result)


func _get_elapsed_time() -> String:
	var elapsed = Time.get_unix_time_from_system() - _session_start
	var minutes = int(elapsed) / 60
	var seconds = int(elapsed) % 60
	return "%02d:%02d" % [minutes, seconds]


func set_in_menu() -> void:
	_current_state = "In Menu"
	_current_details = ""
	_race_target = ""
	_current_room = ""
	_session_start = int(Time.get_unix_time_from_system())
	_update_presence()
	Log.debug("Discord", "Set to menu")


func set_in_lobby(room_name: String = "Lobby") -> void:
	_current_state = "In Lobby"
	_current_room = room_name
	_race_target = ""
	_update_presence()
	Log.debug("Discord", "Set to lobby: %s" % room_name)


func set_room(room_name: String) -> void:
	_current_room = room_name
	_update_presence()


func start_race(target: String) -> void:
	_current_state = "Racing"
	_race_target = target
	_session_start = int(Time.get_unix_time_from_system())
	_update_presence()
	Log.debug("Discord", "Race started to: %s" % target)


func end_race() -> void:
	_current_state = "Race Finished"
	_update_presence()
	Log.debug("Discord", "Race ended")


func cancel_race() -> void:
	_current_state = "In Lobby"
	_race_target = ""
	_update_presence()
	Log.debug("Discord", "Race cancelled")


func _exit_tree() -> void:
	if _client != null:
		_client.disconnect_discord()
		_client = null
