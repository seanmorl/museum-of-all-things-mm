# Environmental Event Icons - Quick Reference

**For:** GraphMinimap.gd  
**Location:** Bottom-right corner of screen during races

---

## Icon Legend

### Movement Events

| Icon | Name | Effect | Color |
|------|------|--------|-------|
| ↗️ | **Speed Up** | Move 50% faster | Green |
| ⬇️ | **Heavy Gravity** | Move 40% slower | Purple |
| 🚶 | **No Running** | Dash disabled | Orange-red |

### Time Events

| Icon | Name | Effect | Color |
|------|------|--------|-------|
| 🐌 | **Time Dilation** | Timer at 50% speed | Light blue |
| ⏩ | **Double Time** | Timer at 200% speed | Gold |
| ⏰ | **Sudden Death** | Timer counts down | Red |

### Visual Events

| Icon | Name | Effect | Color |
|------|------|--------|-------|
| 🌙 | **Darkness** | Lights dim to 15% | Dark gray |
| 🌫️ | **Fog** | Reduced visibility | Light gray |
| 🌈 | **Color Shift** | Monochrome filter | Varies |
| 🌧️ | **Weather System** | Rain/snow particles | Blue-gray |
| 〰️ | **Earthquake** | Camera shake | Orange-brown |

### Navigation Events

| Icon | Name | Effect | Color |
|------|------|--------|-------|
| 🔒 | **Locked Doors** | All doors locked | Gray |
| 🔀 | **Reversed** | Entry/Exit swapped | Magenta |
| 🧭 | **True Compass** | Points to goal | Cyan |
| ❌ | **False Compass** | Points wrong way | Red |

### Audio Events

| Icon | Name | Effect | Color |
|------|------|--------|-------|
| 🔇 | **Silence** | All audio muted | Muted blue |
| 🔊 | **Audio Surprise** | Random sound plays | White |

### Social Events

| Icon | Name | Effect | Color |
|------|------|--------|-------|
| 👑 | **King of the Hill** | Leader wears crown | Yellow-gold |

### Chaos Events

| Icon | Name | Effect | Color |
|------|------|--------|-------|
| 🎲 | **Roulette** | Random event | White |

### Utility Events

| Icon | Name | Effect | Color |
|------|------|--------|-------|
| ✅ | **All Clear** | Ends all events | Green |

---

## Visual Design

### Icon Structure
```
     ┌─────────────┐
     │  Background │  ← Transparent circle (30% opacity)
     │   ╭─────╮   │
     │  │ Symbol│  │  ← Colored arc border (100% opacity)
     │   ╰─────╯   │
     └─────────────┘
```

### Animation
- Icons orbit the minimap perimeter
- Slow rotation: 0.5 radians/second
- Multiple icons distribute evenly
- Pulse effect on appearance

---

## Implementation Details

### Adding New Event Icons

1. **Add to EventManager.EventType enum**
```gdscript
enum EventType {
    # ... existing events
    YOUR_NEW_EVENT,
}
```

2. **Add duration to EVENT_DURATIONS**
```gdscript
const EVENT_DURATIONS := {
    # ...
    EventType.YOUR_NEW_EVENT: [30.0, 60.0],
}
```

3. **Add name to EVENT_NAMES**
```gdscript
const EVENT_NAMES := {
    # ...
    EventType.YOUR_NEW_EVENT: "Your Event Name",
}
```

4. **Add symbol to GraphMinimap._draw_event_symbol()**
```gdscript
EventType.YOUR_NEW_EVENT:
    # Draw your symbol here
    draw_line(center + Vector2(...), ...)
```

5. **Add color to GraphMinimap._get_event_color()**
```gdscript
EventType.YOUR_NEW_EVENT:
    return Color(0.5, 0.6, 0.7)  # Your color
```

---

## Symbol Design Guidelines

### Do's
✅ Keep it simple (3-6 lines max)  
✅ Use clear geometric shapes  
✅ Make it recognizable at 20px scale  
✅ Ensure contrast with background  
✅ Test in both light and dark mode  

