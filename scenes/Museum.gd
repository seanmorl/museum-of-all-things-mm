extends Node3D
## Museum controller managing exhibits, lobby, teleportation, and item queue.
## Uses subsystems for teleportation, multiplayer sync, and exhibit loading.

const _LOBBY_DATA_PATH: String = "res://assets/resources/lobby_data.tres"
const QUEUE_DELAY: float = 0.05
const _GROUP_PLAYER := &"Player"

var StaticData: Resource = preload("res://assets/resources/lobby_data.tres")

# =============================================================================
# EXPORT CONFIGURATION
# =============================================================================
@export var items_per_room_estimate: int = 7
@export var min_rooms_per_exhibit: int = 2
@export var fog_depth: float = 10.0
@export var fog_depth_lobby: float = 20.0
@export var ambient_light_lobby: float = 0.8
@export var ambient_light: float = 0.5
@export var ambient_light_override: float = -1.0  # Deprecated: kept for scene compatibility
@export var ambient_light_multiplier: float = 0.7  # User brightness multiplier (1.0 = mood default)
@export var max_teleport_distance: float = 10.0
@export var max_exhibits_loaded: int = 2
@export var min_room_dimension: int = 2
@export var max_room_dimension: int = 5
@export var npcs_enabled: bool = false
@export var npcs_per_exhibit: int = 0

# =============================================================================
# PRIVATE STATE VARIABLES
# =============================================================================
var _current_room_title: String = "Lobby"
var _grid: GridMap = null
var _player: Node = null
var _custom_door: Hall = null
var _pending_custom_door_title: String = ""

var _queue_running: bool = false
var _global_item_queue_map: Dictionary = {}
var _fog_tween: Tween = null
var _queue_timer: Timer = null
var _disco_hue: float = 0.0
var _dark_mode_lambda: Callable = Callable()

# =============================================================================
# SUBSYSTEMS
# =============================================================================
var _teleport_manager: MuseumTeleportManager = null
var _multiplayer_sync: MuseumMultiplayerSync = null
var _exhibit_loader: ExhibitLoader = null

# Public access to exhibits (used by subsystems)
var _exhibits: Dictionary:
	get: return _exhibit_loader.get_exhibits() if _exhibit_loader else {}

# Track exhibits currently being loaded for riders (to prevent duplicate fetches)
var _rider_loading_exhibits: Dictionary = {}
var _pending_win_room: String = ""


func has_exhibit(title: String) -> bool:
	return _exhibits.has(title)


func clear_rider_loading(title: String) -> void:
	_rider_loading_exhibits.erase(title)


func sync_rider_to_room(room_title: String) -> void:
	## Called when a rider follows their mount to a new room.
	## Updates museum state locally without broadcasting to network.
	if room_title == _current_room_title:
		return

	# Open doors for the rider (mimics _teleport_player door handling)
	# 1. Open the exit door in the source hall (door rider passes through)
	var from_hall: Hall = _find_hall_for_room_transition(_current_room_title, room_title)
	if from_hall:
		from_hall.exit_door.set_open(true)
		from_hall.entry_door.set_open(true)

	# 2. Open the exit door in the destination entry hall (door ahead in new room)
	if _exhibits.has(room_title):
		var dest_exhibit: Node = _exhibits[room_title].get("exhibit")
		if is_instance_valid(dest_exhibit) and "entry" in dest_exhibit:
			dest_exhibit.entry.exit_door.set_open(true)

	_current_room_title = room_title
	WorkQueue.set_current_exhibit(room_title)
	SettingsEvents.emit_set_current_room(room_title)
	_start_queue()

	# Update fog color with mood
	var rider_mood: int = _get_exhibit_mood(_current_room_title)
	_tween_fog_color(ExhibitStyle.gen_fog(_current_room_title), rider_mood)


