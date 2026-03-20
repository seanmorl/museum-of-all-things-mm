extends Node3D

var _font: Font
var _results: Array = []
var _temp_path: String = ""

const VIDEO_URL = "https://upload.wikimedia.org/wikipedia/commons/b/b5/Raindrops_falling_on_pavement.webm"

@onready var _player: VideoStreamPlayer = $SubViewport/VideoStreamPlayer
@onready var _viewport: SubViewport = $SubViewport
@onready var _panel: MeshInstance3D = $Panel
@onready var _bg_rect: ColorRect = $SubViewport/BG
@onready var _title: Label3D = $TitleLabel
@onready var _divider: Label3D = $Divider

# Live race tracking
var _race_timer_label: Label3D = null
var _target_label: Label3D = null
var _leader_label: Label3D = null
var _live_indicator: Label3D = null
var _race_active: bool = false
var _labels_created: bool = false

func _ready() -> void:
	# Link the sub-viewport to the panel's material
	var tex := _viewport.get_texture()
	var mat := _panel.get_surface_override_material(0)
	if not mat:
		mat = _panel.mesh.surface_get_material(0).duplicate()
		_panel.set_surface_override_material(0, mat)
	mat.albedo_texture = tex

	_font = ThemeManager.get_reading_font()
	ThemeManager.reading_font_changed.connect(func(f): _font = f; _refresh())
	RaceManager.race_ended.connect(_on_race_ended)
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.vote_started.connect(_on_vote_started)
	
	# Start timer for live race updates
	set_process(true)

	_refresh_theme()
	ThemeManager.dark_mode_changed.connect(func(_d):
		if is_instance_valid(self): _refresh_theme()
	)

	_fetch_passive_video()


func _refresh_theme() -> void:
	var dark := ThemeManager.is_dark_mode
	if is_instance_valid(_bg_rect):
		_bg_rect.color = Color(0.08, 0.09, 0.12) if dark else Color(0.95, 0.96, 0.98)

	var text_col := Color.WHITE if dark else Color.BLACK
	if is_instance_valid(_title):
		_title.modulate = text_col
	if is_instance_valid(_divider):
		_divider.modulate = text_col.lerp(Color.GRAY, 0.5)

	_refresh()


func _fetch_passive_video() -> void:
	# Simple download logic similar to MediaScreen
	var ext := "webm"
	_temp_path = "user://leaderboard_bg_" + str(hash(VIDEO_URL)) + "." + ext
	
	if FileAccess.file_exists(_temp_path):
		_play_video(_temp_path)
		return

	var http := HTTPRequest.new()
	add_child(http)
	http.download_file = _temp_path
	http.request_completed.connect(func(result, response_code, _headers, _body):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			_play_video(_temp_path)
	)
	http.request(VIDEO_URL)


func _play_video(path: String) -> void:
	var stream = VideoStreamTheora.new()
	stream.file = path
	_player.stream = stream
	_player.play()


func _exit_tree() -> void:
	if _temp_path != "" and FileAccess.file_exists(_temp_path):
		var dir = DirAccess.open("user://")
		if dir:
			dir.remove(_temp_path.get_file())



func _process(delta: float) -> void:
	# Update live race timer every frame (don't recreate labels!)
	if _race_active and _race_timer_label:
		var time_str = RaceManager.get_elapsed_time_string()
		_race_timer_label.text = "⏱ %s" % time_str

func _on_vote_started(_candidates: Array) -> void:
	_race_active = false
	_refresh()

func _on_race_started(target: String, _start: String) -> void:
	print("[SimpleLeaderboard] Race started! Target: ", target)
	_race_active = true
	_refresh()

func _on_race_ended(_peer_id: int, winner_name: String) -> void:
	_race_active = false
	_results.append({
		"name": winner_name,
		"time": RaceManager.get_elapsed_time_string()
	})
	if _results.size() > 8:
		_results = _results.slice(0, 8)
	_refresh()


