class_name CasterSpellGeometry
extends RefCounted

const CombatDirectionSpaceScript := preload(
	"res://scripts/skills/combat_direction_space.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

const CONTRACT_ID := "skills.visual.geometry_cells.world_projection.v1"
const VISUAL_CONTRACT_ID := "skills.caster.geometry_visual_alignment.v1"
const FOOTPRINT_INTERSECTION_CONTRACT_ID := (
	"skills.caster.area_footprint_intersection.ground_gu_sat.v2"
)
const CONTINUOUS_AIM_LINE_CONTRACT_ID := (
	"skills.wizard.line.continuous_ground_gu_footprint_sat.v2"
)
const DISCRETE_CELL_FOOTPRINT_RESOLVER_CONTRACT_ID := (
	"skills.caster.discrete_cells.actor_footprint_resolver_gu.v1"
)
const CONTACT_EPSILON := 0.0001


static func canonical_facing_from_world_direction(world_direction: Vector2) -> Vector2i:
	var direction_index := CombatDirectionSpaceScript.direction_index_for_world_delta(
		world_direction
	)
	return CombatDirectionSpaceScript.canonical_tile_step(direction_index)


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
	target_collision_radius_px: float
) -> PackedVector2Array:
	var combat_radius_gu := (
		WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			target_collision_radius_px
		)
	)
	var result := PackedVector2Array()
	for offset_ground_gu: Vector2 in (
		WorldSpatialRulesScript.actor_footprint_ground_polygon_gu(
			combat_radius_gu
		)
	):
		result.append(target_center_ground_gu + offset_ground_gu)
	return result


static func declared_cells_intersect_actor_footprint(
	effective_geometry_cells: Array[Vector2i],
	target_center_ground_gu: Vector2,
	target_collision_radius_px: float
) -> Dictionary:
	var footprint_ground_gu := actor_footprint_polygon_ground_gu(
		target_center_ground_gu,
		target_collision_radius_px
	)
	return {
		"contract_id": DISCRETE_CELL_FOOTPRINT_RESOLVER_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"intersects": target_footprint_intersects_cells(
			effective_geometry_cells,
			footprint_ground_gu
		),
		"target_center_ground_gu": target_center_ground_gu,
		"target_footprint_ground_gu": footprint_ground_gu,
		"geometry_cells_grid_steps": effective_geometry_cells.duplicate(),
	}


static func continuous_line_strip(
	origin_ground_gu: Vector2,
	aim_ground_gu: Vector2,
	fallback_screen_direction_px: Vector2,
	effect_length_gu: float,
	effect_width_gu: float
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
	var strip_start_ground_gu := origin_ground_gu
	var strip_end_ground_gu := GroundUnitSpaceScript.endpoint_ground_gu(
		origin_ground_gu,
		direction_ground_gu,
		safe_length_gu
	)
	var perpendicular := Vector2(-direction_ground_gu.y, direction_ground_gu.x)
	var half_width := safe_width_gu * 0.5
	var polygon := PackedVector2Array([
		strip_start_ground_gu + perpendicular * half_width,
		strip_end_ground_gu + perpendicular * half_width,
		strip_end_ground_gu - perpendicular * half_width,
		strip_start_ground_gu - perpendicular * half_width,
	])
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
		"half_width_gu": half_width,
		"strip_start_ground_gu": strip_start_ground_gu,
		"strip_end_ground_gu": strip_end_ground_gu,
		"strip_polygon_ground_gu": polygon,
		"centerline_points_ground_gu": centerline_points,
		# Compatibility keys for integration until the GU rename is merged.
		"origin_fractional_tile": origin_ground_gu,
		"aim_fractional_tile": aim_ground_gu,
		"axis_fractional_tile": direction_ground_gu,
		"length_tiles": safe_length_gu,
		"width_tiles": safe_width_gu,
		"strip_start_fractional_tile": strip_start_ground_gu,
		"strip_end_fractional_tile": strip_end_ground_gu,
		"strip_polygon_fractional_tile": polygon,
		"centerline_points_fractional_tile": centerline_points,
		"visual_direction_index": (
			CombatDirectionSpaceScript.direction_index_for_fractional_tile_delta(
				direction_ground_gu
			)
		),
		"damage_axis_quantized": false,
		"visual_axis_quantized_to_nearest_8dir": true,
	}


