extends Control

@onready var timer_label: Label = $MarginContainer/VBox/TimerLabel
@onready var target_label: Label = $MarginContainer/VBox/TargetLabel

func _ready() -> void:
	visible = false
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_ended.connect(_on_race_ended)
	RaceManager.race_cancelled.connect(_on_race_cancelled)
	RaceManager.race_timer_updated.connect(_on_race_timer_updated)

func _on_race_started(target_article: String, _start_article: String) -> void:
	timer_label.text = "00:00"
	target_label.text = "Find: " + target_article
	visible = true

func _on_race_timer_updated(elapsed_seconds: float) -> void:
	var secs: int = int(elapsed_seconds)
	timer_label.text = "%02d:%02d" % [secs / 60, secs % 60]

func _on_race_ended(_winner_peer_id: int, winner_name: String) -> void:
	target_label.text = winner_name + " wins! (" + RaceManager.get_elapsed_time_string() + ")"
	await get_tree().create_timer(4.0).timeout
	visible = false

func _on_race_cancelled() -> void:
	visible = false
