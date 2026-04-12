class_name BackwardsControlsEvent
extends RefCounted
## Backwards Controls - Forward becomes backward and vice versa!

static func apply() -> void:
	# Find the local player and invert their controls directly
	var local_player = Engine.get_main_loop().get_first_node_in_group("local_player")
	if local_player and local_player.has_method("set_controls_inverted"):
		local_player.set_controls_inverted(true)
		Log.info("BackwardsControlsEvent", "Applied: Controls reversed on player!")
	else:
		Log.warn("BackwardsControlsEvent", "Could not find player or set_controls_inverted method!")
		# Fallback: try Player group
		var players = Engine.get_main_loop().get_nodes_in_group("Player")
		if players.size() > 0:
			var player = players[0]
			if player.has_method("set_controls_inverted"):
				player.set_controls_inverted(true)
				Log.info("BackwardsControlsEvent", "Applied via Player group!")

static func end() -> void:
	# Restore normal controls
	var local_player = Engine.get_main_loop().get_first_node_in_group("local_player")
	if local_player and local_player.has_method("set_controls_inverted"):
		local_player.set_controls_inverted(false)
		Log.info("BackwardsControlsEvent", "Controls restored to normal")

static func get_duration() -> float:
	return randf_range(45.0, 90.0)

static func get_display_name() -> String:
	return "Backwards Controls"

static func get_description() -> String:
	return "Your controls are reversed! Forward is backward!"
