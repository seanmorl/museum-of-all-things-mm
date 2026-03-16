# Museum of All Things — Patch Notes

## 🎨 UI & Graphics Overhaul — March 2026

### ✨ New Screens & Overlays

#### 🎯 RaceCountdown
- **New full-screen countdown autoload** (`RaceCountdown.gd` / `.tscn`)
- Displays **3 → 2 → 1 → GO** before each race begins
- Each number scales in with **elastic overshoot** and fires an **ink-ring burst** on impact
- **"Find: [Article]"** sub-line fades in beneath the 3, showing the race target before the whistle
- **GO punches in** large, holds briefly, then scales out as the backdrop fades away
- Target article injected from `Main.gd` via `set_target()` on `vote_ended` signal
- **Layer 110** — above LoadingScreen, below screenshot flash

#### 📦 LoadingScreen
- **New full-screen loading overlay autoload** (`LoadingScreen.gd` / `.tscn`)
- **Custom animated spinner** (8 arc segments, theme-aware accent colour)
- Shows message + optional sub-message, optional progress bar
- Card centred correctly using symmetric 0.5 anchors (fixed off-centre bug)
- **API:**
  - `show_loading(msg, sub)` — Display loading overlay
  - `hide_loading()` — Dismiss overlay
  - `set_progress(0–1)` — Update progress bar
  - `set_message()` — Update message text
- **Setup required:** Register at `res://scenes/ui/LoadingScreen.tscn` as Autoload named `LoadingScreen`

#### 🏆 VictoryScreen
- **Full code-driven rewrite** — no tscn node dependencies
- **Gold starburst / 8-spoke compass rose** drawn procedurally, rotates gently after entry
- Winner name, time, "via N rooms" sub-line, scrollable winner path
- **Path colour-coded:**
  - **Gold** = start room
  - **Accent blue** = target room
  - **Grey** = intermediate rooms
- Auto-dismiss after **12s** with live countdown in the Continue button text
- Mouse shown on race end (`MOUSE_MODE_VISIBLE`), recaptured on dismiss
- Backdrop blocks all input (`MOUSE_FILTER_STOP`) so player can't accidentally interact with world
- **Continue button:** theme-aware transparent ghost style (dark text in light mode, light text in dark mode)
- Scrollable path list with smooth auto-scroll to show target article
- **Old RaceHUD win popup removed** — no more duplicate victory panels

#### 📊 LeaderboardHUD
- **New session leaderboard overlay** (`LeaderboardHUD.gd`)
- Columns: rank · player · target article · time
- Top entry highlighted in gold
- Auto-registers **Tab** keybinding if `toggle_leaderboard` action doesn't exist in InputMap
- Slides down from top-centre on open, slides back up on close
- New entries animate in with a fade when the leaderboard is open
- Reads from `LeaderboardManager` autoload; refreshes on `leaderboard_updated` signal

---

### 🔄 Rewritten / Modernised Components

#### 🗳️ VoteHUD
- **Full code-driven rewrite** — removed all `@onready` tscn node dependencies
- Minimal `.tscn` wrapper (script only)
- **All original functionality preserved:** candidates, timer, host panel (difficulty / category / player management / kick / reroll / seeded shuffle / force start / cancel race / cancel vote), EventBus handlers, `@rpc _kick_player`
- Candidate buttons **slide in from the left**, staggered 50ms per button
- Custom code-drawn loading fallback spinner (no image asset required)
- Panel entry: `TRANS_BACK` scale bounce (0.92 → 1.0)
- Host panel sections separated by 1px dividers for visual clarity

#### ⏱️ RaceHUD
- **Full code-driven rewrite** — removed all `@onready` tscn node dependencies
- **Timer ring** — small custom-drawn pulse ring that fires on every second tick
- **Breadcrumb trail colour roles:**
  - **Green** = start
  - **White** = current
  - **Blue** = target
  - **Grey** = visited
- New room entries **slide in from the right** with a 0.25s fade
- Target label staggers in 0.25s after the panel appears
- Fixed panel height (200px), scroll container fills remaining space with **smooth auto-scroll** on new room entry
- Parser errors fixed (semicolon multi-statements in if/elif/else blocks expanded to separate lines)
- Old win popup removed entirely (replaced by VictoryScreen)
- Moved to **top-left** anchor
- Size reduced: 184px wide, 20px font, 11px target label, 16px ring

#### 👥 PlayerListOverlay
- **Full code-driven rewrite** — removed all `@onready` tscn node dependencies
- Minimal `.tscn` wrapper
- **Colour dot per player** (their chosen multiplayer colour)
- Player name with `· Host` / `· You` inline badges
- Room sub-line beneath each player name
- Each entry fades in individually on refresh
- Slides down from top-right with back-ease on show

