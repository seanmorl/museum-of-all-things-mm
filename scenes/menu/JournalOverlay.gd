extends Control
class_name JournalOverlay
## Two-pane explorer's journal.
## Left:  scrollable entry list with search, filter tabs, sort control.
## Right: rich detail view with inline note editing, tag chips, race history.
## Fully dark-mode aware via ThemeManager.

signal closed

# ── Colour tokens ─────────────────────────────────────────────────────────────
# Resolved at runtime from ThemeManager so dark mode works correctly.
var _c_text:      Color
var _c_subtext:   Color
var _c_bg:        Color
var _c_border:    Color
var _c_accent:    Color  # wiki-blue, lightened in dark mode
var _c_win:       Color
var _c_loss:      Color

# ── State ─────────────────────────────────────────────────────────────────────
enum Filter { ALL, VISITS, PINNED, RACES }
enum Sort   { RECENT, ALPHA, MOST_VISITED, BEST_TIME }

var _is_open:        bool   = false
var _animating:      bool   = false
var _current_filter: int    = Filter.ALL
var _current_sort:   int    = Sort.RECENT
var _search_query:   String = ""
var _selected_title: String = ""
var _active_entries: Array  = []

# ── Scene references (created fully in code) ──────────────────────────────────
var _backdrop:        ColorRect      = null
var _panel:           PanelContainer = null
var _panel_style:     StyleBoxFlat   = null

# Left pane
var _search_field:    LineEdit       = null
var _filter_btns:     Array          = []
var _sort_btns:       Array          = []
var _list_vbox:       VBoxContainer  = null
var _list_scroll:     ScrollContainer = null
var _stats_label:     Label          = null

# Right pane
var _detail_panel:    PanelContainer = null
var _detail_style:    StyleBoxFlat   = null
var _detail_title:    Label          = null
var _detail_meta:     Label          = null
var _detail_content:  RichTextLabel  = null
var _detail_divider:  ColorRect      = null
var _note_label:      Label          = null
var _note_field:      TextEdit       = null
var _tag_hbox:        HBoxContainer  = null
var _tag_input:       LineEdit       = null
var _export_btn:      Button         = null
var _detail_scroll:   ScrollContainer = null

var _serif_font:      Font = null
var _note_save_timer: float = 0.0
var _note_dirty:      bool  = false

const NOTE_DEBOUNCE: float = 1.2


func _ready() -> void:
	visible   = false
	# STOP mouse filter so the panel catches clicks and blocks the game world
	# when the journal is open. IGNORE when closed so nothing is blocked.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	set_process_unhandled_input(false)
	_serif_font = ThemeManager.get_reading_font()
	_resolve_colours()
	_build_ui()
	_apply_theme()
	ThemeManager.dark_mode_changed.connect(func(_d):
		_resolve_colours()
		_apply_theme()
		_refresh_list()
		# Re-apply theme colours to already-rendered detail content without
		# re-fetching — calling _show_detail here triggers a network request
		# via JournalManager.fetch_full_article_text → ExhibitFetcher.fetch
		# which crashes because the caller context has no "new_titles" key.
		if _detail_content:
			_detail_content.add_theme_color_override("default_color", _c_text)
		if _detail_title:
			_detail_title.add_theme_color_override("font_color", _c_text)
		if _detail_meta:
			_detail_meta.add_theme_color_override("font_color", _c_subtext)
	)
	ThemeManager.reading_font_changed.connect(func(f): _serif_font = f; _apply_theme())
	JournalManager.entry_added.connect(_on_journal_changed)
	JournalManager.entry_updated.connect(_on_journal_changed)


func _process(delta: float) -> void:
	if _note_dirty:
		_note_save_timer -= delta
		if _note_save_timer <= 0.0:
			_flush_note()


# ── Colour resolution ─────────────────────────────────────────────────────────

