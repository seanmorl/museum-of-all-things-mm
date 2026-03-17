extends Control
class_name MultiplayerMenu

signal back
signal start_game
signal open_tournament_setup  ## Emitted when host presses Wiki Races mode in lobby

static var default_server_address := "responsible-interactions.gl.at.ply.gg:18964"
const DEFAULT_HOST_NAME := "Host"
const DEFAULT_PLAYER_NAME := "Player"

enum MenuState { MAIN, HOST, JOIN, LOBBY }

var current_state: MenuState = MenuState.MAIN
var _serif_font: Font = null
var _panel_style: StyleBoxFlat = null
var _dedicated_host_btn: Button = null  # unused here, kept for parity
var _closing: bool = false
var _background: Control = null

# The single panel node that slides/fades (mirrors PauseMenu's _panel approach)
@onready var _panel = get_node_or_null("MarginContainer/Panel")
@onready var _inner_panel = get_node_or_null("MarginContainer/Panel")

@onready var _main_container = %MainContainer
@onready var _host_container = %HostContainer
@onready var _join_container = %JoinContainer
@onready var _lobby_container = %LobbyContainer

@onready var _host_port_input = %HostPortInput
@onready var _host_name_input = %HostNameInput
@onready var _host_color_picker = %HostColorPicker
@onready var _join_address_input = %JoinAddressInput
@onready var _join_port_input = %JoinPortInput
@onready var _join_name_input = %JoinNameInput
@onready var _join_color_picker = %JoinColorPicker
@onready var _player_list = %PlayerList
@onready var _lobby_title = %LobbyTitle
@onready var _start_button = %LobbyStartButton
@onready var _error_label = %ErrorLabel

# Pronoun UI - built in code, no scene changes needed
var _host_pronoun_option: OptionButton = null
var _host_pronoun_custom: LineEdit = null
var _join_pronoun_option: OptionButton = null
var _join_pronoun_custom: LineEdit = null
# Dividers
var _dividers: Array[Dictionary] = []
const _DIVIDERS_BY_CONTAINER := {
	"MainContainer": ["JoinButton", "BackButton"],
	"HostContainer": ["HostStartButton", "HostBackButton"],
	"JoinContainer": ["JoinConnectButton", "JoinBackButton"],
	"LobbyContainer": ["LobbyStartButton", "LobbyLeaveButton"]
}


func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	_spawn_background()

	# Build panel style identical to PauseMenu / VoteHUD
	if _inner_panel:
		var orig = _inner_panel.get_theme_stylebox("panel")
		_panel_style = orig.duplicate() if orig is StyleBoxFlat else StyleBoxFlat.new()
		_inner_panel.add_theme_stylebox_override("panel", _panel_style)

	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	MultiplayerEvents.multiplayer_started.connect(_on_multiplayer_started)

	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f): _serif_font = f; _apply_theme())

	_show_state(MenuState.MAIN)
	_setup_pronoun_dropdowns()
	_load_saved_identity()
	call_deferred("_build_dividers")
	_animate_in()


func _spawn_background() -> void:
	## Shared animated background — same script as MainMenu for visual continuity.
	var bg_script := load("res://scenes/menu/MainMenuBackground.gd")
	if not bg_script:
		return
	_background = Control.new()
	_background.name        = "Background"
	_background.set_script(bg_script)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	move_child(_background, 0)


func _on_visibility_changed() -> void:
	if visible:
		_closing = false
		_apply_theme()
		_show_state(MenuState.MAIN)
		_error_label.visible = false
		%HostButton.grab_focus()
		_animate_in()


# ── Theme & Styling ───────────────────────────────────────────────────────────
# All styling follows the exact same patterns as PauseMenu._apply_theme()
# and VoteHUD._apply_theme() so the three screens are visually consistent.

