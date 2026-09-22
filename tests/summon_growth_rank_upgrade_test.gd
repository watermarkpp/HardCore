extends Node

const ORIGIN_GU := Vector2(38.5, 13.5)
const HOME_MAP_ID := 910001
const AWAY_MAP_ID := 910003
const TARGET_MONSTER_ID := 38
const SKELETON_SKILL := "召唤骷髅"
const DIVINE_SKILL := "召唤神兽"

var _game: Node
var _cast_serial := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "道士"
	PlayerState.level = 40
	PlayerState.equipment.clear()
	_set_ranks(1, 1)
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	var deadline_ms := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline_ms:
		if _game.gameplay_input_is_enabled() and _game._target_spatial_query_ready():
			break
		await get_tree().process_frame
	assert(_game.current_map_id == HOME_MAP_ID)
	assert(_game.gameplay_input_is_enabled() and _game._target_spatial_query_ready())
	_freeze_world()
	_game._set_player_world_position(_game._canonical_ground_gu_to_screen_px(ORIGIN_GU))
	_game.player.current_mp = 999
	_cast(SKELETON_SKILL, "main_pet_spawn")
	_cast(DIVINE_SKILL, "main_pet_spawn")
	var skeleton: SummonActor = _game._canonical_main_pet("skeleton")
	var divine: SummonActor = _game._canonical_main_pet("divine_beast")
	assert(skeleton != null and divine != null)
	for summon: SummonActor in [skeleton, divine]:
		_freeze_pet(summon)
		assert(summon.skill_level == 1 and summon.maximum_pet_level == 3)
		assert(summon.summon_exp_level == 1)
	skeleton.current_hp = skeleton.max_hp - 31
	skeleton.pet_growth_exp = 123
	divine.current_hp = divine.max_hp - 47
	divine.pet_growth_exp = 77
	var skeleton_state := _preserved_state(skeleton)
	var divine_state := _preserved_state(divine)
	var original_skeleton_id := skeleton.get_instance_id()
	var original_divine_id := divine.get_instance_id()

	# A real recast at rank2 must update the existing rank1 pet, without
	# replacing it, healing it, clearing saved progress, or raising pet level.
	_set_ranks(2, 1)
	skeleton.global_position += Vector2(600.0, 600.0)
	var stale_position := skeleton.global_position
	_game.player.current_mp = 0
	_cast(SKELETON_SKILL, "recall_existing_main_pet")
	assert(_game._canonical_main_pet("skeleton").get_instance_id() == original_skeleton_id)
	assert(_game._canonical_main_pet("divine_beast").get_instance_id() == original_divine_id)
	assert(skeleton.global_position != stale_position, "same-instance recall did not relocate")
	assert(skeleton.skill_level == 2 and skeleton.maximum_pet_level == 5)
	_assert_preserved(skeleton, skeleton_state, "rank2 recall")
	_assert_preserved(divine, divine_state, "other typed slot during recall")
	assert(_game.player.current_mp == 0, "same-type rank update spent recall mana")
	assert(skeleton.has_method("synchronize_skill_rank"))
	assert(not bool(skeleton.call("synchronize_skill_rank", 2)), "same rank must be idempotent")
	assert(not bool(skeleton.call("synchronize_skill_rank", 0)), "lower rank must not downgrade")
	assert(skeleton.skill_level == 2 and skeleton.maximum_pet_level == 5)
	_assert_preserved(skeleton, skeleton_state, "idempotent/lower direct synchronization")

	# No rank3 recall occurs before travel. The destination must reconcile the
	# captured old rank2/rank1 snapshots against the owner's CURRENT rank3.
	_set_ranks(3, 3)
	assert(_game._request_map_travel(AWAY_MAP_ID), "formal cross-map travel was rejected")
	assert(_game.current_map_id == AWAY_MAP_ID)
	_freeze_world()
	skeleton = _game._canonical_main_pet("skeleton")
	divine = _game._canonical_main_pet("divine_beast")
	assert(skeleton != null and divine != null, "cross-map restore lost a typed pet")
	_freeze_pet(skeleton)
	_freeze_pet(divine)
	assert(skeleton.get_instance_id() != original_skeleton_id)
	assert(divine.get_instance_id() != original_divine_id)
	for summon: SummonActor in [skeleton, divine]:
		assert(summon.skill_level == 3 and summon.maximum_pet_level == 7)
		assert(summon.runtime_map_id == AWAY_MAP_ID and summon.projection_ready())
		assert(summon._combat_spatial_index == _game._combat_spatial_index)
	_assert_preserved(skeleton, skeleton_state, "higher current rank during map restore")
	_assert_preserved(divine, divine_state, "higher current rank during map restore")
	_assert_persisted_rank("skeleton", 3, 7)
	_assert_persisted_rank("divine_beast", 3, 7)
	var restored_skeleton_id := skeleton.get_instance_id()
	var restored_divine_id := divine.get_instance_id()
	assert(not _game._restore_persisted_taoist_main_pet_if_needed())
	assert(_game._canonical_main_pet("skeleton").get_instance_id() == restored_skeleton_id)
	assert(_game._canonical_main_pet("divine_beast").get_instance_id() == restored_divine_id)

	# Lower effective skill ranks cannot lower a live or restored pet's cap.
	_set_ranks(0, 0)
	_cast(SKELETON_SKILL, "recall_existing_main_pet")
	_cast(DIVINE_SKILL, "recall_existing_main_pet")
	for summon: SummonActor in [skeleton, divine]:
		assert(summon.skill_level == 3 and summon.maximum_pet_level == 7)
	_assert_preserved(skeleton, skeleton_state, "lower-rank live recall")
	_assert_preserved(divine, divine_state, "lower-rank live recall")
	assert(_game._request_map_travel(HOME_MAP_ID), "return to formal home map failed")
	assert(_game.current_map_id == HOME_MAP_ID)
	_freeze_world()
	skeleton = _game._canonical_main_pet("skeleton")
	divine = _game._canonical_main_pet("divine_beast")
	assert(skeleton != null and divine != null)
	_freeze_pet(skeleton)
	_freeze_pet(divine)
	for summon: SummonActor in [skeleton, divine]:
		assert(summon.skill_level == 3 and summon.maximum_pet_level == 7)
		assert(summon.runtime_map_id == HOME_MAP_ID and summon.projection_ready())
	_assert_preserved(skeleton, skeleton_state, "lower current rank during map restore")
	_assert_preserved(divine, divine_state, "lower current rank during map restore")
	_assert_persisted_rank("skeleton", 3, 7)
	_assert_persisted_rank("divine_beast", 3, 7)
	_game._set_player_world_position(_game._canonical_ground_gu_to_screen_px(ORIGIN_GU))

	_verify_kill_credit(skeleton, divine)
	_verify_poison_last_participant(skeleton, divine)
	_verify_poison_without_participant(skeleton, divine)
	_verify_dead_last_participant_is_not_reassigned(skeleton, divine)
	_game.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print(
		"SUMMON_GROWTH_RANK_UPGRADE_PASS: real recall and cross-map restore preserve progress; "
		+ "doubled own kills, poison last participant, no owner/other-pet sharing or dead-pet reassignment"
	)
	get_tree().quit(0)


