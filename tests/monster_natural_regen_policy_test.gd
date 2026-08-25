extends Node

const Regen := preload("res://scripts/monster_natural_regen_policy.gd")

var _checks := 0


func _ready() -> void:
	_run()
	print("MONSTER_NATURAL_REGEN_POLICY_PASS checks=%d" % _checks)
	get_tree().quit(0)


func _run() -> void:
	_test_formula_boundaries()
	_test_strict_six_second_cadence()
	_test_full_hp_tick_is_consumed()
	_test_damage_and_poison_do_not_reset_cadence()
	_test_multiple_elapsed_ticks_and_cap()


func _test_formula_boundaries() -> void:
	var cases := [
		[1, 1],
		[74, 1],
		[75, 2],
		[149, 2],
		[150, 3],
		[750, 11],
	]
	for regen_case: Array in cases:
		assert(
			Regen.heal_amount(int(regen_case[0])) == int(regen_case[1]),
			"unexpected natural regen formula at MaxHP=%d" % int(regen_case[0])
		)
		_checks += 1


func _test_strict_six_second_cadence() -> void:
	var regen := Regen.new()
	var before := regen.advance(5.999, 50, 100)
	assert(before.ticks == 0 and before.healed == 0 and before.hp == 50)
	var at_tick := regen.advance(0.001, 50, 100)
	assert(at_tick.ticks == 1)
	assert(at_tick.healed == 2 and at_tick.hp == 52)
	assert(is_equal_approx(float(at_tick.elapsed_seconds), 0.0))
	_checks += 4


func _test_full_hp_tick_is_consumed() -> void:
	var regen := Regen.new()
	var full_tick := regen.advance(6.0, 100, 100)
	assert(full_tick.ticks == 1 and full_tick.healed == 0)

	# Damage after a full-HP service tick must not cause an early heal and must
	# not reset the independent cadence.
	var almost := regen.advance(5.999, 90, 100)
	assert(almost.ticks == 0 and almost.hp == 90)
	var next_tick := regen.advance(0.001, 90, 100)
	assert(next_tick.ticks == 1 and next_tick.healed == 2 and next_tick.hp == 92)
	_checks += 3


func _test_damage_and_poison_do_not_reset_cadence() -> void:
	var regen := Regen.new()
	var hp := 100

	# Four independent damage/status channels are simulated between cadence
	# advances. No call is allowed to reset the policy.
	assert(regen.advance(1.5, hp, 100).ticks == 0)
	hp -= 3 # physical damage
	assert(regen.advance(1.5, hp, 100).ticks == 0)
	hp -= 4 # magic damage
	assert(regen.advance(1.5, hp, 100).ticks == 0)
	hp -= 2 # red-poison-era combat damage / debuff does not matter
	assert(regen.advance(1.499, hp, 100).ticks == 0)
	hp -= 5 # green poison tick
	var independent_tick := regen.advance(0.001, hp, 100)
	assert(independent_tick.ticks == 1)
	assert(independent_tick.healed == 2)
	assert(independent_tick.hp == hp + 2)
	_checks += 7


func _test_multiple_elapsed_ticks_and_cap() -> void:
	var regen := Regen.new()
	var burst := regen.advance(18.0, 50, 150)
	assert(burst.ticks == 3)
	assert(burst.healed == 9)
	assert(burst.hp == 59)
	assert(burst.total_ticks == 3)

	var capped := regen.advance(60.0, 149, 150)
	assert(capped.ticks == 10)
	assert(capped.healed == 1 and capped.hp == 150)
	assert(capped.total_ticks == 13)
	_checks += 7