func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode

	if _inner_panel and _panel_style:
		_panel_style.bg_color = ThemeManager.bg_color
		_panel_style.border_color = ThemeManager.border_color

		for side in [0, 1, 2, 3]:
			_panel_style.set("border_width_" + ["left", "right", "top", "bottom"][side], 1)

		for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
			_panel_style.set("corner_radius_" + corner, 10)

		_panel_style.shadow_color = Color(0, 0, 0, 0.35 if dark else 0.12)
		_panel_style.shadow_size = 16
		_panel_style.shadow_offset = Vector2(0, 6)

	# Style all containers
	for container in [_main_container, _host_container, _join_container, _lobby_container]:
		_style_container_recursive(container)

	# Main title (Multiplayer) and section headings (Host Game, Join Game, Lobby)
	var main_title := _main_container.get_node_or_null("Title") if _main_container else null
	if main_title is Label:
		main_title.label_settings = null # Clear override from .tscn
		main_title.add_theme_color_override("font_color", ThemeManager.text_color)
		main_title.add_theme_font_size_override("font_size", 32)
		if _serif_font:
			main_title.add_theme_font_override("font", _serif_font)

	for container in [_host_container, _join_container]:
		if container:
			var heading: Node = container.get_node_or_null("Title")
			if heading is Label:
				heading.label_settings = null # Clear override from .tscn
				heading.add_theme_color_override("font_color", ThemeManager.text_color)
				heading.add_theme_font_size_override("font_size", 22)
				if _serif_font:
					heading.add_theme_font_override("font", _serif_font)
	if _lobby_title:
		_lobby_title.label_settings = null # Clear override from .tscn
		_lobby_title.add_theme_color_override("font_color", ThemeManager.text_color)
		_lobby_title.add_theme_font_size_override("font_size", 22)
		if _serif_font:
			_lobby_title.add_theme_font_override("font", _serif_font)

	# Error label (default neutral color; _show_error overrides to red when needed)
	if _error_label:
		_error_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
		if _serif_font:
			_error_label.add_theme_font_override("font", _serif_font)
		_error_label.add_theme_font_size_override("font_size", 13)

	for entry in _dividers:
		var line: ColorRect = entry["line"]
		if is_instance_valid(line):
			line.color = ThemeManager.border_color


func _style_container_recursive(container: Control) -> void:
	if not container:
		return
	for child in container.get_children():
		if child is Button:
			_style_button(child)
		elif child is LineEdit:
			_style_line_edit(child)
		elif child is OptionButton:
			_style_option_button(child)
		elif child is Label:
			_style_label(child)
		elif child is ItemList:
			_style_item_list(child)
		elif child is Control:
			_style_container_recursive(child)


# ── Dividers ──────────────────────────────────────────────────────────────────

func _build_dividers() -> void:
	if not _inner_panel: return
	for cont_name in _DIVIDERS_BY_CONTAINER:
		var container = get_node_or_null("%" + cont_name)
		if not container: continue
		for btn_name in _DIVIDERS_BY_CONTAINER[cont_name]:
			var btn = container.get_node_or_null(btn_name)
			if not btn: continue
			var line := ColorRect.new()
			line.name = "Div_" + cont_name + "_" + btn_name
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.color = ThemeManager.border_color
			_inner_panel.add_child(line)
			_dividers.append({"leader": btn, "line": line, "container": container})
	_update_dividers()


func _update_dividers() -> void:
	if not _inner_panel: return
	for entry in _dividers:
		var leader: Control = entry["leader"]
		var line: ColorRect  = entry["line"]
		var container: Control = entry["container"]
		if not is_instance_valid(leader) or not is_instance_valid(line):
			continue
		if not leader.visible or not container.visible:
			line.visible = false
			continue
		line.visible = true
		var y: float = leader.global_position.y - _inner_panel.global_position.y - 4.5
		line.position = Vector2(16.0, y)
		line.size     = Vector2(_inner_panel.size.x - 32.0, 1.0)


func _process(_delta: float) -> void:
	if visible and not _dividers.is_empty():
		_update_dividers()


func _style_label(lbl: Label) -> void:
	lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
	if _serif_font:
		lbl.add_theme_font_override("font", _serif_font)
	lbl.add_theme_font_size_override("font_size", 14)


func _style_item_list(list: ItemList) -> void:
	## Style the player list to match the panel's aesthetic.
	var dark := ThemeManager.is_dark_mode
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0.04) if dark else Color(ThemeManager.border_color, 0.18)
	sn.border_color = ThemeManager.border_color
	sn.border_width_left = 1
	sn.border_width_right = 1
	sn.border_width_top = 1
	sn.border_width_bottom = 1
	sn.set_corner_radius_all(6)
	sn.content_margin_left = 8
	sn.content_margin_right = 8
	sn.content_margin_top = 6
	sn.content_margin_bottom = 6
	list.add_theme_stylebox_override("panel", sn)
	list.add_theme_color_override("font_color", ThemeManager.text_color)
	if _serif_font:
		list.add_theme_font_override("font", _serif_font)
	list.add_theme_font_size_override("font_size", 15)


