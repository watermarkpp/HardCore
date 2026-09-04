class_name SkillFootprintSnapshot
extends RefCounted

## Immutable release-time geometry shared by gameplay hit resolution, projected
## presentation and regression tests. Gameplay owns only ground-GU values; PX
## values are a one-way projection derived from the same ground polygon.

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

const CONTRACT_ID := "skills.footprint_snapshot.ground_gu_projection.v1"
const DIRECTED_RECTANGLE_CONTRACT_ID := (
	"skills.footprint_snapshot.directed_rectangle.v1"
)
const SECTOR_ARC_CONTRACT_ID := "skills.footprint_snapshot.sector_arc.v1"
const CIRCLE_CONTRACT_ID := "skills.footprint_snapshot.circle.v1"
const SWEPT_CAPSULE_PATH_CONTRACT_ID := (
	"skills.footprint_snapshot.swept_capsule_path.v1"
)
const TARGET_FOOTPRINT_CONTRACT_ID := (
	"skills.footprint_snapshot.target_footprint.v1"
)
const CELL_UNION_CONTRACT_ID := (
	"skills.footprint_snapshot.exact_cell_union.v1"
)
const PROJECTION_API_CONTRACT_ID := (
	"skills.footprint_snapshot.projection.iso_64x32.v1"
)

## HC-P1-010: explicit coordinate-space schema V2. Every new formal snapshot
## declares its coordinate_space; absolute snapshots additionally carry the
## runtime map id and the explicit projection origin. The old ambiguous
## "ground_gu" value is only produced by the documented legacy builder entry
## (create_* without a coordinate_context) and must be upgraded through
## upgrade_legacy_snapshot() before entering strict consumers.
const SCHEMA_VERSION := 2
const COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU := (
	&"runtime_map_absolute_ground_gu"
)
const COORDINATE_SPACE_LOCAL_GROUND_DELTA_GU := &"local_ground_delta_gu"
const COORDINATE_SPACE_LEGACY_GROUND_GU := &"ground_gu"
const SUPPORTED_COORDINATE_SPACES: Array[String] = [
	COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU,
	COORDINATE_SPACE_LOCAL_GROUND_DELTA_GU,
]
const LEGACY_SCHEMA_VERSION := 1

## Q1-A: explicit validation policies. STRICT_V2 is the only policy for V2
## coordinate consumers; EXPLICIT_LEGACY_COMPAT requires an explicit legacy
## context (interpretation + converters + consumer identity) and is the only
## way a legacy snapshot may enter a consumer.
const VALIDATION_STRICT_V2 := &"strict_v2"
const VALIDATION_EXPLICIT_LEGACY_COMPAT := &"explicit_legacy_compat"
const LEGACY_VALIDATION_COUNTER_KEY := "legacy_snapshot_validation_count"
static var legacy_snapshot_validation_count := 0

const SHAPE_DIRECTED_RECTANGLE := "directed_rectangle"
const SHAPE_SECTOR_ARC := "sector_arc"
const SHAPE_CIRCLE := "circle"
const SHAPE_SWEPT_CAPSULE_PATH := "swept_capsule_path"
const SHAPE_TARGET_FOOTPRINT := "target_footprint"
const SHAPE_CELL_UNION := "cell_union"
const SUPPORTED_SHAPE_TYPES: Array[String] = [
	SHAPE_DIRECTED_RECTANGLE,
	SHAPE_SECTOR_ARC,
	SHAPE_CIRCLE,
	SHAPE_SWEPT_CAPSULE_PATH,
	SHAPE_TARGET_FOOTPRINT,
	SHAPE_CELL_UNION,
]

const CONTACT_EPSILON_GU := 0.0001
const DEFAULT_CURVE_SEGMENTS := 32


static func make_absolute_runtime_context(
	runtime_map_id: Variant,
	origin_ground_gu: Vector2,
	projection_origin_ground_gu: Vector2,
	ground_to_screen_position: Callable
) -> Dictionary:
	return {
		"coordinate_space": COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU,
		"runtime_map_id": normalize_runtime_map_id(runtime_map_id),
		"origin_ground_gu": origin_ground_gu,
		"projection_origin_ground_gu": projection_origin_ground_gu,
		"ground_position_gu_to_screen_position_px": ground_to_screen_position,
	}


static func make_local_delta_context(
	ground_delta_to_screen_delta: Callable
) -> Dictionary:
	return {
		"coordinate_space": COORDINATE_SPACE_LOCAL_GROUND_DELTA_GU,
		"ground_delta_gu_to_screen_delta_px": ground_delta_to_screen_delta,
		"projection_origin_ground_gu": Vector2.ZERO,
	}


## Q1-B: the project's formal runtime map id is int. All V2 snapshots store a
## normalized int; non-numeric inputs normalize to -1 and fail validation.
static func normalize_runtime_map_id(value: Variant) -> int:
	if value is int:
		return value as int
	if value is float:
		return int(value as float)
	if value is String:
		var trimmed := (value as String).strip_edges()
		if trimmed.is_valid_int():
			return trimmed.to_int()
	return -1


static func _call_vector2_result(
	callable_value: Variant,
	value: Vector2
) -> Dictionary:
	if not callable_value is Callable:
		return {
			"valid": false,
			"value": Vector2.ZERO,
			"reason": "invalid_converter",
		}
	var callable := callable_value as Callable
	if not callable.is_valid():
		return {
			"valid": false,
			"value": Vector2.ZERO,
			"reason": "invalid_converter",
		}
	var result: Variant = callable.call(value)
	if result is Vector2 and _vector2_is_finite(result as Vector2):
		return {
			"valid": true,
			"value": result as Vector2,
			"reason": "",
		}
	return {
		"valid": false,
		"value": Vector2.ZERO,
		"reason": "non_finite_converter_result",
	}


static func _call_vector2(callable_value: Variant, value: Vector2) -> Vector2:
	var result := _call_vector2_result(callable_value, value)
	return result.get("value", Vector2.ZERO) as Vector2


static func _coordinate_fields_from_context(
	coordinate_context: Dictionary
) -> Dictionary:
	var coordinate_space := str(
		coordinate_context.get("coordinate_space", "")
	)
	if coordinate_space == COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU:
		return {
			"schema_version": SCHEMA_VERSION,
			"coordinate_space": coordinate_space,
			"runtime_map_id": normalize_runtime_map_id(
				coordinate_context.get("runtime_map_id", -1)
			),
			"projection_origin_ground_gu": (
				coordinate_context.get(
					"projection_origin_ground_gu", Vector2.ZERO
				)
				as Vector2
			),
			"created_by": str(
				coordinate_context.get("created_by", "production_absolute")
			),
		}
	if coordinate_space == COORDINATE_SPACE_LOCAL_GROUND_DELTA_GU:
		return {
			"schema_version": SCHEMA_VERSION,
			"coordinate_space": coordinate_space,
			"runtime_map_id": normalize_runtime_map_id(
				coordinate_context.get("runtime_map_id", -1)
			),
			"projection_origin_ground_gu": Vector2.ZERO,
			"created_by": str(
				coordinate_context.get("created_by", "production_local_delta")
			),
		}
	# Documented legacy compatibility entry: create_* without an explicit
	# coordinate context keeps the historical ambiguous ground_gu semantics.
	# Strict consumers must route it through upgrade_legacy_snapshot().
	return {
		"schema_version": LEGACY_SCHEMA_VERSION,
		"coordinate_space": COORDINATE_SPACE_LEGACY_GROUND_GU,
		"runtime_map_id": "",
		"projection_origin_ground_gu": Vector2.ZERO,
		"created_by": "legacy_builder_no_context",
	}


