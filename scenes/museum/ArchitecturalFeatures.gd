extends RefCounted
## Enhanced Architectural Features for Museum Generation
## Adds columns, arches, decorative elements, and varied materials

class ArchitecturalStyle:
	var name: String
	var column_type: String  # "doric", "ionic", "corinthian", "modern", "none"
	var arch_style: String  # "round", "pointed", "flat", "none"
	var molding_style: String  # "ornate", "simple", "none"
	var floor_pattern: String  # "checkered", "herringbone", "plain"
	var wall_material: String  # "plaster", "brick", "stone", "wood"
	var ceiling_type: String  # "vaulted", "coffered", "flat", "domed"
	var color_palette: Array[Color]
	
	func _init():
		pass

# Architectural styles
const STYLE_CLASSICAL: Dictionary = {
	"name": "Classical",
	"column_type": "corinthian",
	"arch_style": "round",
	"molding_style": "ornate",
	"floor_pattern": "checkered",
	"wall_material": "marble",
	"ceiling_type": "coffered",
	"color_palette": [Color(0.95, 0.93, 0.88), Color(0.8, 0.75, 0.7), Color(0.6, 0.55, 0.5)]
}

const STYLE_GOTHIC: Dictionary = {
	"name": "Gothic",
	"column_type": "clustered",
	"arch_style": "pointed",
	"molding_style": "ornate",
	"floor_pattern": "herringbone",
	"wall_material": "stone",
	"ceiling_type": "vaulted",
	"color_palette": [Color(0.7, 0.68, 0.65), Color(0.5, 0.48, 0.45), Color(0.3, 0.28, 0.25)]
}

const STYLE_MODERN: Dictionary = {
	"name": "Modern",
	"column_type": "none",
	"arch_style": "flat",
	"molding_style": "none",
	"floor_pattern": "plain",
	"wall_material": "plaster",
	"ceiling_type": "flat",
	"color_palette": [Color(0.98, 0.98, 0.98), Color(0.85, 0.85, 0.85), Color(0.6, 0.6, 0.6)]
}

const STYLE_VICTORIAN: Dictionary = {
	"name": "Victorian",
	"column_type": "ionic",
	"arch_style": "round",
	"molding_style": "ornate",
	"floor_pattern": "herringbone",
	"wall_material": "wood",
	"ceiling_type": "coffered",
	"color_palette": [Color(0.85, 0.78, 0.65), Color(0.65, 0.55, 0.4), Color(0.45, 0.35, 0.25)]
}

# Decorative element definitions
const DECORATIVE_ELEMENTS: Dictionary = {
	"columns": {
		"corinthian": {"height": 4.0, "radius": 0.3, "material": "marble", "has_base": true, "has_capital": true},
		"ionic": {"height": 4.0, "radius": 0.25, "material": "marble", "has_base": true, "has_capital": true},
		"doric": {"height": 4.0, "radius": 0.35, "material": "stone", "has_base": false, "has_capital": true},
		"clustered": {"height": 5.0, "radius": 0.4, "material": "stone", "has_base": true, "has_capital": true},
		"modern": {"height": 3.5, "radius": 0.2, "material": "steel", "has_base": false, "has_capital": false},
		"none": null
	},
	"arches": {
		"round": {"shape": "semicircle", "height_ratio": 0.5, "thickness": 0.3},
		"pointed": {"shape": "pointed", "height_ratio": 0.7, "thickness": 0.25},
		"flat": {"shape": "flat", "height_ratio": 0.1, "thickness": 0.2},
		"none": null
	},
	"moldings": {
		"ornate": {"complexity": "high", "layers": 3, "projection": 0.15},
		"simple": {"complexity": "low", "layers": 1, "projection": 0.05},
		"none": null
	}
}

