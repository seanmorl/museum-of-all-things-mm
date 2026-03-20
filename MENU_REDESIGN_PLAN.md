# Main Menu Redesign Plan

## Reference Design
Minimalist vertical menu on LEFT side with:
- Simple text menu items (no button backgrounds)
- White selection indicator bar on left of selected item
- Logo/title integrated at top left
- Space/planet background
- "Back" + "ESC" hint in bottom right corner

## Changes Required

### 1. MainMenu.gd
**Complete rewrite of `_build_ui()` to create:**
- Left-aligned vertical menu container (MarginContainer + VBoxContainer)
- Text-based menu items (Labels instead of Buttons)
- Selection indicator (ColorRect bar on left)
- Keyboard navigation (up/down arrows, Enter to select)
- Logo/title at top left
- ESC hint in bottom right

**Menu Items:**
```
[LOGO/TITLE]

Play Game          ← Selection bar here
Multiplayer
Settings
Latest Changes
Host Server
Quit Game

─────────────────────  (separator line)
Select Game Mode
```

### 2. MainMenu.tscn
**Simplify scene structure:**
- Remove old centered PanelContainer layout
- Add left menu container
- Add bottom-right ESC hint
- Keep Background layer

### 3. Visual Style
**Colors:**
- Menu text: White / ThemeManager.text_color
- Selected item: Bright white with left indicator bar
- Separator: Thin line, accent color
- ESC hint: White with green "ESC" key

**Typography:**
- Menu items: Cormorant Garamond or selected accessibility font
- Size: 18-20px for menu items
- Title: 42-48px

**Spacing:**
- Menu item spacing: 12-16px
- Left margin: 60-80px from screen edge
- Top margin: 80-100px for title

### 4. Input Handling
**Keyboard:**
- ↑/↓ arrows: Navigate menu
- Enter: Select item
- ESC: Back / Quit (context dependent)

**Mouse:**
- Click on item: Select
- Hover: Highlight

### 5. Animations
**Entrance:**
- Menu items fade in sequentially (staggered)
- Slide in from left slightly
- Title fades in first

**Selection:**
- Smooth transition of indicator bar
- Text color/brightness change

---

## Implementation Priority

1. ✅ Add fonts to accessibility selector (DONE)
2. ⏳ Create new menu layout structure
3. ⏳ Implement keyboard navigation
4. ⏳ Add selection indicator
5. ⏳ Style to match reference
6. ⏳ Add animations
7. ⏳ Test with different fonts
8. ⏳ Test with dark/light mode

---

## Notes

- Keep existing signal connections (start, settings, start_multiplayer, etc.)
- Keep patch notes popup functionality
- Keep dark mode toggle
- Keep accessibility font support
- Background animation stays the same
- Daily Challenge card stays in bottom left