func _resolve_colours() -> void:
	var dark: bool = ThemeManager.is_dark_mode
	_c_text    = ThemeManager.text_color
	_c_subtext = ThemeManager.subtext_color
	_c_bg      = ThemeManager.bg_color
	_c_border  = ThemeManager.border_color
	_c_accent  = Color(0.30, 0.55, 1.00) if dark else Color(0.024, 0.271, 0.678)
	_c_win     = Color(0.20, 0.80, 0.35) if dark else Color(0.0,   0.39,  0.0)
	_c_loss    = Color(0.90, 0.35, 0.35) if dark else Color(0.55,  0.0,   0.0)


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Backdrop dim
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0, 0, 0, 0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	# Outer panel — inset from viewport edges. 40px gives enough breathing room
	# without wasting vertical space on smaller screens.
	_panel = PanelContainer.new()
	_panel.name = "JournalPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left   = 40
	_panel.offset_top    = 40
	_panel.offset_right  = -40
	_panel.offset_bottom = -40
	_panel.clip_contents = true
	add_child(_panel)

	_panel_style = StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _panel_style)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left",   16)
	outer_margin.add_theme_constant_override("margin_right",  16)
	outer_margin.add_theme_constant_override("margin_top",    12)
	outer_margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(outer_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 5)
	outer_margin.add_child(root_vbox)

	# ── Header row ────────────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root_vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.text = "Explorer's Journal"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	_export_btn = _make_button("⎘ Export", _on_export_pressed)
	_export_btn.custom_minimum_size.x = 90
	header.add_child(_export_btn)

	var close_btn := _make_button("✕", close)
	close_btn.custom_minimum_size.x = 36
	header.add_child(close_btn)

	# Subtitle
	var subtitle := Label.new()
	subtitle.name = "SubtitleLabel"
	subtitle.text = "From Museum of All Things, the free encyclopedia"
	root_vbox.add_child(subtitle)

	# Thin divider
	root_vbox.add_child(_make_divider())

	# ── Search + filter + sort row ────────────────────────────────────────────
	var toolbar := VBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 3)
	root_vbox.add_child(toolbar)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Search journal…"
	_search_field.clear_button_enabled = true
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_field.text_changed.connect(_on_search_changed)
	toolbar.add_child(_search_field)

	var filter_sort_row := HBoxContainer.new()
	filter_sort_row.add_theme_constant_override("separation", 4)
	toolbar.add_child(filter_sort_row)

	# Filter tabs
	var filter_labels := ["All", "Visits", "Pinned", "Races"]
	for i in filter_labels.size():
		var btn := _make_tab_button(filter_labels[i])
		btn.button_pressed = (i == 0)
		btn.pressed.connect(_on_filter_pressed.bind(i))
		filter_sort_row.add_child(btn)
		_filter_btns.append(btn)

	var fsep := VSeparator.new()
	fsep.custom_minimum_size.x = 8
	filter_sort_row.add_child(fsep)

	# Sort buttons
	var sort_icons := ["🕐", "A–Z", "🔁", "⏱"]
	var sort_tips  := ["Most recent", "Alphabetical", "Most visited", "Best race time"]
	for i in sort_icons.size():
		var btn := _make_tab_button(sort_icons[i])
		btn.tooltip_text = sort_tips[i]
		btn.button_pressed = (i == 0)
		btn.pressed.connect(_on_sort_pressed.bind(i))
		filter_sort_row.add_child(btn)
		_sort_btns.append(btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_sort_row.add_child(spacer)

	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	filter_sort_row.add_child(_stats_label)

	root_vbox.add_child(_make_divider())

	# ── Two-pane body ─────────────────────────────────────────────────────────
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(body)

	# Left pane — fixed 220 px wide, full height, clips overflowing titles
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size    = Vector2(220, 0)
	left_panel.size_flags_horizontal  = Control.SIZE_SHRINK_BEGIN
	left_panel.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	left_panel.clip_contents          = true
	var left_style := StyleBoxFlat.new()
	left_style.bg_color = Color(0, 0, 0, 0)
	left_panel.add_theme_stylebox_override("panel", left_style)
	body.add_child(left_panel)

	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_panel.add_child(_list_scroll)

	var list_margin := MarginContainer.new()
	list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.add_theme_constant_override("margin_right", 6)
	list_margin.add_theme_constant_override("margin_left",  2)
	_list_scroll.add_child(list_margin)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 2)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.add_child(_list_vbox)

	# Vertical divider between panes — must expand vertically
	var vert_div := ColorRect.new()
	vert_div.name                   = "VertDiv"
	vert_div.custom_minimum_size    = Vector2(1, 0)
	vert_div.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	vert_div.mouse_filter           = Control.MOUSE_FILTER_IGNORE
	vert_div.color                  = _c_border
	body.add_child(vert_div)

	# Right pane — detail, takes all remaining space
	_detail_panel = PanelContainer.new()
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_detail_panel.clip_contents         = true
	_detail_style = StyleBoxFlat.new()
	_detail_style.bg_color = Color(0, 0, 0, 0)
	_detail_panel.add_theme_stylebox_override("panel", _detail_style)
	body.add_child(_detail_panel)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 14)
	_detail_panel.add_child(detail_margin)

	var detail_vbox := VBoxContainer.new()
	detail_vbox.add_theme_constant_override("separation", 6)
	detail_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_margin.add_child(detail_vbox)

	_detail_title = Label.new()
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_vbox.add_child(_detail_title)

	_detail_meta = Label.new()
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_vbox.add_child(_detail_meta)

	_detail_divider = _make_divider()
	detail_vbox.add_child(_detail_divider)

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.clip_contents         = true
	detail_vbox.add_child(_detail_scroll)

	var detail_inner := VBoxContainer.new()
	detail_inner.add_theme_constant_override("separation", 8)
	detail_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_inner.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_detail_scroll.add_child(detail_inner)

	_detail_content = RichTextLabel.new()
	_detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_content.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_detail_content.fit_content           = false   # must be false for ScrollContainer to work
	_detail_content.scroll_active         = false   # ScrollContainer handles scrolling
	_detail_content.bbcode_enabled        = true
	_detail_content.autowrap_mode         = TextServer.AUTOWRAP_WORD_SMART
	detail_inner.add_child(_detail_content)

	# Note editor
	_note_label = Label.new()
	_note_label.text = "📝 Note"
	detail_inner.add_child(_note_label)

	_note_field = TextEdit.new()
	_note_field.placeholder_text = "Add a personal note…"
	_note_field.custom_minimum_size = Vector2(0, 64)
	_note_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note_field.text_changed.connect(_on_note_changed)
	detail_inner.add_child(_note_field)

	# Tag chips
	var tag_row_label := Label.new()
	tag_row_label.text = "🏷 Tags"
	detail_inner.add_child(tag_row_label)

	var tag_area := VBoxContainer.new()
	tag_area.add_theme_constant_override("separation", 4)
	detail_inner.add_child(tag_area)

	_tag_hbox = HBoxContainer.new()
	_tag_hbox.add_theme_constant_override("separation", 4)
	tag_area.add_child(_tag_hbox)

	var tag_input_row := HBoxContainer.new()
	tag_input_row.add_theme_constant_override("separation", 4)
	tag_area.add_child(tag_input_row)

	_tag_input = LineEdit.new()
	_tag_input.placeholder_text = "Add tag…"
	_tag_input.custom_minimum_size.x = 120
	_tag_input.text_submitted.connect(_on_tag_submitted)
	tag_input_row.add_child(_tag_input)

	var tag_add_btn := _make_button("+ Add", func(): _on_tag_submitted(_tag_input.text))
	tag_input_row.add_child(tag_add_btn)

	root_vbox.add_child(_make_divider())

	# ── Footer ────────────────────────────────────────────────────────────────
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	root_vbox.add_child(footer)

	var hint := Label.new()
	hint.name = "FooterHint"
	hint.text = "ESC to close  ·  ← → to navigate list"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)


