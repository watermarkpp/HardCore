extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var legacy_before := Snapshot.legacy_snapshot_validation_count
	var enemy: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(21), Vector2.ZERO, false
	)
	enemy.attack_range_gu = 2.0
	var player_node := PlayerCharacter.new()
	player_node.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		Vector2(2, 0)
	)
	add_child(player_node)

	enemy._deal_melee_hit(player_node, 1)
	var melee: Dictionary = enemy._last_attack_footprint_snapshot
	_assert_v2(enemy, melee, "enemy melee")
	var area: Dictionary = enemy._create_area_attack_footprint_snapshot()
	_assert_v2(enemy, area, "enemy area attack")
	var boss: Dictionary = enemy._create_boss_skill_footprint_snapshot(
		{"shape": "circle", "radius": 100.0},
		"boss:v2:1"
	)
	_assert_v2(enemy, boss, "enemy boss skill")

	# STRICT consumer accepts the same-map snapshot and rejects a cross-map one.
	assert(
		enemy._snapshot_strict_ok(melee),
		"same-map enemy snapshot must pass the strict consumer"
	)
	var cross_context := Snapshot.make_absolute_runtime_context(
		enemy.runtime_map_id + 1,
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(self, "_ground_to_screen")
	)
	cross_context["expected_runtime_map_id"] = enemy.runtime_map_id + 1
	assert(
		not bool(Snapshot.validate_for_consumer(
			melee,
			cross_context,
			Snapshot.VALIDATION_STRICT_V2
		).get("valid", false)),
		"cross-map enemy snapshot must be rejected"
	)
	assert(
		Snapshot.legacy_snapshot_validation_count == legacy_before,
		"enemy production must not touch the legacy counter"
	)

	player_node.queue_free()
	enemy.queue_free()
	game.queue_free()
	await get_tree().process_frame
	print("ENEMY_SNAPSHOT_V2_PRODUCTION_PASS")
	get_tree().quit(0)


func _assert_v2(enemy: EnemyActor, snapshot: Dictionary, label: String) -> void:
	assert(
		int(snapshot.get("schema_version", 0)) == Snapshot.SCHEMA_VERSION,
		"%s must be schema V2" % label
	)
	assert(
		str(snapshot.get("coordinate_space", ""))
		== Snapshot.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU,
		"%s must be runtime-map absolute" % label
	)
	assert(
		int(snapshot.get("runtime_map_id", -1)) == enemy.runtime_map_id,
		"%s must carry the enemy's own runtime map id" % label
	)
	assert(
		(snapshot.get("projection_origin_ground_gu", Vector2.INF) as Vector2)
		.is_finite(),
		"%s must carry a finite projection origin" % label
	)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
