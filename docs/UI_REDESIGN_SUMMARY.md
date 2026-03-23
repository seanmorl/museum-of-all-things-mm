# UI System Redesign Summary

## Overview
Redesigned the Museum of All Things (MoAT) UI system for consistency across all menu and HUD components by introducing a centralized styling system.

## Files Created

### `scenes/util/UIStyle.gd`
A new centralized utility class providing:
- **Design Tokens**: Standardized constants for corner radius, margins, spacing, and animation timings
- **Style Creation Helpers**: Functions to create consistent button, panel, card, input, and tab styles
- **Animation Helpers**: Reusable functions for fade, slide, and scale animations with consistent easing
- **Color Helpers**: Centralized color palette access (accent, gold, Wikipedia blue)

**Key Constants:**
```gdscript
CORNER_RADIUS_PANEL = 12.0    # Panels, modals, cards
CORNER_RADIUS_BUTTON = 6.0    # Buttons, controls
CORNER_RADIUS_SMALL = 4.0     # Chips, tags

MARGIN_STANDARD = 16.0        # Standard padding
MARGIN_LARGE = 24.0           # Large modal padding
BUTTON_PADDING = 10.0         # Button internal padding

SPACING_TIGHT = 4.0           # Related elements
SPACING_STANDARD = 8.0        # Normal spacing
SPACING_LOOSE = 14.0          # Section spacing

FADE_DURATION = 0.35          # Standard fade
FADE_QUICK = 0.18             # Quick fade (toasts, exits)
SLIDE_DURATION = 0.40         # Slide animations
ENTRANCE_DURATION = 0.45      # Modal entrances
EXIT_DURATION = 0.16          # Quick exits

HOVER_DURATION = 0.15         # Button hover enter
HOVER_RETURN_DURATION = 0.18  # Button hover exit
STAGGER_DELAY = 0.04          # Sequential element delay
```

## Files Modified

### `scenes/menu/MainMenu.gd`
**Changes:**
- Replaced inline button styling with `UIStyle.create_button_states()`
- Updated panel styling to use `UIStyle.create_panel_style()`
- Standardized hover animations using `UIStyle.animate_hover_enter()` and `UIStyle.animate_hover_exit()`
- Updated animation timings to use `UIStyle` constants
- Fixed spacing constants to use `UIStyle.SPACING_*` values
- Improved signal connection patterns (named functions instead of lambdas)

**Before:**
```gdscript
var sn := StyleBoxFlat.new()
sn.bg_color = Color(0, 0, 0, 0)
sn.content_margin_left = 14; sn.content_margin_right = 14
# ... 20+ lines of manual style creation
```

**After:**
```gdscript
var states := UIStyle.create_button_states(dark, primary, true)
btn.add_theme_stylebox_override("normal", states.normal)
btn.add_theme_stylebox_override("hover", states.hover)
# ... consistent, maintainable
```

### `scenes/menu/PauseMenu.gd`
**Changes:**
- Replaced inline `_style_button()` with `UIStyle.create_button_states()`
- Updated panel styling to use `UIStyle.create_panel_style()`
- Standardized quit confirmation dialog styling
- Updated animation timings to use `UIStyle` constants
- Unified transition types and easing functions

**Before:**
```gdscript
_panel_style.bg_color = ThemeManager.bg_color
_panel_style.border_color = ThemeManager.border_color
for side in [0, 1, 2, 3]:
    _panel_style.set("border_width_" + ["left", "right", "top", "bottom"][side], 1)
# ... 10+ lines of manual property setting
```

**After:**
```gdscript
_panel_style = UIStyle.create_panel_style(
    ThemeManager.bg_color,
    ThemeManager.border_color,
    dark,
    UIStyle.CORNER_RADIUS_PANEL,
    UIStyle.PANEL_PADDING
)
```

### `scenes/menu/Settings.gd`
**Changes:**
- Updated panel styling to use `UIStyle.create_panel_style()`
- Replaced tab bar styling with `UIStyle.create_tab_style()`
- Updated button styling to use `UIStyle.create_button_style()`
- Updated input field styling to use `UIStyle.create_input_style()`
- Standardized divider styling with `UIStyle.create_divider_style()`
- Updated animation timings to use `UIStyle` constants