func _style_button(btn: Button) -> void:
	## Exact copy of PauseMenu._style_button for visual consistency.
	var dark := ThemeManager.is_dark_mode
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 17)

	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ThemeManager.text_color)
	btn.add_theme_color_override("font_disabled_color", ThemeManager.subtext_color)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0)
	sn.content_margin_left = 16
	sn.content_margin_right = 16
	sn.content_margin_top = 9
	sn.content_margin_bottom = 9
	btn.add_theme_stylebox_override("normal", sn)

	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(1, 1, 1, 0.06) if dark else Color(ThemeManager.border_color, 0.5)
	sh.set_corner_radius_all(5)
	sh.content_margin_left = 16
	sh.content_margin_right = 16
	sh.content_margin_top = 9
	sh.content_margin_bottom = 9
	btn.add_theme_stylebox_override("hover", sh)

	var sp := sh.duplicate() as StyleBoxFlat
	sp.bg_color = Color(1, 1, 1, 0.12) if dark else Color(ThemeManager.border_color, 0.85)
	btn.add_theme_stylebox_override("pressed", sp)

	var sf := sh.duplicate() as StyleBoxFlat
	sf.border_color = ThemeManager.text_color
	sf.border_width_left = 2
	btn.add_theme_stylebox_override("focus", sf)


func _style_line_edit(edit: LineEdit) -> void:
	## Exact copy of VoteHUD._style_vote_line_edit for visual consistency.
	var dark := ThemeManager.is_dark_mode
	if _serif_font:
		edit.add_theme_font_override("font", _serif_font)
	edit.add_theme_font_size_override("font_size", 15)

	edit.add_theme_color_override("font_color", ThemeManager.text_color)
	edit.add_theme_color_override("font_placeholder_color", ThemeManager.subtext_color)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0.03) if dark else Color(ThemeManager.border_color, 0.3)
	sn.border_color = ThemeManager.border_color
	sn.border_width_left = 1
	sn.border_width_right = 1
	sn.border_width_top = 1
	sn.border_width_bottom = 1
	sn.set_corner_radius_all(5)
	sn.content_margin_left = 12
	sn.content_margin_right = 12
	sn.content_margin_top = 8
	sn.content_margin_bottom = 8
	edit.add_theme_stylebox_override("normal", sn)

	var sf := sn.duplicate() as StyleBoxFlat
	sf.border_color = ThemeManager.text_color
	sf.border_width_left = 2
	sf.border_width_right = 2
	sf.border_width_top = 2
	sf.border_width_bottom = 2
	edit.add_theme_stylebox_override("focus", sf)


func _style_option_button(btn: OptionButton) -> void:
	ThemeManager.style_option_button(btn)
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
		btn.get_popup().add_theme_font_override("font", _serif_font)


# ── Animations ────────────────────────────────────────────────────────────────
# Mirrors PauseMenu._animate_in / _animate_out exactly.

func _animate_in() -> void:
	if _panel:
		_panel.modulate.a = 0.0
		_panel.position.y = 14.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.40).set_delay(0.10)
		tw.tween_property(_panel, "position:y", 0.0, 0.40).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.10)


func _animate_out(then: Callable) -> void:
	if _closing:
		return
	_closing = true
	if _panel:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_panel, "modulate:a", 0.0, 0.16)
		tw.tween_property(_panel, "position:y", 10.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(func():
			_closing = false
			then.call()
		)
	else:
		_closing = false
		then.call()


# ── State ─────────────────────────────────────────────────────────────────────

func _show_state(state: MenuState) -> void:
	current_state = state
	_main_container.visible = state == MenuState.MAIN
	_host_container.visible = state == MenuState.HOST
	_join_container.visible = state == MenuState.JOIN
	_lobby_container.visible = state == MenuState.LOBBY
	_error_label.visible = false

	match state:
		MenuState.MAIN:
			%HostButton.grab_focus()
		MenuState.HOST:
			_host_name_input.grab_focus()
		MenuState.JOIN:
			_join_name_input.grab_focus()
		MenuState.LOBBY:
			if NetworkManager.is_server():
				_start_button.grab_focus()
			else:
				%LobbyLeaveButton.grab_focus()


func _show_error(message: String) -> void:
	_error_label.text = message
	_error_label.visible = true
	# Red tint consistent with VoteHUD's cancel button colour
	_error_label.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))


