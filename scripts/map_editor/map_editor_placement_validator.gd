class_name MapEditorPlacementValidator
extends RefCounted


static func validate(document: Dictionary, asset_id: String, anchor_tile: Vector2i, layer := "ground_base", object_role := "", ignore_instance_id := "") -> Dictionary:
	var asset := MapAssetCatalogService.find_asset(asset_id)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if asset.is_empty():
		errors.append("asset_not_found")
	elif not bool(asset.get("placeable", false)):
		errors.append("asset_not_placeable")
	var footprint: Array = asset.get("footprint_tiles", [])
	if footprint.size() != 2:
		errors.append("asset_footprint_missing")
		footprint = [1, 1]
	var size: Array = document.get("design", {}).get("design_size", [0, 0])
	var footprint_size := Vector2i(int(footprint[0]), int(footprint[1]))
	if bool(asset.get("allows_edge_clipping", false)):
		if anchor_tile.x < 0 or anchor_tile.y < 0 or anchor_tile.x >= int(size[0]) or anchor_tile.y >= int(size[1]):
			errors.append("portal_anchor_out_of_bounds")
	else:
		if anchor_tile.x < 0 or anchor_tile.y < 0 or anchor_tile.x + footprint_size.x > int(size[0]) or anchor_tile.y + footprint_size.y > int(size[1]):
			errors.append("footprint_out_of_bounds")
	if str(asset.get("asset_type", "")) == "ground_brush" and layer != "ground_base":
		warnings.append("ground_brush_recommended_on_ground_base")
	if str(asset.get("content_layer", "")) == "vanilla":
		warnings.append("vanilla_asset_read_only_use_expansion_clone")
	var collision_policy := str(asset.get("collision_policy", "none"))
	if object_role == "building": collision_policy = "solid_footprint"
	elif object_role == "obstacle": collision_policy = "preset"
	if collision_policy != "none":
		for existing: Dictionary in MapEditorInstanceService.all_instances(document):
			if str(existing.get("instance_id", "")) == ignore_instance_id or str(existing.get("collision_policy", "none")) == "none":
				continue
			if _overlaps(anchor_tile, footprint_size, _tile(existing), _footprint(existing)):
				errors.append("blocked_footprint_overlap:%s" % existing.instance_id)
				break
	return {"ok": errors.is_empty(), "level": "error" if not errors.is_empty() else "warning" if not warnings.is_empty() else "ok", "errors": errors, "warnings": warnings, "asset": asset, "footprint_tiles": [footprint_size.x, footprint_size.y]}


static func _tile(instance: Dictionary) -> Vector2i:
	var tile: Array = instance.get("tile", [0, 0])
	return Vector2i(int(tile[0]), int(tile[1]))


static func _footprint(instance: Dictionary) -> Vector2i:
	var footprint: Array = instance.get("footprint_tiles", [1, 1])
	return Vector2i(int(footprint[0]), int(footprint[1]))


static func _overlaps(a_position: Vector2i, a_size: Vector2i, b_position: Vector2i, b_size: Vector2i) -> bool:
	return Rect2i(a_position, a_size).intersects(Rect2i(b_position, b_size))
