extends Node

## Frozen _plan outputs from baseline 78a79797, generated with that commit's
## router/resolver/resource service and profession runtimes. Every skill and
## rank 0..3 has an accepted, deterministic request. Canonical release
## snapshots are covered separately by the production golden-plan suite.

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const PlanContract := preload("res://scripts/skills/skill_execution_plan_contract.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	var file := FileAccess.open(
		"res://tests/fixtures/skill_rank_zero_three_baseline_78a79797.json",
		FileAccess.READ,
	)
	assert(file != null, "frozen pre-V2 baseline fixture is required")
	var fixture: Variant = JSON.parse_string(file.get_as_text())
	assert(fixture is Dictionary)
	assert(str(fixture.get("baseline_sha", "")) == "78a797973409c0ce47590b928f3d26ff067fe567")
	var rows: Dictionary = fixture.get("rows", {})
	assert(rows.size() == 132)
	for skill_id: String in Loader.skill_ids():
		for rank in range(4):
			var request := Request.create(
				skill_id, rank, 40, Vector2i.ZERO, Vector2i.RIGHT,
				_context(skill_id), _resources(), 31,
			)
			var plan: Dictionary = Router._plan(request)
			var key := "%s:%d" % [skill_id, rank]
			var expected: Dictionary = rows.get(key, {})
			var actual := _comparable(plan)
			for field: String in expected:
				assert(
					actual.get(field) == expected[field],
					"frozen rank0-3 mismatch %s.%s: expected %s, actual %s"
					% [key, field, expected[field], actual.get(field)],
				)
	print("SKILL_RANK_ZERO_THREE_MATRIX_PASS rows=132")
	get_tree().quit()


func _comparable(plan: Dictionary) -> Dictionary:
	var result := {}
	for key: String in ["accepted", "reason", "effects", "resource_quote", "timing", "geometry", "target", "resource", "mechanics", "geometry_cells", "effective_rank"]:
		var value: Variant = plan.get(key, null)
		if key == "effects" and value is Array:
			value = (value as Array).duplicate(true)
			for raw_effect: Variant in value:
				if raw_effect is Dictionary and str((raw_effect as Dictionary).get("type", "")) == "main_pet_spawn":
					# V2 adds an identity field for extra skeletons; slot 0 keeps
					# the frozen single-pet combat effect.
					(raw_effect as Dictionary).erase("pet_slot_index")
		result[key] = PlanContract._canonicalize(value)
	return result


func _context(skill_id: String) -> Dictionary:
	var result := {
		"has_target": true, "line_of_sight": true, "hostile": true,
		"friendly": false, "target_tile": Vector2i(8, 8), "target_level": 1,
		"target_is_boss": false, "target_immovable": false,
		"target_is_monster": true, "target_is_undead": true,
		"target_tameable": true, "target_max_hp": 200,
		"target_is_living": true, "current_pet_count": 0,
		"forced_temptation_outcome": "tamed", "force_proc": true,
		"force_success": true, "valid_melee_swing": true,
		"eligible_target_count": 4, "charge_consumed": true,
		"map_allows_random_teleport": true, "destination_valid": true,
		"destination_tile": Vector2i(12, 12),
		"targets": [{"level": 1, "hostile_monster": true, "force_success": true}],
		"actual_hp_missing": 100, "friendly_missing_hp": [100],
		"friendly_targets": [{"level": 35}], "affected_friendly_count": 1,
		"primary_stat_roll": 10, "spawn_tile_valid": true,
		"has_main_pet": false,
	}
	if skill_id in ["taoist.defense", "taoist.healing", "taoist.magic_defense", "taoist.mass_healing", "taoist.mass_invisibility"]:
		result["friendly"] = true
		result["hostile"] = false
	return result


func _resources() -> Dictionary:
	return {
		"mana": 9999,
		"materials": {"amulet": 999, "grey_powder": 999, "yellow_powder": 999},
		"selected_material": "grey_powder",
	}
