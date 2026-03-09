extends Node
## Autoload: ThemeManager

signal dark_mode_changed(enabled: bool)
signal reading_font_changed(font: Font)
signal disco_mode_changed(enabled: bool)

var is_dark_mode: bool = false
var disco_mode: bool = false
var current_font_index: int = 0

var bg_color:      Color = Color(1.0,   1.0,   1.0,  0.95)
var border_color:  Color = Color(0.635, 0.663, 0.694, 1.0)
var text_color:    Color = Color(0.0,   0.0,   0.0,  1.0)
var subtext_color: Color = Color(0.4,   0.4,   0.4,  1.0)

const _LIGHT := {
	"bg":      Color(1.0,   1.0,   1.0,  0.95),
	"border":  Color(0.635, 0.663, 0.694, 1.0),
	"text":    Color(0.0,   0.0,   0.0,  1.0),
	"subtext": Color(0.4,   0.4,   0.4,  1.0),
}
const _DARK := {
	"bg":      Color(0.13,  0.13,  0.15, 0.97),
	"border":  Color(0.32,  0.32,  0.37, 1.0),
	"text":    Color(0.92,  0.92,  0.92, 1.0),
	"subtext": Color(0.55,  0.55,  0.60, 1.0),
}

const FONT_PATHS := [
	"res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf",
	"res://assets/fonts/OpenDyslexic/OpenDyslexic-Regular.otf",
	"res://assets/fonts/AtkinsonHyperlegible/AtkinsonHyperlegible-Regular.ttf"
]

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://ui_settings.cfg") == OK:
		is_dark_mode = cfg.get_value("ui", "dark_mode", false)
	
	var acc = SettingsManager.get_settings("accessibility")
	if acc and acc.has("reading_font"):
		current_font_index = acc.reading_font
		
	_update_palette()


func toggle() -> void:
	set_dark_mode(not is_dark_mode)


func set_dark_mode(enabled: bool) -> void:
	if is_dark_mode == enabled:
		return
	is_dark_mode = enabled
	_update_palette()
	_save_preference(is_dark_mode)
	dark_mode_changed.emit(enabled)


func get_reading_font() -> Font:
	var path := FONT_PATHS[0]
	if current_font_index >= 0 and current_font_index < FONT_PATHS.size():
		path = FONT_PATHS[current_font_index]
	return load(path) as Font


func set_reading_font(index: int) -> void:
	current_font_index = index
	reading_font_changed.emit(get_reading_font())


func set_disco_mode(enabled: bool) -> void:
	disco_mode = enabled
	disco_mode_changed.emit(enabled)


func _update_palette() -> void:
	var p := _DARK if is_dark_mode else _LIGHT
	bg_color      = p["bg"]
	border_color  = p["border"]
	text_color    = p["text"]
	subtext_color = p["subtext"]


func update_panel_style(style: StyleBoxFlat) -> void:
	if style:
		style.bg_color     = bg_color
		style.border_color = border_color


func style_option_button(btn: OptionButton) -> void:
	## Applies consistent dark-mode-aware styling to an OptionButton and its popup.
	if not btn:
		return
	
	var normal := StyleBoxFlat.new()
	normal.bg_color         = bg_color
	normal.border_color     = border_color
	for s in ["left","right","top","bottom"]:
		normal.set("border_width_" + s, 1)
	for c in ["top_left","top_right","bottom_left","bottom_right"]:
		normal.set("corner_radius_" + c, 5)
	normal.content_margin_left   = 10
	normal.content_margin_right  = 28
	normal.content_margin_top    = 5
	normal.content_margin_bottom = 5

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color     = Color(0.92, 0.93, 0.98, 1.0) if not is_dark_mode else Color(0.22, 0.23, 0.28, 1.0)
	hover.border_color = Color(0.50, 0.55, 0.85, 1.0)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color     = Color(0.88, 0.90, 0.97, 1.0) if not is_dark_mode else Color(0.18, 0.20, 0.27, 1.0)
	pressed.border_color = Color(0.40, 0.45, 0.80, 1.0)

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.40, 0.45, 0.80, 1.0)
	for s in ["left","right","top","bottom"]:
		focus.set("border_width_" + s, 2)

	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus",   focus)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", text_color)
	btn.add_theme_color_override("font_pressed_color", text_color)
	btn.add_theme_color_override("font_focus_color", text_color)
	btn.add_theme_font_size_override("font_size", 13)

	var popup := btn.get_popup()
	if popup:
		update_popup_style(popup)


func update_popup_style(popup: PopupMenu) -> void:
	## Styles a PopupMenu (dropdown contents) to match dark mode.
	if not popup:
		return
		
	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color     = bg_color
	popup_style.border_color = border_color
	for s in ["left","right","top","bottom"]:
		popup_style.set("border_width_" + s, 1)
	for c in ["top_left","top_right","bottom_left","bottom_right"]:
		popup_style.set("corner_radius_" + c, 5)
	popup_style.shadow_color  = Color(0, 0, 0, 0.25 if is_dark_mode else 0.12)
	popup_style.shadow_size   = 8
	popup_style.shadow_offset = Vector2(0, 3)
	
	popup.add_theme_stylebox_override("panel", popup_style)
	popup.add_theme_color_override("font_color", text_color)
	popup.add_theme_color_override("font_hover_color", bg_color) # Invert on hover for contrast
	popup.add_theme_color_override("font_separator_color", subtext_color)
	popup.add_theme_font_size_override("font_size", 13)
	popup.add_theme_font_size_override("title_font_size", 14)


func _save_preference(enabled: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "dark_mode", enabled)
	cfg.save("user://ui_settings.cfg")
