extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession(ProfessionRules.profession_display_name("taoist"))
	PlayerState.level = 35
	PlayerState.learned_skills = {
		ProfessionRules.skill_display_name("taoist.summon_skeleton"): 3,
		ProfessionRules.skill_display_name("taoist.summon_divine_beast"): 3,
	}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: PlayerCharacter = game.player

	var skeleton := SummonActor.new()
	skeleton.setup(player, ProfessionRules.skill_display_name("taoist.summon_skeleton"), 30, 3, "taoist.summon_skeleton", 35)
	skeleton.configure_runtime_map_projection(
		1,
		Callable(self, "_test_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)
	skeleton.global_position = player.global_position
	game.add_child(skeleton)
	await get_tree().process_frame
	assert(skeleton.skill_id == "taoist.summon_skeleton" and skeleton.attack_type == "physical")
	assert(skeleton.summon_level == 3 and skeleton.summon_exp_level == 3 and skeleton.summon_count == 1)
	assert(skeleton.lifetime_seconds == 864000.0 and skeleton.owner_death_rule == "expire")
	assert(skeleton.reject_when_owner_has_slave and not skeleton.recall_existing_on_create_failure)
	assert(skeleton.state == SummonActor.SummonState.FOLLOW_OWNER)
	var spatial := skeleton.spatial_contract_snapshot()
	assert(spatial.contract_id == SummonActor.SPATIAL_CONTRACT_ID)
	assert(spatial.unit_contract_id == GroundUnit.CONTRACT_ID)
	assert(spatial.move_speed_gu_per_sec > 0.0)
	for sample_index: int in range(32):
		var ground_direction := Vector2.from_angle(
			TAU * float(sample_index) / 32.0
		)
		var screen_delta_px := GroundUnit.ground_delta_gu_to_screen_delta_px(
			ground_direction
		)
		var screen_velocity_px := skeleton._screen_velocity_toward_delta_px(
			screen_delta_px
		)
		var observed_ground_velocity := (
			GroundUnit.screen_delta_px_to_ground_delta_gu(screen_velocity_px)
		)
		assert(is_equal_approx(
			observed_ground_velocity.length(), skeleton.move_speed_gu_per_sec
		))

	var enemy := EnemyActor.new()
	enemy.setup({"name": "summon-test-target", "hp": 9999, "attackMin": 1, "attackMax": 1, "level": 1}, player, false)
	enemy.control_time = 60.0
	enemy.global_position = (
		skeleton.global_position
		+ GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(
			skeleton.attack_range_gu + 2.0, 0.0
		))
	)
	game.add_child(enemy)
	skeleton._current_target = enemy
	skeleton._physics_process(0.016)
	assert(skeleton.state == SummonActor.SummonState.CHASE_TARGET)
	enemy.global_position = (
		skeleton.global_position
		+ GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(0.5, 0.0))
	)
	var enemy_hp := enemy.current_hp
	skeleton._attack_timer = 0.0
	skeleton._physics_process(0.016)
	assert(skeleton.state == SummonActor.SummonState.ATTACK_TARGET and enemy.current_hp == enemy_hp)
	assert(skeleton._pending_attack_target == enemy, "召唤物攻击未等待客户端命中帧")
	skeleton._physics_process(0.50)
	assert(enemy.current_hp < enemy_hp, "召唤物客户端命中帧没有结算伤害")
	assert(skeleton.last_attack_type == "physical")
	skeleton.global_position = (
		player.global_position
		+ GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(
			skeleton.teleport_range_gu + 1.0, 0.0
		))
	)
	skeleton._physics_process(0.016)
	assert(skeleton.distance_gu_to_screen_position_px(player.global_position) < 2.0)
	assert(skeleton.state == SummonActor.SummonState.RETURN_TO_OWNER)
	skeleton.remaining_lifetime = 0.001
	skeleton._physics_process(0.016)
	assert(skeleton.state == SummonActor.SummonState.EXPIRED or skeleton.is_queued_for_deletion())

	var divine_beast := SummonActor.new()
	divine_beast.setup(player, ProfessionRules.skill_display_name("taoist.summon_divine_beast"), 30, 3, "taoist.summon_divine_beast", 35)
	assert(divine_beast.skill_id == "taoist.summon_divine_beast" and divine_beast.attack_type == "fire")
	assert(divine_beast.lifetime_seconds == 864000.0 and divine_beast.recall_existing_on_create_failure)
	assert(divine_beast.max_hp == 448 and skeleton.max_hp == 392)
	assert(divine_beast.attack_range_gu > skeleton.attack_range_gu)
	assert(skeleton.maximum_pet_level == 7 and divine_beast.maximum_pet_level == 7)
	divine_beast.free()
	print("SUMMON_ACTOR_STATE_MACHINE_PASS: levels, attacks, ten-day life, owner follow, recall")
	get_tree().quit(0)
