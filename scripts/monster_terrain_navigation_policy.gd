class_name MonsterTerrainNavigationPolicy
extends RefCounted

## Static terrain-only navigation for canonical monster Ground-GU movement.
## Dynamic actors remain owned by physics/crowd steering; this policy never
## scans combat targets or changes movement speed/cadence.

const CONTRACT_ID := "monster.terrain_navigation.formal_runtime.v1"
const EXPECTED_GROUND_COORDINATE_CONTRACT_ID := "isometric_cell_center_64x32_v2"
const MAX_PATH_QUERIES_PER_PHYSICS_FRAME := 2
const MAX_PATH_EXPANSIONS := 384
const PATH_BOUNDS_MARGIN_CELLS := 8
const MAX_CACHED_WAYPOINTS := 8
const NO_PATH_COOLDOWN_MS := 500

const NEIGHBORS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]

static var _budget_physics_frame := -1
static var _queries_this_physics_frame := 0
static var _path_query_count := 0
static var _path_budget_rejection_count := 0
static var _path_expansion_count := 0


static func build_context(
	runtime_map_id: int,
	runtime: Dictionary,
	ground_coordinate_contract_id: String,
) -> Dictionary:
	var invalid := {
		"contract_id": CONTRACT_ID,
		"valid": false,
		"runtime_map_id": runtime_map_id,
		"reason": "invalid_runtime",
	}
	if runtime_map_id < 0 or runtime.is_empty():
		return _read_only(invalid)
	if ground_coordinate_contract_id != EXPECTED_GROUND_COORDINATE_CONTRACT_ID:
		invalid["reason"] = "coordinate_contract_mismatch"
		return _read_only(invalid)
	var source: Dictionary = runtime.get("source", {})
	if int(source.get("runtime_map_id", -1)) != runtime_map_id:
		invalid["reason"] = "runtime_map_id_mismatch"
		return _read_only(invalid)
	var build_sha256 := str(runtime.get("build_sha256", ""))
	if build_sha256.length() != 64 or not build_sha256.is_valid_hex_number():
		invalid["reason"] = "invalid_build_sha256"
		return _read_only(invalid)
	var design: Dictionary = runtime.get("design", {})
	var raw_design_size: Variant = design.get("design_size", [])
	if not raw_design_size is Array or raw_design_size.size() < 2:
		invalid["reason"] = "missing_design_size"
		return _read_only(invalid)
	var design_size := Vector2i(
		int(round(float(raw_design_size[0]))),
		int(round(float(raw_design_size[1])))
	)
	if design_size.x <= 0 or design_size.y <= 0:
		invalid["reason"] = "invalid_design_size"
		return _read_only(invalid)
	var collision: Dictionary = runtime.get("collision", {})
	var raw_blocked: Variant = collision.get("blocked_tiles", null)
	if not raw_blocked is Array:
		invalid["reason"] = "missing_blocked_tiles"
		return _read_only(invalid)
	var blocked: Dictionary = {}
	for raw_key: Variant in raw_blocked:
		var parsed := _parse_cell_key(str(raw_key))
		if not bool(parsed.get("valid", false)):
			invalid["reason"] = "invalid_blocked_tile"
			return _read_only(invalid)
		var cell: Vector2i = parsed.get("cell", Vector2i.ZERO)
		if not _cell_inside_design(cell, design_size):
			invalid["reason"] = "blocked_tile_out_of_bounds"
			return _read_only(invalid)
		blocked[cell] = true
	blocked.make_read_only()
	var context := {
		"contract_id": CONTRACT_ID,
		"valid": true,
		"runtime_map_id": runtime_map_id,
		"build_sha256": build_sha256,
		"coordinate_contract_id": ground_coordinate_contract_id,
		"design_size": design_size,
		"blocked_cells": blocked,
		"blocked_count": blocked.size(),
	}
	context.make_read_only()
	return context


