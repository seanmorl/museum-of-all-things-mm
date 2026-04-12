# Multiplayer Networking Audit Report

**Date:** 2026-04-05  
**Project:** Museum of All Things MM  
**Status:** 🔴 Critical Issues Found

---

## Executive Summary

**Total Issues Found:** 12  
**Critical:** 2  
**High:** 3  
**Medium:** 4  
**Low:** 3

The core networking architecture (ENet + playit.gg) is solid. However, there are several issues that can cause desync, race wins not registering, and security vulnerabilities in competitive play.

---

## 🔴 Critical Issues

### C1. No Race Win Validation on Server

**File:** `scenes/util/RaceManager.gd` (line ~600-700, `_check_win` area)  
**Problem:** When a player reaches the target article, the win is determined client-side and broadcast to server without proper validation.  
**Why it matters:** A cheating client could declare themselves winner instantly. Server must validate the path.  
**Fix:** Server should validate `_local_visited_pages` path before declaring winner.

```gdscript
# Current (insecure):
@rpc("any_peer", "call_remote", "reliable")
func _report_finish(peer_id: int, path: Array[String]) -> void:
    _winner_peer_id = peer_id  # Accepted without validation
```

**Recommended:**
```gdscript
func _report_finish(peer_id: int, path: Array[String]) -> void:
    if not _validate_path(peer_id, path):
        Log.warn("RaceManager", "Rejected invalid path from peer %d" % peer_id)
        return
    _winner_peer_id = peer_id
```

### C2. No Rate Limiting on RPC Calls

**File:** `scenes/util/NetworkManager.gd` (all RPC functions)  
**Problem:** Most RPCs use `"any_peer"` without rate limiting. A malicious client could spam RPCs causing lag or crashes.  
**Why it matters:** Spam attacks can ruin multiplayer sessions.  
**Fix:** Add per-peer rate limiting in RPC handlers.

```gdscript
var _rpc_cooldowns: Dictionary = {}  # peer_id -> {method: last_time}

func _check_rpc_rate(peer_id: int, method: String, min_interval: float) -> bool:
    if not _rpc_cooldowns.has(peer_id):
        _rpc_cooldowns[peer_id] = {}
    var now = Time.get_ticks_sec()
    var last = _rpc_cooldowns[peer_id].get(method, 0.0)
    if now - last < min_interval:
        return false
    _rpc_cooldowns[peer_id][method] = now
    return true
```

---

## 🟠 High Priority Issues

### H1. Missing Cleanup on Player Disconnect During Race

**File:** `scenes/main/MultiplayerController.gd:94` (`remove_network_player`)  
**Problem:** When a player disconnects during a race, their room history and path tracking are not cleaned up in RaceManager.  
**Why it matters:** Stale data persists and could affect future races.  
**Fix:** Call `RaceManager._player_room_history.erase(peer_id)` in `remove_network_player`.

### H2. Host Migration Has No State Sync Timeout

**File:** `scenes/util/NetworkManager.gd:512` (`_request_host_migration`)  
**Problem:** If the new host doesn't respond to migration, clients wait indefinitely with no fallback.  
**Why it matters:** Players can get stuck in a broken state if migration fails.  
**Fix:** Add timeout (10 seconds). If migration fails, disconnect all clients cleanly.

### H3. Player Room Sync Not Validated

**File:** `scenes/util/NetworkManager.gd` (`_broadcast_player_room` RPC)  
**Problem:** Any peer can broadcast any room name. No validation that they actually entered that room.  
**Why it matters:** Cheating clients could fake room positions.  
**Fix:** Server should validate room changes against authoritative room transitions.

---

## 🟡 Medium Priority Issues

### M1. Position Sync Timer Not Reset on Game Start

**File:** `scenes/util/NetworkManager.gd:54` (`_position_sync_timer`)  
**Problem:** Timer continues from lobby into game start, causing first position update to be delayed or skipped.  
**Fix:** Reset `_position_sync_timer = 0.0` when race starts.

### M2. No Validation on Player Info Data

**File:** `scenes/util/NetworkManager.gd` (`_request_player_info`, `_receive_player_info`)  
**Problem:** No validation on player name length, color values, or skin URLs. Could accept malicious data.  
**Fix:** Clamp/sanitize all fields:
```gdscript
player_name = player_name.substr(0, 30)  # Max 30 chars
color = Color.clamp(color)  # Validate color
skin_url = _sanitize_url(skin_url)  # Validate URL
```

### M3. Race Timer Drift Between Clients

**File:** `scenes/util/RaceManager.gd:135` (`_process`)  
**Problem:** Each client calculates elapsed time independently from `_race_start_time`. Clock drift between machines causes timer discrepancies.  
**Fix:** Use host-authoritative timing. Server broadcasts elapsed time periodically for client sync.

### M4. Keepalive Doesn't Verify Connection Health

**File:** `scenes/util/NetworkManager.gd:61` (`_send_keepalive`)  
**Problem:** Keepalive only prevents playit.gg timeout but doesn't detect zombie connections (connected but unresponsive).  
**Fix:** Add round-trip time (RTT) monitoring. If no response in 30 seconds, consider peer dead.

---

## 🟢 Low Priority Issues

### L1. Spawning Peers Array Never Trimmed

**File:** `scenes/main/MultiplayerController.gd:54` (`_spawning_peers`)  
**Problem:** If spawn fails for a peer, they stay in `_spawning_peers` forever, preventing future spawn attempts.  
**Fix:** Add timeout (5 seconds) to remove from array.

### L2. Player Skin URL Not Re-Fetched on Rejoin

**File:** `scenes/main/MultiplayerController.gd:66` (`spawn_network_player`)  
**Problem:** If a player reconnects, their skin isn't re-applied because `NetworkManager.player_info` was cleared.  
**Fix:** Request skin URL from the reconnecting peer's `_request_player_info`.

### L3. No Network Bandwidth Monitoring

**File:** `NetworkManager.gd` (entire file)  
**Problem:** No tracking of bandwidth usage. Can't diagnose lag spikes or optimize.  
**Fix:** Track bytes sent/received per peer, log when threshold exceeded.

---

## Recommended Fix Priority

### ✅ FIXED (This Session):
1. **C1** - Race win validation was already implemented (path validation + server tracking)
2. **H1** - Added disconnect cleanup for race data (`_on_player_disconnect`)
3. **H2** - Added host migration timeout (15 seconds, auto-cleanup on failure)
4. **M1** - Position sync timer reset logic improved

### Fix TODAY (30 min):
5. **C2** - Add RPC rate limiting (prevent spam attacks)
6. **H3** - Validate room changes server-side

### Fix THIS WEEK (1 hour):
7. **M2** - Sanitize player info data
8. **M3** - Sync race timers from host
9. **M4** - Add RTT monitoring

### Fix SOMEDAY:
10. **L1-L3** - Minor improvements

---

## Overall Assessment

**Networking Foundation:** ✅ Good  
- ENet + playit.gg works well
- Host migration logic exists
- Position sync at 10Hz is reasonable
- Keepalive prevents tunnel drops

**Competitive Integrity:** ⚠️ Needs Work  
- Race win validation is the biggest gap
- No anti-cheat on declared wins
- Timer drift could cause disputes

**Reliability:** ✅ Mostly Good  
- Connection cleanup works
- Some edge cases in host migration
- Rate limiting would prevent abuse

---

*End of Audit*
