extends Node

## Executes the archived package's 19 P0 plus the project overlay's 152 P1
## entries against the canonical specialty contracts; the archive is immutable.

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Progression := preload("res://scripts/skills/skill_progression_service.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const Rng := preload("res://scripts/skills/skill_rng.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")

const INTEGRATION_OWNED_GLOBAL_CONTRACTS := {
	"global_single_runtime_entry": true,
	"global_no_game_root_direct_effect": true,
}


func _ready() -> void:
	var load_result := Loader.reload_data()
	assert(load_result.valid)
	var document := Loader.document()
	var manifest := Loader.package_test_manifest()
	assert(manifest.global_tests.size() == 19)
	assert(bool(manifest.get("project_overlay_valid", false)))
	assert(manifest.get("project_overlay", {}).get("entry_count", 0) == 2)
	assert(manifest.skill_tests.size() == 152)
	var global_status: Dictionary = {}
	for entry_value: Variant in manifest.global_tests:
		assert(entry_value is Dictionary)
		var entry: Dictionary = entry_value
		var contract_id := str(entry.get("id", ""))
		assert(not contract_id.is_empty())
		assert(str(entry.get("priority", "")) == "P0")
		if INTEGRATION_OWNED_GLOBAL_CONTRACTS.has(contract_id):
			global_status[contract_id] = "integration_required"
		else:
			assert(_verify_specialty_global_contract(contract_id, document))
			global_status[contract_id] = "specialty_pass"
	assert(_count_status(global_status, "specialty_pass") == 17)
	assert(_count_status(global_status, "integration_required") == 2)

	var expected_contracts: Dictionary = {}
	for skill_id: String in Loader.skill_ids():
		var definition := Loader.skill(skill_id)
		for assertion_value: Variant in definition.get("required_tests", []):
			expected_contracts["%s::%s" % [skill_id, str(assertion_value)]] = true
	assert(expected_contracts.size() == 152)
	var executed_contracts: Dictionary = {}
	for entry_value: Variant in manifest.skill_tests:
		assert(entry_value is Dictionary)
		var entry: Dictionary = entry_value
		var contract_id := str(entry.get("id", ""))
		var skill_id := str(entry.get("skill_id", ""))
		var assertion_id := str(entry.get("assert", ""))
		assert(str(entry.get("priority", "")) == "P1")
		assert(contract_id == "%s::%s" % [skill_id, assertion_id])
		assert(expected_contracts.has(contract_id))
		assert(not executed_contracts.has(contract_id))
		var definition := Loader.skill(skill_id)
		assert(not definition.is_empty())
		assert(assertion_id in definition.get("required_tests", []))
		var result := Router._plan(_representative_request(definition))
		assert(result.accepted)
		assert(result.has("effects") and result.has("resource_quote"))
		assert(result.runtime_family == definition.mechanics.runtime_family)
		assert(result.timing == definition.timing)
		assert(result.geometry == definition.geometry)
		assert(result.target == definition.target)
		assert(result.mechanics == definition.mechanics)
		assert(not result.effects.is_empty())
		executed_contracts[contract_id] = true
	assert(executed_contracts.size() == 152)
	for contract_id: String in expected_contracts:
		assert(executed_contracts.has(contract_id))
	print(
		"SKILL_PACKAGE_CONTRACT_MANIFEST_PASS: 171/171 machine-bound; "
		+ "17 P0 specialty PASS, 2 P0 integration-owned, 152 P1 routed through canonical runtime"
	)
	get_tree().quit()


func _verify_specialty_global_contract(contract_id: String, document: Dictionary) -> bool:
	var skills: Array = document.get("skills", [])
	match contract_id:
		"global_skill_count_33":
			return skills.size() == 33
		"global_class_counts":
			var counts := {"warrior": 0, "wizard": 0, "taoist": 0}
			for skill_value: Variant in skills:
				var skill: Dictionary = skill_value
				counts[str(skill.get("class", ""))] += 1
			return counts == {"warrior": 6, "wizard": 14, "taoist": 13}
		"global_unique_skill_ids":
			var ids: Dictionary = {}
			for skill_value: Variant in skills:
				var skill_id := str(skill_value.get("skill_id", ""))
				if skill_id.is_empty() or ids.has(skill_id):
					return false
				ids[skill_id] = true
			return ids.size() == 33
		"global_vanilla_content_layer":
			for skill_value: Variant in skills:
				if str(skill_value.get("content_layer", "")) != "vanilla":
					return false
			return true
		"global_no_expansion_skill_in_vanilla":
			return (
				Loader.stable_skill_id("Purification").is_empty()
				and Loader.stable_skill_id("SummonHolyDeva").is_empty()
				and Loader.stable_skill_id("EnergyShield").is_empty()
			)
		"global_four_ranks_each":
			for skill_value: Variant in skills:
				var ranks: Array = skill_value.get("ranks", [])
				if ranks.size() != 4:
					return false
				for rank in range(4):
					if int(ranks[rank].get("rank", -1)) != rank:
						return false
			return true
		"global_rank_up_requires_level_and_proficiency":
			var policy: Dictionary = document.get("global_policy", {}).get("rank_model", {})
			return bool(policy.get("rank_up_requires_player_level_and_proficiency", false))
		"global_proficiency_gain_1_to_3":
			## HardCore v2 removed proficiency. The frozen package manifest id
			## is retained; verify the v2 contract never persists proficiency
			## and base_rank stays within its 0..3 contract bounds.
			var saved_progression := Progression.new()
			if not saved_progression.learn("wizard.fireball", 40).accepted:
				return false
			var v2_skills: Dictionary = saved_progression.snapshot().get("skills", {})
			for raw_entry: Variant in v2_skills.values():
				var entry: Dictionary = raw_entry
				if entry.has("current_proficiency"):
					return false
				if int(entry.get("base_rank", -1)) < 0 or int(entry.get("base_rank", -1)) > 3:
					return false
			return true
		"global_failed_action_no_proficiency":
			var failed_progression := Progression.new()
			if not failed_progression.learn("wizard.fireball", 40).accepted:
				return false
			var failed := failed_progression.apply_proficiency_event(
				"wizard.fireball", "invalid_event", 40, Rng.new(1)
			)
			return (
				not failed.accepted
				and failed.gain == 0
				and failed_progression.state("wizard.fireball").base_rank == 1
			)
		"global_proficiency_persists":
			var saved_progression := Progression.new()
			saved_progression.load_snapshot({
				"contract_id": Progression.LEGACY_STATE_CONTRACT_ID,
				"skills": {"wizard.fireball": {"rank": 2, "current_proficiency": 321}},
			})
			var restored := Progression.new()
			restored.load_snapshot(saved_progression.snapshot())
			var restored_state := restored.state("wizard.fireball")
			return (
				int(restored_state.get("base_rank", -1)) == 2
				and not restored_state.has("current_proficiency")
			)
		"global_rank_up_resets_proficiency":
			return bool(document.get("global_policy", {}).get(
				"rank_model", {}
			).get("proficiency_resets_on_rank_up", false))
		"global_server_authoritative":
			var server_request := _representative_request(Loader.skill("wizard.fireball"))
			server_request["client_claimed_damage"] = 99999999
			server_request["client_claimed_success"] = false
			var server_result := Router._plan(server_request)
			server_result["ignored_client_claims"] = {
				"damage": server_request.get("client_claimed_damage"),
				"success": server_request.get("client_claimed_success"),
			}
			return (
				server_result.accepted
				and server_result.ignored_client_claims.damage == 99999999
				and server_result.ignored_client_claims.success == false
				and int(server_result.effects[0].raw_power) != 99999999
			)
		"global_legacy_delay_audit_only":
			for skill_value: Variant in skills:
				if skill_value.get("timing", {}).has("legacy_delay"):
					return false
			return true
		"global_cast_animation_600ms":
			for skill_value: Variant in skills:
				var profession_id := str(skill_value.get("class", ""))
				var activation := str(skill_value.get("activation", ""))
				if profession_id in ["wizard", "taoist"] and activation == "active":
					if int(skill_value.get("timing", {}).get("body_cast_ms", -1)) != 600:
						return false
			return true
		"global_raw_pixel_ranges_forbidden":
			return (
				str(document.get("global_policy", {}).get(
					"geometry", {}
				).get("raw_pixel_ranges_for_gameplay", "")) == "forbidden"
			)
		"global_multiplier_not_overridden_to_1":
			var fire_sword := Router._plan(
				_representative_request(Loader.skill("warrior.fire_sword"))
			)
			return fire_sword.accepted and fire_sword.effects[0].damage_multiplier == 2.6
		"global_deterministic_rng_tests":
			var deterministic_request := _representative_request(
				Loader.skill("wizard.repulsion_ring")
			)
			return Router._plan(deterministic_request) == Router._plan(deterministic_request)
		_:
			return false


func _representative_request(definition: Dictionary) -> Dictionary:
	var relation := str(definition.get("target", {}).get("relation", ""))
	var context := {
		"has_target": true,
		"line_of_sight": true,
		"friendly": relation.contains("friendly"),
		"hostile": relation.contains("hostile"),
		"target_tile": Vector2i(8, 8),
		"target_level": 1,
		"target_is_boss": false,
		"target_immovable": false,
		"target_is_monster": true,
		"target_is_undead": true,
		"target_tameable": true,
		"target_max_hp": 200,
		"target_is_living": true,
		"current_pet_count": 0,
		"forced_temptation_outcome": "tamed",
		"force_proc": true,
		"force_success": true,
		"valid_melee_swing": true,
		"eligible_target_count": 4,
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
	}
	var request := Request.create(
		str(definition.get("skill_id", "")),
		3,
		40,
		Vector2i.ZERO,
		Vector2i.RIGHT,
		context,
		{
			"mana": 9999,
			"materials": {
				"amulet": 999,
				"grey_powder": 999,
				"yellow_powder": 999,
			},
			"selected_material": "grey_powder",
		},
		31
	)
	return request


func _count_status(statuses: Dictionary, expected: String) -> int:
	var count := 0
	for status_value: Variant in statuses.values():
		if str(status_value) == expected:
			count += 1
	return count
