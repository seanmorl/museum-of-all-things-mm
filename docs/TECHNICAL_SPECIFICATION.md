# Technical Specification: Museum of All Things

**Version:** 1.0  
**Last Updated:** April 2026

---

## 1. Overview

**Project Name:** Museum of All Things (Multiplayer)  
**Project Type:** 3D multiplayer game with VR support  
**Core Functionality:** Procedurally generated museum with Wikipedia-sourced content, multiplayer racing through article exhibits  
**Target Users:** Casual gamers, Wikipedia enthusiasts, VR users

---

## 2. Engine & Platform

### 2.1 Engine Requirements
- **Engine:** Godot 4.6+
- **Language:** GDScript 4.x with strict typing
- **Rendering:** Compatibility renderer for VR support
- **Export Platforms:** Windows, Linux (Flatpak), Meta Quest

### 2.2 Network Requirements
- **Protocol:** ENet UDP (for playit.gg compatibility)
- **Max Players:** 16 per session
- **Port Default:** 7777
- **Timeout Settings:** 32s timeout, 20s UDP re-auth

---

## 3. Architecture Specification

### 3.1 Autoload Singletons (Primary API)

| Autoload | Purpose |
|----------|---------|
| `NetworkManager` | ENet peer management, player info sync |
| `RaceManager` | Race state, voting, timers |
| `ExhibitFetcher` | Wikipedia API calls |
| `ThemeManager` | UI theming, dark mode |
| `SettingsManager` | Persisted settings |
| `JournalManager` | Journal entries |
| `HintManager` | Wiki hints system |
| `EventBus` | Central event dispatch |
| `Log` | Debug logging |
| `TTSManager` | Text-to-speech |
| `VoiceChatManager` | Voice chat (placeholder) |
| `LeaderboardManager` | Daily challenge scores |

### 3.2 Event System

All inter-system communication uses signals through EventBus:
- `GameplayEvents` - Mount, dismount, reactions
- `MultiplayerEvents` - Skin changes, player updates
- `UIEvents` - Menu interactions, errors
- `SettingsEvents` - Accessibility changes

### 3.3 Player Architecture

Player uses subsystem pattern for modularity:
```
Player.gd (main controller)
├── PlayerCrouchSystem
├── PlayerMountSystem
├── PlayerSkinSystem
├── PlayerPaintingSystem
├── PlayerPointingSystem
├── PlayerJournalSystem
└── PlayerFootprintSystem
```

---

## 4. Network Specification

### 4.1 Connection Flow
1. Host calls `NetworkManager.host_game(port)`
2. Clients call `NetworkManager.join_game(address, port)`
3. DNS resolution for hostnames (playit.gg support)
4. Peer info exchange via `_request_player_info` / `_receive_player_info`
5. Timeout set on ENet peer (32s timeout)

### 4.2 Position Sync
- **Interval:** 100ms throttle
- **Interpolation:** Lerp with 15.0 speed factor
- **Snap Threshold:** 5.0 units (teleport detection)

### 4.3 Security Measures
- Sender validation on all RPCs
- Path validation for race wins (anti-cheat)
- Rate limiting on host migration (30s cooldown)

---

## 5. UI/UX Specification

### 5.1 Input Support
- Keyboard (WASD, arrows, function keys)
- Gamepad (Xbox/PlayStation layout)
- VR controllers
- Mouse for menu navigation

### 5.2 Accessibility Features
- Colorblind correction shader (4 modes)
- Invert Y-axis option
- UI scale adjustment (Ctrl+=, Ctrl+-, Ctrl+0)
- Mouse sensitivity control

### 5.3 Post-Processing Effects
| Effect | Description |
|--------|-------------|
| CRT | Scanlines and curvature |
| Soft | Subtle glow |
| VHS | Retro tape distortion |
| PS1 | Low-poly aesthetic |

---

## 6. Exhibit System Specification

### 6.1 Wikipedia Integration
- **API:** Wikipedia REST API
- **Content:** Article text, images from Wikimedia Commons
- **Categories:** Pulled from article categories
- **Links:** Used for hallway connections

### 6.2 Exhibit Generation
- Grid-based room layout
- Wall plaques with article text
- Image frames from Commons
- Hallway doors to linked articles

---

## 7. Race System Specification

### 7.1 Vote Phase
- 5 candidates (configurable)
- 20 second timer
- Seeded shuffle for consistency
- Host can reroll

### 7.2 Race Phase
- 3-2-1-GO countdown
- Timer with event modifiers
- Win detection via room history
- Path validation anti-cheat

### 7.3 Difficulty Levels
| Difficulty | Article Pool |
|------------|-------------|
| Easy | Popular articles (high traffic) |
| Medium | Random articles |
| Hard | Stub articles (<1KB) |
| Random Category | From specific Wikipedia category |

---

## 8. Constants Reference

| Constant | Value | Location |
|----------|-------|----------|
| `VOID_Y_THRESHOLD` | -50.0 | Player.gd |
| `VOID_CHECK_INTERVAL` | 0.5s | Player.gd |
| `INTERPOLATION_SPEED` | 15.0 | Player.gd |
| `TELEPORT_SNAP_THRESHOLD` | 5.0 | Player.gd |
| `VOTE_DURATION` | 20.0s | RaceManager.gd |
| `CANDIDATE_COUNT` | 5 | RaceManager.gd |
| `MAX_PLAYERS` | 16 | Constants |
| `DEFAULT_PORT` | 7777 | Constants |

---

## 9. File Organization

### 9.1 Scene Structure
```
scenes/
├── Main.tscn              # Entry point
├── Museum.tscn            # Museum container
├── Player.tscn            # Player prefab
├── Lobby.tscn             # Start area
├── Hall.tscn              # Hallway between exhibits
├── StraightHall.tscn      # Long hallway variant
├── TiledExhibitGenerator.tscn  # Procedural room generator
└── items/
    ├── ImageItem.tscn     # Displayable images
    ├── TextItem.tscn      # Wall plaques
    ├── Terminal.tscn      # In-game terminal
    └── ...
```

### 9.2 Script Categories
- **Core (`scenes/core/`):** EventBus, GameState, Services
- **Util (`scenes/util/`):** All autoloads and managers
- **Menu (`scenes/menu/`):** UI screens and overlays
- **Main (`scenes/main/`):** Controllers (Multiplayer, Mount, etc.)
- **Items (`scenes/items/`):** Interactive objects

---

## 10. Performance Targets

| Metric | Target |
|--------|--------|
| Frame Rate | 60 FPS (desktop), 72 FPS (VR) |
| Network Latency | < 100ms for smooth interpolation |
| Memory Usage | < 2GB RAM |
| Load Time | < 5s per exhibit |

---

## 11. Testing Requirements

- Manual multiplayer testing with 2+ players
- Anti-cheat path validation testing
- VR compatibility testing
- Cross-platform export testing (Windows, Linux)

---

## 12. Known Limitations

- Voice chat placeholder (not player-facing)
- Power-ups disabled (v0.5.0)
- Services.gd deprecated (autoloads primary)
- Some UI created dynamically in code