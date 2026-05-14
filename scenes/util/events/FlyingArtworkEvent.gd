class_name FlyingArtworkEvent
extends EventBase
## Flying Artwork - All posters/artwork fly off the walls!

static var _flying_items: Array = []

static func apply() -> void:
	var museum := get_museum()
	if not museum:
		Log.error("FlyingArtworkEvent", "Museum not found")
		return

	var current_room: String = museum.get("current_room") if museum.has_method("get_current_room") else "Unknown"
	Log.info("FlyingArtworkEvent", "Applied: Artwork flying off walls in '%s'!" % current_room)

	var items_found := 0
	for node in get_group_nodes("wall_item"):
		if node is Node3D:
			_make_item_fly(node)
			_flying_items.append(node)
			items_found += 1

	for node in get_group_nodes("image_item"):
		if node is Node3D:
			_make_item_fly(node)
			_flying_items.append(node)
			items_found += 1

	if items_found == 0:
		Log.debug("FlyingArtworkEvent", "No grouped items found, searching by type...")
		for node in get_group_nodes("exhibit"):
			if node is Node3D:
				for child in node.get_children():
					if child is MeshInstance3D and child.name.contains("Item"):
						_make_item_fly(child)
						_flying_items.append(child)
						items_found += 1

	Log.info("FlyingArtworkEvent", "Made %d items fly!" % items_found)

static func _make_item_fly(item: Node3D) -> void:
	var tween := item.create_tween()
	tween.set_loops()
	tween.tween_property(item, "position:y", item.position.y + 0.5, 1.0)
	tween.tween_property(item, "position:y", item.position.y - 0.3, 1.0)
	tween.parallel().tween_property(item, "rotation:y", item.rotation.y + PI, 2.0)

static func end() -> void:
	_flying_items.clear()
	Log.info("FlyingArtworkEvent", "Artwork returned to walls")

static func get_duration() -> float:
	return randf_range(30.0, 60.0)

static func get_display_name() -> String:
	return "Flying Artwork"

static func get_description() -> String:
	return "All artwork flies off the walls and floats around!"