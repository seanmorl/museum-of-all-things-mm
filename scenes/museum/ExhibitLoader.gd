extends Node
class_name ExhibitLoader
## Manages exhibit loading, caching, and lifecycle.

signal exhibit_loaded(title: String)
## Handles fetching exhibit data, creating halls, and linking exits.

var _museum: Node3D = null
var _exhibits: Dictionary = {}
var _exhibit_hist: Array = []
var _used_exhibit_heights: Dictionary = {}
var _loading_exhibits: Dictionary = {}  # Track in-flight fetches to prevent duplicates
var _pending_items_results: Dictionary = {}  # title -> Dictionary result (per-title items_complete)
var _logged_slot_cap: bool = false

# Backlink race condition fix: track rooms loaded before backlinks ready
var _pending_backlink_rooms: Array[Dictionary] = []  # {title: String, exit: Hall, hall: Hall, doors: Array}

var _starting_height: int = 40
var _height_increment: int = 20

# Configuration
var _items_per_room_estimate: int = 7
var _min_rooms_per_exhibit: int = 2
var _max_exhibits_loaded: int = 999  # Effectively unlimited - exhibits persist for multiplayer room tracking
var _min_room_dimension: int = 2
var _max_room_dimension: int = 5

# Scenes
var TiledExhibitGenerator: PackedScene = preload("res://scenes/TiledExhibitGenerator.tscn")
var WallItem: PackedScene = preload("res://scenes/items/WallItem.tscn")
var GramophoneItem: PackedScene = preload("res://scenes/items/Gramophone.tscn")
var SoundItem: PackedScene = preload("res://scenes/items/SoundItem.tscn")


func init(museum: Node3D, config: Dictionary) -> void:
	_museum = museum
	_items_per_room_estimate = config.get("items_per_room_estimate", 7)
	_min_rooms_per_exhibit = config.get("min_rooms_per_exhibit", 2)
	_max_exhibits_loaded = config.get("max_exhibits_loaded", 2)
	_min_room_dimension = config.get("min_room_dimension", 2)
	_max_room_dimension = config.get("max_room_dimension", 5)
	if not ItemProcessor.items_complete.is_connected(_on_items_complete):
		ItemProcessor.items_complete.connect(_on_items_complete)
	
	# Connect to hints_loaded signal to handle race condition
	var hint_manager = get_node_or_null("/root/HintManager")
	if hint_manager and hint_manager.has_signal("hints_loaded"):
		if not hint_manager.hints_loaded.is_connected(_on_hints_loaded):
			hint_manager.hints_loaded.connect(_on_hints_loaded)
	
	# Connect to race_ended to clean up pending rooms
	if not RaceManager.race_ended.is_connected(_on_race_ended):
		RaceManager.race_ended.connect(_on_race_ended)
	if not RaceManager.race_cancelled.is_connected(_on_race_cancelled):
		RaceManager.race_cancelled.connect(_on_race_cancelled)


func get_exhibits() -> Dictionary:
	return _exhibits


func _debug_log(msg: String) -> void:
	if OS.is_debug_build():
		print(msg)

func get_free_exhibit_height() -> int:
	var height: int = _starting_height
	while _used_exhibit_heights.has(height):
		height += _height_increment
	_used_exhibit_heights[height] = true
	if OS.is_debug_build():
		print("placing exhibit at height=", height)
	return height


func release_exhibit_height(height: int) -> void:
	_used_exhibit_heights.erase(height)


func load_exhibit_from_entry(entry: Hall) -> void:
	var prev_article: String = Util.coalesce(entry.from_title, "Fungus")

	if entry.from_title == "Lobby":
		return

	if _exhibits.has(prev_article):
		var exhibit: Node = _exhibits[prev_article].exhibit
		if is_instance_valid(exhibit):
			return

	# Fetch exhibit data
	ExhibitFetcher.fetch([prev_article], {
		"title": prev_article,
		"entry": entry,
		"backlink": false,
	})


