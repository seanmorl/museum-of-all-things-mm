extends Node3D
class_name Terminal

func interact() -> void:
	var zone := get_node_or_null("TerminalInteractZone")
	if zone and zone.has_method("interact"):
		zone.interact()