static func project_ground_polygon_to_screen_offsets_px(
	polygon_ground_gu: PackedVector2Array,
	origin_ground_gu: Vector2,
	coordinate_context := {}
) -> PackedVector2Array:
	var coordinate_space := str(
		coordinate_context.get("coordinate_space", "")
	)
	var result := PackedVector2Array()
	if (
		coordinate_space
		== COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU
	):
		var converter: Variant = coordinate_context.get(
			"ground_position_gu_to_screen_position_px",
			Callable()
		)
		# Q1-A: absolute snapshots may ONLY use the ground-position converter.
		# An invalid converter is an explicit projection failure (empty result);
		# it must never fall through to the delta converter.
		if not converter is Callable or not (converter as Callable).is_valid():
			return result
		var projection_origin_ground_gu: Vector2 = (
			coordinate_context.get(
				"projection_origin_ground_gu",
				origin_ground_gu
			) as Vector2
		)
		var projection_origin_result := _call_vector2_result(
			converter,
			projection_origin_ground_gu
		)
		if not bool(projection_origin_result.get("valid", false)):
			return result
		var projection_origin_screen_px := (
			projection_origin_result.get("value", Vector2.ZERO) as Vector2
		)
		for point_ground_gu: Vector2 in polygon_ground_gu:
			var point_result := _call_vector2_result(converter, point_ground_gu)
			if not bool(point_result.get("valid", false)):
				return PackedVector2Array()
			result.append(
				(point_result.get("value", Vector2.ZERO) as Vector2)
				- projection_origin_screen_px
			)
		return result
	# local delta / legacy: only the delta converter is used.
	var delta_converter: Variant = coordinate_context.get(
		"ground_delta_gu_to_screen_delta_px",
		Callable()
	)
	for point_ground_gu: Vector2 in polygon_ground_gu:
		if delta_converter is Callable and (delta_converter as Callable).is_valid():
			var point_result := _call_vector2_result(
				delta_converter,
				point_ground_gu - origin_ground_gu
			)
			if not bool(point_result.get("valid", false)):
				return PackedVector2Array()
			result.append(point_result.get("value", Vector2.ZERO) as Vector2)
		else:
			var fallback := GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				point_ground_gu - origin_ground_gu
			)
			if not _vector2_is_finite(fallback):
				return PackedVector2Array()
			result.append(fallback)
	return result


static func create_directed_rectangle(
	skill_id: String,
	release_id: String,
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	effect_length_gu: float,
	effect_width_gu: float,
	start_offset_gu := 0.0,
	declared_effect_length_gu := 0.0,
	resolved_effect_length_gu := 0.0,
	laser_projection_policy := "",
	coordinate_context := {}
) -> Dictionary:
	var coordinate_fields := _coordinate_fields_from_context(
		coordinate_context
	)
	var effective_origin_ground_gu := origin_ground_gu
	if (
		str(coordinate_fields.get("coordinate_space", ""))
		== COORDINATE_SPACE_LOCAL_GROUND_DELTA_GU
	):
		effective_origin_ground_gu = Vector2.ZERO
	var resolved_direction_ground_gu := direction_ground_gu
	if (
		resolved_direction_ground_gu.length_squared()
		<= CONTACT_EPSILON_GU * CONTACT_EPSILON_GU
	):
		resolved_direction_ground_gu = Vector2(1.0, 1.0)
	resolved_direction_ground_gu = resolved_direction_ground_gu.normalized()
	var perpendicular_ground_gu := Vector2(
		-resolved_direction_ground_gu.y,
		resolved_direction_ground_gu.x
	)
	var safe_length_gu := maxf(0.0, effect_length_gu)
	var safe_width_gu := maxf(CONTACT_EPSILON_GU, effect_width_gu)
	var safe_start_offset_gu := maxf(0.0, float(start_offset_gu))
	var half_width_gu := safe_width_gu * 0.5
	var start_ground_gu := (
		origin_ground_gu
		+ resolved_direction_ground_gu * safe_start_offset_gu
	)
	var end_ground_gu := (
		start_ground_gu + resolved_direction_ground_gu * safe_length_gu
	)
	var polygon_ground_gu := PackedVector2Array([
		start_ground_gu + perpendicular_ground_gu * half_width_gu,
		end_ground_gu + perpendicular_ground_gu * half_width_gu,
		end_ground_gu - perpendicular_ground_gu * half_width_gu,
		start_ground_gu - perpendicular_ground_gu * half_width_gu,
	])
	var polygon_screen_offset_px := project_ground_polygon_to_screen_offsets_px(
		polygon_ground_gu,
		origin_ground_gu,
		coordinate_context
	)
	var axis_screen_offset_px := (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			resolved_direction_ground_gu
			* (safe_start_offset_gu + safe_length_gu)
		)
	)
	var axis_start_screen_offset_px := (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			resolved_direction_ground_gu * safe_start_offset_gu
		)
	)
	var axis_screen_direction_px := (
		axis_screen_offset_px.normalized()
		if axis_screen_offset_px.length_squared() > 0.000001
		else Vector2.ZERO
	)
	var cross_screen_extent_px := _polygon_projection_extent_px(
		polygon_screen_offset_px,
		Vector2(-axis_screen_direction_px.y, axis_screen_direction_px.x)
	)
	var snapshot := {
		"contract_id": CONTRACT_ID,
		"shape_contract_id": DIRECTED_RECTANGLE_CONTRACT_ID,
		"projection_api_contract_id": PROJECTION_API_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"projection_contract_id": GroundUnitSpaceScript.PROJECTION_CONTRACT_ID,
		"snapshot_id": "%s:%s" % [skill_id, release_id],
		"skill_id": skill_id,
		"release_id": release_id,
		"shape_type": SHAPE_DIRECTED_RECTANGLE,
		"origin_ground_gu": effective_origin_ground_gu,
		"start_offset_gu": safe_start_offset_gu,
		"start_ground_gu": start_ground_gu,
		"direction_ground_gu": resolved_direction_ground_gu,
		"perpendicular_ground_gu": perpendicular_ground_gu,
		"effect_length_gu": safe_length_gu,
		"effect_width_gu": safe_width_gu,
		"half_width_gu": half_width_gu,
		"end_ground_gu": end_ground_gu,
		"polygon_ground_gu": polygon_ground_gu,
		"axis_start_screen_offset_px": axis_start_screen_offset_px,
		"axis_screen_offset_px": axis_screen_offset_px,
		"axis_screen_length_px": (
			axis_screen_offset_px - axis_start_screen_offset_px
		).length(),
		"axis_screen_direction_px": axis_screen_direction_px,
		"cross_screen_extent_px": cross_screen_extent_px,
		"polygon_screen_offset_px": polygon_screen_offset_px,
		"declared_effect_length_gu": declared_effect_length_gu,
		"resolved_effect_length_gu": resolved_effect_length_gu,
		"laser_projection_policy": laser_projection_policy,
		"damage_space": str(
			coordinate_fields.get("coordinate_space", "ground_gu")
		),
		"visual_space": "screen_px_derived_only",
	}
	snapshot.merge(coordinate_fields, true)
	snapshot.make_read_only()
	return snapshot


static func create_sector_arc(
	skill_id: String,
	release_id: String,
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	radius_gu: float,
	half_angle_radians: float,
	arc_segments := DEFAULT_CURVE_SEGMENTS,
	coordinate_context := {}
) -> Dictionary:
	var resolved_direction_ground_gu := _normalized_direction_ground_gu(
		direction_ground_gu
	)
	var safe_radius_gu := maxf(0.0, radius_gu)
	var safe_half_angle_radians := clampf(
		absf(half_angle_radians),
		0.0,
		PI * 0.5
	)
	var safe_arc_segments := maxi(2, arc_segments)
	var polygon_ground_gu := PackedVector2Array([origin_ground_gu])
	var center_angle_radians := resolved_direction_ground_gu.angle()
	for index: int in range(safe_arc_segments + 1):
		var weight := float(index) / float(safe_arc_segments)
		var angle_radians := lerpf(
			center_angle_radians - safe_half_angle_radians,
			center_angle_radians + safe_half_angle_radians,
			weight
		)
		polygon_ground_gu.append(
			origin_ground_gu
			+ Vector2.from_angle(angle_radians) * safe_radius_gu
		)
	return _create_polygon_snapshot(
		skill_id,
		release_id,
		SHAPE_SECTOR_ARC,
		SECTOR_ARC_CONTRACT_ID,
		origin_ground_gu,
		polygon_ground_gu,
		{
			"direction_ground_gu": resolved_direction_ground_gu,
			"radius_gu": safe_radius_gu,
			"half_angle_radians": safe_half_angle_radians,
			"effect_length_gu": safe_radius_gu,
			"effect_width_gu": (
				2.0 * safe_radius_gu * sin(safe_half_angle_radians)
			),
			"arc_segments": safe_arc_segments,
		},
		coordinate_context
	)


