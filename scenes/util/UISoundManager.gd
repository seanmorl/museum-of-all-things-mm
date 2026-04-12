extends Node

@export var button_press_sound: AudioStream
@export var focus_sound: AudioStream
@export var drag_ended_sound: AudioStream

func _on_node_added(node):
	if node is Button:
		var press_callable = _play.bind(button_press_sound)
		if not node.pressed.is_connected(press_callable):
			node.pressed.connect(press_callable)
		
		var focus_callable = _play.bind(focus_sound)
		if not node.focus_entered.is_connected(focus_callable):
			node.focus_entered.connect(focus_callable)
	elif node is Slider:
		if not node.value_changed.is_connected(_slider_value_changed):
			node.value_changed.connect(_slider_value_changed)
		
		var focus_callable = _play.bind(focus_sound)
		if not node.focus_entered.is_connected(focus_callable):
			node.focus_entered.connect(focus_callable)

func _slider_value_changed(_value):
	_play(drag_ended_sound)

func _play(sfx):
	if sfx == null:
		return
	var player = AudioStreamPlayer.new()
	player.stream = sfx
	player.bus = &"Sound"
	add_child(player)
	player.finished.connect(_sound_finished.bind(player))
	player.play()

func _sound_finished(player):
	player.queue_free()

func _traverse_tree(node):
	for c in node.get_children():
		_on_node_added(c)
		_traverse_tree(c)

func _ready() -> void:
	get_tree().create_timer(1.0).timeout.connect(_init_sounds)

func _init_sounds():
	get_tree().node_added.connect(_on_node_added)
	_traverse_tree(get_tree().get_root())
