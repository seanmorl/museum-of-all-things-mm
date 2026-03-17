extends Node
class_name MainMenuController
## Handles menu navigation, opening/closing, and navigation stack.

enum Menu { NONE, MAIN, PAUSE, SETTINGS, TERMINAL, MULTIPLAYER }

signal game_start_requested
signal multiplayer_start_requested

var _main: Node = null
var _menu_layer: CanvasLayer = null
var _menu_nav_queue: Array = []


func init(main: Node, canvas_layer: CanvasLayer) -> void:
	_main = main
	_menu_layer = canvas_layer


func get_nav_queue() -> Array:
	return _menu_nav_queue


func open_menu(menu: Menu) -> void:
	_menu_layer.visible = menu != Menu.NONE
	var main_menu = _menu_layer.get_node_or_null("MainMenu")
	var pause_menu = _menu_layer.get_node_or_null("PauseMenu")
	var settings_menu = _menu_layer.get_node_or_null("Settings")
	var terminal_menu = _menu_layer.get_node_or_null("PopupTerminalMenu")
	var multiplayer_menu = _menu_layer.get_node_or_null("MultiplayerMenu")
	
	if main_menu: main_menu.visible = menu == Menu.MAIN
	if pause_menu: pause_menu.visible = menu == Menu.PAUSE
	if settings_menu: settings_menu.visible = menu == Menu.SETTINGS
	if terminal_menu: terminal_menu.visible = menu == Menu.TERMINAL
	if multiplayer_menu: multiplayer_menu.visible = menu == Menu.MULTIPLAYER


func close_menus() -> void:
	open_menu(Menu.NONE)


func open_main_menu() -> void:
	open_menu(Menu.MAIN)
	# Trigger entrance animation when opening main menu
	_trigger_main_menu_entrance()


func open_pause_menu() -> void:
	open_menu(Menu.PAUSE)


func open_settings_menu() -> void:
	open_menu(Menu.SETTINGS)


func open_terminal_menu() -> void:
	open_menu(Menu.TERMINAL)

func is_terminal_open() -> bool:
	"""Check if terminal menu is currently open."""
	if _menu_layer == null or not _menu_layer.visible:
		return false
	var terminal_node = _menu_layer.get_node_or_null("PopupTerminalMenu")
	return terminal_node != null and terminal_node.visible

func open_multiplayer_menu() -> void:
	open_menu(Menu.MULTIPLAYER)


func is_menu_visible() -> bool:
	return _menu_layer.visible


func _trigger_main_menu_entrance() -> void:
	"""Re-trigger the Main Menu entrance animation when returning from sub-menus."""
	if not _menu_layer:
		push_warning("MainMenuController: _menu_layer is null")
		return
	var main_menu := _menu_layer.get_node_or_null("MainMenu")
	if not main_menu:
		push_warning("MainMenuController: MainMenu node not found in _menu_layer")
		return
	if not main_menu.visible:
		push_warning("MainMenuController: MainMenu is not visible when trying to trigger entrance animation")
	if not main_menu.has_method("_entrance_animation"):
		push_warning("MainMenuController: MainMenu does not have _entrance_animation method")
		return
	main_menu.call("_entrance_animation")


func on_main_menu_settings() -> void:
	_menu_nav_queue.append(open_main_menu)
	open_settings_menu()


func on_main_menu_start_pressed() -> void:
	# Start game directly from main menu
	game_start_requested.emit()


func on_pause_menu_settings() -> void:
	_menu_nav_queue.append(open_pause_menu)
	open_settings_menu()


func on_main_menu_multiplayer() -> void:
	_menu_nav_queue.append(open_main_menu)
	open_multiplayer_menu()


func on_multiplayer_menu_back() -> void:
	var prev: Callable = _menu_nav_queue.pop_back()
	if prev:
		prev.call()
	else:
		open_main_menu()


func on_settings_back() -> void:
	var prev: Callable = _menu_nav_queue.pop_back()
	if prev:
		prev.call()
	else:
		open_main_menu()


func on_multiplayer_start_game() -> void:
	multiplayer_start_requested.emit()
