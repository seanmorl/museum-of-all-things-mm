# Multiplayer Test Checklist

**Version:** v0.3.5  
**Date:** 2026-04-05  
**Status:** 📋 Ready to Execute

---

## Prerequisites

- [ ] Godot 4.6 installed
- [ ] At least 2 machines/instances available for testing
- [ ] Playit.gg configured (if testing over internet)
- [ ] Clean save data (backup existing `user://` files first)

---

## 1. Core Multiplayer (P0 - Critical)

### Hosting & Joining
- [ ] Host game from main menu
- [ ] Join game from second client
- [ ] Verify both players see each other in player list
- [ ] Verify player names and colors sync correctly
- [ ] Test with 3-4 players if possible
- [ ] Test join/leave during lobby phase
- [ ] Verify player count updates correctly

### Position Sync
- [ ] Host moves around - client sees smooth movement
- [ ] Client moves around - host sees smooth movement
- [ ] Test dashing (shift key) - sync works
- [ ] Test crouching (ctrl key) - sync works
- [ ] Test jumping - sync works
- [ ] Verify no rubber-banding or teleporting
- [ ] Test with poor connection (simulate lag if possible)

### Room Transitions
- [ ] Host enters exhibit - client sees them leave lobby
- [ ] Client enters exhibit - host sees them arrive
- [ ] Both players in same exhibit - see each other
- [ ] Players in different exhibits - don't see each other (room culling)
- [ ] Test rapid room changes - no crashes or desyncs

---

## 2. Racing System (P0 - Critical)

### Race Voting
- [ ] Vote for target article as host
- [ ] Vote for target article as client
- [ ] Verify votes count correctly
- [ ] Verify tie-breaking works
- [ ] Test vote timeout (no votes cast)

### Race Execution
- [ ] Race starts - both players get countdown
- [ ] Race starts - both players see start article
- [ ] Race starts - both players see target article
- [ ] Move during race - position sync works
- [ ] Reach target - win detected correctly
- [ ] Winner announced to all players
- [ ] Race time calculated correctly

### Race Edge Cases
- [ ] Player disconnects mid-race - race continues
- [ ] Host disconnects mid-race - host migration works
- [ ] All players disconnect - race resets
- [ ] Vote during active race - queued for next race
- [ ] Join during active race - spectator mode or blocked appropriately

---

## 3. Chat System (P0 - Critical)

### Basic Chat
- [ ] Send message as host - all players see it
- [ ] Send message as client - all players see it
- [ ] Player name displays correctly in chat
- [ ] Player color displays correctly in chat
- [ ] Pronouns display in chat (if set)

### Chat Edge Cases
- [ ] Send message while typing special characters
- [ ] Send empty message - should be blocked
- [ ] Send very long message (500+ chars) - truncates or handles
- [ ] Disconnect while typing - no crashes
- [ ] Open console while chat open - both work independently

---

## 4. Sticky Notes (P1 - New Feature)

### Note Placement
- [ ] Enter exhibit (not lobby)
- [ ] Press N key - placement UI appears
- [ ] Type note content (under 500 chars)
- [ ] Pick a color
- [ ] Click "Place Note" - note appears in 3D world
- [ ] Verify note shows author name
- [ ] Verify note shows content preview
- [ ] Try to place note in lobby - should fail gracefully

### Note Sync (Multiplayer)
- [ ] Host places note - client sees it appear
- [ ] Client places note - host sees it appear
- [ ] Both players see note in same position
- [ ] Note content syncs correctly (special characters, unicode)
- [ ] Note color syncs correctly

### Note Editing
- [ ] Edit own note as author - changes sync
- [ ] Try to edit another player's note - should fail
- [ ] Delete own note - removes for all players
- [ ] Host deletes any note - removes for all players
- [ ] Client tries to delete host's note - should fail (or succeed if host)

### Note Persistence
- [ ] Place several notes in exhibit
- [ ] Exit game completely
- [ ] Restart game and enter same exhibit
- [ ] Verify all notes restored
- [ ] Verify positions, colors, content all correct
- [ ] Enter different exhibit - no notes (or correct notes for that room)
- [ ] Return to first exhibit - notes still there

### Note Limits
- [ ] Place 50 notes in one room - should hit limit
- [ ] Try to place 51st note - should fail gracefully with warning
- [ ] Write 500 char note - should work
- [ ] Write 501 char note - should truncate to 500
- [ ] Place notes with only whitespace - should fail or warn

---

## 5. Player Customization (P1 - Important)

### Name & Color
- [ ] Change name in settings - syncs to other players
- [ ] Change color in settings - syncs to other players
- [ ] Change pronouns in settings - syncs correctly
- [ ] Test name with special characters (unicode, emojis)
- [ ] Test very long names (50+ chars) - truncates appropriately

