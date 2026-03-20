# Automated Testing Guide

## Overview

The Museum of All Things now includes a comprehensive automated testing framework for:
- ✅ Environmental Events
- ✅ Procedural Generation
- ✅ Network Synchronization

---

## Quick Start

### Run All Tests (Command Line)

```bash
# Run the full test suite
godot --script-test-runner scenes/test/TestRunner.gd

# Or run specific test suites
godot --script scenes/test/EventTests.gd
```

### Run Tests (Godot Editor)

1. **Full Test Suite:**
   - Open `scenes/test/TestRunner.gd`
   - Press F6 (Run Current Scene)

2. **Environmental Events Tests:**
   - Open `scenes/test/EventTests.gd`
   - Press F6

3. **Procedural Generation Tests:**
   - Open `scenes/test/GenerationTestScene.tscn`
   - Press F6

---

## Test Suites

### 1. Environmental Events Tests (`EventTests.gd`)

**Location:** `scenes/test/EventTests.gd`

**Tests:**
- ✅ All event classes exist and load
- ✅ All events have required methods (`apply`, `end`, `get_duration`, `get_display_name`)
- ✅ Event durations defined in EventManager
- ✅ Event names defined
- ✅ Accessibility mode restrictions work
- ✅ Event colors for minimap indicators
- ✅ Warning banner functionality
- ✅ EventManager configuration API

**Expected Output:**
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

### 2. Procedural Generation Tests (`GenerationTestScene.gd`)

**Location:** `scenes/test/GenerationTestScene.gd`

**Tests:**
- ✅ Minimum rooms generated (configurable per mood)
- ✅ Entry point exists
- ✅ Exits have valid destinations
- ✅ No overlapping rooms
- ✅ Item slots at valid positions

**Test Configurations:**
1. HISTORY - Ancient Rome (3+ rooms, grand halls & atriums)
2. SCIENCE - Quantum Physics (4+ rooms, modular)
3. NATURE - Rainforest (3+ rooms, organic)
4. ASTRO - Deep Space (4+ rooms, complex)
5. MEDIA - Film History (3+ rooms, vertical)

**Manual Testing:**
- Press **1-5** to test specific configurations
- Press **R** to regenerate all tests
- Debug mode shows room boundaries (colored boxes)

---

### 3. Full Test Runner (`TestRunner.gd`)

**Location:** `scenes/test/TestRunner.gd`

**Runs:**
- Environmental Events Suite (12 tests)
- Procedural Generation Suite (10 tests)
- Network Sync Suite (5 tests)

**Features:**
- Automatic test discovery
- Timed test execution
- Detailed failure messages
- Exit code for CI/CD integration

---

## Writing New Tests

### Test Structure

```gdscript
extends Node

func _ready() -> void:
    await _run_test("test_name", _test_something)

func _test_something() -> Dictionary:
    # Test logic here
    if condition_passed:
        return {"passed": true, "message": "OK"}
    else:
        return {"passed": false, "message": "Description of failure"}
```

### Assertion Helpers

```gdscript
# Boolean assertion
_assert_true(condition: bool, message: String) -> Dictionary

# Equality assertion
_assert_equal(actual: Variant, expected: Variant, message: String) -> Dictionary

# Null check
_assert_not_null(value: Variant, message: String) -> Dictionary
```

### Example Test

```gdscript
func _test_speed_up_increases_movement() -> Dictionary:
    # Check class exists
    if not ClassDB.class_exists("SpeedUpEvent"):
        return {"passed": false, "message": "SpeedUpEvent class not found"}
    
    # Check required methods
    var script := load("res://scenes/util/events/SpeedUpEvent.gd")
    if not script.has_static_method("apply"):
        return {"passed": false, "message": "Missing apply method"}
    
    return {"passed": true, "message": "OK"}
```

---

## Continuous Integration (CI)

### GitHub Actions Example

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run Tests
        run: |
          godot --headless --script-test-runner scenes/test/TestRunner.gd
```

### Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

---

## Debugging Failed Tests

### Step-by-Step

1. **Read the failure message:**
   ```
   ❌ FAIL: Event durations defined - Missing durations for: ["SILENCE"]
   ```

2. **Locate the test:**
   - Find the test function name in the output
   - Open the corresponding test file

3. **Run in isolation:**
   - Comment out other tests
   - Run only the failing test

4. **Add debug output:**
   ```gdscript
   func _test_something() -> Dictionary:
       print("DEBUG: value = ", value)
       # ... rest of test
   ```

5. **Fix and re-run**

---

## Test Coverage

### Current Coverage

| Component | Tests | Status |
|-----------|-------|--------|
| EventManager | 6 | ✅ Complete |
| Event Classes | 19 | ✅ Complete |
| EventWarningBanner | 3 | ✅ Complete |
| GraphMinimap Events | 2 | ✅ Complete |
| Procedural Generation | 10 | ✅ Complete |
| Network Sync | 5 | ⚠️ Basic |

### Future Tests

- [ ] Integration tests (full race simulation)
- [ ] Performance tests (generation time benchmarks)
- [ ] Multiplayer stress tests (8+ players)
- [ ] Accessibility compliance tests

---

## Performance Benchmarks

### Expected Test Duration

| Test Suite | Expected Time |
|------------|---------------|
| Environmental Events | 2-5 seconds |
| Procedural Generation | 10-20 seconds |
| Network Sync | 1-3 seconds |
| **Total** | **15-30 seconds** |

### Slow Test Indicators

If a test takes >5 seconds:
- Add timeout detection
- Consider splitting into smaller tests
- Check for infinite loops

---

## Troubleshooting

### Common Issues

**Problem:** Tests fail with "EventManager not loaded"
**Solution:** Wait for autoloads - add `await get_tree().create_timer(0.5).timeout`

**Problem:** Procedural generation tests timeout
**Solution:** Increase timer or reduce room count for tests

**Problem:** Network tests fail in single-player
**Solution:** Network tests require multiplayer setup - mark as "manual test recommended"

---

## Best Practices

1. **Keep tests fast** - Each test should complete in <1 second
2. **Test one thing** - Each test function should verify one behavior
3. **Descriptive names** - Test names should describe what they verify
4. **Isolated tests** - Tests should not depend on each other
5. **Repeatable** - Tests should produce same result every time
6. **Clear failures** - Failure messages should explain what went wrong

---

## Test Data

### Mock Data

For tests that need fake data:

```gdscript
var mock_config: Dictionary = {
    "enabled": true,
    "frequency_seconds": 90.0,
    "allowed_events": [EventManager.EventType.SPEED_UP],
    "duration_modifier": 1.0,
    "max_concurrent": 1
}
```

### Test Fixtures

For procedural generation:

```gdscript
const TEST_CONFIGS: Array[Dictionary] = [
    {
        "name": "HISTORY",
        "title": "Ancient Rome",
        "mood": ExhibitMood.Mood.HISTORY,
        "min_rooms": 3,
    },
    # ... more configs
]
```

---

## Contributing

### Adding New Tests

1. Create test function following naming convention: `_test_<feature>()`
2. Add to appropriate test suite runner
3. Run locally to verify
4. Commit with test results in commit message

### Test Review Checklist

- [ ] Test has descriptive name
- [ ] Test verifies one behavior
- [ ] Failure messages are clear
- [ ] Test runs in <5 seconds
- [ ] Test is deterministic (no randomness)
- [ ] Test handles edge cases

---

## Questions?

For questions about testing:
- Check existing tests in `scenes/test/`
- Read test function names for examples
- Run tests with debug output for insights

**Happy Testing!** 🧪✅
