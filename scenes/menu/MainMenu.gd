extends Control

signal start
signal settings
signal start_multiplayer
signal start_dedicated_host

const FACTS := [
	"The Museum of All Things is procedurally generated — every exhibit is unique!",
	"You can explore MOAT with up to 16 players in multiplayer mode.",
	"Each exhibit hallway is generated from real Wikipedia article links.",
	"MOAT supports 8 languages: English, Portuguese, French, Spanish, Japanese, German, Bengali, and Chinese.",
	"Images in exhibits are pulled automatically from Wikimedia Commons.",
	"The article text you read on plaques is fetched live from Wikipedia.",
	"MOAT is built in the Godot Engine — a free, open-source game engine.",
	"You can host your own MOAT server with the --headless --server flags.",
	"Press ~ or F12 in debug builds to open the developer console.",
	"Press T in-game to open the chat system.",
	"You can vote on which article to race to at the start of each round.",
	"MOAT has a tournament mode with bracket or round-robin formats.",
	"Player skins can be set to any Wikimedia Commons image URL.",
	"Press M to toggle the minimap while exploring.",
	"Press J to open your exploration journal.",
	"Dash by pressing Shift to move faster between exhibits.",
	"You can mount other players by pressing E near them!",
	"Press Q to point at interesting exhibits for other players.",
	"MOAT features King of the Hill events that pause your timer outside the zone.",
	"Event warnings flash before environmental effects change the museum.",
	"The museum has themed architectural features that change per exhibit.",
	"VR mode is supported via OpenXR with dynamic foveation on Meta Quest.",
	"Discord Rich Presence shows what exhibit you're exploring.",
	"The path trail minimap shows your route through the museum.",
	"Audio exhibits let you listen to music and sounds from Wikimedia.",
	"Secret walls can sometimes lead to hidden exhibits.",
	"The Museum of All Things is free and open-source — built with love for the community.",
	"Wikipedia has over 60 million articles in more than 300 languages.",
	"Originally created by m4ym4y (Maya) — the visionary behind MoAT.",
	"Honey never spoils — archaeologists have found edible 3,000-year-old honey in Egyptian tombs.",
	"Octopuses have three hearts, nine brains, and blue blood.",
	"A day on Venus is longer than a year on Venus.",
	"The shortest war in history lasted 38 minutes — between Britain and Zanzibar in 1896.",
	"There are more possible iterations of a game of chess than atoms in the observable universe.",
	"Bananas are berries, but strawberries aren't.",
	"The inventor of the Pringles can is buried in one.",
	"Scotland's national animal is the unicorn.",
	"A cloud can weigh more than a million pounds.",
	"Venus is the only planet that spins clockwise.",
	"There are more trees on Earth than stars in the Milky Way.",
	"Sharks existed before trees — by over 100 million years.",
	"The Eiffel Tower can be 15 cm taller during summer due to thermal expansion.",
	"A jiffy is an actual unit of time — 1/100th of a second.",
	"Nintendo was founded in 1889 as a playing card company.",
	"Oxford University is older than the Aztec Empire.",
	"Cleopatra lived closer in time to the Moon landing than to the construction of the Great Pyramid.",
	"The human brain uses about 20% of the body's total energy.",
	"Wombat poop is cube-shaped.",
	"The longest English word without a repeated letter is 'uncopyrightable' (15 letters).",
	"There are 293 ways to make change for a US dollar.",
	"A group of flamingos is called a 'flamboyance'.",
	"The @ symbol has been used for over 500 years — since the 16th century.",
	"Titanic was the subject of a fictional book in 1898, 14 years before the real ship sank.",
	"Tip: Follow links from one exhibit to discover entirely new wings of the museum.",
	"Tip: Use the race system to compete with friends — vote on your destination!",
	"Tip: The minimap tracks your path — retrace your steps to find your way back.",
	"Tip: Tournament mode supports both fixed rounds and first-to-N formats.",
	"Tip: Events can change the rules of the museum — stay alert for warnings!",
	"Tip: Use the journal to bookmark interesting exhibits for later.",
	"Tip: The dedicated server lets your friends join even when you're not playing.",
	"Tip: MOAT scales from low-end to high-end PCs — adjust graphics in settings.",
	"Tip: Set your pronouns in the multiplayer menu — they appear for all players.",
	"Tip: Player reactions let you emote with number keys 1-8.",
	"Tip: The museum generates infinitely — you'll never run out of new exhibits.",
	"Tip: Every exhibit has a unique mood and atmosphere based on its content.",
	"Tip: Not all doors lead forward — some lead to surprising side exhibits.",
	"Tip: Tab shows which players are currently online.",
]

