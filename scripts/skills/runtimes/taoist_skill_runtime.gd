class_name TaoistSkillRuntime
extends RefCounted

const Formula := preload("res://scripts/skills/formulas/mir2_skill_formula.gd")


static func execute(definition: Dictionary, request: Dictionary, rng: RefCounted) -> Dictionary:
	var skill_id := str(definition.get("skill_id", ""))
	var rank := clampi(int(request.get("rank", 0)), 0, 3)
	var context: Dictionary = request.get("target_context", {})
	var mechanics: Dictionary = definition.get("mechanics", {})
	var trigger := str(definition.get("proficiency_trigger", {}).get("event", ""))
	var plan := _base_plan(definition)
	match skill_id:
		"taoist.healing":
			_resolve_single_heal(plan, definition, request, rng, trigger)
		"taoist.spiritual_warfare":
			plan.effects = [{
				"type": "passive_stat_modifier",
				"stat": "accuracy",
				"value": int(mechanics.get("flat_bonus_by_rank", [0, 0, 0, 0])[rank]),
				"affects": mechanics.get("affects", []).duplicate(),
			}]
			if bool(context.get("valid_melee_swing", false)):
				plan.proficiency_event = trigger
		"taoist.poison":
			_resolve_poison(plan, rank, request, rng, trigger)
		"taoist.soul_fire_talisman":
			plan.effects = [_spirit_damage_effect(definition, request, rng)]
			plan.proficiency_event = trigger
		"taoist.summon_skeleton":
			_resolve_main_pet(plan, rank, context, trigger, "skeleton", rank + 4)
		"taoist.invisibility":
			plan.effects = [_stealth_effect(rank, context, rng, "buff.taoist.invisibility")]
			plan.proficiency_event = trigger
		"taoist.mass_invisibility":
			_resolve_mass_invisibility(plan, rank, context, rng, trigger)
		"taoist.magic_defense", "taoist.defense":
			_resolve_defence_buff(plan, rank, context, rng, mechanics, trigger)
		"taoist.revelation":
			_resolve_revelation(plan, rank, context, rng, trigger)
		"taoist.entrapment":
			_resolve_entrapment(plan, rank, context, rng, trigger)
		"taoist.mass_healing":
			_resolve_mass_heal(plan, definition, request, rng, trigger)
		"taoist.summon_divine_beast":
			_resolve_main_pet(plan, rank, context, trigger, "divine_beast", 1 + 2 * rank)
		_:
			return _reject(plan, "unknown_taoist_skill")
	return plan


static func _resolve_single_heal(
	plan: Dictionary,
	definition: Dictionary,
	request: Dictionary,
	rng: RefCounted,
	trigger: String
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
	if actual_restored > 0:
		plan.proficiency_event = trigger


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
	rng: RefCounted,
	trigger: String
) -> void:
	var context: Dictionary = request.get("target_context", {})
	var resources: Dictionary = request.get("resource_context", {})
	var selected: String = str(resources.get("selected_material", ""))
	if selected not in ["grey_powder", "yellow_powder"]:
		_reject(plan, "selected_poison_powder")
		return
	var poison_type: String = "green_poison" if selected == "grey_powder" else "red_poison"
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
	var duration_seconds: int = int([8, 12, 16, 20][rank]) + int(floor(float(sc_roll) / 5.0))
	var resist_bound := maxi(1, int(context.get("target_poison_resist", 0)) + 7)
	var power_base: int = 40 if poison_type == "green_poison" else 30
	var power: int = Formula.get_power13(rng, rank, power_base) + 2 * sc_roll
	var effect: Dictionary = {
		"type": "poison_resolution",
		"poison_type": poison_type,
		"resisted": resisted,
		"apply_probability": float(mini(7, resist_bound)) / float(resist_bound),
		"duration_seconds": duration_seconds,
		"stacking_policy": "green_and_red_coexist_same_type_refresh",
	}
	if poison_type == "green_poison":
		effect["tick_interval_ms"] = 2000
		effect["damage_per_tick"] = maxi(1, int(floor(float(power) / 10.0)))
	else:
		effect["flat_ac_reduction"] = maxi(1, int(floor(float(power) / 10.0)))
		effect["flat_mac_reduction"] = maxi(1, int(floor(float(power) / 10.0)))
		effect["extra_durability_loss_per_hit"] = 1
	plan.effects = [effect]
	plan.effect_success = not resisted
	plan.resource_commit = true
	if not resisted:
		plan.proficiency_event = trigger


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
	trigger: String,
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
		"initial_pet_level": rank,
		"max_pet_level": max_pet_level,
		"skill_rank_is_pet_level": false,
		"delete_existing": false,
	}]
	plan.proficiency_event = trigger


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
	rng: RefCounted,
	trigger: String
) -> void:
	var affected_count := maxi(0, int(context.get("affected_friendly_count", 0)))
	var effect := _stealth_effect(rank, context, rng, "buff.taoist.mass_invisibility")
	effect["type"] = "area_monster_aggro_stealth"
	effect["affected_count"] = affected_count
	effect["width_tiles"] = 3
	effect["height_tiles"] = 3
	plan.effects = [effect]
	plan.effect_success = affected_count > 0
	plan.resource_commit = affected_count > 0
	if affected_count > 0:
		plan.proficiency_event = trigger


