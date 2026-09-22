extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const FIXTURE_MONSTER_ID := 19

var _index: SpatialIndexScript
var _enemies: Array[EnemyActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	var enemy := _make_enemy(Vector2(0.5, 0.5), 1)
	assert(_query_near(Vector2(0.5, 0.5)).size() == 1)

	# Knockback pushes the enemy across buckets via set_combat_position in the
	# same transaction; the next projectile query in the same frame must find it.
	var knockback_delta_gu := Vector2(8.0, 0.0)
	enemy.set_combat_position(
		enemy.global_position
		+ GroundUnit.ground_delta_gu_to_screen_delta_px(knockback_delta_gu),
		&"knockback"
	)
	var target_ground := GroundUnit.screen_delta_px_to_ground_delta_gu(
		enemy.global_position
	)
	var candidates := _index.query_segment_candidates(
		1,
		target_ground - Vector2(1, 1),
		target_ground + Vector2(1, 1),
		1.0
	)
	assert(
		candidates.size() == 1,
		"knockback target must be discoverable by a same-frame projectile query"
	)
	var old_ground := GroundUnit.screen_delta_px_to_ground_delta_gu(
		enemy.global_position
	) - knockback_delta_gu
	assert(
		_index.query_segment_candidates(
			1,
			old_ground - Vector2(1, 1),
			old_ground + Vector2(1, 1),
			1.0
		).is_empty(),
		"knockback target must not remain in the old bucket"
	)
	_cleanup()
	await get_tree().process_frame
	print("PROJECTILE_SPATIAL_INDEX_SAME_FRAME_KNOCKBACK_PASS")
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
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"knockback fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	enemy.setup(canonical_data, null, false)
	assert(
		enemy.monster_id == FIXTURE_MONSTER_ID and not enemy.is_boss,
		"knockback fixture must remain an ordinary exact-ID target"
	)
	enemy.max_hp = 100
	enemy.current_hp = enemy.max_hp
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)
	enemy.configure_spatial_index(_index, serial)
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	enemy.combat_radius_gu = 0.25
	add_child(enemy)
	assert(
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and enemy.can_receive_damage(),
		"knockback fixture target must survive exact-ID admission"
	)
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
