extends RefCounted
class_name UIStyle
## Centralized UI styling utilities for consistent design across MoAT.
## 
## This class provides standardized styling helpers that all UI components
## should use to ensure visual consistency. All colors, spacing, corner
## radii, and animation timings are defined here.
##
## Usage:
##   var btn_style := UIStyle.create_button_style()
##   var panel_style := UIStyle.create_panel_style()
##   var style := UIStyle.create_card_style(bg_color, border_color)

# ── Design Tokens ─────────────────────────────────────────────────────────────

## Corner radius for large panels (main menu, pause menu, modals)
const CORNER_RADIUS_PANEL: float = 14.0

## Corner radius for buttons and small controls
const CORNER_RADIUS_BUTTON: float = 8.0

## Corner radius for small elements (chips, tags)
const CORNER_RADIUS_SMALL: float = 6.0

## Standard content margin (buttons, panels)
const MARGIN_STANDARD: float = 16.0

## Large content margin (modals, cards)
const MARGIN_LARGE: float = 32.0

## Button internal padding
const BUTTON_PADDING: float = 12.0

## Panel internal padding
const PANEL_PADDING: float = 20.0

## Standard spacing between related elements
const SPACING_TIGHT: float = 4.0

## Standard spacing between elements
const SPACING_STANDARD: float = 8.0

## Spacing for grouped sections
const SPACING_LOOSE: float = 14.0

## Button hover slide offset (pixels)
const HOVER_OFFSET: float = 6.0

# ── Animation Timings ─────────────────────────────────────────────────────────

## Standard fade in/out duration
const FADE_DURATION: float = 0.30

## Quick fade for toasts and notifications
const FADE_QUICK: float = 0.15

## Slide animation duration
const SLIDE_DURATION: float = 0.35

## Button hover transition
const HOVER_DURATION: float = 0.18

## Button hover return (slightly slower for smooth feel)
const HOVER_RETURN_DURATION: float = 0.20

## Panel entrance animation
const ENTRANCE_DURATION: float = 0.45

## Exit animation (quicker than entrance)
const EXIT_DURATION: float = 0.16

## Stagger delay between sequential elements
const STAGGER_DELAY: float = 0.04

# ── Easing Curves ─────────────────────────────────────────────────────────────

## Smooth, natural movement (default for most animations)
const EASE_STANDARD: Tween.EaseType = Tween.EASE_OUT
const TRANS_STANDARD: Tween.TransitionType = Tween.TRANS_CUBIC

## Bouncy entrance for modals and panels
const EASE_BOUNCE: Tween.EaseType = Tween.EASE_OUT
const TRANS_BOUNCE: Tween.TransitionType = Tween.TRANS_BACK

## Quick exit animations
const EASE_EXIT: Tween.EaseType = Tween.EASE_IN
const TRANS_EXIT: Tween.TransitionType = Tween.TRANS_QUAD

## Smooth in-out for continuous animations
const EASE_SMOOTH: Tween.EaseType = Tween.EASE_IN_OUT
const TRANS_SMOOTH: Tween.TransitionType = Tween.TRANS_CUBIC

# ── Style Creation Helpers ────────────────────────────────────────────────────

static func create_button_style(
	bg_color: Color = Color.TRANSPARENT,
	border_color: Color = Color.TRANSPARENT,
	corner_radius: float = CORNER_RADIUS_BUTTON,
	padding: float = BUTTON_PADDING
) -> StyleBoxFlat:
	"""Creates a base button style. Apply state-specific overrides after."""
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1 if border_color.a > 0 else 0)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = padding * 1.4
	style.content_margin_right = padding * 1.4
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


static func create_button_states(
	dark: bool,
	primary: bool = false,
	flat: bool = false
) -> Dictionary:
	"""
	Creates a complete set of button state styles.
	Returns: {normal, hover, pressed, focus, disabled}
	
	Usage:
	  var states := UIStyle.create_button_states(dark_mode, true)
	  btn.add_theme_stylebox_override("normal", states.normal)
	"""
	var accent := Color(0.30, 0.55, 1.00) if dark else Color(0.15, 0.35, 0.85)
	var border := Color(0.32, 0.32, 0.37, 1.0) if dark else Color(0.635, 0.663, 0.694, 1.0)
	var hover_tint := Color(1, 1, 1, 0.07) if dark else Color(accent, 0.07)
	var pressed_tint := Color(1, 1, 1, 0.14) if dark else Color(accent, 0.14)
	
	var normal := create_button_style()
	
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover_tint
	
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = pressed_tint
	
	var focus := hover.duplicate() as StyleBoxFlat
	focus.border_color = accent
	focus.set_border_width_all(2)
	
	var disabled := create_button_style(Color(1, 1, 1, 0.02 if dark else 0.02))
	
	if primary:
		var primary_border := Color(accent, 0.35)
		normal.bg_color = Color(accent, 0.10 if dark else 0.06)
		normal.border_color = primary_border
		
		hover.bg_color = Color(accent, 0.20 if dark else 0.14)
		hover.border_color = Color(accent, 0.60)
		
		pressed.bg_color = Color(accent, 0.30 if dark else 0.20)
	
	if flat:
		normal.border_width_left = 0
		normal.border_width_right = 0
		normal.border_width_top = 0
		normal.border_width_bottom = 0
	
	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"focus": focus,
		"disabled": disabled
	}


