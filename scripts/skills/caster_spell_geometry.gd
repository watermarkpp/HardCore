class_name CasterSpellGeometry
extends RefCounted

const CombatDirectionSpaceScript := preload(
	"res://scripts/skills/combat_direction_space.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

const CONTRACT_ID := "skills.visual.geometry_grid_steps.screen_px_projection.v2"
## GameRoot's cross-system boundary predates CONTRACT_ID but carries the same
## authoritative screen-point payload. Keep the wire ID accepted until the
## integration owner migrates its constant; rejecting it silently detached the
## runtime visual from the formal continuous GU damage strip.
const GAME_ROOT_SCREEN_POINT_CONTRACT_ID := (
	"skills.visual.geometry_cells.world_projection.v1"
)
const VISUAL_CONTRACT_ID := "skills.caster.geometry_visual_alignment.screen_px.v2"
const FOOTPRINT_INTERSECTION_CONTRACT_ID := (
	"skills.caster.area_footprint_intersection.ground_gu_sat.v2"
)
const CONTINUOUS_AIM_LINE_CONTRACT_ID := (
	"skills.wizard.line.continuous_ground_gu_footprint_sat.v2"
)
const DISCRETE_CELL_FOOTPRINT_RESOLVER_CONTRACT_ID := (
	"skills.caster.discrete_cells.actor_footprint_resolver_gu.v1"
)
const EXACT_CELL_UNION_RELEASE_CONTRACT_ID := (
	"skills.caster.ground_exact.cell_union_release_snapshot.v1"
)
const SNAPSHOT_VISUAL_PROJECTION_CONTRACT_ID := (
	"skills.caster.snapshot_visual_projection_consumer.v1"
)
const CONTACT_EPSILON := 0.0001
const LASER_SCREEN_LENGTH_LIMIT_PER_GU := 28.621670111997307


static func snapshot_strict_valid(
	snapshot: Dictionary,
	expected_context: Dictionary
) -> bool:
	return bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		expected_context,
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false))


static func snapshot_legacy_valid(
	snapshot: Dictionary,
	consumer_name: String,
	migration_reason: String
) -> bool:
	return bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		SkillFootprintSnapshotScript.legacy_consumer_context(
			consumer_name,
			migration_reason,
			"world_ground_plane_absolute"
		),
		SkillFootprintSnapshotScript.VALIDATION_EXPLICIT_LEGACY_COMPAT
	).get("valid", false))


static func _plan_validation_policy(plan: Dictionary) -> StringName:
	var raw_policy: Variant = plan.get(
		"snapshot_validation_policy",
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	)
	return raw_policy if raw_policy is StringName else SkillFootprintSnapshotScript.VALIDATION_STRICT_V2


static func _plan_validation_context(plan: Dictionary) -> Dictionary:
	var raw_context: Variant = plan.get("snapshot_validation_context", {})
	return raw_context if raw_context is Dictionary else {}


static func canonical_facing_grid_step_from_screen_direction_px(
	screen_direction_px: Vector2
) -> Vector2i:
	var direction_index := (
		CombatDirectionSpaceScript.direction_index_for_screen_delta_px(
			screen_direction_px
		)
	)
	return CombatDirectionSpaceScript.canonical_grid_step(direction_index)