func _set_ranks(skeleton_rank: int, divine_rank: int) -> void:
	PlayerState.learned_skills = {SKELETON_SKILL: skeleton_rank, DIVINE_SKILL: divine_rank}
	PlayerState.recalculate_stats(false)
	assert(PlayerState.effective_skill_level(SKELETON_SKILL) == skeleton_rank)
	assert(PlayerState.effective_skill_level(DIVINE_SKILL) == divine_rank)


func _cast(skill_name: String, expected_operation: String) -> void:
	_cast_serial += 1
	var result: Dictionary = _game._execute_canonical_skill(
		skill_name, _game.player.global_position, _game.player.facing, 0,
		{"release_id": "summon-growth-rank:%d" % _cast_serial},
	)
	assert(bool(result.get("accepted", false)), "real summon cast rejected: %s" % str(result))
	var plan: Dictionary = result.get("canonical_plan", {})
	var descriptors: Array = plan.get("summon_descriptors", [])
	assert(descriptors.size() == 1)
	assert(str((descriptors[0] as Dictionary).get("operation", "")) == expected_operation)


func _freeze_world() -> void:
	_game.set_process(false)
	_game.set_physics_process(false)
	_game.player.set_physics_process(false)
	_game.auto_target_enabled = false
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and not node.is_queued_for_deletion():
			var enemy := node as EnemyActor
			enemy.set_physics_process(false)
			enemy.set_combat_position(
				_game.player.global_position + Vector2(5000.0, 5000.0),
				&"summon_growth_rank_fixture_clear",
			)


