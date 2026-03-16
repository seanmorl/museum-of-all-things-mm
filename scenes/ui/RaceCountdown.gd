extends CanvasLayer
## RaceCountdown — full-screen countdown overlay for race start.
##
## Connects to RaceManager.race_countdown(number: int) and
## RaceManager.race_started(target, start).
##
## Each number (3, 2, 1) performs:
##   • A dim backdrop that pulses in then fades
##   • The numeral in large Cormorant Garamond — drops from above, overshoots,
##     then snaps to centre with a subtle elastic settle
##   • An expanding ink-ring drawn via _draw() that traces the numeral's impact
##   • The target article title fades in beneath as a fine-print sub-line
##
## On GO:
##   • "GO" slams in from below and catapults upward off-screen
##   • The accent ring fires as a wide fast burst
##   • Backdrop fades fully — race begins
##
## Add to Autoload: res://scenes/ui/RaceCountdown.tscn, name "RaceCountdown".

signal countdown_finished

# ── Layer / visibility ────────────────────────────────────────────────────────
const LAYER: int = 110   # above LoadingScreen (100), below screenshot flash (127)

# ── Animation constants ───────────────────────────────────────────────────────
const SETTLE_SCALE:   Vector2 = Vector2(1.08, 1.08)
const FINAL_SCALE:    Vector2 = Vector2(1.00, 1.00)
const SMALL_SCALE:    Vector2 = Vector2(0.70, 0.70)
const RING_MAX_SCALE: float   = 3.8
const RING_DURATION:  float   = 0.65
const NUM_DURATION:   float   = 0.85

# ── Node refs (built in code) ─────────────────────────────────────────────────
var _root:        Control    = null
var _backdrop:    ColorRect  = null
var _ring_canvas: Control    = null   # draws the expanding ring
var _numeral_lbl: Label      = null
var _target_lbl:  Label      = null   # "Find: [article]" sub-line
var _serif_font:  Font       = null

# ── Ring draw state ───────────────────────────────────────────────────────────
var _ring_scale:  float  = 0.0   # 0.0 = hidden, grows to RING_MAX_SCALE
var _ring_alpha:  float  = 0.0
var _ring_is_go:  bool   = false  # wider burst on GO
var _ring_tween:  Tween  = null

# ── Runtime state ─────────────────────────────────────────────────────────────
var _target_article: String = ""
var _active:         bool   = false


func _ready() -> void:
	layer        = LAYER
	visible      = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_serif_font  = ThemeManager.get_reading_font()
	_build_ui()
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_theme())
	ThemeManager.reading_font_changed.connect(func(f): _serif_font = f; _apply_theme())
	# Connect to RaceManager signals
	RaceManager.race_countdown.connect(_on_race_countdown)
	RaceManager.race_started.connect(_on_race_started)


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Fade-able root Control (CanvasLayer has no modulate)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Dim backdrop
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)

	# Ring canvas — sits behind the numeral
	_ring_canvas = Control.new()
	_ring_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring_canvas.draw.connect(_on_ring_draw)
	_root.add_child(_ring_canvas)

	# Numeral label — fills the whole screen, text centred
	# Using FULL_RECT avoids the PRESET_CENTER position-capture bug where
	# _numeral_lbl.position reads (0,0) before the first layout pass.
	_numeral_lbl = Label.new()
	_numeral_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_numeral_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_numeral_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_numeral_lbl.pivot_offset          = Vector2(0, 0)   # set properly in _apply_theme
	_numeral_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_numeral_lbl)

	# Target article sub-line — just below centre
	_target_lbl = Label.new()
	_target_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_target_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_target_lbl.offset_left   = -280
	_target_lbl.offset_right  =  280
	_target_lbl.offset_top    =  80
	_target_lbl.offset_bottom =  140
	_target_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_target_lbl.modulate.a    = 0.0
	_root.add_child(_target_lbl)

	_apply_theme()


func _apply_theme() -> void:
	if not _backdrop:
		return
	var dark: bool = ThemeManager.is_dark_mode
	var accent := _accent()

	_backdrop.color = Color(0.04, 0.04, 0.06, 0.82) if dark \
		else Color(0.93, 0.94, 0.97, 0.88)

	if _numeral_lbl:
		if _serif_font:
			_numeral_lbl.add_theme_font_override("font", _serif_font)
		_numeral_lbl.add_theme_font_size_override("font_size", 200)
		_numeral_lbl.add_theme_color_override("font_color", ThemeManager.text_color)

	if _target_lbl:
		if _serif_font:
			_target_lbl.add_theme_font_override("font", _serif_font)
		_target_lbl.add_theme_font_size_override("font_size", 17)
		_target_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)

	if _ring_canvas:
		_ring_canvas.queue_redraw()


func _accent() -> Color:
	return Color(0.30, 0.55, 1.00) if ThemeManager.is_dark_mode \
		else Color(0.12, 0.32, 0.82)


# ── Ring drawing ──────────────────────────────────────────────────────────────

