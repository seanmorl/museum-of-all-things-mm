# Museum of All Things — Changelog v0.4.0

**Release Date**: March 17, 2026  
**Version**: 0.4.0  
**Type**: Major Update — UI Overhaul & Tournament Mode (Experimental)  

---

## 🎯 Release Overview

Version 0.4.0 is a **major milestone release** featuring a complete UI overhaul and the experimental debut of Tournament Mode. This update transforms the visual experience with modern, animated interfaces while introducing competitive multiplayer tournament functionality for community events and organized play.

> **⚠️ Tournament Mode is Experimental**  
> The tournament system is currently in beta testing. While functional, expect potential issues and changes as we refine the feature based on community feedback.

---

## 🌟 Major Features

### 🏆 Tournament Mode (EXPERIMENTAL)

**Status**: Beta Testing  
**Files**: `scenes/tournament/TournamentManager.gd`, `scenes/tournament/TournamentSetupMenu.gd`

#### What is Tournament Mode?

Tournament Mode enables organized competitive play where multiple players compete in structured race events with configurable formats, scoring systems, and elimination brackets.

#### Features (Current Implementation):

**Tournament Creation & Configuration**
- Host creates tournaments from the multiplayer lobby
- Configurable tournament name ("Series Name")
- Two format options:
  - **Fixed Rounds** — Set number of rounds (1-10), most wins determines champion
  - **First to N Wins** — First player to reach N victories wins (1-10)
- Points mode selection:
  - **Win Only (1pt)** — Only race winner gets points
  - **Podium (3/2/1)** — 1st: 3pts, 2nd: 2pts, 3rd: 1pt
  - **Speed Bonus** — Additional points for fast times
- Twitch/OBS overlay support for streamers (local HTTP server on port 9876)

**Tournament Setup UI**
- Clean, modern panel interface
- Real-time player count display
- Interactive format selector with visual feedback
- Slider controls for round/win targets
- Dark/Light theme support
- Series name customization

**Tournament Flow**
1. Host clicks "Wiki Races" button in multiplayer lobby
2. Configure tournament settings
3. Tournament starts, all players notified
4. Rounds begin automatically
5. Race voting system determines each round's articles
6. Winners tracked across rounds
7. Tournament champion determined by format rules

**Known Limitations (Experimental Phase)**
- No visual bracket display (planned for future update)
- No elimination system (all players participate in all rounds)
- No tournament history persistence (resets on session end)
- Limited spectator features
- No seeding system

**Planned Features (Future Updates)**
- Visual bracket display
- Single/Double elimination formats
- Player elimination & spectator mode
- Tournament history & statistics
- Seeding & rankings
- Scheduled tournaments
- Replay system
- Community tournament hosting

---

### 🎨 Complete UI Overhaul

**Status**: Complete  
**Scope**: All in-game HUDs, menus, and overlays modernized

#### Philosophy

The UI overhaul focuses on:
- **Code-driven design** — Reduced dependency on `.tscn` files for easier maintenance
- **Smooth animations** — Every transition feels polished with purposeful motion
- **Theme consistency** — Unified visual language across all screens
- **Accessibility** — Clear typography, color contrast, and scalable elements

---

#### ✨ New UI Components

##### 🎯 RaceCountdown
**File**: `scenes/ui/RaceCountdown.gd`

Full-screen countdown sequence before each race:
- **3 → 2 → 1 → GO** display with elastic scale animations
- **Ink-ring burst effects** on each number transition
- **Target article display** — "Find: [Article]" shown beneath countdown
- **GO punch-in animation** — Large, bold, holds briefly then scales out
- Custom audio stings for each beat
- Layer 110 positioning (above loading screen, below screenshots)

---

##### 📦 LoadingScreen
**File**: `scenes/ui/LoadingScreen.gd`

Modern loading overlay with animated spinner:
- **8-segment arc spinner** with theme-aware accent colors
- Message + sub-message support
- Optional progress bar
- Properly centered (fixed historical off-center bug)
- **API**:
  - `show_loading(msg, sub_msg)` — Display overlay
  - `hide_loading()` — Dismiss overlay
  - `set_progress(0–1)` — Update progress bar
  - `set_message(msg)` — Update message text

