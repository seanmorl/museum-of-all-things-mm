# Implementation Plan: Museum of All Things

**Created:** Based on codebase analysis  
**Version:** v0.3.5 - Code Quality & Sticky Notes

---

## Overview

The Museum of All Things is a multiplayer VR/flat game where players race through Wikipedia article exhibits. The implementation followed these key phases:

### Phase 1: Core Game Foundation
- Player controller with movement, jumping, crouching
- Museum/Exhibit generation system
- Wikipedia article fetching and display
- Hallway/door navigation between exhibits

### Phase 2: Multiplayer Implementation
- ENet-based networking with UDP support
- Player synchronization and interpolation
- Host migration and reconnection handling
- Player customization (names, colors, skins)

### Phase 3: Race System
- Vote-based target article selection
- Race countdown and timer
- Win detection with anti-cheat path validation
- Daily challenges and leaderboards

### Phase 4: UI/UX Polish
- Theme-aware styling via ThemeManager
- Accessibility features (colorblind, invert y, UI scaling)
- Multiple input support (keyboard, gamepad, VR)
- Post-processing effects (CRT, VHS, soft, PS1)

### Phase 5: Advanced Features
- Mounting system (ride other players)
- Painting/stealing system
- Journal and sticky notes
- Tournament mode infrastructure
- Spectator mode

---

## Key Implementation Decisions

1. **Autoloads over Services** - Direct singleton access for all game systems
2. **Subsystem architecture** - Player.gd delegates to specialized systems
3. **Event-driven communication** - EventBus for decoupling
4. **Anti-cheat first** - Path validation, sender validation on all RPCs
5. **Async where possible** - Non-blocking Wikipedia fetches

---

## Technical Stack

- **Engine:** Godot 4.6
- **Language:** GDScript 4.x with type hints
- **Network:** ENetMultiplayerPeer (UDP)
- **3D Renderer:** Compatibility mode for VR support

---

## File Structure

```
museum-of-all-things-mm/
├── scenes/
│   ├── Main.gd              # Central game controller
│   ├── Player.gd            # Player controller + subsystems
│   ├── Museum.gd            # Exhibit management
│   ├── core/
│   │   ├── EventBus.gd      # Central event system
│   │   ├── GameState.gd     # State machine
│   │   └── Services.gd      # Archived service locator
│   ├── menu/                # All UI menus
│   ├── util/                # Managers (Race, Network, etc.)
│   └── items/               # Game objects (ImageItem, Bench, etc.)
├── docs/                    # Architecture and roadmap docs
└── assets/                  # Textures, shaders, sounds
```

---

## Implementation Notes

- Main.gd handles multiple responsibilities (menu, multiplayer, race, accessibility)
- Player.gd uses subsystem pattern for modularity
- Archived code in `_archived_*` directories for reference
- Signal-based memory leak prevention implemented