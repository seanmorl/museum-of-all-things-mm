extends Node
## Kokoro TTS Service Wrapper - High-quality neural text-to-speech
## Uses Kokoro GDExtension (https://github.com/PhilNikitin/godot-kokoro)
##
## Features:
## - 11 English neural voices (FP32) or 103 voices (Int8 quantized, faster)
## - Non-blocking async generation
## - Caches generated audio for instant replay
## - No external dependencies (Python, etc.)
## - Fully offline

signal speech_started
signal speech_finished
signal error_occurred(error_text: String)

const CACHE_DIR = "user://kokoro_cache"

# The KokoroTTS instance (GDScript wrapper around TextToSpeech GDExtension)
var kokoro: KokoroTTS = null
var is_ready: bool = false
var current_speaker: int = 0
var speech_speed: float = 1.0

## Use int8 quantized model for faster inference (103 speakers vs 11)
@export var use_int8_model: bool = false

# Audio playback
var _current_player: AudioStreamPlayer = null
var _cache: Dictionary = {}  # text_hash -> AudioStreamWAV


func _ready() -> void:
	_setup_cache()
	_initialize_kokoro()


func _exit_tree() -> void:
	"""Cleanup on exit"""
	kokoro = null


func _setup_cache() -> void:
	"""Create cache directory"""
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)


func _initialize_kokoro() -> void:
	"""Initialize Kokoro TTS engine"""
	print("[KokoroService] Initializing...")

	# Create the KokoroTTS instance (GDScript wrapper around TextToSpeech GDExtension)
	kokoro = KokoroTTS.new()
	add_child(kokoro)

	# Set model type before initialization
	kokoro.use_int8_model = use_int8_model

	# Connect signals
	kokoro.generation_completed.connect(_on_generation_completed)

	# Initialize
	var result = kokoro.initialize()
	if result:
		is_ready = true
		var speaker_count = kokoro.get_speaker_count()
		print("[KokoroService] ✓ Ready with %d speakers" % speaker_count)

		# List available speakers
		for i in range(speaker_count):
			print("[KokoroService]   Speaker %d" % i)
	else:
		print("[KokoroService] ✗ Failed to initialize")
		error_occurred.emit("KokoroTTS initialization failed")


func speak(text: String) -> void:
	"""Generate and speak text using Kokoro TTS"""
	if not is_ready:
		print("[KokoroService] Not ready")
		error_occurred.emit("KokoroTTS not ready")
		return

	if text.is_empty():
		return

	print("[KokoroService] Speaking: ", text.substr(0, 50))

	# Stop any current speech
	stop()

	# Check cache first
	var cache_key = _hash(text)
	if _cache.has(cache_key):
		print("[KokoroService] Using cached audio")
		_play_audio(_cache[cache_key])
		return

	# Generate async (non-blocking!)
	print("[KokoroService] Generating speech (async)...")
	kokoro.speaker_id = current_speaker
	kokoro.speed = speech_speed
	kokoro.speak_async(text)


func _on_generation_completed(request_id: int, audio: AudioStreamWAV) -> void:
	"""Called when async generation completes"""
	print("[KokoroService] Generation complete")
	
	if audio:
		# Cache it
		var cache_key = _hash(request_id)
		_cache[cache_key] = audio
		
		# Play it
		_play_audio(audio)
	else:
		error_occurred.emit("Generation failed")


func _play_audio(audio: AudioStreamWAV) -> void:
	"""Play audio stream"""
	_current_player = AudioStreamPlayer.new()
	_current_player.stream = audio
	_current_player.volume_db = -10  # -10dB safe volume
	_current_player.bus = &"TTS"
	
	add_child(_current_player)
	
	_current_player.finished.connect(_on_playback_finished)
	_current_player.play()
	
	speech_started.emit()
	print("[KokoroService] Playback started")


func _on_playback_finished() -> void:
	"""Called when playback completes"""
	print("[KokoroService] Playback finished")
	
	if _current_player:
		_current_player.queue_free()
		_current_player = null
	
	speech_finished.emit()


func stop() -> void:
	"""Stop any current speech"""
	if _current_player:
		_current_player.stop()
		_current_player.queue_free()
		_current_player = null
		print("[KokoroService] Stopped")


func set_speaker(speaker_id: int) -> bool:
	"""Set the current speaker (0 to speaker_count-1)"""
	if kokoro and speaker_id >= 0 and speaker_id < kokoro.get_speaker_count():
		current_speaker = speaker_id
		print("[KokoroService] Speaker set to: ", speaker_id)
		return true
	return false


func get_speaker_count() -> int:
	"""Get number of available speakers"""
	if kokoro:
		return kokoro.get_speaker_count()
	return 0


func set_speed(speed: float) -> void:
	"""Set speech speed (0.5 to 2.0)"""
	speech_speed = clamp(speed, 0.5, 2.0)
	print("[KokoroService] Speed set to: ", speech_speed)


func clear_cache() -> void:
	"""Clear the audio cache"""
	_cache.clear()
	print("[KokoroService] Cache cleared")


func get_cache_size() -> int:
	"""Get approximate cache size in bytes"""
	var size = 0
	for audio in _cache.values():
		if audio and audio.data:
			size += audio.data.size()
	return size


func _hash(text: Variant) -> String:
	"""Generate cache key"""
	if text is String:
		var h = 0
		for c in text:
			h = (h * 31 + c.unicode_at(0)) & 0x7FFFFFFF
		return "k_%d" % h
	else:
		return "req_%d" % text
