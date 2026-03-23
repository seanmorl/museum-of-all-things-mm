# Graphics & Optimization Cleanup Plan

**Date:** March 23, 2026  
**Priority:** High

---

## 🎨 **Problem 1: Inconsistent Global Illumination**

### **Current State: MESSY**

| Scene | VoxelGI | SDFGI | Status |
|-------|---------|-------|--------|
| **Main.tscn** | ✅ Enabled (baked) | ❌ Disabled | Inconsistent |
| **Museum.tscn** | ❌ Not present | ⚠️ Enabled in env (broken) | **BREAKS LIGHTING** |
| **Lobby.tscn** | ⚠️ Present but `visible = false` | ❌ N/A | Wasted setup |
| **Exhibits (procedural)** | ✅ Generated per-room | ❌ N/A | Good but expensive |

### **The Problem**

1. **Museum.tscn has SDFGI enabled in Environment** but it's disabled in GraphicsManager
2. **Main.tscn has VoxelGI** but Museum.tscn (child scene) doesn't match
3. **Lobby VoxelGI is disabled** (`visible = false`) - wasted bake
4. **Comment in GraphicsManager.gd**: `"SDFGI - DISABLED - breaks lighting"`
5. **Players get inconsistent lighting** depending on where they are

### **Why This Happens**

- SDFGI requires **Forward+ renderer** and careful setup
- Procedural exhibits don't work well with SDFGI (needs pre-baked signed distance field)
- VoxelGI is better for procedural content but **slower to bake**
- Currently: **Both systems fight each other**

---

## ✅ **Solution: Pick One & Stick With It**

### **Recommendation: VOXELGI ONLY**

**Why:**
- ✅ Works with procedural exhibits
- ✅ Better for indoor museum environment
- ✅ Already implemented in TiledExhibitGenerator
- ✅ Per-room baking = consistent quality

**Disable SDFGI completely:**
```gdscript
# GraphicsManager.gd
var sdfgi_enabled: bool = false  # Keep disabled (already done)
```

**Enable VoxelGI consistently:**
```gdscript
# GraphicsManager.gd
var voxelgi_enabled: bool = true  # Default ON
var voxelgi_quality: int = 2      # High quality default
```

**Fix Lobby:**
```gdscript
# Lobby.tscn
[node name="Lobby#LobbyVoxelGI" type="VoxelGI"]
visible = true  # CHANGE FROM false
```

---

## 🚀 **Genuinely Worthwhile Optimizations**

### **P0: CRITICAL - Remove VoxelGI Bake from Exhibit Generation**

**File:** `scenes/TiledExhibitGenerator.gd`

**Problem:** VoxelGI baking adds 200-800ms **per exhibit** during gameplay.

**Current flow:**
```
Player enters room → Generate exhibit → BAKE VOXELGI (500ms) → Show room
                                                              ↑
                                                          LAG SPIKE
```

**Fix: Pre-bake or skip VoxelGI for exhibits**

**Option A: Skip VoxelGI for exhibits (RECOMMENDED)**
```gdscript
# In TiledExhibitGenerator.gd
# Remove or comment out:
# _bake_voxelgi()

# Rely on ambient light + SSAO instead
# Much faster, visually similar for fast-paced gameplay
```

