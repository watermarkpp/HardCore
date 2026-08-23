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

	var fire_wall_name := ProfessionRules.skill_display_name("wizard.fire_wall")
	game.player.current_mp = 100
	var caster: PlayerCharacter = game.player
	var target := _make_enemy(game, caster.global_position + Vector2(80, 0))
	game._set_magic_locked_target(target, true)
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
