extends Node3D
## Skylight window - shows sky and lets sunlight into exhibits
## Creates dramatic light beams and connects interior to exterior
## Works with VoxelGI to bounce sunlight around the room

@export var sun_energy: float = 2.0
@export var glass_transparency: float = 0.3
@export var enabled: bool = true

var _glass_material: StandardMaterial3D = null
var _light: DirectionalLight3D = null


func _ready() -> void:
	# Find and configure glass material
	var glass_mesh = get_node_or_null("GlassPane")
	if glass_mesh and glass_mesh is MeshInstance3D:
		_glass_material = glass_mesh.get_surface_override_material(0)
		if _glass_material:
			_glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_glass_material.albedo_color.a = glass_transparency
	
	# Configure sunlight
	_light = get_node_or_null("SkylightLight")
	if _light:
		_light.light_energy = sun_energy
		# Light points downward by default (rotation set in scene)
	
	# Enable/disable
	visible = enabled
	if _light:
		_light.visible = enabled


func _exit_tree() -> void:
	# Clean up when room unloads
	if _glass_material:
		_glass_material = null
	_light = null


func set_sun_energy(energy: float) -> void:
	"""Adjust sunlight intensity"""
	sun_energy = energy
	if _light:
		_light.light_energy = energy


func set_glass_transparency(transparency: float) -> void:
	"""Adjust how clear/frosted the glass is"""
	glass_transparency = transparency
	if _glass_material:
		_glass_material.albedo_color.a = transparency


func toggle(enabled: bool) -> void:
	"""Show or hide the skylight"""
	self.enabled = enabled
	visible = enabled
	if _light:
		_light.visible = enabled
