extends Node
## Test script for raw PCM playback
## This tests if Godot can play Piper's raw PCM output without static

@onready var player: AudioStreamPlayer = $AudioStreamPlayer
@onready var label: Label = $Label

var pcm_data: PackedByteArray = []


func _ready() -> void:
	label.text = "Loading PCM data..."
	_load_pcm_file()


func _load_pcm_file() -> void:
	var file_path = "user://piper_voices/test_raw.pcm"
	var absolute_path = ProjectSettings.globalize_path(file_path)
	
	if not FileAccess.file_exists(absolute_path):
		label.text = "ERROR: PCM file not found!\nPath: " + absolute_path
		return
	
	var file = FileAccess.open(absolute_path, FileAccess.READ)
	pcm_data = file.get_buffer(file.get_length())
	file.close()
	
	label.text = "PCM loaded: %d bytes\nClick to test playback" % pcm_data.size()
	print("[PCM Test] Loaded %d bytes of PCM data" % pcm_data.size())


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if pcm_data.size() > 0:
			_play_pcm()


func _play_pcm() -> void:
	label.text = "Playing... (volume at 10% for safety)"
	print("[PCM Test] Starting playback...")
	
	# Create AudioStreamGenerator
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = 22050  # Piper's sample rate
	generator.buffer_frames = 4096
	
	# Create player
	var player = AudioStreamPlayer.new()
	player.stream = generator
	player.volume_db = -20  # 10% volume (safe!)
	add_child(player)
	
	# Connect to fill buffer
	var playback = player.get_stream_playback()
	
	# Fill buffer with PCM data
	var frames_to_write = pcm_data.size() / 4  # 16-bit stereo = 4 bytes per frame
	var written = 0
	
	while written < frames_to_write and playback.can_append_buffer():
		var chunk_size = min(1024, frames_to_write - written)
		var chunk = pcm_data.slice(written * 4, (written + chunk_size) * 4)
		
		# Convert to Vector2 format (stereo)
		var samples = []
		for i in range(0, chunk.size(), 4):
			var left = chunk.decode_s16(i)
			var right = chunk.decode_s16(i + 2) if i + 2 < chunk.size() else left
			samples.append(Vector2(left / 32768.0, right / 32768.0))
		
		playback.append_array(samples)
		written += chunk_size
	
	player.play()
	print("[PCM Test] Playback started, %d frames written" % written)
	
	# Wait for playback to finish
	await get_tree().create_timer(10.0).timeout
	label.text = "Playback complete!\nClick to play again"
	print("[PCM Test] Playback finished")
	
	# Cleanup
	player.queue_free()
