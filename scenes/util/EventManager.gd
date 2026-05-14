extends Node
## EventManager - Server-authoritative environmental event system
## All players experience the same events simultaneously

signal event_started(event_type: int, duration: float)
signal event_ended(event_type: int)
signal event_warning(event_type: int)  # Emitted 2s before event starts

enum EventType {
	NONE,
	# Visual & Atmosphere
	DARKNESS,
	COLOR_SHIFT,
	FOG,
	EARTHQUAKE,
	WEATHER_SYSTEM,
	# Movement Modifiers
	SPEED_UP,
	HEAVY_GRAVITY,
	NO_RUNNING,
	DOUBLE_JUMP,
	TRIPLE_JUMP,
	BACKWARDS_CONTROLS,
	LOW_GRAVITY,
	FLYING_ARTWORK,
	CACOPHONY,
	# Time Modifiers
	TIME_DILATION,
	DOUBLE_TIME,
	# Audio
	SILENCE,
	# Navigation
	REVERSED,
	RANDOM_TELEPORT,  # Teleports all players to random articles
	# Utility
	ALL_CLEAR,
}

# Configuration (set by host in VoteHUD)
var events_enabled: bool = true
var event_frequency: float = 90.0  # Seconds between event attempts
var allowed_events: Array[EventType] = []
var duration_modifier: float = 1.0
var max_concurrent: int = 1
var accessibility_mode: bool = false

# State tracking
var _active_events: Dictionary = {}  # event_type -> {end_time, duration, data}
var _event_timer: float = 0.0
var _warning_shown: bool = false
var _event_pending: bool = false  # Guards against overlapping await calls from _process

# Event durations (base values in seconds)
const EVENT_DURATIONS := {
	EventType.DARKNESS: [20.0, 35.0],
	EventType.COLOR_SHIFT: [30.0, 45.0],
	EventType.FOG: [30.0, 50.0],
	EventType.EARTHQUAKE: [20.0, 35.0],
	EventType.WEATHER_SYSTEM: [60.0, 120.0],
	EventType.SPEED_UP: [20.0, 30.0],
	EventType.HEAVY_GRAVITY: [25.0, 40.0],
	EventType.NO_RUNNING: [45.0, 90.0],
	EventType.DOUBLE_JUMP: [30.0, 60.0],
	EventType.TRIPLE_JUMP: [30.0, 60.0],
	EventType.BACKWARDS_CONTROLS: [45.0, 90.0],
	EventType.LOW_GRAVITY: [45.0, 90.0],
	EventType.FLYING_ARTWORK: [30.0, 60.0],
	EventType.CACOPHONY: [20.0, 40.0],
	EventType.TIME_DILATION: [30.0, 50.0],
	EventType.DOUBLE_TIME: [30.0, 60.0],
	EventType.SILENCE: [30.0, 60.0],
	EventType.REVERSED: [30.0, 60.0],
	EventType.RANDOM_TELEPORT: [0.0, 0.0],  # Instant teleport
	EventType.ALL_CLEAR: [10.0, 10.0],
}

# Event display names
const EVENT_NAMES := {
	EventType.DARKNESS: "Darkness",
	EventType.COLOR_SHIFT: "Color Shift",
	EventType.FOG: "Fog",
	EventType.EARTHQUAKE: "Earthquake",
	EventType.WEATHER_SYSTEM: "Weather System",
	EventType.SPEED_UP: "Speed Up",
	EventType.HEAVY_GRAVITY: "Heavy Gravity",
	EventType.NO_RUNNING: "No Running",
	EventType.DOUBLE_JUMP: "Double Jump",
	EventType.TRIPLE_JUMP: "Triple Jump",
	EventType.BACKWARDS_CONTROLS: "Backwards Controls",
	EventType.LOW_GRAVITY: "Low Gravity",
	EventType.FLYING_ARTWORK: "Flying Artwork",
	EventType.CACOPHONY: "Cacophony",
	EventType.TIME_DILATION: "Time Dilation",
	EventType.DOUBLE_TIME: "Double Time",
	EventType.SILENCE: "Silence",
	EventType.REVERSED: "Reversed",
	EventType.RANDOM_TELEPORT: "Random Teleport",
	EventType.ALL_CLEAR: "All Clear",
}


