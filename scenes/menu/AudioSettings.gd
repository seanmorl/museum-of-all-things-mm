extends "res://scenes/menu/BaseSettingsPanel.gd"

@onready var global_volume: HSlider = %GlobalVolume
@onready var sound_volume: HSlider = %SoundVolume
@onready var ambience_volume: HSlider = %AmbienceVolume
@onready var music_volume: HSlider = %MusicVolume
@onready var global_value: Label = %GlobalValue
@onready var sound_value: Label = %SoundValue
@onready var ambience_value: Label = %AmbienceValue
@onready var music_value: Label = %MusicValue
@onready var tts_button: CheckBox = %TTSButton
@onready var tts_voice: OptionButton = %TTSVoice
@onready var tts_speed: HSlider = %TTSSpeed
@onready var tts_speed_value: Label = %TTSSpeedValue

var global_bus_idx: int
var sound_bus_idx: int
var ambience_bus_idx: int
var music_bus_idx: int


func _ready() -> void:
	_settings_namespace = "audio"
	global_bus_idx = AudioServer.get_bus_index("Master")
	sound_bus_idx = AudioServer.get_bus_index("Sound")
	ambience_bus_idx = AudioServer.get_bus_index("Ambience")
	music_bus_idx = AudioServer.get_bus_index("Music")

	# Populate voice dropdown
	_populate_voices()

	super._ready()


func _populate_voices() -> void:
	"""Fill voice dropdown with available TTS voices"""
	tts_voice.clear()

	var voices = TTSManager.get_voices()

	if voices == null or voices.size() == 0:
		tts_voice.add_item("No TTS voices available")
		tts_voice.disabled = true
		print("[AudioSettings] No TTS voices available")
		return

	# System voices are dictionaries: {id, name, language}
	for i in range(voices.size()):
		var voice_data = voices[i]
		var display_name = _format_system_voice(voice_data)
		tts_voice.add_item(display_name)

	tts_voice.disabled = false
	print("[AudioSettings] Loaded %d system TTS voices" % voices.size())


func _apply_settings(settings: Dictionary) -> void:
	global_volume.value = settings.global
	sound_volume.value = settings.sound
	ambience_volume.value = settings.ambience
	music_volume.value = settings.music
	
	if settings.has("tts_enabled"):
		tts_button.button_pressed = settings.tts_enabled
	else:
		tts_button.button_pressed = true
	
	if settings.has("tts_speed"):
		tts_speed.value = settings.tts_speed
		tts_speed_value.text = "%.0f%%" % (settings.tts_speed * 100.0)
	else:
		tts_speed.value = 1.0
		tts_speed_value.text = "100%"


func _create_settings_obj() -> Dictionary:
	return {
		"global": global_volume.value,
		"sound": sound_volume.value,
		"ambience": ambience_volume.value,
		"music": music_volume.value,
		"tts_enabled": tts_button.button_pressed,
		"tts_speed": tts_speed.value,
	}


func _on_global_volume_changed(value: float) -> void:
	global_value.text = str(value * 100) + "%"
	AudioServer.set_bus_volume_db(global_bus_idx, linear_to_db(value))


func _on_sound_volume_changed(value: float) -> void:
	sound_value.text = str(value * 100) + "%"
	AudioServer.set_bus_volume_db(sound_bus_idx, linear_to_db(value))


func _on_ambience_volume_changed(value: float) -> void:
	ambience_value.text = str(value * 100) + "%"
	AudioServer.set_bus_volume_db(ambience_bus_idx, linear_to_db(value))


func _on_music_volume_changed(value: float) -> void:
	music_value.text = str(value * 100) + "%"
	AudioServer.set_bus_volume_db(music_bus_idx, linear_to_db(value))


func _on_tts_button_toggled(toggled_on: bool) -> void:
	if not toggled_on:
		TTSManager.stop()


func _on_tts_voice_item_selected(index: int) -> void:
	"""Player selected a different TTS voice"""
	var voices = TTSManager.get_voices()
	if voices and index < voices.size():
		var voice_data = voices[index]
		var voice_id = voice_data.id if voice_data is Dictionary else voice_data
		if voice_id and not voice_id.is_empty():
			TTSManager.set_voice(voice_id)
			print("[AudioSettings] Voice changed to: ", voice_id)


func _on_tts_speed_changed(value: float) -> void:
	tts_speed_value.text = "%.0f%%" % (value * 100.0)
	var settings = SettingsManager.get_settings("audio")
	if settings is Dictionary:
		settings["tts_speed"] = value
		SettingsManager.save_settings("audio", settings)


func _format_system_voice(voice_data: Dictionary) -> String:
	"""Format system TTS voice into readable name"""
	# System voice format: {id: "...", name: "...", language: "..."}
	var name = voice_data.get("name", "Unknown")
	var language = voice_data.get("language", "")
	
	if language.begins_with("en"):
		var lang_name = {
			"en-GB": "🇬🇧 UK",
			"en-US": "🇺🇸 US",
			"en-AU": "🇦🇺 AU",
			"en-IE": "🇮🇪 IE",
			"en-NZ": "🇳🇿 NZ",
			"en-ZA": "🇿🇦 ZA",
		}.get(language, language)
		return "%s (%s)" % [name, lang_name]
	
	return "%s (%s)" % [name, language]
