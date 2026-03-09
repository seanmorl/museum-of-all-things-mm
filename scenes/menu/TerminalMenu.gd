extends Control

signal resume

var _awaiting_result: bool = false
var _bg_panel: PanelContainer = null
var _separator: ColorRect = null
var _serif_font: Font = null
var _mono_font: Font = load("res://assets/fonts/NotoSansMono/static/NotoSansMono-Regular.ttf")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_serif_font = ThemeManager.get_reading_font()
	_setup_ui_structure()
	
	UIEvents.open_terminal_menu.connect(reset)
	UIEvents.terminal_result_ready.connect(_on_terminal_result_ready)
	UIEvents.ui_cancel_pressed.connect(_resume)
	UIEvents.ui_accept_pressed.connect(_handle_accept)
	ExhibitFetcher.search_complete.connect(_show_page_result)
	ExhibitFetcher.random_complete.connect(_show_page_result)
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	_apply_theme()
	reset()

func _setup_ui_structure() -> void:
	# Add a background panel if it doesn't exist
	if not _bg_panel:
		_bg_panel = PanelContainer.new()
		_bg_panel.name = "TerminalBackground"
		_bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE # Don't block clicks!
		add_child(_bg_panel)
		move_child(_bg_panel, 0) # Back of the bus
		_bg_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	if not _separator:
		_separator = ColorRect.new()
		_separator.name = "TerminalSeparator"
		_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_separator)

func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode
	
	if _bg_panel:
		var style := StyleBoxFlat.new()
		# In light mode, let's keep the terminal slightly off-white for better visual separation
		style.bg_color = ThemeManager.bg_color if dark else Color(0.96, 0.96, 0.96)
		style.border_color = ThemeManager.border_color
		style.border_width_left = 2; style.border_width_top = 2
		style.border_width_right = 2; style.border_width_bottom = 2
		style.set_corner_radius_all(10)
		style.shadow_color = Color(0, 0, 0, 0.4 if dark else 0.15)
		style.shadow_size = 24
		_bg_panel.add_theme_stylebox_override("panel", style)

	if _separator:
		_separator.color = ThemeManager.border_color
		var mc = get_node_or_null("MarginContainer")
		if mc:
			# Place it below the title area (moved down to clear the title text)
			_separator.position = Vector2(16, 140)
			_separator.size = Vector2(size.x - 32, 1)

	# Style all labels and buttons recursively
	_style_terminal_node(self)
	
	# Modulate logo
	var logo = get_node_or_null("LogoContainer/MoatLogoSmall")
	if logo:
		logo.modulate = Color(1, 1, 1, 0.8) # Stronger visibility in light mode
		$LogoContainer.move_to_front() # Ensure it's rendered on top of everything else

func _style_terminal_node(node: Node) -> void:
	if node is Label:
		node.label_settings = null
		node.add_theme_color_override("font_color", ThemeManager.text_color)
		node.add_theme_font_override("font", _mono_font)
		# Header styling for the main welcome label
		if node.text.begins_with("Welcome"):
			node.add_theme_font_size_override("font_size", 20)
			node.add_theme_color_override("font_color", ThemeManager.text_color)
	elif node is Button:
		_style_terminal_button(node)
	elif node is LineEdit:
		_style_terminal_line_edit(node)
	
	for child in node.get_children():
		_style_terminal_node(child)

func _style_terminal_button(btn: Button) -> void:
	var dark := ThemeManager.is_dark_mode
	btn.add_theme_font_override("font", _mono_font)
	btn.add_theme_font_size_override("font_size", 14)
	
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ThemeManager.text_color)
	
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(1, 1, 1, 0.05) if dark else Color(0, 0, 0, 0.05)
	sn.border_color = ThemeManager.border_color
	sn.border_width_left = 1; sn.border_width_top = 1
	sn.border_width_right = 1; sn.border_width_bottom = 1
	sn.set_corner_radius_all(4)
	sn.content_margin_left = 12; sn.content_margin_right = 12
	sn.content_margin_top = 6; sn.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sn)
	
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(1, 1, 1, 0.12) if dark else Color(0, 0, 0, 0.1)
	sh.border_color = ThemeManager.text_color
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("focus", sh)
	
	var sp := sh.duplicate() as StyleBoxFlat
	sp.bg_color = Color(1, 1, 1, 0.2) if dark else Color(0, 0, 0, 0.15)
	btn.add_theme_stylebox_override("pressed", sp)

