# Powerup System - Critical Sync & Effect Application Bugs

**Date**: March 17, 2026  
**Severity**: Critical - Blocks powerup re-enablement  
**Status**: Requires immediate fixes  

---

## 🔴 Critical Issue #1: Effects Only Apply to Local Player

### Problem

In `PlayerPowerupSystem.gd`, nearly all effect functions have this guard:

```gdscript
func _apply_speed_boost() -> void:
    if not _is_local:
        return  # ❌ EARLY RETURN - Network players never get effects!
    if "max_speed_walk" in _player:
        _player.max_speed_walk = _original_walk_speed * SPEED_BOOST_MULTIPLIER
```

**Impact**: 
- Speed Boost only works for local player
- Perfect Knowledge door reveals only work for local player
- Lights Out dimming only works for local player
- Grapple physics only work for local player

**Why This Was Done**: The code assumes that only the local player's effects need to be applied locally, and other players' effects are handled by their own clients. **This is partially correct but misses visual sync.**

### What SHOULD Happen

| Effect | Local Player | Remote Players |
|--------|--------------|----------------|
| Speed Boost | Apply to self | Show other player moving faster (visual only) |
| Perfect Knowledge | Reveal doors for self | N/A (each player sees their own) |
| Lights Out | Dim lights if victim | Dim lights if victim (SHARED environment!) |
| Grapple | Physics for self | Show other player swinging (visual rope) |
| Gun/Trap/Magnet | Activate on use | See effect on all clients |

### The Real Problem: Lights Out

Lights Out affects **shared environment** (lights in the museum). Currently:

```gdscript
func _update_lights_out() -> void:
    if not _is_local:  # ❌ WRONG!
        return
    
    var museum = _player.get_tree().get_first_node_in_group("museum")
    # ... dim lights ...
```

**Result**: Only the local player's client dims the lights. Other players see normal lighting even though they should be affected.

### Fix Required

```gdscript
func _update_lights_out() -> void:
    # Check if LOCAL player is a victim
    var player_id = NetworkManager.get_unique_id()
    var is_victim = PowerupManager.is_lights_out_victim(player_id)
    
    if not is_victim:
        return  # This player can see normally
    
    # Dim lights for THIS client (all victims see darkness)
    var museum = _player.get_tree().get_first_node_in_group("museum")
    if not museum:
        return
    
    var light_index = 0
    for light in museum.get_tree().get_nodes_in_group("managed_light"):
        if light is OmniLight3D or light is SpotLight3D:
            if light_index % 10 == 0:
                light.light_energy = 0.3
            else:
                light.light_energy = 0.02
            light_index += 1
```

**Key Change**: Check if the **local player** is a victim, not if this is the local player node.

---

## 🔴 Critical Issue #2: Tower of Babel Language Not Applied

### Problem

`PowerupManager` tracks which players are affected:

```gdscript
var _tower_of_babel_rooms: Dictionary = {}  # player_id -> rooms_remaining
var _tower_of_babel_language: Dictionary = {}  # player_id -> language
```

But there's **no code** that actually applies the language transformation to exhibit text!

### Missing Implementation

The system expects `Hall.gd` to check for Tower of Babel:

```gdscript
# Hall.gd:73 (found in codebase)
var powerup_manager = get_node_or_null("/root/Main/PowerupManager")
if powerup_manager:
    var local_player_id = NetworkManager.get_unique_id()
    var has_pk = powerup_manager.has_powerup(local_player_id, PowerupManager.PowerupType.PERFECT_KNOWLEDGE)
    # ... but no Tower of Babel check!
```

### Fix Required

**Add to `Hall.gd`** (wherever room labels are set):

```gdscript
func _update_room_labels() -> void:
    var powerup_manager = get_node_or_null("/root/Main/PowerupManager")
    if powerup_manager:
        var player_id = NetworkManager.get_unique_id()
        
        # Check if this player is affected by Tower of Babel
        if powerup_manager.is_tower_of_babel_active(player_id):
            var language = powerup_manager.get_tower_of_babel_language(player_id)
            _apply_language_to_labels(language)
        else:
            _apply_default_language_to_labels()
```

**Add to `PowerupManager`**:

```gdscript
func _apply_language_to_labels(language: String) -> void:
    # Translate room name using language code
    # e.g., "Eiffel Tower" → "Tour Eiffel" (fr)
    # This requires ExhibitFetcher to support translated titles
    pass
```

---

## 🔴 Critical Issue #3: Magnet Network Teleport Broken

### Problem

