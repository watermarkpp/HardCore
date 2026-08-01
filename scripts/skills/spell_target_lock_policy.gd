class_name SpellTargetLockPolicy
extends RefCounted

const CONTRACT_ID := "combat.spell_lock.chebyshev_tiles.v1"
const LOCK_RANGE_TILES := 12.0


static func chebyshev_distance(origin_tile: Vector2, target_tile: Vector2) -> float:
	var delta := target_tile - origin_tile
	return maxf(absf(delta.x), absf(delta.y))


static func is_within_lock_range(origin_tile: Vector2, target_tile: Vector2) -> bool:
	return chebyshev_distance(origin_tile, target_tile) <= LOCK_RANGE_TILES + 0.0001


static func ordered_candidates(raw_candidates: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_candidate: Dictionary in raw_candidates:
		var candidate := raw_candidate.duplicate(true)
		var origin_tile: Vector2 = candidate.get("origin_tile", Vector2.ZERO)
		var target_tile: Vector2 = candidate.get("target_tile", Vector2.ZERO)
		var tile_distance := chebyshev_distance(origin_tile, target_tile)
		if tile_distance > LOCK_RANGE_TILES + 0.0001:
			continue
		candidate["contract_id"] = CONTRACT_ID
		candidate["tile_distance"] = tile_distance
		candidate["tile_distance_squared"] = origin_tile.distance_squared_to(target_tile)
		result.append(candidate)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance := float(a.get("tile_distance", INF))
		var b_distance := float(b.get("tile_distance", INF))
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		var a_tile_squared := float(a.get("tile_distance_squared", INF))
		var b_tile_squared := float(b.get("tile_distance_squared", INF))
		if not is_equal_approx(a_tile_squared, b_tile_squared):
			return a_tile_squared < b_tile_squared
		var a_world_squared := float(a.get("world_distance_squared", INF))
		var b_world_squared := float(b.get("world_distance_squared", INF))
		if not is_equal_approx(a_world_squared, b_world_squared):
			return a_world_squared < b_world_squared
		return int(a.get("instance_id", 0)) < int(b.get("instance_id", 0))
	)
	return result


static func spell_range_allows_target(
	origin_tile: Vector2,
	target_tile: Vector2,
	maximum_range_tiles: float
) -> bool:
	if maximum_range_tiles <= 0.0:
		return true
	return chebyshev_distance(origin_tile, target_tile) <= maximum_range_tiles + 0.0001
