# Minimap Scroll Wheel Zoom

**Date**: March 14, 2026  
**Status**: ✅ Complete

---

## 🎯 Feature Added

**Scroll wheel zoom** for the minimap when it's visible!

---

## 🎮 How to Use

1. **Open Minimap** - Press `M` (or your bound key)
2. **Scroll Up** - Zoom in (up to 300%)
3. **Scroll Down** - Zoom out (down to 50%)
4. **Close Minimap** - Zoom resets to 100%

---

## ✨ Features

### Zoom Controls:
- **Scroll Wheel Up** - Zoom in (+25% per scroll)
- **Scroll Wheel Down** - Zoom out (-25% per scroll)
- **Min Zoom** - 50% (zoomed out)
- **Max Zoom** - 300% (zoomed in)
- **Default Zoom** - 100%

### Visual Feedback:
- **Zoom Indicator** - Shows current zoom percentage (if label exists)
- **Smooth Scaling** - Instant response to scroll input
- **Auto-Reset** - Zoom resets when minimap closes

---

## 📁 Files Modified

| File | Changes |
|------|---------|
| `scenes/ui/MinimapHUD.gd` | Added zoom functionality |

**New Variables:**
- `_zoom_level: float` - Current zoom level (0.5 - 3.0)
- `_min_zoom: float` - Minimum zoom (0.5 = 50%)
- `_max_zoom: float` - Maximum zoom (3.0 = 300%)
- `_zoom_step: float` - Zoom increment (0.25 = 25%)
- `zoom_label: Label` - Optional zoom indicator

**New Functions:**
- `_input(event)` - Handles scroll wheel input
- `_zoom_in()` - Zoom in by step
- `_zoom_out()` - Zoom out by step
- `_apply_zoom()` - Apply zoom to texture
- `reset_zoom()` - Reset to 100%

**Modified Functions:**
- `_ready()` - Initializes zoom
- `_apply_zoom()` - Updates zoom label

---

## 🔧 Configuration

### Adjust Zoom Settings:

In `MinimapHUD.gd`:

```gdscript
var _zoom_level: float = 1.0      # Starting zoom
var _min_zoom: float = 0.5        # Minimum (50%)
var _max_zoom: float = 3.0        # Maximum (300%)
var _zoom_step: float = 0.25      # Step size (25%)
```

### Examples:

**More zoom range:**
```gdscript
var _min_zoom: float = 0.25       # 25% (more zoomed out)
var _max_zoom: float = 5.0        # 500% (more zoomed in)
```

**Finer zoom control:**
```gdscript
var _zoom_step: float = 0.1       # 10% per scroll
```

**Slower zoom:**
```gdscript
var _zoom_step: float = 0.5       # 50% per scroll
```

---

## 🎨 Optional: Add Zoom Indicator Label

To show the current zoom percentage:

### In MinimapHUD.tscn:

Add a Label node as a child of Panel:

```gdscript
[node name="ZoomIndicator" type="Label" parent="Panel"]
offset_left = 10.0
offset_top = 10.0
offset_right = 100.0
offset_bottom = 30.0
text = "Zoom: 100%"
theme_override_colors/font_color = Color(1, 1, 1, 0.8)
theme_override_font_sizes/font_size = 14
```

The script will automatically find and update this label!

---

## 🧪 Testing

1. **Run the game**
2. **Press M** to open minimap
3. **Scroll mouse wheel**:
   - Up → Map should grow (zoom in)
   - Down → Map should shrink (zoom out)
4. **Check zoom limits**:
   - Can't zoom out past 50%
   - Can't zoom in past 300%
5. **Close minimap** → Zoom should reset

---

## 💡 Technical Details

### Input Handling:
```gdscript
func _input(event: InputEvent) -> void:
    if not visible:
        return
    
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _zoom_in()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _zoom_out()
```

### Zoom Application:
```gdscript
func _apply_zoom() -> void:
    texture_rect.scale = Vector2(_zoom_level, _zoom_level)
    # Updates label if it exists
    if zoom_label:
        zoom_label.text = "Zoom: %d%%" % int(_zoom_level * 100)
```

### Zoom Clamping:
```gdscript
func _zoom_in() -> void:
    _zoom_level = min(_zoom_level + _zoom_step, _max_zoom)
    _apply_zoom()

func _zoom_out() -> void:
    _zoom_level = max(_zoom_level - _zoom_step, _min_zoom)
    _apply_zoom()
```

---

## 🎯 Benefits

1. **Better Navigation** - Zoom in to see details
2. **Better Overview** - Zoom out to see full layout
3. **Intuitive Controls** - Standard scroll-to-zoom behavior
4. **Visual Feedback** - See exact zoom percentage
5. **Auto-Reset** - No stuck zoom levels

---

## 📊 Zoom Levels

| Zoom Level | Percentage | Use Case |
|------------|------------|----------|
| **0.5x** | 50% | Full overview, see entire map |
| **0.75x** | 75% | Wide view |
| **1.0x** | 100% | Default view |
| **1.5x** | 150% | Closer look |
| **2.0x** | 200% | Detail view |
| **2.5x** | 250% | High detail |
| **3.0x** | 300% | Maximum zoom |

---

## 🔮 Future Enhancements (Optional)

1. **Zoom Persistence** - Remember zoom level between opens
2. **Zoom Buttons** - UI buttons for +/- zoom
3. **Keyboard Shortcuts** - +/- keys for zoom
4. **Zoom Animation** - Smooth zoom transitions
5. **Minimap Pan** - Drag to move when zoomed in

---

**The minimap now has intuitive scroll wheel zoom!** 🎮🔍