# ── Open / close ──────────────────────────────────────────────────────────────

func open() -> void:
	if _is_open or _animating:
		return
	_is_open = true
	visible  = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(true)
	set_process_unhandled_input(true)
	JournalManager.refresh_snippets()
	_search_field.text = ""
	_search_query      = ""
	_current_filter    = Filter.ALL
	_current_sort      = Sort.RECENT
	_set_active_tab(_filter_btns, 0)
	_set_active_tab(_sort_btns,   0)
	_refresh_list()
	# Select most recent entry automatically
	if not _active_entries.is_empty():
		_show_detail(_active_entries[0].title)
	else:
		_clear_detail()
	_search_field.grab_focus()
	_animate_in()


func close() -> void:
	if not _is_open or _animating:
		return
	_flush_note()
	_animate_out(func():
		_is_open = false
		visible  = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process_input(false)
		set_process_unhandled_input(false)
		closed.emit()
	)


func is_open() -> bool:
	return _is_open


func toggle() -> void:
	if _is_open: close()
	else:        open()


# ── Animations (matching PauseMenu / HostMenu pattern) ────────────────────────

func _animate_in() -> void:
	_animating = true
	_backdrop.color.a = 0.0
	_panel.modulate.a = 0.0
	_panel.position.y = 14.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_backdrop, "color:a", 0.45, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.40).set_delay(0.05)
	tw.tween_property(_panel, "position:y", 0.0, 0.40) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.05)
	tw.chain().tween_callback(func(): _animating = false)


func _animate_out(then: Callable) -> void:
	_animating = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_backdrop, "color:a", 0.0, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.16)
	tw.tween_property(_panel, "position:y", 10.0, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		_animating = false
		_panel.modulate.a = 1.0
		_panel.position.y = 0.0
		then.call()
	)


func _animate_detail_swap() -> void:
	## Brief fade on the detail panel when switching entries.
	if not is_instance_valid(_detail_panel):
		return
	_detail_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_detail_panel, "modulate:a", 1.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ── Theme ─────────────────────────────────────────────────────────────────────

func _apply_theme() -> void:
	if not _panel_style:
		return
	var dark: bool = ThemeManager.is_dark_mode

	# Outer panel
	_panel_style.bg_color     = _c_bg
	_panel_style.border_color = _c_border
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(10)
	_panel_style.shadow_color  = Color(0, 0, 0, 0.35 if dark else 0.12)
	_panel_style.shadow_size   = 16
	_panel_style.shadow_offset = Vector2(0, 6)

	# Walk all styled nodes
	_style_all_labels()
	_style_all_buttons()
	_style_search_field()
	_style_note_field()
	_style_tag_input()

	# Stats label
	if _stats_label:
		_stats_label.add_theme_color_override("font_color", _c_subtext)
		_stats_label.add_theme_font_size_override("font_size", 12)
		if _serif_font:
			_stats_label.add_theme_font_override("font", _serif_font)

	# Title label
	var title_lbl: Label = _panel.get_node_or_null("MarginContainer/VBoxContainer/HeaderHBox/TitleLabel") \
		if _panel.get_node_or_null("MarginContainer") else null
	# Safer: walk children
	_style_title_label()

	# Footer hint
	_style_footer()