**Before:**
```gdscript
var bg := StyleBoxFlat.new()
bg.bg_color = ThemeManager.bg_color
bg.border_color = ThemeManager.border_color
bg.border_width_bottom = 1
for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
    bg.set("corner_radius_" + corner, 8)
# ... 15+ lines
```

**After:**
```gdscript
var bg := UIStyle.create_panel_style(
    ThemeManager.bg_color,
    ThemeManager.border_color,
    dark,
    UIStyle.CORNER_RADIUS_PANEL,
    UIStyle.PANEL_PADDING
)
```

## Design Consistency Achieved

### 1. Corner Radius
- **Panels/Modals**: 12px (was 8-14px inconsistent)
- **Buttons**: 6px (was 2-8px inconsistent)
- **Small elements**: 4px

### 2. Spacing
- **Tight**: 4px (related elements)
- **Standard**: 8px (normal spacing)
- **Loose**: 14px (section spacing)
- **Margins**: 16px standard, 24px large

### 3. Animation Timing
- **Fade In**: 0.35s (was 0.30-0.45s inconsistent)
- **Fade Out**: 0.18s (was 0.16-0.20s inconsistent)
- **Slide**: 0.40s (was 0.30-0.50s inconsistent)
- **Hover**: 0.15s enter, 0.18s exit (was 0.15-0.18s)
- **Stagger**: 0.04s between elements

### 4. Color Palette
All components now use centralized color helpers:
- **Accent**: `Color(0.30, 0.55, 1.00)` dark / `Color(0.15, 0.35, 0.85)` light
- **Gold**: `Color(1.00, 0.82, 0.25)` dark / `Color(0.85, 0.62, 0.05)` light
- **Border/Text**: From `ThemeManager` (unchanged)

## Benefits

### 1. Maintainability
- Single source of truth for all design tokens
- Change a color/spacing/timing once, applies everywhere
- Easier to onboard new developers

### 2. Consistency
- All UI elements now share the same visual language
- Animation timings feel cohesive
- Spacing follows a clear hierarchy

### 3. Extensibility
- New components can easily adopt the design system
- Helper functions reduce boilerplate code
- Well-documented design tokens

### 4. Performance
- Reduced code duplication
- Shared style objects where possible
- Cleaner signal connections

## Usage Examples

### Creating a Button
```gdscript
var btn := Button.new()
var dark := ThemeManager.is_dark_mode
var states := UIStyle.create_button_states(dark, false, true)  # flat=true
btn.add_theme_stylebox_override("normal", states.normal)
btn.add_theme_stylebox_override("hover", states.hover)
btn.add_theme_stylebox_override("pressed", states.pressed)
```

### Creating a Panel
```gdscript
var panel := PanelContainer.new()
var style := UIStyle.create_panel_style(
    ThemeManager.bg_color,
    ThemeManager.border_color,
    ThemeManager.is_dark_mode
)
panel.add_theme_stylebox_override("panel", style)
```

### Animating In
```gdscript
UIStyle.animate_slide_in(my_control, Vector2(0, 10))
# or for modals:
UIStyle.animate_scale_in(my_modal)
```

### Animating Out
```gdscript
UIStyle.animate_slide_out(my_control, Vector2(0, 10), 0.16, close_callback)
```

## Future Improvements

1. **Migrate remaining components**: VictoryScreen, ChatHUD, LoadingScreen can also adopt UIStyle
2. **Add more helpers**: Tooltip styles, dropdown styles, etc.
3. **Theme variants**: Support for additional themes beyond light/dark
4. **Animation presets**: Pre-configured animation sequences for common patterns
5. **Documentation**: Generate visual style guide from UIStyle constants

## Notes

- All changes are backward compatible
- Existing functionality preserved
- No breaking changes to signal interfaces
- Pre-existing error in `Hall.gd:48` unrelated to these changes (ThemeManager autoload timing issue)
