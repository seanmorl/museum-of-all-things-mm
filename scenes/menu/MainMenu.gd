extends Control

signal start
signal settings
signal start_multiplayer
signal start_dedicated_host

const FACTS := [
	"Wikipedia has over 60 million articles in more than 300 languages.",
	"Each room door leads to another Wikipedia article — infinite museum!",
	"Every painting comes from Wikimedia Commons.",
	"Multiplayer supports up to 16 players exploring together.",
	"The race mode lets you vote on a target and race to find it first!",
	"Tournament mode: elimination brackets with multiple rounds.",
	"This project is open source — built with love for the community.",
	"Powered by Godot Engine — a free, open-source game engine.",
	"The Museum uses Wikipedia's API to fetch articles in real-time.",
	"Articles are converted into navigable 3D gallery spaces.",
	"Race against friends to see who navigates Wikipedia fastest!",
	"Originally created by m4ym4y (Maya) — the visionary behind MoAT.",
]

var _serif_font: Font = null
var _sans_font: Font = null
var _selected_index: int = 0
var _menu_nodes: Array[Control] = []
var _selection_bar: ColorRect = null
var _current_fact_index: int = 0
var _fact_timer: Timer = null
var _patch_popup: Control = null
var _trending_label: Label = null
var _trending_articles: Array = []
var _trending_index: int = 0
var _trending_timer: Timer = null

@onready var _logo_label: RichTextLabel = %LogoLabel
@onready var _button_container: VBoxContainer = %ButtonContainer
@onready var _fact_text: Label = %FactText
@onready var _tag_container: HBoxContainer = %TagContainer
@onready var _dc_placeholder: Control = %DCPlaceholder

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_serif_font = load("res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf")
	_sans_font = ThemeManager.get_reading_font()

	_build_ui()
	_update_selection(true)
	_setup_fact_timer()
	_populate_tags()
	_setup_trending_ticker()

	ThemeManager.dark_mode_changed.connect(_on_dark_mode_changed)
	ThemeManager.reading_font_changed.connect(_on_reading_font_changed)
	UIEvents.ui_cancel_pressed.connect(_on_ui_cancel_pressed)

	if Platform.is_web():
		for node in _menu_nodes:
			if node.name == "Quit":
				node.visible = false

	call_deferred("_entrance_animation")


func _on_dark_mode_changed(_d: bool) -> void:
	_apply_theme()


func _on_reading_font_changed(f: Font) -> void:
	_sans_font = f
	_apply_theme()


func _input(event: InputEvent) -> void:
	if not visible: return
	
	# Close patch popup with ESC
	if _patch_popup and event.is_action_pressed("ui_cancel"):
		_close_patch_popup()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_up"):
		_selected_index = posmod(_selected_index - 1, _menu_nodes.size())
		_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_index = posmod(_selected_index + 1, _menu_nodes.size())
		_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_on_item_selected(_selected_index)
		get_viewport().set_input_as_handled()

