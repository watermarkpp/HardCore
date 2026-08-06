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
	var enemy := _make_enemy(Vector2(0.5, 0.5), 1)
	var bucket_a := _query_near(Vector2(0.5, 0.5))
	assert(bucket_a.size() == 1, "enemy must be registered in bucket A")

	# Same-frame teleport to bucket B WITHOUT running enemy physics.
	enemy.set_combat_position(
		GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(9.5, 9.5)),
		&"test_teleport"
	)
	var bucket_b := _query_near(Vector2(9.5, 9.5))
	var bucket_a_after := _query_near(Vector2(0.5, 0.5))
	assert(
		bucket_b.size() == 1,
		"teleported enemy must appear as a candidate in bucket B same frame"
	)
	assert(
		bucket_a_after.size() == 0,
		"teleported enemy must no longer be a valid candidate in bucket A"
	)
	assert(
		_index.index_bucket_change_count >= 1,
		"same-frame teleport must move the index entry"
	)
	_cleanup()
	await get_tree().process_frame
	print("PROJECTILE_SPATIAL_INDEX_SAME_FRAME_TELEPORT_PASS")
	get_tree().quit(0)


func _query_near(center_ground_gu: Vector2) -> Array[Dictionary]:
	return _index.query_segment_candidates(
		1,
		center_ground_gu - Vector2(1, 1),
		center_ground_gu + Vector2(1, 1),
		1.0
	)


func _make_enemy(center_ground_gu: Vector2, serial: int) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "teleport_%d" % serial, "hp": 100, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	enemy.configure_runtime_map_projection(
		1,
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
		1,
		center_ground_gu,
		0.25,
		serial,
		enemy,
		Callable(enemy, "spatial_index_position")
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
