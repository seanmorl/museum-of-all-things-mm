class_name ExhibitMood
extends RefCounted
## Determines exhibit mood from Wikipedia categories.
## Mood affects fog color, fog density, ambient light color, decoration bias, and particles.

enum Mood { DEFAULT, HISTORY, SCIENCE, NATURE, ASTRO, MEDIA, ART, GEOGRAPHY, PHILOSOPHY, SPORTS, FOOD, POLITICS, ECONOMY, MYSTERY }

const MOOD_KEYWORDS: Dictionary = {
	Mood.HISTORY: ["history", "century", "ancient", "medieval", "war", "empire", "dynasty", "civilization", "kingdom", "revolution", "colonial", "heritage", "archaeology", "monarchy", "crusade", "invasion", "battle", "military", "monument", "cathedral", "castle", "antiquity"],
	Mood.SCIENCE: ["science", "physics", "chemistry", "biology", "mathematics", "technology", "engineering", "medicine", "computer", "algorithm", "game", "mechanics", "system", "theory", "research", "laboratory", "experiment", "quantum", "neuroscience", "psychology", "statistics", "formula", "equation", "genetics", "evolution", "molecular"],
	Mood.NATURE: ["nature", "species", "animal", "plant", "ecology", "forest", "ocean", "wildlife", "bird", "fish", "insect", "mammal", "flora", "fauna", "environment", "habitat", "botanical", "conservation", "ecosystem", "organism", "marine", "tropical", "endangered", "extinction"],
	Mood.ASTRO: ["astronomy", "space", "planet", "star", "galaxy", "cosmos", "solar", "lunar", "orbit", "nasa", "telescope", "nebula", "universe", "cosmic", "astronaut", "constellation", "comet", "asteroid", "observatory", "satellite", "astrophysics"],
	Mood.MEDIA: ["film", "television", "album", "song", "music", "novel", "literature", "actor", "actress", "director", "band", "soundtrack", "video game", "gaming", "entertainment", "broadcast", "cinema", "movie", "series", "episode", "franchise", "comic", "animation", "anime", "manga", "pop culture"],
	Mood.ART: ["art", "painting", "sculpture", "artist", "museum", "gallery", "portrait", "landscape", "impressionism", "renaissance", "modern art", "abstract", "photography", "design", "architecture", "craft", "decorative", "vanguard", "surrealism", "baroque", "rococo"],
	Mood.GEOGRAPHY: ["geography", "mountain", "river", "lake", "island", "coast", "desert", "volcano", "continent", "region", "climate", "terrain", "landscape", "geological", "tectonic", "polar", "temperate", "atlas", "map", "canyon", "valley", "peninsula"],
	Mood.PHILOSOPHY: ["philosophy", "religion", "theology", "ethics", "metaphysics", "logic", "theology", "spirituality", "mythology", "consciousness", "existence", "doctrine", "ideology", "rationalism", "wisdom", "belief", "meditation", "enlightenment", "monk", "monastic", "monastery", "cloister", "hermit", "abbey", "friar", "nun", "religious", "saint", "order", "vow", "abbot", "holy", "sacred", "prayer", "worship", "contemplative", "ascetic", "devotion", "canonization", "martyr", "beatification"],
	Mood.SPORTS: ["sport", "football", "soccer", "basketball", "olympics", "athlete", "tennis", "cricket", "baseball", "swimming", "track", "championship", "tournament", "league", "stadium", "gym", "skiing", "hockey", "golf", "cycling", "martial", "racing"],
	Mood.FOOD: ["food", "cuisine", "cooking", "recipe", "restaurant", "chef", "bread", "wine", "beer", "vegetable", "fruit", "spice", "ingredient", "dish", "culinary", "pastry", "dairy", "seafood", "beverage", "alcohol", "chocolate", "coffee", "tea", "sauce"],
	Mood.POLITICS: ["politics", "government", "president", "parliament", "congress", "election", "democracy", "diplomacy", "treaty", "policy", "legislation", "minister", "senator", "governor", "ambassador", "constitution", "law", "justice", "reform", "activist", "suffrage"],
	Mood.ECONOMY: ["economy", "finance", "bank", "trade", "commerce", "industry", "market", "stock", "currency", "business", "corporation", "investment", "wealth", "fiscal", "monetary", "capital", "revenue", "profit", "tax", "infrastructure", "manufacturing"],
	Mood.MYSTERY: ["mystery", "legend", "folklore", "myth", "supernatural", "ghost", "conspiracy", "unsolved", "paranormal", "occult", "cryptid", "witchcraft", "magic", "haunted", "alien", "ufo", "cryptozoology", "divination", "prophecy"],
}

