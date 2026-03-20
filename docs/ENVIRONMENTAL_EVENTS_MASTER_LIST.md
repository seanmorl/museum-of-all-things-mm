# Environmental Events - Master Design Document

**Version**: 1.0  
**Last Updated**: March 17, 2026  
**Total Events**: 52  
**Status**: Ready for Implementation  

---

## 📋 Table of Contents

1. [Executive Summary](#executive-summary)
2. [Quick Reference Table](#quick-reference-table)
3. [Development Priority Tiers](#development-priority-tiers)
4. [Event Categories](#event-categories)
5. [Accessibility Requirements](#accessibility-requirements)
6. [Host Configuration UI](#host-configuration-ui)
7. [Technical Implementation](#technical-implementation)
8. [Testing Checklist](#testing-checklist)

---

## Executive Summary

### Design Philosophy

Environmental Events are **server-controlled global effects** that temporarily modify the museum for ALL players simultaneously. They provide:

- ✅ **Chaos & excitement** (what community wants from powerups)
- ✅ **Zero sync nightmares** (broadcast-only, no per-player state)
- ✅ **Dynamic loading safe** (events apply to newly loaded rooms automatically)
- ✅ **Fair for all players** (everyone affected equally)
- ✅ **Host configurable** (granular control over what appears)

### Key Differences from Powerups

| Aspect | Powerups | Environmental Events |
|--------|----------|---------------------|
| **Target** | Individual player | All players simultaneously |
| **Sync** | Complex (per-player state) | Simple (broadcast only) |
| **Dynamic Loading** | Breaks on room unload | Unload-safe by design |
| **Fairness** | Random advantage | Shared challenge |
| **Implementation** | 15-19 days | 3-4 days |
| **Maintenance** | Fragile | Robust |

### Why Environmental Events Won

1. **Community gets chaos** - Same excitement as powerups
2. **You get stability** - No sync bugs, no crashes
3. **Faster development** - 3-4 days vs 15-19 days
4. **Accessible** - No medical risks (strobe removed)
5. **Configurable** - Hosts pick and choose what appears

---

## Quick Reference Table

### 🟢 Tier 1: Launch Events (22 Events - Safe, Easy, High Impact)

| # | Event Name | Duration | Frequency | Safety | Complexity | Category |
|---|------------|----------|-----------|--------|------------|----------|
| 1 | True Compass | 30-60s | Common | ✅ | 🟢 | Information |
| 2 | False Compass | 30-50s | Uncommon | ✅ | 🟢 | Information |
| 3 | Revealed Path | Room-based | Uncommon | ✅ | 🟢 | Information |
| 4 | Locked Doors | 25-45s | Common | ✅ | 🟢 | Navigation |
| 5 | Reversed | 30-60s | Uncommon | ✅ | 🟢 | Navigation |
| 6 | Fog | 30-50s | Common | ✅ | 🟢 | Visual |
| 7 | One-Way Doors | 45-90s | Uncommon | ✅ | 🟡 | Navigation |
| 8 | No U-Turns | 60-120s | Uncommon | ✅ | 🟢 | Navigation |
| 9 | Slippery Floors | 40-70s | Uncommon | ✅ | 🟢 | Navigation |
| 10 | Rotating Rooms | 45-90s | Rare | ✅ | 🟡 | Navigation |
| 11 | Darkness | 20-35s | Common | ✅ | 🟢 | Visual |
| 12 | Color Shift | 30-45s | Uncommon | ✅ | 🟢 | Visual |
| 13 | Silence | 30-60s | Uncommon | ✅ | 🟢 | Audio |
| 14 | Earthquake | 20-35s | Uncommon | ✅ | 🟢 | Visual |
| 15 | Weather System | 60-120s | Uncommon | ✅ | 🟢 | Visual |
| 16 | Speed Up | 20-30s | Common | ✅ | 🟢 | Movement |
| 17 | Heavy Gravity | 25-40s | Common | ✅ | 🟢 | Movement |
| 18 | No Running | 45-90s | Uncommon | ✅ | 🟢 | Movement |
| 19 | Time Dilation | 30-50s | Uncommon | ✅ | 🟢 | Time |
| 20 | Double Time | 30-60s | Common | ✅ | 🟢 | Time |
| 21 | Sudden Death | Race-end | Very Rare | ✅ | 🟢 | Time |
| 22 | King of the Hill | 60-120s | Rare | ✅ | 🟢 | Social |
| 23 | Audio Surprise | Instant | Uncommon | ✅ | 🟢 | Audio |
| 24 | Roulette | Instant | Rare | ✅ | 🟢 | Chaos |
| 25 | All Clear | 10s | N/A | ✅ | 🟢 | Utility |

**Development Time**: 3-4 days  
**Risk Level**: 🟢 None  

---

### 🟡 Tier 2: Post-Launch Events (15 Events - Safe, Moderate Complexity)

| # | Event Name | Duration | Frequency | Safety | Complexity | Category |
|---|------------|----------|-----------|--------|------------|----------|
| 26 | Hidden Truth | 40-70s | Rare | ✅ | 🟡 | Information |
| 27 | Wikipedia Wisdom | 30-60s | Uncommon | ✅ | 🟡 | Information |
| 28 | Magnetic Walls | 45-80s | Uncommon | ✅ | 🟡 | Navigation |
| 29 | Portal Links | 40-70s | Rare | ⚠️ | 🟠 | Navigation |
| 30 | Seasonal Change | Race-long | Rare | ✅ | 🟡 | Visual |
| 31 | Museum After Hours | 60-120s | Uncommon | ✅ | 🟢 | Visual |
| 32 | Must Dash | 30-60s | Uncommon | ✅ | 🟢 | Movement |
| 33 | Third Person | Race-long | Uncommon | ⚠️ | 🟡 | Movement |
| 34 | Time Freeze | 20-40s | Uncommon | ✅ | 🟢 | Time |
| 35 | Handicap Start | Race-long | Rare | ✅ | 🟡 | Time |
| 36 | Random Teleport | Instant | Very Rare | ⚠️ | 🟡 | Teleport |
| 37 | Shuffle Players | Instant | Very Rare | ⚠️ | 🟡 | Teleport |
| 38 | Pathfinder | 20-40s | Uncommon | ✅ | 🟡 | Vision |
| 39 | Shuffle Labels | 40-70s | Rare | ✅ | 🟡 | Rules |
| 40 | Amplified Sounds | 30-50s | Uncommon | ✅ | 🟢 | Audio |

**Development Time**: 5-7 days  
**Risk Level**: 🟡 Low (requires testing)  

---

### 🟠 Tier 3: Experimental Events (8 Events - Higher Risk, Niche Appeal)

| # | Event Name | Duration | Frequency | Safety | Complexity | Category | Notes |
|---|------------|----------|-----------|--------|------------|----------|-------|
| 41 | Buddy System | Race-long | Very Rare | ⚠️ | 🟡 | Social | Requires win condition changes |
| 42 | Traitor | Race-long | Very Rare | ⚠️ | 🟡 | Social | Could create toxic dynamics |
| 43 | Spectator Swap | 20-40s | Rare | ⚠️ | 🟠 | Social | Motion sickness risk |
| 44 | Blindfolded | 20-40s | Rare | ⚠️ | 🟠 | Vision | Disorientation risk |
| 45 | One Life | Race-long | Very Rare | ✅ | 🟡 | Rules | Too punishing for casual |
| 46 | Ghost Mode | 30-45s | Rare | ⚠️ | 🟠 | Rules | Collision complexity |
| 47 | Mirror World | 40-70s | Very Rare | ⚠️ | 🟡 | Rules | Motion sickness risk |
| 48 | Event Storm | 30-60s | Very Rare | ⚠️ | 🟠 | Chaos | Multi-event sync complexity |
| 49 | Grand Finale | 30s | Very Rare | ⚠️ | 🟠 | Chaos | Event recall complexity |

**Development Time**: 5-7 days  
**Risk Level**: 🟠 Medium (implement only if community requests)  

---

### ❌ Permanently Removed (Medical/Safety Risk)

| Event | Reason | Status |
|-------|--------|--------|
| Strobe | Photosensitive epilepsy trigger | ❌ Never |
| Blackout | Sudden darkness seizure risk | ❌ Never |
| Any flashing/pulsing effects | Medical risk | ❌ Never |
| Screen shake (high amplitude) | Motion sickness | ❌ Never |

---

## Development Priority Tiers

### 🟢 Tier 1: Launch Events (Implement for v0.5.0)

**22-25 Events | 3-4 Days Development**

#### Week 1: Core System
```
Day 1-2: EventManager autoload with configuration
Day 2-3: VoteHUD integration (host settings panel)
Day 4: Warning banner system (2s before event)
Day 5: Gradual transition system (1s fade in/out)
```

#### Week 2: Event Implementation
```
Day 1: Darkness, Fog, Color Shift, Weather System, Earthquake (visual)
Day 2: Locked Doors, Reversed, One-Way Doors, No U-Turns (navigation)
Day 3: Speed Up, Heavy Gravity, No Running (movement)
Day 4: Time Dilation, Double Time, Sudden Death (time)
Day 5: True Compass, False Compass, Revealed Path, King of the Hill, Audio Surprise, Roulette
```

#### Week 3: Polish & Testing
```
Day 1: Rotating Rooms, Slippery Floors (navigation)
Day 2: Accessibility options, host presets
Day 3-4: Multiplayer testing (2, 4, 8 players)
Day 5: Balance tweaks, bug fixes
```

---

### 🟡 Tier 2: Post-Launch (Implement for v0.6.0)

**15 Events | 5-7 Days Development**

#### Month 1 After Launch
```
Week 1: Hidden Truth, Wikipedia Wisdom, Magnetic Walls
Week 2: Portal Links, Seasonal Change, Museum After Hours
Week 3: Must Dash, Third Person, Time Freeze, Handicap Start
Week 4: Random Teleport, Shuffle Players, Pathfinder, Shuffle Labels, Amplified Sounds
```

---

### 🟠 Tier 3: Community Request Only

**8 Events | Implement Only If Requested**

Only implement if:
- Community specifically requests via feedback/polls
- You have dedicated testing time
- Accessibility warnings are prominent

---

## Event Categories

### 📚 Information & Knowledge (5 Events)

Events that provide or manipulate navigation information.

| Event | Effect | Duration | Fun Factor |
|-------|--------|----------|------------|
| **True Compass** | Golden arrow points to target | 30-60s | ⭐⭐⭐⭐ |
| **False Compass** | Arrow points to WRONG target | 30-50s | ⭐⭐⭐⭐ |
| **Revealed Path** | Glowing footprints show route | Room-based | ⭐⭐⭐ |
| **Hidden Truth** | Secret shortcuts revealed | 40-70s | ⭐⭐⭐⭐ |
| **Wikipedia Wisdom** | Random facts hint at path | 30-60s | ⭐⭐⭐ |

**Implementation Notes**:
- All unload-safe (data only, no geometry)
- Easy to implement
- Good positive events to balance negative ones

---

### 🚪 Navigation & Spatial (11 Events)

Events that change how players navigate the museum.

| Event | Effect | Duration | Fun Factor |
|-------|--------|----------|------------|
| **Locked Doors** | All doors temporarily locked | 25-45s | ⭐⭐⭐ |
| **Reversed** | Entry/Exit directions flip | 30-60s | ⭐⭐⭐⭐ |
| **Fog** | Reduced visibility | 30-50s | ⭐⭐⭐ |
| **Rotating Rooms** | All rooms rotate 90° | 45-90s | ⭐⭐⭐⭐ |
| **One-Way Doors** | Can't exit same way entered | 45-90s | ⭐⭐⭐⭐ |
| **Portal Links** | Doors become random portals | 40-70s | ⭐⭐⭐⭐⭐ |
| **No U-Turns** | Must find alternate routes | 60-120s | ⭐⭐⭐ |
| **Magnetic Walls** | Walls repel players | 45-80s | ⭐⭐⭐ |
| **Slippery Floors** | Reduced traction, sliding | 40-70s | ⭐⭐⭐⭐ |

**Implementation Notes**:
- Most are unload-safe (new rooms load with effect active)
- Portal Links needs spawn point validation
- Rotating Rooms is data-only (no geometry rotation)

---

### 🌈 Visual & Atmosphere (7 Events)

Events that change the visual presentation.

| Event | Effect | Duration | Fun Factor |
|-------|--------|----------|------------|
| **Darkness** | Lights dim to 15% | 20-35s | ⭐⭐⭐⭐ |
| **Color Shift** | Monochrome/sepia filter | 30-45s | ⭐⭐⭐ |
| **Weather System** | Rain/snow particles | 60-120s | ⭐⭐⭐ |
| **Seasonal Change** | Holiday themes | Race-long | ⭐⭐⭐ |
| **Museum After Hours** | Warm, dim lighting | 60-120s | ⭐⭐⭐⭐ |
| **Earthquake** | Subtle camera shake | 20-35s | ⭐⭐⭐ |

**Implementation Notes**:
- All viewport/environment effects (unload-safe)
- Darkness: gradual fade (1s), min 15% brightness
- Color Shift: smooth transition (1s), no flashing
- Earthquake: low frequency, small amplitude (motion sickness safe)

---

### ⚡ Speed & Movement (5 Events)

Events that modify player movement.

| Event | Effect | Duration | Fun Factor |
|-------|--------|----------|------------|
| **Speed Up** | +50% movement speed | 20-30s | ⭐⭐⭐ |
| **Heavy Gravity** | -40% movement speed | 25-40s | ⭐⭐ |
| **No Running** | Dash disabled | 45-90s | ⭐⭐ |
| **Must Dash** | Forced dash always | 30-60s | ⭐⭐⭐ |
| **Third Person** | Camera behind player | Race-long | ⭐⭐⭐⭐ |

**Implementation Notes**:
- All are player stat modifiers (unload-safe)
- Third Person needs motion sickness warning
- Speed modifiers apply multiplicatively

---

### ⏱️ Time & Pacing (5 Events)

Events that manipulate the race timer.

| Event | Effect | Duration | Fun Factor |
|-------|--------|----------|------------|
| **Time Dilation** | Timer at 50% speed | 30-50s | ⭐⭐⭐ |
| **Double Time** | Timer at 200% speed | 30-60s | ⭐⭐⭐ |
| **Time Freeze** | Timer pauses | 20-40s | ⭐⭐⭐ |
| **Sudden Death** | Timer counts DOWN | Until end | ⭐⭐⭐⭐⭐ |
| **Handicap Start** | Delayed starts | Race-long | ⭐⭐⭐ |

**Implementation Notes**:
- All modify RaceManager timer (unload-safe)
- Sudden Death: dramatic finale event
- Handicap Start: only at race start

---

### 👥 Social & Competition (4 Events)

Events that create social dynamics.

| Event | Effect | Duration | Fun Factor |
|-------|--------|----------|------------|
| **King of the Hill** | Leader gets visible crown | 60-120s | ⭐⭐⭐⭐ |
| **Buddy System** | Paired players must both finish | Race-long | ⭐⭐⭐ |
| **Traitor** | Secret role, 2x points if win | Race-long | ⭐⭐ |
| **Spectator Swap** | See through another's camera | 20-40s | ⭐⭐⭐ |

**Implementation Notes**:
- King of the Hill: easy (just show crown icon)
- Buddy System: requires win condition changes
- Traitor: could create toxic dynamics (use cautiously)
- Spectator Swap: motion sickness risk

---

### 🔄 Teleport & Position (2 Events)

Events that move players.

| Event | Effect | Duration | Fun Factor |
|-------|--------|----------|------------|
| **Random Teleport** | Players swap to random rooms | Instant | ⭐⭐⭐⭐⭐ |
| **Shuffle Players** | Leader ↔ Last place swap | Instant | ⭐⭐⭐⭐⭐ |

**Implementation Notes**:
- Need 1s fade transition (disorientation)
- Need to handle network player sync
- Add warning banner

---

### 🔊 Audio Events (3 Events)

Events that manipulate audio.

| Event | Effect | Duration | Fun Factor |
|-------|--------|----------|------------|
| **Audio Surprise** | Random funny sound plays | Instant | ⭐⭐⭐⭐⭐ |
| **Silence** | All audio muted | 30-60s | ⭐⭐ |
| **Amplified Sounds** | All sounds 2x louder | 30-50s | ⭐⭐ |

**Implementation Notes**:
- Audio Surprise: use curated royalty-free library
- Normalize all audio to same volume
- 1s audio fade-in (no startle response)
- Add "Disable Audio Events" option

---

### 🎲 Chaos & Random (3 Events)

Events that create maximum chaos.

| Event | Effect | Duration | Fun Factor |
|-------|--------|----------|------------|
| **Roulette** | Random event chosen | Instant | ⭐⭐⭐⭐ |
| **Event Storm** | Multiple events rapidly | 30-60s | ⭐⭐⭐⭐⭐ |
| **Grand Finale** | All previous events re-apply | 30s | ⭐⭐⭐⭐⭐ |

**Implementation Notes**:
- Roulette: pick from allowed events only
- Event Storm: limit to 2-3 concurrent max
- Grand Finale: only in last 30s of race

---

### 🛠️ Utility (1 Event)

| Event | Effect | Duration | Fun Factor |
|-------|--------|----------|------------|
| **All Clear** | Ends all active events | 10s | ⭐⭐ |

**Implementation Notes**:
- Mercy event (can be triggered manually by host)
- Good for when events create impossible situations

---

## Accessibility Requirements

### ⚠️ Mandatory Safety Features

#### 1. Warning Banner (2 seconds before all events)

```gdscript
func _show_event_warning(event_type: int) -> void:
    var banner := Label.new()
    banner.text = "⚠️ %s in 2 seconds..." % _get_event_name(event_type)
    banner.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
    banner.add_theme_font_size_override("font_size", 18)
    
    # Add to UI layer
    get_tree().current_scene.add_child(banner)
    
    # Center on screen
    banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    banner.offset_left = -200
    banner.offset_top = -50
    banner.offset_right = 200
    banner.offset_bottom = 50
    
    # Auto-remove after 2s
    await get_tree().create_timer(2.0).timeout
    banner.queue_free()
```

#### 2. Gradual Transitions (1 second fade in/out)

```gdscript
# NEVER do instant changes (BAD)
light.light_energy = 0.0

# ALWAYS use gradual fade (GOOD)
var tween = light.create_tween()
tween.tween_property(light, "light_energy", 0.15, 1.0)  # 1 second fade
```

#### 3. Host Accessibility Options

```gdscript
# In VoteHUD host settings
var accessibility_options := {
    "disable_disorientation": false,  # Blocks Mirror, Reversed, etc.
    "disable_teleport": false,  # Blocks Random Teleport, Shuffle
    "disable_audio_events": false,  # Blocks Audio Surprise
    "extended_warnings": false,  # 5s instead of 2s
    "reduced_intensity": false,  # Shorter durations, milder effects
}
```

---

### ♿ Accessibility Mode Preset

```
┌─────────────────────────────────────────┐
│ ♿ Accessibility Mode                    │
├─────────────────────────────────────────┤
│ ✅ Extended warnings (5s before)        │
│ ✅ Gradual transitions only (1s+ fade)  │
│ ❌ No disorientation events             │
│    (Mirror, Reversed, Blindfolded)      │
│ ❌ No teleport events                   │
│    (Random Teleport, Shuffle Players)   │
│ ❌ No audio surprise events             │
│ ✅ Reduced intensity (75% duration)     │
│ ✅ Only positive/neutral events         │
└─────────────────────────────────────────┘
```

**Blocked Events in Accessibility Mode**:
- ❌ Reversed (disorientation)
- ❌ Mirror World (motion sickness)
- ❌ Random Teleport (disorientation)
- ❌ Shuffle Players (disorientation)
- ❌ Blindfolded (extreme disorientation)
- ❌ Spectator Swap (motion sickness)
- ❌ Audio Surprise (startle response)

---

## Host Configuration UI

### Full Event Settings Panel

```
┌─────────────────────────────────────────┐
│ 🎭 Environmental Events                 │
├─────────────────────────────────────────┤
│ ☑ Enable Events                         │
│                                         │
│ ── Presets ───────────────────────────  │
│ [Chaos Mode] [Standard] [Chill]        │
│ [Accessibility] [Custom]                │
│                                         │
│ ── Timing ────────────────────────────  │
│ Frequency: [━━━━━●━━━━━] 90s           │
│            30s              180s        │
│                                         │
│ Max Concurrent: [●━━━] 1               │
│                  1    2    3            │
│                                         │
│ Duration:       [━━●━━] 1.0x           │
│                 0.5  1.0  2.0           │
│                                         │
│ ── Allowed Events ────────────────────  │
│ ┌─────────────────────────────────────┐ │
│ │ ☑ Darkness         ☑ Fog            │ │
│ │ ☑ Locked Doors     ☑ Speed Up       │ │
│ │ ☑ Reversed         ☑ Heavy Gravity  │ │
│ │ ☑ Color Shift      ☑ No Running     │ │
│ │ ☑ Rotating Rooms   ☑ Time Dilation  │ │
│ │ ☑ One-Way Doors    ☑ Double Time    │ │
│ │ ☑ No U-Turns       ☑ Sudden Death   │ │
│ │ ☑ Slippery Floors  ☑ King of Hill   │ │
│ │ ☑ Earthquake       ☑ Audio Surprise │ │
│ │ ☑ Weather System   ☑ Roulette       │ │
│ │ ☑ True Compass     ☑ All Clear      │ │
│ │ ☑ False Compass    ☑ Double Points  │ │
│ │ ☑ Revealed Path                     │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ── Accessibility ─────────────────────  │
│ ☐ Accessibility Mode (presets above)   │
│ ☐ Disable disorientation events        │
│ ☐ Disable teleport events              │
│ ☐ Disable audio events                 │
│ ☐ Extended warnings (5s)               │
│ ☐ Reduced intensity                    │
└─────────────────────────────────────────┘
```

### Preset Configurations

```gdscript
const PRESETS := {
    "Chaos Mode": {
        "frequency": 45,
        "max_concurrent": 2,
        "duration": 1.5,
        "all_events": true,
        "accessibility": false
    },
    "Standard": {
        "frequency": 90,
        "max_concurrent": 1,
        "duration": 1.0,
        "all_events": true,
        "accessibility": false
    },
    "Chill": {
        "frequency": 180,
        "max_concurrent": 1,
        "duration": 0.75,
        "all_events": true,
        "accessibility": false
    },
    "Accessibility": {
        "frequency": 120,
        "max_concurrent": 1,
        "duration": 0.75,
        "allowed_events": [
            EventType.TRUE_COMPASS,
            EventType.REVEALED_PATH,
            EventType.WEATHER_SYSTEM,
            EventType.DOUBLE_TIME,
            EventType.ALL_CLEAR
        ],
        "accessibility": true
    },
    "No Events": {
        "enabled": false
    }
}
```

---

## Technical Implementation

### File Structure

```
scenes/
├── util/
│   ├── EventManager.gd              # Main autoload singleton
│   └── events/
│       ├── BaseEvent.gd             # Base class for all events
│       ├── DarknessEvent.gd
│       ├── LockedDoorsEvent.gd
│       ├── ReversedEvent.gd
│       ├── FogEvent.gd
│       ├── SpeedUpEvent.gd
│       ├── HeavyGravityEvent.gd
│       ├── TrueCompassEvent.gd
│       ├── FalseCompassEvent.gd
│       ├── RevealedPathEvent.gd
│       ├── TimeDilationEvent.gd
│       ├── DoubleTimeEvent.gd
│       ├── SuddenDeathEvent.gd
│       ├── KingOfTheHillEvent.gd
│       ├── AudioSurpriseEvent.gd
│       ├── RouletteEvent.gd
│       ├── WeatherEvent.gd
│       ├── EarthquakeEvent.gd
│       ├── ColorShiftEvent.gd
│       ├── SilenceEvent.gd
│       ├── NoRunningEvent.gd
│       ├── OneWayDoorsEvent.gd
│       ├── NoUTurnsEvent.gd
│       ├── SlipperyFloorsEvent.gd
│       └── RotatingRoomsEvent.gd
│
├── menu/
│   └── VoteHUD.gd                   # Host configuration panel
│
└── ui/
    └── EventWarningBanner.gd        # Reusable warning banner

autoload/
└── EventManager.gd                  # Register as autoload
```

---

### EventManager Autoload

```gdscript
# scenes/util/EventManager.gd
extends Node
## Server-authoritative environmental event system

signal event_started(event_type: int, duration: float)
signal event_ended(event_type: int)
signal event_warning(event_type: int)  # 2s before event

enum EventType {
    NONE,
    # Information
    TRUE_COMPASS,
    FALSE_COMPASS,
    REVEALED_PATH,
    HIDDEN_TRUTH,
    WIKIPEDIA_WISDOM,
    # Navigation
    LOCKED_DOORS,
    REVERSED,
    FOG,
    ROTATING_ROOMS,
    ONE_WAY_DOORS,
    PORTAL_LINKS,
    NO_U_TURNS,
    MAGNETIC_WALLS,
    SLIPPERY_FLOORS,
    # Visual
    DARKNESS,
    COLOR_SHIFT,
    WEATHER_SYSTEM,
    SEASONAL_CHANGE,
    MUSEUM_AFTER_HOURS,
    EARTHQUAKE,
    # Movement
    SPEED_UP,
    HEAVY_GRAVITY,
    NO_RUNNING,
    MUST_DASH,
    THIRD_PERSON,
    # Time
    TIME_DILATION,
    DOUBLE_TIME,
    TIME_FREEZE,
    SUDDEN_DEATH,
    HANDICAP_START,
    # Social
    KING_OF_THE_HILL,
    BUDDY_SYSTEM,
    TRAITOR,
    SPECTATOR_SWAP,
    # Teleport
    RANDOM_TELEPORT,
    SHUFFLE_PLAYERS,
    # Audio
    AUDIO_SURPRISE,
    SILENCE,
    AMPLIFIED_SOUNDS,
    # Chaos
    ROULETTE,
    EVENT_STORM,
    GRAND_FINALE,
    # Utility
    ALL_CLEAR,
    DOUBLE_POINTS,
}

# Configuration
var _events_enabled: bool = true
var _event_frequency: float = 90.0
var _allowed_events: Array[EventType] = []
var _duration_modifier: float = 1.0
var _max_concurrent: int = 1
var _accessibility_mode: bool = false

# State
var _active_events: Dictionary = {}  # event_type -> {end_time, duration, data}

func _ready() -> void:
    if multiplayer.is_server():
        _start_event_timer()

func _start_event_timer() -> void:
    while true:
        await get_tree().create_timer(randf_range(30.0, 60.0)).timeout
        if _should_trigger_event():
            _trigger_random_event()

func _should_trigger_event() -> bool:
    if not _events_enabled:
        return false
    if _active_events.size() >= _max_concurrent:
        return false
    if not RaceManager.is_race_active():
        return false
    # No events in first 30 seconds
    if RaceManager.get_race_time() < 30.0:
        return false
    return true

func _trigger_random_event() -> void:
    var available = _get_available_events()
    if available.is_empty():
        return
    
    var event = available.pick_random()
    var duration = _get_event_duration(event)
    
    # Show warning 2 seconds before
    event_warning.emit(event)
    await get_tree().create_timer(2.0).timeout
    
    _start_event(event, duration)

func _start_event(event_type: int, duration: float) -> void:
    if _active_events.has(event_type):
        return  # Already active
    
    _active_events[event_type] = {
        "end_time": Time.get_ticks_msec() + (duration * 1000),
        "duration": duration
    }
    
    # Broadcast to all clients
    _rpc_event_started.rpc(event_type, duration)
    event_started.emit(event_type, duration)

@rpc("authority", "call_local", "reliable")
func _rpc_event_started(event_type: int, duration: float) -> void:
    _active_events[event_type] = {
        "end_time": Time.get_ticks_msec() + (duration * 1000),
        "duration": duration
    }
    event_started.emit(event_type, duration)

func _process(_delta: float) -> void:
    var now = Time.get_ticks_msec()
    for event_type in _active_events.keys():
        if now >= _active_events[event_type].end_time:
            _end_event(event_type)

func _end_event(event_type: int) -> void:
    _active_events.erase(event_type)
    _rpc_event_ended.rpc(event_type)
    event_ended.emit(event_type)

@rpc("authority", "call_local", "reliable")
func _rpc_event_ended(event_type: int) -> void:
    _active_events.erase(event_type)
    event_ended.emit(event_type)

func is_event_active(event_type: int) -> bool:
    return _active_events.has(event_type)

func get_active_events() -> Array:
    return _active_events.keys()

func _get_available_events() -> Array[EventType]:
    var available: Array[EventType] = []
    for event in _allowed_events:
        if event != EventType.NONE and not _active_events.has(event):
            available.append(event)
    return available

func _get_event_duration(event_type: int) -> float:
    var base = _get_base_duration(event_type)
    return base * _duration_modifier

func _get_base_duration(event_type: int) -> float:
    match event_type:
        EventType.DARKNESS: return randf_range(20.0, 35.0)
        EventType.LOCKED_DOORS: return randf_range(25.0, 45.0)
        EventType.REVERSED: return randf_range(30.0, 60.0)
        # ... etc for all events
    return 30.0

# Configuration API
func configure_from_dict(config: Dictionary) -> void:
    _events_enabled = config.get("enabled", true)
    _event_frequency = config.get("frequency_seconds", 90.0)
    _allowed_events = config.get("allowed_events", EventType.values())
    _duration_modifier = config.get("duration_modifier", 1.0)
    _max_concurrent = config.get("max_concurrent", 1)
    _accessibility_mode = config.get("accessibility_mode", false)
    
    if _accessibility_mode:
        _apply_accessibility_restrictions()

func _apply_accessibility_restrictions() -> void:
    # Remove disorientation events
    var blocked = [
        EventType.REVERSED,
        EventType.MIRROR_WORLD,
        EventType.RANDOM_TELEPORT,
        EventType.SHUFFLE_PLAYERS,
        EventType.BLINDFOLDED,
        EventType.SPECTATOR_SWAP,
        EventType.AUDIO_SURPRISE,
    ]
    for event in blocked:
        if event in _allowed_events:
            _allowed_events.erase(event)
```

---

### Base Event Class

```gdscript
# scenes/util/events/BaseEvent.gd
class_name EnvironmentalEvent
extends RefCounted

var event_type: int
var display_name: String
var description: String
var default_duration: float
var frequency_weight: int = 10  # Higher = more common
var safety_rating: String = "Safe"  # "Safe", "Warning", "Disabled"
var complexity: String = "Easy"  # "Easy", "Medium", "Hard"

func apply_event() -> void:
    """Override in subclass to apply event effect"""
    pass

func end_event() -> void:
    """Override in subclass to cleanup/restore"""
    pass

func is_unload_safe() -> bool:
    """Does this event work with dynamic room loading?"""
    return true

func get_warning_text() -> String:
    """Text to show in 2s warning banner"""
    return display_name
```

---

### Example Event Implementation

```gdscript
# scenes/util/events/DarknessEvent.gd
class_name DarknessEvent
extends EnvironmentalEvent

func _init() -> void:
    event_type = EventManager.EventType.DARKNESS
    display_name = "Darkness"
    description = "All lights dim to 15% brightness"
    default_duration = 30.0
    frequency_weight = 15  # Common
    safety_rating = "Safe"
    complexity = "Easy"

func apply_event() -> void:
    for light in Engine.get_main_loop().get_nodes_in_group("managed_light"):
        if light is OmniLight3D or light is SpotLight3D:
            # Gradual fade over 1 second
            var tween = light.create_tween()
            tween.tween_property(light, "light_energy", 0.15, 1.0)

func end_event() -> void:
    for light in Engine.get_main_loop().get_nodes_in_group("managed_light"):
        if light is OmniLight3D or light is SpotLight3D:
            # Restore to normal (1.0 or dark mode value)
            var target = 1.0 if not ThemeManager.is_dark_mode else 0.4
            var tween = light.create_tween()
            tween.tween_property(light, "light_energy", target, 1.0)

func is_unload_safe() -> bool:
    return true  # New rooms will load with lights at normal brightness
```

---

## Testing Checklist

### Pre-Launch Testing (Tier 1 Events)

#### Core System
- [ ] EventManager autoload registers correctly
- [ ] Server triggers events at correct frequency
- [ ] All clients receive event broadcasts
- [ ] Warning banners appear 2s before events
- [ ] Gradual transitions (1s fade) work correctly
- [ ] Events end after correct duration
- [ ] Multiple concurrent events don't conflict

#### Individual Events (Test Each)
- [ ] Darkness - lights dim/restore smoothly
- [ ] Locked Doors - doors lock/unlock
- [ ] Reversed - labels swap correctly
- [ ] Fog - viewport fog applies
- [ ] Speed Up - all players faster
- [ ] Heavy Gravity - all players slower
- [ ] True Compass - arrow points to target
- [ ] False Compass - arrow points wrong way
- [ ] Audio Surprise - sound plays at normalized volume
- [ ] Roulette - random event selected
- [ ] (Test all 22 Tier 1 events)

#### Multiplayer Sync
- [ ] 2 players: all events sync correctly
- [ ] 4 players: all events sync correctly
- [ ] 8 players: all events sync correctly
- [ ] Late joiner: receives active event state
- [ ] Player disconnect: events continue normally

#### Accessibility
- [ ] Accessibility Mode blocks restricted events
- [ ] Extended warnings (5s) work
- [ ] Reduced intensity (75% duration) applies
- [ ] Host can disable individual events
- [ ] Presets load correctly

#### Host Configuration
- [ ] VoteHUD settings panel appears
- [ ] Frequency slider works (30-180s)
- [ ] Max concurrent slider works (1-3)
- [ ] Duration modifier works (0.5-2.0x)
- [ ] Individual event toggles work
- [ ] Presets apply correctly
- [ ] Settings save between races

#### Edge Cases
- [ ] Event triggers during countdown (should not happen)
- [ ] Event triggers at race end (should complete normally)
- [ ] Multiple events trigger simultaneously (should respect max_concurrent)
- [ ] Room loads during event (should have effect applied)
- [ ] Player enters room during event (should experience effect)

---

### Post-Launch Testing (Tier 2 Events)

- [ ] Random Teleport - players teleport with 1s fade
- [ ] Shuffle Players - positions swap correctly
- [ ] Portal Links - doors connect correctly
- [ ] Third Person - camera switches, motion sickness warning shown
- [ ] (Test all 15 Tier 2 events)

---

### Community Beta Testing

- [ ] 10+ community members test for 1 hour
- [ ] Collect feedback on event frequency
- [ ] Collect feedback on event duration
- [ ] Identify any motion sickness issues
- [ ] Identify any accessibility concerns
- [ ] Balance tweaks based on feedback

---

## Event Balance Matrix

### By Impact Level

| Impact | Events | Recommended Frequency |
|--------|--------|----------------------|
| **Low** (Minor) | Heavy Gravity, No Running, Silence, Color Shift, Earthquake | Every 60-90s |
| **Medium** (Adaptation) | Darkness, Fog, Locked Doors, Reversed, Slippery, Speed Up | Every 90-120s |
| **High** (Race-changing) | Sudden Death, Random Teleport, King of the Hill, No U-Turns | Every 120-180s |
| **Extreme** (Reset) | Shuffle Players, Event Storm, Grand Finale | Once per race max |

### By Player Sentiment

| Positive (Helpful) | Neutral (Challenge) | Negative (Hindrance) |
|--------------------|---------------------|---------------------|
| True Compass | Darkness | Locked Doors |
| Revealed Path | Fog | Heavy Gravity |
| Pathfinder | Reversed | No Running |
| Double Points | Rotating Rooms | Silence |
| King of the Hill | One-Way Doors | False Compass |
| Double Time | Slippery Floors | Sudden Death |
| Weather System | Earthquake | Random Teleport |
| Audio Surprise | Color Shift | Blindfolded |
| All Clear | Time Dilation | Mirror World |

**Recommended Mix**: 30% Positive, 50% Neutral, 20% Negative

---

## Launch Checklist

### Code Complete
- [ ] EventManager autoload implemented
- [ ] All 22 Tier 1 events implemented
- [ ] VoteHUD integration complete
- [ ] Accessibility options implemented
- [ ] Warning banner system working
- [ ] Gradual transitions working

### Testing Complete
- [ ] Single-player testing (all events)
- [ ] 2-player testing (all events)
- [ ] 4-player testing (all events)
- [ ] 8-player testing (sample events)
- [ ] Accessibility testing
- [ ] Edge case testing

### Documentation Complete
- [ ] This document saved to repo
- [ ] Event API documented
- [ ] Host configuration guide written
- [ ] Accessibility guide written

### Polish Complete
- [ ] Event icons created
- [ ] Sound effects added (warning chime, event start/end)
- [ ] UI animations smooth
- [ ] No console errors
- [ ] No performance issues

---

## Post-Launch Roadmap

### v0.5.0 (Launch)
- ✅ 22 Tier 1 events
- ✅ Full host configuration
- ✅ Accessibility options

### v0.6.0 (Month 1-2)
- ⏳ 15 Tier 2 events
- ⏳ Additional host presets
- ⏳ Community feedback balance tweaks

### v0.7.0+ (Month 3+)
- ⚠️ Tier 3 events (only if community requests)
- ⚠️ Custom event creation (advanced hosts)
- ⚠️ Event rotation (daily/weekly featured events)

---

## Conclusion

Environmental Events provide:
- ✅ **Chaos & excitement** (what community wants)
- ✅ **Zero sync nightmares** (broadcast-only architecture)
- ✅ **Dynamic loading safe** (events apply to new rooms automatically)
- ✅ **Fair for all players** (everyone affected equally)
- ✅ **Fully configurable** (hosts pick and choose)
- ✅ **Accessibility-safe** (no strobe, gradual transitions, warnings)

**Total Development Time**: 3-4 days for Tier 1 (22 events)  
**Risk Level**: 🟢 None (all events are unload-safe, accessibility-compliant)  
**Community Impact**: ⭐⭐⭐⭐⭐ (memorable moments, shared stories)

**Recommendation**: Proceed with Tier 1 implementation for v0.5.0 launch.

---

*Document Version: 1.0*  
*Last Updated: March 17, 2026*  
*Status: Ready for Implementation*