func load_exhibit_from_exit(exit: Hall) -> void:
	var next_article: String = Util.coalesce(exit.to_title, "Fungus")

	if _exhibits.has(next_article):
		var next_exhibit: Dictionary = _exhibits[next_article]
		if (
			next_exhibit.has("entry") and
			next_exhibit.entry.hall_type[1] == exit.hall_type[1] and
			next_exhibit.entry.floor_type == exit.floor_type
		):
			# Link halls for existing exhibits
			link_halls(next_exhibit.entry, exit)
			next_exhibit.entry.from_title = exit.from_title
			return
		else:
			erase_exhibit(next_article)

	# Prevent duplicate fetches while one is in progress
	if _loading_exhibits.has(next_article):
		return
	_loading_exhibits[next_article] = true

	ExhibitFetcher.fetch([next_article], {
		"title": next_article,
		"exit": exit
	})


func load_exhibit_for_rider_without_hall(to_room: String, from_room: String) -> void:
	## Last resort loading for riders when no hall can be found.
	## Creates exhibit without hall linking (rider will be teleported by mount sync).
	if _exhibits.has(to_room):
		return

	if _loading_exhibits.has(to_room):
		return
	
	# Check if we already have cached data (from server sync)
	if ExhibitFetcher.has_result(to_room):
		print("ExhibitLoader: Using cached data for '", to_room, "'")
		on_fetch_complete([to_room], {"title": to_room, "from_room": from_room})
		return
	
	_loading_exhibits[to_room] = true

	ExhibitFetcher.fetch([to_room], {
		"title": to_room,
		"rider_load": true,
		"from_room": from_room
	})


