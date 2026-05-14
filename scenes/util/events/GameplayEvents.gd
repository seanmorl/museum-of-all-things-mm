extends Node

signal return_to_lobby
signal language_changed(language: String)
signal race_started(target_article: String)
signal race_ended(winner_peer_id: int, winner_name: String)
signal mount_requested(target: Node)
signal dismount_requested()
signal steal_painting_requested(exhibit_title: String, image_title: String, image_url: String, image_size: Vector2, is_audio: bool)
signal place_painting_requested(exhibit_title: String, image_title: String, image_url: String, wall_position: Vector3, wall_normal: Vector3, image_size: Vector2, is_audio: bool)
signal eat_painting_requested(exhibit_title: String, image_title: String)
signal eat_anim_started()
signal eat_anim_cancelled()
signal local_reaction(reaction_index: int, target: Vector3)
signal error_message_requested(message: String)

func emit_return_to_lobby() -> void:
	return_to_lobby.emit()

func emit_language_changed(language: String) -> void:
	language_changed.emit(language)

func emit_race_started(target_article: String) -> void:
	race_started.emit(target_article)

func emit_race_ended(winner_peer_id: int, winner_name: String) -> void:
	race_ended.emit(winner_peer_id, winner_name)

func emit_mount_requested(target: Node) -> void:
	mount_requested.emit(target)

func emit_dismount_requested() -> void:
	dismount_requested.emit()

func emit_steal_painting_requested(exhibit_title: String, image_title: String, image_url: String, image_size: Vector2, is_audio: bool = false) -> void:
	steal_painting_requested.emit(exhibit_title, image_title, image_url, image_size, is_audio)

func emit_place_painting_requested(exhibit_title: String, image_title: String, image_url: String, wall_position: Vector3, wall_normal: Vector3, image_size: Vector2, is_audio: bool = false) -> void:
	place_painting_requested.emit(exhibit_title, image_title, image_url, wall_position, wall_normal, image_size, is_audio)

func emit_eat_painting_requested(exhibit_title: String, image_title: String) -> void:
	eat_painting_requested.emit(exhibit_title, image_title)

func emit_eat_anim_started() -> void:
	eat_anim_started.emit()

func emit_eat_anim_cancelled() -> void:
	eat_anim_cancelled.emit()

func emit_local_reaction(reaction_index: int, target: Vector3) -> void:
	local_reaction.emit(reaction_index, target)

func emit_error_message_requested(message: String) -> void:
	error_message_requested.emit(message)
