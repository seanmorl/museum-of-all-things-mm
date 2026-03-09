import re

with open(r'c:\Users\TeamS\Documents\GitHub\museum-of-all-things-mm\scenes\Lobby.tscn', 'r') as f:
    content = f.read()

# Find the GridMap data
match = re.search(r'"cells": PackedInt32Array\((.*?)\)', content)
if match:
    data = [int(x.strip()) for x in match.group(1).split(',')]
    ys = []
    # GridMap data is (index_low, index_high, cell_data) or (x, y, data)?
    # Wait, in TSCN it's often (x, y, z, item, orientation) or similar.
    # Actually, in Godot 4, cell data is usually (x, z, y, item, orientation) packed or 3 ints.
    # Let's count elements.
    print(f"Total elements: {len(data)}")
    # If 3 elements per cell:
    for i in range(0, len(data), 3):
        # In many versions it's (x, z, item_plus_orientation) and y is somewhere else?
        # Actually, if it's (x, y, data), let's just look at every first/second element.
        pass
    
    # Let's just find the max value that isn't a giant bitmask.
    valid_ys = [x for x in data if -20 < x < 50]
    print(f"Max potential Y: {max(valid_ys) if valid_ys else 'None'}")
    print(f"Sample data: {data[:30]}")
else:
    print("GridMap data not found")
