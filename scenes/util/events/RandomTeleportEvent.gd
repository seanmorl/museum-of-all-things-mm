class_name RandomTeleportEvent
extends EventBase
## Random Teleport - Instantly teleports all players to a random Wikipedia article

static var _teleported: bool = false

static func apply() -> void:
	if _teleported:
		return
	_teleported = true

	_teleport_all_players.call_deferred()

static func _teleport_all_players() -> void:
	var random_article := _fetch_random_article_sync()
	if random_article.is_empty():
		Log.error("RandomTeleportEvent", "Failed to fetch random article - skipping teleport")
		_teleported = false
		return

	Log.info("RandomTeleportEvent", "Applied: Teleporting all players to '%s'" % random_article)

	var main := get_scene()
	var all_players: Array[Node] = []

	if main and main.has_node("Player"):
		var player = main.get_node("Player")
		if is_instance_valid(player):
			all_players.append(player)

	if main and main.has_node("MultiplayerController"):
		var mp_controller = main.get_node("MultiplayerController")
		if mp_controller and mp_controller.has_method("get_all_players"):
			for p in mp_controller.get_all_players():
				if is_instance_valid(p) and p not in all_players:
					all_players.append(p)

	if all_players.is_empty():
		Log.warn("RandomTeleportEvent", "No players found to teleport")
		_teleported = false
		return

	var exhibit_data = ExhibitFetcher.get_result(random_article)
	if not exhibit_data or exhibit_data.is_empty():
		Log.error("RandomTeleportEvent", "Failed to fetch exhibit data for '%s'" % random_article)
		_teleported = false
		return

	var museum := get_museum()
	if not museum:
		Log.error("RandomTeleportEvent", "Museum node not found")
		_teleported = false
		return

	var exhibit_loader = museum.get_node_or_null("ExhibitLoader")
	if exhibit_loader and exhibit_loader.has_method("load_exhibit"):
		var context := {"title": random_article, "data": exhibit_data, "teleport_event": true}
		exhibit_loader.load_exhibit(context)

	var teleport_target: Node = null
	for child in museum.get_children():
		if child.is_in_group("hall") and child.has_node("Entry"):
			teleport_target = child.get_node("Entry")
			break

	if not teleport_target:
		var doors = get_scene().get_tree().get_nodes_in_group("door")
		if not doors.is_empty():
			teleport_target = doors[0]

	if not teleport_target:
		teleport_target = museum

	var teleport_pos: Vector3
	if teleport_target:
		teleport_pos = teleport_target.global_position
	else:
		teleport_pos = Vector3(0, 5, 0)

	for player in all_players:
		if not is_instance_valid(player):
			continue
		if "rotation" in player:
			player.rotation = Vector3.ZERO
		if "pivot" in player and player.has_node("Pivot"):
			var pivot = player.get_node("Pivot")
			pivot.rotation = Vector3.ZERO
		if "global_position" in player:
			player.global_position = teleport_pos + Vector3(0, 2, 0)
		if "current_room" in player:
			player.set("current_room", random_article)

	Log.info("RandomTeleportEvent", "Teleported %d players to '%s'" % [all_players.size(), random_article])
	_show_teleport_notification(random_article)


static func _fetch_random_article_sync() -> String:
	var http := HTTPRequest.new()
	get_scene().add_child(http)

	var url := "https://en.wikipedia.org/w/api.php?action=query&format=json&generator=random&grnnamespace=0&prop=info&grnlimit=1"
	var result := -1
	var response_code := 0

	http.request_completed.connect(func(_r, code, _h, _b):
		result = _r
		response_code = code
	)

	var err = http.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return ""
	return ""


static func _show_teleport_notification(article_title: String) -> void:
	var main := get_scene()
	if main and main.has_node("ChatSystem"):
		var chat = main.get_node("ChatSystem")
		if chat and chat.has_method("_show_system_message"):
			chat._show_system_message(" Random Teleport! All players sent to: %s" % article_title)
	if main and main.has_node("EventWarningBanner"):
		var banner = main.get_node("EventWarningBanner")
		if banner and banner.has_method("show_message"):
			banner.show_message(" Teleported to: " + article_title, 5.0)

static func end() -> void:
	_teleported = false

static func get_duration() -> float:
	return 0.0

static func get_display_name() -> String:
	return "Random Teleport"

static func get_description() -> String:
	return "All players are teleported to a random Wikipedia article!"
