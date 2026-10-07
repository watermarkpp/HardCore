extends RefCounted

## Continuous navigation candidates for crowded ordinary melee bodies.
## Owns no HP, attack permission, timers, reservations or position writes.
const GU := preload("res://scripts/ground_unit_space.gd")
const Reach := preload("res://scripts/monster_source176/source_melee_geometry.gd")
const DIRECTIONS := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP,
	Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]

static func margin_gu(actor: CharacterBody2D) -> float:
	# Largest ground displacement of the existing screen-space recovery
	# margin, across the two singular axes of the isometric projection.
	return actor.safe_margin / (minf(GU.HALF_TILE_SIZE_PX.x, GU.HALF_TILE_SIZE_PX.y) * sqrt(2.0))

static func axis_distance(actor: CharacterBody2D, target_radius: float) -> float:
	return minf(Reach.HALF_EXTENT_GU, float(actor.get("combat_radius_gu")) + target_radius + 2.0 * margin_gu(actor) + GU.EPSILON_GU)

static func station(actor: CharacterBody2D, anchor: Vector2, target_radius: float, slot: int) -> Vector2:
	var direction: Vector2 = DIRECTIONS[slot]
	return anchor + direction * (axis_distance(actor, target_radius) if slot < 4 else Reach.HALF_EXTENT_GU)

static func snapshot_peers(actor: CharacterBody2D, peers: Array) -> Array:
	# One synchronous decision only. Keep source/index order; do not sort or
	# cache eligibility across actors. Eligibility is checked after geometry.
	var result: Array = []
	for other: Variant in peers:
		if not is_instance_valid(other) or other == actor or not other is CharacterBody2D:
			continue
		var position: Vector2 = other.spatial_index_position()
		if not position.is_finite():
			continue
		result.append({"node": other, "position": position, "radius": float(other.combat_radius_gu)})
	return result

static func _snapshot_available(actor: CharacterBody2D, point: Vector2, snapshot: Array) -> bool:
	var own_radius := float(actor.get("combat_radius_gu"))
	for record: Dictionary in snapshot:
		var other: Variant = record.get("node")
		var radius := own_radius + float(record.get("radius", 0.0))
		var center: Vector2 = record.get("position", Vector2.INF)
		# Coarse geometry first: distant peers must incur zero eligibility calls.
		if not center.is_finite() or center.distance_squared_to(point) >= radius * radius - GU.EPSILON_GU:
			continue
		if record.has("eligible"):
			if bool(record.get("eligible", false)):
				return false
			continue
		var eligible: bool = is_instance_valid(other) and other.can_receive_damage() and bool(other.behavior_profile.get("worldCollision", true))
		record["eligible"] = eligible
		if eligible:
			return false
	return true

static func available(actor: CharacterBody2D, hit_target: Node2D, point: Vector2, peers: Array) -> bool:
	return _snapshot_available(actor, point, snapshot_peers(actor, peers))

static func goal_with_snapshot(actor: CharacterBody2D, hit_target: Node2D, anchor: Vector2, slot: int, snapshot: Array) -> Vector2:
	if slot < 0 or slot >= DIRECTIONS.size():
		return Vector2.INF
	var point := station(actor, anchor, float(actor.call("_target_combat_radius_gu", hit_target)), slot)
	return point if _snapshot_available(actor, point, snapshot) else Vector2.INF

static func goal(actor: CharacterBody2D, hit_target: Node2D, anchor: Vector2, slot: int, peers: Array) -> Vector2:
	return goal_with_snapshot(actor, hit_target, anchor, slot, snapshot_peers(actor, peers))