func _update_player_list() -> void:
	_player_list.clear()
	for peer_id in NetworkManager.get_player_list():
		var player_name: String = NetworkManager.get_player_name(peer_id)
		var pronouns: String = NetworkManager.get_player_pronouns(peer_id)
		var pronoun_str: String = " (%s)" % pronouns if pronouns != "" else ""
		var suffix: String = " (Host)" if peer_id == 1 else ""
		var you_suffix: String = " (You)" if peer_id == NetworkManager.get_unique_id() else ""
		_player_list.add_item(player_name + pronoun_str + suffix + you_suffix)


# -- Pronoun UI ---------------------------------------------------------------

func _setup_pronoun_dropdowns() -> void:
	var options := [
		"(no pronouns)", "he/him", "she/her", "they/them",
		"he/they", "she/they", "any pronouns", "ask me", "custom..."
	]
	_host_pronoun_option = _build_pronoun_option(%HostContainer, _host_color_picker, options)
	_host_pronoun_custom = _build_pronoun_custom_field(%HostContainer, _host_pronoun_option)
	_host_pronoun_option.item_selected.connect(_on_host_pronoun_selected)

	_join_pronoun_option = _build_pronoun_option(%JoinContainer, _join_color_picker, options)
	_join_pronoun_custom = _build_pronoun_custom_field(%JoinContainer, _join_pronoun_option)
	_join_pronoun_option.item_selected.connect(_on_join_pronoun_selected)

	# Style the freshly built dropdowns
	_style_option_button(_host_pronoun_option)
	_style_option_button(_join_pronoun_option)
	if _host_pronoun_custom:
		_style_line_edit(_host_pronoun_custom)
	if _join_pronoun_custom:
		_style_line_edit(_join_pronoun_custom)


func _build_pronoun_option(container: Control, after_node: Control, options: Array) -> OptionButton:
	var hbox := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Pronouns:"
	hbox.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in options:
		opt.add_item(item)
	hbox.add_child(opt)
	container.add_child(hbox)
	container.move_child(hbox, after_node.get_index() + 1)
	return opt


func _build_pronoun_custom_field(container: Control, after_opt: OptionButton) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = "enter your pronouns..."
	field.visible = false
	container.add_child(field)
	container.move_child(field, after_opt.get_parent().get_index() + 1)
	return field


func _on_host_pronoun_selected(index: int) -> void:
	_host_pronoun_custom.visible = _host_pronoun_option.get_item_text(index) == "custom..."


func _on_join_pronoun_selected(index: int) -> void:
	_join_pronoun_custom.visible = _join_pronoun_option.get_item_text(index) == "custom..."


func _get_pronouns_from(option: OptionButton, custom_field: LineEdit) -> String:
	var selected := option.get_item_text(option.selected)
	if selected == "(no pronouns)":
		return ""
	if selected == "custom...":
		return custom_field.text.strip_edges()
	return selected


func _save_identity(host_name: String, join_name: String, color: Color, pronouns: String) -> void:
	SettingsManager.save_settings("multiplayer_identity", {
		"host_name": host_name,
		"join_name": join_name,
		"color": color.to_html(),
		"pronouns": pronouns,
	})


func _load_saved_identity() -> void:
	var saved = SettingsManager.get_settings("multiplayer_identity")
	if not saved:
		return
	if saved.has("host_name"):
		_host_name_input.text = saved.host_name
	if saved.has("join_name"):
		_join_name_input.text = saved.join_name
	if saved.has("color"):
		var c := Color.html(saved.color)
		_host_color_picker.color = c
		_join_color_picker.color = c
	if saved.has("pronouns"):
		_set_pronoun_dropdown(_host_pronoun_option, _host_pronoun_custom, saved.pronouns)
		_set_pronoun_dropdown(_join_pronoun_option, _join_pronoun_custom, saved.pronouns)


func _set_pronoun_dropdown(option: OptionButton, custom_field: LineEdit, value: String) -> void:
	for i in option.item_count:
		if option.get_item_text(i) == value:
			option.selected = i
			custom_field.visible = false
			return
	if value != "":
		for i in option.item_count:
			if option.get_item_text(i) == "custom...":
				option.selected = i
				custom_field.text = value
				custom_field.visible = true
				return


