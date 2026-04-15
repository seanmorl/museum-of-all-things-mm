extends Node
class_name TriviaManager
## Generates trivia questions from Wikipedia/Wikidata content for exhibits.

signal trivia_ready(article_title: String, questions: Array)
signal trivia_failed(article_title: String, error: String)

const WIKIDATA_API: String = "https://www.wikidata.org/w/api.php?action=wbgetclaims&format=json&origin=*&entity="
const WIKIDATA_SEARCH: String = "https://www.wikidata.org/w/api.php?action=wbsearchentities&search=%s&language=en&format=json&origin=*&type=item"
const WIKIPEDIA_API: String = "https://en.wikipedia.org/api/rest_v1/page/summary/"

var _trivia_cache: Dictionary = {}
var _pending_requests: Dictionary = {}

var lang: String = "en"

func fetch_trivia(article_title: String) -> void:
	if _trivia_cache.has(article_title):
		trivia_ready.emit(article_title, _trivia_cache[article_title])
		return
	
	if _pending_requests.has(article_title):
		return
	
	_pending_requests[article_title] = true
	_fetch_wikidata_for_article(article_title)

func _fetch_wikidata_for_article(article_title: String) -> void:
	var url = WIKIDATA_SEARCH % article_title.replace(" ", "%20")
	
	var handle_result = func(result):
		_pending_requests.erase(article_title)
		if result[0] != OK:
			trivia_failed.emit(article_title, "Failed to search Wikidata")
			return
		
		var response_text = result[3].get_string_from_utf8()
		if response_text.is_empty():
			_generate_fallback_trivia(article_title)
			return
		
		var data = JSON.parse_string(response_text)
		if not data is Dictionary:
			_generate_fallback_trivia(article_title)
			return
		if not data.has("search") or not data.search is Array or data.search.is_empty():
			_generate_fallback_trivia(article_title)
			return
		
		var search_result = data.search[0]
		if not search_result is Dictionary or not search_result.has("id"):
			_generate_fallback_trivia(article_title)
			return
		
		var wikidata_id = search_result.id
		_fetch_wikidata_properties(article_title, wikidata_id)
	
	RequestSync.request_async(url).completed.connect(handle_result)

func _fetch_wikidata_properties(article_title: String, wikidata_id: String) -> void:
	var url = WIKIDATA_API + wikidata_id
	
	var handle_result = func(result):
		if result[0] != OK:
			_generate_fallback_trivia(article_title)
			return
		
		var response_text = result[3].get_string_from_utf8()
		if response_text.is_empty():
			_generate_fallback_trivia(article_title)
			return
		
		var data = JSON.parse_string(response_text)
		if not data is Dictionary:
			_generate_fallback_trivia(article_title)
			return
		if not data.has("claims") or not data.claims is Dictionary:
			_generate_fallback_trivia(article_title)
			return
		
		var questions = _generate_questions_from_claims(article_title, data.claims)
		_trivia_cache[article_title] = questions
		trivia_ready.emit(article_title, questions)
	
	RequestSync.request_async(url).completed.connect(handle_result)

func _generate_fallback_trivia(article_title: String) -> void:
	var url = WIKIPEDIA_API + article_title.replace(" ", "%20")
	
	var handle_result = func(result):
		_pending_requests.erase(article_title)
		if result[0] != OK:
			trivia_failed.emit(article_title, "Failed to fetch Wikipedia summary")
			return
		
		var response_text = result[3].get_string_from_utf8()
		if response_text.is_empty():
			trivia_failed.emit(article_title, "Empty response")
			return
		
		var data = JSON.parse_string(response_text)
		if not data:
			trivia_failed.emit(article_title, "Failed to parse Wikipedia response")
			return
		
		var extract = data.get("extract", "")
		var questions = _generate_questions_from_text(article_title, extract)
		_trivia_cache[article_title] = questions
		trivia_ready.emit(article_title, questions)
	
	RequestSync.request_async(url).completed.connect(handle_result)

