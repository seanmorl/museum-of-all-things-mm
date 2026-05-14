extends Control
class_name TriviaOverlay
## UI overlay for displaying trivia questions at exhibits.

signal trivia_answered(correct: bool, points: int)
signal trivia_closed
signal trivia_opened

var _trivia_manager: TriviaManager = null
var _current_questions: Array = []
var _current_index: int = 0
var _score: int = 0
var _is_open: bool = false
var _exhibit_title: String = ""
var _closing: bool = false

@onready var _panel: PanelContainer = $PanelContainer
@onready var _header: HBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/HeaderHBox
@onready var _title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HeaderHBox/TitleLabel
@onready var _close_btn: Button = $PanelContainer/MarginContainer/VBoxContainer/HeaderHBox/CloseBtn
@onready var _score_label: Label = $PanelContainer/MarginContainer/VBoxContainer/ScoreLabel
@onready var _question_label: RichTextLabel = $PanelContainer/MarginContainer/VBoxContainer/QuestionLabel
@onready var _answers_container: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/AnswersContainer
@onready var _loading_label: Label = $PanelContainer/MarginContainer/VBoxContainer/LoadingLabel
@onready var _next_btn: Button = $PanelContainer/MarginContainer/VBoxContainer/NextBtn

var _font: Font = null
var _panel_style: StyleBoxFlat = null

func _ready() -> void:
	visible = false
	add_to_group("mouse_overlay")

	if not _panel or not _close_btn or not _next_btn:
		push_error("TriviaOverlay: Missing required nodes in scene tree")
		return

	_panel.modulate.a = 0.0
	_panel.position.y = 14.0
	_close_btn.pressed.connect(close)
	_next_btn.pressed.connect(_on_next_pressed)

	_font = ThemeManager.get_reading_font()

	# Build panel style identical to PauseMenu / MultiplayerMenu
	var orig = _panel.get_theme_stylebox("panel")
	_panel_style = orig.duplicate() if orig is StyleBoxFlat else StyleBoxFlat.new()
	_panel.add_theme_stylebox_override("panel", _panel_style)

	_refresh_theme()
	ThemeManager.dark_mode_changed.connect(_on_theme_changed)
	ThemeManager.reading_font_changed.connect(func(f): _font = f; _refresh_theme())

func _on_theme_changed(_enabled: bool) -> void:
	_refresh_theme()

func init(trivia_manager: TriviaManager) -> void:
	_trivia_manager = trivia_manager
	if _trivia_manager:
		_trivia_manager.trivia_ready.connect(_on_trivia_ready)
		_trivia_manager.trivia_failed.connect(_on_trivia_failed)

func open(exhibit_title: String) -> void:
	_exhibit_title = exhibit_title
	_current_index = 0
	_score = 0
	_is_open = true
	_closing = false
	visible = true

	_panel.modulate.a = 0.0
	_panel.position.y = 14.0
	_animate_in()

	_update_score_label()
	_question_label.visible = false
	_answers_container.visible = false
	_next_btn.visible = false
	_loading_label.visible = true
	_close_btn.text = "✕"
	_title_label.text = exhibit_title

	if _trivia_manager:
		_trivia_manager.fetch_trivia(exhibit_title)
	trivia_opened.emit()

func close() -> void:
	if _closing:
		return
	_closing = true
	_animate_out(func():
		_is_open = false
		visible = false
		trivia_closed.emit()
	)

func _animate_in() -> void:
	if _panel:
		_panel.modulate.a = 0.0
		_panel.position.y = 14.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.40).set_delay(0.10)
		tw.tween_property(_panel, "position:y", 0.0, 0.40) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.10)

