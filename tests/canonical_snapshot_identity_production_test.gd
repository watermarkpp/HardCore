extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")


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
	var caster: PlayerCharacter = game.player
	caster.current_mp = 100

	# Lightning chain: gameplay snapshot -> visual metadata.
	var target := _make_enemy(game, caster.global_position + Vector2(80, 0))
	game.locked_target = target
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
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "t", "hp": 999, "attackMin": 1, "attackMax": 1, "level": 1},
		game.player,
		false
	)
	enemy.global_position = screen_position
	enemy.combat_radius_gu = 0.2
	game.add_child(enemy)
	return enemy
