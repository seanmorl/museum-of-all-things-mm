extends RefCounted
class_name UIUtils
## Shared UI node construction helpers to reduce duplication across menu scripts.
## All methods are static — call directly: UIUtils.full_rect(my_node)

static func full_rect(node: Control, preset: int = Control.PRESET_FULL_RECT) -> void:
	node.set_anchors_and_offsets_preset(preset)


static func backdrop(
	color: Color = Color.BLACK,
	alpha: float = 0.0,
	mouse_filter: int = Control.MOUSE_FILTER_STOP,
	parent: Node = null
) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(color.r, color.g, color.b, alpha)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = mouse_filter
	if parent:
		parent.add_child(rect)
	return rect


static func modal_background(parent: Node, dim_alpha: float = 0.65) -> Dictionary:
	var dim := backdrop(Color.BLACK, dim_alpha, Control.MOUSE_FILTER_IGNORE, parent)
	var margin := MarginContainer.new()
	margin.name = "ModalMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	parent.add_child(margin)
	var center := CenterContainer.new()
	center.name = "ModalCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(center)
	return {"dim": dim, "margin": margin, "center": center}


static func panel_in_center(
	parent: Node,
	width: float = 350,
	height: float = 400,
	theme_res: Resource = null
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ModalPanel"
	if theme_res:
		panel.theme = theme_res
	panel.custom_minimum_size = Vector2(width, height)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("margin_left", 20)
	panel.add_theme_constant_override("margin_top", 16)
	panel.add_theme_constant_override("margin_right", 20)
	panel.add_theme_constant_override("margin_bottom", 16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


static func scroll_in_panel(
	parent: Node,
	min_h: float = 300,
	h_separation: int = 8,
	right_margin: int = 8
) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "ModalScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(280, min_h)
	scroll.add_theme_constant_override("margin_right", right_margin)
	parent.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "ModalScrollContent"
	content.add_theme_constant_override("separation", h_separation)
	scroll.add_child(content)
	return scroll


static func dim_background(parent: Node, alpha: float = 0.65) -> ColorRect:
	return backdrop(Color.BLACK, alpha, Control.MOUSE_FILTER_IGNORE, parent)


static func styled_button(
	text: String,
	callback: Callable,
	theme_res: Resource = null,
	parent: Node = null,
	dark: bool = true
) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(120, 36)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if theme_res:
		btn.theme = theme_res
	var states := UIStyle.create_button_states(dark, false, true)
	btn.add_theme_stylebox_override("normal", states.get("normal"))
	btn.add_theme_stylebox_override("hover", states.get("hover"))
	btn.add_theme_stylebox_override("pressed", states.get("pressed"))
	btn.add_theme_stylebox_override("disabled", states.get("disabled"))
	btn.add_theme_color_override("font_color", Color.WHITE if dark else Color.BLACK)
	if callback.is_valid():
		btn.pressed.connect(callback)
	if parent:
		parent.add_child(btn)
	return btn


static func vbox(parent: Node, separation: int = 8) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", separation)
	parent.add_child(vbox)
	return vbox


static func hbox(parent: Node, separation: int = 8) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", separation)
	parent.add_child(hbox)
	return hbox


static func label(
	text: String,
	parent: Node,
	font_size: int = 16,
	color: Color = Color.WHITE
) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)
	return lbl
