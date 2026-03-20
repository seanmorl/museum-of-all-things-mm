# Powerup System Documentation

## Overview
The powerup system adds collectible items that spawn throughout the museum, providing temporary advantages or one-use abilities.

## Powerup Types

### ⚡ Speed Boost (Yellow)
- **Duration:** 2 minutes (120 seconds)
- **Effect:** Doubles player movement speed (walk and dash)
- **Visual:** Player moves noticeably faster
- **Use Case:** Quick exploration, escaping enemies, reaching race targets faster

### 👁 Perfect Knowledge (Cyan)
- **Duration:** 90 seconds  
- **Effect:** Reveals all hallway room names through walls
- **Visual:** Hallway signs (EntryLabel, ExitLabel, FromSign, ToSign) become visible
- **Use Case:** Navigation advantage, finding optimal paths during races

### 🔫 Teleport Gun (Red)
- **Duration:** One shot (consumed on use)
- **Effect:** Shoot a hitscan projectile that teleports the hit player back to the lobby
- **Controls:** Press Q (point button) while aiming at target
- **Visual:** Red projectile beam effect on fire
- **Use Case:** Eliminating competitors, defensive tool

### 💣 Teleport Trap (Green)
- **Duration:** One use (consumed on trigger)
- **Effect:** Place an invisible trap that teleports enemies to lobby when triggered
- **Controls:** Press Q (point button) while aiming at floor
- **Visual:** Green glowing disk (visible after 1 second arm delay)
- **Arm Time:** 1 second (trap is invisible and harmless during this time)
- **Trigger Radius:** 1.5 meters
- **Use Case:** Area denial, protecting objectives, ambushes

## How It Works

### Spawning
- **Automatic:** Powerups spawn every 30 seconds in exhibit rooms
- **Max Active:** 4 powerups can exist at once
- **Spawn Points:** Looks for nodes named `PowerupSpawn*` in rooms, or uses room center
- **Server Only:** Spawning happens on the server to prevent cheating

### Collection
- Powerups are collected by walking into them
- Collection triggers a pickup animation (scale up + fade out)
- Powerup state is tracked per-player via `PowerupManager`

### HUD Display
- **Location:** Top-left corner of screen
- **Display:** Shows icon, name, and timer for each active powerup
- **Timers:** Count down in real-time (MM:SS format for long durations)

## Code Architecture

### Files
```
scenes/
├── util/
│   └── PowerupManager.gd          # Autoload singleton
├── player/
│   └── PlayerPowerupSystem.gd     # Player subsystem
├── items/
│   ├── PowerupPickup.gd/.tscn     # Collectible item
│   └── PowerupTrap.gd/.tscn       # Trap object
└── ui/
    └── PowerupHUD.gd/.tscn        # HUD overlay
```

### PowerupManager (Autoload)
- Tracks active powerups per player
- Manages spawn timers and limits
- Handles powerup duration timers
- Emits signals: `powerup_collected`, `powerup_activated`, `powerup_expired`, `powerup_used`

### PlayerPowerupSystem
- Attached to each player
- Applies powerup effects (speed boost, perfect knowledge visibility)
- Handles gun firing and trap placement
- Syncs with PowerupManager for state

### Integration Points
- **Player.gd:** Has powerup subsystem, handles input for gun/trap
- **Main.gd:** Should integrate PowerupHUD into UI layer
- **Network:** Uses `multiplayer.is_server()` for authority checks

## Adding Powerup Spawn Points

In your exhibit/room scenes, add spawn points:

```gdscript
# In your room .tscn file:
[node name="PowerupSpawn1" type="Node3D"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 2, 0.5, 3)

[node name="PowerupSpawn2" type="Node3D"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -2, 0.5, -3)
```

Place these at floor level where you want powerups to appear.

## Customization

In `PowerupManager.gd`, adjust:
```gdscript
var _spawn_interval: float = 30.0  # Seconds between spawn attempts
var _max_powerups: int = 4         # Maximum concurrent powerups

const POWERUP_DURATIONS := {
    PowerupType.SPEED_BOOST: 120.0,
    PowerupType.PERFECT_KNOWLEDGE: 90.0,
    PowerupType.GUN: -1.0,         # -1 = instant/one-use
    PowerupType.TRAP: -1.0,
}

const SPEED_BOOST_MULTIPLIER: float = 2.0  # Speed multiplier
```

## Signals to Connect

```gdscript
PowerupManager.powerup_collected.connect(_on_powerup_collected)
PowerupManager.powerup_expired.connect(_on_powerup_expired)
PowerupManager.powerup_used.connect(_on_powerup_used)
```

## Future Enhancements

Consider adding:
- Sound effects for pickup/activation/expiry
- Particle effects for speed boost trail
- Visual indicator for perfect knowledge (shader effect?)
- More powerup types (invisibility, speed freeze, etc.)
- Powerup rarity system
- Audio cues when trap is triggered