func _on_ring_draw() -> void:
	if _ring_alpha <= 0.005 or not _ring_canvas:
		return
	var vp   := _ring_canvas.size
	var cx   := vp.x * 0.5
	var cy   := vp.y * 0.5
	var r: float = (min(vp.x, vp.y) * 0.18) * _ring_scale
	var w    := 3.0 if not _ring_is_go else 5.0
	var acc  := _accent()

	# Outer ring
	_ring_canvas.draw_arc(
		Vector2(cx, cy), r, 0.0, TAU,
		64, Color(acc, _ring_alpha * 0.9), w, true
	)
	# Faint inner echo at 62% radius
	_ring_canvas.draw_arc(
		Vector2(cx, cy), r * 0.62, 0.0, TAU,
		48, Color(acc, _ring_alpha * 0.35), w * 0.6, true
	)


func _fire_ring(is_go: bool = false) -> void:
	_ring_is_go = is_go
	_ring_scale = 0.3
	_ring_alpha = 0.9
	if _ring_tween and _ring_tween.is_valid():
		_ring_tween.kill()
	_ring_tween = create_tween().set_parallel(true)
	var target_scale := RING_MAX_SCALE * (1.4 if is_go else 1.0)
	var duration     := RING_DURATION  * (0.75 if is_go else 1.0)
	_ring_tween.tween_method(func(v: float):
		_ring_scale = v
		if _ring_canvas: _ring_canvas.queue_redraw()
	, 0.3, target_scale, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_ring_tween.tween_method(func(v: float):
		_ring_alpha = v
		if _ring_canvas: _ring_canvas.queue_redraw()
	, 0.9, 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ── Number animation ──────────────────────────────────────────────────────────

func _show_number(text: String, show_target: bool = false) -> void:
	if not _numeral_lbl:
		return

	_numeral_lbl.text = text
	# pivot at screen centre so scale animates from the middle
	_numeral_lbl.pivot_offset = _numeral_lbl.size * 0.5

	_numeral_lbl.scale    = SETTLE_SCALE
	_numeral_lbl.modulate = Color(1, 1, 1, 0)

	# Target sub-line
	_target_lbl.modulate.a = 0.0
	if show_target and _target_article != "":
		_target_lbl.text = "Find:  %s" % _target_article

	var tw := create_tween().set_parallel(true)

	# Scale drops from slightly large with elastic overshoot
	tw.tween_property(_numeral_lbl, "scale",
		FINAL_SCALE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_numeral_lbl, "modulate:a",
		1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Ring fires on impact
	tw.tween_callback(func(): _fire_ring(false)).set_delay(0.30)

	# Show target label
	if show_target and _target_article != "":
		tw.tween_property(_target_lbl, "modulate:a",
			1.0, 0.35).set_delay(0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _exit_number() -> void:
	## Shrink and fade the current numeral out quickly before the next one appears.
	if not _numeral_lbl:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_numeral_lbl, "scale",
		SMALL_SCALE, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_numeral_lbl, "modulate:a",
		0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_target_lbl, "modulate:a",
		0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _show_go() -> void:
	if not _numeral_lbl:
		return
	_target_lbl.modulate.a = 0.0

	_numeral_lbl.text     = "GO"
	_numeral_lbl.scale    = Vector2(1.4, 1.4)
	_numeral_lbl.modulate = Color(1, 1, 1, 0)
	_numeral_lbl.pivot_offset = _numeral_lbl.size * 0.5

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_numeral_lbl, "scale", FINAL_SCALE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_numeral_lbl, "modulate:a", 1.0, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_fire_ring(true)

	# After a beat, shrink GO away and fade everything out
	await get_tree().create_timer(0.55).timeout
	if not _active:
		return

	var out_tw := create_tween().set_parallel(true)
	out_tw.tween_property(_numeral_lbl, "scale", Vector2(1.5, 1.5), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	out_tw.tween_property(_numeral_lbl, "modulate:a", 0.0, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	out_tw.tween_property(_backdrop, "color:a", 0.0, 0.45) \
		.set_delay(0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	out_tw.tween_property(_root, "modulate:a", 0.0, 0.40) \
		.set_delay(0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	await out_tw.finished
	_active          = false
	visible          = false
	_root.modulate.a = 1.0
	countdown_finished.emit()


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_race_countdown(number: int) -> void:
	if number <= 0 or number > 3:
		return

	if not _active:
		# First number — open the overlay
		_active = true
		visible = true
		_root.modulate.a = 0.0
		_apply_theme()
		var open_tw := create_tween()
		open_tw.tween_property(_root, "modulate:a", 1.0, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_exit_number()
		await get_tree().create_timer(0.22).timeout
		if not _active:
			return

	# Show number 3 with target label, 2 and 1 without
	_show_number(str(number), number == 3)


func _on_race_started(target: String, _start: String) -> void:
	_target_article = target
	if not _active:
		return
	_exit_number()
	await get_tree().create_timer(0.20).timeout
	if _active:
		_show_go()


## Call this to inject the target article before the countdown begins
## (e.g. from Main.gd when the vote winner is known).
func set_target(article: String) -> void:
	_target_article = article
