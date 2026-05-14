class_name DoubleJumpEvent
extends EventBase
## Double Jump - Players can jump again while airborne for 30-60 seconds

static func apply() -> void:
	RaceManager.set_double_jump_enabled(true)
	Log.info("DoubleJumpEvent", "Applied: Double jump enabled")

static func end() -> void:
	RaceManager.set_double_jump_enabled(false)
	Log.info("DoubleJumpEvent", "Double jump disabled")

static func get_duration() -> float:
	return randf_range(30.0, 60.0)

static func get_display_name() -> String:
	return "Double Jump"

static func get_description() -> String:
	return "Jump again while in the air!"