static func create_panel_style(
	bg_color: Color,
	border_color: Color,
	dark: bool,
	corner_radius: float = CORNER_RADIUS_PANEL,
	padding: float = PANEL_PADDING,
	shadow: bool = true
) -> StyleBoxFlat:
	"""
	Creates a panel/modal style with optional shadow.
	
	Usage:
	  var panel_style := UIStyle.create_panel_style(
	    ThemeManager.bg_color,
	    ThemeManager.border_color,
	    ThemeManager.is_dark_mode
	  )
	"""
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding * 1.2
	style.content_margin_bottom = padding * 1.2
	
	if shadow:
		style.shadow_color = Color(0, 0, 0, 0.30 if dark else 0.10)
		style.shadow_size = 16
		style.shadow_offset = Vector2(0, 6)
	
	return style


static func create_card_style(
	bg_color: Color,
	border_color: Color,
	dark: bool,
	corner_radius: float = CORNER_RADIUS_SMALL
) -> StyleBoxFlat:
	"""
	Creates a card/toast style (compact panel).
	
	Usage:
	  var card_style := UIStyle.create_card_style(
	    _panel_bg, _panel_border, dark_mode
	  )
	"""
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


static func create_input_style(
	bg_color: Color,
	border_color: Color,
	text_color: Color,
	subtext_color: Color,
	dark: bool,
	font: Font = null
) -> Dictionary:
	"""
	Creates input field styles (LineEdit, SpinBox).
	Returns: {style, focus_style}
	
	Usage:
	  var styles := UIStyle.create_input_style(...)
	  line_edit.add_theme_stylebox_override("normal", styles.style)
	"""
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0.2) if dark else Color(1, 1, 1, 0.8)
	normal.border_color = border_color
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(CORNER_RADIUS_SMALL)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = text_color
	focus.set_border_width_all(2)
	
	return {
		"normal": normal,
		"focus": focus
	}


static func create_tab_style(
	text_color: Color,
	subtext_color: Color,
	accent_color: Color,
	dark: bool,
	font: Font = null
) -> Dictionary:
	"""
	Creates tab bar styles.
	Returns: {tab_selected, tab_unselected, tab_hovered, panel_bg}
	"""
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color.TRANSPARENT
	selected.border_color = accent_color
	selected.border_width_bottom = 2
	selected.content_margin_left = 12
	selected.content_margin_right = 12
	
	var unselected := StyleBoxEmpty.new()
	unselected.content_margin_left = 12
	unselected.content_margin_right = 12
	
	var hovered := StyleBoxFlat.new()
	hovered.bg_color = Color(1, 1, 1, 0.05) if dark else Color(0, 0, 0, 0.05)
	hovered.set_corner_radius_all(CORNER_RADIUS_SMALL)
	hovered.content_margin_left = 12
	hovered.content_margin_right = 12
	
	var panel_bg := StyleBoxEmpty.new()
	
	return {
		"selected": selected,
		"unselected": unselected,
		"hovered": hovered,
		"panel_bg": panel_bg
	}


static func create_divider_style(color: Color) -> StyleBoxLine:
	"""Creates a horizontal divider line."""
	var divider := StyleBoxLine.new()
	divider.color = color
	divider.thickness = 1
	divider.grow_begin = 0
	divider.grow_end = 0
	return divider


# ── Animation Helpers ─────────────────────────────────────────────────────────

static func animate_fade_in(
	node: Control,
	duration: float = FADE_DURATION,
	delay: float = 0.0
) -> Tween:
	"""
	Fades a node in. Returns the Tween for chaining.
	
	Usage:
	  UIStyle.animate_fade_in(my_control)
	"""
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", 1.0, duration) \
		.set_trans(TRANS_STANDARD) \
		.set_ease(EASE_STANDARD) \
		.set_delay(delay)
	return tw


static func animate_fade_out(
	node: Control,
	duration: float = FADE_QUICK,
	then: Callable = Callable()
) -> Tween:
	"""
	Fades a node out. Optionally calls a callback when done.
	
	Usage:
	  UIStyle.animate_fade_out(my_control, 0.2, func(): my_control.visible = false)
	"""
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", 0.0, duration) \
		.set_trans(TRANS_EXIT) \
		.set_ease(EASE_EXIT)
	if then.is_valid():
		tw.chain().tween_callback(then)
	return tw


