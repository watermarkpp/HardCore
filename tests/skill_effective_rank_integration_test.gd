extends Node

const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")
const SkillDataLoader := preload("res://scripts/skills/skill_data_loader.gd")
const SkillResourceService := preload("res://scripts/skills/skill_resource_service.gd")
const SkillCastRequest := preload("res://scripts/skills/skill_cast_request.gd")
const SkillRuntimeRouter := preload("res://scripts/skills/skill_runtime_router.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "法师"
	PlayerState.level = 40
	PlayerState.learned_skills = {"火球术": 0}

	# Instance-level modifiers are injected directly on the inventory records
	# before equipping. The test never relies on a mutable GameData reference.
	var wood_modifiers := [
		{"stat": "skill_level", "scope": "all", "value": 1},
		{"stat": "skill_level", "scope": "profession:wizard", "value": 1},
		{"stat": "skill_level", "scope": "skill:wizard.fireball", "value": 1},
		{"stat": "skill_level", "op": "add", "value": 1, "skill": "火球术"},
		{"stat": "skill_level", "scope": "skill:wizard.lightning", "value": 7},
	]
	var cloth_modifiers := {"skillLevels": {"all": 1}}
	PlayerState.add_item("木剑")
	PlayerState.add_item("布衣(男)")
	PlayerState.inventory[_inventory_index("木剑")]["modifiers"] = (
		wood_modifiers.duplicate(true)
	)
	PlayerState.inventory[_inventory_index("布衣(男)")]["modifiers"] = (
		cloth_modifiers.duplicate(true)
	)

	assert(PlayerState.equip_inventory_index(_inventory_index("木剑")).begins_with("已装备"), "木剑穿装备失败")
	assert(PlayerState.equip_inventory_index(_inventory_index("布衣(男)")).begins_with("已装备"), "布衣穿装备失败")

	assert(PlayerState.effective_skill_level("火球术") == 5, "canonical/legacy 词条叠加后应为 rank5")
	assert(PlayerState.effective_skill_level("雷电术") == 0, "装备不得授予未学技能")
	assert(PlayerState.effective_skill_level("攻杀剑术") == 0, "未学技能即使有 all 加成也必须为 0")
	var affix_contributions: Dictionary = PlayerState.computed_stats.get("skill_level_affix", {}).get("contributions", {})
	assert(int(affix_contributions.get("all", 0)) == 2, "all 词条应只按每件装备计一次")
	assert(int(affix_contributions.get("profession:wizard", 0)) == 1, "profession 词条计数错误")
	assert(int(affix_contributions.get("skill:wizard.fireball", 0)) == 1, "specific 词条计数错误")
	assert(int(affix_contributions.get("skill:wizard.lightning", 0)) == 7, "未学技能 specific 词条仍应进入聚合")

	# Instance modifiers are authoritative; erasing them falls back to the
	# catalog base (木剑 has none) without any double counting.
	PlayerState.equipment["武器"].erase("modifiers")
	PlayerState.recalculate_stats()
	assert(PlayerState.effective_skill_level("火球术") == 1, "移除实例词条后应只剩布衣 all+1")
	PlayerState.equipment["武器"]["modifiers"] = wood_modifiers.duplicate(true)
	PlayerState.recalculate_stats()
	assert(PlayerState.effective_skill_level("火球术") == 5, "恢复实例词条后应为 rank5")

	# rank5 MP preflight matches the canonical quote and canonical plan.
	var definition := SkillDataLoader.skill("wizard.fireball")
	var rank5_context := PlayerState.canonical_skill_resource_context(
		"wizard.fireball",
		9999
	)
	var rank5_quote := SkillResourceService.quote(
		definition,
		5,
		rank5_context
	)
	assert(rank5_quote.valid and rank5_quote.mp_cost == 13, "rank5 MP 报价错误")
	var rank5_plan := _canonical_plan(5)
	assert(int(rank5_plan.get("resource_quote", {}).get("mp_cost", -1)) == 13, "rank5 canonical plan 报价与 quote 不一致")

	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	player.current_mp = 13
	assert(player.can_request_skill("火球术"), "MP 恰好等于 rank5 报价时应可施法")
	player.current_mp = 12
	assert(not player.can_request_skill("火球术"), "MP 低于 rank5 报价时应拒绝预检")

	# rank4 after removing one affix item.
	PlayerState.unequip_slot("衣服")
	assert(PlayerState.effective_skill_level("火球术") == 4, "卸下布衣后应为 rank4")
	var rank4_quote := SkillResourceService.quote(
		definition,
		4,
		PlayerState.canonical_skill_resource_context("wizard.fireball", 9999)
	)
	assert(rank4_quote.valid and rank4_quote.mp_cost == 11, "rank4 MP 报价错误")
	var rank4_plan := _canonical_plan(4)
	assert(int(rank4_plan.get("resource_quote", {}).get("mp_cost", -1)) == 11, "rank4 canonical plan 报价与 quote 不一致")
	player.current_mp = 11
	assert(player.can_request_skill("火球术"), "rank4 MP 恰好等于报价时应可施法")
	player.current_mp = 10
	assert(not player.can_request_skill("火球术"), "rank4 MP 低于报价时应拒绝预检")

	# Unequip and durability-zero both invalidate affixes.
	PlayerState.unequip_slot("武器")
	assert(PlayerState.effective_skill_level("火球术") == 0, "卸装后加成应失效")
	assert(PlayerState.equip_inventory_index(_inventory_index("木剑")).begins_with("已装备"), "重新穿装备失败")
	assert(PlayerState.effective_skill_level("火球术") == 4, "重新穿装备后应恢复 rank4")
	var weapon: Dictionary = PlayerState.equipment["武器"]
	PlayerState.damage_equipment_durability("武器", int(weapon.get("max_durability", 1)))
	assert(PlayerState.effective_skill_level("火球术") == 0, "零耐久装备不得提供技能等级加成")

	# Proficiency is a no-op: snapshot and the stable save fields are unchanged.
	var snapshot_before := PlayerState.skill_progression_snapshot().duplicate(true)
	var noop := PlayerState.apply_skill_proficiency_event(
		"火球术",
		"valid_projectile_cast_created",
		123
	)
	assert(not noop.accepted and noop.gain == 0, "apply proficiency 应返回 no-op 拒绝")
	assert(PlayerState.skill_progression_snapshot() == snapshot_before, "apply proficiency 改变了进度快照")
	PlayerState.active_profile_id = "effective_rank_proficiency_test"
	PlayerState.character_name = "有效等级测试"
	PlayerState.test_mode = false
	PlayerState.save_game()
	var save_path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var saved_before: Dictionary = PlayerState._read_json(save_path)
	PlayerState.apply_skill_proficiency_event("火球术", "valid_projectile_cast_created", 456)
	PlayerState.save_game()
	var saved_after: Dictionary = PlayerState._read_json(save_path)
	var stable_before := saved_before.duplicate(true)
	var stable_after := saved_after.duplicate(true)
	stable_before.erase("updated_at")
	stable_after.erase("updated_at")
	assert(
		JSON.stringify(stable_before) == JSON.stringify(stable_after),
		"apply proficiency 改写了存档稳定字段"
	)
	assert(
		stable_before.get("skill_progression") == stable_after.get("skill_progression"),
		"apply proficiency 改写了 skill_progression"
	)
	assert(
		not (saved_after.get("skill_progression", {}).get("skills", {}).get("wizard.fireball", {}).has("current_proficiency")),
		"存档中出现熟练度"
	)

	player.queue_free()
	var absolute_path := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(absolute_path)
	if FileAccess.file_exists("%s.bak" % save_path):
		DirAccess.remove_absolute("%s.bak" % absolute_path)
	PlayerState.active_profile_id = ""
	PlayerState.test_mode = true
	print("SKILL_EFFECTIVE_RANK_INTEGRATION_PASS: canonical/legacy stacking, instance modifiers authoritative, unlearned=0, unequip/broken invalid, rank4/5 MP preflight == quote == plan, proficiency no-op")
	get_tree().quit(0)


func _inventory_index(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _canonical_plan(effective_rank: int) -> Dictionary:
	var definition := SkillDataLoader.skill("wizard.fireball")
	var context := {
		"has_target": true,
		"line_of_sight": true,
		"friendly": false,
		"hostile": true,
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
	var request := SkillCastRequest.create(
		"wizard.fireball",
		effective_rank,
		PlayerState.level,
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
	return SkillRuntimeRouter._plan(request)