static func effective_cells(
	skill_id: String,
	geometry: Dictionary,
	raw_cells: Variant,
	terrain_blocked: Callable = Callable()
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not raw_cells is Array:
		return result
	var stop_on_terrain := (
		skill_id in ["wizard.hellfire", "wizard.laser"]
		and str(geometry.get("shape", "")) == "line"
		and bool(geometry.get("stops_on_terrain", false))
	)
	for raw_cell: Variant in raw_cells:
		if not raw_cell is Vector2i:
			continue
		var cell: Vector2i = raw_cell
		if stop_on_terrain and terrain_blocked.is_valid() and bool(terrain_blocked.call(cell)):
			break
		result.append(cell)
	return result


static func target_cell_is_affected(
	effective_geometry_cells: Array[Vector2i],
	target_cell: Vector2i
) -> bool:
	return effective_geometry_cells.has(target_cell)


static func target_footprint_intersects_cell(
	target_footprint_tile_polygon: PackedVector2Array,
	cell: Vector2i
) -> bool:
	if target_footprint_tile_polygon.size() < 3:
		return false
	var center := Vector2(cell)
	var cell_polygon := PackedVector2Array([
		center + Vector2(-0.5, -0.5),
		center + Vector2(0.5, -0.5),
		center + Vector2(0.5, 0.5),
		center + Vector2(-0.5, 0.5),
	])
	return _convex_polygons_intersect(target_footprint_tile_polygon, cell_polygon)


static func target_footprint_intersects_cells(
	effective_geometry_cells: Array[Vector2i],
	target_footprint_tile_polygon: PackedVector2Array
) -> bool:
	for cell: Vector2i in effective_geometry_cells:
		if target_footprint_intersects_cell(target_footprint_tile_polygon, cell):
			return true
	return false


static func actor_footprint_polygon_ground_gu(
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for offset_ground_gu: Vector2 in (
		WorldSpatialRulesScript.actor_footprint_ground_polygon_gu(
			target_combat_radius_gu
		)
	):
		result.append(target_center_ground_gu + offset_ground_gu)
	return result


static func declared_cells_intersect_actor_footprint(
	effective_geometry_cells: Array[Vector2i],
	target_center_ground_gu: Vector2,
	target_combat_radius_gu: float,
	skill_footprint_snapshot: Dictionary = {},
	expected_context := {}
) -> Dictionary:
	var footprint_ground_gu := actor_footprint_polygon_ground_gu(
		target_center_ground_gu,
		target_combat_radius_gu
	)
	var valid_union_snapshot := (
		snapshot_strict_valid(skill_footprint_snapshot, expected_context)
		and str(skill_footprint_snapshot.get("shape_type", ""))
		== SkillFootprintSnapshotScript.SHAPE_CELL_UNION
	)
	var intersects := (
		SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			skill_footprint_snapshot,
			target_center_ground_gu,
			target_combat_radius_gu
		)
		if valid_union_snapshot
		else target_footprint_intersects_cells(
			effective_geometry_cells,
			footprint_ground_gu
		)
	)
	return {
		"contract_id": DISCRETE_CELL_FOOTPRINT_RESOLVER_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"intersects": intersects,
		"target_center_ground_gu": target_center_ground_gu,
		"target_footprint_ground_gu": footprint_ground_gu,
		"geometry_cells_grid_steps": effective_geometry_cells.duplicate(),
		"skill_footprint_snapshot": (
			skill_footprint_snapshot if valid_union_snapshot else {}
		),
		"snapshot_consumed": valid_union_snapshot,
	}


static func create_exact_cell_union_release_snapshot(
	skill_id: String,
	release_id: String,
	origin_ground_gu: Vector2,
	effective_geometry_cells: Array[Vector2i],
	coordinate_context := {}
) -> Dictionary:
	return SkillFootprintSnapshotScript.create_cell_union(
		skill_id,
		release_id,
		origin_ground_gu,
		effective_geometry_cells,
		coordinate_context
	)


static func continuous_line_strip_ground_gu(
	origin_ground_gu: Vector2,
	aim_ground_gu: Vector2,
	fallback_screen_direction_px: Vector2,
	effect_length_gu: float,
	effect_width_gu: float,
	skill_id := "wizard.line",
	release_id := "geometry_preview",
	declared_effect_length_gu := -1.0,
	resolved_effect_length_gu := -1.0,
	laser_projection_policy := "",
	coordinate_context := {}
) -> Dictionary:
	var axis_ground_gu := aim_ground_gu - origin_ground_gu
	if axis_ground_gu.length_squared() <= CONTACT_EPSILON * CONTACT_EPSILON:
		axis_ground_gu = GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			fallback_screen_direction_px
		)
	if axis_ground_gu.length_squared() <= CONTACT_EPSILON * CONTACT_EPSILON:
		axis_ground_gu = Vector2(1.0, 1.0)
	var direction_ground_gu := axis_ground_gu.normalized()
	var safe_length_gu := maxf(0.0, effect_length_gu)
	var safe_width_gu := maxf(CONTACT_EPSILON, effect_width_gu)
	var skill_footprint_snapshot := (
		SkillFootprintSnapshotScript.create_directed_rectangle(
			skill_id,
			release_id,
			origin_ground_gu,
			direction_ground_gu,
			safe_length_gu,
			safe_width_gu,
			0.0,
			declared_effect_length_gu,
			resolved_effect_length_gu,
			laser_projection_policy,
			coordinate_context
		)
	)
	var strip_start_ground_gu: Vector2 = skill_footprint_snapshot.get(
		"origin_ground_gu", origin_ground_gu
	)
	var strip_end_ground_gu: Vector2 = skill_footprint_snapshot.get(
		"end_ground_gu",
		GroundUnitSpaceScript.endpoint_ground_gu(
		origin_ground_gu,
		direction_ground_gu,
		safe_length_gu
		)
	)
	var half_width_gu := float(skill_footprint_snapshot.get("half_width_gu", 0.0))
	var polygon_ground_gu := (
		SkillFootprintSnapshotScript.ground_polygon_gu(
			skill_footprint_snapshot
		)
	)
	var centerline_points: Array[Vector2] = []
	for distance: int in range(1, ceili(safe_length_gu) + 1):
		centerline_points.append(
			origin_ground_gu
			+ direction_ground_gu * minf(float(distance), safe_length_gu)
		)
	return {
		"contract_id": CONTINUOUS_AIM_LINE_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"origin_ground_gu": origin_ground_gu,
		"aim_ground_gu": aim_ground_gu,
		"direction_ground_gu": direction_ground_gu,
		"effect_length_gu": safe_length_gu,
		"effect_width_gu": safe_width_gu,
		"half_width_gu": half_width_gu,
		"strip_start_ground_gu": strip_start_ground_gu,
		"strip_end_ground_gu": strip_end_ground_gu,
		"strip_polygon_ground_gu": polygon_ground_gu,
		"skill_footprint_snapshot": skill_footprint_snapshot,
		"centerline_points_ground_gu": centerline_points,
		"visual_direction_index": (
			CombatDirectionSpaceScript.direction_index_for_ground_delta_gu(
				direction_ground_gu
			)
		),
		"damage_axis_quantized": false,
		"visual_axis_quantized_to_nearest_8dir": true,
	}


static func target_footprint_intersects_continuous_line_ground_gu(
	line_strip: Dictionary,
	target_footprint_tile_polygon: PackedVector2Array,
	expected_context := {}
) -> bool:
	if target_footprint_tile_polygon.size() < 3:
		return false
	var raw_snapshot: Variant = line_strip.get("skill_footprint_snapshot", {})
	if (
		raw_snapshot is Dictionary
		and snapshot_strict_valid(raw_snapshot, expected_context)
	):
		return SkillFootprintSnapshotScript.intersects_target_polygon_ground_gu(
			raw_snapshot,
			target_footprint_tile_polygon
		)
	var raw_polygon: Variant = line_strip.get(
		"strip_polygon_ground_gu", PackedVector2Array()
	)
	if not raw_polygon is PackedVector2Array:
		return false
	var strip_polygon := raw_polygon as PackedVector2Array
	if strip_polygon.size() < 3:
		return false
	return _convex_polygons_intersect(target_footprint_tile_polygon, strip_polygon)


