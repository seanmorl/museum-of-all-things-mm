extends StaticBody3D
class_name Bench

@onready var _mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var _col: CollisionShape3D = get_node_or_null("CollisionShape3D")

const BENCH_SIZE := Vector3(0.5, 0.3, 0.4)
const BENCH_POSITION := Vector3(0, 0.5, 0)

func _ready() -> void:
	add_to_group("Seat")
	# Defer collision refresh to ensure mesh is fully loaded
	call_deferred("_refresh_collision")

func _refresh_collision() -> void:
	## Ensure collision matches the actual bench mesh so benches don't block
	## walkable gaps and dismount positions aren't inside oversized boxes.
	if not _col:
		return
	# Use a simple box collision sized for the bench.
	# This is smaller than the default (0.6, 0.2, 0.6) box but accurately
	# represents the bench shape so players can walk through gaps.
	_col.shape = BoxShape3D.new()
	_col.shape.size = BENCH_SIZE
	# Position the collision at the mesh center (offset up from floor)
	_col.position = BENCH_POSITION
	_col.disabled = false

func interact() -> void:
	var player = get_tree().get_first_node_in_group("local_player")
	if player and player.has_method("request_mount"):
		player.request_mount(self)

func get_interaction_text() -> String:
	return "Sit"