func _style_terminal_line_edit(edit: LineEdit) -> void:
	var dark := ThemeManager.is_dark_mode
	edit.add_theme_font_override("font", _mono_font)
	edit.add_theme_color_override("font_color", ThemeManager.text_color)
	edit.add_theme_color_override("font_placeholder_color", Color(ThemeManager.text_color, 0.4))
	
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0.2) if dark else Color(1, 1, 1, 0.2)
	sn.border_color = ThemeManager.border_color
	sn.border_width_bottom = 2
	sn.content_margin_left = 10; sn.content_margin_right = 10
	sn.content_margin_top = 8; sn.content_margin_bottom = 8
	edit.add_theme_stylebox_override("normal", sn)
	edit.add_theme_stylebox_override("focus", sn)

func _resume() -> void:
	resume.emit()

func reset() -> void:
	_awaiting_result = false
	var mc = get_node_or_null("MarginContainer")
	if mc:
		mc.get_node("StartPage/RandomExhibit").disabled = false
		mc.get_node("SearchPage/SearchExhibit").disabled = false
		_switch_to_page("StartPage")
		mc.get_node("StartPage/EnterExhibit").grab_focus()

func _switch_to_page(page: String) -> void:
	var mc = get_node_or_null("MarginContainer")
	if not mc: return
	for vbox in mc.get_children():
		if vbox is VBoxContainer:
			vbox.visible = false
	var p = mc.get_node_or_null(page)
	if p: p.visible = true

func _go_to_search_page() -> void:
	_switch_to_page("SearchPage")
	UIEvents.emit_reset_custom_door()
	var edit = get_node_or_null("MarginContainer/SearchPage/ExhibitTitle")
	if edit: edit.grab_focus()

func _get_random_page() -> void:
	var btn = get_node_or_null("MarginContainer/StartPage/RandomExhibit")
	if btn: btn.disabled = true
	UIEvents.emit_reset_custom_door()
	_awaiting_result = true
	ExhibitFetcher.fetch_random(null)

func _handle_accept() -> void:
	var edit = get_node_or_null("MarginContainer/SearchPage/ExhibitTitle")
	if edit and edit.has_focus():
		_search_exhibit()

func _search_exhibit() -> void:
	var edit = get_node_or_null("MarginContainer/SearchPage/ExhibitTitle")
	if not edit: return
	var search_text = edit.text
	if len(search_text) > 0:
		var btn = get_node_or_null("MarginContainer/SearchPage/SearchExhibit")
		if btn: btn.disabled = true
		_awaiting_result = true
		ExhibitFetcher.fetch_search(search_text, null)

func _show_page_result(page: Variant, _ctx: Variant) -> void:
	if not _awaiting_result:
		return
	_awaiting_result = false
	var edit = get_node_or_null("MarginContainer/SearchPage/ExhibitTitle")
	if edit: edit.text = ""
	_on_terminal_result_ready(not page, page if page else "")

func _on_terminal_result_ready(error: bool, page: String) -> void:
	if error:
		_switch_to_page("ErrorPage")
		var btn = get_node_or_null("MarginContainer/ErrorPage/Reset")
		if btn: btn.grab_focus()
	else:
		_switch_to_page("ResultPage")
		var main := get_tree().get_first_node_in_group("main")
		if main and main.has_method("sync_custom_door"):
			main.sync_custom_door(page)
		else:
			UIEvents.emit_set_custom_door(page)
		
		var lbl = get_node_or_null("MarginContainer/ResultPage/ResultLabel")
		if lbl: lbl.text = "Exhibit Found: \"%s\"" % page
		var btn = get_node_or_null("MarginContainer/ResultPage/Reset")
		if btn: btn.grab_focus()

func _on_reset_pressed() -> void:
	reset()
	_resume()