static func continuous_line_screen_points_px(
	line_strip: Dictionary,
	ground_gu_to_screen_position_px: Callable
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not ground_gu_to_screen_position_px.is_valid():
		return result
	for raw_point: Variant in line_strip.get("centerline_points_ground_gu", []):
		if raw_point is Vector2:
			result.append(ground_gu_to_screen_position_px.call(raw_point))
	return result


static func _convex_polygons_intersect(
	left: PackedVector2Array,
	right: PackedVector2Array
) -> bool:
	for polygon: PackedVector2Array in [left, right]:
		for index: int in range(polygon.size()):
			var edge := polygon[(index + 1) % polygon.size()] - polygon[index]
			if edge.length_squared() <= CONTACT_EPSILON * CONTACT_EPSILON:
				continue
			var axis := Vector2(-edge.y, edge.x).normalized()
			var left_projection := _project_polygon(left, axis)
			var right_projection := _project_polygon(right, axis)
			if (
				left_projection.y < right_projection.x - CONTACT_EPSILON
				or right_projection.y < left_projection.x - CONTACT_EPSILON
			):
				return false
	return true


static func _project_polygon(polygon: PackedVector2Array, axis: Vector2) -> Vector2:
	var minimum := INF
	var maximum := -INF
	for point: Vector2 in polygon:
		var projected := point.dot(axis)
		minimum = minf(minimum, projected)
		maximum = maxf(maximum, projected)
	return Vector2(minimum, maximum)


static func maximum_targets(geometry: Dictionary, mechanics: Dictionary) -> int:
	return maxi(
		0,
		int(geometry.get("maximum_targets", mechanics.get("maximum_targets", 0)))
	)


static func resolve_laser_effect_length_gu(
	direction_ground_gu: Vector2,
	declared_length_gu: float
) -> float:
	var safe_declared_length_gu := maxf(0.0, declared_length_gu)
	if (
		direction_ground_gu.length_squared()
		<= CONTACT_EPSILON * CONTACT_EPSILON
	):
		return safe_declared_length_gu

	var normalized_direction := direction_ground_gu.normalized()
	var screen_unit_length := (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			normalized_direction
		).length()
	)
	if screen_unit_length <= 0.000001:
		return safe_declared_length_gu

	var compensation := minf(
		1.0,
		LASER_SCREEN_LENGTH_LIMIT_PER_GU / screen_unit_length
	)
	return safe_declared_length_gu * compensation


