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

## Subsystems
var _menu_controller: MainMenuController = null
var _multiplayer_controller: MultiplayerController = null
var _mount_controller: MountController = null
var _painting_controller: PaintingController = null
var _pointing_controller: PointingController = null
var _chat_system: Node = null
var _chat_hud: Node = null
var _trivia_manager: TriviaManager = null

@onready var _journal_overlay: JournalOverlay = %JournalOverlay
@onready var player_list_overlay: Control = %PlayerListOverlay
@onready var _server_console_overlay: Control = %ServerConsoleOverlay
@onready var _map_overlay: Control = %ExhibitMapOverlay
@onready var _minimap_hud: Control = %MinimapHUD
@onready var _connection_hud: Control = %ConnectionHUD
@onready var _trivia_overlay: TriviaOverlay = %TriviaOverlay
@onready var _powerup_hud: Control = %PowerupHUD

## 0 = hidden, 1 = 3D minimap, 2 = connection map
var _minimap_mode: int = 0
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
	# Restore UI scale from settings before anything else renders
	var ui_saved = SettingsManager.get_settings("ui")
	if ui_saved and ui_saved.has("scale"):
		get_tree().root.content_scale_factor = float(ui_saved.scale)
	
	# WIP Label font management
	if _wip_label:
		_wip_label.add_theme_font_override("font", ThemeManager.get_reading_font())
		ThemeManager.reading_font_changed.connect(func(f): _wip_label.add_theme_font_override("font", f))
	
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
	# Animate card out in sync with every MainMenu button (Enter, Multiplayer, Settings, Quit)
	if main_menu_node:
		for sig: String in ["start", "settings", "start_multiplayer", "start_dedicated_host"]:
			if main_menu_node.has_signal(sig):
				main_menu_node.connect(sig, func():
					if _daily_challenge_card and _daily_challenge_card.has_method("animate_out"):
						_daily_challenge_card.animate_out())
	# Quit goes through UIEvents — animate card out alongside menu transition
	UIEvents.quit_requested.connect(func():
		if _daily_challenge_card and _daily_challenge_card.has_method("animate_out"):
			_daily_challenge_card.animate_out())
	
	# Connect Settings resume signal to show MainMenu.
	# Guard with is_connected — the scene inspector may already wire this.
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
	_daily_challenge_card_layer = CanvasLayer.new()
	_daily_challenge_card_layer.name = "DailyChallengeCardLayer"
	_daily_challenge_card_layer.layer = 100  # guaranteed above all menus regardless of MenuLayer's layer
	add_child(_daily_challenge_card_layer)
	_daily_challenge_card = load("res://scenes/ui/DailyChallengeCard.gd").new()
	_daily_challenge_card.name = "DailyChallengeCard"
	_daily_challenge_card_layer.add_child(_daily_challenge_card)
	# Pre-fetch today's target right away — don't wait for game start
	_daily_challenge_manager.start_challenge()
	# Show card on main menu immediately (no player yet)
	if _daily_challenge_card.has_method("init_for_main_menu"):
		_daily_challenge_card.init_for_main_menu(_daily_challenge_manager, _daily_challenge_hud, _daily_challenge_leaderboard, _menu_layer)

	# Spectator
	_spectator_controller = load("res://scenes/main/SpectatorController.gd").new()
	_spectator_controller.name = "SpectatorController"
	add_child(_spectator_controller)
	_spectator_controller.spectator_exited.connect(_on_spectator_exited)
	
	_parse_command_line()
	
	# Register host hint keybind (H) at runtime
	if not InputMap.has_action("reveal_hint"):
		InputMap.add_action("reveal_hint")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_H
		InputMap.action_add_event("reveal_hint", ev)
	
	# Register trivia keybind (K) at runtime
	if not InputMap.has_action("toggle_trivia"):
		InputMap.add_action("toggle_trivia")
		var ev_t := InputEventKey.new()
		ev_t.physical_keycode = KEY_K
		InputMap.action_add_event("toggle_trivia", ev_t)

	# Register powerup HUD toggle (P) at runtime
	if not InputMap.has_action("toggle_powerups"):
		InputMap.add_action("toggle_powerups")
		var ev_p := InputEventKey.new()
		ev_p.physical_keycode = KEY_P
		InputMap.action_add_event("toggle_powerups", ev_p)
		var ev_p2 := InputEventJoypadButton.new()
		ev_p2.button_index = JOY_BUTTON_Y
		ev_p2.device = -1
		InputMap.action_add_event("toggle_powerups", ev_p2)

	# Register daily challenge keybind (G)
	if not InputMap.has_action("open_daily_challenge"):
		InputMap.add_action("open_daily_challenge")
		var ev_d := InputEventKey.new()
		ev_d.physical_keycode = KEY_G
		InputMap.action_add_event("open_daily_challenge", ev_d)

	# Register spectator keybind (F) — multiplayer only
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
	
	if _multiplayer_controller.is_server_mode():
		_start_dedicated_server()
		return
	
	if OS.has_feature("movie"):
		_fps_label.visible = false
	
	_recreate_player()
	
	GraphicsManager.change_post_processing.connect(_change_post_processing)
	GraphicsManager.init()
	
	# ✅ FIX: Connect pause menu signals. Guard each with is_connected so we
	# don't double-connect if the scene file already wired them in the inspector.
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
	RaceManager.vote_cancelled.connect(_on_vote_cancelled)
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
	_player_pivot = _player.get_node("Pivot")
	_player_pivot.get_node("Camera3D").make_current()
	_player.rotation.y = starting_rotation
	_player.max_speed = player_speed
	_player.smooth_movement = smooth_movement
	_player.dampening = smooth_movement_dampening
	_player.position = starting_point
	_player.set_player_color(NetworkManager.local_player_color)
	if _minimap_hud and _minimap_hud.has_method("init"):
		_minimap_hud.init(_player)
	if _prompt_hud and _prompt_hud.has_method("init"):
		_prompt_hud.init(_player)
	if _powerup_hud and _powerup_hud.has_method("init"):
		_powerup_hud.init(_player)

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
		_world_light.light_energy = 0.05 if ThemeManager.is_dark_mode else 0.35

