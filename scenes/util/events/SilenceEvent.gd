class_name SilenceEvent
extends RefCounted
## Silence - All audio is muted for 30-60 seconds

static var _original_bus_volumes: Dictionary = {}

static func apply() -> void:
	_original_bus_volumes.clear()

	# Mute all audio buses
	var audio_bus_count = AudioServer.bus_count
	for i in range(audio_bus_count):
		var bus_name = AudioServer.get_bus_name(i)
		_original_bus_volumes[bus_name] = AudioServer.get_bus_volume_db(i)
		AudioServer.set_bus_volume_db(i, -80.0)  # Complete silence

	# Also mute any ambient sound controllers
	for ambience in Engine.get_main_loop().get_nodes_in_group("ambience"):
		if ambience is AudioStreamPlayer:
			ambience.volume_db = -80.0

	Log.info("SilenceEvent", "Applied: All audio muted")

static func end() -> void:
	# Restore original volumes
	for bus_name in _original_bus_volumes:
		var bus_idx = AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, _original_bus_volumes[bus_name])

	# Restore ambience
	for ambience in Engine.get_main_loop().get_nodes_in_group("ambience"):
		if ambience is AudioStreamPlayer:
			ambience.volume_db = 0.0

	_original_bus_volumes.clear()
	Log.info("SilenceEvent", "Audio restored")

static func get_duration() -> float:
	return randf_range(30.0, 60.0)

static func get_display_name() -> String:
	return "Silence"

static func get_description() -> String:
	return "All sound is muted!"
