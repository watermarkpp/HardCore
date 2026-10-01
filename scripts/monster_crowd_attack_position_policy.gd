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

static func available(actor: CharacterBody2D, hit_target: Node2D, point: Vector2, peers: Array) -> bool:
	for other: Variant in peers:
		if not is_instance_valid(other) or other == actor:
			continue
		var radius: float = float(actor.get("combat_radius_gu")) + other.combat_radius_gu
		# Coarse candidates contain distant identities. The unchanged exact
		# overlap predicate excludes them before their eligibility work. Pose
		# is read live in this synchronous query, never retained across calls.
		var other_distance: float = other.spatial_index_position().distance_squared_to(point)
		if other_distance >= radius * radius - GU.EPSILON_GU:
			continue
		if not other.can_receive_damage() or not bool(other.behavior_profile.get("worldCollision", true)):
			continue
		# Settled physical stations remain occupied, including a corner waiting
		# outside reach. Unsettled bodies use actual distance below; an earlier
		# selected goal must not reserve the space needed to leave a jam.
		var anchor: Vector2 = actor.call("_screen_position_px_to_ground_position_gu", hit_target.global_position)
		var owns_goal: bool = other.target == hit_target and other._hc_surround_anchor == anchor and other._hc_surround_slot >= 0 and other._hc_surround_goal.is_finite()
		# A front actor aligning elsewhere is a live route obstacle, but must
		# not permanently deny the destination it is leaving. Arrived/waiting
		# bodies cover both this point and their own actual goal.
		var goal_covers: bool = owns_goal and other._hc_surround_goal.distance_squared_to(point) < radius * radius - GU.EPSILON_GU
		if owns_goal and other.spatial_index_position().distance_squared_to(other._hc_surround_goal) <= GU.EPSILON_GU * GU.EPSILON_GU:
			if goal_covers:
				return false
		elif goal_covers or not owns_goal:
			# Two unsettled bodies cannot deny each other's only destination:
			# selection follows the nearer actual body, not the earlier goal.
			# The loser still participates in every live locomotion core check.
			var own_distance: float = actor.call("spatial_index_position").distance_squared_to(point)
			if other_distance < own_distance or (other_distance == own_distance and other.spatial_actor_runtime_id < int(actor.get("spatial_actor_runtime_id"))):
				return false
	return true

static func axis_ready(actor: CharacterBody2D, hit_target: Node2D, anchor: Vector2, slot: int, peers: Array) -> bool:
	for other: Variant in peers:
		if not is_instance_valid(other) or other == actor or not other.can_receive_damage() or not bool(other.behavior_profile.get("worldCollision", true)) or not other._source176_ordinary_melee():
			continue
		var point := station(other, anchor, other._target_combat_radius_gu(hit_target), slot)
		if other.spatial_index_position().distance_squared_to(point) <= GU.EPSILON_GU * GU.EPSILON_GU:
			return true
	return false

static func owns_station(actor: CharacterBody2D, hit_target: Node2D, anchor: Vector2, other: Variant) -> bool:
	if not is_instance_valid(other) or other == actor or other.target != hit_target or other._hc_surround_slot < 0 or other._hc_surround_anchor != anchor or not other._hc_surround_goal.is_finite():
		return false
	if not other.can_receive_damage() or not bool(other.behavior_profile.get("worldCollision", true)) or not other._source176_ordinary_melee():
		return false
	var expected_scope := [actor.get("runtime_map_id"), int(actor.get_meta("zone_generation", -1)), other._hc_life(other), hit_target.get_instance_id(), other._hc_life(hit_target)]
	return other._hc_surround_scope == expected_scope

static func axis_pending(actor: CharacterBody2D, hit_target: Node2D, anchor: Vector2, slot: int, peers: Array) -> bool:
	# A missing or foreign-life claimant cannot defer a corner forever.
	for other: Variant in peers:
		if is_instance_valid(other) and other._hc_surround_slot == slot and owns_station(actor, hit_target, anchor, other):
			return true
	return false

static func has_station_owner(actor: CharacterBody2D, hit_target: Node2D, anchor: Vector2, peers: Array) -> bool:
	for other: Variant in peers:
		if owns_station(actor, hit_target, anchor, other):
			return true
	return false

static func waiting_station(actor: CharacterBody2D, anchor: Vector2, current: Vector2) -> Vector2:
	# One body diameter beyond the attack box clears the front row's swept
	# body. This is a navigation point, with no reservation or attack grant.
	var extent := 1.0 + 2.0 * float(actor.get("combat_radius_gu")) + 2.0 * margin_gu(actor) + GU.EPSILON_GU
	var offset := current - anchor
	var distance := maxf(absf(offset.x), absf(offset.y))
	if distance >= extent - GU.EPSILON_GU:
		return current
	return anchor + offset * (extent / distance) if distance > GU.EPSILON_GU else anchor + Vector2.RIGHT * extent