func _refresh() -> void:
	# Hide live race labels when not in race
	if is_instance_valid(_target_label):
		_target_label.visible = false
	if is_instance_valid(_race_timer_label):
		_race_timer_label.visible = false
	if is_instance_valid(_live_indicator):
		_live_indicator.visible = false

	# Show the title when not in live race
	if is_instance_valid(_title):
		_title.visible = not _race_active

	# If race is active, show live info ONLY
	if _race_active:
		_show_live_race()
		return

	# Otherwise show recent winners — clear only dynamically-added Label3D entries.
	# Never free _title or _divider: they are @onready scene nodes and freeing them
	# leaves dangling references that crash _refresh_theme on the next dark-mode toggle.
	for child in get_children():
		if child is Label3D \
				and child != _title \
				and child != _divider \
				and child != _target_label \
				and child != _race_timer_label \
				and child != _live_indicator:
			child.queue_free()

	if _results.is_empty():
		_add("No races yet", 0, Color(0.55, 0.55, 0.55))
		return

	for i in _results.size():
		var r: Dictionary = _results[i]
		var dark := ThemeManager.is_dark_mode
		var col := Color.WHITE if dark else Color.BLACK
		if i % 2 != 0:
			col = col.lerp(Color.GRAY, 0.4)
		_add("#%d  %s  —  %s" % [i + 1, r["name"], r["time"]], i, col)

func _show_live_race() -> void:
	# Hide the title during live race
	if is_instance_valid(_title):
		_title.visible = false

	# Create labels once, then reuse them
	if not _labels_created:
		_create_live_race_labels()
		_labels_created = true

	var dark := ThemeManager.is_dark_mode
	var text_col   := Color.WHITE if dark else Color.BLACK
	var accent_col := Color(0.3, 0.6, 1.0) if dark else Color(0.1, 0.3, 0.9)

	var target   := RaceManager.get_target_article()
	var time_str := RaceManager.get_elapsed_time_string()

	if is_instance_valid(_target_label):
		_target_label.text     = "🎯 %s" % target if target else "🎯 Loading..."
		_target_label.modulate = accent_col
		_target_label.visible  = true

	if is_instance_valid(_race_timer_label):
		_race_timer_label.text     = "⏱ %s" % time_str
		_race_timer_label.modulate = text_col
		_race_timer_label.visible  = true

	if is_instance_valid(_live_indicator):
		_live_indicator.modulate = Color(1.0, 0.2, 0.2)
		_live_indicator.visible  = true

func _create_live_race_labels() -> void:
	var dark := ThemeManager.is_dark_mode
	var text_col := Color.WHITE if dark else Color.BLACK
	var accent_col := Color(0.3, 0.6, 1.0) if dark else Color(0.1, 0.3, 0.9)
	
	# Create target label
	_target_label = _add_label("🎯 Target", Vector3(0, 0.9, 0.05), 0.004, 48, accent_col)
	_target_label.name = "TargetLabel"
	
	# Create timer label
	_race_timer_label = _add_label("⏱ 00:00", Vector3(0, 0.2, 0.05), 0.006, 72, text_col)
	_race_timer_label.name = "RaceTimer"
	
	# Create LIVE indicator
	_live_indicator = _add_label("🔴 LIVE", Vector3(0, -0.5, 0.05), 0.003, 36, Color(1.0, 0.2, 0.2))
	_live_indicator.name = "LiveIndicator"

func _add_label(text: String, position: Vector3, pixel_size: float, font_size: int, color: Color) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.position = position
	lbl.pixel_size = pixel_size
	lbl.font_size = font_size
	if _font:
		lbl.font = _font
	lbl.modulate = color
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.outline_size = 0
	lbl.no_depth_test = true
	add_child(lbl)
	return lbl


func _add(text: String, index: int, color: Color) -> void:
	var lbl := Label3D.new()
	lbl.name = "Entry%d" % index
	lbl.text = text
	lbl.position = Vector3(0, 0.7 - index * 0.32, 0.05)
	lbl.pixel_size = 0.005
	lbl.font_size = 64
	if _font:
		lbl.font = _font
	lbl.modulate = color
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.outline_size = 0
	lbl.no_depth_test = true
	add_child(lbl)
