class_name ReversedEvent
extends RefCounted
## Reversed - All door Entry/Exit labels swap for 30-60 seconds

static var _original_labels: Dictionary = {}

static func apply() -> void:
	# Swap all hall labels
	for hall in Engine.get_main_loop().get_nodes_in_group("hall"):
		if hall.has_method("get_doors"):
			# Store original state
			_original_labels[hall] = {
				"from_title": hall.get("from_title") if "from_title" in hall else "",
				"to_title": hall.get("to_title") if "to_title" in hall else ""
			}
			# Swap them
			var temp = hall.get("from_title") if "from_title" in hall else ""
			if "from_title" in hall and "to_title" in hall:
				hall.set("from_title", hall.get("to_title"))
				hall.set("to_title", temp)
				# Update labels if they exist
				hall._update_labels() if hall.has_method("_update_labels") else null

	Log.info("ReversedEvent", "Applied: All door labels swapped")

static func end() -> void:
	# Restore original labels
	for hall in _original_labels:
		if is_instance_valid(hall):
			if "from_title" in hall:
				hall.set("from_title", _original_labels[hall]["from_title"])
			if "to_title" in hall:
				hall.set("to_title", _original_labels[hall]["to_title"])
			if hall.has_method("_update_labels"):
				hall._update_labels()

	_original_labels.clear()
	Log.info("ReversedEvent", "Door labels restored")

static func get_duration() -> float:
	return randf_range(30.0, 60.0)

static func get_display_name() -> String:
	return "Reversed"

static func get_description() -> String:
	return "All door labels are swapped!"