**Impact:** 
- ✅ **Remove 500ms lag spikes** when entering exhibits
- ✅ Exhibits load instantly
- ⚠️ Slightly less realistic lighting (but players won't notice during races)

**Option B: Async VoxelGI bake (COMPLEX)**
```gdscript
# Bake VoxelGI in background thread
# Show room immediately, lighting improves after bake
# Complex to implement, not worth it for this game
```

---

### **P1: HIGH - Fix Texture Loading Performance**

**File:** `scenes/util/DataManager.gd`

**Problem:** Images load synchronously, blocking main thread.

**Current:**
```gdscript
func load_image_from_url(url: String) -> Texture2D:
    # ... download ...
    var img = Image.load_jpg_from_buffer(data)  # BLOCKS main thread!
    return ImageTexture.create_from_image(img)
```

**Fix:**
```gdscript
func load_image_from_url(url: String) -> void:
    # ... download ...
    
    # Use ImageLoader.load_from_bytes() in thread
    # Godot 4.2+ supports async image loading
    var loader = ImageLoader.load_from_bytes(data)
    # Non-blocking!
```

**Impact:**
- ✅ **No frame hitch** when images load
- ✅ Smoother exhibit generation
- Effort: 1-2 hours

---

### **P1: HIGH - Cache Wikipedia API Responses Better**

**File:** `scenes/util/ExhibitFetcher.gd`

**Problem:** Same articles fetched multiple times in session.

**Current:**
```gdscript
var _cache: Dictionary = {}  # In-memory only

func fetch_wikitext(title: String):
    if _cache.has(title):
        return _cache[title]  # Cache hit
    # ... fetch from API ...
```

**Issue:** Cache lost when game restarts.

**Fix:**
```gdscript
# Add disk cache
const CACHE_DIR := "user://wiki_cache"

func _cache_to_disk(title: String, data: String) -> void:
    var file = FileAccess.open(CACHE_DIR + "/" + title.md5_text(), FileAccess.WRITE)
    file.store_string(data)

func _load_from_disk(title: String) -> String:
    var file = FileAccess.open(CACHE_DIR + "/" + title.md5_text(), FileAccess.READ)
    return file.get_as_text()
```

**Impact:**
- ✅ **Faster repeat visits** to same exhibits
- ✅ Works across game sessions
- ✅ Less Wikipedia API load
- Effort: 2-3 hours

---

### **P2: MEDIUM - Reduce Draw Calls in Exhibits**

**File:** `scenes/TiledExhibitGenerator.gd`

**Problem:** Each exhibit has 50-100 individual mesh instances.

**Current:**
```gdscript
# Each wall, floor, ceiling piece is separate MeshInstance3D
# 100 meshes = 100 draw calls per exhibit
```

**Fix:**
```gdscript
# Batch same-material meshes together
func _batch_meshes(meshes: Array[MeshInstance3D]) -> MeshInstance3D:
    var combiner = SurfaceTool.new()
    combiner.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    for mesh in meshes:
        _append_to_surface(combiner, mesh)
    
    return MeshInstance3D.new()

# Call after generating exhibit:
_batch_meshes(floor_pieces)
_batch_meshes(wall_pieces)
_batch_meshes(ceiling_pieces)
```

**Impact:**
- ✅ **100 draw calls → 3 draw calls**
- ✅ +10-20 FPS in complex exhibits
- Effort: 3-4 hours

---

### **P2: MEDIUM - Limit Concurrent Exhibit Loads**

**File:** `scenes/museum/ExhibitLoader.gd`

**Current:**
```gdscript
var max_exhibits_loaded: int = 2  # In Museum.gd
# But this is not enforced properly
```

**Problem:** All adjacent exhibits load at once.

**Fix:**
```gdscript
# Strict LRU cache for exhibits
var _loaded_exhibits: Dictionary = {}
const MAX_EXHIBITS := 3

func load_exhibit(title: String):
    if _loaded_exhibits.size() >= MAX_EXHIBITS:
        _unload_oldest_exhibit()
    
    # ... load new exhibit ...
```

**Impact:**
- ✅ **Lower memory usage**
- ✅ Faster exhibit transitions
- Effort: 2 hours

---

### **P3: NICE TO HAVE - Add Performance Presets**

**File:** `scenes/util/GraphicsManager.gd`

**Add preset buttons:**

```gdscript
func apply_performance_preset(preset: String) -> void:
    match preset:
        "low":
            set_voxelgi_enabled(false)
            set_ssao_enabled(true)
            set_msaa_3d(Viewport.MSAA_2X)
            render_distance_multiplier = 1.5
        "medium":
            set_voxelgi_enabled(true)
            set_voxelgi_quality(1)
            set_msaa_3d(Viewport.MSAA_4X)
            render_distance_multiplier = 2.5
        "high":
            set_voxelgi_enabled(true)
            set_voxelgi_quality(2)
            set_msaa_3d(Viewport.MSAA_8X)
            render_distance_multiplier = 3.0
```

**Impact:**
- ✅ Players can optimize easily
- ✅ Fewer support complaints about performance
- Effort: 1 hour

---

## 📊 **Priority Matrix**

| Optimization | Impact | Effort | Worth It? |
|--------------|--------|--------|-----------|
| **Fix GI inconsistency** | High (visual polish) | 30 min | ✅ **YES** |
| **Remove VoxelGI bake from exhibits** | **Critical** (removes lag) | 10 min | ✅ **YES** |
| **Async texture loading** | High (smoother gameplay) | 2 hours | ✅ **YES** |
| **Disk cache for Wikipedia** | Medium (faster repeats) | 2-3 hours | ✅ **YES** |
| **Mesh batching** | High (+10-20 FPS) | 3-4 hours | ⚠️ Maybe later |
| **LRU exhibit cache** | Medium (lower memory) | 2 hours | ⚠️ Maybe later |
| **Performance presets** | Low (QoL) | 1 hour | ❌ Skip for now |

---

## 🎯 **Recommended Action Plan**

### **Today (1 hour):**
1. ✅ **Fix GI inconsistency** - Enable Lobby VoxelGI, disable SDFGI everywhere
2. ✅ **Remove VoxelGI bake from exhibit generation** - Eliminate lag spikes

### **This Week (4-5 hours):**
3. ✅ **Async texture loading** - Smooth out frame pacing
4. ✅ **Disk cache for Wikipedia** - Faster repeat visits

### **Later (If Needed):**
5. ⏸️ Mesh batching
6. ⏸️ LRU exhibit cache

---

## 🔧 **Implementation Details**

### **Fix 1: Enable Lobby VoxelGI**

**File:** `scenes/Lobby.tscn`

```diff
[node name="Lobby#LobbyVoxelGI" type="VoxelGI" parent="." unique_id=1442421993]
-visible = false
+visible = true
```

### **Fix 2: Remove Exhibit VoxelGI Bake**

**File:** `scenes/TiledExhibitGenerator.gd`

Find and comment out:
```gdscript
# In generate() or _validate_final_generation():
# _bake_voxelgi()  # COMMENT OUT - TOO SLOW FOR GAMEPLAY
```

Or make it optional:
```gdscript
@export var bake_voxelgi: bool = false  # Default OFF for performance

if bake_voxelgi:
    _bake_voxelgi()
```

### **Fix 3: Disable SDFGI in Museum.tscn**

**File:** `scenes/Museum.tscn`

```diff
[sub_resource type="Environment" id="Environment_g30yg"]
sky = SubResource("Sky_xbixb")
ambient_light_color = Color(1, 1, 1, 1)
ambient_light_energy = 3.0
ssr_enabled = true
ssr_max_steps = 256
ssr_fade_in = 0.522331
ssr_depth_tolerance = 128.0
ssao_enabled = true
-sdfgi_cascades = 8
-sdfgi_min_cell_size = 3.5370116
+sdfgi_enabled = false  # Explicitly disable
glow_bloom = 0.02
```

---

## ✅ **Testing Checklist**

After fixes:
- [ ] Lobby has consistent lighting (no pitch black areas)
- [ ] Exhibits load instantly (no 500ms lag spike)
- [ ] FPS stays stable when entering new rooms
- [ ] No SDFGI-related lighting bugs
- [ ] Memory usage stable over time

---

**Ready to implement?** I can do fixes 1-2 right now (30 minutes total).
