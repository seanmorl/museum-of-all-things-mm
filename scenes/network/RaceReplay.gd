extends Node
## Race Replay System
## Records and plays back race data for spectating and analysis

class ReplayFrame:
	var timestamp: float
	var peer_id: int
	var position: Vector3
	var rotation: Vector3
	var velocity: Vector3
	var is_crouching: bool
	var article_visited: String = ""  # Article reached at this frame
	
	func to_dict() -> Dictionary:
		return {
			"timestamp": timestamp,
			"peer_id": peer_id,
			"position": [position.x, position.y, position.z],
			"rotation": [rotation.x, rotation.y, rotation.z],
			"velocity": [velocity.x, velocity.y, velocity.z],
			"is_crouching": is_crouching,
			"article_visited": article_visited
		}
	
	static func from_dict(data: Dictionary) -> ReplayFrame:
		var frame = ReplayFrame.new()
		frame.timestamp = data["timestamp"]
		frame.peer_id = data["peer_id"]
		frame.position = Vector3(data["position"][0], data["position"][1], data["position"][2])
		frame.rotation = Vector3(data["rotation"][0], data["rotation"][1], data["rotation"][2])
		frame.velocity = Vector3(data["velocity"][0], data["velocity"][1], data["velocity"][2])
		frame.is_crouching = data["is_crouching"]
		frame.article_visited = data.get("article_visited", "")
		return frame

class ReplayData:
	var race_id: String
	var start_article: String
	var target_article: String
	var start_time: float
	var end_time: float
	var frames: Array[ReplayFrame] = []
	var players: Dictionary = {}  # peer_id -> player info
	
	func to_dict() -> Dictionary:
		var frames_data = []
		for frame in frames:
			frames_data.append(frame.to_dict())
		
		return {
			"race_id": race_id,
			"start_article": start_article,
			"target_article": target_article,
			"start_time": start_time,
			"end_time": end_time,
			"frames": frames_data,
			"players": players
		}
	
	static func from_dict(data: Dictionary) -> ReplayData:
		var replay = ReplayData.new()
		replay.race_id = data["race_id"]
		replay.start_article = data["start_article"]
		replay.target_article = data["target_article"]
		replay.start_time = data["start_time"]
		replay.end_time = data["end_time"]
		
		for frame_data in data["frames"]:
			replay.frames.append(ReplayFrame.from_dict(frame_data))
		
		replay.players = data.get("players", {})
		return replay

# Recording state
var _is_recording: bool = false
var _current_replay: ReplayData = null
var _recording_frame_interval: float = 0.016  # 60 FPS recording
var _recording_timer: float = 0.0

# Playback state
var _is_playing: bool = false
var _is_paused: bool = false
var _playback_replay: ReplayData = null
var _playback_time: float = 0.0
var _playback_speed: float = 1.0
var _playback_frame_index: int = 0

# Ghost player for comparison
var _ghost_enabled: bool = false
var _ghost_replay: ReplayData = null
var _ghost_peer_id: int = -1

# Storage
const REPLAYS_DIR := "user://replays/"

signal recording_started(race_id: String)
signal recording_stopped()
signal playback_started()
signal playback_paused()
signal playback_stopped()
signal playback_frame_updated(frame: ReplayFrame)
signal playback_completed()

func _ready() -> void:
	_ensure_replays_directory()

func _process(delta: float) -> void:
	if _is_recording:
		_process_recording(delta)
	
	if _is_playing and not _is_paused:
		_process_playback(delta)

func _process_recording(delta: float) -> void:
	"""Record player positions during race"""
	_recording_timer += delta
	
	if _recording_timer >= _recording_frame_interval:
		_recording_timer = 0.0
		_record_frame()

func _record_frame() -> void:
	"""Record a single frame of replay data"""
	if not _current_replay:
		return
	
	# Record all players
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if not player is CharacterBody3D:
			continue

		var frame = ReplayFrame.new()
		frame.timestamp = Time.get_ticks_msec() / 1000.0 - _current_replay.start_time
		frame.peer_id = player.get("peer_id") if player.has_meta("peer_id") else 0
		frame.position = player.global_position
		frame.rotation = Vector3(0, player.rotation.y, 0)
		frame.velocity = player.velocity if player.has_method("get_velocity") else Vector3.ZERO
		frame.is_crouching = player.has_method("is_crouching") and player.is_crouching()

		_current_replay.frames.append(frame)

func _process_playback(delta: float) -> void:
	"""Play back recorded replay data"""
	if not _playback_replay:
		return
	
	_playback_time += delta * _playback_speed
	
	# Find the current frame
	var target_frame = _find_frame_at_time(_playback_time)
	if target_frame >= _playback_replay.frames.size():
		_playback_completed()
		return
	
	_playback_frame_index = target_frame
	var frame = _playback_replay.frames[target_frame]
	playback_frame_updated.emit(frame)

func _find_frame_at_time(time: float) -> int:
	"""Find the frame index at a given time"""
	if not _playback_replay or _playback_replay.frames.is_empty():
		return 0
	
	for i in range(_playback_replay.frames.size()):
		if _playback_replay.frames[i].timestamp >= time:
			return max(0, i - 1)
	
	return _playback_replay.frames.size() - 1

# Recording API

func start_recording(race_id: String, start_article: String, target_article: String) -> void:
	"""Start recording a race"""
	_is_recording = true
	_recording_timer = 0.0
	
	_current_replay = ReplayData.new()
	_current_replay.race_id = race_id
	_current_replay.start_article = start_article
	_current_replay.target_article = target_article
	_current_replay.start_time = Time.get_ticks_msec() / 1000.0
	
	# Record player info
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.has_method("get_peer_id"):
			var peer_id = player.get_peer_id()
			_current_replay.players[peer_id] = {
				"name": player.get("player_name") if "player_name" in player else "Player",
				"color": (player.get("player_color") if "player_color" in player else Color.WHITE).to_html()
			}
	
	recording_started.emit(race_id)
	Log.info("Replay", "Started recording race: %s" % race_id)

