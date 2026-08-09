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
	_verify_refresh_never_downgrades(summon)
	_verify_buff_state_snapshot(summon)
	owner.free()
	print(
		"SUMMON_SUPPORT_BUFF_STATE_PASS: stealth refresh/expiry, AC physical "
		+ "only, MAC magic only, independent timers"
	)
	get_tree().quit(0)


func _verify_stealth_refresh_and_expiry(summon: SummonActor) -> void:
	summon.apply_stealth(5.0, "buff.taoist.mass_invisibility")
	assert(summon.is_stealthed())
	assert(is_equal_approx(summon.stealth_remaining(), 5.0))
	summon._process(2.0)
	assert(is_equal_approx(summon.stealth_remaining(), 3.0))
	summon.apply_stealth(4.0, "buff.taoist.mass_invisibility")
	assert(is_equal_approx(summon.stealth_remaining(), 4.0))
	summon.apply_stealth(2.0, "buff.taoist.mass_invisibility")
	assert(is_equal_approx(summon.stealth_remaining(), 4.0))
	summon._process(4.1)
	assert(not summon.is_stealthed())
	assert(summon.stealth_buff_id.is_empty())
	summon.apply_stealth(0.0)
	assert(not summon.is_stealthed())


func _verify_ac_and_mac_are_separate(summon: SummonActor) -> void:
	summon.current_hp = 100
	summon.apply_ac_buff(7, 10.0, "buff.taoist.blessed_armour_ac")
	summon.take_damage(10)
	assert(summon.current_hp == 97, "AC buff must reduce physical damage")
	summon.take_damage(5)
	assert(summon.current_hp == 96, "physical damage keeps a minimum of 1")

	summon.current_hp = 100
	summon.apply_mac_buff(4, 10.0, "buff.taoist.soul_shield_mac")
	summon.take_magic_damage(10)
	assert(summon.current_hp == 94, "MAC buff must reduce magic damage")

	summon.current_hp = 100
	summon.take_damage(10)
	assert(summon.current_hp == 97, "physical damage must not consume MAC")
	summon.current_hp = 100
	summon.take_magic_damage(10)
	assert(summon.current_hp == 94, "magic damage must not consume AC")

	summon.current_hp = 100
	summon.apply_mac_buff(100, 10.0)
	summon.take_magic_damage(5)
	assert(summon.current_hp == 99, "magic damage keeps a minimum of 1")


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
