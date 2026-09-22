class_name SkillFootprintQueryPlan
extends RefCounted

## R3X-1: one immutable broadphase description per skill release.  This layer
## owns no gameplay resolution and never copies or mutates the release
## snapshot/context; R3X-2 may consume the returned ground AABB later.

const SnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)

const CONTRACT_ID := "skills.footprint_query_plan.v1"
const PLAN_VERSION := 1
const QUERY_KIND_AABB := "aabb"
const QUERY_KIND_SEGMENT := "segment"
const UNLIMITED_TARGETS := -1
const ORDERING_STABLE_COMBAT_INSTANCE := (
	"stable_combat_order_instance_id"
)
const ORDERING_DISTANCE_INSTANCE := "distance_along_line_instance_id"
const ORDERING_CELL_INSTANCE := "instance_id"

static var plan_build_count := 0
static var strict_validation_count := 0


## Caller-owned release cache.  It prevents duplicate construction for one
## release without retaining snapshots globally beyond that release's scope.
static func build_once(
	release_cache: Dictionary,
	release_id: String,
	skill_id: String,
	runtime_map_id: int,
	snapshot: Dictionary,
	validation_context: Dictionary,
	options: Dictionary = {}
) -> Dictionary:
	if not release_id.is_empty() and release_cache.has(release_id):
		var cached: Variant = release_cache.get(release_id, {})
		if cached is Dictionary:
			return cached
	var plan := build(
		release_id,
		skill_id,
		runtime_map_id,
		snapshot,
		validation_context,
		options,
	)
	if not release_id.is_empty():
		release_cache[release_id] = plan
	return plan


