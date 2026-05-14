extends Node
## TournamentManager — multiplayer tournament mode autoload.
##
## Architecture:
##   • Host creates a tournament (bracket or round-robin, N rounds)
##   • Each round = one race. Winner earns points. Standings tracked live.
##   • After all rounds: champion announced via TournamentVictoryScreen
##   • Twitch integration: overlay-ready HTTP endpoint for OBS browser sources
##   • All state synced to every client via RPC
##
## Add as Autoload: res://scenes/tournament/TournamentManager.gd
## Name: TournamentManager

# ── Signals ───────────────────────────────────────────────────────────────────
signal tournament_started(config: Dictionary)
signal tournament_round_started(round_num: int, total_rounds: int)
signal tournament_round_ended(round_num: int, winner_name: String, standings: Array)
signal tournament_ended(champion_name: String, final_standings: Array)
signal tournament_cancelled
signal standings_updated(standings: Array)
signal round_history_updated(history: Array)

# ── Enums ─────────────────────────────────────────────────────────────────────
enum Format { ROUNDS, FIRST_TO_N }
## ROUNDS:     fixed number of races; most points wins
## FIRST_TO_N: races until someone reaches N wins

enum PointsMode { WIN_ONLY, PODIUM, SPEED_BONUS }
## WIN_ONLY:    1 pt for 1st, 0 for others
## PODIUM:      3/2/1 for 1st/2nd/3rd
## SPEED_BONUS: base points + bonus for fast completion

# ── Config ────────────────────────────────────────────────────────────────────
const DEFAULT_ROUNDS:       int   = 5
const DEFAULT_FIRST_TO_N:   int   = 3
const MAX_ROUNDS:           int   = 20
const BETWEEN_ROUND_DELAY:  float = 8.0   # seconds between rounds
const TWITCH_PORT:          int   = 9876  # HTTP port for OBS overlay

# ── State ─────────────────────────────────────────────────────────────────────
var _active:          bool   = false
var _format:          Format = Format.ROUNDS
var _points_mode:     PointsMode = PointsMode.PODIUM
var _total_rounds:    int    = DEFAULT_ROUNDS
var _first_to_n:      int    = DEFAULT_FIRST_TO_N
var _current_round:   int    = 0
var _tournament_name: String = "Tournament"

## peer_id → { name, color, wins, points, best_time, finish_times: Array[float] }
var _standings: Dictionary = {}

## Ordered finish positions for the current race [peer_id, ...]
var _round_finish_order: Array[int] = []
var _round_in_progress:  bool       = false
var _between_rounds:     bool       = false

## Per-round history: [ { round_num, results: [ { peer_id, name, position, points_earned } ] } ]
var _round_history: Array = []

## Twitch HTTP server (TCP)
var _twitch_server: TCPServer = null
var _twitch_clients: Array    = []


func _ready() -> void:
	RaceManager.race_ended.connect(_on_race_ended)
	RaceManager.race_won.connect(_on_race_won_signal)
	RaceManager.race_cancelled.connect(_on_race_cancelled)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)


func _exit_tree() -> void:
	RaceManager.race_ended.disconnect(_on_race_ended)
	RaceManager.race_won.disconnect(_on_race_won_signal)
	RaceManager.race_cancelled.disconnect(_on_race_cancelled)
	NetworkManager.peer_disconnected.disconnect(_on_peer_disconnected)


func _process(delta: float) -> void:
	if _twitch_server:
		_poll_twitch_server()


# ── UI Initialization ─────────────────────────────────────────────────────────

var _ui_initialized: bool = false
var _main_node: Node = null

func initialize_ui(main: Node) -> void:
	if _ui_initialized:
		return
	_ui_initialized = true
	_main_node = main
	_create_tournament_ui()
	_connect_tournament_signals()