#### 🏠 MainMenu
- **Animated entrance sequence** — logo, subtitle, and buttons now stagger in separately
- Logo **drops from above** with elastic overshoot (88% → 100% scale)
- Subtitle fades in 0.35s after logo
- Buttons cascade in every 55ms
- **Animated background added** (`MainMenuBackground.gd`) — floating exhibit cards, dust motes, slow gradient wash, vignette; full dark/light theme support
- Background also applied to **MultiplayerMenu** for visual continuity

---

### 🐛 Bug Fixes

#### Hint/Backlink System Removed
**Severity:** N/A (Design Decision)

**Why it was removed:** The hint/backlink system was removed due to fundamental architectural challenges:

1. **Multiplayer Sync Issues:** Backlinks were only fetched on the server, but door injection needed to happen on all clients. Clients' HintManager was consistently empty, causing hints to fail silently.

2. **Door Injection Complexity:** The system required injecting special "backlink doors" into rooms, which conflicted with the room generation and sync system. This created race conditions where rooms could generate before backlinks were cached.

3. **Fragile Dependencies:** The hint system depended on `ExhibitFetcher.backlinks_complete` signals that would fire at unpredictable times, leading to inconsistent behavior between single-player and multiplayer sessions.

4. **Maintenance Burden:** The complexity of keeping backlink caches synchronized across all clients outweighed the benefit. The code was brittle and prone to breaking with other changes.

**Result:** The hint system, accessibility option ("Keep hints visible"), and all related code have been removed. Players now navigate purely through Wikipedia link exploration without artificial hints.

**Files:** `scenes/util/HintManager.gd` (removed), `docs/HINT_SYSTEM_DESIGN.md` (archived)

#### Race Win Not Triggering (Single Player)
**Severity:** Critical

**Root cause:** In single-player, `NetworkManager.is_multiplayer_active()` is false, so `set_local_player_room()` is never called, `player_room_changed` never emits, and `_player_room_history` stays empty.

**Fix:** Added third fallback in `notify_article_reached` — when both `server_path` and `visited_path` are empty, use `_local_visited_pages` (populated unconditionally via `SettingsEvents.set_current_room`).

#### Countdown Not Showing (Double-Fire)
**Severity:** High

**Root cause:** `_start_countdown` called `race_countdown.emit()` directly AND `_sync_countdown.rpc()` with `call_local = true` → every number fired twice → second call hit `_exit_number()` immediately, breaking the animation.

**Fix:** 
- `race_countdown.emit()` always fires locally
- `_sync_countdown.rpc_id(0, ...)` only fires when `is_multiplayer_active()`
- Changed `_sync_countdown` to `call_remote` so it only runs on clients, never the server

#### VoteHUD Loading Screen Not Showing
**Severity:** Medium

**Root cause 1:** `show_loading()` called `visible = false` on VoteHUD before LoadingScreen's 0.12s delay elapsed → black flash.

**Root cause 2:** `hide_loading()` used `await loading_screen.hidden` inside a signal handler, suspending `_on_vote_started` before candidates were built.

**Fix:** 
- Removed `visible = false` from VoteHUD
- Replaced `await` with `CONNECT_ONE_SHOT` callback pattern

#### JournalOverlay Dark Mode Crash
**Severity:** High

**Root cause:** `dark_mode_changed` lambda called `_show_detail(_selected_title)` which triggered `JournalManager.fetch_full_article_text()` → `ExhibitFetcher.fetch()` with a context dict missing `new_titles` key.

**Fix:** Removed `_show_detail()` from dark mode callback; replaced with targeted `add_theme_color_override` calls on already-rendered nodes.

#### RaceManager Array[String] Type Errors
**Severity:** Medium

**Root cause:** `Dictionary.get()` and `Array.duplicate()` return untyped `Array`, not `Array[String]`.

**Fix:** Receiving into untyped `var raw: Array` then rebuilding as typed with explicit `for` loops.

#### GraphicsSettings Line 656 Crash
**Severity:** Medium

**Root cause:** `var saved_pos: int = SettingsManager.get_settings("hud")` assigned a Dictionary to an int.

**Fix:** Removed the dead `saved_pos` variable (it was never used; `hud_pos_idx` did the work).

#### LoadingScreen Off-Centre
**Severity:** Low

**Root cause:** `PRESET_CENTER` positions the top-left corner at the viewport centre, not the node centre.

**Fix:** Using symmetric `anchor = 0.5` with `offset = ±160/±110` and `GROW_DIRECTION_BOTH`.

#### VictoryScreen Duplicate Panel
**Severity:** Low

**Root cause:** `RaceHUD._on_race_ended` was still connected and showing its own win popup alongside VictoryScreen.

