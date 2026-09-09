extends Node

const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const FIXTURE_MONSTER_ID := 19
## The central outdoor authored spawn avoids the Home polygon and map edge.
const FIXTURE_GROUND_POSITION := Vector2(40.5, 13.5)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

var _projectile_created_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "道士"
	PlayerState.learned_skills = {"灵魂火符": 3}
	PlayerState.recalculate_stats()
	var definition := SkillDataLoaderScript.skill("taoist.soul_fire_talisman")
	var timing: Dictionary = definition.get("timing", {})
	assert(int(timing.get("body_cast_ms", 0)) == 600)
	assert(
		int(timing.get("effect_resolve_ms_from_cast_start", 0)) == 1200,
		"source effect timing must remain unchanged"
	)
	assert(str(definition.get("geometry", {}).get("shape", "")) == "projectile")
	assert(
		PlayerCharacter.SOUL_FIRE_TALISMAN_LAUNCH_TIMING_CONTRACT_ID
			== "skills.taoist.soul_fire_talisman.body_release_frame_launch.v1"
	)

	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.child_entered_tree.connect(func(node: Node) -> void:
		if node is SkillProjectile and (node as SkillProjectile).resolution_skill_id == "taoist.soul_fire_talisman":
			_projectile_created_count += 1
	)
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_formal_world(game)
	var caster: PlayerCharacter = game.player
	caster.current_mp = 999
	var caster_ground: Vector2 = FIXTURE_GROUND_POSITION - Vector2(2.0, 0.0)
	var caster_position: Vector2 = game._canonical_ground_gu_to_screen_px(caster_ground)
	assert(caster_position.is_finite(), "canonical soul-fire fixture needs a finite map projection")
	game._set_player_world_position(caster_position)
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			caster_ground,
			game._active_safe_zones,
		),
		"canonical soul-fire caster fixture must be outside the authored safe area",
	)
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).set_combat_position(
				caster.global_position + Vector2(3000.0, 3000.0),
				&"test_fixture_clear",
			)
	var target_position: Vector2 = game._canonical_ground_gu_to_screen_px(FIXTURE_GROUND_POSITION)
	assert(target_position.is_finite(), "canonical soul-fire fixture needs a finite target projection")
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			FIXTURE_GROUND_POSITION,
			game._active_safe_zones,
		),
		"canonical soul-fire target fixture must be outside the authored safe area",
	)
	var target := _make_enemy(game, caster, target_position)
	assert(
		game._combat_target_world_clear(target, caster.global_position, true),
		"canonical soul-fire target must have a clear WORLD path",
	)
	game._set_magic_locked_target(target, true)
	assert(game.magic_locked_target == target, "canonical soul-fire target was rejected by the formal WORLD gate")
	game._skill_cast_target = target
	await get_tree().process_frame

	var signal_releases: Array[String] = []
	caster.skill_requested.connect(func(skill_name: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void:
		if SkillDataLoaderScript.stable_skill_id(skill_name) == "taoist.soul_fire_talisman":
			signal_releases.append(skill_name)
	)
	assert(caster.request_skill("灵魂火符", target.get_instance_id()))
	await get_tree().create_timer(0.55).timeout
	assert(signal_releases.is_empty(), "projectile released before the 600 ms body release frame")
	assert(_projectile_created_count == 0)
	await get_tree().create_timer(0.10).timeout
	assert(signal_releases.size() == 1, "projectile was not released exactly once near 600 ms")
	assert(_projectile_created_count == 1, "GameRoot did not create exactly one SkillProjectile")
	await get_tree().create_timer(0.65).timeout
	assert(signal_releases.size() == 1, "1200 ms effect timing emitted a second skill release")
	assert(_projectile_created_count == 1, "1200 ms effect timing created a duplicate projectile")
	assert(caster._attack_timer > 0.0, "1500 ms total lock/cooldown ended too early")

	game.queue_free()
	await get_tree().process_frame
	print(
		"TAOIST_SOUL_FIRE_LAUNCH_TIMING_PASS: no early release; body-frame launch "
		+ "created exactly one production projectile; 1200 ms did not duplicate"
	)
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(not canonical_data.is_empty(), "canonical soul-fire target fixture is missing")
	var enemy: EnemyActor = game._spawn_enemy(
		canonical_data,
		position,
		false,
		-1.0,
		{
			"respawn_enabled": false,
			"spawn_slot_id": "test:taoist_soul_fire:%d" % FIXTURE_MONSTER_ID,
		},
	)
	assert(
		enemy != null
			and enemy.monster_id == FIXTURE_MONSTER_ID
			and not enemy.is_boss
			and enemy.runtime_map_id == int(game.get("current_map_id"))
			and enemy.projection_ready()
			and enemy.spatial_actor_runtime_id > 0,
		"canonical soul-fire fixture must use the formal exact-ID mapped spawn",
	)
	enemy.max_hp = 9999
	enemy.current_hp = enemy.max_hp
	enemy.control_time = 60.0
	assert(
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and enemy.can_receive_damage(),
		"canonical soul-fire target fixture is not damage-eligible"
	)
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
		"canonical soul-fire fixture must wait for the formal mapped world",
	)
	assert(game.gameplay_input_is_enabled(), "canonical soul-fire fixture must wait for READY input")
	assert(not game._active_safe_zones.is_empty(), "canonical soul-fire fixture needs the formal safe-zone context")
