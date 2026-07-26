class_name WarriorSkillSemanticContracts
extends RefCounted

const Support := preload("res://tests/skills/skill_semantic_contract_support.gd")

const ASSERTIONS_BY_SKILL := {
	"warrior.basic_swordsmanship": [
		"basic_swordsmanship_accuracy_by_rank",
		"basic_swordsmanship_never_casts",
		"basic_swordsmanship_physical_only",
	],
	"warrior.slaying_swordsmanship": [
		"slaying_proc_table_exact",
		"slaying_dc_bonus_exact",
		"slaying_accuracy_bonus_exact",
		"slaying_training_only_on_proc",
	],
	"warrior.thrusting": [
		"thrusting_two_cell_line",
		"thrusting_second_cell_multiplier",
		"thrusting_second_cell_ignores_ac",
		"thrusting_one_training_event_per_swing",
	],
	"warrior.half_moon": [
		"half_moon_primary_full_damage",
		"half_moon_side_multiplier",
		"half_moon_rotates_all_8_directions",
		"half_moon_mp_once_per_swing",
		"half_moon_training_once_per_swing",
	],
	"warrior.wild_rush": [
		"wild_rush_lower_level_only",
		"wild_rush_probability_formula",
		"wild_rush_distance_by_rank",
		"wild_rush_collision_self_damage",
		"wild_rush_boss_immune",
		"wild_rush_training_only_on_displacement",
	],
	"warrior.fire_sword": [
		"fire_sword_never_auto_casts",
		"fire_sword_multiplier_exact",
		"fire_sword_charge_expires",
		"fire_sword_consumed_once",
		"fire_sword_cooldown_independent_from_charge_lifetime",
	],
}

var _support := Support.new()


func validators() -> Dictionary:
	var result: Dictionary = {}
	for skill_id: String in ASSERTIONS_BY_SKILL:
		for assertion_id: String in ASSERTIONS_BY_SKILL[skill_id]:
			result["%s::%s" % [skill_id, assertion_id]] = Callable(
				self, "_validate"
			).bind(skill_id, assertion_id)
	return result