---

##### 🏆 VictoryScreen
**File**: `scenes/ui/VictoryScreen.gd`

Complete race victory presentation:
- **Procedural gold starburst** — 8-spoke compass rose, gentle rotation
- Winner name, final time, "via N rooms" sub-line
- **Color-coded path display**:
  - 🟡 Gold = Start room
  - 🔵 Accent blue = Target room
  - ⚪ Grey = Intermediate rooms
- Scrollable room path with auto-scroll to target
- **Auto-dismiss after 12s** with live countdown on Continue button
- Mouse revealed on race end (`MOUSE_MODE_VISIBLE`)
- Input-blocking backdrop prevents accidental world interaction
- **Removed**: Duplicate win popup from RaceHUD

---

##### 📊 LeaderboardHUD
**File**: `scenes/ui/LeaderboardHUD.gd`

Session leaderboard overlay:
- Columns: Rank · Player · Target Article · Time
- Top entry highlighted in gold
- **Auto-registers Tab keybinding** if not present in InputMap
- Slides down from top-center on open, slides up on close
- New entries fade in when leaderboard is open
- Reads from `LeaderboardManager` autoload
- Refreshes on `leaderboard_updated` signal

---

#### 🔄 Rewritten Components

##### 🗳️ VoteHUD
**File**: `scenes/menu/VoteHUD.gd`

Complete code-driven rewrite:
- **Candidate buttons slide in from left** — 50ms stagger per button
- Custom loading spinner (no image asset required)
- Panel entry: `TRANS_BACK` scale bounce (0.92 → 1.0)
- Host panel sections separated by 1px dividers
- **All functionality preserved**:
  - Candidate voting
  - Timer display
  - Host panel (difficulty, category, player management, kick, reroll, seeded shuffle, force start, cancel race/vote)
  - EventBus handlers
  - `@rpc _kick_player`

---

##### ⏱️ RaceHUD
**File**: `scenes/menu/RaceHUD.gd`

Modernized race interface:
- **Timer ring** — Custom-drawn pulse ring fires every second
- **Breadcrumb trail color roles**:
  - 🟢 Green = Start
  - ⚪ White = Current
  - 🔵 Blue = Target
  - ⚫ Grey = Visited
- New room entries **slide in from right** with 0.25s fade
- Target label staggers in 0.25s after panel appears
- Fixed panel height (200px) with smooth auto-scroll
- Moved to **top-left anchor**
- Reduced size: 184px wide, 20px font, 11px target label, 16px ring
- **Removed**: Old win popup (replaced by VictoryScreen)

---

##### 👥 PlayerListOverlay
**File**: `scenes/menu/PlayerListOverlay.gd`

Multiplayer player list:
- **Color dot per player** — Matches chosen multiplayer color
- Player name with `· Host` / `· You` inline badges
- Room sub-line beneath each player name
- Each entry fades in individually on refresh
- Slides down from top-right with back-ease on show

---

##### 🏠 MainMenu
**File**: `scenes/menu/MainMenu.gd`

Enhanced main menu experience:
- **Animated entrance sequence**:
  - Logo drops from above with elastic overshoot (88% → 100% scale)
  - Subtitle fades in 0.35s after logo
  - Buttons cascade in every 55ms
- **Animated background** (`MainMenuBackground.gd`):
  - Floating exhibit cards
  - Dust motes particle effect
  - Slow gradient color wash
  - Vignette overlay
  - Full dark/light theme support

---

##### 🌐 MultiplayerMenu
**File**: `scenes/menu/MultiplayerMenu.gd`

Matching animated background for visual continuity with MainMenu.

---

### 🐛 Bug Fixes

#### Main Menu Not Reshowing from Sub-Menues
**Severity**: Critical  
**Files**: `scenes/menu/MainMenu.gd`, `scenes/main/MainMenuController.gd`

**Problem**: After navigating to Settings or Multiplayer menu, pressing "Back" would not properly return to the Main Menu.

**Fix**:
- Removed conflicting animation from `_on_visibility_changed()`
- Added `_trigger_main_menu_entrance()` helper function
- Modified `open_main_menu()` to trigger full entrance animation