func load_exhibit_for_rider(from_room: String, to_room: String) -> void:
	if has_exhibit(to_room):
		_rider_loading_exhibits.erase(to_room)  # Clean up tracking
		# Update room immediately if exhibit already loaded
		_set_current_room_title(to_room)
		return  # Already loaded

	# Prevent duplicate fetches while loading is in progress
	if _rider_loading_exhibits.has(to_room):
		return

	# Try finding hall in from_room first
	var hall: Hall = _find_hall_for_room_transition(from_room, to_room)

	# Fallback: search all loaded exhibits for any hall that leads to to_room
	if not hall:
		hall = _find_any_hall_to_room(to_room)

	if hall:
		_rider_loading_exhibits[to_room] = true
		_exhibit_loader.load_exhibit_from_exit(hall)
	else:
		# Last resort: load without hall context (uses default hall styling)
		_rider_loading_exhibits[to_room] = true
		_exhibit_loader.load_exhibit_for_rider_without_hall(to_room, from_room)

	# Update room title immediately for network sync (even before load completes)
	_set_current_room_title(to_room)

	# Schedule validation - if exhibit fails to load, revert to lobby
	if is_inside_tree():
		await get_tree().create_timer(2.0).timeout
		if _rider_loading_exhibits.has(to_room) and not has_exhibit(to_room):
			_revert_to_safe_position(to_room)

func _revert_to_safe_position(failed_room: String) -> void:
	"""When exhibit fails to load, teleport player back to lobby to prevent void falling."""
	_rider_loading_exhibits.erase(failed_room)
	
	# Find all players in the failed room and teleport them to lobby
	var players = get_tree().get_nodes_in_group("Player")
	for player in players:
		if player.has_node("CollisionShape2") and player.has_node("Feet"):
			# Player has collision - teleport to safe position
			player.global_position = Vector3(0, 4, 0)  # Lobby center
			player.velocity = Vector3.ZERO
			if "current_room" in player:
				player.current_room = "Lobby"
	
	# Reset to lobby
	reset_to_lobby()
	
	# Show warning but don't cancel the race — player is at a safe position
	Log.warn("Museum", "Reverted players to lobby after failed load of '%s'" % failed_room)

func _show_exhibit_load_error(failed_room: String) -> void:
	"""Display error message when exhibit fails to load."""
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("_show_error_message"):
		main._show_error_message("Failed to load exhibit: " + failed_room + "\n\nRace cancelled. Please try again.")


func _find_hall_for_room_transition(from_room: String, to_room: String) -> Hall:
	if _exhibits.has(from_room):
		var exhibit_data: Dictionary = _exhibits[from_room]
		var exhibit: Node = exhibit_data.get("exhibit")
		if is_instance_valid(exhibit) and "exits" in exhibit:
			for exit: Hall in exhibit.exits:
				if exit.to_title == to_room:
					return exit

	if from_room == "Lobby" and has_node("Lobby"):
		for exit: Hall in $Lobby.exits:
			if exit.to_title == to_room:
				return exit

	return null


func _find_any_hall_to_room(to_room: String) -> Hall:
	## Fallback: search ALL loaded exhibits for any hall that leads to to_room.
	## Used when the rider's from_room exhibit was unloaded.
	for exhibit_key: String in _exhibits:
		var exhibit_data: Dictionary = _exhibits[exhibit_key]
		var exhibit: Node = exhibit_data.get("exhibit")
		if is_instance_valid(exhibit) and "exits" in exhibit:
			for exit: Hall in exhibit.exits:
				if exit.to_title == to_room:
					return exit
	return null


# =============================================================================
# LIFECYCLE
# =============================================================================
func _init() -> void:
	if OS.is_debug_build():
		RenderingServer.set_debug_generate_wireframes(true)


func _ready() -> void:
	_grid = $Lobby/GridMap

	_queue_timer = Timer.new()
	_queue_timer.wait_time = 0.0 if Platform.is_web() else QUEUE_DELAY
	_queue_timer.one_shot = true
	_queue_timer.timeout.connect(_process_item_queue)
	add_child(_queue_timer)

	# Initialize subsystems
	_teleport_manager = MuseumTeleportManager.new()
	add_child(_teleport_manager)

	_multiplayer_sync = MuseumMultiplayerSync.new()
	add_child(_multiplayer_sync)
	_multiplayer_sync.init(self)

	_exhibit_loader = ExhibitLoader.new()
	add_child(_exhibit_loader)
	_exhibit_loader.init(self, {
		"items_per_room_estimate": items_per_room_estimate,
		"min_rooms_per_exhibit": min_rooms_per_exhibit,
		"max_exhibits_loaded": max_exhibits_loaded,
		"min_room_dimension": min_room_dimension,
		"max_room_dimension": max_room_dimension,
	})

	ExhibitFetcher.wikitext_complete.connect(_on_fetch_complete)
	ExhibitFetcher.wikidata_complete.connect(_on_wikidata_complete)
	ExhibitFetcher.commons_images_complete.connect(_on_commons_images_complete)
	UIEvents.reset_custom_door.connect(_reset_custom_door)
	UIEvents.set_custom_door.connect(_set_custom_door)
	SettingsEvents.language_changed.connect(_on_change_language)
	_dark_mode_lambda = func(_d): _update_lighting()
	ThemeManager.dark_mode_changed.connect(_dark_mode_lambda)

	# Race blocking: lock non-start lobby halls during races
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_ended.connect(_on_race_ended)
	RaceManager.race_cancelled.connect(_on_race_ended)

	# Twitch integration disabled
	# if TwitchManager:
	# 	TwitchManager.color_change_requested.connect(_on_twitch_color_requested)

	ThemeManager.disco_mode_changed.connect(_on_disco_mode_changed)