func _start_game() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_player.start()
	_menu_controller.close_menus()
	# Hide daily challenge HUD and card when entering museum normally (not via challenge)
	if _daily_challenge_hud and _daily_challenge_hud.has_method("hide_all"):
		_daily_challenge_hud.hide_all()
	if _daily_challenge_card and _daily_challenge_card.has_method("_hide_card"):
		_daily_challenge_card._hide_card()
	_map_overlay.restore_after_pause()
	if _minimap_hud and _minimap_hud.has_method("restore_after_pause"):
		_minimap_hud.restore_after_pause()
	if _connection_hud and _connection_hud.has_method("restore_after_pause"):
		_connection_hud.restore_after_pause()
	# PowerupHUD will auto-show when powerups are collected
	if not game_started:
		game_started = true
		_museum.init(_player)
		# Spawn the physical noticeboard in the lobby
		_spawn_daily_challenge_board()
	# Re-init lobby card for solo play only — never show in multiplayer
	if _daily_challenge_card and _daily_challenge_card.has_method("init"):
		if not _multiplayer_controller.is_multiplayer_game():
			_daily_challenge_card.init(_daily_challenge_manager, _daily_challenge_hud, _player, _daily_challenge_leaderboard, _start_game, _menu_layer)
		else:
			_daily_challenge_card.set_multiplayer_mode(true)

func _pause_game() -> void:
	_player.pause()
	if game_started:
		if _menu_layer.visible:
			return
		_menu_controller.open_pause_menu()
	else:
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

func _use_terminal() -> void:
	# Block terminal access during daily challenge to prevent cheating
	if _daily_challenge_manager and _daily_challenge_manager.is_active():
		if _chat_system:
			_chat_system._show_system_message("⚠ Terminal disabled during Daily Challenge")
		return
	if _minimap_hud and _minimap_hud.has_method("set_hidden"):
		_minimap_hud.set_hidden()
	if _connection_hud and _connection_hud.has_method("set_hidden"):
		_connection_hud.set_hidden()
	# Don't hide powerup HUD - players should still see their active powerups
	_minimap_mode = 0
	_player.pause()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_menu_controller.open_terminal_menu()

