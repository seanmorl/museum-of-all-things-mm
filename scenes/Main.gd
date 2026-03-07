extends Node
## Main game controller handling initialization and delegating to subsystems.


const _SKIN_EQUIP_SOUND: AudioStream = preload("res://assets/sound/UI/UI Crystal 1.ogg")

@export var Player: PackedScene = preload("res://scenes/Player.tscn")
@export var NetworkPlayer: PackedScene = preload("res://scenes/NetworkPlayer.tscn")
@export var smooth_movement: bool = false
@export var smooth_movement_dampening: float = 0.001
@export var player_speed: int = 6
@export var starting_point: Vector3 = Vector3(0, 4, 0)
@export var starting_rotation: float = 0

var _player: CharacterBody3D = null
var _player_pivot: Node3D = null
var _fps_update_timer: float = 0.0

# Subsystems
var _menu_controller: MainMenuController = null
var _multiplayer_controller: MultiplayerController = null
var _mount_controller: MountController = null
var _painting_controller: PaintingController = null
var _pointing_controller: PointingController = null
var _chat_system: Node = null
var _chat_hud: Node = null

@onready var _journal_overlay: JournalOverlay = %JournalOverlay
@onready var player_list_overlay: Control = %PlayerListOverlay
@onready var _server_console_overlay: Control = %ServerConsoleOverlay
@onready var _map_overlay: Control = %ExhibitMapOverlay
@onready var _guestbook_overlay: GuestbookOverlay = %GuestbookOverlay
@onready var _menu_layer: CanvasLayer = %MenuLayer
@onready var _fps_label: Label = %FpsLabel
@onready var _museum: Node3D = %Museum
@onready var _game_launch_sting: AudioStreamPlayer = %GameLaunchSting
@onready var _crt_post_processing: CanvasLayer = %CRTPostProcessing
@onready var _world_light: DirectionalLight3D = %WorldLight
@onready var _pause_menu: Control = %PauseMenu
var game_started: bool = false
## True when running as a UI-based dedicated host (no local player spawned)
var _is_ui_dedicated_host: bool = false
## The peer_id who currently has race control (host by default, first joiner in dedicated host mode)
var _race_controller_peer_id: int = 1


func _debug_log(message: String) -> void:
	Log.debug("Main", message)


func _parse_command_line() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	for i: int in args.size():
		match args[i]:
			"--server":
				_multiplayer_controller.set_server_mode(true)
			"--port":
				if i + 1 < args.size():
					_multiplayer_controller.set_server_mode(
						_multiplayer_controller.is_server_mode(),
						int(args[i + 1])
					)
			"--server-ip":
				if i + 1 < args.size():
					MultiplayerMenu.default_server_address = args[i + 1]


func _ready() -> void:
	# Initialize subsystems first
	_menu_controller = MainMenuController.new()
	_menu_controller.init(self, _menu_layer)
	_menu_controller.game_start_requested.connect(_start_game)
	_menu_controller.multiplayer_start_requested.connect(_on_multiplayer_start_game)
	add_child(_menu_controller)

	# Connect dedicated host button from MainMenu
	var main_menu_node := _menu_layer.get_node_or_null("MainMenu")
	if main_menu_node and main_menu_node.has_signal("start_dedicated_host"):
		main_menu_node.start_dedicated_host.connect(_on_dedicated_host_pressed)

	_multiplayer_controller = MultiplayerController.new()
	_multiplayer_controller.init(self, NetworkPlayer, starting_point)
	add_child(_multiplayer_controller)

	_mount_controller = MountController.new()
	_mount_controller.init(self, _multiplayer_controller)
	add_child(_mount_controller)

	_painting_controller = PaintingController.new()
	_painting_controller.init(self, _multiplayer_controller)
	add_child(_painting_controller)

	_pointing_controller = PointingController.new()
	_pointing_controller.init(self)
	add_child(_pointing_controller)

	_chat_system = ChatSystem.new()
	_chat_system.name = "ChatSystem"
	add_child(_chat_system)
	_chat_system.init(self)

	_chat_hud = ChatHUD.new()
	_chat_hud.name = "ChatHUD"
	add_child(_chat_hud)
	_chat_hud.init(_chat_system)

	_parse_command_line()

	if _multiplayer_controller.is_server_mode():
		_start_dedicated_server()
		return

	if OS.has_feature("movie"):
		_fps_label.visible = false

	_recreate_player()

	GraphicsManager.change_post_processing.connect(_change_post_processing)
	GraphicsManager.init()

	GameplayEvents.return_to_lobby.connect(_on_pause_menu_return_to_lobby)
	MultiplayerEvents.skin_selected.connect(_on_skin_selected)
	MultiplayerEvents.skin_reset.connect(_on_skin_reset)
	UIEvents.open_terminal_menu.connect(_use_terminal)
	UIEvents.quit_requested.connect(_on_quit_requested)

	# Race signals
	_pause_menu.start_race.connect(_on_start_race_pressed)
	add_to_group("main")
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.vote_cancelled.connect(_on_vote_cancelled)
	ExhibitFetcher.random_complete.connect(_on_random_article_complete)
	ExhibitFetcher.category_random_complete.connect(_on_random_article_complete)

	# Load saved skin
	_load_saved_skin()

	# Multiplayer signals
	NetworkManager.peer_connected.connect(_on_network_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_network_peer_disconnected)
	NetworkManager.server_disconnected.connect(_on_network_server_disconnected)
	NetworkManager.player_info_updated.connect(_on_network_player_info_updated)

	call_deferred("_play_sting")

	_world_light.visible = Platform.is_compatibility_renderer()

	_pause_game()


