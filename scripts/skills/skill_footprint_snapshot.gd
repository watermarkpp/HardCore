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
	laser_projection_policy := ""
) -> Dictionary:
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
		origin_ground_gu
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
		"origin_ground_gu": origin_ground_gu,
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
		"damage_space": "ground_gu",
		"visual_space": "screen_px_derived_only",
	}
	snapshot.make_read_only()
	return snapshot


static func create_sector_arc(
	skill_id: String,
	release_id: String,
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	radius_gu: float,
	half_angle_radians: float,
	arc_segments := DEFAULT_CURVE_SEGMENTS
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
		}
	)


static func create_circle(
	skill_id: String,
	release_id: String,
	center_ground_gu: Vector2,
	radius_gu: float,
	segments := DEFAULT_CURVE_SEGMENTS
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
		}
	)


static func create_swept_capsule_path(
	skill_id: String,
	release_id: String,
	segment_start_ground_gu: Vector2,
	segment_end_ground_gu: Vector2,
	path_radius_gu: float,
	cap_segments := DEFAULT_CURVE_SEGMENTS / 2,
	parent_snapshot_id := "",
	segment_index := -1
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
		}
	)


static func create_target_footprint(
	skill_id: String,
	release_id: String,
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	target_instance_id := 0
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
		}
	)


static func create_cell_union(
	skill_id: String,
	release_id: String,
	origin_ground_gu: Vector2,
	geometry_cells_grid_steps: Array[Vector2i]
) -> Dictionary:
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
				origin_ground_gu
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
		"origin_ground_gu": origin_ground_gu,
		"geometry_cells_grid_steps": copied_cells_grid_steps,
		"polygons_ground_gu": polygons_ground_gu,
		"polygons_screen_offset_px": polygons_screen_offset_px,
		"polygon_ground_gu": first_polygon_ground_gu,
		"polygon_screen_offset_px": first_polygon_screen_offset_px,
		"effect_length_gu": 0.0,
		"effect_width_gu": 0.0,
		"damage_space": "ground_gu",
		"visual_space": "screen_px_derived_only",
	}
	snapshot.make_read_only()
	return snapshot


static func is_valid(snapshot: Dictionary) -> bool:
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


static func ground_polygon_gu(snapshot: Dictionary) -> PackedVector2Array:
	if not is_valid(snapshot):
		return PackedVector2Array()
	var raw_polygon: Variant = snapshot.get(
		"polygon_ground_gu", PackedVector2Array()
	)
	return (
		(raw_polygon as PackedVector2Array).duplicate()
		if raw_polygon is PackedVector2Array
		else PackedVector2Array()
	)


static func ground_polygons_gu(
	snapshot: Dictionary
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not is_valid(snapshot):
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
	if not is_valid(snapshot):
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
	if not is_valid(snapshot):
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


static func project_ground_polygon_to_screen_offsets_px(
	polygon_ground_gu: PackedVector2Array,
	origin_ground_gu: Vector2
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point_ground_gu: Vector2 in polygon_ground_gu:
		result.append(
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				point_ground_gu - origin_ground_gu
			)
		)
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
	if not is_valid(snapshot):
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
	extra_fields: Dictionary
) -> Dictionary:
	var polygon_screen_offset_px := project_ground_polygon_to_screen_offsets_px(
		polygon_ground_gu,
		origin_ground_gu
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
		"origin_ground_gu": origin_ground_gu,
		"polygon_ground_gu": polygon_ground_gu,
		"polygon_screen_offset_px": polygon_screen_offset_px,
		"damage_space": "ground_gu",
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
