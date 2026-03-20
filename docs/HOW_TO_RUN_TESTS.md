# How to Run Automated Tests

## Quick Fix Applied ✅

Fixed error: `draw_pixel()` → `draw_circle(pt, 1.0, color)`

---

## Method 1: Run Event Tests (Easiest)

### In Godot Editor:

1. **Open the test scene:**
   - In FileSystem dock, navigate to: `scenes/test/`
   - Double-click `EventTests.tscn` (or create new scene with EventTests.gd as root)

2. **Run the scene:**
   - Press **F6** (Run Current Scene)
   - Or click the "Play Scene" button (triangle with sun icon)

3. **Watch output:**
   - Tests will run automatically
   - Results appear in the Output panel (bottom of editor)
   - Look for ✅ PASS or ❌ FAIL

### Expected Output:
```
╔═══════════════════════════════════════════════════════════╗
║        ENVIRONMENTAL EVENTS - COMPREHENSIVE TESTS        ║
╚═══════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────┐
│ TEST: All event classes exist and load                     │
└─────────────────────────────────────────────────────────────┘
  ✅ PASS: Event class exists: SpeedUpEvent
  ✅ PASS: Event class exists: HeavyGravityEvent
  ...
```

---

## Method 2: Run Generation Tests

### In Godot Editor:

1. **Open the test scene:**
   - Navigate to: `scenes/test/`
   - Double-click `GenerationTestScene.tscn`

2. **Run the scene:**
   - Press **F6**

3. **Watch output:**
   - Automated generation tests run
   - Results show in Output panel

### Manual Testing Controls:
- Press **1-5** to test specific mood configurations
- Press **R** to regenerate all tests
- Debug mode shows colored room boundaries

---

## Method 3: Run Full Test Suite

### Create a Test Runner Scene:

1. **Create new scene:**
   - Scene → New Scene
   - Choose "Other Node" → Node (not Node3D)
   - Name it "TestRunner"

2. **Attach the script:**
   - Right-click TestRunner node → "Attach Script"
   - Or load existing: `scenes/test/TestRunner.gd`

3. **Run:**
   - Press F6

### Or from Command Line:

```bash
# Navigate to your project directory
cd "C:\Users\TeamS\Documents\GitHub\museum-of-all-things-mm"

# Run tests (adjust path to your Godot executable)
"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\Godot_v4.x.exe" --headless --script scenes/test/TestRunner.gd
```

---

## Method 4: Test In-Game (Manual)

### Test Minimap Event Icons:

1. **Start the game:**
   - Run the main scene (F5)
   - Or export and run the game

2. **Start a race:**
   - Host a multiplayer game
   - Start a race

3. **Open debug console:**
   - Press **`~`** (tilde) or **F12**

4. **Trigger events:**
   ```
   event darkness
   event speed_up
   event earthquake
   ```

5. **Open minimap:**
   - Press **M** (or whatever key opens minimap)

6. **Look for icons:**
   - Should see colored symbols orbiting the minimap
   - 🌙 for Darkness
   - ↗️ for Speed Up
   - 〰️ for Earthquake

---

## Troubleshooting

### "Function 'draw_pixel()' not found"

**Fixed!** Changed to `draw_circle(pt, 1.0, color)`

If you still see this error:
1. Close and reopen Godot
2. Or restart the scene

---

### "EventManager not loaded"

**Cause:** Autoloads not ready when tests start

**Solution:** Tests already have `await get_tree().create_timer(0.5).timeout` to wait

If still failing:
1. Make sure EventManager is registered as autoload
2. Check: Project → Project Settings → Autoload
3. Verify `EventManager` is in the list

---

### "EventWarningBanner not loaded"

**Cause:** Same as above - autoload timing

**Solution:** Already handled in tests with delay

---

### Tests fail with "null" errors

**Cause:** Nodes not found

**Solutions:**
1. Run from proper scene context
2. Ensure autoloads are registered
3. Check Output panel for specific errors

---

## Test Output Locations

### Godot Editor:
- **Output Panel:** Bottom dock (or Ctrl+Shift+D)
- **Debugger Panel:** Shows errors/warnings

### Command Line:
- stdout/stderr (printed directly)

---

## What Each Test Does

### EventTests.gd (8 tests, ~5 seconds)

| Test | What It Checks |
|------|----------------|
| `test_all_events_exist` | All 19 event scripts load |
| `test_all_events_have_required_methods` | Each has apply/end/get_duration/get_display_name |
| `test_event_durations_defined` | EVENT_DURATIONS constant has all events |
| `test_event_names_defined` | EVENT_NAMES constant populated |
| `test_accessibility_restrictions` | Accessibility mode blocks certain events |
| `test_event_colors` | Minimap has colors for all events |
| `test_warning_banner` | Banner connects to EventManager |
| `test_event_manager_configuration` | Config API works |

---

### GenerationTestScene.gd (5 tests per mood, ~15 seconds)

| Test | What It Checks |
|------|----------------|
| `test_minimum_rooms` | Generates enough rooms |
| `test_entry_point_exists` | Has entry hall |
| `test_exits_valid` | Exits have destinations |
| `test_no_overlapping_rooms` | Rooms don't intersect |
| `test_item_slots_valid` | Item slots have valid data |

**Test Configurations:**
1. HISTORY - Ancient Rome (3+ rooms)
2. SCIENCE - Quantum Physics (4+ rooms)
3. NATURE - Rainforest (3+ rooms)
4. ASTRO - Deep Space (4+ rooms)
5. MEDIA - Film History (3+ rooms)

---

### TestRunner.gd (27 tests, ~20 seconds)

Combines:
- Environmental Events (12 tests)
- Procedural Generation (10 tests)
- Network Sync (5 tests)

---

## Expected Results

### All Tests Pass:
```
╔═══════════════════════════════════════════════════════════╗
║                    TEST SUMMARY                           ║
╠═══════════════════════════════════════════════════════════╣
║  ✅ Success Rate:                                 100.0%  ║
╠───────────────────────────────────────────────────────────╣
║  Total Tests:    27                                       ║
║  Passed:         27                                       ║
║  Failed:         0                                        ║
╚═══════════════════════════════════════════════════════════╝

  ✅ ALL TESTS PASSED!
```

### Some Tests Fail:
```
  ❌ FAILED TESTS:
    - Event durations defined: Missing durations for: ["SILENCE"]
    - Minimum rooms (3/3): Ancient Rome: Only 2 rooms generated
```

---

## CI/CD Integration

### GitHub Actions Example:

Create `.github/workflows/tests.yml`:

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: barichello/godot-ci:4.2
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Run Tests
        run: |
          godot --headless --script-test-runner scenes/test/TestRunner.gd
```

---

## Tips for Faster Testing

1. **Test individual suites:**
   - Run EventTests.gd for quick feedback (5s)
   - Run GenerationTestScene.gd for generation tests (15s)

2. **Use manual controls:**
   - Press 1-5 to test specific generation configs
   - Don't wait for full suite if testing one feature

3. **Watch Output panel:**
   - Keep it open while developing
   - Errors appear in red

4. **Filter output:**
   - Search for "✅ PASS" or "❌ FAIL"
   - Search for "ERROR" to find issues

---

## Next Steps After Testing

### If Tests Pass:
1. ✅ Test minimap icons in-game
2. ✅ Add more event types if needed
3. ✅ Expand test coverage

### If Tests Fail:
1. Read the failure message
2. Check the specific test function
3. Add debug prints if needed
4. Fix and re-run

---

**Happy Testing!** 🧪✅