func _exit_tree() -> void:
	if _queue_timer and _queue_timer.timeout.is_connected(_process_item_queue):
		_queue_timer.timeout.disconnect(_process_item_queue)
	if ExhibitFetcher.wikitext_complete.is_connected(_on_fetch_complete):
		ExhibitFetcher.wikitext_complete.disconnect(_on_fetch_complete)
	if ExhibitFetcher.wikidata_complete.is_connected(_on_wikidata_complete):
		ExhibitFetcher.wikidata_complete.disconnect(_on_wikidata_complete)
	if ExhibitFetcher.commons_images_complete.is_connected(_on_commons_images_complete):
		ExhibitFetcher.commons_images_complete.disconnect(_on_commons_images_complete)
	if UIEvents.reset_custom_door.is_connected(_reset_custom_door):
		UIEvents.reset_custom_door.disconnect(_reset_custom_door)
	if UIEvents.set_custom_door.is_connected(_set_custom_door):
		UIEvents.set_custom_door.disconnect(_set_custom_door)
	if SettingsEvents.language_changed.is_connected(_on_change_language):
		SettingsEvents.language_changed.disconnect(_on_change_language)
	if RaceManager.race_started.is_connected(_on_race_started):
		RaceManager.race_started.disconnect(_on_race_started)
	if RaceManager.race_ended.is_connected(_on_race_ended):
		RaceManager.race_ended.disconnect(_on_race_ended)
	if RaceManager.race_cancelled.is_connected(_on_race_ended):
		RaceManager.race_cancelled.disconnect(_on_race_ended)
	if ThemeManager.disco_mode_changed.is_connected(_on_disco_mode_changed):
		ThemeManager.disco_mode_changed.disconnect(_on_disco_mode_changed)
	if _dark_mode_lambda.is_valid():
		ThemeManager.dark_mode_changed.disconnect(_dark_mode_lambda)


func init(player: Node) -> void:
	_player = player
	_teleport_manager.init(self, player, max_teleport_distance)
	_set_up_lobby($Lobby)
	reset_to_lobby()


# =============================================================================
# LOBBY MANAGEMENT
# =============================================================================
func _get_lobby_exit_zone(exit: Hall) -> Variant:
	var ex: float = GridUtils.grid_to_world(exit.from_pos).x
	var ez: float = GridUtils.grid_to_world(exit.from_pos).z
	for w: Variant in StaticData.wings:
		var c1: Vector2 = w.corner_1
		var c2: Vector2 = w.corner_2
		if ex >= c1.x and ex <= c2.x and ez >= c1.y and ez <= c2.y:
			return w
	return null


func _set_up_lobby(lobby: Node) -> void:
	var exits: Array = lobby.exits
	_exhibit_loader.get_exhibits()["Lobby"] = { "exhibit": lobby, "height": 0 }

	if OS.is_debug_build():
		Log.debug("Museum", "Setting up lobby with %s exits..." % exits.size())

	var wing_indices: Dictionary = {}

	for exit: Hall in exits:
		var wing: Variant = _get_lobby_exit_zone(exit)

		if wing:
			if not wing_indices.has(wing.name):
				wing_indices[wing.name] = -1
			wing_indices[wing.name] += 1
			if wing_indices[wing.name] < wing.exhibits.size():
				exit.to_title = wing.exhibits[wing_indices[wing.name]]
				ExhibitGraph.add_edge("Lobby", exit.to_title)

		elif not _custom_door:
			_custom_door = exit
			_custom_door.entry_door.set_open(false, true)
			_custom_door.to_sign.visible = false
			# Apply pending custom door title if set
			if _pending_custom_door_title != "":
				_custom_door.to_title = _pending_custom_door_title
				_custom_door.entry_door.set_open(true)
				Log.info("Museum", "Applied pending custom door title '%s'" % _pending_custom_door_title)
				_pending_custom_door_title = ""

		if not exit.loader.body_entered.is_connected(_on_loader_body_entered.bind(exit)):
			exit.loader.body_entered.connect(_on_loader_body_entered.bind(exit))


