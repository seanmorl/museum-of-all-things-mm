class_name LowGravityEvent
extends RefCounted
## Low Gravity - Players float and jump super high!

static func apply() -> void:
	# Reduce gravity for all players
	if RaceManager.has_method("set_gravity_modifier"):
		RaceManager.set_gravity_modifier(0.3)  # 30% of normal gravity
	Log.info("LowGravityEvent", "Applied: Low gravity! Players will float!")

static func end() -> void:
	# Restore normal gravity
	if RaceManager.has_method("set_gravity_modifier"):
		RaceManager.set_gravity_modifier(1.0)
	Log.info("LowGravityEvent", "Gravity restored to normal")

static func get_duration() -> float:
	return randf_range(45.0, 90.0)

static func get_display_name() -> String:
	return "Low Gravity"

static func get_description() -> String:
	return "Gravity is reduced! You'll float like on the moon!"
