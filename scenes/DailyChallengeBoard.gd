extends Node3D
class_name DailyChallengeBoard
## Physical noticeboard placed in the lobby near the spawn point.
## Shows today's target article and top scores on a world-space billboard.
## Add this as an AutoLoad or instantiate it from museum/lobby setup code.
##
## To place it in the editor: attach this script to a Node3D, position it
## near the spawn (e.g. Vector3(2, 0, -2) facing the player start).
## It builds its own mesh, frame, and SubViewport billboard at runtime.

@export var board_position: Vector3 = Vector3(2.5, 0.0, -2.0)
@export var board_rotation_y: float = -30.0   ## degrees, faces toward spawn

const BOARD_W := 0.9    ## metres wide
const BOARD_H := 1.2    ## metres tall
const FRAME_DEPTH := 0.04

var _manager: Node     = null
var _leaderboard: Node = null
var _viewport: SubViewport   = null
var _vp_texture: ViewportTexture = null

## 2D UI nodes inside the SubViewport
var _vp_root: Control        = null
var _title_lbl: Label        = null
var _date_lbl: Label         = null
var _target_caption: Label   = null
var _target_lbl: Label       = null
var _sep: HSeparator         = null
var _lb_caption: Label       = null
var _lb_list: VBoxContainer  = null
var _font: Font              = null

const ACCENT := Color(0.35, 0.75, 1.00)
const BG     := Color(0.97, 0.95, 0.90, 1.0)   ## warm paper colour
const INK    := Color(0.12, 0.10, 0.08, 1.0)
const INK2   := Color(0.40, 0.36, 0.30, 1.0)
const VP_W   := 360
const VP_H   := 480

# ── Setup ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_font = ThemeManager.get_reading_font()
	_build_board_mesh()
	_build_viewport()
	_build_viewport_ui()
	_update_display()

func init(manager: Node, leaderboard: Node = null) -> void:
	_manager     = manager
	_leaderboard = leaderboard
	if _manager and _manager.has_signal("challenge_ready"):
		_manager.challenge_ready.connect(func(_t, _s): _update_display())
	if _leaderboard and _leaderboard.has_signal("scores_updated"):
		_leaderboard.scores_updated.connect(func(e): _rebuild_leaderboard(e))
	if _manager and _manager.has_method("start_challenge") and _manager.get_target_article() == "":
		_manager.start_challenge()
	if _leaderboard and _leaderboard.has_method("fetch_scores") and _manager:
		_leaderboard.fetch_scores(_manager.get_today_key())

# ── 3D construction ───────────────────────────────────────────────────────────

func _build_board_mesh() -> void:
	position = board_position
	rotation_degrees.y = board_rotation_y

	# Wooden frame (slightly larger than the board face)
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(BOARD_W + FRAME_DEPTH * 2, BOARD_H + FRAME_DEPTH * 2, FRAME_DEPTH)
	var frame_inst := MeshInstance3D.new()
	frame_inst.mesh = frame_mesh
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.35, 0.22, 0.10)   ## dark wood
	frame_mat.roughness    = 0.85
	frame_inst.material_override = frame_mat
	frame_inst.position = Vector3(0, BOARD_H * 0.5 + 0.05, 0)
	add_child(frame_inst)

	# White/paper board face — the SubViewport texture goes here
	var face_mesh := QuadMesh.new()
	face_mesh.size = Vector2(BOARD_W, BOARD_H)
	var face_inst := MeshInstance3D.new()
	face_inst.name = "BoardFace"
	face_inst.mesh = face_mesh
	face_inst.position = Vector3(0, BOARD_H * 0.5 + 0.05, FRAME_DEPTH * 0.5 + 0.001)
	add_child(face_inst)

	# Post / stand
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.06, 0.12, 0.06)
	var post_inst := MeshInstance3D.new()
	post_inst.mesh = post_mesh
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.30, 0.18, 0.08)
	post_mat.roughness    = 0.9
	post_inst.material_override = post_mat
	post_inst.position = Vector3(0, 0.04, 0)
	add_child(post_inst)

func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "BoardViewport"
	_viewport.size = Vector2i(VP_W, VP_H)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.transparent_bg = false
	add_child(_viewport)

	# Apply the viewport texture to the board face
	await get_tree().process_frame   # wait for face_inst to be ready
	var face_inst := get_node_or_null("BoardFace") as MeshInstance3D
	if face_inst:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _viewport.get_texture()
		mat.roughness      = 0.95
		mat.metallic       = 0.0
		face_inst.material_override = mat

