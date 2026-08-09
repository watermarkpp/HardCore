class_name SkillExecutionPlanContract
extends RefCounted

## Q3-B: the pure canonical-plan contract module. No dependency on
## SkillRuntimeRouter (the router consumes this module), so the formal chain
## GameRoot -> SkillRuntimeRouter.build_canonical_plan -> contract has exactly
## one planner entry. Also owns the formal sentinel counters.

const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const CasterSpellGeometryScript := preload(
	"res://scripts/skills/caster_spell_geometry.gd"
)
const GroundUnitSpaceScript := preload(
	"res://scripts/ground_unit_space.gd"
)
const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)
const SkillRankResolverScript := preload(
	"res://scripts/skills/skill_rank_resolver.gd"
)
const WorldSpatialRulesScript := preload(
	"res://scripts/world_spatial_rules.gd"
)

const CONTRACT_ID := "skill_execution_plan.v1"
const RESULT_CONTRACT_ID := "skill_execution_result.v1"
const PLAN_VERSION := 1
const CANONICAL_PLANNER_ID := "canonical_planner.v1"
const LEGACY_PLANNER_ID := "skill_runtime_router.v1"

const NON_SPATIAL_SKILLS := {
	"taoist.defense": "pure_defense_buff",
	"taoist.magic_defense": "pure_magic_defense_buff",
	"taoist.invisibility": "self_state_switch",
	"taoist.mass_invisibility": "party_state_switch",
	"taoist.revelation": "self_detect_state",
	"wizard.magic_shield": "self_state_switch",
	"warrior.basic_swordsmanship": "warrior_passive_modifier",
	"warrior.slaying_swordsmanship": "warrior_passive_modifier",
}

const REASON_ACCEPTED := "accepted"
const REASON_UNKNOWN_SKILL := "unknown_skill"
const REASON_INVALID_REQUEST := "invalid_request"
const REASON_INVALID_TARGET := "invalid_target"
const REASON_INSUFFICIENT_RESOURCE := "insufficient_resource"
const REASON_COOLDOWN := "cooldown"
const REASON_INVALID_SNAPSHOT := "invalid_snapshot"
const REASON_MAP_MISMATCH := "map_mismatch"
const REASON_RUNTIME_REJECTED := "runtime_rejected"
const REASON_RESOURCE_COMMIT_FAILED := "resource_commit_failed"

const REASON_ALIASES := {
	"target_required": REASON_INVALID_TARGET,
	"line_of_sight": REASON_INVALID_TARGET,
	"hostile_target_required": REASON_INVALID_TARGET,
	"friendly_target_required": REASON_INVALID_TARGET,
	"invalid_target": REASON_INVALID_TARGET,
	"insufficient_resource": REASON_INSUFFICIENT_RESOURCE,
	"insufficient_mana": REASON_INSUFFICIENT_RESOURCE,
	"insufficient_material": REASON_INSUFFICIENT_RESOURCE,
	"unknown_skill": REASON_UNKNOWN_SKILL,
	"unknown_profession": REASON_RUNTIME_REJECTED,
	"runtime_rejected": REASON_RUNTIME_REJECTED,
	"invalid_request": REASON_INVALID_REQUEST,
	"request_not_dictionary": REASON_INVALID_REQUEST,
	"request_contract": REASON_INVALID_REQUEST,
	"rank": REASON_INVALID_REQUEST,
	"resource_commit_failed": REASON_RESOURCE_COMMIT_FAILED,
	"invalid_snapshot": REASON_INVALID_SNAPSHOT,
	"map_mismatch": REASON_MAP_MISMATCH,
	"cooldown": REASON_COOLDOWN,
}

const GROUND_EXACT_SKILL_IDS := {
	"wizard.repulsion_ring": true,
	"wizard.exploding_flame": true,
	"wizard.fire_wall": true,
	"wizard.hell_lightning": true,
	"wizard.ice_storm": true,
	"taoist.mass_invisibility": true,
	"taoist.magic_defense": true,
	"taoist.defense": true,
	"taoist.entrapment": true,
	"taoist.mass_healing": true,
}

const TARGET_FOOTPRINT_SKILL_IDS := {
	"wizard.lightning": true,
	"wizard.temptation_light": true,
	"wizard.holy_word": true,
	"taoist.healing": true,
	"taoist.poison": true,
	"taoist.revelation": true,
}

const ATTACHED_STATE_SKILL_IDS := {
	"wizard.magic_shield": true,
	"taoist.invisibility": true,
}

const SUMMON_SKILL_IDS := {
	"taoist.summon_skeleton": true,
	"taoist.summon_divine_beast": true,
}