func _animate_out(then: Callable) -> void:
	if _panel:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_panel, "modulate:a", 0.0, 0.16)
		tw.tween_property(_panel, "position:y", 10.0, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(func():
			_closing = false
			then.call()
		)
	else:
		_closing = false
		then.call()

func is_open() -> bool:
	return _is_open

func _on_trivia_ready(article_title: String, questions: Array) -> void:
	if article_title != _exhibit_title:
		return

	_current_questions = questions
	_current_index = 0
	_loading_label.visible = false

	if _current_questions.is_empty():
		_question_label.text = "[i]No trivia available for this exhibit.[/i]"
		_question_label.visible = true
		_close_btn.text = "Close"
		return

	_display_current_question()

func _on_trivia_failed(article_title: String, error: String) -> void:
	if article_title != _exhibit_title:
		return

	_loading_label.visible = false
	_question_label.text = "[i]Could not load trivia: %s[/i]" % error
	_question_label.visible = true

func _display_current_question() -> void:
	if _current_index >= _current_questions.size():
		_show_final_score()
		return

	var q = _current_questions[_current_index]

	_question_label.text = "[b]Q%d / %d[/b]\n\n%s" % [
		_current_index + 1,
		_current_questions.size(),
		q.get("question", "No question available")
	]
	_question_label.visible = true

	for child in _answers_container.get_children():
		child.queue_free()

	var q_type = q.get("type", "multiple_choice")

	if q_type == "multiple_choice":
		_answers_container.visible = true
		_next_btn.visible = false

		var answers: Array = []
		answers.append(q.get("correct", ""))
		var wrong_answers: Array = q.get("wrong", [])
		if wrong_answers is Array:
			answers.append_array(wrong_answers)
		answers.shuffle()

		for answer in answers:
			var btn := _create_answer_button(str(answer))
			btn.pressed.connect(_on_answer_selected.bind(btn, q))
			_answers_container.add_child(btn)

	elif q_type == "fill_blank":
		_answers_container.visible = true
		_next_btn.visible = false

		var input := LineEdit.new()
		input.placeholder_text = "Type your answer..."
		input.custom_minimum_size.x = 300
		_style_line_edit(input)
		input.text_submitted.connect(_on_fill_blank_submitted.bind(q))
		_answers_container.add_child(input)
		input.grab_focus()

func _create_answer_button(text_val: String) -> Button:
	var btn := Button.new()
	btn.text = text_val
	btn.custom_minimum_size.y = 44
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_answer_button(btn, false, false)
	if _font:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 15)
	return btn

func _style_answer_button(btn: Button, correct: bool, wrong: bool) -> void:
	var dark := ThemeManager.is_dark_mode

	var base_bg: Color
	var base_border: Color
	var font_col: Color

	if correct:
		base_bg = Color(0.15, 0.55, 0.25, 0.85) if dark else Color(0.2, 0.7, 0.3, 0.85)
		base_border = Color(0.2, 0.8, 0.35)
		font_col = Color(0.9, 1.0, 0.92)
	elif wrong:
		base_bg = Color(0.55, 0.12, 0.12, 0.85) if dark else Color(0.75, 0.2, 0.2, 0.85)
		base_border = Color(0.85, 0.25, 0.25)
		font_col = Color(1.0, 0.88, 0.88)
	else:
		base_bg = Color(0, 0, 0, 0.0)
		base_border = ThemeManager.border_color
		font_col = ThemeManager.text_color

	var sn := StyleBoxFlat.new()
	sn.bg_color = base_bg
	sn.border_color = base_border
	sn.border_width_left = 1
	sn.border_width_top = 1
	sn.border_width_right = 1
	sn.border_width_bottom = 1
	sn.set_corner_radius_all(6)
	sn.content_margin_left = 16
	sn.content_margin_right = 16
	sn.content_margin_top = 10
	sn.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("disabled", sn)

	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(1, 1, 1, 0.07) if dark else Color(ThemeManager.border_color, 0.45)
	if not correct and not wrong:
		sh.border_color = ThemeManager.text_color.darkened(0.3)
	btn.add_theme_stylebox_override("hover", sh)

	var sp := sh.duplicate() as StyleBoxFlat
	sp.bg_color = Color(1, 1, 1, 0.12) if dark else Color(ThemeManager.border_color, 0.75)
	btn.add_theme_stylebox_override("pressed", sp)

	var sf := sn.duplicate() as StyleBoxFlat
	sf.border_color = ThemeManager.text_color
	sf.border_width_left = 2
	btn.add_theme_stylebox_override("focus", sf)

	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, font_col)
	btn.add_theme_color_override("font_disabled_color", font_col)

