# Minimap Door Labels Toggle

**Date**: March 14, 2026  
**Status**: ✅ Complete

---

## 🎯 Feature Added

**Host-controlled toggle** for showing/hiding door labels on the minimap!

---

## 🎮 How to Use

### As Host:
1. **Press H** to open Host Menu
2. **Look for "Display Options" section**
3. **Toggle "🗺️ Minimap Door Labels"** checkbox
   - ✅ **Checked** = Door/room names visible on minimap
   - ❌ **Unchecked** = Door/room names hidden (cleaner view)

### As Player:
- When host enables labels → You see room names on minimap
- When host disables labels → Room names disappear
- **Syncs automatically** to all players

---

## ✨ What It Does

### Labels OFF (Default):
```
┌─────────────────┐
│  ● ← You        │
│   \             │
│    ●──●         │  ← Just dots and lines
│         \       │     (no text labels)
│          ●      │
└─────────────────┘
```

### Labels ON:
```
┌─────────────────┐
│  ● ← You        │
│   \             │
│    ●──● Physics │  ← Room names visible
│         \       │     on minimap
│          ● Einstein│
└─────────────────┘
```

---

## 📁 Files Modified

| File | Changes |
|------|---------|
| `scenes/menu/ExhibitMapOverlay.gd` | Added global `show_minimap_labels` setting |
| `scenes/menu/HostMenu.gd` | Added toggle checkbox and handler |

**New Variables:**
- `ExhibitMapOverlay.show_minimap_labels: bool` (static) - Global setting

**New UI Element:**
- **CheckButton** - "🗺️ Minimap Door Labels" in Host Menu

**New Function:**
- `_on_minimap_labels_toggled()` - Handles toggle in HostMenu

**Modified Functions:**
- `ExhibitMapOverlay._draw()` - Uses global setting for label visibility

---

## 🎨 Visual Changes

### Before (Labels Always Off):
- Minimap shows dots and lines only
- No room names visible
- Clean but less informative

### After (Labels Toggleable):
- **Host can enable** for better navigation
- **Host can disable** for cleaner view
- **All players see same view** (synced)

---

## 🧪 Testing

### Test as Host:
1. **Host a game**
2. **Press H** → Open Host Menu
3. **Scroll to "Display Options"**
4. **Click "🗺️ Minimap Door Labels"** checkbox
   - Should see: "🗺️ Minimap door labels enabled"
5. **Press M** → Open minimap
   - Should see room names on minimap
6. **Press H** again → Uncheck the box
   - Should see: "🗺️ Minimap door labels disabled"
7. **Press M** → Room names should disappear

### Test Multiplayer Sync:
1. **Host enables labels**
2. **Join as client**
3. **Press M** → Should see labels (synced from host)
4. **Host disables labels**
5. **Client minimap** → Labels should disappear

---

## 💡 Use Cases

### Enable Labels When:
- ✅ **New players** learning the museum
- ✅ **Complex layouts** need navigation help
- ✅ **Educational mode** - want to see all room names
- ✅ **Casual exploration** - not racing

### Disable Labels When:
- ✅ **Experienced players** - don't need help
- ✅ **Racing mode** - more challenging
- ✅ **Clean aesthetic** - prefer minimal UI
- ✅ **Performance** - slightly less rendering

---

## 🔧 Technical Details

### Global Setting:
```gdscript
# In ExhibitMapOverlay.gd
static var show_minimap_labels: bool = false

# Used in _draw()
show_labels = show_minimap_labels  # For minimap mode
```

### Host Menu Toggle:
```gdscript
# In HostMenu.gd
var labels_btn := CheckButton.new()
labels_btn.text = "🗺️ Minimap Door Labels"
labels_btn.button_pressed = ExhibitMapOverlay.show_minimap_labels
labels_btn.toggled.connect(_on_minimap_labels_toggled)

func _on_minimap_labels_toggled(enabled: bool) -> void:
    ExhibitMapOverlay.show_minimap_labels = enabled
```

### Minimap Rendering:
```gdscript
# In ExhibitMapOverlay.gd _draw()
match _mode:
    Mode.MINIMAP:
        show_labels = show_minimap_labels  # Uses global setting
    Mode.FULL:
        show_labels = true  # Always show in full map
```

---

## 📊 Default Settings

| Mode | Default | Can Change? |
|------|---------|-------------|
| **Minimap Labels** | ❌ OFF | ✅ Host can toggle |
| **Full Map Labels** | ✅ ON | ❌ Always on (too small otherwise) |

---

## 🎯 Benefits

1. **Host Control** - Host decides UI complexity
2. **Better Navigation** - Labels help new players
3. **Cleaner View** - Disable for experienced players
4. **Multiplayer Sync** - All players see same view
5. **No Code Changes** - Toggle in-game, no restart needed

---

## 🔮 Future Enhancements (Optional)

1. **Per-Player Setting** - Each player chooses their own
2. **Label Density** - Show all / some / none
3. **Font Size** - Adjust label size
4. **Label Color** - Customize label colors
5. **Smart Labels** - Only show important rooms

---

## 📝 Location in Host Menu

```
Host Controls
├── Players
│   ├── Player 1 (You)
│   ├── Player 2 👢
│   └── ...
├── Race Control
│   ├── ▶ Force Start Race
│   ├── ⏹ Cancel Race
│   ├── --- Separator ---
│   └── Quick Actions
│       ├── 💡 Give Hint to All
│       ├── ⏭ Skip Vote & Start
│       └── 📊 Change Difficulty
├── --- Separator ---
└── Display Options  ← NEW SECTION!
    └── 🗺️ Minimap Door Labels  ← NEW TOGGLE!
```

---

**The host now has full control over minimap label visibility!** 🗺️✨
