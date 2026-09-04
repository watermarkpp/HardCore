class_name TaoistSkillRuntime
extends RefCounted

const Formula := preload("res://scripts/skills/formulas/mir2_skill_formula.gd")
const SkillRankResolverScript := preload(
	"res://scripts/skills/skill_rank_resolver.gd"
)
const TaoistCombatMathScript := preload(
	"res://scripts/taoist_combat_math.gd"
)
const SkillDataLoaderScript := preload(
	"res://scripts/skills/skill_data_loader.gd"
)
const TaoistSupportPolicyScript := preload(
	"res://scripts/skills/taoist_support_policy.gd"
)
const TaoistFriendlyTargetingScript := preload(
	"res://scripts/skills/taoist_friendly_targeting.gd"
)

const SUPPORT_TARGETING_CONTRACT_ID := (
	TaoistSupportPolicyScript.CONTRACT_ID
)
const FRIENDLY_AREA_GEOMETRY_CONTRACT_ID := (
	TaoistFriendlyTargetingScript.CONTRACT_ID
)
const DUAL_DEFENSE_CAST_CONTRACT_ID := "skills.taoist.dual_defense_cast.v1"
const ONGOING_HEAL_CONTRACT_ID := "skills.taoist.ongoing_heal.v1"
const ENTRAPMENT_CONTROLLER_CONTRACT_ID := (
	"skills.taoist.entrapment.boundary_controller.v1"
)
const HEAL_SELECTION_RANGE_GU := (
	TaoistSupportPolicyScript.DEFAULT_HEAL_RANGE_GU
)
const DUAL_DEFENSE_SKILL_IDS: Array[String] = [
	"taoist.magic_defense",
	"taoist.defense",
]
const MASS_INVISIBILITY_GRID_SIZE := 3
const DEFENCE_CHEBYSHEV_RADIUS := 3
const ONGOING_HEAL_TICK_COUNT := 3
const ONGOING_HEAL_TICK_INTERVAL_SECONDS := 0.8


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
			_resolve_defence_buff(plan, definition, request, rng)
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
	# Canonical consumers use the explicit field; keep the legacy field in
	# lockstep until every integration sink has migrated.
	plan.resource_commit_required = bool(plan.get("resource_commit", true))
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
	var rank := SkillRankResolverScript.safe_effective_rank(
		int(request.get("rank", 0))
	)
	var skill_id := str(definition.get("skill_id", ""))
	var candidates := _support_candidates(context)
	var selection: Dictionary = {}
	var selected: Dictionary = {}
	if not candidates.is_empty():
		selection = _heal_selection(context, candidates)
		if not bool(selection.get("valid", false)):
			_reject(
				plan,
				str(selection.get("reason", "friendly_heal_target_required"))
			)
			return
		selected = selection.get("selected", {})
	var raw_heal := _raw_heal(definition, request, rng)
	var missing_hp := 0
	var target_instance_id := 0
	var target_is_self := false
	if not selected.is_empty():
		missing_hp = int(selected.get("max_hp", 1)) - int(
			selected.get("current_hp", 0)
		)
		target_instance_id = int(selected.get("instance_id", 0))
		target_is_self = bool(selected.get("is_self", false))
	else:
		missing_hp = maxi(0, int(context.get("actual_hp_missing", 0)))
	var actual_restored := mini(raw_heal, missing_hp)
	var effect := {
		"type": "dedicated_heal",
		"skill_id": skill_id,
		"rank": rank,
		"target_instance_id": target_instance_id,
		"target_is_self": target_is_self,
		"raw_heal": raw_heal,
		"actual_hp_restored": actual_restored,
		"cap_at_max_hp": true,
		"negative_damage": false,
		"selection_contract_id": SUPPORT_TARGETING_CONTRACT_ID,
		"selection_range_gu": HEAL_SELECTION_RANGE_GU,
	}
	if missing_hp <= 0:
		## User override: a full-HP friendly target is still a valid cast
		## target and receives an attached ongoing recovery (3 x 0.8s ticks).
		effect["ongoing_heal"] = _ongoing_heal_descriptor(
			skill_id,
			target_instance_id,
			raw_heal
		)
	plan.effects = [effect]
	## Full-HP casts succeed and commit resources (ongoing recovery attached);
	## proficiency still keys off actual_hp_restored_gt_zero at the caller.
	plan.effect_success = true
	if not selected.is_empty():
		plan["support_targeting"] = selection


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
	var has_requested_main_pet := false
	if context.has("active_main_pet_summon_ids"):
		var active_ids: Variant = context.get("active_main_pet_summon_ids", [])
		has_requested_main_pet = (
			active_ids is Array and (active_ids as Array).has(template_id)
		)
	else:
		# Compatibility for older isolated planner fixtures. Production always
		# supplies the typed active-id list.
		has_requested_main_pet = bool(context.get("has_main_pet", false))
	if has_requested_main_pet:
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
		"group_limit_scope": "summon_id",
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
		## User override (2026-08-09): any attack or skill submission breaks
		## stealth uniformly; the SOT's per-source break flags are superseded.
		"break_on_melee_attack": true,
		"break_on_ranged_spell_cast": true,
		"break_on_damage": false,
	}


