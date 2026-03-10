extends StaticBody3D
class_name Bench

func _ready() -> void:
	add_to_group("Seat")

func interact() -> void:
	var player = get_tree().get_first_node_in_group("local_player")
	if player and player.has_method("request_mount"):
		player.request_mount(self)

func get_interaction_text() -> String:
	return "Sit"