static func build_visual_context(
	skill_id: String,
	origin_grid_cell: Vector2i,
	origin_screen_px: Vector2,
	effective_geometry_grid_cells: Array[Vector2i],
	grid_cell_to_screen_position_px: Callable
) -> Dictionary:
	var context := {
		"contract_id": VISUAL_CONTRACT_ID,
		"skill_id": skill_id,
		"origin_grid_cell": origin_grid_cell,
		"origin_screen_px": origin_screen_px,
		"geometry_grid_cells": effective_geometry_grid_cells.duplicate(),
		"geometry_screen_points_px": [],
		"geometry_screen_offsets_px": [],
		"grid_cell_screen_extent_px": Vector2.ZERO,
		"geometry_centerline_screen_extent_px": Vector2.ZERO,
		"footprint_screen_extent_px": Vector2.ZERO,
		"desired_sprite_extent_px": 0.0,
		"desired_sprite_footprint_px": Vector2.ZERO,
		"desired_sprite_axis_extent_px": 0.0,
		"desired_sprite_cross_axis_extent_px": 0.0,
		"visual_axis_screen_px": Vector2.ZERO,
	}
	if not grid_cell_to_screen_position_px.is_valid():
		return context
	var snapped_origin_screen_px: Vector2 = grid_cell_to_screen_position_px.call(origin_grid_cell)
	var basis_x_screen_px: Vector2 = (
		grid_cell_to_screen_position_px.call(origin_grid_cell + Vector2i.RIGHT)
		- snapped_origin_screen_px
	)
	var basis_y_screen_px: Vector2 = (
		grid_cell_to_screen_position_px.call(origin_grid_cell + Vector2i.DOWN)
		- snapped_origin_screen_px
	)
	var cell_extent := Vector2(
		absf(basis_x_screen_px.x) + absf(basis_y_screen_px.x),
		absf(basis_x_screen_px.y) + absf(basis_y_screen_px.y)
	)
	var half_cell_extent := cell_extent * 0.5
	var minimum := -half_cell_extent
	var maximum := half_cell_extent
	var centerline_minimum := Vector2.ZERO
	var centerline_maximum := Vector2.ZERO
	var screen_points_px: Array[Vector2] = []
	var screen_offsets_px: Array[Vector2] = []
	for cell: Vector2i in effective_geometry_grid_cells:
		# Preserve the actor's fractional footpoint while projecting the formal
		# integer-cell delta through the active map coordinate system.
		var screen_offset_px: Vector2 = (
			grid_cell_to_screen_position_px.call(cell) - snapped_origin_screen_px
		)
		var screen_point_px := origin_screen_px + screen_offset_px
		screen_points_px.append(screen_point_px)
		screen_offsets_px.append(screen_offset_px)
		centerline_minimum.x = minf(centerline_minimum.x, screen_offset_px.x)
		centerline_minimum.y = minf(centerline_minimum.y, screen_offset_px.y)
		centerline_maximum.x = maxf(centerline_maximum.x, screen_offset_px.x)
		centerline_maximum.y = maxf(centerline_maximum.y, screen_offset_px.y)
		minimum.x = minf(minimum.x, screen_offset_px.x - half_cell_extent.x)
		minimum.y = minf(minimum.y, screen_offset_px.y - half_cell_extent.y)
		maximum.x = maxf(maximum.x, screen_offset_px.x + half_cell_extent.x)
		maximum.y = maxf(maximum.y, screen_offset_px.y + half_cell_extent.y)
	var footprint_extent := Vector2.ZERO
	if not screen_offsets_px.is_empty():
		footprint_extent = maximum - minimum
	context["geometry_screen_points_px"] = screen_points_px
	context["geometry_screen_offsets_px"] = screen_offsets_px
	context["grid_basis_x_screen_px"] = basis_x_screen_px
	context["grid_basis_y_screen_px"] = basis_y_screen_px
	context["grid_cell_screen_extent_px"] = cell_extent
	context["geometry_centerline_screen_extent_px"] = (
		centerline_maximum - centerline_minimum
	)
	context["footprint_screen_extent_px"] = footprint_extent
	if skill_id == "wizard.hellfire":
		# FireGun uses one source-direction flame node and moves copies of it along
		# the canonical line. Fitting that one node against the cast direction made
		# the same source pixels scale by a different amount in every direction.
		# Keep node pixels fixed; geometry_screen_offsets_px alone owns the five-cell
		# trail length.
		pass
	elif skill_id == "wizard.hell_lightning":
		context["desired_sprite_extent_px"] = maxf(
			centerline_maximum.x - centerline_minimum.x,
			centerline_maximum.y - centerline_minimum.y
		)
		context["desired_sprite_footprint_px"] = footprint_extent
	elif skill_id == "wizard.laser":
		context["desired_sprite_extent_px"] = maxf(
			centerline_maximum.x - centerline_minimum.x,
			centerline_maximum.y - centerline_minimum.y
		)
		context["desired_sprite_footprint_px"] = footprint_extent
		if not screen_offsets_px.is_empty():
			var stable_axis_ground_gu := _stable_laser_visual_ground_direction(
				{},
				screen_offsets_px.back()
			)
			var visual_axis_screen_px: Vector2 = (
				GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
					stable_axis_ground_gu
				).normalized()
			)
			context["desired_sprite_axis_extent_px"] = (
				_stable_laser_visual_axis_extent_px(
					skill_id,
					{},
					stable_axis_ground_gu,
					screen_offsets_px.back()
				)
			)
			context["desired_sprite_cross_axis_extent_px"] = (
				_stable_laser_visual_cross_extent(cell_extent)
			)
			context["visual_axis_screen_px"] = visual_axis_screen_px
	context["gameplay_geometry"] = {
		"contract_id": CONTRACT_ID,
		"skill_id": skill_id,
		"origin_grid_cell": origin_grid_cell,
		"origin_screen_px": origin_screen_px,
		"grid_cell_count": effective_geometry_grid_cells.size(),
		"geometry_grid_cells": effective_geometry_grid_cells.duplicate(),
		"grid_cell_screen_extent_px": cell_extent,
		"desired_sprite_extent_px": context["desired_sprite_extent_px"],
		"desired_sprite_footprint_px": context["desired_sprite_footprint_px"],
		"desired_sprite_axis_extent_px": context["desired_sprite_axis_extent_px"],
		"desired_sprite_cross_axis_extent_px": context["desired_sprite_cross_axis_extent_px"],
		"visual_axis_screen_px": context["visual_axis_screen_px"],
	}
	context["visual_geometry"] = {
		"contract_id": VISUAL_CONTRACT_ID,
		"targeted_by": skill_id,
		"contract": CONTRACT_ID,
		"desired_sprite_extent_px": context["desired_sprite_extent_px"],
		"desired_sprite_footprint_px": context["desired_sprite_footprint_px"],
		"desired_sprite_axis_extent_px": context["desired_sprite_axis_extent_px"],
		"desired_sprite_cross_axis_extent_px": context["desired_sprite_cross_axis_extent_px"],
		"visual_axis_screen_px": context["visual_axis_screen_px"],
	}
	return context


