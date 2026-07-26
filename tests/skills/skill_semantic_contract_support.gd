class_name SkillSemanticContractSupport
extends RefCounted

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")


func definition(skill_id: String) -> Dictionary:
	return Loader.skill(skill_id)


func execute(
	skill_id: String,
	rank := 3,
	context_overrides := {},
	resource_overrides := {},
	seed_value := 41
) -> Dictionary:
	var definition_value := definition(skill_id)
	var relation := str(definition_value.get("target", {}).get("relation", ""))
	var context := {
		"has_target": true,
		"line_of_sight": true,
		"friendly": relation.contains("friendly"),
		"hostile": relation.contains("hostile"),
		"target_tile": Vector2i(8, 8),
		"target_level": 1,
		"target_is_monster": true,
		"target_is_living": true,
		"target_is_undead": false,
		"target_tameable": true,
		"target_max_hp": 200,
		"current_pet_count": 0,
		"eligible_target_count": 4,
		"valid_melee_swing": true,
		"force_proc": true,
		"force_success": true,
		"charge_consumed": true,
		"map_allows_random_teleport": true,
		"destination_valid": true,
		"destination_tile": Vector2i(12, 12),
		"targets": [{"level": 1, "hostile_monster": true, "force_success": true}],
		"actual_hp_missing": 100,
		"friendly_missing_hp": [100],
		"friendly_targets": [{"level": 35}],
		"affected_friendly_count": 1,
		"primary_stat_roll": 10,
		"spawn_tile_valid": true,
		"has_main_pet": false,
		"forced_temptation_outcome": "tamed",
	}
	for key: Variant in context_overrides:
		context[key] = context_overrides[key]
	var resources := {
		"mana": 9999,
		"materials": {
			"amulet": 999,
			"grey_powder": 999,
			"yellow_powder": 999,
		},
		"selected_material": "grey_powder",
	}
	for key: Variant in resource_overrides:
		resources[key] = resource_overrides[key]
	return Router.execute(Request.create(
		skill_id,
		rank,
		int(context.get("caster_level", 40)),
		Vector2i.ZERO,
		Vector2i.RIGHT,
		context,
		resources,
		seed_value
	))


func execute_facing(
	skill_id: String,
	rank: int,
	facing: Vector2i,
	context_overrides := {},
	seed_value := 41
) -> Dictionary:
	var definition_value := definition(skill_id)
	var relation := str(definition_value.get("target", {}).get("relation", ""))
	var context := {
		"has_target": true,
		"line_of_sight": true,
		"friendly": relation.contains("friendly"),
		"hostile": relation.contains("hostile"),
		"target_tile": Vector2i(8, 8),
		"eligible_target_count": 4,
	}
	for key: Variant in context_overrides:
		context[key] = context_overrides[key]
	return Router.execute(Request.create(
		skill_id,
		rank,
		int(context.get("caster_level", 40)),
		Vector2i.ZERO,
		facing,
		context,
		{"mana": 9999, "materials": {"amulet": 999}, "selected_material": "amulet"},
		seed_value
	))


func rank_effect_values(
	skill_id: String,
	field: String,
	context_overrides := {}
) -> Array:
	var values: Array = []
	for rank in range(4):
		var result := execute(skill_id, rank, context_overrides)
		if not result.accepted or result.effects.is_empty():
			return []
		values.append(result.effects[0].get(field))
	return values


func deterministic(skill_id: String, context_overrides := {}, seed_value := 83) -> bool:
	return (
		execute(skill_id, 3, context_overrides, {}, seed_value)
		== execute(skill_id, 3, context_overrides, {}, seed_value)
	)


func seeded_effect_outcomes(
	skill_id: String,
	rank: int,
	context_overrides := {},
	max_seed := 512
) -> bool:
	var saw_success := false
	var saw_failure := false
	for seed_value in range(max_seed):
		var result := execute(skill_id, rank, context_overrides, {}, seed_value)
		if not result.accepted:
			continue
		if bool(result.get("effect_success", false)):
			saw_success = true
		else:
			saw_failure = true
		if saw_success and saw_failure:
			return true
	return false


func all_unique(values: Array) -> bool:
	var seen: Dictionary = {}
	for value: Variant in values:
		seen[value] = true
	return seen.size() == values.size()