const ACTIONS := ["idle", "walk", "attack", "hit", "death"]

## Q3-B formal sentinels (read-only; default no per-event logging).
static var canonical_plan_build_count := 0
static var release_id_generation_count := 0
static var snapshot_build_count := 0
static var resource_commit_count := 0
static var cooldown_commit_count := 0
## FREEZE-P0.1: fail-closed projection rejection diagnostics.
static var missing_projection_rejection_count := 0


static func build_canonical_plan(
	legacy_result: Dictionary,
	request: Dictionary,
	context: Dictionary = {}
) -> Dictionary:
	## Pure envelope: wraps an already-computed legacy router plan into the
	## canonical contract, builds the single release snapshot when needed and
	## attaches the presentation geometry. Never performs side effects.
	canonical_plan_build_count += 1
	var skill_id := SkillDataLoaderScript.stable_skill_id(
		str(request.get("skill_id", ""))
	)
	var definition := SkillDataLoaderScript.skill(skill_id)
	var accepted := bool(legacy_result.get("accepted", false))
	var reason := normalize_reason(str(legacy_result.get("reason", "")))
	var release_id := str(
		context.get(
			"release_id",
			request.get("target_context", {}).get("release_id", "")
		)
	)
	if release_id.is_empty():
		release_id = _derive_release_id(skill_id, request)
	var snapshot: Dictionary = context.get(
		"canonical_snapshot",
		request.get("target_context", {}).get(
			"skill_footprint_snapshot", {}
		)
	)
	if not snapshot is Dictionary:
		snapshot = {}
	var non_spatial_reason := str(NON_SPATIAL_SKILLS.get(skill_id, ""))
	var snapshot_required := non_spatial_reason.is_empty()
	var effects: Array = legacy_result.get("effects", [])
	var primary_effect := _primary_effect(effects)
	var line_strip: Dictionary = {}
	var strip_builder: Callable = context.get("line_strip_builder", Callable())
	if strip_builder.is_valid():
		var built_strip: Variant = strip_builder.call(primary_effect, release_id)
		if built_strip is Dictionary:
			line_strip = built_strip
	var effective_cells: Array[Vector2i] = []
	var cells_builder: Callable = context.get(
		"effective_cells_builder", Callable()
	)
	if cells_builder.is_valid():
		var built_cells: Variant = cells_builder.call(
			legacy_result.get("geometry_cells", []),
			primary_effect
		)
		if built_cells is Array:
			for raw_cell: Variant in built_cells:
				if raw_cell is Vector2i:
					effective_cells.append(raw_cell)
	else:
		for raw_cell: Variant in legacy_result.get("geometry_cells", []):
			if raw_cell is Vector2i:
				effective_cells.append(raw_cell)
	if accepted and snapshot_required:
		var runtime_map_id := int(context.get("runtime_map_id", -1))
		var screen_to_ground: Callable = context.get(
			"screen_to_ground_position_px", Callable()
		)
		if runtime_map_id >= 0 and not screen_to_ground.is_valid():
			# FREEZE-P0.1: a mapped spatial plan must never project screen
			# positions through a missing/raw-delta conversion. Reject before
			# any resource/cooldown commit or node creation.
			missing_projection_rejection_count += 1
			accepted = false
			reason = str(
				GroundUnitSpaceScript.REASON_MISSING_RUNTIME_PROJECTION
			)
			snapshot = {}
		var validation_context: Dictionary = (
			context.get("snapshot_validation_context", {})
			if context.get("snapshot_validation_context", {}) is Dictionary
			else {}
		)
		if accepted and snapshot.is_empty():
			snapshot = build_release_snapshot(
				skill_id,
				release_id,
				legacy_result,
				context,
				line_strip,
				effective_cells
			)
		if accepted:
			var snapshot_valid := false
			if not snapshot.is_empty():
				snapshot_valid = _snapshot_valid_for_context(
					snapshot,
					validation_context
				)
			if not snapshot_valid:
				accepted = false
				reason = REASON_INVALID_SNAPSHOT
	if (
		not snapshot.is_empty()
		and str(snapshot.get("shape_type", ""))
			== SkillFootprintSnapshotScript.SHAPE_CELL_UNION
	):
		effective_cells.clear()
		for raw_cell: Variant in snapshot.get(
			"geometry_cells_grid_steps", []
		):
			if raw_cell is Vector2i:
				effective_cells.append(raw_cell)
	# Runtime planners may explicitly suppress resource consumption for an
	# accepted no-op/recall.  Older planners expose `resource_commit`; accepted
	# plans without either field retain the historical commit-by-default rule.
	var resource_commit_required := (
		accepted
		and bool(
			legacy_result.get(
				"resource_commit_required",
				legacy_result.get("resource_commit", true)
			)
		)
	)
	var plan := {
		"contract": CONTRACT_ID,
		"plan_version": PLAN_VERSION,
		"plan_id": _plan_id(skill_id, release_id, definition),
		"release_id": release_id,
		"skill_id": skill_id,
		"skill_definition_revision": _definition_revision(definition),
		"caster_runtime_id": int(context.get("caster_runtime_id", 0)),
		"target_runtime_id": int(context.get("target_runtime_id", 0)),
		"runtime_map_id": int(context.get("runtime_map_id", -1)),
		"input_mode": str(context.get("input_mode", "canonical")),
		"effective_rank": SkillRankResolverScript.safe_effective_rank(
			int(request.get("rank", 0))
		),
		"requested_direction": request.get("facing", Vector2i.DOWN),
		"resolved_direction": _resolved_direction(request, legacy_result),
		"lock_on_context": (
			context.get("lock_on_context", {})
			if context.get("lock_on_context", {}) is Dictionary
			else {}
		),
		"resource_cost": (
			legacy_result.get("resource_quote", {}).duplicate(true)
			if legacy_result.get("resource_quote", {}) is Dictionary
			else {}
		),
		"resource_commit_required": resource_commit_required,
		"cooldown_contract": definition.get("timing", {}).duplicate(true),
		"canonical_snapshot": snapshot,
		"snapshot_id": str(snapshot.get("snapshot_id", "")),
		"snapshot_required": snapshot_required,
		"non_spatial_reason": non_spatial_reason,
		"geometry_cells": _duplicate_array(
			legacy_result.get("geometry_cells", [])
		),
		"effective_geometry_cells": effective_cells.duplicate(),
		"continuous_line_strip_ground_gu": line_strip,
		"gameplay_actions": _duplicate_array(effects),
		"proficiency_event": str(
			legacy_result.get("proficiency_event", "")
		),
		"presentation_actions": _presentation_actions(
			skill_id,
			definition,
			context,
			line_strip
		),
		"projectile_descriptors": _descriptors_of_kind(effects, "projectile"),
		"ground_effect_descriptors": _descriptors_of_kind(effects, "ground"),
		"summon_descriptors": _descriptors_of_kind(
			effects,
			"summon",
			snapshot
		),
		"rejection": {
			"accepted": accepted,
			"reason": reason if not accepted else REASON_ACCEPTED,
		},
		"created_by": CANONICAL_PLANNER_ID,
		"legacy_planner": LEGACY_PLANNER_ID,
	}
	## Combined-cast metadata (e.g. Taoist dual defence) is forwarded from the
	## legacy planner untouched. It is optional: single-skill plans keep the
	## exact previous field set and hash semantics.
	var combined_skill_ids := _duplicate_array(
		legacy_result.get("combined_skill_ids", [])
	)
	if not combined_skill_ids.is_empty():
		plan["combined_skill_ids"] = combined_skill_ids
	var combined_cast_contract_id := str(
		legacy_result.get("combined_cast_contract_id", "")
	)
	if not combined_cast_contract_id.is_empty():
		plan["combined_cast_contract_id"] = combined_cast_contract_id
	## Taoist support metadata (selection result and friendly-area geometry)
	## is forwarded only when the legacy planner produced it. Single-skill
	## plans keep the exact previous field set and hash semantics.
	var support_targeting: Variant = legacy_result.get("support_targeting", {})
	if (
		support_targeting is Dictionary
		and not (support_targeting as Dictionary).is_empty()
	):
		plan["support_targeting"] = (support_targeting as Dictionary).duplicate(true)
	var support_area_geometry: Variant = legacy_result.get(
		"support_area_geometry",
		{}
	)
	if (
		support_area_geometry is Dictionary
		and not (support_area_geometry as Dictionary).is_empty()
	):
		plan["support_area_geometry"] = (
			support_area_geometry as Dictionary
		).duplicate(true)
	plan["plan_hash"] = plan_hash(plan)
	return plan


