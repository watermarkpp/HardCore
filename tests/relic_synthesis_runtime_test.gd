extends Node

const Rules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const Service := preload("res://scripts/layers/runtime/relic_synthesis_service.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	PlayerState.reset_progress(false)
	assert(Rules.records().size() == 6)
	for item_id: int in [950101, 950102, 950103, 950201, 950202, 950203]:
		var item := GameData.get_item_record({"item_id": item_id})
		assert(int(item.get("itemId", -1)) == item_id)
		assert(GameData.get_item(str(item.name)).get("itemId", -1) == item_id)
		assert(item.category == ("徽章" if Rules.is_badge(item_id) else "圣物") and int(item.weight) == 0 and int(item.requirementValue) == 35)
		for field: String in ["inventoryIcon", "groundIcon"]:
			var icon := load(GameData.get_item_art_path({"item_id": item_id}, field)) as Texture2D
			assert(icon != null and icon.get_size().x > 0.0 and icon.get_size().y > 0.0)
			var maximum := GameData.get_item_art_display_size({"item_id": item_id}, field)
			assert(maximum == (Vector2(56, 56) if field == "inventoryIcon" else Vector2(36, 36)))
			var fitted := icon.get_size() * minf(maximum.x / icon.get_size().x, maximum.y / icon.get_size().y)
			assert(fitted.x <= maximum.x and fitted.y <= maximum.y and fitted.x > 0.0 and fitted.y > 0.0)
			if Rules.is_badge(item_id):
				assert(fitted.x >= maximum.x - 2.0, "badge icon transparent padding makes the item look too small")
		if Rules.is_badge(item_id):
			var ground := preload("res://scripts/loot_pickup.gd").ground_visual_descriptor_for_record({"output_item_id": item_id, "item_name": str(item.name), "output_record": item})
			assert(str(ground.get("path", "")) == GameData.get_item_art_path({"item_id": item_id}, "groundIcon"))
			assert(ground.get("display_size", Vector2.ZERO) == Vector2(36, 36))
		var preview := preload("res://scripts/item_detail_presenter.gd").format_item(item)
		assert(preview.contains("随机") and preview.contains("技能等级 +1"))
	for profession: String in ["战士", "法师", "道士"]:
		var names: Array = Rules.SKILL_NAMES[profession]
		var ids := Rules.skill_ids_for(profession)
		assert(ids.size() == names.size())
		var rng := RandomNumberGenerator.new()
		rng.seed = 4816
		for item_id: int in [950101, 950102, 950103]:
			var rolled := Rules.roll_instance(item_id, profession, rng)
			assert(Rules.valid_instance(rolled, item_id))
			var detail := preload("res://scripts/item_detail_presenter.gd").format_item(Rules.record_for_id(item_id), rolled)
			assert(not detail.contains("随机技能等级 +1"))
			assert(ids.has(str(rolled.relic_roll.skill_id)))
			if item_id == 950102:
				for value: Variant in rolled.relic_roll.heart_maxima.values():
					assert(int(value) == 5)
	for item_id: int in [950201, 950202, 950203]:
		var expected_profession: String = {950201: "战士", 950202: "法师", 950203: "道士"}[item_id]
		var rng := RandomNumberGenerator.new()
		rng.seed = item_id
		var rolled := Rules.roll_instance(item_id, "战士", rng)
		assert(Rules.valid_instance(rolled, item_id))
		assert(Rules.skill_ids_for(expected_profession).has(str(rolled.relic_roll.skill_id)))
		assert(int(Rules.record_for_id(item_id).defenseMax) == 5 and int(Rules.record_for_id(item_id).mdefMax) == 5)
	var seen_drop_professions := {}
	for sample in 60:
		var catalog := GameData.get_item_record({"item_id": 950101})
		var identity := {"identity_status": "resolved", "item_id": 950101, "canonical_item_id": 950101, "item_name": str(catalog.name)}
		var dropped := PlayerState.create_drop_item_instance(identity, "relic:class-pool:%d" % sample)
		assert(Rules.valid_instance(dropped.item_instance, 950101))
		assert(not dropped.item_instance.has("drop_affix"))
		for profession: String in ["战士", "法师", "道士"]:
			if Rules.skill_ids_for(profession).has(str(dropped.item_instance.relic_roll.skill_id)):
				seen_drop_professions[profession] = true
	assert(seen_drop_professions.size() == 3, "direct relic drops did not sample all allowed classes")
	for item_id: int in [950201, 950202, 950203]:
		var catalog := GameData.get_item_record({"item_id": item_id})
		var identity := {"identity_status": "resolved", "item_id": item_id, "canonical_item_id": item_id, "item_name": str(catalog.name)}
		var dropped := PlayerState.create_drop_item_instance(identity, "badge:drop:%d" % item_id)
		assert(Rules.valid_instance(dropped.item_instance, item_id))
		assert(not dropped.item_instance.has("drop_affix") and not preload("res://scripts/ui_item_name_style.gd").display_name(catalog, dropped.item_instance).begins_with("★"))
	_test_synthesis_and_claim()
	_test_class_choice_and_badge_recovery()
	_test_forge_tray_and_rollback()
	_test_relic_ground_drop_and_tray_identity()
	_test_relic_stats_and_proc()
	_test_eye_guardian_and_unlearned_skill()
	_test_relic_proc_ground_projection()
	print("RELIC_SYNTHESIS_RUNTIME_PASS")
	get_tree().quit(0)


func _test_synthesis_and_claim() -> void:
	PlayerState.reset_progress(false)
	PlayerState.level = 35
	PlayerState.profession = "战士"
	PlayerState.gold = 900000
	for _index in 5:
		assert(bool(PlayerState.receive("远古圣物碎片", 1, false).get("success", false)))
	var stored_item := GameData.get_item_record({"item_id": 81})
	assert(bool(PlayerState.receive_record({"item_id": 81, "name": str(stored_item.name)}, false).get("success", false)))
	var first_index := _fragment_index()
	var inventory_before := PlayerState.inventory.duplicate(true)
	PlayerState._test_force_atomic_write_failure = true
	assert(not bool(PlayerState.place_workbench_item("synthesis", 1, first_index).get("success", false)))
	PlayerState._test_force_atomic_write_failure = false
	assert(PlayerState.inventory == inventory_before and PlayerState.synthesis_tray[1].is_empty())
	assert(bool(PlayerState.place_workbench_item("synthesis", 1, _item_index(81)).get("success", false)))
	for slot: int in [2, 4, 6, 8, 3]:
		assert(bool(PlayerState.place_workbench_item("synthesis", slot, _fragment_index()).get("success", false)))
	assert(_fragment_index() == -1)
	var service := Service.new(PlayerState)
	var material_slots: Array[int] = [2, 4, 6, 8]
	var quote := service.quote_synthesis(950101, material_slots)
	assert(bool(quote.get("valid", false)))
	var tray_before := PlayerState.synthesis_tray.duplicate(true)
	var gold_before := PlayerState.gold
	PlayerState._test_force_atomic_write_failure = true
	assert(not bool(service.commit_synthesis(quote).get("committed", false)))
	PlayerState._test_force_atomic_write_failure = false
	assert(PlayerState.synthesis_tray == tray_before and PlayerState.gold == gold_before)
	assert(not bool(service.commit_synthesis(quote).get("committed", false)), "consumed quote replayed")
	quote = service.quote_synthesis(950101, material_slots)
	var result := service.commit_synthesis(quote)
	assert(bool(result.get("committed", false)), str(result.get("message", "")))
	assert(PlayerState.gold == gold_before - 400000)
	assert(Rules.valid_instance(PlayerState.synthesis_tray[0], 950101))
	for slot: int in material_slots:
		assert(PlayerState.synthesis_tray[slot].is_empty())
	assert(int(GameData.get_item_record(PlayerState.synthesis_tray[1]).get("itemId", -1)) == 81, "temporary item was consumed")
	assert(int(GameData.get_item_record(PlayerState.synthesis_tray[3]).get("itemId", -1)) == Rules.FRAGMENT_ID, "extra fragment was consumed")
	_assert_tray_survives_save_reload()
	assert(not bool(service.quote_synthesis(950102, material_slots).get("valid", false)), "unclaimed output overwritten")
	var output_before := PlayerState.synthesis_tray[0].duplicate(true)
	PlayerState._test_force_atomic_write_failure = true
	assert(not bool(PlayerState.take_workbench_item("synthesis", 0).get("success", false)))
	PlayerState._test_force_atomic_write_failure = false
	assert(PlayerState.synthesis_tray[0] == output_before)
	assert(bool(PlayerState.take_workbench_item("synthesis", 0).get("success", false)))
	assert(PlayerState.synthesis_tray[0].is_empty())
	assert(_item_index(950101) >= 0)


func _test_class_choice_and_badge_recovery() -> void:
	PlayerState.reset_progress(false)
	PlayerState.profession = "战士"
	PlayerState.level = 35
	PlayerState.gold = 900000
	for _index in 4:
		assert(bool(PlayerState.receive("远古圣物碎片", 1, false).get("success", false)))
	for slot: int in [1, 2, 3, 4]:
		assert(bool(PlayerState.place_workbench_item("synthesis", slot, _fragment_index()).get("success", false)))
	var service := Service.new(PlayerState)
	var slots: Array[int] = [1, 2, 3, 4]
	var quote := service.quote_synthesis(950102, slots, "法师")
	assert(bool(quote.get("valid", false)) and str(quote.skill_profession) == "法师")
	assert(not bool(service.quote_synthesis(950102, slots, "未知职业").get("valid", false)))
	var result := service.commit_synthesis(quote)
	assert(bool(result.get("committed", false)), str(result.get("message", "")))
	assert(Rules.skill_ids_for("法师").has(str(PlayerState.synthesis_tray[0].relic_roll.skill_id)))
	assert(PlayerState.gold == 500000)
	assert(Rules.valid_instance(PlayerState.synthesis_tray[0], 950102))
	assert(not PlayerState.synthesis_tray[0].has("drop_affix"), "crafted relic unexpectedly rolled JP")
	assert(bool(PlayerState.take_workbench_item("synthesis", 0).get("success", false)))
	var heart: Dictionary = PlayerState.inventory[_item_index(950102)]
	var heart_skill_name := preload("res://scripts/skills/skill_data_loader.gd").display_name(str(heart.relic_roll.skill_id))
	PlayerState.learned_skills[heart_skill_name] = 1
	assert(PlayerState.equip_inventory_index(_item_index(950102)).begins_with("已装备"))
	assert(PlayerState.effective_skill_level(heart_skill_name) == 1, "cross-profession relic skill bonus became active")
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 35
	var badge_catalog := Rules.record_for_id(950201)
	var badge := PlayerState._make_item_instance(str(badge_catalog.name), badge_catalog, -1, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1031
	badge.merge(Rules.roll_instance(950201, "战士", rng), true)
	assert(bool(PlayerState.receive_record(badge, false).get("success", false)))
	var defense_before := int(PlayerState.computed_stats.get("defense_max", 0))
	assert(PlayerState.equip_inventory_index(_item_index(950201)).begins_with("已装备"))
	assert(int(PlayerState.computed_stats.get("defense_max", 0)) == defense_before + 5)
	var badge_durability := int(PlayerState.equipment["徽章"].durability_raw)
	PlayerState.damage_equipment_durability("徽章", 100)
	assert(int(PlayerState.equipment["徽章"].durability_raw) == badge_durability)
	var badge_skill_name := preload("res://scripts/skills/skill_data_loader.gd").display_name(str(badge.relic_roll.skill_id))
	PlayerState.learned_skills[badge_skill_name] = 1
	assert(PlayerState.effective_skill_level(badge_skill_name) == 1, "cross-profession badge skill bonus became active")
	var actor := preload("res://scripts/player.gd").new()
	actor.max_hp = 150
	actor.current_hp = 100
	actor.max_mp = 149
	actor.current_mp = 100
	actor._tick_badge_recovery(0.9)
	assert(actor.current_hp == 100)
	actor._tick_badge_recovery(0.1)
	assert(actor.current_hp == 102, "badge recovery must round each one-second tick")
	actor._tick_badge_recovery(2.0)
	assert(actor.current_hp == 106)
	PlayerState.equipment["徽章"] = {}
	actor._tick_badge_recovery(0.6)
	PlayerState.equipment["徽章"] = badge
	actor._tick_badge_recovery(0.5)
	assert(actor.current_hp == 106, "badge timer carried across unequip")
	actor._tick_badge_recovery(0.5)
	assert(actor.current_hp == 108)
	var wisdom := Rules.roll_instance(950202, "战士", rng)
	PlayerState.equipment["徽章"] = wisdom
	actor._tick_badge_recovery(1.0)
	assert(actor.current_mp == 101 and actor.current_hp == 108, "mana badge recovery used wrong resource or rounding")
	actor.max_mp = 49
	actor.current_mp = 1
	actor._tick_badge_recovery(1.0)
	assert(actor.current_mp == 1, "sub-unit badge recovery must not accumulate")
	actor.queue_free()
	var style := preload("res://scripts/ui_item_name_style.gd")
	var reference_ultra := style.describe(GameData.get_item_record({"item_id": 108}))
	var reference_redmoon := style.describe(GameData.get_item_record({"item_id": 140}))
	for item_id: int in [950101, 950102, 950103, 950201, 950202, 950203]:
		var styled := style.describe(GameData.get_item_record({"item_id": item_id}))
		assert(styled.group == "ultra_rare" and styled.color == reference_ultra.color and styled.outline == reference_ultra.outline)
	var fragment_style := style.describe(GameData.get_item_record({"item_id": 950001}))
	assert(fragment_style.group == "redmoon" and fragment_style.color == reference_redmoon.color)
	PlayerState.reset_progress(false)
	PlayerState.profession = "战士"
	PlayerState.level = 35
	PlayerState.gold = 400000
	for _index in 4:
		assert(bool(PlayerState.receive("远古圣物碎片", 1, false).get("success", false)))
	for slot: int in [1, 2, 3, 4]:
		assert(bool(PlayerState.place_workbench_item("synthesis", slot, _fragment_index()).get("success", false)))
	var badge_service := Service.new(PlayerState)
	var badge_quote := badge_service.quote_synthesis(950203, slots, "道士")
	assert(bool(badge_quote.get("valid", false)))
	assert(bool(badge_service.commit_synthesis(badge_quote).get("committed", false)))
	assert(PlayerState.gold == 0 and Rules.valid_instance(PlayerState.synthesis_tray[0], 950203))
	assert(not PlayerState.synthesis_tray[0].has("drop_affix"), "crafted badge unexpectedly rolled JP")
	assert(Rules.skill_ids_for("道士").has(str(PlayerState.synthesis_tray[0].relic_roll.skill_id)))
	for slot: int in slots:
		assert(PlayerState.synthesis_tray[slot].is_empty())
	_assert_tray_survives_save_reload()
	assert(bool(PlayerState.take_workbench_item("synthesis", 0).get("success", false)))
	assert(Rules.valid_instance(PlayerState.inventory[_item_index(950203)], 950203))


func _test_forge_tray_and_rollback() -> void:
	PlayerState.reset_progress(false)
	for item_id: int in [81, 940010, 191, 192]:
		var item := GameData.get_item_record({"item_id": item_id})
		assert(bool(PlayerState.receive_record({"item_id": item_id, "name": str(item.name)}, false).get("success", false)))
	PlayerState.gold = 1000000
	var bag_weight_before := PlayerState.inventory_weight()
	for pair: Array in [[81, 4], [940010, 1], [191, 3], [192, 5]]:
		assert(bool(PlayerState.place_workbench_item("forge", int(pair[1]), _item_index(int(pair[0]))).get("success", false)))
	assert(PlayerState.inventory_weight() < bag_weight_before, "workbench temporary storage counted toward bag weight")
	_assert_tray_survives_save_reload()
	var service := preload("res://scripts/layers/runtime/equipment_enhancement_service.gd").new(PlayerState)
	var quote := service.quote_forge_tray()
	assert(bool(quote.get("valid", false)))
	var before := PlayerState.forge_tray.duplicate(true)
	var target_instance_id := str(before[4].get("instance_id", ""))
	var gold_before := PlayerState.gold
	PlayerState._test_force_atomic_write_failure = true
	assert(not bool(service.commit_forge(quote).get("committed", false)))
	PlayerState._test_force_atomic_write_failure = false
	assert(PlayerState.forge_tray == before and PlayerState.gold == gold_before)
	quote = service.quote_forge_tray()
	assert(bool(service.commit_forge(quote).get("committed", false)))
	assert(str(PlayerState.forge_tray[4].get("name", "")) == "匕首")
	assert(str(PlayerState.forge_tray[4].get("instance_id", "")) == target_instance_id, "forged equipment moved out of its slot")
	for slot: int in [1, 3, 5]:
		assert(PlayerState.forge_tray[slot].is_empty())
	_assert_tray_survives_save_reload()
	assert(bool(PlayerState.take_workbench_item("forge", 4).get("success", false)))
	assert(_item_index(81) >= 0)


func _test_relic_stats_and_proc() -> void:
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 34
	var rng := RandomNumberGenerator.new()
	rng.seed = 2525
	var heart := PlayerState._make_item_instance("魔龙之心", Rules.record_for_id(950102), -1, false)
	heart.merge(Rules.roll_instance(950102, "法师", rng), true)
	assert(bool(PlayerState.receive_record(heart, false).get("success", false)))
	assert(not PlayerState.equip_inventory_index(_item_index(950102)).begins_with("已装备"))
	PlayerState.level = 35
	PlayerState.recalculate_stats(false)
	assert(PlayerState.equip_inventory_index(_item_index(950102)).begins_with("已装备"))
	var stats_before := PlayerState.computed_stats.duplicate(true)
	for stat: String in ["attack_max", "magic_max", "tao_max"]:
		assert(int(stats_before[stat]) >= int(heart.relic_roll.heart_maxima[stat.trim_suffix("_max")]))
	var triggered := false
	for _attempt in 100:
		if PlayerState.try_trigger_relic_proc():
			triggered = true
			break
	assert(triggered)
	for stat: String in ["attack_min", "attack_max", "magic_min", "magic_max", "tao_min", "tao_max"]:
		assert(int(PlayerState.computed_stats[stat]) == roundi(float(stats_before[stat]) * 1.15))
	assert(not PlayerState.try_trigger_relic_proc())
	PlayerState.advance_relic_proc(10.0)
	assert(is_equal_approx(float(PlayerState.relic_proc_status().get("cooldown", 0.0)), 15.0))
	assert(PlayerState.computed_stats == stats_before)
	PlayerState.advance_relic_proc(15.0)
	assert(is_zero_approx(float(PlayerState.relic_proc_status().get("cooldown", -1.0))))
	var before_durability := int(PlayerState.equipment["圣物"].durability_raw)
	PlayerState.damage_equipment_durability("圣物", 100)
	assert(int(PlayerState.equipment["圣物"].durability_raw) == before_durability)


func _test_relic_ground_drop_and_tray_identity() -> void:
	PlayerState.reset_progress(false)
	PlayerState.profession = "道士"
	var item := GameData.get_item_record({"item_id": 950103})
	var identity := {
		"identity_status": "resolved", "item_id": 950103,
		"canonical_item_id": 950103, "output_item_id": 950103,
		"item_name": str(item.name), "output_record": item.duplicate(true),
	}
	var dropped := PlayerState.create_drop_item_instance(identity, "relic:test:guardian")
	assert(str(dropped.get("item_instance_contract_id", "")) == Rules.CONTRACT_ID)
	assert(Rules.valid_instance(dropped.item_instance, 950103))
	assert(not dropped.item_instance.has("drop_affix"), "relic drop unexpectedly rolled JP")
	assert(not preload("res://scripts/ui_item_name_style.gd").display_name(item, dropped.item_instance).begins_with("★"))
	assert(PlayerState.create_drop_item_instance(identity, "relic:test:guardian") == dropped)
	var candidate := {"item_id": 950103, "item_name": str(item.name), "item_instance": dropped.item_instance}
	var received := PlayerState.receive_loot_batch_partial([candidate])
	assert(bool(received.get("success", false)) and int(received.get("success_count", 0)) == 1, str(received))
	assert(PlayerState.inventory[_item_index(950103)] == dropped.item_instance)
	assert(bool(PlayerState.place_workbench_item("forge", 0, _item_index(950103)).get("success", false)))
	_assert_tray_survives_save_reload()
	var duplicate := PlayerState.receive_loot_batch_partial([candidate])
	assert(int(duplicate.get("success_count", 0)) == 0, "drop instance duplicated while held in workbench")
	assert(not PlayerState._validate_profile_drop_instance_uniqueness({
		"inventory": [dropped.item_instance],
		"forge_tray": [dropped.item_instance],
	}))
	assert(bool(PlayerState.take_workbench_item("forge", 0).get("success", false)))
	var recovered: Dictionary = PlayerState.inventory[_item_index(950103)]
	assert(str(recovered.get("instance_id", "")) == str(dropped.item_instance.instance_id))
	assert(Rules.valid_instance(recovered, 950103))
	assert(recovered.relic_roll == dropped.item_instance.relic_roll)
	assert(not bool(PlayerState.receive_record({"item_id": 950103, "name": str(item.name), "relic_roll": {"bad": true}}, false).get("success", false)))
	PlayerState.reset_progress(false)
	assert(bool(PlayerState.receive_record({"item_id": 950103, "name": str(item.name)}, false).get("success", false)))
	assert(Rules.valid_instance(PlayerState.inventory[_item_index(950103)], 950103))


func _test_eye_guardian_and_unlearned_skill() -> void:
	for pair: Array in [[950101, "attack_speed_tier"], [950103, "luck"]]:
		PlayerState.reset_progress(false)
		PlayerState.profession = "战士"
		PlayerState.level = 35
		var item_id := int(pair[0])
		var stat := str(pair[1])
		var rng := RandomNumberGenerator.new()
		rng.seed = 4312 + item_id
		var catalog := Rules.record_for_id(item_id)
		var instance := PlayerState._make_item_instance(str(catalog.name), catalog, -1, false)
		instance.merge(Rules.roll_instance(item_id, "战士", rng), true)
		var rolled_skill_id := str(instance.relic_roll.skill_id)
		var skill_name := preload("res://scripts/skills/skill_data_loader.gd").display_name(rolled_skill_id)
		assert(bool(PlayerState.receive_record(instance, false).get("success", false)))
		assert(PlayerState.equip_inventory_index(_item_index(item_id)).begins_with("已装备"))
		assert(PlayerState.effective_skill_level(skill_name) == 0, "unlearned relic skill became usable")
		PlayerState.learned_skills[skill_name] = 1
		assert(PlayerState.effective_skill_level(skill_name) == 2, "learned relic skill did not gain +1")
		var passive := int(PlayerState.computed_stats.get(stat, 0))
		assert(passive >= 1)
		var triggered := false
		for _attempt in 100:
			if PlayerState.try_trigger_relic_proc():
				triggered = true
				break
		assert(triggered)
		assert(int(PlayerState.computed_stats.get(stat, 0)) == passive + 2)
		PlayerState.advance_relic_proc(10.0)
		assert(int(PlayerState.computed_stats.get(stat, 0)) == passive)
		assert(is_equal_approx(float(PlayerState.relic_proc_status().get("cooldown", 0.0)), 15.0))


func _test_relic_proc_ground_projection() -> void:
	var actor := Node2D.new()
	add_child(actor)
	var effect := preload("res://scripts/ui_relic_proc_effect.gd").new()
	actor.add_child(effect)
	assert(effect.show_behind_parent)
	assert(effect._decal != null and effect._decal.centered and effect._decal.position == Vector2(0, 5))
	assert(effect._decal.texture == UIRelicProcEffect.DECAL_TEXTURE)
	effect.replay(Vector2(12, 20))
	assert(effect.position == Vector2(12, 20))
	assert(effect._decal.position == Vector2(0, 5) and effect.visible)
	effect._process(UIRelicProcEffect.GROW_SECONDS)
	var full_scale: Vector2 = effect._decal.scale
	assert(is_equal_approx(effect._decal.modulate.a, 1.0))
	effect._process(UIRelicProcEffect.HOLD_SECONDS)
	assert(effect._decal.scale.is_equal_approx(full_scale))
	assert(is_equal_approx(effect._decal.modulate.a, 1.0))
	effect._process(UIRelicProcEffect.FADE_SECONDS)
	assert(not effect.visible)
	actor.queue_free()


func _assert_tray_survives_save_reload() -> void:
	var old_directory := PlayerState.profile_directory
	var old_profile := PlayerState.active_profile_id
	var old_name := PlayerState.character_name
	PlayerState.profile_directory = "user://tests/relic_workbench_profiles"
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory)) == OK)
	PlayerState.active_profile_id = "relic_test"
	PlayerState.character_name = "圣物工作格测试"
	var forge_before := PlayerState.forge_tray.duplicate(true)
	var synthesis_before := PlayerState.synthesis_tray.duplicate(true)
	assert(PlayerState.save_game(false), "workbench save failed: %s" % str(PlayerState.last_save_result))
	PlayerState.forge_tray = PlayerState._empty_workbench_tray()
	PlayerState.synthesis_tray = PlayerState._empty_workbench_tray()
	PlayerState.load_save()
	assert(bool(PlayerState.last_load_result.get("success", false)), str(PlayerState.last_load_result.get("reason", "")))
	assert(JSON.parse_string(JSON.stringify(PlayerState.forge_tray)) == JSON.parse_string(JSON.stringify(forge_before)) and JSON.parse_string(JSON.stringify(PlayerState.synthesis_tray)) == JSON.parse_string(JSON.stringify(synthesis_before)), "workbench contents lost after reload")
	PlayerState.profile_directory = old_directory
	PlayerState.active_profile_id = old_profile
	PlayerState.character_name = old_name


func _fragment_index() -> int:
	for index in PlayerState.inventory.size():
		if str(PlayerState.inventory[index].get("name", "")) == "远古圣物碎片":
			return index
	return -1


func _item_index(item_id: int) -> int:
	for index in PlayerState.inventory.size():
		if int(PlayerState.inventory[index].get("item_id", -1)) == item_id:
			return index
	return -1