func _style_title_label() -> void:
	if not _panel:
		return
	var lbl: Label = _panel.find_child("TitleLabel", true, false) as Label
	if lbl:
		lbl.add_theme_color_override("font_color", _c_text)
		lbl.add_theme_font_size_override("font_size", 28)
		if _serif_font:
			lbl.add_theme_font_override("font", _serif_font)
	var sub: Label = _panel.find_child("SubtitleLabel", true, false) as Label
	if sub:
		sub.add_theme_color_override("font_color", _c_subtext)
		sub.add_theme_font_size_override("font_size", 13)
		if _serif_font:
			sub.add_theme_font_override("font", _serif_font)


func _style_footer() -> void:
	var hint: Label = _panel.find_child("FooterHint", true, false) as Label
	if hint:
		hint.add_theme_color_override("font_color", _c_subtext)
		hint.add_theme_font_size_override("font_size", 12)


func _style_all_labels() -> void:
	for lbl: Label in [_detail_title, _detail_meta, _note_label]:
		if not is_instance_valid(lbl):
			continue
		lbl.add_theme_color_override("font_color", _c_text)
		if _serif_font:
			lbl.add_theme_font_override("font", _serif_font)

	if _detail_title:
		_detail_title.add_theme_font_size_override("font_size", 20)
	if _detail_meta:
		_detail_meta.add_theme_color_override("font_color", _c_subtext)
		_detail_meta.add_theme_font_size_override("font_size", 12)
	if _note_label:
		_note_label.add_theme_color_override("font_color", _c_subtext)
		_note_label.add_theme_font_size_override("font_size", 12)

	# RichTextLabel — font, size, and default colour must be set explicitly.
	# Without these the label inherits the theme default which is near-invisible
	# in light mode.
	if _detail_content:
		if _serif_font:
			_detail_content.add_theme_font_override("normal_font", _serif_font)
			_detail_content.add_theme_font_override("bold_font",   _serif_font)
			_detail_content.add_theme_font_override("italics_font", _serif_font)
		_detail_content.add_theme_font_size_override("normal_font_size", 15)
		_detail_content.add_theme_color_override("default_color", _c_text)

	if _detail_divider:
		_detail_divider.color = _c_border
	for cr: ColorRect in _get_all_dividers():
		cr.color = _c_border


func _get_all_dividers() -> Array:
	var out: Array = []
	if _panel:
		for cr in _panel.find_children("*", "ColorRect", true, false):
			# Horizontal dividers have height=1; vertical divider has width=1
			if cr.custom_minimum_size.y == 1 or cr.custom_minimum_size.x == 1:
				out.append(cr)
	return out


func _style_all_buttons() -> void:
	if not _panel:
		return
	for btn in _panel.find_children("*", "Button", true, false):
		if btn is Button:
			_style_button(btn)
	for btn in _filter_btns:
		_style_tab_button(btn)
	for btn in _sort_btns:
		_style_tab_button(btn)


func _style_button(btn: Button) -> void:
	var dark: bool = ThemeManager.is_dark_mode
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 15)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		btn.add_theme_color_override(state, _c_text)
	btn.add_theme_color_override("font_disabled_color", _c_subtext)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0)
	sn.content_margin_left = 12
	sn.content_margin_right = 12
	sn.content_margin_top = 6
	sn.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sn)

	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(1,1,1,0.06) if dark else Color(_c_border, 0.5)
	sh.set_corner_radius_all(5)
	sh.content_margin_left = 12
	sh.content_margin_right = 12
	sh.content_margin_top = 6
	sh.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", sh)

	var sp := sh.duplicate() as StyleBoxFlat
	sp.bg_color = Color(1,1,1,0.12) if dark else Color(_c_border, 0.85)
	btn.add_theme_stylebox_override("pressed", sp)

	var sf := sh.duplicate() as StyleBoxFlat
	sf.border_color      = _c_text
	sf.border_width_left = 2
	btn.add_theme_stylebox_override("focus", sf)


func _style_tab_button(btn: Button) -> void:
	var dark: bool = ThemeManager.is_dark_mode
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 13)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		btn.add_theme_color_override(state, _c_text)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0,0,0,0)
	sn.content_margin_left = 10
	sn.content_margin_right = 10
	sn.content_margin_top = 4
	sn.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", sn)

	# Active (pressed) tab gets a bottom border in accent colour
	var sp := StyleBoxFlat.new()
	sp.bg_color = Color(_c_accent, 0.12)
	sp.border_color = _c_accent
	sp.border_width_bottom = 2
	sp.set_corner_radius_all(4)
	sp.content_margin_left = 10
	sp.content_margin_right = 10
	sp.content_margin_top = 4
	sp.content_margin_bottom = 4
	btn.add_theme_stylebox_override("pressed", sp)

	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(1,1,1,0.05) if dark else Color(_c_border, 0.4)
	sh.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", sh)


func _style_search_field() -> void:
	if not _search_field:
		return
	_style_line_edit(_search_field)


func _style_tag_input() -> void:
	if not _tag_input:
		return
	_style_line_edit(_tag_input)