func _play_sting() -> void:
	_game_launch_sting.play()


func _recreate_player() -> void:
	if _player:
		remove_child(_player)
		_player.queue_free()

	_player = Player.instantiate()
	add_child(_player)
	_player_pivot = _player.get_node("Pivot")
	_player_pivot.get_node("Camera3D").make_current()
	_player.rotation.y = starting_rotation
	_player.max_speed = player_speed
	_player.smooth_movement = smooth_movement
	_player.dampening = smooth_movement_dampening
	_player.position = starting_point
	_player.set_player_color(NetworkManager.local_player_color)


func _change_post_processing(post_processing: String) -> void:
	_crt_post_processing.visible = post_processing == "crt"


func _start_game() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_player.start()
	_menu_controller.close_menus()
	_map_overlay.restore_after_pause()
	if not game_started:
		game_started = true
		_museum.init(_player)


func _pause_game() -> void:
	_player.pause()
	if game_started:
		if _menu_layer.visible:
			return
		_menu_controller.open_pause_menu()
	else:
		_menu_controller.open_main_menu()


func _use_terminal() -> void:
	_player.pause()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_menu_controller.open_terminal_menu()


# =============================================================================
# MENU CALLBACKS
# =============================================================================

func _on_main_menu_start_pressed() -> void:
	_start_game()


func _on_main_menu_multiplayer() -> void:
	_menu_controller.on_main_menu_multiplayer()


func _on_multiplayer_menu_back() -> void:
	_menu_controller.on_multiplayer_menu_back()


func _on_multiplayer_start_game() -> void:
	_multiplayer_controller.set_multiplayer_game(true)
	_start_multiplayer_game()


func _on_dedicated_host_pressed() -> void:
	_start_ui_dedicated_host()


func _start_ui_dedicated_host() -> void:
	## Starts the server while keeping the host in the main menu UI.
	## No local player is spawned. The first player to join gets race control.
	_is_ui_dedicated_host = true
	_race_controller_peer_id = -1  # not yet assigned

	_multiplayer_controller.set_server_mode(true)
	_multiplayer_controller.set_multiplayer_game(true)

	# Signals are already connected in _ready() — no reconnection needed

	var error: Error = NetworkManager.host_game(_multiplayer_controller.get_server_port(), true)
	if error != OK:
		Log.error("Main", "Dedicated host failed: %s" % str(error))
		_is_ui_dedicated_host = false
		return

	game_started = true
	_museum.init(null)

	# Update main menu to show hosting status + stop button
	var main_menu_node := _menu_layer.get_node_or_null("MainMenu")
	if main_menu_node:
		var lbl := Label.new()
		lbl.name = "HostStatusLabel"
		lbl.text = "Hosting on port %d — waiting for players..." % _multiplayer_controller.get_server_port()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.4, 0.7, 0.4))
		var container := main_menu_node.get_node("%Quit").get_parent()
		container.add_child(lbl)

		var stop_btn := Button.new()
		stop_btn.name = "StopHostingButton"
		stop_btn.text = "Stop Hosting"
		stop_btn.pressed.connect(_on_stop_hosting_pressed)
		container.add_child(stop_btn)

		# Hide the Host Server button while hosting
		var host_btn := main_menu_node.get_node_or_null("DedicatedHost")
		if host_btn:
			host_btn.visible = false

	Log.info("Main", "UI dedicated host started on port %d" % _multiplayer_controller.get_server_port())


