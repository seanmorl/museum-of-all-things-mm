extends Node
## Autoload: VoiceChatManager
## Handles proximity-based voice chat between players.
##
## Features:
##   - Push-to-talk (V key or configured action)
##   - Proximity-based volume attenuation
##   - Mute toggle
##   - Real-time microphone capture via AudioEffectRecord
##   - Voice activity signal for UI indicators
##
## Requirements:
##   - A "Voice" audio bus must exist in the project bus layout.
##     If it doesn't exist at runtime, it will be created automatically.
##   - Microphone permission must be granted (handled automatically on _ready).

const MAX_VOICE_DISTANCE: float = 15.0
const VOICE_ATTENUATION_EXPONENT: float = 0.5

var _voice_players: Dictionary = {}  # peer_id -> AudioStreamPlayer3D
var _local_voice: AudioStreamPlayer3D = null
var _is_muted: bool = false
var _push_to_talk: bool = false
var _is_talking: bool = false
var _mic_recording: AudioEffectRecord = null
var _mic_stream: AudioStreamMicrophone = null
var _mic_active: bool = false
var _v_key_prev: bool = false  # Track V key state for edge detection

signal voice_activity_changed(peer_id: int, is_active: bool)
signal local_talking_changed(is_talking: bool)


func _ready() -> void:
	_ensure_voice_bus_exists()
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	_register_push_to_talk_action()
	_setup_microphone()


func _process(_delta: float) -> void:
	_update_voice_activity()


func _exit_tree() -> void:
	_stop_microphone()


# ── Audio Bus Setup ──────────────────────────────────────────────────────────

func _ensure_voice_bus_exists() -> void:
	## Godot projects may not have a "Voice" bus defined. Create one at runtime
	## so AudioStreamPlayer3D nodes assigned to "Voice" don't produce errors.
	var bus_idx: int = AudioServer.get_bus_index("Voice")
	if bus_idx < 0:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, "Voice")
		AudioServer.set_bus_send(bus_idx, "Master")
		# Add a limiter to prevent clipping from multiple simultaneous voices
		var limiter := AudioEffectLimiter.new()
		limiter.threshold = -6.0
		limiter.ramp = 0.1
		AudioServer.add_bus_effect(bus_idx, limiter, 0)
		Log.info("VoiceChat", "Created 'Voice' audio bus at index %d" % bus_idx)


# ── Microphone Capture ───────────────────────────────────────────────────────

func _setup_microphone() -> void:
	## Set up a microphone stream and record effect for local voice capture.
	## This is deferred until the first push-to-talk press in practice, but we
	## initialise the objects here so they're ready.
	_mic_stream = AudioStreamMicrophone.new()

	# Create a player to hold the mic → we extract recorded PCM from the bus
	_local_voice = AudioStreamPlayer3D.new()
	_local_voice.name = "VoiceAudio"
	_local_voice.bus = "Voice"
	_local_voice.stream = _mic_stream
	add_child(_local_voice)

	# Add the record effect to the Voice bus (index 0 = first slot)
	var voice_bus_idx: int = AudioServer.get_bus_index("Voice")
	if voice_bus_idx >= 0:
		# Check if limiter already added a slot
		var record_idx: int = AudioServer.get_bus_effect_count(voice_bus_idx)
		_mic_recording = AudioEffectRecord.new()
		AudioServer.add_bus_effect(voice_bus_idx, _mic_recording, 1)
		Log.info("VoiceChat", "Microphone ready on Voice bus")


func _start_microphone() -> void:
	if _mic_active or _is_muted:
		return
	if not _local_voice or not _mic_recording:
		Log.warn("VoiceChat", "Microphone not set up, cannot start")
		return
	_local_voice.play()
	_mic_active = true
	_mic_recording.set_recording_active(true)
	Log.debug("VoiceChat", "Microphone started")


func _stop_microphone() -> void:
	if not _mic_active:
		return
	if _mic_recording:
		_mic_recording.set_recording_active(false)
	if _local_voice and _local_voice.playing:
		_local_voice.stop()
	_mic_active = false
	Log.debug("VoiceChat", "Microphone stopped")


func _get_pcm_data() -> AudioStreamWAV:
	## Grab recorded audio from the recording effect.
	## Returns null if nothing recorded.
	if not _mic_recording or not _mic_active:
		return null
	return _mic_recording.get_recording()


# ── Public API ───────────────────────────────────────────────────────────────

func init_local_voice(_player: Node3D) -> void:
	## Legacy API — local voice is now attached to the VoiceChatManager itself.
	## Kept for backward compatibility. No-op.
	pass


func send_voice_audio(_peer_id: int, _audio_data: PackedByteArray) -> void:
	## Legacy unicast API — replaced by broadcast RPC. Kept for compatibility.
	pass


