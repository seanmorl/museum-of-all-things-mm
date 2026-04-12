class_name RandomTeleportEvent
extends RefCounted
## Random Teleport - Instantly teleports all players to a random Wikipedia article
## This is an instant event (0 duration) - chaos mode!

static var _teleported: bool = false

static func apply() -> void:
	if _teleported:
		return  # Already teleported this event instance
	
	_teleported = true
	
	# Fetch a random Wikipedia article
	var random_article = await _fetch_random_article()
	
	if random_article.is_empty():
		Log.error("RandomTeleportEvent", "Failed to fetch random article - skipping teleport")
		_teleported = false
		return

	Log.info("RandomTeleportEvent", "Applied: Teleporting all players to '%s'" % random_article)
	
	# Teleport all players to the random article
	await _teleport_all_players(random_article)


static func _fetch_random_article() -> String:
	"""Fetch a random Wikipedia article title"""
	var http := HTTPRequest.new()
	Engine.get_main_loop().current_scene.add_child(http)
	
	var result: int = -1
	var response_code: int = 0
	var body: PackedByteArray = []
	
	# Use Wikipedia's random article API
	var url := "https://en.wikipedia.org/w/api.php?action=query&format=json&generator=random&grnnamespace=0&prop=info&grnlimit=1"
	
	http.request_completed.connect(func(r, code, _headers, b):
		result = r
		response_code = code
		body = b
	)
	
	var err = http.request(url, RequestSync.COMMON_HEADERS)
	if err != OK:
		http.queue_free()
		return ""
	
	# Wait for response (max 5 seconds)
	var timeout := 5.0
	var elapsed := 0.0
	while result == -1 and elapsed < timeout:
		await Engine.get_main_loop().create_timer(0.1).timeout
		elapsed += 0.1
	
	http.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return ""
	
	# Parse JSON response
	var json := JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		return ""
	
	var data = json.get_data()
	if not data is Dictionary:
		return ""
	
	# Extract article title from response
	var query: Dictionary = data.get("query", {})
	var pages: Dictionary = query.get("pages", {})
	
	for page_id in pages.keys():
		var page: Dictionary = pages[page_id]
		var title: String = page.get("title", "")
		if not title.is_empty():
			return title
	
	return ""


static func _teleport_all_players(target_article: String) -> void:
	"""Teleport all players to the target article"""
	var main = Engine.get_main_loop().current_scene
	
	# Get all players
	var all_players: Array[Node] = []
	
	# Add local player
	if main and main.has_node("Player"):
		var player = main.get_node("Player")
		if player and is_instance_valid(player):
			all_players.append(player)
	
	# Add network players
	if main and main.has_node("MultiplayerController"):
		var mp_controller = main.get_node("MultiplayerController")
		if mp_controller and mp_controller.has_method("get_all_players"):
			var network_players = mp_controller.get_all_players()
			for p in network_players:
				if is_instance_valid(p) and p not in all_players:
					all_players.append(p)
	
	if all_players.is_empty():
		Log.warn("RandomTeleportEvent", "No players found to teleport")
		return

	# Fetch exhibit data for the target article
	var exhibit_data = await ExhibitFetcher.fetch_article(target_article)

	if not exhibit_data or exhibit_data.is_empty():
		Log.error("RandomTeleportEvent", "Failed to fetch exhibit data for '%s'" % target_article)
		return

	# Generate/load the exhibit
	var museum = main.get_node_or_null("Museum") if main else null
	if not museum:
		Log.error("RandomTeleportEvent", "Museum node not found")
		return

	# Use ExhibitLoader to load the exhibit
	var exhibit_loader = museum.get_node_or_null("ExhibitLoader")
	if not exhibit_loader:
		Log.error("RandomTeleportEvent", "ExhibitLoader not found")
		return
	
	# Load the exhibit (this will generate it if needed)
	var context = {
		"title": target_article,
		"data": exhibit_data,
		"teleport_event": true  # Flag to indicate this is from teleport event
	}
	
	exhibit_loader.load_exhibit(context)
	
	# Wait for exhibit to be ready (max 5 seconds)
	var max_wait := 5.0
	var elapsed := 0.0
	while elapsed < max_wait:
		await Engine.get_main_loop().create_timer(0.2).timeout
		elapsed += 0.2
		# Check if exhibit was generated (check if museum has any halls)
		if museum.get_child_count() > 1:  # More than just Lobby
			break
	
	# Find a safe teleport location
	var teleport_target: Node = null
	
	# Try to find a hall that was just created
	for child in museum.get_children():
		if child.is_in_group("hall") and child.has_node("Entry"):
			teleport_target = child.get_node("Entry")
			break
	
	if not teleport_target:
		# Fallback: find any door in the museum
		var doors = museum.get_tree().get_nodes_in_group("door")
		if not doors.is_empty():
			teleport_target = doors[0]
	
	if not teleport_target:
		# Last resort: use museum origin
		teleport_target = museum
	
	# Teleport each player
	var teleport_pos = teleport_target.global_position if teleport_target else Vector3(0, 5, 0)
	
	for player in all_players:
		if not is_instance_valid(player):
			continue
		
		# Reset player rotation to prevent disorientation
		if "rotation" in player:
			player.rotation = Vector3.ZERO
		if "pivot" in player:
			var pivot = player.get_node("Pivot") if player.has_node("Pivot") else null
			if pivot:
				pivot.rotation = Vector3.ZERO
		
		# Set player position
		if "global_position" in player:
			player.global_position = teleport_pos + Vector3(0, 2, 0)
		
		# Update player's room tracking
		if "current_room" in player:
			player.set("current_room", target_article)

	Log.info("RandomTeleportEvent", "Teleported %d players to '%s'" % [all_players.size(), target_article])
	
	# Show notification to all players
	_show_teleport_notification(target_article)


static func _show_teleport_notification(article_title: String) -> void:
	"""Show a notification to players about the teleport"""
	var main = Engine.get_main_loop().current_scene
	
	# Try to use the chat system for notification
	if main and main.has_node("ChatSystem"):
		var chat = main.get_node("ChatSystem")
		if chat and chat.has_method("_show_system_message"):
			chat._show_system_message("🌀 Random Teleport! All players sent to: %s" % article_title)
	
	# Also try EventWarningBanner if available
	if main and main.has_node("EventWarningBanner"):
		var banner = main.get_node("EventWarningBanner")
		if banner and banner.has_method("show_message"):
			banner.show_message("🌀 Teleported to: " + article_title, 5.0)


static func end() -> void:
	# Nothing to clean up - teleport is instant and permanent
	_teleported = false


static func get_duration() -> float:
	return 0.0  # Instant event


static func get_display_name() -> String:
	return "Random Teleport"


static func get_description() -> String:
	return "All players are teleported to a random Wikipedia article!"