func _cycle_minimap() -> void:
	_minimap_mode = (_minimap_mode + 1) % 3
	match _minimap_mode:
		0: # Hidden
			if _minimap_hud and _minimap_hud.has_method("set_hidden"):
				_minimap_hud.set_hidden()
			if _connection_hud and _connection_hud.has_method("set_hidden"):
				_connection_hud.set_hidden()
			# NOTE: Do NOT touch _powerup_hud here — minimap cycling is independent
		1: # 3D Minimap
			if _minimap_hud and _minimap_hud.has_method("show_hud"):
				_minimap_hud.show_hud()
			if _connection_hud and _connection_hud.has_method("set_hidden"):
				_connection_hud.set_hidden()
			# NOTE: Do NOT touch _powerup_hud here — it manages its own visibility
		2: # Connection map
			if _minimap_hud and _minimap_hud.has_method("set_hidden"):
				_minimap_hud.set_hidden()
			if _connection_hud and _connection_hud.has_method("show_hud"):
				_connection_hud.show_hud()
			# NOTE: Do NOT touch _powerup_hud here

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

	# Host keybind: H = reveal next hint to all players during a race
	if event.is_action_pressed("reveal_hint") and not event.is_echo():
		var chat_open: bool = _chat_hud != null and _chat_hud.is_input_open()
		if not chat_open and NetworkManager.is_server() and RaceManager.is_race_active():
			var ok := RaceManager.reveal_hint_now()
			if not ok and _chat_system:
				_chat_system._show_system_message("⚠ No hints available.")
			get_viewport().set_input_as_handled()
			return

	# DEBUG: F10 = spawn powerup near player (multiplayer only)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		if NetworkManager.is_multiplayer_active():
			PowerupManager.debug_spawn_powerup_near_player()

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

			if event.is_action_pressed("toggle_powerups"):
				if _powerup_hud and _powerup_hud.has_method("toggle"):
					_powerup_hud.toggle()

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
				if _spectator_controller and _multiplayer_controller.is_multiplayer_game():
					if _spectator_controller.is_spectating():
						_spectator_controller.exit_spectator_mode()
					elif _multiplayer_controller.get_network_players().size() > 0:
						_spectator_controller.enter_spectator_mode(_player)
		
		# UI scale keyboard shortcuts — work in any state
		if event.is_action_pressed("ui_scale_in"):
			_adjust_ui_scale(0.1)
			get_viewport().set_input_as_handled()
		if event.is_action_pressed("ui_scale_out"):
			_adjust_ui_scale(-0.1)
			get_viewport().set_input_as_handled()
		if event.is_action_pressed("ui_scale_reset"):
			_adjust_ui_scale(0.0)
			get_viewport().set_input_as_handled()
		
		if event.is_action_pressed("pause"):
			if _minimap_hud and _minimap_hud.has_method("set_hidden"):
				_minimap_hud.set_hidden()
			if _connection_hud and _connection_hud.has_method("set_hidden"):
				_connection_hud.set_hidden()
			_minimap_mode = 0
			_pause_game()
		
		if event.is_action_pressed("free_pointer"):
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
		if event.is_action_pressed("click") and not _menu_layer.visible:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
				var overlay_open: bool = (_journal_overlay and _journal_overlay.is_open()) or (_guestbook_overlay and _guestbook_overlay.is_open()) or (_trivia_overlay and _trivia_overlay.is_open())
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
	_debug_log("Main: Race start requested by peer, fetching random articles for vote...")
	_race_candidates.clear()
	_race_start_article = ""
	_race_fetches_pending = RaceManager.CANDIDATE_COUNT + 1
	_show_vote_loading()
	_fetch_race_candidates()
	_fetch_race_start_article()

## Collects random articles for the vote pool. Winner = race target.
var _race_candidates: Array = []
var _race_start_article: String = ""  ## random article — where the lobby door opens
var _race_fetches_pending: int = 0
var _race_retry_count: int = 0
const MAX_RACE_RETRIES: int = 10

func _on_random_article_complete(title: Variant, context: Variant) -> void:
	if not context or not (context is Dictionary) or not context.has("race") or not context.race:
		return
	if title == null or title == " ":
		_race_retry_count += 1
		if _race_retry_count > MAX_RACE_RETRIES:
			Log.error("Main", "Too many fetch failures — giving up and launching with what we have")
			_race_retry_count = 0
			if _race_candidates.size() > 0:
				_launch_vote()
			return
		Log.error("Main", "Failed to fetch random article for race — retrying (%d/%d)" % [_race_retry_count, MAX_RACE_RETRIES])
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
			_debug_log("Main: Duplicate candidate '%s' — retrying" % title)
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
	## Fetches a completely random article as the starting point — ignores difficulty.
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
	## Host cancelled the vote — clear pending fetch state and return all players to pause menu.
	_race_candidates.clear()
	_race_start_article = ""
	_race_fetches_pending = 0
	_pause_game()

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

func _on_race_started(target_article: String, start_article: String) -> void:
	_debug_log("Main: Race started, sending all players to '%s'" % start_article)
	_debug_log("Main: Target article is '%s'" % target_article)
	# Clear backlink map from previous race and set start article to exclude from backlinks
	_museum._exhibit_loader.clear_backlink_map()
	_museum._exhibit_loader.set_race_start_article(start_article)
	_museum._exhibit_loader.set_race_target_article(target_article)
	# Server fetches backlinks to populate the hint pool
	if NetworkManager.is_server() and target_article != "":
		_debug_log("Main: Fetching backlinks for target '%s'..." % target_article)
		ExhibitFetcher.backlinks_complete.connect(_on_backlinks_for_hints, CONNECT_ONE_SHOT)
		ExhibitFetcher.fetch_backlinks(target_article, {"hints": true})
	
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

