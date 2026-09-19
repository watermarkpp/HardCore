extends RefCounted
## Per-instance polygons use image-local pixels with the SAME anchor transform.
## No guessed ownership of legacy cells; copy/delete keep the field naturally.
const FIELD := "hc_collision_local_px"
const CONTRACT := "hc.material.texture_pixels.v1"
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const Visual := preload("res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd")

static func instances(document: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_layer: Variant in document.get("layers", {}).values():
		if not raw_layer is Array:
			continue
		for raw: Variant in raw_layer:
			if raw is Dictionary and raw.has("instance_id"):
				result.append(raw)
	return result

static func locate(document: Dictionary, id: String) -> Dictionary:
	for layer: String in document.get("layers", {}):
		var items: Variant = document.layers[layer]
		if not items is Array:
			continue
		for i: int in range(items.size()):
			if items[i] is Dictionary and str(items[i].get("instance_id", "")) == id:
				return {"ok": true, "layer": layer, "index": i, "instance": items[i]}
	return {"ok": false, "errors": ["material_instance_missing:%s" % id]}

static func pair(raw: Variant, fallback: Vector2) -> Vector2:
	if not raw is Array or raw.size() != 2 or not Geo.numeric(raw[0]) or not Geo.numeric(raw[1]):
		return fallback
	return Vector2(float(raw[0]), float(raw[1]))

static func frame(instance: Dictionary, asset: Dictionary, size_gu: Vector2i) -> Dictionary:
	var tile := pair(instance.get("tile"), Vector2.INF)
	var scale_px := pair(instance.get("scale", [1, 1]), Vector2.INF)
	var offset := pair(instance.get("offset_px", [0, 0]), Vector2.INF)
	var footprint := pair(instance.get("footprint_tiles", asset.get("footprint_tiles", [1, 1])), Vector2.INF)
	var anchor := pair(instance.get("anchor_px", instance.get("placement_anchor_px", asset.get("anchor_px", [0, 0]))), Vector2.INF)
	var angle_raw: Variant = instance.get("rotation_deg", 0.0)
	if not tile.is_finite() or not scale_px.is_finite() or not offset.is_finite() or not footprint.is_finite() or not anchor.is_finite() or not Geo.numeric(angle_raw):
		return {"ok": false, "errors": ["material_transform_invalid"]}
	if size_gu.x <= 0 or size_gu.y <= 0 or footprint.x <= 0.0 or footprint.y <= 0.0:
		return {"ok": false, "errors": ["material_size_invalid"]}
	if absf(scale_px.x) <= Geo.EPS or absf(scale_px.y) <= Geo.EPS:
		return {"ok": false, "errors": ["material_transform_singular"]}
	var foot := Visual.instance_foot_tile(instance, asset)
	var center := Coord.ground_position_gu_to_screen_position_px(foot, size_gu) + offset
	var transform := Transform2D(deg_to_rad(float(angle_raw)), scale_px, 0.0, center)
	# Texture coordinates, not merely the pivot: later anchor calibration must
	# move the bound contour exactly as it moves the corresponding image pixels.
	transform.origin = center - transform.basis_xform(anchor)
	return {"ok": true, "transform": transform, "foot_world_px": center}

static func to_ground(local: PackedVector2Array, instance: Dictionary, asset: Dictionary, size_gu: Vector2i) -> PackedVector2Array:
	var checked := frame(instance, asset, size_gu)
	var result := PackedVector2Array()
	if not checked.ok:
		return result
	var transform: Transform2D = checked.transform
	for point: Vector2 in local:
		result.append(Coord.screen_position_px_to_ground_position_gu(transform * point, size_gu))
	return result

static func to_local(points: PackedVector2Array, instance: Dictionary, asset: Dictionary, size_gu: Vector2i) -> PackedVector2Array:
	var checked := frame(instance, asset, size_gu)
	var result := PackedVector2Array()
	if not checked.ok:
		return result
	var transform: Transform2D = checked.transform
	var inverse := transform.affine_inverse()
	for point: Vector2 in points:
		result.append(inverse * Coord.ground_position_gu_to_screen_position_px(point, size_gu))
	return result

static func gather(document: Dictionary) -> Dictionary:
	var records: Array[Dictionary] = []
	var errors: Array[String] = []
	var size_gu := Geo.parse_size(document.get("design", {}).get("design_size", []))
	for raw: Variant in document.get("layers", {}).get("collision", []):
		if not raw is Dictionary:
			errors.append("polygon_entry_not_dictionary")
			continue
		var record: Dictionary = raw.duplicate(true)
		record["owner"] = ""
		record["local_id"] = ""
		var data: Variant = raw.get("data", {})
		if not data is Dictionary:
			errors.append("polygon_data_not_dictionary")
			continue
		record["points"] = Geo.decode(data.get("points", []))
		records.append(record)
	for instance: Dictionary in instances(document):
		if not bool(instance.get("runtime_export", true)) or not instance.has(FIELD):
			continue
		var polygons: Variant = instance[FIELD]
		if not polygons is Array:
			errors.append("bound_polygon_array_invalid:%s" % str(instance.get("instance_id", "")))
			continue
		var asset := MapAssetCatalogService.find_asset(str(instance.get("asset_id", "")))
		var seen: Dictionary = {}
		for local_record: Variant in polygons:
			if not local_record is Dictionary:
				errors.append("bound_polygon_record_invalid")
				continue
			var id := str(local_record.get("id", ""))
			if id.is_empty() or seen.has(id) or str(local_record.get("contract_id", "")) != CONTRACT:
				errors.append("bound_polygon_id_or_contract_invalid")
				continue
			seen[id] = true
			var points := to_ground(Geo.decode(local_record.get("points", [])), instance, asset, size_gu)
			var owner := str(instance.instance_id)
			records.append({"collision_id": "bound:%s:%s" % [owner, id], "shape": "polygon",
				"data": {"points": Geo.encode(points)}, "points": points,
				"source": "bound_material", "owner": owner, "local_id": id,
				"blocks_player": true, "blocks_monster": true,
				"content_layer": str(local_record.get("content_layer", "personal_expansion"))})
	return {"ok": errors.is_empty(), "errors": errors, "records": records}

static func next_local_id(records: Array) -> String:
	var used: Dictionary = {}
	for record: Dictionary in records:
		used[str(record.get("id", ""))] = true
	var number := records.size() + 1
	while used.has("local_%06d" % number):
		number += 1
	return "local_%06d" % number

static func put_local(document: Dictionary, owner: String, points: PackedVector2Array, local_id := "") -> Dictionary:
	var found := locate(document, owner)
	if not found.ok:
		return found
	var instance: Dictionary = found.instance
	if bool(instance.get("selection_locked", false)) or not bool(instance.get("runtime_export", true)):
		return {"ok": false, "errors": ["bound_owner_locked_or_not_exported"]}
	var size_gu := Geo.parse_size(document.get("design", {}).get("design_size", []))
	var checked := Geo.validate(Geo.encode(points), size_gu)
	if not checked.ok:
		return checked
	var asset := MapAssetCatalogService.find_asset(str(instance.get("asset_id", "")))
	var local := to_local(checked.points, instance, asset, size_gu)
	if local.size() != points.size():
		return {"ok": false, "errors": ["bound_transform_failed"]}
	var entries: Array = instance.get(FIELD, []).duplicate(true)
	var target := -1
	for i: int in range(entries.size()):
		if str(entries[i].get("id", "")) == local_id:
			target = i
	if local_id.is_empty():
		local_id = next_local_id(entries)
	elif target < 0:
		return {"ok": false, "errors": ["bound_polygon_missing"]}
	var row := {"id": local_id, "contract_id": CONTRACT, "points": Geo.encode(local),
		"content_layer": "personal_expansion"}
	if target < 0:
		entries.append(row)
	else:
		entries[target] = row
	instance[FIELD] = entries
	document.layers[found.layer][found.index] = instance
	return {"ok": true, "local_id": local_id}

static func remove(document: Dictionary, record: Dictionary) -> bool:
	var owner := str(record.get("owner", ""))
	if owner.is_empty():
		var entries: Array = document.layers.get("collision", [])
		for i: int in range(entries.size()):
			if str(entries[i].get("collision_id", "")) == str(record.get("collision_id", "")):
				entries.remove_at(i)
				document.layers.collision = entries
				return true
		return false
	var found := locate(document, owner)
	if not found.ok:
		return false
	var entries: Array = found.instance.get(FIELD, []).duplicate(true)
	for i: int in range(entries.size()):
		if str(entries[i].get("id", "")) == str(record.get("local_id", "")):
			entries.remove_at(i)
			found.instance[FIELD] = entries
			document.layers[found.layer][found.index] = found.instance
			return true
	return false
