# Museum of All Things — Development Roadmap

**Last Updated:** April 5, 2026  
**Current Version:** v0.3.5 — Code Quality & Sticky Notes  
**Next Version:** v0.4.0 — Wiki Races Update (Tournament Mode)

---

## 🎯 Vision

A fast-paced multiplayer Wikipedia navigation game where players race through article links to reach targets first. Competitive, accessible, and endlessly replayable.

---

## ✅ Completed (v0.3.0-v0.3.5 — March-April 2026)

### v0.3.0: UI & Graphics Overhaul
- ✨ 4 new overlay systems (RaceCountdown, LoadingScreen, VictoryScreen, LeaderboardHUD)
- 🔄 4 rewritten components (VoteHUD, RaceHUD, PlayerListOverlay, MainMenu)
- 🐛 8 critical bug fixes (host visibility, race win detection, countdown sync, etc.)
- 🎨 Theme-aware styling across all UI
- ⚡ Performance optimizations

**Status:** ✅ **Released**

### v0.3.5: Code Quality & Sticky Notes (April 2026)
- 📝 **Sticky Note System** - Multiplayer-synchronized persistent notes in exhibits
- 🧹 **Dead Code Removal** - Removed archived power-up references from active code
- 🔧 **Architecture Cleanup** - Resolved service layer vs singleton confusion
- 🐛 **Bug Fixes** - Fixed export config typo, documentation mismatches
- 📚 **Documentation** - Added architecture decisions, integration guides

**Status:** ✅ **Complete**

---

## 🚧 In Progress (v0.4.0 — Q2 2026)

### Wiki Races / Tournament Mode

#### Core Features
- [ ] **Tournament Brackets** — Single/double elimination support
- [ ] **Ranked Leaderboards** — ELO or MMR-based ranking system
- [x] **Matchmaking** — Skill-based player matching (✅ Implemented, needs testing)
- [ ] **Scheduled Events** — Daily/weekly tournaments
- [x] **Spectator Mode** — Watch live matches with observer UI (✅ Implemented)
- [ ] **Tournament Lobby** — Pre-match staging area

#### Technical Requirements
- [ ] Tournament data persistence (PostgreSQL/SQLite)
- [x] Anti-cheat enhancements for competitive play (✅ Implemented: speed hack, teleport, path validation)
- [x] Replay system (record and playback) (✅ Implemented: RaceReplay.gd)
- [ ] Admin tools for tournament organizers

**Target Release:** Q2 2026 (April–June)  
**Status:** 🚧 **~60% Complete** — Core infrastructure done, tournament logic needs work

---

## 📋 Planned (v0.5.0 — Q3 2026)

### Power-ups Restored & Rebalanced

All 9 power-ups re-enabled with improved balance:

- [ ] 🏃 **Speed Boost** — 2x movement speed (15s)
- [ ] 🧠 **Perfect Knowledge** — Reveal all room labels
- [ ] 🔫 **Teleport Gun** — Teleport hit player to lobby
- [ ] 🪤 **Teleport Trap** — Place trap, teleport victims
- [ ] 🗼 **Tower of Babel** — Force non-English Wikipedia (5 rooms)
- [ ] 💡 **Lights Out** — Dim lights (120s)
- [ ] 🧲 **Magnet** — Pull all players to your room
- [ ] 🕷️ **Spider Grapple** — Grapple and swing (60s)
- [ ] 🔮 **Omniscience** — Reveal all player positions (30s)

#### Improvements
- [ ] Visual effect polish for all power-ups
- [ ] Better balance (cooldowns, durations, counters)
- [ ] Power-up draft mode (pick before race)
- [ ] Power-up disabled option for tournaments

**Target Release:** Q3 2026 (July–September)  
**Status:** 📋 **Planned** — Code archived in `_archived_powerups_OLD/`

---

## 🔮 Future Considerations (v1.0.0+ — 2026+)

### Candidate Features for 1.0.0

These features would make strong candidates for a v1.0.0 release:

#### Game Modes
- [ ] **Team Mode** — 2v2 or 3v3 cooperative races
- [ ] **King of the Hill** — Defend the target article
- [ ] **Capture the Flag** — Steal articles from opponent bases
- [ ] **Time Attack** — Solo speedrun mode with ghosts
- [ ] **Custom Races** — Player-created rule sets

#### Social Features
- [ ] **Friends List** — Add and track friends
- [ ] **Clans/Guilds** — Form teams with shared leaderboards
- [ ] **Chat Improvements** — Emotes, quick chat, voice proximity
- [ ] **Player Profiles** — Stats, achievements, cosmetics

#### Content
- [ ] **Daily Challenges** — Shared daily targets (already implemented ✅)
- [ ] **Weekly Challenges** — Extended challenges with bigger rewards
- [ ] **Achievement System** — Unlockables for milestones
- [ ] **Cosmetic Customization** — Skins, colors, trails (beyond current system)

