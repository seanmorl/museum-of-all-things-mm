extends Node
## Persists ghost silhouettes and guestbook messages per exhibit.

signal ghost_placed(exhibit_title: String, pos: Vector3)
signal guestbook_message_added(exhibit_title: String, message: String)

const TRACE_FILE: String = "user://visitor_traces.json"
const MAX_GHOSTS_PER_EXHIBIT: int = 20
const MAX_MESSAGES_PER_EXHIBIT: int = 50

var _data: Dictionary = {}  # exhibit_title -> { ghosts: [], messages: [] }


func _ready() -> void:
	_load()


func _load() -> void:
	if not FileAccess.file_exists(TRACE_FILE):
		return
	var file: FileAccess = FileAccess.open(TRACE_FILE, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_data = parsed


func _save() -> void:
	var file: FileAccess = FileAccess.open(TRACE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_data))
		file.close()


func _ensure_exhibit(title: String) -> void:
	if not _data.has(title):
		_data[title] = {"ghosts": [], "messages": []}


func add_ghost(exhibit_title: String, pos: Vector3, rot_y: float) -> void:
	_ensure_exhibit(exhibit_title)
	var ghosts: Array = _data[exhibit_title].ghosts
	ghosts.append({"x": pos.x, "y": pos.y, "z": pos.z, "rot_y": rot_y, "time": Time.get_unix_time_from_system()})
	while ghosts.size() > MAX_GHOSTS_PER_EXHIBIT:
		ghosts.pop_front()
	_save()
	ghost_placed.emit(exhibit_title, pos)


func get_ghosts(exhibit_title: String) -> Array:
	if _data.has(exhibit_title) and _data[exhibit_title].has("ghosts"):
		return _data[exhibit_title].ghosts
	return []


func add_guestbook_message(exhibit_title: String, player_name: String, message: String) -> void:
	_ensure_exhibit(exhibit_title)
	var messages: Array = _data[exhibit_title].messages
	messages.append({
		"name": player_name,
		"text": message.substr(0, 140),
		"time": Time.get_unix_time_from_system(),
	})
	while messages.size() > MAX_MESSAGES_PER_EXHIBIT:
		messages.pop_front()
	_save()
	guestbook_message_added.emit(exhibit_title, message)


func get_messages(exhibit_title: String) -> Array:
	if _data.has(exhibit_title) and _data[exhibit_title].has("messages"):
		return _data[exhibit_title].messages
	return []


# =============================================================================
# PLACED PAINTINGS PERSISTENCE
# =============================================================================
# Placed paintings are stored per exhibit as a list of placement records.
# Each record: { image_title, image_url, image_size: {x,y},
#               wall_position: {x,y,z}, wall_normal: {x,y,z} }

const MAX_PAINTINGS_PER_EXHIBIT: int = 20


func save_placed_painting(exhibit_title: String, image_title: String, image_url: String,
		image_size: Vector2, wall_position: Vector3, wall_normal: Vector3) -> void:
	_ensure_exhibit(exhibit_title)
	var paintings: Array = _get_paintings(exhibit_title)
	# Remove any prior placement of the same painting (replace with new spot)
	for i in range(paintings.size() - 1, -1, -1):
		if paintings[i].get("image_title", "") == image_title:
			paintings.remove_at(i)
	paintings.append({
		"image_title":  image_title,
		"image_url":    image_url,
		"image_size":   {"x": image_size.x, "y": image_size.y},
		"wall_position": {"x": wall_position.x, "y": wall_position.y, "z": wall_position.z},
		"wall_normal":  {"x": wall_normal.x,   "y": wall_normal.y,   "z": wall_normal.z},
	})
	while paintings.size() > MAX_PAINTINGS_PER_EXHIBIT:
		paintings.pop_front()
	_data[exhibit_title]["paintings"] = paintings
	_save()


func remove_placed_painting(exhibit_title: String, image_title: String) -> void:
	## Called when a painting is picked back up, so it's no longer placed.
	if not _data.has(exhibit_title):
		return
	var paintings: Array = _get_paintings(exhibit_title)
	for i in range(paintings.size() - 1, -1, -1):
		if paintings[i].get("image_title", "") == image_title:
			paintings.remove_at(i)
	_data[exhibit_title]["paintings"] = paintings
	_save()


func get_placed_paintings(exhibit_title: String) -> Array:
	return _get_paintings(exhibit_title)


func _get_paintings(exhibit_title: String) -> Array:
	if _data.has(exhibit_title) and _data[exhibit_title].has("paintings"):
		return _data[exhibit_title]["paintings"]
	return []