**Fix:** Removed the entire win popup from RaceHUD (`_build_win_popup`, `_on_race_ended`, `_populate_win_timeline`, all related vars).

#### Multiple Parser Errors
**Severity:** Medium

**Root cause:** GDScript rejects multiple statements joined by `;` on the same line as `if`/`elif`/`else`.

**Fix:** Expanded inline assignments to separate lines in:
- RaceHUD (`prefix`/`role` assignments)
- MinimapHUD (`toggle()` inline if/else)

**Additional fix:** GDScript also rejects `"×%.2g" % float` when a multi-byte Unicode character precedes the format specifier — fixed with `str(snappedf(...))` in MinimapHUD.

---

### 🎨 Polish & Theming

#### Consistent Panel Styling
- All new panels use the same `StyleBoxFlat` pattern: `ThemeManager.bg_color`, `ThemeManager.border_color`, 10–14px corner radius, subtle drop shadow (heavier in dark mode)
- All new buttons use the same ghost style: transparent fill, border, `ThemeManager.text_color` font, accent tint on hover

#### MinimapHUD
- Theme-aware panel style applied at runtime (dark: deep navy / light: frosted white)
- Accent-coloured border matching UI accent colour
- Serif font applied to zoom label
- Slide-in / slide-out animations on toggle
- Original `.tscn` structure preserved (reverted from broken circular attempt)

#### RaceCountdown Centering
- Numeral label switched from `PRESET_CENTER` (broken — captures position before layout) to `PRESET_FULL_RECT` with `ALIGNMENT_CENTER` — animations now use scale only, no position tweening

---

### ⚡ Performance Optimizations

- Debug logs stripped in release builds
- LRU cache for article data (500 max)
- Memory leak prevention in long sessions
- Faster network queue processing

---

### 📁 Files Changed

| File | Status |
|------|--------|
| `RaceCountdown.gd` / `.tscn` | ✨ New |
| `LoadingScreen.gd` / `.tscn` | ✨ New |
| `LeaderboardHUD.gd` | ✨ New |
| `MainMenuBackground.gd` | ✨ New |
| `VictoryScreen.gd` / `.tscn` | 🔄 Rewritten |
| `VoteHUD.gd` / `.tscn` | 🔄 Rewritten |
| `RaceHUD.gd` | 🔄 Rewritten |
| `PlayerListOverlay.gd` / `.tscn` | 🔄 Rewritten |
| `MainMenu.gd` | 🔧 Modified |
| `MultiplayerMenu.gd` | 🔧 Modified |
| `MinimapHUD.gd` | 🔧 Modified |
| `RaceManager.gd` | 🔧 Modified (countdown fix, path type fix, win detection fix) |
| `Main.gd` | 🔧 Modified (countdown sound + set_target injection, vote_ended hook) |
| `JournalOverlay.gd` | 🔧 Modified (dark mode crash fix) |
| `GraphicsSettings.gd` | 🔧 Modified (type error fix) |

---

## 📅 Daily Challenge System (Previous Update)

### 🎮 Features
- **New game mode**: Race against the clock to find a specific Wikipedia article
- **Daily rotating target**: A new article to find each day
- **Streak tracking**: Build and maintain your daily completion streak
- **Global leaderboard**: Compete for the fastest times worldwide
- **Personal best tracking**: Beat your own records

### 📋 Daily Challenge HUD
- **Timer strip**: Compact top-center display showing elapsed time during the race
- **Results popup**: Completion screen with grade, final time, and global leaderboard
- **Light/Dark mode support**: All UI elements respect your theme preference
- **Help popup**: Press the info button (ⓘ) to view challenge rules

### 🔒 Anti-Cheat Measures
- **Terminal disabled**: Search terminal is blocked during daily challenge runs
- **System message**: "⚠ Terminal disabled during Daily Challenge" when attempting to use terminal

---

## 🎮 All Existing Features Still Working!

- 📅 Daily Challenge System
- 🔒 Anti-Cheat Measures  
- 🚪 Search Corridor Door System
- 👥 Multiplayer Room Sync
- 📖 Journal System
- 🏆 Leaderboards

### ⚠️ Power-ups Temporarily Disabled

**All 9 power-ups are disabled for the foreseeable future.**

The power-up system is being reworked for better balance and stability. They will return in a future update.

**Disabled power-ups:**
- 🏃 Speed Boost
- 🧠 Perfect Knowledge
- 🔫 Teleport Gun
- 🪤 Teleport Trap
- 🗼 Tower of Babel
- 💡 Lights Out
- 🧲 Magnet
- 🕷️ Spider Grapple
- 🔮 Omniscience

---

*Last updated: March 16, 2026*