# ── Build ─────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Clear existing
	for c in _button_container.get_children():
		c.queue_free()
	_menu_nodes.clear()

	# Create selection bar (procedural glow added via code)
	_selection_bar = ColorRect.new()
	_selection_bar.custom_minimum_size = Vector2(4, 24)
	_selection_bar.color = Color.WHITE
	add_child(_selection_bar)
	_selection_bar.hide()
	
	# Add procedural glow using nested ColorRects (CSS-like glow)
	for i in range(3):
		var shadow := ColorRect.new()
		shadow.custom_minimum_size = _selection_bar.custom_minimum_size + Vector2(i*4, i*4)
		shadow.color = Color(0.4, 0.6, 1.0, 0.15 / (i + 1))
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_selection_bar.add_child(shadow)
		shadow.position = -Vector2(i*2, i*2)
		shadow.show()

	var items = [
		{"label": "Play Game", "icon": "🏛", "callback": _on_start_pressed},
		{"label": "Multiplayer", "icon": "🌐", "callback": _on_multiplayer_pressed},
		{"label": "Settings", "icon": "⚙", "callback": _on_settings_pressed},
		{"label": "Toggle Theme", "icon": "☾", "callback": _on_theme_toggle_pressed},
		{"label": "Latest Changes", "icon": "📋", "callback": _show_patch_notes},
		{"label": "DedicatedHost", "icon": "🖥", "callback": _on_dedicated_host_pressed}, # Named for Main.gd compatibility
		{"label": "Quit", "icon": "✕", "callback": _on_quit_pressed} # Named for Main.gd compatibility
	]

	for item in items:
		var btn_hbox := HBoxContainer.new()
		btn_hbox.name = item.label
		btn_hbox.add_theme_constant_override("separation", 16)
		btn_hbox.mouse_filter = Control.MOUSE_FILTER_STOP
		
		var icon_lbl := Label.new()
		icon_lbl.text = item.icon
		if item.label == "Toggle Theme":
			icon_lbl.text = "☾" if not ThemeManager.is_dark_mode else "☀"
			icon_lbl.name = "ThemeIcon"
		
		icon_lbl.add_theme_font_size_override("font_size", 18)
		icon_lbl.modulate.a = 0.6
		btn_hbox.add_child(icon_lbl)
		
		var lbl := Label.new()
		var label_text = item.label
		if label_text == "DedicatedHost": label_text = "Host Server"
		elif label_text == "Toggle Theme": label_text = "Light Mode" if ThemeManager.is_dark_mode else "Dark Mode"
		
		lbl.text = label_text
		if item.label == "Toggle Theme": lbl.name = "ThemeLabel"
		
		lbl.add_theme_font_override("font", _serif_font)
		lbl.add_theme_font_size_override("font_size", 20)
		btn_hbox.add_child(lbl)
		
		# For Main.gd %Quit access
		if item.label == "Quit":
			btn_hbox.unique_name_in_owner = true
		
		btn_hbox.gui_input.connect(_on_item_gui_input.bind(_menu_nodes.size()))
		btn_hbox.mouse_entered.connect(_on_item_mouse_entered.bind(_menu_nodes.size()))
		
		_button_container.add_child(btn_hbox)
		btn_hbox.owner = self
		_menu_nodes.append(btn_hbox)

	_apply_theme()


func _update_selection(instant: bool = false) -> void:
	for i in range(_menu_nodes.size()):
		var node = _menu_nodes[i]
		var is_selected = (i == _selected_index)
		
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# Improved readability: 0.6 instead of 0.4 for inactive items
		tw.tween_property(node, "modulate:a", 1.0 if is_selected else 0.6, 0.2)
		
		var target_x = 12 if is_selected else 0
		if instant:
			node.position.x = target_x
		else:
			tw.parallel().tween_property(node, "position:x", target_x, 0.2)
		
	if _selected_index < _menu_nodes.size():
		var target_node = _menu_nodes[_selected_index]
		_selection_bar.show()
		
		# Update bar color based on theme
		_selection_bar.color = ThemeManager.text_color
		
		var target_pos = target_node.global_position
		target_pos.x -= 24 # Offset to the left
		target_pos.y += (target_node.size.y - _selection_bar.size.y) / 2
		
		if instant:
			_selection_bar.global_position = target_pos
		else:
			var tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(_selection_bar, "global_position", target_pos, 0.2)


func _on_item_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_item_selected(index)


func _on_item_mouse_entered(index: int) -> void:
	if _selected_index != index:
		_selected_index = index
		_update_selection()


func _on_item_selected(index: int) -> void:
	match index:
		0: _on_start_pressed()
		1: _on_multiplayer_pressed()
		2: _on_settings_pressed()
		3: _on_theme_toggle_pressed()
		4: _show_patch_notes()
		5: _on_dedicated_host_pressed()
		6: _on_quit_pressed()

# ── Styling ───────────────────────────────────────────────────────────────────

