extends Node
## Main game controller handling initialization and delegating to subsystems.

# UI Sound Effects
const _UI_CRYSTAL_SOUND: AudioStream = preload("res://assets/sound/UI/UI Crystal 1.ogg")
const _UI_SELECT_SOUND: AudioStream = preload("res://assets/sound/UI/UI Select 10.ogg")
const _UI_GO_SOUND: AudioStream = preload("res://assets/sound/UI/UI Select 2.ogg")
# Note: Using same sound for skin equip and victory events
const _SKIN_EQUIP_SOUND: AudioStream = _UI_CRYSTAL_SOUND
const _VICTORY_SOUND: AudioStream = _UI_CRYSTAL_SOUND
const _COUNTDOWN_SOUND: AudioStream = _UI_SELECT_SOUND
const _GO_SOUND: AudioStream = _UI_GO_SOUND

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

## Subsystems
var _menu_controller: MainMenuController = null
var _multiplayer_controller: MultiplayerController = null
var _mount_controller: MountController = null
var _painting_controller: PaintingController = null
var _pointing_controller: PointingController = null
var _chat_system: Node = null
var _chat_hud: Node = null
var _trivia_manager: TriviaManager = null
var _host_menu: CanvasLayer = null

## Stored lambdas for proper cleanup
var _reading_font_lambda: Callable = Callable()
var _quit_lambda: Callable = Callable()

@onready var _journal_overlay: JournalOverlay = %JournalOverlay
@onready var player_list_overlay: Control = %PlayerListOverlay
@onready var _server_console_overlay: Control = %ServerConsoleOverlay
@onready var _map_overlay: Control = %ExhibitMapOverlay
var _minimap_controller: Control = null
var _race_status_hud: Control = null

# Hint system cooldown
var _last_hint_time: float = 0.0
const HINT_COOLDOWN_SECONDS: float = 3.0
var _hint_backlinks: Array[String] = []
var _hints_revealed: int = 0

# â”€â”€ Tournament nodes (created in _ready) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
var _tournament_setup_menu:    Control = null
var _tournament_hud:           Control = null
var _tournament_bracket_hud:   Control = null
var _tournament_victory_screen: Control = null
@onready var _trivia_overlay: TriviaOverlay = %TriviaOverlay
@onready var _guestbook_overlay: GuestbookOverlay = %GuestbookOverlay
@onready var _prompt_hud: Control = %PromptHUD
@onready var _menu_layer: CanvasLayer = %MenuLayer
@onready var _fps_label: Label = %FpsLabel
@onready var _museum: Node3D = %Museum
@onready var _game_launch_sting: AudioStreamPlayer = %GameLaunchSting
@onready var _crt_post_processing: CanvasLayer = %CRTPostProcessing
@onready var _post_process_rect: ColorRect = _crt_post_processing.get_node("ColorRect")
@onready var _world_light: DirectionalLight3D = %WorldLight
@onready var _pause_menu: Control = %PauseMenu
@onready var _wip_label: Label = %WIPLabel

var game_started: bool = false
## True when running as a UI-based dedicated host (no local player spawned)
var _is_ui_dedicated_host: bool = false
## The peer_id who currently has race control (host by default, first joiner in dedicated host mode)
var _race_controller_peer_id: int = 1

## Daily Challenge
var _daily_challenge_manager: Node = null
var _daily_challenge_hud: Node = null
var _daily_challenge_card: Node = null
var _daily_challenge_leaderboard: Node = null
var _daily_challenge_board: Node = null
var _daily_challenge_card_layer: CanvasLayer = null
## Spectator
var _spectator_controller: Node = null
const POST_PROCESS_MATERIALS := {
	"crt": preload("res://assets/textures/post_process_crt.tres"),
	"soft": preload("res://assets/textures/post_process_soft.tres"),
	"vhs": preload("res://assets/textures/post_process_vhs.tres"),
	"ps1": preload("res://assets/textures/post_process_ps1.tres"),
}

func _debug_log(message: String) -> void:
	# Only log in debug builds
	if not OS.is_debug_build():
		return
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
	# Initialize core services FIRST (before any other initialization)
	# Note: Services and EventBus are autoloads, accessed globally
	Services.initialize()
	
	# Restore UI scale from settings before anything else renders
	var ui_saved = SettingsManager.get_settings("ui")
	if ui_saved and ui_saved.has("scale"):
		get_tree().root.content_scale_factor = float(ui_saved.scale)

	# Initialize RoomService with museum references (after @onready vars are set)
	call_deferred("_initialize_room_service")

	# WIP Label font management
	if _wip_label:
		_wip_label.add_theme_font_override("font", ThemeManager.get_reading_font())
		_reading_font_lambda = func(f): _wip_label.add_theme_font_override("font", f)
		ThemeManager.reading_font_changed.connect(_reading_font_lambda)

func _initialize_room_service() -> void:
	"""Initialize RoomService with museum references (called after @onready vars are set)."""
	if Services.room_service and _museum:
		var exhibit_loader = _museum.get_node_or_null("ExhibitLoader")
		if exhibit_loader:
			Services.room_service.initialize(_museum, exhibit_loader)
			print("Main: RoomService initialized with museum and exhibit loader")

	# Initialize exhibit service
	if Services.exhibit_service and _museum:
		var exhibit_loader = _museum.get_node_or_null("ExhibitLoader")
		if exhibit_loader:
			Services.exhibit_service.initialize(_museum, exhibit_loader)
			print("Main: ExhibitService initialized")

	# Also initialize network service
	if Services.network_service:
		Services.network_service.initialize()
		print("Main: NetworkService initialized")

	# Initialize subsystems first
	_menu_controller = MainMenuController.new()
	_menu_controller.init(self, _menu_layer)
	_menu_controller.game_start_requested.connect(_start_game)
	_menu_controller.multiplayer_start_requested.connect(_on_multiplayer_start_game)
	add_child(_menu_controller)
	
	# Connect dedicated host button from MainMenu
	var main_menu_node := _menu_layer.get_node_or_null("MainMenu")
	if main_menu_node:
		# Connect MainMenu buttons to controller
		if main_menu_node.has_signal("start"):
			main_menu_node.start.connect(func(): _menu_controller.on_main_menu_start_pressed())
		if main_menu_node.has_signal("start_multiplayer"):
			main_menu_node.start_multiplayer.connect(func(): _menu_controller.on_main_menu_multiplayer())
		if main_menu_node.has_signal("settings"):
			main_menu_node.settings.connect(func(): _menu_controller.on_main_menu_settings())
		
		# Connect dedicated host button
		if main_menu_node.has_signal("start_dedicated_host"):
			main_menu_node.start_dedicated_host.connect(_on_dedicated_host_pressed)
		
		# Animate card out in sync with every MainMenu button
		for sig: String in ["start", "settings", "start_multiplayer", "start_dedicated_host"]:
			if main_menu_node.has_signal(sig):
				main_menu_node.connect(sig, func():
					if _daily_challenge_card and _daily_challenge_card.has_method("animate_out"):
						_daily_challenge_card.animate_out())
	# Quit goes through UIEvents â€” animate card out alongside menu transition
	UIEvents.quit_requested.connect(func():
		if _daily_challenge_card and _daily_challenge_card.has_method("animate_out"):
			_daily_challenge_card.animate_out())
	
	# Connect Settings resume signal to show MainMenu.
	# Guard with is_connected â€” the scene inspector may already wire this.
	var settings_node := _menu_layer.get_node_or_null("Settings")
	if settings_node and settings_node.has_signal("resume") \
			and not settings_node.resume.is_connected(_on_settings_back):
		settings_node.resume.connect(_on_settings_back)

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

	# â”€â”€ Tournament mode â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	_spawn_tournament_nodes()

	_trivia_manager = TriviaManager.new()
	_trivia_manager.name = "TriviaManager"
	add_child(_trivia_manager)
	
	# Connect trivia overlay
	if _trivia_overlay:
		_trivia_overlay.init(_trivia_manager)
		_trivia_overlay.trivia_closed.connect(_on_trivia_closed)
	
	# Connect UI events for trivia
	UIEvents.open_trivia.connect(_on_open_trivia)

	# Daily Challenge
	_daily_challenge_manager = load("res://scenes/autoload/DailyChallengeManager.gd").new()
	_daily_challenge_manager.name = "DailyChallengeManager"
	add_child(_daily_challenge_manager)

	_daily_challenge_hud = load("res://scenes/ui/DailyChallengeHUD.gd").new()
	_daily_challenge_hud.name = "DailyChallengeHUD"
	_daily_challenge_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Own CanvasLayer so visibility is independent of _menu_layer
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "DailyChallengeHUDLayer"
	hud_layer.layer = 20  # above game HUDs, below debug overlay
	add_child(hud_layer)
	hud_layer.add_child(_daily_challenge_hud)
	# Leaderboard must be created first so we can pass it into the HUD
	_daily_challenge_leaderboard = load("res://scenes/ui/DailyChallengeLeaderboard.gd").new()
	_daily_challenge_leaderboard.name = "DailyChallengeLeaderboard"
	add_child(_daily_challenge_leaderboard)
	_daily_challenge_hud.init(_daily_challenge_manager, _daily_challenge_leaderboard)
	_daily_challenge_hud.challenge_started.connect(_on_daily_challenge_started)
	_daily_challenge_hud.challenge_closed.connect(_on_daily_challenge_closed)
	# Submit score when challenge completes
	if _daily_challenge_manager.has_signal("challenge_completed"):
		_daily_challenge_manager.challenge_completed.connect(_on_challenge_completed_for_leaderboard)

	# Lobby card — member-var CanvasLayer so it stays alive after _ready() returns
	# Spectator
	_spectator_controller = load("res://scenes/main/SpectatorController.gd").new()
	_spectator_controller.name = "SpectatorController"
	add_child(_spectator_controller)
	_spectator_controller.spectator_exited.connect(_on_spectator_exited)

	_parse_command_line()

	# Register trivia keybind (K) at runtime
	if not InputMap.has_action("toggle_trivia"):
		InputMap.add_action("toggle_trivia")
		var ev_t := InputEventKey.new()
		ev_t.physical_keycode = KEY_K
		InputMap.action_add_event("toggle_trivia", ev_t)

	# Register daily challenge keybind (G)
	if not InputMap.has_action("open_daily_challenge"):
		InputMap.add_action("open_daily_challenge")
		var ev_d := InputEventKey.new()
		ev_d.physical_keycode = KEY_G
		InputMap.action_add_event("open_daily_challenge", ev_d)

	# Register host menu keybind (F1 and H)
	if not InputMap.has_action("toggle_host_menu"):
		InputMap.add_action("toggle_host_menu")
		var ev_f1 := InputEventKey.new()
		ev_f1.physical_keycode = KEY_F1
		InputMap.action_add_event("toggle_host_menu", ev_f1)
		
		# Also bind H for convenience
		var ev_h := InputEventKey.new()
		ev_h.physical_keycode = KEY_H
		InputMap.action_add_event("toggle_host_menu", ev_h)

	# Initialize host menu (multiplayer only)
	_host_menu = load("res://scenes/menu/HostMenu.gd").new()
	_host_menu.name = "HostMenu"
	add_child(_host_menu)
	_host_menu.init(self)

	# Register spectator keybind (F) â€” multiplayer only
	if not InputMap.has_action("toggle_spectator"):
		InputMap.add_action("toggle_spectator")
		var ev_s := InputEventKey.new()
		ev_s.physical_keycode = KEY_F
		InputMap.action_add_event("toggle_spectator", ev_s)
	
	# Register UI scale keyboard shortcuts (Ctrl+= zoom in, Ctrl+- zoom out, Ctrl+0 reset)
	for action_name in ["ui_scale_in", "ui_scale_out", "ui_scale_reset"]:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
	var _ev_in := InputEventKey.new()
	_ev_in.physical_keycode = KEY_EQUAL; _ev_in.ctrl_pressed = true
	InputMap.action_add_event("ui_scale_in", _ev_in)
	var _ev_in2 := InputEventKey.new()
	_ev_in2.physical_keycode = KEY_KP_ADD; _ev_in2.ctrl_pressed = true
	InputMap.action_add_event("ui_scale_in", _ev_in2)
	var _ev_out := InputEventKey.new()
	_ev_out.physical_keycode = KEY_MINUS; _ev_out.ctrl_pressed = true
	InputMap.action_add_event("ui_scale_out", _ev_out)
	var _ev_out2 := InputEventKey.new()
	_ev_out2.physical_keycode = KEY_KP_SUBTRACT; _ev_out2.ctrl_pressed = true
	InputMap.action_add_event("ui_scale_out", _ev_out2)
	var _ev_reset := InputEventKey.new()
	_ev_reset.physical_keycode = KEY_0; _ev_reset.ctrl_pressed = true
	InputMap.action_add_event("ui_scale_reset", _ev_reset)

	# Register screenshot keybind (F12)
	if not InputMap.has_action("take_screenshot"):
		InputMap.add_action("take_screenshot")
		var ev_ss := InputEventKey.new()
		ev_ss.physical_keycode = KEY_F12
		InputMap.action_add_event("take_screenshot", ev_ss)
	
	if _multiplayer_controller.is_server_mode():
		_start_dedicated_server()
		return
	
	if OS.has_feature("movie"):
		_fps_label.visible = false
	
	_recreate_player()
	
	# Minimap — MinimapController cycles OFF → Compass → Graph
	_minimap_controller = load("res://scenes/ui/MinimapController.gd").new()
	_minimap_controller.name = "MinimapController"
	add_child(_minimap_controller)
	
	# Race Status HUD — bottom-left, R key toggles during a race
	# (Tab is already used for the player-list hold overlay)
	_race_status_hud = load("res://scenes/ui/RaceStatusHUD.gd").new()
	_race_status_hud.name = "RaceStatusHUD"
	add_child(_race_status_hud)
	
	GraphicsManager.change_post_processing.connect(_change_post_processing)
	GraphicsManager.init()
	
	# âœ… FIX: Connect pause menu signals. Guard each with is_connected so we
	# don't double-connect if the scene file already wired them in the inspector.
	if _pause_menu:
		if not _pause_menu.resume.is_connected(_start_game):
			_pause_menu.resume.connect(_start_game)
		if not _pause_menu.settings.is_connected(_on_pause_menu_settings):
			_pause_menu.settings.connect(_on_pause_menu_settings)
		if not _pause_menu.return_to_lobby.is_connected(_on_pause_menu_return_to_lobby):
			_pause_menu.return_to_lobby.connect(_on_pause_menu_return_to_lobby)
		if not _pause_menu.start_race.is_connected(_on_start_race_pressed):
			_pause_menu.start_race.connect(_on_start_race_pressed)

	MultiplayerEvents.skin_selected.connect(_on_skin_selected)
	MultiplayerEvents.skin_reset.connect(_on_skin_reset)
	UIEvents.open_terminal_menu.connect(_use_terminal)
	UIEvents.quit_requested.connect(_on_quit_requested)
	
	# Race signals
	add_to_group("main")
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_countdown.connect(_on_race_countdown)
	RaceManager.race_won.connect(_on_race_won)
	RaceManager.vote_cancelled.connect(_on_vote_cancelled)
	RaceManager.target_determined.connect(_on_target_determined)
	if RaceManager.has_signal("race_won"):
		RaceManager.race_won.connect(_on_race_won_for_daily_challenge)
	ExhibitFetcher.random_complete.connect(_on_random_article_complete)
	ExhibitFetcher.category_random_complete.connect(_on_random_article_complete)
	
	# Journal
	if _journal_overlay:
		_journal_overlay.closed.connect(_on_journal_closed)
	
	# Load saved skin
	_load_saved_skin()
	
	# Multiplayer signals
	NetworkManager.peer_connected.connect(_on_network_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_network_peer_disconnected)
	NetworkManager.server_disconnected.connect(_on_network_server_disconnected)
	NetworkManager.player_info_updated.connect(_on_network_player_info_updated)
	
	# Accessibility
	SettingsEvents.accessibility_changed.connect(_on_accessibility_changed)
	_load_accessibility_settings()
	
	call_deferred("_play_sting")
	
	_world_light.visible = Platform.is_compatibility_renderer()
	ThemeManager.dark_mode_changed.connect(func(_d): _update_world_light_intensity())
	_update_world_light_intensity()
	
	_pause_game()

