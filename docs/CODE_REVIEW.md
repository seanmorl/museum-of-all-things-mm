# Code Review: Museum of All Things

**Review Date:** May 2026  
**Reviewer:** AI Code Reviewer  
**Codebase Version:** v0.3.5  

---

<analysis>
## Code Review Analysis: Museum of All Things

### 1. Code Organization & Structure

**Strengths:**
- **Well-organized modular subsystems** in Player.gd (crouch, mount, skin, painting, pointing, journal, footprint) - follows single responsibility principle effectively
- **Event-driven architecture** via EventBus.gd - good for decoupling between systems
- **Autoload singletons** properly used as primary API (per architecture decision in ARCHITECTURE_DECISIONS.md)
- **Archived/deprecated code** properly separated in `_archived_*` directories
- **Good separation** between scenes, scripts, assets, shaders, and docs

**Issues/Concerns:**
- **Main.gd is monolithic** (~1400+ lines) - handles too many responsibilities: menu control, multiplayer coordination, race management, tournament UI, daily challenge UI, accessibility, and ~50+ input actions
- **Player.gd is also large** (~1000 lines) - while subsystem pattern helps, the main file still has extensive responsibilities (void detection, mount/dismount, painting eat, pointing, interactable target tracking)
- **Circular dependencies** - Player.gd calls Main.gd methods directly via `get_tree().current_scene.has_method()` instead of using signals
- **Services.gd is archived but still loaded** - creates confusion per documentation
- **Duplicate race state tracking** - Main.gd maintains `_race_candidates`, `_race_start_article`, `_race_fetches_pending` while RaceManager also tracks candidates

**Suggestions:**
- Break Main.gd into focused controllers (GameController, MenuController, MultiplayerController, RaceController)
- Extract tournament/daily challenge logic into dedicated managers
- Replace direct Main references with EventBus signals
- Consolidate race state into single source (RaceManager)

### 2. Code Quality & Best Practices

**Strengths:**
- **Strong typing** used throughout (GDScript 4.x type hints)
- **Proper signal management** - memory leak fixes implemented with `is_connected()` guards
- **Security-first multiplayer** - sender_id validation on all RPCs
- **Anti-cheat implementation** - path validation, speed detection, teleport detection
- **Good error handling** with try/catch patterns and fallback logic
- **Constants properly defined** - VOID_Y_THRESHOLD, VOID_CHECK_INTERVAL, etc. in appropriate files

**Issues/Concerns:**
- **Inconsistent naming patterns** - some methods use `_name` (private convention) but are actually public API
- **Some magic numbers inline** - while key constants are extracted, some intermediate values remain hardcoded
- **Duplicate code** in Player.gd mount/dismount logic (two nearly identical blocks for mounting)
- **Deprecated patterns still in code** - Services.gd referenced, archived services loaded
- **Complex anti-cheat** - path validation logic spans multiple files and is hard to follow

**Suggestions:**
- Add `const` for any remaining magic numbers in loops/conditionals
- Create base interface for subsystems to reduce duplication
- Document complex algorithms (anti-cheat path validation) with inline comments
- Add unit tests for critical systems (RaceManager win detection)

### 3. UI/UX

**Strengths:**
- **Theme-aware styling** via ThemeManager - consistent look across all UI elements
- **Accessibility features** - colorblind support (4 modes), invert y, UI scaling (Ctrl+/-/0)
- **Multiple input support** - keyboard, gamepad, VR with proper deadzone handling
- **Post-processing effects** - CRT, VHS, soft, PS1 for aesthetic variety
- **Good feedback** - hover states, transitions, loading indicators
- **Loading states** - VoteHUD shows loading during candidate fetch

**Issues/Concerns:**
- **Complex input handling** - Main.gd handles ~50+ input actions in single `_input()` method
- **UI states can conflict** - multiple overlays can be open simultaneously (journal, map, trivia, vote)
- **Host menu accessibility** - F1/H hotkey may conflict with common browser/debugger shortcuts
- **Some UI elements created dynamically** in code - harder to maintain than scene-based
- **Missing loading feedback** - dedicated host start doesn't show loading state

