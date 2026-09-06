extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var owner := PlayerCharacter.new()
	var summon := SummonActor.new()
	summon.setup(
		owner,
		"变异骷髅",
		1,
		0,
		"taoist.summon_skeleton",
		19,
		1
	)
	add_child(summon)
	_verify_stealth_refresh_and_expiry(summon)
	_verify_ac_and_mac_are_separate(summon)
	_verify_direct_spell_pipeline(summon)
	_verify_owner_teleport_relocation(summon)
	_verify_refresh_never_downgrades(summon)
	_verify_buff_state_snapshot(summon)
	_verify_persistence_round_trip(owner, summon)
	_verify_owner_level_contract(owner)
	_verify_death_is_idempotent(summon)
	owner.free()
	print(
		"SUMMON_SUPPORT_BUFF_STATE_PASS: stealth refresh/expiry, AC physical "
		+ "only, MAC magic only, direct-spell settlement, canonical restore"
	)
	get_tree().quit(0)


func _verify_stealth_refresh_and_expiry(summon: SummonActor) -> void:
	summon.apply_stealth(5.0, "buff.taoist.mass_invisibility")
	summon._update_stealth_visual()
	assert(summon.is_stealthed())
	assert(is_equal_approx(summon.stealth_remaining(), 5.0))
	assert(is_equal_approx(summon.modulate.a, 1.0))
	assert(is_equal_approx(summon._sprite.self_modulate.a, 0.60))
	summon._process(2.0)
	assert(is_equal_approx(summon.stealth_remaining(), 3.0))
	assert(is_equal_approx(summon._sprite.self_modulate.a, 0.60))
	summon.apply_stealth(4.0, "buff.taoist.mass_invisibility")
	assert(is_equal_approx(summon.stealth_remaining(), 4.0))
	summon.apply_stealth(2.0, "buff.taoist.mass_invisibility")
	assert(is_equal_approx(summon.stealth_remaining(), 4.0))
	summon._process(4.1)
	assert(not summon.is_stealthed())
	assert(summon.stealth_buff_id.is_empty())
	assert(is_equal_approx(summon.modulate.a, 1.0))
	assert(is_equal_approx(summon._sprite.self_modulate.a, 1.0))
	summon.apply_stealth(0.0)
	assert(not summon.is_stealthed())


func _verify_ac_and_mac_are_separate(summon: SummonActor) -> void:
	summon.current_hp = 100
	summon.clear_ac_buff()
	# Rank-0 skeleton AC is 2..4. The deterministic roll proves base AC is
	# consumed before the minimum-one damage floor.
	summon.take_damage(10, null, 4)
	assert(summon.current_hp == 94, "base AC must reduce physical damage")
	summon.current_hp = 100
	summon.apply_ac_buff(7, 10.0, "buff.taoist.blessed_armour_ac")
	summon.take_damage(10, null, 4)
	assert(summon.current_hp == 99, "AC base plus buff must reduce physical damage")
	summon.take_damage(5, null, 4)
	assert(summon.current_hp == 98, "physical damage keeps a minimum of 1")

	summon.current_hp = 100
	summon.clear_mac_buff()
	# Rank-0 skeleton MAC is 3..6.
	summon.take_magic_damage(10, 6)
	assert(summon.current_hp == 96, "base MAC must reduce magic damage")
	summon.current_hp = 100
	summon.apply_mac_buff(4, 10.0, "buff.taoist.soul_shield_mac")
	summon.take_magic_damage(10, 6)
	assert(summon.current_hp == 97, "MAC base plus buff must reduce magic damage")

	summon.current_hp = 100
	summon.clear_ac_buff()
	summon.clear_mac_buff()
	summon.take_damage(10, null, 4)
	assert(summon.current_hp == 94, "physical damage must not consume MAC")
	summon.current_hp = 100
	summon.take_magic_damage(10, 6)
	assert(summon.current_hp == 96, "magic damage must not consume AC")

	summon.current_hp = 100
	summon.apply_mac_buff(100, 10.0)
	summon.take_magic_damage(5)
	assert(summon.current_hp == 99, "magic damage keeps a minimum of 1")


func _verify_direct_spell_pipeline(summon: SummonActor) -> void:
	summon.current_hp = 100
	summon.clear_mac_buff()
	var base := summon.take_direct_spell_damage("", 10, 9, 6)
	assert(base.runtime_contract == "summon.direct_spell_damage.openmir2.v1")
	assert(base.anti_magic_checked == false)
	assert(base.magic_defense_checked)
	assert(base.magic_defense_min == 3 and base.magic_defense_max == 6)
	assert(base.magic_defense_roll == 6)
	assert(base.final_damage == 4 and base.applied_damage == 4)
	assert(base.physical_defense_bypassed)

	summon.current_hp = 100
	summon.apply_mac_buff(4, 10.0, "buff.taoist.soul_shield_mac")
	var buffed := summon.take_direct_spell_damage("", 10, 9, 10)
	assert(buffed.magic_defense_min == 7 and buffed.magic_defense_max == 10)
	assert(buffed.magic_defense_roll == 10)
	assert(buffed.final_damage == 0 and buffed.applied_damage == 0)
	assert(summon.current_hp == 100)