func _play_sting() -> void:
	_game_launch_sting.play()

func _recreate_player() -> void:
	if _player:
		remove_child(_player)
		_player.queue_free()
	_player = Player.instantiate()
	add_child(_player)
	_player_pivot = _player.get_node_or_null("Pivot")
	if _player_pivot:
		var camera = _player_pivot.get_node_or_null("Camera3D")
		if camera:
			camera.make_current()
	_player.rotation.y = starting_rotation
	_player.max_speed = player_speed
	_player.smooth_movement = smooth_movement
	_player.dampening = smooth_movement_dampening
	_player.position = starting_point
	_player.set_player_color(NetworkManager.local_player_color)
	if _minimap_controller and _minimap_controller.has_method("init"):
		_minimap_controller.init(_player)
	if _prompt_hud and _prompt_hud.has_method("init"):
		_prompt_hud.init(_player)

	# Initialize voice chat for the local player
	if VoiceChatManager:
		VoiceChatManager.init_local_voice(_player)

	# Re-initialise spectator with the new player reference
	if _spectator_controller:
		_spectator_controller.init(self, _multiplayer_controller)

	# Update lobby card with new player reference
	if _daily_challenge_card and _daily_challenge_card.has_method("set_player"):
		_daily_challenge_card.set_player(_player)

	# Fix Minimap Viewport World
	var map_viewport: SubViewport = _player.get_node_or_null("MapCameraContainer/MapViewport")
	if map_viewport:
		map_viewport.world_3d = get_viewport().find_world_3d()

func _change_post_processing(post_processing: String) -> void:
	# Hide overlay completely when disabled.
	if post_processing == "none":
		_crt_post_processing.visible = false
		return
	
	_crt_post_processing.visible = true
	# Swap material based on the selected effect, falling back to CRT if unknown.
	if POST_PROCESS_MATERIALS.has(post_processing):
		_post_process_rect.material = POST_PROCESS_MATERIALS[post_processing]
	else:
		_post_process_rect.material = POST_PROCESS_MATERIALS["crt"]

func _update_world_light_intensity() -> void:
	if _world_light:
		# Much brighter in light mode to differentiate from dark mode
		_world_light.light_energy = 0.08 if ThemeManager.is_dark_mode else 1.2

func _start_game() -> void:
	# Ensure player exists (might be null after returning from main menu)
	if not _player or not is_instance_valid(_player):
		_recreate_player()
	
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Player.start() already enables the player (_enabled = true)
	_player.start()
	_menu_controller.close_menus()
	# Hide daily challenge HUD and card when entering museum normally (not via challenge)
	if _daily_challenge_hud and _daily_challenge_hud.has_method("hide_all"):
		_daily_challenge_hud.hide_all()
	if _daily_challenge_card and _daily_challenge_card.has_method("_hide_card"):
		_daily_challenge_card._hide_card()
	if _daily_challenge_card_layer:
		_daily_challenge_card_layer.visible = true  # <--- Show now that we are in-game
	_map_overlay.restore_after_pause()
	if not game_started:
		game_started = true
		_museum.init(_player)
		# Spawn the physical noticeboard in the lobby
		_spawn_daily_challenge_board()
	# Re-init lobby card for solo play only â€” never show in multiplayer
	if _daily_challenge_card and _daily_challenge_card.has_method("init"):
		if not _multiplayer_controller.is_multiplayer_game():
			_daily_challenge_card.init(_daily_challenge_manager, _daily_challenge_hud, _player, _daily_challenge_leaderboard, _start_game, _menu_layer)
		else:
			_daily_challenge_card.set_multiplayer_mode(true)

func _pause_game() -> void:
	if _player:
		_player.pause()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if game_started:
		# Check if pause menu is already visible
		var pause_menu_visible := _pause_menu and _pause_menu.visible
		if pause_menu_visible:
			return
		if _menu_controller:
			_menu_controller.open_pause_menu()
	else:
		if _menu_controller:
			_menu_controller.open_main_menu()

func hide_pause_menu() -> void:
	if _pause_menu:
		_pause_menu.visible = false
	if _menu_layer:
		_menu_layer.visible = false
		# Also hide the backdrop ColorRect that might block clicks
		var backdrop = _menu_layer.get_node_or_null("ColorRect")
		if backdrop:
			backdrop.visible = false

func _cycle_minimap() -> void:
	if _minimap_controller:
		_minimap_controller.cycle_mode()

func _use_terminal() -> void:
	# Block terminal access during daily challenge to prevent cheating
	if _daily_challenge_manager and _daily_challenge_manager.is_active():
		if _chat_system:
			_chat_system._show_system_message("⚠ Terminal disabled during Daily Challenge")
		return
	
	# Hide overlay UI during terminal
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
	if _daily_challenge_card and _daily_challenge_card.has_method("set_multiplayer_mode"):
		_daily_challenge_card.set_multiplayer_mode(true)
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
	
	# Signals are already connected in _ready() â€” no reconnection needed
	
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
		var quit_node = main_menu_node.get_node_or_null("%Quit")
		if quit_node:
			var container := quit_node.get_parent()
			
			# Show server address for host to share
			var server_addr := NetworkManager.get_server_address()
			var addr_lbl := Label.new()
			addr_lbl.name = "ServerAddressLabel"
			addr_lbl.text = "Server Address: %s" % server_addr
			addr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			addr_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			addr_lbl.add_theme_font_size_override("font_size", 14)
			container.add_child(addr_lbl)
			
			var lbl := Label.new()
			lbl.name = "HostStatusLabel"
			lbl.text = "Hosting on port %d — waiting for players..." % _multiplayer_controller.get_server_port()
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_color_override("font_color", Color(0.4, 0.7, 0.4))
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
	# Re-initialize daily challenge card for main menu display
	if _daily_challenge_card and _daily_challenge_card.has_method("set_main_menu_mode"):
		_daily_challenge_card.set_main_menu_mode()
	# Restore main menu UI
	var main_menu_node := _menu_layer.get_node_or_null("MainMenu")
	if main_menu_node:
		var quit_node = main_menu_node.get_node_or_null("%Quit")
		if quit_node:
			var container := quit_node.get_parent()
			var lbl := container.get_node_or_null("HostStatusLabel")
			if lbl:
				lbl.queue_free()
			var addr_lbl := container.get_node_or_null("ServerAddressLabel")
			if addr_lbl:
				addr_lbl.queue_free()
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
	if _player:
		_player.rotation.y = starting_rotation
		_player.position = starting_point
	if _museum:
		_museum.reset_to_lobby()
		_start_game()