### Don'ts
❌ Don't use text (hard to read at small size)  
❌ Don't use more than 8 line segments  
❌ Don't rely on color alone for meaning  
❌ Don't make symbols too similar  
❌ Don't use diagonal lines at awkward angles  

---

## Color Palette

### Event Type Colors
```gdscript
# Movement
SPEED_UP:       Color(0.2, 0.8, 0.2)  # Green
HEAVY_GRAVITY:  Color(0.6, 0.3, 0.6)  # Purple
NO_RUNNING:     Color(0.9, 0.4, 0.2)  # Orange-red

# Time
TIME_DILATION:  Color(0.2, 0.6, 0.8)  # Light blue
DOUBLE_TIME:    Color(0.8, 0.6, 0.2)  # Gold
SUDDEN_DEATH:   Color(1.0, 0.0, 0.0)  # Red

# Visual
DARKNESS:       Color(0.2, 0.2, 0.3)  # Dark gray
FOG:            Color(0.7, 0.7, 0.8)  # Light gray
EARTHQUAKE:     Color(0.8, 0.5, 0.2)  # Orange-brown
WEATHER:        Color(0.5, 0.6, 0.9)  # Blue-gray

# Navigation
TRUE_COMPASS:   Color(0.2, 0.9, 0.9)  # Cyan
FALSE_COMPASS:  Color(0.9, 0.3, 0.3)  # Red
LOCKED_DOORS:   Color(0.5, 0.5, 0.5)  # Gray
REVERSED:       Color(0.9, 0.5, 0.9)  # Magenta

# Audio
SILENCE:        Color(0.6, 0.6, 0.7)  # Muted blue
AUDIO_SURPRISE: Color(0.9, 0.9, 0.9)  # White

# Social
KING_OF_HILL:   Color(1.0, 0.8, 0.0)  # Yellow-gold

# Chaos
ROULETTE:       Color(0.9, 0.9, 0.9)  # White
```

---

## Testing Your Icons

### Visual Test Checklist

1. **Open game**
2. **Start a race**
3. **Open console** (`~` or `F12`)
4. **Trigger events:**
   ```
   event speed_up
   event darkness
   event earthquake
   ```
5. **Open minimap** (default: M key)
6. **Verify:**
   - [ ] Icons are visible
   - [ ] Icons orbit smoothly
   - [ ] Symbols are recognizable
   - [ ] Colors are distinct
   - [ ] No performance drop

### Screenshot Comparison

Take screenshots of each event icon for documentation:
```
Event: Speed Up
Icon: ↗️ Green arrow
Location: Bottom-right minimap
```

---

## Accessibility Notes

### Color Blindness

The icon system is designed to be colorblind-friendly:
- **Symbols are distinct** - Not relying on color alone
- **High contrast** - Works in both light/dark mode
- **Shape variety** - Arrows, circles, waves, zigzags

### Motion Sensitivity

- **Slow orbit** - 0.5 rad/s is gentle
- **No flashing** - Smooth transitions only
- **Can be disabled** - Turn off events in accessibility mode

---

## Performance

### Rendering Cost
- **Per-icon:** ~10 draw calls
- **Max concurrent:** 1-3 events
- **Total cost:** ~30 draw calls (negligible)
- **FPS impact:** <1%

### Memory
- **No textures** - All procedural drawing
- **State:** One Dictionary entry per active event
- **Total:** <1KB

---

## Troubleshooting

### Icons Not Showing?

1. Check EventManager is loaded
2. Verify event is actually active
3. Check console for errors
4. Ensure minimap is visible

### Icons Wrong Color?

1. Check `_get_event_color()` implementation
2. Verify event type enum matches
3. Test in both light/dark modes

### Icons Not Orbiting?

1. Check `_time` variable is incrementing
2. Verify `_process()` is being called
3. Ensure `queue_redraw()` is called on event change

---

**Quick Reference Card v1.0**  
Last updated: March 18, 2026