func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode
	
	# Background (transparency handled by MainMenuBackground script)
	var bg_col = ThemeManager.bg_color
	bg_col.a = 0.6
	# $Background.color = bg_col <-- Removed because Background is now a Control with a draw script
	
	# Logo
	var logo_text_col := "#F0EDE8" if dark else "#1A1814"
	var accent_col := "#6BA3E8" if dark else "#3B7DD8"
	_logo_label.text = "[color=%s]M[/color][color=%s]·[/color][color=%s]AT[/color]" % [logo_text_col, accent_col, logo_text_col]
	
	# Subtitle
	%SubtitleLabel.add_theme_color_override("font_color", ThemeManager.subtext_color)
	
	# Menu Items
	for node in _menu_nodes:
		for child in node.get_children():
			if child is Label:
				child.add_theme_color_override("font_color", ThemeManager.text_color)
				# Reset icon modulation if it's the icon label
				if child.text.length() <= 2: # Likely an icon
					child.modulate.a = 0.6
	
	# Selection Bar Glow
	if _selection_bar:
		_selection_bar.color = ThemeManager.text_color
		for child in _selection_bar.get_children():
			if child is ColorRect:
				child.color = (Color(0.4, 0.6, 1.0) if dark else Color(0.2, 0.4, 0.8))
				child.color.a = 0.15 / (child.get_index() + 1)
	
	# Fact Panel
	var fact_style := StyleBoxFlat.new()
	fact_style.bg_color = ThemeManager.bg_color
	fact_style.bg_color.a = 0.4 if dark else 0.8
	fact_style.border_width_left = 1
	fact_style.border_width_top = 1
	fact_style.border_width_right = 1
	fact_style.border_width_bottom = 1
	fact_style.border_color = ThemeManager.border_color
	fact_style.corner_radius_top_left = 12
	fact_style.corner_radius_top_right = 12
	fact_style.corner_radius_bottom_right = 12
	fact_style.corner_radius_bottom_left = 12
	%FactPanel.add_theme_stylebox_override("panel", fact_style)
	
	_fact_text.add_theme_color_override("font_color", ThemeManager.text_color)
	
	# Update tags
	_populate_tags()
	
	# Footer
	$MainLayout/LeftCol/BrandingVBox/Footer/ModeDesc.add_theme_color_override("font_color", ThemeManager.subtext_color)
	$MainLayout/LeftCol/BrandingVBox/Footer/Sep.color = ThemeManager.border_color
	$EscHint.add_theme_color_override("font_color", ThemeManager.subtext_color)
	
	# Update trending ticker
	if _trending_label:
		_trending_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	# Update trending separator
	var trending_sep = get_node_or_null("MainLayout/RightCol/WidgetVBox/TrendingSep")
	if trending_sep:
		trending_sep.color = ThemeManager.border_color

# ── Tags ──────────────────────────────────────────────────────────────────────

func _populate_tags() -> void:
	for c in _tag_container.get_children():
		c.queue_free()
	
	var dark := ThemeManager.is_dark_mode
	var tags = ["Wikipedia-powered", "Multiplayer", "Open Source"]
	for t in tags:
		var lbl := Label.new()
		lbl.text = t
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_font_override("font", _sans_font)
		lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
		
		var style := StyleBoxFlat.new()
		style.bg_color = ThemeManager.bg_color
		style.bg_color.a = 0.1 if dark else 0.3
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = ThemeManager.border_color
		style.corner_radius_top_left = 20
		style.corner_radius_top_right = 20
		style.corner_radius_bottom_right = 20
		style.corner_radius_bottom_left = 20
		style.content_margin_left = 12
		style.content_margin_top = 4
		style.content_margin_right = 12
		style.content_margin_bottom = 4
		
		lbl.add_theme_stylebox_override("normal", style)
		_tag_container.add_child(lbl)


# ── Wikipedia Trending Ticker ─────────────────────────────────────────────────

func _setup_trending_ticker() -> void:
	# Create timer first
	_trending_timer = Timer.new()
	_trending_timer.wait_time = 4.0
	_trending_timer.timeout.connect(_on_trending_timer_timeout)
	add_child(_trending_timer)
	
	# WikipediaTrending is now an autoload
	var wt = get_node_or_null("/root/WikipediaTrending")
	if wt:
		wt.trending_updated.connect(_on_trending_updated)
		wt.fetch_failed.connect(_on_trending_failed)
		wt.fetch_trending()

	# Create ticker label at bottom of right column
	_trending_label = Label.new()
	_trending_label.name = "TrendingLabel"
	_trending_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trending_label.add_theme_font_override("font", _sans_font)
	_trending_label.add_theme_font_size_override("font_size", 11)
	_trending_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	_trending_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	# Add to right column, below tags
	var right_col = get_node_or_null("MainLayout/RightCol/WidgetVBox")
	if right_col:
		right_col.add_child(_trending_label)

		# Create separator above ticker
		var sep := ColorRect.new()
		sep.name = "TrendingSep"
		sep.custom_minimum_size.y = 1
		sep.color = ThemeManager.border_color
		right_col.add_child(sep)
		right_col.move_child(sep, right_col.get_child_count() - 2)

	_update_trending_display()


func _on_trending_updated(articles: Array) -> void:
	_trending_articles = articles
	_trending_index = 0
	_update_trending_display()
	if _trending_timer:
		_trending_timer.start()


func _on_trending_failed(error: String) -> void:
	# Don't show error, the hardcoded fallback will be used
	pass