func _on_settings_back() -> void:
	_menu_controller.on_settings_back()

# =============================================================================
# INPUT HANDLING
# =============================================================================

func _input(event: InputEvent) -> void:
	# TEST: F10 = Play PCM test audio (for Piper TTS development)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		_test_pcm_playback()
		return
	
	if Input.is_action_pressed("toggle_fullscreen"):
		UIEvents.fullscreen_toggled.emit(not GraphicsManager.fullscreen)

	# Don't process game inputs while the chat input or debug console is open
	var chat_open: bool = _chat_hud != null and _chat_hud.is_input_open()
	var console_open: bool = DebugConsole.is_active()

	if not chat_open and not console_open:
		if Input.is_action_just_pressed("ui_accept"):
			UIEvents.emit_ui_accept_pressed()

		# ESC opens pause menu if closed, closes menus if open
		if Input.is_action_just_pressed("ui_cancel"):
			# Check if pause menu is specifically the one visible
			var pause_menu_visible := _pause_menu and _pause_menu.visible
			if pause_menu_visible:
				# Pause menu is open, so ESC should close it
				UIEvents.emit_ui_cancel_pressed()
			elif _menu_layer.visible:
				# Another menu is open (settings, terminal, etc.) â€” let it handle ESC
				UIEvents.emit_ui_cancel_pressed()
			elif game_started:
				_pause_game()  # Open pause menu
			else:
				_menu_controller.open_main_menu()  # Open main menu if not in game
				# Show daily challenge card on main menu
				if _daily_challenge_card and _daily_challenge_card.has_method("set_main_menu_mode"):
					_daily_challenge_card.set_main_menu_mode()
			get_viewport().set_input_as_handled()

		if Input.is_action_just_pressed("show_fps"):
			_fps_label.visible = not _fps_label.visible

		if Input.is_action_just_pressed("toggle_server_console"):
			if _multiplayer_controller and _multiplayer_controller.is_multiplayer_game():
				_server_console_overlay.toggle()
		
		# Guard journal/map/etc behind menu check
		if not _menu_layer.visible:
			if event.is_action_pressed("toggle_journal"):
				if _journal_overlay:
					if _journal_overlay.is_open():
						_journal_overlay.close()
					else:
						_journal_overlay.open()
						Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
						_player.pause()

			if event.is_action_pressed("toggle_map"):
				_cycle_minimap()

			if event.is_action_pressed("toggle_trivia"):
				if _trivia_overlay:
					if _trivia_overlay.is_open():
						_trivia_overlay.close()
					elif _player and "current_room" in _player:
						UIEvents.emit_open_trivia(_player.current_room)

			if event.is_action_pressed("open_daily_challenge"):
				if _daily_challenge_hud:
					if _daily_challenge_hud.is_open():
						_daily_challenge_hud.close()
					else:
						_daily_challenge_hud.open()
						Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
						_player.pause()

			if event.is_action_pressed("toggle_spectator"):
				if _spectator_controller and _multiplayer_controller and _multiplayer_controller.is_multiplayer_game():
					if _spectator_controller.is_spectating():
						_spectator_controller.exit_spectator_mode()
					elif _multiplayer_controller.get_network_players().size() > 0:
						_spectator_controller.enter_spectator_mode(_player)

			if event.is_action_pressed("toggle_host_menu"):
				# Don't open host menu if journal or other overlays are open
				var overlay_open: bool = (_journal_overlay and _journal_overlay.is_open()) or \
					(_guestbook_overlay and _guestbook_overlay.is_open()) or \
					(_trivia_overlay and _trivia_overlay.is_open())
				if _host_menu and NetworkManager.is_server() and not overlay_open:
					_host_menu.toggle()

			# Host hint keybind (I key) - only works during active race
			if event.is_action_pressed("host_hint"):
				if NetworkManager.is_server() and RaceManager.is_race_active():
					var now := Time.get_unix_time_from_system()
					if now - _last_hint_time >= HINT_COOLDOWN_SECONDS:
						_reveal_host_hint()
						_last_hint_time = now
					get_viewport().set_input_as_handled()

		# UI scale keyboard shortcuts â€” work in any state
		if InputMap.has_action("ui_scale_in") and event.is_action_pressed("ui_scale_in"):
			_adjust_ui_scale(0.1)
			get_viewport().set_input_as_handled()
		if InputMap.has_action("ui_scale_out") and event.is_action_pressed("ui_scale_out"):
			_adjust_ui_scale(-0.1)
			get_viewport().set_input_as_handled()
		if InputMap.has_action("ui_scale_reset") and event.is_action_pressed("ui_scale_reset"):
			_adjust_ui_scale(0.0)
			get_viewport().set_input_as_handled()

		# Screenshot â€” F12, works in any game state
		if InputMap.has_action("take_screenshot") and event.is_action_pressed("take_screenshot"):
			_take_screenshot()
			get_viewport().set_input_as_handled()
		

		if event.is_action_pressed("click") and not _menu_layer.visible:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
				# Check if any UI overlay is open (including VoteHUD)
				var vote_hud := get_node_or_null("TabMenu/VoteHUD")
				var vote_open: bool = vote_hud != null and vote_hud.visible
				var overlay_open: bool = (_journal_overlay and _journal_overlay.is_open()) or (_guestbook_overlay and _guestbook_overlay.is_open()) or (_trivia_overlay and _trivia_overlay.is_open()) or vote_open or console_open
				if not overlay_open:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
		# Tab key for player list overlay
		if _multiplayer_controller and _multiplayer_controller.is_multiplayer_game() and not _menu_layer.visible and not console_open:
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

	# Guard: _multiplayer_controller might not be initialized yet
	if not _multiplayer_controller:
		return

	# Guard: _player might not be initialized yet
	if not _player or not is_instance_valid(_player):
		return

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
# ACCESSIBILITY FUNCTIONS
# =============================================================================

func _load_accessibility_settings() -> void:
	var saved: Dictionary = SettingsManager.get_settings("accessibility") if SettingsManager.get_settings("accessibility") else {}
	
	# Broadcast all saved accessibility settings to consumers (RaceHUD, items, etc)
	for key: String in saved:
		SettingsEvents.emit_accessibility_changed(key, saved[key])
		
	# Apply global settings that belong to the main app scope
	if saved.has("colorblind_mode"):
		_apply_colorblind_filter(saved.get("colorblind_mode"))

func _on_accessibility_changed(key: String, value: Variant) -> void:
	if key == "colorblind_mode":
		_apply_colorblind_filter(value as int)

func _apply_colorblind_filter(mode: int) -> void:
	var root := get_tree().root
	var overlay := root.find_child("ColorblindOverlay", true, false)

	if mode == 0:
		if overlay:
			overlay.visible = false
		return

	if not overlay:
		var shader_path := "res://assets/shaders/colorblind_correction.gdshader"
		if not ResourceLoader.exists(shader_path):
			push_warning("Main: Colorblind shader not found at " + shader_path)
			return
		var canvas := CanvasLayer.new()
		canvas.name = "ColorblindLayer"
		canvas.layer = 128  # render on top of everything
		root.add_child(canvas)
		
		var rect := ColorRect.new()
		rect.name = "ColorblindOverlay"
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = load(shader_path)
		rect.material = mat
		canvas.add_child(rect)
		overlay = rect

	overlay.visible = true
	var mat := overlay.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("mode", mode)
		mat.set_shader_parameter("strength", 1.0)

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
	if OS.is_debug_build():
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
	
	# Close pause menu BEFORE starting race vote
	hide_pause_menu()
	_menu_controller.close_menus()
	
	if not NetworkManager.is_multiplayer_active() or NetworkManager.is_server():
		_debug_log("Main: Fetching random articles for race vote...")
		_race_candidates.clear()
		_race_start_article = ""
		_race_fetches_pending = RaceManager.CANDIDATE_COUNT + 1  # +1 start
		_show_vote_loading()
		_fetch_race_candidates()
		_fetch_race_start_article()
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
	
	# Close pause menu BEFORE starting race vote
	hide_pause_menu()
	_menu_controller.close_menus()
	
	_debug_log("Main: Race start requested by peer, fetching random articles for vote...")
	_race_candidates.clear()
	_race_start_article = ""
	_race_fetches_pending = RaceManager.CANDIDATE_COUNT + 1
	_show_vote_loading()
	_fetch_race_candidates()
	_fetch_race_start_article()

## Collects random articles for the vote pool. Winner = race target.
var _race_candidates: Array = []
var _race_start_article: String = ""  ## random article â€” where the lobby door opens
var _race_fetches_pending: int = 0
var _race_retry_count: int = 0
const MAX_RACE_RETRIES: int = 10

func _on_random_article_complete(title: Variant, context: Variant) -> void:
	if not context or not (context is Dictionary) or not context.has("race") or not context.race:
		return
	if title == null or title == " ":
		_race_retry_count += 1
		if _race_retry_count > MAX_RACE_RETRIES:
			Log.error("Main", "Too many fetch failures â€” giving up and launching with what we have")
			_race_retry_count = 0
			if _race_candidates.size() > 0:
				_launch_vote()
			return
		Log.error("Main", "Failed to fetch random article for race â€” retrying (%d/%d)" % [_race_retry_count, MAX_RACE_RETRIES])
		var role: String = context.get("race_role", "candidate")
		if role == "start":
			_fetch_race_start_article()
		else:
			_fetch_one_candidate()
		return
	
	_race_retry_count = 0
	var role: String = context.get("race_role", "candidate")
	if role == "candidate":
		# Deduplicate
		if title in _race_candidates:
			_debug_log("Main: Duplicate candidate '%s' â€” retrying" % title)
			_fetch_one_candidate()
			return
		_race_candidates.append(title)
		_race_fetches_pending -= 1
		_debug_log("Main: Got candidate '%s' (%d remaining)" % [title, _race_fetches_pending])
		if _race_fetches_pending <= 0 and _race_start_article != " ":
			_launch_vote()
	elif role == "start":
		_race_start_article = title
		_race_fetches_pending -= 1
		_debug_log("Main: Got start article '%s'" % title)
		if _race_fetches_pending <= 0 and _race_candidates.size() >= RaceManager.CANDIDATE_COUNT:
			_launch_vote()

func _fetch_one_candidate() -> void:
	## Fetches a single replacement candidate, respecting category/difficulty settings.
	var cat := RaceManager.get_category_override()
	# Check for both empty string AND space to avoid malformed Toolforge URLs
	if cat != null and cat.strip_edges() != "" and cat != " ":
		ExhibitFetcher.fetch_random_from_category(cat, {"race": true, "race_role": "candidate"})
	elif RaceManager.get_difficulty() == "random_category":
		ExhibitFetcher.fetch_random_category_article({"race": true, "race_role": "candidate"})
	else:
		ExhibitFetcher.fetch_random_target({"race": true, "race_role": "candidate"}, RaceManager.get_difficulty())

func _fetch_race_start_article() -> void:
	## Fetches a completely random article as the starting point â€” ignores difficulty.
	ExhibitFetcher.fetch_random({"race": true, "race_role": "start"})

func _fetch_race_candidates() -> void:
	## All candidates respect the current difficulty/category setting.
	var cat := RaceManager.get_category_override()
	# Check for both empty string AND space to avoid malformed Toolforge URLs
	if cat != null and cat.strip_edges() != "" and cat != " ":
		for i in RaceManager.CANDIDATE_COUNT:
			ExhibitFetcher.fetch_random_from_category(cat, {"race": true, "race_role": "candidate"})
	elif RaceManager.get_difficulty() == "random_category":
		for i in RaceManager.CANDIDATE_COUNT:
			ExhibitFetcher.fetch_random_category_article({"race": true, "race_role": "candidate"})
	else:
		for i in RaceManager.CANDIDATE_COUNT:
			ExhibitFetcher.fetch_random_target({"race": true, "race_role": "candidate"}, RaceManager.get_difficulty())