static func build_result(
	plan: Dictionary,
	overrides: Dictionary = {}
) -> Dictionary:
	var rejection: Dictionary = plan.get("rejection", {})
	var accepted := bool(
		overrides.get("accepted", rejection.get("accepted", false))
	)
	var result := {
		"contract": RESULT_CONTRACT_ID,
		"plan_id": str(plan.get("plan_id", "")),
		"release_id": str(plan.get("release_id", "")),
		"accepted": accepted,
		"rejection_reason": str(
			overrides.get("rejection_reason", rejection.get("reason", ""))
		),
		"resource_committed": bool(overrides.get("resource_committed", false)),
		"cooldown_committed": bool(overrides.get("cooldown_committed", false)),
		"damage_results": _duplicate_array(overrides.get("damage_results", [])),
		"status_results": _duplicate_array(overrides.get("status_results", [])),
		"spawned_projectile_ids": _duplicate_array(
			overrides.get("spawned_projectile_ids", [])
		),
		"spawned_ground_effect_ids": _duplicate_array(
			overrides.get("spawned_ground_effect_ids", [])
		),
		"spawned_summon_ids": _duplicate_array(
			overrides.get("spawned_summon_ids", [])
		),
		"created_visual_ids": _duplicate_array(
			overrides.get("created_visual_ids", [])
		),
		"snapshot_id": str(plan.get("snapshot_id", "")),
		"side_effect_count": int(overrides.get("side_effect_count", 0)),
	}
	if not accepted:
		result["resource_committed"] = false
		result["cooldown_committed"] = false
	return result