# Room type definitions with architectural features
const ROOM_TYPES: Dictionary = {
	"atrium": {
		"min_size": Vector2i(8, 8),
		"max_size": Vector2i(12, 12),
		"features": ["columns", "skylight", "balcony"],
		"column_spacing": 3.0,
		"has_central_feature": true
	},
	"grand_hall": {
		"min_size": Vector2i(6, 10),
		"max_size": Vector2i(10, 20),
		"features": ["columns", "arches", "high_ceiling"],
		"column_spacing": 4.0,
		"has_central_feature": false
	},
	"gallery": {
		"min_size": Vector2i(4, 8),
		"max_size": Vector2i(6, 15),
		"features": ["moldings", "pedestals"],
		"column_spacing": 0.0,
		"has_central_feature": false
	},
	"rotunda": {
		"min_size": Vector2i(8, 8),
		"max_size": Vector2i(12, 12),
		"features": ["columns", "dome", "circular"],
		"column_spacing": 3.5,
		"has_central_feature": true
	},
	"corridor": {
		"min_size": Vector2i(2, 6),
		"max_size": Vector2i(3, 12),
		"features": ["arches", "wall_niches"],
		"column_spacing": 0.0,
		"has_central_feature": false
	}
}

static func get_style(style_name: String) -> Dictionary:
	"""Get architectural style definition"""
	match style_name.to_lower():
		"classical":
			return STYLE_CLASSICAL
		"gothic":
			return STYLE_GOTHIC
		"modern":
			return STYLE_MODERN
		"victorian":
			return STYLE_VICTORIAN
		_:
			return STYLE_CLASSICAL

static func get_room_type(room_type: String) -> Dictionary:
	"""Get room type definition"""
	return ROOM_TYPES.get(room_type, ROOM_TYPES["gallery"])

static func select_style_for_mood(mood: int) -> String:
	"""Select appropriate architectural style based on exhibit mood"""
	match mood:
		ExhibitMood.Mood.HISTORY:
			return "classical" if randf() > 0.5 else "gothic"
		ExhibitMood.Mood.SCIENCE:
			return "modern"
		ExhibitMood.Mood.ART:
			return "victorian" if randf() > 0.5 else "classical"
		ExhibitMood.Mood.NATURE:
			return "modern"
		ExhibitMood.Mood.ASTRO:
			return "modern" if randf() > 0.5 else "classical"
		ExhibitMood.Mood.MEDIA:
			return "modern" if randf() > 0.5 else "victorian"
		ExhibitMood.Mood.GEOGRAPHY:
			var styles = ["classical", "modern", "victorian"]
			return styles[randi() % styles.size()]
		ExhibitMood.Mood.PHILOSOPHY:
			return "gothic" if randf() > 0.5 else "classical"
		ExhibitMood.Mood.SPORTS:
			return "modern"
		ExhibitMood.Mood.FOOD:
			return "victorian" if randf() > 0.5 else "modern"
		ExhibitMood.Mood.POLITICS:
			return "classical" if randf() > 0.5 else "gothic"
		ExhibitMood.Mood.ECONOMY:
			return "modern" if randf() > 0.5 else "classical"
		ExhibitMood.Mood.MYSTERY:
			return "gothic"
		_:
			var styles = ["classical", "gothic", "modern", "victorian"]
			return styles[randi() % styles.size()]

static func generate_column_positions(room_rect: Rect2, style: Dictionary, column_spacing: float) -> Array[Vector3]:
	"""Generate column positions for a room"""
	var positions: Array[Vector3] = []
	
	if style["column_type"] == "none":
		return positions
	
	var column_def = DECORATIVE_ELEMENTS["columns"].get(style["column_type"])
	if not column_def:
		return positions
	
	# Place columns along room perimeter
	var half_width = room_rect.size.x / 2
	var half_height = room_rect.size.y / 2
	var center = room_rect.get_center()
	
	# Columns along X axis (top and bottom)
	var x_positions = []
	var x = -half_width + column_spacing
	while x < half_width:
		x_positions.append(x)
		x += column_spacing
	
	# Columns along Z axis (left and right)
	var z_positions = []
	var z = -half_height + column_spacing
	while z < half_height:
		z_positions.append(z)
		z += column_spacing
	
	# Add columns at perimeter
	for x_pos in x_positions:
		# Top edge
		positions.append(Vector3(center.x + x_pos, 0, center.y - half_height))
		# Bottom edge
		positions.append(Vector3(center.x + x_pos, 0, center.y + half_height))
	
	for z_pos in z_positions:
		# Left edge
		positions.append(Vector3(center.x - half_width, 0, center.y + z_pos))
		# Right edge
		positions.append(Vector3(center.x + half_width, 0, center.y + z_pos))
	
	return positions

