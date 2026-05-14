class_name CacophonyEvent
extends EventBase
## Cacophony - All sound files in the current room play at once!

static var _playing_sounds: Array = []

static func apply() -> void:
	var museum := get_museum()
	if not museum:
		Log.error("CacophonyEvent", "Museum not found")
		return

	Log.info("CacophonyEvent", "Applied: ALL THE SOUNDS AT ONCE!")

	for audio_player in museum.get_tree().get_nodes_in_group("audio"):
		if audio_player is AudioStreamPlayer3D:
			if audio_player.stream and not audio_player.playing:
				audio_player.play()
				_playing_sounds.append(audio_player)

	for gramophone in museum.get_tree().get_nodes_in_group("gramophone"):
		if gramophone.has_method("play"):
			gramophone.play()
			_playing_sounds.append(gramophone)

	Log.info("CacophonyEvent", "Playing %d sounds simultaneously! CHAOS!" % _playing_sounds.size())

static func end() -> void:
	for sound in _playing_sounds:
		if is_instance_valid(sound) and sound.has_method("stop"):
			sound.stop()
	_playing_sounds.clear()
	Log.info("CacophonyEvent", "Silence at last")

static func get_duration() -> float:
	return randf_range(20.0, 40.0)

static func get_display_name() -> String:
	return "Cacophony"

static func get_description() -> String:
	return "Every sound in the room plays at once! CHAOS!"