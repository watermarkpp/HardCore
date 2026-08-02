class_name WizardSkillRuntime
extends RefCounted

const Formula := preload("res://scripts/skills/formulas/mir2_skill_formula.gd")


static func execute(definition: Dictionary, request: Dictionary, rng: RefCounted) -> Dictionary:
	var skill_id := str(definition.get("skill_id", ""))
	var rank := clampi(int(request.get("rank", 0)), 0, 3)
	var caster_level := int(request.get("caster_level", 1))
	var context: Dictionary = request.get("target_context", {})
	var mechanics: Dictionary = definition.get("mechanics", {})
	var trigger := str(definition.get("proficiency_trigger", {}).get("event", ""))
	var plan := _base_plan(definition)
	match skill_id:
		"wizard.fireball", "wizard.great_fireball":
			plan.effects = [_damage_effect(definition, request, rng, "projectile_damage")]
			plan.proficiency_event = trigger
		"wizard.repulsion_ring":
			_resolve_repulsion(plan, rank, caster_level, context, rng, trigger)
		"wizard.temptation_light":
			_resolve_temptation(plan, rank, caster_level, context, rng, trigger)
		"wizard.hellfire":
			var hellfire := _damage_effect(definition, request, rng, "line_damage")
			hellfire["length_tiles"] = int(definition.get("geometry", {}).get("length_tiles", 4))
			hellfire["width_tiles"] = float(definition.get("geometry", {}).get("width_tiles", 1.5))
			hellfire["pierces_units"] = false
			# The primary 1.76 geometry and target-count contracts are independent.
			# This project's user-authoritative presentation override shortens the
			# formal five-cell source line to four cells without changing its width,
			# power formula, terrain blocking or all-intersecting target semantics.
			# client flag above describes the line effect's movement semantics; it
			# must not be adapted into a one-monster damage cap.
			hellfire["maximum_targets"] = 0
			hellfire["target_limit_policy"] = "all_intersecting_effect_cells"
			hellfire["target_selection_contract"] = (
				"skills.wizard.hellfire.all_intersecting_4x1_5_user_override.v1"
			)
			hellfire["line_geometry_contract"] = (
				"skills.wizard.line.continuous_tile_axis_footprint_sat.v1"
			)
			hellfire["cast_input_contract"] = (
				"skills.wizard.hellfire.discrete_cast_hold_repeats_after_recast_gate.v1"
			)
			hellfire["channeled"] = false
			hellfire["stops_on_terrain"] = bool(definition.get("geometry", {}).get("stops_on_terrain", true))
			plan.effects = [hellfire]
			plan.proficiency_event = trigger
		"wizard.lightning":
			var lightning := _damage_effect(definition, request, rng, "targeted_sky_strike")
			var race_multiplier := 1.5 if bool(context.get("target_is_undead", false)) else 1.0
			lightning["race_multiplier"] = race_multiplier
			lightning["raw_power_after_race"] = roundi(float(lightning.raw_power) * race_multiplier)
			lightning["horizontal_projectile"] = false
			plan.effects = [lightning]
			plan.proficiency_event = trigger
		"wizard.teleport":
			_resolve_teleport(plan, rank, context, rng, trigger)
		"wizard.exploding_flame", "wizard.ice_storm":
			var area := _damage_effect(definition, request, rng, "area_damage")
			area["width_tiles"] = int(definition.get("geometry", {}).get("width_tiles", 3))
			area["height_tiles"] = int(definition.get("geometry", {}).get("height_tiles", 3))
			plan.effects = [area]
			plan.proficiency_event = trigger
		"wizard.fire_wall":
			var primary_stat_roll := int(context.get("primary_stat_roll", 0))
			var field := _damage_effect(definition, request, rng, "persistent_ground_damage")
			field["width_tiles"] = 2
			field["height_tiles"] = 2
			field["tick_interval_ms"] = int(definition.get("timing", {}).get("tick_interval_ms", 1000))
			field["max_ticks_per_target_per_caster"] = 1
			field["duration_seconds"] = maxi(
				1,
				Formula.get_power(rng, rank, 10) + int(floor(float(primary_stat_roll) / 2.0))
			)
			field["stacking_policy"] = str(mechanics.get("stacking_policy", ""))
			plan.effects = [field]
			plan.proficiency_event = trigger
		"wizard.laser":
			var laser := _damage_effect(definition, request, rng, "piercing_line_damage")
			laser["length_tiles"] = int(definition.get("geometry", {}).get("length_tiles", 8))
			laser["width_tiles"] = int(definition.get("geometry", {}).get("width_tiles", 1))
			laser["pierces_units"] = true
			laser["line_geometry_contract"] = (
				"skills.wizard.line.continuous_tile_axis_footprint_sat.v1"
			)
			laser["stops_on_terrain"] = bool(definition.get("geometry", {}).get("stops_on_terrain", true))
			plan.effects = [laser]
			plan.proficiency_event = trigger
		"wizard.hell_lightning":
			var ring := _damage_effect(definition, request, rng, "caster_centered_area_damage")
			ring["radius_tiles"] = int(definition.get("geometry", {}).get("radius_tiles", 2))
			ring["exclude_center"] = true
			ring["maximum_targets"] = int(mechanics.get("maximum_targets", 24))
			plan.effects = [ring]
			plan.proficiency_event = trigger
		"wizard.magic_shield":
			var mc_roll := int(context.get("primary_stat_roll", 0))
			plan.effects = [{
				"type": "refreshable_damage_reduction_buff",
				"buff_id": "buff.wizard.magic_shield",
				"duration_seconds": maxi(1, Formula.get_power(rng, rank, mc_roll + 15)),
				"damage_reduction": float(mechanics.get("damage_reduction_by_rank", [0.15, 0.3, 0.45, 0.6])[rank]),
				"affected_damage_types": mechanics.get("affected_damage_types", []).duplicate(),
				"stack_count_max": 1,
				"stacking_policy": "refresh_same_buff_no_stacking",
			}]
			plan.proficiency_event = trigger
		"wizard.holy_word":
			_resolve_holy_word(plan, rank, caster_level, context, rng, trigger)
		_:
			return _reject(plan, "unknown_wizard_skill")
	return plan