static func visual_context_from_plan(
	skill_id: String,
	plan: Dictionary,
	fallback_origin_screen_px: Vector2,
	ground_gu_to_screen_position_px: Callable = Callable()
) -> Dictionary:
	var declared_contract := str(plan.get("canonical_geometry_contract", ""))
	var raw_skill_footprint_snapshot: Variant = plan.get(
		"skill_footprint_snapshot", {}
	)
	var validation_policy := _plan_validation_policy(plan)
	var validation_context := _plan_validation_context(plan)
	var skill_footprint_snapshot: Dictionary = (
		(raw_skill_footprint_snapshot as Dictionary)
		if (
			raw_skill_footprint_snapshot is Dictionary
			and bool(SkillFootprintSnapshotScript.validate_for_consumer(
				raw_skill_footprint_snapshot as Dictionary,
				validation_context,
				validation_policy
			).get("valid", false))
		)
		else {}
	)
	if not ground_gu_to_screen_position_px.is_valid():
		var raw_callable: Variant = plan.get(
			"ground_gu_to_screen_position_px",
			Callable()
		)
		if raw_callable is Callable:
			ground_gu_to_screen_position_px = raw_callable
	var snapshot_projection_context := snapshot_visual_projection_context(
		skill_footprint_snapshot,
		fallback_origin_screen_px,
		ground_gu_to_screen_position_px,
		validation_context,
		validation_policy
	)
	var raw_plan_visual_context: Variant = plan.get("visual_geometry_context", {})
	var base_plan_visual_context: Dictionary = (
		raw_plan_visual_context if raw_plan_visual_context is Dictionary else {}
	)
	var legacy_gameplay_geometry: Dictionary = {}
	var legacy_visual_geometry: Dictionary = {}
	if base_plan_visual_context.has("gameplay_geometry"):
		var source_gameplay_geometry: Variant = base_plan_visual_context.get(
			"gameplay_geometry"
		)
		if source_gameplay_geometry is Dictionary:
			legacy_gameplay_geometry = source_gameplay_geometry.duplicate(true)
	if base_plan_visual_context.has("visual_geometry"):
		var source_visual_geometry: Variant = base_plan_visual_context.get("visual_geometry")
		if source_visual_geometry is Dictionary:
			legacy_visual_geometry = source_visual_geometry.duplicate(true)
	if not canonical_geometry_contract_is_supported(declared_contract):
		var compatibility_context: Dictionary = plan.get(
			"visual_geometry_context", {}
		).duplicate(true)
		var gameplay_geometry := legacy_gameplay_geometry.duplicate(true)
		var visual_geometry := legacy_visual_geometry.duplicate(true)
		gameplay_geometry["contract_id"] = CONTRACT_ID
		if not gameplay_geometry.has("skill_id"):
			gameplay_geometry["skill_id"] = skill_id
		if not gameplay_geometry.has("origin_screen_px"):
			gameplay_geometry["origin_screen_px"] = fallback_origin_screen_px
		gameplay_geometry["canonical_contract"] = declared_contract
		gameplay_geometry["contract_supported"] = false
		visual_geometry["contract_id"] = VISUAL_CONTRACT_ID
		if not visual_geometry.has("skill_id"):
			visual_geometry["skill_id"] = skill_id
		compatibility_context["gameplay_geometry"] = gameplay_geometry
		compatibility_context["visual_geometry"] = visual_geometry
		compatibility_context.merge(snapshot_projection_context, true)
		return compatibility_context
	var origin_screen_px: Vector2 = plan.get(
		"geometry_origin_screen_px", fallback_origin_screen_px
	)
	var raw_screen_points_px: Variant = plan.get("geometry_screen_points_px", [])
	var raw_grid_cells: Variant = plan.get("geometry_grid_cells", [])
	var screen_points_px: Array[Vector2] = []
	var screen_offsets_px: Array[Vector2] = []
	if (
		raw_screen_points_px is Array
		or raw_screen_points_px is PackedVector2Array
	):
		for raw_point: Variant in raw_screen_points_px:
			if raw_point is Vector2:
				var point: Vector2 = raw_point
				screen_points_px.append(point)
				screen_offsets_px.append(point - origin_screen_px)
	var grid_cells: Array[Vector2i] = []
	if raw_grid_cells is Array:
		for raw_grid_cell: Variant in raw_grid_cells:
			if raw_grid_cell is Vector2i:
				grid_cells.append(raw_grid_cell)
	var basis_x := Vector2.ZERO
	var basis_y := Vector2.ZERO
	var canonical_projection_scale := 0.0
	if grid_cells.size() == screen_points_px.size():
		for left_index: int in range(grid_cells.size()):
			for right_index: int in range(left_index + 1, grid_cells.size()):
				var grid_delta := grid_cells[right_index] - grid_cells[left_index]
				var screen_delta_px := screen_points_px[right_index] - screen_points_px[left_index]
				if canonical_projection_scale <= 0.0 and grid_delta != Vector2i.ZERO:
					var canonical_screen_delta_px := (
						CombatDirectionSpaceScript.ground_delta_gu_to_screen_delta_px(
							Vector2(grid_delta)
						)
					)
					if canonical_screen_delta_px.length() > 0.001:
						canonical_projection_scale = (
							screen_delta_px.length() / canonical_screen_delta_px.length()
						)
				if basis_x.is_zero_approx() and abs(grid_delta.x) == 1 and grid_delta.y == 0:
					basis_x = screen_delta_px * float(grid_delta.x)
				if basis_y.is_zero_approx() and grid_delta.x == 0 and abs(grid_delta.y) == 1:
					basis_y = screen_delta_px * float(grid_delta.y)
				if not basis_x.is_zero_approx() and not basis_y.is_zero_approx():
					break
			if not basis_x.is_zero_approx() and not basis_y.is_zero_approx():
				break
	# A one-cell-wide line can expose only one map axis (or only a diagonal),
	# so a second basis vector cannot always be recovered from its own cells.
	# The integration contract is the same canonical isometric direction space;
	# recover the missing basis from the measured projection scale instead of
	# guessing a generic pixel cell size.
	if canonical_projection_scale > 0.0:
		if basis_x.is_zero_approx():
			basis_x = (
				CombatDirectionSpaceScript.ground_delta_gu_to_screen_delta_px(
					Vector2.RIGHT
				)
				* canonical_projection_scale
			)
		if basis_y.is_zero_approx():
			basis_y = (
				CombatDirectionSpaceScript.ground_delta_gu_to_screen_delta_px(
					Vector2.DOWN
				)
				* canonical_projection_scale
			)
	elif not screen_offsets_px.is_empty():
		# Continuous line plans intentionally carry fractional GU points rather
		# than integer grid steps. Their contract is the shared 64x32 isometric
		# plane, so recover its two one-GU basis vectors for the formal one-step
		# visual width instead of falling back to uniform screen-space scaling.
		basis_x = (
			CombatDirectionSpaceScript.ground_delta_gu_to_screen_delta_px(
				Vector2.RIGHT
			)
		)
		basis_y = (
			CombatDirectionSpaceScript.ground_delta_gu_to_screen_delta_px(
				Vector2.DOWN
			)
		)
	var cell_extent := Vector2(
		absf(basis_x.x) + absf(basis_y.x),
		absf(basis_x.y) + absf(basis_y.y)
	)
	var minimum_step := INF
	for index: int in range(1, screen_points_px.size()):
		var distance := screen_points_px[index].distance_to(screen_points_px[index - 1])
		if distance > 0.001:
			minimum_step = minf(minimum_step, distance)
	var half_cell_extent := cell_extent * 0.5
	var minimum := -half_cell_extent
	var maximum := half_cell_extent
	var centerline_minimum := Vector2.ZERO
	var centerline_maximum := Vector2.ZERO
	for offset: Vector2 in screen_offsets_px:
		centerline_minimum.x = minf(centerline_minimum.x, offset.x)
		centerline_minimum.y = minf(centerline_minimum.y, offset.y)
		centerline_maximum.x = maxf(centerline_maximum.x, offset.x)
		centerline_maximum.y = maxf(centerline_maximum.y, offset.y)
		minimum.x = minf(minimum.x, offset.x - half_cell_extent.x)
		minimum.y = minf(minimum.y, offset.y - half_cell_extent.y)
		maximum.x = maxf(maximum.x, offset.x + half_cell_extent.x)
		maximum.y = maxf(maximum.y, offset.y + half_cell_extent.y)
	var footprint_extent := (
		maximum - minimum
		if not screen_offsets_px.is_empty()
		else Vector2.ZERO
	)
	var desired_extent := 0.0
	var desired_footprint := Vector2.ZERO
	var desired_axis_extent := 0.0
	var desired_cross_axis_extent := 0.0
	var visual_axis_screen_px := Vector2.ZERO
	if skill_id == "wizard.hellfire":
		# The primary FireGun node is not a direction-specific full-line image.
		# Its fixed source-pixel scale is independent from target distance and cast
		# direction; only the shared geometry offsets determine trail placement.
		pass
	elif skill_id in ["wizard.hell_lightning", "wizard.laser"]:
		desired_extent = maxf(
			centerline_maximum.x - centerline_minimum.x,
			centerline_maximum.y - centerline_minimum.y
		)
		desired_footprint = footprint_extent
		if skill_id == "wizard.laser" and not screen_offsets_px.is_empty():
			var stable_axis_ground_gu := _stable_laser_visual_ground_direction(
				plan,
				screen_offsets_px.back()
			)
			desired_axis_extent = _stable_laser_visual_axis_extent_px(
				skill_id,
				plan,
				stable_axis_ground_gu,
				screen_offsets_px.back()
			)
			visual_axis_screen_px = (
				GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
					stable_axis_ground_gu
				).normalized()
			)
			desired_cross_axis_extent = (
				_stable_laser_visual_cross_extent(cell_extent)
			)
	var formal_core_polygon_screen_offset_px := PackedVector2Array()
	var formal_core_axis_screen_offset_px := Vector2.ZERO
	if not skill_footprint_snapshot.is_empty():
		formal_core_polygon_screen_offset_px = (
			SkillFootprintSnapshotScript.projected_polygon_screen_offset_px(
				skill_footprint_snapshot
			)
		)
		formal_core_axis_screen_offset_px = skill_footprint_snapshot.get(
			"axis_screen_offset_px", Vector2.ZERO
		)
	var result := {
		"contract_id": VISUAL_CONTRACT_ID,
		"canonical_geometry_contract": CONTRACT_ID,
		"canonical_geometry_source_wire_contract": declared_contract,
		"skill_id": skill_id,
		"origin_screen_px": origin_screen_px,
		"geometry_grid_cells": grid_cells,
		"geometry_screen_points_px": screen_points_px,
		"geometry_screen_offsets_px": screen_offsets_px,
		"grid_basis_x_screen_px": basis_x,
		"grid_basis_y_screen_px": basis_y,
		"grid_cell_screen_extent_px": cell_extent,
		"geometry_centerline_screen_extent_px": (
			centerline_maximum - centerline_minimum
		),
		"footprint_screen_extent_px": footprint_extent,
		"desired_sprite_extent_px": desired_extent,
		"desired_sprite_footprint_px": desired_footprint,
		"desired_sprite_axis_extent_px": desired_axis_extent,
		"desired_sprite_cross_axis_extent_px": desired_cross_axis_extent,
		"visual_axis_screen_px": visual_axis_screen_px,
		"skill_footprint_snapshot": skill_footprint_snapshot,
		"formal_core_polygon_screen_offset_px": (
			formal_core_polygon_screen_offset_px
		),
		"formal_core_axis_screen_offset_px": formal_core_axis_screen_offset_px,
		"formal_core_contract_id": str(
			skill_footprint_snapshot.get("contract_id", "")
		),
		"debug_skill_visual_geometry": bool(
			plan.get("debug_skill_visual_geometry", false)
		),
	}
	result["gameplay_geometry"] = {
		"contract_id": CONTRACT_ID,
		"skill_id": skill_id,
		"origin_screen_px": origin_screen_px,
		"declared_contract": declared_contract,
		"grid_cell_count": grid_cells.size(),
		"maximum_range_gu": float(plan.get("maximum_range_gu", 0.0)),
		"maximum_targets": int(plan.get("maximum_targets", 0)),
		"geometry_grid_cells": grid_cells.duplicate(),
		"geometry_screen_points_px": screen_points_px,
		"geometry_screen_offsets_px": screen_offsets_px,
		"geometry_origin_screen_px": origin_screen_px,
		"canonical_geometry_contract": declared_contract,
	}
	var merged_visual_geometry := {
		"contract_id": VISUAL_CONTRACT_ID,
		"skill_id": skill_id,
		"desired_sprite_extent_px": desired_extent,
		"desired_sprite_footprint_px": desired_footprint,
		"desired_sprite_axis_extent_px": desired_axis_extent,
		"desired_sprite_cross_axis_extent_px": desired_cross_axis_extent,
		"visual_axis_screen_px": visual_axis_screen_px,
		"fit_axis_world": Vector2.ZERO
	}
	merged_visual_geometry.merge(legacy_visual_geometry, true)
	result["visual_geometry"] = merged_visual_geometry
	# Q1-A: propagate the explicit validation policy/context to downstream
	# visual consumers (CasterSkillVisualEffect, beam) so they never fall back
	# to a context-free is_valid() gate.
	result["snapshot_validation_policy"] = validation_policy
	result["snapshot_validation_context"] = validation_context
	result.merge(snapshot_projection_context, true)
	return result


