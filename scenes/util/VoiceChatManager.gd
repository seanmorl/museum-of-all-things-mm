extends Node
## Autoload: VoiceChatManager
## Handles proximity-based voice chat between players.

const MAX_VOICE_DISTANCE: float = 15.0
const VOICE_ATTENUATION: float = 0.5

var _voice_players: Dictionary = {}  # peer_id -> AudioStreamPlayer3D
var _local_voice: AudioStreamPlayer3D = null
var _is_muted: bool = false
var _push_to_talk: bool = false
var _is_talking: bool = false

signal voice_activity_changed(peer_id: int, is_active: bool)

func _ready() -> void:
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	_register_push_to_talk_action()

func _process(_delta: float) -> void:
	_update_voice_activity()

func init_local_voice(player: Node3D) -> void:
	# Create local voice audio player attached to player
	if _local_voice:
		_local_voice.queue_free()
	
	_local_voice = AudioStreamPlayer3D.new()
	_local_voice.name = "VoiceAudio"
	_local_voice.bus = "Voice"
	# Note: AudioStreamPlayer3D doesn't have attenuation property in Godot 4
	# Distance filtering is handled by the audio bus/effects
	player.add_child(_local_voice)

func send_voice_audio(peer_id: int, audio_data: PackedByteArray) -> void:
	if _is_muted:
		return
	
	# In a real implementation, this would capture microphone audio
	# and send it via multiplayer RPC
	# For now, this is a framework for future implementation
	if NetworkManager.multiplayer and NetworkManager.multiplayer.has_multiplayer_peer():
		_receive_voice_audio.rpc_id(peer_id, audio_data)

func _update_voice_activity() -> void:
	# Check push-to-talk input
	var talk_pressed = Input.is_action_pressed("push_to_talk") if InputMap.has_action("push_to_talk") else false
	var voice_key = Input.is_key_pressed(KEY_V)
	
	_push_to_talk = talk_pressed or voice_key
	
	if _push_to_talk and not _is_talking and not _is_muted:
		_is_talking = true
		# In real implementation: start microphone capture
	elif not _push_to_talk and _is_talking:
		_is_talking = false
		# In real implementation: stop microphone capture

func set_muted(muted: bool) -> void:
	_is_muted = muted
	if _is_muted and _is_talking:
		_is_talking = false

func is_muted() -> bool:
	return _is_muted

func toggle_mute() -> void:
	set_muted(not _is_muted)

func _on_peer_connected(peer_id: int) -> void:
	# Create voice player for new peer
	_create_voice_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	_remove_voice_player(peer_id)

func _on_server_disconnected() -> void:
	# Clear all voice players
	for peer_id in _voice_players.keys():
		_remove_voice_player(peer_id)

func _create_voice_player(peer_id: int) -> void:
	if _voice_players.has(peer_id):
		return
	
	var voice_player = AudioStreamPlayer3D.new()
	voice_player.name = "Voice_%d" % peer_id
	voice_player.bus = "Voice"
	# Note: AudioStreamPlayer3D doesn't have attenuation/max_distance in Godot 4
	# Find the network player node and attach voice to it
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("get_network_player"):
		var net_player = main.get_network_player(peer_id)
		if net_player:
			net_player.add_child(voice_player)
			_voice_players[peer_id] = voice_player

func _remove_voice_player(peer_id: int) -> void:
	if _voice_players.has(peer_id):
		_voice_players[peer_id].queue_free()
		_voice_players.erase(peer_id)
		voice_activity_changed.emit(peer_id, false)

@rpc("any_peer", "call_remote", "unreliable")
func _receive_voice_audio(peer_id: int, audio_data: PackedByteArray) -> void:
	# In real implementation: decode and play audio data
	# For now, this is a framework
	pass

# Push-to-talk action registration
func _register_push_to_talk_action() -> void:
	if not InputMap.has_action("push_to_talk"):
		InputMap.add_action("push_to_talk")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_V
		InputMap.action_add_event("push_to_talk", ev)
