class_name SkillExecutionPlan
extends RefCounted

## Q3-A / HC-P1-009 (contract phase): the unique canonical skill execution plan
## contract plus the side-effect-free canonical planner, plan hashing, plan
## diagnostics and the execution result contract.
##
## The canonical planner consumes the SAME frozen inputs as the legacy
## SkillRuntimeRouter planner and never performs gameplay side effects
## (no MP, no cooldown, no damage, no nodes, no world writes, no lock changes).

const SkillCastRequestScript := preload("res://scripts/skills/skill_cast_request.gd")
const SkillCastResultScript := preload("res://scripts/skills/skill_cast_result.gd")
const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const SkillRuntimeRouterScript := preload(
	"res://scripts/skills/skill_runtime_router.gd"
)
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)

const CONTRACT_ID := "skill_execution_plan.v1"
const RESULT_CONTRACT_ID := "skill_execution_result.v1"
const PLAN_VERSION := 1
const CANONICAL_PLANNER_ID := "canonical_planner.v1"
const LEGACY_PLANNER_ID := "skill_runtime_router.v1"

## Frozen non-spatial skills (pure buffs / state switches that do not require
## range geometry). Everything else is spatial and requires a Snapshot V2.
const NON_SPATIAL_SKILLS := {
	"taoist.defense": "pure_defense_buff",
	"taoist.magic_defense": "pure_magic_defense_buff",
	"taoist.invisibility": "self_state_switch",
	"taoist.mass_invisibility": "party_state_switch",
	"taoist.revelation": "self_detect_state",
	"wizard.magic_shield": "self_state_switch",
}

## Canonical rejection reason contract: legacy reasons are normalized into
## this closed set so both planners compare with the same vocabulary.
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
	"unknown_skill": REASON_UNKNOWN_SKILL,
	"unknown_profession": REASON_RUNTIME_REJECTED,
	"runtime_rejected": REASON_RUNTIME_REJECTED,
	"invalid_request": REASON_INVALID_REQUEST,
	"request_not_dictionary": REASON_INVALID_REQUEST,
	"request_contract": REASON_INVALID_REQUEST,
	"rank": REASON_INVALID_REQUEST,
	"resource_commit_failed": REASON_RESOURCE_COMMIT_FAILED,
	"insufficient_mana": REASON_INSUFFICIENT_RESOURCE,
	"insufficient_material": REASON_INSUFFICIENT_RESOURCE,
	"invalid_snapshot": REASON_INVALID_SNAPSHOT,
	"map_mismatch": REASON_MAP_MISMATCH,
	"cooldown": REASON_COOLDOWN,
}


static func build_plan(request: Dictionary, context: Dictionary = {}) -> Dictionary:
	## Canonical planner. Runs the real legacy router plan (side-effect-free) as
	## the gameplay source of truth and envelopes every frozen input into the
	## canonical contract. Never commits anything.
	var request_validation := SkillCastRequestScript.validate(request)
	if not bool(request_validation.get("valid", false)):
		return _rejection_plan(
			"",
			str(request_validation.get("reason", "invalid_request")),
			request,
			context
		)
	var skill_id := SkillDataLoaderScript.stable_skill_id(
		str(request.get("skill_id", ""))
	)
	var definition := SkillDataLoaderScript.skill(skill_id)
	if definition.is_empty():
		return _rejection_plan(skill_id, "unknown_skill", request, context)
	var legacy_result := SkillRuntimeRouterScript.execute(request)
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
	var snapshot_id := str(snapshot.get("snapshot_id", ""))
	var non_spatial_reason := str(NON_SPATIAL_SKILLS.get(skill_id, ""))
	var snapshot_required := non_spatial_reason.is_empty()
	if accepted and snapshot_required:
		var snapshot_valid := false
		if not snapshot.is_empty():
			var validation_context: Dictionary = (
				context.get("snapshot_validation_context", {})
				if context.get("snapshot_validation_context", {}) is Dictionary
				else {}
			)
			if validation_context.is_empty():
				# Structural STRICT_V2 check when no consumer context is given:
				# the frozen snapshot object itself must be a valid V2 object.
				snapshot_valid = bool(
					SkillFootprintSnapshotScript.validate(
						snapshot,
						{}
					).get("valid", false)
				)
			else:
				snapshot_valid = bool(
					SkillFootprintSnapshotScript.validate_for_consumer(
						snapshot,
						validation_context,
						SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
					).get("valid", false)
				)
		if not snapshot_valid:
			accepted = false
			reason = REASON_INVALID_SNAPSHOT
	var effects: Array = legacy_result.get("effects", [])
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
		"cooldown_contract": definition.get("timing", {}).duplicate(true),
		"canonical_snapshot": snapshot,
		"snapshot_id": snapshot_id,
		"snapshot_required": snapshot_required,
		"non_spatial_reason": non_spatial_reason,
		"geometry_cells": _duplicate_array(legacy_result.get("geometry_cells", [])),
		"gameplay_actions": _duplicate_array(effects),
		"presentation_actions": _presentation_actions(skill_id, definition),
		"projectile_descriptors": _descriptors_of_kind(effects, "projectile"),
		"ground_effect_descriptors": _descriptors_of_kind(effects, "ground"),
		"summon_descriptors": _descriptors_of_kind(effects, "summon"),
		"rejection": {
			"accepted": accepted,
			"reason": reason if not accepted else REASON_ACCEPTED,
		},
		"created_by": CANONICAL_PLANNER_ID,
		"legacy_planner": LEGACY_PLANNER_ID,
	}
	plan["plan_hash"] = plan_hash(plan)
	return plan