static func _resolve_mass_invisibility(
	plan: Dictionary,
	rank: int,
	context: Dictionary,
	rng: RefCounted
) -> void:
	var candidates := _support_candidates(context)
	if not candidates.is_empty():
		var center_ground_gu: Variant = context.get(
			"caster_ground_position_gu",
			Vector2.ZERO
		)
		if not center_ground_gu is Vector2:
			_reject(plan, "friendly_target_context_required")
			return
		var center_tile := TaoistFriendlyTargetingScript.grid_tile(
			center_ground_gu
		)
		var cells := TaoistFriendlyTargetingScript.exact_square_cells(
			center_tile,
			MASS_INVISIBILITY_GRID_SIZE
		)
		var affected := TaoistFriendlyTargetingScript.candidates_in_cells(
			candidates,
			center_ground_gu,
			cells
		)
		var effect := _stealth_effect(
			rank,
			context,
			rng,
			"buff.taoist.mass_invisibility"
		)
		effect["type"] = "area_monster_aggro_stealth"
		effect["affected_count"] = affected.size()
		effect["target_instance_ids"] = _instance_ids_from_candidates(affected)
		effect["width_grid_steps"] = MASS_INVISIBILITY_GRID_SIZE
		effect["height_grid_steps"] = MASS_INVISIBILITY_GRID_SIZE
		effect["center_ground_gu"] = center_ground_gu
		effect["center_tile"] = center_tile
		effect["area_contract_id"] = FRIENDLY_AREA_GEOMETRY_CONTRACT_ID
		effect["support_contract_id"] = SUPPORT_TARGETING_CONTRACT_ID
		plan.effects = [effect]
		plan["support_area_geometry"] = _area_geometry(
			"square",
			center_tile,
			center_ground_gu,
			cells,
			affected,
			{
				"width_grid_steps": MASS_INVISIBILITY_GRID_SIZE,
				"height_grid_steps": MASS_INVISIBILITY_GRID_SIZE,
			}
		)
		plan.effect_success = not affected.is_empty()
		plan.resource_commit = not affected.is_empty()
		return
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
	definition: Dictionary,
	request: Dictionary,
	rng: RefCounted
) -> void:
	var context: Dictionary = request.get("target_context", {})
	var rank := SkillRankResolverScript.safe_effective_rank(
		int(request.get("rank", 0))
	)
	var mechanics: Dictionary = definition.get("mechanics", {})
	var skill_id := str(definition.get("skill_id", ""))
	var candidates := _support_candidates(context)
	if not candidates.is_empty():
		var center_ground_gu: Variant = context.get(
			"caster_ground_position_gu",
			Vector2.ZERO
		)
		if not center_ground_gu is Vector2:
			_reject(plan, "friendly_target_context_required")
			return
		var center_tile := TaoistFriendlyTargetingScript.grid_tile(
			center_ground_gu
		)
		var cells := TaoistFriendlyTargetingScript.chebyshev_area_cells(
			center_tile,
			DEFENCE_CHEBYSHEV_RADIUS
		)
		var affected := TaoistFriendlyTargetingScript.candidates_in_cells(
			candidates,
			center_ground_gu,
			cells
		)
		var dual_context: Variant = context.get("dual_defense_context", {})
		var is_dual := (
			dual_context is Dictionary
			and str((dual_context as Dictionary).get(
				"partner_skill_id",
				""
			)) in DUAL_DEFENSE_SKILL_IDS
			and str((dual_context as Dictionary).get(
				"partner_skill_id",
				""
			)) != skill_id
		)
		plan["support_area_geometry"] = _area_geometry(
			"chebyshev_area",
			center_tile,
			center_ground_gu,
			cells,
			affected,
			{"radius_grid_steps": DEFENCE_CHEBYSHEV_RADIUS}
		)
		if is_dual:
			_resolve_dual_defence_effects(
				plan,
				skill_id,
				rank,
				dual_context as Dictionary,
				affected,
				context,
				rng
			)
		else:
			var duration_seconds := _defence_duration(rank, context, rng)
			var effects: Array[Dictionary] = []
			for target: Dictionary in affected:
				var value := _defence_value(int(target.get("level", 1)))
				effects.append({
					"type": "friendly_defence_buff",
					"skill_id": skill_id,
					"rank": rank,
					"buff_id": str(mechanics.get("buff_id", "")),
					"stat": str(mechanics.get("stat", "")),
					"flat_bonus": value,
					"value": value,
					"duration_seconds": duration_seconds,
					"stacking_policy": str(mechanics.get("stacking_policy", "")),
					"target_instance_id": int(target.get("instance_id", 0)),
					"target_is_self": bool(target.get("is_self", false)),
					"level": int(target.get("level", 1)),
				})
			plan.effects = effects
		plan.effect_success = not affected.is_empty()
		plan.resource_commit = not affected.is_empty()
		return
	var targets: Array = context.get("friendly_targets", [])
	var legacy_effects: Array[Dictionary] = []
	var duration_seconds := _defence_duration(rank, context, rng)
	for target_value: Variant in targets:
		if not target_value is Dictionary:
			continue
		var target: Dictionary = target_value
		legacy_effects.append({
			"type": "friendly_defence_buff",
			"buff_id": str(mechanics.get("buff_id", "")),
			"stat": str(mechanics.get("stat", "")),
			"flat_bonus": maxi(1, int(floor(float(target.get("level", 1)) / 7.0))),
			"duration_seconds": duration_seconds,
			"stacking_policy": str(mechanics.get("stacking_policy", "")),
			"target_instance_id": int(target.get("target_instance_id", 0)),
		})
	plan.effects = legacy_effects
	plan.effect_success = not legacy_effects.is_empty()
	plan.resource_commit = not legacy_effects.is_empty()


