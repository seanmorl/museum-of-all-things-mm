extends Node
## WikipediaTrending - Fetches most viewed Wikipedia articles.
##
## Uses the Wikimedia Pageviews API to get top articles by view count.
## API: https://wikimedia.org/api/rest_v1/metrics/pageviews/top/en.wikipedia.org/{access}/{date}

signal trending_updated(articles: Array)
signal fetch_failed(error: String)

var _http_request: HTTPRequest = null
var _trending_articles: Array = []
var _last_fetch_date: String = ""
var _is_fetching: bool = false

# Cache file path
const CACHE_FILE := "user://wikipedia_trending.cache"
const CACHE_DURATION_HOURS := 6  # Refresh every 6 hours


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.request_completed.connect(_on_request_completed)
	add_child(_http_request)

	# Try to load from cache first
	_load_from_cache()


func fetch_trending() -> void:
	if _is_fetching:
		return

	var date_dict := _get_date_dict()

	# Check if we have recent cached data
	if _last_fetch_date == date_dict.date_str and not _trending_articles.is_empty():
		trending_updated.emit(_trending_articles)
		return

	_is_fetching = true
	var url := "https://wikimedia.org/api/rest_v1/metrics/pageviews/top/en.wikipedia.org/all-access/%04d/%02d/%02d" % [date_dict.year, date_dict.month, date_dict.day]
	push_warning("[WikipediaTrending] Fetching: ", url)
	var error = _http_request.request(url)
	if error != OK:
		push_warning("[WikipediaTrending] Request failed, trying fallback date")
		# Try fallback date (2 days ago)
		var fallback := _get_fallback_date_dict()
		var fallback_url := "https://wikimedia.org/api/rest_v1/metrics/pageviews/top/en.wikipedia.org/all-access/%04d/%02d/%02d" % [fallback.year, fallback.month, fallback.day]
		error = _http_request.request(fallback_url)
		if error != OK:
			_is_fetching = false
			_use_hardcoded_fallback()


func get_trending_articles() -> Array:
	return _trending_articles.duplicate()


func get_top_article() -> String:
	if _trending_articles.is_empty():
		return ""
	return _trending_articles[0]


func _get_date_dict() -> Dictionary:
	# Get yesterday's date (today's stats aren't complete yet)
	var dict = Time.get_datetime_dict_from_system()
	var day = dict.day - 1
	var month = dict.month
	var year = dict.year

	if day < 1:
		# Go to previous month
		month -= 1
		if month < 1:
			month = 12
			year -= 1
		# Get last day of previous month
		var days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
		# Handle leap year
		if month == 2 and (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)):
			days_in_month[1] = 29
		day = days_in_month[month - 1]

	return {
		"year": year,
		"month": month,
		"day": day,
		"date_str": "%04d%02d%02d" % [year, month, day]
	}


func _get_fallback_date_dict() -> Dictionary:
	# Get 2 days ago as fallback
	var dict = Time.get_datetime_dict_from_system()
	var day = dict.day - 2
	var month = dict.month
	var year = dict.year

	if day < 1:
		month -= 1
		if month < 1:
			month = 12
			year -= 1
		var days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
		if month == 2 and (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)):
			days_in_month[1] = 29
		day = days_in_month[month - 1]

	return {
		"year": year,
		"month": month,
		"day": day,
		"date_str": "%04d%02d%02d" % [year, month, day]
	}


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_fetching = false

	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[WikipediaTrending] Request failed with result: ", result)
		# Try fallback date
		_try_fallback_date()
		return
	
	if response_code != 200:
		push_warning("[WikipediaTrending] HTTP error: ", response_code)
		# Try fallback date
		_try_fallback_date()
		return

	var json := JSON.new()
	var error = json.parse(body.get_string_from_utf8())
	if error != OK:
		push_warning("[WikipediaTrending] JSON parse error at line: ", json.get_error_line())
		fetch_failed.emit("JSON parse error")
		return

	var data = json.data
	if not data:
		fetch_failed.emit("No data in response")
		return
	
	# API returns nested structure: items[0].articles
	var items = data.get("items", [])
	if items.is_empty():
		fetch_failed.emit("Empty items array")
		return
	
	var articles_data = items[0].get("articles", [])
	if articles_data.is_empty():
		fetch_failed.emit("No articles in response")
		return

	_parse_articles(articles_data)


func _try_fallback_date() -> void:
	var fallback_date := _get_fallback_date_dict()
	push_warning("[WikipediaTrending] Trying fallback date: ", fallback_date.date_str)
	var url := "https://wikimedia.org/api/rest_v1/metrics/pageviews/top/en.wikipedia.org/all-access/%04d/%02d/%02d" % [fallback_date.year, fallback_date.month, fallback_date.day]
	var error = _http_request.request(url)
	if error != OK:
		_is_fetching = false
		_use_hardcoded_fallback()


func _use_hardcoded_fallback() -> void:
	# If API is completely unavailable, use interesting fallback articles
	_trending_articles = [
		"Octopus",
		"Honey",
		"Venus",
		"Anglo-Zanzibar War",
		"Shark",
		"Tree",
		"Milky Way",
		"Great Pyramid of Giza",
		"Nintendo",
		"University of Oxford",
	]
	push_warning("[WikipediaTrending] Using hardcoded fallback articles")
	trending_updated.emit(_trending_articles)


func _parse_articles(items: Array) -> void:
	_trending_articles.clear()
	
	for item in items:
		if _trending_articles.size() >= 10:
			break
		
		var article = item.article
		# Filter out Wikipedia internal pages
		if article.begins_with("Special:") or \
		   article.begins_with("Main_Page") or \
		   article.begins_with("Portal:") or \
		   article.begins_with("Help:") or \
		   article.begins_with("File:") or \
		   article.begins_with("Category:") or \
		   article.begins_with("Template:") or \
		   article.begins_with("Wikipedia:"):
			continue
		
		# Decode URL-encoded article titles
		article = article.replace("_", " ")
		_trending_articles.append(article)
	
	if _trending_articles.is_empty():
		fetch_failed.emit("No valid articles found")
		return

	var date_dict := _get_date_dict()
	_last_fetch_date = date_dict.date_str
	_save_to_cache()
	trending_updated.emit(_trending_articles)


func _save_to_cache() -> void:
	var date_dict := _get_date_dict()
	var file = FileAccess.open(CACHE_FILE, FileAccess.WRITE)
	if file:
		var data = {
			"date": date_dict.date_str,
			"articles": _trending_articles
		}
		file.store_string(JSON.stringify(data))


func _load_from_cache() -> void:
	if not FileAccess.file_exists(CACHE_FILE):
		return

	var file = FileAccess.open(CACHE_FILE, FileAccess.READ)
	if file:
		var json := JSON.new()
		var error = json.parse(file.get_as_text())
		if error == OK:
			var data = json.data
			if data and "articles" in data and "date" in data:
				_last_fetch_date = data.date
				_trending_articles = data.articles
				trending_updated.emit(_trending_articles)
