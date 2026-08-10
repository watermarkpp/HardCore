extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const VisibilityPolicy := preload(
	"res://scripts/skills/skill_visibility_policy.gd"
)


func _ready() -> void:
	assert(Loader.reload_data().valid)
	var healing := _execute("taoist.healing", {
		"has_target": true,
		"actual_hp_missing": 10,
		"primary_stat_roll": 8,
	})
	assert(healing.effects[0].type == "dedicated_heal")
	assert(healing.effects[0].actual_hp_restored == 10)
	assert(not healing.effects[0].negative_damage)
	assert(healing.proficiency_event.is_empty())
	var full_hp_healing := _execute("taoist.healing", {
		"has_target": true, "actual_hp_missing": 0, "primary_stat_roll": 8,
	})
	assert(full_hp_healing.accepted)
	assert(full_hp_healing.effect_success)
	assert(full_hp_healing.resource_commit)
	assert(full_hp_healing.effects[0].actual_hp_restored == 0)
	var full_ongoing: Dictionary = full_hp_healing.effects[0].get(
		"ongoing_heal",
		{}
	)
	assert(
		not full_ongoing.is_empty()
		and full_ongoing.contract_id == "skills.taoist.ongoing_heal.v1"
	)
	assert(int(full_ongoing.get("tick_count", 0)) == 3)
	assert(full_hp_healing.proficiency_event.is_empty())

	var spiritual := _execute("taoist.spiritual_warfare", {
		"valid_melee_swing": true,
	})
	assert(spiritual.effects[0].value == 8)
	assert(spiritual.proficiency_event.is_empty())

	var dual_poison := _execute("taoist.poison", {
		"has_target": true,
		"line_of_sight": true,
		"force_success": true,
		"primary_stat_roll": 10,
	}, "")
	assert(dual_poison.effects.size() == 2)
	assert(dual_poison.effects[0].poison_type == "green_poison")
	assert(dual_poison.effects[1].poison_type == "red_poison")
	assert(dual_poison.effects[0].tick_interval_ms == 2000)
	assert(dual_poison.effects[1].flat_ac_reduction == dual_poison.effects[1].flat_mac_reduction)
	assert(dual_poison.effects[1].extra_durability_loss_per_hit == 1)
	assert(dual_poison.effects[0].resisted == dual_poison.effects[1].resisted)
	assert(dual_poison.effects[0].apply_probability == dual_poison.effects[1].apply_probability)
	assert(dual_poison.effects[0].duration_seconds == dual_poison.effects[1].duration_seconds)
	assert(dual_poison.resource_quote.material_id == "")
	assert(dual_poison.resource_quote.material_amount == 0)
	assert(dual_poison.resource_quote.material_free)
	assert(
		dual_poison.resource_quote.material_policy_contract_id
		== "skills.taoist.material_free.v1"
	)
	var poison_definition := Loader.skill("taoist.poison")
	assert(
		dual_poison.resource_quote.mp_cost
		== int(poison_definition.get("mp_cost_by_rank", [])[3]) * 2
	)
	assert(dual_poison.proficiency_event.is_empty())
	var resisted_poison := _execute("taoist.poison", {
		"has_target": true,
		"line_of_sight": true,
		"force_resist": true,
	}, "grey_powder")
	assert(not resisted_poison.effect_success and resisted_poison.resource_commit)
	assert(resisted_poison.effects.size() == 2)
	assert(resisted_poison.effects[0].resisted and resisted_poison.effects[1].resisted)
	assert(resisted_poison.effects[0].apply_probability == resisted_poison.effects[1].apply_probability)
	assert(resisted_poison.proficiency_event.is_empty())
	var invalid_poison := _execute("taoist.poison", {
		"has_target": false,
		"line_of_sight": false,
	}, "")
	assert(not invalid_poison.accepted and not invalid_poison.resource_commit)

	var talisman := _execute("taoist.soul_fire_talisman", {
		"has_target": true,
		"line_of_sight": true,
		"primary_stat_roll": 11,
	})
	assert(talisman.effects[0].type == "talisman_projectile_damage")
	assert(talisman.effects[0].damage_type == "spirit_magic")
	assert(talisman.resource_quote.material_id == "")
	assert(talisman.resource_quote.material_amount == 0)
	assert(talisman.proficiency_event.is_empty())

	var skeleton := _execute("taoist.summon_skeleton", {
		"spawn_tile_valid": true,
	})
	assert(skeleton.effects[0].spawned)
	assert(skeleton.effects[0].initial_pet_level == 3)
	assert(skeleton.effects[0].max_pet_level == 7)
	assert(not skeleton.effects[0].skill_rank_is_pet_level)
	assert(skeleton.resource_quote.material_id == "")
	assert(skeleton.resource_quote.material_amount == 0)
	assert(skeleton.resource_commit_required == skeleton.resource_commit)
	assert(skeleton.proficiency_event.is_empty())
	var recalled_skeleton := _execute("taoist.summon_skeleton", {
		"has_main_pet": true,
	}, "", 0)
	assert(recalled_skeleton.accepted and recalled_skeleton.effects[0].type == "recall_existing_main_pet")
	assert(not recalled_skeleton.resource_commit)
	assert(not recalled_skeleton.resource_commit_required)
	assert(recalled_skeleton.resource_quote.material_amount == 0)
	assert(recalled_skeleton.proficiency_event.is_empty())

	var invisibility := _execute("taoist.invisibility", {
		"primary_stat_roll": 5,
	})
	assert(invisibility.effects[0].duration_seconds == 45)
	assert(invisibility.effects[0].break_on_tile_movement)
	assert(invisibility.effects[0].break_on_melee_attack)
	assert(invisibility.effects[0].break_on_ranged_spell_cast)
	assert(not invisibility.effects[0].pvp_invisibility)
	assert(invisibility.proficiency_event.is_empty())

	var mass_invisibility := _execute("taoist.mass_invisibility", {
		"has_target": true,
		"target_tile": Vector2i(10, 10),
		"affected_friendly_count": 2,
		"affected_friendly_target_instance_ids": [101, 102],
		"primary_stat_roll": 4,
	})
	assert(mass_invisibility.geometry_cells.size() == 9)
	assert(mass_invisibility.effects[0].affected_count == 2)
	assert(mass_invisibility.effects[0].target_instance_ids == [101, 102])
	assert(mass_invisibility.resource_commit)
	assert(mass_invisibility.proficiency_event.is_empty())
	var empty_mass_invisibility := _execute("taoist.mass_invisibility", {
		"has_target": true,
		"affected_friendly_count": 0,
	})
	assert(not empty_mass_invisibility.effect_success)
	assert(not empty_mass_invisibility.resource_commit)

	var soul_shield := _execute("taoist.magic_defense", {
		"has_target": true,
		"target_tile": Vector2i(10, 10),
		"friendly_targets": [{"level": 35, "target_instance_id": 201}],
		"primary_stat_roll": 4,
	})
	assert(soul_shield.geometry_cells.size() == 49)
	assert(soul_shield.effects[0].stat == "MAC")
	assert(soul_shield.effects[0].flat_bonus == 5)
	assert(soul_shield.effects[0].duration_seconds == 10)
	assert(soul_shield.effects[0].target_instance_id == 201)
	assert(str(soul_shield.effects[0].stacking_policy).contains("blessed_armour"))

	var blessed_armour := _execute("taoist.defense", {
		"has_target": true,
		"target_tile": Vector2i(10, 10),
		"friendly_targets": [{"level": 35, "target_instance_id": 202}],
		"primary_stat_roll": 4,
	})
	assert(blessed_armour.effects[0].stat == "AC")
	assert(blessed_armour.effects[0].flat_bonus == 5)
	assert(blessed_armour.effects[0].target_instance_id == 202)
	assert(str(blessed_armour.effects[0].stacking_policy).contains("soul_shield"))

	var revelation := _execute("taoist.revelation", {
		"has_target": true,
		"line_of_sight": true,
		"target_is_living": true,
		"primary_stat_roll": 5,
	})
	assert(revelation.effects[0].revealed)
	assert(revelation.effects[0].success_probability == 1.0)
	assert(revelation.effects[0].duration_ms == 40000)
	assert(revelation.effects[0].damage == 0)
	assert(not revelation.effects[0].target_stat_modification)

	var entrapment := _execute("taoist.entrapment", {
		"has_target": true,
		"target_instance_id": 301,
		"target_is_monster": true,
		"target_is_boss": false,
		"target_control_immune": false,
		"target_within_level_gate": true,
		"primary_stat_roll": 3,
	})
	assert(entrapment.effects[0].trapped_count == 1)
	assert(entrapment.effects[0].target_instance_ids == [301])
	assert(entrapment.effects[0].prevents_boundary_exit)
	assert(entrapment.effects[0].break_on_any_player_entry)
	assert(not entrapment.effects[0].generic_root)
	assert(entrapment.resource_commit)
	assert(entrapment.geometry_cells.size() == 8)
	var boss_only_entrapment := _execute("taoist.entrapment", {
		"has_target": true,
		"target_instance_id": 302,
		"target_is_monster": true,
		"target_is_boss": true,
		"target_control_immune": true,
		"target_within_level_gate": true,
	})
	assert(not boss_only_entrapment.effect_success)
	assert(not boss_only_entrapment.resource_commit)
	assert(boss_only_entrapment.proficiency_event.is_empty())

	var immune_entrapment := _execute("taoist.entrapment", {
		"has_target": true,
		"target_instance_id": 303,
		"target_is_monster": true,
		"target_is_boss": false,
		"target_control_immune": true,
		"target_within_level_gate": true,
	})
	assert(not immune_entrapment.effect_success)
	assert(not immune_entrapment.resource_commit)
	var gated_entrapment := _execute("taoist.entrapment", {
		"has_target": true,
		"target_instance_id": 304,
		"target_is_monster": true,
		"target_is_boss": false,
		"target_control_immune": false,
		"target_within_level_gate": false,
	})
	assert(not gated_entrapment.effect_success)
	assert(not gated_entrapment.resource_commit)

	var mass_healing := _execute("taoist.mass_healing", {
		"has_target": true,
		"target_tile": Vector2i(12, 12),
		"friendly_missing_hp": [5, 20, 0],
		"friendly_target_instance_ids": [401, 402, 403],
		"primary_stat_roll": 6,
	})
	assert(mass_healing.geometry_cells.size() == 9)
	assert(mass_healing.effects[0].type == "dedicated_area_heal")
	assert(mass_healing.effects[0].total_actual_hp_restored > 0)
	assert(mass_healing.effects[0].target_instance_ids == [401, 402, 403])
	assert(mass_healing.effects[0].target_results[1].target_instance_id == 402)
	assert(not mass_healing.effects[0].negative_damage)
	assert(mass_healing.proficiency_event.is_empty())

	var divine_beast := _execute("taoist.summon_divine_beast", {
		"spawn_tile_valid": true,
	})
	assert(divine_beast.effects[0].template_id == "divine_beast")
	assert(divine_beast.effects[0].initial_pet_level == 3)
	assert(divine_beast.effects[0].max_pet_level == 7)
	assert(divine_beast.resource_quote.material_id == "")
	assert(divine_beast.resource_quote.material_amount == 0)
	assert(divine_beast.resource_commit_required == divine_beast.resource_commit)
	assert(divine_beast.proficiency_event.is_empty())

	## Revelation stays fully present in data/code (stable ID preserved) while
	## the visibility policy hides it from the visible/usable skill system.
	var revelation_definition := Loader.skill("taoist.revelation")
	assert(not revelation_definition.is_empty())
	assert(not VisibilityPolicy.is_skill_visible("taoist.revelation"))
	assert(not VisibilityPolicy.is_skill_castable("taoist.revelation"))
	assert(VisibilityPolicy.is_skill_visible("taoist.poison"))
	assert(VisibilityPolicy.is_skill_castable("taoist.poison"))

	for result: Dictionary in [
		healing, spiritual, dual_poison, talisman, skeleton,
		recalled_skeleton, invisibility, mass_invisibility, soul_shield,
		blessed_armour, revelation, entrapment, mass_healing, divine_beast,
	]:
		assert(result.accepted)
		assert(result.has("effects") and result.has("proficiency_event"))
		assert(
			bool(result.resource_commit_required)
			== bool(result.resource_commit)
		)
	print("TAOIST_CANONICAL_RUNTIME_PASS: thirteen skills, material-free dual poison/pets, buffs, healing and boundary control")
	get_tree().quit()


func _execute(
	skill_id: String,
	target_context: Dictionary,
	_selected_material := "amulet",
	_material_count := 99
) -> Dictionary:
	if not target_context.has("friendly"):
		target_context["friendly"] = false
	if not target_context.has("hostile"):
		target_context["hostile"] = false
	var request := Request.create(
		skill_id,
		3,
		40,
		Vector2i.ZERO,
		Vector2i.RIGHT,
		target_context,
		{
			"mana": 999,
			"materials": {},
		},
		23
	)
	return Router._plan(request)