func _style_line_edit(edit: LineEdit) -> void:
	var dark: bool = ThemeManager.is_dark_mode
	if _serif_font:
		edit.add_theme_font_override("font", _serif_font)
	edit.add_theme_font_size_override("font_size", 14)
	edit.add_theme_color_override("font_color", _c_text)
	edit.add_theme_color_override("font_placeholder_color", _c_subtext)

	var sn := StyleBoxFlat.new()
	sn.bg_color     = Color(0,0,0,0.03) if dark else Color(_c_border, 0.25)
	sn.border_color = _c_border
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(5)
	sn.content_margin_left = 10
	sn.content_margin_right = 10
	sn.content_margin_top = 6
	sn.content_margin_bottom = 6
	edit.add_theme_stylebox_override("normal", sn)

	var sf := sn.duplicate() as StyleBoxFlat
	sf.border_color = _c_accent
	sf.set_border_width_all(2)
	edit.add_theme_stylebox_override("focus", sf)


func _style_note_field() -> void:
	if not _note_field:
		return
	var dark: bool = ThemeManager.is_dark_mode
	if _serif_font:
		_note_field.add_theme_font_override("font", _serif_font)
	_note_field.add_theme_font_size_override("font_size", 14)
	_note_field.add_theme_color_override("font_color", _c_text)
	_note_field.add_theme_color_override("font_placeholder_color", _c_subtext)
	_note_field.add_theme_color_override("background_color", Color(0,0,0,0))

	var sn := StyleBoxFlat.new()
	sn.bg_color     = Color(0,0,0,0.04) if dark else Color(_c_border, 0.2)
	sn.border_color = _c_border
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(5)
	sn.content_margin_left = 8
	sn.content_margin_right = 8
	sn.content_margin_top = 6
	sn.content_margin_bottom = 6
	_note_field.add_theme_stylebox_override("normal", sn)
	_note_field.add_theme_stylebox_override("focus",  sn.duplicate())


# ── List rendering ─────────────────────────────────────────────────────────────

func _refresh_list() -> void:
	# Build filtered + sorted entry set
	var base: Array
	match _current_filter:
		Filter.VISITS: base = JournalManager.get_entries_filtered("visit")
		Filter.RACES:  base = JournalManager.get_entries_filtered("race")
		Filter.PINNED:
			base = JournalManager.get_entries().filter(
				func(e): return e.get("pinned_items", []).size() > 0)
		_:
			base = JournalManager.get_entries()

	if _search_query != "":
		var q: String = _search_query.to_lower()
		base = base.filter(func(e: Dictionary) -> bool:
			if q in e.get("title",   "").to_lower(): return true
			if q in e.get("snippet", "").to_lower(): return true
			if q in e.get("note",    "").to_lower(): return true
			for tag: String in e.get("tags", []):
				if q in tag: return true
			return false
		)

	# Sort
	match _current_sort:
		Sort.ALPHA:
			base.sort_custom(func(a, b): return a.title.to_lower() < b.title.to_lower())
		Sort.MOST_VISITED:
			base.sort_custom(func(a, b):
				return a.get("visit_count", 0) > b.get("visit_count", 0))
		Sort.BEST_TIME:
			base.sort_custom(func(a, b):
				var ta: int = a.get("pb_secs", -1)
				var tb: int = b.get("pb_secs", -1)
				if ta == -1: ta = 999999
				if tb == -1: tb = 999999
				return ta < tb)

	_active_entries = base

	# Stats bar
	var stats: Dictionary = JournalManager.get_stats()
	_stats_label.text = "%d visits · %d races · %d pins" % [
		stats.visits, stats.races_won + stats.races_lost, stats.pins]

	# Clear list
	for child in _list_vbox.get_children():
		child.queue_free()

	if _active_entries.is_empty():
		var empty := Label.new()
		empty.text = "No entries." if _search_query == "" else "No results."
		empty.add_theme_color_override("font_color", _c_subtext)
		empty.add_theme_font_size_override("font_size", 13)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if _serif_font:
			empty.add_theme_font_override("font", _serif_font)
		_list_vbox.add_child(empty)
		_clear_detail()
		return

	# Build list cards with a stagger animation
	for i in _active_entries.size():
		var entry: Dictionary = _active_entries[i]
		var card := _make_list_card(entry)
		_list_vbox.add_child(card)
		# Stagger fade-in for up to first 12 items
		if i < 12:
			card.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(card, "modulate:a", 1.0, 0.18) \
				.set_delay(i * 0.03).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Restore selection
	if _selected_title == "" or not _active_entries.any(func(e): return e.title == _selected_title):
		_show_detail(_active_entries[0].title)


