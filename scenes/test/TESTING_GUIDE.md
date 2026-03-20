# Testing the Exhibit Generator Changes

## Quick Test Method (Recommended)

### Step 1: Enable Debug Mode (Optional)

Edit `scenes/museum/ExhibitLoader.gd` around line 196-206:

```gdscript
new_exhibit.generate({
    "start_pos": Vector3.UP * exhibit_height,
    "min_room_dimension": _min_room_dimension,
    "max_room_dimension": _max_room_dimension,
    "title": context.title,
    "prev_title": prev_title,
    "no_props": items.size() < 10,
    "hall_type": hall_type,
    "exit_limit": doors.size(),
    "mood": mood,
    "min_rooms": 3,           # ADD THIS
    "debug_mode": true,       # ADD THIS - shows visual indicators (optional)
})
```

### Step 2: Run the Main Game

1. Open Godot editor
2. Press F5 to run the game
3. Navigate to any exhibit (click a door)

### Step 3: Watch for In-Game Notifications! 🎉

**Top-Left Corner Toast Notifications:**

When you enter an exhibit, you'll see:

1. **Generation Start** (purple toast):
   ```
   🏛️ Ancient Rome
   Generating exhibit...
   ```

2. **Special Rooms Created** (colored toasts):
   - 🟪 **Atrium created** (purple border)
     ```
     🏛️ Atrium created
     3-level vertical space
     ```
   
   - 🟨 **Grand Hall created** (gold border)
     ```
     🏛️ Grand Hall created
     6×5 symmetric hall
     ```

3. **Fallback Messages** (orange border, if generation struggles):
   ```
   🔄 Regenerating...
   Relaxing constraints (attempt 1)
   ```

4. **Final Summary** (green border):
   ```
   🏛️ Ancient Rome
   Generated 5 rooms • 🏛️ Atrium, 🏛️ Grand Hall
   ```

### Step 4: Revert After Testing

Remember to remove or set `debug_mode: false` after testing!

---

## Alternative: Test Scene

Run the dedicated test scene:

1. In Godot editor, open `scenes/test/ExhibitTestScene.tscn`
2. Press F6 to run current scene
3. Press keys 1-5 to test different configurations

**Controls:**
- **1**: HISTORY mood (Grand Halls + Atriums likely)
- **2**: SCIENCE mood (Grand Halls likely)
- **3**: NATURE mood (Pools + Planters)
- **4**: ASTRO mood (Complex layouts)
- **5**: MEDIA mood (Atriums likely)
- **R**: Regenerate current config
- **C**: Clear and regenerate

---

## What Makes Atriums & Grand Halls Spawn?

### Atriums (Purple)
- **Mood requirement**: HISTORY or MEDIA
- **Chance**: 15% when adding a room (if mood matches)
- **Room count requirement**: At least 2 rooms exist
- **Visual**: 3-level tall open space, look up!

### Grand Halls (Gold)
- **Mood requirement**: HISTORY or SCIENCE  
- **Chance**: 15% when adding a room (if mood matches)
- **Size**: 5-7 tiles wide, 4-6 tiles long
- **Visual**: Multiple exits, symmetrical layout

---

## Troubleshooting

**Not seeing special rooms?**
- Check console for "Created ATRIUM/GRAND_HALL" messages
- Try HISTORY or MEDIA mood (highest chance)
- Regenerate multiple times (only 15% chance per room)

**Debug overlay not showing?**
- Make sure `debug_mode: true` in generate params
- Check console for any errors

**Validation failing?**
- Check logs for "Fallback generation" messages
- May need to lower `min_rooms` or adjust dimension constraints
