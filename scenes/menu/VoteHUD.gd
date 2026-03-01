extends Control
## In-world HUD overlay for voting on the race target article.

@onready var _countdown_label: Label = $MarginContainer/CenterContainer/Panel/Content/CountdownLabel
@onready var _candidates_container: VBoxContainer = $MarginContainer/CenterContainer/Panel/Content/CandidatesContainer
@onready var _status_label: Label = $MarginContainer/CenterContainer/Panel/Content/StatusLabel

var _my_vote: int = -1
var _candidate_buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	RaceManager.vote_started.connect(_on_vote_started)
	RaceManager.vote_ended.connect(_on_vote_ended)
	RaceManager.race_started.connect(_on_race_started)
	if RaceManager.is_vote_active():
		_on_vote_started(RaceManager.get_vote_candidates())


func _process(_delta: float) -> void:
	if not visible or not RaceManager.is_vote_active():
		return
	var remaining: float = RaceManager.get_vote_time_remaining()
	_countdown_label.text = "Time remaining: %d" % ceili(remaining)


func _on_vote_started(candidates: Array) -> void:
	_my_vote = -1
	_status_label.text = "Vote for the race target!"

	for child in _candidates_container.get_children():
		child.queue_free()
	_candidate_buttons.clear()

	for i in candidates.size():
		var btn: Button = Button.new()
		btn.text = candidates[i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_candidate_pressed.bind(i))
		_candidates_container.add_child(btn)
		_candidate_buttons.append(btn)

	visible = true


func _on_candidate_pressed(index: int) -> void:
	_my_vote = index
	RaceManager.cast_vote(index)
	for i in _candidate_buttons.size():
		_candidate_buttons[i].disabled = (i != index)
	_status_label.text = "Voted for: " + RaceManager.get_vote_candidates()[index]


func _on_close_pressed() -> void:
	visible = false


func _on_vote_ended(winner: String) -> void:
	_countdown_label.text = "Race starting!"
	_status_label.text = "Target: " + winner
	for btn in _candidate_buttons:
		btn.disabled = true


func _on_race_started(_target: String, _start: String) -> void:
	await get_tree().create_timer(1.5).timeout
	visible = false
