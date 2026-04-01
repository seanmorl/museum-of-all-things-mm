extends Node3D

@export var starting_text: String = ""
@export var arrow: bool = true
@export var arrow_left: bool = true

static var max_lines: int = 4
var L_ARROW: String = "←"
var R_ARROW: String = "→"
var _text_value: String = ""

var text: String:
	get:
		return _text_value
	set(v):
		_text_value = v
		$Text.text = v.replace("$", "")
		call_deferred("_resize_text")

var left: bool:
	get:
		return $Arrow.text == L_ARROW
	set(v):
		$Arrow.text = L_ARROW if v else R_ARROW

func _resize_text() -> void:
	TextUtils.resize_text_to_px($Text, $Text.width * max_lines)

func _ready() -> void:
	if starting_text:
		text = starting_text
	if not arrow:
		$Arrow.visible = false
	else:
		left = arrow_left

	SettingsEvents.accessibility_changed.connect(_on_accessibility_changed)
	ThemeManager.dark_mode_changed.connect(_on_dark_mode_changed)
	_on_dark_mode_changed(ThemeManager.is_dark_mode)
	_on_accessibility_changed()

var _tween: Tween = null
var _setup_complete: bool = false

func _on_accessibility_changed(key: String = "", value: Variant = null) -> void:
	# Check if floating signs mode is enabled
	if key != "" and key != "floating_signs":
		return
	
	var saved = SettingsManager.get_settings("accessibility")
	var floating_signs: bool = saved.get("floating_signs", false) if saved else false
	
	# Hide physical board mesh, keep text visible in same position
	if $MeshInstance3D:
		$MeshInstance3D.visible = not floating_signs
	
	# Make text larger and add outline when floating, but keep same orientation
	if floating_signs:
		$Text.pixel_size = 0.008  # 4x larger than physical sign
		$Text.outline_size = 4
		$Text.outline_modulate = Color(0, 0, 0, 0.5)
		$Arrow.pixel_size = 0.008
		$Arrow.outline_size = 4
		$Arrow.outline_modulate = Color(0, 0, 0, 0.5)
	else:
		$Text.pixel_size = 0.002
		$Text.outline_size = 0
		$Arrow.pixel_size = 0.002
		$Arrow.outline_size = 6

func _on_dark_mode_changed(is_dark: bool) -> void:
	var target_text_color = Color(0.9, 0.9, 0.9) if is_dark else Color(0, 0, 0)
	var target_outline_color = Color(1, 1, 1, 0.15) if is_dark else Color(1, 1, 1, 0)
	var target_board_color = Color(0.04, 0.04, 0.04) if is_dark else Color(1, 1, 1)

	if not _setup_complete:
		$Text.modulate = target_text_color
		$Text.outline_modulate = target_outline_color
		$Arrow.modulate = target_text_color
		$Arrow.outline_modulate = target_outline_color
		_setup_complete = true
		
		var mesh: MeshInstance3D = $MeshInstance3D
		if mesh:
			var board_mat: StandardMaterial3D = mesh.get_surface_override_material(1)
			if not board_mat:
				var orig = mesh.mesh.surface_get_material(1)
				board_mat = orig.duplicate() if orig else StandardMaterial3D.new()
				mesh.set_surface_override_material(1, board_mat)
			board_mat.albedo_color = target_board_color
			board_mat.emission_enabled = false
		return

	if _tween and _tween.is_valid():
		_tween.kill()
	
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Important: Allow the fade to happen even when the game is paused
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	
	_tween.tween_property($Text, "modulate", target_text_color, 0.35)
	_tween.tween_property($Text, "outline_modulate", target_outline_color, 0.35)
	_tween.tween_property($Arrow, "modulate", target_text_color, 0.35)
	_tween.tween_property($Arrow, "outline_modulate", target_outline_color, 0.35)
	
	var mesh: MeshInstance3D = $MeshInstance3D
	if mesh:
		var board_mat: StandardMaterial3D = mesh.get_surface_override_material(1)
		if not board_mat:
			var orig = mesh.mesh.surface_get_material(1)
			board_mat = orig.duplicate() if orig else StandardMaterial3D.new()
			mesh.set_surface_override_material(1, board_mat)
		
		board_mat.emission_enabled = false
		_tween.tween_property(board_mat, "albedo_color", target_board_color, 0.35)
