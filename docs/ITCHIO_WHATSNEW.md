# Museum of All Things — What's New (v0.3.0)

## 🎨 UI & Graphics Overhaul — March 2026

A **complete visual transformation** of the Museum of All Things!

---

## ✨ What's New

### 🎯 Race Countdown
Stunning full-screen **3→2→1→GO** countdown with elastic animations and ink-ring burst effects. Target article shown before the race starts!

### 📦 Loading Screen
Professional loading overlay with **8-segment animated spinner**, progress bar, and theme-aware colors.

### 🏆 Victory Screen
Beautiful winner celebration with **rotating gold starburst**, color-coded room path, and auto-dismiss countdown.

### 📊 Leaderboard Overlay
Press **Tab** to toggle the session leaderboard — shows rank, player, target, and time. Top entry highlighted in gold!

### 🏠 Animated Menus
Main menu and multiplayer lobby now feature **floating exhibit cards**, **dust motes**, and **slow gradient wash** effects.

---

## 🔄 Modernized Components

**VoteHUD, RaceHUD, PlayerListOverlay** — Completely rewritten with:
- Smooth slide-in animations
- Theme-aware styling
- Custom-drawn elements (no image dependencies)
- Cleaner visual hierarchy

---

## 🐛 Critical Fixes

- ✅ **Race win detection** — Fixed single-player wins not triggering
- ✅ **Countdown double-fire** — Fixed broken animations
- ✅ **Loading screen flash** — Fixed black flash on vote start
- ✅ **Journal dark mode crash** — Fixed crash when switching themes
- ✅ **Type errors** — Fixed Array[String] and Dictionary issues
- ✅ **Off-center loading screen** — Now perfectly centered

---

## 🎨 Polish

- Consistent panel styling across all UI
- Theme-aware backgrounds, borders, and shadows
- Ghost button style with accent hover tint
- Minimap HUD now theme-aware with accent border

---

## ⚡ Performance

- Debug logs stripped in release builds
- LRU cache for article data (500 max)
- Memory leak prevention
- Faster network queue processing

---

## 🎮 All Your Favorite Features Still Work!

- 📅 Daily Challenge System
- 🔒 Anti-Cheat Measures  
- 🚪 Search Corridor Door System
- 👥 Multiplayer Room Sync
- 📖 Journal System

### ⚠️ Power-ups Temporarily Disabled

**All 9 power-ups are disabled for the foreseeable future.**

They're being reworked for better balance and stability, and will return in a future update.

---

## 🛠️ Setup (Important!)

**Before playing**, make sure these autoloads are registered in Project Settings:
- `LoadingScreen` → `res://scenes/ui/LoadingScreen.tscn`
- `RaceCountdown` → `res://scenes/autoload/RaceCountdown.tscn`

---

## 📋 Files Changed

**New:** RaceCountdown, LoadingScreen, LeaderboardHUD, MainMenuBackground  
**Rewritten:** VictoryScreen, VoteHUD, RaceHUD, PlayerListOverlay  
**Modified:** MainMenu, MultiplayerMenu, MinimapHUD, RaceManager, Main.gd

---

**Built with Godot Engine 4.x** | **Licensed under [Your License]**
