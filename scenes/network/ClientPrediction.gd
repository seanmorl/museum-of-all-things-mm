extends RefCounted
## Client-side prediction system for smooth player movement in multiplayer.
## Stores input commands and applies local prediction before server confirmation.

class InputCommand:
	var sequence_number: int
	var timestamp: float
	var input_direction: Vector2
	var jump_pressed: bool
	var crouch_pressed: bool
	var dash_pressed: bool
	
	func _init(seq: int, time: float, direction: Vector2, jump: bool, crouch: bool, dash: bool):
		self.sequence_number = seq
		self.timestamp = time
		self.input_direction = direction
		self.jump_pressed = jump
		self.crouch_pressed = crouch
		self.dash_pressed = dash

# Input command queue for reconciliation
var _input_queue: Array[InputCommand] = []
var _last_sequence_number: int = 0
var _last_confirmed_sequence: int = 0

# Server state for reconciliation
var _server_position: Vector3 = Vector3.ZERO
var _server_velocity: Vector3 = Vector3.ZERO
var _server_sequence: int = 0
var _has_server_state: bool = false

# Prediction settings
# NOTE: Reconciliation is disabled by default in host-authoritative mode.
# The host is the source of truth for game state; clients trust the host's
# corrections. Full reconciliation would require storing physics state per
# input frame, which is expensive. See apply_reconciliation() for details.
var _reconciliation_enabled: bool = false
var _max_rewind_frames: int = 20
var _position_error_threshold: float = 0.5  # Snap if error > this

signal server_state_received(sequence: int, position: Vector3, velocity: Vector3)

func get_next_sequence_number() -> int:
	_last_sequence_number += 1
	return _last_sequence_number

func queue_input_command(direction: Vector2, jump: bool, crouch: bool, dash: bool) -> InputCommand:
	var cmd = InputCommand.new(
		get_next_sequence_number(),
		Time.get_ticks_msec() / 1000.0,
		direction,
		jump,
		crouch,
		dash
	)
	_input_queue.append(cmd)
	
	# Limit queue size
	if _input_queue.size() > _max_rewind_frames:
		_input_queue.pop_front()
	
	return cmd

func process_server_state(sequence: int, position: Vector3, velocity: Vector3) -> void:
	"""Process server state and perform reconciliation"""
	_server_position = position
	_server_velocity = velocity
	_server_sequence = sequence
	_has_server_state = true
	_last_confirmed_sequence = sequence
	
	# Remove all commands up to and including the confirmed sequence
	while _input_queue.size() > 0 and _input_queue[0].sequence_number <= sequence:
		_input_queue.pop_front()
	
	server_state_received.emit(sequence, position, velocity)

func get_commands_to_send() -> Array[InputCommand]:
	"""Get unconfirmed commands to send to server"""
	return _input_queue.duplicate()

func needs_reconciliation(local_position: Vector3) -> bool:
	"""Check if local position diverges too much from server"""
	if not _has_server_state or not _reconciliation_enabled:
		return false
	
	var error = local_position.distance_to(_server_position)
	return error > _position_error_threshold

func apply_reconciliation(player: Node3D) -> Vector3:
	"""Apply server reconciliation - rewind and replay inputs"""
	if not _has_server_state or _input_queue.is_empty():
		return _server_position

	# Reconciliation is disabled by default. A full implementation would:
	# 1. Save physics state snapshots each frame
	# 2. Restore to server position + velocity
	# 3. Replay each input command through the physics step
	# This is expensive and unnecessary in host-authoritative mode where
	# the host sends periodic position that clients snap to.
	#
	# The simplified approach: just snap to server position if divergence
	# exceeds threshold (checked in needs_reconciliation).

	return _server_position

func reset() -> void:
	"""Reset all state"""
	_input_queue.clear()
	_last_sequence_number = 0
	_last_confirmed_sequence = 0
	_has_server_state = false
	_server_position = Vector3.ZERO
	_server_velocity = Vector3.ZERO

func set_reconciliation_enabled(enabled: bool) -> void:
	_reconciliation_enabled = enabled

func is_reconciliation_enabled() -> bool:
	return _reconciliation_enabled
