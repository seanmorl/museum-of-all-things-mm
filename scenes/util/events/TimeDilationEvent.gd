class_name TimeDilationEvent
extends EventBase
## Time Dilation - Race timer runs at 50%% speed for 30-50 seconds

static var _original_time_scale: float = 1.0

static func apply() -> void:
	_original_time_scale = 1.0
	RaceManager.set_timer_scale(0.5)
	Log.info("TimeDilationEvent", "Applied: Timer at 50%% speed (race will run slower)")

static func end() -> void:
	RaceManager.set_timer_scale(1.0)
	Log.info("TimeDilationEvent", "Timer restored to normal speed")

static func get_duration() -> float:
	return randf_range(30.0, 50.0)

static func get_display_name() -> String:
	return "Time Dilation"

static func get_description() -> String:
	return "The race timer slows to half speed!"