static func target_footprint_intersects_continuous_line(
	line_strip: Dictionary,
	target_footprint_tile_polygon: PackedVector2Array
) -> bool:
	if target_footprint_tile_polygon.size() < 3:
		return false
	var raw_polygon: Variant = line_strip.get(
		"strip_polygon_ground_gu",
		line_strip.get("strip_polygon_fractional_tile", PackedVector2Array())
	)
	if not raw_polygon is PackedVector2Array:
		return false
	var strip_polygon := raw_polygon as PackedVector2Array
	if strip_polygon.size() < 3:
		return false
	return _convex_polygons_intersect(target_footprint_tile_polygon, strip_polygon)


static func continuous_line_world_points(
	line_strip: Dictionary,
	fractional_tile_to_world: Callable
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not fractional_tile_to_world.is_valid():
		return result
	for raw_point: Variant in line_strip.get(
		"centerline_points_ground_gu",
		line_strip.get("centerline_points_fractional_tile", [])
	):
		if raw_point is Vector2:
			result.append(fractional_tile_to_world.call(raw_point))
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


static func build_visual_context(
	skill_id: String,
	origin_tile: Vector2i,
	origin_world: Vector2,
	effective_geometry_cells: Array[Vector2i],
	tile_to_world: Callable
) -> Dictionary:
	var context := {
		"contract_id": VISUAL_CONTRACT_ID,
		"skill_id": skill_id,
		"origin_tile": origin_tile,
		"origin_world": origin_world,
		"geometry_cells": effective_geometry_cells.duplicate(),
		"geometry_world_points": [],
		"geometry_world_offsets": [],
		"cell_world_extent": Vector2.ZERO,
		"geometry_centerline_world_extent": Vector2.ZERO,
		"footprint_world_extent": Vector2.ZERO,
		"desired_sprite_extent": 0.0,
		"desired_sprite_footprint": Vector2.ZERO,
		"desired_sprite_axis_extent": 0.0,
		"desired_sprite_cross_axis_extent": 0.0,
		"visual_axis_world": Vector2.ZERO,
	}
	if not tile_to_world.is_valid():
		return context
	var snapped_origin_world: Vector2 = tile_to_world.call(origin_tile)
	var basis_x: Vector2 = tile_to_world.call(origin_tile + Vector2i.RIGHT) - snapped_origin_world
	var basis_y: Vector2 = tile_to_world.call(origin_tile + Vector2i.DOWN) - snapped_origin_world
	var cell_extent := Vector2(
		absf(basis_x.x) + absf(basis_y.x),
		absf(basis_x.y) + absf(basis_y.y)
	)
	var half_cell_extent := cell_extent * 0.5
	var minimum := -half_cell_extent
	var maximum := half_cell_extent
	var centerline_minimum := Vector2.ZERO
	var centerline_maximum := Vector2.ZERO
	var world_points: Array[Vector2] = []
	var world_offsets: Array[Vector2] = []
	for cell: Vector2i in effective_geometry_cells:
		# Preserve the actor's fractional footpoint while projecting the formal
		# integer-cell delta through the active map coordinate system.
		var world_offset: Vector2 = tile_to_world.call(cell) - snapped_origin_world
		var world_point := origin_world + world_offset
		world_points.append(world_point)
		world_offsets.append(world_offset)
		centerline_minimum.x = minf(centerline_minimum.x, world_offset.x)
		centerline_minimum.y = minf(centerline_minimum.y, world_offset.y)
		centerline_maximum.x = maxf(centerline_maximum.x, world_offset.x)
		centerline_maximum.y = maxf(centerline_maximum.y, world_offset.y)
		minimum.x = minf(minimum.x, world_offset.x - half_cell_extent.x)
		minimum.y = minf(minimum.y, world_offset.y - half_cell_extent.y)
		maximum.x = maxf(maximum.x, world_offset.x + half_cell_extent.x)
		maximum.y = maxf(maximum.y, world_offset.y + half_cell_extent.y)
	var footprint_extent := Vector2.ZERO
	if not world_offsets.is_empty():
		footprint_extent = maximum - minimum
	context["geometry_world_points"] = world_points
	context["geometry_world_offsets"] = world_offsets
	context["tile_basis_x_world"] = basis_x
	context["tile_basis_y_world"] = basis_y
	context["cell_world_extent"] = cell_extent
	context["geometry_centerline_world_extent"] = (
		centerline_maximum - centerline_minimum
	)
	context["footprint_world_extent"] = footprint_extent
	if skill_id == "wizard.hellfire":
		# FireGun uses one source-direction flame node and moves copies of it along
		# the canonical line. Fitting that one node against the cast direction made
		# the same source pixels scale by a different amount in every direction.
		# Keep node pixels fixed; geometry_world_offsets alone owns the five-cell
		# trail length.
		pass
	elif skill_id == "wizard.hell_lightning":
		context["desired_sprite_extent"] = maxf(
			centerline_maximum.x - centerline_minimum.x,
			centerline_maximum.y - centerline_minimum.y
		)
		context["desired_sprite_footprint"] = footprint_extent
	elif skill_id == "wizard.laser":
		context["desired_sprite_extent"] = maxf(
			centerline_maximum.x - centerline_minimum.x,
			centerline_maximum.y - centerline_minimum.y
		)
		context["desired_sprite_footprint"] = footprint_extent
		if not world_offsets.is_empty():
			var visual_axis: Vector2 = world_offsets.back().normalized()
			context["desired_sprite_axis_extent"] = world_offsets.back().length()
			context["desired_sprite_cross_axis_extent"] = (
				_stable_laser_visual_cross_extent(cell_extent)
			)
			context["visual_axis_world"] = visual_axis
	return context


static func visual_context_from_plan(
	skill_id: String,
	plan: Dictionary,
	fallback_origin_world: Vector2
) -> Dictionary:
	var declared_contract := str(plan.get("canonical_geometry_contract", ""))
	if declared_contract != CONTRACT_ID:
		return plan.get("visual_geometry_context", {}).duplicate(true)
	var origin_world: Vector2 = plan.get(
		"geometry_origin_screen_px", fallback_origin_world
	)
	var raw_world_points: Variant = plan.get("geometry_world_points", [])
	var raw_tile_points: Variant = plan.get("geometry_tile_points", [])
	var world_points: Array[Vector2] = []
	var world_offsets: Array[Vector2] = []
	if raw_world_points is Array:
		for raw_point: Variant in raw_world_points:
			if raw_point is Vector2:
				var point: Vector2 = raw_point
				world_points.append(point)
				world_offsets.append(point - origin_world)
	var tile_points: Array[Vector2i] = []
	if raw_tile_points is Array:
		for raw_tile: Variant in raw_tile_points:
			if raw_tile is Vector2i:
				tile_points.append(raw_tile)
	var basis_x := Vector2.ZERO
	var basis_y := Vector2.ZERO
	var canonical_projection_scale := 0.0
	if tile_points.size() == world_points.size():
		for left_index: int in range(tile_points.size()):
			for right_index: int in range(left_index + 1, tile_points.size()):
				var tile_delta := tile_points[right_index] - tile_points[left_index]
				var world_delta := world_points[right_index] - world_points[left_index]
				if canonical_projection_scale <= 0.0 and tile_delta != Vector2i.ZERO:
					var canonical_world_delta := (
						CombatDirectionSpaceScript.fractional_tile_delta_to_world_delta(
							Vector2(tile_delta)
						)
					)
					if canonical_world_delta.length() > 0.001:
						canonical_projection_scale = (
							world_delta.length() / canonical_world_delta.length()
						)
				if basis_x.is_zero_approx() and abs(tile_delta.x) == 1 and tile_delta.y == 0:
					basis_x = world_delta * float(tile_delta.x)
				if basis_y.is_zero_approx() and tile_delta.x == 0 and abs(tile_delta.y) == 1:
					basis_y = world_delta * float(tile_delta.y)
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
				CombatDirectionSpaceScript.fractional_tile_delta_to_world_delta(
					Vector2.RIGHT
				)
				* canonical_projection_scale
			)
		if basis_y.is_zero_approx():
			basis_y = (
				CombatDirectionSpaceScript.fractional_tile_delta_to_world_delta(
					Vector2.DOWN
				)
				* canonical_projection_scale
			)
	elif not world_offsets.is_empty():
		# Continuous line plans intentionally carry fractional world points rather
		# than integer tile cells. Their contract is the shared 64x32 isometric
		# plane, so recover its two one-tile basis vectors for the formal one-cell
		# visual width instead of falling back to uniform screen-space scaling.
		basis_x = (
			CombatDirectionSpaceScript.fractional_tile_delta_to_world_delta(
				Vector2.RIGHT
			)
		)
		basis_y = (
			CombatDirectionSpaceScript.fractional_tile_delta_to_world_delta(
				Vector2.DOWN
			)
		)
	var cell_extent := Vector2(
		absf(basis_x.x) + absf(basis_y.x),
		absf(basis_x.y) + absf(basis_y.y)
	)
	var minimum_step := INF
	for index: int in range(1, world_points.size()):
		var distance := world_points[index].distance_to(world_points[index - 1])
		if distance > 0.001:
			minimum_step = minf(minimum_step, distance)
	var half_cell_extent := cell_extent * 0.5
	var minimum := -half_cell_extent
	var maximum := half_cell_extent
	var centerline_minimum := Vector2.ZERO
	var centerline_maximum := Vector2.ZERO
	for offset: Vector2 in world_offsets:
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
		if not world_offsets.is_empty()
		else Vector2.ZERO
	)
	var desired_extent := 0.0
	var desired_footprint := Vector2.ZERO
	var desired_axis_extent := 0.0
	var desired_cross_axis_extent := 0.0
	var visual_axis_world := Vector2.ZERO
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
		if skill_id == "wizard.laser" and not world_offsets.is_empty():
			desired_axis_extent = world_offsets.back().length()
			visual_axis_world = world_offsets.back().normalized()
			desired_cross_axis_extent = (
				_stable_laser_visual_cross_extent(cell_extent)
			)
	return {
		"contract_id": VISUAL_CONTRACT_ID,
		"canonical_geometry_contract": declared_contract,
		"skill_id": skill_id,
		"origin_world": origin_world,
		"geometry_cells": tile_points,
		"geometry_world_points": world_points,
		"geometry_world_offsets": world_offsets,
		"tile_basis_x_world": basis_x,
		"tile_basis_y_world": basis_y,
		"cell_world_extent": cell_extent,
		"geometry_centerline_world_extent": (
			centerline_maximum - centerline_minimum
		),
		"footprint_world_extent": footprint_extent,
		"desired_sprite_extent": desired_extent,
		"desired_sprite_footprint": desired_footprint,
		"desired_sprite_axis_extent": desired_axis_extent,
		"desired_sprite_cross_axis_extent": desired_cross_axis_extent,
		"visual_axis_world": visual_axis_world,
	}


static func _stable_laser_visual_cross_extent(cell_extent: Vector2) -> float:
	# The damage strip remains one isometric cell wide. Presentation uses the
	# area-equivalent screen width of that cell, which is direction invariant:
	# sqrt(64 * 32) = 45.2548 px for the canonical map projection.
	return sqrt(maxf(0.001, cell_extent.x * cell_extent.y))