func _style_line_edit(edit: LineEdit) -> void:
	var dark := ThemeManager.is_dark_mode
	if _font:
		edit.add_theme_font_override("font", _font)
	edit.add_theme_font_size_override("font_size", 15)
	edit.add_theme_color_override("font_color", ThemeManager.text_color)
	edit.add_theme_color_override("font_placeholder_color", ThemeManager.subtext_color)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0.03) if dark else Color(ThemeManager.border_color, 0.3)
	sn.border_color = ThemeManager.border_color
	sn.border_width_left = 1
	sn.border_width_right = 1
	sn.border_width_top = 1
	sn.border_width_bottom = 1
	sn.set_corner_radius_all(6)
	sn.content_margin_left = 12
	sn.content_margin_right = 12
	sn.content_margin_top = 8
	sn.content_margin_bottom = 8
	edit.add_theme_stylebox_override("normal", sn)

	var sf := sn.duplicate() as StyleBoxFlat
	sf.border_color = ThemeManager.text_color
	sf.border_width_left = 2
	sf.border_width_right = 2
	sf.border_width_top = 2
	sf.border_width_bottom = 2
	edit.add_theme_stylebox_override("focus", sf)

func _on_answer_selected(button: Button, question: Dictionary) -> void:
	var selected_answer := button.text
	var correct_answer: String = question.get("correct", "")
	var is_correct := selected_answer.to_lower() == correct_answer.to_lower()

	for child in _answers_container.get_children():
		if child is Button:
			child.disabled = true
			var is_the_correct: bool = child.text.to_lower() == correct_answer.to_lower()
			var is_the_wrong: bool = child.text.to_lower() == selected_answer.to_lower() and not is_correct
			_style_answer_button(child, is_the_correct, is_the_wrong and not is_the_correct)

	if is_correct:
		_score += 10
		_update_score_label()
		trivia_answered.emit(true, 10)
	else:
		trivia_answered.emit(false, 0)

	_next_btn.visible = true
	_next_btn.text = "Next →" if _current_index < _current_questions.size() - 1 else "See Results"

func _on_fill_blank_submitted(text: String, question: Dictionary) -> void:
	var correct_answer: String = question.get("correct", "").to_lower()
	var submitted := text.strip_edges().to_lower()
	var is_correct := submitted == correct_answer

	if not is_correct and correct_answer.begins_with(submitted) and submitted.length() > 2:
		is_correct = true

	if is_correct:
		_score += 10
		_update_score_label()
		trivia_answered.emit(true, 10)
	else:
		trivia_answered.emit(false, 0)

	_next_btn.visible = true
	_next_btn.text = "Next →" if _current_index < _current_questions.size() - 1 else "See Results"

func _on_next_pressed() -> void:
	_current_index += 1
	_display_current_question()

func _show_final_score() -> void:
	var total := _current_questions.size() * 10
	var pct := int(float(_score) / float(total) * 100.0) if total > 0 else 0
	var grade: String
	if pct >= 90:
		grade = "🏆 Excellent!"
	elif pct >= 70:
		grade = "👍 Good work!"
	elif pct >= 50:
		grade = "📖 Keep reading!"
	else:
		grade = "💡 Better luck next time!"

	_question_label.text = (
		"[center][b]Trivia Complete![/b][/center]\n\n" +
		"[center]%s[/center]\n\n" +
		"[center]Score: [b]%d / %d[/b] (%d%%)[/center]"
	) % [grade, _score, total, pct]
	_question_label.visible = true
	_answers_container.visible = false
	_next_btn.visible = false