func broadcast_voice_audio() -> void:
	## Capture current recorded audio and broadcast it to all remote peers.
	if _is_muted or not NetworkManager.is_multiplayer_active():
		return

	var wav_stream := _get_pcm_data()
	if wav_stream == null or wav_stream.data.is_empty():
		return

	var pcm: PackedByteArray = wav_stream.data

	# Send in chunks to stay within RPC size limits
	const CHUNK_SIZE: int = 8000
	var offset: int = 0
	while offset < pcm.size():
		var chunk: PackedByteArray = pcm.slice(offset, offset + CHUNK_SIZE)
		_receive_voice_audio.rpc(chunk)
		offset += CHUNK_SIZE


func _update_voice_activity() -> void:
	# Check push-to-talk input
	var talk_just_pressed = Input.is_action_just_pressed("push_to_talk") if InputMap.has_action("push_to_talk") else false
	var talk_held = Input.is_action_pressed("push_to_talk") if InputMap.has_action("push_to_talk") else false
	var voice_key = Input.is_key_pressed(KEY_V)
	var voice_just_pressed = voice_key and not _v_key_prev
	_v_key_prev = voice_key

	if (talk_just_pressed or voice_just_pressed) and not _is_muted:
		_start_microphone()

	if not _is_muted and (talk_held or voice_key):
		if not _is_talking:
			_is_talking = true
			local_talking_changed.emit(true)
			broadcast_voice_audio()
	elif _is_talking:
		_is_talking = false
		_stop_microphone()
		local_talking_changed.emit(false)


func set_muted(muted: bool) -> void:
	_is_muted = muted
	if _is_muted:
		_stop_microphone()
		if _is_talking:
			_is_talking = false
			local_talking_changed.emit(false)


func is_muted() -> bool:
	return _is_muted


func toggle_mute() -> void:
	set_muted(not _is_muted)


# ── Peer Management ──────────────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	_create_voice_player(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_remove_voice_player(peer_id)


func _on_server_disconnected() -> void:
	for pid: int in _voice_players.keys():
		_remove_voice_player(pid)


func _create_voice_player(peer_id: int) -> void:
	if _voice_players.has(peer_id):
		return

	var voice_player = AudioStreamPlayer3D.new()
	voice_player.name = "Voice_%d" % peer_id
	voice_player.bus = "Voice"

	# Try to attach to the network player node for spatial audio
	var main = get_tree().get_first_node_in_group("main")
	var attached := false
	if main and main.has_method("get_network_players"):
		var players: Dictionary = main.get_network_players()
		if players.has(peer_id):
			var net_player: Node = players[peer_id]
			if is_instance_valid(net_player):
				net_player.add_child(voice_player)
				attached = true

	if not attached:
		# Fallback: attach to the root so it still works without spatial audio
		var root := get_tree().root
		root.add_child(voice_player)
		Log.debug("VoiceChat", "Could not attach voice for peer %d to player node — attached to root" % peer_id)

	_voice_players[peer_id] = voice_player


func _remove_voice_player(peer_id: int) -> void:
	if _voice_players.has(peer_id):
		_voice_players[peer_id].queue_free()
		_voice_players.erase(peer_id)
		voice_activity_changed.emit(peer_id, false)


# ── RPC — Receive and Play Voice Audio ───────────────────────────────────────

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_voice_audio(audio_data: PackedByteArray) -> void:
	if audio_data.is_empty():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == multiplayer.get_unique_id():
		return  # Ignore our own broadcasts

	if not _voice_players.has(sender_id):
		return

	var voice_player: AudioStreamPlayer3D = _voice_players[sender_id]
	if not is_instance_valid(voice_player):
		return

	# Proximity-based volume
	var local_pos := Vector3.ZERO
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("get_local_player"):
		var lp: Node3D = main.get_local_player()
		if lp:
			local_pos = lp.global_position

	var sender_pos := voice_player.global_position
	var dist := local_pos.distance_to(sender_pos)

	if dist > MAX_VOICE_DISTANCE:
		return  # Too far — drop audio

	var volume_factor: float = clamp(1.0 - pow(dist / MAX_VOICE_DISTANCE, VOICE_ATTENUATION_EXPONENT), 0.0, 1.0)
	voice_player.volume_db = linear_to_db(volume_factor)

	# Decode and play the PCM data as an AudioStreamWAV
	var wav := AudioStreamWAV.new()
	wav.mix_rate = 16000
	wav.data = audio_data
	wav.stereo = false

	# Stop previous playback if still going
	if voice_player.playing:
		voice_player.stop()
	voice_player.stream = wav
	voice_player.play()

	# Clean up wav stream after play finishes
	voice_player.finished.connect(func():
		voice_player.stream = null
		wav.data = PackedByteArray()
	, CONNECT_ONE_SHOT)


# ── Push-to-Talk Action Registration ─────────────────────────────────────────

func _register_push_to_talk_action() -> void:
	if not InputMap.has_action("push_to_talk"):
		InputMap.add_action("push_to_talk")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_V
		InputMap.action_add_event("push_to_talk", ev)