func _create_tournament_ui() -> void:
	if not _main_node:
		return
	
	var t_layer := CanvasLayer.new()
	t_layer.name = "TournamentLayer"
	t_layer.layer = 95
	_main_node.add_child(t_layer)

	var t_hud_script := load("res://scenes/tournament/TournamentHUD.gd")
	if t_hud_script:
		var hud := Control.new()
		hud.set_script(t_hud_script)
		hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hud.name = "TournamentHUD"
		t_layer.add_child(hud)
	
	var t_bracket_script := load("res://scenes/tournament/TournamentBracketHUD.gd")
	if t_bracket_script:
		var bracket := Control.new()
		bracket.set_script(t_bracket_script)
		bracket.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bracket.name = "TournamentBracketHUD"
		t_layer.add_child(bracket)
	
	var t_vic_script := load("res://scenes/tournament/TournamentVictoryScreen.gd")
	if t_vic_script:
		var vic := Control.new()
		vic.set_script(t_vic_script)
		vic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vic.name = "TournamentVictoryScreen"
		t_layer.add_child(vic)
	
	var t_setup_script := load("res://scenes/tournament/TournamentSetupMenu.gd")
	if t_setup_script:
		var setup := Control.new()
		setup.set_script(t_setup_script)
		setup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		setup.name = "TournamentSetupMenu"
		setup.visible = false
		t_layer.add_child(setup)


func _connect_tournament_signals() -> void:
	tournament_cancelled.connect(_on_ui_tournament_cancelled)


func get_tournament_layer() -> CanvasLayer:
	if _main_node:
		return _main_node.get_node_or_null("TournamentLayer")
	return null


func get_tournament_hud() -> Control:
	var layer := get_tournament_layer()
	if layer:
		return layer.get_node_or_null("TournamentHUD")
	return null


func get_tournament_setup_menu() -> Control:
	var layer := get_tournament_layer()
	if layer:
		return layer.get_node_or_null("TournamentSetupMenu")
	return null


func _on_ui_tournament_cancelled() -> void:
	if not _main_node:
		return
	var t_layer := _main_node.get_node_or_null("TournamentLayer")
	if t_layer:
		var hud := t_layer.get_node_or_null("TournamentHUD")
		if hud:
			hud.visible = false
		var bracket := t_layer.get_node_or_null("TournamentBracketHUD")
		if bracket:
			bracket.visible = false


# ── Public API ────────────────────────────────────────────────────────────────

func is_active() -> bool:
	return _active

func get_current_round() -> int:
	return _current_round

func get_total_rounds() -> int:
	return _total_rounds

func get_standings() -> Array:
	## Returns standings sorted by points desc, then wins desc, then best_time asc.
	var list: Array = []
	for peer_id in _standings:
		var entry: Dictionary = _standings[peer_id].duplicate()
		entry["peer_id"] = peer_id
		list.append(entry)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.points != b.points:
			return a.points > b.points
		if a.wins != b.wins:
			return a.wins > b.wins
		var at: float = a.best_time if a.best_time > 0 else 99999.0
		var bt: float = b.best_time if b.best_time > 0 else 99999.0
		return at < bt
	)
	return list

func get_config() -> Dictionary:
	return {
		"name":        _tournament_name,
		"format":      _format,
		"points_mode": _points_mode,
		"total_rounds": _total_rounds,
		"first_to_n":  _first_to_n,
		"current_round": _current_round,
		"active":      _active,
	}

func get_round_history() -> Array:
	## Returns the per-round result history for bracket display.
	## Each entry: { round_num, results: [ { peer_id, name, position, points_earned } ] }
	return _round_history.duplicate(true)


# ── Host: Start / Stop ────────────────────────────────────────────────────────

func host_start_tournament(config: Dictionary) -> void:
	## Call from host only. config keys:
	##   name (String), format (Format), points_mode (PointsMode),
	##   total_rounds (int), first_to_n (int)
	if not NetworkManager.is_server():
		push_error("TournamentManager: Only host can start a tournament")
		return
	if _active:
		push_error("TournamentManager: Tournament already active")
		return

	_tournament_name = config.get("name", "Tournament")
	_format          = config.get("format", Format.ROUNDS)
	_points_mode     = config.get("points_mode", PointsMode.PODIUM)
	_total_rounds    = clampi(config.get("total_rounds", DEFAULT_ROUNDS), 1, MAX_ROUNDS)
	_first_to_n      = clampi(config.get("first_to_n", DEFAULT_FIRST_TO_N), 1, MAX_ROUNDS)
	_current_round   = 0
	_active          = true
	_standings.clear()
	_round_history.clear()

	# Register all currently connected players
	for peer_id in NetworkManager.get_player_list():
		_register_player(peer_id)

	# Sync to all clients
	_rpc_sync_tournament_start.rpc(
		_tournament_name, int(_format), int(_points_mode),
		_total_rounds, _first_to_n
	)
	tournament_started.emit(get_config())

	await get_tree().create_timer(1.0).timeout
	_start_next_round()


