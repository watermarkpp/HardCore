extends Node

const Profiles := preload("res://scripts/test_character_skill_profiles.gd")
const EXPECTED_COUNTS := {
	"warrior": 6,
	"wizard": 14,
	"taoist": 13,
}


func _ready() -> void:
	var formal_ids_by_profession := {}
	var level_three_rows := {}
	for row: Variant in GameData.skills:
		if not row is Dictionary:
			continue
		var skill_id := str(row.get("skill_id", ""))
		var profession_id := str(row.get("profession_id", ""))
		if skill_id.is_empty() or profession_id.is_empty():
			continue
		if int(row.get("skillLevel", -1)) == 0:
			if not formal_ids_by_profession.has(profession_id):
				formal_ids_by_profession[profession_id] = {}
			formal_ids_by_profession[profession_id][skill_id] = true
		elif int(row.get("skillLevel", -1)) == 3:
			level_three_rows[skill_id] = row

	var seen_character_ids := {}
	for profession_id: String in EXPECTED_COUNTS:
		var template := Profiles.profile_for_profession(profession_id)
		assert(template.contract_id == Profiles.CONTRACT_ID, "%s测试技能契约错误" % profession_id)
		assert(template.template_id == "test.skills.%s.full.v1" % profession_id, "%s模板ID错误" % profession_id)
		assert(template.minimum_character_level == 40, "%s满技能测试等级必须覆盖全部三级学习要求" % profession_id)
		assert(template.learned_skill_ids.size() == EXPECTED_COUNTS[profession_id], "%s正式技能数量错误" % profession_id)
		assert(template.learned_skill_ids.size() == formal_ids_by_profession[profession_id].size(), "%s存在正式技能遗漏" % profession_id)
		assert(template.quick_slot_ids.size() == 4 and template.quick_slots.size() == 4, "%s默认快捷槽必须正好4个" % profession_id)
		if profession_id in ["wizard", "taoist"]:
			var package: CasterProfessionPackage = WizardProfessionPackage.new() if profession_id == "wizard" else TaoistProfessionPackage.new()
			package.reset_character(template.minimum_character_level)
			var load_result := package.load_skill_state(template.learned_skill_ids)
			assert(load_result.loaded_count == EXPECTED_COUNTS[profession_id] and load_result.rejected.is_empty(), "%s满技能状态不能载入职业状态机" % profession_id)
		for skill_id: String in template.learned_skill_ids:
			assert(formal_ids_by_profession[profession_id].has(skill_id), "%s混入跨职业技能%s" % [profession_id, skill_id])
			assert(int(template.learned_skill_ids[skill_id]) == 3, "%s没有加载到当前规则满级" % skill_id)
			var level_row: Dictionary = level_three_rows.get(skill_id, {})
			assert(not level_row.is_empty(), "%s缺少三级数据" % skill_id)
			assert(int(level_row.get("requiredCharacterLevel", 999)) <= template.minimum_character_level, "%s人物等级不足以合法持有三级技能" % skill_id)
			var profile := ProfessionRules.skill_combat_profile(skill_id, 3)
			assert(not profile.is_empty() and profile.skill_id == skill_id, "%s缺少可执行战斗档案" % skill_id)
			assert(not str(profile.get("cast_type", "")).is_empty(), "%s状态机缺少施法类型" % skill_id)
			if profession_id in ["wizard", "taoist"]:
				var plan := CasterSkillRuntime.resolve(skill_id, {
					"skill_level": 3,
					"caster_level": 40,
					"owner_level": 40,
					"magic_stat_roll": 30,
					"spiritual_stat_roll": 30,
				})
				assert(plan.runtime_contract == "caster_skill_runtime.v1", "%s不能进入职业状态机" % skill_id)
				assert(plan.get("failure_reason", "") != "missing_runtime_operation", "%s缺少运行时操作" % skill_id)
		for quick_skill_id: String in template.quick_slot_ids:
			assert(template.learned_skill_ids.has(quick_skill_id), "%s快捷槽技能未学习" % quick_skill_id)
			assert(str(ProfessionRules.skill_combat_profile(quick_skill_id, 3).get("cast_type", "")) != "passive", "%s被动技能不能占用默认快捷槽" % quick_skill_id)
			var slot_index: int = template.quick_slot_ids.find(quick_skill_id)
			var assignment := SkillLoadoutRules.assign_quick_slot(template.quick_slots, template.learned_skills, {
				"contract_id": "ui.skill.button_assignment.v2",
				"slot_group": "center",
				"slot_index": slot_index,
				"skill_id": quick_skill_id,
			})
			assert(assignment.ok and assignment.change.skill_id == quick_skill_id, "%s默认快捷槽ID不能通过正式置换契约" % quick_skill_id)
		for equipment_tier: String in Profiles.EQUIPMENT_TIERS:
			var character := Profiles.profile_for_character(profession_id, equipment_tier)
			assert(character.template_id == template.template_id, "%s三装备档没有复用同一技能模板" % profession_id)
			assert(character.learned_skills == template.learned_skills and character.quick_slots == template.quick_slots, "%s装备档污染职业技能模板" % character.character_profile_id)
			assert(not seen_character_ids.has(character.character_profile_id), "测试人物ID重复")
			seen_character_ids[character.character_profile_id] = true
	assert(seen_character_ids.size() == 9, "必须生成3职业×3装备档共9个稳定测试人物ID")
	print("TEST_CHARACTER_FULL_SKILL_PROFILES_PASS: 9 profiles reuse 3 complete profession templates covering all 33 formal skills")
	get_tree().quit(0)
