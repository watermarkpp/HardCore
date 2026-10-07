extends Node

## R1 monster struck policy: verifiable vanilla-1.76 constants and tables.
## Evidence: TAnimalObject.Struck attack-tick formula, client struck frame
## time and the direct-magic actor RNG compatibility boundary (Level < 50).

const Policy := preload("res://scripts/monster_struck_policy.gd")

var _checks := 0


func _ready() -> void:
	_run()
	print("MONSTER_STRUCK_POLICY_PASS checks=%d" % _checks)
	get_tree().quit(0)


func _check(condition: bool, label: String) -> void:
	assert(condition, "MONSTER_STRUCK_POLICY: " + label)
	_checks += 1


func _run() -> void:
	_test_attack_delay_table()
	_test_struck_frame_ms_table()
	_test_direct_magic_compatibility_boundary()
	_test_backlog_speed_and_cap()


func _test_attack_delay_table() -> void:
	# 150 - min(130, level * 4): 146ms at Lv1, saturating at 20ms from Lv33+.
	var table := {
		1: 146,
		10: 110,
		20: 70,
		26: 46,
		28: 38,
		32: 22,
		33: 20,
		43: 20,
		49: 20,
		# Level-50 divergence note (R1 ruling): the Delphi 1.76 family and
		# OpenMir2 keep the ordinary penalty at every level; only the direct
		# magic walk delay has the Level<50 gate.
		50: 20,
		60: 20,
	}
	for level: int in table:
		_check(
			Policy.attack_delay_ms(level) == table[level],
			"attack_delay_ms(%d) must be %d" % [level, table[level]]
		)
	_check(Policy.attack_delay_ms(0) == Policy.attack_delay_ms(1), "level clamps to >= 1")
	_check(Policy.attack_delay_ms(-3) == 146, "negative level clamps to Lv1")


func _test_struck_frame_ms_table() -> void:
	# max(80, 200 - level * 5): 195ms/frame at Lv1, floor 80ms from Lv24.
	var table := {
		1: 195,
		10: 150,
		20: 100,
		23: 85,
		24: 80,
		43: 80,
		50: 80,
	}
	for level: int in table:
		_check(
			Policy.struck_frame_ms(level) == table[level],
			"struck_frame_ms(%d) must be %d" % [level, table[level]]
		)
	_check(Policy.struck_frame_ms(0) == 195, "level clamps to >= 1")


func _test_direct_magic_compatibility_boundary() -> void:
	_check(Policy.direct_magic_compatibility_draw_required(1, false), "Lv1 keeps compatibility draw")
	_check(Policy.direct_magic_compatibility_draw_required(43, false), "Lv43 keeps compatibility draw")
	_check(Policy.direct_magic_compatibility_draw_required(49, false), "Lv49 keeps compatibility draw")
	_check(not Policy.direct_magic_compatibility_draw_required(50, false), "Lv50 has no legacy draw")
	_check(not Policy.direct_magic_compatibility_draw_required(51, false), "Lv51 has no legacy draw")
	_check(not Policy.direct_magic_compatibility_draw_required(43, true), "source-exempt has no legacy draw")


func _test_backlog_speed_and_cap() -> void:
	_check(Policy.struck_speed_multiplier(0) == 1.0, "no backlog -> 1.0x")
	_check(Policy.struck_speed_multiplier(1) == 1.0, "single backlog -> 1.0x")
	_check(
		is_equal_approx(Policy.struck_speed_multiplier(2), 1.5),
		">=2 backlog -> 1.5x (frame time x 2/3)"
	)
	_check(
		is_equal_approx(Policy.struck_speed_multiplier(10), 1.5),
		"deep backlog stays 1.5x"
	)
	_check(Policy.MAX_PENDING_STRUCK == 255, "malformed-input cap is 255")