func _freeze_pet(summon: SummonActor) -> void:
	summon.set_process(false)
	summon.set_physics_process(false)


func _preserved_state(summon: SummonActor) -> Dictionary:
	return {
		"pet_level": summon.summon_exp_level,
		"growth_exp": summon.pet_growth_exp,
		"hp": summon.current_hp,
		"max_hp": summon.max_hp,
	}


func _assert_preserved(summon: SummonActor, expected: Dictionary, label: String) -> void:
	assert(_preserved_state(summon) == expected, "%s altered pet progress/HP: %s" % [
		label, str(_preserved_state(summon)),
	])


func _assert_persisted_rank(summon_id: String, expected_rank: int, expected_cap: int) -> void:
	var saved := PlayerState.taoist_main_pet_runtime_state_for_restore(summon_id)
	assert(int(saved.get("skill_rank", -1)) == expected_rank)
	assert(int(saved.get("maximum_pet_level", -1)) == expected_cap)


func _new_credit_target() -> EnemyActor:
	var position: Vector2 = _game._canonical_ground_gu_to_screen_px(ORIGIN_GU + Vector2(1.0, 0.0))
	var enemy: EnemyActor = _game._spawn_enemy(
		GameData.get_monster_by_id(TARGET_MONSTER_ID), position, false, -1.0,
		{"respawn_enabled": false, "spawn_group_id": "summon_growth_rank_credit"},
	)
	assert(enemy != null and enemy.monster_id == TARGET_MONSTER_ID)
	enemy.set_physics_process(false)
	enemy.set_combat_position(position, &"summon_growth_credit_target")
	assert(enemy.can_receive_damage() and enemy.defense == 0 and enemy.magic_defense == 0)
	assert(int(enemy.monster_data.get("level", 0)) == 28)
	return enemy


func _pet_hit(summon: SummonActor, enemy: EnemyActor) -> void:
	summon.global_position = _game._canonical_ground_gu_to_screen_px(ORIGIN_GU)
	summon._begin_attack(enemy)
	assert(summon._pending_attack_target == enemy)
	assert(summon.attack_release_snapshot_intersects_target(summon._pending_attack_snapshot, enemy))
	var hp_before := enemy.current_hp
	summon._release_pending_attack()
	assert(enemy.current_hp < hp_before, "participating pet must actually deal positive damage")
	assert(summon._pending_attack_target == null)


func _credit_pair(skeleton: SummonActor, divine: SummonActor) -> Vector2i:
	return Vector2i(skeleton.pet_growth_exp, divine.pet_growth_exp)


func _settle_death() -> void:
	# Complete the existing actor/deferred reward pipeline as well, so an
	# owner-kill broadcast or a second grant cannot hide behind a later signal.
	var settled: Dictionary = _game._drain_enemy_death_queue_for_logout()
	assert(bool(settled.get("success", false)), "real death settlement failed: %s" % str(settled))