# ── WCAG 2.4.7 Focus Indicator Constants ─────────────────────────────────────
# 3px border exceeds the WCAG minimum 2px; colours chosen for >=3:1 contrast.
const FOCUS_BORDER_WIDTH := 3
const FOCUS_CORNER_RADIUS := 8
const FOCUS_COLOR_DARK  := Color(0.31, 0.55, 1.0)   # bright blue on dark bg
const FOCUS_COLOR_LIGHT := Color(0.11, 0.34, 0.73)   # deep blue on light bg

var _serif_font: Font = null
var _sans_font: Font = null
var _menu_buttons: Array[Button] = []
var _current_fact_index: int = 0
var _fact_timer: Timer = null
var _fact_order: Array[int] = []
var _patch_popup: Control = null
var _trending_label: Label = null
var _trending_articles: Array = []
var _trending_index: int = 0
var _trending_timer: Timer = null
var _available_locales: Array[String] = []
var _current_locale_index: int = 0

@onready var _logo_label: RichTextLabel = %LogoLabel
@onready var _button_container: VBoxContainer = %ButtonContainer
@onready var _fact_text: Label = %FactText
@onready var _tag_container: HBoxContainer = %TagContainer
@onready var _dc_placeholder: Control = %DCPlaceholder

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_serif_font = load("res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf")
	_sans_font = ThemeManager.get_reading_font()

	_build_menu()
	_setup_fact_timer()
	_populate_tags()
	_setup_trending_ticker()
	_setup_language_list()

	ThemeManager.dark_mode_changed.connect(_on_dark_mode_changed)
	ThemeManager.reading_font_changed.connect(_on_reading_font_changed)
	UIEvents.ui_cancel_pressed.connect(_on_ui_cancel_pressed)
	SettingsEvents.language_changed.connect(_on_language_changed_from_settings)

	if Platform.is_web():
		for btn in _menu_buttons:
			if btn.name == "Quit":
				btn.visible = false

	call_deferred("_entrance_animation")


func _on_dark_mode_changed(_d: bool) -> void:
	_apply_theme()


func _on_reading_font_changed(f: Font) -> void:
	_sans_font = f
	_apply_theme()


func _setup_language_list() -> void:
	_available_locales = ["en"]
	for locale in TranslationServer.get_loaded_locales():
		if locale != "en":
			_available_locales.append(locale)
	_current_locale_index = _available_locales.find(LanguageManager.get_locale())
	if _current_locale_index < 0:
		_current_locale_index = 0


func _on_language_changed_from_settings(language: String) -> void:
	_current_locale_index = _available_locales.find(language)
	if _current_locale_index < 0:
		_current_locale_index = 0
	_update_language_toggle_ui()
	# Rebuild buttons to pick up translated labels
	_build_menu()


# ── Build Menu ────────────────────────────────────────────────────────────────

