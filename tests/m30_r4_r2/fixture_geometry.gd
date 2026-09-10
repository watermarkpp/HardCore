extends RefCounted

const Rules := preload("res://scripts/world_spatial_rules.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Neighbor := preload("res://scripts/monster_neighbor_step_policy.gd")
const SourceGame := preload("res://scripts/game_root.gd")

static func stable_reference(game: Node, point: Vector2, radius: float) -> Vector2:
	# Independent frozen reference formula: compare with, not delegate to, new core.
	if not point.is_finite() or not is_finite(radius) or radius < 0.0:
		return Vector2.INF
	if int(game.current_map_id) != int(SourceGame.BICH_RUNTIME_MAP_ID):
		return point
	if not game._safe_zone_context_is_valid():
		return Vector2.INF
	return Rules.project_outside_safe_zones_ground_gu(
		point, game._active_safe_zones, radius + float(SourceGame.SAFE_ZONE_ACTOR_PADDING_GU)
	)

static func describe_collision(hit: KinematicCollision2D) -> Dictionary:
	var collider: Object = hit.get_collider()
	return {
		"collider_id": collider.get_instance_id() if is_instance_valid(collider) else 0,
		"path": str((collider as Node).get_path()) if collider is Node and (collider as Node).is_inside_tree() else "",
		"class": collider.get_class() if is_instance_valid(collider) else "",
		"layer": (collider as CollisionObject2D).collision_layer if collider is CollisionObject2D else -1,
		"normal_px": [hit.get_normal().x, hit.get_normal().y],
	}

static func body_check(body: PhysicsBody2D, origin_px: Vector2, motion_px: Vector2, margin: float) -> Dictionary:
	var transform: Transform2D = body.global_transform
	transform.origin = origin_px
	var hit := KinematicCollision2D.new()
	# recovery_as_collision also reports initial overlap; a centre ray cannot.
	var blocked: bool = body.test_move(transform, motion_px, hit, margin, true)
	return {"clear": not blocked, "collision": describe_collision(hit) if blocked else {}}

static func corridor(game: Node, probe: EnemyActor, center: Vector2, direction_index: int) -> Dictionary:
	var direction := Vector2.from_angle(TAU * float(direction_index) / 8.0)
	var start := center + direction * 2.0
	var preferred: float = probe._hc_preferred(game.player)
	var endpoint := center + direction * preferred
	var result := {"dir": direction_index, "start": [start.x, start.y], "end": [endpoint.x, endpoint.y], "clear": false, "reason": ""}
	if preferred >= 2.0 - 0.01:
		result.reason = "no_half_step_for_this_body"
		return result
	# Match point occupancy, footprint safety, cell-edge traversal AND real bodies.
	for i: int in range(9):
		var point := start.lerp(endpoint, float(i) / 8.0)
		var stable: Vector2 = stable_reference(game, point, probe.combat_radius_gu)
		if not stable.is_finite() or not stable.is_equal_approx(point):
			result.reason = "safe_zone_footprint_padding"
			result["at"] = [point.x, point.y]
			result["projected"] = [stable.x, stable.y] if stable.is_finite() else []
			return result
		if not probe._hc_point_walkable(point):
			result.reason = "navigation_point"
			return result
		if not probe._hc_world_between(center, point):
			result.reason = "world_los"
			return result
	var a := Neighbor.temporary_cell(start)
	var b := Neighbor.temporary_cell(endpoint)
	if a != b and not Terrain.can_traverse_neighbor(probe._terrain_navigation_context, a, b, probe.combat_radius_gu):
		result.reason = "cell_edge"
		return result
	var start_px: Vector2 = game._canonical_ground_gu_to_screen_px(start)
	var end_px: Vector2 = game._canonical_ground_gu_to_screen_px(endpoint)
	var initial := body_check(probe, start_px, Vector2.ZERO, probe.safe_margin)
	if not bool(initial.get("clear", false)):
		result.reason = "initial_body_overlap"
		result["physics"] = initial
		return result
	var sweep := body_check(probe, start_px, end_px - start_px, probe.safe_margin)
	if not bool(sweep.get("clear", false)):
		result.reason = "body_sweep"
		result["physics"] = sweep
		return result
	result["clear"] = true
	return result
