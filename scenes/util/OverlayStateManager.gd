extends Node
## Tracks blocking overlay states to prevent conflicts.
## Some overlays use is_open() (journal, trivia, daily challenge) — checked dynamically.
## Others (pause, settings, map) use explicit open/close tracking.

enum OverlayType {
	JOURNAL,
	MAP,
	TRIVIA,
	SETTINGS,
	PAUSE,
}

## Nodes that follow the is_open() pattern — checked dynamically at call time
var _dynamic_overlays: Array[Node] = []
## Explicitly tracked overlays (no is_open() method)
var _explicit_open: Array[OverlayType] = []


func _ready() -> void:
	add_to_group("overlay_state_manager")


func register_dynamic_overlay(node: Node) -> void:
	if not node in _dynamic_overlays:
		_dynamic_overlays.append(node)


func open_overlay(type: OverlayType) -> void:
	if not type in _explicit_open:
		_explicit_open.append(type)


func close_overlay(type: OverlayType) -> void:
	if type in _explicit_open:
		_explicit_open.erase(type)


func is_open(type: OverlayType) -> bool:
	if type in _explicit_open:
		return true
	match type:
		OverlayType.JOURNAL:
			return _any_dynamic_open("is_open")
		OverlayType.TRIVIA:
			return _any_dynamic_open("is_open")
	return false


func _any_dynamic_open(method: String) -> bool:
	for node in _dynamic_overlays:
		if is_instance_valid(node) and node.has_method(method) and node.call(method):
			return true
	return false


func is_any_blocking() -> bool:
	if not _explicit_open.is_empty():
		return true
	return _any_dynamic_open("is_open")


func get_open_types() -> Array[OverlayType]:
	var result := _explicit_open.duplicate()
	if _any_dynamic_open("is_open"):
		result.append(OverlayType.JOURNAL)
	return result
