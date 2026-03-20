class_name TripleJumpEvent
extends RefCounted
## Triple Jump - Players can jump THREE times before landing!

static func apply() -> void:
	# Tell all players to enable triple jump
	if RaceManager.has_method("set_triple_jump_enabled"):
		RaceManager.set_triple_jump_enabled(true)
	print("[TripleJumpEvent] Applied: Triple jump enabled! WHEEE!")

static func end() -> void:
	# Disable triple jump
	if RaceManager.has_method("set_triple_jump_enabled"):
		RaceManager.set_triple_jump_enabled(false)
	print("[TripleJumpEvent] Ended: Triple jump disabled")

static func get_duration() -> float:
	return randf_range(30.0, 60.0)

static func get_display_name() -> String:
	return "Triple Jump"

static func get_description() -> String:
	return "You can now jump THREE times before landing!"