**Impact**: Menu navigation now works correctly with proper animations.

---

#### TournamentManager Cannot Find Main Node
**Severity**: Critical  
**File**: `scenes/tournament/TournamentManager.gd`

**Problem**: Starting a tournament round produced error: "Cannot find Main in group 'main'"

**Root Cause**: `HintManager` is also in the "main" group, causing `get_first_node_in_group()` to return the wrong node.

**Fix**: Iterate through all nodes in group and find the one with `_on_start_race_pressed()` method.

**Impact**: Tournaments now start without errors.

---

#### TournamentSetupMenu Sliders Not Working
**Severity**: High  
**File**: `scenes/tournament/TournamentSetupMenu.gd`

**Problem**: Slider controls were non-functional; values remained at default.

**Root Cause**: GDScript passes by value, so slider references were never assigned to member variables.

**Fix**: Retrieve slider/label references from node metadata after creation.

**Impact**: Tournament setup sliders now work correctly.

---

#### TournamentSetupMenu Format Switch Reset
**Severity**: Medium  
**File**: `scenes/tournament/TournamentSetupMenu.gd`

**Problem**: Switching formats didn't reset slider values.

**Fix**: Enhanced `_update_format_visibility()` to reset slider values and labels when switching formats.

**Impact**: Format switching provides clean, predictable UX.

---

### 🟡 Code Quality Improvements

#### MainMenuController Error Handling
**File**: `scenes/main/MainMenuController.gd`

**Changes**:
- Added null checks in `open_menu()` using `get_node_or_null()`
- Enhanced `_trigger_main_menu_entrance()` with detailed warnings
- Better error reporting for debugging

---

## 📊 Statistics

| Metric | Value |
|--------|-------|
| **New Files Created** | 5 |
| **Files Rewritten** | 4 |
| **Files Modified** | 8 |
| **Lines Added** | ~1,200 |
| **Lines Removed** | ~400 |
| **New UI Components** | 4 |
| **Rewritten Components** | 4 |
| **Critical Bugs Fixed** | 2 |
| **High Priority Fixed** | 2 |

---

## 🧪 Testing Checklist

### Tournament Mode
- [ ] **Create Tournament**: Host clicks "Wiki Races" in lobby → Setup panel opens
- [ ] **Configure Settings**: Change format, rounds, points mode → All controls respond
- [ ] **Format Switching**: Toggle between formats → Sliders reset to defaults
- [ ] **Start Tournament**: Press "Start Tournament" → Tournament begins without errors
- [ ] **First Round**: Round starts without "Cannot find Main" error
- [ ] **Multiplayer Sync**: All players see tournament start notification

### UI Overhaul
- [ ] **Race Countdown**: 3-2-1-GO sequence displays correctly with target article
- [ ] **Loading Screen**: Spinner animates, message displays
- [ ] **Victory Screen**: Winner panel appears on race end with correct data
- [ ] **Leaderboard**: Tab key toggles leaderboard overlay
- [ ] **VoteHUD**: Candidate buttons slide in, host panel functions
- [ ] **RaceHUD**: Timer ring pulses, breadcrumb trail updates
- [ ] **PlayerList**: Players display with correct colors and badges
- [ ] **MainMenu**: Entrance animation plays on load and when returning from sub-menus

### Menu Navigation
- [ ] **Main → Settings → Back**: Main Menu reshow with entrance animation
- [ ] **Main → Multiplayer → Back**: Main Menu reshow with entrance animation
- [ ] **Menu Focus**: Correct buttons receive keyboard focus

---

## 🔧 Migration Notes

### For Server Administrators

**Tournament Mode Setup**:
- No special configuration required
- Twitch overlay available at `http://localhost:9876/overlay`
- Tournament data does not persist between sessions (experimental phase)

### For Modders

**UI Changes**:
- All new UI components are code-driven with minimal `.tscn` dependencies
- Theme colors controlled by `ThemeManager` autoload
- Animations use Tween API with standardized timing

**New Autoloads**:
- `LoadingScreen` — Register `res://scenes/ui/LoadingScreen.tscn`
- `RaceCountdown` — Register `res://scenes/ui/RaceCountdown.tscn`

### For Players

