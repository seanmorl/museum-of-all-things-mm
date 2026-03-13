extends Node
## Centralized event bus for decoupled communication between systems.
## Replace direct signal connections with event publish/subscribe.

# --- Event Classes ---
class GameEvent:
	pass

class StateChangedEvent extends GameEvent:
	var old_state: GameState.State
	var new_state: GameState.State
	var sub_state: GameState.SubState
	
	func _init(o: GameState.State, n: GameState.State, s: GameState.SubState) -> void:
		old_state = o
		new_state = n
		sub_state = s

class RaceStartedEvent extends GameEvent:
	var target: String
	var start: String
	
	func _init(t: String, s: String) -> void:
		target = t
		start = s

class RaceFinishedEvent extends GameEvent:
	var winner: String
	var time: float
	
	func _init(w: String, t: float) -> void:
		winner = w
		time = t

class VoteStartedEvent extends GameEvent:
	var candidates: Array[String]
	var deadline: float
	
	func _init(c: Array[String], d: float) -> void:
		candidates = c
		deadline = d

class VoteEndedEvent extends GameEvent:
	var winner: String
	
	func _init(w: String) -> void:
		winner = w

class CountdownStartedEvent extends GameEvent:
	pass

class CountdownTickEvent extends GameEvent:
	var number: int
	
	func _init(n: int) -> void:
		number = n

class ExhibitLoadedEvent extends GameEvent:
	var title: String
	
	func _init(t: String) -> void:
		title = t

class DoorOpenedEvent extends GameEvent:
	var target: String
	
	func _init(t: String) -> void:
		target = t

class PlayerMovedEvent extends GameEvent:
	var peer_id: int
	var room: String
	var position: Vector3
	
	func _init(p: int, r: String, pos: Vector3) -> void:
		peer_id = p
		room = r
		position = pos

class NetworkPeerConnectedEvent extends GameEvent:
	var peer_id: int
	
	func _init(p: int) -> void:
		peer_id = p

class NetworkPeerDisconnectedEvent extends GameEvent:
	var peer_id: int
	
	func _init(p: int) -> void:
		peer_id = p

# --- Event Bus Implementation ---

signal event_published(event: GameEvent)

var _subscribers: Dictionary = {}  # event_class -> Array[Callable]

func _ready() -> void:
	# Don't remove this - EventBus is autoloaded
	pass

func subscribe(event_class: GDScript, callback: Callable) -> void:
	"""Subscribe to an event type.
	
Usage:
	EventBus.subscribe(RaceStartedEvent, _on_race_started)
	"""
	if not _subscribers.has(event_class):
		_subscribers[event_class] = []
	_subscribers[event_class].append(callback)

func unsubscribe(event_class: GDScript, callback: Callable) -> void:
	"""Unsubscribe from an event type."""
	if _subscribers.has(event_class):
		var idx = _subscribers[event_class].find(callback)
		if idx >= 0:
			_subscribers[event_class].remove_at(idx)

func publish(event: GameEvent) -> void:
	"""Publish an event to all subscribers."""
	event_published.emit(event)
	
	var event_class = event.get_class()
	if _subscribers.has(event_class):
		for callback: Callable in _subscribers[event_class]:
			# Call in next frame to avoid reentrancy issues
			call_deferred("_invoke_callback", callback, event)

func _invoke_callback(callback: Callable, event: GameEvent) -> void:
	if callback.is_valid():
		callback.call(event)

# --- Convenience Methods ---

func publish_state_changed(old: GameState.State, new: GameState.State, sub: GameState.SubState) -> void:
	publish(StateChangedEvent.new(old, new, sub))

func publish_race_started(target: String, start: String) -> void:
	publish(RaceStartedEvent.new(target, start))

func publish_race_finished(winner: String, time: float) -> void:
	publish(RaceFinishedEvent.new(winner, time))

func publish_vote_started(candidates: Array[String], deadline: float) -> void:
	publish(VoteStartedEvent.new(candidates, deadline))

func publish_vote_ended(winner: String) -> void:
	publish(VoteEndedEvent.new(winner))

func publish_countdown_started() -> void:
	publish(CountdownStartedEvent.new())

func publish_countdown_tick(number: int) -> void:
	publish(CountdownTickEvent.new(number))

func publish_exhibit_loaded(title: String) -> void:
	publish(ExhibitLoadedEvent.new(title))

func publish_door_opened(target: String) -> void:
	publish(DoorOpenedEvent.new(target))

func publish_player_moved(peer_id: int, room: String, position: Vector3) -> void:
	publish(PlayerMovedEvent.new(peer_id, room, position))
