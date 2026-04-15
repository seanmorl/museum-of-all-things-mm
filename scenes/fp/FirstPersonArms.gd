extends Node3D
## First-person arms renderer for the local player.
## Handles simple state-based animations: idle, point, eat, crouch.

var _left_arm: MeshInstance3D
var _right_arm: MeshInstance3D
var _mat: StandardMaterial3D

# Base positions (camera-local space)
var _left_base: Vector3 = Vector3(-0.25, -0.5, 0.8)
var _right_base: Vector3 = Vector3(0.25, -0.5, 0.8)

# Target positions for each state
var _targets = {
	"idle": {
		"left": Vector3(-0.25, -0.5, 0.8),
		"right": Vector3(0.25, -0.5, 0.8),
		"rot": Vector3.ZERO
	},
	"point": {
		"left": Vector3(-0.3, -0.5, 0.6),
		"right": Vector3(0.1, -0.35, 1.1),
		"rot": Vector3(0.3, 0, 0)
	},
	"eat": {
		"left": Vector3(-0.15, -0.35, 0.9),
		"right": Vector3(0.15, -0.35, 0.9),
		"rot": Vector3(-0.2, 0, 0)
	},
	"crouch": {
		"left": Vector3(-0.2, -0.35, 0.8),
		"right": Vector3(0.2, -0.35, 0.8),
		"rot": Vector3(0.1, 0, 0)
	}
}

var _current_state: String = "idle"
var _is_eating: bool = false
var _is_crouching: bool = false

func _ready() -> void:
	print("[FP Arms] Initializing first-person arms...")
	_setup_meshes()
	_animate_arms_to("idle")

func _setup_meshes() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.85, 0.7, 0.55)  # Skin tone
	_mat.metallic = 0.1
	_mat.roughness = 0.8
	
	# Shared mesh resource (safe to reuse for static geometry)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.04
	capsule.height = 0.45

	_left_arm = MeshInstance3D.new()
	_left_arm.name = "LeftArm"
	_left_arm.mesh = capsule
	_left_arm.position = _left_base
	_left_arm.material_override = _mat
	_left_arm.layers = 1
	add_child(_left_arm)
	
	_right_arm = MeshInstance3D.new()
	_right_arm.name = "RightArm"
	_right_arm.mesh = capsule
	_right_arm.position = _right_base
	_right_arm.material_override = _mat
	_right_arm.layers = 1
	add_child(_right_arm)
	
	print("[FP Arms] Arms created successfully. Layers: %d" % _left_arm.layers)

func set_state(state: String) -> void:
	if _current_state == state:
		return
	_current_state = state
	_animate_arms_to(state)

func set_eating(active: bool) -> void:
	_is_eating = active
	if active:
		set_state("eat")
	else:
		set_state("crouch" if _is_crouching else "idle")

func set_crouching(active: bool) -> void:
	_is_crouching = active
	if active and not _is_eating:
		set_state("crouch")
	elif not active and not _is_eating:
		set_state("idle")

func _animate_arms_to(state: String) -> void:
	var t = _targets.get(state, _targets["idle"])
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	tween.tween_property(_left_arm, "position", t["left"], 0.2)
	tween.tween_property(_right_arm, "position", t["right"], 0.2)
	tween.tween_property(_left_arm, "rotation", t["rot"], 0.2)
	tween.tween_property(_right_arm, "rotation", t["rot"], 0.2)