static func build_release_snapshot(
	skill_id: String,
	release_id: String,
	legacy_result: Dictionary,
	context: Dictionary,
	continuous_line_strip: Dictionary = {},
	effective_cells: Array[Vector2i] = []
) -> Dictionary:
	## Single release-level Snapshot V2 builder (mirrors the frozen production
	## rules). Consumes only the plan's cells/effects + context projections.
	snapshot_build_count += 1
	var raw_line_snapshot: Variant = continuous_line_strip.get(
		"skill_footprint_snapshot", {}
	)
	if raw_line_snapshot is Dictionary:
		var line_ok := _snapshot_valid_for_context(
			raw_line_snapshot,
			context.get("snapshot_validation_context", {})
		)
		if line_ok:
			return raw_line_snapshot
	var screen_to_ground: Callable = context.get(
		"screen_to_ground_position_px", Callable()
	)
	var ground_to_screen: Callable = context.get(
		"ground_gu_to_screen_position_px", Callable()
	)
	var map_id := int(context.get("runtime_map_id", -1))
	if GROUND_EXACT_SKILL_IDS.has(skill_id) and not effective_cells.is_empty():
		var origin_screen_px: Vector2 = context.get(
			"origin_screen_px", Vector2.ZERO
		)
		var origin_ground_gu := _project(screen_to_ground, origin_screen_px, map_id)
		var absolute_context := SkillFootprintSnapshotScript.make_absolute_runtime_context(
			map_id,
			origin_ground_gu,
			origin_ground_gu,
			ground_to_screen
		)
		return CasterSpellGeometryScript.create_exact_cell_union_release_snapshot(
			skill_id,
			release_id,
			origin_ground_gu,
			effective_cells,
			absolute_context
		)
	var target: EnemyActor = context.get("target")
	if TARGET_FOOTPRINT_SKILL_IDS.has(skill_id):
		var target_actor: Node2D = (
			target
			if target != null and is_instance_valid(target)
			else null
		)
		if target_actor == null and context.get("fallback_target_actor") != null:
			target_actor = context.get("fallback_target_actor")
		if target_actor == null:
			return {}
		var target_ground_gu := _project(screen_to_ground, target_actor.global_position
		, map_id)
		var target_context := SkillFootprintSnapshotScript.make_absolute_runtime_context(
			map_id,
			target_ground_gu,
			target_ground_gu,
			ground_to_screen
		)
		return SkillFootprintSnapshotScript.create_target_footprint(
			skill_id,
			release_id,
			target_ground_gu,
			float(context.get("target_combat_radius_gu", 0.0)),
			target_actor.get_instance_id(),
			target_context
		)
	if ATTACHED_STATE_SKILL_IDS.has(skill_id):
		var player_actor: Node2D = context.get("player_actor")
		if player_actor == null or not is_instance_valid(player_actor):
			return {}
		var player_ground_gu := _project(screen_to_ground, player_actor.global_position
		, map_id)
		var player_context := SkillFootprintSnapshotScript.make_absolute_runtime_context(
			map_id,
			player_ground_gu,
			player_ground_gu,
			ground_to_screen
		)
		return SkillFootprintSnapshotScript.create_target_footprint(
			skill_id,
			release_id,
			player_ground_gu,
			float(context.get("player_combat_radius_gu", 0.0)),
			player_actor.get_instance_id(),
			player_context
		)
	if SUMMON_SKILL_IDS.has(skill_id):
		# Q3-B: the formal summon release owns one release snapshot matching
		# SummonActor.configure_spawn_release_footprint (target footprint at the
		# frozen spawn position with the summon's combat radius).
		var spawn_screen_px: Vector2 = context.get(
			"summon_spawn_position_screen_px",
			Vector2.ZERO
		)
		if spawn_screen_px == Vector2.ZERO:
			var summon_player: Node2D = context.get("player_actor")
			if summon_player != null and is_instance_valid(summon_player):
				spawn_screen_px = summon_player.global_position
			else:
				return {}
		var spawn_center_ground_gu := _project(screen_to_ground, spawn_screen_px
		, map_id)
		var summon_template_id := ""
		for raw_descriptor: Variant in _descriptors_of_kind(
			legacy_result.get("effects", []),
			"summon"
		):
			if not raw_descriptor is Dictionary:
				continue
			var descriptor: Dictionary = raw_descriptor
			summon_template_id = str(
				descriptor.get("template_id", "")
			)
			break
		var summon_radius_gu := (
			WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
				21.0 if summon_template_id == "divine_beast" else 15.0
			)
		)
		var summon_context := (
			SkillFootprintSnapshotScript.make_absolute_runtime_context(
				map_id,
				spawn_center_ground_gu,
				spawn_center_ground_gu,
				ground_to_screen
			)
		)
		return SkillFootprintSnapshotScript.create_target_footprint(
			skill_id,
			release_id,
			spawn_center_ground_gu,
			summon_radius_gu,
			int(context.get("caster_runtime_id", 0)),
			summon_context
		)
	var effects: Array = legacy_result.get("effects", [])
	for raw_effect: Variant in effects:
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		var effect_type := str(effect.get("type", ""))
		var radius_gu := maxf(0.0, float(effect.get("radius_gu", 0.0)))
		if (
			effect_type in ["area_damage", "caster_centered_area_damage"]
			and radius_gu > 0.0
		):
			var center_screen_px: Vector2 = (
				context.get("target_position_screen_px", Vector2.ZERO)
				if effect_type == "area_damage"
				else context.get("origin_screen_px", Vector2.ZERO)
			)
			var center_ground_gu := _project(screen_to_ground, center_screen_px, map_id)
			var circle_context := SkillFootprintSnapshotScript.make_absolute_runtime_context(
				map_id,
				center_ground_gu,
				center_ground_gu,
				ground_to_screen
			)
			return SkillFootprintSnapshotScript.create_circle(
				skill_id,
				release_id,
				center_ground_gu,
				radius_gu,
				SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS,
				circle_context
			)
	for raw_effect: Variant in effects:
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		var effect_type := str(effect.get("type", ""))
		if effect_type not in [
			"projectile_damage",
			"talisman_projectile_damage",
		]:
			continue
		# Q3-B: projectile releases own the swept-capsule footprint exactly as
		# SkillProjectile._build_release_footprint_snapshot does, so the single
		# release snapshot exists in the plan before the node factory runs.
		var origin_screen_px: Vector2 = context.get(
			"origin_screen_px", Vector2.ZERO
		)
		# FREEZE-P0: a projectile release ORIGIN is a POSITION on the runtime
		# map, so it must cross the map-aware screen->ground projection (design
		# center included). Raw screen-delta inversion is reserved for the
		# direction vector below.
		var origin_ground_gu := _project(screen_to_ground, origin_screen_px, map_id)
		var direction_screen_px: Vector2 = context.get(
			"direction_screen_px", Vector2.ZERO
		)
		var direction_ground_gu := (
			GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
				direction_screen_px
			).normalized()
		)
		if (
			direction_ground_gu.length_squared()
			<= GroundUnitSpaceScript.EPSILON_GU
				* GroundUnitSpaceScript.EPSILON_GU
		):
			direction_ground_gu = Vector2(1.0, -1.0).normalized()
		var projectile_geometry: Dictionary = (
			SkillDataLoaderScript.skill(skill_id).get("geometry", {})
		)
		var maximum_distance_gu := maxf(
			0.0,
			float(projectile_geometry.get("maximum_range_gu", 0.0))
		)
		if maximum_distance_gu <= 0.0:
			return {}
		var projectile_context := (
			SkillFootprintSnapshotScript.make_absolute_runtime_context(
				map_id,
				origin_ground_gu,
				origin_ground_gu,
				ground_to_screen
			)
		)
		return SkillFootprintSnapshotScript.create_swept_capsule_path(
			skill_id,
			release_id,
			origin_ground_gu,
			origin_ground_gu
				+ direction_ground_gu * maximum_distance_gu,
			CombatUnitLegacyAdapterScript.PROJECTILE_RADIUS_GU,
			SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS / 2,
			"",
			-1,
			projectile_context
		)
	return {}