func _on_stop_hosting_pressed() -> void:
	Log.info("Main", "Stopping dedicated host...")
	_multiplayer_controller.end_multiplayer_session()
	NetworkManager.disconnect_from_game()
	_multiplayer_controller.set_server_mode(false)
	_multiplayer_controller.set_multiplayer_game(false)
	_is_ui_dedicated_host = false
	_race_controller_peer_id = 1
	game_started = false

	# Restore main menu UI
	var main_menu_node := _menu_layer.get_node_or_null("MainMenu")
	if main_menu_node:
		var container := main_menu_node.get_node("%Quit").get_parent()
		var lbl := container.get_node_or_null("HostStatusLabel")
		if lbl:
			lbl.queue_free()
		var stop_btn := container.get_node_or_null("StopHostingButton")
		if stop_btn:
			stop_btn.queue_free()
		var host_btn := main_menu_node.get_node_or_null("DedicatedHost")
		if host_btn:
			host_btn.visible = true


func _on_main_menu_settings() -> void:
	_menu_controller.on_main_menu_settings()


func _on_pause_menu_settings() -> void:
	_menu_controller.on_pause_menu_settings()


func _on_pause_menu_return_to_lobby() -> void:
	_player.rotation.y = starting_rotation
	_player.position = starting_point
	_museum.reset_to_lobby()
	_start_game()


func _on_settings_back() -> void:
	_menu_controller.on_settings_back()


# =============================================================================
# INPUT HANDLING
# =============================================================================
func _input(event: InputEvent) -> void:
	if Input.is_action_pressed("toggle_fullscreen"):
		UIEvents.fullscreen_toggled.emit(not GraphicsManager.fullscreen)

	if not game_started:
		return

	# Don't process game inputs while the chat input is open
	var chat_open: bool = _chat_hud != null and _chat_hud.is_input_open()
	if not chat_open:
		if Input.is_action_just_pressed("ui_accept"):
			UIEvents.emit_ui_accept_pressed()

		if Input.is_action_just_pressed("ui_cancel") and _menu_layer.visible:
			UIEvents.emit_ui_cancel_pressed()

		if Input.is_action_just_pressed("show_fps"):
			_fps_label.visible = not _fps_label.visible

		if Input.is_action_just_pressed("toggle_server_console"):
			if _multiplayer_controller.is_multiplayer_game():
				_server_console_overlay.toggle()

		if event.is_action_pressed("toggle_journal"):
			if _journal_overlay:
				if _journal_overlay.is_open():
					_journal_overlay.close()
				else:
					_journal_overlay.open()
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
					_player.pause()

		if event.is_action_pressed("toggle_map") and not _menu_layer.visible:
			_map_overlay.cycle_mode()

		if event.is_action_pressed("pause"):
			_map_overlay.set_hidden()
			_pause_game()

		if event.is_action_pressed("free_pointer"):
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

		if event.is_action_pressed("click") and not _menu_layer.visible:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
				var overlay_open: bool = (_journal_overlay and _journal_overlay.is_open()) or (_guestbook_overlay and _guestbook_overlay.is_open())
				if not overlay_open:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

		# Tab key for player list overlay
		if _multiplayer_controller.is_multiplayer_game() and not _menu_layer.visible:
			if event.is_action_pressed("show_player_list"):
				player_list_overlay.visible = true
			elif event.is_action_released("show_player_list"):
				player_list_overlay.visible = false