**Suggestions:**
- Centralize input handling with input modifiers and action handlers
- Add UI state machine to prevent overlay conflicts
- Consider standardizing keybinds with common game conventions (F1 for help/debug, not game actions)
- Move more UI to scene-based structures with script inheritance
- Add loading indicators for network operations (host start, leaderboard fetch)

### 4. Multiplayer & Networking

**Strengths:**
- **Robust ENet implementation** with proper fallback for hostname resolution
- **Keepalive/timeout handling** for playit.gg UDP tunnels (5s ping, 32s timeout)
- **Host migration support** with state transfer and rate limiting
- **Position interpolation** for smooth remote player movement
- **Connection watchdog** for failed connections (15s timeout)
- **Anti-spoofing validation** on all RPCs

**Issues/Concerns:**
- **Complex state sync** - multiple systems (NetworkManager, Services, RaceManager) all handle state
- **Race state tracked in multiple places** (Main.gd, RaceManager, GameState) - consolidation needed
- **Migration code complexity** - the `/_elect_and_migrate_host()` flow is intricate
- **Late joiner sync** - race state sync to new peers may miss intermediate state

**Suggestions:**
- Consolidate race state into single source (RaceManager) - remove from Main.gd
- Add network state validation/sync tests
- Consider reducing RPC overhead with unreliable position sync more aggressively
- Document host migration flow with sequence diagram

### 5. Performance & Optimization

**Strengths:**
- **Position sync throttling** (100ms) - good bandwidth optimization
- **Signal-based architecture** reduces polling
- **Void detection** prevents infinite falls with last valid position tracking
- **Memory leak fixes** implemented with proper signal cleanup
- **Hint cache clearing** between races prevents memory growth

**Issues/Concerns:**
- **No frame time monitoring** - can't detect performance issues on low-end hardware
- **No object pooling** - frequently created/destroyed objects (particles, audio sources) may cause GC spikes
- **Async texture loading incomplete** - per OPTIMIZATION_SUMMARY.md, still needed
- **Memory profiling missing** - no tracking of large allocations

**Suggestions:**
- Add frame rate monitoring for mobile/VR with warning on sustained low FPS
- Consider object pooling for frequently created/destroyed objects
- Implement async texture loading as documented in optimization plan
- Add optional connection quality indicator for multiplayer

### 6. Security

**Strengths:**
- **Sender validation** on all RPCs
- **Anti-cheat path validation** prevents teleport exploits
- **Rate limiting** on host migration (30s cooldown)
- **Input sanitization** (player names limited to 32 chars)
- **Room name length validation** (256 char limit)

**Issues/Concerns:**
- **Client-provided paths still accepted** as fallback when server tracking unavailable
- **Some anti-cheat checks have bypass paths** - room history size 0 allows direct wins

**Suggestions:**
- Strengthen fallback validation - require minimum path length even for client-provided
- Add server-side velocity checks for speed hack detection
- Consider adding client-side hash verification

---

## Summary

The codebase demonstrates solid engineering practices with:
- ✅ Good architectural decisions (autoloads, event-driven, subsystems)
- ✅ Strong security focus (anti-cheat, RPC validation)
- ✅ Comprehensive accessibility features
- ✅ Clean signal management and memory handling

Areas needing attention:
- ⚠️ Main.gd size and responsibility sprawl
- ⚠️ Race state duplication (Main.gd + RaceManager)
- ⚠️ Direct Main references instead of signals
- ⚠️ UI overlay conflict prevention
- ⚠️ Performance monitoring for low-end hardware
</analysis>

---

# Optimization Plan

## Code Structure & Organization

### Step 1: Consolidate Race State Management
- **Task:** Remove duplicate race tracking from Main.gd, use RaceManager as single source of truth
- **Files:**
  - `scenes/Main.gd`: Remove `_race_candidates` (line 986), `_race_start_article` (line 987), `_race_fetches_pending` (line 988), `_race_retry_count` (line 989). Update methods to use RaceManager getters instead.
  - `scenes/util/RaceManager.gd`: Ensure `get_vote_candidates()` returns current candidates. Add `get_vote_start_article()` if needed.
- **Step Dependencies:** None
- **Acceptance Criteria:** Race voting still functions correctly; Main.gd no longer stores race candidates directly; vote HUD reads from RaceManager