func _ready() -> void:
	# Server runs the event loop
	if not multiplayer or not multiplayer.multiplayer_peer:
		return  # No multiplayer yet (main menu)

	if multiplayer.is_server():
		# Initialize with all implemented events allowed by default
		# NOTE: Keep this list in sync with reset_to_defaults()
		allowed_events = [
			EventType.DARKNESS,
			EventType.COLOR_SHIFT,
			EventType.FOG,
			EventType.EARTHQUAKE,
			EventType.WEATHER_SYSTEM,
			EventType.SPEED_UP,
			EventType.HEAVY_GRAVITY,
			EventType.NO_RUNNING,
			EventType.DOUBLE_JUMP,
			EventType.TRIPLE_JUMP,
			EventType.BACKWARDS_CONTROLS,
			EventType.LOW_GRAVITY,
			EventType.FLYING_ARTWORK,
			EventType.CACOPHONY,
			EventType.TIME_DILATION,
			EventType.DOUBLE_TIME,
			EventType.SILENCE,
			EventType.REVERSED,
			EventType.RANDOM_TELEPORT,
		]


func _process(delta: float) -> void:
	# Check if we have a multiplayer peer first
	if not multiplayer or not multiplayer.multiplayer_peer:
		return

	if not multiplayer.is_server():
		return

	if not events_enabled:
		return

	if not RaceManager.is_race_active():
		if _active_events.size() > 0:
			# Force end all events if race ended
			for event_type in _active_events.keys():
				_end_event(event_type)
		return

	# Update earthquake shaking if active
	_update_earthquake(delta)

	# Check for ending events EVERY frame
	_check_ending_events()

	# Check if we should trigger an event
	_event_timer += delta
	if _event_timer >= event_frequency and not _event_pending:
		_event_timer = 0.0
		_try_trigger_event()


func _update_earthquake(delta: float) -> void:
	# Handle continuous earthquake shaking
	if is_event_active(EventType.EARTHQUAKE):
		EarthquakeEvent._process_shake(delta)


func _try_trigger_event() -> void:
	# Guard against overlapping calls from _process while awaiting
	if _event_pending:
		return
	_event_pending = true

	# Can't trigger if at max concurrent
	if _active_events.size() >= max_concurrent:
		_event_pending = false
		return

	# No events in first 30 seconds of race
	if RaceManager.get_race_time() < 30.0:
		_event_pending = false
		return

	# No events during countdown
	if RaceManager.is_countdown_active():
		_event_pending = false
		return

	# No events when leader is near finish
	if RaceManager.leader_is_near_finish():
		_event_pending = false
		return

	# Get available events
	var available = _get_available_events()
	if available.is_empty():
		_event_pending = false
		return

	# Pick random event
	var event = available.pick_random()
	var duration = _get_event_duration(event)

	# Show warning 2 seconds before
	_warning_shown = true
	_rpc_show_warning.rpc(event)

	# Wait 2 seconds then start
	if is_inside_tree():
		await get_tree().create_timer(2.0).timeout
	_start_event(event, duration)
	_event_pending = false


func _start_event(event_type: int, duration: float) -> void:
	if _active_events.has(event_type):
		return  # Already active

	_active_events[event_type] = {
		"end_time": Time.get_ticks_msec() + (duration * 1000),
		"duration": duration,
		"started_at": RaceManager.get_race_time()
	}

	# Apply the event effect
	_apply_event_effect(event_type)

	# Broadcast to all clients
	_rpc_event_started.rpc(event_type, duration)
	event_started.emit(event_type, duration)


