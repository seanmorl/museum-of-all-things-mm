extends Node

const _settings_ns: String = "language"
var _locale: String = "en"

const LANGUAGES := [
	{"code": "en", "display_name": "English"},
	{"code": "pt", "display_name": "Português"},
	{"code": "fr", "display_name": "Français"},
	{"code": "es", "display_name": "Español"},
	{"code": "ja", "display_name": "日本語"},
	{"code": "de", "display_name": "Deutsch"},
	{"code": "bn", "display_name": "বাংলা"},
	{"code": "zh", "display_name": "中文"},
]

func _create_settings_obj() -> Dictionary:
	return {
		"locale": _locale
	}

func _ready() -> void:
	var loaded_settings = SettingsManager.get_settings(_settings_ns)
	if loaded_settings:
		set_locale(loaded_settings.locale)

func get_locale() -> String:
	return _locale

var current_language: String:
	get:
		return _locale

func set_locale(locale: String) -> void:
	_locale = locale
	TranslationServer.set_locale(locale)
	ExhibitFetcher.set_language(locale)
	SettingsEvents.language_changed.emit(locale)
	SettingsManager.save_settings(_settings_ns, _create_settings_obj())

func set_language(code: String) -> void:
	set_locale(code)

func get_available_languages() -> Array:
	return LANGUAGES
