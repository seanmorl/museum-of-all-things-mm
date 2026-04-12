class_name MuseumReverb
extends RefCounted

## Dynamically creates a "Museum" audio bus with reverb effect.
## Used by gramophones and sound items to sound like they're in a large hall.

const BUS_NAME := "MuseumReverb"

static func ensure_bus() -> int:
	## Returns the bus index. Creates the bus + reverb effect if it doesn't exist.
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx != -1:
		return idx

	# Create bus
	AudioServer.add_bus(-1)
	idx = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(idx, BUS_NAME)
	AudioServer.set_bus_volume_db(idx, 0.0)
	AudioServer.set_bus_send(idx, "Master")

	# Add reverb effect (large hall sound)
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 1.0       # Large room
	reverb.damping = 0.3
	reverb.wet = 0.8             # Heavy reverb
	reverb.dry = 0.3
	reverb.predelay_ms = 30
	reverb.hfcutoff = 2000
	reverb.spread = 1.0
	AudioServer.add_bus_effect(idx, reverb)

	Log.debug("MuseumReverb", "Created bus '%s' at index %d" % [BUS_NAME, idx])
	return idx

static func route_stream_player_to_museum(player: AudioStreamPlayer) -> void:
	player.bus = BUS_NAME
