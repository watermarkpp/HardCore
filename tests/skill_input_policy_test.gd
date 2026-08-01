extends Node

const Policy := preload("res://scripts/skill_input_policy.gd")
const LoadoutRules := preload("res://scripts/skill_loadout_rules.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")


func _ready() -> void:
	var basic := Policy.metadata("warrior.basic_swordsmanship")
	var slaying := Policy.metadata("warrior.slaying_swordsmanship")
	var thrust := Policy.metadata("warrior.thrusting")
	var half_moon := Policy.metadata("warrior.half_moon")
	var fire := Policy.metadata("warrior.fire_sword")
	var wild_rush := Policy.metadata("warrior.wild_rush")
	var fireball := Policy.metadata("wizard.fireball")
	var magic_shield := Policy.metadata("wizard.magic_shield")
	var healing := Policy.metadata("taoist.healing")
	var soul_fire := Policy.metadata("taoist.soul_fire_talisman")
	assert(basic.passive and not basic.bindable_to_skill_slot and not basic.bindable_to_attack_slot)
	assert(slaying.passive and slaying.hit_effect_only and slaying.player_body_action == "attack")
	assert(not slaying.uses_independent_player_body_action)
	assert(slaying.hit_effect_base == 800 and slaying.hit_effect_library == "Magic.wil")
	assert(slaying.runtime_override_id == Policy.SLAYING_LAYER_OVERRIDE_ID)
	assert(slaying.can_combine_with_higher_attack_mode and slaying.body_mode_priority == 0)
	assert(slaying.proc_rolls_per_melee_action == 1)
	assert(slaying.proc_roll_eligibility == "canonical_hit_frame_valid_melee_swing")
	assert(slaying.accuracy_timing == "before_each_target_hit_check")
	assert(slaying.modifier_timing == "after_body_skill_formula_before_target_damage_commit")
	assert(slaying.modifier_scope == "all_hits_of_selected_melee_action")
	assert(slaying.preserves_body_action_and_effect)
	assert(thrust.toggle and thrust.attack_priority == 200)
	assert(half_moon.toggle and half_moon.attack_priority == 300)
	assert(fire.toggle and fire.attack_priority == 400)
	assert(fire.runtime_override_id == Policy.FIRE_TOGGLE_OVERRIDE_ID)
	assert(fire.cooldown_commit_policy_id == Policy.FIRE_COOLDOWN_COMMIT_POLICY_ID)
	assert(fire.fallback_when_unavailable)
	assert(fire.fallback_priority_order == ["warrior.half_moon", "warrior.thrusting", "normal"])
	assert(fire.requires_valid_target_at_input)
	assert(fire.empty_swing_policy == "physical_miss_only")
	assert(wild_rush.click_release and wild_rush.bindable_to_skill_slot)
	assert(wild_rush.bindable_to_attack_slot, "主动技能必须支持未来绑定攻击键")

	assert(fireball.press_hold_repeat and fireball.repeatable_offensive_spell)
	assert(fireball.runtime_activation == "press_or_hold_repeat")
	assert(soul_fire.press_hold_repeat and soul_fire.repeatable_offensive_spell)
	assert(not healing.press_hold_repeat and not healing.repeatable_offensive_spell)
	assert(magic_shield.toggle and not magic_shield.press_hold_repeat)
	assert(magic_shield.runtime_override_id == Policy.MAGIC_SHIELD_TOGGLE_POLICY_ID)
	assert(magic_shield.auto_refresh_capacity_ratio == 0.20)
	assert(magic_shield.auto_refresh_uses_normal_cast_pipeline)

	for skill_id: String in Loader.skill_ids():
		var input := Policy.metadata(skill_id)
		assert(input.contract_id == Policy.INPUT_METADATA_CONTRACT_ID)
		assert(input.has("passive") and input.has("toggle") and input.has("click_release"))
		assert(input.has("bindable_to_skill_slot") and input.has("bindable_to_attack_slot"))
		assert(input.has("attack_priority"))
		assert(input.has("repeatable_offensive_spell") and input.has("press_hold_repeat"))

	var slots: Array[String] = ["野蛮冲撞", "", "", ""]
	var learned := {"基本剑术": 3, "攻杀剑术": 3, "野蛮冲撞": 3}
	for passive_name: String in ["基本剑术", "攻杀剑术"]:
		var rejected := LoadoutRules.assign_quick_slot(slots, learned, {
			"contract_id": "ui.skill.button_assignment.v2",
			"slot_group": "center",
			"slot_index": 1,
			"skill_name": passive_name,
		})
		assert(not rejected.ok and rejected.reason == "skill_not_bindable")
		assert(rejected.slots == slots, "被动技能拒绝时不得污染快捷栏")
	assert(LoadoutRules.can_bind_to_attack_slot("雷电术"))
	assert(not LoadoutRules.can_bind_to_attack_slot("精神力战法"))

	var migrated_v2 := LoadoutRules.normalize_assignments({
		"contract_id": LoadoutRules.LEGACY_BUTTON_ASSIGNMENTS_CONTRACT_ID,
		"center": ["雷电术", "火墙", "魔法盾", "冰咆哮"],
		"attack_ring": ["野蛮冲撞", "雷电术", "火墙"],
	})
	assert(migrated_v2.attack == [""])
	assert(migrated_v2.attack_ring == ["野蛮冲撞", "雷电术", "火墙", "", "", ""])
	assert(LoadoutRules.validate_assignments(migrated_v2).valid)
	var passive_migration := LoadoutRules.normalize_assignments({
		"contract_id": LoadoutRules.LEGACY_BUTTON_ASSIGNMENTS_CONTRACT_ID,
		"attack_ring": ["基本剑术", "攻杀剑术", "刺杀剑术"],
	})
	assert(passive_migration.attack_ring == ["", "", "刺杀剑术", "", "", ""])
	var attack_assignment := LoadoutRules.assign_button_slot(
		migrated_v2,
		{"野蛮冲撞": 3},
		{
			"contract_id": "ui.skill.button_assignment.v3",
			"slot_group": "attack",
			"slot_index": 0,
			"slot_id": "hud.attack.primary",
			"skill_name": "野蛮冲撞",
		}
	)
	assert(attack_assignment.ok and attack_assignment.assignments.attack == ["野蛮冲撞"])
	assert(attack_assignment.change.slot_id == "hud.attack.primary")
	var restored_attack := LoadoutRules.clear_button_slot(
		attack_assignment.assignments,
		{
			"contract_id": "ui.skill.button_assignment.v3",
			"slot_group": "attack",
			"slot_index": 0,
			"slot_id": "hud.attack.primary",
		}
	)
	assert(restored_attack.ok and restored_attack.reason == "restored_basic_attack")
	assert(restored_attack.assignments.attack == [""])
	var cleared_ring := LoadoutRules.clear_button_slot(
		migrated_v2,
		{
			"contract_id": "ui.skill.button_assignment.v3",
			"slot_group": "attack_ring",
			"slot_index": 1,
			"slot_id": "hud.attack_ring_skill.2",
		}
	)
	assert(cleared_ring.ok and cleared_ring.assignments.attack_ring[1].is_empty())
	var bad_clear := LoadoutRules.clear_button_slot(
		migrated_v2,
		{
			"contract_id": "ui.skill.button_assignment.v3",
			"slot_group": "attack",
			"slot_index": 0,
			"slot_id": "hud.attack_ring_skill.1",
		}
	)
	assert(not bad_clear.ok and bad_clear.reason == "slot_id_mismatch")

	print("SKILL_INPUT_POLICY_PASS：33技能输入元数据与v3 attack[1]+attack_ring[6]契约通过")
	get_tree().quit(0)