func _make_list_card(entry: Dictionary) -> Button:
	var is_selected: bool = (entry.title == _selected_title)
	var type: String      = entry.get("type", "visit")
	var dark: bool        = ThemeManager.is_dark_mode

	var btn := Button.new()
	btn.flat                  = true
	btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode            = Control.FOCUS_CLICK
	btn.custom_minimum_size   = Vector2(0, 44)
	btn.pressed.connect(_on_list_entry_pressed.bind(entry.title))

	# Button children must not block mouse or layout breaks
	# Use a MarginContainer so the VBox gets proper size from the button
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_left",   8)
	mc.add_theme_constant_override("margin_right",  8)
	mc.add_theme_constant_override("margin_top",    5)
	mc.add_theme_constant_override("margin_bottom", 5)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(mc)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_child(vb)

	# Title row
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title_row)

	if type == "race":
		var icon_lbl := Label.new()
		icon_lbl.text = "★"
		icon_lbl.add_theme_font_size_override("font_size", 11)
		icon_lbl.add_theme_color_override("font_color", _c_accent)
		icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(icon_lbl)
	elif entry.get("pinned_items", []).size() > 0:
		var icon_lbl := Label.new()
		icon_lbl.text = "📌"
		icon_lbl.add_theme_font_size_override("font_size", 11)
		icon_lbl.add_theme_color_override("font_color", _c_subtext)
		icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(icon_lbl)

	var title_lbl := Label.new()
	title_lbl.text = entry.title
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.clip_text = true
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", _c_accent if is_selected else _c_text)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _serif_font:
		title_lbl.add_theme_font_override("font", _serif_font)
	title_row.add_child(title_lbl)

	# Meta line
	var meta_lbl := Label.new()
	meta_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_lbl.add_theme_font_size_override("font_size", 11)
	meta_lbl.add_theme_color_override("font_color", _c_subtext)
	if type == "race":
		var runs: int      = entry.get("runs", []).size()
		var pb: int        = entry.get("pb_secs", -1)
		var pb_str: String = ("%02d:%02d" % [pb / 60, pb % 60]) if pb >= 0 else "—"
		meta_lbl.text = "%d run%s · PB %s" % [runs, "s" if runs != 1 else "", pb_str]
	else:
		var vc: int = entry.get("visit_count", 1)
		meta_lbl.text = "%d visit%s" % [vc, "s" if vc != 1 else ""]
	vb.add_child(meta_lbl)

	# Card background styles
	var s_normal := StyleBoxFlat.new()
	s_normal.bg_color = Color(_c_accent, 0.12) if is_selected else Color(0, 0, 0, 0)
	s_normal.set_corner_radius_all(6)
	s_normal.content_margin_left   = 0
	s_normal.content_margin_right  = 0
	s_normal.content_margin_top    = 0
	s_normal.content_margin_bottom = 0
	if is_selected:
		s_normal.border_color      = _c_accent
		s_normal.border_width_left = 2
	btn.add_theme_stylebox_override("normal", s_normal)

	var s_hover := s_normal.duplicate() as StyleBoxFlat
	s_hover.bg_color = Color(_c_accent, 0.18) if is_selected \
		else (Color(1, 1, 1, 0.05) if dark else Color(_c_border, 0.4))
	btn.add_theme_stylebox_override("hover",   s_hover)
	btn.add_theme_stylebox_override("pressed", s_hover)
	btn.add_theme_stylebox_override("focus",   s_normal)

	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn.add_theme_color_override(state, _c_text)

	return btn


# ── Detail pane ───────────────────────────────────────────────────────────────

func _show_detail(title: String) -> void:
	_selected_title = title
	var entry: Variant = JournalManager.get_entry(title)
	if entry == null:
		_clear_detail()
		return

	_animate_detail_swap()

	var type: String = entry.get("type", "visit")

	# Title
	_detail_title.text = entry.title
	_detail_title.add_theme_color_override("font_color", _c_text)
	_detail_title.add_theme_font_size_override("font_size", 20)
	if _serif_font:
		_detail_title.add_theme_font_override("font", _serif_font)

	# Meta line
	if type == "race":
		var runs: int = entry.get("runs", []).size()
		var pb: int   = entry.get("pb_secs", -1)
		var wins: int = entry.get("runs", []).filter(func(r): return r.get("won", false)).size()
		_detail_meta.text = "%d run%s · %dW / %dL · PB %s" % [
			runs, ("s" if runs != 1 else ""),
			wins, runs - wins,
			"%02d:%02d" % [pb / 60, pb % 60] if pb >= 0 else "—"
		]
	else:
		var vc: int         = entry.get("visit_count", 1)
		var date: String    = Time.get_date_string_from_unix_time(int(entry.get("timestamp", 0)))
		var last: String    = Time.get_date_string_from_unix_time(int(entry.get("last_visited", 0)))
		_detail_meta.text = "First visited %s · %d visit%s · Last %s" % [
			date, vc, ("s" if vc != 1 else ""), last]
	_detail_meta.add_theme_color_override("font_color", _c_subtext)

	# Rich body
	var body: String = ""
	if type == "race":
		body = _build_race_body(entry)
	else:
		body = _build_visit_body(entry)

	_detail_content.text = ""
	_detail_content.append_text(body)
	# Re-apply colour/font overrides each time content changes — BBCode colour
	# tags handle the body, but the default_color fallback must match the theme.
	if _serif_font:
		_detail_content.add_theme_font_override("normal_font", _serif_font)
		_detail_content.add_theme_font_override("bold_font",   _serif_font)
		_detail_content.add_theme_font_override("italics_font", _serif_font)
	_detail_content.add_theme_font_size_override("normal_font_size", 15)
	_detail_content.add_theme_color_override("default_color", _c_text)

	# Scroll to top
	await get_tree().process_frame
	if is_instance_valid(_detail_scroll):
		_detail_scroll.scroll_vertical = 0

	# Note field
	_note_field.text = entry.get("note", "")
	_note_dirty = false

	# Tag chips
	_rebuild_tag_chips(entry)


