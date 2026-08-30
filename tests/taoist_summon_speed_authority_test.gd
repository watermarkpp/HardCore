extends Node

const TaoistCombatMathScript := preload("res://scripts/taoist_combat_math.gd")


func _ready() -> void:
	TaoistCombatMathScript.clear_cache_for_tests()
	var expected_intervals := [500, 450, 400, 350]
	for skill_rank: int in range(expected_intervals.size()):
		var expected_interval_ms: int = expected_intervals[skill_rank]
		for summon_id: String in ["skeleton", "divine_beast"]:
			var template := TaoistCombatMathScript.summon_template(summon_id)
			var expected_monster_id := 145 if summon_id == "skeleton" else 146
			assert(int(template.get("monster_id", -1)) == expected_monster_id)
			assert(
				TaoistCombatMathScript.effective_summon_move_interval_ms(
					summon_id,
					skill_rank,
				) == expected_interval_ms
			)
			var profile := TaoistCombatMathScript.summon_profile(
				str(template.get("skill_id", "")),
				skill_rank,
				1,
				0,
			)
			assert(int(profile.get("move_interval_ms", -1)) == expected_interval_ms)
			assert(
				is_equal_approx(
					float(profile.get("move_speed_gu_per_sec", 0.0)),
					1000.0 / float(expected_interval_ms),
				)
			)
	print("TAOIST_SUMMON_SPEED_AUTHORITY_PASS checks=32")
	get_tree().quit(0)