static func context_valid(context: Dictionary, expected_runtime_map_id := -1) -> bool:
	if not bool(context.get("valid", false)):
		return false
	if str(context.get("contract_id", "")) != CONTRACT_ID:
		return false
	if (
		str(context.get("coordinate_contract_id", ""))
		!= EXPECTED_GROUND_COORDINATE_CONTRACT_ID
	):
		return false
	if expected_runtime_map_id >= 0 and int(context.get("runtime_map_id", -1)) != expected_runtime_map_id:
		return false
	var design_size: Variant = context.get("design_size")
	var blocked_cells: Variant = context.get("blocked_cells")
	return (
		design_size is Vector2i
		and design_size.x > 0
		and design_size.y > 0
		and blocked_cells is Dictionary
		and str(context.get("build_sha256", "")).length() == 64
	)


static func cell_walkable(
	context: Dictionary,
	cell: Vector2i,
	combat_radius_gu: float,
	extra_blocked_cell := Vector2i(-2147483648, -2147483648),
) -> bool:
	if not context_valid(context):
		return false
	var design_size: Vector2i = context.get("design_size", Vector2i.ZERO)
	if not _cell_inside_design(cell, design_size):
		return false
	if cell == extra_blocked_cell:
		return false
	var blocked: Dictionary = context.get("blocked_cells", {})
	if blocked.has(cell):
		return false
	var radius := maxf(0.0, combat_radius_gu)
	var center := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
	if (
		center.x - radius < 0.0
		or center.y - radius < 0.0
		or center.x + radius > float(design_size.x)
		or center.y + radius > float(design_size.y)
	):
		return false
	if radius <= 0.0:
		return true
	var search_radius := ceili(radius + 0.5)
	for offset_y in range(-search_radius, search_radius + 1):
		for offset_x in range(-search_radius, search_radius + 1):
			var blocked_cell := cell + Vector2i(offset_x, offset_y)
			if not blocked.has(blocked_cell):
				continue
			var blocked_center := Vector2(
				float(blocked_cell.x) + 0.5,
				float(blocked_cell.y) + 0.5
			)
			var delta := (center - blocked_center).abs() - Vector2(0.5, 0.5)
			var nearest_distance := Vector2(
				maxf(0.0, delta.x),
				maxf(0.0, delta.y)
			).length()
			if nearest_distance + 0.000001 < radius:
				return false
	return true


static func can_traverse_neighbor(
	context: Dictionary,
	from_cell: Vector2i,
	to_cell: Vector2i,
	combat_radius_gu: float,
	extra_blocked_cell := Vector2i(-2147483648, -2147483648),
) -> bool:
	var delta := to_cell - from_cell
	if delta == Vector2i.ZERO or abs(delta.x) > 1 or abs(delta.y) > 1:
		return false
	if not cell_walkable(context, to_cell, combat_radius_gu, extra_blocked_cell):
		return false
	if delta.x != 0 and delta.y != 0:
		# No diagonal corner cutting: both cardinal shoulders must fit the same
		# combat footprint before the diagonal destination is accepted.
		if not cell_walkable(
			context,
			from_cell + Vector2i(delta.x, 0),
			combat_radius_gu,
			extra_blocked_cell,
		):
			return false
		if not cell_walkable(
			context,
			from_cell + Vector2i(0, delta.y),
			combat_radius_gu,
			extra_blocked_cell,
		):
			return false
	return true