func show_disconnected_message() -> void:
	_show_error("Disconnected from server")


# -- Main menu buttons --------------------------------------------------------

func _on_host_pressed() -> void:
	_show_state(MenuState.HOST)
	_host_port_input.text = str(NetworkManager.DEFAULT_PORT)
	_host_name_input.text = DEFAULT_HOST_NAME

func _on_join_pressed() -> void:
	_show_state(MenuState.JOIN)
	_join_address_input.text = default_server_address
	_join_address_input.placeholder_text = "host:port  or  hostname"
	_join_port_input.text = ""
	_join_name_input.text = DEFAULT_PLAYER_NAME

func _on_back_pressed() -> void:
	if current_state == MenuState.MAIN:
		_animate_out(func(): back.emit())
	else:
		_show_state(MenuState.MAIN)


# -- Host menu buttons --------------------------------------------------------

func _on_host_start_pressed() -> void:
	var port_str: String = _host_port_input.text.strip_edges()
	
	# Validate port input
	if not port_str.is_valid_int():
		_show_error("Port must be a number")
		return
	
	var port: int = int(port_str)
	if port <= 0 or port > 65535:
		_show_error("Invalid port number (must be 1-65535)")
		return

	var host_pronouns := _get_pronouns_from(_host_pronoun_option, _host_pronoun_custom)
	NetworkManager.set_local_player_name(_host_name_input.text)
	NetworkManager.set_local_player_color(_host_color_picker.color)
	NetworkManager.set_local_player_pronouns(host_pronouns)
	_save_identity(_host_name_input.text, _join_name_input.text, _host_color_picker.color, host_pronouns)

	var error := NetworkManager.host_game(port)
	if error != OK:
		_show_error("Failed to start server: " + str(error))
		return

	_lobby_title.text = "Lobby (Hosting)"
	_start_button.visible = true
	_update_player_list()
	_show_state(MenuState.LOBBY)
	_add_tournament_button()

func _on_host_back_pressed() -> void:
	_show_state(MenuState.MAIN)


func _on_join_back_pressed() -> void:
	_show_state(MenuState.MAIN)


# -- Join menu buttons --------------------------------------------------------

func _on_join_connect_pressed() -> void:
	var raw: String = _join_address_input.text.strip_edges()

	if raw.is_empty():
		_show_error("Please enter an address")
		return

	var address: String
	var port: int

	if ":" in raw and not raw.begins_with("["):
		var colon: int = raw.rfind(":")
		address = raw.substr(0, colon).strip_edges()
		var port_str: String = raw.substr(colon + 1).strip_edges()
		
		# Validate port from address
		if not port_str.is_valid_int():
			_show_error("Port in address must be a number")
			return
		port = int(port_str)
	else:
		address = raw
		var port_str: String = _join_port_input.text.strip_edges()
		
		# Validate port input
		if not port_str.is_valid_int():
			_show_error("Port must be a number")
			return
		port = int(port_str)

	if address.is_empty():
		_show_error("Please enter an address")
		return

	if port <= 0 or port > 65535:
		_show_error("Invalid port number (must be 1-65535)")
		return

	var join_pronouns := _get_pronouns_from(_join_pronoun_option, _join_pronoun_custom)
	NetworkManager.set_local_player_name(_join_name_input.text)
	NetworkManager.set_local_player_color(_join_color_picker.color)
	NetworkManager.set_local_player_pronouns(join_pronouns)
	_save_identity(_host_name_input.text, _join_name_input.text, _join_color_picker.color, join_pronouns)

	%JoinConnectButton.disabled = true
	_error_label.text    = "Connecting to %s..." % address
	_error_label.visible = true
	# Neutral colour while connecting (not red)
	_error_label.add_theme_color_override("font_color", ThemeManager.subtext_color)

	# Connect with timeout (10 seconds) - simplified approach
	var timeout_timer := get_tree().create_timer(10.0)
	var join_complete := false
	var error: Error = OK
	
	# Start join operation in background
	var join_task := func():
		error = await NetworkManager.join_game(address, port)
		join_complete = true
	
	# Start the task
	join_task.call_deferred()
	
	# Wait for completion or timeout
	while not join_complete and timeout_timer.time_left > 0:
		await get_tree().process_frame
	
	%JoinConnectButton.disabled = false
	
	if not join_complete:
		# Timeout
		NetworkManager.close_connection()
		_show_error("Connection timed out. Server may be offline or address is incorrect.")
		return
	
	if error != OK:
		_show_error("Failed to connect: " + error_string(error))
		return