func _on_backlinks_for_hints(titles: Array, context: Dictionary) -> void:
	if not context.get("hints", false):
		return
	## The hint pool is the list of articles that LINK TO the target (backlinks).
	_debug_log("Main: Backlinks received for target '%s', count=%d" % [RaceManager.get_target_article(), titles.size()])
	
	# We deduplicate, strip blank entries, and exclude the start article.
	var seen: Dictionary = {}
	var filtered: Array = []
	var start_article = RaceManager.get_start_article()
	for t: String in titles:
		if t != "" and t != " " and t != start_article and not seen.has(t):
			seen[t] = true
			filtered.append(t)
	_debug_log("Main: Filtered to %d backlinks (excluded start article '%s')" % [filtered.size(), start_article])
	_debug_log("Main: Backlink list: %s" % str(filtered))
	
	RaceManager.set_hint_pool(filtered)
	# Store backlink titles in ExhibitLoader for proper exit linking
	_museum._exhibit_loader.set_backlink_titles(filtered)
	# Update existing exhibits that are in the backlink list
	_museum._exhibit_loader.update_backlink_exits(filtered, RaceManager.get_target_article())

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
	
	print("Main: _on_network_peer_connected - peer_id=%d, game_started=%s, is_multiplayer_game=%s" % [
		peer_id, game_started, _multiplayer_controller.is_multiplayer_game()
	])
	
	if _multiplayer_controller.is_multiplayer_game() and game_started:
		print("Main: Spawning network player for peer %d (game started)" % peer_id)
		_multiplayer_controller.spawn_network_player(peer_id)
	elif _multiplayer_controller.is_multiplayer_game() and not game_started:
		# Game hasn't started yet, but we should still track the player
		print("Main: Peer %d connected but game hasn't started yet" % peer_id)

	if NetworkManager.is_server():
		_notify_game_started.rpc_id(peer_id)
		
		# In dedicated host mode, first joiner gets race control
		if _is_ui_dedicated_host and _race_controller_peer_id == -1:
			_race_controller_peer_id = peer_id
			_grant_race_control.rpc_id(peer_id)

		# Sync placed paintings to late joiner so they see paintings placed
		# before they connected.
		if _painting_controller:
			var state: Array = _painting_controller.get_placed_paintings_state()
			if state.size() > 0:
				_sync_placed_paintings_to_peer.rpc_id(peer_id, state)
		
		# Sync stolen paintings to late joiner
		if _painting_controller:
			var stolen_state: Dictionary = _painting_controller.get_stolen_paintings_state()
			if not stolen_state.is_empty():
				_sync_stolen_paintings_to_peer.rpc_id(peer_id, stolen_state)

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

## Painting RPCs
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

@rpc("authority", "call_remote", "reliable")
func _sync_placed_paintings_to_peer(state: Array) -> void:
	## Received by a newly-joined client. Materialises all paintings that existed
	## before they connected.
	if _painting_controller:
		_painting_controller.apply_placed_paintings_state(state, _player)

@rpc("authority", "call_remote", "reliable")
func _sync_stolen_paintings_to_peer(state: Dictionary) -> void:
	## Received by a newly-joined client. Populates the stolen painting map.
	if _painting_controller:
		_painting_controller.apply_stolen_paintings_state(state)

## Syncs the race starting exhibit to all non-server peers so they also
## open the search door and load the starting article.
@rpc("authority", "call_remote", "reliable")
func _sync_race_start_article(start_article: String) -> void:
	_museum.reset_to_lobby()
	UIEvents.emit_set_custom_door(start_article)
	_start_game()

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
	## Player confirmed they want to race — load start article and go.
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

func _on_race_won_for_daily_challenge() -> void:
	## Fires when any race_won signal is received. If a daily challenge
	## is active, complete it and pop the results screen.
	if _daily_challenge_manager and _daily_challenge_manager.is_active():
		_daily_challenge_manager.complete_challenge()
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
	## SpectatorController dismissed itself — restore normal play.
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
	# Position it near the spawn — adjust these to suit your lobby layout
	_daily_challenge_board.board_position  = Vector3(2.5, 0.0, -2.0)
	_daily_challenge_board.board_rotation_y = -30.0
	_museum.add_child(_daily_challenge_board)
	if _daily_challenge_board.has_method("init"):
		_daily_challenge_board.init(_daily_challenge_manager, _daily_challenge_leaderboard)