static func static_line_of_sight_clear(
	context: Dictionary,
	start_ground_gu: Vector2,
	end_ground_gu: Vector2,
) -> bool:
	if not context_valid(context) or not start_ground_gu.is_finite() or not end_ground_gu.is_finite():
		return false
	var current := Vector2i(floori(start_ground_gu.x), floori(start_ground_gu.y))
	var finish := Vector2i(floori(end_ground_gu.x), floori(end_ground_gu.y))
	if _cell_blocks_los(context, current) or _cell_blocks_los(context, finish):
		return false
	if current == finish:
		return true
	var delta := end_ground_gu - start_ground_gu
	var step_x := 1 if delta.x > 0.0 else (-1 if delta.x < 0.0 else 0)
	var step_y := 1 if delta.y > 0.0 else (-1 if delta.y < 0.0 else 0)
	var t_delta_x := INF if step_x == 0 else absf(1.0 / delta.x)
	var t_delta_y := INF if step_y == 0 else absf(1.0 / delta.y)
	var next_boundary_x := float(current.x + (1 if step_x > 0 else 0))
	var next_boundary_y := float(current.y + (1 if step_y > 0 else 0))
	var t_max_x := INF if step_x == 0 else absf((next_boundary_x - start_ground_gu.x) / delta.x)
	var t_max_y := INF if step_y == 0 else absf((next_boundary_y - start_ground_gu.y) / delta.y)
	var guard := 0
	while current != finish and guard < 4096:
		guard += 1
		if is_equal_approx(t_max_x, t_max_y):
			var shoulder_x := current + Vector2i(step_x, 0)
			var shoulder_y := current + Vector2i(0, step_y)
			if _cell_blocks_los(context, shoulder_x) or _cell_blocks_los(context, shoulder_y):
				return false
			current += Vector2i(step_x, step_y)
			t_max_x += t_delta_x
			t_max_y += t_delta_y
		elif t_max_x < t_max_y:
			current.x += step_x
			t_max_x += t_delta_x
		else:
			current.y += step_y
			t_max_y += t_delta_y
		if _cell_blocks_los(context, current):
			return false
	return current == finish


static func find_bounded_path(
	context: Dictionary,
	start_cell: Vector2i,
	goal_cell: Vector2i,
	combat_radius_gu: float,
	extra_blocked_cell := Vector2i(-2147483648, -2147483648),
) -> Dictionary:
	if not context_valid(context):
		return {"accepted": false, "found": false, "reason": "invalid_context"}
	if not _claim_path_query_budget():
		return {"accepted": false, "found": false, "reason": "frame_budget_exhausted"}
	_path_query_count += 1
	if start_cell == goal_cell:
		return {"accepted": true, "found": true, "waypoints": []}
	if not cell_walkable(context, goal_cell, combat_radius_gu, extra_blocked_cell):
		return {"accepted": true, "found": false, "reason": "goal_blocked", "expansions": 0}
	var design_size: Vector2i = context.get("design_size", Vector2i.ZERO)
	var min_cell := Vector2i(
		maxi(0, mini(start_cell.x, goal_cell.x) - PATH_BOUNDS_MARGIN_CELLS),
		maxi(0, mini(start_cell.y, goal_cell.y) - PATH_BOUNDS_MARGIN_CELLS)
	)
	var max_cell := Vector2i(
		mini(design_size.x - 1, maxi(start_cell.x, goal_cell.x) + PATH_BOUNDS_MARGIN_CELLS),
		mini(design_size.y - 1, maxi(start_cell.y, goal_cell.y) + PATH_BOUNDS_MARGIN_CELLS)
	)
	var open: Array[Vector2i] = [start_cell]
	var open_members := {start_cell: true}
	var closed: Dictionary = {}
	var came_from: Dictionary = {}
	var g_score := {start_cell: 0.0}
	var f_score := {start_cell: _octile_distance(start_cell, goal_cell)}
	var expansions := 0
	while not open.is_empty() and expansions < MAX_PATH_EXPANSIONS:
		var best_index := 0
		var current := open[0]
		var best_f := float(f_score.get(current, INF))
		for index in range(1, open.size()):
			var candidate := open[index]
			var candidate_f := float(f_score.get(candidate, INF))
			if candidate_f < best_f or (
				is_equal_approx(candidate_f, best_f)
				and _cell_order_less(candidate, current)
			):
				best_index = index
				current = candidate
				best_f = candidate_f
		open.remove_at(best_index)
		open_members.erase(current)
		if current == goal_cell:
			_path_expansion_count += expansions
			return {
				"accepted": true,
				"found": true,
				"waypoints": _reconstruct_path(came_from, start_cell, goal_cell),
				"expansions": expansions,
			}
		closed[current] = true
		expansions += 1
		for neighbor_delta: Vector2i in NEIGHBORS:
			var neighbor := current + neighbor_delta
			if (
				neighbor.x < min_cell.x or neighbor.y < min_cell.y
				or neighbor.x > max_cell.x or neighbor.y > max_cell.y
				or closed.has(neighbor)
			):
				continue
			if not can_traverse_neighbor(
				context,
				current,
				neighbor,
				combat_radius_gu,
				extra_blocked_cell,
			):
				continue
			var tentative := float(g_score.get(current, INF)) + Vector2(neighbor_delta).length()
			if tentative + 0.000001 >= float(g_score.get(neighbor, INF)):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			f_score[neighbor] = tentative + _octile_distance(neighbor, goal_cell)
			if not open_members.has(neighbor):
				open.append(neighbor)
				open_members[neighbor] = true
	_path_expansion_count += expansions
	return {
		"accepted": true,
		"found": false,
		"reason": "expansion_or_bounds_limit",
		"expansions": expansions,
	}


