class_name SkillInputPolicy
extends RefCounted

const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")

const INPUT_METADATA_CONTRACT_ID := "gameplay.skill.input_metadata.v1"
const WARRIOR_ATTACK_POLICY_ID := "gameplay.warrior.attack_priority.v1"
const WARRIOR_HIT_EFFECT_POLICY_ID := "gameplay.warrior.hit_effect_fallback.v1"
const FIRE_TOGGLE_OVERRIDE_ID := "gameplay.warrior.fire_sword.attack_toggle.user_override.v1"
const FIRE_COOLDOWN_COMMIT_POLICY_ID := "gameplay.warrior.fire_sword.cooldown_on_legal_resolution.v1"
const SLAYING_LAYER_OVERRIDE_ID := "gameplay.warrior.slaying.layered_proc.user_override.v1"
const OFFENSIVE_SPELL_HOLD_POLICY_ID := "gameplay.caster.offensive_spell.press_hold_repeat.v1"
const MAGIC_SHIELD_TOGGLE_POLICY_ID := "gameplay.wizard.magic_shield.auto_refresh_toggle.v1"

const INTERACTION_PASSIVE := "passive"
const INTERACTION_TOGGLE := "toggle"
const INTERACTION_CLICK_RELEASE := "click_release"

const ATTACK_PRIORITY := {
	"warrior.fire_sword": 400,
	"warrior.half_moon": 300,
	"warrior.thrusting": 200,
}


static func metadata(skill_name_or_id: String) -> Dictionary:
	var definition := SkillDataLoaderScript.skill(skill_name_or_id)
	if definition.is_empty():
		return {}
	var skill_id := str(definition.get("skill_id", ""))
	var activation := str(definition.get("activation", ""))
	var interaction_mode := INTERACTION_CLICK_RELEASE
	if activation in ["passive", "passive_proc"]:
		interaction_mode = INTERACTION_PASSIVE
	elif activation == "toggle_attack_mode" or skill_id in [
		"warrior.fire_sword",
		"wizard.magic_shield",
	]:
		interaction_mode = INTERACTION_TOGGLE
	var passive := interaction_mode == INTERACTION_PASSIVE
	var target: Dictionary = definition.get("target", {})
	var hostile_relation := str(target.get("relation", "")).contains("hostile")
	var repeatable_offensive_spell := (
		interaction_mode == INTERACTION_CLICK_RELEASE
		and str(definition.get("class", "")) in ["wizard", "taoist"]
		and hostile_relation
	)
	var result := {
		"contract_id": INPUT_METADATA_CONTRACT_ID,
		"skill_id": skill_id,
		"display_name": str(definition.get("display_name", "")),
		"profession_id": str(definition.get("class", "")),
		"canonical_activation": activation,
		"interaction_mode": interaction_mode,
		"passive": passive,
		"toggle": interaction_mode == INTERACTION_TOGGLE,
		"click_release": interaction_mode == INTERACTION_CLICK_RELEASE,
		"bindable_to_skill_slot": not passive,
		# The attack button is a first-class active-skill destination. This is
		# generic so future wizard/taoist active skills need no warrior special
		# case in UI code.
		"bindable_to_attack_slot": not passive,
		"repeatable_offensive_spell": repeatable_offensive_spell,
		"press_hold_repeat": repeatable_offensive_spell,
		"attack_priority": int(ATTACK_PRIORITY.get(skill_id, 0)),
		"source_contract": SkillDataLoaderScript.RULESET_ID,
	}
	if skill_id == "wizard.magic_shield":
		result.merge({
			"runtime_override_id": MAGIC_SHIELD_TOGGLE_POLICY_ID,
			"runtime_activation": "toggle_auto_refresh",
			"auto_refresh_capacity_ratio": 0.20,
			"auto_refresh_before_expiry": true,
			"auto_refresh_uses_normal_cast_pipeline": true,
			"repeatable_offensive_spell": false,
			"press_hold_repeat": false,
		}, true)
	elif skill_id == "warrior.fire_sword":
		result.merge({
			"runtime_override_id": FIRE_TOGGLE_OVERRIDE_ID,
			"cooldown_commit_policy_id": FIRE_COOLDOWN_COMMIT_POLICY_ID,
			"runtime_activation": "single_attack_input_direct_melee",
			"fallback_when_unavailable": true,
			"fallback_priority_order": [
				"warrior.half_moon",
				"warrior.thrusting",
				"normal",
			],
			"requires_valid_target_at_input": true,
			"empty_swing_policy": "physical_miss_only",
		}, true)
	elif skill_id == "warrior.slaying_swordsmanship":
		result.merge({
			"runtime_override_id": SLAYING_LAYER_OVERRIDE_ID,
			"runtime_activation": "one_proc_roll_per_valid_melee_action",
			"player_body_action": "attack",
			"hit_effect_only": true,
			"uses_independent_player_body_action": false,
			"hit_effect_resource": "res://assets/art/characters/warrior/effects/power_hit.png",
			"hit_effect_base": 800,
			"hit_effect_distribution": "client.classic_raw_complete",
			"hit_effect_library": "Magic.wil",
			"can_combine_with_higher_attack_mode": true,
			"body_mode_priority": 0,
			"proc_rolls_per_melee_action": 1,
			"proc_roll_eligibility": "canonical_hit_frame_valid_melee_swing",
			"accuracy_timing": "before_each_target_hit_check",
			"modifier_timing": "after_body_skill_formula_before_target_damage_commit",
			"modifier_scope": "all_hits_of_selected_melee_action",
			"preserves_body_action_and_effect": true,
			"proficiency_event": "successful_slaying_proc_on_valid_melee_swing",
		}, true)
	elif interaction_mode == INTERACTION_TOGGLE:
		result["runtime_activation"] = "attack_button_melee_mode"
	elif interaction_mode == INTERACTION_CLICK_RELEASE:
		result["runtime_activation"] = (
			"press_or_hold_repeat"
			if repeatable_offensive_spell
			else "press_to_release"
		)
	else:
		result["runtime_activation"] = "always_on"
	return result