static func plan_hash(plan: Dictionary) -> String:
	var protected := {
		"plan_id": plan.get("plan_id", ""),
		"release_id": plan.get("release_id", ""),
		"skill_id": plan.get("skill_id", ""),
		"skill_definition_revision": plan.get(
			"skill_definition_revision", ""
		),
		"caster_runtime_id": plan.get("caster_runtime_id", 0),
		"target_runtime_id": plan.get("target_runtime_id", 0),
		"runtime_map_id": plan.get("runtime_map_id", -1),
		"requested_direction": plan.get("requested_direction", Vector2i.ZERO),
		"resolved_direction": plan.get("resolved_direction", Vector2i.ZERO),
		"effective_rank": plan.get("effective_rank", 0),
		"resource_cost": plan.get("resource_cost", {}),
		"resource_commit_required": plan.get(
			"resource_commit_required",
			bool(plan.get("rejection", {}).get("accepted", false))
		),
		"cooldown_contract": plan.get("cooldown_contract", {}),
		"canonical_snapshot": plan.get("canonical_snapshot", {}),
		"geometry_cells": plan.get("geometry_cells", []),
		"gameplay_actions": plan.get("gameplay_actions", []),
		"proficiency_event": plan.get("proficiency_event", ""),
		"presentation_actions": plan.get("presentation_actions", []),
		"projectile_descriptors": plan.get("projectile_descriptors", []),
		"ground_effect_descriptors": plan.get(
			"ground_effect_descriptors", []
		),
		"summon_descriptors": plan.get("summon_descriptors", []),
		"rejection": plan.get("rejection", {}),
	}
	## Combined-cast metadata participates in the hash only when present, so
	## existing single-skill plan hashes are unchanged.
	var combined_skill_ids: Variant = plan.get("combined_skill_ids", [])
	if combined_skill_ids is Array and not (combined_skill_ids as Array).is_empty():
		protected["combined_skill_ids"] = combined_skill_ids
	var combined_cast_contract_id := str(plan.get("combined_cast_contract_id", ""))
	if not combined_cast_contract_id.is_empty():
		protected["combined_cast_contract_id"] = combined_cast_contract_id
	var support_targeting: Variant = plan.get("support_targeting", {})
	if (
		support_targeting is Dictionary
		and not (support_targeting as Dictionary).is_empty()
	):
		protected["support_targeting"] = support_targeting
	var support_area_geometry: Variant = plan.get("support_area_geometry", {})
	if (
		support_area_geometry is Dictionary
		and not (support_area_geometry as Dictionary).is_empty()
	):
		protected["support_area_geometry"] = support_area_geometry
	return "%d" % hash(_canonicalize(protected))