static func animate_slide_in(
	node: Control,
	offset: Vector2 = Vector2(0, 10),
	duration: float = SLIDE_DURATION,
	delay: float = 0.0,
	bounce: bool = true
) -> Tween:
	"""
	Slides and fades a node in.
	
	Usage:
	  UIStyle.animate_slide_in(my_panel, Vector2(0, 14))
	"""
	node.modulate.a = 0.0
	node.position = node.position + offset
	
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "modulate:a", 1.0, duration).set_delay(delay)
	tw.tween_property(node, "position", node.position - offset, duration) \
		.set_trans(TRANS_BOUNCE if bounce else TRANS_STANDARD) \
		.set_ease(EASE_BOUNCE if bounce else EASE_STANDARD) \
		.set_delay(delay)
	return tw


static func animate_slide_out(
	node: Control,
	offset: Vector2 = Vector2(0, 10),
	duration: float = EXIT_DURATION,
	then: Callable = Callable()
) -> Tween:
	"""
	Slides and fades a node out.
	
	Usage:
	  UIStyle.animate_slide_out(my_panel, Vector2(0, 10), 0.16, close_callback)
	"""
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "modulate:a", 0.0, duration) \
		.set_trans(TRANS_EXIT) \
		.set_ease(EASE_EXIT)
	tw.tween_property(node, "position", node.position + offset, duration) \
		.set_trans(TRANS_EXIT) \
		.set_ease(EASE_EXIT)
	if then.is_valid():
		tw.chain().tween_callback(then)
	return tw


static func animate_scale_in(
	node: Control,
	from_scale: Vector2 = Vector2(0.88, 0.88),
	duration: float = ENTRANCE_DURATION,
	delay: float = 0.0
) -> Tween:
	"""
	Scales and fades a node in (modal entrance).
	
	Usage:
	  UIStyle.animate_scale_in(victory_panel)
	"""
	node.modulate.a = 0.0
	node.scale = from_scale
	node.pivot_offset = node.size * 0.5
	
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "modulate:a", 1.0, duration).set_delay(delay)
	tw.tween_property(node, "scale", Vector2.ONE, duration) \
		.set_trans(TRANS_BOUNCE) \
		.set_ease(EASE_BOUNCE) \
		.set_delay(delay)
	return tw


static func animate_hover_enter(
	btn: Button,
	offset: float = HOVER_OFFSET,
	duration: float = HOVER_DURATION
) -> void:
	"""
	Applies hover enter animation (slide right).
	
	Usage in button.mouse_entered:
	  UIStyle.animate_hover_enter(button)
	"""
	if not is_instance_valid(btn): return
	if btn.has_meta("_htw"):
		var old = btn.get_meta("_htw")
		if old is Tween and old.is_valid(): old.kill()
	
	var tw := btn.create_tween()
	btn.set_meta("_htw", tw)
	tw.tween_property(btn, "position:x", offset, duration) \
		.set_trans(TRANS_STANDARD) \
		.set_ease(EASE_STANDARD)


static func animate_hover_exit(
	btn: Button,
	duration: float = HOVER_RETURN_DURATION
) -> void:
	"""
	Applies hover exit animation (slide back).
	
	Usage in button.mouse_exited:
	  UIStyle.animate_hover_exit(button)
	"""
	if not is_instance_valid(btn): return
	if btn.has_meta("_htw"):
		var old = btn.get_meta("_htw")
		if old is Tween and old.is_valid(): old.kill()
	
	var tw := btn.create_tween()
	btn.set_meta("_htw", tw)
	tw.tween_property(btn, "position:x", 0.0, duration) \
		.set_trans(TRANS_STANDARD) \
		.set_ease(EASE_STANDARD)


# ── Font Helpers ──────────────────────────────────────────────────────────────

static func apply_font_to_label(
	label: Label,
	font: Font,
	size: int,
	color: Color
) -> void:
	"""Applies font settings to a Label."""
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


static func apply_font_to_button(
	btn: Button,
	font: Font,
	size: int,
	color: Color
) -> void:
	"""Applies font settings to a Button."""
	if font:
		btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", size)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, color)


# ── Color Helpers ─────────────────────────────────────────────────────────────

static func get_accent_color(dark: bool) -> Color:
	"""Returns the primary accent color for the current theme."""
	return Color(0.30, 0.55, 1.00) if dark else Color(0.15, 0.35, 0.85)


static func get_gold_color(dark: bool) -> Color:
	"""Returns gold color for victory/special states."""
	return Color(1.00, 0.82, 0.25) if dark else Color(0.85, 0.62, 0.05)


static func get_wikipedia_blue() -> Color:
	"""Returns Wikipedia blue for primary actions."""
	return Color(0.024, 0.271, 0.678)


static func create_hover_tint(base: Color, dark: bool, intensity: float = 0.07) -> Color:
	"""Creates a hover tint color."""
	if dark:
		return Color(1, 1, 1, intensity)
	else:
		return Color(base, intensity)
