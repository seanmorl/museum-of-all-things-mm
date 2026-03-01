extends Node3D

# =============================================
# ADD YOUR FRIENDS HERE — one entry per line
# Format: ["Display Name", "url or handle"]
# =============================================
const LINKS: Array = [
	["Morl", "twitch.tv/SeanMorl"],
	["Harry",  "Twitch.tv/HarryHardy"],
	["AGoodPete","Twitch.tv/AGoodPete"],
]
# =============================================

const FONT_PATH = "res://assets/fonts/CormorantGaramond/CormorantGaramond-SemiBold.ttf"


func _ready() -> void:
	var font: Font = load(FONT_PATH)
	_build(font)


func _build(font: Font) -> void:
	for child in get_children():
		if child.name.begins_with("Link_"):
			child.queue_free()

	for i in LINKS.size():
		var entry: Array = LINKS[i]
		var name_lbl := _make_label("%-14s  %s" % [entry[0], entry[1]], font)
		name_lbl.name = "Link_%d" % i
		name_lbl.position = Vector3(0, 0.28 - i * 0.22, 0.05)
		add_child(name_lbl)


func _make_label(text: String, font: Font) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.pixel_size = 0.004
	lbl.font_size = 36
	lbl.font = font
	lbl.modulate = Color(0.1, 0.1, 0.1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.outline_size = 0
	lbl.no_depth_test = true
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	return lbl
