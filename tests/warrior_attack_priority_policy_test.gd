extends Node

const Policy := preload("res://scripts/skill_input_policy.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const ResourceService := preload("res://scripts/skills/skill_resource_service.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")

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
	var direct_fire_effect := Policy.resolve_warrior_hit_effect(
		direct_fire,
		{
			"learned_skills": LEARNED,
			"toggles": ALL_TOGGLES,
			"has_combat_target": true,
			"current_mp": 40,
			"fire_rank": 3,
			"half_moon_rank": 3,
		}
	)
	assert(Policy.fire_direct_release_consumes_cooldown(direct_fire, direct_fire_effect, "hit"))
	assert(Policy.fire_direct_release_consumes_cooldown(direct_fire, direct_fire_effect, "miss"))
	assert(not Policy.fire_direct_release_consumes_cooldown(
		direct_fire, direct_fire_effect, "invalid_target"
	))
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
	assert(fire_cooldown.action == "attack" and fire_cooldown.mode == "half_moon")
	assert(fire_cooldown.attack_priority == 300)
	assert(fire_cooldown.fallback_trace[0].reason == "cooldown")
	_assert_single_slaying_layer(fire_cooldown)

	var cooldown_to_thrust := _resolve({
		"toggles": {"warrior.fire_sword": true, "warrior.thrusting": true},
		"fire_cooldown_remaining_ms": 5000,
	})
	assert(cooldown_to_thrust.mode == "thrust")
	assert(cooldown_to_thrust.fallback_trace[0].reason == "cooldown")

	var cooldown_to_normal := _resolve({
		"toggles": {"warrior.fire_sword": true},
		"fire_cooldown_remaining_ms": 5000,
	})
	assert(cooldown_to_normal.mode == "normal")
	assert(cooldown_to_normal.fallback_trace[0].reason == "cooldown")

	var fire_ready_again := _resolve({
		"fire_cooldown_remaining_ms": 0,
	})
	assert(fire_ready_again.mode == "fire" and fire_ready_again.direct_toggle_release)

	var fire_no_mana := _resolve({
		"current_mp": 5,
		"fire_armed": false,
	})
	assert(fire_no_mana.action == "attack" and fire_no_mana.mode == "half_moon")
	assert(fire_no_mana.fallback_trace[0].reason == "insufficient_mana")
	_assert_single_slaying_layer(fire_no_mana)

	var half_no_mana := _resolve({
		"toggles": {"warrior.half_moon": true, "warrior.thrusting": true},
		"current_mp": 0,
		"fire_armed": false,
	})
	assert(half_no_mana.mode == "half_moon" and half_no_mana.attack_priority == 300)
	assert(
		half_no_mana.effect_validation == "canonical_hit_frame",
		"半月资源与命中资格必须由命中帧 canonical 适配器判断"
	)
	_assert_single_slaying_layer(half_no_mana)
	var half_no_mana_effect := Policy.resolve_warrior_hit_effect(
		half_no_mana,
		{
			"learned_skills": LEARNED,
			"toggles": ALL_TOGGLES,
			"has_combat_target": true,
			"current_mp": 0,
			"half_moon_rank": 3,
		}
	)
	assert(half_no_mana_effect.selected_body_mode == "half_moon")
	assert(half_no_mana_effect.visual_mode == "half_moon")
	assert(half_no_mana_effect.effect_mode == "thrust")
	assert(half_no_mana_effect.preserve_selected_body_action)
	assert(half_no_mana_effect.body_mode_immutable)
	assert(not half_no_mana_effect.effect_mode_can_override_visual)
	assert(half_no_mana_effect.resource_reason == "insufficient_mana_at_hit_frame")
	assert(half_no_mana_effect.proc_rolls_performed == 0)
	assert(
		half_no_mana_effect.fallback_trace[0].reason
		== "insufficient_mana_at_hit_frame"
	)
	var half_fallback_proc := Router.resolve_warrior_melee_modifiers({
		"body_mode": half_no_mana_effect.effect_mode,
		"basic_sword_learned": true,
		"basic_sword_rank": 3,
		"slaying_learned": true,
		"slaying_rank": 3,
		"valid_melee_swing": true,
		"force_slaying_proc": true,
	})
	assert(half_fallback_proc.slaying_proc_roll_count == 1)
	assert(half_fallback_proc.slaying_proc)
	var half_only_no_mana_effect := Policy.resolve_warrior_hit_effect(
		half_no_mana,
		{
			"learned_skills": {"半月弯刀": 3, "攻杀剑术": 3},
			"toggles": {"warrior.half_moon": true},
			"has_combat_target": true,
			"current_mp": 0,
			"half_moon_rank": 3,
		}
	)
	assert(half_only_no_mana_effect.visual_mode == "half_moon")
	assert(half_only_no_mana_effect.effect_mode == "normal")
	assert(half_only_no_mana_effect.proc_rolls_performed == 0)
	var normal_fallback_no_proc := Router.resolve_warrior_melee_modifiers({
		"body_mode": half_only_no_mana_effect.effect_mode,
		"slaying_learned": true,
		"slaying_rank": 3,
		"valid_melee_swing": true,
		"force_no_slaying_proc": true,
	})
	assert(normal_fallback_no_proc.slaying_proc_roll_count == 1)
	assert(not normal_fallback_no_proc.slaying_proc)
	var fire_late_resource_fallback := Policy.resolve_warrior_hit_effect(
		direct_fire,
		{
			"learned_skills": LEARNED,
			"toggles": ALL_TOGGLES,
			"has_combat_target": true,
			"current_mp": 5,
			"fire_rank": 3,
			"half_moon_rank": 3,
		}
	)
	assert(fire_late_resource_fallback.selected_body_mode == "fire")
	assert(fire_late_resource_fallback.visual_mode == "fire")
	assert(fire_late_resource_fallback.effect_mode == "half_moon")
	assert(fire_late_resource_fallback.effect_available)
	assert(fire_late_resource_fallback.resource_reason == "insufficient_mana_at_hit_frame")
	assert(fire_late_resource_fallback.preserve_selected_body_action)
	assert(not Policy.fire_direct_release_consumes_cooldown(
		direct_fire, fire_late_resource_fallback, "hit"
	))
	var charged_fire_effect := Policy.resolve_warrior_hit_effect(
		ready_fire,
		{
			"learned_skills": LEARNED,
			"toggles": ALL_TOGGLES,
			"has_combat_target": true,
			"current_mp": 0,
			"fire_rank": 3,
		}
	)
	assert(not Policy.fire_direct_release_consumes_cooldown(
		ready_fire, charged_fire_effect, "hit"
	))

	var no_target := _resolve({
		"current_mp": 40,
		"fire_armed": true,
		"has_combat_target": false,
	})
	assert(no_target.action == "attack" and no_target.mode == "half_moon")
	assert(no_target.skill_name == "半月弯刀")
	assert(no_target.fallback_trace[0].reason == "no_valid_melee_target")
	assert(not no_target.target_available_at_input)
	_assert_single_slaying_layer(no_target)
	var no_target_effect := Policy.resolve_warrior_hit_effect(
		no_target,
		{
			"learned_skills": LEARNED,
			"toggles": ALL_TOGGLES,
			"has_combat_target": false,
			"current_mp": 40,
		}
	)
	assert(not no_target_effect.effect_available)
	assert(no_target_effect.visual_mode == "half_moon")
	assert(no_target_effect.selected_body_mode == "half_moon")
	assert(no_target_effect.reason == "no_valid_melee_target")
	assert(no_target_effect.resource_reason.is_empty())
	assert(no_target_effect.proc_rolls_performed == 0)

	var thrust_without_target := Policy.resolve_warrior_attack({
		"learned_skills": LEARNED,
		"toggles": {"warrior.thrusting": true},
		"has_combat_target": false,
		"current_mp": 0,
		"slaying_rank": 3,
	})
	assert(thrust_without_target.mode == "thrust")
	assert(thrust_without_target.skill_name == "刺杀剑术")
	assert(not thrust_without_target.target_available_at_input)
	_assert_single_slaying_layer(thrust_without_target)
	assert(not thrust_without_target.passive_proc_layers[0].target_available_at_input)

	for attack_index in range(24):
		var transient_target := attack_index % 3 != 0
		for stable_mode: Dictionary in [
			{"toggles": {"warrior.half_moon": true, "warrior.thrusting": true}, "mode": "half_moon", "skill": "半月弯刀"},
			{"toggles": {"warrior.thrusting": true}, "mode": "thrust", "skill": "刺杀剑术"},
		]:
			var repeated := Policy.resolve_warrior_attack({
				"learned_skills": LEARNED,
				"toggles": stable_mode.toggles,
				"has_combat_target": transient_target,
				"current_mp": 0,
				"slaying_rank": 3,
			})
			assert(repeated.mode == stable_mode.mode)
			assert(repeated.skill_name == stable_mode.skill)
			assert(repeated.passive_proc_layers.size() == 1)
			assert(
				repeated.passive_proc_layers[0].target_available_at_input
				== transient_target
			)

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

	print("WARRIOR_ATTACK_PRIORITY_POLICY_PASS：目标瞬时检测不改变半月/刺杀主体动作；攻杀仅为单次附加层")
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
	assert(layer.roll_eligibility == "canonical_hit_frame_valid_melee_swing")
	assert(layer.accuracy_timing == "before_each_target_hit_check")
	assert(layer.modifier_timing == "after_body_skill_formula_before_target_damage_commit")
	assert(layer.modifier_scope == "all_hits_of_selected_melee_action")
	assert(layer.does_not_replace_body_mode)
