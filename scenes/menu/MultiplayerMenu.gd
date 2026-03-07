extends Control
class_name MultiplayerMenu

signal back
signal start_game

static var default_server_address := "responsible-interactions.gl.at.ply.gg:18964"
const DEFAULT_HOST_NAME := "Host"
const DEFAULT_PLAYER_NAME := "Player"

enum MenuState { MAIN, HOST, JOIN, LOBBY }

var current_state: MenuState = MenuState.MAIN

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


func _ready() -> void:
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	MultiplayerEvents.multiplayer_started.connect(_on_multiplayer_started)

	_show_state(MenuState.MAIN)
	_setup_pronoun_dropdowns()
	_load_saved_identity()


func _on_visibility_changed() -> void:
	if visible:
		_show_state(MenuState.MAIN)
		_error_label.visible = false
		%HostButton.grab_focus()


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
		back.emit()
	else:
		_show_state(MenuState.MAIN)


# -- Host menu buttons --------------------------------------------------------

func _on_host_start_pressed() -> void:
	var port := int(_host_port_input.text)
	if port <= 0 or port > 65535:
		_show_error("Invalid port number")
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

func _on_host_back_pressed() -> void:
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
		var colon := raw.rfind(":")
		address = raw.substr(0, colon).strip_edges()
		port    = int(raw.substr(colon + 1).strip_edges())
	else:
		address = raw
		port    = int(_join_port_input.text)

	if address.is_empty():
		_show_error("Please enter an address")
		return

	if port <= 0 or port > 65535:
		_show_error("Invalid port number (got %d)" % port)
		return

	var join_pronouns := _get_pronouns_from(_join_pronoun_option, _join_pronoun_custom)
	NetworkManager.set_local_player_name(_join_name_input.text)
	NetworkManager.set_local_player_color(_join_color_picker.color)
	NetworkManager.set_local_player_pronouns(join_pronouns)
	_save_identity(_host_name_input.text, _join_name_input.text, _join_color_picker.color, join_pronouns)

	%JoinConnectButton.disabled = true
	_error_label.text    = "Resolving %s..." % address
	_error_label.visible = true
	_error_label.modulate = Color(0.7, 0.7, 0.7, 1.0)

	var error: Error = await NetworkManager.join_game(address, port)

	%JoinConnectButton.disabled = false
	_error_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

	if error != OK:
		_show_error("Failed to connect: " + error_string(error))
		return

func _on_join_back_pressed() -> void:
	_show_state(MenuState.MAIN)


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