func _apply_event_effect(event_type: int) -> void:
	match event_type:
		EventType.SPEED_UP:
			SpeedUpEvent.apply()
		EventType.HEAVY_GRAVITY:
			HeavyGravityEvent.apply()
		EventType.DARKNESS:
			DarknessEvent.apply()
		EventType.TIME_DILATION:
			TimeDilationEvent.apply()
		EventType.DOUBLE_TIME:
			DoubleTimeEvent.apply()
		EventType.NO_RUNNING:
			NoRunningEvent.apply()
		EventType.DOUBLE_JUMP:
			DoubleJumpEvent.apply()
		EventType.TRIPLE_JUMP:
			TripleJumpEvent.apply()
		EventType.BACKWARDS_CONTROLS:
			BackwardsControlsEvent.apply()
		EventType.LOW_GRAVITY:
			LowGravityEvent.apply()
		EventType.FLYING_ARTWORK:
			FlyingArtworkEvent.apply()
		EventType.CACOPHONY:
			CacophonyEvent.apply()
		EventType.REVERSED:
			ReversedEvent.apply()
		EventType.COLOR_SHIFT:
			ColorShiftEvent.apply()
		EventType.FOG:
			FogEvent.apply()
		EventType.EARTHQUAKE:
			EarthquakeEvent.apply()
		EventType.WEATHER_SYSTEM:
			WeatherSystemEvent.apply()
		EventType.SILENCE:
			SilenceEvent.apply()
		EventType.RANDOM_TELEPORT:
			RandomTeleportEvent.apply()
		EventType.ALL_CLEAR:
			_clear_all_events()

func _clear_all_events() -> void:
	for event_type in _active_events.keys():
		if event_type != EventType.ALL_CLEAR:
			_end_event(event_type)


func _end_event_effect(event_type: int) -> void:
	match event_type:
		EventType.SPEED_UP:
			SpeedUpEvent.end()
		EventType.HEAVY_GRAVITY:
			HeavyGravityEvent.end()
		EventType.DARKNESS:
			DarknessEvent.end()
		EventType.TIME_DILATION:
			TimeDilationEvent.end()
		EventType.DOUBLE_TIME:
			DoubleTimeEvent.end()
		EventType.NO_RUNNING:
			NoRunningEvent.end()
		EventType.DOUBLE_JUMP:
			DoubleJumpEvent.end()
		EventType.TRIPLE_JUMP:
			TripleJumpEvent.end()
		EventType.BACKWARDS_CONTROLS:
			BackwardsControlsEvent.end()
		EventType.LOW_GRAVITY:
			LowGravityEvent.end()
		EventType.FLYING_ARTWORK:
			FlyingArtworkEvent.end()
		EventType.CACOPHONY:
			CacophonyEvent.end()
		EventType.REVERSED:
			ReversedEvent.end()
		EventType.COLOR_SHIFT:
			ColorShiftEvent.end()
		EventType.FOG:
			FogEvent.end()
		EventType.EARTHQUAKE:
			EarthquakeEvent.end()
		EventType.WEATHER_SYSTEM:
			WeatherSystemEvent.end()
		EventType.SILENCE:
			SilenceEvent.end()


func _check_ending_events() -> void:
	var now = Time.get_ticks_msec()
	for event_type in _active_events.keys():
		var end_time = _active_events[event_type].end_time
		if now >= end_time:
			_end_event(event_type)


func _end_event(event_type: int) -> void:
	# End the event effect first
	_end_event_effect(event_type)

	_active_events.erase(event_type)

	_rpc_event_ended.rpc(event_type)
	event_ended.emit(event_type)


# ── RPC Methods ──────────────────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _rpc_event_started(event_type: int, duration: float) -> void:
	# All clients receive this
	_active_events[event_type] = {
		"end_time": Time.get_ticks_msec() + (duration * 1000),
		"duration": duration
	}
	event_started.emit(event_type, duration)


@rpc("authority", "call_local", "reliable")
func _rpc_event_ended(event_type: int) -> void:
	# All clients receive this
	if _active_events.has(event_type):
		_active_events.erase(event_type)
	event_ended.emit(event_type)


@rpc("authority", "call_local", "reliable")
func _rpc_show_warning(event_type: int) -> void:
	# All clients show warning banner
	event_warning.emit(event_type)


# ── Public API ──────────────────────────────────────────────────────────────

func is_event_active(event_type: int) -> bool:
	return _active_events.has(event_type)


func get_active_events() -> Array:
	return _active_events.keys()


func get_remaining_duration(event_type: int) -> float:
	if not _active_events.has(event_type):
		return 0.0
	
	var now = Time.get_ticks_msec()
	var remaining_ms = _active_events[event_type].end_time - now
	return max(0.0, remaining_ms / 1000.0)


func get_event_name(event_type: int) -> String:
	return EVENT_NAMES.get(event_type, "Unknown")


