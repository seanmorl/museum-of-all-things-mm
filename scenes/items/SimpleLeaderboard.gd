extends Node3D

const FONT_PATH = "res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf"
var _font: Font
var _results: Array = []


func _ready() -> void:
	_font = load(FONT_PATH)
	RaceManager.race_ended.connect(_on_race_ended)


func _on_race_ended(_peer_id: int, winner_name: String) -> void:
	_results.append({
		"name": winner_name,
		"time": RaceManager.get_elapsed_time_string()
	})
	if _results.size() > 8:
		_results = _results.slice(0, 8)
	_refresh()


func _refresh() -> void:
	for child in get_children():
		if child.name.begins_with("Entry"):
			child.queue_free()

	if _results.is_empty():
		_add("No races yet", 0, Color(0.55, 0.55, 0.55))
		return

	for i in _results.size():
		var r: Dictionary = _results[i]
		var col := Color(0.05, 0.05, 0.05) if i % 2 == 0 else Color(0.3, 0.3, 0.3)
		_add("#%d  %s  —  %s" % [i + 1, r["name"], r["time"]], i, col)


func _add(text: String, index: int, color: Color) -> void:
	var lbl := Label3D.new()
	lbl.name = "Entry%d" % index
	lbl.text = text
	lbl.position = Vector3(0, 0.7 - index * 0.32, 0.05)
	lbl.pixel_size = 0.005
	lbl.font_size = 64
	if _font:
		lbl.font = _font
	lbl.modulate = color
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.outline_size = 0
	lbl.no_depth_test = true
	add_child(lbl)
