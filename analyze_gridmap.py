import re

# Use relative path so this works for all developers
with open('scenes/Lobby.tscn', 'r') as f:
    content = f.read()

# Find the GridMap data
match = re.search(r'"cells": PackedInt32Array\((.*?)\)', content)
if match:
    data = [int(x.strip()) for x in match.group(1).split(',')]
    # GridMap data is (x, z, item_plus_orientation) packed in groups of 3
    # Let's just find values in a reasonable range (not bitmasks)
    valid_values = [x for x in data if -20 < x < 50]
    print(f"Total elements: {len(data)}")
    print(f"Max potential Y: {max(valid_values) if valid_values else 'None'}")
    print(f"Sample data: {data[:30]}")
else:
    print("GridMap data not found")
    print("Run this script from the project root directory")
