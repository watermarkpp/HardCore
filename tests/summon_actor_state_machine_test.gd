extends Node


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
	skeleton.global_position = player.global_position
	game.add_child(skeleton)
	await get_tree().process_frame
	assert(skeleton.skill_id == "taoist.summon_skeleton" and skeleton.attack_type == "physical")
	assert(skeleton.summon_level == 3 and skeleton.summon_exp_level == 3 and skeleton.summon_count == 1)
	assert(skeleton.lifetime_seconds == 864000.0 and skeleton.owner_death_rule == "expire")
	assert(skeleton.reject_when_owner_has_slave and not skeleton.recall_existing_on_create_failure)
	assert(skeleton.state == SummonActor.SummonState.FOLLOW_OWNER)

	var enemy := EnemyActor.new()
	enemy.setup({"name": "summon-test-target", "hp": 9999, "attackMin": 1, "attackMax": 1, "level": 1}, player, false)
	enemy.control_time = 60.0
	enemy.global_position = skeleton.global_position + Vector2(skeleton.attack_range + 30.0, 0)
	game.add_child(enemy)
	skeleton._current_target = enemy
	skeleton._physics_process(0.016)
	assert(skeleton.state == SummonActor.SummonState.CHASE_TARGET)
	enemy.global_position = skeleton.global_position + Vector2(10.0, 0)
	var enemy_hp := enemy.current_hp
	skeleton._attack_timer = 0.0
	skeleton._physics_process(0.016)
	assert(skeleton.state == SummonActor.SummonState.ATTACK_TARGET and enemy.current_hp < enemy_hp)
	assert(skeleton.last_attack_type == "physical")
	skeleton.global_position = player.global_position + Vector2(skeleton.teleport_range + 20.0, 0)
	skeleton._physics_process(0.016)
	assert(skeleton.global_position.distance_to(player.global_position) < 100.0)
	assert(skeleton.state == SummonActor.SummonState.RETURN_TO_OWNER)
	skeleton.remaining_lifetime = 0.001
	skeleton._physics_process(0.016)
	assert(skeleton.state == SummonActor.SummonState.EXPIRED or skeleton.is_queued_for_deletion())

	var divine_beast := SummonActor.new()
	divine_beast.setup(player, ProfessionRules.skill_display_name("taoist.summon_divine_beast"), 30, 3, "taoist.summon_divine_beast", 35)
	assert(divine_beast.skill_id == "taoist.summon_divine_beast" and divine_beast.attack_type == "fire")
	assert(divine_beast.lifetime_seconds == 864000.0 and divine_beast.recall_existing_on_create_failure)
	assert(divine_beast.max_hp > skeleton.max_hp and divine_beast.attack_range > skeleton.attack_range)
	divine_beast.free()
	print("SUMMON_ACTOR_STATE_MACHINE_PASS: levels, attacks, ten-day life, owner follow, recall")
	get_tree().quit(0)