func _process(delta: float) -> void:
	if _fps_label.visible:
		_fps_update_timer -= delta
		if _fps_update_timer <= 0.0:
			_fps_update_timer = 0.5
			_fps_label.text = str(Engine.get_frames_per_second())

	# Broadcast local player position to other players
	if _multiplayer_controller.process_position_sync(delta, _player):
		var pivot_rot_x: float = _player_pivot.rotation.x if _player_pivot else 0.0
		var pivot_pos_y: float = _player_pivot.position.y if _player_pivot else 1.35
		var is_mounted: bool = _player.is_mounted
		var mounted_peer_id: int = _player.mount_peer_id
		# If mounted, use mount's room to stay synced during room transitions
		var current_room: String = "Lobby"
		if is_mounted and is_instance_valid(_player.mounted_on) and "current_room" in _player.mounted_on:
			current_room = _player.mounted_on.current_room
		elif "current_room" in _player:
			current_room = _player.current_room
		var pointing: bool = _player.is_pointing
		var pt_target: Vector3 = _player.point_target if pointing else Vector3.ZERO
		_sync_player_position.rpc(
			NetworkManager.get_unique_id(),
			_player.global_position,
			_player.rotation.y,
			pivot_rot_x,
			pivot_pos_y,
			is_mounted,
			mounted_peer_id,
			current_room,
			pointing,
			pt_target
		)


# =============================================================================
# SKIN FUNCTIONS
# =============================================================================
func _save_skin_preference(url: String) -> void:
	var player_settings = SettingsManager.get_settings("player")
	if not player_settings:
		player_settings = {}
	player_settings["skin_url"] = url
	SettingsManager.save_settings("player", player_settings)



func _on_skin_selected(url: String, _texture: ImageTexture) -> void:
	NetworkManager.set_local_player_skin(url)
	_save_skin_preference(url)
	if _player:
		_player.set_player_skin(url, _texture)
	UISoundManager._play(_SKIN_EQUIP_SOUND)
	_debug_log("Main: Skin selected: " + url)


func _on_skin_reset() -> void:
	NetworkManager.set_local_player_skin("")
	_save_skin_preference("")
	if _player:
		_player.clear_player_skin()
	_debug_log("Main: Skin reset")


func _load_saved_skin() -> void:
	var player_settings = SettingsManager.get_settings("player")
	if player_settings and player_settings.has("skin_url"):
		var skin_url: String = player_settings["skin_url"]
		if skin_url != "":
			NetworkManager.local_player_skin = skin_url
			if _player:
				_player.set_player_skin(skin_url)
			_debug_log("Main: Loaded saved skin: " + skin_url)


# =============================================================================
# RACE FUNCTIONS
# =============================================================================
func _on_start_race_pressed() -> void:
	if RaceManager.is_race_active():
		return

	if NetworkManager.is_server():
		_debug_log("Main: Fetching random articles for race vote...")
		_race_candidates.clear()
		_race_target_article = ""
		_race_fetches_pending = RaceManager.CANDIDATE_COUNT + 1
		_show_vote_loading()
		# Fetch all candidates in a single Wikipedia API call
		_fetch_race_candidates()
		# Target still uses Toolforge for quality filtering
		_fetch_race_target()
	else:
		_debug_log("Main: Sending _request_race_start RPC to server (my id: %d, multiplayer active: %s)" % [multiplayer.get_unique_id(), NetworkManager.is_multiplayer_active()])
		_request_race_start.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_race_start() -> void:
	_debug_log("Main: _request_race_start RPC received from peer %d" % multiplayer.get_remote_sender_id())
	if not NetworkManager.is_server():
		return
	if RaceManager.is_race_active():
		return
	_debug_log("Main: Race start requested by peer, fetching random articles for vote...")
	_race_candidates.clear()
	_race_target_article = ""
	_race_fetches_pending = RaceManager.CANDIDATE_COUNT + 1
	_show_vote_loading()
	_fetch_race_candidates()
	_fetch_race_target()


## Collects random articles for the vote pool + target.
var _race_candidates: Array = []
var _race_target_article: String = ""
var _race_fetches_pending: int = 0

var _race_retry_count: int = 0
const MAX_RACE_RETRIES: int = 10