func stop_recording() -> void:
	"""Stop recording"""
	_is_recording = false
	_current_replay.end_time = Time.get_ticks_msec() / 1000.0 - _current_replay.start_time

	recording_stopped.emit()
	Log.info("Replay", "Stopped recording. Total frames: %d" % _current_replay.frames.size())

func save_replay(filename: String = "") -> String:
	"""Save the current replay to file"""
	if not _current_replay:
		return ""

	if filename == "":
		filename = "replay_%s_%d.json" % [_current_replay.race_id, int(Time.get_unix_time_from_system())]

	var path = REPLAYS_DIR + filename
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_current_replay.to_dict(), ""))
		file.close()
		Log.info("Replay", "Saved replay to: %s" % path)
		return path
	
	return ""

func load_replay(path: String) -> bool:
	"""Load a replay from file"""
	if not FileAccess.file_exists(path):
		return false
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		Log.error("RaceReplay", "Failed to open replay file: %s" % path)
		return false
	var json = file.get_as_text()
	file.close()
	if json.is_empty():
		Log.error("RaceReplay", "Replay file is empty: %s" % path)
		return false
	
	var parsed = JSON.parse_string(json)
	if parsed == null:
		Log.error("RaceReplay", "Failed to parse replay JSON: %s" % path)
		return false
	if parsed is Dictionary:
		_playback_replay = ReplayData.from_dict(parsed)
		return true
	
	return false

# Playback API

func start_playback(replay: ReplayData = null) -> void:
	"""Start playing back a replay"""
	if replay:
		_playback_replay = replay
	
	if not _playback_replay:
		return
	
	_is_playing = true
	_is_paused = false
	_playback_time = 0.0
	_playback_frame_index = 0
	_playback_speed = 1.0
	
	playback_started.emit()
	Log.info("Replay", "Started playback")

func pause_playback() -> void:
	"""Pause playback"""
	_is_paused = true
	playback_paused.emit()

func resume_playback() -> void:
	"""Resume paused playback"""
	_is_paused = false
	playback_started.emit()

func stop_playback() -> void:
	"""Stop playback"""
	_is_playing = false
	_is_paused = false
	_playback_time = 0.0
	_playback_frame_index = 0
	
	playback_stopped.emit()

func set_playback_speed(speed: float) -> void:
	"""Set playback speed (0.5 = half speed, 2.0 = double)"""
	_playback_speed = clamp(speed, 0.25, 4.0)

func seek_to_time(time: float) -> void:
	"""Seek to a specific time in the replay"""
	_playback_time = clamp(time, 0.0, _playback_replay.end_time if _playback_replay else 0.0)

func get_playback_time() -> float:
	"""Get current playback time"""
	return _playback_time

func get_playback_duration() -> float:
	"""Get total replay duration"""
	return _playback_replay.end_time if _playback_replay else 0.0

func is_playing() -> bool:
	return _is_playing

func is_paused() -> bool:
	return _is_paused

func is_recording() -> bool:
	return _is_recording

# Ghost Player API

func enable_ghost(replay: ReplayData, peer_id: int = -1) -> void:
	"""Enable ghost player from a replay"""
	_ghost_replay = replay
	_ghost_peer_id = peer_id
	_ghost_enabled = true
	Log.debug("Replay", "Ghost enabled")

func disable_ghost() -> void:
	"""Disable ghost player"""
	_ghost_enabled = false
	_ghost_replay = null
	_ghost_peer_id = -1
	Log.debug("Replay", "Ghost disabled")

func get_ghost_position(time: float) -> Vector3:
	"""Get ghost position at a given time"""
	if not _ghost_replay or _ghost_peer_id < 0:
		return Vector3.ZERO
	
	var frame_idx = _find_frame_at_time(time)
	for i in range(frame_idx, _ghost_replay.frames.size()):
		if _ghost_replay.frames[i].peer_id == _ghost_peer_id:
			return _ghost_replay.frames[i].position
	
	return Vector3.ZERO

func get_ghost_replay() -> ReplayData:
	"""Get the current ghost replay"""
	return _ghost_replay

# Utility

func _ensure_replays_directory() -> void:
	"""Create replays directory if it doesn't exist"""
	if not DirAccess.dir_exists_absolute(REPLAYS_DIR):
		DirAccess.make_dir_recursive_absolute(REPLAYS_DIR)

func list_replays() -> Array:
	"""List all saved replays"""
	var replays = []
	var dir = DirAccess.open(REPLAYS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				replays.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	return replays

func delete_replay(filename: String) -> bool:
	"""Delete a replay file"""
	var path = REPLAYS_DIR + filename
	return DirAccess.remove_absolute(path) == OK

func get_replay_info(filename: String) -> Dictionary:
	"""Get info about a replay file"""
	var path = REPLAYS_DIR + filename
	if not FileAccess.file_exists(path):
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var json = file.get_as_text()
		file.close()
		
		var parsed = JSON.parse_string(json)
		if parsed is Dictionary:
			return {
				"filename": filename,
				"race_id": parsed.get("race_id", ""),
				"target": parsed.get("target_article", ""),
				"duration": parsed.get("end_time", 0),
				"frames": parsed.get("frames", []).size()
			}
	
	return {}

func _playback_completed() -> void:
	"""Called when playback completes"""
	stop_playback()
	playback_completed.emit()

func clear_current_replay() -> void:
	"""Clear the current replay data"""
	_current_replay = null
	_playback_replay = null