func host_cancel_tournament() -> void:
	if not NetworkManager.is_server() or not _active:
		return
	_rpc_sync_tournament_cancelled.rpc()
	_reset_state()
	tournament_cancelled.emit()


func host_advance_round() -> void:
	## Force-advance to next round (host only, skips between-round delay)
	if not NetworkManager.is_server() or not _active or not _between_rounds:
		return
	_start_next_round()


# ── Round flow ────────────────────────────────────────────────────────────────

func _start_next_round() -> void:
	if not NetworkManager.is_server():
		return
	_current_round += 1
	_round_finish_order.clear()
	_round_in_progress = true
	_between_rounds    = false

	_rpc_sync_round_started.rpc(_current_round, _total_rounds)
	tournament_round_started.emit(_current_round, _total_rounds)

	# Trigger the normal race vote flow through Main.gd.
	# _on_start_race_pressed() fetches candidates and launches the VoteHUD.
	# Note: Use get_nodes_in_group and find the one with the method, because
	# HintManager is also in the "main" group and might be returned first.
	var nodes := get_tree().get_nodes_in_group("main")
	for node in nodes:
		if node.has_method("_on_start_race_pressed"):
			node._on_start_race_pressed()
			return
	push_error("TournamentManager: Cannot find node with _on_start_race_pressed in group 'main'")


func _on_race_won_signal(winner_name: String, _final_time: float) -> void:
	## race_won fires immediately when the first player crosses — record them
	if not _active or not _round_in_progress:
		return
	# Find peer_id by name
	for peer_id in NetworkManager.get_player_list():
		if NetworkManager.get_player_name(peer_id) == winner_name:
			if not _round_finish_order.has(peer_id):
				_round_finish_order.append(peer_id)
			break


func _on_race_ended(winner_peer_id: int, winner_name: String) -> void:
	if not _active or not _round_in_progress:
		return
	if not NetworkManager.is_server():
		return

	# Ensure winner is recorded first if race_won didn't fire
	if not _round_finish_order.has(winner_peer_id):
		_round_finish_order.push_front(winner_peer_id)

	_round_in_progress = false
	var final_time: float = RaceManager.get_final_time()
	_award_round_points(final_time)

	var standings := get_standings()
	_rpc_sync_standings.rpc(_serialise_standings(standings))
	_rpc_sync_round_ended.rpc(_current_round, winner_name, _serialise_standings(standings))

	tournament_round_ended.emit(_current_round, winner_name, standings)
	standings_updated.emit(standings)

	# Check tournament end condition
	if _should_tournament_end():
		await get_tree().create_timer(BETWEEN_ROUND_DELAY).timeout
		_end_tournament()
	else:
		_between_rounds = true
		await get_tree().create_timer(BETWEEN_ROUND_DELAY).timeout
		if _active:
			_start_next_round()


func _on_race_cancelled() -> void:
	## Handle race cancellation - reset round state for retry or continue
	if not _active or not _round_in_progress:
		return
	if not NetworkManager.is_server():
		return

	_round_in_progress = false
	_round_finish_order.clear()
	_between_rounds = false

	Log.info("TournamentManager", "Race cancelled - round state reset")