func _generate_questions_from_claims(article_title: String, claims: Dictionary) -> Array:
	var questions: Array = []
	
	var fact_templates = [
		{
			"property": "P31",
			"question": "What type of %s is %s?",
			"wording": "is a type of"
		},
		{
			"property": "P571",
			"question": "When was %s founded or created?",
			"wording": "was founded"
		},
		{
			"property": "P17",
			"question": "What country is %s located in?",
			"wording": "is located in"
		},
		{
			"property": "P276",
			"question": "Where is %s located?",
			"wording": "is located in"
		},
		{
			"property": "P1376",
			"question": "What is the capital of %s?",
			"wording": "capital of"
		},
		{
			"property": "P1080",
			"question": "What is %s a part of?",
			"wording": "is part of"
		},
		{
			"property": "P39",
			"question": "What position did %s hold?",
			"wording": "held position"
		},
		{
			"property": "P106",
			"question": "What profession does %s have?",
			"wording": "profession"
		},
		{
			"property": "P27",
			"question": "What is the nationality of %s?",
			"wording": "nationality"
		},
		{
			"property": "P569",
			"question": "When was %s born?",
			"wording": "born"
		},
		{
			"property": "P570",
			"question": "When did %s die?",
			"wording": "died"
		},
		{
			"property": "P40",
			"question": "Who is the child of %s?",
			"wording": "child of"
		},
		{
			"property": "P22",
			"question": "Who is the father of %s?",
			"wording": "father"
		},
		{
			"property": "P25",
			"question": "Who is the mother of %s?",
			"wording": "mother"
		},
		{
			"property": "P19",
			"question": "Where was %s born?",
			"wording": "born in"
		},
		{
			"property": "P20",
			"question": "Where did %s die?",
			"wording": "died in"
		},
		{
			"property": "P264",
			"question": "What record label did %s work with?",
			"wording": "record label"
		},
		{
			"property": "P86",
			"question": "Who composed the music for %s?",
			"wording": "composer"
		},
		{
			"property": "P161",
			"question": "Who cast in %s?",
			"wording": "cast in"
		},
		{
			"property": "P57",
			"question": "Who directed %s?",
			"wording": "directed"
		},
		{
			"property": "P180",
			"question": "What depicts %s?",
			"wording": "depicts"
		},
		{
			"property": "P170",
			"question": "Who created %s?",
			"wording": "created"
		},
		{
			"property": "P571",
			"question": "What year was %s created?",
			"wording": "created in"
		},
		{
			"property": "P495",
			"question": "What country did %s originate from?",
			"wording": "originates from"
		},
		{
			"property": "P241",
			"question": "What army does %s belong to?",
			"wording": "army"
		},
		{
			"property": "P102",
			"question": "What political party does %s belong to?",
			"wording": "political party"
		},
		{
			"property": "P6",
			"question": "Who is the head of government of %s?",
			"wording": "head of government"
		},
		{
			"property": "P35",
			"question": "Who is the head of state of %s?",
			"wording": "head of state"
		},
		{
			"property": "P1128",
			"question": "How many employees does %s have?",
			"wording": "employees"
		},
		{
			"property": "P2132",
			"question": "What is the population of %s?",
			"wording": "population"
		},
		{
			"property": "P38",
			"question": "What is the currency of %s?",
			"wording": "currency"
		},
		{
			"property": "P37",
			"question": "What language is official in %s?",
			"wording": "official language"
		},
		{
			"property": "P1908",
			"question": "What is the motto of %s?",
			"wording": "motto"
		},
		{
			"property": "P1566",
			"question": "What is the population of %s?",
			"wording": "population"
		}
	]
	
	var used_properties: Array = []
	
	for i in range(min(5, fact_templates.size())):
		var template = fact_templates[i]
		var property = template["property"]
		
		if not claims.has(property):
			continue
		
		if property in used_properties:
			continue
		used_properties.append(property)
		
		var claim_list: Array = claims.get(property, [])
		if claim_list.is_empty():
			continue
		
		if not claim_list[0] is Dictionary:
			continue
		
		var main_claim: Dictionary = claim_list[0]
		if not main_claim.has("mainsnak"):
			continue
		
		var mainsnak = main_claim.mainsnak
		if not mainsnak.has("datavalue"):
			continue
		
		var datavalue = mainsnak.datavalue
		var formatted_value = _format_datavalue(datavalue)
		if formatted_value == "":
			continue
		
		var question_text = template["question"]
		if question_text.count("%s") == 2:
			question_text = question_text % [formatted_value, article_title]
		elif question_text.count("%s") == 1:
			question_text = question_text % formatted_value
		else:
			continue  # Skip if no placeholders
		
		var correct_answer = formatted_value
		var wrong_answers = _generate_wrong_answers(property, formatted_value)
		
		if wrong_answers.size() >= 3:
			questions.append({
				"question": question_text,
				"correct": correct_answer,
				"wrong": wrong_answers.slice(0, 3),
				"type": "multiple_choice"
			})
	
	return questions