func _build_menu() -> void:
	for c in _button_container.get_children():
		c.queue_free()
	_menu_buttons.clear()

	var items := [
		{"label": tr("Play Game"),    "icon": "🏛", "name": "Play",           "action": _on_start_pressed},
		{"label": tr("Multiplayer"),  "icon": "🌐", "name": "Multiplayer",    "action": _on_multiplayer_pressed},
		{"label": tr("Settings"),     "icon": "⚙",  "name": "Settings",       "action": _on_settings_pressed},
		{"label": tr("Toggle Theme"), "icon": "☾",  "name": "Toggle Theme",   "action": _on_theme_toggle_pressed},
		{"label": tr("Language"),     "icon": "🌍", "name": "Language",       "action": _on_language_toggle_pressed},
		{"label": tr("Latest Changes"), "icon": "📋", "name": "LatestChanges", "action": _show_patch_notes},
		{"label": tr("DedicatedHost"), "icon": "🖥",  "name": "DedicatedHost", "action": _on_dedicated_host_pressed},
		{"label": tr("Quit"),         "icon": "✕",  "name": "Quit",           "action": _on_quit_pressed},
	]

	for item in items:
		var btn := Button.new()
		btn.name = item.name
		btn.focus_mode = Control.FOCUS_ALL

		# Build display text with icon + label
		var display_text: String = item.label
		if item.name == "DedicatedHost":
			display_text = "Host Server"
		elif item.name == "Toggle Theme":
			display_text = ("Light Mode" if ThemeManager.is_dark_mode else "Dark Mode")
		elif item.name == "Language":
			display_text = _get_current_language_name()

		btn.text = item.icon + "  " + display_text
		btn.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT

		# ── WCAG 2.4.7: StyleBoxFlat with explicit focus state ─────────
		# Every state gets a StyleBoxFlat so the focus ring is always
		# drawn by Godot's own rendering — no manual overlay needed.
		_apply_button_style(btn)

		btn.pressed.connect(item.action)
		btn.custom_minimum_size = Vector2(280, 44)
		# Hover → focus sync: mouse hover also grabs keyboard focus so the
		# focus indicator follows the pointer (WCAG 2.4.7 / 1.4.11).
		btn.mouse_entered.connect(btn.grab_focus)

		_button_container.add_child(btn)
		btn.owner = self
		_menu_buttons.append(btn)

	# ── WCAG 2.4.7: Focus neighbour chain ─────────────────────────────
	# Godot uses these to move focus with arrow keys and Tab.
	for i in range(_menu_buttons.size()):
		var btn = _menu_buttons[i]
		var prev_btn = _menu_buttons[posmod(i - 1, _menu_buttons.size())]
		var next_btn = _menu_buttons[posmod(i + 1, _menu_buttons.size())]
		btn.focus_neighbor_top    = prev_btn.get_path()
		btn.focus_neighbor_bottom = next_btn.get_path()
		btn.focus_neighbor_left   = btn.get_path()
		btn.focus_neighbor_right  = btn.get_path()
		btn.focus_previous = prev_btn.get_path()
		btn.focus_next     = next_btn.get_path()

	_apply_theme()


# ── WCAG 2.4.7: Button Styling ───────────────────────────────────────────────

func _apply_button_style(btn: Button) -> void:
	"""Apply a StyleBoxFlat for every button state.
	The *focus* state uses a 3px accent-coloured border (>=3:1 contrast)
	to satisfy WCAG 2.4.7 Focus Visible."""
	var dark := ThemeManager.is_dark_mode

	# ── Normal ─────────────────────────────────────────────────────────
	var normal := StyleBoxFlat.new()
	normal.bg_color        = Color(1, 1, 1, 0.04) if dark else Color(0, 0, 0, 0.02)
	normal.border_color    = Color(1, 1, 1, 0.06) if dark else Color(0, 0, 0, 0.04)
	normal.border_width_left   = 1
	normal.border_width_top    = 1
	normal.border_width_right  = 1
	normal.border_width_bottom = 1
	normal.set_corner_radius_all(FOCUS_CORNER_RADIUS)
	normal.content_margin_left   = 16
	normal.content_margin_right  = 16
	normal.content_margin_top    = 10
	normal.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", normal)

	# ── Hover ──────────────────────────────────────────────────────────
	var hover := normal.duplicate()
	hover.bg_color     = Color(1, 1, 1, 0.10) if dark else Color(0, 0, 0, 0.06)
	hover.border_color = Color(1, 1, 1, 0.14) if dark else Color(0, 0, 0, 0.10)
	btn.add_theme_stylebox_override("hover", hover)

	# ── Focus (WCAG 2.4.7) ────────────────────────────────────────────
	var focus := normal.duplicate()
	focus.border_width_left   = FOCUS_BORDER_WIDTH
	focus.border_width_top    = FOCUS_BORDER_WIDTH
	focus.border_width_right  = FOCUS_BORDER_WIDTH
	focus.border_width_bottom = FOCUS_BORDER_WIDTH
	focus.border_color = FOCUS_COLOR_DARK if dark else FOCUS_COLOR_LIGHT
	focus.bg_color     = Color(1, 1, 1, 0.07) if dark else Color(0, 0, 0, 0.04)
	# Glow / shadow for extra contrast (WCAG 1.4.11 non-text contrast)
	focus.shadow_color  = FOCUS_COLOR_DARK if dark else FOCUS_COLOR_LIGHT
	focus.shadow_color.a = 0.25 if dark else 0.18
	focus.shadow_size   = 4
	focus.shadow_offset = Vector2.ZERO
	btn.add_theme_stylebox_override("focus", focus)

	# ── Pressed ────────────────────────────────────────────────────────
	var pressed := normal.duplicate()
	pressed.bg_color     = Color(1, 1, 1, 0.16) if dark else Color(0, 0, 0, 0.09)
	pressed.border_color = FOCUS_COLOR_DARK if dark else FOCUS_COLOR_LIGHT
	pressed.border_width_left   = FOCUS_BORDER_WIDTH
	pressed.border_width_top    = FOCUS_BORDER_WIDTH
	pressed.border_width_right  = FOCUS_BORDER_WIDTH
	pressed.border_width_bottom = FOCUS_BORDER_WIDTH
	btn.add_theme_stylebox_override("pressed", pressed)

	# ── Hover + Pressed ────────────────────────────────────────────────
	var hover_pressed := pressed.duplicate()
	hover_pressed.bg_color = Color(1, 1, 1, 0.18) if dark else Color(0, 0, 0, 0.11)
	btn.add_theme_stylebox_override("hover_pressed", hover_pressed)

	# ── Font overrides ─────────────────────────────────────────────────
	btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color",          ThemeManager.text_color)
	btn.add_theme_color_override("font_hover_color",    ThemeManager.text_color)
	btn.add_theme_color_override("font_focus_color",    ThemeManager.text_color)
	btn.add_theme_color_override("font_pressed_color",  ThemeManager.text_color)
	btn.add_theme_color_override("font_hover_pressed_color", ThemeManager.text_color)


