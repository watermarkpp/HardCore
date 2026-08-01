class_name CasterSpellGeometry
extends RefCounted

const CombatDirectionSpaceScript := preload(
	"res://scripts/skills/combat_direction_space.gd"
)

const CONTRACT_ID := "skills.visual.geometry_cells.world_projection.v1"
const VISUAL_CONTRACT_ID := "skills.caster.geometry_visual_alignment.v1"


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
		context["desired_sprite_extent"] = maxf(cell_extent.x, cell_extent.y)
		context["desired_sprite_footprint"] = cell_extent
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
		"geometry_origin_world", fallback_origin_world
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
	if skill_id == "wizard.hellfire":
		desired_extent = maxf(cell_extent.x, cell_extent.y)
		desired_footprint = cell_extent
		if desired_extent <= 0.0 and minimum_step < INF:
			desired_extent = minimum_step
	elif skill_id in ["wizard.hell_lightning", "wizard.laser"]:
		desired_extent = maxf(
			centerline_maximum.x - centerline_minimum.x,
			centerline_maximum.y - centerline_minimum.y
		)
		desired_footprint = footprint_extent
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
	}
