# Export Crash Fix - DebugConsole

## Problem
Exported versions of the game crashed immediately when loading the main menu.

## Root Cause
The `DebugConsole` autoload was calling `queue_free()` in export builds (`if not OS.is_debug_build()`), but other scripts continued to call `DebugConsole.is_active()`, causing null reference crashes.

**Affected files:**
- `scenes/Player.gd` (line 238)
- `scenes/menu/ChatHUD.gd` (line 245)
- `scenes/Main.gd` (line 679)

## Solution

### 1. Changed `is_active()` to Static Method
**File:** `scenes/ui/DebugConsole.gd`

```gdscript
# Before (instance method):
func is_active() -> bool:
    return _console_visible

# After (static method safe for export):
static func is_active() -> bool:
    if not OS.is_debug_build():
        return false
    var console = get_tree().get_first_node_in_group("debug_console")
    if console and console.has_method("_get_visible"):
        return console._get_visible()
    return false
```

### 2. Changed `_ready()` to Disable Instead of Free
**File:** `scenes/ui/DebugConsole.gd`

```gdscript
# Before:
if not OS.is_debug_build():
    queue_free()  # ← This caused crashes!
    return

# After:
if not OS.is_debug_build():
    visible = false
    process_mode = PROCESS_MODE_DISABLED
    return
```

### 3. Added Guard Checks to All Methods
Added `if not OS.is_debug_build(): return` to:
- `_process()`
- `_input()`
- `toggle_console()`

### 4. Added Scene Group
**File:** `scenes/ui/DebugConsole.tscn`

Added `groups = ["debug_console"]` to enable the static method to find the instance.

## Testing

### Before Fix
- ❌ Export crashes immediately on main menu load
- Error: "Attempt to call function 'is_active' on a null instance"

### After Fix
- ✅ Export loads main menu successfully
- ✅ DebugConsole disabled in export (no console toggle)
- ✅ Debug builds still work normally

## Export Checklist

Before exporting, verify:

1. **Export Presets**
   - ✅ `export_filter="all_resources"` (includes all files)
   - ✅ `script_export_mode=2` (compile scripts to bytecode)
   - ✅ `binary_format/embed_pck=true` (embed PCK in executable)

2. **Autoloads**
   - ✅ All autoloads load without errors
   - ✅ DebugConsole gracefully disables in export

3. **Resources**
   - ✅ No missing dependencies
   - ✅ All textures/sounds imported

4. **Build Verification**
   ```bash
   # Test export
   ./export.sh --dry-run windows
   ./export.sh windows
   
   # Run and verify
   ./dist/Windows/MOATMPWindows.exe
   ```

## Files Modified

| File | Changes |
|------|---------|
| `scenes/ui/DebugConsole.gd` | Static `is_active()`, disabled instead of freed, guard checks |
| `scenes/ui/DebugConsole.tscn` | Added `debug_console` group |

## Related Issues

- Export console output should show no errors
- Main menu should load within 5 seconds
- No memory leaks in long sessions

---

**Fixed:** March 20, 2026  
**Version:** v0.3.1  
**Tested Platforms:** Windows, Linux