static func verify_immutable(
	plan: Dictionary,
	hash_before: String
) -> Dictionary:
	var hash_after := plan_hash(plan)
	return {
		"valid": hash_before == hash_after,
		"hash_before": hash_before,
		"hash_after": hash_after,
		"snapshot_hash_before": _snapshot_hash(plan),
		"snapshot_hash_after": _snapshot_hash(plan),
	}


static func skill_execution_plan_diagnostics(plan: Dictionary) -> Dictionary:
	var rejection: Dictionary = plan.get("rejection", {})
	return {
		"contract": str(plan.get("contract", "")),
		"plan_id": str(plan.get("plan_id", "")),
		"release_id": str(plan.get("release_id", "")),
		"skill_id": str(plan.get("skill_id", "")),
		"planner": str(plan.get("created_by", "")),
		"accepted": bool(rejection.get("accepted", false)),
		"rejection_reason": str(rejection.get("reason", "")),
		"target_id": int(plan.get("target_runtime_id", 0)),
		"runtime_map_id": int(plan.get("runtime_map_id", -1)),
		"snapshot_id": str(plan.get("snapshot_id", "")),
		"resource_cost": plan.get("resource_cost", {}),
		"resource_commit_required": bool(
			plan.get("resource_commit_required", false)
		),
		"cooldown": plan.get("cooldown_contract", {}),
		"gameplay_action_count": (plan.get("gameplay_actions", []) as Array).size(),
		"presentation_action_count": (
			plan.get("presentation_actions", []) as Array
		).size(),
		"plan_hash": str(plan.get("plan_hash", "")),
	}


static func normalize_reason(reason: String) -> String:
	var trimmed := reason.strip_edges()
	if trimmed.is_empty():
		return REASON_ACCEPTED
	return str(REASON_ALIASES.get(trimmed, trimmed))


static func reset_sentinels_for_tests() -> void:
	canonical_plan_build_count = 0
	release_id_generation_count = 0
	snapshot_build_count = 0
	resource_commit_count = 0
	cooldown_commit_count = 0


