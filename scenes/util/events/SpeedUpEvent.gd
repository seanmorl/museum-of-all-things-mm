class_name SpeedUpEvent
extends RefCounted
## Speed Up - All players move 50% faster for 20-30 seconds

static func apply() -> void:
	# Set global speed modifier
	RaceManager.set_global_speed_modifier(1.5)
	Log.info("SpeedUpEvent", "Applied: 1.5x speed")

static func end() -> void:
	# Restore normal speed
	RaceManager.set_global_speed_modifier(1.0)
	Log.info("SpeedUpEvent", "Speed restored")

static func get_duration() -> float:
	return randf_range(20.0, 30.0)

static func get_display_name() -> String:
	return "Speed Up"

static func get_description() -> String:
	return "All players move 50% faster!"