### Step 2: Break Up Main.gd - Extract Tournament UI Initialization
- **Task:** Move tournament node creation and management to TournamentManager
- **Files:**
  - `scenes/Main.gd`: Remove `_spawn_tournament_nodes()` body (lines 1067-1133), replace with `TournamentManager.initialize_ui(self, _menu_layer)`
  - `scenes/util/TournamentManager.gd`: Add `initialize_ui(main, menu_layer)` method that creates tournament UI nodes
  - `scenes/tournament/TournamentHUD.gd`: Ensure script exists and handles initialization
- **Step Dependencies:** Step 1
- **Acceptance Criteria:** Tournament UI (HUD, bracket, victory screen, setup menu) still spawns and functions after initialization

### Step 3: Extract Daily Challenge UI Initialization
- **Task:** Consolidate daily challenge HUD creation into DailyChallengeManager
- **Files:**
  - `scenes/Main.gd`: Replace lines 237-264 (daily challenge setup) with `DailyChallengeManager.initialize_ui(self, _menu_layer)`
  - `scenes/autoload/DailyChallengeManager.gd`: Add `initialize_ui(main, menu_layer)` method that creates CanvasLayer and HUD
  - Update `_on_daily_challenge_started`, `_on_daily_challenge_closed` to use manager methods
- **Step Dependencies:** None
- **Acceptance Criteria:** Daily challenge card and HUD still appear correctly; leaderboard still fetches data

### Step 4: Create Dedicated Input Manager
- **Task:** Extract input action registration and keybind setup into dedicated manager
- **Files:**
  - `scenes/util/InputManager.gd` (new): Create class with methods:
    - `register_trivia_keybind()` - K key
    - `register_daily_challenge_keybind()` - G key
    - `register_host_menu_keybind()` - Ctrl+H
    - `register_spectator_keybind()` - F key
    - `register_ui_scale_shortcuts()` - Ctrl+=/-/0
    - `register_screenshot_keybind()` - F12
    - `register_all()` - Call all registration methods
  - `scenes/Main.gd`: Replace keybind registration blocks (lines 270-334) with single call `InputManager.register_all()`
  - Update `project.godot` if needed for new input actions
- **Step Dependencies:** None
- **Acceptance Criteria:** All keybinds still work (K, G, Ctrl+H, F, Ctrl+=/-/0, F12); removing Main.gd references doesn't break inputs

### Step 5: Replace Main.gd Direct Calls with EventBus Signals
- **Task:** Use EventBus signal-based communication instead of direct Main reference in Player.gd
- **Files:**
  - `scenes/core/EventBus.gd`: Add new signals:
    - `mount_requested(target: Node)`
    - `dismount_requested()`
    - `steal_painting_requested(exhibit_title, image_title, image_url, image_size, is_audio)`
    - `place_painting_requested(exhibit_title, image_title, image_url, wall_position, wall_normal, image_size, is_audio)`
    - `eat_painting_requested(exhibit_title, image_title)`
  - `scenes/Player.gd`: Replace `get_tree().current_scene.has_method("_request_mount")` with `GameplayEvents.mount_requested.emit(target)` (lines 562-565, 568-573, 897-925)
  - `scenes/Main.gd`: Connect new EventBus signals to existing handlers in `_ready()`:
    - `GameplayEvents.mount_requested.connect(_request_mount)`
    - `GameplayEvents.dismount_requested.connect(_request_dismount)`
    - etc.
- **Step Dependencies:** None
- **Acceptance Criteria:** Mount/dismount, painting steal/place/eat still work via E key; architecture properly decoupled

---

## Code Quality Improvements