func _on_trending_timer_timeout() -> void:
	if _trending_articles.size() > 1:
		_trending_index = (_trending_index + 1) % _trending_articles.size()
		# Fade out, update text, fade in
		var tw := create_tween()
		tw.tween_property(_trending_label, "modulate:a", 0.0, 0.5)
		tw.chain().tween_callback(_update_trending_display)
		tw.chain().tween_property(_trending_label, "modulate:a", 1.0, 0.5)


func _update_trending_display() -> void:
	if not _trending_label:
		return
	
	if _trending_articles.is_empty():
		_trending_label.text = "📈 Loading trending articles..."
		_trending_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
		return
	
	var article = _trending_articles[_trending_index]
	if _trending_articles.size() > 1:
		_trending_label.text = "📈 Trending: %s (%d/%d)" % [article, _trending_index + 1, _trending_articles.size()]
	else:
		_trending_label.text = "📈 Trending: %s" % article

# ── Animations ────────────────────────────────────────────────────────────────

func _entrance_animation() -> void:
	_logo_label.modulate.a = 0
	_button_container.modulate.a = 0
	%FactPanel.modulate.a = 0
	%TagContainer.modulate.a = 0
	%DCPlaceholder.modulate.a = 0
	
	# Reparent Daily Challenge Card if it exists in the tree - DISABLED
	# var card = get_tree().root.find_child("DailyChallengeCard", true, false)
	# if card and card.get_parent() != _dc_placeholder:
	# 	card.get_parent().remove_child(card)
	# 	_dc_placeholder.add_child(card)
	# 	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_logo_label, "modulate:a", 1.0, 0.8)
	tw.tween_property(_button_container, "modulate:a", 1.0, 0.8).set_delay(0.3)
	tw.tween_property(%FactPanel, "modulate:a", 1.0, 0.8).set_delay(0.5)
	tw.tween_property(%TagContainer, "modulate:a", 1.0, 0.8).set_delay(0.6)
	# Daily Challenge card disabled - not an important part of the game currently
	# tw.tween_property(%DCPlaceholder, "modulate:a", 1.0, 0.8).set_delay(0.7)
	
	# Staggered items
	var delay = 0.4
	for node in _menu_nodes:
		node.modulate.a = 0
		var twb := create_tween()
		twb.tween_property(node, "modulate:a", 1.0 if node == _menu_nodes[_selected_index] else 0.4, 0.4).set_delay(delay)
		delay += 0.08

# ── Fact Logic ────────────────────────────────────────────────────────────────

func _setup_fact_timer() -> void:
	_fact_timer = Timer.new()
	_fact_timer.wait_time = 8.0
	_fact_timer.timeout.connect(_on_fact_timer_timeout)
	add_child(_fact_timer)
	_fact_timer.start()