func _on_vote_cancelled() -> void:
	## Host cancelled the vote â€” clear pending fetch state and return all players to pause menu.
	_race_candidates.clear()
	_race_start_article = ""
	_race_fetches_pending = 0
	_pause_game()

func _spawn_tournament_nodes() -> void:
	## Creates and wires all tournament UI nodes. Called once from _ready.
	## Nodes live on a dedicated CanvasLayer (layer 95) â€” above the game HUDs
	## but below LoadingScreen (100) and RaceCountdown (110).
	var t_layer := CanvasLayer.new()
	t_layer.name   = "TournamentLayer"
	t_layer.layer  = 95
	add_child(t_layer)

	# Tournament HUD â€" live standings panel, always visible during a tournament
	var t_hud_script := load("res://scenes/tournament/TournamentHUD.gd")
	if t_hud_script:
		_tournament_hud = Control.new()
		_tournament_hud.set_script(t_hud_script)
		_tournament_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tournament_hud.name = "TournamentHUD"
		t_layer.add_child(_tournament_hud)

	# Tournament Bracket HUD â€" visual bracket showing per-round results (Tab to toggle)
	var t_bracket_script := load("res://scenes/tournament/TournamentBracketHUD.gd")
	if t_bracket_script:
		_tournament_bracket_hud = Control.new()
		_tournament_bracket_hud.set_script(t_bracket_script)
		_tournament_bracket_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tournament_bracket_hud.name = "TournamentBracketHUD"
		t_layer.add_child(_tournament_bracket_hud)
		# Wire bracket reference into standings HUD for Tab toggle
		if _tournament_hud and _tournament_hud.has_method("set_bracket_hud"):
			_tournament_hud.set_bracket_hud(_tournament_bracket_hud)

	# Tournament Victory Screen â€” champion announcement
	var t_vic_script := load("res://scenes/tournament/TournamentVictoryScreen.gd")
	if t_vic_script:
		_tournament_victory_screen = Control.new()
		_tournament_victory_screen.set_script(t_vic_script)
		_tournament_victory_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tournament_victory_screen.name = "TournamentVictoryScreen"
		t_layer.add_child(_tournament_victory_screen)

	# Tournament Setup Menu â€” host-only config panel, shown from MultiplayerMenu
	var t_setup_script := load("res://scenes/tournament/TournamentSetupMenu.gd")
	if t_setup_script:
		_tournament_setup_menu = Control.new()
		_tournament_setup_menu.set_script(t_setup_script)
		_tournament_setup_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tournament_setup_menu.name = "TournamentSetupMenu"
		_tournament_setup_menu.visible = false
		t_layer.add_child(_tournament_setup_menu)
		# Wire setup menu signals
		if _tournament_setup_menu.has_signal("tournament_started"):
			_tournament_setup_menu.tournament_started.connect(func():
				# Kick off the first round immediately after setup closes
				pass  # TournamentManager.host_start_tournament already calls _start_next_round
			)

	# Wire TournamentManager â†’ MultiplayerMenu so the lobby can show setup
	var mp_menu := _menu_layer.get_node_or_null("MultiplayerMenu")
	if mp_menu and mp_menu.has_signal("open_tournament_setup"):
		mp_menu.open_tournament_setup.connect(_on_open_tournament_setup)

	# Cancel tournament if the host leaves the game
	TournamentManager.tournament_cancelled.connect(func():
		if _tournament_hud:
			_tournament_hud.visible = false
		if _tournament_bracket_hud:
			_tournament_bracket_hud.visible = false
	)


func _on_open_tournament_setup() -> void:
	## Called when the host presses "Tournament Mode" in the MultiplayerMenu lobby.
	if not NetworkManager.is_server():
		return
	if _tournament_setup_menu:
		_tournament_setup_menu.open()


func _show_vote_loading() -> void:
	var vote_hud := get_node_or_null("TabMenu/VoteHUD")
	if vote_hud and vote_hud.has_method("show_loading"):
		vote_hud.show_loading()

func reroll_vote() -> void:
	## Called by VoteHUD reroll button (host only). Re-fetches all candidates + start article.
	if not NetworkManager.is_server():
		return
	RaceManager.set_vote_timer_paused(true)
	_race_candidates.clear()
	_race_start_article = ""
	_race_fetches_pending = RaceManager.CANDIDATE_COUNT + 1
	_fetch_race_candidates()
	_fetch_race_start_article()

func _launch_vote() -> void:
	_debug_log("Main: Launching vote with candidates %s, start '%s'" % [str(_race_candidates), _race_start_article])
	RaceManager.set_vote_timer_paused(false)
	RaceManager.begin_vote(_race_candidates.duplicate(), _race_start_article)
	_race_candidates.clear()
	_race_start_article = ""
	# Tell VoteHUD reroll button it can re-enable
	var vote_hud := get_node_or_null("TabMenu/VoteHUD")
	if vote_hud and vote_hud.has_method("on_reroll_ready"):
		vote_hud.on_reroll_ready()

func _on_target_determined(target: String) -> void:
	"""Called when vote ends and target is determined - prefetch backlinks early."""
	Log.info("Main", "Target determined: '%s', prefetching backlinks..." % target)
	_hint_backlinks.clear()
	_hints_revealed = 0
	_fetch_and_cache_backlinks(target)

func _on_race_started(target_article: String, start_article: String) -> void:
	Log.debug("Main", "_on_race_started CALLED! target=%s start=%s" % [target_article, start_article])
	_debug_log("Main: Race started, sending all players to '%s'" % start_article)
	_debug_log("Main: Target article is '%s'" % target_article)

	# In dedicated host mode there is no local player â€” just sync to clients and return
	if _is_ui_dedicated_host:
		if start_article != "" and NetworkManager.is_server():
			Log.debug("Main", "Dedicated host - calling _sync_race_start_article.rpc and local")
			_sync_race_start_article.rpc(start_article)
			_sync_race_start_article(start_article)  # Also run locally
		GameplayEvents.emit_race_started(target_article)
		return

	if _player == null:
		Log.error("Main", "_player is null, returning early")
		return

	# Ensure menus are closed and game is unpaused BEFORE any operations
	hide_pause_menu()
	_menu_controller.close_menus()
	if _player:
		_player.set_process(true)
		_player.set_physics_process(true)
		_player.set_process_input(true)

	# Reset to lobby first
	if _museum:
		_museum.reset_to_lobby()

	# Open the search door to the starting exhibit for all players
	if start_article != "":
		Log.debug("Main", "Calling _sync_race_start_article.rpc and local for start_article=%s" % start_article)
		UIEvents.emit_set_custom_door(start_article)
		if NetworkManager.is_server():
			_sync_race_start_article.rpc(start_article)
			_sync_race_start_article(start_article)  # Also run locally on server

	# Start game (close menus, capture mouse) - DO NOT WAIT for Wikipedia fetch
	_start_game()

	# Server fetches Wikipedia data for start article AFTER game has started (non-blocking)
	if NetworkManager.is_server():
		_debug_log("Main: Fetching Wikipedia data for start article '%s' (non-blocking)..." % start_article)
		_fetch_and_broadcast_start_article_non_blocking(start_article)

	GameplayEvents.emit_race_started(target_article)

func _fetch_and_broadcast_start_article(article: String) -> void:
	## Fetch Wikipedia data on server and broadcast to all clients (blocking version)
	Log.info("Main", "Starting Wikipedia fetch for '%s'" % article)
	ExhibitFetcher.fetch([article], {
		"title": article,
		"race_start": true  # Mark this as race start data
	})

	# Wait for fetch to complete (poll until data arrives) - max 2 seconds
	var max_wait := 2.0
	var wait_step := 0.1
	var waited := 0.0
	while not ExhibitFetcher.has_result(article) and waited < max_wait:
		await get_tree().create_timer(wait_step).timeout
		waited += wait_step

	# Get the fetched data
	var result = ExhibitFetcher.get_result(article)
	if result:
		Log.debug("Main", "Broadcasting Wikipedia data for '%s' to all clients" % article)
		_sync_wikipedia_data.rpc(article, result)
	else:
		Log.error("Main", "Wikipedia fetch failed for '%s'" % article)

func _fetch_and_broadcast_start_article_non_blocking(article: String) -> void:
	## Fetch Wikipedia data on server and broadcast to all clients (non-blocking)
	## This version returns immediately and broadcasts when data arrives
	Log.info("Main", "Starting Wikipedia fetch for '%s' (non-blocking)" % article)
	
	# Use a flag to ensure we only process once
	var processed: bool = false
	
	# Set up a one-shot connection to fetch the data when it arrives
	var on_wikitext_complete: Callable
	on_wikitext_complete = func(titles: Array, context: Variant) -> void:
		if processed:
			return
		processed = true
		
		if context and context.has("race_start") and context.has("title") and context.title == article:
			var result = ExhibitFetcher.get_result(article)
			if result:
				Log.debug("Main", "Broadcasting Wikipedia data for '%s' to all clients" % article)
				_sync_wikipedia_data.rpc(article, result)
			else:
				Log.error("Main", "Wikipedia fetch failed for '%s'" % article)
	
	ExhibitFetcher.wikitext_complete.connect(on_wikitext_complete, CONNECT_ONE_SHOT)
	
	# Start the fetch (returns immediately)
	ExhibitFetcher.fetch([article], {
		"title": article,
		"race_start": true
	})

func _on_race_countdown(number: int) -> void:
	## Play countdown sound effect
	Log.debug("Main", "Received countdown: %d" % number)
	if number > 0 and number <= 3:
		_play_countdown_sound()
	elif number == 0:
		# "GO!" - play sound with delay to match visual appearance
		# The GO text scales in over 0.22s, play sound when it's mostly visible
		await get_tree().create_timer(0.15).timeout
		_play_go_sound()

func _play_countdown_sound() -> void:
	## Play a short beep for countdown (3-2-1)
	_play_one_shot_audio(_COUNTDOWN_SOUND, Constants.COUNTDOWN_SOUND_VOLUME)

func _play_go_sound() -> void:
	## Play the "GO!" sound (more emphatic)
	_play_one_shot_audio(_GO_SOUND, Constants.GO_SOUND_VOLUME)

func _play_victory_sound() -> void:
	## Play victory fanfare
	_play_one_shot_audio(_VICTORY_SOUND, Constants.VICTORY_SOUND_VOLUME)

func _on_race_won(winner_name: String, final_time: float) -> void:
	## Play victory sound when someone wins the race
	_debug_log("Main: Race won by %s in %.1fs - playing victory sound" % [winner_name, final_time])
	_play_victory_sound()

func _play_one_shot_audio(stream: AudioStream, volume_db: float = 0.0) -> void:
	## Play a sound once and auto-clean up the player
	## Useful for UI sounds, countdown beeps, victory fanfare, etc.
	if not stream:
		return
	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()
	player.finished.connect(func(): player.queue_free())

# =============================================================================
# MULTIPLAYER FUNCTIONS
# =============================================================================

