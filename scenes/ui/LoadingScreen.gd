extends CanvasLayer
## LoadingScreen — full-screen overlay with animated spinner and status message.
##
## Usage:
##   LoadingScreen.show_loading("Fetching article…")
##   LoadingScreen.set_message("Building exhibit…")
##   LoadingScreen.set_progress(0.75)   # optional 0.0–1.0 progress bar
##   LoadingScreen.hide_loading()
##
## The overlay is a CanvasLayer (layer 100) so it always renders above the 3D
## world and all in-game UI, but below the screenshot flash layer (127).
## Add as an Autoload at res://scenes/ui/LoadingScreen.gd.

signal hidden

## How long the fade-in / fade-out takes in seconds.
const FADE_DURATION: float = 0.28

## How long to wait before showing the spinner (avoids flash for fast loads).
const SHOW_DELAY:    float = 0.12

## Number of arc segments in the spinner.
const SEGMENT_COUNT: int   = 8

## Visual state
var _visible_state: bool   = false
var _show_timer:    float  = 0.0
var _pending_show:  bool   = false
var _spin_angle:    float  = 0.0

## Node references — built in _ready
var _backdrop:     ColorRect   = null
var _root:         Control     = null   # full-screen Control we fade instead of self
var _card:         Control     = null
var _card_style:   StyleBoxFlat = null
var _spinner:      Control     = null   # draws via _draw override
var _msg_label:    Label       = null
var _sub_label:    Label       = null
var _progress_bg:  ColorRect   = null
var _progress_bar: ColorRect   = null
var _serif_font:   Font        = null

## Progress (0.0 – 1.0, negative = hidden)
var _progress: float = -1.0

## Stored lambdas for proper signal cleanup
var _dark_mode_lambda: Callable = Callable()
var _reading_font_lambda: Callable = Callable()


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_serif_font = ThemeManager.get_reading_font()
	_build_ui()
	_dark_mode_lambda = func(_d): _apply_theme()
	_reading_font_lambda = func(f): _serif_font = f; _apply_theme()
	ThemeManager.dark_mode_changed.connect(_dark_mode_lambda)
	ThemeManager.reading_font_changed.connect(_reading_font_lambda)


func _exit_tree() -> void:
	if _dark_mode_lambda.is_valid():
		ThemeManager.dark_mode_changed.disconnect(_dark_mode_lambda)
	if _reading_font_lambda.is_valid():
		ThemeManager.reading_font_changed.disconnect(_reading_font_lambda)


func _process(delta: float) -> void:
	if _pending_show:
		_show_timer -= delta
		if _show_timer <= 0.0:
			_pending_show = false
			_do_show()
		return

	if _visible_state and is_instance_valid(_spinner):
		_spin_angle += delta * 2.4   # radians/sec
		_spinner.queue_redraw()


# ── Public API ────────────────────────────────────────────────────────────────

func show_loading(message: String = "Loading…", sub: String = "") -> void:
	## Show the loading screen with an optional message and sub-message.
	if _visible_state:
		set_message(message, sub)
		return
	_set_message_text(message, sub)
	set_progress(-1.0)
	_pending_show = true
	_show_timer   = SHOW_DELAY


func hide_loading() -> void:
	## Fade the loading screen out.
	_pending_show = false
	if not _visible_state:
		return
	_visible_state = false
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		visible = false
		_root.modulate.a = 1.0
		hidden.emit()
	)


func set_message(message: String, sub: String = "") -> void:
	_set_message_text(message, sub)


func set_progress(value: float) -> void:
	## Pass 0.0–1.0 to show a progress bar. Pass -1.0 to hide it.
	_progress = value
	if not is_instance_valid(_progress_bg):
		return
	if value < 0.0:
		_progress_bg.visible = false
	else:
		_progress_bg.visible = true
		var w: float = _progress_bg.size.x
		_progress_bar.size.x = clampf(value, 0.0, 1.0) * w


# ── Internal helpers ──────────────────────────────────────────────────────────

func _do_show() -> void:
	visible              = true
	_visible_state       = true
	_root.modulate.a     = 0.0
	_apply_theme()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_message_text(msg: String, sub: String) -> void:
	if is_instance_valid(_msg_label):
		_msg_label.text = msg
	if is_instance_valid(_sub_label):
		_sub_label.text = sub
		_sub_label.visible = sub != ""


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# CanvasLayer has no modulate — we fade a full-screen Control child instead.
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Full-screen backdrop
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	# Centred card — anchor to viewport centre, offset by half card size
	_card = Control.new()
	_card.custom_minimum_size = Vector2(320, 220)
	_card.size = Vector2(320, 220)
	# Anchor to centre of parent, then pull back by half width/height
	_card.anchor_left   = 0.5
	_card.anchor_top    = 0.5
	_card.anchor_right  = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left   = -160
	_card.offset_top    = -110
	_card.offset_right  =  160
	_card.offset_bottom =  110
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_root.add_child(_card)

	var card_panel := PanelContainer.new()
	card_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_style = StyleBoxFlat.new()
	card_panel.add_theme_stylebox_override("panel", _card_style)
	_card.add_child(card_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Inset the content
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   32)
	mc.add_theme_constant_override("margin_right",  32)
	mc.add_theme_constant_override("margin_top",    28)
	mc.add_theme_constant_override("margin_bottom", 28)
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_panel.add_child(mc)
	mc.add_child(vbox)

	# Spinner (custom drawn Control)
	var spinner_wrapper := CenterContainer.new()
	spinner_wrapper.custom_minimum_size = Vector2(0, 72)
	vbox.add_child(spinner_wrapper)

	_spinner = _SpinnerNode.new()
	_spinner.custom_minimum_size = Vector2(60, 60)
	_spinner.size = Vector2(60, 60)
	_spinner.loading_screen = self   # pass reference so it reads _spin_angle, colours
	spinner_wrapper.add_child(_spinner)

	# Message
	_msg_label = Label.new()
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_msg_label)

	# Sub message
	_sub_label = Label.new()
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.visible = false
	vbox.add_child(_sub_label)

	# Progress bar track
	_progress_bg = ColorRect.new()
	_progress_bg.custom_minimum_size = Vector2(0, 3)
	_progress_bg.visible = false
	vbox.add_child(_progress_bg)

	# Progress bar fill — positioned inside track after layout
	_progress_bar = ColorRect.new()
	_progress_bar.size = Vector2(0, 3)
	_progress_bg.add_child(_progress_bar)

	_apply_theme()


