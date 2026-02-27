extends Control

@onready var target_label: Label = $MarginContainer/VBox/TargetLabel
@onready var timer_label: Label = $MarginContainer/VBox/TimerLabel

func _ready() -> void:
	visible = false
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_ended.connect(_on_race_ended)
	RaceManager.race_cancelled.connect(_on_race_cancelled)
	RaceManager.race_timer_updated.connect(_on_timer_updated)

func _on_race_started(target_article: String) -> void:
	target_label.text = "Target: " + target_article
	timer_label.text = "00:00"
	visible = true

func _on_timer_updated(_elapsed_seconds: float) -> void:
	timer_label.text = RaceManager.get_elapsed_time_string()

func _on_race_ended(_winner_peer_id: int, winner_name: String) -> void:
	timer_label.text = RaceManager.get_elapsed_time_string()
	target_label.text = winner_name + " wins!"
	var tween: Tween = create_tween()
	tween.tween_interval(4.0)
	tween.tween_callback(func() -> void: visible = false)

func _on_race_cancelled() -> void:
	visible = false