# -- Lobby buttons ------------------------------------------------------------

func _on_lobby_start_pressed() -> void:
	if NetworkManager.is_server():
		_start_multiplayer_game.rpc()

func _on_lobby_leave_pressed() -> void:
	# Let Main._on_multiplayer_menu_back handle full session teardown
	back.emit()


# -- Network callbacks --------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	_update_player_list()

func _add_tournament_button() -> void:
	## Adds the Wiki Races button to the lobby — host only.
	## Idempotent: safe to call multiple times.
	if not _lobby_container:
		return
	if _lobby_container.get_node_or_null("TournamentButton"):
		return  # already added
	var btn := Button.new()
	btn.name = "TournamentButton"
	btn.text = "🏆  Wiki Races"
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_button(btn)
	# Show a visual distinction when a tournament is already running
	if TournamentManager.is_active():
		btn.text = "🏆  Wiki Races — Round %d/%d" % [
			TournamentManager.get_current_round(),
			TournamentManager.get_total_rounds()
		]
	btn.pressed.connect(func():
		if TournamentManager.is_active():
			# Give the host a cancel option instead
			_show_tournament_cancel_confirm()
		else:
			open_tournament_setup.emit()
	)
	_lobby_container.add_child(btn)
	# Position above the Leave button
	var leave := _lobby_container.get_node_or_null("LobbyLeaveButton")
	if leave:
		_lobby_container.move_child(btn, leave.get_index())
	# Update button text if tournament state changes while menu is open
	TournamentManager.tournament_started.connect(func(_cfg):
		if is_instance_valid(btn):
			btn.text = "🏆  Wiki Races — Starting"
	, CONNECT_ONE_SHOT)
	TournamentManager.tournament_cancelled.connect(func():
		if is_instance_valid(btn):
			btn.text = "🏆  Wiki Races"
	)


func _show_tournament_cancel_confirm() -> void:
	## Simple confirm dialog so the host doesn't accidentally cancel a running tournament.
	var dialog_node := _lobby_container.get_node_or_null("TournamentCancelConfirm")
	if dialog_node:
		dialog_node.queue_free()
		return
	var hbox := HBoxContainer.new()
	hbox.name = "TournamentCancelConfirm"
	hbox.add_theme_constant_override("separation", 6)
	_lobby_container.add_child(hbox)
	var leave := _lobby_container.get_node_or_null("LobbyLeaveButton")
	if leave:
		_lobby_container.move_child(hbox, leave.get_index())
	var lbl := Label.new()
	lbl.text = "Cancel Wiki Races?"
	lbl.add_theme_color_override("font_color", Color(0.85, 0.25, 0.25))
	if _serif_font: lbl.add_theme_font_override("font", _serif_font)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)
	var yes_btn := Button.new()
	yes_btn.text = "Yes"
	yes_btn.pressed.connect(func():
		TournamentManager.host_cancel_tournament()
		hbox.queue_free()
	)
	_style_button(yes_btn)
	hbox.add_child(yes_btn)
	var no_btn := Button.new()
	no_btn.text = "No"
	no_btn.pressed.connect(func(): hbox.queue_free())
	_style_button(no_btn)
	hbox.add_child(no_btn)


func _on_peer_disconnected(_id: int) -> void:
	_update_player_list()

func _on_connection_succeeded() -> void:
	_lobby_title.text = "Lobby (Connected)"
	_start_button.visible = false
	_update_player_list()
	_show_state(MenuState.LOBBY)

func _on_connection_failed() -> void:
	_show_error("Connection failed")
	_show_state(MenuState.JOIN)

func _on_server_disconnected() -> void:
	_show_error("Disconnected from server")
	_show_state(MenuState.MAIN)

func _on_multiplayer_started() -> void:
	if current_state == MenuState.LOBBY and not NetworkManager.is_server():
		start_game.emit()


@rpc("authority", "call_local", "reliable")
func _start_multiplayer_game() -> void:
	MultiplayerEvents.emit_multiplayer_started()
	start_game.emit()
