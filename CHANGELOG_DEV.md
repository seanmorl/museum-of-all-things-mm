# Changelog

## [Unreleased] - 2026-03-13

### 🎯 Major Changes

**Race & Spawn Improvements**
- Fixed player spawn position - now spawns directly on the raceline facing the search corridor door
- Players spread out on spawn (no more stacking on top of each other!)
- Reduced teleport delay from 4 seconds to ~1.5 seconds max
- Countdown is snappier (0.7s between numbers instead of 1.0s)
- Exhibit generation wait reduced from 10s to 0.5s

**Powerup Fixes**
- Perfect Knowledge now actually works - door labels show when activated!
- Spider Grapple physics improved - smoother swinging with damping
- All 9 powerups verified and working correctly
- TTS (text-to-speech) toggle working - press E to start/stop reading

**Graphics & Performance**
- Removed experimental SDFGI (was causing crashes on some hardware)
- Debug logs now stripped in release builds (better performance)
- LRU cache for article data (500 max, prevents memory leaks)
- Faster network queue processing (1 frame vs 9 frames)
- Fixed floor lights bug - entry/exit markers now properly hidden

**Bug Fixes**
- Fixed race_won signal argument mismatch
- Fixed Daily Challenge HUD light mode readability
- Fixed mount system for static seats (benches)
- Added proper error handling throughout
- Fixed timeline duplicate entries (start article only shows once)

### 📋 Code Quality

**Refactoring (from yesterday)**
- New service-based architecture
- EventBus for clean communication
- Proper state machine implementation
- Multiplayer room sync rewritten
- Player position sync with smooth interpolation

**New Services**
- RoomService - Room generation & sync
- NetworkService - Network abstraction
- ExhibitService - Exhibit lifecycle
- RaceService - Race logic & validation

### 🎨 UI Improvements

- Latest Changes title now readable in light mode
- Daily Challenge HUD text darker and more visible in light mode
- Daily Challenge Card subtext improved for light mode
- Patch notes updated with all recent improvements

### 🔧 Technical

- Logger.strip_debug_logs flag for release builds
- GraphicsManager no longer references SDFGI
- PlayerPowerupSystem grapple physics tuned (force: 20, damping: 0.95)
- Main.gd teleport functions optimized
- RaceManager countdown interval reduced

---

## Notes

- Aquarium panels and bubble tubes were attempted but proved too problematic to create via text files - scripts are ready if someone wants to create them in-editor
- All existing features still working: Daily Challenge, Anti-Cheat, 9 Power-ups, Search Corridor Door System
- Project should now load and run without errors

---

*Made with ☕ and occasional frustration over Godot scene file formats*
