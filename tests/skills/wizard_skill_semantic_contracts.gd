class_name WizardSkillSemanticContracts
extends RefCounted

const Support := preload("res://tests/skills/skill_semantic_contract_support.gd")

const ASSERTIONS_BY_SKILL := {
	"wizard.fireball": [
		"fireball_uses_target_and_los", "fireball_power_formula",
		"fireball_rank_increases_expected_power", "fireball_mac_defence",
	],
	"wizard.repulsion_ring": [
		"repulsion_no_damage", "repulsion_lower_level_only", "repulsion_probability",
		"repulsion_push_distance", "repulsion_collision",
	],
	"wizard.temptation_light": [
		"temptation_monster_only", "temptation_boss_immune", "temptation_pet_cap",
		"temptation_tame_probability_deterministic", "temptation_failure_control",
		"temptation_not_six_second_generic_charm",
	],
	"wizard.hellfire": [
		"hellfire_exact_five_tile_line", "hellfire_width_one",
		"hellfire_stops_on_terrain", "hellfire_power_formula",
	],
	"wizard.lightning": [
		"lightning_is_sky_strike", "lightning_no_horizontal_projectile",
		"lightning_undead_multiplier", "lightning_power_formula",
	],
	"wizard.great_fireball": [
		"great_fireball_los", "great_fireball_power_formula",
		"great_fireball_expected_power_exceeds_or_differs_from_fireball",
	],
	"wizard.teleport": [
		"teleport_never_forward_dash", "teleport_probability_exact",
		"teleport_failure_stays_in_place", "teleport_destination_valid",
		"teleport_server_authoritative",
	],
	"wizard.exploding_flame": [
		"exploding_flame_target_centered", "exploding_flame_exact_3x3",
		"exploding_flame_power_formula",
	],
	"wizard.fire_wall": [
		"fire_wall_exact_2x2", "fire_wall_duration_scales",
		"fire_wall_tick_once_per_caster", "fire_wall_refresh_not_stack",
		"fire_wall_not_circle_or_cross",
	],
	"wizard.laser": [
		"laser_exact_eight_tile_line", "laser_width_one", "laser_pierces_units",
		"laser_stops_on_terrain", "laser_no_undead_bonus",
	],
	"wizard.hell_lightning": [
		"hell_lightning_max_24", "hell_lightning_caster_centered_radius_2",
		"hell_lightning_excludes_center", "hell_lightning_power_formula",
	],
	"wizard.magic_shield": [
		"magic_shield_reduction_increases_by_rank",
		"magic_shield_reduces_physical_and_magic", "magic_shield_duration_uses_mc",
		"magic_shield_refresh_not_stack",
	],
	"wizard.holy_word": [
		"holy_word_undead_only", "holy_word_boss_immune", "holy_word_probability_exact",
		"holy_word_success_kills", "holy_word_failure_no_damage",
		"holy_word_training_on_success_only",
	],
	"wizard.ice_storm": [
		"ice_storm_target_centered", "ice_storm_exact_3x3", "ice_storm_power_formula",
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
		"fireball_uses_target_and_los":
			return (
				not _support.execute(skill_id, 3, {"has_target": false}).accepted
				and not _support.execute(skill_id, 3, {"line_of_sight": false}).accepted
			)
		"fireball_power_formula":
			return _support.execute(skill_id, 3, {"primary_stat_roll": 12}).effects[0].raw_power == 17
		"fireball_rank_increases_expected_power":
			return _rank_power_increases(skill_id)
		"fireball_mac_defence":
			return _support.execute(skill_id, 3).effects[0].defence_type == "MAC"
		"repulsion_no_damage":
			return _support.execute(skill_id, 3).effects[0].damage == 0
		"repulsion_lower_level_only":
			var eligible := _support.execute(skill_id, 3, {
				"caster_level": 40, "targets": [{"level": 39, "force_success": true}],
			})
			var equal := _support.execute(skill_id, 3, {
				"caster_level": 40, "targets": [{"level": 40, "force_success": true}],
			})
			return eligible.effect_success and not equal.effect_success
		"repulsion_probability":
			var result := _support.execute(skill_id, 2, {
				"caster_level": 40, "targets": [{"level": 35, "force_success": true}],
			})
			return (
				is_equal_approx(float(result.effects[0].success_probability), 0.85)
				and _support.seeded_effect_outcomes(skill_id, 0, {
					"caster_level": 40,
					"force_success": false,
					"targets": [{"level": 39, "force_success": false}],
				})
			)
		"repulsion_push_distance":
			var distances: Array = []
			for rank in range(4):
				var result := _support.execute(skill_id, rank, {
					"targets": [{"level": 1, "force_success": true}],
				}, {}, 7)
				distances.append(int(result.effects[0].push_distance_tiles))
			return distances[0] in [1, 2] and distances[1] in [1, 2] and distances[2] in [2, 3] and distances[3] in [3, 4]
		"repulsion_collision":
			var blocked := _support.execute(skill_id, 3, {
				"targets": [{"level": 1, "force_success": true, "path_blocked": true}],
			})
			return not blocked.effect_success and not blocked.effects[0].displaced
		"temptation_monster_only":
			return not _support.execute(skill_id, 3, {"target_is_monster": false}).accepted
		"temptation_boss_immune":
			return not _support.execute(skill_id, 3, {"target_is_boss": true}).accepted
		"temptation_pet_cap":
			var tamed := _support.execute(skill_id, 3, {"forced_temptation_outcome": "tamed"})
			return tamed.effects[0].pet_cap == 5
		"temptation_tame_probability_deterministic":
			return (
				_support.deterministic(skill_id, {
					"forced_temptation_outcome": "", "target_is_undead": false,
				}, 219)
				and _support.seeded_effect_outcomes(skill_id, 3, {
					"forced_temptation_outcome": "",
					"force_success": false,
					"target_is_undead": false,
				})
			)
		"temptation_failure_control":
			var rooted := _support.execute(skill_id, 2, {
				"forced_temptation_outcome": "rooted", "forced_duration_seconds": 7,
			})
			var confused := _support.execute(skill_id, 2, {
				"forced_temptation_outcome": "confused", "forced_duration_seconds": 11,
			})
			return rooted.effects[0].duration_seconds == 7 and confused.effects[0].duration_seconds == 11
		"temptation_not_six_second_generic_charm":
			var tamed := _support.execute(skill_id, 3, {"forced_temptation_outcome": "tamed"})
			return tamed.effects[0].outcome == "tamed" and not tamed.effects[0].has("generic_charm_seconds")
		"hellfire_exact_five_tile_line":
			return _support.execute(skill_id, 3).geometry_cells.size() == 5
		"hellfire_width_one":
			return _support.execute(skill_id, 3).effects[0].width_tiles == 1
		"hellfire_stops_on_terrain":
			return bool(_support.execute(skill_id, 3).effects[0].stops_on_terrain)
		"hellfire_power_formula":
			return _support.execute(skill_id, 3, {"primary_stat_roll": 10}).effects[0].raw_power == 30
		"lightning_is_sky_strike":
			return _support.execute(skill_id, 3).effects[0].type == "targeted_sky_strike"
		"lightning_no_horizontal_projectile":
			return not bool(_support.execute(skill_id, 3).effects[0].horizontal_projectile)
		"lightning_undead_multiplier":
			var normal := _support.execute(skill_id, 3, {"target_is_undead": false}, {}, 5)
			var undead := _support.execute(skill_id, 3, {"target_is_undead": true}, {}, 5)
			return undead.effects[0].raw_power_after_race == roundi(float(normal.effects[0].raw_power) * 1.5)
		"lightning_power_formula":
			return _support.deterministic(skill_id, {"primary_stat_roll": 10}, 71)
		"great_fireball_los":
			return not _support.execute(skill_id, 3, {"line_of_sight": false}).accepted
		"great_fireball_power_formula":
			return _support.execute(skill_id, 3, {"primary_stat_roll": 10}).effects[0].raw_power == 26
		"great_fireball_expected_power_exceeds_or_differs_from_fireball":
			var great := _support.execute(skill_id, 3, {"primary_stat_roll": 10}, {}, 5)
			var basic := _support.execute("wizard.fireball", 3, {"primary_stat_roll": 10}, {}, 5)
			return great.effects[0].raw_power != basic.effects[0].raw_power
		"teleport_never_forward_dash":
			return not bool(_support.execute(skill_id, 3).effects[0].forward_dash)
		"teleport_probability_exact":
			var probabilities: Array = []
			for rank in range(4):
				probabilities.append(_support.execute(skill_id, rank).effects[0].success_probability)
			return (
				_floats_equal(probabilities, [4.0 / 11.0, 6.0 / 11.0, 8.0 / 11.0, 10.0 / 11.0])
				and _support.seeded_effect_outcomes(skill_id, 0, {
					"force_success": false, "force_failure": false,
				})
			)
		"teleport_failure_stays_in_place":
			var failed := _support.execute(skill_id, 3, {"force_success": false, "force_failure": true})
			return not failed.effects[0].moved and failed.effects[0].remain_in_place_on_failure
		"teleport_destination_valid":
			var invalid := _support.execute(skill_id, 3, {
				"force_success": true, "destination_valid": false,
			})
			return not invalid.effects[0].moved and invalid.effects[0].destination == null
		"teleport_server_authoritative":
			return bool(_support.execute(skill_id, 3).effects[0].server_authoritative)
		"exploding_flame_target_centered":
			return _support.execute(skill_id, 3, {"target_tile": Vector2i(8, 8)}).geometry_cells.has(Vector2i(8, 8))
		"exploding_flame_exact_3x3":
			return _support.execute(skill_id, 3).geometry_cells.size() == 9
		"exploding_flame_power_formula":
			return _support.execute(skill_id, 3, {"primary_stat_roll": 10}).effects[0].raw_power == 24
		"fire_wall_exact_2x2":
			return _support.execute(skill_id, 3).geometry_cells.size() == 4
		"fire_wall_duration_scales":
			var low := _support.execute(skill_id, 0, {"primary_stat_roll": 0})
			var high := _support.execute(skill_id, 3, {"primary_stat_roll": 20})
			return high.effects[0].duration_seconds > low.effects[0].duration_seconds
		"fire_wall_tick_once_per_caster":
			var field: Dictionary = _support.execute(skill_id, 3).effects[0]
			return field.tick_interval_ms == 1000 and field.max_ticks_per_target_per_caster == 1
		"fire_wall_refresh_not_stack":
			return str(_support.execute(skill_id, 3).effects[0].stacking_policy).contains("refresh")
		"fire_wall_not_circle_or_cross":
			var cells: Array = _support.execute(skill_id, 3).geometry_cells
			return cells.size() == 4 and cells.has(Vector2i(8, 8)) and cells.has(Vector2i(9, 9))
		"laser_exact_eight_tile_line":
			return _support.execute(skill_id, 3).geometry_cells.size() == 8
		"laser_width_one":
			return _support.execute(skill_id, 3).effects[0].width_tiles == 1
		"laser_pierces_units":
			return bool(_support.execute(skill_id, 3).effects[0].pierces_units)
		"laser_stops_on_terrain":
			return bool(_support.execute(skill_id, 3).effects[0].stops_on_terrain)
		"laser_no_undead_bonus":
			var normal := _support.execute(skill_id, 3, {"target_is_undead": false}, {}, 13)
			var undead := _support.execute(skill_id, 3, {"target_is_undead": true}, {}, 13)
			return normal.effects[0].raw_power == undead.effects[0].raw_power
		"hell_lightning_max_24":
			return _support.execute(skill_id, 3).effects[0].maximum_targets == 24
		"hell_lightning_caster_centered_radius_2":
			var ring := _support.execute(skill_id, 3)
			return ring.effects[0].radius_tiles == 2 and ring.geometry_cells.size() == 24
		"hell_lightning_excludes_center":
			return not _support.execute(skill_id, 3).geometry_cells.has(Vector2i.ZERO)
		"hell_lightning_power_formula":
			return _support.deterministic(skill_id, {"primary_stat_roll": 10}, 17)
		"magic_shield_reduction_increases_by_rank":
			return _floats_equal(
				_support.rank_effect_values(skill_id, "damage_reduction"),
				[0.15, 0.3, 0.45, 0.6]
			)
		"magic_shield_reduces_physical_and_magic":
			return _support.execute(skill_id, 3).effects[0].affected_damage_types == ["physical", "magic"]
		"magic_shield_duration_uses_mc":
			var low := _support.execute(skill_id, 3, {"primary_stat_roll": 0})
			var high := _support.execute(skill_id, 3, {"primary_stat_roll": 20})
			return high.effects[0].duration_seconds > low.effects[0].duration_seconds
		"magic_shield_refresh_not_stack":
			var shield: Dictionary = _support.execute(skill_id, 3).effects[0]
			return shield.stack_count_max == 1 and str(shield.stacking_policy).contains("refresh")
		"holy_word_undead_only":
			return not _support.execute(skill_id, 3, {"target_is_undead": false}).accepted
		"holy_word_boss_immune":
			return not _support.execute(skill_id, 3, {
				"target_is_undead": true, "target_is_boss": true,
			}).accepted
		"holy_word_probability_exact":
			var holy := _support.execute(skill_id, 2, {
				"target_is_undead": true, "caster_level": 40, "target_level": 35,
			})
			return (
				is_equal_approx(float(holy.effects[0].kill_probability), 0.34)
				and _support.seeded_effect_outcomes(skill_id, 0, {
					"target_is_undead": true,
					"caster_level": 40,
					"target_level": 39,
					"force_success": false,
				})
			)
		"holy_word_success_kills":
			return bool(_support.execute(skill_id, 3, {
				"target_is_undead": true, "force_success": true,
			}).effects[0].instant_kill)
		"holy_word_failure_no_damage":
			var failed := _support.execute(skill_id, 3, {
				"target_is_undead": true, "caster_level": 40, "target_level": 40,
				"force_success": false,
			})
			return not failed.effect_success and failed.effects[0].normal_damage == 0
		"holy_word_training_on_success_only":
			var success := _support.execute(skill_id, 3, {
				"target_is_undead": true, "force_success": true,
			})
			var failed := _support.execute(skill_id, 3, {
				"target_is_undead": true, "caster_level": 40, "target_level": 40,
				"force_success": false,
			})
			return not success.proficiency_event.is_empty() and failed.proficiency_event.is_empty()
		"ice_storm_target_centered":
			return _support.execute(skill_id, 3, {"target_tile": Vector2i(8, 8)}).geometry_cells.has(Vector2i(8, 8))
		"ice_storm_exact_3x3":
			return _support.execute(skill_id, 3).geometry_cells.size() == 9
		"ice_storm_power_formula":
			return _support.deterministic(skill_id, {"primary_stat_roll": 10}, 29)
		_:
			return false


func _rank_power_increases(skill_id: String) -> bool:
	var values := _support.rank_effect_values(skill_id, "raw_power", {"primary_stat_roll": 0})
	return values.size() == 4 and values[0] < values[1] and values[1] < values[2] and values[2] < values[3]


func _floats_equal(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index in range(actual.size()):
		if not is_equal_approx(float(actual[index]), float(expected[index])):
			return false
	return true
