extends Node
class_name MainMenuController
## Handles menu navigation, opening/closing, and navigation stack.
## WCAG 2.4.7: Restores keyboard focus when transitioning between
## menus so the visible focus indicator always reflects the current
## interactive element.

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
        _trigger_main_menu_entrance()


func open_pause_menu() -> void:
        open_menu(Menu.PAUSE)


func open_settings_menu() -> void:
        open_menu(Menu.SETTINGS)


func open_terminal_menu() -> void:
        open_menu(Menu.TERMINAL)

func is_terminal_open() -> bool:
        if _menu_layer == null or not _menu_layer.visible:
                return false
        var terminal_node = _menu_layer.get_node_or_null("PopupTerminalMenu")
        return terminal_node != null and terminal_node.visible

func open_multiplayer_menu() -> void:
        open_menu(Menu.MULTIPLAYER)


func is_menu_visible() -> bool:
        return _menu_layer.visible


func _trigger_main_menu_entrance() -> void:
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


# ── WCAG 2.4.7: Focus Restoration ────────────────────────────────────────────

func _restore_focus_to_menu(menu_node: Control) -> void:
        """Try the menu's _grab_initial_focus, or fall back to finding
        the first focusable child."""
        if not menu_node:
                return
        if menu_node.has_method("_grab_initial_focus"):
                menu_node.call("_grab_initial_focus")
                return
        _restore_focus_recursive(menu_node)


func _restore_focus_recursive(node: Node) -> bool:
        """Find the first visible Control with focus_mode != FOCUS_NONE."""
        if node is Control:
                var ctrl = node as Control
                if ctrl.focus_mode != Control.FOCUS_NONE and ctrl.visible:
                        ctrl.grab_focus()
                        return true
        for child in node.get_children():
                if _restore_focus_recursive(child):
                        return true
        return false


func _grab_focus_on_visible_menu() -> void:
        """Restore focus to whichever menu is currently visible."""
        if not _menu_layer or not _menu_layer.visible:
                return

        var main_menu = _menu_layer.get_node_or_null("MainMenu")
        var pause_menu = _menu_layer.get_node_or_null("PauseMenu")

        if main_menu and main_menu.visible:
                _restore_focus_to_menu(main_menu)
        elif pause_menu and pause_menu.visible:
                _restore_focus_recursive(pause_menu)


func on_main_menu_settings() -> void:
        _menu_nav_queue.append(open_main_menu)
        # Feature 9: Use MainMenu's transition animation if available
        var main_menu := _menu_layer.get_node_or_null("MainMenu") if _menu_layer else null
        if main_menu and main_menu.has_method("transition_to"):
                main_menu.transition_to(open_settings_menu)
        else:
                open_settings_menu()


func on_main_menu_start_pressed() -> void:
        # Feature 9: Use transition animation
        var main_menu := _menu_layer.get_node_or_null("MainMenu") if _menu_layer else null
        if main_menu and main_menu.has_method("transition_to"):
                main_menu.transition_to(func(): game_start_requested.emit())
        else:
                game_start_requested.emit()


func on_pause_menu_settings() -> void:
        _menu_nav_queue.append(open_pause_menu)
        open_settings_menu()


func on_main_menu_multiplayer() -> void:
        _menu_nav_queue.append(open_main_menu)
        # Feature 9: Use transition animation
        var main_menu := _menu_layer.get_node_or_null("MainMenu") if _menu_layer else null
        if main_menu and main_menu.has_method("transition_to"):
                main_menu.transition_to(open_multiplayer_menu)
        else:
                open_multiplayer_menu()


func on_multiplayer_menu_back() -> void:
        var prev: Callable = _menu_nav_queue.pop_back()
        if prev:
                prev.call()
                _grab_focus_on_visible_menu()
        else:
                open_main_menu()


func on_settings_back() -> void:
        var prev: Callable = _menu_nav_queue.pop_back()
        if prev:
                prev.call()
                _grab_focus_on_visible_menu()
        else:
                open_main_menu()


func on_multiplayer_start_game() -> void:
        multiplayer_start_requested.emit()