### Player Skins
- [ ] Set custom skin URL - loads correctly
- [ ] Skin visible to other players
- [ ] Invalid skin URL - falls back to default gracefully
- [ ] Skin syncs on join (don't need to wait for change)

---

## 6. Mounting System (P1 - Important)

### Mounting Players
- [ ] Mount another player as host
- [ ] Mount another player as client
- [ ] Rider position syncs correctly
- [ ] Mountee can move while carrying rider
- [ ] Both players see mounting correctly

### Dismounting
- [ ] Dismount as rider - works
- [ ] Dismount as mountee - works
- [ ] Dismount when far from other players - syncs
- [ ] Mount then leave game - mount state clears

---

## 7. Spectator Mode (P2 - Nice to Have)

### Spectator Features
- [ ] Enter spectator mode (if available)
- [ ] Free-fly camera works
- [ ] Follow player mode works
- [ ] Top-down view works
- [ ] Spectator invisible to players in exhibits
- [ ] Spectator can see all rooms

---

## 8. Anti-Cheat (P2 - Important for Competitive)

### Speed Hack Detection
- [ ] Modify client to move faster - detected by server
- [ ] Warning issued to cheating player
- [ ] Position corrected to valid location
- [ ] False positives: normal dashing not flagged

### Teleport Detection
- [ ] Teleport large distance - detected
- [ ] Snap back to valid position
- [ ] Legitimate teleports (race wins) not flagged

### Path Validation
- [ ] Race path recorded correctly
- [ ] Invalid path (skipping rooms) rejected
- [ ] Valid path accepted

---

## 9. Journal System (P2 - Single Player with Multiplayer Elements)

### Journal Entries
- [ ] Enter exhibit - auto-logged to journal
- [ ] Add note to journal entry - saves
- [ ] Add tag to journal entry - saves
- [ ] Pin item to journal entry - saves
- [ ] Edit journal note - debounced auto-save works
- [ ] Search journal entries - finds correct results
- [ ] Filter by tag - works
- [ ] Sort by different criteria - works

### Journal Persistence
- [ ] Exit game with journal entries
- [ ] Restart - all entries restored
- [ ] Notes, tags, pins all persist

---

## 10. UI & Menus (P2 - Polish)

### Main Menu
- [ ] Host button visible and clickable
- [ ] Join button visible and clickable
- [ ] Settings accessible
- [ ] Dark/light mode works

### In-Game UI
- [ ] Player list overlay works
- [ ] Race HUD shows correctly
- [ ] Vote HUD shows correctly
- [ ] Chat HUD opens with T key
- [ ] Journal opens with J key
- [ ] Map overlay works with M key
- [ ] Pause menu works with ESC

---

## 11. Network Resilience (P2 - Important)

### Disconnection Handling
- [ ] Client disconnects gracefully (ALT+F4)
- [ ] Host sees "player left" message
- [ ] Client can rejoin after disconnect
- [ ] Game state preserved during disconnect
- [ ] Race continues after player disconnects

### Host Migration
- [ ] Host disconnects mid-game
- [ ] New host elected automatically
- [ ] Game continues without reset
- [ ] All players notified of new host
- [ ] Race state preserved during migration

### Connection Errors
- [ ] Try to join non-existent server - error message
- [ ] Try to join full server (16 players) - error message
- [ ] Network timeout during join - error message
- [ ] Invalid server address - error message

---

## 12. Performance (P3 - Optimization)

### Frame Rate
- [ ] Host maintains 60 FPS with 1 player
- [ ] Host maintains 60 FPS with 4 players
- [ ] Client maintains 60 FPS
- [ ] No memory leaks after 10 minutes of play

### Network Bandwidth
- [ ] Monitor network usage during idle (should be minimal)
- [ ] Monitor during movement (should be reasonable)
- [ ] Monitor with 4 players (should scale well)
- [ ] No network flooding or exponential growth

---

## Test Results

### Pass Rate
- **Total Tests:** 100+
- **Passed:** ___ / ___
- **Failed:** ___ / ___
- **Skipped:** ___ / ___

### Critical Failures
| Test | Expected | Actual | Severity |
|------|----------|--------|----------|
| | | | |

### Notes
```
Add any observations, edge cases discovered, or recommendations here.
```

---

## Sign-off

**Tested By:** ________________  
**Date:** ________________  
**Build:** v0.3.5  
**Result:** ☐ PASS  ☐ FAIL  ☐ PASS WITH NOTES

**Comments:**
```

```

---

## Next Steps

If all P0 tests pass:
- [ ] Ready for public testing
- [ ] Can proceed to v0.4.0 development

If P0 tests fail:
- [ ] Fix critical issues
- [ ] Re-test failed items
- [ ] Do not release until P0 passes

If only P1/P2 fail:
- [ ] Document issues
- [ ] Prioritize fixes for next patch
- [ ] Can release with known issues documented