func _on_random_article_complete(title: Variant, context: Dictionary) -> void:
	if not context or not context.has("race") or not context.race:
		return

	if title == null or title == "":
		_race_retry_count += 1
		if _race_retry_count > MAX_RACE_RETRIES:
			Log.error("Main", "Too many fetch failures — giving up and launching with what we have")
			_race_retry_count = 0
			if _race_candidates.size() > 0:
				_launch_vote()
			return
		Log.error("Main", "Failed to fetch random article for race — retrying (%d/%d)" % [_race_retry_count, MAX_RACE_RETRIES])
		var role: String = context.get("race_role", "candidate")
		if role == "candidate":
			_fetch_one_candidate()
		else:
			_fetch_race_target()
		return

	_race_retry_count = 0
	var role: String = context.get("race_role", "candidate")
	if role == "candidate":
		# Deduplicate: if this title is already in the pool, fetch a replacement
		if title in _race_candidates or title == _race_target_article:
			_debug_log("Main: Duplicate candidate '%s' — retrying" % title)
			_fetch_one_candidate()
			return
		_race_candidates.append(title)
		_race_fetches_pending -= 1
		_debug_log("Main: Got candidate '%s' (%d remaining)" % [title, _race_fetches_pending])
		if _race_fetches_pending <= 0 and _race_target_article != "":
			_launch_vote()
	elif role == "target":
		_race_target_article = title
		_race_fetches_pending -= 1
		_debug_log("Main: Got target '%s'" % title)
		if _race_fetches_pending <= 0 and _race_candidates.size() >= RaceManager.CANDIDATE_COUNT:
			_launch_vote()

func _fetch_race_target() -> void:
	## Category override takes priority over difficulty setting.
	var cat := RaceManager.get_category_override()
	if cat != "":
		ExhibitFetcher.fetch_random_from_category(cat, { "race": true, "race_role": "target" })
	elif RaceManager.get_difficulty() == "random_category":
		ExhibitFetcher.fetch_random_category_article({ "race": true, "race_role": "target" })
	else:
		ExhibitFetcher.fetch_random_target({ "race": true, "race_role": "target" }, RaceManager.get_difficulty())

func _fetch_one_candidate() -> void:
	## Fetches a single replacement candidate, respecting category/difficulty settings.
	var cat := RaceManager.get_category_override()
	if cat != "":
		ExhibitFetcher.fetch_random_from_category(cat, { "race": true, "race_role": "candidate" })
	elif RaceManager.get_difficulty() == "random_category":
		ExhibitFetcher.fetch_random_category_article({ "race": true, "race_role": "candidate" })
	else:
		ExhibitFetcher.fetch_random_batch([{ "race": true, "race_role": "candidate" }])


func _fetch_race_candidates() -> void:
	## When a category override is set, candidates also come from that category.
	## Otherwise use the fast batch random endpoint.
	var cat := RaceManager.get_category_override()
	if cat != "":
		for i in RaceManager.CANDIDATE_COUNT:
			ExhibitFetcher.fetch_random_from_category(cat, { "race": true, "race_role": "candidate" })
	elif RaceManager.get_difficulty() == "random_category":
		for i in RaceManager.CANDIDATE_COUNT:
			ExhibitFetcher.fetch_random_category_article({ "race": true, "race_role": "candidate" })
	else:
		var candidate_contexts: Array = []
		for i in RaceManager.CANDIDATE_COUNT:
			candidate_contexts.append({ "race": true, "race_role": "candidate" })
		ExhibitFetcher.fetch_random_batch(candidate_contexts)


func _on_vote_cancelled() -> void:
	## Host cancelled the vote — clear pending fetch state and return all players to pause menu.
	_race_candidates.clear()
	_race_target_article = ""
	_race_fetches_pending = 0
	_pause_game()


func _show_vote_loading() -> void:
	var vote_hud := get_node_or_null("TabMenu/VoteHUD")
	if vote_hud and vote_hud.has_method("show_loading"):
		vote_hud.show_loading()


func reroll_vote() -> void:
	## Called by VoteHUD reroll button (host only). Re-fetches all candidates.
	if not NetworkManager.is_server():
		return
	RaceManager.set_vote_timer_paused(true)
	_race_candidates.clear()
	_race_target_article = ""
	_race_fetches_pending = RaceManager.CANDIDATE_COUNT + 1
	_fetch_race_candidates()
	_fetch_race_target()


