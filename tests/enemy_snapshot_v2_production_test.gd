extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

## Authored world_bich_province monster_id=21 spawn tile [28, 66].
const FIXTURE_ENEMY_GROUND_POSITION := Vector2(28.5, 66.5)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_formal_world(game)

	var legacy_before := Snapshot.legacy_snapshot_validation_count
	var enemy_position: Vector2 = game._canonical_ground_gu_to_screen_px(
		FIXTURE_ENEMY_GROUND_POSITION
	)
	var target_ground: Vector2 = FIXTURE_ENEMY_GROUND_POSITION + Vector2(2.0, 0.0)
	var target_position: Vector2 = game._canonical_ground_gu_to_screen_px(target_ground)
	assert(enemy_position.is_finite() and target_position.is_finite(), "enemy snapshot fixture needs a finite map projection")
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			FIXTURE_ENEMY_GROUND_POSITION,
			game._active_safe_zones,
		)
			and not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
				target_ground,
				game._active_safe_zones,
			),
		"enemy snapshot fixture must exercise an authored outdoor point"
	)
	var enemy: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(21),
		enemy_position,
		false,
		-1.0,
		{"respawn_enabled": false}
	)
	assert(
		enemy != null
			and enemy.runtime_map_id == int(game.get("current_map_id"))
			and enemy.projection_ready()
			and enemy.spatial_actor_runtime_id > 0,
		"enemy snapshot fixture must use the formal mapped spawn"
	)
	enemy.attack_range_gu = 2.0
	var player_node: PlayerCharacter = PlayerCharacter.new()
	add_child(player_node)
	player_node.set_physics_process(false)
	player_node.global_position = target_position

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


func _wait_for_formal_world(game: Node) -> void:
	var deadline_ms: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline_ms:
		var current_map_id: int = int(game.get("current_map_id"))
		var input_enabled: bool = bool(game.call("gameplay_input_is_enabled"))
		if current_map_id >= 0 and input_enabled:
			break
		await get_tree().process_frame
	assert(
		int(game.get("current_map_id")) == GameData.service_runtime_map_id(0),
		"enemy snapshot fixture must wait for the formal mapped world"
	)
	assert(not game._active_safe_zones.is_empty(), "enemy snapshot fixture needs the formal safe-zone context")