func on_fetch_complete(_titles: Array, context: Dictionary) -> void:
	# we don't need to do anything to handle a prefetch
	if context.has("prefetch"):
		_loading_exhibits.erase(context.get("title", ""))
		return

	# Handle secret room content
	if context.get("secret_room", false):
		_on_secret_room_fetch_complete(context)
		return

	var backlink: bool = context.has("backlink") and context.backlink
	var rider_load: bool = context.has("rider_load") and context.rider_load
	var hall: Hall = context.entry if backlink else context.get("exit")
	var result: Variant = ExhibitFetcher.get_result(context.title)

	# ERROR HANDLING: If fetch failed, show error and revert
	if not result:
		Log.error("ExhibitLoader", "Failed to fetch data for '%s'" % context.title)
		_loading_exhibits.erase(context.get("title", ""))
		_show_error_to_player("Failed to load room: " + context.title)
		# Revert player to previous room if this was a rider load
		if rider_load and _museum and _museum.has_method("_teleport_player_to_lobby"):
			_museum._teleport_player_to_lobby()
		return

	# For rider_load, we don't require a hall - we'll use defaults
	if not result or (not rider_load and not is_instance_valid(hall)):
		_loading_exhibits.erase(context.get("title", ""))
		return

	var prev_title: String
	if rider_load:
		prev_title = context.get("from_room", "")
	else:
		prev_title = hall.from_title

	# Async item generation (runs on worker thread)
	ItemProcessor.create_items(context.title, result, prev_title)

	# Wait for items_complete signal with matching title
	var data: Dictionary = await _wait_for_items_complete(context.title)

	var doors: Array = data.doors
	var items: Array = data.items
	var extra_text: Array = data.extra_text
	var mood: int = data.get("mood", ExhibitMood.Mood.DEFAULT)

	Log.info("ExhibitLoader", "Room '%s' has %d doors" % [context.title, doors.size()])

	var exhibit_height: int = get_free_exhibit_height()

	var new_exhibit: Node3D = TiledExhibitGenerator.instantiate()
	_museum.add_child(new_exhibit)
	_logged_slot_cap = false

	# For rider_load without hall, use default hall_type
	var hall_type: Array = hall.hall_type if is_instance_valid(hall) else [0, 0]
	if is_instance_valid(hall):
		new_exhibit.exit_added.connect(_on_exit_added.bind(doors, backlink, new_exhibit, hall))
	else:
		new_exhibit.exit_added.connect(_on_exit_added_no_hall.bind(doors, new_exhibit))

	new_exhibit.generate({
		"start_pos": Vector3.UP * exhibit_height,
		"min_room_dimension": _min_room_dimension,
		"max_room_dimension": _max_room_dimension,
		"title": context.title,
		"prev_title": prev_title,
		"no_props": items.size() < 10,
		"hall_type": hall_type,
		"exit_limit": doors.size(),
		"mood": mood,
	})

	Log.info("ExhibitLoader", "Generated '%s': exit_limit=%d, doors=%d, items=%d" % [
		context.title, doors.size(), doors.size(), items.size()])

	if not _exhibits.has(context.title):
		_exhibits[context.title] = { "entry": new_exhibit.entry, "exhibit": new_exhibit, "height": exhibit_height, "mood": mood }
		_exhibit_hist.append(context.title)

		# Link halls if we have exit context (critical for door teleportation!)
		if is_instance_valid(hall):
			link_halls(new_exhibit.entry, hall)

		# Spawn NPCs if enabled
		if _museum.npcs_enabled:
			var npc_manager: NPCManager = NPCManager.new()
			new_exhibit.add_child(npc_manager)
			npc_manager.call_deferred("init", new_exhibit, _museum.npcs_per_exhibit)
		
		if _exhibit_hist.size() > _max_exhibits_loaded:
			call_deferred("_cleanup_old_exhibits", new_exhibit.title)
	else:
		# Exhibit already exists - still emit signal so waiters don't hang
		print("ExhibitLoader: Exhibit '", context.title, "' already exists, emitting signal anyway")

	# ALWAYS emit signal (whether new or existing exhibit)
	print("ExhibitLoader: Emitting exhibit_loaded signal for '", context.title, "'")
	exhibit_loaded.emit(context.title)

	# Clear loading flag after exhibit exists (handles both new and duplicate fetch cases)
	_loading_exhibits.erase(context.title)

	var image_titles: Array = []
	var item_queue: Array = []
	for item_data: Dictionary in items:
		if item_data:
			var t: String = item_data.get("type", "") as String
			if (t == "image" or t == "audio") and item_data.has("title") and item_data.title != "":
				image_titles.append(item_data.title)
			item_queue.append(_add_item.bind(new_exhibit, item_data))

	if result.has("wikidata_entity"):
		_museum._queue_item_front(context.title, ExhibitFetcher.fetch_wikidata.bind(result.wikidata_entity, {
			"exhibit": new_exhibit,
			"title": context.title,
			"hall": hall,
			"backlink": backlink,
			"extra_text": extra_text
		}))

	_museum._queue_item_front(context.title, ExhibitFetcher.fetch_images.bind(image_titles, null))
	_museum._queue_item(context.title, item_queue)

	# Spawn persistent ghost silhouettes from previous visits (multiplayer only)
	if NetworkManager.is_multiplayer_active():
		var ghosts: Array = TraceManager.get_ghosts(context.title)
		for ghost_data: Dictionary in ghosts:
			GhostSilhouette.spawn_from_data(new_exhibit, ghost_data)

	# Restore persistently placed paintings for this exhibit
	var placed_paintings: Array = TraceManager.get_placed_paintings(context.title)
	for pd: Dictionary in placed_paintings:
		var wp: Dictionary = pd.get("wall_position", {})
		var wn: Dictionary = pd.get("wall_normal",   {})
		var sz: Dictionary = pd.get("image_size",    {})
		if wp.is_empty() or wn.is_empty():
			continue
		var wall_pos  := Vector3(wp.get("x", 0), wp.get("y", 0), wp.get("z", 0))
		var wall_norm := Vector3(wn.get("x", 0), wn.get("y", 0), wn.get("z", 0))
		var img_size  := Vector2(sz.get("x", 1), sz.get("y", 1))
		_museum._queue_item(context.title, _restore_placed_painting.bind(
			new_exhibit, context.title,
			pd.get("image_title", ""), pd.get("image_url", ""),
			wall_pos, wall_norm, img_size
		))

	# Queue secret room content fetch if exhibit has a secret room
	if new_exhibit.has_secret_room():
		var secret_article: String = SecretRoomContent.get_secret_article(context.title)
		var secret_slots: Array = new_exhibit.get_secret_item_slots()
		if secret_slots.size() > 0:
			ExhibitFetcher.fetch([secret_article], {
				"title": secret_article,
				"secret_room": true,
				"exhibit": new_exhibit,
				"exhibit_title": context.title,
				"secret_slots": secret_slots,
			})

	if backlink:
		new_exhibit.entry.loader.body_entered.connect(_museum._on_loader_body_entered.bind(new_exhibit.entry, true))
	elif rider_load:
		new_exhibit.entry.loader.body_entered.connect(_museum._on_loader_body_entered.bind(new_exhibit.entry, true))