func _start_dedicated_server() -> void:
	Log.info("Main", "Starting dedicated server on port %d..." % _multiplayer_controller.get_server_port())
	# Signals are already connected in _ready() â€” no reconnection needed
	
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
	# Set timeout unconditionally â€” must happen regardless of game state.
	if NetworkManager.peer:
		var enet_peer := NetworkManager.peer.get_peer(peer_id)
		if enet_peer:
			enet_peer.set_timeout(32, 20000, 60000)
	
	Log.debug("Main", "_on_network_peer_connected - peer_id=%d, game_started=%s, is_multiplayer_game=%s" % [
		peer_id, str(game_started), str(_multiplayer_controller != null and _multiplayer_controller.is_multiplayer_game())
	])

	if _multiplayer_controller and _multiplayer_controller.is_multiplayer_game() and game_started:
		Log.info("Main", "Spawning network player for peer %d (game started)" % peer_id)
		_multiplayer_controller.spawn_network_player(peer_id)
	elif _multiplayer_controller and _multiplayer_controller.is_multiplayer_game() and not game_started:
		# Game hasn't started yet, but we should still track the player
		Log.debug("Main", "Peer %d connected but game hasn't started yet" % peer_id)

	if NetworkManager.is_server():
		_notify_game_started.rpc_id(peer_id)
		
		# In dedicated host mode, first joiner gets race control
		if _is_ui_dedicated_host and _race_controller_peer_id == -1:
			_race_controller_peer_id = peer_id
			_grant_race_control.rpc_id(peer_id)

		# Sync placed audio state to late joiner
		if _painting_controller:
			var audio_state: Dictionary = _painting_controller.get_placed_audio_state()
			if not audio_state.is_empty():
				_sync_placed_audio_to_peer.rpc_id(peer_id, audio_state)

		# Sync stolen paintings to late joiner (state only, no visual sync needed)
		if _painting_controller:
			var stolen_state: Dictionary = _painting_controller.get_stolen_paintings_state()
			if not stolen_state.is_empty():
				_sync_stolen_paintings_to_peer.rpc_id(peer_id, stolen_state)

		# Sync mount state to late joiner so they see mounted players
		var mount_state: Dictionary = _mount_controller.get_mount_state()
		if not mount_state.is_empty():
			_sync_mount_state_to_peer.rpc_id(peer_id, mount_state)

		# Sync current exhibit to late joiner so they see other players
		if _museum and _museum.has_method("get_current_exhibit"):
			var current_exhibit: String = _museum.get_current_exhibit()
			if current_exhibit != "":
				_sync_exhibit_to_peer.rpc_id(peer_id, current_exhibit)

		# Sync placed paintings AFTER exhibit loads (deferred)
		if _painting_controller:
			var state: Array = _painting_controller.get_placed_paintings_state()
			if state.size() > 0:
				call_deferred("_sync_placed_paintings_deferred", peer_id, state)

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
	if _daily_challenge_card and _daily_challenge_card.has_method("set_multiplayer_mode"):
		_daily_challenge_card.set_multiplayer_mode(false)
	if _daily_challenge_card and _daily_challenge_card.has_method("set_main_menu_mode"):
		_daily_challenge_card.set_main_menu_mode()
	_menu_controller.open_main_menu()

func _on_quit_requested() -> void:
	if _multiplayer_controller.is_multiplayer_game():
		NetworkManager.disconnect_from_game()
		_multiplayer_controller.end_multiplayer_session()
		if _daily_challenge_card and _daily_challenge_card.has_method("set_main_menu_mode"):
			_daily_challenge_card.set_main_menu_mode()
		_menu_controller.open_main_menu()
	else:
		get_tree().quit()

func _on_network_player_info_updated(peer_id: int) -> void:
	_multiplayer_controller.update_player_info(peer_id)

func get_local_player() -> Node:
	return _player

func get_network_players() -> Dictionary:
	return _multiplayer_controller.get_network_players() if _multiplayer_controller else {}

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
	Log.debug("Main", "_request_dismount() called, _player=%s, _mount_controller=%s" % [_player, _mount_controller])
	_mount_controller.request_dismount(_player)

# =============================================================================
# PAINTING SYSTEM
# =============================================================================

func _request_steal_painting(exhibit_title: String, image_title: String, image_url: String, image_size: Vector2, is_audio: bool = false) -> void:
	_painting_controller.request_steal(exhibit_title, image_title, image_url, image_size, _player, is_audio)

func _request_place_painting(exhibit_title: String, image_title: String, image_url: String, wall_position: Vector3, wall_normal: Vector3, image_size: Vector2, is_audio: bool = false) -> void:
	_painting_controller.request_place(exhibit_title, image_title, image_url, wall_position, wall_normal, image_size, _player, is_audio)

func restore_placed_painting(exhibit: Node3D, exhibit_title: String,
	image_title: String, image_url: String,
	wall_position: Vector3, wall_normal: Vector3, image_size: Vector2) -> void:
	## Called by ExhibitLoader to re-materialise a saved painting when its room reloads.
	if _painting_controller:
		_painting_controller.restore_placed_painting(exhibit, exhibit_title,
			image_title, image_url, wall_position, wall_normal, image_size)

func check_painting_stolen(exhibit_title: String, image_title: String) -> bool:
	## Called by ExhibitLoader/WallItem to see if a painting was previously stolen.
	if _painting_controller:
		return _painting_controller.is_painting_stolen(exhibit_title, image_title)
	return false


func check_audio_stolen(exhibit_title: String, audio_title: String) -> bool:
	## Called by ExhibitLoader/SoundItem to see if an audio was previously stolen.
	if _painting_controller:
		return _painting_controller.is_audio_stolen(exhibit_title, audio_title)
	return false

func _request_eat_painting(exhibit_title: String, image_title: String) -> void:
	_painting_controller.request_eat(exhibit_title, image_title, _player)

func _on_journal_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_player.start()

func _on_open_trivia(exhibit_title: String) -> void:
	if _trivia_overlay and _trivia_overlay.is_open():
		_trivia_overlay.close()
	elif _trivia_overlay:
		_player.pause()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_trivia_overlay.open(exhibit_title)

func _on_trivia_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_player.start()

