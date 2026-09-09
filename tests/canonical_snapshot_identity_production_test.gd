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
	PlayerState.level = 50
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {"雷电术": 3, "火墙": 3}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_formal_world(game)
	var legacy_before := Snapshot.legacy_snapshot_validation_count
	var caster: PlayerCharacter = game.player
	caster.current_mp = 100
	var caster_ground: Vector2 = FIXTURE_GROUND_POSITION - Vector2(2.0, 0.0)
	var caster_position: Vector2 = game._canonical_ground_gu_to_screen_px(caster_ground)
	assert(caster_position.is_finite(), "canonical snapshot fixture needs a finite map projection")
	game._set_player_world_position(caster_position)
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			caster_ground,
			game._active_safe_zones,
		),
		"canonical snapshot caster fixture must be outside the authored safe area",
	)
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = caster.global_position + Vector2(3000.0, 3000.0)

	# Lightning chain: gameplay snapshot -> visual metadata.
	var target_position: Vector2 = game._canonical_ground_gu_to_screen_px(FIXTURE_GROUND_POSITION)
	assert(target_position.is_finite(), "canonical snapshot fixture needs a finite target projection")
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			FIXTURE_GROUND_POSITION,
			game._active_safe_zones,
		),
		"canonical snapshot target fixture must be outside the authored safe area",
	)
	var target := _make_enemy(game, target_position)
	assert(
		game._combat_target_world_clear(target, caster.global_position, true),
		"canonical snapshot target must have a clear WORLD path",
	)
	game.locked_target = target
	game._set_magic_locked_target(target, true)
	assert(game.magic_locked_target == target, "canonical snapshot target was rejected by the formal WORLD gate")
	game._skill_cast_target = target
	var lightning_name := ProfessionRules.skill_display_name("wizard.lightning")
	var lightning: Dictionary = game._execute_canonical_skill(
		lightning_name,
		caster.global_position,
		Vector2.RIGHT,
		999999
	)
	assert(bool(lightning.get("accepted", false)), "lightning must be accepted")
	var visual_snapshot_id := ""
	for child: Node in game.get_children():
		if (
			child is CasterSkillVisualEffect
			and child.skill_id == "wizard.lightning"
		):
			visual_snapshot_id = str(
				child.snapshot_visual_projection_metadata().get(
					"snapshot_id", ""
				)
			)
			break
	assert(
		not visual_snapshot_id.is_empty(),
		"lightning visual must carry the release snapshot id"
	)

	# Fire wall chain: controller + 4 visual cells share one canonical snapshot.
	game._set_magic_locked_target(target, true)
	game._skill_cast_target = target
	var fire_wall_name := ProfessionRules.skill_display_name("wizard.fire_wall")
	var fire_wall: Dictionary = game._execute_canonical_skill(
		fire_wall_name,
		caster.global_position,
		Vector2.RIGHT,
		0,
		{"primary_stat_roll": 8}
	)
	assert(bool(fire_wall.get("accepted", false)), "fire wall must be accepted")
	var controller_snapshot: Dictionary = {}
	var ground_ids: Array[String] = []
	for child: Node in game.get_children():
		if child is FireWallFieldController:
			controller_snapshot = (
				child.visual_cells[0].skill_footprint_snapshot
			)
			for cell: GroundSkillVisualCell in child.visual_cells:
				ground_ids.append(str(
					cell.skill_footprint_snapshot.get("snapshot_id", "")
				))
		elif (
			child is GroundSkillEffect
			and child.skill_id == "wizard.fire_wall"
		):
			ground_ids.append(str(
				child.skill_footprint_snapshot.get("snapshot_id", "")
			))
	assert(
		ground_ids.size() >= 4,
		"fire wall chain must expose at least 4 consumers"
	)
	for snapshot_id: String in ground_ids:
		assert(
			snapshot_id == str(controller_snapshot.get("snapshot_id", "")),
			"fire wall consumers must share the canonical snapshot id"
		)
	_assert_identity(controller_snapshot, "fire wall canonical")
	assert(
		str(controller_snapshot.get("snapshot_id", "")) != visual_snapshot_id,
		"different releases must not share a snapshot id"
	)
	assert(
		Snapshot.legacy_snapshot_validation_count == legacy_before,
		"canonical production chain must not touch the legacy counter"
	)

	target.queue_free()
	game.queue_free()
	await get_tree().process_frame
	print("CANONICAL_SNAPSHOT_IDENTITY_PRODUCTION_PASS")
	get_tree().quit(0)


func _assert_identity(snapshot: Dictionary, label: String) -> void:
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
		(snapshot.get("projection_origin_ground_gu", Vector2.INF) as Vector2)
		.is_finite(),
		"%s must carry a finite projection origin" % label
	)


func _make_enemy(game: Node, screen_position: Vector2) -> EnemyActor:
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"canonical snapshot fixture canonical monster ID=%d must resolve"
		% FIXTURE_MONSTER_ID
	)
	var enemy: EnemyActor = game._spawn_enemy(
		canonical_data,
		screen_position,
		false,
		-1.0,
		{
			"respawn_enabled": false,
			"spawn_slot_id": "test:canonical_snapshot_identity:%d" % FIXTURE_MONSTER_ID,
		},
	)
	assert(
		enemy != null
			and enemy.monster_id == FIXTURE_MONSTER_ID
			and not enemy.is_boss
			and enemy.runtime_map_id == int(game.get("current_map_id"))
			and enemy.projection_ready()
			and enemy.spatial_actor_runtime_id > 0,
		"canonical snapshot fixture must use the formal exact-ID mapped spawn",
	)
	# Keep the identity chain independent of authored combat stats while
	# retaining the production target's durable test HP.
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
		"canonical snapshot fixture must wait for the formal mapped world",
	)
	assert(not game._active_safe_zones.is_empty(), "canonical snapshot fixture needs the formal safe-zone context")