func _build_viewport_ui() -> void:
	_vp_root = Control.new()
	_vp_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_vp_root)

	# Background
	var bg_rect := ColorRect.new()
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.color = BG
	_vp_root.add_child(bg_rect)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   20)
	margin.add_theme_constant_override("margin_right",  20)
	margin.add_theme_constant_override("margin_top",    18)
	margin.add_theme_constant_override("margin_bottom", 14)
	_vp_root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title banner
	var title_bg := ColorRect.new()
	title_bg.color = ACCENT
	title_bg.custom_minimum_size = Vector2(0, 42)
	vbox.add_child(title_bg)

	var title_margin := MarginContainer.new()
	title_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_margin.add_theme_constant_override("margin_left", 10)
	title_margin.add_theme_constant_override("margin_right", 10)
	title_bg.add_child(title_margin)

	_title_lbl = Label.new()
	_title_lbl.text = "📅  Daily Challenge"
	_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_vp_lbl(_title_lbl, Color(0.10, 0.06, 0.0), 17)
	title_margin.add_child(_title_lbl)

	_date_lbl = Label.new()
	_style_vp_lbl(_date_lbl, INK2, 12)
	vbox.add_child(_date_lbl)

	var sep1 := HSeparator.new()
	sep1.modulate = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6)
	vbox.add_child(sep1)

	_target_caption = Label.new()
	_target_caption.text = "TODAY'S TARGET"
	_style_vp_lbl(_target_caption, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85), 10)
	vbox.add_child(_target_caption)

	_target_lbl = Label.new()
	_target_lbl.text = "Loading..."
	_target_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_vp_lbl(_target_lbl, INK, 20)
	vbox.add_child(_target_lbl)

	var sep2 := HSeparator.new()
	sep2.modulate = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6)
	vbox.add_child(sep2)

	_lb_caption = Label.new()
	_lb_caption.text = "TODAY'S TOP TIMES"
	_style_vp_lbl(_lb_caption, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85), 10)
	vbox.add_child(_lb_caption)

	_lb_list = VBoxContainer.new()
	_lb_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_lb_list)

	var placeholder := Label.new()
	placeholder.text = "Loading scores..."
	_style_vp_lbl(placeholder, INK2, 13)
	_lb_list.add_child(placeholder)

func _style_vp_lbl(lbl: Label, color: Color, size: int) -> void:
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	if _font:
		lbl.add_theme_font_override("font", _font)

# ── Content updates ───────────────────────────────────────────────────────────

func _update_display() -> void:
	if not _manager:
		return
	var today: String = _manager.get_today_key() if _manager.has_method("get_today_key") else ""
	var target: String = _manager.get_target_article() if _manager.has_method("get_target_article") else ""
	var streak: int = _manager.get_streak() if _manager.has_method("get_streak") else 0

	if _date_lbl:
		_date_lbl.text = today + ("   🔥 %d day streak" % streak if streak > 0 else "")
	if _target_lbl:
		_target_lbl.text = target if target != "" else "Loading..."

func _rebuild_leaderboard(entries: Array) -> void:
	if not _lb_list:
		return
	for child in _lb_list.get_children():
		child.queue_free()

	if entries.is_empty():
		var lbl := Label.new()
		lbl.text = "No scores yet — be first!"
		_style_vp_lbl(lbl, INK2, 13)
		_lb_list.add_child(lbl)
		return

	for i in min(entries.size(), 5):
		var entry: Dictionary = entries[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_lb_list.add_child(row)

		var medals := ["🥇", "🥈", "🥉", "4.", "5."]
		var rank_lbl := Label.new()
		rank_lbl.text = medals[i] if i < medals.size() else "%d." % (i + 1)
		_style_vp_lbl(rank_lbl, ACCENT if i == 0 else INK2, 14)
		row.add_child(rank_lbl)

		var name_lbl := Label.new()
		name_lbl.text = str(entry.get("name", "?"))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_vp_lbl(name_lbl, INK if i == 0 else INK2, 13)
		row.add_child(name_lbl)

		var time_lbl := Label.new()
		var t := float(entry.get("time_seconds", 0))
		time_lbl.text = "%d:%02d" % [int(t) / 60, int(t) % 60]
		_style_vp_lbl(time_lbl, ACCENT if i == 0 else INK2, 13)
		row.add_child(time_lbl)
