extends StaticBody3D
## Plays .ogg audio files streamed from Wikimedia Commons.
class_name Gramophone

var title: String = ""
var text: String = ""
var url: String = ""
var is_playing: bool = false
var _stream: AudioStream = null
var _loading: bool = false
var _interact_queued: bool = false

@onready var _player: AudioStreamPlayer3D = $AudioPlayer

func _ready() -> void:
	add_to_group("sound_item")
	ExhibitFetcher.images_complete.connect(_on_images_fetched)


func _on_images_fetched(file_titles: Array, _caller_ctx: Variant) -> void:
	Log.debug("Gramophone", "Images fetch complete for: %s (looking for: %s)" % [file_titles, _pending_file_title])
	for ft in file_titles:
		if ft == _pending_file_title:
			var result = ExhibitFetcher.get_result(ft)
			Log.debug("Gramophone", "Found result for %s: %s" % [ft, "yes" if result else "no"])
			if result and result.has("url"):
				Log.info("Gramophone", "Got audio URL on demand: %s" % result.url)
				url = result.url
				_pending_file_title = ""
				_fetch_audio()
				return
	Log.warn("Gramophone", "Audio fetch completed but no URL found")


var _pending_file_title: String = ""


func init(exhibit_title: String, item_text: String, audio_url: String, file_title: String = "") -> void:
	title = exhibit_title
	text = item_text
	url = audio_url
	_loading = true
	if url != "":
		_fetch_audio()
	elif file_title != "":
		_fetch_audio_on_demand(file_title)
	else:
		_loading = false
		Log.warn("Gramophone", "No audio URL or file title for '%s'" % text)

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


func _fetch_audio_on_demand(file_title: String) -> void:
	Log.info("Gramophone", "Fetching audio URL on demand for: %s" % file_title)
	_pending_file_title = file_title
	ExhibitFetcher.fetch_images([file_title], null)
	call_deferred("_check_audio_url_on_demand")


func _check_audio_url_on_demand() -> void:
	if _pending_file_title == "":
		return
	
	var result = ExhibitFetcher.get_result(_pending_file_title)
	if result and result.has("url"):
		Log.info("Gramophone", "Got audio URL on demand: %s" % result.url)
		url = result.url
		_pending_file_title = ""
		_fetch_audio()
	else:
		await get_tree().create_timer(0.5).timeout
		if _pending_file_title != "":
			_check_audio_url_on_demand()

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

		# Try to load audio based on file extension
		_stream = _load_audio_stream(body, url)

		if _stream:
			_player.stream = _stream
			MuseumReverb.ensure_bus()
			_player.bus = MuseumReverb.BUS_NAME
			is_playing = false
			Log.info("Gramophone", "Audio stream loaded successfully (museum reverb enabled)")
			# Process queued interaction if any
			if _interact_queued:
				_interact_queued = false
				_play_audio()
		else:
			Log.error("Gramophone", "Failed to create audio stream from buffer (%d bytes)" % body.size())
			_set_error_state("Unsupported audio format")
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
	Log.debug("Gramophone", "interact() called: _loading=%s, _stream=%s, url=%s" % [_loading, _stream != null, url])
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


func _load_audio_stream(body: PackedByteArray, file_url: String) -> AudioStream:
	# Detect format from URL extension
	var ext := ""
	if "." in file_url:
		ext = file_url.get_slice(".", -1).to_lower()
	
	Log.debug("Gramophone", "Attempting to load audio format: .%s" % ext)
	
	# Try OGG first (most common on Wikimedia)
	var stream: AudioStream = AudioStreamOggVorbis.load_from_buffer(body)
	if stream:
		Log.debug("Gramophone", "Successfully loaded OGG audio")
		return stream
	
	# Try MP3
	stream = AudioStreamMP3.load_from_buffer(body)
	if stream:
		Log.debug("Gramophone", "Successfully loaded MP3 audio")
		return stream
	
	# Try WAV
	stream = AudioStreamWAV.load_from_buffer(body)
	if stream:
		Log.debug("Gramophone", "Successfully loaded WAV audio")
		return stream
	
	# No format worked
	Log.warn("Gramophone", "No supported audio format found for .%s" % ext)
	return null


func get_interaction_text() -> String:
	if _loading:
		return "⏳ Loading..."
	if not _stream:
		if title.begins_with("Error:"):
			return "🔇 " + title
		return "🔇 Loading..."
	return "⏹ Stop Music" if is_playing else "▶ Play Music"


func _exit_tree() -> void:
	ExhibitFetcher.images_complete.disconnect(_on_images_fetched)
