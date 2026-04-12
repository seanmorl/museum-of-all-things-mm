extends Node
## Piper TTS Service - High-quality neural text-to-speech
## Uses Piper TTS (https://github.com/rhasspy/piper) for offline neural speech synthesis.
##
## Features:
## - Generates speech from text using Piper TTS
## - Caches generated audio for instant replay
## - Supports multiple voice models
## - Integrates with Godot's audio system
## - Non-blocking threaded generation (game doesn't freeze!)
##
## Installation:
## 1. Install Piper: pip install piper-tts
## 2. Download voices to user://piper_voices/
## 3. This service auto-detects installed voices
##
## Note: Requires Godot with threading support enabled

signal speech_started
signal speech_finished
signal error_occurred(error_text: String)
signal generation_complete(audio_stream: AudioStreamWAV)

const CACHE_DIR = "user://piper_cache"
const VOICES_DIR = "user://piper_voices"

# Python executable path (auto-detected)
var python_executable: String = ""
var is_ready: bool = false
var current_voice: String = "en_US-lessac-medium"
var current_voice_config: String = ""

# Audio playback
var _current_player: AudioStreamPlayer = null
var _voice_models: Array[String] = []

# Threading
var _generation_thread: Thread = Thread.new()
var _generation_active: bool = false
var _pending_text: String = ""


func _ready() -> void:
	_setup_directories()
	_find_python()
	_scan_voices()
	_check_piper()


func _exit_tree() -> void:
	"""Cleanup thread on exit"""
	if _generation_thread.is_started():
		_generation_thread.wait_to_finish()


func _setup_directories() -> void:
	"""Create cache and voices directories"""
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	DirAccess.make_dir_recursive_absolute(VOICES_DIR)


func _find_python() -> void:
	"""Find Python executable - tries common paths"""
	var paths = [
		"C:/Users/TeamS/AppData/Local/Programs/Python/Python312/python.exe",
		"C:/Users/TeamS/AppData/Local/Programs/Python/Python311/python.exe",
		"C:/Users/TeamS/AppData/Local/Programs/Python/Python310/python.exe",
		"C:/Python312/python.exe",
		"C:/Python311/python.exe",
		"python",
		"python3",
	]
	
	for path in paths:
		if FileAccess.file_exists(path):
			python_executable = path
			Log.debug("PiperService", "Found Python: %s" % path)
			return

	# Fallback to PATH
	python_executable = "python"
	Log.debug("PiperService", "Using Python from PATH")


func _scan_voices() -> void:
	"""Scan voices directory for available voice models"""
	var dir = DirAccess.open(VOICES_DIR)
	if not dir:
		Log.warn("PiperService", "Could not open voices directory: %s" % VOICES_DIR)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".onnx"):
			# Keep full filename without .onnx extension
			var voice_name = file_name.replace(".onnx", "")
			_voice_models.append(voice_name)
			Log.debug("PiperService", "Found voice model: %s" % voice_name)
		file_name = dir.get_next()

	dir.list_dir_end()

	if _voice_models.size() == 0:
		Log.warn("PiperService", "No voice models found in %s" % VOICES_DIR)
		Log.warn("PiperService", "Download voices with: python -m piper.download_voices")
	else:
		Log.debug("PiperService", "Total voices found: %d" % _voice_models.size())
		current_voice = _voice_models[0]
		Log.debug("PiperService", "Default voice set to: %s" % current_voice)


func _check_piper() -> void:
	"""Verify Piper TTS is installed and working"""
	var output = []
	var exit_code = OS.execute(python_executable, ["-m", "piper", "--help"], output, true)

	if exit_code == 0:
		is_ready = true
		Log.info("PiperService", "Piper TTS is ready")

		if _voice_models.size() > 0:
			current_voice = _voice_models[0]
			Log.debug("PiperService", "Using voice: %s" % current_voice)
	else:
		is_ready = false
		Log.error("PiperService", "Piper TTS not found")
		Log.error("PiperService", "Install with: pip install piper-tts")
		error_occurred.emit("Piper TTS not installed. Run: pip install piper-tts")


func speak(text: String) -> void:
	"""Generate and speak text using Piper TTS"""
	if not is_ready:
		Log.error("PiperService", "Not ready - Piper not installed")
		error_occurred.emit("Piper TTS not ready")
		return

	if text.is_empty():
		return

	if _generation_active:
		# Already generating, queue this text
		_pending_text = text
		Log.debug("PiperService", "Generation in progress, queuing text")
		return

	Log.debug("PiperService", "Speaking: %s" % text.substr(0, 50))

	# Stop any current speech
	stop()

	# Generate in background thread (non-blocking!)
	_generation_active = true
	_generation_thread.start(_generate_threaded.bind(text))