## Builds the immutable plan.  The strict snapshot validation call below is
## deliberately the only target-resolution validation performed here.
static func build(
	release_id: String,
	skill_id: String,
	runtime_map_id: int,
	snapshot: Dictionary,
	validation_context: Dictionary,
	options: Dictionary = {}
) -> Dictionary:
	plan_build_count += 1
	var invalid_plan := _base_plan(
		release_id,
		skill_id,
		runtime_map_id,
		snapshot,
		validation_context,
		options,
	)
	if release_id.is_empty():
		return _freeze_plan(invalid_plan, "release_id_missing")
	if skill_id.is_empty():
		return _freeze_plan(invalid_plan, "skill_id_missing")
	if runtime_map_id < 0:
		return _freeze_plan(invalid_plan, "runtime_map_id_invalid")
	if snapshot.is_empty():
		return _freeze_plan(invalid_plan, "snapshot_missing")
	if not snapshot.is_read_only():
		return _freeze_plan(invalid_plan, "snapshot_not_immutable")

	var strict_context: Dictionary = validation_context
	if (
		runtime_map_id >= 0
		and not validation_context.has("expected_runtime_map_id")
	):
		# Only add the expected map discriminator to a shallow validation view;
		# the caller-owned context stored in the plan remains untouched.
		strict_context = validation_context.duplicate(false)
		strict_context["expected_runtime_map_id"] = runtime_map_id
	strict_validation_count += 1
	var validation := SnapshotScript.validate_for_consumer(
		snapshot,
		strict_context,
		SnapshotScript.VALIDATION_STRICT_V2,
	)
	if not bool(validation.get("valid", false)):
		return _freeze_plan(
			invalid_plan,
			str(validation.get("reason", "snapshot_invalid")),
		)
	var snapshot_skill_id := str(snapshot.get("skill_id", ""))
	var snapshot_release_id := str(snapshot.get("release_id", ""))
	if snapshot_skill_id != skill_id:
		return _freeze_plan(invalid_plan, "snapshot_skill_id_mismatch")
	if snapshot_release_id != release_id:
		return _freeze_plan(invalid_plan, "snapshot_release_id_mismatch")
	var coordinate_space := str(snapshot.get("coordinate_space", ""))
	if coordinate_space == SnapshotScript.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU:
		if int(snapshot.get("runtime_map_id", -1)) != runtime_map_id:
			return _freeze_plan(invalid_plan, "snapshot_runtime_map_id_mismatch")

	var aabb := SnapshotScript.ground_aabb(snapshot)
	if not bool(aabb.get("valid", false)):
		return _freeze_plan(
			invalid_plan,
			str(aabb.get("reason", "ground_aabb_invalid")),
		)
	var resolved_query_kind := str(options.get("query_kind", ""))
	if resolved_query_kind.is_empty():
		resolved_query_kind = (
			QUERY_KIND_SEGMENT
			if str(snapshot.get("shape_type", ""))
			== SnapshotScript.SHAPE_SWEPT_CAPSULE_PATH
			else QUERY_KIND_AABB
		)
	if resolved_query_kind not in [QUERY_KIND_AABB, QUERY_KIND_SEGMENT]:
		return _freeze_plan(invalid_plan, "query_kind_invalid")
	var resolved_ordering_policy := str(
		options.get("ordering_policy", "")
	)
	if resolved_ordering_policy.is_empty():
		resolved_ordering_policy = (
			ORDERING_DISTANCE_INSTANCE
			if resolved_query_kind == QUERY_KIND_SEGMENT
			else ORDERING_STABLE_COMBAT_INSTANCE
		)
	if resolved_ordering_policy not in [
		ORDERING_STABLE_COMBAT_INSTANCE,
		ORDERING_DISTANCE_INSTANCE,
		ORDERING_CELL_INSTANCE,
	]:
		return _freeze_plan(invalid_plan, "ordering_policy_invalid")
	var raw_maximum_targets: Variant = options.get(
		"maximum_targets",
		0,
	)
	if not raw_maximum_targets is int and not raw_maximum_targets is float:
		return _freeze_plan(invalid_plan, "maximum_targets_invalid")
	var maximum_targets := 0
	if raw_maximum_targets is int:
		maximum_targets = raw_maximum_targets
	else:
		if not is_finite(float(raw_maximum_targets)):
			return _freeze_plan(invalid_plan, "maximum_targets_invalid")
		maximum_targets = int(raw_maximum_targets)
	if (
		maximum_targets < UNLIMITED_TARGETS
		or not is_finite(float(raw_maximum_targets))
		or not is_equal_approx(
			float(raw_maximum_targets), float(maximum_targets)
		)
	):
		return _freeze_plan(invalid_plan, "maximum_targets_invalid")

	var cell_sequence_result := _cell_sequence_for_snapshot(snapshot, options)
	if not bool(cell_sequence_result.get("valid", false)):
		return _freeze_plan(
			invalid_plan,
			str(cell_sequence_result.get("reason", "cell_sequence_invalid")),
		)
	var line_origin_result := _line_origin_for_snapshot(snapshot, options)
	if not bool(line_origin_result.get("valid", false)):
		return _freeze_plan(
			invalid_plan,
			str(line_origin_result.get("reason", "line_origin_invalid")),
		)
	var line_direction_result := _line_direction_for_snapshot(snapshot, options)
	if not bool(line_direction_result.get("valid", false)):
		return _freeze_plan(
			invalid_plan,
			str(line_direction_result.get("reason", "line_direction_invalid")),
		)
	var plan := {
		"contract": CONTRACT_ID,
		"plan_version": PLAN_VERSION,
		"release_id": release_id,
		"skill_id": skill_id,
		"runtime_map_id": runtime_map_id,
		"shape_type": str(snapshot.get("shape_type", "")),
		"validated_snapshot_reference": snapshot,
		"validation_context_reference": validation_context,
		"ground_aabb": aabb.get("bounds_ground_gu", Rect2()),
		"query_kind": resolved_query_kind,
		"ordering_policy": resolved_ordering_policy,
		"maximum_targets": maximum_targets,
		"cell_sequence": cell_sequence_result.get("value", []),
		"line_origin_ground_gu": line_origin_result.get(
			"value", Vector2.ZERO
		),
		"line_direction_ground_gu": line_direction_result.get(
			"value", Vector2.ZERO
		),
		"valid": true,
		"failure_reason": "",
	}
	plan.make_read_only()
	return plan


static func clear_release_cache(
	release_cache: Dictionary,
	release_id: String
) -> void:
	if not release_id.is_empty():
		release_cache.erase(release_id)


static func reset_for_tests() -> void:
	plan_build_count = 0
	strict_validation_count = 0