static func get_arch_mesh(arch_style: String, width: float, height: float) -> String:
	"""Get the mesh path for an arch"""
	if arch_style == "none":
		return ""
	
	match arch_style:
		"round":
			return "res://assets/meshes/arch_round.glb"
		"pointed":
			return "res://assets/meshes/arch_pointed.glb"
		"flat":
			return "res://assets/meshes/arch_flat.glb"
	
	return ""

static func get_column_mesh(column_type: String) -> String:
	"""Get the mesh path for a column"""
	if column_type == "none":
		return ""
	
	match column_type:
		"corinthian":
			return "res://assets/meshes/column_corinthian.glb"
		"ionic":
			return "res://assets/meshes/column_ionic.glb"
		"doric":
			return "res://assets/meshes/column_doric.glb"
		"clustered":
			return "res://assets/meshes/column_compound.glb"
		"modern":
			return "res://assets/meshes/column_tuscan.glb"
	
	return ""

static func get_floor_material(floor_pattern: String, style: Dictionary) -> String:
	"""Get the material path for a floor pattern"""
	match floor_pattern:
		"checkered":
			return "res://assets/materials/floor_checkered.tres"
		"herringbone":
			return "res://assets/materials/floor_herringbone.tres"
		"plain":
			match style.get("wall_material", "plaster"):
				"marble":
					return "res://assets/materials/floor_marble.tres"
				"stone":
					return "res://assets/materials/floor_stone.tres"
				"wood":
					return "res://assets/materials/floor_wood.tres"
				_:
					return "res://assets/materials/floor_plain.tres"
	
	return "res://assets/materials/floor_plain.tres"

static func get_wall_material(wall_material: String, color_palette: Array[Color]) -> StandardMaterial3D:
	"""Create a wall material based on type"""
	var material = StandardMaterial3D.new()
	
	match wall_material:
		"marble":
			material.albedo_color = color_palette[0] if color_palette.size() > 0 else Color.WHITE
			material.metallic = 0.1
			material.roughness = 0.3
		"stone":
			material.albedo_color = color_palette[1] if color_palette.size() > 1 else Color.GRAY
			material.metallic = 0.0
			material.roughness = 0.8
		"wood":
			material.albedo_color = color_palette[2] if color_palette.size() > 2 else Color.BROWN
			material.metallic = 0.0
			material.roughness = 0.6
		"plaster":
			material.albedo_color = color_palette[0] if color_palette.size() > 0 else Color.WHITE_SMOKE
			material.metallic = 0.0
			material.roughness = 0.9
	
	return material

static func calculate_room_acoustics(room_type: String, style: Dictionary) -> Dictionary:
	"""Calculate acoustic properties for a room (for ambient audio)"""
	var acoustics = {
		"reverb": 0.5,
		"echo": 0.2,
		"ambient_volume": 0.3
	}
	
	match room_type:
		"atrium", "grand_hall":
			acoustics["reverb"] = 0.8
			acoustics["echo"] = 0.4
		"gallery":
			acoustics["reverb"] = 0.4
			acoustics["echo"] = 0.1
		"rotunda":
			acoustics["reverb"] = 0.9
			acoustics["echo"] = 0.5
		"corridor":
			acoustics["reverb"] = 0.6
			acoustics["echo"] = 0.3
	
	# Adjust based on materials
	if style["wall_material"] == "marble":
		acoustics["reverb"] += 0.1
	elif style["wall_material"] == "stone":
		acoustics["reverb"] += 0.05
	
	return acoustics
