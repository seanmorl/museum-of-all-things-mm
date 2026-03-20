class_name NoRunningEvent
extends RefCounted
## No Running - Dash/sprint disabled for 45-90 seconds

static func apply() -> void:
	# Set global flag to disable dashing
	RaceManager.set_dash_enabled(false)
	print("[NoRunningEvent] Applied: Dash disabled")

static func end() -> void:
	# Re-enable dashing
	RaceManager.set_dash_enabled(true)
	print("[NoRunningEvent] Ended: Dash re-enabled")

static func get_duration() -> float:
	return randf_range(45.0, 90.0)

static func get_display_name() -> String:
	return "No Running"

static func get_description() -> String:
	return "Dash/sprint is disabled - walk only!"