static func reset_diagnostics() -> void:
	_budget_physics_frame = -1
	_queries_this_physics_frame = 0
	_path_query_count = 0
	_path_budget_rejection_count = 0
	_path_expansion_count = 0


static func diagnostics() -> Dictionary:
	return {
		"path_queries": _path_query_count,
		"path_budget_rejections": _path_budget_rejection_count,
		"path_expansions": _path_expansion_count,
		"queries_this_physics_frame": _queries_this_physics_frame,
		"max_queries_per_physics_frame": MAX_PATH_QUERIES_PER_PHYSICS_FRAME,
	}


static func _claim_path_query_budget() -> bool:
	var physics_frame := Engine.get_physics_frames()
	if physics_frame != _budget_physics_frame:
		_budget_physics_frame = physics_frame
		_queries_this_physics_frame = 0
	if _queries_this_physics_frame >= MAX_PATH_QUERIES_PER_PHYSICS_FRAME:
		_path_budget_rejection_count += 1
		return false
	_queries_this_physics_frame += 1
	return true


static func _reconstruct_path(
	came_from: Dictionary,
	start_cell: Vector2i,
	goal_cell: Vector2i,
) -> Array[Vector2i]:
	var reversed: Array[Vector2i] = []
	var current := goal_cell
	while current != start_cell and reversed.size() <= MAX_PATH_EXPANSIONS:
		reversed.append(current)
		if not came_from.has(current):
			return []
		current = came_from[current]
	reversed.reverse()
	var result: Array[Vector2i] = []
	for index in range(mini(reversed.size(), MAX_CACHED_WAYPOINTS)):
		result.append(reversed[index])
	return result


static func _cell_blocks_los(context: Dictionary, cell: Vector2i) -> bool:
	var design_size: Vector2i = context.get("design_size", Vector2i.ZERO)
	return (
		not _cell_inside_design(cell, design_size)
		or (context.get("blocked_cells", {}) as Dictionary).has(cell)
	)


static func _parse_cell_key(key: String) -> Dictionary:
	var parts := key.split(",", false)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return {"valid": false}
	return {
		"valid": true,
		"cell": Vector2i(int(parts[0]), int(parts[1])),
	}


static func _cell_inside_design(cell: Vector2i, design_size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < design_size.x and cell.y < design_size.y


static func _octile_distance(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var delta := (to_cell - from_cell).abs()
	var diagonal := mini(delta.x, delta.y)
	var axis := maxi(delta.x, delta.y) - diagonal
	return float(axis) + float(diagonal) * sqrt(2.0)


static func _cell_order_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _read_only(value: Dictionary) -> Dictionary:
	value.make_read_only()
	return value