static func _damage_effect(
	definition: Dictionary,
	request: Dictionary,
	rng: RefCounted,
	effect_type: String
) -> Dictionary:
	var context: Dictionary = request.get("target_context", {})
	var raw_fields: Dictionary = definition.get("magic_db_reference", {}).get("raw_fields", {})
	var raw_power := Formula.raw_magic_power(
		rng,
		int(request.get("rank", 0)),
		raw_fields,
		int(context.get("primary_stat_roll", 0))
	)
	return {
		"type": effect_type,
		"raw_power": raw_power,
		"damage_type": str(definition.get("mechanics", {}).get("damage_type", "magic")),
		"defence_type": str(definition.get("mechanics", {}).get("defence_type", "MAC")),
		"server_authoritative": true,
	}


static func _resolve_repulsion(
	plan: Dictionary,
	rank: int,
	caster_level: int,
	context: Dictionary,
	rng: RefCounted,
	trigger: String
) -> void:
	var resolutions: Array[Dictionary] = []
	var displaced_count := 0
	var targets: Array = context.get("targets", [])
	for target_value: Variant in targets:
		if not target_value is Dictionary:
			continue
		var target: Dictionary = target_value
		var target_level := int(target.get("level", caster_level))
		var eligible := (
			target_level < caster_level
			and not bool(target.get("is_boss", false))
			and not bool(target.get("immovable", false))
		)
		var probability := clampf(
			(6.0 + 3.0 * float(rank) + float(caster_level - target_level)) / 20.0,
			0.0,
			1.0
		)
		var roll_success: bool = (
			eligible
			and (
				bool(target.get("force_success", context.get("force_success", false)))
				or bool(rng.call("chance", probability))
			)
		)
		var path_clear := not bool(target.get("path_blocked", false))
		var displaced: bool = roll_success and path_clear
		if displaced:
			displaced_count += 1
		resolutions.append({
			"type": "adjacent_push",
			"target_instance_id": int(target.get("instance_id", 0)),
			"eligible": eligible,
			"success_probability": probability,
			"push_distance_tiles": 1 + maxi(0, rank - 1) + int(rng.call("pascal_random_exclusive", 2)),
			"displaced": displaced,
			"damage": 0,
		})
	plan.effects = resolutions
	plan.effect_success = displaced_count > 0
	plan.resource_commit = true
	if displaced_count > 0:
		plan.proficiency_event = trigger