static func choose_with_snapshot(actor: CharacterBody2D, hit_target: Node2D, anchor: Vector2, current: Vector2, snapshot: Array, previous_slot: int) -> int:
	var target_radius: float = float(actor.call("_target_combat_radius_gu", hit_target))
	# These geometry inputs are immutable during one synchronous decision. Keep
	# the exact station arithmetic while avoiding eight repeated margin reads.
	var axial_distance := axis_distance(actor, target_radius)
	var best := -1
	var best_cost := INF
	var order: Array[int] = []
	if previous_slot >= 0 and previous_slot < DIRECTIONS.size():
		order.append(previous_slot)
	for slot: int in DIRECTIONS.size():
		if slot not in order:
			order.append(slot)
	for slot: int in order:
		var point: Vector2 = anchor + DIRECTIONS[slot] * (axial_distance if slot < 4 else Reach.HALF_EXTENT_GU)
		var cost := current.distance_squared_to(point)
		if slot == previous_slot:
			cost -= GU.EPSILON_GU
		# Candidate order and strict tie behavior are unchanged. A candidate
		# whose cost cannot beat the current winner cannot affect the result, so
		# skip its live eligibility/terrain/WORLD queries. All possible winners
		# still execute the complete fresh checks below.
		if not cost < best_cost:
			continue
		if not _snapshot_available(actor, point, snapshot):
			continue
		if not bool(actor.call("_hc_point_walkable", point)) or not bool(actor.call("_hc_world_between", point, anchor)):
			continue
		best = slot
		best_cost = cost
	return best

static func choose(actor: CharacterBody2D, hit_target: Node2D, anchor: Vector2, current: Vector2, peers: Array, previous_slot: int) -> int:
	return choose_with_snapshot(actor, hit_target, anchor, current, snapshot_peers(actor, peers), previous_slot)

static func _free_ray_extent(origin: Vector2, direction: Vector2, center: Vector2, radius: float, extent: float) -> float:
	var offset := origin - center
	var toward := offset.dot(direction)
	var clearance := offset.length_squared() - radius * radius
	if clearance <= 0.0:
		# Existing overlap can only leave the core, never cross its centre.
		return 0.0 if toward < 0.0 else extent
	if toward >= 0.0:
		return extent
	var square := direction.length_squared()
	var discriminant := toward * toward - square * clearance
	if discriminant < 0.0:
		return extent
	var entry := (-toward - sqrt(discriminant)) / square
	return minf(extent, maxf(0.0, entry - GU.EPSILON_GU / sqrt(square)))

static func contact_leg_with_snapshot(actor: CharacterBody2D, hit_target: Node2D, origin: Vector2, direction: Vector2, snapshot: Array) -> Vector2:
	var extent := 1.0
	var own_radius := float(actor.get("combat_radius_gu"))
	for record: Dictionary in snapshot:
		var other: Variant = record.get("node")
		if other == hit_target:
			continue
		var center: Vector2 = record.get("position", Vector2.INF)
		var radius := own_radius + float(record.get("radius", 0.0)) + margin_gu(actor) + margin_gu(other)
		# The envelope bound is exact for this one-unit candidate leg; only
		# then read live eligibility. The final motion predicate remains fresh.
		if not center.is_finite() or maxf(absf(center.x - origin.x), absf(center.y - origin.y)) > 1.0 + radius:
			continue
		if not is_instance_valid(other) or other.runtime_map_id != int(actor.get("runtime_map_id")) or not other.can_receive_damage() or not bool(other.behavior_profile.get("worldCollision", true)):
			continue
		extent = _free_ray_extent(origin, direction, center, radius, extent)
		if extent <= GU.EPSILON_GU:
			return Vector2.INF
	if hit_target is CharacterBody2D:
		var center: Vector2 = actor.call("_screen_position_px_to_ground_position_gu", hit_target.global_position)
		var radius := own_radius + float(actor.call("_target_combat_radius_gu", hit_target)) + margin_gu(actor) + margin_gu(hit_target)
		extent = _free_ray_extent(origin, direction, center, radius, extent)
	return origin + direction * extent if extent > GU.EPSILON_GU else Vector2.INF

static func contact_leg(actor: CharacterBody2D, hit_target: Node2D, origin: Vector2, direction: Vector2, peers: Array) -> Vector2:
	return contact_leg_with_snapshot(actor, hit_target, origin, direction, snapshot_peers(actor, peers))
