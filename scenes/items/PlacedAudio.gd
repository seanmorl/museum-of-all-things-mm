extends MeshInstance3D
class_name PlacedAudio
## Placed audio item that can be played, picked up, and synced across multiplayer.

var audio_url: String = ""
var title: String = ""
var exhibit_title: String = ""
var _stream: AudioStreamOggVorbis = null
var _is_playing: bool = false
var _player: AudioStreamPlayer3D = null
var _loading: bool = false

var is_playing: bool = false:
	get:
		return _is_playing
	set(value):
		if _is_playing != value:
			_is_playing = value
			if _is_playing:
				play_requested.emit()
			else:
				stop_requested.emit()

signal play_requested
signal stop_requested

func _ready() -> void:
	add_to_group("sound_item")
	add_to_group("ExhibitItem")
	_setup_audio_player()
	_fetch_audio()

func _setup_audio_player() -> void:
	if has_node("AudioPlayer"):
		_player = $AudioPlayer
	else:
		_player = AudioStreamPlayer3D.new()
		_player.name = "AudioPlayer"
		_player.max_distance = 180.0
		_player.bus = &"Sound"
		add_child(_player)

func init(_audio_url: String, _title: String, _exhibit_title: String) -> void:
	audio_url = _audio_url
	title = _title
	exhibit_title = _exhibit_title

func _fetch_audio() -> void:
	if audio_url == "":
		return
	_loading = true
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_audio_downloaded.bind(http))
	http.request(audio_url)

func _on_audio_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	_loading = false
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		_stream = AudioStreamOggVorbis.load_from_buffer(body)
		if _stream and _player:
			_player.stream = _stream

func set_stolen(stolen: bool) -> void:
	if stolen:
		visible = false
		if has_node("InteractionBody/CollisionShape3D"):
			$InteractionBody/CollisionShape3D.disabled = true
		if _player:
			_player.stop()
		is_playing = false
	else:
		visible = true
		if has_node("InteractionBody/CollisionShape3D"):
			$InteractionBody/CollisionShape3D.disabled = false

func interact() -> void:
	if _loading or not _stream:
		return
	
	# Toggle play state locally
	if is_playing:
		stop_audio()
	else:
		play_audio()

func play_audio() -> void:
	if not _stream:
		return
	is_playing = true
	_player.volume_db = -80.0
	_player.play()
	var tween = create_tween()
	tween.tween_property(_player, "volume_db", 0.0, 1.0).set_trans(Tween.TRANS_SINE)
	# Don't emit signal here - it's emitted by the setter via _update_playing_state

func stop_audio() -> void:
	is_playing = false
	var tween = create_tween()
	tween.tween_property(_player, "volume_db", -80.0, 1.5).set_trans(Tween.TRANS_SINE)
	tween.finished.connect(_player.stop)
	# Don't emit signal here - state change is tracked by setter

func get_interaction_text() -> String:
	if _loading or not _stream:
		return "🔇 Loading..."
	return "⏹ Stop" if _is_playing else "▶ Play"