static func snapshot_visual_projection_context(
	skill_footprint_snapshot: Dictionary,
	fallback_origin_screen_px: Vector2,
	ground_gu_to_screen_position_px: Callable = Callable(),
	expected_context := {},
	validation_policy: StringName = SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
) -> Dictionary:
	if not bool(SkillFootprintSnapshotScript.validate_for_consumer(
		skill_footprint_snapshot,
		expected_context,
		validation_policy
	).get("valid", false)):
		return {}
	var shape_type := str(skill_footprint_snapshot.get("shape_type", ""))
	var anchor_ground_gu: Vector2
	var anchor_policy := "release_origin"
	match shape_type:
		SkillFootprintSnapshotScript.SHAPE_TARGET_FOOTPRINT:
			anchor_ground_gu = skill_footprint_snapshot.get(
				"target_center_ground_gu", Vector2.ZERO
			)
			anchor_policy = "target_release_frame_footpoint"
		SkillFootprintSnapshotScript.SHAPE_CIRCLE:
			anchor_ground_gu = skill_footprint_snapshot.get(
				"center_ground_gu", Vector2.ZERO
			)
			anchor_policy = "circle_center_ground_gu"
		SkillFootprintSnapshotScript.SHAPE_SWEPT_CAPSULE_PATH:
			anchor_ground_gu = skill_footprint_snapshot.get(
				"segment_start_ground_gu", Vector2.ZERO
			)
			anchor_policy = "sweep_segment_start_diagnostic_only"
		_:
			anchor_ground_gu = skill_footprint_snapshot.get(
				"origin_ground_gu", Vector2.ZERO
			)
	var anchor_screen_px: Vector2
	if ground_gu_to_screen_position_px.is_valid():
		var mapped_anchor_screen_px: Variant = (
			ground_gu_to_screen_position_px.call(anchor_ground_gu)
		)
		anchor_screen_px = (
			mapped_anchor_screen_px
			if mapped_anchor_screen_px is Vector2
			else fallback_origin_screen_px
		)
	else:
		# Without an active map projection, absolute ground coordinates cannot be
		# converted to screen pixels. The caller already provides the correct screen
		# origin (caster foot, target foot, or world impact point) in
		# fallback_origin_screen_px. Polygon offsets are relative to the snapshot
		# anchor, so placing them at the fallback origin produces the correct
		# screen-space layout.
		anchor_screen_px = fallback_origin_screen_px
	var anchor_offset_from_effect_px := (
		anchor_screen_px - fallback_origin_screen_px
	)
	var projected_polygons_from_anchor := (
		SkillFootprintSnapshotScript.projected_polygons_screen_offset_px(
			skill_footprint_snapshot
		)
	)
	var projected_polygons_local_to_effect: Array[PackedVector2Array] = []
	for polygon_from_anchor: PackedVector2Array in projected_polygons_from_anchor:
		var local_polygon := PackedVector2Array()
		for point_from_anchor: Vector2 in polygon_from_anchor:
			local_polygon.append(
				point_from_anchor + anchor_offset_from_effect_px
			)
		projected_polygons_local_to_effect.append(local_polygon)
	var visual_core_policy := "projected_polygon_core"
	if shape_type == SkillFootprintSnapshotScript.SHAPE_CELL_UNION:
		visual_core_policy = "all_exact_cell_polygons_no_bounding_shape"
	elif shape_type == SkillFootprintSnapshotScript.SHAPE_TARGET_FOOTPRINT:
		visual_core_policy = "target_anchor_and_footprint_no_extra_area"
	elif shape_type == SkillFootprintSnapshotScript.SHAPE_SWEPT_CAPSULE_PATH:
		visual_core_policy = "diagnostic_only_do_not_force_capsule_visual"
	var declared_coordinate_space := str(
		skill_footprint_snapshot.get(
			"coordinate_space",
			SkillFootprintSnapshotScript.COORDINATE_SPACE_LEGACY_GROUND_GU
		)
	)
	var snapshot_is_absolute := (
		declared_coordinate_space
		== SkillFootprintSnapshotScript.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU
	)
	return {
		"snapshot_visual_projection_contract_id": (
			SNAPSHOT_VISUAL_PROJECTION_CONTRACT_ID
		),
		"skill_footprint_snapshot": skill_footprint_snapshot,
		"snapshot_shape_type": shape_type,
		"snapshot_anchor_policy": anchor_policy,
		"snapshot_anchor_ground_gu": anchor_ground_gu,
		"coordinate_space": declared_coordinate_space,
		"snapshot_coordinate_space": declared_coordinate_space,
		"snapshot_schema_version": int(
			skill_footprint_snapshot.get("schema_version", 1)
		),
		"snapshot_runtime_map_id": str(
			skill_footprint_snapshot.get("runtime_map_id", "")
		),
		"snapshot_projection_origin_ground_gu": (
			skill_footprint_snapshot.get(
				"projection_origin_ground_gu", Vector2.ZERO
			) as Vector2
		),
		"snapshot_id": str(
			skill_footprint_snapshot.get("snapshot_id", "")
		),
		"screen_anchor_source": (
			"runtime_map_ground_projection"
			if ground_gu_to_screen_position_px.is_valid()
			else "runtime_fallback_origin"
		),
		"absolute_ground_reprojected_as_delta": (
			snapshot_is_absolute
			and not ground_gu_to_screen_position_px.is_valid()
		),
		"snapshot_anchor_screen_px": anchor_screen_px,
		"snapshot_anchor_offset_from_effect_px": (
			anchor_offset_from_effect_px
		),
		"snapshot_projected_polygons_screen_offset_px": (
			projected_polygons_from_anchor
		),
		"snapshot_projected_polygons_local_to_effect_px": (
			projected_polygons_local_to_effect
		),
		"snapshot_visual_core_policy": visual_core_policy,
		"decoration_sprite_transform_policy": (
			"source_asset_unchanged_no_snapshot_rescale"
		),
	}


