extends RefCounted
class_name EventBase
## Base class for all environmental events in MoAT.
## Provides:
## - Static registry so EventManager auto-discovers new events
## - Scene/node access helpers to avoid repeating Engine.get_main_loop() calls
## - Default implementations for required interface
##
## To create a new event, extend this class and implement:
##   get_duration() -> float  (or keep 0 for instant)
##   get_display_name() -> String
##   get_description() -> String
##   apply()           (called when event starts)
##   end()             (called when event ends)
##
## The event is auto-registered via the static registry below.

static var _registry: Array[Script] = []

## Override in subclass to return duration in seconds (0 = instant)
static func get_duration() -> float:
	return 0.0

## Override in subclass to return display name
static func get_display_name() -> String:
	return "Unknown Event"

## Override in subclass to return description
static func get_description() -> String:
	return ""

## Override in subclass to apply the event effect
static func apply() -> void:
	pass

## Override in subclass to clean up the event effect
static func end() -> void:
	pass

static func get_registered_events() -> Array[Script]:
	return _registry.duplicate()

static func _auto_register(script: Script) -> void:
	if not script in _registry:
		_registry.append(script)

## Returns the current scene (Museum or MainMenu)
static func get_scene() -> Node:
	return Engine.get_main_loop().current_scene

## Returns the local player node (or null)
static func get_local_player() -> Node:
	var tree := Engine.get_main_loop()
	if tree:
		return tree.current_scene.get_tree().get_first_node_in_group("local_player")
	return null

## Returns all nodes in a group, or empty array if none
static func get_group_nodes(group: String) -> Array[Node]:
	var tree := Engine.get_main_loop()
	if tree and tree.current_scene:
		return tree.current_scene.get_tree().get_nodes_in_group(group)
	return []

## Returns first node in a group, or null
static func get_first_group_node(group: String) -> Node:
	var tree := Engine.get_main_loop()
	if tree and tree.current_scene:
		return tree.current_scene.get_tree().get_first_node_in_group(group)
	return null

## Check if race is currently active
static func is_race_active() -> bool:
	return RaceManager.is_race_active()

## Returns the museum node (or null)
static func get_museum() -> Node:
	var scene := get_scene()
	if scene:
		return scene.get_node_or_null("Museum")
	return null

## Log a debug message with event name prefix
static func debug(msg: String) -> void:
	Log.debug(get_display_name(), msg)