const MOOD_FOG_COLOR: Dictionary = {
	Mood.DEFAULT: Color.WHITE,
	Mood.HISTORY: Color(1.0, 0.85, 0.6),
	Mood.SCIENCE: Color(0.75, 0.88, 1.0),
	Mood.NATURE: Color(0.7, 0.95, 0.7),
	Mood.ASTRO: Color(0.5, 0.4, 0.8),
	Mood.MEDIA: Color(1.0, 0.92, 0.8),
	Mood.ART: Color(1.0, 0.95, 0.9),
	Mood.GEOGRAPHY: Color(0.8, 0.9, 0.95),
	Mood.PHILOSOPHY: Color(0.9, 0.7, 0.3),
	Mood.SPORTS: Color(1.0, 0.95, 0.85),
	Mood.FOOD: Color(1.0, 0.9, 0.75),
	Mood.POLITICS: Color(0.85, 0.85, 0.9),
	Mood.ECONOMY: Color(1.0, 0.95, 0.7),
	Mood.MYSTERY: Color(0.6, 0.55, 0.7),
}

const MOOD_FOG_DEPTH: Dictionary = {
	Mood.DEFAULT: 10.0,
	Mood.HISTORY: 12.0,
	Mood.SCIENCE: 8.0,
	Mood.NATURE: 14.0,
	Mood.ASTRO: 6.0,
	Mood.MEDIA: 10.0,
	Mood.ART: 11.0,
	Mood.GEOGRAPHY: 15.0,
	Mood.PHILOSOPHY: 11.0,
	Mood.SPORTS: 10.0,
	Mood.FOOD: 10.0,
	Mood.POLITICS: 10.0,
	Mood.ECONOMY: 10.0,
	Mood.MYSTERY: 8.0,
}

const MOOD_AMBIENT_COLOR: Dictionary = {
	Mood.DEFAULT: Color(1.0, 1.0, 1.0),
	Mood.HISTORY: Color(1.0, 0.9, 0.7),
	Mood.SCIENCE: Color(0.8, 0.9, 1.0),
	Mood.NATURE: Color(0.8, 1.0, 0.8),
	Mood.ASTRO: Color(0.6, 0.5, 0.9),
	Mood.MEDIA: Color(1.0, 0.95, 0.85),
	Mood.ART: Color(1.0, 0.97, 0.92),
	Mood.GEOGRAPHY: Color(0.85, 0.92, 0.97),
	Mood.PHILOSOPHY: Color(0.9, 0.7, 0.3),
	Mood.SPORTS: Color(1.0, 0.97, 0.9),
	Mood.FOOD: Color(1.0, 0.92, 0.8),
	Mood.POLITICS: Color(0.88, 0.88, 0.93),
	Mood.ECONOMY: Color(1.0, 0.97, 0.75),
	Mood.MYSTERY: Color(0.65, 0.6, 0.75),
}

const MOOD_AMBIENT_ENERGY: Dictionary = {
	Mood.DEFAULT: 0.15,
	Mood.HISTORY: 0.12,
	Mood.SCIENCE: 0.13,
	Mood.NATURE: 0.1,
	Mood.ASTRO: 0.08,
	Mood.MEDIA: 0.13,
	Mood.ART: 0.15,
	Mood.GEOGRAPHY: 0.15,
	Mood.PHILOSOPHY: 0.12,
	Mood.SPORTS: 0.18,
	Mood.FOOD: 0.13,
	Mood.POLITICS: 0.13,
	Mood.ECONOMY: 0.15,
	Mood.MYSTERY: 0.06,
}

