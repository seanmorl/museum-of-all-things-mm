# Contributing to Museum of All Things

Thank you for your interest in contributing! This guide will help you get started.

## Quick Start

### Prerequisites

- **Godot 4.6** - This project requires Godot 4.6 or later
- **Git** - For version control
- **~5GB disk space** - For the project and dependencies

### Setup Instructions

1. **Clone the repository**
   ```bash
   git clone https://github.com/m4ym4y/museum-of-all-things.git
   cd museum-of-all-things
   ```

2. **Open in Godot**
   - Launch Godot 4.6+
   - Import the project by selecting `project.godot`
   - Godot will automatically import assets and generate `.uid` files

3. **Run the project**
   - Press F5 or click the Play button in Godot
   - The main scene is `res://scenes/Main.tscn`

## Project Structure

```
museum-of-all-things/
├── scenes/              # GDScript files and scene files
│   ├── autoload/        # Auto-loaded singletons (TTS, daily challenges)
│   ├── core/            # Core architecture (EventBus, Services, GameState)
│   ├── fx/              # Visual effects and particle systems
│   ├── items/           # Placeable museum items
│   ├── main/            # Main game controllers
│   ├── menu/            # UI menus and overlays
│   ├── museum/          # Museum-specific systems
│   ├── network/         # Multiplayer networking
│   ├── npc/             # Non-player characters
│   ├── player/          # Player controllers and systems
│   ├── services/        # Business logic services
│   ├── test/            # Test scenes and scripts
│   ├── tournament/      # Tournament mode systems
│   ├── ui/              # UI components and HUDs
│   └── util/            # Utility classes and helpers
├── assets/              # Game assets
│   ├── 3d_tiles/        # 3D tile models
│   ├── animations/      # Animation files
│   ├── fonts/           # Font files
│   ├── materials/       # Material resources
│   ├── meshes/          # Mesh files
│   ├── models/          # 3D models
│   ├── resources/       # Godot resources
│   ├── sound/           # Audio files
│   ├── textures/        # Texture files
│   └── translations/    # Localization files
├── addons/              # Third-party plugins
├── shaders/             # Shader files
├── docs/                # Documentation
└── tools/               # Development tools
```

## Code Style Guidelines

### GDScript Conventions

- **Class names**: PascalCase (`PlayerMountSystem`, `RaceManager`)
- **Variables**: snake_case with leading underscore for private (`_player`, `_current_room`)
- **Constants**: UPPER_SNAKE_CASE (`MAX_PLAYERS`, `DEFAULT_PORT`)
- **Functions**: snake_case (`fetch_exhibit`, `reset_to_lobby`)
- **Signals**: snake_case (`race_started`, `player_connected`)

### File Organization

- One class per file
- File name matches class name (`PlayerMountSystem.gd` for class `PlayerMountSystem`)
- Use `class_name` to register global classes
- Use `@export` for inspector-visible variables
- Add docstrings with `##` for public functions

### Example

```gdscript
class_name ExampleClass
extends Node

## Description of what this constant is for
const MAX_COUNT := 10

## Player's current health
@export var health: float = 100.0

var _private_data: String = ""

## Brief description of function
## @param amount - how much to heal
## @returns true if healing was successful
func heal(amount: float) -> bool:
    ## Internal logic
    if amount > 0:
        health = min(health + amount, 100)
        return true
    return false
```

## Making Contributions

### Bug Fixes

1. Check existing issues to see if it's already reported
2. Create a new issue if needed
3. Fork the repository
4. Create a feature branch (`git checkout -b fix/bug-name`)
5. Make your changes
6. Test thoroughly
7. Submit a pull request

### Features

1. **File an issue first!** Discuss the feature before implementing
2. Get approval from maintainer (@m4ym4y)
3. Fork and create feature branch (`git checkout -b feature/feature-name`)
4. Implement the feature
5. Test thoroughly
6. Submit a pull request

### Translations

See the [Translation Guide](docs/translation-guide.md) for detailed instructions on adding your language.

### What We're Looking For

We **welcome** these contributions:
- ✅ Bug fixes
- ✅ Performance optimizations
- ✅ Visual improvements
- ✅ Accessibility enhancements
- ✅ Translations
- ✅ Documentation improvements
- ✅ Code cleanup and refactoring

We are **selective** about:
- ⚠️ Creative direction changes
- ⚠️ Major feature additions
- ⚠️ Gameplay mechanic modifications

## Pull Request Process

1. Update the README.md with details of changes if needed
2. Test your changes on multiple platforms if possible
3. Update documentation if you're changing functionality
4. The PR should work for both client and dedicated server builds
5. Your PR will be reviewed by maintainers

### PR Title Format

Use descriptive titles:
- `Fix: Null reference crash in Main.gd`
- `Add: Player sprint feature`
- `Improve: Exhibit generation performance`
- `Update: German translation`

## Architecture Notes

The project uses several architectural patterns:

- **Event Bus**: Central event system (`EventBus.gd`) for decoupled communication
- **Services**: Business logic separated into service classes
- **Autoloads**: Global singletons for frequently accessed systems
- **State Machines**: Player behavior uses state machine pattern

See `docs/ARCHITECTURE_DECISIONS.md` for more details.

## Testing

### Manual Testing Checklist

- [ ] Game launches without errors
- [ ] Main menu works
- [ ] Single player game works
- [ ] Host multiplayer works
- [ ] Join multiplayer works
- [ ] Dedicated server starts
- [ ] No console errors in log

### Godot's Built-in Tests

Run any test scenes in `scenes/test/`:
- `ExhibitTestScene.tscn` - Test exhibit generation
- `GenerationTestScene.tscn` - Test procedural generation
- `EventTests.tscn` - Test event system

## Common Tasks

### Adding a New Language

1. Create translation file in `assets/translations/`
2. Add to project settings
3. See [Translation Guide](docs/translation-guide.md)

### Adding a New Menu Item

1. Add UI element to appropriate scene in `scenes/menu/`
2. Connect signals
3. Test in both client and server modes

### Debugging

- Use `print()` for quick debugging
- Use `Log.info()` or `Log.debug()` for proper logging
- Enable debug console in development builds (press `~` in-game)
- Check `docs/DEBUG_CONSOLE.md` for console commands

## Getting Help

- **Bugs**: File an issue with exhibit name and platform
- **Questions**: File an issue with your question
- **Discussions**: Use GitHub Discussions

## License

By contributing, you agree that your contributions will be licensed under the project's MIT License.

---

**Thank you for contributing to the Museum of All Things!** 🏛️