```gdscript
# PlayerPowerupSystem.gd:317
func _pull_all_players_to_room(target_room: String) -> void:
    var all_players = _player.get_tree().get_nodes_in_group("Player")
    for p in all_players:
        if p == _player:
            continue
        var peer_id = p.get_multiplayer_authority() if p.has_method("get_multiplayer_authority") else 1
        if peer_id != NetworkManager.get_unique_id():
            _teleport_player_to_room(p, target_room)  # ❌ DOES NOTHING!
```

And `_teleport_player_to_room()`:

```gdscript
func _teleport_player_to_room(target_player: CharacterBody3D, target_room: String) -> void:
    # ... finds teleport position ...
    
    if target_player.is_local:  # ❌ Only works for local player!
        target_player.global_transform.origin = teleport_pos
        if "current_room" in target_player:
            target_player.current_room = target_room
    else:
        # Network player - would need RPC to teleport
        pass  # ❌ DOES NOTHING!
```

### Impact

When a player uses Magnet:
- Local player stays in place (correct - caster doesn't teleport self)
- **Remote players are NOT teleported** (broken!)
- No visual feedback anywhere

### Fix Required

**Add RPC for network teleport**:

```gdscript
# PlayerPowerupSystem.gd
func _pull_all_players_to_room(target_room: String) -> void:
    var caster_id = NetworkManager.get_unique_id()
    var all_players = _player.get_tree().get_nodes_in_group("Player")
    
    for p in all_players:
        if p == _player:
            continue
        
        var peer_id = p.get_multiplayer_authority()
        if peer_id == caster_id:
            # Caster is pulling others - server handles this
            if multiplayer.is_server():
                _rpc_teleport_player_to_room.rpc(p, target_room)
        else:
            # This client owns this player - teleport locally
            if p.is_local:
                _teleport_player_to_room(p, target_room)

@rpc("authority", "call_local", "reliable")
func _rpc_teleport_player_to_room(target_player: CharacterBody3D, target_room: String) -> void:
    _teleport_player_to_room(target_player, target_room)
```

**Better Approach**: Handle Magnet entirely on server:

```gdscript
# PowerupManager.gd
func activate_magnet(caster_id: int, target_room: String) -> void:
    _magnet_target_room = target_room
    # Server tells all clients to teleport their players
    _rpc_magnet_pull.rpc(caster_id, target_room)

@rpc("authority", "call_local", "reliable")
func _rpc_magnet_pull(caster_id: int, target_room: String) -> void:
    # Each client teleports their local player (except caster)
    var local_id = NetworkManager.get_unique_id()
    if local_id != caster_id:
        var player = _get_local_player()
        if player:
            _teleport_player_to_room(player, target_room)
    # Show visual effect
    _show_magnet_pull_effect(caster_id, target_room)
```

---

## 🟠 High Priority Issue #4: Grapple Visual Not Synced

### Problem

When Player A uses grapple:
- Player A sees their own grapple rope ✅
- Player B sees **nothing** ❌

### Why

```gdscript
# PlayerPowerupSystem.gd:389
func _create_grapple_rope(from: Vector3, to: Vector3) -> void:
    _grapple_rope = CSGBox3D.new()
    # ... creates rope ...
    _player.get_tree().current_scene.add_child(_grapple_rope)
```

The rope is created locally and never synced.

### Fix Required

**Option 1: RPC Sync (Simple)**

```gdscript
@rpc("authority", "call_local", "reliable")
func _rpc_create_grapple_rope(player_id: int, from: Vector3, to: Vector3) -> void:
    _create_grapple_rope_for_player(player_id, from, to)
```

**Option 2: Network Spawn (Better)**

Spawn a network-synced grapple rope node that all clients can see.

---

## 🟠 High Priority Issue #5: Gun/Trap Effects Not Synced

### Problem

```gdscript
# PlayerPowerupSystem.gd:251
func _spawn_gun_projectile_effect(from: Vector3, to: Vector3) -> void:
    var effect := MeshInstance3D.new()
    # ... creates effect locally ...
```

Other players don't see:
- Gun projectile beam
- Trap placement
- Trap trigger teleport

### Fix Required

Add RPC broadcasts for all visual effects:

```gdscript
# When firing gun
_spawn_gun_projectile_effect(from, hit_position)
_rpc_gun_effect.rpc(from, hit_position)

@rpc("authority", "call_local", "reliable")
func _rpc_gun_effect(from: Vector3, to: Vector3) -> void:
    _spawn_gun_projectile_effect(from, to)
```

---

## 🟡 Medium Priority Issue #6: Perfect Knowledge Only Local

### Current Behavior

Each player's Perfect Knowledge only affects their own client. This is **actually correct** - the powerup should only reveal doors for the player who has it.

### Enhancement (Optional)

Add visual indicator when another player has Perfect Knowledge active (glowing eyes icon above their head).

---

## 📋 Complete Fix Checklist

### Critical (Blocks Re-Enablement)

- [ ] **Fix Lights Out** - Check victim status, not `_is_local`
- [ ] **Fix Tower of Babel** - Implement language transformation in Hall.gd
- [ ] **Fix Magnet** - Add RPC for network player teleport
- [ ] **Test all effects** in 2-player, 4-player, 8-player sessions

### High Priority

- [ ] **Sync grapple rope** - RPC broadcast for visual
- [ ] **Sync gun beam** - RPC broadcast for visual
- [ ] **Sync trap placement** - RPC broadcast for visual
- [ ] **Sync trap trigger** - Show victim teleport effect

### Medium Priority

- [ ] **Add victim indicators** - UI element when affected by Tower/Lights Out/Omniscience
- [ ] **Add audio cues** - Sound when powerup used near you
- [ ] **Add visual indicators** - Icon above players with active powerups

---

## 🔧 Implementation Priority

### Week 1: Core Sync Fixes
1. **Day 1-2**: Fix Lights Out (critical, affects all players)
2. **Day 3-4**: Fix Magnet teleport (critical, completely broken)
3. **Day 5**: Fix Tower of Babel language application

### Week 2: Visual Sync
1. **Day 1-2**: Add RPC for grapple rope
2. **Day 3**: Add RPC for gun/trap effects
3. **Day 4-5**: Test all fixes in multiplayer

### Week 3: Polish
1. **Day 1-2**: Add victim indicators
2. **Day 3-4**: Add audio/visual feedback
3. **Day 5**: Final testing

---

## 🧪 Testing Matrix

After fixes, test each powerup:

| Powerup | Local Effect | Remote Visual | Remote Effect | Sync Status |
|---------|--------------|---------------|---------------|-------------|
| Speed Boost | ✅ Self faster | ⚠️ See others fast | N/A | Needs visual |
| Perfect Knowledge | ✅ Doors revealed | ⚠️ Icon above player | N/A | OK as-is |
| Gun | ✅ Fires, teleports | ❌ No beam | ✅ Victim teleports | Needs beam |
| Trap | ✅ Places, triggers | ❌ No trap model | ✅ Victim teleports | Needs trap |
| Tower of Babel | ⚠️ Language? | ⚠️ Icon above caster | ❌ No language | CRITICAL |
| Lights Out | ❌ No dimming | ⚠️ Icon above caster | ❌ No dimming | CRITICAL |
| Magnet | ✅ Pulls others | ⚠️ Effect? | ❌ No teleport | CRITICAL |
| Grapple | ✅ Swings | ❌ No rope | N/A | Needs rope |
| Omniscience | ✅ Spy panel | ⚠️ Icon above caster | N/A | OK as-is |

**Legend**: ✅ Working | ⚠️ Partial/Enhancement | ❌ Broken | CRITICAL Blocks release

---

## 📝 Code Changes Summary

### Files to Modify

1. **PlayerPowerupSystem.gd** (~200 lines changed)
   - Remove `_is_local` guards from shared effects
   - Add RPC methods for visual sync
   - Fix Magnet teleport

2. **PowerupManager.gd** (~50 lines changed)
   - Add Magnet RPC
   - Add Tower of Babel language application helper
   - Fix Lights Out victim check

3. **Hall.gd** (~30 lines added)
   - Check Tower of Babel status
   - Apply language transformation to labels

4. **Main.gd** (~20 lines added)
   - Register new RPC methods
   - Add victim indicator UI

**Total**: ~300 lines of changes

---

## 🎯 Success Criteria

Powerup effects are properly synced when:

- [ ] Lights Out dims lights for ALL victims simultaneously
- [ ] Magnet teleports ALL players to caster's room
- [ ] Tower of Babel shows foreign language text to ALL victims
- [ ] Grapple rope visible to ALL players
- [ ] Gun beam visible to ALL players
- [ ] Trap visible to placer, teleport visible to all
- [ ] No desync errors in console
- [ ] 60 FPS maintained with all effects active

---

*Analysis completed: March 17, 2026*  
*Estimated fix time: 10-15 days*  
*Priority: CRITICAL - Blocks v0.5.0 powerup re-enablement*