static func _resolve_dual_defence_effects(
	plan: Dictionary,
	clicked_skill_id: String,
	clicked_rank: int,
	dual_context: Dictionary,
	affected: Array[Dictionary],
	context: Dictionary,
	rng: RefCounted
) -> void:
	var partner_skill_id := str(dual_context.get("partner_skill_id", ""))
	var partner_rank := SkillRankResolverScript.safe_effective_rank(
		int(dual_context.get("partner_rank", clicked_rank))
	)
	var mac_skill_id := "taoist.magic_defense"
	var ac_skill_id := "taoist.defense"
	var mac_rank := clicked_rank if clicked_skill_id == mac_skill_id else partner_rank
	var ac_rank := clicked_rank if clicked_skill_id == ac_skill_id else partner_rank
	## Each effect grows and prices with its own skill's effective rank:
	## MAC duration uses magic_defense's rank, AC duration uses defense's rank.
	## The cast/animation/resource transaction stays shared.
	var mac_duration := _defence_duration(mac_rank, context, rng)
	var ac_duration := _defence_duration(ac_rank, context, rng)
	plan.effects = [
		_dual_defence_effect(
			"MAC",
			mac_skill_id,
			mac_rank,
			"buff.taoist.soul_shield_mac",
			mac_duration,
			affected,
			ac_skill_id
		),
		_dual_defence_effect(
			"AC",
			ac_skill_id,
			ac_rank,
			"buff.taoist.blessed_armour_ac",
			ac_duration,
			affected,
			mac_skill_id
		),
	]
	plan["combined_skill_ids"] = DUAL_DEFENSE_SKILL_IDS.duplicate()
	plan["combined_cast_contract_id"] = DUAL_DEFENSE_CAST_CONTRACT_ID


