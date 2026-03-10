extends Control

@onready var texture_rect: TextureRect = $Panel/TextureRect

var _active: bool = false
var _player: Node = null

func _ready() -> void:
	visible = false
	_active = false

func init(player: Node) -> void:
	_player = player

func _process(_delta: float) -> void:
	if visible and _player and _player.has_method("get_minimap_texture"):
		texture_rect.texture = _player.get_minimap_texture()

func toggle() -> void:
	_active = !_active
	visible = _active

func set_hidden() -> void:
	_active = false
	visible = false

func restore_after_pause() -> void:
	if _active:
		visible = true