func _adjust_ui_scale(delta: float) -> void:
	## delta=0 resets to 1.0; otherwise clamps current + delta to [0.5, 2.0].
	var root := get_tree().root
	var current: float = root.content_scale_factor
	var target: float
	if delta == 0.0:
		target = 1.0
	else:
		target = clampf(snappedf(current + delta, 0.05), 0.5, 2.0)
	if is_equal_approx(target, current):
		return
	# Save + broadcast
	var data: Dictionary = SettingsManager.get_settings("ui") if SettingsManager.get_settings("ui") else {}
	data["scale"] = target
	SettingsManager.save_settings("ui", data)
	SettingsEvents.emit_ui_scale_changed(target)
	# Smooth tween
	var tw := create_tween()
	tw.tween_method(func(v: float): root.content_scale_factor = v,
		current, target, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	_multiplayer_controller.apply_network_position(peer_id, pos, rot_y, pivot_rot_x, pivot_pos_y, is_mounted, mounted_peer_id, _player, current_room, pointing, pt_target)

@rpc("any_peer", "call_remote", "reliable")
func _request_mount_rpc(rider_peer_id: int, mount_peer_id: int) -> void:
	if not NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != rider_peer_id:
		Log.warn("Main", "Mount rejected - sender %d != rider %d" % [sender_id, rider_peer_id])
		return
	_mount_controller.handle_mount_request(rider_peer_id, mount_peer_id, _player)

@rpc("any_peer", "call_remote", "reliable")
func _request_dismount_rpc(rider_peer_id: int) -> void:
	if not NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != rider_peer_id:
		Log.warn("Main", "Dismount rejected - sender %d != rider %d" % [sender_id, rider_peer_id])
		return
	_mount_controller.handle_dismount_request(rider_peer_id, _player)

@rpc("authority", "call_local", "reliable")
func _execute_mount_sync(rider_peer_id: int, mount_peer_id: int) -> void:
	_mount_controller.execute_mount_sync(rider_peer_id, mount_peer_id, _player)

@rpc("authority", "call_local", "reliable")
func _execute_dismount_sync(rider_peer_id: int) -> void:
	_mount_controller.execute_dismount_sync(rider_peer_id, _player)

## Painting RPCs
@rpc("any_peer", "call_remote", "reliable")
func _request_steal_painting_rpc(peer_id: int, exhibit_title: String, image_title: String, image_url: String, image_size: Vector2) -> void:
	if not NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	_painting_controller.handle_steal_request(peer_id, exhibit_title, image_title, image_url, image_size, _player)

@rpc("any_peer", "call_remote", "reliable")
func _request_place_painting_rpc(peer_id: int, exhibit_title: String, image_title: String, image_url: String, wall_position: Vector3, wall_normal: Vector3, image_size: Vector2) -> void:
	if not NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	_painting_controller.handle_place_request(peer_id, exhibit_title, image_title, image_url, wall_position, wall_normal, image_size, _player)

@rpc("any_peer", "call_remote", "reliable")
func _request_steal_audio_rpc(peer_id: int, exhibit_title: String, audio_title: String, audio_url: String) -> void:
	if not NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	_painting_controller.handle_steal_audio_request(peer_id, exhibit_title, audio_title, audio_url, _player)

@rpc("any_peer", "call_remote", "reliable")
func _request_place_audio_rpc(peer_id: int, exhibit_title: String, audio_title: String, audio_url: String, position: Vector3, normal: Vector3) -> void:
	if not NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	_painting_controller.handle_place_audio_request(peer_id, exhibit_title, audio_title, audio_url, position, normal, _player)

@rpc("any_peer", "call_remote", "reliable")
func _request_eat_painting_rpc(peer_id: int, exhibit_title: String, image_title: String) -> void:
	if not NetworkManager.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	_painting_controller.handle_eat_request(peer_id, exhibit_title, image_title, _player)

@rpc("authority", "call_local", "reliable")
func _execute_steal_sync(peer_id: int, exhibit_title: String, image_title: String, image_url: String, image_size: Vector2) -> void:
	_painting_controller.execute_steal_sync(peer_id, exhibit_title, image_title, image_url, image_size, _player)

@rpc("authority", "call_local", "reliable")
func _execute_steal_audio_sync(peer_id: int, exhibit_title: String, audio_title: String, audio_url: String) -> void:
	_painting_controller.execute_steal_audio_sync(peer_id, exhibit_title, audio_title, audio_url, _player)

@rpc("authority", "call_local", "reliable")
func _execute_place_sync(peer_id: int, exhibit_title: String, image_title: String, image_url: String, wall_position: Vector3, wall_normal: Vector3, image_size: Vector2) -> void:
	_painting_controller.execute_place_sync(peer_id, exhibit_title, image_title, image_url, wall_position, wall_normal, image_size, _player)

@rpc("authority", "call_local", "reliable")
func _execute_place_audio_sync(peer_id: int, exhibit_title: String, audio_title: String, audio_url: String, position: Vector3, normal: Vector3) -> void:
	_painting_controller.execute_place_audio_sync(peer_id, exhibit_title, audio_title, audio_url, position, normal, _player)

# Audio playback sync RPCs
@rpc("any_peer", "call_remote", "reliable")
func _request_audio_play_rpc(audio_key: String, exhibit_title: String, audio_title: String) -> void:
	if not NetworkManager.is_server():
		return
	_painting_controller.handle_audio_play_request(exhibit_title, audio_title)
	_broadcast_audio_play_sync.rpc(audio_key, exhibit_title, audio_title)

@rpc("any_peer", "call_remote", "reliable")
func _request_audio_stop_rpc(audio_key: String, exhibit_title: String, audio_title: String) -> void:
	if not NetworkManager.is_server():
		return
	_painting_controller.handle_audio_stop_request(exhibit_title, audio_title)
	_broadcast_audio_stop_sync.rpc(audio_key, exhibit_title, audio_title)

@rpc("authority", "call_local", "reliable")
func _broadcast_audio_play_sync(audio_key: String, exhibit_title: String, audio_title: String) -> void:
	_painting_controller.sync_audio_play(exhibit_title, audio_title)

@rpc("authority", "call_local", "reliable")
func _broadcast_audio_stop_sync(audio_key: String, exhibit_title: String, audio_title: String) -> void:
	_painting_controller.sync_audio_stop(exhibit_title, audio_title)

@rpc("authority", "call_local", "reliable")
func _execute_eat_sync(peer_id: int) -> void:
	_painting_controller.execute_eat_sync(peer_id, _player)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _eat_anim_start_sync(peer_id: int) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	_painting_controller.apply_eat_anim_start(peer_id, _player)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _eat_anim_cancel_sync(peer_id: int) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	_painting_controller.apply_eat_anim_cancel(peer_id, _player)

@rpc("any_peer", "call_remote", "reliable")
func _reaction_sync(peer_id: int, reaction_index: int, target: Vector3) -> void:
	if peer_id != NetworkManager.get_unique_id():
		_pointing_controller.spawn_reaction(reaction_index, target)

@rpc("authority", "call_remote", "reliable")
func _sync_placed_paintings_to_peer(state: Array) -> void:
	## Received by a newly-joined client. Materialises all paintings that existed
	## before they connected.
	if _painting_controller:
		_painting_controller.apply_placed_paintings_state(state, _player)

@rpc("authority", "call_remote", "reliable")
func _sync_placed_audio_to_peer(state: Dictionary) -> void:
	## Received by a newly-joined client. Sets the playing state of placed audio.
	if _painting_controller:
		_painting_controller.apply_placed_audio_state(state)

@rpc("authority", "call_local", "reliable")
func _sync_stolen_paintings_to_peer(state: Dictionary) -> void:
	## Received by a newly-joined client. Populates the stolen painting map.
	if _painting_controller:
		_painting_controller.apply_stolen_paintings_state(state)

@rpc("authority", "call_local", "reliable")
func _sync_mount_state_to_peer(state: Dictionary) -> void:
	## Received by a newly-joined peer. Sets initial mount state for all players.
	for rider_peer_id in state:
		var mount_peer_id: int = state[rider_peer_id]
		if mount_peer_id != -1:
			_mount_controller.apply_mount_state(rider_peer_id, mount_peer_id, _player)

@rpc("authority", "call_remote", "reliable")
func _sync_wikipedia_data(article: String, data: Dictionary) -> void:
	## Received by clients - caches Wikipedia data from server
	Log.debug("Main", "Received Wikipedia data for '%s' from server" % article)
	# Directly cache the result in ExhibitFetcher
	ExhibitFetcher._cache_result(article, data)


func _sync_placed_paintings_deferred(peer_id: int, state: Array) -> void:
	## Deferred sync for placed paintings - waits one frame to ensure exhibit is loaded
	## This prevents paintings from being parented to the wrong node.
	if not is_instance_valid(_painting_controller):
		return

	# Check if exhibit is loaded (wait up to 2 seconds)
	var max_wait: int = 40  # 40 frames at 60fps = ~0.67 seconds
	var wait_count: int = 0

	while wait_count < max_wait:
		# Check if museum has any exhibits loaded
		var museum: Node = get_node_or_null("Museum")
		if museum and museum.get_child_count() > 0:
			# Exhibit loaded - sync now
			_sync_placed_paintings_to_peer.rpc_id(peer_id, state)
			return

		wait_count += 1
		await get_tree().process_frame

	# Timeout - sync anyway (paintings will be parented to Main as fallback)
	Log.warn("Main", "Exhibit didn't load in time for painting sync - syncing anyway")
	_sync_placed_paintings_to_peer.rpc_id(peer_id, state)


## Syncs the race starting exhibit to all non-server peers so they also
## open the search door and load the starting article.
@rpc("authority", "call_remote", "reliable")
func _sync_race_start_article(start_article: String) -> void:
	Log.debug("Main", "_sync_race_start_article: Loading exhibit '%s'" % start_article)

	# Wait for Wikipedia data to arrive from server (if we're a client) - max 1 second
	var max_wait := 1.0
	var wait_step := 0.1
	var waited := 0.0
	while not ExhibitFetcher.has_result(start_article) and waited < max_wait:
		await get_tree().create_timer(wait_step).timeout
		waited += wait_step

	if not ExhibitFetcher.has_result(start_article):
		Log.warn("Main", "Wikipedia data never arrived for '%s'" % start_article)
	else:
		Log.debug("Main", "Wikipedia data received for '%s'" % start_article)

	# SERVER: Generate room and broadcast to all clients
	if NetworkManager.is_server() and Services.room_service:
		Log.info("Main", "Server generating room for '%s'" % start_article)

		# Get target FIRST - set it in HintManager before room generates
		var target_article: String = RaceManager.get_target_article()
		Log.info("Main", "Race target set to '%s'" % target_article)
		
		# Set target in HintManager immediately so door replacement can work
		# Hint system disabled
		# var hint_manager = get_node_or_null("/root/HintManager")
		# if hint_manager:
		# 	hint_manager.set_current_target(target_article)
		
		# # Fetch and cache backlinks (non-blocking)
		# _fetch_and_cache_backlinks(target_article)
		
		var room_data = Services.room_service.generate_room(start_article)

		# Get Wikipedia data (or empty dict if failed)
		var wiki_data: Variant = ExhibitFetcher.get_result(start_article)
		if wiki_data == null:
			Log.warn("Main", "No Wikipedia data for '%s', generating room with empty data" % start_article)
			wiki_data = {}

		Services.room_service.populate_room_data(room_data, wiki_data, [])
		Services.room_service.broadcast_room(room_data)
	else:
		# CLIENT: Wait for room data from server
		Log.debug("Main", "Client waiting for room data from server...")

	# Load the exhibit (will use cached RoomData if available)
	if _museum.has_method("load_exhibit_for_rider"):
		Log.debug("Main", "Loading exhibit '%s' before opening door..." % start_article)
		_museum.load_exhibit_for_rider("Lobby", start_article)

	# Wait for exhibit to generate (up to 0.5 seconds)
	Log.debug("Main", "Waiting for exhibit to generate (max 0.5s)...")
	for i in range(10):  # 10 x 0.05s = 0.5 seconds
		await get_tree().create_timer(0.05).timeout
		if _museum.has_exhibit(start_article):
			Log.debug("Main", "Exhibit generated after %.2fs" % ((i + 1) * 0.05))
			break

	# Set custom door FIRST (before reset_to_lobby)
	UIEvents.emit_set_custom_door(start_article)
	Log.debug("Main", "Custom door set to '%s'" % start_article)
	
	# THEN reset to lobby (this will show the custom door)
	_museum.reset_to_lobby()
	Log.debug("Main", "Door opened for '%s' - exhibit ready to walk into!" % start_article)

	# Teleport all players to the start line
	teleport_all_players_to_start_line(start_article)

	# Start the game (player can now walk through door)
	_start_game()

func _teleport_all_players_to_article(article: String) -> void:
	## Teleport all connected players to the specified article
	Log.debug("Main", "[_teleport_all_players_to_article] Called with article=%s" % article)
	if not _museum:
		Log.error("Main", "_museum is null!")
		return

	# Check if exhibit exists
	if not _museum.has_exhibit(article):
		var exhibits_dict = _museum.get("exhibits") if "exhibits" in _museum else _museum.get("_exhibits")
		var exhibit_keys = exhibits_dict.keys() if exhibits_dict else []
		Log.error("Main", "Exhibit '%s' NOT loaded! Available: %s" % [article, exhibit_keys])
		return

	Log.debug("Main", "Exhibit '%s' found" % article)

	# Get all players
	var all_players = get_tree().get_nodes_in_group("Player")
	Log.debug("Main", "Found %d players to teleport" % all_players.size())

	for player in all_players:
		if not is_instance_valid(player):
			Log.debug("Main", "Skipping invalid player")
			continue

		# Find the entry marker - it's inside the Hall node
		var new_exhibit = _get_exhibit_for_article(article)
		if not new_exhibit:
			Log.error("Main", "Could not get exhibit node for %s" % article)
			continue
		
		# Try multiple possible locations for EntryMarker
		var entry_marker: Node = null
		if new_exhibit.has_node("Entry/EntryMarker"):
			entry_marker = new_exhibit.get_node("Entry/EntryMarker")
		elif new_exhibit.has_node("Hall/EntryMarker"):
			entry_marker = new_exhibit.get_node("Hall/EntryMarker")
		else:
			# Search recursively
			entry_marker = new_exhibit.find_child("EntryMarker", true, false)
		
		if not entry_marker:
			Log.error("Main", "EntryMarker not found in exhibit! Children: %s" % [new_exhibit.get_children()])
			continue

		var entry_pos = entry_marker.global_transform.origin
		Log.debug("Main", "Teleporting %s to %s" % [player.name, entry_pos])
		player.global_transform.origin = entry_pos + Vector3(0, 1, 0)
		if "current_room" in player:
			player.current_room = article
			Log.debug("Main", "Set %s current_room to %s" % [player.name, article])

		# Also teleport mounted riders
		_teleport_mounted_rider(player, entry_pos, article)
	
	Log.debug("Main", "<<< Teleport complete for %d players" % all_players.size())

func _teleport_mounted_rider(player: Node, position: Vector3, room: String) -> void:
	## Teleport a mounted rider to the same location as their mount
	if not ("mounted_by" in player and player.mounted_by):
		return
	
	var rider = player.mounted_by
	if not is_instance_valid(rider):
		return
	
	rider.global_transform.origin = position + Vector3(0, Constants.MOUNTED_RIDER_Y_OFFSET, 0)
	if "current_room" in rider:
		rider.current_room = room

func teleport_all_players_to_start_line(start_article: String) -> void:
	"""Teleport all players to the race start line in the lobby."""
	Log.debug("Main", ">>> Teleporting all players to race start line")

	# The start line is at the bottom of the stairs, before the search corridor
	# Spawn HIGH above the floor so players fall down onto it safely
	var base_z: float = 23.0  # Z position of the start line
	var base_y: float = 5.0  # Height above the floor

	# Get all players
	var all_players = get_tree().get_nodes_in_group("Player")
	Log.debug("Main", "Found %d players to teleport" % all_players.size())

	# Spread players across the start line to avoid stacking
	var player_index: int = 0
	for player in all_players:
		if not is_instance_valid(player):
			Log.debug("Main", "Skipping invalid player")
			continue

		# Offset players horizontally along the start line (X axis)
		# Each player is 1.5 units apart, centered around X=0
		var offset_x: float = (player_index - (all_players.size() - 1) / 2.0) * 1.5
		var lobby_start_pos = Vector3(offset_x, base_y, base_z)

		Log.debug("Main", "Teleporting %s to start line at %s" % [player.name, lobby_start_pos])
		player.global_transform.origin = lobby_start_pos
		player.rotation = Vector3(0, deg_to_rad(180), 0)  # Face toward search corridor
		player.velocity = Vector3.ZERO  # Reset velocity
		player_index += 1
		if "current_room" in player:
			player.current_room = "Lobby"
			Log.debug("Main", "Set %s current_room to Lobby" % player.name)

		# Also teleport mounted riders
		_teleport_mounted_rider(player, lobby_start_pos, "Lobby")
	
	Log.debug("Main", "<<< All %d players teleported to race start line!" % all_players.size())

func _fetch_and_cache_backlinks(target_article: String) -> void:
	"""Fetch backlinks at race start and cache for text hints."""
	if target_article == "":
		return
	
	if _hint_backlinks.size() > 0:
		return
	
	var url: String = "https://en.wikipedia.org/w/api.php?action=query&format=json&list=backlinks&bllimit=100&bltitle=" + target_article.uri_encode() + "&blnamespace=0&origin=*"
	var http := HTTPRequest.new()
	add_child(http)
	
	var request_completed = func(result_code, response_code, _headers, body):
		if result_code == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var data = json.get_data()
				if data.has("query") and data.query.has("backlinks"):
					var backlinks: Array[String] = []
					var seen: Dictionary = {}
					for bl in data.query.backlinks:
						if bl.has("title"):
							var title = bl.title as String
							if title.begins_with("File:") or title.begins_with("Image:"):
								continue
							if title.begins_with("Category:"):
								continue
							if title.begins_with("Template:"):
								continue
							if title.begins_with("Wikipedia:") or title.begins_with("Help:"):
								continue
							if not seen.has(title):
								seen[title] = true
								backlinks.append(title)
					_hint_backlinks = backlinks
					Log.debug("Main", "Cached %d backlinks for hints" % backlinks.size())
				else:
					Log.debug("Main", "No backlinks found")
		http.queue_free()
	
	http.request_completed.connect(request_completed)
	http.request(url)

func _validate_backlinks_and_cache(target_article: String, potential_backlinks: Array[String]) -> void:
	"""Validate each backlink by fetching its content and checking if target appears."""
	if potential_backlinks.is_empty():
		var hint_manager = get_node_or_null("/root/HintManager")
		if hint_manager:
			hint_manager.set_backlinks(target_article, [])
		return
	
	# Batch process - validate first 5 backlinks only (fast validation)
	var to_validate = potential_backlinks.slice(0, min(5, potential_backlinks.size()))
	
	# Use a Dictionary to track state across closures
	var state = {
		"validated": [] as Array[String],
		"pending": to_validate.size(),
		"target": target_article,
		"original_count": potential_backlinks.size()
	}
	
	for backlink in to_validate:
		# Wikipedia API: fetch page content (full extract, not just intro)
		var url: String = "https://en.wikipedia.org/w/api.php?action=query&format=json&prop=extracts&explaintext=true&titles=" + backlink.uri_encode() + "&origin=*"
		var http := HTTPRequest.new()
		add_child(http)
		
		var on_complete = func(result_code, response_code, _headers, body):
			if result_code == HTTPRequest.RESULT_SUCCESS and response_code == 200:
				var json = JSON.new()
				if json.parse(body.get_string_from_utf8()) == OK:
					var data = json.get_data()
					if data.has("query") and data.has("pages"):
						var pages = data.query.pages
						for page_id in pages:
							var page = pages[page_id]
							if page.has("extract"):
								var extract = page.extract as String
								# Check if target appears in the extract (main content)
								var target_lower = state.target.to_lower()
								var extract_lower = extract.to_lower()
								# Also check for common variations (e.g., "the Outback", "Outback region")
								var found = extract_lower.find(target_lower) != -1
								if not found:
									# Try with "the " prefix
									found = extract_lower.find("the " + target_lower) != -1
								if found:
									state.validated.append(backlink)
									Log.debug("Main", "VALIDATED backlink '%s' contains '%s'" % [backlink, state.target])
			
			state.pending -= 1
			if state.pending == 0:
				# All validations complete - cache results
				var hint_manager = get_node_or_null("/root/HintManager")
				if hint_manager:
					hint_manager.set_backlinks(state.target, state.validated)
					Log.info("Main", "Cached %d VALIDATED backlinks for '%s' (filtered from %d)" % [state.validated.size(), state.target, state.original_count])
				# Clean up any remaining HTTP requests
				for child in get_children():
					if child is HTTPRequest:
						child.queue_free()
		
		http.request_completed.connect(on_complete)
		http.request(url)

func _reveal_host_hint() -> void:
	"""Host pressed I key - reveal a text hint to all players."""
	if _hint_backlinks.is_empty():
		return
	
	var available_hints: Array[String] = []
	for bl in _hint_backlinks:
		if not _hints_revealed or not bl in _hint_backlinks.slice(0, _hints_revealed):
			available_hints.append(bl)
	
	if available_hints.is_empty():
		return
	
	var hint: String = available_hints.pick_random()
	_hints_revealed += 1
	
	# Emit to RaceHUD via HintManager
	var hint_manager = get_node_or_null("/root/HintManager")
	if hint_manager and hint_manager.has_signal("hint_revealed"):
		hint_manager.reveal_hint_to_all(hint, "backlink")

	Log.info("Main", "Host revealed hint %d: '%s'" % [_hints_revealed, hint])

func _fetch_categories_for_article(article: String) -> Array[String]:
	"""Fetch Wikipedia categories for an article."""
	var categories: Array[String] = []
	
	# Check if we already have the data cached
	var result = ExhibitFetcher.get_result(article)
	if result and result.has("categories"):
		for cat_data in result.categories:
			if cat_data.has("title"):
				categories.append(cat_data.title.replace("Category:", ""))
	
	# If no categories, fetch them
	if categories.size() == 0:
		# Direct API call for categories
		var url := "https://en.wikipedia.org/w/api.php?action=query&prop=categories&format=json&cllimit=50&titles=" + article.uri_encode()
		var http := HTTPRequest.new()
		add_child(http)
		var fetch_complete: bool = false
		
		var request_completed = func(result_code, response_code, _headers, body):
			if result_code == HTTPRequest.RESULT_SUCCESS and response_code == 200:
				var json = JSON.new()
				if json.parse(body.get_string_from_utf8()) == OK:
					var data = json.get_data()
					if data.has("query") and data.query.has("pages"):
						for page_id in data.query.pages:
							var page = data.query.pages[page_id]
							if page.has("categories"):
								for cat in page.categories:
									if cat.has("title"):
										categories.append(cat.title.replace("Category:", ""))
			fetch_complete = true
			http.queue_free()
		
		http.request_completed.connect(request_completed)
		http.request(url)
		
		# Wait for response (max 2 seconds)
		for i in range(20):
			if fetch_complete:
				break
			await get_tree().create_timer(0.1).timeout
	
	return categories

func _fetch_wikidata_properties(article: String) -> Array[Dictionary]:
	"""Fetch Wikidata properties for an article."""
	var properties: Array[Dictionary] = []
	
	# Properties to fetch (P31=instance of, P279=subclass of, P106=medical use, P921=main topic)
	var useful_properties = ["P31", "P279", "P106", "P921", "P361", "P527"]
	
	# Step 1: Get Q-ID from Wikipedia
	var q_id: String = await _get_wikidata_qid(article)
	if q_id == "":
		return properties
	
	# Step 2: Fetch claims for useful properties
	var url := "https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&ids=" + q_id + "&props=claims&languages=en"
	var http := HTTPRequest.new()
	add_child(http)
	var fetch_complete: bool = false
	var raw_claims: Dictionary = {}
	
	var request_completed = func(result_code, response_code, _headers, body):
		if result_code == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var data = json.get_data()
				if data.has("entities") and data.entities.has(q_id):
					var entity = data.entities[q_id]
					if entity.has("claims"):
						raw_claims = entity.claims
		fetch_complete = true
		http.queue_free()
	
	http.request_completed.connect(request_completed)
	http.request(url)
	
	# Wait for response
	for i in range(20):
		if fetch_complete:
			break
		await get_tree().create_timer(0.1).timeout
	
	# Step 3: Extract property values and fetch labels
	if raw_claims.size() > 0:
		var q_ids_to_fetch: Array[String] = []
		
		# Collect all Q-IDs we need labels for
		for prop_id in useful_properties:
			if raw_claims.has(prop_id):
				for claim in raw_claims[prop_id]:
					if claim.has("mainsnak") and claim.mainsnak.has("datavalue") and \
					   claim.mainsnak.datavalue.has("value") and \
					   claim.mainsnak.datavalue.value.has("id"):
						var value_id: String = claim.mainsnak.datavalue.value.id
						if value_id.begins_with("Q"):
							q_ids_to_fetch.append(value_id)
		
		# Fetch labels for all Q-IDs
		if q_ids_to_fetch.size() > 0:
			var labels_url := "https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&ids=" + "|".join(q_ids_to_fetch) + "&languages=en&props=labels"
			var labels_http := HTTPRequest.new()
			add_child(labels_http)
			var labels_complete: bool = false
			var labels_data: Dictionary = {}
			
			var labels_completed = func(result_code, response_code, _headers, body):
				if result_code == HTTPRequest.RESULT_SUCCESS and response_code == 200:
					var json = JSON.new()
					if json.parse(body.get_string_from_utf8()) == OK:
						labels_data = json.get_data()
				labels_complete = true
				labels_http.queue_free()
			
			labels_http.request_completed.connect(labels_completed)
			labels_http.request(labels_url)
			
			# Wait for labels
			for i in range(20):
				if labels_complete:
					break
				await get_tree().create_timer(0.1).timeout
			
			# Build properties array
			var labels: Dictionary = {}
			if labels_data.has("entities"):
				for qid in labels_data.entities:
					var entity = labels_data.entities[qid]
					if entity.has("labels") and entity.labels.has("en"):
						labels[qid] = entity.labels["en"].value
			
			# Property labels
			var prop_labels = {
				"P31": "Type",
				"P279": "Subclass of",
				"P106": "Medical use",
				"P921": "Main topic",
				"P361": "Part of",
				"P527": "Has part"
			}
			
			for prop_id in useful_properties:
				if raw_claims.has(prop_id):
					var claims_array: Array = raw_claims[prop_id]
					for claim_variant in claims_array:
						var claim: Dictionary = claim_variant as Dictionary
						if claim.is_empty():
							continue
						if claim.has("mainsnak") and claim.mainsnak.has("datavalue") and \
						   claim.mainsnak.datavalue.has("value") and \
						   claim.mainsnak.datavalue.value.has("id"):
							var value_id: String = claim.mainsnak.datavalue.value.id
							var value_label: String = labels.get(value_id, value_id)
							var prop_label: String = prop_labels.get(prop_id, prop_id)
							properties.append({"label": prop_label, "value": value_label})
	
	return properties

func _get_wikidata_qid(article: String) -> String:
	"""Get Wikidata Q-ID for a Wikipedia article."""
	# Check if we have it cached from Wikipedia fetch
	var result = ExhibitFetcher.get_result(article)
	if result and result.has("wikibase_item"):
		return result.wikibase_item
	
	# Fetch from Wikipedia API
	var url := "https://en.wikipedia.org/w/api.php?action=query&prop=pageprops&format=json&titles=" + article.uri_encode()
	var http := HTTPRequest.new()
	add_child(http)
	var fetch_complete: bool = false
	var q_id: String = ""
	
	var request_completed = func(result_code, response_code, _headers, body):
		if result_code == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var data = json.get_data()
				if data.has("query") and data.query.has("pages"):
					for page_id in data.query.pages:
						var page = data.query.pages[page_id]
						if page.has("pageprops") and page.pageprops.has("wikibase_item"):
							q_id = page.pageprops.wikibase_item
		fetch_complete = true
		http.queue_free()
	
	http.request_completed.connect(request_completed)
	http.request(url)
	
	# Wait for response
	for i in range(20):
		if fetch_complete:
			break
		await get_tree().create_timer(0.1).timeout
	
	return q_id

func _get_exhibit_for_article(article: String) -> Node:
	## Get the exhibit node for an article title
	if not _museum or not _museum.has_method("has_exhibit"):
		return null
	
	if not _museum.has_exhibit(article):
		return null
	
	# Access exhibits dictionary through Museum
	if "exhibits" in _museum or "_exhibits" in _museum:
		var exhibits = _museum.get("exhibits") if "exhibits" in _museum else _museum.get("_exhibits")
		if exhibits and exhibits.has(article):
			var exhibit_data = exhibits[article]
			if exhibit_data is Dictionary and exhibit_data.has("exhibit"):
				return exhibit_data.exhibit
	
	return null

func sync_custom_door(page: String) -> void:
	## Synchronises the search corridor door to a specific page for all players.
	## If called by a client, it requests the server to broadcast the change.
	if not NetworkManager.is_multiplayer_active() or NetworkManager.is_server():
		if NetworkManager.is_multiplayer_active():
			_sync_race_start_article.rpc(page)
		UIEvents.emit_set_custom_door(page)
	else:
		_request_sync_custom_door.rpc_id(1, page)

@rpc("any_peer", "call_remote", "reliable")
func _request_sync_custom_door(page: String) -> void:
	if NetworkManager.is_server():
		sync_custom_door(page)

@rpc("authority", "call_remote", "reliable")
func _grant_race_control() -> void:
	## Called on the client that should have race control in dedicated host mode.
	## Overrides the PauseMenu visibility check to show Start Race.
	if _pause_menu and _pause_menu.has_method("set_race_control_override"):
		_pause_menu.set_race_control_override(true)

# =============================================================================
# DAILY CHALLENGE FUNCTIONS
# =============================================================================

func _on_daily_challenge_started() -> void:
	## Player confirmed they want to race â€” load start article and go.
	game_started = true
	_menu_controller.close_menus()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _player:
		_player.start()
	var start_article: String = _daily_challenge_manager.get_start_article()
	var target_article: String = _daily_challenge_manager.get_target_article()
	if start_article != "":
		_museum.reset_to_lobby()
		UIEvents.emit_set_custom_door(start_article)
		if NetworkManager.is_multiplayer_active() and NetworkManager.is_server():
			_sync_race_start_article.rpc(start_article)
	GameplayEvents.emit_race_started(target_article)
	_daily_challenge_manager.begin_timer()
	# Show persistent in-game timer strip
	if _daily_challenge_hud and _daily_challenge_hud.has_method("show_strip"):
		_daily_challenge_hud.show_strip()

func _on_daily_challenge_closed() -> void:
	_menu_controller.close_menus()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _player:
		_player.start()

func _on_race_won_for_daily_challenge(winner_name: String, final_time: float) -> void:
	## Fires when any race_won signal is received. If a daily challenge
	## is active, complete it and pop the results screen.
	if _daily_challenge_manager and _daily_challenge_manager.is_active():
		_daily_challenge_manager.complete_challenge()

func _show_system_message(message: String) -> void:
	"""Display a system message to the player via chat system."""
	if _chat_system and _chat_system.has_method("_show_system_message"):
		_chat_system._show_system_message(message)


func _show_error_message(message: String) -> void:
	"""Display an error message to the player via chat/prompt system."""
	if _chat_system and _chat_system.has_method("_show_system_message"):
		_chat_system._show_system_message("âš ï¸ " + message)
	if _prompt_hud and _prompt_hud.has_method("show_message"):
		_prompt_hud.show_message(message)
		call_deferred("_show_daily_challenge_results")

func _show_daily_challenge_results() -> void:
	if _daily_challenge_hud and _daily_challenge_hud.has_method("show_results"):
		if _player: _player.pause()
		var time_sec: float = _daily_challenge_manager.get_elapsed()
		var is_best: bool = _daily_challenge_manager.get_best_time() == time_sec
		_daily_challenge_hud.show_results(time_sec, is_best)

# =============================================================================
# SPECTATOR FUNCTIONS
# =============================================================================

func _on_spectator_exited() -> void:
	## SpectatorController dismissed itself â€” restore normal play.
	_start_game()

func _on_challenge_completed_for_leaderboard(time_seconds: float, _is_best: bool) -> void:
	if not _daily_challenge_leaderboard:
		return
	var player_name: String = NetworkManager.get_player_name(NetworkManager.get_unique_id())
	if player_name == "" or player_name == "Player":
		player_name = "Anonymous"
	_daily_challenge_leaderboard.submit_score(
		_daily_challenge_manager.get_today_key(),
		player_name,
		time_seconds
	)

func _spawn_daily_challenge_board() -> void:
	if _daily_challenge_board and is_instance_valid(_daily_challenge_board):
		return
	var board_script := load("res://scenes/DailyChallengeBoard.gd")
	if not board_script:
		return
	_daily_challenge_board = board_script.new()
	_daily_challenge_board.name = "DailyChallengeBoard"
	# Position it near the spawn â€” adjust these to suit your lobby layout
	_daily_challenge_board.board_position  = Vector3(2.5, 0.0, -2.0)
	_daily_challenge_board.board_rotation_y = -30.0
	_museum.add_child(_daily_challenge_board)
	if _daily_challenge_board.has_method("init"):
		_daily_challenge_board.init(_daily_challenge_manager, _daily_challenge_leaderboard)

# === Host Menu Support Methods ===

func set_custom_start(article: String) -> void:
	"""Set custom race start article"""
	if article != "":
		_race_start_article = article
		if _museum and _museum.has_method("sync_custom_door"):
			_museum.sync_custom_door(article)

func _teleport_player_to_lobby() -> void:
	"""Teleport local player to lobby"""
	if _player:
		_player.position = Vector3(0, 4, 0)
		_player.rotation.y = 0
		if _museum:
			_museum._current_room_title = "Lobby"


# =============================================================================
# SCREENSHOT
# =============================================================================

## Canvas layer that shows the flash + filename toast.
var _screenshot_layer: CanvasLayer = null

func _take_screenshot() -> void:
	## Captures the current viewport, saves to user://screenshots/YYYY-MM-DD_HH-MM-SS.png,
	## and briefly flashes the screen with the saved filename.
	var img: Image = get_viewport().get_texture().get_image()
	if not img:
		return

	# Build save path
	var dir_path: String = "user://screenshots"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var filename: String = "%04d-%02d-%02d_%02d-%02d-%02d.png" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]
	var full_path: String = "%s/%s" % [dir_path, filename]

	var err: Error = img.save_png(full_path)
	if err != OK:
		push_warning("Screenshot failed: %s" % error_string(err))
		return

	_show_screenshot_toast(filename, OS.get_user_data_dir() + "/screenshots/" + filename)


