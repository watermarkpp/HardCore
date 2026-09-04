extends Node

const SnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "propagation目标",
		"hp": 9999,
		"attackMin": 1,
		"attackMax": 1,
		"level": 1,
		"anti_magic_points": 0,
		"magic_defense_min": 0,
		"magic_defense_max": 0,
	}, caster, false)
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	return enemy


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {"雷电术": 3, "火墙": 3}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var caster: PlayerCharacter = game.player
	caster.current_mp = 100
	var target := _make_enemy(game, caster, caster.global_position + Vector2(80, 0))
	game.locked_target = target

	# Lightning: gameplay result -> CasterSkillVisualEffect chain.
	var lightning: Dictionary = game._execute_canonical_skill(
		"雷电术",
		caster.global_position,
		Vector2.RIGHT,
		999999
	)
	assert(bool(lightning.get("accepted", false)), "lightning must be accepted")
	var found_lightning_visual := false
	var lightning_metadata: Dictionary = {}
	for child: Node in game.get_children():
		if (
			child is CasterSkillVisualEffect
			and child.skill_id == "wizard.lightning"
		):
			lightning_metadata = child.snapshot_visual_projection_metadata()
			found_lightning_visual = true
	assert(found_lightning_visual, "lightning must create a formal visual effect")
	assert(
		not str(lightning_metadata.get("snapshot_id", "")).is_empty(),
		"lightning visual must carry a snapshot id"
	)
	assert(
		int(lightning_metadata.get("snapshot_schema_version", 0))
		== SnapshotScript.SCHEMA_VERSION,
		"lightning visual snapshot must be schema V2"
	)
	assert(
		str(lightning_metadata.get("snapshot_coordinate_space", ""))
		== SnapshotScript.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU,
		"lightning visual snapshot must declare runtime-map absolute space"
	)
	assert(
		str(lightning_metadata.get("snapshot_runtime_map_id", ""))
		== str(game.current_map_id),
		"lightning visual snapshot runtime_map_id must match the active map"
	)

	# Fire wall: gameplay result -> one controller owning 4 pure visual cells.
	game._set_magic_locked_target(target, true)
	game._skill_cast_target = target
	var fire_wall: Dictionary = game._execute_canonical_skill(
		"火墙",
		caster.global_position,
		Vector2.RIGHT,
		0,
		{"primary_stat_roll": 8}
	)
	assert(bool(fire_wall.get("accepted", false)), "fire wall must be accepted")
	var found_controller := false
	var fire_wall_snapshot: Dictionary = {}
	var fire_wall_ground_snapshot_ids: Array[String] = []
	for child: Node in game.get_children():
		if child is FireWallFieldController:
			found_controller = true
			assert(
				child.visual_cells.size() == 4,
				"fire wall controller must own 4 visual cells"
			)
			fire_wall_snapshot = child.visual_cells[0].skill_footprint_snapshot
			for cell: GroundSkillVisualCell in child.visual_cells:
				assert(
					str(cell.skill_footprint_snapshot.get("snapshot_id", ""))
					== str(fire_wall_snapshot.get("snapshot_id", "")),
					"all fire wall visual cells must share one snapshot id"
				)
	assert(found_controller, "fire wall must create a field controller")
	assert(
		fire_wall_ground_snapshot_ids.is_empty(),
		"Q2-C: fire wall must not spawn standalone GroundSkillEffect cells"
	)
	assert(
		not fire_wall_snapshot.is_empty()
		and bool(SnapshotScript.validate(fire_wall_snapshot).get("valid", false)),
		"fire wall canonical snapshot must be a valid V2 absolute snapshot: %s"
		% SnapshotScript.validate(fire_wall_snapshot).get("reason", "")
	)
	assert(
		str(fire_wall_snapshot.get("runtime_map_id", ""))
		== str(game.current_map_id),
		"fire wall snapshot runtime_map_id must match the active map"
	)
	assert(
		str(fire_wall_snapshot.get("snapshot_id", ""))
		!= str(lightning_metadata.get("snapshot_id", "")),
		"different releases must not share a snapshot id"
	)

	game.queue_free()
	print(
		"CANONICAL_SNAPSHOT_PROPAGATION_PASS snapshot_id=%s schema=%d space=%s map=%s" % [
			str(fire_wall_snapshot.get("snapshot_id", "")),
			int(fire_wall_snapshot.get("schema_version", 0)),
			str(fire_wall_snapshot.get("coordinate_space", "")),
			str(fire_wall_snapshot.get("runtime_map_id", "")),
		]
	)
	get_tree().quit(0)