static func build_result(
	plan: Dictionary,
	overrides: Dictionary = {}
) -> Dictionary:
	## Execution Result contract: what was actually committed (vs what the plan
	## prepared). Never conflated with the immutable plan object.
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


static func plan_hash(plan: Dictionary) -> String:
	## Deterministic hash over the protected plan fields; consumers cannot
	## change target/map/snapshot/cost/cooldown/actions without changing it.
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
		"resource_cost": plan.get("resource_cost", {}),
		"cooldown_contract": plan.get("cooldown_contract", {}),
		"canonical_snapshot": plan.get("canonical_snapshot", {}),
		"geometry_cells": plan.get("geometry_cells", []),
		"gameplay_actions": plan.get("gameplay_actions", []),
		"presentation_actions": plan.get("presentation_actions", []),
		"projectile_descriptors": plan.get("projectile_descriptors", []),
		"ground_effect_descriptors": plan.get(
			"ground_effect_descriptors", []
		),
		"summon_descriptors": plan.get("summon_descriptors", []),
		"rejection": plan.get("rejection", {}),
	}
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


static func _rejection_plan(
	skill_id: String,
	reason: String,
	request: Dictionary,
	context: Dictionary
) -> Dictionary:
	var normalized := normalize_reason(reason)
	var release_id := str(
		context.get(
			"release_id",
			request.get("target_context", {}).get("release_id", "")
		)
	)
	if release_id.is_empty():
		release_id = _derive_release_id(skill_id, request)
	return {
		"contract": CONTRACT_ID,
		"plan_version": PLAN_VERSION,
		"plan_id": "",
		"release_id": release_id,
		"skill_id": skill_id,
		"skill_definition_revision": "",
		"caster_runtime_id": int(context.get("caster_runtime_id", 0)),
		"target_runtime_id": int(context.get("target_runtime_id", 0)),
		"runtime_map_id": int(context.get("runtime_map_id", -1)),
		"input_mode": str(context.get("input_mode", "canonical")),
		"requested_direction": request.get("facing", Vector2i.DOWN),
		"resolved_direction": request.get("facing", Vector2i.DOWN),
		"lock_on_context": {},
		"resource_cost": {},
		"cooldown_contract": {},
		"canonical_snapshot": {},
		"snapshot_id": "",
		"snapshot_required": not NON_SPATIAL_SKILLS.has(skill_id),
		"non_spatial_reason": str(NON_SPATIAL_SKILLS.get(skill_id, "")),
		"geometry_cells": [],
		"gameplay_actions": [],
		"presentation_actions": [],
		"projectile_descriptors": [],
		"ground_effect_descriptors": [],
		"summon_descriptors": [],
		"rejection": {"accepted": false, "reason": normalized},
		"created_by": CANONICAL_PLANNER_ID,
		"legacy_planner": LEGACY_PLANNER_ID,
	}


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
		target_context.get("direction_step", request.get("facing", Vector2i.DOWN))
	)
	if resolved is Vector2i:
		return resolved
	return request.get("facing", Vector2i.DOWN)


static func _presentation_actions(
	skill_id: String,
	definition: Dictionary
) -> Array:
	var actions: Array = []
	var profile := CasterSkillVisualRegistry.profile(skill_id)
	var role := str(profile.get("role", ""))
	if not role.is_empty():
		actions.append({
			"type": "visual",
			"skill_id": skill_id,
			"role": role,
			"phase": str(profile.get("status", "")),
			"visual_radius_px": float(
				definition.get("geometry", {}).get(
					"visual_radius_px", profile.get("visual_radius_px", 0.0)
				)
			),
		})
	return actions


static func _descriptors_of_kind(effects: Array, kind: String) -> Array:
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
				if effect_type in ["main_pet_spawn", "summon"]:
					result.append({
						"kind": "summon",
						"skill_id": str(effect.get("skill_id", "")),
						"release_id": str(effect.get("release_id", "")),
						"template_id": str(effect.get("template_id", "")),
						"spawned": bool(effect.get("spawned", true)),
					})
	return result


static func _canonicalize(value: Variant) -> String:
	if value is Dictionary:
		var parts := PackedStringArray()
		var keys: Array = (value as Dictionary).keys()
		keys.sort()
		for key: Variant in keys:
			parts.append("%s=%s" % [str(key), _canonicalize((value as Dictionary).get(key))])
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
