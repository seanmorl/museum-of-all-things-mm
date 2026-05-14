extends Node
class_name DailyChallengeManager
## Manages the Daily Challenge mode: a shared article target that rotates every UTC midnight.
## The target is seeded from today's date so all players worldwide get the same challenge.
## Streaks and best times are persisted locally via SettingsManager.

signal challenge_ready(target_article: String, start_article: String)
signal challenge_failed(error: String)
signal challenge_started
signal challenge_completed(time_seconds: float, is_best: bool)

## UI nodes managed by this manager (extracted from Main.gd)
var _hud: CanvasLayer = null
var _leaderboard: Node = null


func initialize_ui(main: Node) -> void:
	var hud: DailyChallengeHUD = load("res://scenes/ui/DailyChallengeHUD.gd").new()
	hud.name = "DailyChallengeHUD"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "DailyChallengeHUDLayer"
	hud_layer.layer = 20
	main.add_child(hud_layer)
	hud_layer.add_child(hud)
	_hud = hud_layer

	_leaderboard = load("res://scenes/ui/DailyChallengeLeaderboard.gd").new()
	_leaderboard.name = "DailyChallengeLeaderboard"
	main.add_child(_leaderboard)

	hud.init(self, _leaderboard)


func get_hud() -> CanvasLayer:
	return _hud


func get_leaderboard() -> Node:
	return _leaderboard


func hide_all() -> void:
	if _hud and _hud.has_method("hide_all"):
		_hud.hide_all()


func hud_is_open() -> bool:
	if _hud and _hud.has_method("is_open"):
		return _hud.is_open()
	return false


func hud_open() -> void:
	if _hud and _hud.has_method("open"):
		_hud.open()


func hud_close() -> void:
	if _hud and _hud.has_method("close"):
		_hud.close()


func show_strip() -> void:
	if _hud and _hud.has_method("show_strip"):
		_hud.show_strip()


func show_results(time_sec: float, is_best: bool) -> void:
	if _hud and _hud.has_method("show_results"):
		_hud.show_results(time_sec, is_best)


func submit_score(name: String, elapsed: float) -> void:
	if _leaderboard and _leaderboard.has_method("submit_score"):
		_leaderboard.submit_score(name, elapsed)


func init_board(board: Node, manager: Node, leaderboard: Node) -> void:
	if board and board.has_method("init"):
		board.init(manager, leaderboard)


func is_board_ready() -> bool:
	return _leaderboard != null

## Wikipedia endpoint for deterministic "article of the day" via featured content
const FEATURED_API: String = "https://en.wikipedia.org/api/rest_v1/feed/featured/%d/%02d/%02d"
## Fallback: use a seeded random from a curated pool when featured API fails
const FALLBACK_SEED_POOL: Array = [
	"Photosynthesis", "Roman Empire", "Black hole", "Evolution",
	"Great Wall of China", "Marie Curie", "Jazz", "Olympic Games",
	"Internet", "French Revolution", "DNA", "Beethoven",
	"Sahara Desert", "Apollo 11", "Leonardo da Vinci", "Magna Carta",
	"Periodic table", "Shakespeare", "Taj Mahal", "Theory of relativity",
	"Silk Road", "Gutenberg", "Vaccination", "Renaissance",
	"Stonehenge", "Isaac Newton", "Cleopatra", "Printing press",
	"World War II", "Electricity", "Gravity", "Democracy",
	"Microscope", "Solar system", "Buddhism", "Steam engine",
	"Pyramid", "Fibonacci sequence", "Compass", "Quantum mechanics"
]

var _today_key: String = ""           ## "YYYY-MM-DD"
var _target_article: String = ""
var _start_article: String = ""
var _is_active: bool = false
var _is_loading: bool = false
var _timer_start: float = 0.0
var _elapsed: float = 0.0
var _fetch_callback: Callable = func(_result: Array): pass  ## Prevents lambda GC during async fetch
var _pending_request: Variant = null  ## Hold reference to ResponseAsync to prevent GC

func _ready() -> void:
	_today_key = _get_today_key()

# ── Public API ────────────────────────────────────────────────────────────────

func get_today_key() -> String:
	return _today_key

func get_target_article() -> String:
	return _target_article

func get_start_article() -> String:
	return _start_article

func is_active() -> bool:
	return _is_active

func is_loading() -> bool:
	return _is_loading

func already_completed_today() -> bool:
	var saved := _load_record()
	return saved.get("last_completed", "") == _today_key

func get_streak() -> int:
	return _load_record().get("streak", 0)

func get_best_time() -> float:
	return float(_load_record().get("best_time", 0.0))

func get_elapsed() -> float:
	if _is_active:
		return Time.get_ticks_msec() / 1000.0 - _timer_start
	return _elapsed

## Fetch today's target + a random start article then emit challenge_ready.
func start_challenge() -> void:
	if _is_loading:
		Log.warn("DailyChallengeManager", "start_challenge called while already loading")
		return
	_is_loading = true
	_today_key = _get_today_key()
	Log.info("DailyChallengeManager", "Starting daily challenge for %s" % _today_key)
	_fetch_todays_target()