static func diagnostics() -> Dictionary:
	return {
		"contract": CONTRACT_ID,
		"plan_build_count": plan_build_count,
		"strict_validation_count": strict_validation_count,
	}


static func _base_plan(
	release_id: String,
	skill_id: String,
	runtime_map_id: int,
	snapshot: Dictionary,
	validation_context: Dictionary,
	options: Dictionary,
) -> Dictionary:
	var empty_cells: Array[Vector2i] = []
	empty_cells.make_read_only()
	var raw_maximum_targets: Variant = options.get("maximum_targets", 0)
	var base_maximum_targets := 0
	if raw_maximum_targets is int:
		base_maximum_targets = raw_maximum_targets
	elif raw_maximum_targets is float and is_finite(float(raw_maximum_targets)):
		base_maximum_targets = int(raw_maximum_targets)
	return {
		"contract": CONTRACT_ID,
		"plan_version": PLAN_VERSION,
		"release_id": release_id,
		"skill_id": skill_id,
		"runtime_map_id": runtime_map_id,
		"shape_type": str(snapshot.get("shape_type", "")),
		"validated_snapshot_reference": snapshot,
		"validation_context_reference": validation_context,
		"ground_aabb": Rect2(),
		"query_kind": str(options.get("query_kind", "")),
		"ordering_policy": str(options.get("ordering_policy", "")),
		"maximum_targets": base_maximum_targets,
		"cell_sequence": empty_cells,
		"line_origin_ground_gu": Vector2.ZERO,
		"line_direction_ground_gu": Vector2.ZERO,
		"valid": false,
		"failure_reason": "",
	}


static func _freeze_plan(plan: Dictionary, reason: String) -> Dictionary:
	plan["valid"] = false
	plan["failure_reason"] = reason
	plan.make_read_only()
	return plan


static func _cell_sequence_for_snapshot(
	snapshot: Dictionary,
	options: Dictionary
) -> Dictionary:
	var raw_cells: Variant = options.get("cell_sequence", null)
	if raw_cells == null and str(snapshot.get("shape_type", "")) == SnapshotScript.SHAPE_CELL_UNION:
		raw_cells = snapshot.get("geometry_cells_grid_steps", null)
	if raw_cells == null:
		return {
			"valid": true,
			"value": _empty_cell_sequence(),
			"reason": "",
		}
	if not raw_cells is Array:
		return {
			"valid": false,
			"value": _empty_cell_sequence(),
			"reason": "cell_sequence_invalid",
		}
	var copied_cells: Array[Vector2i] = []
	for raw_cell: Variant in raw_cells as Array:
		if not raw_cell is Vector2i:
			return {
				"valid": false,
				"value": _empty_cell_sequence(),
				"reason": "cell_sequence_invalid",
			}
		copied_cells.append(raw_cell)
	copied_cells.make_read_only()
	return {"valid": true, "value": copied_cells, "reason": ""}


static func _empty_cell_sequence() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.make_read_only()
	return result


static func _line_origin_for_snapshot(
	snapshot: Dictionary,
	options: Dictionary
) -> Dictionary:
	var raw_origin: Variant = options.get("line_origin_ground_gu", null)
	if raw_origin == null:
		raw_origin = snapshot.get(
			"segment_start_ground_gu",
			snapshot.get("start_ground_gu", snapshot.get("origin_ground_gu", Vector2.ZERO)),
		)
	if not raw_origin is Vector2 or not (raw_origin as Vector2).is_finite():
		return {"valid": false, "value": Vector2.ZERO, "reason": "line_origin_invalid"}
	return {"valid": true, "value": raw_origin as Vector2, "reason": ""}


static func _line_direction_for_snapshot(
	snapshot: Dictionary,
	options: Dictionary
) -> Dictionary:
	var raw_direction: Variant = options.get("line_direction_ground_gu", null)
	if raw_direction == null:
		raw_direction = snapshot.get("direction_ground_gu", Vector2.ZERO)
	if not raw_direction is Vector2 or not (raw_direction as Vector2).is_finite():
		return {"valid": false, "value": Vector2.ZERO, "reason": "line_direction_invalid"}
	return {"valid": true, "value": raw_direction as Vector2, "reason": ""}