static func _dual_defence_effect(
	stat: String,
	skill_id: String,
	skill_rank: int,
	buff_id: String,
	duration_seconds: int,
	affected: Array[Dictionary],
	coexisting_skill_id: String
) -> Dictionary:
	var targets: Array[Dictionary] = []
	var target_instance_ids: Array[int] = []
	var first_value := 0
	for target: Dictionary in affected:
		var value := _defence_value(int(target.get("level", 1)))
		if targets.is_empty():
			first_value = value
		targets.append({
			"target_instance_id": int(target.get("instance_id", 0)),
			"target_is_self": bool(target.get("is_self", false)),
			"level": int(target.get("level", 1)),
			"value": value,
			"flat_bonus": value,
			"duration_seconds": duration_seconds,
		})
		target_instance_ids.append(int(target.get("instance_id", 0)))
	return {
		"type": "friendly_defence_buff",
		"stat": stat,
		"skill_id": skill_id,
		"rank": skill_rank,
		"buff_id": buff_id,
		"duration_seconds": duration_seconds,
		"value": first_value,
		"flat_bonus": first_value,
		"stacking_policy": "refresh_same_buff; coexists_with_%s" % [
			coexisting_skill_id
		],
		"targets": targets,
		"target_instance_ids": target_instance_ids,
		"affected_count": targets.size(),
		"combined_defense": true,
		"combined_cast_contract_id": DUAL_DEFENSE_CAST_CONTRACT_ID,
	}


static func _defence_value(target_level: int) -> int:
	return maxi(1, int(floor(float(maxi(1, target_level)) / 7.0)))


