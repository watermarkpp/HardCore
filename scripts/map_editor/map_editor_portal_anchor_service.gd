class_name MapEditorPortalAnchorService
extends RefCounted

const CONTRACT_ID := "linked_visual_footprint_center_v1"


static func is_portal_asset(asset: Dictionary) -> bool:
	return (
		str(asset.get("object_class", "")) == "map_entrance"
		or str(asset.get("semantic_role", "")) == "map_portal"
	)


static func trigger_tile(
	instance: Dictionary,
	asset: Dictionary,
	design_size: Vector2i
) -> Vector2i:
	var explicit: Array = instance.get("portal_trigger_tile", [])
	if explicit.size() == 2:
		return _clamp_tile(
			Vector2i(int(explicit[0]), int(explicit[1])),
			design_size
		)
	var origin_raw: Array = instance.get("tile", [0, 0])
	var footprint: Array = instance.get(
		"footprint_tiles",
		asset.get("footprint_tiles", [1, 1])
	)
	var offset: Array = instance.get(
		"portal_trigger_offset_tiles",
		asset.get("portal_trigger_offset_tiles", [])
	)
	var result := Vector2i(int(origin_raw[0]), int(origin_raw[1]))
	if offset.size() == 2:
		result += Vector2i(int(offset[0]), int(offset[1]))
	else:
		result += Vector2i(
			floori(float(footprint[0]) * 0.5),
			floori(float(footprint[1]) * 0.5)
		)
	return _clamp_tile(result, design_size)


static func synchronize_linked_semantics(
	document: Dictionary,
	instance_id: String
) -> Dictionary:
	var located := MapEditorInstanceService._locate(document, instance_id)
	if not bool(located.get("ok", false)):
		return located
	var instance: Dictionary = located.instance
	var asset := MapAssetCatalogService.find_asset(
		str(instance.get("asset_id", ""))
	)
	if not is_portal_asset(asset):
		return {"ok": true, "updated": 0}
	var size_raw: Array = document.get("design", {}).get(
		"design_size",
		[0, 0]
	)
	var design_size := Vector2i(
		int(size_raw[0]),
		int(size_raw[1])
	)
	var tile := trigger_tile(instance, asset, design_size)
	var synchronized := MapEditorGameplaySemanticService.sync_linked_instance_tile(
		document,
		instance_id,
		tile
	)
	if not bool(synchronized.get("ok", false)):
		return synchronized
	for layer_name: String in [
		"door_points",
		"map_entrance_points",
		"map_exit_points",
	]:
		var entries: Array = document.get("layers", {}).get(layer_name, [])
		for index in entries.size():
			if (
				str(entries[index].get("linked_visual_instance_id", ""))
				!= instance_id
			):
				continue
			entries[index]["portal_anchor_contract_id"] = CONTRACT_ID
			entries[index]["portal_visual_origin_tile"] = (
				instance.get("tile", [0, 0]).duplicate()
			)
			entries[index]["portal_visual_footprint_tiles"] = (
				instance.get(
					"footprint_tiles",
					asset.get("footprint_tiles", [1, 1])
				).duplicate()
			)
		document.layers[layer_name] = entries
	synchronized["tile"] = tile
	synchronized["contract_id"] = CONTRACT_ID
	return synchronized


static func _clamp_tile(tile: Vector2i, design_size: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(tile.x, 0, maxi(0, design_size.x - 1)),
		clampi(tile.y, 0, maxi(0, design_size.y - 1))
	)
