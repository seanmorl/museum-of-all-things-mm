# Existing Code: Museum of All Things

**Version:** v0.3.5 (Current)  
**Date:** May 2026

---

## Overview

This document catalogs the current codebase as implemented following the original plan. The implementation consists of approximately 200+ GDScript files organized across scenes, utilities, menus, and core systems.

---

## Directory Structure

```
museum-of-all-things-mm/
├── addons/                    # Godot addons
│   ├── discord-rpc-gd/        # Discord Rich Presence (disabled)
│   └── discord_social_sdk/     # Discord integration
├── assets/                    # Resources
│   ├── models/mannequin/      # Player model
│   ├── resources/             # .tres files
│   ├── sound/UI/              # UI sound effects
│   ├── textures/              # Images and shaders
│   └── translations/          # Localization .po files
├── docs/                      # Documentation
├── resource_definitions/      # Resource script classes
├── scenes/                    # Main scene files
├── scripts/                   # Standalone scripts
├── shaders/                   # Shader files
└── linux/                     # Linux-specific files
```

---

## Core Systems

### 1. Entry Point: Main.tscn / Main.gd

**Lines:** ~1400+ (monolithic)  
**Responsibilities:**
- Game initialization and state management
- Player creation and management
- Menu control (MainMenuController)
- Multiplayer coordination (MultiplayerController)
- Race management and voting
- Tournament/Daily Challenge UI
- Accessibility (colorblind, invert Y, UI scale)
- Input handling (~50+ actions)

**Key Signals:**
- `game_start_requested`
- `multiplayer_start_requested`
- `race_started`, `race_won`, `vote_cancelled`

**Key Methods:**
- `_start_game()` - Initiates gameplay
- `_recreate_player()` - Spawns player node
- `_on_race_started()` - Handles race start with countdown
- `_input()` - Central input processing

### 2. Player Controller: Player.tscn / Player.gd

**Lines:** ~1000  
**Architecture:** Subsystem pattern

**Subsystems:**
| Subsystem | File | Purpose |
|-----------|------|---------|
| Crouch | `player/PlayerCrouchSystem.gd` | Sneaking mechanics |
| Mount | `player/PlayerMountSystem.gd` | Ride other players |
| Skin | `player/PlayerSkinSystem.gd` | Custom player skins |
| Painting | `player/PlayerPaintingSystem.gd` | Steal/place paintings |
| Pointing | `player/PlayerPointingSystem.gd` | Reactions/emotes |
| Journal | `player/PlayerJournalSystem.gd` | Journal pin system |
| Footprint | `player/PlayerFootprintSystem.gd` | Ghost placement |

**Key Properties:**
- `mounted_on`, `mounted_by` - Mount state
- `is_carrying_painting` - Painting system state
- `current_room` - Room tracking for anti-cheat

**Key Methods:**
- `pause()`, `start()` - Enable/disable input
- `_teleport_to_safety()` - Void detection recovery

### 3. Network System: NetworkManager.gd

**Lines:** ~750  
**Protocol:** ENetMultiplayerPeer (UDP)

**Key Features:**
- DNS resolution for hostname support
- Keepalive pings (5s interval)
- Connection watchdog (15s timeout)
- ENet timeout configuration (32s timeout, 20s re-auth)
- Host migration with state transfer
- Anti-spoofing validation on all RPCs

**Key Signals:**
- `peer_connected`, `peer_disconnected`
- `connection_succeeded`, `connection_failed`
- `player_info_updated`, `player_room_changed`

**Key Methods:**
- `host_game(port, dedicated)` - Start server
- `join_game(address, port)` - Connect to server
- `get_server_address()` - Get LAN IP for sharing

### 4. Race System: RaceManager.gd

**Lines:** ~980  
**Purpose:** Vote management, race timing, win detection

**States:** `IDLE`, `ACTIVE`  
**Vote:** 5 candidates, 20-second timer

**Key Signals:**
- `race_started`, `race_won`, `race_ended`
- `vote_started`, `vote_ended`, `vote_cancelled`
- `target_determined` (for hint prefetch)

**Key Methods:**
- `begin_vote()` - Start vote round
- `start_race()` - Initiate race with countdown
- `notify_article_reached()` - Win detection with anti-cheat
- `_validate_path_continuity()` - Anti-cheat validation

**Anti-Cheat:**
- Server tracks room history per peer
- Path validation prevents teleportation exploits
- Requires at least one room transition

### 5. Exhibit System: Museum.tscn / ExhibitFetcher.gd

**Purpose:** Wikipedia API integration and exhibit generation

**API Endpoints:**
- `/page/summary` - Article summary
- `/parse` - Full wikitext
- `/category/members` - Category articles
- Wikimedia Commons for images

**Key Methods:**
- `fetch(articles, context)` - Fetch article data
- `fetch_random(context)` - Random article
- `fetch_random_from_category(category, context)` - Category-based
- `has_result()`, `get_result()` - Cache access

### 6. Event Bus: EventBus.gd

**Location:** `scenes/core/EventBus.gd`  
**Pattern:** Central signal dispatcher

**Sub-EventBuses (autoloads):**
- `GameplayEvents` - Gameplay signals
- `MultiplayerEvents` - MP-specific signals
- `UIEvents` - UI interaction signals
- `SettingsEvents` - Settings change signals