#### Quality of Life
- [ ] **Tutorial System** — Interactive onboarding for new players
- [ ] **Practice Mode** — Race against bots or ghosts
- [ ] **Article Categories** — Filter races by topic (science, history, etc.)
- [ ] **Custom Lobbies** — Private rooms with custom rules
- [ ] **Replay Sharing** — Export and share race replays

#### Technical
- [ ] **Cross-Platform Play** — Web, Windows, Linux, macOS
- [ ] **Mobile Companion App** — View leaderboards, join tournaments
- [ ] **Dedicated Server Binaries** — Community-hosted servers
- [ ] **Mod Support** — Custom articles, rooms, game modes

---

## 🐛 Known Issues & Technical Debt

### Current Issues
| Issue | Priority | Target Version | Status |
|-------|----------|----------------|--------|
| Power-ups disabled | High | v0.5.0 | 📋 Planned |
| Voice chat not fully implemented | Medium | v0.5.0 | ⚠️ Not player-facing |
| Service layer redundancy | Low | v0.4.0 | ✅ Documented, archived |
| Large monolithic files | Low | Ongoing | 📝 Refactor gradually |

### Recently Fixed ✅
| Issue | Fixed In | Date |
|-------|----------|------|
| Typo in export_presets.cfg (`search_hhistory`) | v0.3.5 | 2026-04-05 |
| Broken `!hint` command stub | v0.3.5 | 2026-04-05 |
| Documentation mismatch (60Hz vs 10Hz sync) | v0.3.5 | 2026-04-05 |
| Dead power-up code in Player.gd/Main.gd | v0.3.5 | 2026-04-05 |

### Technical Debt
- [ ] Remove debug logging from release builds (partially done)
- [ ] Optimize network bandwidth for large player counts
- [ ] Improve error handling for network disconnects
- [ ] Add automated testing for critical systems
- [x] Document codebase for community contributors ✅ (docs/ added)
- [x] Resolve service layer vs singleton architecture ✅ (see ARCHITECTURE_DECISIONS.md)

---

## 📊 Version History

| Version | Name | Date | Status |
|---------|------|------|--------|
| v0.1.0 | Initial Prototype | 2025 | ✅ Released |
| v0.2.0 | Multiplayer Update | 2025 | ✅ Released |
| **v0.3.0** | **UI & Graphics Overhaul** | **Mar 2026** | ✅ **Released** |
| **v0.3.5** | **Code Quality & Sticky Notes** | **Apr 2026** | ✅ **Complete** |
| v0.4.0 | Wiki Races Update | Q2 2026 | 🚧 In Progress |
| v0.5.0 | Power-ups Restored | Q3 2026 | 📋 Planned |
| v1.0.0 | Release Candidate | TBA | 🔮 Future |

---

## 🎮 Feature Priority Matrix

### High Priority (Must Have)
- ✅ Core multiplayer racing
- ✅ Vote system for targets
- ✅ Daily challenges
- ✅ Tournament mode (v0.4.0)
- 🔲 Power-ups restored (v0.5.0)

### Medium Priority (Should Have)
- [ ] Ranked leaderboards
- [ ] Matchmaking
- [ ] Spectator mode
- [ ] Voice chat
- [ ] Tutorial system

### Low Priority (Nice to Have)
- [ ] Cosmetics beyond colors
- [ ] Clan system
- [ ] Mobile app
- [ ] Mod support
- [ ] Cross-platform

---

## 🗓️ Development Timeline

```
2026
├── Q1 (Jan–Mar)
│   └── ✅ v0.3.0 — UI & Graphics Overhaul
│
├── Q2 (Apr–Jun)
│   ├── ✅ v0.3.5 — Code Quality & Sticky Notes (April)
│   └── 🚧 v0.4.0 — Wiki Races Update (Tournament Mode)
│
├── Q3 (Jul–Sep)
│   └── 📋 v0.5.0 — Power-ups Restored
│
└── Q4 (Oct–Dec)
    └── 🔮 v1.0.0 — Release Candidate (if features complete)
```

---

## 🤝 Community Feedback

We want your input! Help prioritize future features:

- 📢 **Discord:** [Your Discord Link]
- 🐛 **Bug Reports:** [GitHub Issues]
- 💡 **Feature Requests:** [GitHub Discussions]
- 📊 **Polls:** [Discord/Twitter Polls]

---

## 📝 Notes

### Version Numbering
We follow [Semantic Versioning](https://semver.org/):
- **MAJOR.MINOR.PATCH** (e.g., v0.4.0)
- **v0.x.x** = Active development, features may change
- **v1.0.0** = Production ready, stable API

### Scope Changes
This roadmap is a living document. Features may be:
- ✅ Added based on community feedback
- ⏸️ Delayed due to technical challenges
- ❌ Removed if they don't fit the vision

### Transparency
We're committed to open development. Major changes to this roadmap will be announced via:
- Discord announcements
- GitHub release notes
- Social media updates

---

**Last Roadmap Review:** March 16, 2026  
**Next Roadmap Review:** After v0.4.0 release

---

*Built with ❤️ by [Your Name/Studio]*
