# Architecture Decision: Services vs Autoload Singletons

**Date:** 2026-04-05  
**Status:** ✅ DECIDED  
**Decision:** Keep autoloads as primary API, archive service layer

---

## The Problem

The codebase has TWO parallel systems for the same functionality:

### Autoload Singletons (Currently Used Everywhere)
```gdscript
NetworkManager.is_server()
RaceManager.start_race()
RoomService.get_current_room()
```
These are registered in `project.godot` `[autoload]` section and available globally.

### Service Layer (Partially Implemented)
```gdscript
Services.get_network().is_server()
Services.get_race().start_race()
Services.get_room().get_current_room()
```
These are thin wrappers around the autoloads, providing a "cleaner" API.

## Analysis

### Service Layer Pros
- ✅ Provides abstraction over autoloads
- ✅ Better testability (could mock services)
- ✅ Clean separation of concerns
- ✅ Follows service locator pattern

### Service Layer Cons
- ❌ **Thin wrappers** - Don't add functionality, just delegate to autoloads
- ❌ **Redundant** - Two ways to do the same thing
- ❌ **Confusing** - New contributors don't know which to use
- ❌ **Incomplete** - Not all features have service equivalents
- ❌ **Indirection overhead** - Extra function calls for no benefit
- ❌ **Maintenance burden** - Need to update both when adding features

### Autoload Pros
- ✅ **Already working** - Used everywhere in codebase
- ✅ **Direct access** - No indirection
- ✅ **Godot-idiomatic** - Standard Godot pattern
- ✅ **Complete coverage** - All features available

### Autoload Cons
- ❌ Global state (but this is fine for Godot games)
- ❌ Harder to test in isolation (but we don't have unit tests anyway)

## Decision

**We will use autoload singletons as the primary API.**

### Rationale

1. **Pragmatism over purity** - The service layer doesn't add enough value to justify the confusion
2. **Godot conventions** - Autoloads are the standard Godot pattern for global managers
3. **Minimal overhead** - Direct calls are faster and simpler
4. **Existing investment** - 99% of code already uses autoloads
5. **No testing framework** - Service mockability doesn't matter without tests

### What This Means

**DO:**
```gdscript
# Direct autoload usage
NetworkManager.is_server()
RaceManager.start_race("Article", "Start")
StickyNoteManager.create_note("Text", pos, rot)
```

**DON'T:**
```gdscript
# Service layer usage (confusing and redundant)
Services.get_network().is_server()
Services.get_race().start_race("Article", "Start")
```

## Implementation Plan

### Phase 1: Document the Decision (NOW) ✅
- Create this document
- Add comments to Services.gd explaining the decision

### Phase 2: Archive Service Layer (Next Dev Session)
- Move `scenes/services/` to `_archived_services_OLD/`
- Remove Services.gd initialization from Main.gd
- Update CODE_QUALITY_ISSUES.md

### Phase 3: Prevent Future Confusion
- Add note to project README about architecture
- New contributors should use autoloads only

## Exceptions

The ONLY valid use of the service layer would be:
- If we add REAL functionality (not just delegation)
- If we need to swap implementations at runtime
- If we add comprehensive unit tests

Until then, autoloads are the way.

## Alternatives Considered

### Alternative 1: Migrate fully to services
- **Rejected because:** Requires massive refactoring with no tangible benefit
- **Would take:** 5-10 hours of careful migration
- **Benefit:** Marginal architectural purity

### Alternative 2: Keep both but document when to use each
- **Rejected because:** Still confusing, still redundant
- **Problem:** Where do you draw the line? When does something belong in services?

### Alternative 3: Make services the real implementation, demote autoloads
- **Rejected because:** Backwards incompatible, breaks existing code
- **Would require:** Rewiring all signal connections, updating all callers

## References

- `scenes/core/Services.gd` - Service locator
- `scenes/services/NetworkService.gd` - Network wrapper
- `scenes/services/RaceService.gd` - Race wrapper
- `scenes/services/RoomService.gd` - Room wrapper
- `scenes/services/ExhibitService.gd` - Exhibit wrapper
- `project.godot` - Autoload registrations