static func can_bind(skill_name_or_id: String, destination: String) -> bool:
	var input := metadata(skill_name_or_id)
	if input.is_empty():
		return false
	match destination:
		"skill_slot":
			return bool(input.get("bindable_to_skill_slot", false))
		"attack_slot":
			return bool(input.get("bindable_to_attack_slot", false))
	return false


static func resolve_warrior_attack(context: Dictionary) -> Dictionary:
	var trace: Array[Dictionary] = []
	var learned: Dictionary = context.get("learned_skills", {})
	var toggles: Dictionary = context.get("toggles", {})
	var has_target := bool(context.get("has_combat_target", false))
	var current_mp := maxi(0, int(context.get("current_mp", 0)))

	if bool(toggles.get("warrior.fire_sword", false)):
		if not _is_learned(learned, "warrior.fire_sword"):
			trace.append(_blocked("warrior.fire_sword", "not_learned"))
		elif not has_target:
			trace.append(_blocked("warrior.fire_sword", "no_valid_melee_target"))
		elif bool(context.get("fire_armed", false)):
			var charged_fire := _selection(
				"attack",
				"fire",
				"warrior.fire_sword",
				trace
			)
			charged_fire["direct_toggle_release"] = false
			return _with_slaying_layer(charged_fire, context, learned, has_target)
		elif int(context.get("fire_cooldown_remaining_ms", 0)) > 0:
			trace.append(_blocked("warrior.fire_sword", "cooldown"))
		elif current_mp < _mana_cost("warrior.fire_sword", int(context.get("fire_rank", 0))):
			trace.append(_blocked("warrior.fire_sword", "insufficient_mana"))
		else:
			var direct_fire := _selection(
				"attack",
				"fire",
				"warrior.fire_sword",
				trace
			)
			direct_fire["direct_toggle_release"] = true
			return _with_slaying_layer(direct_fire, context, learned, has_target)

	if bool(toggles.get("warrior.half_moon", false)):
		if not _is_learned(learned, "warrior.half_moon"):
			trace.append(_blocked("warrior.half_moon", "not_learned"))
		elif current_mp < _mana_cost(
			"warrior.half_moon",
			int(context.get("half_moon_rank", 0))
		):
			# Resource state is already authoritative at input time, so do not start
			# a half-moon body/visual that can never legally resolve. Continue the
			# existing priority chain to thrust or normal without spending MP.
			trace.append(_blocked("warrior.half_moon", "insufficient_mana"))
		else:
			var half_moon := _with_slaying_layer(
				_selection("attack", "half_moon", "warrior.half_moon", trace),
				context,
				learned,
				has_target
			)
			half_moon["effect_validation"] = "canonical_hit_frame"
			half_moon["target_available_at_input"] = has_target
			return half_moon

	if bool(toggles.get("warrior.thrusting", false)):
		if not _is_learned(learned, "warrior.thrusting"):
			trace.append(_blocked("warrior.thrusting", "not_learned"))
		else:
			var thrust := _with_slaying_layer(
				_selection("attack", "thrust", "warrior.thrusting", trace),
				context,
				learned,
				has_target
			)
			thrust["effect_validation"] = "canonical_hit_frame"
			thrust["target_available_at_input"] = has_target
			return thrust

	return _with_slaying_layer(
		_selection("attack", "normal", "", trace),
		context,
		learned,
		has_target
	)


