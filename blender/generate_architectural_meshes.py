bl_info = {
    "name": "MoAT Architectural Mesh Generator",
    "description": "Batch-generate architectural meshes using Archimesh for Museum of All Things",
    "version": (1, 0, 0),
    "blender": (3, 0, 0),
    "category": "Import-Export",
}

import bpy
import os

# ── Configuration ──────────────────────────────────────────────────────────────
# Output directory — adjust to match your Godot project path
OUTPUT_DIR = r"C:\Users\TeamS\Documents\GitHub\museum-of-all-things-mm\assets\meshes"

# ── Helpers ────────────────────────────────────────────────────────────────────

def ensure_output_dir():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    # Also clear orphan data
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        if block.users == 0:
            bpy.data.materials.remove(block)

def export_glb(name: str):
    """Export all selected objects (or all if none selected) as a GLB."""
    filepath = os.path.join(OUTPUT_DIR, f"{name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_colors=True,
    )
    print(f"  Exported: {filepath}")

def set_column_style(obj, style: str):
    """Configure an Archimesh column object's style properties."""
    if obj is None:
        return
    # Archimesh column properties
    if hasattr(obj, "archimesh_column_base"):
        obj.archimesh_column_base = True
    if hasattr(obj, "archimesh_column_cap"):
        obj.archimesh_column_cap = True

    # Order/style mapping (Archimesh uses numeric order for column styles)
    style_map = {
        "doric": 0,
        "ionic": 1,
        "corinthian": 2,
        "tuscan": 3,
        "compound": 4,
    }
    if hasattr(obj, "archimesh_column_order") and style in style_map:
        obj.archimesh_column_order = style_map[style]

def set_arch_style(obj, style: str):
    """Configure an Archimesh arch/door opening to simulate arch styles."""
    if obj is None:
        return
    # Archimesh doesn't have a direct "arch" type, but doors/windows can simulate
    # We use the door type with specific proportions
    pass

# ── Generators ─────────────────────────────────────────────────────────────────

def generate_column(style: str, height: float = 4.0, radius: float = 0.3):
    """Generate a single column of the given style."""
    clear_scene()
    bpy.ops.archimesh.add_mesh(type='COLUMN')
    col = bpy.context.active_object
    if col is None:
        print(f"  WARNING: Failed to create column '{style}'")
        return None

    col.name = f"column_{style}"

    # Set dimensions
    if hasattr(col, "archimesh_column_height"):
        col.archimesh_column_height = height
    if hasattr(col, "archimesh_column_radio"):
        col.archimesh_column_radio = radius

    set_column_style(col, style)
    return col

def generate_arch_round():
    """Generate a round arch using a door frame as base."""
    clear_scene()
    bpy.ops.archimesh.add_mesh(type='DOOR')
    door = bpy.context.active_object
    if door is None:
        print("  WARNING: Failed to create round arch")
        return None
    door.name = "arch_round"
    # Configure as arch (no door leaf, round top)
    if hasattr(door, "archimesh_door_hide"):
        door.archimesh_door_hide = True
    if hasattr(door, "archimesh_door_round"):
        door.archimesh_door_round = True
    if hasattr(door, "archimesh_width"):
        door.archimesh_width = 3.0
    if hasattr(door, "archimesh_height"):
        door.archimesh_height = 4.0
    if hasattr(door, "archimesh_depth"):
        door.archimesh_depth = 0.4
    return door

def generate_arch_pointed():
    """Generate a pointed (Gothic) arch."""
    clear_scene()
    bpy.ops.archimesh.add_mesh(type='DOOR')
    door = bpy.context.active_object
    if door is None:
        print("  WARNING: Failed to create pointed arch")
        return None
    door.name = "arch_pointed"
    if hasattr(door, "archimesh_door_hide"):
        door.archimesh_door_hide = True
    if hasattr(door, "archimesh_door_round"):
        door.archimesh_door_round = True
    if hasattr(door, "archimesh_width"):
        door.archimesh_width = 3.0
    if hasattr(door, "archimesh_height"):
        door.archimesh_height = 5.0  # Taller for pointed look
    if hasattr(door, "archimesh_depth"):
        door.archimesh_depth = 0.3
    return door

def generate_arch_flat():
    """Generate a flat (modern) arch / lintel."""
    clear_scene()
    bpy.ops.archimesh.add_mesh(type='DOOR')
    door = bpy.context.active_object
    if door is None:
        print("  WARNING: Failed to create flat arch")
        return None
    door.name = "arch_flat"
    if hasattr(door, "archimesh_door_hide"):
        door.archimesh_door_hide = True
    if hasattr(door, "archimesh_door_round"):
        door.archimesh_door_round = False  # Flat top
    if hasattr(door, "archimesh_width"):
        door.archimesh_width = 3.0
    if hasattr(door, "archimesh_height"):
        door.archimesh_height = 3.5
    if hasattr(door, "archimesh_depth"):
        door.archimesh_depth = 0.25
    return door

def generate_molding_ornate():
    """Generate an ornate crown molding using room cornice."""
    clear_scene()
    bpy.ops.archimesh.add_mesh(type='ROOM')
    room = bpy.context.active_object
    if room is None:
        print("  WARNING: Failed to create ornate molding")
        return None
    room.name = "molding_ornate"
    # Configure as just cornice/molding
    if hasattr(room, "archimesh_room_cornice"):
        room.archimesh_room_cornice = True
    if hasattr(room, "archimesh_room_baseboard"):
        room.archimesh_room_baseboard = True
    if hasattr(room, "archimesh_room_width"):
        room.archimesh_room_width = 4.0
    if hasattr(room, "archimesh_room_height"):
        room.archimesh_room_height = 3.0
    if hasattr(room, "archimesh_room_depth"):
        room.archimesh_room_depth = 4.0
    return room

