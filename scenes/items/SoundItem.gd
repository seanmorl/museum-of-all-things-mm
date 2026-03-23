extends MeshInstance3D
class_name SoundItem
## Movable sound item that can be picked up and placed like paintings.
## Contains audio playback functionality with gramophone visual.

signal loaded

var audio_url: String
var _stream: AudioStreamOggVorbis = null
var text: String
var title: String
var is_stolen: bool = false
var is_playing: bool = false
var _loading: bool = false
var _interact_queued: bool = false

var _player: AudioStreamPlayer3D = null

func _ready() -> void:
	add_to_group("sound_item")
	add_to_group("ExhibitItem")
	_setup_audio_player()

func _setup_audio_player() -> void:
	# Create AudioStreamPlayer3D if not present
	if has_node("AudioPlayer"):
		_player = $AudioPlayer
	else:
		_player = AudioStreamPlayer3D.new()
		_player.name = "AudioPlayer"
		_player.max_distance = 180.0
		_player.attenuation = 0.25
		_player.bus = &"Sound"
		add_child(_player)

func init(exhibit_title: String, item_text: String, audio_url: String) -> void:
	title = exhibit_title
	text = item_text
	self.audio_url = audio_url
	_loading = true
	if audio_url != "":
		_fetch_audio()
	else:
		_loading = false
		Log.warn("SoundItem", "No audio URL provided for '%s'" % text)

func _fetch_audio() -> void:
	if audio_url == "":
		_loading = false
		return

	Log.info("SoundItem", "Fetching audio from: %s" % audio_url)
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_audio_downloaded.bind(http))
	var err = http.request(audio_url, RequestSync.COMMON_HEADERS)
	if err != OK:
		Log.error("SoundItem", "Failed to start HTTP request for audio: %s (error: %d)" % [audio_url, err])
		_loading = false
		_set_error_state("HTTP request failed to start")
	else:
		Log.debug("SoundItem", "HTTP request started successfully")

func _on_audio_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	_loading = false

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		Log.info("SoundItem", "Audio downloaded, %d bytes" % body.size())

		if body.size() == 0:
			Log.error("SoundItem", "Downloaded audio buffer is empty for '%s'" % text)
			_set_error_state("Empty audio file")
			return

		_stream = AudioStreamOggVorbis.load_from_buffer(body)

		if _stream:
			_player.stream = _stream
			is_playing = false
			Log.info("SoundItem", "Audio stream loaded successfully")
			loaded.emit()
			if _interact_queued:
				_interact_queued = false
				_play_audio()
		else:
			Log.error("SoundItem", "Failed to create audio stream from buffer (%d bytes)" % body.size())
			_stream = AudioStreamOggVorbis.load_from_buffer(body)
			if _stream:
				_player.stream = _stream
				is_playing = false
				Log.info("SoundItem", "Audio stream loaded on retry")
				loaded.emit()
				if _interact_queued:
					_interact_queued = false
					_play_audio()
			else:
				_set_error_state("Invalid audio format")
	else:
		Log.error("SoundItem", "Failed to download audio. Result: %d, Response: %d" % [result, response_code])
		_set_error_state("Download failed")

func _set_error_state(error_message: String) -> void:
	title = "Error: %s" % error_message
	text = "This sound cannot play. The file may be corrupted or unsupported."
	is_playing = false
	Log.error("SoundItem", "Error state set: %s" % error_message)

func set_stolen(stolen: bool) -> void:
	is_stolen = stolen
	layers = 0 if stolen else 1
	if has_node("InteractionBody/CollisionShape3D"):
		$InteractionBody/CollisionShape3D.disabled = stolen
	visible = not stolen
	if stolen:
		_player.stop()
	elif is_playing and _stream:
		_player.play()

func interact() -> void:
	if _loading:
		Log.debug("SoundItem", "Audio loading, queuing interact for '%s'" % text)
		_interact_queued = true
		return

	if not _stream:
		if audio_url == "":
			Log.warn("SoundItem", "Interact called but no audio URL was provided")
		else:
			Log.warn("SoundItem", "Interact called but audio failed to load for '%s'" % text)
		return

	_play_audio()

func _play_audio() -> void:
	var tween = create_tween()
	if is_playing:
		is_playing = false
		tween.tween_property(_player, "volume_db", -80.0, 1.5).set_trans(Tween.TRANS_SINE)
		tween.finished.connect(_player.stop)
	else:
		is_playing = true
		_player.volume_db = -80.0
		_player.play()
		tween.tween_property(_player, "volume_db", 0.0, 1.0).set_trans(Tween.TRANS_SINE)

func get_interaction_text() -> String:
	if _loading:
		return "⏳ Loading..."
	if not _stream:
		if title.begins_with("Error:"):
			return "🔇 " + title
		return "🔇 Loading..."
	return "⏹ Stop" if is_playing else "▶ Play"

func _on_pointer_event(event: Variant) -> void:
	if event.event_type == "click" or (event.has("pressed") and event.pressed):
		interact()

func _exit_tree() -> void:
	if _player:
		_player.stop()