static func resolve_warrior_hit_effect(
	body_selection: Dictionary,
	runtime_context: Dictionary
) -> Dictionary:
	var selected_body_mode := str(body_selection.get("mode", "normal"))
	var learned: Dictionary = runtime_context.get("learned_skills", {})
	var toggles: Dictionary = runtime_context.get("toggles", {})
	var has_target := bool(runtime_context.get("has_combat_target", false))
	var current_mp := maxi(0, int(runtime_context.get("current_mp", 0)))
	var trace: Array[Dictionary] = []
	if not has_target:
		return _effect_selection(selected_body_mode, "", "", "no_valid_melee_target", trace)

	if selected_body_mode == "fire":
		var charged_fire := not bool(body_selection.get("direct_toggle_release", false))
		var fire_cost := (
			0
			if charged_fire
			else _mana_cost(
				"warrior.fire_sword",
				int(runtime_context.get("fire_rank", 0))
			)
		)
		if current_mp >= fire_cost:
			return _effect_selection(
				selected_body_mode,
				"fire",
				"warrior.fire_sword",
				"",
				trace
			)
		trace.append(_blocked("warrior.fire_sword", "insufficient_mana_at_hit_frame"))

	if selected_body_mode in ["fire", "half_moon"]:
		if (
			bool(toggles.get("warrior.half_moon", false))
			and _is_learned(learned, "warrior.half_moon")
		):
			var half_cost := _mana_cost(
				"warrior.half_moon",
				int(runtime_context.get("half_moon_rank", 0))
			)
			if current_mp >= half_cost:
				return _effect_selection(
					selected_body_mode,
					"half_moon",
					"warrior.half_moon",
					"",
					trace
				)
			trace.append(_blocked("warrior.half_moon", "insufficient_mana_at_hit_frame"))

	if (
		selected_body_mode in ["fire", "half_moon", "thrust"]
		and bool(toggles.get("warrior.thrusting", false))
		and _is_learned(learned, "warrior.thrusting")
	):
		return _effect_selection(
			selected_body_mode,
			"thrust",
			"warrior.thrusting",
			"",
			trace
		)
	return _effect_selection(selected_body_mode, "normal", "", "", trace)


static func fire_direct_release_consumes_cooldown(
	body_selection: Dictionary,
	hit_effect: Dictionary,
	canonical_resolution: String
) -> bool:
	return (
		bool(body_selection.get("direct_toggle_release", false))
		and str(body_selection.get("mode", "")) == "fire"
		and bool(hit_effect.get("effect_available", false))
		and str(hit_effect.get("effect_mode", "")) == "fire"
		and canonical_resolution in ["hit", "miss"]
	)