# ── Theme ─────────────────────────────────────────────────────────────────────

func _apply_theme() -> void:
	var dark := ThemeManager.is_dark_mode

	# Logo
	var logo_text_col := "#F0EDE8" if dark else "#1A1814"
	var accent_hex    := "#4C8CFF" if dark else "#2659D9"
	_logo_label.text = "[color=%s]M[/color][color=%s]·[/color][color=%s]AT[/color]" % [logo_text_col, accent_hex, logo_text_col]

	%SubtitleLabel.add_theme_color_override("font_color", ThemeManager.subtext_color)

	# Re-style every button (colours may have changed)
	for btn in _menu_buttons:
		_apply_button_style(btn)

	# Fact panel
	var fact_style := StyleBoxFlat.new()
	fact_style.bg_color          = Color(1, 1, 1, 0.06) if dark else Color(1, 1, 1, 0.55)
	fact_style.border_width_left = 1
	fact_style.border_width_top  = 1
	fact_style.border_width_right  = 1
	fact_style.border_width_bottom = 1
	fact_style.border_color = Color(1, 1, 1, 0.12) if dark else Color(0, 0, 0, 0.08)
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		fact_style.set("corner_radius_" + c, 14)
	fact_style.shadow_color   = Color(0, 0, 0, 0.25 if dark else 0.08)
	fact_style.shadow_size    = 20
	fact_style.shadow_offset  = Vector2(0, 4)
	%FactPanel.add_theme_stylebox_override("panel", fact_style)
	_fact_text.add_theme_color_override("font_color", ThemeManager.text_color)

	_populate_tags()

	# Footer
	var footer = $MainLayout/LeftCol/BrandingVBox/Footer
	footer.get_node("ModeDesc").add_theme_color_override("font_color", ThemeManager.subtext_color)
	footer.get_node("Sep").color = Color(1, 1, 1, 0.08) if dark else Color(0, 0, 0, 0.06)

	$EscHint.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _trending_label:
		_trending_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	var trending_sep = get_node_or_null("MainLayout/RightCol/WidgetVBox/TrendingSep")
	if trending_sep:
		trending_sep.color = Color(1, 1, 1, 0.08) if dark else Color(0, 0, 0, 0.06)


# ── Tags ──────────────────────────────────────────────────────────────────────

