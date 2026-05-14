class_name DoubleTimeEvent
extends EventBase
## Double Time - Race timer runs at 200%% speed for 30-60 seconds

static func apply() -> void:
	RaceManager.set_timer_scale(2.0)
	Log.info("DoubleTimeEvent", "Applied: Timer at 200%% speed")

static func end() -> void:
	RaceManager.set_timer_scale(1.0)
	Log.info("DoubleTimeEvent", "Timer restored to normal")

static func get_duration() -> float:
	return randf_range(30.0, 60.0)

static func get_display_name() -> String:
	return "Double Time"

static func get_description() -> String:
	return "The race timer runs at double speed!"