func _validate(skill_id: String, assertion_id: String) -> bool:
	match assertion_id:
		"basic_swordsmanship_accuracy_by_rank":
			return _support.rank_effect_values(skill_id, "value") == [0, 3, 6, 9]
		"basic_swordsmanship_never_casts":
			var result := _support.execute(skill_id, 3)
			return result.accepted and result.timing.body_cast_ms == 0 and result.timing.total_action_lock_ms == 0
		"basic_swordsmanship_physical_only":
			var effect: Dictionary = _support.execute(skill_id, 3).effects[0]
			return effect.affects == ["physical_melee_hit_checks"]
		"slaying_proc_table_exact":
			return _floats_equal(
				_support.rank_effect_values(skill_id, "success_probability"),
				[0.1, 0.125, 1.0 / 6.0, 0.25]
			) and _support.seeded_effect_outcomes(
				skill_id, 0, {"force_proc": false, "force_no_proc": false}
			)
		"slaying_dc_bonus_exact":
			return _support.rank_effect_values(skill_id, "flat_dc_bonus") == [5, 6, 7, 8]
		"slaying_accuracy_bonus_exact":
			return _support.rank_effect_values(skill_id, "flat_accuracy_bonus") == [0, 1, 2, 3]
		"slaying_training_only_on_proc":
			var success := _support.execute(skill_id, 3, {"force_proc": true})
			var failure := _support.execute(skill_id, 3, {"force_proc": false, "force_no_proc": true})
			return not success.proficiency_event.is_empty() and failure.proficiency_event.is_empty()
		"thrusting_two_cell_line":
			var thrust := _support.execute(skill_id, 3)
			return thrust.geometry_cells == [Vector2i(1, 0), Vector2i(2, 0)]
		"thrusting_second_cell_multiplier":
			var values: Array = []
			for rank in range(4):
				values.append(_support.execute(skill_id, rank).effects[1].multiplier)
			return _floats_equal(values, [0.4, 0.6, 0.8, 1.0])
		"thrusting_second_cell_ignores_ac":
			return bool(_support.execute(skill_id, 0).effects[1].ignore_ac)
		"thrusting_one_training_event_per_swing":
			var thrust := _support.execute(skill_id, 3, {"eligible_target_count": 2})
			return not thrust.proficiency_event.is_empty() and thrust.effects.size() == 2
		"half_moon_primary_full_damage":
			return _support.execute(skill_id, 3).effects[0].primary_multiplier == 1.0
		"half_moon_side_multiplier":
			return _floats_equal(
				_support.rank_effect_values(skill_id, "side_multiplier"),
				[0.15, 0.23, 0.31, 5.0 / 13.0]
			)
		"half_moon_rotates_all_8_directions":
			var footprints: Array = []
			for facing: Vector2i in [
				Vector2i.UP, Vector2i(1, -1), Vector2i.RIGHT, Vector2i(1, 1),
				Vector2i.DOWN, Vector2i(-1, 1), Vector2i.LEFT, Vector2i(-1, -1),
			]:
				footprints.append(_support.execute_facing(skill_id, 3, facing).geometry_cells)
			return _support.all_unique(footprints)
		"half_moon_mp_once_per_swing":
			return _support.execute(skill_id, 3).effects[0].max_resource_commits == 1
		"half_moon_training_once_per_swing":
			return _support.execute(skill_id, 3).effects[0].max_training_events == 1
		"wild_rush_lower_level_only":
			var lower := _support.execute(skill_id, 3, {"caster_level": 40, "target_level": 39})
			var equal := _support.execute(skill_id, 3, {"caster_level": 40, "target_level": 40})
			return lower.accepted and not equal.accepted
		"wild_rush_probability_formula":
			var rush := _support.execute(skill_id, 2, {"caster_level": 40, "target_level": 35})
			return (
				is_equal_approx(float(rush.effects[0].success_probability), 1.0)
				and _support.seeded_effect_outcomes(skill_id, 0, {
					"caster_level": 40, "target_level": 39,
					"force_success": false, "force_failure": false,
				})
			)
		"wild_rush_distance_by_rank":
			return _support.rank_effect_values(
				skill_id, "push_distance_tiles", {"caster_level": 40, "target_level": 1}
			) == [1, 1, 2, 3]
		"wild_rush_collision_self_damage":
			var collision := _support.execute(skill_id, 3, {
				"path_blocked_after_start": true, "caster_max_hp": 1000,
			})
			return not collision.effect_success and collision.effects[1].amount == 10
		"wild_rush_boss_immune":
			return not _support.execute(skill_id, 3, {"target_is_boss": true}).accepted
		"wild_rush_training_only_on_displacement":
			var moved := _support.execute(skill_id, 3, {"force_success": true})
			var failed := _support.execute(skill_id, 3, {"force_success": false, "force_failure": true})
			return not moved.proficiency_event.is_empty() and failed.proficiency_event.is_empty()
		"fire_sword_never_auto_casts":
			return not bool(_support.execute(skill_id, 3).effects[0].auto_cast)
		"fire_sword_multiplier_exact":
			return _floats_equal(
				_support.rank_effect_values(skill_id, "damage_multiplier"),
				[1.4, 1.8, 2.2, 2.6]
			)
		"fire_sword_charge_expires":
			var charge := _support.execute(skill_id, 3, {"charge_consumed": false})
			return charge.effects[0].charge_lifetime_ms == 10000 and charge.proficiency_event.is_empty()
		"fire_sword_consumed_once":
			var consumed := _support.execute(skill_id, 3, {"charge_consumed": true})
			return consumed.effects[0].stack_count_max == 1 and not consumed.proficiency_event.is_empty()
		"fire_sword_cooldown_independent_from_charge_lifetime":
			var charge := _support.execute(skill_id, 3)
			return charge.timing.cooldown_ms == 8000 and charge.effects[0].charge_lifetime_ms == 10000
		_:
			return false


func _floats_equal(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index in range(actual.size()):
		if not is_equal_approx(float(actual[index]), float(expected[index])):
			return false
	return true
