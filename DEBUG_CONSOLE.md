# Debug Console - Development Tool

## Overview
An in-game developer console for testing and debugging. **Only active in debug builds** - automatically disabled when the project is exported for release.

## How to Open
Press **`~`** (tilde) or **`F12`** during gameplay to toggle the console.

## Features
- **Command history** - Use ↑/↓ arrows to cycle through previous commands
- **Syntax highlighting** - Commands, output, and errors are color-coded
- **GDScript evaluation** - Type expressions and see results
- **Autoload access** - Direct access to EventManager, RaceManager, etc.

## Available Commands

### General
| Command | Description |
|---------|-------------|
| `help` | Show all available commands |
| `clear` / `cls` | Clear console output |
| `toggle` | Toggle console visibility |
| `exit` / `quit` | Close console |

### Event Testing
| Command | Description |
|---------|-------------|
| `banner` | Test the event warning banner |
| `events` | List all available environmental events |
| `event <name>` | Trigger a specific event |

**Event names:**
- `darkness`, `color_shift`, `fog`, `earthquake`, `weather_system`
- `speed_up`, `heavy_gravity`, `no_running`
- `time_dilation`, `double_time`
- `true_compass`, `false_compass`
- `audio_surprise`, `silence`
- `locked_doors`, `reversed`
- `king_of_the_hill`, `roulette`

**Examples:**
```
event darkness
event time_dilation
event roulette
```

### Game State
| Command | Description |
|---------|-------------|
| `race` | Show current race status |
| `time` | Show elapsed race time |
| `speed` | Show current timer scale modifier |
| `fps` | Show current FPS |

## Export Behavior
The console automatically removes itself when:
- Project is exported for release
- `OS.is_debug_build()` returns `false`

This ensures:
- No performance impact on released builds
- Players can't access debug commands
- No security risks from exposed internals

## Technical Details
- **Layer:** 999 (topmost UI)
- **Toggle keys:** `~` or `F12`
- **Auto-disabled:** In exported builds
- **Memory:** ~50KB when loaded, 0KB when exported
