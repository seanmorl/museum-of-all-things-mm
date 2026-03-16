extends StaticBody3D
## Plays .ogg audio files streamed from Wikimedia Commons.

var title: String = ""
var text: String = ""
var url: String = ""
var is_playing: bool = false
var _stream: AudioStreamOggVorbis = null

@onready var _player: AudioStreamPlayer3D = $AudioPlayer

func _ready() -> void:
	pass

func init(exhibit_title: String, item_text: String, audio_url: String) -> void:
	title = exhibit_title
	text = item_text
	url = audio_url
	_fetch_audio()

func _fetch_audio() -> void:
	if url == "":
		Log.warn("Gramophone", "No audio URL provided for '%s'" % text)
		return

	Log.info("Gramophone", "Fetching audio from: %s" % url)
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_audio_downloaded.bind(http))
	var err = http.request(url, RequestSync.COMMON_HEADERS)
	if err != OK:
		Log.error("Gramophone", "Failed to start HTTP request for audio: " + url)

func _on_audio_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		Log.info("Gramophone", "Audio downloaded, %d bytes" % body.size())
		_stream = AudioStreamOggVorbis.load_from_buffer(body)
		if _stream:
			_player.stream = _stream
			is_playing = false
			Log.info("Gramophone", "Audio stream loaded successfully")
		else:
			Log.error("Gramophone", "Failed to create audio stream from buffer")
	else:
		Log.error("Gramophone", "Failed to download audio. Result: %d, Response: %d" % [result, response_code])

func set_stolen(stolen: bool) -> void:
	visible = not stolen
	if stolen:
		_player.stop()
	elif is_playing and _stream:
		_player.play()

func interact() -> void:
	if not _stream:
		Log.warn("Gramophone", "Interact called but no stream loaded")
		return

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
	if not _stream:
		return "🔇 Loading..."
	return "⏹ Stop Music" if is_playing else "▶ Play Music"