static func _resolve_temptation(
	plan: Dictionary,
	rank: int,
	caster_level: int,
	context: Dictionary,
	rng: RefCounted,
	trigger: String
) -> void:
	if (
		not bool(context.get("target_is_monster", false))
		or bool(context.get("target_is_boss", false))
		or bool(context.get("target_has_other_master", false))
	):
		_reject(plan, "ineligible_temptation_target")
		return
	var forced_outcome := str(context.get("forced_temptation_outcome", ""))
	var outcome := forced_outcome
	var duration_seconds := 0
	if outcome.is_empty():
		if int(rng.call("pascal_random_exclusive", 4 - rank)) != 0:
			outcome = "no_effect"
		elif int(rng.call("pascal_random_exclusive", 2)) != 0:
			outcome = "rooted"
			duration_seconds = int(rng.call("pascal_random_exclusive", rank * 5 + 10))
		elif int(context.get("target_level", 1)) > caster_level + 2:
			outcome = "no_effect"
		elif int(rng.call("pascal_random_exclusive", 3)) != 0:
			if bool(context.get("target_is_undead", false)):
				outcome = "no_effect"
			else:
				outcome = "confused"
				duration_seconds = int(rng.call("pascal_random_exclusive", 20)) + 10
		elif int(rng.call(
			"pascal_random_exclusive",
			caster_level + 20 + rank * 5
		)) <= int(context.get("target_level", 1)) + 10:
			if (
				not bool(context.get("target_is_undead", false))
				and int(rng.call("pascal_random_exclusive", 20)) == 0
			):
				outcome = "confused"
				duration_seconds = int(rng.call("pascal_random_exclusive", 20)) + 10
			else:
				outcome = "no_effect"
		elif (
			not bool(context.get("target_tameable", false))
			or bool(context.get("target_is_undead", false))
			or int(context.get("target_level", 1)) > 50
			or int(context.get("current_pet_count", 0)) >= rank + 2
		):
			if (
				bool(context.get("target_is_undead", false))
				and int(rng.call("pascal_random_exclusive", 20)) == 0
			):
				outcome = "instant_kill"
			else:
				outcome = "no_effect"
		else:
			var hp_rate := int(floor(float(context.get("target_max_hp", 100)) / 100.0))
			var tame_difficulty := 2 if hp_rate <= 2 else hp_rate * 2
			if int(rng.call("pascal_random_exclusive", tame_difficulty)) == 0:
				outcome = "tamed"
			elif int(rng.call("pascal_random_exclusive", 14)) == 0:
				outcome = "instant_kill"
			else:
				outcome = "no_effect"
	if outcome == "rooted" and duration_seconds == 0:
		duration_seconds = maxi(1, int(context.get("forced_duration_seconds", 1)))
	elif outcome == "confused" and duration_seconds == 0:
		duration_seconds = maxi(1, int(context.get("forced_duration_seconds", 10)))
	var state_changed := outcome in ["tamed", "rooted", "confused", "instant_kill"]
	var effect := {
		"type": "temptation_resolution",
		"outcome": outcome,
		"duration_seconds": duration_seconds,
		"pet_group": "wizard_tamed_pet",
		"pet_make_level": rank,
		"pet_cap": rank + 2,
		"server_authoritative": true,
	}
	if outcome == "tamed":
		effect["loyalty_duration_ms"] = (
			int(rng.call("pascal_random_exclusive", caster_level * 2)) + rank * 20 + 20
		) * 60 * 1000
		effect["walk_speed_cap_ms"] = 1500 - rank * 200
		effect["attack_interval_cap_ms"] = 2000 - rank * 200
	plan.effects = [effect]
	plan.effect_success = state_changed
	if state_changed:
		plan.proficiency_event = trigger


static func _resolve_teleport(
	plan: Dictionary,
	rank: int,
	context: Dictionary,
	rng: RefCounted,
	trigger: String
) -> void:
	if not bool(context.get("map_allows_random_teleport", true)):
		_reject(plan, "map_disallows_random_teleport")
		return
	var probability := float(2 * rank + 4) / 11.0
	var roll_success: bool = (
		not bool(context.get("force_failure", false))
		and (
			bool(context.get("force_success", false))
			or int(rng.call("pascal_random_exclusive", 11)) < 2 * rank + 4
		)
	)
	var destination_valid := bool(context.get("destination_valid", true))
	var moved: bool = roll_success and destination_valid
	plan.effects = [{
		"type": "server_random_teleport",
		"server_authoritative": true,
		"forward_dash": false,
		"success_probability": probability,
		"moved": moved,
		"destination": context.get("destination_tile") if moved else null,
		"remain_in_place_on_failure": true,
	}]
	plan.effect_success = moved
	plan.proficiency_event = trigger


static func _resolve_holy_word(
	plan: Dictionary,
	rank: int,
	caster_level: int,
	context: Dictionary,
	rng: RefCounted,
	trigger: String
) -> void:
	if (
		not bool(context.get("target_is_monster", false))
		or not bool(context.get("target_is_undead", false))
		or bool(context.get("target_is_boss", false))
		or bool(context.get("holy_word_immune", false))
	):
		_reject(plan, "ineligible_holy_word_target")
		return
	var target_level := int(context.get("target_level", 1))
	var precheck := (
		bool(context.get("force_success", false))
		or int(rng.call("pascal_random_exclusive", 2)) + caster_level - 1 > target_level
	)
	var probability := clampf(
		(7.0 * float(rank) + 15.0 + float(caster_level - target_level)) / 100.0,
		0.0,
		1.0
	)
	var killed: bool = (
		precheck
		and (
			bool(context.get("force_success", false))
			or bool(rng.call("chance", probability))
		)
	)
	plan.effects = [{
		"type": "holy_word_resolution",
		"eligible": true,
		"precheck_passed": precheck,
		"kill_probability": probability,
		"instant_kill": killed,
		"normal_damage": 0,
	}]
	plan.effect_success = killed
	if killed:
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