func _generate_threaded(text: String) -> void:
	"""Thread function for non-blocking generation"""
	var audio_stream = _synthesize(text)
	
	# Call main thread to play audio
	call_deferred("_on_generation_complete", audio_stream, text)


func _on_generation_complete(audio_stream: AudioStreamWAV, text: String) -> void:
	"""Called when threaded generation completes"""
	_generation_active = false
	
	if audio_stream:
		_play_audio(audio_stream)
		
		# Check if there's queued text
		if _pending_text != "":
			var next_text = _pending_text
			_pending_text = ""
			speak(next_text)
	else:
		error_occurred.emit("Failed to generate speech")


func _synthesize(text: String) -> AudioStreamWAV:
	"""Synthesize text to audio stream"""
	var cache_file = _get_cache_path(text)

	# Check cache first
	if FileAccess.file_exists(cache_file):
		Log.debug("PiperService", "Using cached audio")
		return _load_wav(cache_file)

	# Generate new audio
	Log.debug("PiperService", "Generating speech...")

	# Build Piper command
	var args = [
		python_executable, "-m", "piper",
		"-m", current_voice,
		"-f", cache_file,
		"--data-dir", ProjectSettings.globalize_path(VOICES_DIR),
		"--cuda",  # GPU acceleration (remove if no GPU)
		"--"
	]
	args.append(text)

	var output = []
	var exit_code = OS.execute(python_executable, args.slice(1), output, true)

	if exit_code == 0 and FileAccess.file_exists(cache_file):
		Log.debug("PiperService", "Generated %s" % cache_file)
		return _load_wav(cache_file)
	else:
		Log.error("PiperService", "Generation failed: %d" % exit_code)
		if output.size() > 0:
			Log.error("PiperService", "Error: %s" % "".join(output))
		return null


func _load_wav(file_path: String) -> AudioStreamWAV:
	"""Load WAV file into AudioStreamWAV"""
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return null
	
	var wav_data = file.get_buffer(file.get_length())
	file.close()
	
	if wav_data.size() < 44:
		return null
	
	# Extract PCM data (skip 44-byte WAV header)
	var pcm_data = wav_data.slice(44)
	
	# Read WAV header for format info
	var sample_rate = wav_data[24] | (wav_data[25] << 8) | (wav_data[26] << 16) | (wav_data[27] << 24)
	
	# Create AudioStreamWAV
	var stream = AudioStreamWAV.new()
	stream.data = pcm_data
	stream.mix_rate = sample_rate
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false  # Piper outputs mono
	
	return stream


func _get_cache_path(text: String) -> String:
	"""Generate cache file path from text"""
	var hash = 0
	for c in text:
		hash = (hash * 31 + c.unicode_at(0)) & 0x7FFFFFFF
	
	var cache_file = "piper_%d.wav" % hash
	return ProjectSettings.globalize_path(CACHE_DIR.path_join(cache_file))


func _play_audio(stream: AudioStreamWAV) -> void:
	"""Play audio stream through AudioStreamPlayer"""
	_current_player = AudioStreamPlayer.new()
	_current_player.stream = stream
	_current_player.volume_db = -10  # -10dB (safe volume)
	_current_player.bus = &"TTS"
	
	add_child(_current_player)
	
	_current_player.finished.connect(_on_playback_finished)
	_current_player.play()

	speech_started.emit()
	Log.debug("PiperService", "Playback started")


func _on_playback_finished() -> void:
	"""Called when audio playback completes"""
	Log.debug("PiperService", "Playback finished")

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
		Log.debug("PiperService", "Stopped")


func set_voice(voice_name: String) -> bool:
	"""Set the current voice model"""
	if voice_name in _voice_models:
		current_voice = voice_name
		Log.debug("PiperService", "Voice set to: %s" % voice_name)
		return true
	else:
		Log.warn("PiperService", "Voice not available: %s" % voice_name)
		return false


func get_voices() -> Array[String]:
	"""Get list of available voice models"""
	return _voice_models


func clear_cache() -> void:
	"""Clear the audio cache directory"""
	var dir = DirAccess.open(CACHE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		Log.debug("PiperService", "Cache cleared")


func get_cache_size() -> int:
	"""Get total cache size in bytes"""
	var total = 0
	var dir = DirAccess.open(CACHE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			total += dir.get_file_size(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	return total