### Step 6: Add GameConstants File for Magic Numbers
- **Task:** Extract magic numbers scattered across codebase into centralized constants
- **Files:**
  - `scenes/util/GameConstants.gd` (new): Define constants:
    ```gdscript
    # Player constants
    VOID_Y_THRESHOLD: float = -50.0
    VOID_CHECK_INTERVAL: float = 0.5
    VOID_SPAWN_Y: float = 5.0
    VOID_SPAWN_XZ: Vector2 = Vector2(0, 23)
    
    # Race constants
    VOTE_DURATION: float = 20.0
    CANDIDATE_COUNT: int = 5
    MAX_RACE_RETRIES: int = 10
    
    # UI constants
    HINT_COOLDOWN_SECONDS: float = 3.0
    CONNECTION_TIMEOUT: float = 15.0
    KEEPALIVE_INTERVAL: float = 5.0
    
    # Performance constants
    POSITION_SYNC_INTERVAL: float = 0.1
    MIGRATION_TIMEOUT: float = 15.0
    ```
  - `scenes/Player.gd`: Replace magic numbers with `GameConstants.VOID_Y_THRESHOLD` etc.
  - `scenes/util/RaceManager.gd`: Replace with constants
  - `scenes/util/NetworkManager.gd`: Replace with constants
- **Step Dependencies:** None
- **Acceptance Criteria:** All magic numbers replaced with named constants; no regressions in gameplay

### Step 7: Document Anti-Cheat Path Validation
- **Task:** Add comprehensive documentation to RaceManager path validation
- **Files:**
  - `scenes/util/RaceManager.gd`: Add docstrings and inline comments:
    - Document `_validate_path_continuity()` with algorithm explanation
    - Document `_are_rooms_connected()` with connection graph concept
    - Document `_get_exhibit_by_title()` fallback behavior
    - Add sequence diagram comment for win validation flow
- **Step Dependencies:** None
- **Acceptance Criteria:** New contributors can understand anti-cheat logic from code comments; no functional changes

### Step 8: Extract UI Helpers into Shared Module
- **Task:** Create shared UI utility functions to reduce duplication in menu scripts
- **Files:**
  - `scenes/util/UIUtils.gd` (new): Create helper functions:
    - `create_centered_label(text, font_size, color)` -> Label
    - `create_styled_button(text, callback)` -> Button
    - `theme_label_from_style(label, style_name)` -> void
    - `create_modal_background()` -> ColorRect
  - `scenes/menu/MainMenu.gd`: Refactor to use UIUtils for repeated patterns
  - `scenes/menu/MultiplayerMenu.gd`: Refactor to use UIUtils
  - `scenes/menu/HostMenu.gd`: Refactor to use UIUtils
- **Step Dependencies:** None
- **Acceptance Criteria:** Reduced code duplication in menu scripts; identical styling across menus

---

## UI/UX Improvements

### Step 9: Implement Overlay State Manager
- **Task:** Prevent conflicting overlay states (journal + map + trivia simultaneously)
- **Files:**
  - `scenes/util/OverlayStateManager.gd` (new): Track open overlays with methods:
    - `open_overlay(type: OverlayType)` - Open specific overlay, close conflicting ones
    - `close_overlay(type: OverlayType)` - Close specific overlay
    - `is_any_blocking()` -> bool - Check if game input should be blocked
    - `get_open_overlay_types()` -> Array[OverlayType]
    - Define `enum OverlayType { JOURNAL, MAP, TRIVIA, SETTINGS, PAUSE }`
  - `scenes/Main.gd`: Replace journal/map/trivia toggle logic (lines 722-749) with `OverlayStateManager.open_overlay()`
  - Update `_input()` to check `OverlayStateManager.is_any_blocking()` before processing game inputs
- **Step Dependencies:** Step 4
- **Acceptance Criteria:** Only one overlay type (journal/map/trivia/settings/pause) visible at a time; non-conflicting elements (vote HUD, chat) still work

### Step 10: Change Host Menu Hotkey from F1 to Ctrl+H
- **Task:** Reduce F1 conflicts with common browser/debugger shortcuts
- **Files:**
  - `scenes/Main.gd`: Change keybind registration (lines 284-294) to use Ctrl+H instead of F1/H
  - `project.godot`: Update `toggle_host_menu` input action to remove F1, add Ctrl+H
  - Update documentation in CONTRIBUTING.md if keybind conventions documented
- **Step Dependencies:** None
- **Acceptance Criteria:** Host menu opens with Ctrl+H; F1 reserved for browser help/debug

