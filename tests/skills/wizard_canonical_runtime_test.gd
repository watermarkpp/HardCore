extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	var fireball := _execute("wizard.fireball", {
		"has_target": true, "line_of_sight": true, "primary_stat_roll": 12,
	})
	assert(fireball.accepted and fireball.effects[0].type == "projectile_damage")
	assert(fireball.effects[0].raw_power == 17)
	assert(fireball.proficiency_event == "valid_projectile_cast_created")

	var repulsion := _execute("wizard.repulsion_ring", {
		"force_success": true,
		"targets": [{"level": 30, "instance_id": 417}],
	})
	assert(repulsion.effects.size() == 1 and repulsion.effects[0].displaced)
	assert(repulsion.effects[0].damage == 0)
	assert(repulsion.effects[0].target_instance_id == 417)
	assert(repulsion.proficiency_event == "at_least_one_target_displaced")
	var boss_repulsion := _execute("wizard.repulsion_ring", {
		"targets": [{"level": 1, "is_boss": true, "force_success": true}],
	})
	assert(not boss_repulsion.effect_success)
	assert(boss_repulsion.proficiency_event.is_empty())

	var temptation := _execute("wizard.temptation_light", {
		"has_target": true,
		"target_is_monster": true,
		"target_tameable": true,
		"target_level": 30,
		"target_max_hp": 200,
		"forced_temptation_outcome": "tamed",
	})
	assert(temptation.effects[0].outcome == "tamed")
	assert(temptation.effects[0].pet_cap == 5 and temptation.effects[0].pet_make_level == 3)
	assert(temptation.proficiency_event == "valid_attempt_reaches_tame_or_control_resolution")
	var temptation_no_effect := _execute("wizard.temptation_light", {
		"has_target": true,
		"target_is_monster": true,
		"forced_temptation_outcome": "no_effect",
	})
	assert(not temptation_no_effect.effect_success)
	assert(temptation_no_effect.proficiency_event.is_empty())

	var hellfire := _execute("wizard.hellfire", {
		"has_target": true, "primary_stat_roll": 10,
	})
	assert(hellfire.effects[0].length_tiles == 4)
	assert(is_equal_approx(float(hellfire.effects[0].width_tiles), 1.5))
	assert(not hellfire.effects[0].pierces_units and hellfire.geometry_cells.size() == 4)
	assert(hellfire.effects[0].maximum_targets == 0)
	assert(hellfire.effects[0].target_limit_policy == "all_intersecting_effect_cells")
	assert(
		hellfire.effects[0].target_selection_contract
		== "skills.wizard.hellfire.all_intersecting_4x1_5_user_override.v1"
	)
	assert(
		hellfire.effects[0].line_geometry_contract
		== "skills.wizard.line.continuous_tile_axis_footprint_sat.v1"
	)
	assert(not hellfire.effects[0].channeled)
	assert(
		hellfire.effects[0].cast_input_contract
		== "skills.wizard.hellfire.discrete_cast_hold_repeats_after_recast_gate.v1"
	)
	assert(hellfire.proficiency_event == "valid_cast_releases_line")

	var lightning := _execute("wizard.lightning", {
		"has_target": true,
		"line_of_sight": true,
		"target_is_undead": true,
		"primary_stat_roll": 10,
	})
	assert(lightning.effects[0].type == "targeted_sky_strike")
	assert(lightning.effects[0].race_multiplier == 1.5)
	assert(not lightning.effects[0].horizontal_projectile)

	var great_fireball := _execute("wizard.great_fireball", {
		"has_target": true, "line_of_sight": true, "primary_stat_roll": 10,
	})
	assert(great_fireball.effects[0].type == "projectile_damage")
	assert(great_fireball.proficiency_event == "valid_projectile_cast_created")

	var teleport := _execute("wizard.teleport", {
		"map_allows_random_teleport": true,
		"destination_valid": true,
		"destination_tile": Vector2i(18, 9),
		"force_success": true,
	})
	assert(teleport.effects[0].moved)
	assert(teleport.effects[0].destination == Vector2i(18, 9))
	assert(is_equal_approx(float(teleport.effects[0].success_probability), 10.0 / 11.0))
	assert(teleport.proficiency_event == "teleport_attempt_passes_eligibility_and_resolves")
	var disallowed_teleport := _execute("wizard.teleport", {
		"map_allows_random_teleport": false,
	})
	assert(not disallowed_teleport.accepted and not disallowed_teleport.resource_commit)

	var exploding := _execute("wizard.exploding_flame", {
		"has_target": true, "target_tile": Vector2i(10, 10), "primary_stat_roll": 9,
	})
	assert(exploding.effects[0].width_tiles == 3)
	assert(exploding.geometry_cells.size() == 9)
	assert(exploding.proficiency_event == "valid_area_cast_created")

	var fire_wall := _execute("wizard.fire_wall", {
		"has_target": true, "target_tile": Vector2i(10, 10), "primary_stat_roll": 8,
	})
	assert(fire_wall.geometry_cells.size() == 4)
	assert(fire_wall.effects[0].tick_interval_ms == 1000)
	assert(fire_wall.effects[0].duration_seconds == 14)
	assert(fire_wall.proficiency_event == "valid_fire_wall_field_created")

	var laser := _execute("wizard.laser", {
		"has_target": true, "primary_stat_roll": 11,
	})
	assert(laser.effects[0].pierces_units and laser.effects[0].length_tiles == 8)
	assert(
		laser.effects[0].line_geometry_contract
		== "skills.wizard.line.continuous_tile_axis_footprint_sat.v1"
	)
	assert(laser.geometry_cells.size() == 8)
	assert(laser.proficiency_event == "valid_line_cast_released")

	var hell_lightning := _execute("wizard.hell_lightning", {
		"primary_stat_roll": 12,
	})
	assert(hell_lightning.effects[0].maximum_targets == 24)
	assert(hell_lightning.geometry_cells.size() == 24)
	assert(hell_lightning.proficiency_event == "valid_area_cast_released")

	var shield := _execute("wizard.magic_shield", {"primary_stat_roll": 12})
	assert(shield.effects[0].damage_reduction == 0.6)
	assert(shield.effects[0].duration_seconds == 27)
	assert(shield.effects[0].stack_count_max == 1)
	assert(shield.timing.total_action_lock_ms == 1800)
	assert(shield.proficiency_event == "shield_buff_successfully_applied_or_refreshed")

	var holy_word := _execute("wizard.holy_word", {
		"has_target": true,
		"line_of_sight": true,
		"target_is_monster": true,
		"target_is_undead": true,
		"target_level": 30,
		"force_success": true,
	})
	assert(holy_word.effects[0].instant_kill and holy_word.effects[0].normal_damage == 0)
	assert(holy_word.proficiency_event == "instant_kill_success")
	assert(holy_word.timing.total_action_lock_ms == 1800)
	var failed_holy_word := _execute("wizard.holy_word", {
		"has_target": true,
		"line_of_sight": true,
		"target_is_monster": true,
		"target_is_undead": true,
		"target_level": 40,
	})
	assert(failed_holy_word.accepted and not failed_holy_word.effect_success)
	assert(failed_holy_word.effects[0].normal_damage == 0)
	assert(failed_holy_word.proficiency_event.is_empty())

	var ice_storm := _execute("wizard.ice_storm", {
		"has_target": true, "target_tile": Vector2i(12, 12), "primary_stat_roll": 10,
	})
	assert(ice_storm.geometry_cells.size() == 9)
	assert(ice_storm.effects[0].damage_type == "ice_magic")
	assert(ice_storm.proficiency_event == "valid_area_cast_released")

	for result: Dictionary in [
		fireball, repulsion, temptation, hellfire, lightning, great_fireball,
		teleport, exploding, fire_wall, laser, hell_lightning, shield, holy_word, ice_storm,
	]:
		assert(result.accepted)
		assert(result.timing.body_cast_ms == 600)
		assert(result.runtime_contract == Router.RUNTIME_CONTRACT_ID)
	print("WIZARD_CANONICAL_RUNTIME_PASS: fourteen skills, 600ms casts, tile geometry and exact state gates")
	get_tree().quit()


func _execute(skill_id: String, target_context: Dictionary) -> Dictionary:
	if not target_context.has("friendly"):
		target_context["friendly"] = false
	var request := Request.create(
		skill_id,
		3,
		40,
		Vector2i.ZERO,
		Vector2i.RIGHT,
		target_context,
		{"mana": 999, "materials": {}},
		17
	)
	return Router.execute(request)