static func canonical_geometry_contract_is_supported(contract_id: String) -> bool:
	return contract_id in [CONTRACT_ID, GAME_ROOT_SCREEN_POINT_CONTRACT_ID]


static func _stable_laser_visual_cross_extent(cell_extent: Vector2) -> float:
	# The damage strip remains one isometric cell wide. Presentation uses the
	# area-equivalent screen width of that cell, which is direction invariant:
	# sqrt(64 * 32) = 45.2548 px for the canonical map projection.
	return sqrt(maxf(0.001, cell_extent.x * cell_extent.y))


static func _stable_laser_visual_ground_direction(
	plan: Dictionary,
	fallback_axis_screen: Vector2
) -> Vector2:
	# Quantize laser axis to a canonical 16-way ground step to avoid flicker in
	# boundary angles (especially for W/E), then consume this in the visual axis.
	var direction_ground_gu := Vector2.ZERO
	var raw_snapshot: Variant = plan.get("skill_footprint_snapshot", {})
	if (
		raw_snapshot is Dictionary
		and bool(SkillFootprintSnapshotScript.validate_for_consumer(
			raw_snapshot as Dictionary,
			_plan_validation_context(plan),
			_plan_validation_policy(plan)
		).get("valid", false))
	):
		direction_ground_gu = raw_snapshot.get("direction_ground_gu", Vector2.ZERO)
	if direction_ground_gu.length_squared() <= CONTACT_EPSILON * CONTACT_EPSILON:
		var plan_direction_ground_gu: Vector2 = plan.get(
			"direction_ground_gu",
			Vector2.ZERO
		)
		if (
			plan_direction_ground_gu is Vector2
			and plan_direction_ground_gu.length_squared() > CONTACT_EPSILON * CONTACT_EPSILON
		):
			direction_ground_gu = plan_direction_ground_gu
	if direction_ground_gu.length_squared() <= CONTACT_EPSILON * CONTACT_EPSILON:
		direction_ground_gu = (
			GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
				fallback_axis_screen
			)
		)
	if direction_ground_gu.length_squared() <= CONTACT_EPSILON * CONTACT_EPSILON:
		direction_ground_gu = Vector2(1.0, 1.0)
	if direction_ground_gu.length_squared() <= CONTACT_EPSILON * CONTACT_EPSILON:
		return Vector2.ZERO
	var direction_index := int(
		round(direction_ground_gu.angle() / (TAU / 16.0))
	)
	return Vector2.from_angle(
		float(posmod(direction_index, 16)) * TAU / 16.0
	)