static func sentinel_diagnostics() -> Dictionary:
	return {
		"canonical_plan_build_count": canonical_plan_build_count,
		"release_id_generation_count": release_id_generation_count,
		"snapshot_build_count": snapshot_build_count,
		"resource_commit_count": resource_commit_count,
		"cooldown_commit_count": cooldown_commit_count,
	}


static func _project(callable: Callable, value: Vector2,
	runtime_map_id: int
) -> Vector2:
	if callable.is_valid():
		var projected: Variant = callable.call(value)
		if projected is Vector2:
			return projected
	if runtime_map_id < 0:
		return value
	missing_projection_rejection_count += 1
	return Vector2.INF


static func _snapshot_valid_for_context(
	snapshot: Dictionary,
	validation_context: Dictionary
) -> bool:
	## Q3-B: a release snapshot must validate under STRICT_V2 against the
	## frozen runtime-map context. When the caller's context has no runtime map
	## bound yet (expected_runtime_map_id < 0, e.g. the frozen home/unmapped
	## test harness), absolute-map checks are meaningless; fall back to the
	## structural base-contract check so well-formed release snapshots are not
	## rejected solely for lacking a map binding.
	var expected_map: Variant = validation_context.get(
		"expected_runtime_map_id", -1
	)
	var runtime_map_bound := (
		expected_map is int
		and int(expected_map) >= 0
	)
	if not runtime_map_bound:
		if SkillFootprintSnapshotScript.has_legacy_base_contract(snapshot):
			return true
	if validation_context.is_empty():
		return bool(
			SkillFootprintSnapshotScript.validate(
				snapshot,
				{}
			).get("valid", false)
		)
	return bool(
		SkillFootprintSnapshotScript.validate_for_consumer(
			snapshot,
			validation_context,
			SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
		).get("valid", false)
	)


static func _derive_release_id(skill_id: String, request: Dictionary) -> String:
	return "canonical:%s:%d" % [skill_id, int(request.get("seed", 0))]


static func _plan_id(
	skill_id: String,
	release_id: String,
	definition: Dictionary
) -> String:
	return "plan:%s:%s:%s" % [
		skill_id,
		release_id,
		_definition_revision(definition),
	]


static func _definition_revision(definition: Dictionary) -> String:
	return "%d" % hash(
		str(definition.get("skill_id", ""))
		+ str(definition.get("class", ""))
		+ str(definition.get("timing", {}))
	)


static func _resolved_direction(
	request: Dictionary,
	legacy_result: Dictionary
) -> Vector2i:
	var target_context: Dictionary = request.get("target_context", {})
	var resolved: Variant = target_context.get(
		"resolved_direction",
		target_context.get(
			"direction_step",
			request.get("facing", Vector2i.DOWN)
		)
	)
	if resolved is Vector2i:
		return resolved
	return request.get("facing", Vector2i.DOWN)


static func _presentation_actions(
	skill_id: String,
	definition: Dictionary,
	context: Dictionary,
	line_strip: Dictionary = {}
) -> Array:
	var actions: Array = []
	var profile := CasterSkillVisualRegistry.profile(skill_id)
	var role := str(profile.get("role", ""))
	if role.is_empty():
		return actions
	var geometry_cells: Array[Vector2i] = []
	var screen_points: Array[Vector2] = []
	var grid_to_screen: Callable = context.get(
		"grid_cell_to_screen_position_px", Callable()
	)
	if grid_to_screen.is_valid():
		for raw_cell: Variant in context.get("geometry_cells", []):
			if not raw_cell is Vector2i:
				continue
			geometry_cells.append(raw_cell)
			var point: Variant = grid_to_screen.call(raw_cell)
			if point is Vector2:
				screen_points.append(point)
	if (
		str(line_strip.get("contract_id", "")) in [
			CasterSpellGeometryScript.CONTINUOUS_AIM_LINE_CONTRACT_ID,
			"skills.wizard.line.continuous_tile_axis_footprint_sat.v1",
		]
		and context.get("ground_gu_to_screen_position_px") is Callable
	):
		var projected_points: Array = (
			CasterSpellGeometryScript.continuous_line_screen_points_px(
				line_strip,
				context.get("ground_gu_to_screen_position_px")
			)
		)
		for point: Variant in projected_points:
			if point is Vector2:
				screen_points.append(point)
	actions.append({
		"type": "visual",
		"skill_id": skill_id,
		"role": role,
		"phase": str(profile.get("status", "")),
		"visual_radius_px": float(
			definition.get("geometry", {}).get(
				"visual_radius_px", profile.get("visual_radius_px", 72.0)
			)
		),
		"visual_duration": CasterSkillVisualRegistry.animation_duration(
			skill_id
		),
		"canonical_geometry_contract": CasterSpellGeometryScript.CONTRACT_ID,
		"geometry_origin_screen_px": context.get(
			"origin_screen_px", Vector2.ZERO
		),
		"target_position_screen_px": context.get(
			"target_position_screen_px", Vector2.ZERO
		),
		"geometry_grid_cells": geometry_cells,
		"geometry_screen_points_px": screen_points,
		"ground_gu_to_screen_position_px": context.get(
			"ground_gu_to_screen_position_px", Callable()
		),
		"snapshot_validation_context": (
			context.get("snapshot_validation_context", {})
			if context.get("snapshot_validation_context", {}) is Dictionary
			else {}
		),
	})
	return actions