func _on_exit_added_no_hall(exit: Hall, doors: Array, new_exhibit: Node3D) -> void:
	## Simplified exit handler for rider_load case without a source hall.
	var linked_exhibit: String = Util.coalesce(doors.pop_front(), "")
	exit.to_title = linked_exhibit
	if linked_exhibit != "":
		ExhibitGraph.add_edge(new_exhibit.title, linked_exhibit)
	exit.loader.body_entered.connect(_museum._on_loader_body_entered.bind(exit))


func _on_exit_added(exit: Hall, doors: Array, backlink: bool, new_exhibit: Node3D, hall: Hall) -> void:
	var linked_exhibit: String = ""

	# Check if this room is a backlink of the race target (replace random door with target)
	var race_target: String = _get_race_target()
	var hint_manager = get_node_or_null("/root/HintManager")
	var backlinks_ready: bool = hint_manager and hint_manager.has_hints()
	var is_backlink_room: bool = _is_backlink_of_target(new_exhibit.title, race_target)
	
	if is_backlink_room and race_target != "":
		# Replace a random door with the race target
		if doors.size() > 0:
			var random_idx: int = randi() % doors.size()
			linked_exhibit = doors[random_idx]
			doors[random_idx] = race_target  # Replace with target
			Log.info("ExhibitLoader", "Backlink room '%s': replaced door with race target '%s'" % [new_exhibit.title, race_target])
		else:
			linked_exhibit = race_target  # No doors, just use target
			Log.info("ExhibitLoader", "Backlink room '%s': no doors, using race target '%s'" % [new_exhibit.title, race_target])
	elif not backlinks_ready and race_target != "" and not doors.is_empty():
		# Backlinks not ready yet - store this room for later processing
		_pending_backlink_rooms.append({
			"title": new_exhibit.title,
			"exit": exit,
			"hall": hall,
			"doors": doors.duplicate()
		})
		Log.debug("ExhibitLoader", "Room '%s' loaded before backlinks ready - queued for later" % new_exhibit.title)
		# Normal: pop the first door for now (will be updated when backlinks arrive)
		linked_exhibit = Util.coalesce(doors.pop_front(), "")
	elif doors.size() > 0:
		# Normal: pop the first door
		linked_exhibit = Util.coalesce(doors.pop_front(), "")
		Log.debug("ExhibitLoader", "Exit '%s' -> '%s' (doors remaining: %d)" % [
			new_exhibit.title, linked_exhibit, doors.size()])
	else:
		# No more doors left! This exit won't lead anywhere useful
		linked_exhibit = "Lobby"  # Fallback
		Log.warn("ExhibitLoader", "Exit added but no doors remaining! Using fallback to Lobby")

	exit.to_title = linked_exhibit
	if linked_exhibit != "":
		ExhibitGraph.add_edge(new_exhibit.title, linked_exhibit)
	exit.loader.body_entered.connect(_museum._on_loader_body_entered.bind(exit))

func _get_race_target() -> String:
	"""Get the current race target from HintManager."""
	var hint_manager = get_node_or_null("/root/HintManager")
	if hint_manager and hint_manager.has_method("get_current_target"):
		return hint_manager.get_current_target()
	return ""

func _is_backlink_of_target(room_title: String, target: String) -> bool:
	"""Check if this room is a backlink of the race target."""
	if target == "" or room_title == "":
		return false
	var hint_manager = get_node_or_null("/root/HintManager")
	if hint_manager and hint_manager.has_method("get_backlinks"):
		var backlinks = hint_manager.get_backlinks(target)
		if backlinks.is_empty():
			Log.debug("ExhibitLoader", "No backlinks cached for target '%s' yet" % target)
		return backlinks.has(room_title)
	Log.warn("ExhibitLoader", "HintManager not found for backlink check")
	return false

func _on_hints_loaded(_target: String) -> void:
	"""Called when backlinks are loaded - process any pending rooms."""
	if _pending_backlink_rooms.is_empty():
		return
	
	var race_target: String = _get_race_target()
	if race_target == "":
		_pending_backlink_rooms.clear()
		return
	
	var processed_count: int = 0
	for pending in _pending_backlink_rooms:
		var room_title: String = pending.title
		var exit: Hall = pending.exit
		var doors: Array = pending.doors
		
		# Check if this room is now known to be a backlink
		if _is_backlink_of_target(room_title, race_target):
			# Replace the door with the race target
			if doors.size() > 0:
				var old_dest: String = exit.to_title
				exit.to_title = race_target
				Log.info("ExhibitLoader", "Backlink room '%s' (loaded early): updated door from '%s' to '%s'" % [
					room_title, old_dest, race_target])
				processed_count += 1
	
	Log.info("ExhibitLoader", "Processed %d pending backlink rooms after hints loaded" % processed_count)
	_pending_backlink_rooms.clear()