func _show_screenshot_toast(filename: String, full_os_path: String) -> void:
	## Creates a brief white-flash overlay + filename label, then fades out.
	if not _screenshot_layer or not is_instance_valid(_screenshot_layer):
		_screenshot_layer = CanvasLayer.new()
		_screenshot_layer.name = "ScreenshotLayer"
		_screenshot_layer.layer = 127
		add_child(_screenshot_layer)

	# White flash rect
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0.55)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screenshot_layer.add_child(flash)

	# Toast label at bottom-centre
	var toast := Label.new()
	toast.text = "ðŸ“· Saved: %s" % filename
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toast.offset_top    = -60
	toast.offset_bottom = 0
	toast.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_font_size_override("font_size", 16)
	toast.add_theme_color_override("font_color", Color.WHITE)
	toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	toast.add_theme_constant_override("shadow_offset_x", 1)
	toast.add_theme_constant_override("shadow_offset_y", 1)
	_screenshot_layer.add_child(toast)

	# Fade out flash quickly, keep toast a little longer
	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "color:a", 0.0, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(toast, "modulate:a", 0.0, 1.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.8)


# =============================================================================
# PIPER TTS TESTING
# =============================================================================

func _test_pcm_playback() -> void:
	"""Test playing Piper TTS audio - Press F10 to test"""
	Log.debug("Main", "[Piper Test] F10 pressed - testing WAV playback...")

	# Try loading the WAV file we generated earlier
	var file_path = "user://piper_voices/test_output.wav"
	var absolute_path = ProjectSettings.globalize_path(file_path)

	if not FileAccess.file_exists(absolute_path):
		Log.error("Main", "[Piper Test] WAV file not found at: %s" % absolute_path)
		return

	# Read raw WAV data
	var file = FileAccess.open(absolute_path, FileAccess.READ)
	var wav_data = file.get_buffer(file.get_length())
	file.close()

	Log.debug("Main", "[Piper Test] Loaded %d bytes of WAV data" % wav_data.size())

	# WAV header is 44 bytes - skip it to get raw PCM
	if wav_data.size() < 44:
		Log.error("Main", "[Piper Test] File too small for WAV")
		return

	# Extract raw PCM (skip 44-byte WAV header)
	var pcm_data = wav_data.slice(44)
	Log.debug("Main", "[Piper Test] Extracted %d bytes of PCM data" % pcm_data.size())

	# Read WAV header to get format info
	# Sample rate is at bytes 24-27 (little-endian)
	var sample_rate = wav_data[24] | (wav_data[25] << 8) | (wav_data[26] << 16) | (wav_data[27] << 24)
	Log.debug("Main", "[Piper Test] Sample rate: %d Hz" % sample_rate)

	# Create AudioStreamWAV and set data directly
	var stream = AudioStreamWAV.new()
	stream.data = pcm_data
	stream.mix_rate = sample_rate
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false  # Piper outputs mono

	Log.debug("Main", "[Piper Test] AudioStreamWAV configured")

	# Create player
	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -20  # 10% volume (safe!)
	add_child(player)

	player.play()
	Log.debug("Main", "[Piper Test] Playback started")
	Log.debug("Main", "[Piper Test] Listen for clear speech (no static)")

	# Cleanup after playback
	await player.finished
	Log.debug("Main", "[Piper Test] Playback finished")
	player.queue_free()


func _exit_tree() -> void:
	# Clean up menu controller connections
	if _menu_controller:
		_menu_controller.game_start_requested.disconnect(_start_game)
		_menu_controller.multiplayer_start_requested.disconnect(_on_multiplayer_start_game)
	
	# Clean up ThemeManager signal (lambda stored in _ready)
	if _reading_font_lambda.is_valid():
		ThemeManager.reading_font_changed.disconnect(_reading_font_lambda)
	
	# Clean up UI events (lambda may have been connected in _initialize_room_service)
	# Note: _quit_lambda may not be stored if connect was inline, so we use is_valid check
	if _quit_lambda.is_valid():
		UIEvents.quit_requested.disconnect(_quit_lambda)
	
	UIEvents.open_trivia.disconnect(_on_open_trivia)
	
	# Clean up trivia overlay
	if _trivia_overlay and _trivia_overlay.trivia_closed.is_connected(_on_trivia_closed):
		_trivia_overlay.trivia_closed.disconnect(_on_trivia_closed)
	
	# Clean up multiplayer controller
	if _multiplayer_controller:
		_multiplayer_controller.end_multiplayer_session()