func _apply_theme() -> void:
	if not is_instance_valid(_backdrop):
		return
	var dark: bool = ThemeManager.is_dark_mode

	# Backdrop — semi-transparent tint
	_backdrop.color = Color(0.05, 0.05, 0.08, 0.72) if dark \
		else Color(0.90, 0.90, 0.93, 0.80)

	# Card
	if _card_style:
		_card_style.bg_color     = ThemeManager.bg_color
		_card_style.border_color = ThemeManager.border_color
		_card_style.set_border_width_all(1)
		_card_style.set_corner_radius_all(12)
		_card_style.shadow_color  = Color(0, 0, 0, 0.30 if dark else 0.12)
		_card_style.shadow_size   = 20
		_card_style.shadow_offset = Vector2(0, 6)

	# Labels
	for lbl: Label in [_msg_label, _sub_label]:
		if not is_instance_valid(lbl):
			continue
		if _serif_font:
			lbl.add_theme_font_override("font", _serif_font)
		lbl.add_theme_color_override("font_color", ThemeManager.text_color)

	if is_instance_valid(_msg_label):
		_msg_label.add_theme_font_size_override("font_size", 18)

	if is_instance_valid(_sub_label):
		_sub_label.add_theme_color_override("font_color", ThemeManager.subtext_color)
		_sub_label.add_theme_font_size_override("font_size", 13)

	# Progress bar colours
	var accent := Color(0.35, 0.55, 1.00) if dark else Color(0.15, 0.35, 0.85)
	if is_instance_valid(_progress_bg):
		_progress_bg.color = Color(accent, 0.18)
	if is_instance_valid(_progress_bar):
		_progress_bar.color = accent

	if is_instance_valid(_spinner):
		_spinner.queue_redraw()


# ── Spinner node (inner class) ────────────────────────────────────────────────

class _SpinnerNode extends Control:
	const SEGMENT_COUNT: int = 8  # must be redeclared — inner classes can't access outer consts
	## Draws a rotating arc-segment ring — the MoAT loading mark.
	## Eight segments at staggered opacities, plus a slow counter-rotating
	## outer ring, give a refined clockwork feel that suits the museum aesthetic.

	var loading_screen: Node = null   # parent LoadingScreen reference

	func _draw() -> void:
		if not loading_screen:
			return

		var dark: bool = ThemeManager.is_dark_mode
		var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.10, 0.30, 0.80)

		var cx: float = size.x * 0.5
		var cy: float = size.y * 0.5
		var r_outer: float = min(cx, cy) - 2.0
		var r_inner: float = r_outer * 0.58
		var seg_gap: float = 0.18   # radians of gap between segments

		var angle: float = loading_screen._spin_angle

		# ── Inner rotating segments ───────────────────────────────────────────
		for i in SEGMENT_COUNT:
			var seg_angle: float = TAU / SEGMENT_COUNT
			var start_a:   float = angle + i * seg_angle + seg_gap * 0.5
			var end_a:     float = angle + (i + 1) * seg_angle - seg_gap * 0.5

			# Trailing fade: segment 0 is brightest, last is dimmest
			var t: float = float(i) / float(SEGMENT_COUNT)
			var alpha: float = lerpf(1.0, 0.08, t)
			var col := Color(accent, alpha)

			# Draw arc as a fan of thin triangles
			var steps: int = 12
			for s in steps:
				var a0: float = lerpf(start_a, end_a, float(s)     / steps)
				var a1: float = lerpf(start_a, end_a, float(s + 1) / steps)
				var pts: PackedVector2Array = PackedVector2Array([
					Vector2(cx + cos(a0) * r_inner, cy + sin(a0) * r_inner),
					Vector2(cx + cos(a0) * r_outer, cy + sin(a0) * r_outer),
					Vector2(cx + cos(a1) * r_outer, cy + sin(a1) * r_outer),
					Vector2(cx + cos(a1) * r_inner, cy + sin(a1) * r_inner),
				])
				draw_colored_polygon(pts, col)

		# ── Outer slow counter-rotating dotted ring ───────────────────────────
		var dot_count: int = 12
		var dot_r: float = r_outer + 7.0
		var dot_radius: float = 1.8
		var slow_angle: float = -loading_screen._spin_angle * 0.3
		for i in dot_count:
			var da: float = slow_angle + i * TAU / dot_count
			var dx: float = cx + cos(da) * dot_r
			var dy: float = cy + sin(da) * dot_r
			var dot_alpha: float = lerpf(0.6, 0.12, float(i) / dot_count)
			draw_circle(Vector2(dx, dy), dot_radius, Color(accent, dot_alpha))

		# ── Centre dot ────────────────────────────────────────────────────────
		draw_circle(Vector2(cx, cy), 3.5, Color(accent, 0.55))