### Step 11: Add Loading States for Dynamic UI Elements
- **Task:** Show loading indicators when creating dynamic UI or fetching data
- **Files:**
  - `scenes/Main.gd`: Add loading indicator in `_start_ui_dedicated_host()` method (lines 569-623):
    - Create `Label` showing "Starting server..."
    - Update label to "Waiting for players..." after server starts
    - Remove loading label when first player connects
  - `scenes/menu/DailyChallengeCard.gd`: Add loading state for leaderboard fetch with spinner
  - `scenes/ui/LoadingScreen.tscn`: Verify loading indicator exists and shows for network operations
- **Step Dependencies:** None
- **Acceptance Criteria:** Users see feedback during network operations; no UI appears without context

---

## Performance & Polish

### Step 12: Add Frame Time Warning for Low-End Hardware
- **Task:** Log warning when frame time exceeds targets for extended period
- **Files:**
  - `scenes/Main.gd`: Add FPS monitoring code to `_process()` (after line 808):
    ```gdscript
    var _low_fps_count: int = 0
    const LOW_FPS_THRESHOLD: int = 45
    const LOW_FPS_WARNING_COUNT: int = 150  # ~2.5 seconds at 60fps
    
    if _fps_label.visible:
        var fps := Engine.get_frames_per_second()
        if fps < LOW_FPS_THRESHOLD:
            _low_fps_count += 1
            if _low_fps_count >= LOW_FPS_WARNING_COUNT:
                Log.warn("Main", "Low FPS detected (%d fps for %d frames)" % [fps, _low_fps_count])
        else:
            _low_fps_count = 0
    ```
  - Add to GameConstants.gd for Step 6 integration
- **Step Dependencies:** Step 6
- **Acceptance Criteria:** Console warning if FPS drops below 45 for 5+ seconds; warning includes frame count

### Step 13: Add Network Quality Indicator
- **Task:** Visual feedback for connection quality in multiplayer
- **Files:**
  - `scenes/util/NetworkManager.gd`: Add methods:
    - `get_connection_quality()` -> String ("good", "degraded", "poor") based on packet loss/ping
    - Track average latency via ENet peer stats if available
  - `scenes/ui/RaceStatusHUD.gd`: Add optional connection quality indicator (green/yellow/red dot) in corner
  - Make indicator optional in settings (default off)
- **Step Dependencies:** None
- **Acceptance Criteria:** Players can optionally see connection quality in multiplayer; off by default to reduce UI clutter

### Step 14: Cleanup Archived Code References
- **Task:** Remove remaining references to archived Services and clean up deprecation warnings
- **Files:**
  - `scenes/Main.gd`: Remove `Services.room_service` initialization (lines 135-153), replace with direct exhibit loader access
  - Remove any `Services.get_*()` calls throughout codebase
  - `scenes/core/Services.gd`: Verify it's only used for deprecation warning (already archived)
  - `scenes/Museum.gd`: Check for any Services references, replace with autoloads
- **Step Dependencies:** None
- **Acceptance Criteria:** No runtime warnings about deprecated Services usage; all game logic uses autoloads directly

## Additional Context: Events vs Power-ups

**Status:** Environmental events (Darkness, Fog, Earthquake, etc.) are the active system replacing old power-ups.

The event files in `scenes/util/events/` are live code, not archived. They share boilerplate patterns worth cleaning up.

---

## Additional Optimization: Event System Refactor

*Theme: Eliminate Event Boilerplate Duplication*

20+ event files each duplicate the same 5-method pattern (apply/end/duration/display/description). A base class reduces total event file size by ~40% and makes adding new events trivial.

### Step 15: Create EventBase Base Class
- **Task:** Create `scenes/util/events/EventBase.gd` as abstract base class providing:
  - Common `get_duration()`, `get_display_name()`, `get_description()` implementations
  - Static `register()` / `unregister()` methods for auto-registration
  - Common `apply()` / `end()` hooks (no-ops by default)
  - Shared logging prefix from class name
- **Files:**
  - `scenes/util/events/EventBase.gd` (new): ~80 lines
- **Dependencies:** None
- **Acceptance Criteria:** EventBase.gd compiles; no runtime errors on load