## Call when the player reaches the target article.
func complete_challenge() -> void:
	if not _is_active:
		return
	_elapsed = Time.get_ticks_msec() / 1000.0 - _timer_start
	_is_active = false

	var rec := _load_record()
	var prev_best: float = float(rec.get("best_time", 0.0))
	var is_best: bool = prev_best <= 0.0 or _elapsed < prev_best

	# Update streak
	var last_date: String = rec.get("last_completed", "")
	var yesterday: String = _get_yesterday_key()
	if last_date == yesterday:
		rec["streak"] = int(rec.get("streak", 0)) + 1
	elif last_date != _today_key:
		rec["streak"] = 1  # broke streak or first ever

	rec["last_completed"] = _today_key
	rec["last_time"] = _elapsed
	if is_best:
		rec["best_time"] = _elapsed
	_save_record(rec)

	challenge_completed.emit(_elapsed, is_best)

## Begin the in-game timer (called once the race actually starts moving).
func begin_timer() -> void:
	_timer_start = Time.get_ticks_msec() / 1000.0
	_is_active = true
	challenge_started.emit()

# ── Fetching ──────────────────────────────────────────────────────────────────

func _fetch_todays_target() -> void:
	var t := Time.get_datetime_dict_from_system()
	var url := FEATURED_API % [t.year, t.month, t.day]
	Log.info("DailyChallengeManager", "Fetching today's target from: %s" % url)

	_fetch_callback = func(result: Array):
		Log.info("DailyChallengeManager", "Fetch callback called: result[0]=%s, result[1]=%s" % [str(result[0]), str(result[1])])
		_pending_request = null  # Release reference after callback completes
		if result[0] != OK:
			Log.error("DailyChallengeManager", "Failed to fetch today's target (HTTP request error %s), using fallback" % str(result[0]))
			_use_fallback_target()
			return
		var text: String = result[3].get_string_from_utf8()
		if text.is_empty():
			Log.error("DailyChallengeManager", "Empty response from Wikipedia API, using fallback")
			_use_fallback_target()
			return
		var data = JSON.parse_string(text)
		if not data is Dictionary:
			Log.error("DailyChallengeManager", "Failed to parse Wikipedia API response, using fallback")
			_use_fallback_target()
			return
		# Wikipedia featured content puts the article of the day under "tfa"
		var tfa = data.get("tfa", {})
		var title: String = tfa.get("title", "") if tfa is Dictionary else ""
		if title.strip_edges() == "":
			Log.error("DailyChallengeManager", "No featured article found in response, using fallback")
			_use_fallback_target()
			return
		Log.info("DailyChallengeManager", "Fetched today's target: %s" % title)
		_target_article = title
		_fetch_start_article()

	_pending_request = RequestSync.request_async(url)
	_pending_request.completed.connect(_fetch_callback)

func _use_fallback_target() -> void:
	## Derive a deterministic article from today's date using a seeded index.
	var t := Time.get_datetime_dict_from_system()
	var seed_val: int = t.year * 10000 + t.month * 100 + t.day
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var idx: int = rng.randi() % FALLBACK_SEED_POOL.size()
	_target_article = FALLBACK_SEED_POOL[idx]
	_fetch_start_article()

func _fetch_start_article() -> void:
	## Fetch a separate random article as the starting room.
	## We use ExhibitFetcher so the room actually loads correctly.
	Log.info("DailyChallengeManager", "Fetching start article for daily challenge")
	ExhibitFetcher.random_complete.connect(_on_start_article_ready, CONNECT_ONE_SHOT)
	ExhibitFetcher.fetch_random({"daily_challenge": true})

func _on_start_article_ready(title: Variant, context: Variant) -> void:
	Log.info("DailyChallengeManager", "_on_start_article_ready called: title=%s, context=%s" % [str(title), str(context)])
	if not (context is Dictionary) or not context.get("daily_challenge", false):
		# Not ours — reconnect for next call (shouldn't happen with ONE_SHOT but be safe)
		Log.warn("DailyChallengeManager", "_on_start_article_ready: context mismatch, ignoring")
		return
	if title == null or str(title).strip_edges() == "":
		Log.error("DailyChallengeManager", "Could not fetch a starting article (title was empty)")
		_is_loading = false
		challenge_failed.emit("Could not fetch a starting article.")
		return

	Log.info("DailyChallengeManager", "Daily challenge ready: %s -> %s" % [title, _target_article])
	_start_article = str(title)
	_is_loading = false
	challenge_ready.emit(_target_article, _start_article)

# ── Persistence ───────────────────────────────────────────────────────────────

func _load_record() -> Dictionary:
	var saved = SettingsManager.get_settings("daily_challenge")
	return saved if saved is Dictionary else {}

func _save_record(rec: Dictionary) -> void:
	SettingsManager.save_settings("daily_challenge", rec)

# ── Date helpers ──────────────────────────────────────────────────────────────

func _get_today_key() -> String:
	var t := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [t.year, t.month, t.day]

func _get_yesterday_key() -> String:
	var unix: int = Time.get_unix_time_from_system() as int - 86400
	var t := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [t.year, t.month, t.day]
