extends Node
class_name MoATStyle
## MoATStyle — Single source of truth for all visual tokens.
## AutoLoad as "MoATStyle" before any menu scripts.
##
## Design principles:
##   • WCAG AA contrast (4.5:1) for all body text, WCAG AAA (7:1) for critical info
##   • 48 px minimum touch targets (WCAG 2.5.5)
##   • 2 px focus rings on every interactive element
##   • reduce_motion() checked before every animation
##   • All colours adapt to ThemeManager light/dark

# ── Sizing constants ──────────────────────────────────────────────────────────
const BTN_H       := 48
const BTN_H_LG    := 56
const CORNER      := 8       ## Refined from 4 to 8
const CORNER_CARD := 14      ## Refined from 6 to 14
const STRIPE_W    := 3
const RAINBOW_H   := 3       ## Refined from 4 to 3
const CARD_PAD    := 24
const CARD_PAD_SM := 16      ## Refined from 14 to 16

# ── Accent palette ────────────────────────────────────────────────────────────
const C_BLUE   := Color(0.231, 0.490, 0.847)   ## #3B7DD8
const C_ART    := Color(0.620, 0.227, 0.071)   ## Refined
const C_CINEMA := Color(0.784, 0.482, 0.078)   ## #C87B14
const C_GEO    := Color(0.118, 0.478, 0.227)   ## #1E7A3A
const C_CULT   := Color(0.643, 0.082, 0.376)   ## #A41560
const C_PURPLE := Color(0.420, 0.122, 0.627)   ## #6B1FA0
const C_DAILY  := Color(0.106, 0.545, 0.831)   ## #1B8BD4

const ACCENT_BLUE   := C_BLUE
const ACCENT_RED    := C_CINEMA
const ACCENT_YELLOW := C_ART

const RAINBOW: Array[Color] = [C_BLUE, C_ART, C_CINEMA, C_GEO, C_CULT, C_PURPLE]


# ── Semantic colours ──────────────────────────────────────────────────────────

## Page / layer background
static func bg(dark: bool) -> Color:
	return Color(0.075, 0.078, 0.094, 0.97) if dark \
	       else Color(0.980, 0.976, 0.965, 0.98)

## Elevated card surface
static func surface(dark: bool) -> Color:
	return Color(0.110, 0.115, 0.135, 1.0) if dark \
	       else Color(1.000, 1.000, 1.000, 1.0)

## Subtle 1 px border
static func border(dark: bool) -> Color:
	return Color(1, 1, 1, 0.10) if dark else Color(0, 0, 0, 0.11)

## Primary text — WCAG AA on bg()
static func txt(dark: bool) -> Color:
	return Color(0.930, 0.930, 0.940, 1.0) if dark else Color(0.075, 0.075, 0.100, 1.0)

## Secondary / caption — WCAG AA on bg()
static func sub(dark: bool) -> Color:
	return Color(0.620, 0.625, 0.650, 1.0) if dark else Color(0.400, 0.400, 0.430, 1.0)

## Disabled — clearly muted but readable
static func dim(dark: bool) -> Color:
	return Color(0.42, 0.42, 0.46, 1.0) if dark else Color(0.58, 0.58, 0.62, 1.0)

## Primary blue accent
static func accent(dark: bool) -> Color:
	return Color(0.420, 0.639, 0.910, 1.0) if dark else C_BLUE

## High-contrast focus ring (always maximum contrast)
static func ring(dark: bool) -> Color:
	return Color(0.420, 0.639, 0.910, 1.0) if dark else C_BLUE

## Success / green
static func ok(dark: bool) -> Color:
	return Color(0.25, 0.72, 0.42, 1.0) if dark \
	       else Color(0.184, 0.620, 0.353, 1.0)

## Danger / red
static func err(dark: bool) -> Color:
	return Color(0.92, 0.30, 0.35, 1.0) if dark \
	       else Color(0.863, 0.208, 0.271, 1.0)

## Daily challenge accent
static func daily(dark: bool) -> Color:
	return C_DAILY if dark else Color(0.08, 0.50, 0.82, 1.0)


# ── StyleBox factories ────────────────────────────────────────────────────────