static func _selection(action: String, mode: String, skill_id: String, trace: Array[Dictionary]) -> Dictionary:
	return {
		"policy_id": WARRIOR_ATTACK_POLICY_ID,
		"action": action,
		"mode": mode,
		"selected_body_mode": mode,
		"body_action_locked": true,
		"skill_id": skill_id,
		"skill_name": SkillDataLoaderScript.display_name(skill_id) if not skill_id.is_empty() else "attack",
		"attack_priority": int(ATTACK_PRIORITY.get(skill_id, 0)),
		"fallback_trace": trace,
	}


static func _blocked_attack(
	mode: String,
	skill_id: String,
	reason: String,
	trace: Array[Dictionary]
) -> Dictionary:
	var result := _selection("blocked", mode, skill_id, trace)
	result["reason"] = reason
	result["effect_validation"] = "rejected_before_body_action"
	result["target_available_at_input"] = false
	result["passive_proc_layers"] = []
	return result


static func _effect_selection(
	selected_body_mode: String,
	effect_mode: String,
	skill_id: String,
	reason: String,
	trace: Array[Dictionary]
) -> Dictionary:
	var resource_reason := ""
	for entry: Dictionary in trace:
		var entry_reason := str(entry.get("reason", ""))
		if entry_reason.contains("mana") or entry_reason.contains("resource"):
			resource_reason = entry_reason
			break
	return {
		"policy_id": WARRIOR_HIT_EFFECT_POLICY_ID,
		"visual_mode": selected_body_mode,
		"selected_body_mode": selected_body_mode,
		"body_mode_immutable": true,
		"effect_mode": effect_mode,
		"effect_skill_id": skill_id,
		"effect_skill_name": (
			SkillDataLoaderScript.display_name(skill_id)
			if not skill_id.is_empty()
			else ("attack" if effect_mode == "normal" else "")
		),
		"effect_available": not effect_mode.is_empty(),
		"preserve_selected_body_action": true,
		"effect_mode_can_override_visual": false,
		"reason": reason,
		"resource_reason": resource_reason,
		"fallback_trace": trace,
		"proc_rolls_performed": 0,
		"uses_existing_melee_modifier_resolution": true,
	}


static func _with_slaying_layer(
	selection: Dictionary,
	context: Dictionary,
	learned: Dictionary,
	has_target: bool
) -> Dictionary:
	selection["passive_proc_layers"] = []
	if not _is_learned(learned, "warrior.slaying_swordsmanship"):
		return selection
	var layer := {
		"skill_id": "warrior.slaying_swordsmanship",
		"rank": clampi(int(context.get("slaying_rank", 0)), 0, 3),
		"rolls_per_melee_action": 1,
		"roll_eligibility": "canonical_hit_frame_valid_melee_swing",
		"target_available_at_input": has_target,
		"accuracy_timing": "before_each_target_hit_check",
		"modifier_timing": "after_body_skill_formula_before_target_damage_commit",
		"modifier_scope": "all_hits_of_selected_melee_action",
		"does_not_replace_body_mode": true,
		"runtime_override_id": SLAYING_LAYER_OVERRIDE_ID,
	}
	selection["passive_proc_layers"] = [layer]
	# Compatibility field for the integration adapter. It identifies a layer,
	# never the selected body skill or animation.
	selection["passive_proc_skill_id"] = str(layer.skill_id)
	return selection


static func _blocked(skill_id: String, reason: String) -> Dictionary:
	return {
		"skill_id": skill_id,
		"attack_priority": int(ATTACK_PRIORITY.get(skill_id, 0)),
		"reason": reason,
		"fallback": true,
	}


static func _is_learned(learned: Dictionary, skill_id: String) -> bool:
	var display_name := SkillDataLoaderScript.display_name(skill_id)
	return learned.has(skill_id) or learned.has(display_name)


static func _mana_cost(skill_id: String, rank: int) -> int:
	var definition := SkillDataLoaderScript.skill(skill_id)
	var costs: Array = definition.get("mp_cost_by_rank", [])
	if costs.is_empty():
		return 0
	return maxi(0, int(costs[clampi(rank, 0, mini(3, costs.size() - 1))]))
