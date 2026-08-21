class_name MapEditorPlacementValidator
extends RefCounted


static func validate(
	document: Dictionary,
	asset_id: String,
	anchor_tile: Vector2i,
	layer := "ground_base",
	object_role := "",
	ignore_instance_id := "",
	footprint_override := []
) -> Dictionary:
	var asset := MapAssetCatalogService.find_asset(asset_id)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if asset.is_empty():
		errors.append("asset_not_found")
	elif not bool(asset.get("placeable", false)):
		errors.append("asset_not_placeable")
	var footprint: Array = (
		footprint_override
		if footprint_override is Array and footprint_override.size() == 2
		else asset.get("footprint_tiles", [])
	)
	if footprint.size() != 2:
		errors.append("asset_footprint_missing")
		footprint = [1, 1]
	var size: Array = document.get("design", {}).get("design_size", [0, 0])
	var footprint_size := Vector2i(int(footprint[0]), int(footprint[1]))
	var occupancy: Array = (
		footprint_override
		if footprint_override is Array and footprint_override.size() == 2
		else asset.get("occupancy_footprint_tiles", footprint)
	)
	if occupancy.size() != 2:
		occupancy = footprint
	var occupancy_size := Vector2i(int(occupancy[0]), int(occupancy[1]))
	if not _is_within_map_bounds(
		asset,
		anchor_tile,
		footprint_size,
		Vector2i(int(size[0]), int(size[1]))
	):
		errors.append(
			"portal_anchor_out_of_bounds"
			if bool(asset.get("allows_edge_clipping", false))
			else "footprint_out_of_bounds"
		)
	if str(asset.get("asset_type", "")) == "ground_brush" and layer != "ground_base":
		warnings.append("ground_brush_recommended_on_ground_base")
	if str(asset.get("content_layer", "")) == "vanilla":
		warnings.append("vanilla_asset_read_only_use_expansion_clone")
	var placement_rule := (
		"non_overlapping"
		if object_role in ["building", "obstacle", "terrain"]
		else "inside_map"
	)
	if placement_rule == "non_overlapping":
		for existing: Dictionary in MapEditorInstanceService.all_instances(document):
			if str(existing.get("instance_id", "")) == ignore_instance_id:
				continue
			var existing_rule := str(existing.get("placement_rule", ""))
			var existing_role := str(existing.get("object_role", "decoration"))
			if (
				existing_rule != "non_overlapping"
				and not (
					existing_rule.is_empty()
					and existing_role in ["building", "obstacle", "terrain"]
				)
			):
				continue
			if _overlaps(
				anchor_tile,
				occupancy_size,
				_tile(existing),
				_occupancy_footprint(existing)
			):
				errors.append("blocked_footprint_overlap:%s" % existing.instance_id)
				break
	return {"ok": errors.is_empty(), "level": "error" if not errors.is_empty() else "warning" if not warnings.is_empty() else "ok", "errors": errors, "warnings": warnings, "asset": asset, "footprint_tiles": [footprint_size.x, footprint_size.y]}


static func _is_within_map_bounds(
	asset: Dictionary,
	anchor_tile: Vector2i,
	footprint_size: Vector2i,
	design_size: Vector2i
) -> bool:
	if design_size.x <= 0 or design_size.y <= 0:
		return false
	if bool(asset.get("allows_edge_clipping", false)):
		return MapEditorCoordinate.contains_tile(
			Vector2(anchor_tile),
			design_size
		)
	if str(asset.get("asset_type", "")) == "ground_brush":
		return (
			anchor_tile.x >= 0
			and anchor_tile.y >= 0
			and anchor_tile.x + footprint_size.x <= design_size.x
			and anchor_tile.y + footprint_size.y <= design_size.y
		)
	if anchor_tile.x < 0 or anchor_tile.y < 0:
		return false
	# The sprite and selection rectangle are visual geometry, not a map
	# boundary. Keep the same placement anchor used by the canvas inside the
	# map so large props may overhang the right/bottom edges just as they
	# already overhang the left/top edges.
	var placement_anchor := Vector2(anchor_tile) + Vector2(0.5, 0.5)
	if str(asset.get("asset_type", "")) != "wall_module":
		placement_anchor = (
			Vector2(anchor_tile)
			+ Vector2(footprint_size) * 0.5
		)
	return (
		placement_anchor.x >= 0.0
		and placement_anchor.y >= 0.0
		and placement_anchor.x < float(design_size.x)
		and placement_anchor.y < float(design_size.y)
	)


static func _tile(instance: Dictionary) -> Vector2i:
	var tile: Array = instance.get("tile", [0, 0])
	return Vector2i(int(tile[0]), int(tile[1]))


static func _footprint(instance: Dictionary) -> Vector2i:
	var footprint: Array = instance.get("footprint_tiles", [1, 1])
	return Vector2i(int(footprint[0]), int(footprint[1]))


static func _occupancy_footprint(instance: Dictionary) -> Vector2i:
	var footprint: Array = instance.get(
		"occupancy_footprint_tiles",
		instance.get("footprint_tiles", [1, 1])
	)
	return Vector2i(int(footprint[0]), int(footprint[1]))


static func _overlaps(a_position: Vector2i, a_size: Vector2i, b_position: Vector2i, b_size: Vector2i) -> bool:
	return Rect2i(a_position, a_size).intersects(Rect2i(b_position, b_size))
