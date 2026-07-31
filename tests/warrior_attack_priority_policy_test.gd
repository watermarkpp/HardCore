extends Node

const Policy := preload("res://scripts/skill_input_policy.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const ResourceService := preload("res://scripts/skills/skill_resource_service.gd")

const LEARNED := {
	"烈火剑法": 3,
	"半月弯刀": 3,
	"刺杀剑术": 3,
	"攻杀剑术": 3,
}
const ALL_TOGGLES := {
	"warrior.fire_sword": true,
	"warrior.half_moon": true,
	"warrior.thrusting": true,
}


func _ready() -> void:
	var ready_fire := _resolve({
		"current_mp": 40,
		"fire_armed": true,
	})
	assert(ready_fire.mode == "fire" and ready_fire.attack_priority == 400)
	_assert_single_slaying_layer(ready_fire)

	var direct_fire := _resolve({
		"current_mp": 40,
		"fire_armed": false,
	})
	assert(direct_fire.action == "attack" and direct_fire.mode == "fire")
	assert(direct_fire.direct_toggle_release, "烈火开关必须在同一次攻击输入直接释放")
	_assert_single_slaying_layer(direct_fire)
	var direct_quote := ResourceService.quote(
		Loader.skill("warrior.fire_sword"),
		3,
		{"mana": 40, "materials": {}},
		{"charge_consumed": true, "direct_toggle_release": true}
	)
	assert(direct_quote.valid and direct_quote.mp_cost == 7, "烈火直释必须在同一次攻击唯一扣除主源MP")
	var legacy_charge_quote := ResourceService.quote(
		Loader.skill("warrior.fire_sword"),
		3,
		{"mana": 0, "materials": {}},
		{"charge_consumed": true}
	)
	assert(legacy_charge_quote.valid and legacy_charge_quote.mp_cost == 0, "旧已充能消费兼容不得二次扣MP")

	var fire_cooldown := _resolve({
		"current_mp": 40,
		"fire_armed": false,
		"fire_cooldown_remaining_ms": 5000,
	})
	assert(fire_cooldown.mode == "half_moon" and fire_cooldown.attack_priority == 300)
	assert(fire_cooldown.fallback_trace[0].reason == "cooldown")
	_assert_single_slaying_layer(fire_cooldown)

	var fire_no_mana := _resolve({
		"current_mp": 5,
		"fire_armed": false,
	})
	assert(fire_no_mana.mode == "half_moon", "烈火资源不足必须降级，不能卡死攻击")
	assert(fire_no_mana.fallback_trace[0].reason == "insufficient_mana")

	var half_no_mana := _resolve({
		"current_mp": 0,
		"fire_armed": false,
		"fire_cooldown_remaining_ms": 5000,
	})
	assert(half_no_mana.mode == "thrust" and half_no_mana.attack_priority == 200)
	assert(half_no_mana.fallback_trace[1].reason == "insufficient_mana")
	_assert_single_slaying_layer(half_no_mana)

	var no_target := _resolve({
		"current_mp": 40,
		"fire_armed": true,
		"has_combat_target": false,
	})
	assert(no_target.mode == "normal", "无目标时所有目标型开关必须降级到普通空挥")
	assert(no_target.skill_id == "", "无目标空挥不得错误触发攻杀")
	assert(no_target.passive_proc_layers.is_empty())

	var slaying := Policy.resolve_warrior_attack({
		"learned_skills": {"攻杀剑术": 3},
		"toggles": {},
		"has_combat_target": true,
		"current_mp": 0,
		"slaying_rank": 3,
	})
	assert(slaying.mode == "normal" and slaying.skill_name == "attack")
	assert(slaying.passive_proc_skill_id == "warrior.slaying_swordsmanship")
	assert(slaying.attack_priority == 0, "攻杀不得占用或替换主体攻击优先级")
	_assert_single_slaying_layer(slaying)

	print("WARRIOR_ATTACK_PRIORITY_POLICY_PASS：烈火>半月>刺杀>普通；攻杀对每次有效近战仅附加一层判定")
	get_tree().quit(0)


func _resolve(overrides: Dictionary) -> Dictionary:
	var context := {
		"learned_skills": LEARNED,
		"toggles": ALL_TOGGLES,
		"has_combat_target": true,
		"current_mp": 40,
		"fire_armed": false,
		"fire_cooldown_remaining_ms": 0,
		"fire_rank": 3,
		"half_moon_rank": 3,
		"slaying_rank": 3,
	}
	context.merge(overrides, true)
	return Policy.resolve_warrior_attack(context)


func _assert_single_slaying_layer(selection: Dictionary) -> void:
	assert(selection.passive_proc_layers.size() == 1)
	var layer: Dictionary = selection.passive_proc_layers[0]
	assert(layer.skill_id == "warrior.slaying_swordsmanship")
	assert(layer.rank == 3 and layer.rolls_per_melee_action == 1)
	assert(layer.modifier_timing == "before_body_skill_formula")
	assert(layer.modifier_scope == "all_hits_of_selected_melee_action")
	assert(layer.does_not_replace_body_mode)
