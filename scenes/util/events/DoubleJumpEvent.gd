class_name DoubleJumpEvent
extends RefCounted
## Double Jump - Players can jump twice before landing

static func apply() -> void:
	# Tell all players to enable double jump
	if RaceManager.has_method("set_double_jump_enabled"):
		RaceManager.set_double_jump_enabled(true)
	print("[DoubleJumpEvent] Applied: Double jump enabled!")

static func end() -> void:
	# Disable double jump
	if RaceManager.has_method("set_double_jump_enabled"):
		RaceManager.set_double_jump_enabled(false)
	print("[DoubleJumpEvent] Ended: Double jump disabled")

static func get_duration() -> float:
	return randf_range(30.0, 60.0)

static func get_display_name() -> String:
	return "Double Jump"

static func get_description() -> String:
	return "You can now jump twice before landing!"
