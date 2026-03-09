extends StaticBody3D
## Plays .webm video files downloaded from Wikimedia Commons.

var title: String = ""
var text: String = ""
var url: String = ""
var is_playing: bool = false
var temp_path: String = ""

@onready var _player: VideoStreamPlayer = $SubViewport/VideoStreamPlayer
@onready var _sprite: Sprite3D = $Sprite3D
@onready var _viewport: SubViewport = $SubViewport
@onready var _status_label: Label3D = $StatusLabel

func _ready() -> void:
	# Link the viewport to the Sprite3D so the video renders on the mesh
	_sprite.texture = _viewport.get_texture()

func init(exhibit_title: String, item_text: String, video_url: String) -> void:
	title = exhibit_title
	text = item_text
	url = video_url
	_status_label.text = "Initializing..."
	_fetch_video()

func _fetch_video() -> void:
	if url == "":
		return
	
	var ext := "webm"
	if url.to_lower().ends_with(".ogv"):
		ext = "ogv"
	else:
		_status_label.text = "Warning: .webm may only play audio"
		_status_label.modulate = Color.YELLOW
	temp_path = "user://temp_video_" + str(hash(url)) + "." + ext
	
	var http := HTTPRequest.new()
	add_child(http)
	http.download_file = temp_path
	http.request_completed.connect(_on_video_downloaded.bind(http))
	var err = http.request(url, RequestSync.COMMON_HEADERS)
	if err == OK:
		_status_label.text = "Downloading..."
	else:
		_status_label.text = "Error: Request failed"
		Log.error("MediaScreen", "Failed to start HTTP request for video: " + url)

func _on_video_downloaded(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	Log.debug("MediaScreen", "Download completed. Result: %d, Response: %d, URL: %s" % [result, response_code, url])
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		Log.debug("MediaScreen", "Setting up VideoStreamTheora with file: " + temp_path)
		var stream = VideoStreamTheora.new()
		stream.file = temp_path
		_player.stream = stream
		_status_label.text = "Ready (Right-click to play)"
		_status_label.modulate = Color.GREEN
		is_playing = false
	else:
		_status_label.text = "Error: Download failed (%d)" % response_code
		_status_label.modulate = Color.RED
		Log.error("MediaScreen", "Failed to download video. Response: %d" % response_code)

func set_stolen(stolen: bool) -> void:
	visible = not stolen
	if stolen:
		_player.stop()
	elif is_playing:
		_player.play()

func _exit_tree() -> void:
	# Cleanup temp video file
	if temp_path != "" and FileAccess.file_exists(temp_path):
		var dir = DirAccess.open("user://")
		if dir:
			dir.remove(temp_path.get_file())

func interact() -> void:
	if not _player.stream:
		return
	if is_playing:
		_player.stop()
		_status_label.text = "Paused"
		is_playing = false
	else:
		_player.play()
		_status_label.text = "Playing"
		is_playing = true
