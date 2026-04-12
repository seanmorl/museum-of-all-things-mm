class_name ExhibitStyle
extends RefCounted

# Base floor types (must match mesh library indices)
static var FLOOR_LIST: Array[int] = [Constants.FLOOR_WOOD, Constants.FLOOR_MARBLE, Constants.FLOOR_CARPET]

# Mood-biased floor weights: each mood prefers certain floor types
# Weights are [wood, marble, carpet] — higher weight = more likely
static var FLOOR_WEIGHTS: Dictionary = {
	ExhibitMood.Mood.DEFAULT:  [3, 3, 2],  # Balanced
	ExhibitMood.Mood.HISTORY:  [4, 5, 1],  # Prefers marble (classical) and wood
	ExhibitMood.Mood.SCIENCE:  [2, 5, 2],  # Prefers marble (clean, clinical)
	ExhibitMood.Mood.NATURE:   [3, 2, 4],  # Prefers carpet (warm, organic)
	ExhibitMood.Mood.ASTRO:    [2, 4, 3],  # Prefers marble (dark, reflective)
	ExhibitMood.Mood.MEDIA:    [4, 2, 3],  # Prefers wood (warm, theatrical)
	ExhibitMood.Mood.ART:      [3, 4, 2],  # Marble gallery floors
	ExhibitMood.Mood.GEOGRAPHY:[4, 2, 3],  # Wood (natural, earthy)
	ExhibitMood.Mood.PHILOSOPHY:[3, 3, 3], # Balanced (contemplative neutrality)
	ExhibitMood.Mood.SPORTS:   [4, 3, 2],  # Wood (gymnasium style)
	ExhibitMood.Mood.FOOD:     [5, 2, 2],  # Wood (warm kitchen)
	ExhibitMood.Mood.POLITICS: [2, 5, 2],  # Marble (institutional grandeur)
	ExhibitMood.Mood.ECONOMY:  [3, 5, 1],  # Marble (banking hall)
	ExhibitMood.Mood.MYSTERY:  [4, 1, 4],  # Wood + carpet (dim, atmospheric)
}

static var FOG_LIST: Array[Color] = [Color.WHITE, Color.WHITE, Color.BLACK]
static var ITEM_MATERIAL_LIST: Array[String] = ["wood", "marble", "none"]
static var PLATE_STYLE_LIST: Array[String] = ["white", "black"]

static func gen_floor(title: String) -> int:
	# Default: uniform random from all floor types
	return FLOOR_LIST[hash(title) % len(FLOOR_LIST)]

## Generate floor type biased by exhibit mood
static func gen_floor_mooded(title: String, mood: int = ExhibitMood.Mood.DEFAULT) -> int:
	var weights: Array = FLOOR_WEIGHTS.get(mood, FLOOR_WEIGHTS[ExhibitMood.Mood.DEFAULT])
	
	# Weighted random selection
	var total: int = 0
	for w: int in weights:
		total += w
	
	var roll: int = hash(title + ":floor") % total
	var cumulative: int = 0
	
	for i: int in range(len(FLOOR_LIST)):
		cumulative += weights[i]
		if roll < cumulative:
			return FLOOR_LIST[i]
	
	return FLOOR_LIST[len(FLOOR_LIST) - 1]  # Fallback

static func gen_fog(title: String) -> Color:
	if title == "Lobby":
		return Color.WHITE
	return FOG_LIST[hash(title) % len(FOG_LIST)]

static func gen_item_material(title: String) -> String:
	return ITEM_MATERIAL_LIST[hash(title + ":material") % len(ITEM_MATERIAL_LIST)]

static func gen_plate_style(title: String) -> String:
	var material := gen_item_material(title)
	if material == "none":
		return "white"
	return PLATE_STYLE_LIST[hash(title + ":plate") % len(PLATE_STYLE_LIST)]
