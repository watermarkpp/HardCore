class_name MapEditorWallLoopService
extends RefCounted

const SUPPORTED_CORNER_TOPOLOGIES := ["outer_corner", "inner_corner"]
const AXIS_X := "iso_x"
const AXIS_Y := "iso_y"


static func available_families() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if str(asset.get("asset_type", "")) != "wall_module":
			continue
		var family_id := str(asset.get("wall_family_id", ""))
		if family_id.is_empty() or seen.has(family_id):
			continue
		seen[family_id] = true
		result.append({
			"wall_family_id": family_id,
			"display_name": _family_display_name(family_id, str(asset.get("theme", ""))),
			"theme": str(asset.get("theme", "")),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.display_name) < str(b.display_name)
	)
	return result


static func plan_closed_rectangle(
	wall_family_id: String,
	bounds: Rect2i,
	corner_topology := "outer_corner"
) -> Dictionary:
	var errors: Array[String] = []
	if wall_family_id.is_empty():
		errors.append("wall_family_required")
	if corner_topology not in SUPPORTED_CORNER_TOPOLOGIES:
		errors.append("unsupported_corner_topology:%s" % corner_topology)
	if bounds.size.x < 3 or bounds.size.y < 3:
		errors.append("wall_loop_requires_at_least_3x3")
	if bounds.position.x < 0 or bounds.position.y < 0:
		errors.append("wall_loop_bounds_negative")
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "entries": []}

	var modules := _family_modules(wall_family_id)
	if modules.is_empty():
		return {"ok": false, "errors": ["wall_family_not_found:%s" % wall_family_id], "entries": []}
	var minimum := bounds.position
	var maximum := bounds.end - Vector2i.ONE
	var entries: Array[Dictionary] = []
	var corner_specs := [
		{"tile": minimum, "directions": ["iso_x_pos", "iso_y_pos"], "role": "corner_min_min"},
		{"tile": Vector2i(maximum.x, minimum.y), "directions": ["iso_x_neg", "iso_y_pos"], "role": "corner_max_min"},
		{"tile": maximum, "directions": ["iso_x_neg", "iso_y_neg"], "role": "corner_max_max"},
		{"tile": Vector2i(minimum.x, maximum.y), "directions": ["iso_x_pos", "iso_y_neg"], "role": "corner_min_max"},
	]
	for spec: Dictionary in corner_specs:
		var corner := _find_corner(modules, corner_topology, spec.directions)
		if corner.is_empty():
			errors.append(
				"wall_corner_missing:%s:%s"
				% [wall_family_id, ",".join(spec.directions)]
			)
			continue
		entries.append(_entry(corner, spec.tile, spec.role))

	_append_span(
		entries, errors, modules, AXIS_X,
		Vector2i(minimum.x + 1, minimum.y), bounds.size.x - 2, "edge_min_y"
	)
	_append_span(
		entries, errors, modules, AXIS_X,
		Vector2i(minimum.x + 1, maximum.y), bounds.size.x - 2, "edge_max_y"
	)
	_append_span(
		entries, errors, modules, AXIS_Y,
		Vector2i(minimum.x, minimum.y + 1), bounds.size.y - 2, "edge_min_x"
	)
	_append_span(
		entries, errors, modules, AXIS_Y,
		Vector2i(maximum.x, minimum.y + 1), bounds.size.y - 2, "edge_max_x"
	)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "entries": entries}
	return {
		"ok": true,
		"errors": [],
		"entries": entries,
		"wall_family_id": wall_family_id,
		"corner_topology": corner_topology,
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
	}