static func _defence_duration(
	rank: int,
	context: Dictionary,
	rng: RefCounted
) -> int:
	var sc_roll := int(context.get("primary_stat_roll", 0))
	return maxi(
		1,
		int(floor(float(Formula.get_power13(rng, rank, 60) + 10 * sc_roll) / 10.0))
	)


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
	var trapped_ids := {}
	## Production path: the current valid locked monster is the sole occupant of
	## the open center. context.targets belongs to the eight-cell boundary query
	## and therefore cannot be promoted to trapped occupants.
	var locked_target_id := int(context.get("target_instance_id", 0))
	if locked_target_id > 0:
		var locked_eligible := (
			bool(context.get("target_is_monster", false))
			and not bool(context.get("target_is_boss", false))
			and not bool(
				context.get(
					"target_control_immune",
					bool(context.get("control_immune", false))
				)
			)
			and bool(
				context.get(
					"target_within_level_gate",
					bool(context.get("within_level_gate", true))
				)
			)
		)
		if locked_eligible:
			trapped_count = 1
			trapped_target_instance_ids.append(locked_target_id)
			trapped_ids[locked_target_id] = true
	## Production context.targets is selected by intersection with the eight
	## boundary cells. Those actors are attackers outside the open center, not
	## trap occupants. Only the locked actor defines the center occupant until a
	## future producer supplies a separately proven open-center footprint list.
	## Preserve the old pure-runtime candidate path only when there is no
	## production identity/context at all.
	if (
		locked_target_id <= 0
		and str(context.get("input_mode", "")) != "production_canonical"
	):
		for target_value: Variant in candidates:
			if not target_value is Dictionary:
				continue
			var target: Dictionary = target_value
			if not (
				bool(target.get("hostile_monster", false))
				and not bool(target.get("is_boss", false))
				and not bool(target.get("control_immune", false))
				and bool(target.get("within_level_gate", true))
			):
				continue
			var target_instance_id := int(
				target.get("target_instance_id", target.get("instance_id", 0))
			)
			if target_instance_id > 0:
				if trapped_ids.has(target_instance_id):
					continue
				trapped_ids[target_instance_id] = true
				trapped_target_instance_ids.append(target_instance_id)
			trapped_count += 1
	var duration_seconds := maxi(
		1,
		Formula.get_power13(rng, rank, 40) + 3 * int(context.get("primary_stat_roll", 0))
	)
	var boundary_snapshot: Dictionary = context.get(
		"skill_footprint_snapshot", {}
	)
	var geometry_cells: Array = context.get("geometry_cells", [])
	if (
		str(context.get("input_mode", "")) == "production_canonical"
		and (
			boundary_snapshot.is_empty()
			or geometry_cells.size() != 8
		)
	):
		_reject(plan, "entrapment_strict_boundary_required")
		return
	plan.effects = [{
		"type": "monster_boundary_control",
		"controller_contract_id": ENTRAPMENT_CONTROLLER_CONTRACT_ID,
		"trapped_count": trapped_count,
		"target_instance_ids": trapped_target_instance_ids,
		"duration_seconds": duration_seconds,
		"caster_instance_id": int(context.get("caster_runtime_id", 0)),
		"runtime_map_id": int(context.get("runtime_map_id", -1)),
		"boundary_snapshot": boundary_snapshot.duplicate(true),
		"boundary_cell_count": geometry_cells.size(),
		"boundary_ring_candidate_count": candidates.size(),
		"boundary_ring_candidates_are_not_trap_targets": true,
		"required_snapshot_validation_policy": "strict_v2",
		"footprint": "canonical_3x3_boundary",
		"prevents_boundary_exit": true,
		"break_on_any_player_entry": true,
		"break_on_damage": false,
		"break_on_map_transition": true,
		"external_attack_behavior": "summon_actor_rejected_other_sources_allowed",
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
	var rank := SkillRankResolverScript.safe_effective_rank(
		int(request.get("rank", 0))
	)
	var skill_id := str(definition.get("skill_id", ""))
	var candidates := _support_candidates(context)
	var raw_heal := _raw_heal(definition, request, rng)
	if not candidates.is_empty():
		var selection := _heal_selection(context, candidates)
		if not bool(selection.get("valid", false)):
			_reject(
				plan,
				str(selection.get("reason", "friendly_heal_target_required"))
			)
			return
		var selected: Dictionary = selection.get("selected", {})
		var center_ground_gu: Vector2 = selected.get(
			"ground_position_gu",
			Vector2.ZERO
		)
		var center_tile := TaoistFriendlyTargetingScript.grid_tile(
			center_ground_gu
		)
		var cells := TaoistFriendlyTargetingScript.exact_square_cells(
			center_tile,
			MASS_INVISIBILITY_GRID_SIZE
		)
		var affected := TaoistFriendlyTargetingScript.candidates_in_cells(
			candidates,
			center_ground_gu,
			cells
		)
		var actual_by_target: Array[int] = []
		var target_results: Array[Dictionary] = []
		var target_instance_ids: Array[int] = []
		var total_restored := 0
		for target: Dictionary in affected:
			var missing := int(target.get("max_hp", 1)) - int(
				target.get("current_hp", 0)
			)
			var actual := mini(raw_heal, maxi(0, missing))
			actual_by_target.append(actual)
			var target_id := int(target.get("instance_id", 0))
			target_instance_ids.append(target_id)
			target_results.append({
				"target_instance_id": target_id,
				"target_is_self": bool(target.get("is_self", false)),
				"actual_hp_restored": actual,
			})
			total_restored += actual
		plan.effects = [{
			"type": "dedicated_area_heal",
			"skill_id": skill_id,
			"rank": rank,
			"raw_heal_per_target": raw_heal,
			"actual_hp_restored_by_target": actual_by_target,
			"target_instance_ids": target_instance_ids,
			"target_results": target_results,
			"total_actual_hp_restored": total_restored,
			"affected_count": affected.size(),
			"width_grid_steps": MASS_INVISIBILITY_GRID_SIZE,
			"height_grid_steps": MASS_INVISIBILITY_GRID_SIZE,
			"center_ground_gu": center_ground_gu,
			"center_tile": center_tile,
			"selected_target_instance_id": int(
				selected.get("instance_id", 0)
			),
			"selected_target_is_self": bool(selected.get("is_self", false)),
			"selection_contract_id": SUPPORT_TARGETING_CONTRACT_ID,
			"negative_damage": false,
		}]
		plan["support_targeting"] = selection
		plan["support_area_geometry"] = _area_geometry(
			"square",
			center_tile,
			center_ground_gu,
			cells,
			affected,
			{
				"width_grid_steps": MASS_INVISIBILITY_GRID_SIZE,
				"height_grid_steps": MASS_INVISIBILITY_GRID_SIZE,
			}
		)
		if total_restored == 0 and not target_instance_ids.is_empty():
			plan.effects[0]["ongoing_heal_targets"] = _ongoing_heal_targets(
				skill_id,
				affected,
				raw_heal
			)
		plan.effect_success = not affected.is_empty()
		plan.resource_commit = not affected.is_empty()
		return
	var target_missing_hp: Array = context.get("friendly_missing_hp", [])
	var legacy_target_instance_ids := _instance_ids(
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
				int(legacy_target_instance_ids[target_index])
				if target_index < legacy_target_instance_ids.size()
				else 0
			),
			"actual_hp_restored": actual,
		})
		total_restored += actual
	plan.effects = [{
		"type": "dedicated_area_heal",
		"raw_heal_per_target": raw_heal,
		"actual_hp_restored_by_target": actual_by_target,
		"target_instance_ids": legacy_target_instance_ids,
		"target_results": target_results,
		"total_actual_hp_restored": total_restored,
		"width_grid_steps": 3,
		"height_grid_steps": 3,
		"negative_damage": false,
	}]
	if total_restored == 0 and not legacy_target_instance_ids.is_empty():
		plan.effects[0]["ongoing_heal_targets"] = []
		for target_instance_id: int in legacy_target_instance_ids:
			plan.effects[0]["ongoing_heal_targets"].append(
				_ongoing_heal_descriptor(
					skill_id,
					target_instance_id,
					raw_heal
				)
			)
	plan.effect_success = not legacy_target_instance_ids.is_empty()
	plan.resource_commit = not legacy_target_instance_ids.is_empty()


