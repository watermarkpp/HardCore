extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const RuntimeCombatSpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const WorldSpatialRulesScript := preload(
	"res://scripts/world_spatial_rules.gd"
)


class ExternalAttackPolicyEnemy:
	extends EnemyActor

	var allow_external_attack := true

	func accepts_external_attack_from(_attacker: Node) -> bool:
		return allow_external_attack


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
	skeleton.set_physics_process(false)
	await get_tree().process_frame
	assert(skeleton.skill_id == "taoist.summon_skeleton" and skeleton.attack_type == "physical")
	assert(skeleton.summon_level == 3 and skeleton.summon_exp_level == 3 and skeleton.summon_count == 1)
	assert(skeleton.lifetime_seconds == 864000.0 and skeleton.owner_death_rule == "expire")
	assert(skeleton.reject_when_owner_has_slave and not skeleton.recall_existing_on_create_failure)
	assert(skeleton.state == SummonActor.SummonState.FOLLOW_OWNER)
	skeleton.current_hp = skeleton.max_hp - 7
	skeleton.reset_performance_diagnostics_for_tests()
	assert(skeleton.restore_health(5) == 5)
	assert(skeleton.current_hp == skeleton.max_hp - 2)
	assert(
		int(skeleton.performance_diagnostics().custom_draw_request_count) == 1,
		"effective summon healing must redraw the HP bar in the same frame"
	)
	assert(skeleton.restore_health(99) == 2)
	assert(skeleton.current_hp == skeleton.max_hp)
	assert(skeleton.restore_health(1) == 0)
	assert(
		int(skeleton.performance_diagnostics().custom_draw_request_count) == 2,
		"full-HP healing must not enqueue a redundant redraw"
	)
	var dead_heal_fixture := SummonActor.new()
	dead_heal_fixture.setup(
		player,
		"dead-heal-fixture",
		1,
		0,
		"taoist.summon_skeleton",
		35
	)
	dead_heal_fixture.take_damage(dead_heal_fixture.current_hp)
	dead_heal_fixture.reset_performance_diagnostics_for_tests()
	assert(dead_heal_fixture.state == SummonActor.SummonState.DEAD)
	assert(dead_heal_fixture.restore_health(50) == 0)
	assert(
		int(dead_heal_fixture.performance_diagnostics().custom_draw_request_count)
			== 0
	)
	dead_heal_fixture.free()
	var expired_heal_fixture := SummonActor.new()
	expired_heal_fixture.setup(
		player,
		"expired-heal-fixture",
		1,
		0,
		"taoist.summon_skeleton",
		35
	)
	expired_heal_fixture._set_state(SummonActor.SummonState.EXPIRED)
	expired_heal_fixture.current_hp -= 1
	expired_heal_fixture.reset_performance_diagnostics_for_tests()
	assert(expired_heal_fixture.restore_health(50) == 0)
	assert(
		int(expired_heal_fixture.performance_diagnostics().custom_draw_request_count)
			== 0
	)
	expired_heal_fixture.free()
	var spatial := skeleton.spatial_contract_snapshot()
	assert(spatial.contract_id == SummonActor.SPATIAL_CONTRACT_ID)
	assert(spatial.unit_contract_id == GroundUnit.CONTRACT_ID)
	assert(spatial.move_speed_gu_per_sec > 0.0)
	assert(
		spatial.attack_footprint_contract_id
			== "skills.summon.attack_release_directed_gu.v2"
	)
	assert(is_equal_approx(float(spatial.attack_effect_length_gu), 1.5))
	assert(is_equal_approx(float(spatial.attack_effect_width_gu), 1.0))
	assert(is_equal_approx(float(spatial.attack_interval_seconds), 1.2))
	var summon_source := FileAccess.get_file_as_string(
		"res://scripts/summon_actor.gd"
	)
	assert(
		not summon_source.contains('get_nodes_in_group("enemies")'),
		"summon acquisition must never restore a full enemy-group scan"
	)
	assert(
		not summon_source.contains("get_property_list()"),
		"summon acquisition must never reflect every target property list"
	)
	skeleton.reset_performance_diagnostics_for_tests()
	assert(skeleton._nearest_enemy() == null)
	var missing_index_diagnostics := skeleton.performance_diagnostics()
	assert(int(missing_index_diagnostics.target_acquire_fail_closed_count) == 1)
	assert(
		missing_index_diagnostics.target_acquire_last_rejection_reason
			== "spatial_index_unavailable"
	)
	var combat_index := RuntimeCombatSpatialIndexScript.new()
	skeleton.configure_spatial_index(combat_index)
	var missing_projection := SummonActor.new()
	missing_projection.setup(
		player,
		ProfessionRules.skill_display_name("taoist.summon_skeleton"),
		30,
		3,
		"taoist.summon_skeleton",
		35
	)
	missing_projection.configure_runtime_map_projection(
		1, Callable(self, "_test_ground_to_screen")
	)
	missing_projection.configure_spatial_index(combat_index)
	assert(missing_projection._nearest_enemy() == null)
	var missing_projection_diagnostics := (
		missing_projection.performance_diagnostics()
	)
	assert(
		missing_projection_diagnostics.target_acquire_last_rejection_reason
			== "screen_to_ground_projection_unavailable"
	)
	missing_projection.free()
	var original_movement_facing := player.movement_facing
	var original_attack_facing := player.facing
	player.movement_facing = Vector2.RIGHT
	player.facing = Vector2.UP
	skeleton.global_position = player.global_position
	skeleton._current_target = null
	skeleton._target_acquire_remaining = 1.0
	var single_skeleton_formation := skeleton.rest_formation_contract_snapshot()
	assert(
		single_skeleton_formation.contract_id
			== "skills.summon.owner_formation_slots.v1"
	)
	assert(single_skeleton_formation.typed_slot_id == "skeleton")
	assert(
		single_skeleton_formation.direction_source
			== "owner_movement_facing"
	)
	for single_formation_frame: int in range(120):
		skeleton._physics_process(1.0 / 60.0)
	assert(
		skeleton.distance_gu_to_screen_position_px(
			single_skeleton_formation.desired_screen_position_px
		) <= float(single_skeleton_formation.settle_distance_gu)
	)
	var formation_beast := SummonActor.new()
	formation_beast.setup(
		player,
		ProfessionRules.skill_display_name("taoist.summon_divine_beast"),
		30,
		3,
		"taoist.summon_divine_beast",
		35
	)
	formation_beast.configure_runtime_map_projection(
		1,
		Callable(self, "_test_ground_to_screen"),
		GroundUnit.screen_delta_px_to_ground_delta_gu
	)
	formation_beast.configure_spatial_index(combat_index)
	formation_beast.global_position = player.global_position
	game.add_child(formation_beast)
	formation_beast.set_physics_process(false)
	var skeleton_formation := skeleton.rest_formation_contract_snapshot()
	var beast_formation := formation_beast.rest_formation_contract_snapshot()
	assert(
		skeleton_formation.collision_contract_id
			== "skills.summon.collision.player_pet_passthrough.v1"
	)
	assert(skeleton_formation.typed_slot_id == "skeleton")
	assert(beast_formation.typed_slot_id == "divine_beast")
	assert(
		skeleton_formation.desired_screen_position_px
			!= beast_formation.desired_screen_position_px
	)
	for formation_frame: int in range(120):
		skeleton._physics_process(1.0 / 60.0)
		formation_beast._physics_process(1.0 / 60.0)
	var rested_separation_gu := skeleton.distance_gu_to_screen_position_px(
		formation_beast.global_position
	)
	assert(
		rested_separation_gu
			>= (
				skeleton.combat_radius_gu
				+ formation_beast.combat_radius_gu
				+ 0.2
			),
		"dual pets must settle at distinct non-overlapping typed slots"
	)
	assert(
		skeleton.distance_gu_to_screen_position_px(
			skeleton_formation.desired_screen_position_px
		) <= float(skeleton_formation.settle_distance_gu)
	)
	assert(
		formation_beast.distance_gu_to_screen_position_px(
			beast_formation.desired_screen_position_px
		) <= float(beast_formation.settle_distance_gu)
	)
	assert(
		float(skeleton_formation.expected_dual_separation_gu)
			> skeleton.combat_radius_gu
				+ formation_beast.combat_radius_gu
				+ 0.2
	)
	assert(
		bool(skeleton_formation.player_pass_through)
		and not bool(skeleton_formation.pet_hard_collision_enabled)
	)
	assert(
		bool(skeleton_formation.world_collision_preserved)
		and bool(skeleton_formation.enemy_collision_preserved)
	)
	assert(
		player.collision_layer == WorldSpatialRulesScript.PLAYER_LAYER
		and (
			player.collision_mask & WorldSpatialRulesScript.PLAYER_LAYER
		) == 0,
		"player movement mask must continue to pass through pet bodies"
	)
	var skeleton_before_attack_facing := (
		skeleton.rest_formation_contract_snapshot()
	)
	var beast_before_attack_facing := (
		formation_beast.rest_formation_contract_snapshot()
	)
	var skeleton_anchor_before_attack_facing: Vector2 = (
		skeleton_before_attack_facing.desired_screen_position_px
	)
	var beast_anchor_before_attack_facing: Vector2 = (
		beast_before_attack_facing.desired_screen_position_px
	)
	player.facing = Vector2.LEFT
	var skeleton_after_attack_facing := (
		skeleton.rest_formation_contract_snapshot()
	)
	var beast_after_attack_facing := (
		formation_beast.rest_formation_contract_snapshot()
	)
	assert(
		(skeleton_after_attack_facing.desired_screen_position_px as Vector2
		).is_equal_approx(
			skeleton_anchor_before_attack_facing
		)
	)
	assert(
		(beast_after_attack_facing.desired_screen_position_px as Vector2
		).is_equal_approx(
			beast_anchor_before_attack_facing
		)
	)
	var far_recall_position := (
		player.global_position
		+ GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(
			skeleton.teleport_range_gu + 1.0,
			0.0
		))
	)
	skeleton.global_position = far_recall_position
	formation_beast.global_position = far_recall_position
	skeleton._target_acquire_remaining = 1.0
	formation_beast._target_acquire_remaining = 1.0
	skeleton._physics_process(1.0 / 60.0)
	formation_beast._physics_process(1.0 / 60.0)
	assert(skeleton.global_position.is_equal_approx(
		skeleton_anchor_before_attack_facing
	))
	assert(formation_beast.global_position.is_equal_approx(
		beast_anchor_before_attack_facing
	))
	assert(skeleton.global_position != formation_beast.global_position)
	var skeleton_ground_for_formation_combat := (
		GroundUnit.screen_delta_px_to_ground_delta_gu(skeleton.global_position)
	)
	var formation_combat_enemy := _make_indexed_enemy(
		game,
		player,
		combat_index,
		1,
		900,
		900,
		skeleton_ground_for_formation_combat + Vector2(3.0, 0.0)
	)
	skeleton._current_target = formation_combat_enemy
	skeleton._physics_process(1.0 / 60.0)
	assert(skeleton.state == SummonActor.SummonState.CHASE_TARGET)
	assert(skeleton.velocity.length_squared() > 0.0)
	combat_index.unregister(900)
	formation_combat_enemy.free()
	skeleton._current_target = null
	formation_beast.free()
	player.movement_facing = original_movement_facing
	player.facing = original_attack_facing
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
	enemy.set_physics_process(false)
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_test_ground_to_screen"),
		GroundUnit.screen_delta_px_to_ground_delta_gu
	)
	enemy.configure_spatial_index(combat_index, 300)
	combat_index.register(
		300,
		1,
		enemy.spatial_index_position(),
		enemy.combat_radius_gu,
		30,
		enemy,
		Callable(enemy, "spatial_index_position")
	)
	var cross_map_enemy := _make_indexed_enemy(
		game,
		player,
		combat_index,
		2,
		10,
		1,
		GroundUnit.screen_delta_px_to_ground_delta_gu(skeleton.global_position)
	)
	var mismatched_map_enemy := _make_indexed_enemy(
		game,
		player,
		combat_index,
		2,
		11,
		1,
		GroundUnit.screen_delta_px_to_ground_delta_gu(skeleton.global_position)
	)
	combat_index.unregister(11)
	combat_index.register(
		11,
		1,
		mismatched_map_enemy.spatial_index_position(),
		mismatched_map_enemy.combat_radius_gu,
		1,
		mismatched_map_enemy,
		Callable(mismatched_map_enemy, "spatial_index_position")
	)
	var decoys: Array[Node2D] = []
	for decoy_index: int in range(256):
		var decoy := Node2D.new()
		decoy.add_to_group("enemies")
		game.add_child(decoy)
		decoys.append(decoy)
	assert(get_tree().get_nodes_in_group("enemies").size() >= 256)
	skeleton.reset_performance_diagnostics_for_tests()
	assert(skeleton._nearest_enemy() == enemy)
	var indexed_diagnostics := skeleton.performance_diagnostics()
	assert(int(indexed_diagnostics.target_candidate_count) == 2)
	assert(int(indexed_diagnostics.target_acquire_fail_closed_count) == 0)
	assert(
		indexed_diagnostics.target_acquisition_contract_id
			== "skills.summon.target_acquisition.shared_spatial_index.v1"
	)
	for decoy: Node2D in decoys:
		decoy.free()
	assert(is_instance_valid(cross_map_enemy))
	var skeleton_ground_gu := GroundUnit.screen_delta_px_to_ground_delta_gu(
		skeleton.global_position
	)
	var boundary_distance_gu := (
		skeleton.aggro_radius_gu
		+ skeleton.combat_radius_gu
		+ enemy.combat_radius_gu
		- GroundUnit.EPSILON_GU
	)
	enemy.set_combat_position(
		GroundUnit.ground_delta_gu_to_screen_delta_px(
			skeleton_ground_gu + Vector2(boundary_distance_gu, 0.0)
		),
		&"summon_boundary_test"
	)
	assert(skeleton._nearest_enemy() == enemy)
	var stable_order_enemy := _make_indexed_enemy(
		game,
		player,
		combat_index,
		1,
		200,
		20,
		skeleton_ground_gu + Vector2(2.0, 0.0)
	)
	var actor_id_enemy := _make_indexed_enemy(
		game,
		player,
		combat_index,
		1,
		100,
		20,
		skeleton_ground_gu + Vector2(2.0, 0.0)
	)
	var stable_priority_enemy := _make_indexed_enemy(
		game,
		player,
		combat_index,
		1,
		500,
		10,
		skeleton_ground_gu + Vector2(2.0, 0.0)
	)
	assert(skeleton._nearest_enemy() == stable_priority_enemy)
	combat_index.unregister(500)
	assert(skeleton._nearest_enemy() == actor_id_enemy)
	combat_index.unregister(100)
	assert(skeleton._nearest_enemy() == stable_order_enemy)
	var rejecting_enemy := _make_policy_enemy(
		game,
		player,
		combat_index,
		1,
		600,
		1,
		skeleton_ground_gu + Vector2(0.25, 0.0),
		false
	)
	assert(
		skeleton._nearest_enemy() == stable_order_enemy,
		"summon acquisition must skip enemies rejecting external pet attacks"
	)
	combat_index.unregister(600)
	rejecting_enemy.free()
	var release_policy_enemy := _make_policy_enemy(
		game,
		player,
		combat_index,
		1,
		601,
		1,
		skeleton_ground_gu + Vector2(0.5, 0.0),
		true
	)
	var policy_hp_before := release_policy_enemy.current_hp
	skeleton._clear_pending_attack()
	skeleton._begin_attack(release_policy_enemy)
	release_policy_enemy.allow_external_attack = false
	skeleton._release_pending_attack()
	assert(
		release_policy_enemy.current_hp == policy_hp_before,
		"delayed summon release must recheck external-attack eligibility"
	)
	assert(skeleton._pending_attack_target == null)
	combat_index.unregister(601)
	release_policy_enemy.free()
	skeleton._current_target = enemy
	skeleton._physics_process(0.016)
	assert(skeleton.state == SummonActor.SummonState.CHASE_TARGET)
	enemy.global_position = (
		skeleton.global_position
		+ GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(0.5, 0.0))
	)
	var enemy_hp := enemy.current_hp
	skeleton._attack_timer = 0.0
	skeleton.apply_stealth(10.0, "buff.taoist.mass_invisibility")
	skeleton._update_stealth_visual()
	assert(is_equal_approx(skeleton.modulate.a, 1.0))
	assert(is_equal_approx(skeleton._sprite.self_modulate.a, 0.60))
	skeleton._physics_process(0.016)
	assert(skeleton.state == SummonActor.SummonState.ATTACK_TARGET and enemy.current_hp == enemy_hp)
	assert(not skeleton.is_stealthed(), "entering attack must break summon stealth immediately")
	assert(skeleton.stealth_buff_id.is_empty())
	assert(is_equal_approx(skeleton._sprite.self_modulate.a, 1.0))
	assert(skeleton._pending_attack_target == enemy, "召唤物攻击未等待客户端命中帧")
	assert(skeleton.last_attack_footprint_snapshot.shape_type == "directed_rectangle")
	assert(is_equal_approx(
		float(skeleton.last_attack_footprint_snapshot.effect_length_gu), 1.5
	))
	assert(is_equal_approx(
		float(skeleton.last_attack_footprint_snapshot.effect_width_gu), 1.0
	))
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
	assert(divine_beast.max_hp == 840 and skeleton.max_hp == 392)
	assert(divine_beast.attack_range_gu > skeleton.attack_range_gu)
	assert(is_equal_approx(divine_beast.attack_range_gu, 3.0))
	assert(is_equal_approx(divine_beast.attack_interval, 1.2))
	var beast_spatial := divine_beast.spatial_contract_snapshot()
	assert(is_equal_approx(float(beast_spatial.attack_effect_length_gu), 3.0))
	assert(is_equal_approx(float(beast_spatial.attack_effect_width_gu), 1.0))
	assert(skeleton.maximum_pet_level == 7 and divine_beast.maximum_pet_level == 7)
	divine_beast.free()
	print("SUMMON_ACTOR_STATE_MACHINE_PASS: levels, attacks, ten-day life, owner follow, recall")
	get_tree().quit(0)