func _launch_vote() -> void:
	_debug_log("Main: Launching vote with candidates %s, target '%s'" % [str(_race_candidates), _race_target_article])
	RaceManager.set_vote_timer_paused(false)
	RaceManager.begin_vote(_race_candidates.duplicate(), _race_target_article)
	_race_candidates.clear()
	_race_target_article = ""
	# Tell VoteHUD reroll button it can re-enable
	var vote_hud := get_node_or_null("TabMenu/VoteHUD")
	if vote_hud and vote_hud.has_method("on_reroll_ready"):
		vote_hud.on_reroll_ready()


func _on_race_started(target_article: String, start_article: String) -> void:
	_debug_log("Main: Race started, sending all players to '%s'" % start_article)

	# In dedicated host mode there is no local player — just sync to clients and return
	if _is_ui_dedicated_host:
		if start_article != "" and NetworkManager.is_server():
			_sync_race_start_article.rpc(start_article)
		GameplayEvents.emit_race_started(target_article)
		return

	if _player == null:
		return
	_menu_controller.close_menus()

	# Reset to lobby first
	_museum.reset_to_lobby()

	# Open the search door to the starting exhibit for all players
	if start_article != "":
		UIEvents.emit_set_custom_door(start_article)
		if NetworkManager.is_server():
			_sync_race_start_article.rpc(start_article)

	# Start game (close menus, capture mouse)
	_start_game()

	GameplayEvents.emit_race_started(target_article)


# =============================================================================
# MULTIPLAYER FUNCTIONS
# =============================================================================
func _start_dedicated_server() -> void:
	Log.info("Main", "Starting dedicated server on port %d..." % _multiplayer_controller.get_server_port())

	# Signals are already connected in _ready() — no reconnection needed

	var error: Error = NetworkManager.host_game(_multiplayer_controller.get_server_port(), true)
	if error != OK:
		Log.error("Main", "Failed to start server: %s" % str(error))
		get_tree().quit(1)
		return

	_multiplayer_controller.set_multiplayer_game(true)
	game_started = true

	# Initialize museum without a local player
	_museum.init(null)

	Log.info("Main", "Server started successfully. Waiting for players...")


func _start_multiplayer_game() -> void:
	_start_game()
	if NetworkManager.is_multiplayer_active():
		for peer_id: int in NetworkManager.get_player_list():
			if peer_id != NetworkManager.get_unique_id():
				_multiplayer_controller.spawn_network_player(peer_id)


func _on_network_peer_connected(peer_id: int) -> void:
	# Set timeout unconditionally — must happen regardless of game state.
	if NetworkManager.peer:
		var enet_peer := NetworkManager.peer.get_peer(peer_id)
		if enet_peer:
			enet_peer.set_timeout(32, 20000, 60000)

	if _multiplayer_controller.is_multiplayer_game() and game_started:
		_multiplayer_controller.spawn_network_player(peer_id)

		if NetworkManager.is_server():
			_notify_game_started.rpc_id(peer_id)

			# In dedicated host mode, first joiner gets race control
			if _is_ui_dedicated_host and _race_controller_peer_id == -1:
				_race_controller_peer_id = peer_id
				_grant_race_control.rpc_id(peer_id)


func _on_network_peer_disconnected(peer_id: int) -> void:
	if _painting_controller:
		_painting_controller.on_player_disconnected(peer_id, _player)
	_multiplayer_controller.remove_network_player(peer_id, _player, _mount_controller.get_mount_state())

	# If the race controller disconnected in dedicated host mode, assign the next peer
	if _is_ui_dedicated_host and peer_id == _race_controller_peer_id:
		_race_controller_peer_id = -1
		var players := NetworkManager.get_player_list()
		for p in players:
			if p != 1:  # skip server peer id
				_race_controller_peer_id = p
				_grant_race_control.rpc_id(p)
				break


func _on_network_server_disconnected() -> void:
	# Only fires on clients. In auto-host mode the host is the server so this
	# never triggers for them. For clients it means the host quit.
	_multiplayer_controller.end_multiplayer_session()
	_menu_controller.open_main_menu()


func _on_quit_requested() -> void:
	if _multiplayer_controller.is_multiplayer_game():
		NetworkManager.disconnect_from_game()
		_multiplayer_controller.end_multiplayer_session()
		_menu_controller.open_main_menu()
	else:
		get_tree().quit()


