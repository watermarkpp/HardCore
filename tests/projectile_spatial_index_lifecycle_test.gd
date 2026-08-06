extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

var _index: SpatialIndexScript
var _enemies: Array[EnemyActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	var enemy := _make_enemy(1, Vector2(0.0, 0.0), 1)
	assert(
		_index.registered_actor_count() == 1,
		"spawn must register the enemy once"
	)
	assert(_index.index_register_count == 1)

	# Same-bucket movement must not change buckets.
	_index.update_actor(1, Vector2(1.5, 0.5))
	assert(
		_index.index_bucket_change_count == 0,
		"same-bucket movement must not re-home the entry"
	)
	assert(
		_index.index_update_check_count == 1,
		"update check must be counted"
	)

	# Cross-bucket movement must move the entry.
	_index.update_actor(1, Vector2(6.0, 6.0))
	assert(
		_index.index_bucket_change_count == 1,
		"cross-bucket movement must re-home the entry"
	)
	var candidates := _index.query_segment_candidates(
		1,
		Vector2(5.0, 5.0),
		Vector2(7.0, 7.0),
		1.0
	)
	assert(candidates.size() == 1, "moved enemy must be queryable in its new bucket")

	# Death (queue_free) must unregister on exit.
	enemy.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	assert(
		_index.registered_actor_count() == 0,
		"death must unregister the enemy"
	)
	assert(
		_index.index_unregister_count >= 1,
		"unregister counter must increase"
	)

	# WeakRef cleanup: a registered node freed without explicit unregister is
	# cleaned lazily on the next query (a node outside the tree never fires
	# _exit_tree, so the defensive stale path must handle it).
	var ghost := Node.new()
	_index.register(2, 1, Vector2.ZERO, 0.25, 2, ghost)
	ghost.free()
	var ghost_candidates := _index.query_segment_candidates(
		1,
		Vector2(-1.0, -1.0),
		Vector2(1.0, 1.0),
		1.0
	)
	assert(
		ghost_candidates.is_empty(),
		"dead weakref must be cleaned from the query result"
	)
	assert(
		_index.index_stale_cleanup_count >= 1,
		"stale cleanup counter must increase"
	)

	# Map registration and clear_map.
	var map_b_enemy := _make_enemy(2, Vector2(3.0, 3.0), 3)
	assert(_index.registered_actor_count() == 1)
	_index.clear_map(2)
	assert(
		_index.registered_actor_count() == 0,
		"clear_map must drop the map partition"
	)
	map_b_enemy.queue_free()
	_cleanup()
	await get_tree().process_frame
	await get_tree().physics_frame
	print(
		"PROJECTILE_SPATIAL_INDEX_LIFECYCLE_PASS registers=%d unregisters=%d updates=%d bucket_changes=%d stale=%d"
		% [
			_index.index_register_count,
			_index.index_unregister_count,
			_index.index_update_check_count,
			_index.index_bucket_change_count,
			_index.index_stale_cleanup_count,
		]
	)
	get_tree().quit(0)


func _make_enemy(
	map_id: int,
	center_ground_gu: Vector2,
	serial: int
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "life_%d" % serial, "hp": 100, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	enemy.configure_runtime_map_projection(
		map_id,
		Callable(self, "_ground_to_screen")
	)
	enemy.configure_spatial_index(_index, serial)
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	enemy.combat_radius_gu = 0.25
	add_child(enemy)
	_index.register(
		serial,
		map_id,
		center_ground_gu,
		0.25,
		serial,
		enemy
	)
	_enemies.append(enemy)
	return enemy


func _cleanup() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