func _populate_tags() -> void:
	for c in _tag_container.get_children():
		c.queue_free()

	var dark := ThemeManager.is_dark_mode
	var tags = ["Wikipedia-powered", "Multiplayer", "Open Source"]
	for t in tags:
		var lbl := Label.new()
		lbl.text = t
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_font_override("font", _sans_font)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.55) if dark else Color(0, 0, 0, 0.5))

		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.06) if dark else Color(0, 0, 0, 0.04)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(1, 1, 1, 0.1) if dark else Color(0, 0, 0, 0.06)
		for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
			style.set("corner_radius_" + c, 16)
		style.content_margin_left   = 10
		style.content_margin_top    = 3
		style.content_margin_right  = 10
		style.content_margin_bottom = 3

		lbl.add_theme_stylebox_override("normal", style)
		_tag_container.add_child(lbl)


# ── Trending Ticker ───────────────────────────────────────────────────────────

func _setup_trending_ticker() -> void:
	_trending_timer = Timer.new()
	_trending_timer.wait_time = 4.0
	_trending_timer.timeout.connect(_on_trending_timer_timeout)
	add_child(_trending_timer)

	var wt = get_node_or_null("/root/WikipediaTrending")
	if wt:
		wt.trending_updated.connect(_on_trending_updated)
		wt.fetch_failed.connect(_on_trending_failed)
		wt.fetch_trending()

	_trending_label = Label.new()
	_trending_label.name = "TrendingLabel"
	_trending_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trending_label.add_theme_font_override("font", _sans_font)
	_trending_label.add_theme_font_size_override("font_size", 11)
	_trending_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
	_trending_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	var right_col = get_node_or_null("MainLayout/RightCol/WidgetVBox")
	if right_col:
		right_col.add_child(_trending_label)
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


func _on_trending_failed(_error: String) -> void:
	pass


func _on_trending_timer_timeout() -> void:
	if _trending_articles.size() > 1:
		_trending_index = (_trending_index + 1) % _trending_articles.size()
		var tw := create_tween()
		tw.tween_property(_trending_label, "modulate:a", 0.0, 0.5)
		tw.chain().tween_callback(_update_trending_display)
		tw.chain().tween_property(_trending_label, "modulate:a", 1.0, 0.5)


func _update_trending_display() -> void:
	if not _trending_label:
		return
	if _trending_articles.is_empty():
		_trending_label.text = "Loading trending articles..."
		_trending_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
		return
	var article = _trending_articles[_trending_index]
	if _trending_articles.size() > 1:
		_trending_label.text = "Trending: %s (%d/%d)" % [article, _trending_index + 1, _trending_articles.size()]
	else:
		_trending_label.text = "Trending: %s" % article


# ── Entrance Animation ────────────────────────────────────────────────────────

func _entrance_animation() -> void:
	_logo_label.modulate.a = 0
	_button_container.modulate.a = 0
	%FactPanel.modulate.a = 0
	%TagContainer.modulate.a = 0

	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_logo_label, "modulate:a", 1.0, 0.7)
	tw.tween_property(_button_container, "modulate:a", 1.0, 0.7).set_delay(0.25)
	tw.tween_property(%FactPanel, "modulate:a", 1.0, 0.7).set_delay(0.4)
	tw.tween_property(%TagContainer, "modulate:a", 1.0, 0.7).set_delay(0.55)

	var delay: float = 0.35
	for btn in _menu_buttons:
		btn.modulate.a = 0
		var twb := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		twb.tween_property(btn, "modulate:a", 1.0, 0.35).set_delay(delay)
		delay += 0.06

	# ── WCAG 2.4.7: Auto-focus first button after animation ───────────
	var grab_delay: float = delay + 0.15
	var grab_tw := create_tween()
	grab_tw.tween_callback(_grab_initial_focus).set_delay(grab_delay)


func _grab_initial_focus() -> void:
	"""Give keyboard focus to the first visible menu button."""
	if not is_visible_in_tree():
		return
	for btn in _menu_buttons:
		if btn.visible:
			btn.grab_focus()
			return


# ── Facts ─────────────────────────────────────────────────────────────────────

func _setup_fact_timer() -> void:
	_shuffle_facts()
	_current_fact_index = randi() % _fact_order.size()
	_fact_text.text = FACTS[_fact_order[_current_fact_index]]

	_fact_timer = Timer.new()
	_fact_timer.wait_time = 6.0
	_fact_timer.timeout.connect(_on_fact_timer_timeout)
	add_child(_fact_timer)
	_fact_timer.start()