func _on_network_player_info_updated(peer_id: int) -> void:
	_multiplayer_controller.update_player_info(peer_id)


func get_local_player() -> Node:
	return _player


func get_all_players() -> Array:
	return _multiplayer_controller.get_all_players(_player)


func is_multiplayer_game() -> bool:
	return _multiplayer_controller.is_multiplayer_game()


func _get_player_by_peer_id(peer_id: int) -> Node:
	return _multiplayer_controller.get_player_by_peer_id(peer_id, _player)


# =============================================================================
# MOUNT SYSTEM
# =============================================================================
func _request_mount(target: Node) -> void:
	_mount_controller.request_mount(target, _player)


func _request_dismount() -> void:
	_mount_controller.request_dismount(_player)


# =============================================================================
# PAINTING SYSTEM
# =============================================================================
func _request_steal_painting(exhibit_title: String, image_title: String, image_url: String, image_size: Vector2) -> void:
	_painting_controller.request_steal(exhibit_title, image_title, image_url, image_size, _player)


func _request_place_painting(exhibit_title: String, image_title: String, image_url: String, wall_position: Vector3, wall_normal: Vector3, image_size: Vector2) -> void:
	_painting_controller.request_place(exhibit_title, image_title, image_url, wall_position, wall_normal, image_size, _player)


func _request_eat_painting(exhibit_title: String, image_title: String) -> void:
	_painting_controller.request_eat(exhibit_title, image_title, _player)


func _on_journal_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_player.start()


func _open_guestbook(exhibit_title: String) -> void:
	if _guestbook_overlay and not _guestbook_overlay.is_open():
		_guestbook_overlay.open(exhibit_title)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_player.pause()


func _on_local_reaction(reaction_index: int, target: Vector3) -> void:
	_pointing_controller.spawn_reaction(reaction_index, target)
	if _multiplayer_controller.is_multiplayer_game() and NetworkManager.is_multiplayer_active():
		_reaction_sync.rpc(NetworkManager.get_unique_id(), reaction_index, target)


func _broadcast_eat_anim_start() -> void:
	if _multiplayer_controller.is_multiplayer_game() and NetworkManager.is_multiplayer_active():
		var peer_id: int = NetworkManager.get_unique_id()
		_eat_anim_start_sync.rpc(peer_id)


func _broadcast_eat_anim_cancel() -> void:
	if _multiplayer_controller.is_multiplayer_game() and NetworkManager.is_multiplayer_active():
		var peer_id: int = NetworkManager.get_unique_id()
		_eat_anim_cancel_sync.rpc(peer_id)


# =============================================================================
# MULTIPLAYER RPCS
# =============================================================================
@rpc("authority", "call_remote", "reliable")
func _notify_game_started() -> void:
	_debug_log("Main: Received notification that game has already started")
	_multiplayer_controller.set_multiplayer_game(true)

	# Tell MultiplayerMenu to close and fire its start_game signal,
	# which is what normally transitions the client out of the lobby screen.
	MultiplayerEvents.emit_multiplayer_started()

	# Defer _start_multiplayer_game by one frame so that all player_info RPCs
	# from _on_peer_connected have time to arrive and populate NetworkManager
	# before we try to iterate get_player_list() and spawn network players.
	call_deferred("_start_multiplayer_game")

	# If a race is already active, apply the start article and fire race_started
	# (RaceManager._sync_race_state_to_peer handles target/start/time separately)
	if RaceManager.is_race_active():
		var start_article: String = RaceManager.get_start_article()
		if start_article != "":
			UIEvents.emit_set_custom_door(start_article)
		GameplayEvents.emit_race_started(RaceManager.get_target_article())


@rpc("authority", "call_remote", "reliable")
func _sync_exhibit_to_peer(exhibit_title: String) -> void:
	_debug_log("Main: Syncing exhibit to late joiner: " + exhibit_title)
	_museum.sync_to_exhibit(exhibit_title)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync_player_position(peer_id: int, pos: Vector3, rot_y: float, pivot_rot_x: float, pivot_pos_y: float = 1.35, is_mounted: bool = false, mounted_peer_id: int = -1, current_room: String = "Lobby", pointing: bool = false, pt_target: Vector3 = Vector3.ZERO) -> void:
	_multiplayer_controller.apply_network_position(peer_id, pos, rot_y, pivot_rot_x, pivot_pos_y, is_mounted, mounted_peer_id, _player, current_room, pointing, pt_target)