static func _primary_effect(effects: Array) -> Dictionary:
	for raw_effect: Variant in effects:
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		if str(effect.get("type", "")) in [
			"line_damage",
			"piercing_line_damage",
			"area_damage",
			"caster_centered_area_damage",
		]:
			return effect
	return {}


static func _descriptors_of_kind(
	effects: Array,
	kind: String,
	canonical_snapshot: Dictionary = {}
) -> Array:
	var result: Array = []
	for raw_effect: Variant in effects:
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		var effect_type := str(effect.get("type", ""))
		match kind:
			"projectile":
				if effect_type in [
					"projectile_damage",
					"talisman_projectile_damage",
				]:
					result.append({
						"kind": "projectile",
						"skill_id": str(effect.get("skill_id", "")),
						"release_id": str(effect.get("release_id", "")),
						"raw_power": int(
							effect.get(
								"raw_power_after_race",
								effect.get("raw_power", 0)
							)
						),
						"operation": "projectile_damage",
					})
			"ground":
				if effect_type == "persistent_ground_damage":
					result.append({
						"kind": "ground_effect",
						"skill_id": str(effect.get("skill_id", "")),
						"release_id": str(effect.get("release_id", "")),
						"raw_power": int(effect.get("raw_power", 0)),
						"radius_gu": float(effect.get("radius_gu", 0.5)),
						"duration_seconds": float(
							effect.get("duration_seconds", 1.0)
						),
						"tick_interval_ms": int(
							effect.get("tick_interval_ms", 1000)
						),
						"operation": "ground_dot",
					})
			"summon":
				if effect_type in [
					"main_pet_spawn",
					"recall_existing_main_pet",
					"summon",
				]:
					result.append({
						"kind": "summon",
						"skill_id": str(effect.get(
							"skill_id",
							canonical_snapshot.get("skill_id", "")
						)),
						"release_id": str(effect.get(
							"release_id",
							canonical_snapshot.get("release_id", "")
						)),
						"operation": effect_type,
						"template_id": str(
							effect.get(
								"template_id",
								effect.get("template_requested", "")
							)
						),
						"spawned": bool(effect.get(
							"spawned",
							effect_type != "recall_existing_main_pet"
						)),
						"initial_pet_level": int(
							effect.get("initial_pet_level", 0)
						),
						"max_pet_level": int(
							effect.get("max_pet_level", -1)
						),
						"skill_rank_is_pet_level": bool(
							effect.get("skill_rank_is_pet_level", false)
						),
						"spawn_snapshot_id": str(
							canonical_snapshot.get("snapshot_id", "")
						),
						"spawn_runtime_map_id": int(
							canonical_snapshot.get("runtime_map_id", -1)
						),
						"spawn_footprint_snapshot": canonical_snapshot,
					})
	return result


static func _canonicalize(value: Variant) -> String:
	if value is Dictionary:
		var parts := PackedStringArray()
		var keys: Array = (value as Dictionary).keys()
		keys.sort()
		for key: Variant in keys:
			parts.append(
				"%s=%s" % [str(key), _canonicalize((value as Dictionary).get(key))]
			)
		return "{%s}" % ",".join(parts)
	if value is Array:
		var parts_array := PackedStringArray()
		for item: Variant in value:
			parts_array.append(_canonicalize(item))
		return "[%s]" % ",".join(parts_array)
	if value is Callable:
		return "callable:%d" % (value as Callable).get_object_id()
	if value is Vector2 or value is Vector2i or value is Rect2:
		return str(value)
	return str(value)


static func _snapshot_hash(plan: Dictionary) -> String:
	var snapshot: Dictionary = plan.get("canonical_snapshot", {})
	return "%d" % hash(_canonicalize(snapshot))


static func _duplicate_array(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item: Variant in value:
			if item is Dictionary:
				result.append((item as Dictionary).duplicate(true))
			elif item is Array:
				result.append(_duplicate_array(item))
			else:
				result.append(item)
	return result
