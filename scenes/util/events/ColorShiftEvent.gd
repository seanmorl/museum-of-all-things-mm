class_name ColorShiftEvent
extends RefCounted
## Color Shift - All colors shift to random hues for 30-45 seconds

static var _original_colors: Dictionary = {}  # material -> Color

static func apply() -> void:
	# Apply color shift to all materials in the scene
	_original_colors.clear()

	var mesh_instances = Engine.get_main_loop().get_nodes_in_group("managed_material")
	for mesh in mesh_instances:
		if mesh is MeshInstance3D:
			var surface_count = mesh.get_surface_override_material_count()
			for i in range(surface_count):
				var material = mesh.get_surface_override_material(i)
				if material and material is StandardMaterial3D:
					# Store original color (use material as key, not mesh)
					if material not in _original_colors:
						_original_colors[material] = material.albedo_color
					# Apply random hue shift
					var new_color = material.albedo_color
					new_color.h = randf()
					material.albedo_color = new_color

	Log.info("ColorShiftEvent", "Applied: Colors shifted to random hues")

static func end() -> void:
	# Restore original colors
	for material in _original_colors:
		if is_instance_valid(material):
			material.albedo_color = _original_colors[material]

	_original_colors.clear()
	Log.info("ColorShiftEvent", "Colors restored")

static func get_duration() -> float:
	return randf_range(30.0, 45.0)

static func get_display_name() -> String:
	return "Color Shift"

static func get_description() -> String:
	return "All colors shift to random hues!"
