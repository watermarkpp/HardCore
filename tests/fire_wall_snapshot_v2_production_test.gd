extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const FIXTURE_MONSTER_ID := 18
## The central outdoor authored spawn avoids the Home polygon and map edge.
const FIXTURE_GROUND_POSITION := Vector2(40.5, 13.5)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")


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

	var fire_wall_name := ProfessionRules.skill_display_name("wizard.fire_wall")
	var caster: PlayerCharacter = game.player
	caster.current_mp = 100
	var caster_ground: Vector2 = FIXTURE_GROUND_POSITION - Vector2(2.0, 0.0)
	var caster_position: Vector2 = game._canonical_ground_gu_to_screen_px(caster_ground)
	assert(caster_position.is_finite(), "fire wall snapshot fixture needs a finite map projection")
	game._set_player_world_position(caster_position)
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			caster_ground,
			game._active_safe_zones,
		),
		"fire wall snapshot caster fixture must be outside the authored safe area",
	)
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).set_combat_position(
				caster.global_position + Vector2(3000.0, 3000.0),
				&"test_fixture_clear",
			)
	var target_position: Vector2 = game._canonical_ground_gu_to_screen_px(FIXTURE_GROUND_POSITION)
	assert(target_position.is_finite(), "fire wall snapshot fixture needs a finite target projection")
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			FIXTURE_GROUND_POSITION,
			game._active_safe_zones,
		),
		"fire wall snapshot target fixture must be outside the authored safe area",
	)
	var target := _make_enemy(game, target_position)
	assert(
		game._combat_target_world_clear(target, caster.global_position, true),
		"fire wall snapshot target must have a clear WORLD path",
	)
	game._set_magic_locked_target(target, true)
	assert(game.magic_locked_target == target, "fire wall snapshot target was rejected by the formal WORLD gate")
	game._skill_cast_target = target
	var result: Dictionary = game._execute_canonical_skill(
		fire_wall_name,
		caster.global_position,
		Vector2.RIGHT,
		0,
		{"primary_stat_roll": 8}
	)
	assert(bool(result.get("accepted", false)), "fire wall must be accepted")
	var controller: FireWallFieldController
	var controller_snapshot: Dictionary = {}
	for child: Node in game.get_children():
		if child is FireWallFieldController:
			controller = child
			break
	assert(controller != null, "fire wall must create a field controller")
	assert(
		controller.visual_cells.size() == 4,
		"fire wall controller must own 4 visual cells"
	)
	controller_snapshot = controller.visual_cells[0].skill_footprint_snapshot
	_assert_v2(controller_snapshot, "fire wall canonical")
	for cell: GroundSkillVisualCell in controller.visual_cells:
		var cell_snapshot: Dictionary = cell.skill_footprint_snapshot
		assert(
			str(cell_snapshot.get("snapshot_id", ""))
			== str(controller_snapshot.get("snapshot_id", "")),
			"all fire wall visual cells must share one canonical snapshot id"
		)
		assert(
			int(cell_snapshot.get("runtime_map_id", -1))
			== int(controller_snapshot.get("runtime_map_id", -1)),
			"all fire wall visual cells must share the runtime map id"
		)
		assert(
			int(cell_snapshot.get("schema_version", 0))
			== Snapshot.SCHEMA_VERSION,
			"fire wall visual cells must be schema V2"
		)
	assert(
		Snapshot.legacy_snapshot_validation_count == legacy_before,
		"fire wall production must not touch the legacy counter"
	)

	target.queue_free()
	game.queue_free()
	await get_tree().process_frame
	print("FIRE_WALL_SNAPSHOT_V2_PRODUCTION_PASS")
	get_tree().quit(0)


func _assert_v2(snapshot: Dictionary, label: String) -> void:
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
		snapshot.get("runtime_map_id", -1) is int
		and int(snapshot.get("runtime_map_id", -1)) >= 0,
		"%s must carry a typed runtime map id" % label
	)
	assert(
		not str(snapshot.get("snapshot_id", "")).is_empty(),
		"%s must carry a snapshot id" % label
	)


func _make_enemy(game: Node, screen_position: Vector2) -> EnemyActor:
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"fire wall snapshot fixture canonical monster ID=%d must resolve"
		% FIXTURE_MONSTER_ID
	)
	var enemy: EnemyActor = game._spawn_enemy(
		canonical_data,
		screen_position,
		false,
		-1.0,
		{
			"respawn_enabled": false,
			"spawn_slot_id": "test:fire_wall_snapshot:%d" % FIXTURE_MONSTER_ID,
		},
	)
	assert(
		enemy != null
			and enemy.monster_id == FIXTURE_MONSTER_ID
			and not enemy.is_boss
			and enemy.runtime_map_id == int(game.get("current_map_id"))
			and enemy.projection_ready()
			and enemy.spatial_actor_runtime_id > 0,
		"fire wall snapshot fixture must use the formal exact-ID mapped spawn",
	)
	# Keep the production snapshot test independent of authored combat stats.
	enemy.max_hp = 999
	enemy.current_hp = enemy.max_hp
	enemy.attack_min = 1
	enemy.attack_max = 1
	enemy.combat_radius_gu = 0.2
	return enemy


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
		"fire wall snapshot fixture must wait for the formal mapped world",
	)
	assert(game.gameplay_input_is_enabled(), "fire wall snapshot fixture must wait for READY input")
	assert(not game._active_safe_zones.is_empty(), "fire wall snapshot fixture needs the formal safe-zone context")
