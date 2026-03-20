# Exhibit Layout Variety

Increase visual and structural variety in procedurally generated exhibits to make exploration more engaging.

## Implemented Features

### [TiledExhibitGenerator.gd](file:///c:/Users/TeamS/Documents/GitHub/museum-of-all-things-mm/scenes/TiledExhibitGenerator.gd)

- **Special Architectural Features**:
    - **Atriums**: Multi-level open spaces (3 levels high) that create vertical drama
        - Triggered by `prefers_verticality()` mood check (HISTORY, MEDIA)
        - 15% chance when adding rooms after the first 2
        - Visualized with purple debug overlay
    - **Grand Halls**: Large symmetrical rooms (5-7 tiles wide)
        - Triggered by `prefers_symmetry()` mood check (HISTORY, SCIENCE)
        - Multiple exit points for better flow
        - Visualized with gold debug overlay

- **Fallback & Validation System**:
    - `_validate_generation_progress()`: Monitors room count during generation
    - `_try_fallback_generation()`: Relaxes constraints when stuck
        - Reduces room dimension requirements
        - Retries from existing rooms (up to 3 attempts)
    - `validate_final_generation()`: Post-generation validation
        - Ensures minimum room count is met
        - Verifies entry point exists
    - Configurable `min_rooms` parameter (default: 2)

- **Debug Visualization**:
    - `debug_mode` parameter enables visual debugging
    - Color-coded room overlays:
        - Green: Square rooms
        - Blue: Rectangular rooms
        - Purple: Atriums
        - Gold: Grand Halls
        - Orange: Hallways
    - `_debug_draw_box()`: Renders 3D wireframe boxes
    - `clear_debug_meshes()`: Cleanup on regeneration

### [ExhibitMood.gd](file:///c:/Users/TeamS/Documents/GitHub/museum-of-all-things-mm/scenes/util/ExhibitMood.gd)

- Add helper methods:
    - `prefers_verticality(mood: int)` - For atrium placement (HISTORY, MEDIA)
    - `prefers_symmetry(mood: int)` - For grand hall placement (HISTORY, SCIENCE)
    - `prefers_complex_shapes(mood: int)` - For future L/T shapes (SCIENCE, ASTRO)

- Extended keyword lists for better mood detection:
    - SCIENCE: Added "game", "mechanics", "system", "theory", "research"
    - HISTORY: Added "heritage", "archaeology"
    - NATURE: Added "environment", "habitat"
    - ASTRO: Added "universe", "cosmic"
    - MEDIA: Added "video game", "gaming", "entertainment", "broadcast"

## Verification Plan

### Automated Tests
- None currently implemented for procedural generation.
- **Recommended**: Add basic validation tests:
    - `test_minimum_rooms_generated()`: Ensure at least `min_rooms` are created
    - `test_all_rooms_reachable()`: Verify connectivity from entry
    - `test_no_overlap()`: Confirm rooms don't intersect

### Manual Verification
1.  **Regeneration**: Use the Debug Console to regenerate exhibits and observe the new variety.
2.  **Traversability**: Ensure all raised/sunken sections are accessible via correctly oriented stairs.
3.  **Collision**: Verify no "bleeding" or overlap between rooms and hallways.
4.  **Aesthetics**: Confirm that mood-based layouts feel appropriate for their Wikipedia categories.
5.  **Special Features**: Look for atriums (tall open spaces) and grand halls (large symmetric rooms).
6.  **Debug Mode**: Enable `debug_mode: true` in generation params to visualize room boundaries.
7.  **Fallback Testing**: Force generation failures by setting extremely small dimension limits.

### Console Logs to Watch For
```
[TiledExhibitGenerator] Created ATRIUM at (x, y, z)
[TiledExhibitGenerator] Created GRAND_HALL at (x, y, z)
[TiledExhibitGenerator] Validation PASSED: 5 rooms generated
[TiledExhibitGenerator] Attempting fallback generation (attempt 1/3)
```
