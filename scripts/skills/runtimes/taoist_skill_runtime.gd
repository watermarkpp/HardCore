class_name TaoistSkillRuntime
extends RefCounted

const Formula := preload("res://scripts/skills/formulas/mir2_skill_formula.gd")
const SkillRankResolverScript := preload(
	"res://scripts/skills/skill_rank_resolver.gd"
)
const TaoistCombatMathScript := preload(
	"res://scripts/taoist_combat_math.gd"
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
		"taoist.healing":
			_resolve_single_heal(plan, definition, request, rng)
		"taoist.spiritual_warfare":
			plan.effects = [{
				"type": "passive_stat_modifier",
				"stat": "accuracy",
				"value": SkillRankResolverScript.linear_int(
					mechanics.get("flat_bonus_by_rank", [0, 0, 0, 0]),
					rank
				),
				"affects": mechanics.get("affects", []).duplicate(),
			}]
		"taoist.poison":
			_resolve_poison(plan, rank, request, rng)
		"taoist.soul_fire_talisman":
			plan.effects = [_spirit_damage_effect(definition, request, rng)]
		"taoist.summon_skeleton":
			_resolve_main_pet(
				plan,
				rank,
				context,
				"skeleton",
				TaoistCombatMathScript.maximum_summon_pet_level(rank)
			)
		"taoist.invisibility":
			plan.effects = [_stealth_effect(rank, context, rng, "buff.taoist.invisibility")]
		"taoist.mass_invisibility":
			_resolve_mass_invisibility(plan, rank, context, rng)
		"taoist.magic_defense", "taoist.defense":
			_resolve_defence_buff(plan, rank, context, rng, mechanics)
		"taoist.revelation":
			_resolve_revelation(plan, rank, context, rng)
		"taoist.entrapment":
			_resolve_entrapment(plan, rank, context, rng)
		"taoist.mass_healing":
			_resolve_mass_heal(plan, definition, request, rng)
		"taoist.summon_divine_beast":
			_resolve_main_pet(
				plan,
				rank,
				context,
				"divine_beast",
				TaoistCombatMathScript.maximum_summon_pet_level(rank)
			)
		_:
			return _reject(plan, "unknown_taoist_skill")
	return plan


static func _resolve_single_heal(
	plan: Dictionary,
	definition: Dictionary,
	request: Dictionary,
	rng: RefCounted
) -> void:
	var context: Dictionary = request.get("target_context", {})
	if bool(context.get("hostile", false)):
		_reject(plan, "friendly_heal_target_required")
		return
	var raw_heal := _raw_heal(definition, request, rng)
	var missing_hp := maxi(0, int(context.get("actual_hp_missing", 0)))
	var actual_restored := mini(raw_heal, missing_hp)
	plan.effects = [{
		"type": "dedicated_heal",
		"raw_heal": raw_heal,
		"actual_hp_restored": actual_restored,
		"cap_at_max_hp": true,
		"negative_damage": false,
	}]
	plan.effect_success = actual_restored > 0


static func _raw_heal(definition: Dictionary, request: Dictionary, rng: RefCounted) -> int:
	var context: Dictionary = request.get("target_context", {})
	var raw_fields: Dictionary = definition.get("magic_db_reference", {}).get("raw_fields", {})
	return Formula.raw_magic_power(
		rng,
		int(request.get("rank", 0)),
		raw_fields,
		2 * int(context.get("primary_stat_roll", 0))
	)


static func _resolve_poison(
	plan: Dictionary,
	rank: int,
	request: Dictionary,
	rng: RefCounted
) -> void:
	var context: Dictionary = request.get("target_context", {})
	var sc_roll := int(context.get("primary_stat_roll", 0))
	var resisted: bool = (
		bool(context.get("force_resist", false))
		or not (
			bool(context.get("force_success", false))
			or int(rng.call(
				"pascal_random_exclusive",
				int(context.get("target_poison_resist", 0)) + 7
			)) <= 6
		)
	)
	var duration_seconds: int = SkillRankResolverScript.linear_int(
		[8, 12, 16, 20],
		rank
	) + int(floor(float(sc_roll) / 5.0))
	var resist_bound := maxi(1, int(context.get("target_poison_resist", 0)) + 7)
	var apply_probability := float(mini(7, resist_bound)) / float(resist_bound)
	var green_power := Formula.get_power13(rng, rank, 40) + 2 * sc_roll
	var red_power := Formula.get_power13(rng, rank, 30) + 2 * sc_roll
	var green_effect: Dictionary = {
		"type": "poison_resolution",
		"poison_type": "green_poison",
		"resisted": resisted,
		"apply_probability": apply_probability,
		"duration_seconds": duration_seconds,
		"stacking_policy": "green_and_red_coexist_same_type_refresh",
		"tick_interval_ms": 2000,
		"damage_per_tick": maxi(1, int(floor(float(green_power) / 10.0))),
	}
	var red_reduction := maxi(1, int(floor(float(red_power) / 10.0)))
	var red_effect: Dictionary = {
		"type": "poison_resolution",
		"poison_type": "red_poison",
		"resisted": resisted,
		"apply_probability": apply_probability,
		"duration_seconds": duration_seconds,
		"stacking_policy": "green_and_red_coexist_same_type_refresh",
		"flat_ac_reduction": red_reduction,
		"flat_mac_reduction": red_reduction,
		"extra_durability_loss_per_hit": 1,
	}
	plan.effects = [green_effect, red_effect]
	plan.effect_success = not resisted
	plan.resource_commit = true


static func _spirit_damage_effect(
	definition: Dictionary,
	request: Dictionary,
	rng: RefCounted
) -> Dictionary:
	var context: Dictionary = request.get("target_context", {})
	var raw_fields: Dictionary = definition.get("magic_db_reference", {}).get("raw_fields", {})
	return {
		"type": "talisman_projectile_damage",
		"raw_power": Formula.raw_magic_power(
			rng,
			int(request.get("rank", 0)),
			raw_fields,
			int(context.get("primary_stat_roll", 0))
		),
		"damage_type": "spirit_magic",
		"defence_type": "MAC",
		"server_authoritative": true,
	}


static func _resolve_main_pet(
	plan: Dictionary,
	rank: int,
	context: Dictionary,
	template_id: String,
	max_pet_level: int
) -> void:
	if bool(context.get("has_main_pet", false)):
		plan.effects = [{
			"type": "recall_existing_main_pet",
			"pet_group": "taoist_main_pet",
			"template_requested": template_id,
			"delete_existing": false,
		}]
		plan.resource_commit = false
		plan.effect_success = true
		return
	if not bool(context.get("spawn_tile_valid", true)):
		plan.effects = [{
			"type": "main_pet_spawn",
			"spawned": false,
			"reason": "no_valid_adjacent_tile",
		}]
		plan.resource_commit = false
		plan.effect_success = false
		return
	plan.effects = [{
		"type": "main_pet_spawn",
		"spawned": true,
		"pet_group": "taoist_main_pet",
		"group_limit": 1,
		"template_id": template_id,
		"initial_pet_level": SkillRankResolverScript.summon_pet_level(rank),
		"max_pet_level": max_pet_level,
		"skill_rank_is_pet_level": false,
		"delete_existing": false,
	}]


static func _stealth_effect(
	rank: int,
	context: Dictionary,
	rng: RefCounted,
	buff_id: String
) -> Dictionary:
	var sc_roll := int(context.get("primary_stat_roll", 0))
	return {
		"type": "monster_aggro_stealth",
		"buff_id": buff_id,
		"duration_seconds": maxi(1, Formula.get_power13(rng, rank, 30) + 3 * sc_roll),
		"pvp_invisibility": false,
		"untargetable": false,
		"invulnerable": false,
		"break_on_tile_movement": true,
		"break_on_melee_attack": false,
		"break_on_ranged_spell_cast": false,
		"break_on_damage": false,
	}


static func _resolve_mass_invisibility(
	plan: Dictionary,
	rank: int,
	context: Dictionary,
	rng: RefCounted
) -> void:
	var affected_count := maxi(0, int(context.get("affected_friendly_count", 0)))
	var target_instance_ids := _instance_ids(
		context.get("affected_friendly_target_instance_ids", [])
	)
	var effect := _stealth_effect(rank, context, rng, "buff.taoist.mass_invisibility")
	effect["type"] = "area_monster_aggro_stealth"
	effect["affected_count"] = affected_count
	effect["target_instance_ids"] = target_instance_ids
	effect["width_grid_steps"] = 3
	effect["height_grid_steps"] = 3
	plan.effects = [effect]
	plan.effect_success = affected_count > 0
	plan.resource_commit = affected_count > 0


static func _resolve_defence_buff(
	plan: Dictionary,
	rank: int,
	context: Dictionary,
	rng: RefCounted,
	mechanics: Dictionary
) -> void:
	var targets: Array = context.get("friendly_targets", [])
	var effects: Array[Dictionary] = []
	var sc_roll := int(context.get("primary_stat_roll", 0))
	var duration_seconds := maxi(
		1,
		int(floor(float(Formula.get_power13(rng, rank, 60) + 10 * sc_roll) / 10.0))
	)
	for target_value: Variant in targets:
		if not target_value is Dictionary:
			continue
		var target: Dictionary = target_value
		effects.append({
			"type": "friendly_defence_buff",
			"buff_id": str(mechanics.get("buff_id", "")),
			"stat": str(mechanics.get("stat", "")),
			"flat_bonus": maxi(1, int(floor(float(target.get("level", 1)) / 7.0))),
			"duration_seconds": duration_seconds,
			"stacking_policy": str(mechanics.get("stacking_policy", "")),
			"target_instance_id": int(target.get("target_instance_id", 0)),
		})
	plan.effects = effects
	plan.effect_success = not effects.is_empty()
	plan.resource_commit = not effects.is_empty()


static func _resolve_revelation(
	plan: Dictionary,
	rank: int,
	context: Dictionary,
	rng: RefCounted
) -> void:
	if not bool(context.get("target_is_living", true)):
		_reject(plan, "living_revelation_target_required")
		return
	var probability := SkillRankResolverScript.capped_probability(
		float(rank + 4) / 6.0
	)
	var revealed: bool = (
		bool(context.get("force_success", false))
		or int(rng.call("pascal_random_exclusive", 6)) <= rank + 3
	)
	var duration_ms := Formula.get_power13(
		rng,
		rank,
		2 * int(context.get("primary_stat_roll", 0)) + 30
	) * 1000
	plan.effects = [{
		"type": "hp_information_reveal",
		"revealed": revealed,
		"success_probability": probability,
		"duration_ms": duration_ms,
		"fields": ["current_hp", "max_hp"],
		"damage": 0,
		"target_stat_modification": false,
	}]
	plan.effect_success = revealed


static func _resolve_entrapment(
	plan: Dictionary,
	rank: int,
	context: Dictionary,
	rng: RefCounted
) -> void:
	var candidates: Array = context.get("targets", [])
	var trapped_count := 0
	var trapped_target_instance_ids: Array[int] = []
	for target_value: Variant in candidates:
		if not target_value is Dictionary:
			continue
		var target: Dictionary = target_value
		if (
			bool(target.get("hostile_monster", false))
			and not bool(target.get("is_boss", false))
			and not bool(target.get("control_immune", false))
			and bool(target.get("within_level_gate", true))
		):
			trapped_count += 1
			var target_instance_id := int(target.get("target_instance_id", 0))
			if target_instance_id > 0:
				trapped_target_instance_ids.append(target_instance_id)
	var duration_seconds := maxi(
		1,
		Formula.get_power13(rng, rank, 40) + 3 * int(context.get("primary_stat_roll", 0))
	)
	plan.effects = [{
		"type": "monster_boundary_control",
		"trapped_count": trapped_count,
		"target_instance_ids": trapped_target_instance_ids,
		"duration_seconds": duration_seconds,
		"footprint": "canonical_3x3_boundary",
		"prevents_boundary_exit": true,
		"break_on_any_player_entry": true,
		"external_attack_behavior": "trapped_state_evasion_policy",
		"generic_root": false,
	}]
	plan.effect_success = trapped_count > 0
	plan.resource_commit = trapped_count > 0


static func _resolve_mass_heal(
	plan: Dictionary,
	definition: Dictionary,
	request: Dictionary,
	rng: RefCounted
) -> void:
	var context: Dictionary = request.get("target_context", {})
	var raw_heal := _raw_heal(definition, request, rng)
	var target_missing_hp: Array = context.get("friendly_missing_hp", [])
	var target_instance_ids := _instance_ids(
		context.get("friendly_target_instance_ids", [])
	)
	var actual_by_target: Array[int] = []
	var target_results: Array[Dictionary] = []
	var total_restored := 0
	for target_index: int in range(target_missing_hp.size()):
		var missing_value: Variant = target_missing_hp[target_index]
		var actual := mini(raw_heal, maxi(0, int(missing_value)))
		actual_by_target.append(actual)
		target_results.append({
			"target_instance_id": (
				int(target_instance_ids[target_index])
				if target_index < target_instance_ids.size()
				else 0
			),
			"actual_hp_restored": actual,
		})
		total_restored += actual
	plan.effects = [{
		"type": "dedicated_area_heal",
		"raw_heal_per_target": raw_heal,
		"actual_hp_restored_by_target": actual_by_target,
		"target_instance_ids": target_instance_ids,
		"target_results": target_results,
		"total_actual_hp_restored": total_restored,
		"width_grid_steps": 3,
		"height_grid_steps": 3,
		"negative_damage": false,
	}]
	plan.effect_success = total_restored > 0


static func _instance_ids(raw_ids: Variant) -> Array[int]:
	var result: Array[int] = []
	if not raw_ids is Array:
		return result
	for raw_id: Variant in raw_ids:
		result.append(int(raw_id))
	return result


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


static func _reject(plan: Dictionary, reason: String) -> Dictionary:
	plan.accepted = false
	plan.effect_success = false
	plan.reason = reason
	plan.resource_commit = false
	return plan
