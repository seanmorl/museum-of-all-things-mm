extends Node
## Autoload: ThemeManager

signal dark_mode_changed(enabled: bool)
signal reading_font_changed(font: Font)

var is_dark_mode: bool = false
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


func _save_preference(enabled: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "dark_mode", enabled)
	cfg.save("user://ui_settings.cfg")
