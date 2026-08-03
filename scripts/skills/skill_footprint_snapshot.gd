class_name SkillFootprintSnapshot
extends RefCounted

## Immutable release-time geometry shared by gameplay hit resolution, projected
## presentation and regression tests. Gameplay owns only ground-GU values; PX
## values are a one-way projection derived from the same ground polygon.

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const CONTRACT_ID := "skills.footprint_snapshot.ground_gu_projection.v1"
const DIRECTED_RECTANGLE_CONTRACT_ID := (
	"skills.footprint_snapshot.directed_rectangle.v1"
)
const PROJECTION_API_CONTRACT_ID := (
	"skills.footprint_snapshot.projection.iso_64x32.v1"
)

const SHAPE_DIRECTED_RECTANGLE := "directed_rectangle"
const SHAPE_SECTOR_ARC := "sector_arc"
const SHAPE_CIRCLE := "circle"
const SHAPE_SWEPT_CAPSULE_PATH := "swept_capsule_path"
const SHAPE_TARGET_FOOTPRINT := "target_footprint"
const SUPPORTED_SHAPE_TYPES: Array[String] = [
	SHAPE_DIRECTED_RECTANGLE,
	SHAPE_SECTOR_ARC,
	SHAPE_CIRCLE,
	SHAPE_SWEPT_CAPSULE_PATH,
	SHAPE_TARGET_FOOTPRINT,
]

const CONTACT_EPSILON_GU := 0.0001


static func create_directed_rectangle(
	skill_id: String,
	release_id: String,
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	effect_length_gu: float,
	effect_width_gu: float,
	start_offset_gu := 0.0
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
	var footprint_polygon_ground_gu := ground_polygon_gu(snapshot)
	if footprint_polygon_ground_gu.size() < 3:
		return false
	if float(snapshot.get("effect_length_gu", 0.0)) <= CONTACT_EPSILON_GU:
		return false
	return convex_polygons_intersect_inclusive_ground_gu(
		footprint_polygon_ground_gu,
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
		"snapshot_builder_available": shape_type == SHAPE_DIRECTED_RECTANGLE,
	}
	classification.make_read_only()
	return classification


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