static func goal(actor: CharacterBody2D, hit_target: Node2D, anchor: Vector2, slot: int, peers: Array) -> Vector2:
	var point := station(actor, anchor, float(actor.call("_target_combat_radius_gu", hit_target)), slot)
	if slot >= 4 and float(actor.get("combat_radius_gu")) * 2.0 + GU.EPSILON_GU >= Reach.HALF_EXTENT_GU:
		var direction: Vector2 = DIRECTIONS[slot]
		var x_slot := 0 if direction.x > 0.0 else 2
		var y_slot := 1 if direction.y > 0.0 else 3
		var wait_x := axis_pending(actor, hit_target, anchor, x_slot, peers) and not axis_ready(actor, hit_target, anchor, x_slot, peers)
		var wait_y := axis_pending(actor, hit_target, anchor, y_slot, peers) and not axis_ready(actor, hit_target, anchor, y_slot, peers)
		if wait_x or wait_y:
			point += direction * (2.0 * margin_gu(actor) + GU.EPSILON_GU)
	return point

static func choose(actor: CharacterBody2D, hit_target: Node2D, anchor: Vector2, current: Vector2, peers: Array, previous_slot: int) -> int:
	var target_radius: float = float(actor.call("_target_combat_radius_gu", hit_target))
	var inside := maxf(absf(current.x - anchor.x), absf(current.y - anchor.y)) <= Reach.HALF_EXTENT_GU + GU.EPSILON_GU
	var best := -1
	var best_cost := INF
	if previous_slot >= 0 and previous_slot < DIRECTIONS.size():
		var previous := goal(actor, hit_target, anchor, previous_slot, peers)
		if available(actor, hit_target, previous, peers) and bool(actor.call("_hc_point_walkable", previous)) and bool(actor.call("_hc_world_between", previous, anchor)):
			# An outer detour keeps its destination. Once physically in the
			# attack box, the nearer vacant entrance wins; a distant old claim
			# must not trap a corner waiting for an axis nobody can approach.
			if not inside:
				return previous_slot
			best = previous_slot
			best_cost = current.distance_squared_to(station(actor, anchor, target_radius, previous_slot))
			if best_cost <= GU.EPSILON_GU * GU.EPSILON_GU:
				return previous_slot
	for slot: int in DIRECTIONS.size():
		if not inside and best >= 0 and best < 4 and slot >= 4:
			break
		var point := goal(actor, hit_target, anchor, slot, peers)
		if not available(actor, hit_target, point, peers) or not bool(actor.call("_hc_point_walkable", point)) or not bool(actor.call("_hc_world_between", point, anchor)):
			continue
		# Fill axial passages before admitting the corner bodies which can
		# close them. A front actor already in reach aligns to its nearest slot.
		var cost := current.distance_squared_to(station(actor, anchor, target_radius, slot))
		if cost < best_cost:
			best = slot
			best_cost = cost
	return best

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

static func contact_leg(actor: CharacterBody2D, hit_target: Node2D, origin: Vector2, direction: Vector2, peers: Array) -> Vector2:
	# Propose a complete eight-way waypoint at the first live body envelope.
	# The movement owner still checks the whole leg against WORLD/body core;
	# this grants no permission, shortens no accepted step and caches no pose.
	var extent := 1.0
	var own_radius := float(actor.get("combat_radius_gu"))
	for other: Variant in peers:
		if not is_instance_valid(other) or other == actor or other == hit_target or not other is CharacterBody2D:
			continue
		var radius := own_radius + float(other.combat_radius_gu) + margin_gu(actor) + margin_gu(other)
		var center: Vector2 = other.spatial_index_position()
		if maxf(absf(center.x - origin.x), absf(center.y - origin.y)) > 1.0 + radius:
			continue
		if other.runtime_map_id != int(actor.get("runtime_map_id")) or not other.can_receive_damage() or not bool(other.behavior_profile.get("worldCollision", true)):
			continue
		extent = _free_ray_extent(origin, direction, center, radius, extent)
		if extent <= GU.EPSILON_GU:
			return Vector2.INF
	if hit_target is CharacterBody2D:
		var center: Vector2 = actor.call("_screen_position_px_to_ground_position_gu", hit_target.global_position)
		var radius := own_radius + float(actor.call("_target_combat_radius_gu", hit_target)) + margin_gu(actor) + margin_gu(hit_target)
		extent = _free_ray_extent(origin, direction, center, radius, extent)
	return origin + direction * extent if extent > GU.EPSILON_GU else Vector2.INF