func _award_round_points(winner_time: float) -> void:
	## Award points to all players based on finish order + points mode.
	## Only the winner has a meaningful finish time (RaceManager only tracks
	## the winner's time). Non-winners get -1.0 recorded.
	var podium_points := [3, 2, 1]   # PODIUM mode
	var all_peers := NetworkManager.get_player_list()
	var round_results: Array = []    # Per-round bracket data

	for i in _round_finish_order.size():
		var peer_id: int = _round_finish_order[i]
		if not _standings.has(peer_id):
			_register_player(peer_id)
		var s: Dictionary = _standings[peer_id] as Dictionary
		var pts: int = 0
		match _points_mode:
			PointsMode.WIN_ONLY:
				pts = 1 if i == 0 else 0
			PointsMode.PODIUM:
				pts = podium_points[i] if i < podium_points.size() else 0
			PointsMode.SPEED_BONUS:
				if i == 0:
					pts = 3
					# Bonus point for finishing under 60s
					if winner_time < 60.0:
						pts += 1
				elif i == 1: pts = 2
				elif i == 2: pts = 1
		s.points += pts
		if i == 0:
			s.wins += 1
		# Record finish time. Only the winner has a meaningful time available
		# (RaceManager tracks first-place finish only). All other finishers
		# get -1.0 since we don't have per-player timestamps.
		var finish_time: float = RaceManager.get_final_time() if i == 0 else -1.0
		s.finish_times.append(finish_time)
		if finish_time > 0 and (s.best_time <= 0 or finish_time < s.best_time):
			s.best_time = finish_time

		# Record per-round bracket data
		round_results.append({
			"peer_id":       peer_id,
			"name":          s.name,
			"color":         s.color,
			"position":      i + 1,
			"points_earned": pts,
		})

	# Players who didn't finish get 0 pts, still registered
	for peer_id in all_peers:
		if not _round_finish_order.has(peer_id):
			if not _standings.has(peer_id):
				_register_player(peer_id)
			_standings[peer_id].finish_times.append(-1.0)
			var s: Dictionary = _standings[peer_id]
			round_results.append({
				"peer_id":       peer_id,
				"name":          s.name,
				"color":         s.color,
				"position":      _round_finish_order.size() + 1,  # DNF
				"points_earned": 0,
			})

	# Save round to history
	_round_history.append({
		"round_num": _current_round,
		"results":   round_results,
	})
	round_history_updated.emit(_round_history.duplicate(true))


func _should_tournament_end() -> bool:
	match _format:
		Format.ROUNDS:
			return _current_round >= _total_rounds
		Format.FIRST_TO_N:
			for peer_id in _standings:
				if _standings[peer_id].wins >= _first_to_n:
					return true
			return false
	return false


func _end_tournament() -> void:
	var standings := get_standings()
	var champion: String = standings[0].name if standings.size() > 0 else "Unknown"
	_rpc_sync_tournament_ended.rpc(champion, _serialise_standings(standings))
	tournament_ended.emit(champion, standings)
	_reset_state()


# ── Player registration ────────────────────────────────────────────────────────

func _register_player(peer_id: int) -> void:
	if _standings.has(peer_id):
		return
	_standings[peer_id] = {
		"name":         NetworkManager.get_player_name(peer_id),
		"color":        NetworkManager.get_player_color(peer_id),
		"wins":         0,
		"points":       0,
		"best_time":    -1.0,
		"finish_times": [],
		"peer_id":      peer_id,
	}


func _on_peer_disconnected(peer_id: int) -> void:
	if not _active:
		return
	# Keep their score in standings (they'll just stop winning rounds)
	if _standings.has(peer_id):
		_standings[peer_id].name += " (left)"


# ── Serialisation helpers ─────────────────────────────────────────────────────

func _serialise_standings(standings: Array) -> Array:
	## Convert to a plain Array of Dictionaries safe for RPC
	var out: Array = []
	for entry in standings:
		out.append({
			"name":      entry.get("name", ""),
			"points":    entry.get("points", 0),
			"wins":      entry.get("wins", 0),
			"best_time": entry.get("best_time", -1.0),
			"peer_id":   entry.get("peer_id", -1),
		})
	return out


func _deserialise_standings(raw: Array) -> Array:
	return raw  # Already plain dicts on client side


func _reset_state() -> void:
	_active          = false
	_current_round   = 0
	_round_in_progress = false
	_between_rounds  = false
	_standings.clear()
	_round_history.clear()
	_round_finish_order.clear()