func _shuffle_facts() -> void:
	_fact_order.clear()
	for i in FACTS.size():
		_fact_order.append(i)
	_fact_order.shuffle()


func _on_fact_timer_timeout() -> void:
	var tw := create_tween()
	tw.tween_property(_fact_text, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(_cycle_fact)
	tw.chain().tween_property(_fact_text, "modulate:a", 1.0, 0.5)


func _cycle_fact() -> void:
	_current_fact_index += 1
	if _current_fact_index >= _fact_order.size():
		_shuffle_facts()
		_current_fact_index = 0
	_fact_text.text = FACTS[_fact_order[_current_fact_index]]


func _on_ui_cancel_pressed() -> void:
	if not visible:
		return
	# Focus the last button (Quit) on Escape
	for i in range(_menu_buttons.size() - 1, -1, -1):
		if _menu_buttons[i].visible:
			_menu_buttons[i].grab_focus()
			return


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
	# Update the toggle button's text
	for btn in _menu_buttons:
		if btn.name == "Toggle Theme":
			var icon: String = "☾" if not ThemeManager.is_dark_mode else "☀"
			var label: String = "Light Mode" if ThemeManager.is_dark_mode else "Dark Mode"
			btn.text = icon + "  " + label
			_apply_button_style(btn)
			break


func _on_language_toggle_pressed() -> void:
	_current_locale_index = posmod(_current_locale_index + 1, _available_locales.size())
	var locale = _available_locales[_current_locale_index]
	LanguageManager.set_locale(locale)
	_update_language_toggle_ui()


func _update_language_toggle_ui() -> void:
	for btn in _menu_buttons:
		if btn.name == "Language":
			btn.text = "🌍  " + _get_current_language_name()
			_apply_button_style(btn)
			break


func _get_current_language_name() -> String:
	if _available_locales.is_empty() or _current_locale_index < 0 or _current_locale_index >= _available_locales.size():
		return "Language"
	var locale = _available_locales[_current_locale_index]
	var lang_name = TranslationServer.get_language_name(locale)
	if lang_name.is_empty():
		lang_name = locale
	return lang_name


# ── Patch Notes Popup ─────────────────────────────────────────────────────────

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
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_patch_popup.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -360.0
	panel.offset_top    = -280.0
	panel.offset_right  = 360.0
	panel.offset_bottom = 280.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_patch_popup.add_child(panel)

	var dark := ThemeManager.is_dark_mode
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color      = Color(0.08, 0.08, 0.1, 0.92) if dark else Color(1, 1, 1, 0.95)
	panel_style.border_color  = Color(1, 1, 1, 0.1) if dark else Color(0, 0, 0, 0.08)
	for s in ["left", "right", "top", "bottom"]:
		panel_style.set("border_width_" + s, 1)
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		panel_style.set("corner_radius_" + c, 16)
	panel_style.shadow_color   = Color(0, 0, 0, 0.4)
	panel_style.shadow_size    = 32
	panel_style.shadow_offset  = Vector2(0, 8)
	panel.add_theme_stylebox_override("panel", panel_style)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 28)
	outer.add_theme_constant_override("margin_right", 28)
	outer.add_theme_constant_override("margin_top", 24)
	outer.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(outer)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	outer.add_child(vbox)

	# ── Header with WCAG 2.4.7 close button ───────────────────────────
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "📋 Latest Changes"
	title.add_theme_font_override("font", _serif_font)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ThemeManager.text_color)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.name = "PatchCloseButton"
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.pressed.connect(_close_patch_popup)
	close_btn.mouse_entered.connect(close_btn.grab_focus)
	_style_popup_button(close_btn, false)
	header.add_child(close_btn)

	var sep := ColorRect.new()
	sep.custom_minimum_size.y = 1
	sep.color = Color(1, 1, 1, 0.08) if dark else Color(0, 0, 0, 0.06)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	var notes := [
		{"title": "🔒 Security", "items": [
			"All RPC endpoints now validate sender identity",
			"Vote timer, race cancel, and win validation RPCs secured",
			"Host state transfer requires authentication",
			"ExhibitGraph edge injection prevented (anti-cheat)",
			"Terminal inoperable bug fixed (was missing interact())"
		]},
		{"title": "🎨 UI & Visuals", "items": [
			"Main menu background completely redesigned",
			"Smooth dark/light mode transitions on main menu",
			"Settings tabs no longer crash on open (tab init ordering fixed)",
			"Main.tscn no longer corrupt (format/UID issues resolved)",
			"WIP label unicode parsing error fixed",
			"Main menu logo replaced with funky variant"
		]},
		{"title": "🔗 Networking", "items": [
			"ENet timeout fixed: 32ms → 5000ms (playit.gg connections work)",
			"Server/client channel counts set explicitly (2 channels)",
			"Join timeout crash fixed (nonexistent method call)",
			"DNS resolution timing improved"
		]},
		{"title": "🏎️ Race System", "items": [
			"Host player can now win races (was always rejected)",
			"Countdown no longer bypasses race cancellation",
			"Path validation sender check fixed"
		]},
		{"title": "💡 Lighting", "items": [
			"Ambient light source changed to COLOR (decoupled from sky)",
			"Skybox gradient textures properly assigned (were missing)",
			"Directional skylights changed to OmniLight (stopped global bleed)",
			"Exhibit ambient energy recalibrated for new lighting model",
			"Wall sconce lights no longer clip through walls (position offset fixed)",
			"Wall sconce decoration lights removed entirely",
			"Exhibit mood keyword lists expanded — more articles get themed lighting",
			"PHILOSOPHY mood recolored to warm monastic ochre (#D05112)"
		]},
		{"title": "🐛 Bug Fixes", "items": [
			"Main.tscn invalid/corrupt error resolved",
			"Multiple scene parse errors fixed",
			"Node reference crashes in GraphicsSettings fixed",
			"Signal double-connection errors fixed",
			"@onready initialization order race conditions fixed",
			"Redundant path building in win validation removed",
			"FLAC audio files no longer crash SoundItem (WAV decoder rejection)",
			"MainMenu.gd indentation errors fixed (space/tab consistency)"
		]},
		{"title": "♿ Accessibility", "items": [
			"Exhibit text color restored to black (was inheriting theme)",
			"Settings UI now uses consistent UIStyle theming",
			"All scene files verified for resource path validity"
		]},
		{"title": "⚠️ Known Issues", "items": [
			"Twitch addon missing (non-critical)",
			"Discord RPC addon partially disabled",
			"Archived player scripts have Godot 3 syntax (non-critical)"
		]}
	]

	for section in notes:
		var section_title := Label.new()
		section_title.text = section.title
		section_title.add_theme_font_override("font", _serif_font)
		section_title.add_theme_font_size_override("font_size", 15)
		section_title.add_theme_color_override("font_color", ThemeManager.text_color)
		content.add_child(section_title)

		for item_text in section.items:
			var item_lbl := Label.new()
			item_lbl.text = "•  " + item_text
			item_lbl.add_theme_font_override("font", _sans_font)
			item_lbl.add_theme_font_size_override("font_size", 12)
			item_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
			item_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			content.add_child(item_lbl)

	# ── Footer with WCAG 2.4.7 close button ───────────────────────────
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var ok_btn := Button.new()
	ok_btn.text = "Close"
	ok_btn.name = "PatchOkButton"
	ok_btn.focus_mode = Control.FOCUS_ALL
	ok_btn.custom_minimum_size = Vector2(100, 36)
	ok_btn.pressed.connect(_close_patch_popup)
	ok_btn.mouse_entered.connect(ok_btn.grab_focus)
	_style_popup_button(ok_btn, true)
	footer.add_child(ok_btn)

	# Animate in
	_patch_popup.modulate.a = 0.0
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.92, 0.92)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_patch_popup, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(panel, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(panel, "scale", Vector2(1, 1), 0.2)

	# ── WCAG 2.4.7: Auto-focus close button when popup opens ──────────
	tw.chain().tween_callback(func():
		if close_btn.is_visible_in_tree():
			close_btn.grab_focus()
	)


func _close_patch_popup() -> void:
	if not _patch_popup:
		return
	var popup_to_free := _patch_popup
	_patch_popup = null
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(popup_to_free, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(func(): popup_to_free.queue_free())

	# ── WCAG 2.4.7: Return focus to the first menu button ─────────────
	for btn in _menu_buttons:
		if btn.visible:
			btn.grab_focus()
			break


func _style_popup_button(btn: Button, primary: bool) -> void:
	"""Style a popup button with a WCAG 2.4.7 focus indicator."""
	var dark := ThemeManager.is_dark_mode
	var ring_color  := FOCUS_COLOR_DARK if dark else FOCUS_COLOR_LIGHT
	var glow_color  := FOCUS_COLOR_DARK if dark else FOCUS_COLOR_LIGHT
	glow_color.a = 0.25 if dark else 0.18

	btn.add_theme_font_override("font", _sans_font)
	btn.add_theme_font_size_override("font_size", 13)

	# Normal
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(8)
	normal.content_margin_left   = 16
	normal.content_margin_right  = 16
	normal.content_margin_top    = 6
	normal.content_margin_bottom = 6
	if primary:
		normal.bg_color     = Color(1, 1, 1, 0.08) if dark else Color(0, 0, 0, 0.04)
		normal.border_width_left = 1
		normal.border_width_top = 1
		normal.border_width_right = 1
		normal.border_width_bottom = 1
		normal.border_color = Color(1, 1, 1, 0.12) if dark else Color(0, 0, 0, 0.08)
	else:
		normal.bg_color = Color(0, 0, 0, 0)
	btn.add_theme_stylebox_override("normal", normal)

	# Hover
	var hover := normal.duplicate()
	if primary:
		hover.bg_color = Color(1, 1, 1, 0.14) if dark else Color(0, 0, 0, 0.08)
	else:
		hover.bg_color = Color(1, 1, 1, 0.04) if dark else Color(0, 0, 0, 0.02)
	btn.add_theme_stylebox_override("hover", hover)

	# ── Focus (WCAG 2.4.7) ────────────────────────────────────────────
	var focus := normal.duplicate()
	focus.border_width_left   = FOCUS_BORDER_WIDTH
	focus.border_width_top    = FOCUS_BORDER_WIDTH
	focus.border_width_right  = FOCUS_BORDER_WIDTH
	focus.border_width_bottom = FOCUS_BORDER_WIDTH
	focus.border_color = ring_color
	focus.shadow_color  = glow_color
	focus.shadow_size   = 4
	focus.shadow_offset = Vector2.ZERO
	if primary:
		focus.bg_color = Color(1, 1, 1, 0.12) if dark else Color(0, 0, 0, 0.06)
	else:
		focus.bg_color = Color(1, 1, 1, 0.06) if dark else Color(0, 0, 0, 0.03)
	btn.add_theme_stylebox_override("focus", focus)

	# Pressed
	var pressed := normal.duplicate()
	pressed.border_width_left   = FOCUS_BORDER_WIDTH
	pressed.border_width_top    = FOCUS_BORDER_WIDTH
	pressed.border_width_right  = FOCUS_BORDER_WIDTH
	pressed.border_width_bottom = FOCUS_BORDER_WIDTH
	pressed.border_color = ring_color
	if primary:
		pressed.bg_color = Color(1, 1, 1, 0.18) if dark else Color(0, 0, 0, 0.1)
	else:
		pressed.bg_color = Color(1, 1, 1, 0.08) if dark else Color(0, 0, 0, 0.05)
	btn.add_theme_stylebox_override("pressed", pressed)

	# Font colours
	if primary:
		btn.add_theme_color_override("font_color",         ThemeManager.text_color)
		btn.add_theme_color_override("font_hover_color",   ThemeManager.text_color)
		btn.add_theme_color_override("font_focus_color",   ThemeManager.text_color)
		btn.add_theme_color_override("font_pressed_color", ThemeManager.text_color)
	else:
		btn.add_theme_color_override("font_color",         ThemeManager.subtext_color)
		btn.add_theme_color_override("font_hover_color",   ThemeManager.text_color)
		btn.add_theme_color_override("font_focus_color",   ThemeManager.text_color)
		btn.add_theme_color_override("font_pressed_color", ThemeManager.text_color)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _exit_tree() -> void:
	ThemeManager.dark_mode_changed.disconnect(_on_dark_mode_changed)
	ThemeManager.reading_font_changed.disconnect(_on_reading_font_changed)
	UIEvents.ui_cancel_pressed.disconnect(_on_ui_cancel_pressed)
	SettingsEvents.language_changed.disconnect(_on_language_changed_from_settings)