func _verify_kill_credit(skeleton: SummonActor, divine: SummonActor) -> void:
	var owner_target := _new_credit_target()
	var before := _credit_pair(skeleton, divine)
	_pet_hit(skeleton, owner_target)
	_pet_hit(divine, owner_target)
	assert(owner_target.current_hp > 0)
	assert(_credit_pair(skeleton, divine) == before, "nonlethal participation awarded kill growth")
	assert(_game._apply_physical_hit(owner_target, owner_target.current_hp))
	assert(owner_target.current_hp == 0)
	_settle_death()
	assert(_credit_pair(skeleton, divine) == before, "owner direct kill was shared with participating pets")
	for killer: SummonActor in [skeleton, divine]:
		var enemy := _new_credit_target()
		enemy.current_hp = 1
		before = _credit_pair(skeleton, divine)
		var expected := before
		var credit := int(enemy.monster_data.level) * 2
		if killer == skeleton:
			expected.x += credit
		else:
			expected.y += credit
		_pet_hit(killer, enemy)
		assert(enemy.current_hp == 0)
		assert(_credit_pair(skeleton, divine) == expected, "own kill did not credit exactly its killer")
		killer._release_pending_attack()
		_settle_death()
		assert(_credit_pair(skeleton, divine) == expected, "direct kill was duplicated or shared with the other pet")


func _kill_with_real_poison_tick(enemy: EnemyActor) -> void:
	assert(enemy.can_receive_damage())
	enemy.apply_poison(enemy.current_hp, 1.0, 0.1)
	enemy._update_status_effects(0.1)
	assert(enemy.current_hp == 0, "real poison interval did not commit the lethal tick")
	# Subsequent scheduled ticks must not create another growth award.
	enemy._update_status_effects(0.1)
	_settle_death()


func _verify_poison_last_participant(skeleton: SummonActor, divine: SummonActor) -> void:
	# Reverse the order as well: credit follows actual participation order,
	# never a preferred pet type or the order of the two persistence slots.
	for last_pet: SummonActor in [divine, skeleton]:
		var first_pet := skeleton if last_pet == divine else divine
		var enemy := _new_credit_target()
		var before := _credit_pair(skeleton, divine)
		_pet_hit(first_pet, enemy)
		_pet_hit(last_pet, enemy)
		assert(enemy.current_hp > 0 and _credit_pair(skeleton, divine) == before)
		var expected := before
		var credit := int(enemy.monster_data.level) * 2
		if last_pet == skeleton:
			expected.x += credit
		else:
			expected.y += credit
		_kill_with_real_poison_tick(enemy)
		assert(
			_credit_pair(skeleton, divine) == expected,
			"poison death must grant doubled level credit only to the last pet that dealt damage",
		)


func _verify_poison_without_participant(skeleton: SummonActor, divine: SummonActor) -> void:
	var enemy := _new_credit_target()
	var before := _credit_pair(skeleton, divine)
	# A real owner hit still does not create a pet participant for poison.
	assert(_game._apply_physical_hit(enemy, 1))
	assert(enemy.current_hp > 0)
	_kill_with_real_poison_tick(enemy)
	assert(_credit_pair(skeleton, divine) == before, "poison without pet participation awarded growth")


func _verify_dead_last_participant_is_not_reassigned(
	skeleton: SummonActor, divine: SummonActor,
) -> void:
	var enemy := _new_credit_target()
	var before := _credit_pair(skeleton, divine)
	_pet_hit(skeleton, enemy)
	_pet_hit(divine, enemy)
	assert(enemy.current_hp > 0)
	divine.take_damage(divine.current_hp + 9999)
	assert(divine.current_hp == 0 and divine.state == SummonActor.SummonState.DEAD)
	assert(_game._canonical_main_pet("divine_beast") == null)
	_kill_with_real_poison_tick(enemy)
	assert(
		_credit_pair(skeleton, divine) == before,
		"dead last poison participant received growth or its credit was reassigned to the earlier pet",
	)
