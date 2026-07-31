extends Node

const Profiles := preload("res://scripts/test_character_skill_profiles.gd")
const LoadoutRules := preload("res://scripts/skill_loadout_rules.gd")
const EXPECTED_SKILL_COUNTS := {
	"warrior": 6,
	"wizard": 14,
	"taoist": 13,
}


func _ready() -> void:
	var legacy_center: Array[String] = ["雷电术", "火墙", "魔法盾", "冰咆哮"]
	var migrated := LoadoutRules.normalize_assignments({}, legacy_center)
	assert(
		migrated.contract_id == LoadoutRules.BUTTON_ASSIGNMENTS_CONTRACT_ID,
		"七键技能栏必须输出稳定 v2 契约"
	)
	assert(migrated.center == legacy_center, "旧四快捷槽必须原样迁移到中央四键")
	assert(
		migrated.attack_ring == ["雷电术", "火墙", "魔法盾"],
		"旧 HUD 的前三槽镜像必须仅在首次迁移时复制到攻击环"
	)
	assert(
		migrated.migration == "legacy_quick_slots_mirrored_once",
		"旧四槽兼容迁移必须可审计"
	)

	var learned := {
		"wizard.lightning": 3,
		"火墙": 3,
		"魔法盾": 3,
		"冰咆哮": 3,
		"瞬息移动": 3,
	}
	var center_result := LoadoutRules.assign_button_slot(migrated, learned, {
		"contract_id": "ui.skill.button_assignment.v2",
		"slot_group": "center",
		"slot_index": 3,
		"slot_id": "hud.profession_skill.4",
		"skill_id": "wizard.teleport",
	})
	assert(center_result.ok and center_result.changed, "中央技能键不能按稳定技能 ID 独立改槽")
	assert(center_result.assignments.center[3] == "瞬息移动", "中央第四键没有保存目标技能")
	assert(
		center_result.assignments.attack_ring == migrated.attack_ring,
		"修改中央键错误污染攻击环"
	)
	assert(
		center_result.change.slot_id == "hud.profession_skill.4",
		"中央键稳定槽位 ID 错误"
	)

	var ring_result := LoadoutRules.assign_button_slot(
		center_result.assignments,
		learned,
		{
			"contract_id": "ui.skill.button_assignment.v2",
			"slot_group": "attack_ring",
			"slot_index": 2,
			"slot_id": "hud.attack_ring_skill.3",
			"skill_name": "火墙",
		}
	)
	assert(ring_result.ok, "攻击环不能按显示名独立改槽")
	assert(ring_result.assignments.attack_ring[2] == "火墙", "攻击环第三键没有保存目标技能")
	assert(
		ring_result.assignments.center == center_result.assignments.center,
		"修改攻击环错误污染中央四键"
	)
	assert(
		ring_result.change.slot_id == "hud.attack_ring_skill.3",
		"攻击环稳定槽位 ID 错误"
	)
	var invalid := LoadoutRules.assign_button_slot(ring_result.assignments, learned, {
		"contract_id": "ui.skill.button_assignment.v2",
		"slot_group": "attack_ring",
		"slot_index": 3,
		"skill_name": "火墙",
	})
	assert(
		not invalid.ok
		and invalid.reason == "slot_out_of_range"
		and invalid.assignments == ring_result.assignments,
		"越界请求必须被拒绝且不能改写七键快照"
	)

	var legacy_result := LoadoutRules.assign_quick_slot(legacy_center, learned, {
		"contract_id": "ui.skill.quick_slot_assignment.v1",
		"slot_index": 0,
		"skill_name": "火墙",
	})
	assert(
		legacy_result.ok
		and legacy_result.slots.size() == 4
		and legacy_result.change.contract_id == LoadoutRules.ASSIGNMENT_CONTRACT_ID,
		"旧四槽 assign_quick_slot 包装器必须保持 v1 兼容"
	)

	var v1_warrior := Profiles.profile_for_character("warrior", "woma")
	assert(
		v1_warrior.character_profile_id == "test.character.warrior.woma.v1",
		"QA v2 不得覆盖或回退既有 v1 测试角色"
	)
	var seen_profile_ids := {}
	var profiles := Profiles.qa_v2_profiles()
	assert(profiles.size() == 9, "必须生成三职业乘三装备档共九个 QA v2 模板")
	var qa_source: Dictionary = Profiles._qa_v2_data().get("source", {})
	assert(
		qa_source.get("lane", "") == "skills"
		and qa_source.get("tier", "") == "primary"
		and not bool(qa_source.get("fallback_used", true)),
		"QA v2 技能模板必须记录技能主源且禁止隐式 fallback"
	)
	for profile: Dictionary in profiles:
		var profession_id := str(profile.get("profession_id", ""))
		var profile_id := str(profile.get("character_profile_id", ""))
		assert(profile_id.ends_with(".v2"), "QA v2 角色必须使用全新稳定 ID")
		assert(not seen_profile_ids.has(profile_id), "QA v2 稳定角色 ID 重复")
		seen_profile_ids[profile_id] = true
		assert(
			int(profile.get("skill_count", -1)) == int(EXPECTED_SKILL_COUNTS[profession_id]),
			"%s QA v2 技能数量错误" % profession_id
		)
		assert(
			str(profile.get("character_name", "")).contains("%d技能" % EXPECTED_SKILL_COUNTS[profession_id]),
			"QA v2 角色名没有清晰标注技能数量"
		)
		var assignments: Dictionary = profile.get("button_assignments", {})
		assert(
			assignments.get("center", []).size() == 4
			and assignments.get("attack_ring", []).size() == 3,
			"%s QA v2 没有提供真实七键初始配置" % profession_id
		)
		for skill_name: Variant in assignments.get("center", []) + assignments.get("attack_ring", []):
			assert(
				profile.learned_skills.has(str(skill_name)),
				"%s QA v2 槽位引用了未学习技能" % profession_id
			)

	print("SKILL_BUTTON_ASSIGNMENTS_V2_PASS: independent 4+3 slots, v1 migration, nine QA v2 profiles")
	get_tree().quit(0)
