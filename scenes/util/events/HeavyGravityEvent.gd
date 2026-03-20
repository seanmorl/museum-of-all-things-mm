class_name HeavyGravityEvent
extends RefCounted
## Heavy Gravity - All players move 40% slower for 25-40 seconds

static func apply() -> void:
	# Set global speed modifier
	RaceManager.set_global_speed_modifier(0.6)
	print("[HeavyGravityEvent] Applied: 0.6x speed")

static func end() -> void:
	# Restore normal speed
	RaceManager.set_global_speed_modifier(1.0)
	print("[HeavyGravityEvent] Ended")

static func get_duration() -> float:
	return randf_range(25.0, 40.0)

static func get_display_name() -> String:
	return "Heavy Gravity"

static func get_description() -> String:
	return "Movement feels sluggish and heavy!"
