extends Node
## TTSManager — Simple TTS using Godot's DisplayServer.
##
## Uses Godot's built-in TTS API. Works offline with system voices.
##
## Relevant SettingsManager("audio") keys:
##   tts_enabled : bool   — master on/off switch
##   tts_voice   : String — voice ID from DisplayServer

signal narration_started
signal narration_stopped

var _is_narrating: bool = false
var _voice_id: String = ""


func _ready() -> void:
	_find_voice()
	Log.debug("TTSManager", "Ready — using system TTS")


func _find_voice() -> void:
	"""Find an English voice from system TTS"""
	var voices = DisplayServer.tts_get_voices()
	if voices == null or voices.is_empty():
		push_warning("[TTSManager] No TTS voices available")
		return

	# Prefer English voices
	for v in voices:
		if v.language.begins_with("en"):
			_voice_id = v.id
			Log.debug("TTSManager", "Using voice: %s (%s)" % [v.name, v.language])
			return
	
	# Fall back to first available
	if not voices.is_empty():
		_voice_id = voices[0].id


# ── Public API ─────────────────────────────────────────────────────────────────

func narrate(text: String) -> void:
	stop()
	var settings = _get_settings()
	if not settings.get("tts_enabled", true) or text.is_empty():
		return
	
	DisplayServer.tts_speak(text, _voice_id)
	_is_narrating = true
	narration_started.emit()


func stop() -> void:
	if not _is_narrating:
		return
	
	DisplayServer.tts_stop()
	_is_narrating = false
	narration_stopped.emit()


func toggle_narration(text: String) -> void:
	if _is_narrating:
		stop()
	else:
		narrate(text)


func is_narrating() -> bool:
	return _is_narrating


func set_voice(voice_id: String) -> void:
	_voice_id = voice_id


func set_speed(speed: float) -> void:
	"""Note: DisplayServer doesn't support speed control"""
	pass


func get_voices() -> Array:
	return DisplayServer.tts_get_voices()


# ── Helpers ────────────────────────────────────────────────────────────────────

func _get_settings() -> Dictionary:
	var s = SettingsManager.get_settings("audio")
	return s if s is Dictionary else {}