func _format_datavalue(datavalue: Dictionary) -> String:
	var type = datavalue.get("type", "")
	var value = datavalue.get("value", {})
	
	match type:
		"string":
			return str(value)
		"wikibase-entityid":
			return str(value.get("id", ""))
		"quantity":
			var amount = str(value.get("amount", "0"))
			var unit = str(value.get("unit", ""))
			if unit and unit != "1":
				var parts = unit.split("/")
				var unit_name = parts[-1] if parts.size() > 0 else unit
				return "%s %s" % [amount, unit_name]
			return amount
		"time":
			var time_val = str(value.get("time", ""))
			if time_val.begins_with("+"):
				time_val = time_val.substr(1)
			var year = time_val.split("-")[0]
			return year
		"monolingualtext":
			return str(value.get("text", ""))
		"globecoordinate":
			return "%s, %s" % [value.get("latitude", 0), value.get("longitude", 0)]
	
	return str(value)

func _generate_wrong_answers(property: String, correct_answer: String) -> Array:
	var generic_wrong: Array = []
	
	match property:
		"P31":  # instance of
			generic_wrong = ["country", "city", "person", "company", "book", "film", "song", "animal", "food", "weapon"]
		"P17", "P276":  # country, location
			generic_wrong = ["France", "Germany", "Japan", "Brazil", "India", "Australia", "Canada", "Russia", "China", "Italy"]
		"P571":  # founded
			generic_wrong = ["1990", "1850", "2000", "1800", "1975", "1960", "1920", "2010", "1945", "1888"]
		"P569", "P570":  # birth/death
			generic_wrong = ["1900", "1950", "1880", "1920", "1980", "1850", "2000", "1910", "1870", "1930"]
		"P106":  # profession
			generic_wrong = ["doctor", "lawyer", "teacher", "engineer", "artist", "musician", "actor", "writer", "scientist", "politician"]
		"P27":  # nationality
			generic_wrong = ["American", "British", "French", "German", "Japanese", "Italian", "Spanish", "Canadian", "Australian", "Indian"]
		"P19", "P20":  # birth/death place
			generic_wrong = ["New York", "London", "Paris", "Tokyo", "Berlin", "Rome", "Sydney", "Toronto", "Mumbai", "Cairo"]
		"P161":  # cast
			generic_wrong = ["Tom Hanks", "Leonardo DiCaprio", "Scarlett Johansson", "Brad Pitt", "Jennifer Lawrence", "Robert Downey Jr.", "Emma Stone", "Chris Evans", "Mark Ruffalo", "Tom Holland"]
		"P57":  # director
			generic_wrong = ["Steven Spielberg", "Christopher Nolan", "James Cameron", "Quentin Tarantino", "Martin Scorsese", "Ridley Scott", "Peter Jackson", "George Lucas", "Francis Ford Coppola", "Tim Burton"]
		"P37":  # language
			generic_wrong = ["English", "Spanish", "French", "German", "Chinese", "Japanese", "Russian", "Portuguese", "Italian", "Arabic"]
		"P38":  # currency
			generic_wrong = ["USD", "GBP", "EUR", "JPY", "CNY", "RUB", "INR", "CAD", "AUD", "CHF"]
		"P2132":  # population
			generic_wrong = ["1000000", "5000000", "10000000", "50000", "100000", "500000", "2000000", "8000000", "3000000", "15000000"]
		_:
			generic_wrong = ["Unknown", "Various", "None", "Multiple", "Other", "N/A", "None of the above"]
	
	generic_wrong.shuffle()
	return generic_wrong

func _generate_questions_from_text(article_title: String, extract: String) -> Array:
	var questions: Array = []
	
	if extract.is_empty():
		return questions
	
	var sentences = extract.split(".", false)
	if sentences.size() < 2:
		return questions
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for i in range(min(3, sentences.size() - 1)):
		var sentence = sentences[i].strip_edges()
		if sentence.length() < 20:
			continue
		
		var words = sentence.split(" ", false)
		if words.size() < 5:
			continue
		
		var key_index = rng.randi() % words.size()
		var key_word = words[key_index]
		key_word = key_word.trim_prefix("(").trim_suffix(")")
		key_word = key_word.trim_prefix("[").trim_suffix("]")
		
		if key_word.length() < 4:
			continue
		
		var question = sentence.replace(key_word, "_______")
		question = "Fill in the blank: " + question + "?"
		
		questions.append({
			"question": question,
			"correct": key_word,
			"wrong": [],
			"type": "fill_blank"
		})
	
	return questions

func get_cached_trivia(article_title: String) -> Array:
	return _trivia_cache.get(article_title, [])

func clear_cache() -> void:
	_trivia_cache.clear()
