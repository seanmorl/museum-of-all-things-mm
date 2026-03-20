extends StaticBody3D
## Plays .ogg audio files streamed from Wikimedia Commons.

var title: String = ""
var text: String = ""
var url: String = ""
var is_playing: bool = false
var _stream: AudioStreamOggVorbis = null
var _loading: bool = false
var _interact_queued: bool = false

@onready var _player: AudioStreamPlayer3D = $AudioPlayer

func _ready() -> void:
	pass

func init(exhibit_title: String, item_text: String, audio_url: String) -> void:
	title = exhibit_title
	text = item_text
	url = audio_url
	_loading = true
	_fetch_audio()

func _fetch_audio() -> void:
	if url == "":
		Log.warn("Gramophone", "No audio URL provided for '%s'" % text)
		_loading = false
		return

	Log.info("Gramophone", "Fetching audio from: %s" % url)
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_audio_downloaded.bind(http))
	var err = http.request(url, RequestSync.COMMON_HEADERS)
	if err != OK:
		Log.error("Gramophone", "Failed to start HTTP request for audio: %s (error: %d)" % [url, err])
		_loading = false
		_set_error_state("HTTP request failed to start")
	else:
		Log.debug("Gramophone", "HTTP request started successfully")

func _on_audio_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	_loading = false

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		Log.info("Gramophone", "Audio downloaded, %d bytes" % body.size())

		# Validate buffer has data
		if body.size() == 0:
			Log.error("Gramophone", "Downloaded audio buffer is empty for '%s'" % text)
			_set_error_state("Empty audio file")
			return

		# Load audio stream (no await - direct load)
		_stream = AudioStreamOggVorbis.load_from_buffer(body)

		if _stream:
			_player.stream = _stream
			is_playing = false
			Log.info("Gramophone", "Audio stream loaded successfully")
			# Process queued interaction if any
			if _interact_queued:
				_interact_queued = false
				_play_audio()
		else:
			Log.error("Gramophone", "Failed to create audio stream from buffer (%d bytes)" % body.size())
			# Try one retry without await
			_stream = AudioStreamOggVorbis.load_from_buffer(body)
			if _stream:
				_player.stream = _stream
				is_playing = false
				Log.info("Gramophone", "Audio stream loaded on retry")
				if _interact_queued:
					_interact_queued = false
					_play_audio()
			else:
				_set_error_state("Invalid audio format")
	else:
		Log.error("Gramophone", "Failed to download audio. Result: %d, Response: %d" % [result, response_code])
		_set_error_state("Download failed")


func _set_error_state(error_message: String) -> void:
	"""Set gramophone to error state with user-friendly message"""
	title = "Error: %s" % error_message
	text = "This gramophone cannot play audio. The file may be corrupted or in an unsupported format."
	is_playing = false
	Log.error("Gramophone", "Error state set: %s" % error_message)

func set_stolen(stolen: bool) -> void:
	visible = not stolen
	if stolen:
		_player.stop()
	elif is_playing and _stream:
		_player.play()

func interact() -> void:
	if _loading:
		# Audio still loading - queue the interaction
		Log.debug("Gramophone", "Audio loading, queuing interact for '%s'" % text)
		_interact_queued = true
		return
	
	if not _stream:
		if url == "":
			Log.warn("Gramophone", "Interact called but no audio URL was provided")
		else:
			Log.warn("Gramophone", "Interact called but audio failed to load for '%s'" % text)
		return

	_play_audio()


func _play_audio() -> void:
	"""Internal function to play the audio with fade-in"""
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
	return "⏹ Stop Music" if is_playing else "▶ Play Music"