static func create_circle(
	skill_id: String,
	release_id: String,
	center_ground_gu: Vector2,
	radius_gu: float,
	segments := DEFAULT_CURVE_SEGMENTS,
	coordinate_context := {}
) -> Dictionary:
	var safe_radius_gu := maxf(0.0, radius_gu)
	var safe_segments := maxi(8, segments)
	return _create_polygon_snapshot(
		skill_id,
		release_id,
		SHAPE_CIRCLE,
		CIRCLE_CONTRACT_ID,
		center_ground_gu,
		_circle_polygon_ground_gu(
			center_ground_gu, safe_radius_gu, safe_segments
		),
		{
			"center_ground_gu": center_ground_gu,
			"radius_gu": safe_radius_gu,
			"effect_length_gu": safe_radius_gu,
			"effect_width_gu": safe_radius_gu * 2.0,
			"curve_segments": safe_segments,
		},
		coordinate_context
	)


static func create_swept_capsule_path(
	skill_id: String,
	release_id: String,
	segment_start_ground_gu: Vector2,
	segment_end_ground_gu: Vector2,
	path_radius_gu: float,
	cap_segments := DEFAULT_CURVE_SEGMENTS / 2,
	parent_snapshot_id := "",
	segment_index := -1,
	coordinate_context := {}
) -> Dictionary:
	var safe_radius_gu := maxf(0.0, path_radius_gu)
	var segment_ground_gu := (
		segment_end_ground_gu - segment_start_ground_gu
	)
	var safe_cap_segments := maxi(4, cap_segments)
	var polygon_ground_gu := PackedVector2Array()
	if (
		segment_ground_gu.length_squared()
		<= CONTACT_EPSILON_GU * CONTACT_EPSILON_GU
	):
		polygon_ground_gu = _circle_polygon_ground_gu(
			segment_start_ground_gu,
			safe_radius_gu,
			safe_cap_segments * 2
		)
	else:
		var direction_ground_gu := segment_ground_gu.normalized()
		var side_ground_gu := Vector2(
			-direction_ground_gu.y, direction_ground_gu.x
		)
		for index: int in range(safe_cap_segments + 1):
			var weight := float(index) / float(safe_cap_segments)
			var angle_radians := lerpf(PI * 0.5, -PI * 0.5, weight)
			polygon_ground_gu.append(
				segment_end_ground_gu
				+ (
					direction_ground_gu * cos(angle_radians)
					+ side_ground_gu * sin(angle_radians)
				) * safe_radius_gu
			)
		for index: int in range(safe_cap_segments + 1):
			var weight := float(index) / float(safe_cap_segments)
			var angle_radians := lerpf(-PI * 0.5, -PI * 1.5, weight)
			polygon_ground_gu.append(
				segment_start_ground_gu
				+ (
					direction_ground_gu * cos(angle_radians)
					+ side_ground_gu * sin(angle_radians)
				) * safe_radius_gu
			)
	var direction_ground_gu := _normalized_direction_ground_gu(
		segment_ground_gu
	)
	return _create_polygon_snapshot(
		skill_id,
		release_id,
		SHAPE_SWEPT_CAPSULE_PATH,
		SWEPT_CAPSULE_PATH_CONTRACT_ID,
		segment_start_ground_gu,
		polygon_ground_gu,
		{
			"segment_start_ground_gu": segment_start_ground_gu,
			"segment_end_ground_gu": segment_end_ground_gu,
			"direction_ground_gu": direction_ground_gu,
			"path_radius_gu": safe_radius_gu,
			"effect_length_gu": segment_ground_gu.length(),
			"effect_width_gu": safe_radius_gu * 2.0,
			"cap_segments": safe_cap_segments,
			"parent_snapshot_id": parent_snapshot_id,
			"segment_index": segment_index,
		},
		coordinate_context
	)


static func create_target_footprint(
	skill_id: String,
	release_id: String,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	target_instance_id := 0,
	coordinate_context := {}
) -> Dictionary:
	var safe_radius_gu := maxf(0.0, target_combat_radius_gu)
	var polygon_ground_gu := PackedVector2Array()
	for offset_ground_gu: Vector2 in (
		WorldSpatialRulesScript.actor_footprint_ground_polygon_gu(
			safe_radius_gu
		)
	):
		polygon_ground_gu.append(
			target_center_ground_gu + offset_ground_gu
		)
	return _create_polygon_snapshot(
		skill_id,
		release_id,
		SHAPE_TARGET_FOOTPRINT,
		TARGET_FOOTPRINT_CONTRACT_ID,
		target_center_ground_gu,
		polygon_ground_gu,
		{
			"target_center_ground_gu": target_center_ground_gu,
			"target_combat_radius_gu": safe_radius_gu,
			"target_instance_id": target_instance_id,
			"effect_length_gu": safe_radius_gu * 2.0,
			"effect_width_gu": safe_radius_gu * 2.0,
			"target_footprint_contract_id": (
				WorldSpatialRulesScript.ACTOR_GROUND_FOOTPRINT_CONTRACT_ID
			),
		},
		coordinate_context
	)


static func create_cell_union(
	skill_id: String,
	release_id: String,
	origin_ground_gu: Vector2,
	geometry_cells_grid_steps: Array[Vector2i],
	coordinate_context := {}
) -> Dictionary:
	var coordinate_fields := _coordinate_fields_from_context(
		coordinate_context
	)
	var effective_origin_ground_gu := origin_ground_gu
	if (
		str(coordinate_fields.get("coordinate_space", ""))
		== COORDINATE_SPACE_LOCAL_GROUND_DELTA_GU
	):
		effective_origin_ground_gu = Vector2.ZERO
	var polygons_ground_gu: Array[PackedVector2Array] = []
	var polygons_screen_offset_px: Array[PackedVector2Array] = []
	var copied_cells_grid_steps: Array[Vector2i] = []
	for cell_grid_steps: Vector2i in geometry_cells_grid_steps:
		var center_ground_gu := Vector2(cell_grid_steps)
		var cell_polygon_ground_gu := PackedVector2Array([
			center_ground_gu + Vector2(-0.5, -0.5),
			center_ground_gu + Vector2(0.5, -0.5),
			center_ground_gu + Vector2(0.5, 0.5),
			center_ground_gu + Vector2(-0.5, 0.5),
		])
		polygons_ground_gu.append(cell_polygon_ground_gu)
		polygons_screen_offset_px.append(
			project_ground_polygon_to_screen_offsets_px(
				cell_polygon_ground_gu,
				origin_ground_gu,
				coordinate_context
			)
		)
		copied_cells_grid_steps.append(cell_grid_steps)
	polygons_ground_gu.make_read_only()
	polygons_screen_offset_px.make_read_only()
	copied_cells_grid_steps.make_read_only()
	var first_polygon_ground_gu := (
		polygons_ground_gu[0]
		if not polygons_ground_gu.is_empty()
		else PackedVector2Array()
	)
	var first_polygon_screen_offset_px := (
		polygons_screen_offset_px[0]
		if not polygons_screen_offset_px.is_empty()
		else PackedVector2Array()
	)
	var snapshot := {
		"contract_id": CONTRACT_ID,
		"shape_contract_id": CELL_UNION_CONTRACT_ID,
		"projection_api_contract_id": PROJECTION_API_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"projection_contract_id": GroundUnitSpaceScript.PROJECTION_CONTRACT_ID,
		"snapshot_id": "%s:%s" % [skill_id, release_id],
		"skill_id": skill_id,
		"release_id": release_id,
		"shape_type": SHAPE_CELL_UNION,
		"origin_ground_gu": effective_origin_ground_gu,
		"geometry_cells_grid_steps": copied_cells_grid_steps,
		"polygons_ground_gu": polygons_ground_gu,
		"polygons_screen_offset_px": polygons_screen_offset_px,
		"polygon_ground_gu": first_polygon_ground_gu,
		"polygon_screen_offset_px": first_polygon_screen_offset_px,
		"effect_length_gu": 0.0,
		"effect_width_gu": 0.0,
		"damage_space": str(
			coordinate_fields.get("coordinate_space", "ground_gu")
		),
		"visual_space": "screen_px_derived_only",
	}
	snapshot.merge(coordinate_fields, true)
	snapshot.make_read_only()
	return snapshot


