extends Node
class_name SpectatorController
## Spectator mode: lets a finished/opted-in player float-follow other players.
## Hooks into the existing MultiplayerController network player tracking.
## The local player is paused and hidden; a free Camera3D takes over the viewport.
##
## Controls:
##   [E] / [Q] or [RB] / [LB]   — cycle to next / previous player
##   [Escape] / Pause            — exit spectator mode
##   Mouse                       — look around (captured)

signal spectator_entered
signal spectator_exited
signal target_changed(player_name: String)

const LERP_SPEED: float = 8.0        ## Camera follow smoothing
const OFFSET: Vector3 = Vector3(0, 1.8, 3.5)  ## Behind-and-above offset

var _main: Node = null
var _multiplayer_controller: MultiplayerController = null
var _local_player: Node = null

var _is_spectating: bool = false
var _cam: Camera3D = null
var _cam_pivot: Node3D = null        ## intermediate node for mouse-look
var _target_index: int = 0
var _targets: Array = []             ## list of valid NetworkPlayer nodes
var _yaw: float = 0.0
var _pitch: float = 0.0
var _mouse_sensitivity: float = 0.002

## HUD elements (built in code, no scene file needed)
var _hud_layer: CanvasLayer = null
var _hud_panel: PanelContainer = null
var _name_lbl: Label = null
var _hint_lbl: Label = null
var _font: Font = null
var _panel_style: StyleBoxFlat = null

func init(main: Node, multiplayer_controller: MultiplayerController) -> void:
	_main = main
	_multiplayer_controller = multiplayer_controller
	_build_hud()

# ── Enter / Exit ──────────────────────────────────────────────────────────────

func enter_spectator_mode(local_player: Node) -> void:
	if _is_spectating:
		return
	_local_player = local_player

	_targets = _get_valid_targets()
	if _targets.is_empty():
		return  # nobody to watch

	_is_spectating = true
	_target_index = 0

	# Hide and pause the local player
	if _local_player:
		_local_player.set_body_visible(false) if _local_player.has_method("set_body_visible") else null
		_local_player.pause() if _local_player.has_method("pause") else null

	# Build ghost camera
	_cam_pivot = Node3D.new()
	_cam_pivot.name = "SpectatorPivot"
	_main.add_child(_cam_pivot)

	_cam = Camera3D.new()
	_cam.name = "SpectatorCamera"
	_cam_pivot.add_child(_cam)
	_cam.make_current()

	# Snap to first target immediately
	_snap_to_target()

	# Show HUD
	_hud_layer.visible = true
	_update_hud_label()

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)

	spectator_entered.emit()

func exit_spectator_mode() -> void:
	if not _is_spectating:
		return
	_is_spectating = false

	# Restore camera to player
	if _local_player:
		var player_cam := _local_player.get_node_or_null("Pivot/Camera3D")
		if player_cam:
			player_cam.make_current()
		_local_player.set_body_visible(true) if _local_player.has_method("set_body_visible") else null
		_local_player.start() if _local_player.has_method("start") else null

	# Clean up ghost camera
	if _cam_pivot and is_instance_valid(_cam_pivot):
		_cam_pivot.queue_free()
	_cam = null
	_cam_pivot = null

	_hud_layer.visible = false

	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)

	spectator_exited.emit()

func is_spectating() -> bool:
	return _is_spectating

# ── Process / Input ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _is_spectating:
		return

	# Refresh target list (players may join/leave)
	_targets = _get_valid_targets()
	if _targets.is_empty():
		exit_spectator_mode()
		return
	_target_index = clamp(_target_index, 0, _targets.size() - 1)

	# Smoothly follow target
	var target_node: Node = _targets[_target_index]
	if not is_instance_valid(target_node):
		_cycle(1)
		return

	var target_pos: Vector3 = target_node.global_position

	# Position: behind + above target, rotated by our yaw
	var offset_rotated := Vector3(
		OFFSET.x * cos(_yaw) + OFFSET.z * sin(_yaw),
		OFFSET.y,
		-OFFSET.x * sin(_yaw) + OFFSET.z * cos(_yaw)
	)
	var desired_pos := target_pos + offset_rotated
	_cam_pivot.global_position = _cam_pivot.global_position.lerp(desired_pos, LERP_SPEED * delta)

	# Apply yaw + pitch to camera
	_cam_pivot.rotation.y = _yaw
	_cam.rotation.x = _pitch

