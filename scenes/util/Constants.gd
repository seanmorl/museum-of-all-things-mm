class_name Constants
extends RefCounted

# Floor types
const FLOOR_WOOD := 0
const FLOOR_CARPET := 11
const FLOOR_MARBLE := 12
# Reserved for future use (need mesh library entries):
# const FLOOR_TILE := 13
# const FLOOR_STONE := 14
# const FLOOR_CONCRETE := 15
# const FLOOR_TERRAZZO := 16

# Network
const DEFAULT_PORT := 7777  # Primary port (as requested)
const MAX_PLAYERS := 8

# Grid
const GRID_CELL_SIZE := 4.0

# Slots/limits
const MAX_SLOTS_MOBILE := 200
const MAX_SLOTS_DESKTOP := 2500

# Graphics - managed lights
const MANAGED_LIGHTS_MAX := 8
const MANAGED_LIGHTS_DIRECTION_THRESHOLD := -0.2
const MANAGED_LIGHTS_FREQUENCY := 1.0

# UI Canvas Layers (z-order)
const UI_LAYER_BEHIND = 10
const UI_LAYER_HUD = 20
const UI_LAYER_HOST_MENU = 50
const UI_LAYER_OVERLAY = 95
const UI_LAYER_VOTE_LOADING = 95
const UI_LAYER_SCREENSHOT = 127
const UI_LAYER_TOPMOST = 128
const UI_LAYER_DEBUG = 1000
const UI_LAYER_LOADING_SCREEN = 100

# Physics collision layers (matching project layer_names)
const COLLISION_LAYER_STATIC_WORLD = 1  # 2^0
const COLLISION_LAYER_DYNAMIC_WORLD = 2  # 2^1
const COLLISION_LAYER_PICKABLE = 4  # 2^2
const COLLISION_LAYER_WALL_WALKING = 8  # 2^3
const COLLISION_LAYER_GRAPPLE_TARGET = 16  # 2^4
const COLLISION_LAYER_POINTABLE = 1048576  # 2^20 (layer 21)
const COLLISION_LAYER_HELD_OBJECTS = 131072  # 2^17
const COLLISION_LAYER_PLAYER_HANDS = 262144  # 2^18
const COLLISION_LAYER_PLAYER_BODY = 1048576  # 2^20

# Player spawn/positioning
const PLAYER_STARTING_POSITION := Vector3(0, 4, 0)
const PLAYER_STARTING_Y := 0.0
const MOUNTED_RIDER_Y_OFFSET := 2.5
const MOUNTED_RIDER_Y_LOW_OFFSET := 1.0

# Exhibit generation probabilities
const COLUMN_SPAWN_CHANCE_PERCENT := 30
const DECORATION_SPAWN_CHANCE_40 := 40
const DECORATION_SPAWN_CHANCE_20 := 20

# Player positioning in races
const RACE_START_LINE_Z := 23.0
const RACE_START_LINE_Y := 5.0
const RACE_START_PLAYER_SPACING := 1.5

# Audio
const COUNTDOWN_SOUND_VOLUME := -5.0
const GO_SOUND_VOLUME := -3.0
const VICTORY_SOUND_VOLUME := -3.0

# Lighting
const LIGHT_ENERGY_DARK_MODE := 0.08
const LIGHT_ENERGY_LIGHT_MODE := 1.2