static func _ongoing_heal_descriptor(
	skill_id: String,
	target_instance_id: int,
	raw_heal: int
) -> Dictionary:
	return {
		"contract_id": ONGOING_HEAL_CONTRACT_ID,
		"source_skill_id": skill_id,
		"target_instance_id": target_instance_id,
		"heal_per_tick": maxi(
			1,
			int(ceil(float(raw_heal) / float(ONGOING_HEAL_TICK_COUNT)))
		),
		"tick_count": ONGOING_HEAL_TICK_COUNT,
		"tick_interval_seconds": ONGOING_HEAL_TICK_INTERVAL_SECONDS,
	}


static func _ongoing_heal_targets(
	skill_id: String,
	affected: Array[Dictionary],
	raw_heal: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for target: Dictionary in affected:
		result.append(_ongoing_heal_descriptor(
			skill_id,
			int(target.get("instance_id", 0)),
			raw_heal
		))
	return result


static func _support_candidates(context: Dictionary) -> Array[Dictionary]:
	return TaoistSupportPolicyScript.normalize_candidates(
		context.get("friendly_candidates", [])
	)


static func _heal_selection(
	context: Dictionary,
	candidates: Array[Dictionary]
) -> Dictionary:
	var center: Variant = context.get(
		"caster_ground_position_gu",
		Vector2.ZERO
	)
	if not center is Vector2:
		return {
			"valid": false,
			"contract_id": SUPPORT_TARGETING_CONTRACT_ID,
			"reason": TaoistSupportPolicyScript.REASON_NO_FRIENDLY_CANDIDATES,
			"center_ground_gu": Vector2.ZERO,
			"range_gu": HEAL_SELECTION_RANGE_GU,
			"candidate_count": candidates.size(),
		}
	return TaoistSupportPolicyScript.select_heal_target(
		candidates,
		center,
		HEAL_SELECTION_RANGE_GU
	)


static func _area_geometry(
	shape: String,
	center_tile: Vector2i,
	center_ground_gu: Vector2,
	cells: Array,
	affected: Array[Dictionary],
	shape_fields: Dictionary
) -> Dictionary:
	var result := {
		"contract_id": FRIENDLY_AREA_GEOMETRY_CONTRACT_ID,
		"support_targeting_contract_id": SUPPORT_TARGETING_CONTRACT_ID,
		"shape": shape,
		"center_tile": center_tile,
		"center_ground_gu": center_ground_gu,
		"cell_count": cells.size(),
		"affected_count": affected.size(),
		"affected_instance_ids": _instance_ids_from_candidates(affected),
	}
	for key: Variant in shape_fields:
		result[key] = shape_fields[key]
	return result


static func _instance_ids_from_candidates(candidates: Array) -> Array[int]:
	var result: Array[int] = []
	for raw_candidate: Variant in candidates:
		if not raw_candidate is Dictionary:
			continue
		var candidate: Dictionary = raw_candidate
		var instance_id := int(candidate.get("instance_id", 0))
		if instance_id > 0:
			result.append(instance_id)
	return result


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
		"resource_commit_required": true,
	}


static func _reject(plan: Dictionary, reason: String) -> Dictionary:
	plan.accepted = false
	plan.effect_success = false
	plan.reason = reason
	plan.resource_commit = false
	plan.resource_commit_required = false
	return plan
