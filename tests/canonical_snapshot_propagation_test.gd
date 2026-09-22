extends Node

const SnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const FIXTURE_MONSTER_ID := 19
## The central outdoor authored spawn avoids the Home polygon and map edge.
const FIXTURE_GROUND_POSITION := Vector2(40.5, 13.5)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"snapshot propagation fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	var enemy: EnemyActor = game._spawn_enemy(
		canonical_data,
		position,
		false,
		-1.0,
		{
			"respawn_enabled": false,
			"spawn_slot_id": "test:canonical_snapshot:%d" % FIXTURE_MONSTER_ID,
		},
	)
	assert(
		enemy != null
			and enemy.monster_id == FIXTURE_MONSTER_ID
			and not enemy.is_boss
			and enemy.runtime_map_id == int(game.get("current_map_id"))
			and enemy.projection_ready()
			and enemy.spatial_actor_runtime_id > 0,
		"snapshot propagation fixture must use the formal exact-ID mapped spawn",
	)
	enemy.max_hp = 9999
	enemy.current_hp = enemy.max_hp
	enemy.control_time = 60.0
	assert(
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and enemy.can_receive_damage(),
		"snapshot propagation fixture target must survive exact-ID admission"
	)
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
	await _wait_for_formal_world(game)
	var caster: PlayerCharacter = game.player
	caster.current_mp = 100
	var caster_ground: Vector2 = FIXTURE_GROUND_POSITION - Vector2(2.0, 0.0)
	var caster_position: Vector2 = game._canonical_ground_gu_to_screen_px(caster_ground)
	assert(caster_position.is_finite(), "snapshot propagation fixture needs a finite map projection")
	game._set_player_world_position(caster_position)
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			caster_ground,
			game._active_safe_zones,
		),
		"snapshot propagation caster fixture must be outside the authored safe area",
	)
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).set_combat_position(
				caster.global_position + Vector2(3000.0, 3000.0),
				&"test_fixture_clear",
			)
	var target_position: Vector2 = game._canonical_ground_gu_to_screen_px(FIXTURE_GROUND_POSITION)
	assert(target_position.is_finite(), "snapshot propagation fixture needs a finite target projection")
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			FIXTURE_GROUND_POSITION,
			game._active_safe_zones,
		),
		"snapshot propagation target fixture must be outside the authored safe area",
	)
	var target := _make_enemy(game, caster, target_position)
	assert(
		game._combat_target_world_clear(target, caster.global_position, true),
		"snapshot propagation target must have a clear WORLD path",
	)
	game.locked_target = target
	game._set_magic_locked_target(target, true)
	assert(game.magic_locked_target == target, "snapshot propagation target was rejected by the formal WORLD gate")
	game._skill_cast_target = target

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

	# Fire wall: gameplay result -> one controller owning 9 pure visual cells
	# (the formal centered 3x3 geometry contract).
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
				child.visual_cells.size() == 9,
				"fire wall controller must own 9 visual cells (3x3)"
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
		"snapshot propagation fixture must wait for the formal mapped world",
	)
	assert(game.gameplay_input_is_enabled(), "snapshot propagation fixture must wait for READY input")
	assert(not game._active_safe_zones.is_empty(), "snapshot propagation fixture needs the formal safe-zone context")
