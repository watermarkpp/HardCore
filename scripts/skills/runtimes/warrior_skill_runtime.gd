class_name WarriorSkillRuntime
extends RefCounted

const WarriorMeleeGeometryScript := preload(
	"res://scripts/skills/warrior_melee_geometry.gd"
)
const SkillRankResolverScript := preload(
	"res://scripts/skills/skill_rank_resolver.gd"
)


static func execute(definition: Dictionary, request: Dictionary, rng: RefCounted) -> Dictionary:
	var skill_id := str(definition.get("skill_id", ""))
	var rank := SkillRankResolverScript.safe_effective_rank(
		int(request.get("rank", 0))
	)
	var context: Dictionary = request.get("target_context", {})
	var mechanics: Dictionary = definition.get("mechanics", {})
	var plan := _base_plan(definition)
	match skill_id:
		"warrior.basic_swordsmanship":
			plan.effects = [{
				"type": "passive_stat_modifier",
				"stat": "accuracy",
				"value": SkillRankResolverScript.linear_int(
					mechanics.get("flat_bonus_by_rank", [0, 0, 0, 0]),
					rank
				),
				"affects": mechanics.get("affects", []).duplicate(),
			}]
		"warrior.slaying_swordsmanship":
			var denominators: Array = mechanics.get("proc_denominator_by_rank", [7, 6, 5, 4])
			var denominator := SkillRankResolverScript.denominator(
				denominators,
				rank
			)
			var valid_melee_action := bool(context.get("valid_melee_swing", false))
			var force_proc := bool(context.get("force_proc", false))
			var force_no_proc := bool(context.get("force_no_proc", false))
			var proc_roll := -1
			if context.has("proc_roll"):
				proc_roll = clampi(int(context.get("proc_roll", 0)), 0, denominator - 1)
			elif force_proc:
				proc_roll = 0
			elif valid_melee_action and not force_no_proc:
				proc_roll = int(rng.call("pascal_random_exclusive", denominator))
			var proc: bool = (
				valid_melee_action
				and not force_no_proc
				and (force_proc or proc_roll == 0)
			)
			plan.effect_success = proc
			plan.effects = [{
				"type": "melee_proc_modifier",
				"proc": proc,
				"success_probability": 1.0 / float(denominator),
				"proc_denominator": denominator,
				"proc_roll": proc_roll,
				"flat_damage_bonus": SkillRankResolverScript.linear_int(
					mechanics.get("flat_damage_bonus_by_rank", [2, 4, 6, 8]),
					rank
				),
				"flat_accuracy_bonus": SkillRankResolverScript.linear_int(
					mechanics.get("flat_accuracy_bonus_by_rank", [0, 1, 2, 3]),
					rank
				),
				"accuracy_always_applies": true,
				"damage_bonus_applies_after_body_formula": true,
				"valid_melee_action": valid_melee_action,
				"defence_type": "AC",
			}]
		"warrior.thrusting":
			var first: Dictionary = mechanics.get("first_cell", {})
			var second: Dictionary = mechanics.get("second_cell", {})
			var thrust_limit := WarriorMeleeGeometryScript.maximum_targets(
				WarriorMeleeGeometryScript.SKILL_THRUST
			)
			plan.effect_success = bool(context.get("eligible_target_count", 1) > 0)
			plan.effects = [
				{
					"type": "melee_hit",
					"cell": 1,
					"multiplier": float(first.get("damage_multiplier", 1.0)),
					"ignore_ac": false,
					"maximum_targets": thrust_limit,
					"target_count_policy_id": WarriorMeleeGeometryScript.TARGET_COUNT_POLICY_ID,
				},
				{
					"type": "melee_hit",
					"cell": 2,
					"multiplier": SkillRankResolverScript.linear_float(
						second.get(
							"damage_multiplier_by_rank", [0.4, 0.6, 0.8, 1.0]
						),
						rank
					),
					"ignore_ac": bool(second.get("ignore_ac", true)),
					"maximum_targets": thrust_limit,
					"target_count_policy_id": WarriorMeleeGeometryScript.TARGET_COUNT_POLICY_ID,
				},
			]
		"warrior.half_moon":
			plan.effect_success = bool(context.get("eligible_target_count", 1) > 0)
			plan.effects = [{
				"type": "melee_arc",
				"maximum_targets": WarriorMeleeGeometryScript.maximum_targets(
					WarriorMeleeGeometryScript.SKILL_HALF_MOON
				),
				"target_count_policy_id": WarriorMeleeGeometryScript.TARGET_COUNT_POLICY_ID,
				"primary_multiplier": float(mechanics.get("primary_damage_multiplier", 1.0)),
				"side_multiplier": SkillRankResolverScript.linear_float(
					mechanics.get(
						"side_damage_multiplier_by_rank",
						[0.15, 0.23, 0.31, 5.0 / 13.0]
					),
					rank
				),
				"max_resource_commits": 1,
				"max_training_events": 1,
			}]
		"warrior.wild_rush":
			var target_level := int(context.get("target_level", request.get("caster_level", 1)))
			var caster_level := int(request.get("caster_level", 1))
			var eligible := (
				caster_level > target_level
				and not bool(context.get("target_is_boss", false))
				and not bool(context.get("target_immovable", false))
				and not bool(context.get("safe_zone", false))
			)
			if not eligible:
				return _failed_resolution(plan, "ineligible_push_target")
			var maximum_distance_gu := float(
				mechanics.get("fixed_push_distance_gu", 3.0)
			)
			var dynamic_blocked := bool(context.get("dynamic_blocker_in_corridor", false))
			var resolved_distance_gu := clampf(
				float(context.get(
					"resolved_push_distance_gu", maximum_distance_gu
				)),
				0.0,
				maximum_distance_gu
			)
			if dynamic_blocked:
				resolved_distance_gu = 0.0
			var displaced := resolved_distance_gu > 0.0
			plan.effect_success = displaced
			plan.effects = [{
				"type": "level_gated_push",
				"success_probability": 1.0,
				"push_distance_gu": maximum_distance_gu,
				"resolved_push_distance_gu": resolved_distance_gu,
				"displaced": displaced,
				"caster_moves_into_vacated_path": true,
				"atomic_path_preflight_required": true,
				"dynamic_blocker_cancels_all_displacement": true,
				"static_obstacle_stops_before_blocker": true,
				"damage_amount": 0,
				"self_damage_amount": 0,
			}]
		"warrior.fire_sword":
			plan.effects = [{
				"type": "next_melee_charge",
				"damage_multiplier": SkillRankResolverScript.linear_float(
					mechanics.get(
						"damage_multiplier_by_rank",
						[1.4, 1.8, 2.2, 2.6]
					),
					rank
				),
				"stack_count_max": 1,
				"auto_cast": false,
				"consume_on": "next_valid_melee_damage_attempt",
				"charge_lifetime_ms": int(definition.get("timing", {}).get("charge_lifetime_ms", 10000)),
			}]
		_:
			return _failed_resolution(plan, "unknown_warrior_skill")
	return plan


static func _base_plan(definition: Dictionary) -> Dictionary:
	return {
		"accepted": true,
		"effect_success": true,
		"reason": "",
		"runtime_family": str(definition.get("mechanics", {}).get("runtime_family", "")),
		"effects": [],
		"proficiency_event": "",
		"resource_commit": true,
	}


static func _failed_resolution(plan: Dictionary, reason: String) -> Dictionary:
	plan.accepted = false
	plan.effect_success = false
	plan.reason = reason
	plan.resource_commit = false
	return plan