func _unhandled_input(event: InputEvent) -> void:
	if not _is_spectating:
		return

	if event is InputEventMouseMotion:
		_yaw   -= event.relative.x * _mouse_sensitivity
		_pitch -= event.relative.y * _mouse_sensitivity
		_pitch  = clamp(_pitch, -1.2, 0.6)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not _is_spectating:
		return

	# Cycle next
	if event.is_action_pressed("ui_page_down") or \
	   (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_RIGHT_SHOULDER and event.pressed):
		_cycle(1)
		get_viewport().set_input_as_handled()

	# Cycle previous
	if event.is_action_pressed("ui_page_up") or \
	   (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_LEFT_SHOULDER and event.pressed):
		_cycle(-1)
		get_viewport().set_input_as_handled()

	# Exit
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		exit_spectator_mode()
		get_viewport().set_input_as_handled()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_valid_targets() -> Array:
	var result: Array = []
	if not _multiplayer_controller:
		return result
	var net_players := _multiplayer_controller.get_network_players()
	for pid: int in net_players:
		var np: Node = net_players[pid]
		if is_instance_valid(np) and np != _local_player:
			result.append(np)
	return result

func _cycle(direction: int) -> void:
	if _targets.is_empty():
		return
	_target_index = (_target_index + direction) % _targets.size()
	if _target_index < 0:
		_target_index += _targets.size()
	_snap_to_target()
	_update_hud_label()

func _snap_to_target() -> void:
	if _targets.is_empty() or not _cam_pivot:
		return
	var target_node: Node = _targets[_target_index]
	if is_instance_valid(target_node):
		_cam_pivot.global_position = target_node.global_position + OFFSET
		_yaw   = 0.0
		_pitch = -0.2

func _update_hud_label() -> void:
	if _targets.is_empty():
		_name_lbl.text = "No players to watch"
		return
	var target_node: Node = _targets[_target_index]
	if not is_instance_valid(target_node):
		return
	var pid: int = target_node.get_multiplayer_authority() if target_node.has_method("get_multiplayer_authority") else -1
	var name_str: String = NetworkManager.get_player_name(pid) if pid > 0 else "Unknown"
	_name_lbl.text = "👁 Watching: " + name_str
	_hint_lbl.text = "[ PageUp / PageDown ] Switch   [ Esc ] Exit"
	target_changed.emit(name_str)

# ── HUD ───────────────────────────────────────────────────────────────────────

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "SpectatorHUD"
	_hud_layer.layer = 10
	_hud_layer.visible = false
	_main.add_child(_hud_layer)

	_font = ThemeManager.get_reading_font()

	# Bottom-centre panel
	_hud_panel = PanelContainer.new()
	_hud_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hud_panel.offset_left   = 200.0
	_hud_panel.offset_right  = -200.0
	_hud_panel.offset_top    = -80.0
	_hud_panel.offset_bottom = -16.0
	_hud_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud_layer.add_child(_hud_panel)

	_panel_style = StyleBoxFlat.new()
	_hud_panel.add_theme_stylebox_override("panel", _panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top",   10)
	margin.add_theme_constant_override("margin_bottom",10)
	_hud_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	_name_lbl = Label.new()
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_name_lbl)

	_hint_lbl = Label.new()
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_hint_lbl)

	_apply_hud_style()
	ThemeManager.dark_mode_changed.connect(func(_d): _apply_hud_style())

func _apply_hud_style() -> void:
	if not _panel_style:
		return
	var dark := ThemeManager.is_dark_mode
	var bg: Color = ThemeManager.bg_color
	bg.a = 0.88
	_panel_style.bg_color = bg
	_panel_style.border_color = ThemeManager.border_color
	for side in [0, 1, 2, 3]:
		_panel_style.set("border_width_" + ["left", "right", "top", "bottom"][side], 1)
	_panel_style.set_corner_radius_all(8)
	_panel_style.shadow_color = Color(0, 0, 0, 0.3 if dark else 0.1)
	_panel_style.shadow_size = 10

	if _name_lbl:
		_name_lbl.add_theme_color_override("font_color", ThemeManager.text_color)
		_name_lbl.add_theme_font_size_override("font_size", 17)
		if _font: _name_lbl.add_theme_font_override("font", _font)

	if _hint_lbl:
		_hint_lbl.add_theme_color_override("font_color", ThemeManager.subtext_color)
		_hint_lbl.add_theme_font_size_override("font_size", 12)
		if _font: _hint_lbl.add_theme_font_override("font", _font)
