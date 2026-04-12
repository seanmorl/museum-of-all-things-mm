extends RefCounted
class_name GameState
## Central game state management - single source of truth for game state.
## This is a pure GDScript class (no Godot dependencies) for easy testing.

enum State {
	MENU,          # Main menu, no game active
	LOBBY,         # In lobby, waiting for players
	VOTING,        # Race target vote in progress
	RACE_ACTIVE,   # Race in progress
	RACE_FINISHED  # Race completed, showing results
}

enum SubState {
	NONE,
	COUNTDOWN,     # 3-2-1-GO countdown
	LOADING,       # Exhibit generating
	PLAYING        # Actively playing
}

# Current state
var current_state: State = State.MENU
var sub_state: SubState = SubState.NONE

# Race data
var race_target: String = ""
var race_start: String = ""
var race_start_time: float = 0.0
var race_elapsed: float = 0.0
var race_winner: String = ""
var race_winner_time: float = 0.0

# Vote data
var vote_candidates: Array[String] = []
var vote_deadline: float = 0.0

# Player data (local player)
var local_player_name: String = ""
var local_player_room: String = "Lobby"
var local_player_position: Vector3 = Vector3.ZERO

# Multiplayer state
var is_server: bool = false
var connected_peers: Array[int] = []

# Daily Challenge state
var daily_challenge_active: bool = false
var daily_challenge_target: String = ""
var daily_challenge_start: String = ""

# --- State Transitions ---

func enter_menu() -> void:
	current_state = State.MENU
	sub_state = SubState.NONE
	_clear_race_data()
	_clear_vote_data()

func enter_lobby() -> void:
	current_state = State.LOBBY
	sub_state = SubState.NONE
	local_player_room = "Lobby"

func enter_voting(candidates: Array[String], deadline: float) -> void:
	current_state = State.VOTING
	sub_state = SubState.NONE
	vote_candidates = candidates
	vote_deadline = deadline

func enter_race(target: String, start: String) -> void:
	current_state = State.RACE_ACTIVE
	sub_state = SubState.LOADING  # Start with loading state
	race_target = target
	race_start = start
	race_start_time = Time.get_unix_time_from_system()
	race_elapsed = 0.0

func set_race_sub_state(new_sub_state: SubState) -> void:
	sub_state = new_sub_state

func finish_race(winner_name: String, winner_time: float) -> void:
	current_state = State.RACE_FINISHED
	sub_state = SubState.NONE
	race_winner = winner_name
	race_winner_time = winner_time

# --- Helpers ---

func _clear_race_data() -> void:
	race_target = ""
	race_start = ""
	race_start_time = 0.0
	race_elapsed = 0.0
	race_winner = ""
	race_winner_time = 0.0

func _clear_vote_data() -> void:
	vote_candidates = []
	vote_deadline = 0.0

# --- State Queries ---

func is_race_active() -> bool:
	return current_state == State.RACE_ACTIVE

func is_voting_active() -> bool:
	return current_state == State.VOTING

func can_vote() -> bool:
	return current_state == State.VOTING and Time.get_unix_time_from_system() < vote_deadline

func get_race_elapsed() -> float:
	if current_state != State.RACE_ACTIVE:
		return 0.0
	return Time.get_unix_time_from_system() - race_start_time

# --- State Machine Helpers ---

func can_transition_to(new_state: State) -> bool:
	"""Check if state transition is valid."""
	match current_state:
		State.MENU:
			return new_state in [State.LOBBY]
		State.LOBBY:
			return new_state in [State.MENU, State.VOTING]
		State.VOTING:
			return new_state in [State.RACE_ACTIVE, State.LOBBY]
		State.RACE_ACTIVE:
			return new_state in [State.RACE_FINISHED, State.LOBBY]
		State.RACE_FINISHED:
			return new_state in [State.LOBBY, State.MENU]
	return false

func enter_state(new_state: State) -> void:
	"""Safely transition to a new state."""
	if not can_transition_to(new_state):
		Log.warn("GameState", "Invalid transition from %s to %s" % [State.keys()[current_state], State.keys()[new_state]])
		return

	var old_state = current_state
	current_state = new_state
	sub_state = SubState.NONE
	Log.info("GameState", "%s → %s" % [State.keys()[old_state], State.keys()[new_state]])

# --- Serialization (for network sync) ---

func to_dict() -> Dictionary:
	return {
		"current_state": current_state,
		"sub_state": sub_state,
		"race_target": race_target,
		"race_start": race_start,
		"race_elapsed": get_race_elapsed(),
		"race_winner": race_winner,
		"vote_candidates": vote_candidates,
		"is_server": is_server
	}

static func from_dict(data: Dictionary) -> GameState:
	var state = GameState.new()
	state.current_state = data.get("current_state", State.MENU)
	state.sub_state = data.get("sub_state", SubState.NONE)
	state.race_target = data.get("race_target", "")
	state.race_start = data.get("race_start", "")
	state.race_winner = data.get("race_winner", "")
	state.vote_candidates = data.get("vote_candidates", [])
	state.is_server = data.get("is_server", false)
	return state
