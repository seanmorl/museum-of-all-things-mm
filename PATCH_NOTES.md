# Patch Notes - Daily Challenge Update

## New Features

### 📅 Daily Challenge System
- **New game mode**: Race against the clock to find a specific Wikipedia article
- **Daily rotating target**: A new article to find each day
- **Streak tracking**: Build and maintain your daily completion streak
- **Global leaderboard**: Compete for the fastest times worldwide
- **Personal best tracking**: Beat your own records

### 🎮 Daily Challenge HUD
- **Timer strip**: Compact top-center display showing elapsed time during the race
- **Results popup**: Completion screen with grade, final time, and global leaderboard
- **Light/Dark mode support**: All UI elements respect your theme preference
- **Help popup**: Press the info button (ⓘ) to view challenge rules

### 📋 Daily Challenge Card
- **Main menu widget**: Shows today's target article and your streak
- **Quick access**: Click "Play" to start the challenge immediately
- **Info button**: Learn the rules before starting
- **Auto-hide**: Card hides when entering museum normally (not via challenge)

### 🔒 Anti-Cheat Measures
- **Terminal disabled**: Search terminal is blocked during daily challenge runs
- **System message**: "⚠ Terminal disabled during Daily Challenge" when attempting to use terminal

## Power-ups

### All Power-ups (Verified Working)
| Power-up | Key | Effect | Status |
|----------|-----|--------|--------|
| 🏃 Speed Boost | Auto | 2x movement speed for 15 seconds | ✅ Working |
| 🧠 Perfect Knowledge | Auto | Reveals all room labels | ✅ Working |
| 🔫 Teleport Gun | Q | Teleport hit player to lobby | ✅ Working |
| 🪤 Teleport Trap | Q | Place trap that teleports victims to lobby | ✅ Working |
| 🗼 Tower of Babel | Auto | Forces random non-English Wikipedia for 5 rooms | ✅ Working |
| 💡 Lights Out | Auto | Dims all lights for 120 seconds | ✅ Working |
| 🧲 Magnet | Q | Pulls all players to your current room | ✅ Working |
| 🕷️ Spider Grapple | Q | Grapple to walls/ceilings, swing for 60 seconds | ✅ Working |
| 🔮 Omniscience | Auto | Reveals all player positions for 30 seconds | ✅ Working |

### Power-up Usage
- **Q Key**: Activates held power-ups (Gun, Trap, Magnet, Grapple)
- **Auto-activate**: Some power-ups activate on pickup (Speed Boost, Perfect Knowledge, Tower of Babel, Lights Out, Omniscience)

## Bug Fixes
- Fixed ESC key not opening pause menu during daily challenge
- Fixed Daily Challenge HUD remaining visible when entering museum normally
- Fixed orange/gold text readability in light mode
- Added info button to Daily Challenge card and modal
- Added smooth enter/exit animations to help popups

## Known Issues
- Voice proximity chat framework is in place but not fully implemented
- Some power-up visual effects may need polish

## Technical Changes
- `DailyChallengeHUD.gd`: Added `_should_intercept_esc` flag for proper input handling
- `DailyChallengeCard.gd`: Added help popup with animations
- `Main.gd`: Added `game_started = true` to `_on_daily_challenge_started()`
- `TerminalInteractZone.gd`: Added daily challenge check
- `PowerupManager.gd`: All 9 power-ups fully implemented and tested

---

## Power-up Details

### Tower of Babel 🗼
- **Duration**: Until victim enters 5 rooms
- **Effect**: Changes victim's Wikipedia to a random non-English language
- **Languages**: German, French, Spanish, Italian, Japanese, Chinese, Russian, Portuguese
- **Activation**: Automatic on pickup
- **Usage**: Press Q after pickup to activate (sends language to all victims)

### Spider Grapple 🕷️
- **Duration**: 60 seconds
- **Range**: 30 units
- **Effect**: Fire grapple hook at walls/ceilings, swing toward anchor point
- **Controls**: Press Q while looking at valid surface (wall or ceiling, not floor)
- **Visual**: White rope connects player to grapple point
- **Notes**: 
  - Only works on walls (normal.y between -0.3 and 0.3) and ceilings (normal.y < -0.3)
  - Does NOT work on floors (normal.y > 0.5)
  - Player swings toward anchor point with physics-based movement

### Magnet 🧲
- **Duration**: Instant activation
- **Effect**: Pulls all players to your current room
- **Usage**: Press Q while in any room (not lobby)
- **Notes**: Cannot be used in the lobby

---

*Last updated: March 12, 2026*
