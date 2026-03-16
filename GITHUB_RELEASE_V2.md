# Museum of All Things — v0.3.0 UI & Graphics Overhaul

## 🎨 What's New

A **complete visual transformation** with 4 new overlay systems, 4 rewritten components, and critical bug fixes.

### ✨ New Features
- **🎯 RaceCountdown** — Full-screen 3→2→1→GO countdown with elastic animations and target preview
- **📦 LoadingScreen** — Animated spinner with progress bar support
- **🏆 VictoryScreen** — Winner celebration with rotating starburst and room path
- **📊 LeaderboardHUD** — Press Tab to toggle session leaderboard
- **🏠 MainMenuBackground** — Animated backgrounds with floating cards and dust motes

### 🔄 Rewritten Components
- **VoteHUD** — Code-driven, staggered animations, custom loading spinner
- **RaceHUD** — Pulse ring timer, color-coded breadcrumbs, slide-in rooms
- **PlayerListOverlay** — Color-coded player dots, individual fade-ins
- **MainMenu** — Animated entrance sequence with elastic overshoot

### 🐛 Bug Fixes
- **Hint System Removed** — Multiplayer sync issues and door injection complexity (see notes below)
- **Race Win Detection** — Fixed single-player wins not triggering
- **Countdown Double-Fire** — Fixed broken animations from dual signal firing
- **LoadingScreen Flash** — Fixed black flash on vote start
- **Journal Dark Mode Crash** — Fixed crash when switching themes
- **Type Errors** — Fixed Array[String] and Dictionary issues
- **Off-Center Loading** — Fixed viewport centering

### 🎨 Polish
- Consistent panel styling across all UI
- Theme-aware backgrounds, borders, and shadows
- Minimap HUD now theme-aware with accent border

### ⚡ Performance
- Debug logs stripped in release builds
- LRU cache for article data (500 max)
- Memory leak prevention
- Faster network queue processing

---

## ⚠️ Important Notices

### Power-ups Temporarily Disabled
All 9 power-ups are **disabled for the foreseeable future**. They're being reworked for better balance and stability and will return in a future update.

### Hint/Backlink System Removed
The hint/backlink system has been **permanently removed** due to fundamental architectural issues:

1. **Multiplayer Sync:** Backlinks fetched on server, but door injection needed on clients → clients' HintManager always empty
2. **Door Injection Conflicts:** Injecting backlink doors conflicted with room generation, causing race conditions
3. **Fragile Signals:** `ExhibitFetcher.backlinks_complete` fired at unpredictable times
4. **Maintenance Burden:** Complexity outweighed benefits; code was brittle

**Result:** Pure Wikipedia navigation without artificial hints. Simpler and more reliable.

---

## 🛠️ Setup Required

Register these autoloads in Project Settings before running:
- `LoadingScreen` → `res://scenes/ui/LoadingScreen.tscn`
- `RaceCountdown` → `res://scenes/autoload/RaceCountdown.tscn`

---

## 📁 Files Changed

**New:** `RaceCountdown.gd/.tscn`, `LoadingScreen.gd/.tscn`, `LeaderboardHUD.gd`, `MainMenuBackground.gd`

**Rewritten:** `VictoryScreen.gd/.tscn`, `VoteHUD.gd/.tscn`, `RaceHUD.gd`, `PlayerListOverlay.gd/.tscn`

**Modified:** `MainMenu.gd`, `MultiplayerMenu.gd`, `MinimapHUD.gd`, `RaceManager.gd`, `Main.gd`, `JournalOverlay.gd`, `GraphicsSettings.gd`

**Removed:** `scenes/util/HintManager.gd`, `docs/HINT_SYSTEM_DESIGN.md` (archived)

---

## ✅ Testing Checklist

- [ ] Race countdown shows 3→2→1→GO before each race
- [ ] Target article appears under countdown
- [ ] Loading screen shows during vote resolution
- [ ] Victory screen appears on race win (not old popup)
- [ ] Leaderboard toggles with Tab key
- [ ] All menus have animated backgrounds
- [ ] Dark/light mode switching works on all new UI
- [ ] Single-player race win triggers correctly
- [ ] Multiplayer countdown syncs to all clients
- [ ] No console errors in debugger

---

## 🎮 Features Still Working

- 📅 Daily Challenge System
- 🔒 Anti-Cheat Measures
- 🚪 Search Corridor Door System
- 👥 Multiplayer Room Sync
- 📖 Journal System
- 🏆 Leaderboards
- 🎨 Dark/Light Mode

---

**Full changelog:** See `PATCH_NOTES.md` for detailed information.
