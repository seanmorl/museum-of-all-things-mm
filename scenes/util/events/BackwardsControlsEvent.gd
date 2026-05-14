class_name BackwardsControlsEvent
extends EventBase
## Backwards Controls - Forward becomes backward and vice versa!

static func apply() -> void:
	var local_player := get_local_player()
	if local_player and local_player.has_method("set_controls_inverted"):
		local_player.set_controls_inverted(true)
		Log.info("BackwardsControlsEvent", "Applied: Controls reversed on player!")
	else:
		Log.warn("BackwardsControlsEvent", "Could not find player or set_controls_inverted method!")
		var players := get_group_nodes("Player")
		if not players.is_empty():
			var player = players[0]
			if player.has_method("set_controls_inverted"):
				player.set_controls_inverted(true)
				Log.info("BackwardsControlsEvent", "Applied via Player group!")

static func end() -> void:
	var local_player := get_local_player()
	if local_player and local_player.has_method("set_controls_inverted"):
		local_player.set_controls_inverted(false)
		Log.info("BackwardsControlsEvent", "Controls restored to normal")

static func get_duration() -> float:
	return randf_range(45.0, 90.0)

static func get_display_name() -> String:
	return "Backwards Controls"

static func get_description() -> String:
	return "Your controls are reversed! Forward is backward!"