func _on_race_ended(_winner_peer_id: int, _winner_name: String) -> void:
	"""Clean up pending backlink rooms when race ends."""
	if not _pending_backlink_rooms.is_empty():
		Log.debug("ExhibitLoader", "Clearing %d pending backlink rooms on race end" % _pending_backlink_rooms.size())
		_pending_backlink_rooms.clear()

func _on_race_cancelled() -> void:
	"""Clean up pending backlink rooms when race is cancelled."""
	if not _pending_backlink_rooms.is_empty():
		Log.debug("ExhibitLoader", "Clearing %d pending backlink rooms on race cancel" % _pending_backlink_rooms.size())
		_pending_backlink_rooms.clear()


func link_halls(entry: Hall, exit: Hall) -> void:
	if entry.linked_hall == exit and exit.linked_hall == entry:
		return

	for hall: Hall in [entry, exit]:
		Util.clear_listeners(hall, "on_player_toward_exit")
		Util.clear_listeners(hall, "on_player_toward_entry")

	exit.on_player_toward_exit.connect(func():
		if is_instance_valid(exit) and is_instance_valid(entry): _museum._teleport_manager.teleport(exit, entry))
	entry.on_player_toward_entry.connect(func():
		if is_instance_valid(entry) and is_instance_valid(exit): _museum._teleport_manager.teleport(entry, exit, true))
	exit.linked_hall = entry
	entry.linked_hall = exit

	if exit.player_in_hall and exit.player_direction == "exit":
		_museum._teleport_manager.teleport(exit, entry)
	elif entry.player_in_hall and entry.player_direction == "entry":
		_museum._teleport_manager.teleport(entry, exit, true)


func _cleanup_old_exhibits(new_title: String) -> void:
	for e: int in range(_exhibit_hist.size()):
		var key: String = _exhibit_hist[e]
		if _exhibits.has(key):
			var old_exhibit: Dictionary = _exhibits[key]
			var player: Node = _museum._player
			if player and abs(4 * old_exhibit.height - player.position.y) < 20:
				continue
			if old_exhibit.exhibit.title == new_title:
				continue
			erase_exhibit(key)
			break


func _show_error_to_player(message: String) -> void:
	"""Show error message to player via chat system"""
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("_show_system_message"):
		main._show_system_message("❌ " + message)
	Log.error("ExhibitLoader", message)


func _on_items_complete(data: Dictionary) -> void:
	"""Dispatcher: store result keyed by title for per-title waiting"""
	var title: String = data.get("title", "")
	_pending_items_results[title] = data

func _wait_for_items_complete(expected_title: String) -> Dictionary:
	"""Wait for ItemProcessor.items_complete with matching title.
	Uses per-title result map to avoid race conditions with concurrent loads."""
	var timeout_ms := 60000
	var start_time := Time.get_ticks_msec()
	while not _pending_items_results.has(expected_title):
		if Time.get_ticks_msec() - start_time > timeout_ms:
			Log.error("ExhibitLoader", "Timeout waiting for items_complete: %s" % expected_title)
			return {}
		await get_tree().process_frame
	var result: Dictionary = _pending_items_results[expected_title]
	_pending_items_results.erase(expected_title)
	return result


func _on_secret_room_fetch_complete(context: Dictionary) -> void:
	var result: Dictionary = ExhibitFetcher.get_result(context.title)
	if not result:
		return
	var exhibit: Node3D = context.get("exhibit")
	if not is_instance_valid(exhibit):
		return

	var secret_slots: Array = context.get("secret_slots", [])
	if secret_slots.is_empty():
		return

	# Create items from the secret article (async)
	ItemProcessor.create_items(context.title, result)
	var data: Dictionary = await _wait_for_items_complete(context.title)

	var items: Array = data.items
	var slot_idx: int = 0
	var image_titles: Array = []
	for item_data: Dictionary in items:
		if slot_idx >= secret_slots.size():
			break
		if item_data and item_data.has("type"):
			var t: String = item_data.get("type", "") as String
			if (t == "image" or t == "audio") and item_data.has("title") and item_data.title != "":
				image_titles.append(item_data.title)
			var slot: Array = secret_slots[slot_idx]
			_museum._queue_item(context.exhibit_title, _add_item_at_slot.bind(exhibit, item_data, slot))
			slot_idx += 1

	if image_titles.size() > 0:
		_museum._queue_item_front(context.exhibit_title, ExhibitFetcher.fetch_images.bind(image_titles, null))
	
	pass  # Ensure function has explicit end