func _make_indexed_enemy(
	parent: Node,
	player: PlayerCharacter,
	index: RuntimeCombatSpatialIndexScript,
	map_id: int,
	actor_runtime_id: int,
	stable_combat_order: int,
	ground_position_gu: Vector2
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "summon-index-target-%d" % actor_runtime_id,
		"hp": 9999,
		"attackMin": 1,
		"attackMax": 1,
		"level": 1,
	}, player, false)
	enemy.control_time = 60.0
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		ground_position_gu
	)
	enemy.configure_runtime_map_projection(
		map_id,
		Callable(self, "_test_ground_to_screen"),
		GroundUnit.screen_delta_px_to_ground_delta_gu
	)
	enemy.configure_spatial_index(index, actor_runtime_id)
	parent.add_child(enemy)
	enemy.set_physics_process(false)
	index.register(
		actor_runtime_id,
		map_id,
		ground_position_gu,
		enemy.combat_radius_gu,
		stable_combat_order,
		enemy,
		Callable(enemy, "spatial_index_position")
	)
	return enemy


func _make_policy_enemy(
	parent: Node,
	player: PlayerCharacter,
	index: RuntimeCombatSpatialIndexScript,
	map_id: int,
	actor_runtime_id: int,
	stable_combat_order: int,
	ground_position_gu: Vector2,
	allow_external_attack: bool
) -> ExternalAttackPolicyEnemy:
	var enemy := ExternalAttackPolicyEnemy.new()
	enemy.allow_external_attack = allow_external_attack
	enemy.setup({
		"name": "summon-policy-target-%d" % actor_runtime_id,
		"hp": 9999,
		"attackMin": 1,
		"attackMax": 1,
		"level": 1,
	}, player, false)
	enemy.control_time = 60.0
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		ground_position_gu
	)
	enemy.configure_runtime_map_projection(
		map_id,
		Callable(self, "_test_ground_to_screen"),
		GroundUnit.screen_delta_px_to_ground_delta_gu
	)
	enemy.configure_spatial_index(index, actor_runtime_id)
	parent.add_child(enemy)
	enemy.set_physics_process(false)
	index.register(
		actor_runtime_id,
		map_id,
		ground_position_gu,
		enemy.combat_radius_gu,
		stable_combat_order,
		enemy,
		Callable(enemy, "spatial_index_position")
	)
	return enemy
