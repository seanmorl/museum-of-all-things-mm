extends Control
## MinimapController — single owner of all in-game minimap sub-views.
##
## Replaces the old Minimap.gd loader in Main.gd.
##
## Mode cycle (M key):
##   OFF  →  COMPASS  →  GRAPH  →  OFF
##
##   COMPASS  = CompassMinimap   (compass ring + real exit blips + heading arrow)
##   GRAPH    = Minimap          (topological exhibit graph, centred on player)
##
## Public API (called by Main.gd):
##   init(player)          — must be called after every player (re-)spawn
##   cycle_mode()          — advance through OFF→COMPASS→GRAPH→OFF
##   set_current_room(r)   — forward to graph sub-view for label update
##   save_mode()           — snapshot mode before pause
##   restore_mode()        — restore snapshot after pause

enum Mode { OFF, COMPASS, GRAPH }

var _mode        : Mode    = Mode.OFF
var _saved_mode  : Mode    = Mode.OFF
var _player      : Node    = null

var _compass     : Control = null   ## CompassMinimap instance
var _graph       : Control = null   ## Minimap (graph) instance


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ── Compass sub-view ────────────────────────────────────────────────────
	_compass = load("res://scenes/ui/CompassMinimap.gd").new()
	_compass.name    = "CompassView"
	_compass.visible = false
	add_child(_compass)

	# ── Graph sub-view ──────────────────────────────────────────────────────
	_graph = load("res://scenes/ui/Minimap.gd").new()
	_graph.name    = "GraphView"
	_graph.visible = false
	add_child(_graph)


# ── Public API ─────────────────────────────────────────────────────────────

func init(player: Node) -> void:
	## Call after every player (re-)spawn. Passes the player reference to any
	## sub-view that needs real-world bearing / position data.
	_player = player
	if _compass and _compass.has_method("init"):
		_compass.init(player)
	if _graph and _graph.has_method("init"):
		_graph.init(player)


func cycle_mode() -> void:
	## Advance through OFF → COMPASS → GRAPH → OFF with smooth transitions.
	var prev := _mode
	match _mode:
		Mode.OFF:     _mode = Mode.COMPASS
		Mode.COMPASS: _mode = Mode.GRAPH
		Mode.GRAPH:   _mode = Mode.OFF

	_apply_mode_change(prev, _mode)


func toggle() -> void:
	## Binary show/hide. If OFF advances to COMPASS; otherwise goes to OFF.
	## Kept for callers that only want a simple on/off flip.
	if _mode == Mode.OFF:
		cycle_mode()
	else:
		var prev := _mode
		_mode = Mode.OFF
		_apply_mode_change(prev, _mode)


func set_current_room(room: String) -> void:
	## Forward room label to the graph view's label.
	if _graph and _graph.has_method("set_current_room"):
		_graph.set_current_room(room)


func save_mode() -> void:
	## Snapshot current mode before entering a pause menu.
	_saved_mode = _mode
	_set_subview_visible(_mode, false)


func restore_mode() -> void:
	## Restore mode saved by save_mode().
	_mode = _saved_mode
	_set_subview_visible(_mode, true)


func is_any_visible() -> bool:
	return _mode != Mode.OFF


# ── Internal ───────────────────────────────────────────────────────────────

func _apply_mode_change(prev: Mode, next: Mode) -> void:
	_set_subview_visible(prev, false)
	_set_subview_visible(next, true)


func _set_subview_visible(mode: Mode, show: bool) -> void:
	match mode:
		Mode.COMPASS:
			if _compass:
				if show:
					_compass.visible = true
					_fade(_compass, 0.0, 1.0, 0.18)
				else:
					_fade(_compass, 1.0, 0.0, 0.12, func(): _compass.visible = false)
		Mode.GRAPH:
			if _graph:
				if show:
					_graph.visible = true
					_fade(_graph, 0.0, 1.0, 0.18)
				else:
					_fade(_graph, 1.0, 0.0, 0.12, func(): _graph.visible = false)


func _fade(node: Control, from_a: float, to_a: float, dur: float,
		on_done: Callable = Callable()) -> void:
	if not is_instance_valid(node): return
	node.modulate.a = from_a
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.set_ease(Tween.EASE_IN_OUT if from_a > to_a else Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", to_a, dur)
	if on_done.is_valid():
		tw.tween_callback(on_done)