# Subtle wall color tints per mood (multiplied against wall material)
const MOOD_WALL_TINT: Dictionary = {
	Mood.DEFAULT: Color(1.0, 1.0, 1.0),      # Neutral white
	Mood.HISTORY: Color(1.0, 0.92, 0.8),      # Warm parchment
	Mood.SCIENCE: Color(0.88, 0.93, 1.0),     # Cool clinical
	Mood.NATURE: Color(0.9, 0.97, 0.88),      # Soft sage
	Mood.ASTRO: Color(0.85, 0.82, 0.95),      # Deep twilight
	Mood.MEDIA: Color(1.0, 0.95, 0.85),       # Warm theatrical
	Mood.ART: Color(1.0, 0.97, 0.93),         # Gallery white
	Mood.GEOGRAPHY: Color(0.9, 0.95, 0.97),   # Sky blue
	Mood.PHILOSOPHY: Color(0.95, 0.8, 0.4),    # Saffron robe warmth
	Mood.SPORTS: Color(1.0, 0.97, 0.9),       # Energetic warm
	Mood.FOOD: Color(1.0, 0.93, 0.82),        # Kitchen warmth
	Mood.POLITICS: Color(0.92, 0.92, 0.95),   # Institutional gray-blue
	Mood.ECONOMY: Color(1.0, 0.97, 0.8),      # Gold tinge
	Mood.MYSTERY: Color(0.75, 0.72, 0.82),    # Shadowy purple
}


static func compute_mood(categories: Array) -> int:
	var scores: Dictionary = {}
	for mood: int in MOOD_KEYWORDS:
		scores[mood] = 0

	for category: String in categories:
		var lower: String = category.to_lower()
		for mood: int in MOOD_KEYWORDS:
			for keyword: String in MOOD_KEYWORDS[mood]:
				if lower.find(keyword) >= 0:
					scores[mood] += 1

	var best_mood: int = Mood.DEFAULT
	var best_score: int = 0
	for mood: int in scores:
		if scores[mood] > best_score:
			best_score = scores[mood]
			best_mood = mood

	# Need at least 2 keyword hits to assign a mood
	if best_score < 2:
		return Mood.DEFAULT
	return best_mood


static func get_fog_color(mood: int) -> Color:
	return MOOD_FOG_COLOR.get(mood, MOOD_FOG_COLOR[Mood.DEFAULT])


static func get_fog_depth(mood: int) -> float:
	return MOOD_FOG_DEPTH.get(mood, MOOD_FOG_DEPTH[Mood.DEFAULT])


static func get_ambient_color(mood: int) -> Color:
	return MOOD_AMBIENT_COLOR.get(mood, MOOD_AMBIENT_COLOR[Mood.DEFAULT])


static func get_ambient_energy(mood: int) -> float:
	return MOOD_AMBIENT_ENERGY.get(mood, MOOD_AMBIENT_ENERGY[Mood.DEFAULT])


static func get_adjusted_ambient_energy(mood: int, is_dark_mode: bool) -> float:
	var base = get_ambient_energy(mood)
	if is_dark_mode:
		return clamp(base * 0.7, 0.15, 0.5)
	else:
		return clamp(base * 1.8, 0.6, 1.5)


static func prefers_pool(mood: int) -> bool:
	return mood == Mood.ASTRO or mood == Mood.NATURE


static func prefers_planter(mood: int) -> bool:
	return mood == Mood.NATURE or mood == Mood.HISTORY

static func get_wall_tint(mood: int) -> Color:
	return MOOD_WALL_TINT.get(mood, MOOD_WALL_TINT[Mood.DEFAULT])



static func prefers_verticality(mood: int) -> bool:
	## Returns true if this mood prefers vertical architectural features (atriums)
	return mood == Mood.HISTORY or mood == Mood.MEDIA


static func prefers_symmetry(mood: int) -> bool:
	## Returns true if this mood prefers symmetrical grand halls
	return mood == Mood.HISTORY or mood == Mood.SCIENCE