@rpc("any_peer", "call_remote", "reliable")
func _request_mount_rpc(rider_peer_id: int, mount_peer_id: int) -> void:
	if NetworkManager.is_server():
		_mount_controller.handle_mount_request(rider_peer_id, mount_peer_id, _player)


@rpc("any_peer", "call_remote", "reliable")
func _request_dismount_rpc(rider_peer_id: int) -> void:
	if NetworkManager.is_server():
		_mount_controller.handle_dismount_request(rider_peer_id, _player)


@rpc("authority", "call_local", "reliable")
func _execute_mount_sync(rider_peer_id: int, mount_peer_id: int) -> void:
	_mount_controller.execute_mount_sync(rider_peer_id, mount_peer_id, _player)


@rpc("authority", "call_local", "reliable")
func _execute_dismount_sync(rider_peer_id: int) -> void:
	_mount_controller.execute_dismount_sync(rider_peer_id, _player)


# Painting RPCs
@rpc("any_peer", "call_remote", "reliable")
func _request_steal_painting_rpc(peer_id: int, exhibit_title: String, image_title: String, image_url: String, image_size: Vector2) -> void:
	if NetworkManager.is_server():
		_painting_controller.handle_steal_request(peer_id, exhibit_title, image_title, image_url, image_size, _player)


@rpc("any_peer", "call_remote", "reliable")
func _request_place_painting_rpc(peer_id: int, exhibit_title: String, image_title: String, image_url: String, wall_position: Vector3, wall_normal: Vector3, image_size: Vector2) -> void:
	if NetworkManager.is_server():
		_painting_controller.handle_place_request(peer_id, exhibit_title, image_title, image_url, wall_position, wall_normal, image_size, _player)


@rpc("any_peer", "call_remote", "reliable")
func _request_eat_painting_rpc(peer_id: int, exhibit_title: String, image_title: String) -> void:
	if NetworkManager.is_server():
		_painting_controller.handle_eat_request(peer_id, exhibit_title, image_title, _player)


@rpc("authority", "call_local", "reliable")
func _execute_steal_sync(peer_id: int, exhibit_title: String, image_title: String, image_url: String, image_size: Vector2) -> void:
	_painting_controller.execute_steal_sync(peer_id, exhibit_title, image_title, image_url, image_size, _player)


@rpc("authority", "call_local", "reliable")
func _execute_place_sync(peer_id: int, exhibit_title: String, image_title: String, image_url: String, wall_position: Vector3, wall_normal: Vector3, image_size: Vector2) -> void:
	_painting_controller.execute_place_sync(peer_id, exhibit_title, image_title, image_url, wall_position, wall_normal, image_size, _player)


@rpc("authority", "call_local", "reliable")
func _execute_eat_sync(peer_id: int) -> void:
	_painting_controller.execute_eat_sync(peer_id, _player)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _eat_anim_start_sync(peer_id: int) -> void:
	_painting_controller.apply_eat_anim_start(peer_id, _player)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _eat_anim_cancel_sync(peer_id: int) -> void:
	_painting_controller.apply_eat_anim_cancel(peer_id, _player)


@rpc("any_peer", "call_remote", "reliable")
func _reaction_sync(peer_id: int, reaction_index: int, target: Vector3) -> void:
	if peer_id != NetworkManager.get_unique_id():
		_pointing_controller.spawn_reaction(reaction_index, target)

## Syncs the race starting exhibit to all non-server peers so they also
## open the search door and load the starting article.
@rpc("authority", "call_remote", "reliable")
func _sync_race_start_article(start_article: String) -> void:
	_museum.reset_to_lobby()
	UIEvents.emit_set_custom_door(start_article)
	_start_game()


@rpc("authority", "call_remote", "reliable")
func _grant_race_control() -> void:
	## Called on the client that should have race control in dedicated host mode.
	## Overrides the PauseMenu visibility check to show Start Race.
	if _pause_menu and _pause_menu.has_method("set_race_control_override"):
		_pause_menu.set_race_control_override(true)
