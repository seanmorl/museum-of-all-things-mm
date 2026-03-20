class_name TimeDilationEvent
extends RefCounted
## Time Dilation - Race timer runs at 50% speed for 30-50 seconds

static var _original_time_scale: float = 1.0

static func apply() -> void:
	# Slow down the race timer (not game speed, just the timer)
	_original_time_scale = 1.0
	RaceManager.set_timer_scale(0.5)
	print("[TimeDilationEvent] ⏰ Applied: Timer at 50%% speed (race will run slower)")

static func end() -> void:
	# Restore normal timer speed
	RaceManager.set_timer_scale(1.0)
	print("[TimeDilationEvent] ⏰ Ended: Timer restored to normal speed")

static func get_duration() -> float:
	return randf_range(30.0, 50.0)

static func get_display_name() -> String:
	return "Time Dilation"

static func get_description() -> String:
	return "The race timer slows to half speed!"