### Step 16: Refactor 5 Simple Events to Use EventBase
- **Task:** Refactor events with no scene access:
  1. `SpeedUpEvent.gd` - uses `set_global_speed_modifier(1.5)`
  2. `HeavyGravityEvent.gd` - uses `set_global_speed_modifier(0.6)`
  3. `TimeDilationEvent.gd` - uses `set_timer_scale(0.5)`
  4. `DoubleTimeEvent.gd` - uses `set_timer_scale(2.0)`
  5. `NoRunningEvent.gd` - uses `set_dash_enabled(false)`
- **Files:**
  - `scenes/util/events/EventBase.gd`: add static registry methods
  - `scenes/util/events/SpeedUpEvent.gd`: reduce to ~30 lines
  - `scenes/util/events/HeavyGravityEvent.gd`: reduce to ~30 lines
  - `scenes/util/events/TimeDilationEvent.gd`: reduce to ~30 lines
  - `scenes/util/events/DoubleTimeEvent.gd`: reduce to ~30 lines
  - `scenes/util/events/NoRunningEvent.gd`: reduce to ~30 lines
- **Dependencies:** Step 15
- **Acceptance Criteria:** All 5 events still function identically; EventManager triggers them via base class

### Step 17: Refactor 5 Medium Events (with scene access)
- **Task:** Refactor events needing scene access (camera, lights, audio):
  1. `DarknessEvent.gd` - manages WorldLight
  2. `FogEvent.gd` - manages WorldEnvironment fog
  3. `SilenceEvent.gd` - manages AudioServer buses
  4. `EarthquakeEvent.gd` - manages camera shake
  5. `ColorShiftEvent.gd` - manages material colors
- **Files:**
  - `scenes/util/events/EventBase.gd`: add `get_museum()` and `get_local_player()` helpers
  - Each event file: reduce to 35-45 lines
- **Dependencies:** Step 16
- **Acceptance Criteria:** All 5 events still function identically

### Step 18: Refactor Remaining Events + Update EventManager
- **Task:** 
  - Refactor remaining 10 events (DoubleJump, TripleJump, LowGravity, FlyingArtwork, Cacophony, WeatherSystem, Reversed, RandomTeleport, BackwardsControls, Fog variant)
  - Update `EventManager.gd` to use EventBase registry instead of `allowed_events` array
- **Files:**
  - All 10 event files: reduce to 25-50 lines each
  - `scenes/util/events/EventManager.gd`: use `EventBase.get_registered_events()`, update match statement
- **Dependencies:** Step 17
- **Acceptance Criteria:** All events work; new events auto-register without manual updates; total code reduced from ~600 lines to ~350 lines

---

## Summary

| Category | Steps | Files Modified (Est.) |
|----------|-------|----------------------|
| Code Structure & Organization | 1-5 | ~15 files |
| Code Quality Improvements | 6-8 | ~12 files |
| UI/UX Improvements | 9-11 | ~8 files |
| Performance & Polish | 12-14 | ~6 files |
| Event System Refactor | 15-18 | ~25 files |
| **Total** | **18 steps** | **~50 files** |

**Risk Level:** Low - all changes maintain existing functionality  
**Priority Order:** Structure (1-5) → Quality (6-8) → UX (9-11) → Polish (12-14) → Events (15-18)  
**Estimated Time:** 6-8 hours total (spreads across sessions)

---

## Guidance for Implementation

1. **Test after each step** - Run the game and verify race/multiplayer still work
2. **Run existing tests** - Check `scenes/test/` for automated tests (`EventTests.tscn`, etc.)
3. **Check export builds** - Some changes may affect Linux/Flatpak builds differently
4. **Review keybinds** - Changes to input handling should be tested with gamepad
5. **Document breaking changes** - If any, add to `docs/CHANGELOG.md`
6. **Peer review** - Submit PR for review before merging

---

## Logical Next Step

After completing all optimization steps, the codebase will be ready for **Tournament Mode completion (v0.4.0)** with:

1. Cleaner architecture that's easier for community contributors to work with
2. Properly decoupled systems (no direct Main references)
3. Centralized constants for easier tuning
4. Overlay conflict prevention for better UX
5. Performance monitoring for support requests

The next logical feature work would be tournament bracket visualization and ranked matchmaking integration.