def generate_molding_simple():
    """Generate a simple molding."""
    clear_scene()
    bpy.ops.archimesh.add_mesh(type='ROOM')
    room = bpy.context.active_object
    if room is None:
        print("  WARNING: Failed to create simple molding")
        return None
    room.name = "molding_simple"
    if hasattr(room, "archimesh_room_cornice"):
        room.archimesh_room_cornice = True
    if hasattr(room, "archimesh_room_baseboard"):
        room.archimesh_room_baseboard = False
    if hasattr(room, "archimesh_room_width"):
        room.archimesh_room_width = 4.0
    if hasattr(room, "archimesh_room_height"):
        room.archimesh_room_height = 3.0
    if hasattr(room, "archimesh_room_depth"):
        room.archimesh_room_depth = 4.0
    return room

def generate_ceiling_vaulted():
    """Generate a vaulted ceiling section."""
    clear_scene()
    bpy.ops.archimesh.add_mesh(type='ROOM')
    room = bpy.context.active_object
    if room is None:
        print("  WARNING: Failed to create vaulted ceiling")
        return None
    room.name = "ceiling_vaulted"
    if hasattr(room, "archimesh_room_ceiling"):
        room.archimesh_room_ceiling = True
    if hasattr(room, "archimesh_room_width"):
        room.archimesh_room_width = 6.0
    if hasattr(room, "archimesh_room_height"):
        room.archimesh_room_height = 5.0
    if hasattr(room, "archimesh_room_depth"):
        room.archimesh_room_depth = 6.0
    return room

def generate_ceiling_coffered():
    """Generate a coffered ceiling section."""
    clear_scene()
    bpy.ops.archimesh.add_mesh(type='ROOM')
    room = bpy.context.active_object
    if room is None:
        print("  WARNING: Failed to create coffered ceiling")
        return None
    room.name = "ceiling_coffered"
    if hasattr(room, "archimesh_room_ceiling"):
        room.archimesh_room_ceiling = True
    if hasattr(room, "archimesh_room_width"):
        room.archimesh_room_width = 6.0
    if hasattr(room, "archimesh_room_height"):
        room.archimesh_room_height = 4.0
    if hasattr(room, "archimesh_room_depth"):
        room.archimesh_room_depth = 6.0
    return room

def generate_ceiling_flat():
    """Generate a flat ceiling section."""
    clear_scene()
    bpy.ops.archimesh.add_mesh(type='ROOM')
    room = bpy.context.active_object
    if room is None:
        print("  WARNING: Failed to create flat ceiling")
        return None
    room.name = "ceiling_flat"
    if hasattr(room, "archimesh_room_ceiling"):
        room.archimesh_room_ceiling = True
    if hasattr(room, "archimesh_room_width"):
        room.archimesh_room_width = 6.0
    if hasattr(room, "archimesh_room_height"):
        room.archimesh_room_height = 3.0
    if hasattr(room, "archimesh_room_depth"):
        room.archimesh_room_depth = 6.0
    return room

# ── Main ───────────────────────────────────────────────────────────────────────

def run_generation():
    ensure_output_dir()

    # Enable archimesh if not already enabled
    addon_name = "archimesh"
    if addon_name not in bpy.context.preferences.addons:
        try:
            bpy.ops.preferences.addon_enable(module=addon_name)
            print(f"Enabled addon: {addon_name}")
        except Exception as e:
            print(f"ERROR: Could not enable archimesh: {e}")
            print("Make sure Archimesh is installed and available in your Blender version.")
            return

    print(f"\n{'='*60}")
    print(f"MoAT Architectural Mesh Generator")
    print(f"Output: {OUTPUT_DIR}")
    print(f"{'='*60}\n")

    # ── Columns ────────────────────────────────────────────────────────────
    print("--- Columns ---")
    for style in ["doric", "ionic", "corinthian", "tuscan", "compound"]:
        print(f"  Generating column_{style}...")
        generate_column(style)
        export_glb(f"column_{style}")

    # ── Arches ─────────────────────────────────────────────────────────────
    print("\n--- Arches ---")
    for name, gen_fn in [
        ("arch_round", generate_arch_round),
        ("arch_pointed", generate_arch_pointed),
        ("arch_flat", generate_arch_flat),
    ]:
        print(f"  Generating {name}...")
        gen_fn()
        export_glb(name)

    # ── Moldings ───────────────────────────────────────────────────────────
    print("\n--- Moldings ---")
    for name, gen_fn in [
        ("molding_ornate", generate_molding_ornate),
        ("molding_simple", generate_molding_simple),
    ]:
        print(f"  Generating {name}...")
        gen_fn()
        export_glb(name)

    # ── Ceilings ───────────────────────────────────────────────────────────
    print("\n--- Ceilings ---")
    for name, gen_fn in [
        ("ceiling_vaulted", generate_ceiling_vaulted),
        ("ceiling_coffered", generate_ceiling_coffered),
        ("ceiling_flat", generate_ceiling_flat),
    ]:
        print(f"  Generating {name}...")
        gen_fn()
        export_glb(name)

    # ── Cleanup ────────────────────────────────────────────────────────────
    clear_scene()
    print(f"\n{'='*60}")
    print("Done! All meshes exported.")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    run_generation()