static func _stable_laser_visual_axis_extent_px(
	skill_id: String,
	plan: Dictionary,
	stable_axis_ground_gu: Vector2,
	fallback_axis_screen: Vector2
) -> float:
	if skill_id != "wizard.laser":
		return fallback_axis_screen.length()
	var fallback_axis_length := fallback_axis_screen.length()
	var raw_plan_offsets: Variant = plan.get("geometry_screen_offsets_px", [])
	if (
		raw_plan_offsets is Array
		or raw_plan_offsets is PackedVector2Array
	) and raw_plan_offsets.size() > 0:
		var fallback_axis_offset_length := 0.0
		for raw_offset: Variant in raw_plan_offsets:
			if raw_offset is Vector2:
				fallback_axis_offset_length = maxf(
					fallback_axis_offset_length,
					(raw_offset as Vector2).length()
				)
		if fallback_axis_offset_length > 0.000001:
			return fallback_axis_offset_length
	var raw_plan_points: Variant = plan.get("geometry_screen_points_px", [])
	if (
		raw_plan_points is Array
		or raw_plan_points is PackedVector2Array
	) and raw_plan_points.size() > 0:
		var raw_first_point: Variant = raw_plan_points[0]
		var raw_last_point: Variant = raw_plan_points[raw_plan_points.size() - 1]
		if raw_last_point is Vector2:
			var plan_axis_length := (raw_last_point as Vector2).length()
			if raw_first_point is Vector2:
				plan_axis_length = (
					(raw_last_point as Vector2) - (raw_first_point as Vector2)
				).length()
			if plan_axis_length > 0.000001:
				return plan_axis_length
	if fallback_axis_length > CONTACT_EPSILON:
		return fallback_axis_length
	var raw_snapshot: Variant = plan.get("skill_footprint_snapshot", {})
	var snapshot_axis_extent_px := 0.0
	if (
		raw_snapshot is Dictionary
		and bool(SkillFootprintSnapshotScript.validate_for_consumer(
			raw_snapshot as Dictionary,
			_plan_validation_context(plan),
			_plan_validation_policy(plan)
		).get("valid", false))
	):
		snapshot_axis_extent_px = float(raw_snapshot.get("axis_screen_length_px", 0.0))
		if snapshot_axis_extent_px > 0.0:
			return snapshot_axis_extent_px
		var safe_length_gu := maxf(
			0.0,
			float(raw_snapshot.get("effect_length_gu", 0.0))
		)
		if (
			safe_length_gu > 0.0
			and stable_axis_ground_gu.length_squared()
			> CONTACT_EPSILON * CONTACT_EPSILON
		):
			return (
				GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
					stable_axis_ground_gu * safe_length_gu
				).length()
			)
	var stable_axis_ground_unit := stable_axis_ground_gu.normalized()
	if stable_axis_ground_unit.length_squared() <= CONTACT_EPSILON * CONTACT_EPSILON:
		return fallback_axis_screen.length()
	var fallback_axis_ground := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(fallback_axis_screen)
	)
	if fallback_axis_ground.length_squared() <= CONTACT_EPSILON * CONTACT_EPSILON:
		return fallback_axis_screen.length()
	return fallback_axis_length if fallback_axis_length > 0.000001 else 0.0
