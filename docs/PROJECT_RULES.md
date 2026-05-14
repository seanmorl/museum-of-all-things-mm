# Project Rules: Museum of All Things

**Version:** 1.0  
**Last Updated:** April 2026

---

## 1. Architecture Rules

### 1.1 Use Autoloads, Not Services
- **Primary API:** Direct autoload singleton access (e.g., `NetworkManager.is_server()`)
- **Archived:** Services.gd is deprecated - do not use for new code
- **Rationale:** Godot-idiomatic, no indirection, already used everywhere

### 1.2 Event-Driven Communication
- **Required:** Use EventBus signals for inter-system communication
- **Forbidden:** Direct method calls between unrelated systems
- **Exceptions:** Player → Main communication via `get_tree().current_scene` (to be refactored)

### 1.3 Subsystem Pattern for Player
- Player.gd must delegate to specialized subsystems
- Each subsystem handles one responsibility
- Subsystems communicate via Player facade methods

---

## 2. Coding Standards

### 2.1 Type Safety
- **Required:** Use GDScript 4.x type hints on all variables and function parameters
- **Return types:** Specify return types on all functions
- **Exceptions:** None (strict typing required)

### 2.2 Naming Conventions
- **Private variables:** `_name` prefix
- **Constants:** `UPPER_SNAKE_CASE`
- **Signals:** past tense (e.g., `race_started`)
- **Methods:** snake_case

### 2.3 Memory Management
- **Required:** Disconnect signals in `_exit_tree()`
- **Pattern:** Use `is_connected()` guard before disconnect
- **Forbidden:** Lambdas that capture external references (unless brief)

### 2.4 Error Handling
- **Required:** Log errors with `Log.error()` or `Log.warn()`
- **Required:** Validate all user input
- **Required:** Handle null checks on `get_node_or_null()`

---

## 3. Network Security Rules

### 3.1 RPC Validation
- **Required:** Validate sender identity on all RPCs
- **Pattern:** Check `multiplayer.get_remote_sender_id()` matches claimed peer_id
- **Forbidden:** Trust client-provided data without validation

### 3.2 Anti-Cheat
- **Required:** Path validation for race win detection
- **Required:** Server-side room history tracking
- **Required:** Rate limiting on host migration (30s cooldown)

### 3.3 Connection Handling
- **Required:** Keepalive pings every 5 seconds (playit.gg UDP tunnel)
- **Required:** 32-second ENet timeout configuration
- **Required:** Connection watchdog for failed connections (15s timeout)

---

## 4. UI/UX Rules

### 4.1 Theme Consistency
- **Required:** Use ThemeManager for all UI styling
- **Forbidden:** Hardcoded colors in UI elements
- **Pattern:** Theme-aware text colors via `add_theme_color_override()`

### 4.2 Accessibility
- **Required:** Support colorblind modes
- **Required:** Provide invert Y option
- **Required:** Support UI scaling
- **Required:** Support gamepad navigation

### 4.3 Input Handling
- **Forbidden:** Direct input processing when menus are open
- **Pattern:** Use `InputMap` action-based input, not raw key codes
- **Hint:** Provide feedback for all user actions

---

## 5. Performance Rules

### 5.1 Network Optimization
- **Required:** Throttle position sync to 100ms minimum
- **Required:** Use interpolation for remote player movement
- **Recommended:** Use unreliable RPC for position updates

### 5.2 Memory Optimization
- **Required:** Clear hint cache between races
- **Required:** Remove signal connections before freeing nodes
- **Forbidden:** Store large data in signals

### 5.3 Loading Optimization
- **Required:** Use async texture loading where possible
- **Required:** Show loading indicators during long operations
- **Recommended:** Pre-fetch exhibit data during race countdown

---

## 6. Documentation Rules

### 6.1 Code Documentation
- **Required:** Docstrings on all public methods
- **Required:** Document anti-cheat logic with inline comments
- **Recommended:** Document complex state transitions

### 6.2 Architecture Documentation
- **Required:** Update ARCHITECTURE_DECISIONS.md for significant changes
- **Required:** Keep ROADMAP.md current
- **Required:** Document deprecated patterns

---

## 7. Testing Rules

### 7.1 Manual Testing
- **Required:** Test multiplayer with 2+ actual players
- **Required:** Test VR compatibility if affecting VR code
- **Required:** Test cross-platform exports

### 7.2 Regression Prevention
- **Required:** Verify race voting works after refactoring
- **Required:** Verify mount/dismount works after subsystem changes
- **Required:** Test network reconnection scenarios

---

## 8. Version Control Rules

### 8.1 Commit Messages
- **Format:** `type(scope): description`
- **Examples:** `fix(race): correct countdown timing`, `feat(ui): add tournament bracket`
- **Forbidden:** "WIP" or "temp" in final commits

### 8.2 Branching Strategy
- **Main:** Stable releases
- **Development:** Active development
- **Feature branches:** For new features
- **Hotfix branches:** For critical bugs

---

## 9. Exception Process

To deviate from these rules:
1. Document the reason in code comments
2. Add to ARCHITECTURE_DECISIONS.md if significant
3. Verify no regression in functionality
4. Test with multiplayer if affects networking

---

## 10. Enforcement

- **Linting:** Use Godot editor warnings
- **Code Review:** All PRs require review
- **Documentation:** Required for new features

---

*These rules ensure code quality and maintainability across the project.*