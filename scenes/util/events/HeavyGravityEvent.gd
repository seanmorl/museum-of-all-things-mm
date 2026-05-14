class_name HeavyGravityEvent
extends EventBase
## Heavy Gravity - All players move 40%% slower for 25-40 seconds

static func apply() -> void:
	RaceManager.set_global_speed_modifier(0.6)
	Log.info("HeavyGravityEvent", "Applied: 0.6x speed")

static func end() -> void:
	RaceManager.set_global_speed_modifier(1.0)
	Log.info("HeavyGravityEvent", "Heavy gravity ended")

static func get_duration() -> float:
	return randf_range(25.0, 40.0)

static func get_display_name() -> String:
	return "Heavy Gravity"

static func get_description() -> String:
	return "Movement feels sluggish and heavy!"