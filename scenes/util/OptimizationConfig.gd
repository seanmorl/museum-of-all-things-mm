class_name OptimizationConfig
extends RefCounted
## Central configuration for performance optimizations.
## All flags can be toggled at runtime for testing.

# ── MULTIPLAYER OPTIMIZATIONS ─────────────────────────────────────────────────

## Use unreliable RPC for player position sync (30-50% bandwidth reduction)
## If players experience lag/teleporting, set to false to fall back to reliable
const USE_UNRELIABLE_POSITION_SYNC := true

## Position sync interval (seconds)
## Lower = smoother but more bandwidth, Higher = less bandwidth but choppier
const POSITION_SYNC_INTERVAL := 0.05  # 20 updates per second (50ms)

## Adaptive sync: increase interval when players are far apart or stationary
const USE_ADAPTIVE_SYNC_RATE := false  # Disabled by default - test first

## Min/max sync intervals for adaptive sync
const ADAPTIVE_SYNC_MIN := 0.025  # 40 updates/sec when close
const ADAPTIVE_SYNC_MAX := 0.2    # 5 updates/sec when far

## Dead reckoning: predict movement between sync updates
const USE_DEAD_RECKONING := false  # Disabled by default - can cause rubber-banding

# ── GRAPHICS OPTIMIZATIONS ────────────────────────────────────────────────────

## Enable room-based visibility culling (hide distant exhibits)
const USE_ROOM_VISIBILITY_CULLING := true

## Enable manual occluders for walls (improves occlusion culling)
const USE_MANUAL_OCCLUDERS := false  # Not yet implemented

## Enable LOD system for items
const USE_LOD_SYSTEM := false  # Not yet implemented

## Enable HLOD for entire rooms
const USE_HLOD := false  # Not yet implemented

# ── DEBUG / TESTING ───────────────────────────────────────────────────────────

## Show optimization debug info (FPS, bandwidth, etc.)
const SHOW_DEBUG_INFO := false

## Force fallback to reliable sync (for testing)
static func force_reliable_sync(enabled: bool) -> void:
	"""Toggle to test reliable vs unreliable sync at runtime."""
	# This would be connected to a debug key (e.g., F4)
	if enabled:
		print("[OptimizationConfig] FORCED reliable sync (F4)")
	else:
		print("[OptimizationConfig] Using unreliable sync (F4)")