func _verify_owner_teleport_relocation(summon: SummonActor) -> void:
	var target := EnemyActor.new()
	summon._current_target = target
	summon._pending_attack_target = target
	summon._pending_attack_snapshot = {"stale": true}
	summon._pending_attack_release_remaining = 0.75
	summon._rest_formation_moving = true
	summon._attack_timer = 2.0
	summon.velocity = Vector2(13.0, -9.0)
	summon.actual_ground_motion_gu = Vector2(0.4, 0.2)
	summon._set_state(SummonActor.SummonState.ATTACK_TARGET)
	var final_position_px := Vector2(421.0, 287.0)
	var result := summon.relocate_after_owner_teleport(final_position_px)
	assert(result.contract_id == "skills.summon.owner_teleport_relocation.v1")
	assert(result.relocated)
	assert(result.final_position_px == final_position_px)
	assert(result.target_cleared and result.pending_attack_cleared)
	assert(summon.global_position == final_position_px)
	assert(summon._current_target == null)
	assert(summon._pending_attack_target == null)
	assert(summon._pending_attack_snapshot.is_empty())
	assert(is_equal_approx(summon._pending_attack_release_remaining, 0.0))
	assert(summon._attack_timer == 0.0)
	assert(summon.velocity == Vector2.ZERO)
	assert(summon.actual_ground_motion_gu == Vector2.ZERO)
	assert(not summon._rest_formation_moving)
	assert(summon.state == SummonActor.SummonState.FOLLOW_OWNER)
	target.free()


func _verify_buff_state_snapshot(summon: SummonActor) -> void:
	summon.clear_ac_buff()
	summon.clear_mac_buff()
	summon.apply_ac_buff(7, 2.0, "buff.taoist.blessed_armour_ac")
	summon.apply_mac_buff(4, 10.0, "buff.taoist.soul_shield_mac")
	summon._process(3.0)
	assert(summon.physical_defence_bonus() == 0, "AC timer expired")
	assert(summon.magic_defence_bonus() == 4, "MAC timer still active")
	var snapshot := summon.buff_state_snapshot()
	assert(snapshot.contract_id == SummonActor.BUFF_STATE_CONTRACT_ID)
	assert(snapshot.stealth_contract_id == SummonActor.STEALTH_STATE_CONTRACT_ID)
	assert(snapshot.physical_defence.bonus == 0)
	assert(snapshot.magic_defence.bonus == 4)
	assert(snapshot.magic_defence.buff_id == "buff.taoist.soul_shield_mac")


func _verify_persistence_round_trip(
	owner: PlayerCharacter,
	summon: SummonActor
) -> void:
	summon.current_hp = 77
	# Deliberately stale persisted max HP: pet level is the canonical source.
	summon.max_hp = 1
	summon.summon_exp_level = 1
	summon.maximum_pet_level = 7
	summon.pet_growth_exp = 83
	summon.remaining_lifetime = 1234.5
	summon.apply_stealth(6.0, "buff.taoist.mass_invisibility")
	summon.clear_ac_buff()
	summon.clear_mac_buff()
	summon.apply_ac_buff(9, 12.0, "buff.taoist.blessed_armour_ac")
	summon.apply_mac_buff(7, 14.0, "buff.taoist.soul_shield_mac")
	var snapshot := summon.persistence_snapshot()
	assert(snapshot.contract_id == "skills.summon.persistence.runtime_state.v1")
	assert(snapshot.alive)
	assert(snapshot.summon_id == "skeleton")
	assert(snapshot.skill_rank == 0)
	assert(snapshot.owner_level == 19)

	var restored := SummonActor.new()
	restored.setup(
		owner,
		"鍙樺紓楠烽珔",
		1,
		0,
		"taoist.summon_skeleton",
		19,
		7
	)
	add_child(restored)
	restored.set_process(false)
	assert(restored.restore_persistence_snapshot(snapshot))
	assert(restored.current_hp == 77 and restored.max_hp == 196)
	assert(restored.summon_exp_level == 1)
	assert(restored.attack_max == 24)
	assert(restored.ac_min == 2 and restored.ac_max == 4)
	assert(restored.mac_min == 3 and restored.mac_max == 6)
	assert(restored.maximum_pet_level == 7)
	assert(restored.pet_growth_exp == 83)
	assert(is_equal_approx(restored.remaining_lifetime, 1234.5))
	assert(is_equal_approx(restored.stealth_remaining_seconds, 6.0))
	assert(restored.stealth_buff_id == "buff.taoist.mass_invisibility")
	assert(is_equal_approx(restored.modulate.a, 1.0))
	assert(is_equal_approx(restored._sprite.self_modulate.a, 0.60))
	assert(restored.ac_buff_bonus == 9)
	assert(is_equal_approx(restored.ac_buff_remaining_seconds, 12.0))
	assert(restored.mac_buff_bonus == 7)
	assert(is_equal_approx(restored.mac_buff_remaining_seconds, 14.0))
	var dead_snapshot := snapshot.duplicate(true)
	dead_snapshot.alive = false
	assert(not restored.restore_persistence_snapshot(dead_snapshot))
	restored.free()


