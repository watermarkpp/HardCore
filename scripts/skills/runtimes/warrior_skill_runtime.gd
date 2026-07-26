class_name WarriorSkillRuntime
extends RefCounted


static func execute(definition: Dictionary, request: Dictionary, rng: RefCounted) -> Dictionary:
	var skill_id := str(definition.get("skill_id", ""))
	var rank := clampi(int(request.get("rank", 0)), 0, 3)
	var context: Dictionary = request.get("target_context", {})
	var mechanics: Dictionary = definition.get("mechanics", {})
	var trigger := str(definition.get("proficiency_trigger", {}).get("event", ""))
	var plan := _base_plan(definition)
	match skill_id:
		"warrior.basic_swordsmanship":
			plan.effects = [{
				"type": "passive_stat_modifier",
				"stat": "accuracy",
				"value": int(mechanics.get("flat_bonus_by_rank", [0, 0, 0, 0])[rank]),
				"affects": mechanics.get("affects", []).duplicate(),
			}]
			if bool(context.get("valid_melee_swing", false)):
				plan.proficiency_event = trigger
		"warrior.slaying_swordsmanship":
			var probabilities: Array = mechanics.get("proc_chance_by_rank", [0.1, 0.125, 1.0 / 6.0, 0.25])
			var proc: bool = (
				not bool(context.get("force_no_proc", false))
				and (
					bool(context.get("force_proc", false))
					or bool(rng.call("chance", float(probabilities[rank])))
				)
			)
			plan.effect_success = proc
			plan.effects = [{
				"type": "melee_proc_modifier",
				"proc": proc,
				"success_probability": float(probabilities[rank]),
				"flat_dc_bonus": int(mechanics.get("flat_dc_bonus_by_rank", [5, 6, 7, 8])[rank]),
				"flat_accuracy_bonus": int(mechanics.get("flat_accuracy_bonus_by_rank", [0, 1, 2, 3])[rank]),
				"defence_type": "AC",
			}]
			if proc and bool(context.get("valid_melee_swing", true)):
				plan.proficiency_event = trigger
		"warrior.thrusting":
			var first: Dictionary = mechanics.get("first_cell", {})
			var second: Dictionary = mechanics.get("second_cell", {})
			plan.effect_success = bool(context.get("eligible_target_count", 1) > 0)
			plan.effects = [
				{"type": "melee_hit", "cell": 1, "multiplier": float(first.get("damage_multiplier", 1.0)), "ignore_ac": false},
				{"type": "melee_hit", "cell": 2, "multiplier": float(second.get("damage_multiplier_by_rank", [0.4, 0.6, 0.8, 1.0])[rank]), "ignore_ac": bool(second.get("ignore_ac", true))},
			]
			if plan.effect_success:
				plan.proficiency_event = trigger
		"warrior.half_moon":
			plan.effect_success = bool(context.get("eligible_target_count", 1) > 0)
			plan.effects = [{
				"type": "melee_arc",
				"maximum_targets": int(definition.get("geometry", {}).get("maximum_targets", 4)),
				"primary_multiplier": float(mechanics.get("primary_damage_multiplier", 1.0)),
				"side_multiplier": float(mechanics.get("side_damage_multiplier_by_rank", [0.15, 0.23, 0.31, 5.0 / 13.0])[rank]),
				"max_resource_commits": 1,
				"max_training_events": 1,
			}]
			if plan.effect_success:
				plan.proficiency_event = trigger
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
			var probability := clampf(
				(6.0 + 6.0 * float(rank) + float(caster_level - target_level)) / 20.0,
				0.0,
				1.0
			)
			var roll_success: bool = (
				not bool(context.get("force_failure", false))
				and (
					bool(context.get("force_success", false))
					or bool(rng.call("chance", probability))
				)
			)
			var path_blocked := bool(context.get("path_blocked_after_start", false))
			var displaced: bool = roll_success and not path_blocked
			plan.effect_success = displaced
			plan.effects = [{
				"type": "level_gated_push",
				"success_probability": probability,
				"push_distance_tiles": int(mechanics.get("push_distance_by_rank", [1, 1, 2, 3])[rank]),
				"displaced": displaced,
				"caster_moves_into_vacated_path": true,
			}]
			if path_blocked:
				plan.effects.append({
					"type": "self_damage",
					"amount": maxi(1, int(floor(float(context.get("caster_max_hp", 1)) * 0.01))),
					"reason": "rush_path_collision",
				})
			if displaced:
				plan.proficiency_event = trigger
		"warrior.fire_sword":
			plan.effects = [{
				"type": "next_melee_charge",
				"damage_multiplier": float(mechanics.get("damage_multiplier_by_rank", [1.4, 1.8, 2.2, 2.6])[rank]),
				"stack_count_max": 1,
				"auto_cast": false,
				"consume_on": "next_valid_melee_damage_attempt",
				"charge_lifetime_ms": int(definition.get("timing", {}).get("charge_lifetime_ms", 10000)),
			}]
			if bool(context.get("charge_consumed", false)):
				plan.proficiency_event = trigger
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