func _set_custom_door(title: String) -> void:
	if _custom_door and is_instance_valid(_custom_door):
		_custom_door.to_title = title
		_custom_door.entry_door.set_open(true)
		Log.info("Museum", "Custom door set to '%s', door opened" % title)
	else:
		Log.warn("Museum", "_custom_door is null! Can't set door to '%s'" % title)
		# Store the title for when door becomes available
		_pending_custom_door_title = title

func _reset_custom_door() -> void:
	if _custom_door and is_instance_valid(_custom_door):
		_custom_door.entry_door.set_open(false)


# =============================================================================
# RACE LOBBY BLOCKING
# =============================================================================

func _on_race_started(_target: String, start_article: String) -> void:
	## When a race starts, lock all lobby halls except the one leading to the start article.
	## This herds players through the intended search corridor.
	var lobby: Node = get_node_or_null("Lobby")
	if not lobby or not "exits" in lobby:
		return

	for hall in lobby.exits:
		if not is_instance_valid(hall):
			continue
		# Don't lock a hall while a player is standing in it
		if hall.player_in_hall:
			continue
		# Lock halls that don't lead to the start article
		if hall.to_title != start_article:
			hall.set_passable(false)
		else:
			# Ensure the start hall is open
			hall.set_passable(true)

func _on_race_ended(_winner_peer_id: int = 0, _winner_name: String = "") -> void:
	## When a race ends, restore all lobby halls to unlocked.
	var lobby: Node = get_node_or_null("Lobby")
	if not lobby or not "exits" in lobby:
		return

	for hall in lobby.exits:
		if not is_instance_valid(hall):
			continue
		hall.set_passable(true)