static func card(dark: bool, pad: int = CARD_PAD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = surface(dark)
	s.border_color = border(dark)
	s.set_border_width_all(1)
	s.set_corner_radius_all(CORNER_CARD)
	s.shadow_color  = Color(0, 0, 0, 0.26 if dark else 0.07)
	s.shadow_size   = 16; s.shadow_offset = Vector2(0, 4)
	s.set_content_margin_all(pad)
	return s

static func card_bare(dark: bool) -> StyleBoxFlat:
	var s := card(dark, 0)
	s.shadow_size = 20; s.shadow_color = Color(0, 0, 0, 0.30 if dark else 0.08)
	return s

## Adds a glassmorphic background to a PanelContainer.
## Requires a BackBufferCopy node if using backdrop blur.
static func apply_glass(panel: PanelContainer, dark: bool) -> void:
	panel.add_theme_stylebox_override("panel", card_bare(dark))
	
	# Create backdrop blur rect
	var blur := ColorRect.new()
	blur.name = "GlassBlur"
	blur.show_behind_parent = true
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/GlassPanel.gdshader")
	var tint := Color(0,0,0,0.4) if dark else Color(1,1,1,0.4)
	mat.set_shader_parameter("tint_color", tint)
	mat.set_shader_parameter("blur_amount", 3.0)
	blur.material = mat
	
	panel.add_child(blur)
	panel.move_child(blur, 0)


# ── Button state tables ───────────────────────────────────────────────────────
## Each returns a Dictionary with keys: normal, hover, pressed, focus, disabled, tc, dtc

static func btn_primary(dark: bool) -> Dictionary:
	var fill := Color(0.92, 0.92, 0.94) if dark else Color(0.06, 0.06, 0.10)
	var tc   := Color(0.06, 0.06, 0.10) if dark else Color(0.96, 0.96, 0.98)
	return {
		"normal":   _b(fill,                 Color(0,0,0,0), CORNER),
		"hover":    _b(fill.lightened(0.08),  Color(0,0,0,0), CORNER),
		"pressed":  _b(fill.darkened(0.08),   Color(0,0,0,0), CORNER),
		"focus":    _b(fill, ring(dark),       CORNER, 2),
		"disabled": _b(Color(fill,0.35),      Color(0,0,0,0), CORNER),
		"tc": tc, "dtc": dim(dark),
	}

static func btn_secondary(dark: bool) -> Dictionary:
	var brd := border(dark)
	var hbg := Color(accent(dark), 0.10)
	var tc  := txt(dark)
	return {
		"normal":   _b(Color(0,0,0,0), brd,          CORNER, 1),
		"hover":    _b(hbg, accent(dark),             CORNER, 1),
		"pressed":  _b(Color(accent(dark),0.18), accent(dark), CORNER, 1),
		"focus":    _b(Color(0,0,0,0), ring(dark),    CORNER, 2),
		"disabled": _b(Color(0,0,0,0), Color(brd,0.4),CORNER, 1),
		"tc": tc, "dtc": dim(dark),
	}

static func btn_flat(dark: bool) -> Dictionary:
	var hbg := Color(1,1,1,0.06) if dark else Color(0,0,0,0.05)
	var pbg := Color(1,1,1,0.10) if dark else Color(0,0,0,0.08)
	var tc  := txt(dark)
	return {
		"normal":   _bare(),
		"hover":    _b(hbg, Color(0,0,0,0), CORNER),
		"pressed":  _b(pbg, Color(0,0,0,0), CORNER),
		"focus":    _b(Color(0,0,0,0), ring(dark), CORNER, 2),
		"disabled": _bare(),
		"tc": tc, "dtc": dim(dark),
	}

static func btn_danger(dark: bool) -> Dictionary:
	var fill := err(dark)
	var tc   := Color(1,1,1,0.96)
	return {
		"normal":   _b(fill,               Color(0,0,0,0), CORNER),
		"hover":    _b(fill.lightened(0.1), Color(0,0,0,0), CORNER),
		"pressed":  _b(fill.darkened(0.1),  Color(0,0,0,0), CORNER),
		"focus":    _b(fill, ring(dark),    CORNER, 2),
		"disabled": _b(Color(fill,0.35),    Color(0,0,0,0), CORNER),
		"tc": tc, "dtc": dim(dark),
	}

static func btn_daily(dark: bool) -> Dictionary:
	var acc  := daily(dark)
	var fill := Color(acc, 0.14)
	var tc   := acc
	return {
		"normal":   _b(fill,              acc, CORNER, 1),
		"hover":    _b(Color(acc,0.24),   acc, CORNER, 1),
		"pressed":  _b(Color(acc,0.32),   acc, CORNER, 1),
		"focus":    _b(fill, ring(dark),  CORNER, 2),
		"disabled": _b(Color(fill,0.35), Color(acc,0.3), CORNER, 1),
		"tc": tc, "dtc": dim(dark),
	}

## Apply a button state table to a Button node.
static func apply_btn(btn: Button, style: Dictionary,
		font: Font = null, size: int = 16) -> void:
	for k in ["normal","hover","pressed","focus","disabled"]:
		btn.add_theme_stylebox_override(k, style[k])
	var tc: Color = style["tc"]
	btn.add_theme_color_override("font_color",         tc)
	btn.add_theme_color_override("font_hover_color",   tc)
	btn.add_theme_color_override("font_pressed_color", tc)
	btn.add_theme_color_override("font_focus_color",   tc)
	btn.add_theme_color_override("font_disabled_color", style["dtc"])
	btn.add_theme_font_size_override("font_size", size)
	if font: btn.add_theme_font_override("font", font)

## Apply theme colours to a Label.
static func apply_lbl(lbl: Label, dark: bool,
		font: Font = null, size: int = 15, role: String = "") -> void:
	var c: Color
	match role:
		"sub":     c = sub(dark)
		"accent":  c = accent(dark)
		"ok":      c = ok(dark)
		"err":     c = err(dark)
		"daily":   c = daily(dark)
		_:         c = txt(dark)
	lbl.add_theme_color_override("font_color", c)
	lbl.add_theme_font_size_override("font_size", size)
	if font: lbl.add_theme_font_override("font", font)

## Apply theme colours to a LineEdit.
static func apply_edit(edit: LineEdit, dark: bool, font: Font = null) -> void:
	if font: edit.add_theme_font_override("font", font)
	edit.add_theme_font_size_override("font_size", 15)
	edit.add_theme_color_override("font_color", txt(dark))
	edit.add_theme_color_override("font_placeholder_color", sub(dark))
	edit.add_theme_color_override("caret_color", accent(dark))
	edit.add_theme_color_override("selection_color", Color(accent(dark), 0.28))
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(1,1,1,0.05) if dark else Color(0,0,0,0.04)
	sn.border_color = border(dark); sn.set_border_width_all(1)
	sn.set_corner_radius_all(CORNER)
	sn.content_margin_left = 12; sn.content_margin_right  = 12
	sn.content_margin_top  =  9; sn.content_margin_bottom =  9
	edit.add_theme_stylebox_override("normal", sn)
	var sf := sn.duplicate() as StyleBoxFlat
	sf.border_color = ring(dark); sf.set_border_width_all(2)
	edit.add_theme_stylebox_override("focus", sf)


# ── Structural node builders ──────────────────────────────────────────────────

## 1 px divider line
static func divider(dark: bool) -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.color = border(dark)
	return d

## Rainbow top bar as HBoxContainer (insert into outer VBox first)
static func rainbow_bar(height: int = RAINBOW_H) -> HBoxContainer:
	var rb := HBoxContainer.new()
	rb.name = "RainbowBar"
	rb.custom_minimum_size = Vector2(0, height)
	rb.add_theme_constant_override("separation", 0)
	rb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in RAINBOW:
		var seg := ColorRect.new(); seg.color = c
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.custom_minimum_size = Vector2(0, height)
		rb.add_child(seg)
	return rb

## Left accent stripe ColorRect — add as first child of an HBoxContainer
static func stripe(color: Color = C_BLUE) -> ColorRect:
	var s := ColorRect.new(); s.name = "Stripe"
	s.color = color
	s.custom_minimum_size = Vector2(STRIPE_W, 0)
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

## 10 px ALL-CAPS eyebrow label
static func eyebrow(text: String, dark: bool, font: Font = null) -> Label:
	var l := Label.new(); l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", sub(dark))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font: l.add_theme_font_override("font", font)
	return l

## Build a panel shell: rainbow bar + left stripe + inner content VBox.
## Applies card_bare stylebox to the panel.
## Returns the inner content VBoxContainer where callers add their children.
static func panel_shell(panel: PanelContainer, dark: bool,
		stripe_col: Color = C_BLUE) -> VBoxContainer:
	panel.add_theme_stylebox_override("panel", card_bare(dark))

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	panel.add_child(outer)

	outer.add_child(rainbow_bar())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(row)

	row.add_child(stripe(stripe_col))

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   CARD_PAD)
	mc.add_theme_constant_override("margin_right",  CARD_PAD)
	mc.add_theme_constant_override("margin_top",    CARD_PAD_SM)
	mc.add_theme_constant_override("margin_bottom", CARD_PAD_SM)
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	row.add_child(mc)

	var content := VBoxContainer.new()
	content.name = "PanelContent"
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	mc.add_child(content)

	return content


# ── Motion helper (Static) ───────────────────────────────────────────────────

static func reduce_motion() -> bool:
	if not Engine.has_singleton("SettingsManager"): return false
	var acc = SettingsManager.get_settings("accessibility")
	return acc is Dictionary and acc.get("reduce_motion", false)


# ── Private ───────────────────────────────────────────────────────────────────

static func _b(bg_col: Color, brd_col: Color,
		corner: int, bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg_col; s.border_color = brd_col
	s.set_border_width_all(bw if brd_col.a > 0.01 else 0)
	s.set_corner_radius_all(corner)
	s.content_margin_left   = 24; s.content_margin_right  = 24
	s.content_margin_top    = 11; s.content_margin_bottom = 11
	return s

static func _bare() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0,0,0,0); s.set_border_width_all(0)
	s.content_margin_left   = 24; s.content_margin_right  = 24
	s.content_margin_top    = 11; s.content_margin_bottom = 11
	return s