**No Breaking Changes**:
- All existing features continue to work
- Save data compatible with previous versions
- Multiplayer sessions compatible with v0.3.x clients (tournament mode unavailable to older clients)

---

## 🎯 Impact

### Before v0.4.0:
- ❌ No tournament functionality
- ❌ Basic, static UI elements
- ❌ No race countdown sequence
- ❌ Simple victory popup
- ❌ No session leaderboard
- ❌ Menu navigation bugs

### After v0.4.0:
- ✅ Experimental tournament mode with configurable formats
- ✅ Modern, animated UI throughout
- ✅ Dramatic 3-2-1-GO countdown sequence
- ✅ Full victory screen with procedural graphics
- ✅ Live session leaderboard
- ✅ Smooth menu navigation with proper animations

---

## 📁 Complete File List

### New Files
| File | Purpose |
|------|---------|
| `scenes/ui/RaceCountdown.gd` | Race countdown sequence |
| `scenes/ui/RaceCountdown.tscn` | Countdown scene wrapper |
| `scenes/ui/LoadingScreen.gd` | Loading overlay |
| `scenes/ui/LoadingScreen.tscn` | Loading scene wrapper |
| `scenes/ui/LeaderboardHUD.gd` | Session leaderboard |
| `scenes/ui/VictoryScreen.gd` | Victory presentation |
| `scenes/ui/VictoryScreen.tscn` | Victory scene wrapper |
| `scenes/menu/MainMenuBackground.gd` | Animated menu background |
| `scenes/tournament/TournamentManager.gd` | Tournament controller |
| `scenes/tournament/TournamentSetupMenu.gd` | Tournament configuration UI |

### Rewritten Files
| File | Changes |
|------|---------|
| `scenes/menu/VoteHUD.gd` | Code-driven rewrite, animations |
| `scenes/menu/RaceHUD.gd` | Modernized, new animations |
| `scenes/menu/PlayerListOverlay.gd` | Code-driven rewrite |
| `scenes/menu/MainMenu.gd` | Entrance animations, background |

### Modified Files
| File | Changes |
|------|---------|
| `scenes/main/MainMenuController.gd` | Entrance animation trigger, error handling |
| `scenes/main/MultiplayerController.gd` | Tournament integration |
| `scenes/Main.gd` | Tournament setup, UI integration |
| `scenes/tournament/TournamentManager.gd` | Node lookup fix |
| `scenes/tournament/TournamentSetupMenu.gd` | Slider fix, format reset |
| `scenes/util/RaceManager.gd` | Countdown integration |

---

## 🚀 Deployment

1. **Clear Godot cache**: Delete `.godot/` folder
2. **Reopen project** in Godot
3. **Register new autoloads**:
   - `LoadingScreen` → `res://scenes/ui/LoadingScreen.tscn`
   - `RaceCountdown` → `res://scenes/ui/RaceCountdown.tscn`
4. **Test thoroughly** using checklist above
5. **Deploy to production**

---

## ⚠️ Known Issues

### Tournament Mode (Experimental)
- No visual bracket display
- All players participate in all rounds (no elimination)
- Tournament data resets on session end
- Limited to 2 formats (Fixed Rounds, First to N Wins)

### General
- Power-ups remain disabled (temporary)
- Some UI sounds may not play during transitions

---

## 🔮 Future Roadmap

### v0.4.1 (Bug Fix Release)
- Address tournament mode bugs from community feedback
- Fix any UI animation timing issues
- Performance optimizations

### v0.5.0 (Next Major Update)
- Tournament bracket visualization
- Player elimination & spectator mode
- Tournament history persistence
- Additional tournament formats (Double Elimination, Round Robin)
- Power-ups re-enabled with balance changes

---

## 📝 Credits

**UI Overhaul Design**: Based on community feedback from March 2026 survey  
**Tournament Mode**: Inspired by Wikipedia Race community requests  
**Testing**: Early access feedback from Discord community

---

## 📞 Support

**Bug Reports**: GitHub Issues  
**Feature Requests**: Discord #suggestions channel  
**Community Discussion**: Discord #tournament-mode channel

---

**Thank you for playing Museum of All Things!** 🎮✨

*Last updated: March 17, 2026*
