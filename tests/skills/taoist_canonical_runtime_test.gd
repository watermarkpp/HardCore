extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")


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
	assert(healing.proficiency_event == "actual_hp_restored_gt_zero")
	var full_hp_healing := _execute("taoist.healing", {
		"has_target": true, "actual_hp_missing": 0, "primary_stat_roll": 8,
	})
	assert(not full_hp_healing.effect_success)
	assert(full_hp_healing.proficiency_event.is_empty())

	var spiritual := _execute("taoist.spiritual_warfare", {
		"valid_melee_swing": true,
	})
	assert(spiritual.effects[0].value == 8)
	assert(spiritual.proficiency_event == "valid_taoist_melee_attack_resolved")

	var green_poison := _execute("taoist.poison", {
		"has_target": true,
		"line_of_sight": true,
		"force_success": true,
		"primary_stat_roll": 10,
	}, "grey_powder")
	assert(green_poison.effects[0].poison_type == "green_poison")
	assert(green_poison.effects[0].tick_interval_ms == 2000)
	assert(green_poison.resource_quote.material_id == "grey_powder")
	assert(green_poison.proficiency_event == "poison_status_successfully_applied_or_refreshed")
	var red_poison := _execute("taoist.poison", {
		"has_target": true,
		"line_of_sight": true,
		"force_success": true,
		"primary_stat_roll": 10,
	}, "yellow_powder")
	assert(red_poison.effects[0].poison_type == "red_poison")
	assert(red_poison.effects[0].flat_ac_reduction == red_poison.effects[0].flat_mac_reduction)
	assert(red_poison.effects[0].extra_durability_loss_per_hit == 1)
	var resisted_poison := _execute("taoist.poison", {
		"has_target": true,
		"line_of_sight": true,
		"force_resist": true,
	}, "grey_powder")
	assert(not resisted_poison.effect_success and resisted_poison.resource_commit)
	assert(resisted_poison.proficiency_event.is_empty())

	var talisman := _execute("taoist.soul_fire_talisman", {
		"has_target": true,
		"line_of_sight": true,
		"primary_stat_roll": 11,
	})
	assert(talisman.effects[0].type == "talisman_projectile_damage")
	assert(talisman.effects[0].damage_type == "spirit_magic")
	assert(talisman.resource_quote.material_amount == 1)
	assert(talisman.proficiency_event == "valid_talisman_projectile_created")

	var skeleton := _execute("taoist.summon_skeleton", {
		"spawn_tile_valid": true,
	})
	assert(skeleton.effects[0].spawned)
	assert(skeleton.effects[0].initial_pet_level == 3)
	assert(skeleton.effects[0].max_pet_level == 7)
	assert(not skeleton.effects[0].skill_rank_is_pet_level)
	assert(skeleton.resource_quote.material_amount == 1)
	assert(skeleton.proficiency_event == "new_skeleton_successfully_spawned")
	var recalled_skeleton := _execute("taoist.summon_skeleton", {
		"has_main_pet": true,
	}, "", 0)
	assert(recalled_skeleton.accepted and recalled_skeleton.effects[0].type == "recall_existing_main_pet")
	assert(not recalled_skeleton.resource_commit)
	assert(recalled_skeleton.resource_quote.material_amount == 0)
	assert(recalled_skeleton.proficiency_event.is_empty())

	var invisibility := _execute("taoist.invisibility", {
		"primary_stat_roll": 5,
	})
	assert(invisibility.effects[0].duration_seconds == 45)
	assert(invisibility.effects[0].break_on_tile_movement)
	assert(not invisibility.effects[0].break_on_ranged_spell_cast)
	assert(not invisibility.effects[0].pvp_invisibility)
	assert(invisibility.proficiency_event == "invisibility_buff_successfully_applied")

	var mass_invisibility := _execute("taoist.mass_invisibility", {
		"has_target": true,
		"target_tile": Vector2i(10, 10),
		"affected_friendly_count": 2,
		"primary_stat_roll": 4,
	})
	assert(mass_invisibility.geometry_cells.size() == 9)
	assert(mass_invisibility.effects[0].affected_count == 2)
	assert(mass_invisibility.resource_commit)
	assert(mass_invisibility.proficiency_event == "at_least_one_valid_friendly_receives_buff")
	var empty_mass_invisibility := _execute("taoist.mass_invisibility", {
		"has_target": true,
		"affected_friendly_count": 0,
	})
	assert(not empty_mass_invisibility.effect_success)
	assert(not empty_mass_invisibility.resource_commit)

	var soul_shield := _execute("taoist.magic_defense", {
		"has_target": true,
		"target_tile": Vector2i(10, 10),
		"friendly_targets": [{"level": 35}],
		"primary_stat_roll": 4,
	})
	assert(soul_shield.geometry_cells.size() == 49)
	assert(soul_shield.effects[0].stat == "MAC")
	assert(soul_shield.effects[0].flat_bonus == 5)
	assert(soul_shield.effects[0].duration_seconds == 10)
	assert(str(soul_shield.effects[0].stacking_policy).contains("blessed_armour"))

	var blessed_armour := _execute("taoist.defense", {
		"has_target": true,
		"target_tile": Vector2i(10, 10),
		"friendly_targets": [{"level": 35}],
		"primary_stat_roll": 4,
	})
	assert(blessed_armour.effects[0].stat == "AC")
	assert(blessed_armour.effects[0].flat_bonus == 5)
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
		"targets": [
			{"hostile_monster": true, "within_level_gate": true},
			{"hostile_monster": true, "is_boss": true},
		],
		"primary_stat_roll": 3,
	})
	assert(entrapment.effects[0].trapped_count == 1)
	assert(entrapment.effects[0].prevents_boundary_exit)
	assert(entrapment.effects[0].break_on_any_player_entry)
	assert(not entrapment.effects[0].generic_root)
	assert(entrapment.resource_commit)
	assert(entrapment.geometry_cells.size() == 8)
	var boss_only_entrapment := _execute("taoist.entrapment", {
		"has_target": true,
		"targets": [{"hostile_monster": true, "is_boss": true}],
	})
	assert(not boss_only_entrapment.effect_success)
	assert(not boss_only_entrapment.resource_commit)
	assert(boss_only_entrapment.proficiency_event.is_empty())

	var mass_healing := _execute("taoist.mass_healing", {
		"has_target": true,
		"target_tile": Vector2i(12, 12),
		"friendly_missing_hp": [5, 20, 0],
		"primary_stat_roll": 6,
	})
	assert(mass_healing.geometry_cells.size() == 9)
	assert(mass_healing.effects[0].type == "dedicated_area_heal")
	assert(mass_healing.effects[0].total_actual_hp_restored > 0)
	assert(not mass_healing.effects[0].negative_damage)
	assert(mass_healing.proficiency_event == "total_actual_hp_restored_gt_zero")

	var divine_beast := _execute("taoist.summon_divine_beast", {
		"spawn_tile_valid": true,
	})
	assert(divine_beast.effects[0].template_id == "divine_beast")
	assert(divine_beast.effects[0].initial_pet_level == 3)
	assert(divine_beast.effects[0].max_pet_level == 7)
	assert(divine_beast.resource_quote.material_amount == 5)
	assert(divine_beast.proficiency_event == "new_divine_beast_successfully_spawned")

	for result: Dictionary in [
		healing, spiritual, green_poison, red_poison, talisman, skeleton,
		recalled_skeleton, invisibility, mass_invisibility, soul_shield,
		blessed_armour, revelation, entrapment, mass_healing, divine_beast,
	]:
		assert(result.accepted)
		assert(result.runtime_contract == Router.RUNTIME_CONTRACT_ID)
	print("TAOIST_CANONICAL_RUNTIME_PASS: thirteen skills, materials, pets, buffs, healing and boundary control")
	get_tree().quit()


func _execute(
	skill_id: String,
	target_context: Dictionary,
	selected_material := "amulet",
	material_count := 99
) -> Dictionary:
	if not target_context.has("friendly"):
		target_context["friendly"] = false
	if not target_context.has("hostile"):
		target_context["hostile"] = false
	var materials := {
		"amulet": material_count,
		"grey_powder": material_count,
		"yellow_powder": material_count,
	}
	var request := Request.create(
		skill_id,
		3,
		40,
		Vector2i.ZERO,
		Vector2i.RIGHT,
		target_context,
		{
			"mana": 999,
			"materials": materials,
			"selected_material": selected_material,
		},
		23
	)
	return Router.execute(request)
