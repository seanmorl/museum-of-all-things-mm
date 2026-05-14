class_name ColorShiftEvent
extends EventBase
## Color Shift - All colors shift to random hues for 30-45 seconds

static var _original_colors: Dictionary = {}

static func apply() -> void:
	_original_colors.clear()
	for mesh in get_group_nodes("managed_material"):
		if mesh is MeshInstance3D:
			for i in range(mesh.get_surface_override_material_count()):
				var material: Material = mesh.get_surface_override_material(i)
				if material and material is StandardMaterial3D:
					if material not in _original_colors:
						_original_colors[material] = material.albedo_color
					var mat := material as StandardMaterial3D
					var new_color := mat.albedo_color
					new_color.h = randf()
					material.albedo_color = new_color
	Log.info("ColorShiftEvent", "Applied: Colors shifted to random hues")

static func end() -> void:
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
