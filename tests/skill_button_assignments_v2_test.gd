extends Node

const Profiles := preload("res://scripts/test_character_skill_profiles.gd")
const LoadoutRules := preload("res://scripts/skill_loadout_rules.gd")
const EXPECTED_SKILL_COUNTS := {
	"warrior": 6,
	"wizard": 14,
	"taoist": 13,
}


func _ready() -> void:
	var legacy_slots: Array[String] = ["雷电术", "火墙", "魔法盾", "冰咆哮"]
	var migrated_legacy := LoadoutRules.normalize_assignments({}, legacy_slots)
	assert(migrated_legacy.contract_id == LoadoutRules.BUTTON_ASSIGNMENTS_CONTRACT_ID)
	assert(migrated_legacy.attack == [""], "旧存档迁移不得擅自占用攻击主键")
	assert(
		migrated_legacy.attack_ring == ["雷电术", "火墙", "魔法盾", "冰咆哮", "", ""],
		"旧四快捷槽必须迁移到六环前四槽"
	)
	assert(migrated_legacy.migration == "legacy_quick_slots_to_attack_ring")

	var migrated_v2 := LoadoutRules.normalize_assignments({
		"contract_id": LoadoutRules.LEGACY_BUTTON_ASSIGNMENTS_CONTRACT_ID,
		"center": ["雷电术", "火墙", "魔法盾", "冰咆哮"],
		"attack_ring": ["野蛮冲撞", "雷电术", "火墙"],
	})
	assert(migrated_v2.attack == [""])
	assert(migrated_v2.attack_ring == ["野蛮冲撞", "雷电术", "火墙", "", "", ""])
	assert(migrated_v2.migration == "v2_attack_ring_preserved")

	var learned := {
		"野蛮冲撞": 3,
		"雷电术": 3,
		"火墙": 3,
		"基本剑术": 3,
		"攻杀剑术": 3,
	}
	var attack_result := LoadoutRules.assign_button_slot(migrated_v2, learned, {
		"contract_id": "ui.skill.button_assignment.v3",
		"slot_group": "attack",
		"slot_index": 0,
		"slot_id": "hud.attack.primary",
		"skill_name": "雷电术",
	})
	assert(attack_result.ok and attack_result.assignments.attack == ["雷电术"])
	assert(attack_result.assignments.attack_ring == migrated_v2.attack_ring)

	var ring_result := LoadoutRules.assign_button_slot(
		attack_result.assignments,
		learned,
		{
			"contract_id": "ui.skill.button_assignment.v3",
			"slot_group": "attack_ring",
			"slot_index": 5,
			"slot_id": "hud.attack_ring_skill.6",
			"skill_name": "火墙",
		}
	)
	assert(ring_result.ok and ring_result.assignments.attack_ring[5] == "火墙")
	assert(ring_result.assignments.attack == ["雷电术"], "六环修改污染攻击主键")
	for passive_name: String in ["基本剑术", "攻杀剑术"]:
		var rejected := LoadoutRules.assign_button_slot(
			ring_result.assignments,
			learned,
			{
				"contract_id": "ui.skill.button_assignment.v3",
				"slot_group": "attack_ring",
				"slot_index": 4,
				"skill_name": passive_name,
			}
		)
		assert(not rejected.ok and rejected.reason == "skill_not_bindable")

	var cleared := LoadoutRules.clear_button_slot(
		ring_result.assignments,
		{
			"contract_id": "ui.skill.button_assignment.v3",
			"slot_group": "attack",
			"slot_index": 0,
			"slot_id": "hud.attack.primary",
		}
	)
	assert(cleared.ok and cleared.assignments.attack == [""])
	assert(cleared.reason == "restored_basic_attack")

	var v1_warrior := Profiles.profile_for_character("warrior", "woma")
	assert(v1_warrior.character_profile_id == "test.character.warrior.woma.v1")
	var seen_profile_ids := {}
	var profiles := Profiles.qa_v2_profiles()
	assert(profiles.size() == 9)
	for profile: Dictionary in profiles:
		var profession_id := str(profile.get("profession_id", ""))
		var profile_id := str(profile.get("character_profile_id", ""))
		assert(profile_id.ends_with(".v2") and not seen_profile_ids.has(profile_id))
		seen_profile_ids[profile_id] = true
		assert(
			int(profile.get("skill_count", -1)) == int(EXPECTED_SKILL_COUNTS[profession_id])
		)
		var assignments: Dictionary = profile.get("button_assignments", {})
		assert(assignments.get("attack", []).size() == 1)
		assert(assignments.get("attack_ring", []).size() == 6)
		for skill_name: Variant in (
			assignments.get("attack", [])
			+ assignments.get("attack_ring", [])
		):
			assert(
				str(skill_name).is_empty()
				or profile.learned_skills.has(str(skill_name))
			)

	## Hidden skills (e.g. taoist.revelation) cannot be newly assigned, but
	## bindings saved in older profiles stay loadable untouched.
	var learned_with_revelation := {"心灵启示": 3}
	var hidden_assignment := LoadoutRules.assign_button_slot(
		migrated_v2,
		learned_with_revelation,
		{
			"contract_id": "ui.skill.button_assignment.v3",
			"slot_group": "attack_ring",
			"slot_index": 0,
			"slot_id": "hud.attack_ring_skill.1",
			"skill_name": "心灵启示",
		}
	)
	assert(
		not hidden_assignment.ok and hidden_assignment.reason == "skill_hidden"
	)
	var legacy_hidden := LoadoutRules.normalize_assignments({
		"contract_id": LoadoutRules.LEGACY_BUTTON_ASSIGNMENTS_CONTRACT_ID,
		"center": [],
		"attack_ring": ["心灵启示"],
	})
	assert(
		legacy_hidden.attack_ring[0] == "心灵启示",
		"old hidden-skill bindings must be preserved for save compatibility"
	)

	print("SKILL_BUTTON_ASSIGNMENTS_V3_PASS：攻击主键1槽、六环6槽、旧存档迁移、被动与隐藏技能排除正常")
	get_tree().quit(0)
