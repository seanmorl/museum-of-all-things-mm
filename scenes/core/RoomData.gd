extends Resource
class_name RoomData
## Serializable room data for multiplayer room synchronization.
## Server generates once, broadcasts to all clients for identical rooms.

@export var title: String = ""
@export var seed: int = 0
@export var wikipedia_data: Dictionary = {}
@export var backlinks: Array = []
@export var layout_data: Dictionary = {}  # Wall positions, item placements
@export var mood: int = 0  # ExhibitMood.Mood enum
@export var exhibit_height: int = 0

# --- Creation ---

static func create(title: String, seed_value: int) -> RoomData:
	var data = RoomData.new()
	data.title = title
	data.seed = seed_value
	return data

# --- Serialization ---

func to_dict() -> Dictionary:
	return {
		"title": title,
		"seed": seed,
		"wikipedia_data": wikipedia_data,
		"backlinks": backlinks,
		"layout_data": layout_data,
		"mood": mood,
		"exhibit_height": exhibit_height
	}

static func from_dict(data: Dictionary) -> RoomData:
	var room = RoomData.new()
	room.title = data.get("title", "")
	room.seed = data.get("seed", 0)
	room.wikipedia_data = data.get("wikipedia_data", {})
	room.backlinks = data.get("backlinks", [])
	room.layout_data = data.get("layout_data", {})
	room.mood = data.get("mood", 0)
	room.exhibit_height = data.get("exhibit_height", 0)
	return room

func to_var() -> Variant:
	return to_dict()

static func from_var(variant: Variant) -> RoomData:
	if variant is Dictionary:
		return from_dict(variant)
	return RoomData.new()

# --- Helpers ---

func get_wikipedia_title() -> String:
	if wikipedia_data.has("title"):
		return wikipedia_data.title
	return title

func has_data() -> bool:
	return title != "" and not wikipedia_data.is_empty()