func _verify_refresh_never_downgrades(summon: SummonActor) -> void:
	summon.clear_ac_buff()
	summon.clear_mac_buff()
	## Strong then weak: bonus must not drop.
	summon.apply_ac_buff(10, 10.0, "buff.taoist.blessed_armour_ac")
	summon.apply_ac_buff(5, 10.0, "buff.taoist.blessed_armour_ac")
	assert(summon.physical_defence_bonus() == 10)
	## Weak then strong still upgrades.
	summon.apply_ac_buff(12, 2.0, "buff.taoist.blessed_armour_ac")
	assert(summon.physical_defence_bonus() == 12)
	## Short refresh never shortens the remaining duration.
	summon._process(8.0)
	assert(
		is_equal_approx(
			summon.buff_state_snapshot().physical_defence.remaining_seconds,
			2.0
		)
	)
	summon.apply_ac_buff(12, 0.5, "buff.taoist.blessed_armour_ac")
	assert(
		is_equal_approx(
			summon.buff_state_snapshot().physical_defence.remaining_seconds,
			2.0
		)
	)
	## Weak value with a long duration keeps the strong bonus and extends time.
	summon.apply_ac_buff(3, 30.0, "buff.taoist.blessed_armour_ac")
	assert(summon.physical_defence_bonus() == 12)
	assert(
		is_equal_approx(
			summon.buff_state_snapshot().physical_defence.remaining_seconds,
			30.0
		)
	)
	## After expiry a fresh weaker cast applies normally.
	summon._process(30.1)
	assert(summon.physical_defence_bonus() == 0)
	summon.apply_ac_buff(3, 10.0, "buff.taoist.blessed_armour_ac")
	assert(summon.physical_defence_bonus() == 3)
	## MAC keeps the same independent max-refresh semantics.
	summon.apply_mac_buff(8, 10.0, "buff.taoist.soul_shield_mac")
	summon.apply_mac_buff(4, 10.0, "buff.taoist.soul_shield_mac")
	assert(summon.magic_defence_bonus() == 8)
	summon.apply_mac_buff(4, 3.0, "buff.taoist.soul_shield_mac")
	assert(
		is_equal_approx(
			summon.buff_state_snapshot().magic_defence.remaining_seconds,
			10.0
		)
	)


func _verify_owner_level_contract(owner: PlayerCharacter) -> void:
	## Default value before setup.
	var fresh := SummonActor.new()
	assert(fresh.owner_level == 1)
	fresh.free()

	## Explicit owner level 21 is frozen independently of the pet level.
	var fixed_owner := SummonActor.new()
	fixed_owner.setup(
		owner,
		"变异骷髅",
		1,
		0,
		"taoist.summon_skeleton",
		21,
		7
	)
	add_child(fixed_owner)
	assert(fixed_owner.owner_level == 21)
	assert(fixed_owner.summon_exp_level != fixed_owner.owner_level)
	assert(fixed_owner.summon_exp_level == 0)
	fixed_owner.pet_growth_exp = TaoistCombatMath.summon_growth_threshold(
		"skeleton",
		0
	)
	assert(fixed_owner.gain_growth_from_kill(1))
	assert(fixed_owner.summon_exp_level == 1)
	assert(
		fixed_owner.owner_level == 21,
		"pet growth must never change the frozen owner level"
	)
	fixed_owner.free()

	## No owner level argument: fall back to the PlayerState owner level.
	PlayerState.test_mode = true
	PlayerState.level = 19
	var fallback_owner := SummonActor.new()
	fallback_owner.setup(
		owner,
		"变异骷髅",
		1,
		0,
		"taoist.summon_skeleton"
	)
	assert(fallback_owner.owner_level == 19)
	fallback_owner.free()


func _verify_death_is_idempotent(summon: SummonActor) -> void:
	assert(summon.is_in_group("combat_targets"))
	assert(summon.collision_layer != 0 and summon.collision_mask != 0)
	summon.current_hp = 1
	summon.take_damage(999)
	assert(summon.state == SummonActor.SummonState.DEAD)
	assert(not summon.is_in_group("combat_targets"))
	assert(summon.collision_layer == 0 and summon.collision_mask == 0)
	var death_duration := summon._death_visual_remaining
	assert(death_duration > 0.0)
	summon.take_magic_damage(999)
	assert(summon.current_hp == 0)
	assert(
		is_equal_approx(summon._death_visual_remaining, death_duration),
		"repeat damage must not restart summon death lifetime"
	)