func _on_fact_timer_timeout() -> void:
	var tw := create_tween()
	tw.tween_property(_fact_text, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(_cycle_fact)
	tw.chain().tween_property(_fact_text, "modulate:a", 1.0, 0.5)

func _cycle_fact() -> void:
	_current_fact_index = (_current_fact_index + 1) % FACTS.size()
	_fact_text.text = FACTS[_current_fact_index]

func _on_ui_cancel_pressed() -> void:
	if not visible: return
	if _selected_index != _menu_nodes.size() - 1: # If not on Quit
		_selected_index = _menu_nodes.size() - 1
		_update_selection()
	else:
		_on_quit_pressed()

# ── Signal Handlers ───────────────────────────────────────────────────────────

func _on_start_pressed() -> void:
	start.emit()

func _on_settings_pressed() -> void:
	settings.emit()

func _on_multiplayer_pressed() -> void:
	start_multiplayer.emit()

func _on_dedicated_host_pressed() -> void:
	start_dedicated_host.emit()


func _on_theme_toggle_pressed() -> void:
	ThemeManager.toggle()
	# Update the label and icon for the toggle button
	var theme_node = null
	for node in _menu_nodes:
		if node.name == "Toggle Theme":
			theme_node = node
			break

	if theme_node:
		var icon = theme_node.get_node_or_null("ThemeIcon")
		var label = theme_node.get_node_or_null("ThemeLabel")
		if icon: icon.text = "☾" if not ThemeManager.is_dark_mode else "☀"
		if label: label.text = "Light Mode" if ThemeManager.is_dark_mode else "Dark Mode"


func _show_patch_notes() -> void:
	if _patch_popup:
		_patch_popup.queue_free()
		_patch_popup = null
		return
	
	_patch_popup = Control.new()
	_patch_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_patch_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_patch_popup)
	
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_patch_popup.add_child(dim)
	
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -350.0
	panel.offset_top = -280.0
	panel.offset_right = 350.0
	panel.offset_bottom = 280.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_patch_popup.add_child(panel)
	
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = ThemeManager.bg_color
	panel_style.border_color = ThemeManager.border_color
	for s in ["left", "right", "top", "bottom"]:
		panel_style.set("border_width_" + s, 1)
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		panel_style.set("corner_radius_" + c, 12)
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 28
	panel_style.shadow_offset = Vector2(0, 8)
	panel.add_theme_stylebox_override("panel", panel_style)
	
	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 24)
	outer.add_theme_constant_override("margin_right", 24)
	outer.add_theme_constant_override("margin_top", 20)
	outer.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(outer)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	outer.add_child(vbox)
	
	var header := HBoxContainer.new()
	vbox.add_child(header)
	
	var title := Label.new()
	title.text = "📋 Latest Changes"
	title.add_theme_font_override("font", _serif_font)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", ThemeManager.text_color)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(_close_patch_popup)
	header.add_child(close_btn)
	
	vbox.add_child(HSeparator.new())
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	
	var notes := [
		{"title": "🎨 UI & Graphics Overhaul", "items": [
			"New full-screen race countdown (3 → 2 → 1 → GO)",
			"New loading screen with animated spinner",
			"VictoryScreen with gold starburst animation",
			"Session leaderboard overlay (press Tab)",
			"Animated main menu background",
			"Rewritten VoteHUD, RaceHUD, PlayerListOverlay"
		]},
		{"title": "🐛 Bug Fixes", "items": [
			"Hint system removed (multiplayer sync issues)",
			"Race win detection fixed for single-player",
			"Countdown double-fire bug fixed",
			"Loading screen flash bug fixed",
			"JournalOverlay dark mode crash fixed",
			"Multiple parser errors fixed"
		]},
		{"title": "⚠️ Known Issues", "items": [
			"Power-ups temporarily disabled (being reworked)",
			"Daily Challenge card hidden from main menu"
		]}
	]
	
	for section in notes:
		var section_title := Label.new()
		section_title.text = section.title
		section_title.add_theme_font_override("font", _serif_font)
		section_title.add_theme_font_size_override("font_size", 16)
		section_title.add_theme_color_override("font_color", ThemeManager.text_color)
		content.add_child(section_title)
		
		for item in section.items:
			var item_lbl := Label.new()
			item_lbl.text = "• " + item
			item_lbl.add_theme_font_override("font", _sans_font)
			item_lbl.add_theme_font_size_override("font_size", 13)
			item_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
			item_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			content.add_child(item_lbl)
		
		if section != notes[-1]:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, 8)
			content.add_child(spacer)
	
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vbox.add_child(footer)
	
	var refresh_btn := Button.new()
	refresh_btn.text = "↻ Refresh"
	refresh_btn.pressed.connect(_on_patch_refresh_pressed)
	footer.add_child(refresh_btn)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	
	var ok_btn := Button.new()
	ok_btn.text = "Close"
	ok_btn.pressed.connect(_close_patch_popup)
	footer.add_child(ok_btn)
	
	_style_patch_btn(close_btn, false)
	_style_patch_btn(refresh_btn, false)
	_style_patch_btn(ok_btn, true)
	
	_patch_popup.modulate.a = 0.0
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_patch_popup, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(panel, "scale", Vector2(1, 1), 0.25)


func _close_patch_popup() -> void:
	if not _patch_popup: return
	var popup_to_free := _patch_popup
	_patch_popup = null
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(popup_to_free, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(func(): popup_to_free.queue_free())


func _on_patch_refresh_pressed() -> void:
	_close_patch_popup()
	call_deferred("_show_patch_notes")


func _style_patch_btn(btn: Button, primary: bool) -> void:
	btn.add_theme_font_override("font", _sans_font)
	btn.add_theme_font_size_override("font_size", 14)
	if primary:
		btn.add_theme_color_override("font_color", ThemeManager.text_color)
		btn.add_theme_color_override("font_hover_color", ThemeManager.text_color)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.1) if ThemeManager.is_dark_mode else Color(0, 0, 0, 0.05)
		style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color.a = 0.2 if ThemeManager.is_dark_mode else 0.1
		btn.add_theme_stylebox_override("hover", hover)
	else:
		btn.add_theme_color_override("font_color", ThemeManager.subtext_color)
		btn.add_theme_color_override("font_hover_color", ThemeManager.text_color)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", style)


func _on_quit_pressed() -> void:

	get_tree().quit()