# Debug function - manually trigger an event for testing
func debug_trigger_event(event_type: int = -1) -> void:
	if not multiplayer or not multiplayer.multiplayer_peer:
		printerr("[EventManager] debug_trigger_event: No multiplayer peer!")
		return
	
	if not multiplayer.is_server():
		printerr("[EventManager] debug_trigger_event: Not server!")
		return
	
	var event = event_type
	if event < 0:
		var available = _get_available_events()
		if available.is_empty():
			printerr("[EventManager] debug_trigger_event: No available events!")
			return
		event = available.pick_random()

	_try_trigger_event_manual(event)


func _try_trigger_event_manual(event: EventType) -> void:
	var duration = _get_event_duration(event)

	_rpc_show_warning.rpc(event)

	if is_inside_tree():
		await get_tree().create_timer(2.0).timeout
	_start_event(event, duration)


func _get_available_events() -> Array[EventType]:
	var available: Array[EventType] = []
	for event in allowed_events:
		# Skip if already active
		if event != EventType.NONE and not _active_events.has(event):
			available.append(event)
	return available


func _get_event_duration(event_type: int) -> float:
	if not EVENT_DURATIONS.has(event_type):
		return 30.0
	
	var range = EVENT_DURATIONS[event_type]
	if range[0] == range[1]:
		return range[0]  # Fixed duration
	
	var base = randf_range(range[0], range[1])
	return base * duration_modifier


# ── Host Configuration API ────────────────────────────────────────────────────

func configure_from_dict(config: Dictionary) -> void:
	events_enabled = config.get("enabled", true)
	event_frequency = config.get("frequency_seconds", 90.0)
	allowed_events = config.get("allowed_events", allowed_events)
	duration_modifier = config.get("duration_modifier", 1.0)
	max_concurrent = config.get("max_concurrent", 1)
	accessibility_mode = config.get("accessibility_mode", false)
	
	if accessibility_mode:
		_apply_accessibility_restrictions()


func _apply_accessibility_restrictions() -> void:
	# Remove potentially problematic events
	var blocked = [
		EventType.REVERSED,  # Disorientation
	]
	for event in blocked:
		if event in allowed_events:
			allowed_events.erase(event)

	# Reduce intensity
	duration_modifier = 0.75


func reset_to_defaults() -> void:
	events_enabled = true
	event_frequency = 90.0
	duration_modifier = 1.0
	max_concurrent = 1
	accessibility_mode = false
	allowed_events = [
		EventType.DARKNESS,
		EventType.COLOR_SHIFT,
		EventType.FOG,
		EventType.EARTHQUAKE,
		EventType.WEATHER_SYSTEM,
		EventType.SPEED_UP,
		EventType.HEAVY_GRAVITY,
		EventType.NO_RUNNING,
		EventType.DOUBLE_JUMP,
		EventType.TRIPLE_JUMP,
		EventType.BACKWARDS_CONTROLS,
		EventType.LOW_GRAVITY,
		EventType.FLYING_ARTWORK,
		EventType.CACOPHONY,
		EventType.TIME_DILATION,
		EventType.DOUBLE_TIME,
		EventType.SILENCE,
		EventType.REVERSED,
		EventType.RANDOM_TELEPORT,
	]


# ── Late Joiner Sync ─────────────────────────────────────────────────────────

func get_active_events_state() -> Array:
	"""Returns state of all active events for syncing to late joiners."""
	var state: Array = []
	for event_type in _active_events.keys():
		state.append({
			"event_type": event_type,
			"end_time": _active_events[event_type].end_time,
			"duration": _active_events[event_type].duration
		})
	return state


func apply_active_events_state(state: Array) -> void:
	"""Applies active event state received from server (late joiner sync)."""
	for entry: Dictionary in state:
		var event_type: int = entry.get("event_type", EventType.NONE)
		var end_time: int = entry.get("end_time", 0)
		var duration: float = entry.get("duration", 0.0)
		
		_active_events[event_type] = {
			"end_time": end_time,
			"duration": duration
		}
		# Apply event effect locally
		_apply_event_effect(event_type)
		event_started.emit(event_type, duration)


@rpc("authority", "call_remote", "reliable")
func _sync_events_to_peer(state: Array) -> void:
	"""RPC to sync active events to a newly connected client."""
	apply_active_events_state(state)