## Q1-A: is_valid() is now a strict-V2 delegate. It no longer means "has the
## old base contract"; coordinate consumers must call validate_for_consumer()
## with an explicit expected context and policy. Legacy consumers must use
## has_legacy_base_contract() or the EXPLICIT_LEGACY_COMPAT policy.
static func is_valid(snapshot: Dictionary) -> bool:
	return bool(
		validate_for_consumer(
			snapshot,
			{},
			VALIDATION_STRICT_V2
		).get("valid", false)
	)


static func has_legacy_base_contract(snapshot: Dictionary) -> bool:
	return (
		str(snapshot.get("contract_id", "")) == CONTRACT_ID
		and str(snapshot.get("shape_type", "")) in SUPPORTED_SHAPE_TYPES
		and not str(snapshot.get("skill_id", "")).is_empty()
		and not str(snapshot.get("release_id", "")).is_empty()
		and str(snapshot.get("unit_contract_id", ""))
		== GroundUnitSpaceScript.CONTRACT_ID
		and str(snapshot.get("projection_contract_id", ""))
		== GroundUnitSpaceScript.PROJECTION_CONTRACT_ID
	)


static func legacy_consumer_context(
	consumer_name: String,
	migration_reason: String,
	coordinate_interpretation: String,
	converter: Callable = Callable()
) -> Dictionary:
	return {
		"legacy_coordinate_interpretation": coordinate_interpretation,
		"consumer_name": consumer_name,
		"migration_reason": migration_reason,
		"ground_delta_gu_to_screen_delta_px": converter,
	}


## Q1-A: the single formal consumer-facing validation entry. STRICT_V2 rejects
## legacy/ambiguous snapshots; EXPLICIT_LEGACY_COMPAT requires an explicit
## legacy context and records a lightweight counter.
static func validate_for_consumer(
	snapshot: Dictionary,
	expected_context: Dictionary,
	policy: StringName = VALIDATION_STRICT_V2
) -> Dictionary:
	if policy == VALIDATION_STRICT_V2:
		var strict := validate(snapshot, expected_context)
		if not bool(strict.get("valid", false)):
			return {
				"valid": false,
				"reason": str(strict.get("reason", "invalid_snapshot")),
				"schema_version": int(snapshot.get("schema_version", 0)),
				"coordinate_space": str(snapshot.get("coordinate_space", "")),
				"runtime_map_id": str(snapshot.get("runtime_map_id", "")),
				"policy": VALIDATION_STRICT_V2,
				"legacy_used": false,
				"details": strict.get("details", {}),
			}
		var coordinate_space := str(snapshot.get("coordinate_space", ""))
		var position_converter_valid := true
		var delta_converter_valid := true
		if coordinate_space == COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU:
			var converter: Variant = expected_context.get(
				"ground_position_gu_to_screen_position_px", Callable()
			)
			position_converter_valid = (
				converter is Callable
				and (converter as Callable).is_valid()
			)
			if not position_converter_valid:
				return {
					"valid": false,
					"reason": "absolute_position_requires_position_converter",
					"schema_version": int(
						snapshot.get("schema_version", 0)
					),
					"coordinate_space": coordinate_space,
					"runtime_map_id": str(
						snapshot.get("runtime_map_id", "")
					),
					"policy": VALIDATION_STRICT_V2,
					"legacy_used": false,
					"details": {},
				}
		elif coordinate_space == COORDINATE_SPACE_LOCAL_GROUND_DELTA_GU:
			var delta_converter: Variant = expected_context.get(
				"ground_delta_gu_to_screen_delta_px", Callable()
			)
			delta_converter_valid = (
				delta_converter is Callable
				and (delta_converter as Callable).is_valid()
			)
			if not delta_converter_valid:
				return {
					"valid": false,
					"reason": "local_delta_requires_delta_converter",
					"schema_version": int(
						snapshot.get("schema_version", 0)
					),
					"coordinate_space": coordinate_space,
					"runtime_map_id": str(
						snapshot.get("runtime_map_id", "")
					),
					"policy": VALIDATION_STRICT_V2,
					"legacy_used": false,
					"details": {},
				}
		return {
			"valid": true,
			"reason": "",
			"schema_version": SCHEMA_VERSION,
			"coordinate_space": coordinate_space,
			"runtime_map_id": str(snapshot.get("runtime_map_id", "")),
			"policy": VALIDATION_STRICT_V2,
			"legacy_used": false,
			"details": {
				"position_converter_valid": position_converter_valid,
				"delta_converter_valid": delta_converter_valid,
			},
		}
	if policy == VALIDATION_EXPLICIT_LEGACY_COMPAT:
		if not has_legacy_base_contract(snapshot):
			return {
				"valid": false,
				"reason": "legacy_base_contract_missing",
				"schema_version": int(snapshot.get("schema_version", 0)),
				"coordinate_space": str(snapshot.get("coordinate_space", "")),
				"runtime_map_id": str(snapshot.get("runtime_map_id", "")),
				"policy": VALIDATION_EXPLICIT_LEGACY_COMPAT,
				"legacy_used": false,
				"details": {},
			}
		var interpretation := str(
			expected_context.get("legacy_coordinate_interpretation", "")
		)
		var consumer_name := str(
			expected_context.get("consumer_name", "")
		)
		var migration_reason := str(
			expected_context.get("migration_reason", "")
		)
		if (
			interpretation.is_empty()
			or consumer_name.is_empty()
			or migration_reason.is_empty()
		):
			return {
				"valid": false,
				"reason": "legacy_context_required",
				"schema_version": int(snapshot.get("schema_version", 0)),
				"coordinate_space": str(snapshot.get("coordinate_space", "")),
				"runtime_map_id": str(snapshot.get("runtime_map_id", "")),
				"policy": VALIDATION_EXPLICIT_LEGACY_COMPAT,
				"legacy_used": false,
				"details": {},
			}
		var legacy_strict := validate(
			snapshot,
			{"allow_legacy_v1": true}
		)
		if not bool(legacy_strict.get("valid", false)):
			return {
				"valid": false,
				"reason": str(
					legacy_strict.get("reason", "legacy_snapshot_invalid")
				),
				"schema_version": int(snapshot.get("schema_version", 0)),
				"coordinate_space": str(snapshot.get("coordinate_space", "")),
				"runtime_map_id": str(snapshot.get("runtime_map_id", "")),
				"policy": VALIDATION_EXPLICIT_LEGACY_COMPAT,
				"legacy_used": false,
				"details": {},
			}
		legacy_snapshot_validation_count += 1
		return {
			"valid": true,
			"reason": "",
			"schema_version": int(snapshot.get("schema_version", 1)),
			"coordinate_space": str(snapshot.get("coordinate_space", "")),
			"runtime_map_id": str(snapshot.get("runtime_map_id", "")),
			"policy": VALIDATION_EXPLICIT_LEGACY_COMPAT,
			"legacy_used": true,
			"details": {
				"legacy_consumer": consumer_name,
				"legacy_reason": migration_reason,
				"legacy_coordinate_interpretation": interpretation,
			},
		}
	return {
		"valid": false,
		"reason": "unsupported_validation_policy",
		"schema_version": 0,
		"coordinate_space": "",
		"runtime_map_id": "",
		"policy": str(policy),
		"legacy_used": false,
		"details": {},
	}


