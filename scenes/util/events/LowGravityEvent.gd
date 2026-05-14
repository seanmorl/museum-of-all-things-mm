class_name LowGravityEvent
extends EventBase
## Low Gravity - Players float higher and fall slower for 45-90 seconds

static func apply() -> void:
	RaceManager.set_gravity_modifier(0.5)
	Log.info("LowGravityEvent", "Applied: Gravity at 50%%")

static func end() -> void:
	RaceManager.set_gravity_modifier(1.0)
	Log.info("LowGravityEvent", "Gravity restored")

static func get_duration() -> float:
	return randf_range(45.0, 90.0)

static func get_display_name() -> String:
	return "Low Gravity"

static func get_description() -> String:
	return "Lower gravity - float higher and fall slower!"