**GameEvent Pattern:**
```gdscript
class_name GameEvent
extends RefCounted

class RaceStartedEvent extends GameEvent:
    var target_article: String
    var start_article: String
```

---

## UI System

### Menu Structure

| Menu | Script | Purpose |
|------|--------|---------|
| MainMenu | `menu/MainMenu.gd` | Entry point |
| MultiplayerMenu | `menu/MultiplayerMenu.gd` | Host/Join UI |
| HostMenu | `menu/HostMenu.gd` | In-game host controls |
| Settings | `menu/Settings.gd` | Settings panel |
| PauseMenu | `menu/PauseMenu.gd` | In-game pause |
| JournalOverlay | `menu/JournalOverlay.gd` | Exhibit journal |
| VoteHUD | `menu/VoteHUD.gd` | Race target voting |
| RaceHUD | `menu/RaceHUD.gd` | Race timer/standings |

### Overlays

| Overlay | Script | Purpose |
|---------|--------|---------|
| RaceCountdown | `ui/RaceCountdown.tscn` | 3-2-1-GO display |
| LoadingScreen | `ui/LoadingScreen.tscn` | Loading indicator |
| DebugConsole | `ui/DebugConsole.tscn` | Debug commands |
| EventWarningBanner | `ui/EventWarningBanner.tscn` | Event alerts |

---

## Archive Status

### Archived Code (Do Not Use)
- `scenes/_archived_services_OLD/` - Old service layer (deprecated)
- `scenes/_archive_player_v1/` - Old player implementation
- `scenes/_archived_services_OLD/RaceService.gd` - Replaced by RaceManager
- `scenes/_archived_services_OLD/NetworkService.gd` - Replaced by NetworkManager
- `scenes/_archived_services_OLD/RoomService.gd` - Replaced by direct calls

### Archived Power-ups
- `scenes/_archived_powerups_OLD/` - Disabled power-up system
- References cleaned from Player.gd and Main.gd

---

## Key Implementation Notes

### 1. Memory Leak Prevention
All signal connections use `is_connected()` guards before disconnecting in `_exit_tree()`:
```gdscript
func _exit_tree() -> void:
    if SettingsEvents.set_invert_y.is_connected(_set_invert_y):
        SettingsEvents.set_invert_y.disconnect(_set_invert_y)
```

### 2. Signal Cleanup Pattern
```gdscript
func connect_signal(sig: Signal, callback: Callable) -> void:
    if not sig.is_connected(callback):
        sig.connect(callback)
```

### 3. Void Detection
Player.gd tracks last valid position and teleports back when Y < -50:
```gdscript
const VOID_Y_THRESHOLD: float = -50.0
const VOID_CHECK_INTERVAL: float = 0.5
```

### 4. Network Security
All RPCs validate sender identity:
```gdscript
@rpc("any_peer", "call_local", "reliable")
func _broadcast_player_room(peer_id: int, room: String) -> void:
    var sender_id := multiplayer.get_remote_sender_id()
    if sender_id != 0 and sender_id != peer_id:
        Log.warn("Network", "Rejected spoofed room update")
        return
```

### 5. Main.gd Direct Calls
Player.gd uses `get_tree().current_scene` to call Main methods:
```gdscript
func request_mount(target: Node) -> void:
    var main_node: Node = get_tree().current_scene
    if main_node and main_node.has_method("_request_mount"):
        main_node._request_mount(target)
```
**Note:** This violates event-driven architecture but is used for mount/steal/paint interactions.

---

## Dependency Graph

```
Main.gd
├── MainMenuController
├── MultiplayerController
├── MountController
├── PaintingController
├── PointingController
├── ChatSystem
├── ChatHUD
├── TriviaManager
├── TournamentManager
├── DailyChallengeManager
├── RaceManager (autoload)
├── NetworkManager (autoload)
├── ExhibitFetcher (autoload)
└── ThemeManager (autoload)

Player.gd
├── PlayerCrouchSystem
├── PlayerMountSystem
├── PlayerSkinSystem
├── PlayerPaintingSystem
├── PlayerPointingSystem
├── PlayerJournalSystem
└── PlayerFootprintSystem

NetworkManager.gd
├── RaceManager
├── Services (deprecated)
└── Logger

RaceManager.gd
└── NetworkManager
└── EventBus
```

---

## File Counts

| Category | Count | Examples |
|----------|-------|----------|
| Core Scripts | 5 | EventBus.gd, GameState.gd, Services.gd |
| Autoloads | 25+ | NetworkManager, RaceManager, ThemeManager |
| Menu Scripts | 20+ | MainMenu, MultiplayerMenu, PauseMenu |
| Item Scripts | 30+ | ImageItem, Bench, Terminal |
| Player Systems | 7 | Crouch, Mount, Skin, etc. |
| Tests | 6 | EventTests, ExhibitTestScene |
| Archived | 10+ | Old services, old player |

---

## Known Technical Debt

1. **Main.gd size** - 1400+ lines, handles too many responsibilities
2. **Direct Main references** - Player.gd calls Main via get_tree().current_scene
3. **Services.gd** - Deprecated but still initialized
4. **Dynamic UI creation** - Some UI created in code, not scenes
5. **Large handler methods** - Some input handling is complex

---

*This document reflects the current state of the codebase as of v0.3.5*