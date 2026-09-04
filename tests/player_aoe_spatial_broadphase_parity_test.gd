extends Node

const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")

const RUNTIME_MAP_ID := 9101


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var context := Snapshot.make_local_delta_context(
		Callable(GroundUnitSpace, "ground_delta_gu_to_screen_delta_px")
	)
	var index := SpatialIndex.new()
	var enemies: Array[EnemyActor] = []
	var positions: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(2.8, 0.0),
		Vector2(0.0, 2.0),
		Vector2(5.0, 0.0),
	]
	for index_value: int in range(positions.size()):
		var enemy := EnemyActor.new()
		enemy.current_hp = 100
		enemy.max_hp = 100
		enemy.combat_radius_gu = 0.25
		enemy.global_position = positions[index_value]
		enemy._dying = false
		enemy._death_pending = false
		enemies.append(enemy)
		index.register(
			index_value + 1,
			RUNTIME_MAP_ID,
			positions[index_value],
			enemy.combat_radius_gu,
			index_value + 1,
			enemy,
		)

	var radial := Snapshot.create_circle(
		"player.aoe.circle",
		"aoe.circle.release",
		Vector2.ZERO,
		1.5,
		32,
		context,
	)
	assert(radial.is_read_only())
	var radial_bounds: Rect2 = Snapshot.ground_aabb(radial).get(
		"bounds_ground_gu", Rect2()
	)
	var radial_candidates: Array = []
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		radial_bounds,
		radial_candidates,
	)
	var radial_ids := _exact_ids_in_group_order(radial, radial_candidates)
	var radial_naive := _exact_ids_in_group_order(radial, enemies)
	assert(radial_ids == radial_naive, "radial broadphase changed group-order parity")
	assert(radial_ids == [enemies[0].get_instance_id(), enemies[1].get_instance_id()])

	var cells := Snapshot.create_cell_union(
		"player.aoe.cells",
		"aoe.cells.release",
		Vector2.ZERO,
		[Vector2i(2, 0), Vector2i(0, 2)],
		context,
	)
	var cell_bounds: Rect2 = Snapshot.ground_aabb(cells).get(
		"bounds_ground_gu", Rect2()
	)
	var cell_candidates: Array = []
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		cell_bounds,
		cell_candidates,
	)
	var cell_ids := _exact_ids_sorted_by_instance(cells, cell_candidates)
	var cell_naive := _exact_ids_sorted_by_instance(cells, enemies)
	assert(cell_ids == cell_naive, "CELL_UNION broadphase changed ID parity")
	assert(not cell_ids.is_empty(), "CELL_UNION fixture must select a target")

	var line := Snapshot.create_swept_capsule_path(
		"player.aoe.line",
		"aoe.line.release",
		Vector2.ZERO,
		Vector2(4.0, 0.0),
		0.5,
		8,
		"",
		-1,
		context,
	)
	assert(line.is_read_only())
	var line_candidates: Array = []
	index.query_enemy_nodes_segment_into(
		RUNTIME_MAP_ID,
		Vector2.ZERO,
		Vector2(4.0, 0.0),
		0.0,
		line_candidates,
	)
	var line_ids := _exact_ids_sorted_by_line(
		line,
		line_candidates,
		Vector2.ZERO,
		Vector2.RIGHT,
	)
	var line_naive := _exact_ids_sorted_by_line(
		line,
		enemies,
		Vector2.ZERO,
		Vector2.RIGHT,
	)
	assert(line_ids == line_naive, "continuous line broadphase changed distance parity")
	assert(line_ids.size() == 3, "continuous line fixture must select three targets")

	var wrong_map: Array = []
	index.query_enemy_nodes_aabb_into(RUNTIME_MAP_ID + 1, radial_bounds, wrong_map)
	assert(wrong_map.is_empty(), "AOE query leaked another runtime map")
	index.unregister(3)
	var after_unregister: Array = []
	index.query_enemy_nodes_aabb_into(RUNTIME_MAP_ID, cell_bounds, after_unregister)
	assert(not after_unregister.has(enemies[2]))
	index.clear_map(RUNTIME_MAP_ID)
	var after_clear: Array = []
	index.query_enemy_nodes_aabb_into(RUNTIME_MAP_ID, radial_bounds, after_clear)
	assert(after_clear.is_empty(), "map clear left AOE candidates")
	for enemy: EnemyActor in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	print("PLAYER_AOE_SPATIAL_BROADPHASE_PARITY_PASS radial=1 cell_union=1 map_scope=1")
	get_tree().quit(0)


func _exact_ids_in_group_order(
	snapshot: Dictionary,
	candidates: Array,
) -> Array[int]:
	var ids: Array[int] = []
	for value: Variant in candidates:
		if value is EnemyActor and Snapshot.intersects_target_combat_footprint_ground_gu(
			snapshot,
			(value as EnemyActor).global_position,
			(value as EnemyActor).combat_radius_gu,
		):
			ids.append((value as EnemyActor).get_instance_id())
	return ids


func _exact_ids_sorted_by_instance(
	snapshot: Dictionary,
	candidates: Array,
) -> Array[int]:
	var ids := _exact_ids_in_group_order(snapshot, candidates)
	ids.sort()
	return ids


func _exact_ids_sorted_by_line(
	snapshot: Dictionary,
	candidates: Array,
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
) -> Array[int]:
	var ordered: Array[Dictionary] = []
	for value: Variant in candidates:
		if not value is EnemyActor:
			continue
		var enemy := value as EnemyActor
		if not Snapshot.intersects_target_combat_footprint_ground_gu(
			snapshot,
			enemy.global_position,
			enemy.combat_radius_gu,
		):
			continue
		ordered.append({
			"id": enemy.get_instance_id(),
			"distance": (enemy.global_position - origin_ground_gu).dot(
				direction_ground_gu
			),
		})
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_distance := float(left.get("distance", INF))
		var right_distance := float(right.get("distance", INF))
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return int(left.get("id", 0)) < int(right.get("id", 0))
	)
	var ids: Array[int] = []
	for record: Dictionary in ordered:
		ids.append(int(record.get("id", 0)))
	return ids