func _on_change_language(_lang: String = "") -> void:
	if _current_room_title == "Lobby":
		for exhibit: String in _exhibit_loader.get_exhibits().keys():
			if exhibit != "Lobby":
				_exhibit_loader.erase_exhibit(exhibit)
		ExhibitGraph.reset()
		StaticData = ResourceLoader.load(_LOBBY_DATA_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		_set_up_lobby($Lobby)


# =============================================================================
# ROOM/EXHIBIT STATE
# =============================================================================
func get_current_room() -> String:
	return _current_room_title


func hint_preload_nearby_exhibits(from_position: Vector3, extra_radius: float = 0.0) -> void:
	## Called by minimap system when the player zooms out, so rooms that are
	## visible on the map but not yet loaded start generating.
	## Walks all exit halls reachable from the current room and fires their
	## loader triggers if the player is within (normal_range + extra_radius).
	if not _exhibit_loader:
		return
	var check_radius: float = max_teleport_distance + extra_radius
	var lobby: Node = get_node_or_null("Lobby")

	# Collect all halls from loaded exhibits + lobby
	var halls_to_check: Array = []
	if lobby and "exits" in lobby:
		halls_to_check.append_array(lobby.exits)
	for exhibit_data in _exhibit_loader.get_exhibits().values():
		var exhibit: Node = exhibit_data.get("exhibit")
		if is_instance_valid(exhibit) and "exits" in exhibit:
			halls_to_check.append_array(exhibit.exits)

	for hall in halls_to_check:
		if not is_instance_valid(hall):
			continue
		if hall.to_title == "" or _exhibits.has(hall.to_title):
			continue  # Already loaded or no destination
		# Check if the hall entrance is within view range
		var hall_pos: Vector3 = hall.global_position
		if from_position.distance_to(hall_pos) <= check_radius:
			_exhibit_loader.load_exhibit_from_exit(hall)


func _get_exhibit_mood(room_title: String) -> int:
	if _exhibits.has(room_title) and _exhibits[room_title].has("mood"):
		return _exhibits[room_title].mood
	return ExhibitMood.Mood.DEFAULT


func reset_to_lobby() -> void:
	ExhibitGraph.reset()
	for exit: Hall in $Lobby.exits:
		if exit.to_title != "" and exit.to_title != "Lobby":
			ExhibitGraph.add_edge("Lobby", exit.to_title)
	_set_current_room_title("Lobby")
	# All exhibits stay visible - room filtering is handled by player visibility instead
	var exhibits: Dictionary = _exhibit_loader.get_exhibits()
	for exhibit_key: String in exhibits:
		exhibits[exhibit_key]['exhibit'].visible = true


func _set_current_room_title(title: String) -> void:
	_current_room_title = title
	WorkQueue.set_current_exhibit(title)
	SettingsEvents.emit_set_current_room(title)
	_start_queue()
	
	# Update Discord Rich Presence
	if has_node("/root/DiscordRichPresence"):
		$"/root/DiscordRichPresence".set_in_lobby(title)

	# Update local player's room BEFORE broadcasting (so visibility checks use the new value)
	if _player and "current_room" in _player:
		_player.current_room = title

		# Also update any rider mounted on local player (sync room immediately to prevent race condition)
		if "has_rider" in _player and _player.has_rider:
			var rider: Node = _player.mounted_by
			if is_instance_valid(rider) and "current_room" in rider:
				rider.current_room = title

	# Broadcast room change to network
	if NetworkManager.is_multiplayer_active():
		NetworkManager.set_local_player_room(title)

	# Race win detection - only trigger if exhibit actually loaded successfully
	if RaceManager.is_race_active() and title == RaceManager.get_target_article():
		# Verify the exhibit exists and has content before allowing win
		if has_exhibit(title):
			var exhibit_data = _exhibits[title]
			if exhibit_data and exhibit_data.get("exhibit"):
				# Exhibit loaded successfully - valid win
				_pending_win_room = ""
				RaceManager.notify_article_reached(NetworkManager.get_unique_id(), title)
			else:
				Log.warn("Museum", "Blocked false win - exhibit '%s' has no content" % title)
		else:
			# Defer win check — exhibit is still loading
			_pending_win_room = title

	var mood: int = _get_exhibit_mood(_current_room_title)
	_tween_fog_color(ExhibitStyle.gen_fog(_current_room_title), mood)


func _tween_fog_color(fog_color: Color, mood: int = ExhibitMood.Mood.DEFAULT) -> void:
	var environment: Environment = $WorldEnvironment.environment
	if _fog_tween and _fog_tween.is_valid():
		_fog_tween.kill()
	_fog_tween = create_tween()
	_fog_tween.set_parallel(true)
	_fog_tween.set_trans(Tween.TRANS_LINEAR)
	_fog_tween.set_ease(Tween.EASE_IN_OUT)

	# Fog color from mood (overrides style-based fog for non-default moods)
	var target_fog: Color = ExhibitMood.get_fog_color(mood) if mood != ExhibitMood.Mood.DEFAULT else fog_color
	_fog_tween.tween_property(environment, "fog_light_color", target_fog, 1.0)

	# Fog density (scaled relative to default depth of 10)
	var target_depth: float = ExhibitMood.get_fog_depth(mood)
	_fog_tween.tween_property(environment, "fog_density", 10.0 / target_depth, 1.0)

	# Ambient light — combine mood-adjusted base with user brightness multiplier
	var is_dark = ThemeManager.is_dark_mode
	var target_ambient_color: Color = ExhibitMood.get_ambient_color(mood)
	var base_energy: float = ExhibitMood.get_adjusted_ambient_energy(mood, is_dark)
	var target_ambient_energy: float = clamp(base_energy * ambient_light_multiplier, 0.0, 1.5)

	_fog_tween.tween_property(environment, "ambient_light_color", target_ambient_color, 1.0)
	_fog_tween.tween_property(environment, "ambient_light_energy", target_ambient_energy, 1.0)

	# Boost tonemap exposure in light mode for overall brighter appearance
	var target_exposure: float = 1.0 if not is_dark else 0.8
	_fog_tween.tween_property(environment, "tonemap_exposure", target_exposure, 1.0)

	# Per-room glow intensity — varies with mood so each exhibit feels distinct.
	var target_glow: float = _get_glow_for_mood(mood)
	GraphicsManager.tween_room_glow(target_glow, 1.2)


func _get_glow_for_mood(mood: int) -> float:
	## Maps exhibit mood to a target glow intensity.
	## Art / creative exhibits glow more; science / tech exhibits glow less.
	match mood:
		ExhibitMood.Mood.DEFAULT: return 0.6
		ExhibitMood.Mood.HISTORY: return 0.7
		ExhibitMood.Mood.SCIENCE: return 0.5
		ExhibitMood.Mood.NATURE: return 0.7
		ExhibitMood.Mood.ASTRO: return 0.5
		ExhibitMood.Mood.MEDIA: return 0.8
		ExhibitMood.Mood.ART: return 0.9
		ExhibitMood.Mood.GEOGRAPHY: return 0.6
		ExhibitMood.Mood.PHILOSOPHY: return 0.5
		ExhibitMood.Mood.SPORTS: return 0.8
		ExhibitMood.Mood.FOOD: return 0.7
		ExhibitMood.Mood.POLITICS: return 0.6
		ExhibitMood.Mood.ECONOMY: return 0.7
		ExhibitMood.Mood.MYSTERY: return 0.4
		_:
			return 0.6


func _update_lighting() -> void:
	var mood: int = _get_exhibit_mood(_current_room_title)
	_tween_fog_color(ExhibitStyle.gen_fog(_current_room_title), mood)


func set_ambient_light(value: float) -> void:
	"""Set ambient light via brightness slider. Stores user preference as a multiplier
	of the mood-adjusted base, so dark/light mode transitions preserve relative brightness."""
	var mood: int = _get_exhibit_mood(_current_room_title)
	var is_dark = ThemeManager.is_dark_mode
	var base_energy: float = ExhibitMood.get_adjusted_ambient_energy(mood, is_dark)
	if base_energy > 0.001:
		ambient_light_multiplier = clamp(value / base_energy, 0.1, 5.0)
	else:
		ambient_light_multiplier = 1.0
	var environment: Environment = $WorldEnvironment.environment
	if environment:
		environment.ambient_light_energy = clamp(value, 0.0, 1.5)


func _on_twitch_color_requested(color: Color) -> void:
	if not _multiplayer_sync.is_local_player(_player) and NetworkManager.is_multiplayer_active():
		return # Only host/local player processes Twitch input for the museum state

	var environment: Environment = $WorldEnvironment.environment
	if _fog_tween and _fog_tween.is_valid():
		_fog_tween.kill()
	_fog_tween = create_tween()
	_fog_tween.tween_property(environment, "ambient_light_color", color, 2.0)
	_fog_tween.parallel().tween_property(environment, "ambient_light_energy", 0.5, 2.0)


func _on_disco_mode_changed(enabled: bool) -> void:
	if not enabled:
		# Immediately restore the intended museum atmosphere
		_update_lighting()


# =============================================================================
# EXHIBIT LOADING (DELEGATES TO ExhibitLoader)
# =============================================================================
func _load_exhibit_from_entry(entry: Hall) -> void:
	_exhibit_loader.load_exhibit_from_entry(entry)


func _load_exhibit_from_exit(exit: Hall) -> void:
	_exhibit_loader.load_exhibit_from_exit(exit)


func _on_fetch_complete(titles: Array, context: Dictionary) -> void:
	clear_rider_loading(context.get("title", ""))
	_exhibit_loader.on_fetch_complete(titles, context)
	# Check if this was a pending win room
	var loaded_title: String = context.get("title", "")
	if _pending_win_room != "" and loaded_title == _pending_win_room and RaceManager.is_race_active():
		if loaded_title == RaceManager.get_target_article() and has_exhibit(loaded_title):
			_pending_win_room = ""
			RaceManager.notify_article_reached(NetworkManager.get_unique_id(), loaded_title)


func _on_wikidata_complete(entity: String, ctx: Dictionary) -> void:
	var result: Variant = ExhibitFetcher.get_result(entity)
	if result and (result.has("commons_category") or result.has("commons_gallery")):
		if result.has("commons_category"):
			ExhibitFetcher.fetch_commons_images(result.commons_category, ctx)
		if result.has("commons_gallery"):
			ExhibitFetcher.fetch_commons_images(result.commons_gallery, ctx)
	else:
		_queue_extra_text(ctx.exhibit, ctx.extra_text)
		_queue_item(ctx.title, _on_finished_exhibit.bind(ctx))


func _on_commons_images_complete(images: Array, ctx: Dictionary) -> void:
	if images.size() > 0:
		var item_data: Array = ItemProcessor.commons_images_to_items(ctx.title, images, ctx.extra_text)
		for item: Dictionary in item_data:
			_queue_item(ctx.title, _exhibit_loader._add_item.bind(
				ctx.exhibit,
				item
			))
	_queue_item(ctx.title, _on_finished_exhibit.bind(ctx))


func _on_finished_exhibit(ctx: Dictionary) -> void:
	if not is_instance_valid(ctx.exhibit):
		return
	if OS.is_debug_build():
		Log.debug("Museum", "finished exhibit. slots=%d" % ctx.exhibit._item_slots.size())
	if ctx.backlink:
		_exhibit_loader._link_backlink_to_exit(ctx.exhibit, ctx.hall)


# =============================================================================
# MULTIPLAYER TRANSITIONS (DELEGATES TO MuseumMultiplayerSync)
# =============================================================================
func _on_loader_body_entered(body: Node, hall: Hall, backlink: bool = false) -> void:
	if hall.to_title == "" or hall.to_title == _current_room_title:
		return

	if body.is_in_group(_GROUP_PLAYER):
		if NetworkManager.is_multiplayer_active() and not _multiplayer_sync.is_local_player(body):
			return

		if NetworkManager.is_multiplayer_active():
			_multiplayer_sync.request_multiplayer_transition(hall, backlink)
		else:
			if backlink:
				_load_exhibit_from_entry(hall)
			else:
				_load_exhibit_from_exit(hall)


@rpc("any_peer", "call_remote", "reliable")
func request_transition(to_title: String, hall_info: Dictionary) -> void:
	_multiplayer_sync.handle_transition_request(to_title, hall_info)


@rpc("authority", "call_local", "reliable")
func execute_transition(to_title: String, from_title: String, hall_info: Dictionary) -> void:
	_multiplayer_sync.execute_transition(to_title, from_title, hall_info)


func sync_to_exhibit(exhibit_title: String) -> void:
	_multiplayer_sync.sync_to_exhibit(exhibit_title)


# =============================================================================
# ITEM QUEUE SYSTEM
# =============================================================================
func _process(delta: float) -> void:
	if ThemeManager.disco_mode:
		## Respect the "reduce motion" accessibility setting by capping hue speed.
		var hue_speed: float = 0.08 if GraphicsManager.reduce_motion else 0.5
		_disco_hue = fmod(_disco_hue + delta * hue_speed, 1.0)
		var disco_color = Color.from_hsv(_disco_hue, 0.8, 0.8)
		var world_env := $WorldEnvironment
		if world_env:
			world_env.environment.ambient_light_color = disco_color
			world_env.environment.ambient_light_energy = 0.6

	var queue: Array = _global_item_queue_map.get(_current_room_title, [])
	if queue.is_empty():
		_queue_running = false
		return
	var batch: int = 5 if Platform.is_web() else 1
	for _i in batch:
		if queue.is_empty():
			break
		var callable: Callable = queue.pop_front()
		callable.call()
	_queue_running = true
	_queue_timer.start()


func _process_item_queue() -> void:
	var queue: Array = _global_item_queue_map.get(_current_room_title, [])
	if queue.is_empty():
		_queue_running = false
		return
	var batch: int = 5 if Platform.is_web() else 1
	for _i in batch:
		if queue.is_empty():
			break
		var callable: Callable = queue.pop_front()
		callable.call()
	_queue_running = true
	_queue_timer.start()


func _queue_item_front(title: String, item: Variant) -> void:
	_queue_item(title, item, true)


func _queue_item(title: String, item: Variant, front: bool = false) -> void:
	if not _global_item_queue_map.has(title):
		_global_item_queue_map[title] = []
	if typeof(item) == TYPE_CALLABLE:
		# Wrap callable in lambda to check instance validity before calling
		var original_callable: Callable = item as Callable
		var safe_callable: Callable = func():
			# Check if the first bound object (exhibit) is still valid
			var obj: Object = original_callable.get_object()
			if is_instance_valid(obj):
				original_callable.call()
		if not front:
			_global_item_queue_map[title].append(safe_callable)
		else:
			_global_item_queue_map[title].push_front(safe_callable)
	elif typeof(item) == TYPE_ARRAY:
		_global_item_queue_map[title].append_array(item)
	elif not front:
		_global_item_queue_map[title].append(item)
	else:
		_global_item_queue_map[title].push_front(item)
	_start_queue()


func _start_queue() -> void:
	if not _queue_running:
		_process_item_queue()


func _queue_extra_text(exhibit: Node, extra_text: Array) -> void:
	for item: Dictionary in extra_text:
		_queue_item(exhibit.title, _exhibit_loader._add_item.bind(exhibit, item))