func _add_item_at_slot(exhibit: Node3D, item_data: Dictionary, slot: Array) -> void:
	if not is_instance_valid(exhibit):
		return
	var item: Node3D = WallItem.instantiate()
	item.position = GridUtils.grid_to_world(slot[0]) - slot[1] * 0.01
	item.rotation.y = GridUtils.vec_to_rot(slot[1])
	_init_item(exhibit, item, item_data)


func erase_exhibit(key: String) -> void:
	if OS.is_debug_build():
		print("erasing exhibit ", key)
	_exhibits[key].exhibit.queue_free()
	release_exhibit_height(_exhibits[key].height)
	_museum._global_item_queue_map.erase(key)
	_exhibits.erase(key)
	var i: int = _exhibit_hist.find(key)
	if i >= 0:
		_exhibit_hist.remove_at(i)


func _add_item(exhibit: Node3D, item_data: Dictionary) -> void:
	if not is_instance_valid(exhibit):
		return

	var slot: Variant = exhibit.get_item_slot()
	if slot == null:
		exhibit.add_room()
		if exhibit.has_item_slot():
			_add_item(exhibit, item_data)
		else:
			if not _logged_slot_cap:
				Log.error("ExhibitLoader", "unable to add item slots to exhibit (further messages suppressed)")
				_logged_slot_cap = true
		return

	var t: String = item_data.get("type", "") as String
	var item: Node3D
	if t == "audio":
		item = SoundItem.instantiate()
	else:
		item = WallItem.instantiate()

	item.position = GridUtils.grid_to_world(slot[0]) - slot[1] * 0.01
	item.rotation.y = GridUtils.vec_to_rot(slot[1])

	_init_item(exhibit, item, item_data)


func _init_item(exhibit: Node3D, item: Node3D, data: Dictionary) -> void:
	if is_instance_valid(exhibit) and is_instance_valid(item):
		exhibit.add_child(item)
		var t: String = data.get("type", "") as String
		if t == "audio":
			var get_res = ExhibitFetcher.get_result(data.get("title", ""))
			var media_url: String = ""
			if get_res and get_res.has("url"):
				media_url = get_res.url
				Log.info("ExhibitLoader", "Audio URL found for '%s': %s" % [data.get("title", ""), media_url])
			else:
				Log.warn("ExhibitLoader", "No audio URL for '%s' - get_res=%s" % [data.get("title", ""), "YES" if get_res else "NO"])
			item.init(exhibit.title, data.get("text", ""), media_url)
			
			# Check if this audio should be stolen (missing)
			var main: Node = _museum.get_parent()
			if main and main.has_method("check_audio_stolen"):
				if main.check_audio_stolen(exhibit.title, data.get("title", "")):
					item.set_stolen(true)
		else:
			item.init(data)

		# Check if this painting should be stolen (missing)
		if data.type == "image":
			var main: Node = _museum.get_parent()
			if main and main.has_method("check_painting_stolen"):
				if main.check_painting_stolen(exhibit.title, data.get("title", "")):
					item.set_stolen(true)


func _restore_placed_painting(exhibit: Node3D, exhibit_title: String,
		image_title: String, image_url: String,
		wall_position: Vector3, wall_normal: Vector3, image_size: Vector2) -> void:
	## Recreates a placed painting mesh at the saved position when the exhibit reloads.
	if not is_instance_valid(exhibit):
		return
	if not _museum.has_node(".."):  # safety
		pass

	# Delegate to PaintingController if available, otherwise build the mesh directly
	var main: Node = _museum.get_parent()
	if main and main.has_method("restore_placed_painting"):
		main.restore_placed_painting(exhibit, exhibit_title, image_title, image_url, wall_position, wall_normal, image_size)