static func _resolve_defence_buff(
	plan: Dictionary,
	rank: int,
	context: Dictionary,
	rng: RefCounted,
	mechanics: Dictionary,
	trigger: String
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
		})
	plan.effects = effects
	plan.effect_success = not effects.is_empty()
	plan.resource_commit = not effects.is_empty()
	if not effects.is_empty():
		plan.proficiency_event = trigger


static func _resolve_revelation(
	plan: Dictionary,
	rank: int,
	context: Dictionary,
	rng: RefCounted,
	trigger: String
) -> void:
	if not bool(context.get("target_is_living", true)):
		_reject(plan, "living_revelation_target_required")
		return
	var probability := clampf(float(rank + 4) / 6.0, 0.0, 1.0)
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
	if revealed:
		plan.proficiency_event = trigger


static func _resolve_entrapment(
	plan: Dictionary,
	rank: int,
	context: Dictionary,
	rng: RefCounted,
	trigger: String
) -> void:
	var candidates: Array = context.get("targets", [])
	var trapped_count := 0
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
	var duration_seconds := maxi(
		1,
		Formula.get_power13(rng, rank, 40) + 3 * int(context.get("primary_stat_roll", 0))
	)
	plan.effects = [{
		"type": "monster_boundary_control",
		"trapped_count": trapped_count,
		"duration_seconds": duration_seconds,
		"footprint": "canonical_3x3_boundary",
		"prevents_boundary_exit": true,
		"break_on_any_player_entry": true,
		"external_attack_behavior": "trapped_state_evasion_policy",
		"generic_root": false,
	}]
	plan.effect_success = trapped_count > 0
	plan.resource_commit = trapped_count > 0
	if trapped_count > 0:
		plan.proficiency_event = trigger


static func _resolve_mass_heal(
	plan: Dictionary,
	definition: Dictionary,
	request: Dictionary,
	rng: RefCounted,
	trigger: String
) -> void:
	var context: Dictionary = request.get("target_context", {})
	var raw_heal := _raw_heal(definition, request, rng)
	var target_missing_hp: Array = context.get("friendly_missing_hp", [])
	var actual_by_target: Array[int] = []
	var total_restored := 0
	for missing_value: Variant in target_missing_hp:
		var actual := mini(raw_heal, maxi(0, int(missing_value)))
		actual_by_target.append(actual)
		total_restored += actual
	plan.effects = [{
		"type": "dedicated_area_heal",
		"raw_heal_per_target": raw_heal,
		"actual_hp_restored_by_target": actual_by_target,
		"total_actual_hp_restored": total_restored,
		"width_tiles": 3,
		"height_tiles": 3,
		"negative_damage": false,
	}]
	plan.effect_success = total_restored > 0
	if total_restored > 0:
		plan.proficiency_event = trigger


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