func _clear_detail() -> void:
	_selected_title = ""
	if _detail_title:  _detail_title.text  = ""
	if _detail_meta:   _detail_meta.text   = ""
	if _detail_content: _detail_content.text = ""
	if _note_field:    _note_field.text    = ""
	if _tag_hbox:
		for c in _tag_hbox.get_children():
			c.queue_free()


func _build_visit_body(entry: Dictionary) -> String:
	var out: String    = ""
	var accent_hex: String = "#%s" % _c_accent.to_html(false)
	var sub_hex: String    = "#%s" % _c_subtext.to_html(false)
	var text_hex: String   = "#%s" % _c_text.to_html(false)

	# Snippet — convert == headers to bold BBCode, strip raw wikitext markers,
	# then wrap in explicit text colour for light-mode readability.
	var snippet: String = entry.get("snippet", "")
	if snippet != "":
		var lines2 := snippet.split("\n")
		var cleaned: PackedStringArray = []
		for line in lines2:
			var s := line.strip_edges()
			if s.begins_with("==") and s.ends_with("=="):
				var heading := s.trim_prefix("===").trim_suffix("===")\
					.trim_prefix("==").trim_suffix("==").strip_edges()
				if heading != "":
					cleaned.append("")
					cleaned.append("[b]%s[/b]" % heading)
			else:
				cleaned.append(line)
		var display: String = "\n".join(cleaned)
		if _search_query != "":
			display = _highlight(display, _search_query, accent_hex)
		out += "[color=%s]%s[/color]\\n\\n" % [text_hex, display]
	else:
		out += "[color=%s][i]No article excerpt available.[/i][/color]\\n\\n" % sub_hex
	# Pinned items
	var pins: Array = entry.get("pinned_items", [])
	if not pins.is_empty():
		out += "[color=%s][b]Pinned (%d)[/b][/color]\n" % [text_hex, pins.size()]
		for pin: Dictionary in pins:
			if pin.type == "image":
				out += "  [color=%s]🖼 %s[/color]\n" % [accent_hex, pin.get("caption", "Image")]
			elif pin.type == "text":
				var ex: String = pin.get("excerpt", "").substr(0, 120)
				out += "  [color=%s]📄 %s[/color]\n" % [accent_hex, ex]
		out += "\n"

	return out


func _build_race_body(entry: Dictionary) -> String:
	var out: String    = ""
	var acc: String    = "#%s" % _c_accent.to_html(false)
	var sub: String    = "#%s" % _c_subtext.to_html(false)
	var win_hex: String  = "#%s" % _c_win.to_html(false)
	var loss_hex: String = "#%s" % _c_loss.to_html(false)

	var runs: Array = entry.get("runs", [])
	if runs.is_empty():
		out += "[color=%s][i]No race runs recorded.[/i][/color]" % sub
		return out

	out += "[color=%s][b]Race History[/b][/color]\n" % acc

	var pb: int = entry.get("pb_secs", -1)
	for run: Dictionary in runs:
		var won: bool     = run.get("won", false)
		var secs: int     = run.get("time_secs", 0)
		var ts: int       = run.get("time_secs", 0)
		var date: String  = Time.get_date_string_from_unix_time(int(run.get("timestamp", 0)))
		var result_color: String = win_hex if won else loss_hex
		var result_word: String  = "Victory" if won else "Defeat"
		var time_str: String     = "%02d:%02d" % [secs / 60, secs % 60]
		var pb_tag: String       = "  [color=%s]⭐ PB[/color]" % acc if (won and secs == pb) else ""

		var start: String = run.get("start_article", "")
		var start_str: String = ("  [color=%s]from %s[/color]" % [sub, start]) if start != "" else ""

		out += "[color=%s][b]%s[/b][/color]  %s%s%s  [color=%s]%s[/color]\n" % [
			result_color, result_word, time_str, pb_tag, start_str, sub, date]

	return out


func _rebuild_tag_chips(entry: Dictionary) -> void:
	for c in _tag_hbox.get_children():
		c.queue_free()
	var tags: Array = entry.get("tags", [])
	for tag: String in tags:
		var chip := _make_tag_chip(tag, entry.title)
		_tag_hbox.add_child(chip)


