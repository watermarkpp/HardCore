extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const Policy := preload("res://scripts/skills/taoist_support_policy.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(Loader.reload_data().valid)
	_verify_single_heal_selection_and_rejection()
	_verify_mass_heal_3x3_around_selected()
	_verify_mass_invisibility_self_centered_3x3()
	_verify_defence_self_centered_7x7()
	print(
		"TAOIST_SUPPORT_RUNTIME_PASS: auto-selection, full-HP rejection, "
		+ "3x3 mass heal/invisibility, 7x7 defence, friendlies=self+summons"
	)
	get_tree().quit(0)


func _verify_single_heal_selection_and_rejection() -> void:
	var context := _base_context()
	var candidates := _candidates()
	context["friendly_candidates"] = candidates
	var plan := _plan("taoist.healing", context)
	assert(plan.accepted and plan.effect_success)
	assert(plan.effects[0].type == "dedicated_heal")
	assert(plan.effects[0].target_instance_id == 101)
	assert(plan.effects[0].target_is_self == false)
	assert(plan.support_targeting.selected.instance_id == 101)
	assert(plan.support_targeting.contract_id == Policy.CONTRACT_ID)
	assert(plan.support_targeting.range_gu == 9.0)
	assert(plan.effects[0].selection_contract_id == Policy.CONTRACT_ID)

	var full_context := _base_context()
	full_context["friendly_candidates"] = [
		Policy.make_candidate(55, true, 100, 100, Vector2(0, 0), 40),
		Policy.make_candidate(101, false, 80, 80, Vector2(1, 0), 5),
	]
	var full_plan := _plan("taoist.healing", full_context)
	assert(not full_plan.accepted)
	assert(full_plan.reason == Policy.REASON_ALL_FRIENDLY_TARGETS_FULL_HP)
	assert(not full_plan.resource_commit and not full_plan.effect_success)


func _verify_mass_heal_3x3_around_selected() -> void:
	var context := _base_context()
	context["has_target"] = true
	var candidates := _candidates()
	candidates.append(Policy.make_candidate(102, false, 20, 100, Vector2(5, 0), 5))
	context["friendly_candidates"] = candidates
	var plan := _plan("taoist.mass_healing", context)
	assert(plan.accepted and plan.effect_success)
	var effect: Dictionary = plan.effects[0]
	assert(effect.type == "dedicated_area_heal")
	assert(effect.selected_target_instance_id == 101)
	assert(effect.width_grid_steps == 3 and effect.height_grid_steps == 3)
	var geometry: Dictionary = plan.support_area_geometry
	assert(geometry.contract_id == "skills.taoist.friendly_area_geometry.v1")
	assert(geometry.shape == "square" and geometry.cell_count == 9)
	assert(geometry.center_tile == Vector2i(1, 0))
	assert(effect.affected_count == 2)
	assert(effect.target_instance_ids.has(55) and effect.target_instance_ids.has(101))
	assert(not effect.target_instance_ids.has(102))
	assert(effect.total_actual_hp_restored > 0)


func _verify_mass_invisibility_self_centered_3x3() -> void:
	var context := _base_context()
	context["has_target"] = true
	var candidates := _candidates()
	candidates.append(Policy.make_candidate(102, false, 50, 100, Vector2(10, 0), 5))
	context["friendly_candidates"] = candidates
	var plan := _plan("taoist.mass_invisibility", context)
	assert(plan.accepted and plan.effect_success)
	var effect: Dictionary = plan.effects[0]
	assert(effect.type == "area_monster_aggro_stealth")
	assert(effect.width_grid_steps == 3 and effect.height_grid_steps == 3)
	assert(effect.target_instance_ids.has(55) and effect.target_instance_ids.has(101))
	assert(not effect.target_instance_ids.has(102))
	var geometry: Dictionary = plan.support_area_geometry
	assert(geometry.shape == "square" and geometry.cell_count == 9)
	assert(geometry.center_tile == Vector2i(0, 0))
	assert(geometry.center_ground_gu == Vector2(0, 0))
	assert(plan.resource_commit)


func _verify_defence_self_centered_7x7() -> void:
	var context := _base_context()
	context["has_target"] = true
	var candidates := _candidates()
	candidates.append(Policy.make_candidate(102, false, 50, 100, Vector2(10, 0), 5))
	context["friendly_candidates"] = candidates
	var plan := _plan("taoist.magic_defense", context)
	assert(plan.accepted and plan.effect_success)
	assert(plan.effects.size() == 2)
	assert(plan.effects[0].stat == "MAC" and plan.effects[1].stat == "MAC")
	var geometry: Dictionary = plan.support_area_geometry
	assert(geometry.shape == "chebyshev_area")
	assert(geometry.radius_grid_steps == 3 and geometry.cell_count == 49)
	assert(geometry.center_tile == Vector2i(0, 0))
	assert(plan.effects[0].target_instance_id == 55)
	assert(plan.effects[0].value == 5)
	assert(plan.effects[1].target_instance_id == 101)
	assert(plan.effects[1].value == 1)
	assert(plan.effects[0].rank == 3 and plan.effects[0].skill_id == "taoist.magic_defense")
	assert(not plan.has("combined_skill_ids"))


func _base_context() -> Dictionary:
	return {
		"has_target": false,
		"line_of_sight": true,
		"friendly": true,
		"hostile": false,
		"target_tile": Vector2i(0, 0),
		"caster_ground_position_gu": Vector2(0, 0),
		"primary_stat_roll": 8,
	}


func _candidates() -> Array:
	return [
		Policy.make_candidate(55, true, 40, 100, Vector2(0, 0), 40),
		Policy.make_candidate(101, false, 5, 100, Vector2(1, 0), 7),
	]


func _plan(skill_id: String, context: Dictionary) -> Dictionary:
	var request := Request.create(
		skill_id,
		3,
		40,
		Vector2i.ZERO,
		Vector2i.DOWN,
		context,
		{"mana": 999, "materials": {}},
		23
	)
	return Router._plan(request)
