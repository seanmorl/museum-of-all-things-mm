# Bubble Tube & Aquarium Panel - Creation Guide

These are optional decorative items. To add them:

## In Godot Editor:

1. **Bubble Tube:**
   - Create new Node3D named "BubbleTube"
   - Add child MeshInstance3D with CylinderMesh (glass tube)
   - Add child MeshInstance3D with SphereMesh (base)
   - Add child OmniLight3D (blue light)
   - Add child GPUParticles3D (rising bubbles)
   - Attach `BubbleTube.gd` script
   - Save as `scenes/items/BubbleTube.tscn`
   - Instance in Lobby at positions (-2.5, 2, 8) and (2.5, 2, 8)

2. **Aquarium Panel:**
   - Create new Node3D named "AquariumPanel"
   - Add child MeshInstance3D with BoxMesh (frame)
   - Add 3x MeshInstance3D children with SphereMesh (fish)
   - Add child OmniLight3D (backlight)
   - Add child GPUParticles3D (bubbles)
   - Attach `AquariumPanel.gd` script
   - Save as `scenes/items/AquariumPanel.tscn`
   - Instance in Lobby at positions (-6, 3, 0) and (6, 3, 0)

## Scripts are ready:
- `scenes/items/BubbleTube.gd` ✓
- `scenes/items/AquariumPanel.gd` ✓

These will animate the decorations automatically once the scenes are created.
