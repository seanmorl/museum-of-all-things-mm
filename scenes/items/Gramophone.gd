extends StaticBody3D
## Plays .ogg audio files streamed from Wikimedia Commons.
class_name Gramophone

signal audio_play_requested(exhibit_title: String, audio_title: String)
signal audio_stop_requested(exhibit_title: String, audio_title: String)

var title: String = ""
var text: String = ""
var url: String = ""
var _stream: AudioStream = null
var _is_playing: bool = false
var _loading: bool = false
var _interact_queued: bool = false
var _exhibit_title: String = ""
var _file_title: String = ""

@onready var _player: AudioStreamPlayer3D = $AudioPlayer

var is_playing: bool:
	get:
		return _is_playing

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
	_exhibit_title = exhibit_title
	_file_title = file_title if file_title != "" else exhibit_title
	title = _file_title
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
			_player.stream = _stream
			_is_playing = false
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
	_is_playing = false
	Log.error("Gramophone", "Error state set: %s" % error_message)

func set_stolen(stolen: bool) -> void:
	visible = not stolen
	if stolen:
		_player.stop()
		_is_playing = false
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
	# Sync to other players via Main's audio RPC system
	if _exhibit_title != "" and _file_title != "":
		var main = _get_main_node()
		if main and main.has_method("_request_audio_play_rpc"):
			var audio_key = _exhibit_title + ":" + _file_title
			if is_playing:
				main._request_audio_stop_rpc.rpc_id(1, audio_key, _exhibit_title, _file_title)
			else:
				main._request_audio_play_rpc.rpc_id(1, audio_key, _exhibit_title, _file_title)
	
	# Play/stop locally
	var tween = create_tween()
	if is_playing:
		_is_playing = false
		tween.tween_property(_player, "volume_db", -80.0, 1.5).set_trans(Tween.TRANS_SINE)
		tween.finished.connect(_player.stop)
	else:
		_is_playing = true
		_player.volume_db = -80.0
		_player.play()
		tween.tween_property(_player, "volume_db", 0.0, 1.0).set_trans(Tween.TRANS_SINE)


func sync_play() -> void:
	if _loading or not _stream:
		return
	_is_playing = true
	_player.volume_db = -80.0
	_player.play()
	var tween = create_tween()
	tween.tween_property(_player, "volume_db", 0.0, 1.0).set_trans(Tween.TRANS_SINE)


func sync_stop() -> void:
	_is_playing = false
	var tween = create_tween()
	tween.tween_property(_player, "volume_db", -80.0, 1.5).set_trans(Tween.TRANS_SINE)
	tween.finished.connect(_player.stop)


func _get_main_node() -> Node:
	var museum = get_tree().get_first_node_in_group("Museum")
	if museum and museum.has_node(".."):
		return museum.get_parent()
	return null


func _load_audio_stream(body: PackedByteArray, file_url: String) -> AudioStream:
	# Try to detect format from file content magic bytes
	# OGG: "OggS" magic bytes
	# MP3: "ID3" or first byte >= 0xFF
	# WAV: "RIFF" magic bytes
	# FLAC: "fLaC" magic bytes
	
	if body.size() >= 4:
		var magic: String = body.slice(0, 4).get_string_from_utf8()
		var first_bytes: String = body.slice(0, 3).get_string_from_ascii()
		
		# Try OGG first (most common from Wikipedia)
		if body.size() >= 4 and (magic == "OggS" or file_url.to_lower().ends_with(".ogg")):
			var stream = AudioStreamOggVorbis.load_from_buffer(body)
			if stream:
				Log.debug("Gramophone", "Successfully loaded OGG audio (magic: %s)" % magic)
				return stream
		
		# Try MP3 (check for ID3 tag or sync word)
		if body.size() >= 3 and (first_bytes == "ID3" or (body[0] == 0xFF and (body[1] & 0xE0) == 0xE0)):
			var stream = AudioStreamMP3.load_from_buffer(body)
			if stream:
				Log.debug("Gramophone", "Successfully loaded MP3 audio")
				return stream
		
		# Try WAV (RIFF header)
		if magic == "RIFF" and body.size() >= 8 and body.slice(4, 8).get_string_from_ascii() == "WAVE":
			var stream = AudioStreamWAV.load_from_buffer(body)
			if stream:
				Log.debug("Gramophone", "Successfully loaded WAV audio")
				return stream
		
		# Try FLAC
		if magic == "fLaC":
			var stream = AudioStreamWAV.load_from_buffer(body)
			if stream:
				Log.debug("Gramophone", "Loaded FLAC as WAV")
				return stream
	
	# Fallback: try based on URL extension
	var ext := ""
	if "." in file_url:
		ext = file_url.get_slice(".", -1).to_lower()
	
	Log.debug("Gramophone", "Attempting fallback load for format: .%s" % ext)
	
	if ext == "ogg":
		var stream = AudioStreamOggVorbis.load_from_buffer(body)
		if stream:
			return stream
	
	if ext == "mp3":
		var stream = AudioStreamMP3.load_from_buffer(body)
		if stream:
			return stream
	
	if ext == "wav":
		var stream = AudioStreamWAV.load_from_buffer(body)
		if stream:
			return stream
	
	Log.warn("Gramophone", "No supported audio format found for .%s (size: %d)" % [ext, body.size()])
	return null


func get_interaction_text() -> String:
	if _loading:
		return "⏳ Loading..."
	if not _stream:
		if title.begins_with("Error:"):
			return "🔇 " + title
		return "🔇 Loading..."
	return "⏹ Stop Music" if _is_playing else "▶ Play Music"


func _exit_tree() -> void:
	ExhibitFetcher.images_complete.disconnect(_on_images_fetched)
