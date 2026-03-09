extends Control

@onready var player_container = $PanelContainer/MarginContainer/VBoxContainer/PlayerListContainer

func _ready() -> void:
	NetworkManager.peer_connected.connect(_refresh)
	NetworkManager.peer_disconnected.connect(_refresh)
	NetworkManager.player_info_updated.connect(_refresh)
	visibility_changed.connect(_on_visibility_changed)
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	_apply_theme()


func _apply_theme() -> void:
	var title = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/Title")
	if title:
		title.label_settings = null
		title.add_theme_color_override("font_color", ThemeManager.text_color)
		title.add_theme_font_override("font", ThemeManager.get_reading_font())
	
	var panel = get_node_or_null("PanelContainer")
	if panel:
		var style := StyleBoxFlat.new()
		style.bg_color = ThemeManager.bg_color
		style.border_color = ThemeManager.border_color
		style.border_width_left = 1; style.border_width_top = 1
		style.border_width_right = 1; style.border_width_bottom = 1
		style.corner_radius_top_left = 8; style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8; style.corner_radius_bottom_right = 8
		panel.add_theme_stylebox_override("panel", style)


func _on_visibility_changed() -> void:
	if visible:
		_refresh()

func _refresh(_id: Variant = null) -> void:
	if not is_inside_tree():
		return

	for child in player_container.get_children():
		child.queue_free()

	for peer_id in NetworkManager.get_player_list():
		var vbox := VBoxContainer.new()
		
		var label = Label.new()
		var player_name = NetworkManager.get_player_name(peer_id)
		var suffix = " (Host)" if peer_id == 1 else ""
		var you = " (You)" if peer_id == NetworkManager.get_unique_id() else ""
		label.text = player_name + suffix + you
		label.add_theme_color_override("font_color", NetworkManager.get_player_color(peer_id))
		label.add_theme_font_override("font", ThemeManager.get_reading_font())
		vbox.add_child(label)
		
		var room_label := Label.new()
		var room_name := NetworkManager.get_player_room(peer_id)
		room_label.text = "  Location: " + room_name
		room_label.add_theme_font_size_override("font_size", 10)
		room_label.add_theme_color_override("font_color", Color(ThemeManager.text_color.r, ThemeManager.text_color.g, ThemeManager.text_color.b, 0.7))
		room_label.add_theme_font_override("font", ThemeManager.get_reading_font())
		vbox.add_child(room_label)
		
		player_container.add_child(vbox)