func _make_tag_chip(tag: String, entry_title: String) -> Button:
	var btn := Button.new()
	btn.text = "%s ✕" % tag
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func():
		JournalManager.remove_tag(entry_title, tag)
		_show_detail(entry_title)
		_refresh_list()
	)
	# Filter shortcut: clicking a tag also sets the search field
	var dark: bool = ThemeManager.is_dark_mode
	var s := StyleBoxFlat.new()
	s.bg_color = Color(_c_accent, 0.15)
	s.border_color = _c_accent
	s.set_border_width_all(1)
	s.set_corner_radius_all(12)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(_c_accent, 0.28)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sh)
	for state in ["font_color","font_hover_color","font_pressed_color"]:
		btn.add_theme_color_override(state, _c_accent)
	if _serif_font:
		btn.add_theme_font_override("font", _serif_font)
	btn.add_theme_font_size_override("font_size", 12)
	return btn


# ── Note editing ──────────────────────────────────────────────────────────────

func _on_note_changed() -> void:
	if _selected_title == "":
		return
	_note_dirty      = true
	_note_save_timer = NOTE_DEBOUNCE


func _flush_note() -> void:
	if not _note_dirty or _selected_title == "":
		return
	_note_dirty = false
	JournalManager.set_note(_selected_title, _note_field.text)


# ── Event handlers ────────────────────────────────────────────────────────────

func _on_list_entry_pressed(title: String) -> void:
	if title == _selected_title:
		return
	_flush_note()
	_show_detail(title)
	# Re-render list to update selected highlight
	_refresh_list()


func _on_search_changed(text: String) -> void:
	_search_query = text.strip_edges()
	_refresh_list()


func _on_filter_pressed(idx: int) -> void:
	_current_filter = idx
	_set_active_tab(_filter_btns, idx)
	_refresh_list()


func _on_sort_pressed(idx: int) -> void:
	_current_sort = idx
	_set_active_tab(_sort_btns, idx)
	_refresh_list()


func _set_active_tab(btns: Array, active: int) -> void:
	for i in btns.size():
		btns[i].button_pressed = (i == active)


func _on_journal_changed(_arg = null) -> void:
	if _is_open:
		_refresh_list()
		if _selected_title != "":
			_show_detail(_selected_title)


func _on_tag_submitted(text: String) -> void:
	var tag: String = text.strip_edges()
	if tag == "" or _selected_title == "":
		return
	JournalManager.add_tag(_selected_title, tag)
	_tag_input.text = ""
	_show_detail(_selected_title)
	_refresh_list()


func _on_export_pressed() -> void:
	var md: String = JournalManager.export_markdown(_active_entries)
	DisplayServer.clipboard_set(md)
	# Brief visual feedback on the export button
	if is_instance_valid(_export_btn):
		var original: String = _export_btn.text
		_export_btn.text = "✓ Copied!"
		_export_btn.disabled = true
		await get_tree().create_timer(1.8).timeout
		if is_instance_valid(_export_btn):
			_export_btn.text     = original
			_export_btn.disabled = false


# ── Highlight helper ──────────────────────────────────────────────────────────

func _highlight(text: String, query: String, color_hex: String) -> String:
	var lower: String = text.to_lower()
	var q: String     = query.to_lower()
	var idx: int      = lower.find(q)
	if idx < 0:
		return text
	return "%s[color=%s][b]%s[/b][/color]%s" % [
		text.substr(0, idx),
		color_hex,
		text.substr(idx, query.length()),
		text.substr(idx + query.length())
	]


# ── Builder helpers ───────────────────────────────────────────────────────────

func _make_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_CLICK
	btn.pressed.connect(callback)
	return btn


func _make_tab_button(text: String) -> Button:
	var btn := Button.new()
	btn.text        = text
	btn.toggle_mode = true
	btn.focus_mode  = Control.FOCUS_NONE
	return btn


func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.color               = _c_border
	d.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	return d


# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	## Use _input (not _unhandled_input) so ESC is captured before Main.gd
	## can re-route it to the pause menu.
	if not _is_open:
		return
	if not event.is_action_pressed("ui_cancel"):
		return

	# If search field has focus, clear it first (don't close journal yet)
	if _search_field and _search_field.has_focus():
		_search_field.release_focus()
		get_viewport().set_input_as_handled()
		return

	# If note field has focus, just unfocus it
	if _note_field and _note_field.has_focus():
		_note_field.release_focus()
		get_viewport().set_input_as_handled()
		return

	# Otherwise close the journal
	close()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	## Navigation keys — only reach here if ESC was not consumed above.
	if not _is_open:
		return
	if _search_field and _search_field.has_focus():
		return
	if _note_field and _note_field.has_focus():
		return
	if event.is_action_pressed("strafe_left") or event.is_action_pressed("move_forward"):
		_select_adjacent(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("strafe_right") or event.is_action_pressed("move_back"):
		_select_adjacent(1)
		get_viewport().set_input_as_handled()


func _select_adjacent(dir: int) -> void:
	if _active_entries.is_empty():
		return
	var cur_idx: int = 0
	for i in _active_entries.size():
		if _active_entries[i].title == _selected_title:
			cur_idx = i
			break
	var new_idx: int = clampi(cur_idx + dir, 0, _active_entries.size() - 1)
	if new_idx != cur_idx:
		_flush_note()
		_show_detail(_active_entries[new_idx].title)
		_refresh_list()
