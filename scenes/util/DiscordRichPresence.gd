extends Node
## Discord Rich Presence - placeholder for future implementation.

var _current_state: String = "In Menu"
var _current_room: String = ""
var _race_target: String = ""
var _session_start: int = 0


func _ready() -> void:
	_session_start = int(Time.get_unix_time_from_system())
	set_in_menu()
	_connect_signals()


func _process(_delta: float) -> void:
	# Placeholder - Discord integration disabled for now
	pass


func _connect_signals() -> void:
	if RaceManager:
		RaceManager.race_started.connect(_on_race_started)
		RaceManager.race_ended.connect(_on_race_ended)
		RaceManager.race_cancelled.connect(_on_race_cancelled)
		RaceManager.vote_started.connect(_on_vote_started)
		RaceManager.vote_cancelled.connect(_on_vote_cancelled)

	if SettingsEvents:
		SettingsEvents.set_current_room.connect(_on_room_changed)


func _on_race_started(target: String, _start: String) -> void:
	start_race(target)


func _on_race_ended(_winner: int, _name: String) -> void:
	end_race()


func _on_race_cancelled() -> void:
	cancel_race()


func _on_vote_started(_candidates: Array) -> void:
	set_in_lobby()


func _on_vote_cancelled() -> void:
	set_in_lobby()


func _on_room_changed(room_name: Variant) -> void:
	if room_name is String:
		set_room(room_name)


func set_in_menu() -> void:
	_current_state = "In Menu"
	_current_room = ""
	_race_target = ""
	_session_start = int(Time.get_unix_time_from_system())


func set_in_lobby(room_name: String = "Lobby") -> void:
	_current_state = "In Lobby"
	_current_room = room_name
	_race_target = ""


func set_room(room_name: String) -> void:
	_current_room = room_name


func start_race(target: String) -> void:
	_current_state = "Racing"
	_race_target = target
	_session_start = int(Time.get_unix_time_from_system())


func end_race() -> void:
	_current_state = "Race Finished"


func cancel_race() -> void:
	_current_state = "In Lobby"
	_race_target = ""


func _exit_tree() -> void:
	pass
