extends Control
class_name PowerupNotification
## Shows notifications when other players collect/use powerups.

const ICONS := {
	PowerupManager.PowerupType.SPEED_BOOST: "⚡",
	PowerupManager.PowerupType.PERFECT_KNOWLEDGE: "👁",
	PowerupManager.PowerupType.GUN: "🔫",
	PowerupManager.PowerupType.TRAP: "💣",
	PowerupManager.PowerupType.TOWER_OF_BABEL: "🗼",
	PowerupManager.PowerupType.LIGHTS_OUT: "🌑",
	PowerupManager.PowerupType.MAGNET: "🧲"
}

const COLORS := {
	PowerupManager.PowerupType.SPEED_BOOST: Color(1.0, 0.8, 0.0),
	PowerupManager.PowerupType.PERFECT_KNOWLEDGE: Color(0.0, 1.0, 1.0),
	PowerupManager.PowerupType.GUN: Color(1.0, 0.2, 0.2),
	PowerupManager.PowerupType.TRAP: Color(0.2, 1.0, 0.2),
	PowerupManager.PowerupType.TOWER_OF_BABEL: Color(0.6, 0.4, 0.9),
	PowerupManager.PowerupType.LIGHTS_OUT: Color(0.1, 0.1, 0.3),
	PowerupManager.PowerupType.MAGNET: Color(0.8, 0.2, 0.5)
}

@onready var _container: VBoxContainer = $MarginContainer/VBoxContainer

var _serif_font: Font = null
var _sans_font: Font = null

func _ready() -> void:
	visible = false
	_serif_font = load("res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf")
	_sans_font = load("res://assets/fonts/NotoSans/NotoSans-Regular.ttf")
	
	# Connect to network powerup events
	PowerupManager.powerup_collected_network.connect(_on_powerup_collected)
	PowerupManager.powerup_used_network.connect(_on_powerup_used)

func _on_powerup_collected(player_id: int, powerup_type: int) -> void:
	if player_id == NetworkManager.get_unique_id():
		return  # Don't notify for self
	
	var player_name = NetworkManager.get_player_name(player_id)
	var powerup_name = PowerupManager.get_powerup_name(powerup_type)
	var icon = ICONS[powerup_type]
	var color = COLORS[powerup_type]
	
	_show_notification("%s collected %s!" % [player_name, powerup_name], icon, color)

func _on_powerup_used(player_id: int, powerup_type: int) -> void:
	if player_id == NetworkManager.get_unique_id():
		return  # Don't notify for self
	
	var player_name = NetworkManager.get_player_name(player_id)
	var powerup_name = PowerupManager.get_powerup_name(powerup_type)
	var icon = ICONS[powerup_type]
	var color = COLORS[powerup_type]
	
	var message = ""
	match powerup_type:
		PowerupManager.PowerupType.GUN:
			message = "%s fired the %s!" % [player_name, powerup_name]
		PowerupManager.PowerupType.TRAP:
			message = "%s placed a %s!" % [player_name, powerup_name]
		PowerupManager.PowerupType.MAGNET:
			message = "%s activated %s!" % [player_name, powerup_name]
		_:
			message = "%s used %s!" % [player_name, powerup_name]
	
	_show_notification(message, icon, color)

func _show_notification(message: String, icon: String, color: Color) -> void:
	var notification = _create_notification(message, icon, color)
	_container.add_child(notification)
	
	# Animate in
	notification.modulate.a = 0.0
	notification.position.x = 300.0
	var tw := create_tween()
	tw.tween_property(notification, "modulate:a", 1.0, 0.3).set_delay(0.1)
	tw.tween_property(notification, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.1)
	
	# Auto-remove after 4 seconds
	await get_tree().create_timer(4.0).timeout
	_animate_out(notification)

func _create_notification(message: String, icon: String, color: Color) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 60)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.border_color = color
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)
	
	# Icon
	var icon_label = Label.new()
	icon_label.text = icon
	icon_label.add_theme_font_size_override("font_size", 32)
	hbox.add_child(icon_label)
	
	# Text
	var text_label = Label.new()
	text_label.text = message
	text_label.add_theme_font_size_override("font_size", 14)
	if _sans_font:
		text_label.add_theme_font_override("font", _sans_font)
	text_label.add_theme_color_override("font_color", Color.WHITE)
	hbox.add_child(text_label)
	
	return panel

func _animate_out(notification: PanelContainer) -> void:
	var tw := create_tween()
	tw.tween_property(notification, "modulate:a", 0.0, 0.2)
	tw.tween_property(notification, "position:x", 300.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(notification.queue_free)