static func apply_closed_rectangle(
	document: Dictionary,
	wall_family_id: String,
	bounds: Rect2i,
	corner_topology := "outer_corner",
	layer := "terrain_base",
	replace_existing := true,
	structure_id := ""
) -> Dictionary:
	var raw_size: Array = document.get("design", {}).get("design_size", [0, 0])
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	if bounds.end.x > design_size.x or bounds.end.y > design_size.y:
		return {"ok": false, "errors": ["wall_loop_out_of_bounds"]}
	var plan := plan_closed_rectangle(wall_family_id, bounds, corner_topology)
	if not bool(plan.get("ok", false)):
		return plan
	var original_layers: Dictionary = document.layers.duplicate(true)
	var removed: Array[Dictionary] = []
	for layer_name: String in document.get("layers", {}):
		var kept: Array = []
		for instance: Dictionary in document.layers[layer_name]:
			var asset := MapAssetCatalogService.find_asset(str(instance.get("asset_id", "")))
			if (
				str(asset.get("wall_family_id", "")) == wall_family_id
				and _instance_touches_perimeter(instance, bounds)
			):
				removed.append({"layer": layer_name, "instance": instance.duplicate(true)})
				if replace_existing:
					continue
			kept.append(instance)
		document.layers[layer_name] = kept
	if not replace_existing and not removed.is_empty():
		var occupied_instance_ids: Array[String] = []
		for value: Dictionary in removed:
			occupied_instance_ids.append(str(value.instance.get("instance_id", "")))
		return {
			"ok": false,
			"errors": ["wall_loop_perimeter_occupied"],
			"occupied_instance_ids": occupied_instance_ids,
		}

	var added_ids: Array[String] = []
	var resolved_structure_id := structure_id
	if resolved_structure_id.is_empty():
		resolved_structure_id = "%s.closed_loop.%d_%d_%d_%d" % [
			str(document.get("map_id", "map")),
			bounds.position.x,
			bounds.position.y,
			bounds.size.x,
			bounds.size.y,
		]
	for planned: Dictionary in plan.entries:
		var tile: Vector2i = planned.tile
		var placed := MapEditorInstanceService.create_instance(
			document,
			str(planned.asset_id),
			"terrain",
			tile,
			layer
		)
		if not bool(placed.get("ok", false)):
			document.layers = original_layers
			return {
				"ok": false,
				"errors": ["wall_loop_place_failed:%s@%s" % [planned.asset_id, tile]]
					+ placed.get("errors", []),
			}
		var entries: Array = document.layers[layer]
		var instance: Dictionary = entries.back()
		instance["structure_id"] = resolved_structure_id
		instance["structure_role"] = str(planned.role)
		instance["generated_by"] = "MapEditorWallLoopService"
		instance["scene_intent"] = "dungeon_wall_visual_structure"
		instance["collision_policy"] = "none"
		instance["collision_profile_id"] = "none_visual"
		instance["collision_footprint_tiles"] = [0, 0]
		instance["collision_cells"] = []
		instance["navigation_policy"] = "ignore"
		instance["manual_collision_expected"] = true
		instance["map_collision_override"] = "disabled"
		entries[entries.size() - 1] = instance
		document.layers[layer] = entries
		added_ids.append(str(instance.instance_id))

	_sort_layer(document, layer)
	var loops: Array = document.design.get("wall_loops", [])
	loops = loops.filter(
		func(value: Dictionary) -> bool:
			return str(value.get("structure_id", "")) != resolved_structure_id
	)
	loops.append({
		"structure_id": resolved_structure_id,
		"wall_family_id": wall_family_id,
		"corner_topology": corner_topology,
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"visual_render_contract": "segmented_isometric_depth_v1",
		"collision_authority": "manual_by_user",
	})
	document.design["wall_loops"] = loops
	return {
		"ok": true,
		"errors": [],
		"structure_id": resolved_structure_id,
		"removed": removed,
		"removed_count": removed.size(),
		"added_instance_ids": added_ids,
		"added_count": added_ids.size(),
		"plan": plan,
	}


static func validate_closed_rectangle(
	document: Dictionary,
	wall_family_id: String,
	bounds: Rect2i,
	structure_id := ""
) -> Dictionary:
	var counts := {}
	var sockets := {}
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if not structure_id.is_empty() and str(instance.get("structure_id", "")) != structure_id:
			continue
		var asset := MapAssetCatalogService.find_asset(str(instance.get("asset_id", "")))
		if str(asset.get("wall_family_id", "")) != wall_family_id:
			continue
		var tile_raw: Array = instance.get("tile", [0, 0])
		var tile := Vector2i(int(tile_raw[0]), int(tile_raw[1]))
		for connector: Dictionary in asset.get("connectors", []):
			sockets["%d,%d:%s" % [tile.x, tile.y, str(connector.get("direction", ""))]] = true
		var footprint: Array = instance.get("footprint_tiles", asset.get("footprint_tiles", [1, 1]))
		for y in range(tile.y, tile.y + int(footprint[1])):
			for x in range(tile.x, tile.x + int(footprint[0])):
				var cell := Vector2i(x, y)
				if _is_perimeter_cell(cell, bounds):
					var key := "%d,%d" % [x, y]
					counts[key] = int(counts.get(key, 0)) + 1
	var errors: Array[String] = []
	for cell: Vector2i in _perimeter_cells(bounds):
		var key := "%d,%d" % [cell.x, cell.y]
		if int(counts.get(key, 0)) != 1:
			errors.append("wall_loop_cell_count:%s:%d" % [key, int(counts.get(key, 0))])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"perimeter_cell_count": counts.size(),
		"socket_count": sockets.size(),
	}


