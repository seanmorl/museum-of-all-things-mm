extends Node
## Autoload: ThemeManager

signal dark_mode_changed(enabled: bool)

var is_dark_mode: bool = false

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


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://ui_settings.cfg") == OK:
		is_dark_mode = cfg.get_value("ui", "dark_mode", false)
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
