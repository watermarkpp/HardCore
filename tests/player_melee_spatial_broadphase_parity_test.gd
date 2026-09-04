extends Node

const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")

const RUNTIME_MAP_ID := 9102


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var context := Snapshot.make_local_delta_context(
		Callable(GroundUnitSpace, "ground_delta_gu_to_screen_delta_px")
	)
	var index := SpatialIndex.new()
	var enemies: Array[EnemyActor] = []
	var positions: Array[Vector2] = [
		Vector2(0.75, 0.0),
		Vector2(1.75, 0.0),
		Vector2(0.75, 0.75),
		Vector2(3.0, 0.0),
		Vector2(-1.0, 0.0),
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

	var release := Snapshot.create_directed_rectangle(
		"player.melee.normal",
		"melee.release.1",
		Vector2.ZERO,
		Vector2.RIGHT,
		2.5,
		1.0,
		0.0,
		0.0,
		0.0,
		"",
		context,
	)
	assert(release.is_read_only())
	var release_bounds: Rect2 = Snapshot.ground_aabb(release).get(
		"bounds_ground_gu", Rect2()
	)
	var broadphase_candidates: Array = []
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		release_bounds,
		broadphase_candidates,
	)
	var broadphase_ids := _melee_ids(release, broadphase_candidates)
	var naive_ids := _melee_ids(release, enemies)
	assert(broadphase_ids == naive_ids, "melee broadphase changed target parity")
	assert(broadphase_ids.size() == 3)

	index.update_actor(1, Vector2(4.0, 0.0))
	var moved_candidates: Array = []
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		release_bounds,
		moved_candidates,
	)
	assert(not moved_candidates.has(enemies[0]), "moved target stayed in old bucket")

	var replacement := EnemyActor.new()
	replacement.current_hp = 100
	replacement.max_hp = 100
	replacement.combat_radius_gu = 0.25
	replacement.global_position = Vector2(0.75, 0.0)
	replacement._dying = false
	replacement._death_pending = false
	index.unregister(1)
	index.register(
		101,
		RUNTIME_MAP_ID,
		Vector2(0.75, 0.0),
		replacement.combat_radius_gu,
		1,
		replacement,
	)
	var replacement_candidates: Array = []
	index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		release_bounds,
		replacement_candidates,
	)
	assert(replacement_candidates.has(replacement))
	assert(not replacement_candidates.has(enemies[0]))

	index.clear_map(RUNTIME_MAP_ID)
	var after_clear: Array = []
	index.query_enemy_nodes_aabb_into(RUNTIME_MAP_ID, release_bounds, after_clear)
	assert(after_clear.is_empty(), "melee map clear left stale candidates")
	for enemy: EnemyActor in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	if is_instance_valid(replacement):
		replacement.queue_free()
	print("PLAYER_MELEE_SPATIAL_BROADPHASE_PARITY_PASS exact=1 move=1 replacement=1")
	get_tree().quit(0)


func _melee_ids(snapshot: Dictionary, candidates: Array) -> Array[int]:
	var ids: Array[int] = []
	for value: Variant in candidates:
		if value is EnemyActor and Snapshot.intersects_target_combat_footprint_ground_gu(
			snapshot,
			(value as EnemyActor).global_position,
			(value as EnemyActor).combat_radius_gu,
		):
			ids.append((value as EnemyActor).get_instance_id())
	return ids