static func validation_diagnostics(result: Dictionary) -> Dictionary:
	return {
		"consumer": str(result.get("details", {}).get("legacy_consumer", "")),
		"policy": str(result.get("policy", "")),
		"valid": bool(result.get("valid", false)),
		"reason": str(result.get("reason", "")),
		"schema_version": int(result.get("schema_version", 0)),
		"coordinate_space": str(result.get("coordinate_space", "")),
		"snapshot_runtime_map_id": str(result.get("runtime_map_id", "")),
		"expected_runtime_map_id": str(
			result.get("details", {}).get("expected_runtime_map_id", "")
		),
		"legacy_used": bool(result.get("legacy_used", false)),
		"projection_origin_present": bool(
			result.get("details", {}).get("projection_origin_present", false)
		),
		"position_converter_valid": bool(
			result.get("details", {}).get("position_converter_valid", false)
		),
		"delta_converter_valid": bool(
			result.get("details", {}).get("delta_converter_valid", false)
		),
	}


static func validate(
	snapshot: Dictionary,
	expected_context := {}
) -> Dictionary:
	var problems: Array[String] = []
	var schema_version := int(snapshot.get("schema_version", LEGACY_SCHEMA_VERSION))
	if schema_version not in [LEGACY_SCHEMA_VERSION, SCHEMA_VERSION]:
		problems.append("unsupported_schema_version")
	var coordinate_space := str(snapshot.get("coordinate_space", ""))
	if coordinate_space.is_empty():
		problems.append("missing_coordinate_space")
	elif coordinate_space == COORDINATE_SPACE_LEGACY_GROUND_GU:
		if not bool(expected_context.get("allow_legacy_v1", false)):
			problems.append("legacy_ambiguous_coordinate_space")
	elif coordinate_space not in SUPPORTED_COORDINATE_SPACES:
		problems.append("invalid_coordinate_space")
	var shape_type := str(snapshot.get("shape_type", ""))
	if shape_type not in SUPPORTED_SHAPE_TYPES:
		problems.append("invalid_shape_kind")
	if str(snapshot.get("skill_id", "")).is_empty():
		problems.append("missing_skill_id")
	for length_key: String in [
		"effect_length_gu",
		"effect_width_gu",
		"axis_screen_length_px",
	]:
		var value := float(snapshot.get(length_key, 0.0))
		if not is_finite(value) or value < 0.0:
			problems.append("invalid_%s" % length_key)
	for vector_key: String in [
		"origin_ground_gu",
		"projection_origin_ground_gu",
		"direction_ground_gu",
		"axis_screen_offset_px",
		"axis_screen_direction_px",
		"start_ground_gu",
		"end_ground_gu",
	]:
		if snapshot.has(vector_key) and not _vector2_is_finite(
			snapshot.get(vector_key, Vector2.ZERO) as Vector2
		):
			problems.append("non_finite_%s" % vector_key)
	for polygon_key: String in [
		"polygon_ground_gu",
		"polygon_screen_offset_px",
	]:
		if snapshot.has(polygon_key) and not _polygon_is_finite(
			snapshot.get(polygon_key, PackedVector2Array())
		):
			problems.append("non_finite_%s" % polygon_key)
	if coordinate_space == COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU:
		var snapshot_map_id: Variant = snapshot.get("runtime_map_id", -1)
		if (
			not snapshot_map_id is int
			or int(snapshot_map_id) < 0
		):
			problems.append("absolute_missing_runtime_map_id")
		var projection_origin: Variant = snapshot.get(
			"projection_origin_ground_gu", Vector2.INF
		)
		if (
			not projection_origin is Vector2
			or (projection_origin as Vector2) == Vector2.INF
			or not _vector2_is_finite(projection_origin as Vector2)
		):
			problems.append("absolute_missing_projection_origin")
		var expected_map_id: Variant = expected_context.get(
			"expected_runtime_map_id", -1
		)
		if expected_map_id is int and int(expected_map_id) >= 0:
			if (
				not snapshot_map_id is int
				or int(snapshot_map_id) != int(expected_map_id)
			):
				problems.append("runtime_map_id_mismatch")
		elif not expected_map_id is int:
			problems.append("runtime_map_id_type_mismatch")
	elif coordinate_space == COORDINATE_SPACE_LOCAL_GROUND_DELTA_GU:
		var origin: Variant = snapshot.get("origin_ground_gu", Vector2.ZERO)
		if (
			origin is Vector2
			and (origin as Vector2) != Vector2.ZERO
		):
			problems.append("local_delta_must_have_zero_origin")
	var axis_direction: Variant = snapshot.get(
		"axis_screen_direction_px", Vector2.ZERO
	)
	if (
		axis_direction is Vector2
		and (axis_direction as Vector2).length_squared() > 0.000001
		and not _vector2_is_finite(axis_direction as Vector2)
	):
		problems.append("non_finite_axis_screen_direction_px")
	if problems.is_empty():
		return {
			"valid": true,
			"reason": "",
			"details": {
				"schema_version": schema_version,
				"coordinate_space": coordinate_space,
				"shape_type": shape_type,
			},
		}
	return {
		"valid": false,
		"reason": ";".join(problems),
		"details": {
			"schema_version": schema_version,
			"coordinate_space": coordinate_space,
			"shape_type": shape_type,
			"problems": problems.duplicate(),
		},
	}


static func upgrade_legacy_snapshot(
	snapshot: Dictionary,
	explicit_context: Dictionary
) -> Dictionary:
	var coordinate_space := str(
		explicit_context.get("coordinate_space", "")
	)
	if coordinate_space not in SUPPORTED_COORDINATE_SPACES:
		return {}
	if coordinate_space == COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU:
		if normalize_runtime_map_id(
			explicit_context.get("runtime_map_id", -1)
		) < 0:
			return {}
		var projection_origin: Variant = explicit_context.get(
			"projection_origin_ground_gu", Vector2.INF
		)
		if (
			not projection_origin is Vector2
			or (projection_origin as Vector2) == Vector2.INF
		):
			return {}
		var converter: Variant = explicit_context.get(
			"ground_position_gu_to_screen_position_px",
			Callable()
		)
		if not converter is Callable or not (converter as Callable).is_valid():
			return {}
	var upgraded := snapshot.duplicate(true)
	var coordinate_fields := _coordinate_fields_from_context(explicit_context)
	coordinate_fields["created_by"] = "legacy_upgrade"
	coordinate_fields["migration_source"] = "legacy_v1"
	upgraded.merge(coordinate_fields, true)
	if (
		coordinate_space == COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU
	):
		upgraded["origin_ground_gu"] = explicit_context.get(
			"origin_ground_gu",
			snapshot.get("origin_ground_gu", Vector2.ZERO)
		)
	else:
		upgraded["origin_ground_gu"] = Vector2.ZERO
	var raw_polygon: Variant = upgraded.get(
		"polygon_ground_gu", PackedVector2Array()
	)
	if raw_polygon is PackedVector2Array:
		var polygon := raw_polygon as PackedVector2Array
		var origin_ground_gu := Vector2.ZERO
		if coordinate_space == COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU:
			origin_ground_gu = (
				upgraded.get("origin_ground_gu", Vector2.ZERO) as Vector2
			)
		upgraded["polygon_screen_offset_px"] = (
			project_ground_polygon_to_screen_offsets_px(
				polygon,
				origin_ground_gu,
				explicit_context
			)
		)
		var raw_polygons: Variant = upgraded.get(
			"polygons_ground_gu", []
		)
		var polygons_screen_offset_px: Array[PackedVector2Array] = []
		if raw_polygons is Array:
			for raw_item: Variant in raw_polygons:
				if raw_item is PackedVector2Array:
					polygons_screen_offset_px.append(
						project_ground_polygon_to_screen_offsets_px(
							raw_item as PackedVector2Array,
							origin_ground_gu,
							explicit_context
						)
					)
		if not polygons_screen_offset_px.is_empty():
			upgraded["polygons_screen_offset_px"] = polygons_screen_offset_px
	upgraded["damage_space"] = coordinate_space
	upgraded.make_read_only()
	return upgraded


