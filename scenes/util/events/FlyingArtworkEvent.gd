class_name FlyingArtworkEvent
extends RefCounted
## Flying Artwork - All posters/artwork fly off the walls!

static var _flying_items: Array = []

static func apply() -> void:
	# Find all artwork/items in current exhibit and make them float
	var museum = Engine.get_main_loop().current_scene.get_node_or_null("Museum")
	if not museum:
		Log.error("FlyingArtworkEvent", "Museum not found")
		return

	# Get current exhibit
	var current_room = museum.get("current_room") if museum.has_method("get_current_room") else "Unknown"
	Log.info("FlyingArtworkEvent", "Applied: Artwork flying off walls in '%s'!" % current_room)

	# Find ALL MeshInstance3D nodes that look like artwork (search entire scene tree)
	var items_found = 0
	for node in Engine.get_main_loop().get_nodes_in_group("wall_item"):
		if node is Node3D:
			_make_item_fly(node)
			_flying_items.append(node)
			items_found += 1

	# Also search for any MeshInstance3D that might be artwork
	for node in Engine.get_main_loop().get_nodes_in_group("image_item"):
		if node is Node3D:
			_make_item_fly(node)
			_flying_items.append(node)
			items_found += 1

	# Fallback: search for ANY MeshInstance3D in exhibits (brute force)
	if items_found == 0:
		Log.debug("FlyingArtworkEvent", "No grouped items found, searching by type...")
		for node in Engine.get_main_loop().get_nodes_in_group("exhibit"):
			if node is Node3D:
				for child in node.get_children():
					if child is MeshInstance3D and child.name.contains("Item"):
						_make_item_fly(child)
						_flying_items.append(child)
						items_found += 1

	Log.info("FlyingArtworkEvent", "Made %d items fly!" % items_found)

static func _make_item_fly(item: Node3D) -> void:
	# Make item float upward with rotation
	if item.has_method("set_position"):
		var tween = item.create_tween()
		tween.set_loops()
		# Bob up and down
		tween.tween_property(item, "position:y", item.position.y + 0.5, 1.0)
		tween.tween_property(item, "position:y", item.position.y - 0.3, 1.0)
		# Rotate slowly
		tween.parallel().tween_property(item, "rotation:y", item.rotation.y + PI, 2.0)

static func end() -> void:
	# Clear the array - tweens will stop automatically when items are done
	_flying_items.clear()
	Log.info("FlyingArtworkEvent", "Artwork returned to walls")

static func get_duration() -> float:
	return randf_range(30.0, 60.0)

static func get_display_name() -> String:
	return "Flying Artwork"

static func get_description() -> String:
	return "All artwork flies off the walls and floats around!"
