extends Node
## Manages Text-To-Speech (TTS) narration for exhibits.
## Interfaces with Godot's built-in DisplayServer TTS capabilities.

signal narration_started
signal narration_stopped

var _is_narrating: bool = false
var _current_voice: String = ""

func _ready() -> void:
	# Find a suitable English voice if available
	var voices = DisplayServer.tts_get_voices()
	if voices == null or voices.size() == 0:
		return
	for voice in voices:
		if voice.language.begins_with("en"):
			_current_voice = voice.id
			break
	if _current_voice == "" and voices.size() > 0:
		_current_voice = voices[0].id

## Speaks the given text using the system TTS engine.
## If currently narrating, it interrupts the previous text.
func narrate(text: String) -> void:
	stop()
	
	var audio_settings = SettingsManager.get_settings("audio")
	if audio_settings != null and audio_settings.has("tts_enabled") and not audio_settings.tts_enabled:
		return
		
	if text.is_empty():
		return
		
	# TTS engine requires audio features enabled or it will fail silently on some OS
	# DisplayServer.tts_speak handles the OS-level hook
	DisplayServer.tts_speak(text, _current_voice)
	_is_narrating = true
	narration_started.emit()

## Stops any ongoing narration.
func stop() -> void:
	if _is_narrating:
		DisplayServer.tts_stop()
		_is_narrating = false
		narration_stopped.emit()

## Toggles narration for the given text
func toggle_narration(text: String) -> void:
	if _is_narrating:
		stop()
	else:
		narrate(text)

func is_narrating() -> bool:
	return _is_narrating
