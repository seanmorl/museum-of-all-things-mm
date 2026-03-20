class_name RouletteEvent
extends RefCounted
## Roulette - Randomly selects and applies another event instantly

static var _applied_event: int = -1

static func apply() -> void:
	# Get list of available events (excluding NONE, ALL_CLEAR, and ROULETTE itself)
	var available_events = [
		EventManager.EventType.DARKNESS,
		EventManager.EventType.COLOR_SHIFT,
		EventManager.EventType.FOG,
		EventManager.EventType.EARTHQUAKE,
		EventManager.EventType.WEATHER_SYSTEM,
		EventManager.EventType.SPEED_UP,
		EventManager.EventType.HEAVY_GRAVITY,
		EventManager.EventType.NO_RUNNING,
		EventManager.EventType.TIME_DILATION,
		EventManager.EventType.DOUBLE_TIME,
		EventManager.EventType.SILENCE,
		EventManager.EventType.REVERSED,
	]

	# Pick a random event
	_applied_event = available_events.pick_random()

	# Apply the selected event immediately
	match _applied_event:
		EventManager.EventType.SPEED_UP:
			SpeedUpEvent.apply()
		EventManager.EventType.HEAVY_GRAVITY:
			HeavyGravityEvent.apply()
		EventManager.EventType.DARKNESS:
			DarknessEvent.apply()
		EventManager.EventType.TIME_DILATION:
			TimeDilationEvent.apply()
		EventManager.EventType.DOUBLE_TIME:
			DoubleTimeEvent.apply()
		EventManager.EventType.NO_RUNNING:
			NoRunningEvent.apply()
		EventManager.EventType.REVERSED:
			ReversedEvent.apply()
		EventManager.EventType.COLOR_SHIFT:
			ColorShiftEvent.apply()
		EventManager.EventType.FOG:
			FogEvent.apply()
		EventManager.EventType.EARTHQUAKE:
			EarthquakeEvent.apply()
		EventManager.EventType.WEATHER_SYSTEM:
			WeatherSystemEvent.apply()
		EventManager.EventType.SILENCE:
			SilenceEvent.apply()

	print("[RouletteEvent] Applied: Random event selected - %s" % EventManager.EVENT_NAMES.get(_applied_event, "Unknown"))

static func end() -> void:
	# End the applied event if it has duration
	if _applied_event >= 0:
		match _applied_event:
			EventManager.EventType.SPEED_UP:
				SpeedUpEvent.end()
			EventManager.EventType.HEAVY_GRAVITY:
				HeavyGravityEvent.end()
			EventManager.EventType.DARKNESS:
				DarknessEvent.end()
			EventManager.EventType.TIME_DILATION:
				TimeDilationEvent.end()
			EventManager.EventType.DOUBLE_TIME:
				DoubleTimeEvent.end()
			EventManager.EventType.NO_RUNNING:
				NoRunningEvent.end()
			EventManager.EventType.REVERSED:
				ReversedEvent.end()
			EventManager.EventType.COLOR_SHIFT:
				ColorShiftEvent.end()
			EventManager.EventType.FOG:
				FogEvent.end()
			EventManager.EventType.EARTHQUAKE:
				EarthquakeEvent.end()
			EventManager.EventType.WEATHER_SYSTEM:
				WeatherSystemEvent.end()
			EventManager.EventType.SILENCE:
				SilenceEvent.end()

	_applied_event = -1
	print("[RouletteEvent] Ended")

static func get_duration() -> float:
	return 0.0  # Instant - applies another event

static func get_display_name() -> String:
	return "Roulette"

static func get_description() -> String:
	return "A random event is selected!"