func _update_score_label() -> void:
	_score_label.text = "Score: %d" % _score

func _refresh_theme() -> void:
	if not _panel or not _panel_style:
		return

	var dark := ThemeManager.is_dark_mode

	_panel_style.bg_color = ThemeManager.bg_color
	_panel_style.border_color = ThemeManager.border_color
	for side in [0, 1, 2, 3]:
		_panel_style.set("border_width_" + ["left", "right", "top", "bottom"][side], 1)
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		_panel_style.set("corner_radius_" + corner, 10)
	_panel_style.shadow_color = Color(0, 0, 0, 0.35 if dark else 0.12)
	_panel_style.shadow_size = 16
	_panel_style.shadow_offset = Vector2(0, 6)
	_panel_style.content_margin_left   = 30
	_panel_style.content_margin_right  = 30
	_panel_style.content_margin_top    = 24
	_panel_style.content_margin_bottom = 20

	if _title_label:
		_title_label.label_settings = null
		_title_label.add_theme_color_override("font_color", ThemeManager.text_color)
		_title_label.add_theme_font_size_override("font_size", 28)
		if _font:
			_title_label.add_theme_font_override("font", _font)

	if _close_btn:
		_close_btn.add_theme_color_override("font_color", ThemeManager.subtext_color)
		_close_btn.add_theme_color_override("font_hover_color", Color(0.85, 0.3, 0.3))
		_close_btn.add_theme_font_size_override("font_size", 16)
		for style_name in ["normal", "hover", "pressed", "focus"]:
			var s := StyleBoxFlat.new()
			s.bg_color = Color(0, 0, 0, 0) if style_name == "normal" else \
				(Color(0.7, 0.2, 0.2, 0.15) if style_name == "hover" else Color(0.7, 0.2, 0.2, 0.25))
			s.set_corner_radius_all(4)
			_close_btn.add_theme_stylebox_override(style_name, s)

	if _score_label:
		_score_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
		if _font:
			_score_label.add_theme_font_override("font", _font)
		_score_label.add_theme_font_size_override("font_size", 15)

	if _question_label:
		_question_label.add_theme_color_override("default_color", ThemeManager.text_color)
		if _font:
			_question_label.add_theme_font_override("normal_font", _font)
			_question_label.add_theme_font_override("bold_font", _font)
		_question_label.add_theme_font_size_override("normal_font_size", 18)

	if _loading_label:
		_loading_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
		if _font:
			_loading_label.add_theme_font_override("font", _font)
		_loading_label.add_theme_font_size_override("font_size", 16)

	var hs := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/HSeparator")
	if hs:
		hs.add_theme_color_override("color", ThemeManager.border_color)

	if _next_btn:
		if _font:
			_next_btn.add_theme_font_override("font", _font)
		_next_btn.add_theme_font_size_override("font_size", 16)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			_next_btn.add_theme_color_override(state, ThemeManager.text_color)

		var sn := StyleBoxFlat.new()
		sn.bg_color = Color(0, 0, 0, 0)
		sn.content_margin_left = 16; sn.content_margin_right = 16
		sn.content_margin_top = 9;   sn.content_margin_bottom = 9
		_next_btn.add_theme_stylebox_override("normal", sn)

		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(1, 1, 1, 0.06) if dark else Color(ThemeManager.border_color, 0.5)
		sh.set_corner_radius_all(5)
		sh.content_margin_left = 16; sh.content_margin_right = 16
		sh.content_margin_top = 9;   sh.content_margin_bottom = 9
		_next_btn.add_theme_stylebox_override("hover", sh)

		var sp := sh.duplicate() as StyleBoxFlat
		sp.bg_color = Color(1, 1, 1, 0.12) if dark else Color(ThemeManager.border_color, 0.85)
		_next_btn.add_theme_stylebox_override("pressed", sp)

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