static func diagnostics(snapshot: Dictionary) -> Dictionary:
	var validation := validate(snapshot, {"allow_legacy_v1": true})
	return {
		"schema_version": int(snapshot.get("schema_version", 1)),
		"snapshot_id": str(snapshot.get("snapshot_id", "")),
		"coordinate_space": str(snapshot.get("coordinate_space", "")),
		"runtime_map_id": str(snapshot.get("runtime_map_id", "")),
		"origin_ground_gu": snapshot.get("origin_ground_gu", Vector2.ZERO),
		"projection_origin_ground_gu": snapshot.get(
			"projection_origin_ground_gu", Vector2.ZERO
		),
		"axis_screen_length_px": float(
			snapshot.get("axis_screen_length_px", 0.0)
		),
		"valid": bool(validation.get("valid", false)),
		"validation_reason": str(validation.get("reason", "")),
	}


static func _vector2_is_finite(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


static func _polygon_is_finite(polygon: PackedVector2Array) -> bool:
	for point: Vector2 in polygon:
		if not _vector2_is_finite(point):
			return false
	return true


static func ground_polygon_gu(snapshot: Dictionary) -> PackedVector2Array:
	if not has_legacy_base_contract(snapshot):
		return PackedVector2Array()
	var raw_polygon: Variant = snapshot.get(
		"polygon_ground_gu", PackedVector2Array()
	)
	return (
		(raw_polygon as PackedVector2Array).duplicate()
		if raw_polygon is PackedVector2Array
		else PackedVector2Array()
	)


## R3X-1: derive the broadphase envelope only from authoritative ground-GU
## geometry. Screen-space visual bounds are intentionally never consulted.
static func ground_aabb(snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty():
		return _ground_aabb_failure("snapshot_missing")
	if not has_legacy_base_contract(snapshot):
		return _ground_aabb_failure("contract_invalid")
	var shape_type := str(snapshot.get("shape_type", ""))
	if shape_type not in SUPPORTED_SHAPE_TYPES:
		return _ground_aabb_failure("shape_type_invalid")
	if shape_type == SHAPE_CELL_UNION:
		return _ground_aabb_cell_union(snapshot)
	if shape_type == SHAPE_CIRCLE and (
		snapshot.has("center_ground_gu")
		or snapshot.has("radius_gu")
	):
		if not snapshot.has("center_ground_gu") or not snapshot.has("radius_gu"):
			return _ground_aabb_failure("circle_fields_incomplete")
		var raw_center: Variant = snapshot.get("center_ground_gu", null)
		var raw_radius: Variant = snapshot.get("radius_gu", null)
		if (
			not raw_center is Vector2
			or not _vector2_is_finite(raw_center as Vector2)
			or (not raw_radius is int and not raw_radius is float)
		):
			return _ground_aabb_failure("circle_fields_invalid")
		var radius_gu := float(raw_radius)
		if not is_finite(radius_gu) or radius_gu < 0.0:
			return _ground_aabb_failure("circle_radius_invalid")
		var center_ground_gu: Vector2 = raw_center
		return _ground_aabb_from_min_max(
			center_ground_gu - Vector2.ONE * radius_gu,
			center_ground_gu + Vector2.ONE * radius_gu,
		)
	return _ground_aabb_from_polygon_value(
		snapshot.get("polygon_ground_gu", null)
	)


static func _ground_aabb_cell_union(snapshot: Dictionary) -> Dictionary:
	var raw_polygons: Variant = snapshot.get("polygons_ground_gu", null)
	if raw_polygons is Array and not (raw_polygons as Array).is_empty():
		var min_ground_gu := Vector2(INF, INF)
		var max_ground_gu := Vector2(-INF, -INF)
		for raw_polygon: Variant in raw_polygons as Array:
			if not raw_polygon is PackedVector2Array:
				return _ground_aabb_failure("cell_union_polygon_invalid")
			var polygon: PackedVector2Array = raw_polygon
			if polygon.size() < 3 or not _polygon_is_finite(polygon):
				return _ground_aabb_failure("cell_union_polygon_invalid")
			for point_ground_gu: Vector2 in polygon:
				min_ground_gu = min_ground_gu.min(point_ground_gu)
				max_ground_gu = max_ground_gu.max(point_ground_gu)
		return _ground_aabb_from_min_max(min_ground_gu, max_ground_gu)
	if raw_polygons != null and not raw_polygons is Array:
		return _ground_aabb_failure("cell_union_polygons_invalid")
	var raw_cells: Variant = snapshot.get("geometry_cells_grid_steps", null)
	if not raw_cells is Array or (raw_cells as Array).is_empty():
		return _ground_aabb_failure("cell_union_geometry_missing")
	var min_ground_gu := Vector2(INF, INF)
	var max_ground_gu := Vector2(-INF, -INF)
	for raw_cell: Variant in raw_cells as Array:
		if not raw_cell is Vector2i:
			return _ground_aabb_failure("cell_union_cell_invalid")
		var center_ground_gu := Vector2(raw_cell as Vector2i)
		min_ground_gu = min_ground_gu.min(
			center_ground_gu - Vector2.ONE * 0.5
		)
		max_ground_gu = max_ground_gu.max(
			center_ground_gu + Vector2.ONE * 0.5
		)
	return _ground_aabb_from_min_max(min_ground_gu, max_ground_gu)


static func _ground_aabb_from_polygon_value(raw_polygon: Variant) -> Dictionary:
	if not raw_polygon is PackedVector2Array:
		return _ground_aabb_failure("polygon_missing")
	var polygon: PackedVector2Array = raw_polygon
	if polygon.size() < 3 or not _polygon_is_finite(polygon):
		return _ground_aabb_failure("polygon_invalid")
	var min_ground_gu := polygon[0]
	var max_ground_gu := polygon[0]
	for point_ground_gu: Vector2 in polygon:
		min_ground_gu = min_ground_gu.min(point_ground_gu)
		max_ground_gu = max_ground_gu.max(point_ground_gu)
	return _ground_aabb_from_min_max(min_ground_gu, max_ground_gu)


static func _ground_aabb_from_min_max(
	min_ground_gu: Vector2,
	max_ground_gu: Vector2
) -> Dictionary:
	if (
		not _vector2_is_finite(min_ground_gu)
		or not _vector2_is_finite(max_ground_gu)
		or min_ground_gu.x > max_ground_gu.x
		or min_ground_gu.y > max_ground_gu.y
	):
		return _ground_aabb_failure("aabb_non_finite")
	return {
		"valid": true,
		"bounds_ground_gu": Rect2(
			min_ground_gu,
			max_ground_gu - min_ground_gu
		),
		"reason": "",
	}


static func _ground_aabb_failure(reason: String) -> Dictionary:
	return {
		"valid": false,
		"bounds_ground_gu": Rect2(),
		"reason": reason,
	}


static func ground_polygons_gu(
	snapshot: Dictionary
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not has_legacy_base_contract(snapshot):
		return result
	var raw_polygons: Variant = snapshot.get("polygons_ground_gu", [])
	if raw_polygons is Array:
		for raw_polygon: Variant in raw_polygons:
			if raw_polygon is PackedVector2Array:
				result.append((raw_polygon as PackedVector2Array).duplicate())
	if result.is_empty():
		var polygon_ground_gu := ground_polygon_gu(snapshot)
		if not polygon_ground_gu.is_empty():
			result.append(polygon_ground_gu)
	return result


static func projected_polygon_screen_offset_px(
	snapshot: Dictionary
) -> PackedVector2Array:
	if not has_legacy_base_contract(snapshot):
		return PackedVector2Array()
	var raw_polygon: Variant = snapshot.get(
		"polygon_screen_offset_px", PackedVector2Array()
	)
	return (
		(raw_polygon as PackedVector2Array).duplicate()
		if raw_polygon is PackedVector2Array
		else PackedVector2Array()
	)


static func projected_polygons_screen_offset_px(
	snapshot: Dictionary
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not has_legacy_base_contract(snapshot):
		return result
	var raw_polygons: Variant = snapshot.get(
		"polygons_screen_offset_px", []
	)
	if raw_polygons is Array:
		for raw_polygon: Variant in raw_polygons:
			if raw_polygon is PackedVector2Array:
				result.append((raw_polygon as PackedVector2Array).duplicate())
	if result.is_empty():
		var polygon_screen_offset_px := (
			projected_polygon_screen_offset_px(snapshot)
		)
		if not polygon_screen_offset_px.is_empty():
			result.append(polygon_screen_offset_px)
	return result


static func projected_polygon_screen_px(
	snapshot: Dictionary,
	origin_screen_px: Vector2
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for offset_px: Vector2 in projected_polygon_screen_offset_px(snapshot):
		result.append(origin_screen_px + offset_px)
	return result


static func intersects_target_polygon_ground_gu(
	snapshot: Dictionary,
	target_polygon_ground_gu: PackedVector2Array
) -> bool:
	if target_polygon_ground_gu.size() < 3:
		return false
	for footprint_polygon_ground_gu: PackedVector2Array in (
		ground_polygons_gu(snapshot)
	):
		if (
			footprint_polygon_ground_gu.size() >= 3
			and convex_polygons_intersect_inclusive_ground_gu(
				footprint_polygon_ground_gu,
				target_polygon_ground_gu
			)
		):
			return true
	return false


static func intersects_target_combat_footprint_ground_gu(
	snapshot: Dictionary,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float
) -> bool:
	if not has_legacy_base_contract(snapshot):
		return false
	var safe_target_radius_gu := maxf(0.0, target_combat_radius_gu)
	if str(snapshot.get("shape_type", "")) == SHAPE_SWEPT_CAPSULE_PATH:
		return _swept_segment_intersects_circle_inclusive_ground_gu(
			snapshot.get("segment_start_ground_gu", Vector2.ZERO),
			snapshot.get("segment_end_ground_gu", Vector2.ZERO),
			target_center_ground_gu,
			float(snapshot.get("path_radius_gu", 0.0))
			+ safe_target_radius_gu
		)
	if str(snapshot.get("shape_type", "")) == SHAPE_CIRCLE:
		return _circles_intersect_inclusive_ground_gu(
			snapshot.get("center_ground_gu", Vector2.ZERO),
			float(snapshot.get("radius_gu", 0.0)),
			target_center_ground_gu,
			safe_target_radius_gu
		)
	if str(snapshot.get("shape_type", "")) == SHAPE_TARGET_FOOTPRINT:
		return _circles_intersect_inclusive_ground_gu(
			snapshot.get("target_center_ground_gu", Vector2.ZERO),
			float(snapshot.get("target_combat_radius_gu", 0.0)),
			target_center_ground_gu,
			safe_target_radius_gu
		)
	if str(snapshot.get("shape_type", "")) == SHAPE_DIRECTED_RECTANGLE:
		return _directed_rectangle_intersects_circle_inclusive_ground_gu(
			snapshot,
			target_center_ground_gu,
			safe_target_radius_gu
		)
	if str(snapshot.get("shape_type", "")) == SHAPE_SECTOR_ARC:
		return _sector_intersects_circle_inclusive_ground_gu(
			snapshot,
			target_center_ground_gu,
			safe_target_radius_gu
		)
	if str(snapshot.get("shape_type", "")) == SHAPE_CELL_UNION:
		return _cell_union_intersects_circle_inclusive_ground_gu(
			snapshot,
			target_center_ground_gu,
			safe_target_radius_gu
		)
	var target_polygon_ground_gu := PackedVector2Array()
	for offset_ground_gu: Vector2 in (
		WorldSpatialRulesScript.actor_footprint_ground_polygon_gu(
			safe_target_radius_gu
		)
	):
		target_polygon_ground_gu.append(
			target_center_ground_gu + offset_ground_gu
		)
	return intersects_target_polygon_ground_gu(
		snapshot,
		target_polygon_ground_gu
	)


static func convex_polygons_intersect_inclusive_ground_gu(
	left_polygon_ground_gu: PackedVector2Array,
	right_polygon_ground_gu: PackedVector2Array
) -> bool:
	if left_polygon_ground_gu.size() < 3 or right_polygon_ground_gu.size() < 3:
		return false
	for polygon_ground_gu: PackedVector2Array in [
		left_polygon_ground_gu,
		right_polygon_ground_gu,
	]:
		for index: int in range(polygon_ground_gu.size()):
			var edge_ground_gu := (
				polygon_ground_gu[(index + 1) % polygon_ground_gu.size()]
				- polygon_ground_gu[index]
			)
			if (
				edge_ground_gu.length_squared()
				<= CONTACT_EPSILON_GU * CONTACT_EPSILON_GU
			):
				continue
			var axis_ground_gu := Vector2(
				-edge_ground_gu.y, edge_ground_gu.x
			).normalized()
			var left_projection_gu := _project_polygon(
				left_polygon_ground_gu, axis_ground_gu
			)
			var right_projection_gu := _project_polygon(
				right_polygon_ground_gu, axis_ground_gu
			)
			if (
				left_projection_gu.y
				< right_projection_gu.x - CONTACT_EPSILON_GU
				or right_projection_gu.y
				< left_projection_gu.x - CONTACT_EPSILON_GU
			):
				return false
	return true


static func shape_classification(shape_type: String) -> Dictionary:
	var classification := {
		"shape_type": shape_type,
		"supported_by_projection_api": shape_type in SUPPORTED_SHAPE_TYPES,
		"damage_space": "ground_gu",
		"screen_px_damage_allowed": false,
		"snapshot_builder_available": shape_type in SUPPORTED_SHAPE_TYPES,
	}
	classification.make_read_only()
	return classification


static func _create_polygon_snapshot(
	skill_id: String,
	release_id: String,
	shape_type: String,
	shape_contract_id: String,
	origin_ground_gu: Vector2,
	polygon_ground_gu: PackedVector2Array,
	extra_fields: Dictionary,
	coordinate_context := {}
) -> Dictionary:
	var coordinate_fields := _coordinate_fields_from_context(
		coordinate_context
	)
	var effective_origin_ground_gu := origin_ground_gu
	if (
		str(coordinate_fields.get("coordinate_space", ""))
		== COORDINATE_SPACE_LOCAL_GROUND_DELTA_GU
	):
		effective_origin_ground_gu = Vector2.ZERO
	var polygon_screen_offset_px := project_ground_polygon_to_screen_offsets_px(
		polygon_ground_gu,
		origin_ground_gu,
		coordinate_context
	)
	var snapshot := {
		"contract_id": CONTRACT_ID,
		"shape_contract_id": shape_contract_id,
		"projection_api_contract_id": PROJECTION_API_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"projection_contract_id": GroundUnitSpaceScript.PROJECTION_CONTRACT_ID,
		"snapshot_id": "%s:%s" % [skill_id, release_id],
		"skill_id": skill_id,
		"release_id": release_id,
		"shape_type": shape_type,
		"origin_ground_gu": effective_origin_ground_gu,
		"polygon_ground_gu": polygon_ground_gu,
		"polygon_screen_offset_px": polygon_screen_offset_px,
		"damage_space": str(
			coordinate_fields.get("coordinate_space", "ground_gu")
		),
		"visual_space": "screen_px_derived_only",
	}
	var polygons_ground_gu: Array[PackedVector2Array] = [polygon_ground_gu]
	var polygons_screen_offset_px: Array[PackedVector2Array] = [
		polygon_screen_offset_px
	]
	polygons_ground_gu.make_read_only()
	polygons_screen_offset_px.make_read_only()
	snapshot["polygons_ground_gu"] = polygons_ground_gu
	snapshot["polygons_screen_offset_px"] = polygons_screen_offset_px
	snapshot.merge(coordinate_fields, true)
	snapshot.merge(extra_fields, true)
	snapshot.make_read_only()
	return snapshot


static func _circle_polygon_ground_gu(
	center_ground_gu: Vector2,
	radius_gu: float,
	segments: int
) -> PackedVector2Array:
	var polygon_ground_gu := PackedVector2Array()
	var safe_segments := maxi(8, segments)
	for index: int in range(safe_segments):
		var angle_radians := TAU * float(index) / float(safe_segments)
		polygon_ground_gu.append(
			center_ground_gu
			+ Vector2.from_angle(angle_radians) * radius_gu
		)
	return polygon_ground_gu


static func _normalized_direction_ground_gu(
	direction_ground_gu: Vector2
) -> Vector2:
	if (
		direction_ground_gu.length_squared()
		<= CONTACT_EPSILON_GU * CONTACT_EPSILON_GU
	):
		return Vector2(1.0, 1.0).normalized()
	return direction_ground_gu.normalized()


static func _swept_segment_intersects_circle_inclusive_ground_gu(
	segment_start_ground_gu: Vector2,
	segment_end_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	combined_radius_gu: float
) -> bool:
	var start_relative_gu := (
		segment_start_ground_gu - target_center_ground_gu
	)
	var segment_ground_gu := (
		segment_end_ground_gu - segment_start_ground_gu
	)
	var closest_relative_gu := start_relative_gu
	if (
		segment_ground_gu.length_squared()
		> CONTACT_EPSILON_GU * CONTACT_EPSILON_GU
	):
		var weight := clampf(
			-start_relative_gu.dot(segment_ground_gu)
			/ segment_ground_gu.length_squared(),
			0.0,
			1.0
		)
		closest_relative_gu += segment_ground_gu * weight
	var inclusive_radius_gu := (
		maxf(0.0, combined_radius_gu) + CONTACT_EPSILON_GU
	)
	return (
		closest_relative_gu.length_squared()
		<= inclusive_radius_gu * inclusive_radius_gu
	)


static func _circles_intersect_inclusive_ground_gu(
	left_center_ground_gu: Vector2,
	left_radius_gu: float,
	right_center_ground_gu: Vector2,
	right_radius_gu: float
) -> bool:
	var inclusive_radius_gu := (
		maxf(0.0, left_radius_gu)
		+ maxf(0.0, right_radius_gu)
		+ CONTACT_EPSILON_GU
	)
	return (
		left_center_ground_gu.distance_squared_to(right_center_ground_gu)
		<= inclusive_radius_gu * inclusive_radius_gu
	)


static func _directed_rectangle_intersects_circle_inclusive_ground_gu(
	snapshot: Dictionary,
	target_center_ground_gu: Vector2,
	target_radius_gu: float
) -> bool:
	var start_ground_gu: Vector2 = snapshot.get(
		"start_ground_gu", snapshot.get("origin_ground_gu", Vector2.ZERO)
	)
	var direction_ground_gu := _normalized_direction_ground_gu(
		snapshot.get("direction_ground_gu", Vector2.ZERO)
	)
	var perpendicular_ground_gu: Vector2 = snapshot.get(
		"perpendicular_ground_gu",
		Vector2(-direction_ground_gu.y, direction_ground_gu.x)
	)
	var relative_ground_gu := target_center_ground_gu - start_ground_gu
	var closest_ground_gu := (
		start_ground_gu
		+ direction_ground_gu * clampf(
			relative_ground_gu.dot(direction_ground_gu),
			0.0,
			maxf(0.0, float(snapshot.get("effect_length_gu", 0.0)))
		)
		+ perpendicular_ground_gu * clampf(
			relative_ground_gu.dot(perpendicular_ground_gu),
			-maxf(0.0, float(snapshot.get("half_width_gu", 0.0))),
			maxf(0.0, float(snapshot.get("half_width_gu", 0.0)))
		)
	)
	var inclusive_radius_gu := maxf(0.0, target_radius_gu) + CONTACT_EPSILON_GU
	return (
		closest_ground_gu.distance_squared_to(target_center_ground_gu)
		<= inclusive_radius_gu * inclusive_radius_gu
	)


static func _sector_intersects_circle_inclusive_ground_gu(
	snapshot: Dictionary,
	target_center_ground_gu: Vector2,
	target_radius_gu: float
) -> bool:
	var origin_ground_gu: Vector2 = snapshot.get(
		"origin_ground_gu", Vector2.ZERO
	)
	var direction_ground_gu := _normalized_direction_ground_gu(
		snapshot.get("direction_ground_gu", Vector2.ZERO)
	)
	var radius_gu := maxf(0.0, float(snapshot.get("radius_gu", 0.0)))
	var half_angle_radians := clampf(
		absf(float(snapshot.get("half_angle_radians", 0.0))),
		0.0,
		PI * 0.5
	)
	var safe_target_radius_gu := maxf(0.0, target_radius_gu)
	var relative_ground_gu := target_center_ground_gu - origin_ground_gu
	var distance_gu := relative_ground_gu.length()
	if distance_gu <= safe_target_radius_gu + CONTACT_EPSILON_GU:
		return true
	if distance_gu > radius_gu + safe_target_radius_gu + CONTACT_EPSILON_GU:
		return false
	var angle_delta_radians := absf(wrapf(
		relative_ground_gu.angle() - direction_ground_gu.angle(),
		-PI,
		PI
	))
	if angle_delta_radians <= half_angle_radians + CONTACT_EPSILON_GU:
		return true
	var left_edge_end_ground_gu := (
		origin_ground_gu
		+ direction_ground_gu.rotated(-half_angle_radians) * radius_gu
	)
	var right_edge_end_ground_gu := (
		origin_ground_gu
		+ direction_ground_gu.rotated(half_angle_radians) * radius_gu
	)
	var inclusive_radius_squared_gu := pow(
		safe_target_radius_gu + CONTACT_EPSILON_GU,
		2.0
	)
	return (
		_point_segment_distance_squared_ground_gu(
			target_center_ground_gu,
			origin_ground_gu,
			left_edge_end_ground_gu
		) <= inclusive_radius_squared_gu
		or _point_segment_distance_squared_ground_gu(
			target_center_ground_gu,
			origin_ground_gu,
			right_edge_end_ground_gu
		) <= inclusive_radius_squared_gu
	)


static func _cell_union_intersects_circle_inclusive_ground_gu(
	snapshot: Dictionary,
	target_center_ground_gu: Vector2,
	target_radius_gu: float
) -> bool:
	var raw_cells: Variant = snapshot.get("geometry_cells_grid_steps", [])
	if not raw_cells is Array:
		return false
	var inclusive_radius_gu := maxf(0.0, target_radius_gu) + CONTACT_EPSILON_GU
	var inclusive_radius_squared_gu := inclusive_radius_gu * inclusive_radius_gu
	for raw_cell: Variant in raw_cells:
		if not raw_cell is Vector2i:
			continue
		var delta_ground_gu := target_center_ground_gu - Vector2(raw_cell)
		var nearest_delta_ground_gu := Vector2(
			maxf(absf(delta_ground_gu.x) - 0.5, 0.0),
			maxf(absf(delta_ground_gu.y) - 0.5, 0.0)
		)
		if nearest_delta_ground_gu.length_squared() <= inclusive_radius_squared_gu:
			return true
	return false


static func _point_segment_distance_squared_ground_gu(
	point_ground_gu: Vector2,
	segment_start_ground_gu: Vector2,
	segment_end_ground_gu: Vector2
) -> float:
	var segment_ground_gu := (
		segment_end_ground_gu - segment_start_ground_gu
	)
	if (
		segment_ground_gu.length_squared()
		<= CONTACT_EPSILON_GU * CONTACT_EPSILON_GU
	):
		return point_ground_gu.distance_squared_to(segment_start_ground_gu)
	var weight := clampf(
		(point_ground_gu - segment_start_ground_gu).dot(segment_ground_gu)
		/ segment_ground_gu.length_squared(),
		0.0,
		1.0
	)
	return point_ground_gu.distance_squared_to(
		segment_start_ground_gu + segment_ground_gu * weight
	)


static func _polygon_projection_extent_px(
	polygon_screen_offset_px: PackedVector2Array,
	axis_screen_px: Vector2
) -> float:
	if (
		polygon_screen_offset_px.is_empty()
		or axis_screen_px.length_squared() <= 0.000001
	):
		return 0.0
	var interval_px := _project_polygon(
		polygon_screen_offset_px,
		axis_screen_px.normalized()
	)
	return maxf(0.0, interval_px.y - interval_px.x)


static func _project_polygon(
	polygon: PackedVector2Array,
	axis: Vector2
) -> Vector2:
	var minimum := polygon[0].dot(axis)
	var maximum := minimum
	for index: int in range(1, polygon.size()):
		var projected := polygon[index].dot(axis)
		minimum = minf(minimum, projected)
		maximum = maxf(maximum, projected)
	return Vector2(minimum, maximum)
