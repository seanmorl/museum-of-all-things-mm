extends Node3D
## Controls ambient audio including background tracks, voice events, and random ambience events.
##
## Theme dimming: instead of writing to the shared Ambience bus (which AudioSettings.tscn
## sliders also own and will overwrite on open), we apply a volume *offset* directly to
## every AudioStreamPlayer this node creates. The user's bus-level slider is left untouched.

var _current_player: AudioStreamPlayer = null
var _fade_duration: float = 2.5

## Volume offset (dB) applied per-player on top of the bus level.
## 0 dB = no change (light mode).  -9 dB ≈ half perceived loudness (dark mode).
const _OFFSET_LIGHT: float          =  0.0
const _OFFSET_DARK:  float          = -9.0
const _VOLUME_TWEEN_DURATION: float =  1.5

## Current target offset — new players start here so track crossfades stay consistent.
var _current_offset: float = _OFFSET_LIGHT

var _ambience_tracks: Array[AudioStream] = [
	preload("res://assets/sound/Global Ambience/Global ambience 1.ogg"),
	preload("res://assets/sound/Global Ambience/Global ambience 2.ogg"),
	preload("res://assets/sound/Global Ambience/Global ambience 3.ogg"),
	preload("res://assets/sound/Global Ambience/Global ambience 4.ogg"),
]

var _ambient_voice_space_min: int = 60
var _ambient_voice_space_max: int = 300
var _ambient_voices: Array[AudioStream] = [
	preload("res://assets/sound/Voices/Voices 1.ogg"),
	preload("res://assets/sound/Voices/Voices 2.ogg"),
	preload("res://assets/sound/Voices/Voices 3.ogg"),
	preload("res://assets/sound/Voices/Voices 4.ogg"),
	preload("res://assets/sound/Voices/Voices 5.ogg"),
	preload("res://assets/sound/Voices/Voices 6.ogg"),
	preload("res://assets/sound/Voices/Voices 7.ogg"),
	preload("res://assets/sound/Voices/Voices 8.ogg"),
	preload("res://assets/sound/Voices/Voices 9.ogg"),
]

var _ambience_event_space_min: int = 30
var _ambience_event_space_max: int = 180
var _ambience_events_weighted: Array = [
	[2,  preload("res://assets/sound/Easter Eggs/Bird Cry 1.ogg")],
	[2,  preload("res://assets/sound/Easter Eggs/Bird Flapping 1.ogg")],
	[2,  preload("res://assets/sound/Easter Eggs/Peepers 1.ogg")],
	[5,  preload("res://assets/sound/Easter Eggs/Cricket Loop.ogg")],
	[5,  preload("res://assets/sound/Easter Eggs/Easter Eggs pen drop 1.ogg")],
	[10, preload("res://assets/sound/Easter Eggs/Random Ambience 1.ogg")],
	[10, preload("res://assets/sound/Easter Eggs/Random Ambience 2.ogg")],
	[10, preload("res://assets/sound/Easter Eggs/Random Ambience 3.ogg")],
	[10, preload("res://assets/sound/Easter Eggs/Random Ambience 4.ogg")],
]


func _ready() -> void:
	ThemeManager.dark_mode_changed.connect(_on_dark_mode_changed)
	# Defer so the full scene tree (Lobby, AudioSettings, etc.) finishes _ready()
	# before we start playing or set any volumes.
	call_deferred("_deferred_ready")


func _deferred_ready() -> void:
	_current_offset = _OFFSET_DARK if ThemeManager.is_dark_mode else _OFFSET_LIGHT
	_start_playing()


# =============================================================================
# Playback
# =============================================================================

func _start_playing() -> void:
	_current_player = _create_player(_random_track())
	$Timer.timeout.connect(_next_track)
	$Timer.start()
	_ambience_event_timer()
	_ambience_voice_timer()


func _ambience_voice_timer() -> void:
	var delay: int = randi_range(_ambient_voice_space_min, _ambient_voice_space_max)
	if OS.is_debug_build():
		print("ambient voice delay=", delay)
	get_tree().create_timer(delay).timeout.connect(_play_ambience_voice)


func _ambience_event_timer() -> void:
	var delay: int = randi_range(_ambience_event_space_min, _ambience_event_space_max)
	if OS.is_debug_build():
		print("ambient event delay=", delay)
	get_tree().create_timer(delay).timeout.connect(_play_ambience_event)


func _play_ambience_voice() -> void:
	var player: AudioStreamPlayer = _create_player(_ambient_voices[randi() % _ambient_voices.size()])
	if OS.is_debug_build():
		print("playing ambience voice. src=", player.stream.resource_path)
	player.finished.connect(_clean_player.bind(player))
	player.finished.connect(_ambience_voice_timer)


func _play_ambience_event() -> void:
	_ambience_event_timer()
	var weight_sum: int = 0
	for ev: Array in _ambience_events_weighted:
		weight_sum += ev[0]
	var choice: int = randi_range(1, weight_sum)
	for ev: Array in _ambience_events_weighted:
		choice -= ev[0]
		if choice <= 0:
			var player: AudioStreamPlayer = _create_player(ev[1])
			player.finished.connect(_clean_player.bind(player))
			if OS.is_debug_build():
				print("playing ambience event. src=", player.stream.resource_path)
			break


func _random_track() -> AudioStream:
	return _ambience_tracks[randi() % _ambience_tracks.size()]


func _create_player(res: AudioStream) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream    = res
	audio.volume_db = _current_offset  # start at current theme offset, not 0
	audio.autoplay  = true
	audio.bus       = &"Ambience"
	add_child(audio)
	audio.play()
	return audio


func _fade_between(audio1: AudioStreamPlayer, res2: AudioStream, duration: float) -> AudioStreamPlayer:
	# New track starts silent then fades up to _current_offset.
	# Old track fades down from its current volume (which may already be offset).
	var audio2: AudioStreamPlayer = _create_player(res2)
	audio2.volume_db = -80.0
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(audio2, "volume_db", _current_offset, duration)
	tween.tween_property(audio1, "volume_db", -80.0,           duration)
	tween.finished.connect(_clean_player.bind(audio1))
	return audio2


func _clean_player(audio: AudioStreamPlayer) -> void:
	audio.queue_free()


func _next_track() -> void:
	_current_player = _fade_between(_current_player, _random_track(), _fade_duration)


# =============================================================================
# Theme integration — tweens every live player to the new offset
# =============================================================================

func _on_dark_mode_changed(enabled: bool) -> void:
	var target: float = _OFFSET_DARK if enabled else _OFFSET_LIGHT
	_current_offset = target
	for child in get_children():
		if child is AudioStreamPlayer:
			var tw: Tween = get_tree().create_tween()
			tw.tween_property(child, "volume_db", target, _VOLUME_TWEEN_DURATION)