# ── RPCs — server → all clients ───────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _rpc_sync_tournament_start(
		t_name: String, format: int, points_mode: int,
		total_rounds: int, first_to_n: int) -> void:
	_tournament_name = t_name
	_format          = format as Format
	_points_mode     = points_mode as PointsMode
	_total_rounds    = total_rounds
	_first_to_n      = first_to_n
	_current_round   = 0
	_active          = true
	_standings.clear()
	_round_history.clear()

	# Register all currently connected players on this client too
	for peer_id in NetworkManager.get_player_list():
		_register_player(peer_id)

	tournament_started.emit(get_config())


@rpc("authority", "call_local", "reliable")
func _rpc_sync_round_started(round_num: int, total: int) -> void:
	_current_round     = round_num
	_round_in_progress = true
	_between_rounds    = false
	tournament_round_started.emit(round_num, total)

	# Do NOT trigger _on_start_race_pressed() on clients.
	# The host already called it from _start_next_round().  Clients receive
	# vote candidate data via RaceManager._sync_vote_start (emitted when
	# the host finishes fetching candidates). Calling _on_start_race_pressed()
	# here would cause every client to independently fetch the same candidates
	# from the Wikipedia API — wasting bandwidth and creating duplicate data.


@rpc("authority", "call_local", "reliable")
func _rpc_sync_round_ended(round_num: int, winner_name: String, raw_standings: Array) -> void:
	_round_in_progress = false
	_between_rounds    = true
	var standings := _deserialise_standings(raw_standings)
	tournament_round_ended.emit(round_num, winner_name, standings)
	standings_updated.emit(standings)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_standings(raw_standings: Array) -> void:
	var standings := _deserialise_standings(raw_standings)
	standings_updated.emit(standings)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_tournament_ended(champion: String, raw_standings: Array) -> void:
	var standings := _deserialise_standings(raw_standings)
	_reset_state()
	tournament_ended.emit(champion, standings)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_tournament_cancelled() -> void:
	_reset_state()
	tournament_cancelled.emit()


# ── Twitch / OBS overlay HTTP server ─────────────────────────────────────────

func start_twitch_server() -> void:
	## Starts a local TCP server on TWITCH_PORT.
	## OBS browser source: http://localhost:9876/overlay
	## Returns JSON standings at http://localhost:9876/standings
	if _twitch_server:
		return
	_twitch_server = TCPServer.new()
	var err := _twitch_server.listen(TWITCH_PORT)
	if err != OK:
		push_error("TournamentManager: Could not start Twitch server on port %d" % TWITCH_PORT)
		_twitch_server = null
	else:
		Log.info("TournamentManager", "Twitch overlay server listening on http://localhost:%d" % TWITCH_PORT)


func stop_twitch_server() -> void:
	if _twitch_server:
		_twitch_server.stop()
		_twitch_server = null
	_twitch_clients.clear()


func _poll_twitch_server() -> void:
	if not _twitch_server:
		return
	if _twitch_server.is_connection_available():
		var conn := _twitch_server.take_connection()
		if conn:
			_twitch_clients.append(conn)

	var to_remove: Array = []
	for client in _twitch_clients:
		if not client.is_connected_to_host():
			to_remove.append(client)
			continue
		var available: int = client.get_available_bytes()
		if available > 0:
			var raw: String = client.get_string(available)
			var path: String = _parse_http_path(raw)
			var response: String = _build_http_response(path)
			client.put_data(response.to_utf8_buffer())
			to_remove.append(client)
	for c in to_remove:
		_twitch_clients.erase(c)


func _parse_http_path(raw: String) -> String:
	var lines := raw.split("\n")
	if lines.size() == 0:
		return "/"
	var parts := lines[0].split(" ")
	return parts[1] if parts.size() > 1 else "/"


func _build_http_response(path: String) -> String:
	var body: String
	var content_type: String

	match path:
		"/standings", "/standings/":
			body         = _build_standings_json()
			content_type = "application/json"
		"/overlay", "/overlay/":
			body         = _build_overlay_html()
			content_type = "text/html"
		"/config", "/config/":
			body         = _build_config_json()
			content_type = "application/json"
		_:
			body         = '{"error":"not found"}'
			content_type = "application/json"

	var header := "HTTP/1.1 200 OK\r\nContent-Type: %s; charset=utf-8\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" \
		% [content_type, body.length()]
	return header + body


