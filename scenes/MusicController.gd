extends Node3D
## Controls background music playback with smooth crossfade between tracks.

const FADE_DURATION: float = 2.0
const TARGET_DB: float = 0.0

@onready var _tracks: Array[AudioStream] = [
	preload("res://assets/sound/Music/MoAT Track 1 - Waiting on the Weather.ogg"),
	preload("res://assets/sound/Music/MoAT Track 2 - Comfort on the way.ogg"),
	preload("res://assets/sound/Music/MoAT Track 3 - Life is Older Than You Knew.ogg"),
	preload("res://assets/sound/Music/MoAT Track 4 - Blue Sky Inside.ogg"),
	preload("res://assets/sound/Music/MoAT Track 5 - Waiting for a ride.ogg"),
	preload("res://assets/sound/Music/MoAT Track 6 - Memory In Passing.ogg"),
	preload("res://assets/sound/Music/MoAT Track 7 - Blue Sky Outside.ogg"),
	preload("res://assets/sound/Music/MoAT Track 8 - Stillness After Closing.ogg"),
]

@export var min_space_start: float = 20.0
@export var min_space: float = 60.0 * 3
@export var max_space: float = 60.0 * 6

var _player_a: AudioStreamPlayer = null
var _player_b: AudioStreamPlayer = null
var _last_track: int = -1
var _current_player: AudioStreamPlayer = null


func _ready() -> void:
	# Set up two audio players for crossfade
	_player_a = _get_or_create_player("AudioPlayerA")
	_player_b = _get_or_create_player("AudioPlayerB")
	_current_player = _player_a

	var wait_time: float = randf_range(min_space_start, max_space)
	if OS.is_debug_build():
		Log.debug("MusicController", "waiting for first track. time=%s" % wait_time)
	get_tree().create_timer(wait_time).timeout.connect(_play_track, ConnectFlags.CONNECT_ONE_SHOT)


func _get_or_create_player(name: String) -> AudioStreamPlayer:
	var existing := get_node_or_null(name)
	if existing:
		return existing
	var p := AudioStreamPlayer.new()
	p.name = name
	p.bus = "Music"
	add_child(p)
	return p


func _play_track() -> void:
	var track_idx: int
	if _last_track < 0:
		track_idx = randi() % _tracks.size()
	else:
		track_idx = (_last_track + (randi() % (_tracks.size() - 1))) % _tracks.size()
	_last_track = track_idx

	if OS.is_debug_build():
		Log.debug("MusicController", "crossfading to track #%d" % track_idx)

	# Choose the inactive player for the new track
	var new_player: AudioStreamPlayer = _player_a if _current_player != _player_a else _player_b
	var old_player: AudioStreamPlayer = _current_player

	new_player.stream = _tracks[track_idx]
	new_player.volume_db = -80.0
	new_player.seek(0.0)
	new_player.play()

	# Crossfade: old out, new in
	var tw := create_tween().set_parallel(true)
	if old_player:
		tw.tween_property(old_player, "volume_db", -80.0, FADE_DURATION)
	tw.tween_property(new_player, "volume_db", TARGET_DB, FADE_DURATION)
	tw.finished.connect(func():
		if old_player:
			old_player.stop()
	)

	_current_player = new_player
	# Schedule next track after this one finishes (use the track's actual length minus fade)
	var track_len: float = _tracks[track_idx].get_length()
	if track_len > 0:
		get_tree().create_timer(track_len - FADE_DURATION).timeout.connect(_play_track,
			ConnectFlags.CONNECT_ONE_SHOT)


func _reset_timer() -> void:
	# Legacy — kept in case anything calls it externally
	var wait_time: float = randf_range(min_space, max_space)
	if OS.is_debug_build():
		Log.debug("MusicController", "waiting for next track. time=%s" % wait_time)
	get_tree().create_timer(wait_time).timeout.connect(_play_track,
		ConnectFlags.CONNECT_ONE_SHOT)