static func _family_modules(wall_family_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if (
			str(asset.get("asset_type", "")) == "wall_module"
			and str(asset.get("wall_family_id", "")) == wall_family_id
			and bool(asset.get("placeable", false))
		):
			result.append(asset)
	return result


static func _find_corner(
	modules: Array[Dictionary],
	topology: String,
	directions: Array
) -> Dictionary:
	var expected := directions.duplicate()
	expected.sort()
	for module: Dictionary in modules:
		if str(module.get("topology", "")) != topology:
			continue
		var actual: Array[String] = []
		for connector: Dictionary in module.get("connectors", []):
			actual.append(str(connector.get("direction", "")))
		actual.sort()
		if actual == expected:
			return module
	return {}


static func _append_span(
	entries: Array[Dictionary],
	errors: Array[String],
	modules: Array[Dictionary],
	axis: String,
	start: Vector2i,
	length: int,
	role: String
) -> void:
	var available := {}
	for module: Dictionary in modules:
		if str(module.get("topology", "")) != "straight":
			continue
		if str(module.get("axis", "")) != axis:
			continue
		var module_length := int(module.get("length_tiles", 0))
		if module_length <= 0:
			continue
		if not available.has(module_length):
			available[module_length] = []
		available[module_length].append(module)
	var decomposition := _decompose_span(length, available.keys())
	if decomposition.is_empty():
		errors.append("wall_span_unfillable:%s:%d" % [axis, length])
		return
	var cursor := start
	var variant_cursor := 0
	for module_length: int in decomposition:
		var variants: Array = available[module_length]
		var module: Dictionary = variants[variant_cursor % variants.size()]
		var entry_role := "%s_%02d" % [role, variant_cursor]
		entries.append(_entry(module, cursor, entry_role))
		cursor += Vector2i(module_length, 0) if axis == AXIS_X else Vector2i(0, module_length)
		variant_cursor += 1


static func _decompose_span(length: int, raw_lengths: Array) -> Array[int]:
	var lengths: Array[int] = []
	for value: Variant in raw_lengths:
		var number := int(value)
		if number > 0 and number <= length:
			lengths.append(number)
	lengths.sort()
	lengths.reverse()
	var best: Array = []
	var queue: Array = [{"remaining": length, "parts": []}]
	var seen := {}
	while not queue.is_empty():
		var state: Dictionary = queue.pop_front()
		var remaining := int(state.remaining)
		if remaining == 0:
			best = state.parts
			break
		if seen.has(remaining):
			continue
		seen[remaining] = true
		for module_length: int in lengths:
			if module_length > remaining:
				continue
			var parts: Array = state.parts.duplicate()
			parts.append(module_length)
			queue.append({"remaining": remaining - module_length, "parts": parts})
	var typed: Array[int] = []
	for value: Variant in best:
		typed.append(int(value))
	return typed


static func _entry(asset: Dictionary, tile: Vector2i, role: String) -> Dictionary:
	return {
		"asset_id": str(asset.get("asset_id", "")),
		"tile": tile,
		"role": role,
		"topology": str(asset.get("topology", "")),
		"connectors": asset.get("connectors", []).duplicate(true),
	}


static func _instance_touches_perimeter(instance: Dictionary, bounds: Rect2i) -> bool:
	var tile_raw: Array = instance.get("tile", [0, 0])
	var footprint: Array = instance.get("footprint_tiles", [1, 1])
	for y in range(int(tile_raw[1]), int(tile_raw[1]) + int(footprint[1])):
		for x in range(int(tile_raw[0]), int(tile_raw[0]) + int(footprint[0])):
			if _is_perimeter_cell(Vector2i(x, y), bounds):
				return true
	return false


static func _is_perimeter_cell(cell: Vector2i, bounds: Rect2i) -> bool:
	if not bounds.has_point(cell):
		return false
	var maximum := bounds.end - Vector2i.ONE
	return (
		cell.x == bounds.position.x
		or cell.x == maximum.x
		or cell.y == bounds.position.y
		or cell.y == maximum.y
	)


static func _perimeter_cells(bounds: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var maximum := bounds.end - Vector2i.ONE
	for x in range(bounds.position.x, bounds.end.x):
		result.append(Vector2i(x, bounds.position.y))
		if maximum.y != bounds.position.y:
			result.append(Vector2i(x, maximum.y))
	for y in range(bounds.position.y + 1, maximum.y):
		result.append(Vector2i(bounds.position.x, y))
		if maximum.x != bounds.position.x:
			result.append(Vector2i(maximum.x, y))
	return result


static func _sort_layer(document: Dictionary, layer: String) -> void:
	var entries: Array = document.layers.get(layer, [])
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_tile: Array = a.get("tile", [0, 0])
		var b_tile: Array = b.get("tile", [0, 0])
		var a_key := (int(a_tile[0]) + int(a_tile[1])) * 10000 + int(a_tile[0])
		var b_key := (int(b_tile[0]) + int(b_tile[1])) * 10000 + int(b_tile[0])
		return a_key < b_key
	)
	document.layers[layer] = entries


static func _family_display_name(family_id: String, theme: String) -> String:
	return {
		"orc_tomb_rough_stone_u0": "兽人古墓粗砌旧石墙",
		"cave_granite_u0": "天然洞穴花岗岩墙",
		"wooma_temple_gothic_stone_u0": "沃玛寺庙哥特旧石墙",
	}.get(family_id, "%s（%s）" % [family_id, theme])
