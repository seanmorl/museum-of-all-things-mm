class_name TripleJumpEvent
extends EventBase
## Triple Jump - Players can jump three times while airborne for 30-60 seconds

static func apply() -> void:
	RaceManager.set_triple_jump_enabled(true)
	Log.info("TripleJumpEvent", "Applied: Triple jump enabled")

static func end() -> void:
	RaceManager.set_triple_jump_enabled(false)
	Log.info("TripleJumpEvent", "Triple jump disabled")

static func get_duration() -> float:
	return randf_range(30.0, 60.0)

static func get_display_name() -> String:
	return "Triple Jump"

static func get_description() -> String:
	return "Jump three times while in the air!"