func _build_standings_json() -> String:
	var standings := get_standings()
	var entries: Array = []
	for i in standings.size():
		var s: Dictionary = standings[i]
		entries.append({
			"rank":      i + 1,
			"name":      s.get("name", ""),
			"points":    s.get("points", 0),
			"wins":      s.get("wins", 0),
			"best_time": s.get("best_time", -1.0),
		})
	var config := get_config()
	return JSON.stringify({
		"tournament":     config.get("name", ""),
		"round":          _current_round,
		"total_rounds":   _total_rounds,
		"active":         _active,
		"between_rounds": _between_rounds,
		"standings":      entries,
	})


func _build_config_json() -> String:
	return JSON.stringify(get_config())


func _build_overlay_html() -> String:
	## Self-refreshing HTML page for OBS browser source.
	## Polls /standings every 3 seconds and renders a live table.
	return """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body {
    background: transparent;
	font-family: 'Segoe UI', sans-serif;
    color: #fff;
    padding: 12px;
  }
  #container {
    background: rgba(8,9,14,0.82);
    border: 1px solid rgba(80,130,255,0.55);
    border-radius: 10px;
    padding: 12px 16px;
    min-width: 260px;
    backdrop-filter: blur(6px);
  }
  #title {
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: rgba(180,210,255,0.8);
    margin-bottom: 6px;
  }
  #round {
    font-size: 11px;
    color: rgba(255,255,255,0.4);
    margin-bottom: 10px;
  }
  table { width:100%; border-collapse: collapse; }
  th {
    font-size: 9px;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: rgba(255,255,255,0.35);
    padding: 2px 4px;
    text-align: left;
    border-bottom: 1px solid rgba(255,255,255,0.08);
  }
  td {
    font-size: 12px;
    padding: 5px 4px;
    border-bottom: 1px solid rgba(255,255,255,0.05);
  }
  tr.first td { color: #FFD240; font-weight: 700; }
  tr.second td { color: #C8D8FF; }
  tr.third td { color: #C8A87A; }
  .rank { width: 22px; color: rgba(255,255,255,0.35); font-size:10px; }
  .pts { text-align:right; font-variant-numeric: tabular-nums; }
  .time { text-align:right; font-size:10px; color:rgba(255,255,255,0.4);
          font-variant-numeric: tabular-nums; }
</style>
</head>
<body>
<div id="container">
  <div id="title">MoAT Tournament</div>
  <div id="round">Loading...</div>
  <table>
    <thead><tr>
      <th class="rank">#</th>
      <th>Player</th>
      <th class="pts">Pts</th>
      <th class="pts">W</th>
      <th class="time">Best</th>
    </tr></thead>
    <tbody id="tbody"></tbody>
  </table>
</div>
<script>
function fmt(t) {
  if (t < 0) return '-';
  var s = Math.floor(t);
  return String(Math.floor(s/60)).padStart(2,'0') + ':' + String(s%60).padStart(2,'0');
}
function refresh() {
  fetch('/standings').then(r=>r.json()).then(d=>{
	document.getElementById('title').textContent = d.tournament || 'Wiki Races';
	var rnd = d.active ? 'Round ' + d.round + ' / ' + d.total_rounds : 'Wiki Races — Complete';
	if (d.between_rounds && d.active) rnd += ' — next round soon';
	document.getElementById('round').textContent = rnd;
	var rows = '';
	var cls = ['first','second','third'];
    (d.standings||[]).forEach(function(s,i){
	  var c = i < 3 ? cls[i] : '';
	  rows += '<tr class="' + c + '">' +
		'<td class="rank">' + s.rank + '</td>' +
		'<td>' + s.name + '</td>' +
		'<td class="pts">' + s.points + '</td>' +
		'<td class="pts">' + s.wins + '</td>' +
		'<td class="time">' + fmt(s.best_time) + '</td>' +
		'</tr>';
    });
	document.getElementById('tbody').innerHTML = rows;
  }).catch(function(err){
	console.error('Tournament standings refresh failed:', err);
  });
}
refresh();
setInterval(refresh, 3000);
</script>
</body>
</html>"""
