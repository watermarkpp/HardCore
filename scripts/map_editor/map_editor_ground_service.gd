class_name MapEditorGroundService
extends RefCounted

const GROUND_SCHEMA_VERSION := 1
const MANIFEST_FILE := "ground_manifest.json"
const STATE_FILE := "ground_state.json"
static var _normalized_ground_image_cache: Dictionary = {}


static func initialize(document: Dictionary) -> Dictionary:
	var errors := MapEditorTypes.validate_document(document)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var root := workspace_root(document)
	_sync_document_ground_contract(document, root)
	var manifest_path := root.path_join("ground").path_join(MANIFEST_FILE)
	var state_path := root.path_join("ground").path_join(STATE_FILE)
	var manifest := _read_json(manifest_path)
	var manifest_changed := false
	if manifest.is_empty():
		manifest = _new_manifest(document)
		manifest_changed = true
	elif _sync_blank_policy(document, manifest):
		manifest_changed = true
	var state := _read_json(state_path)
	var state_changed := false
	if state.is_empty():
		state = {"schema_version": GROUND_SCHEMA_VERSION, "map_id": document.map_id, "dirty_chunks": [], "operations_by_chunk": {}}
		state_changed = true
	var contract_sync := _sync_coordinate_contract(manifest, state)
	manifest_changed = manifest_changed or bool(contract_sync.manifest_changed)
	state_changed = state_changed or bool(contract_sync.state_changed)
	if manifest_changed:
		var write_manifest := _write_json_atomic(manifest_path, manifest)
		if not write_manifest.ok:
			return write_manifest
	if state_changed:
		var write_state := _write_json_atomic(state_path, state)
		if not write_state.ok:
			return write_state
	return {"ok": true, "manifest": manifest, "state": state, "manifest_path": manifest_path, "state_path": state_path}


static func record_tile_paint(document: Dictionary, tile: Vector2i, asset_id: String) -> Dictionary:
	return _record_operation(document, tile, {"op": "paint_tile", "asset_id": asset_id})


static func record_tile_erase(document: Dictionary, tile: Vector2i) -> Dictionary:
	return _record_operation(document, tile, {"op": "erase_tile"})


static func record_tile_paint_batch(document: Dictionary, paints: Array[Dictionary]) -> Dictionary:
	return _record_tile_batch(document, paints)


static func record_tile_erase_batch(document: Dictionary, tiles: Array[Vector2i]) -> Dictionary:
	var operations: Array[Dictionary] = []
	for tile: Vector2i in tiles:
		operations.append({"op": "erase_tile", "tile": [tile.x, tile.y]})
	return _record_tile_batch(document, operations)


static func _record_tile_batch(document: Dictionary, paints: Array[Dictionary]) -> Dictionary:
	var initialized := initialize(document)
	if not initialized.ok:
		return initialized
	var design_size := _design_size(document)
	var manifest: Dictionary = initialized.manifest
	var state: Dictionary = initialized.state
	var chunk_size := Vector2i(int(manifest.chunk_size_px[0]), int(manifest.chunk_size_px[1]))
	var chunks: Array = manifest.chunks
	var operations_by_chunk: Dictionary = state.operations_by_chunk
	var changed_chunks := {}
	for paint: Dictionary in paints:
		var raw_tile: Array = paint.get("tile", [])
		var operation_type := str(paint.get("op", "paint_tile"))
		var asset_id := str(paint.get("asset_id", ""))
		if raw_tile.size() != 2 or operation_type not in ["paint_tile", "erase_tile"] or (operation_type == "paint_tile" and asset_id.is_empty()):
			return {"ok": false, "errors": ["invalid_batch_paint"]}
		var tile := Vector2i(int(raw_tile[0]), int(raw_tile[1]))
		if not MapEditorCoordinate.contains_tile(tile, design_size):
			return {"ok": false, "errors": ["tile_out_of_bounds"]}
		var ground_px := MapEditorCoordinate.cell_center_to_ground_px(tile, design_size)
		var chunk_id := chunk_id_for_grid(MapEditorCoordinate.chunk_grid_for_ground_px(ground_px, chunk_size))
		var chunk_index := -1
		for index in chunks.size():
			if str(chunks[index].get("chunk_id", "")) == chunk_id:
				chunk_index = index
				break
		if chunk_index < 0:
			return {"ok": false, "errors": ["chunk_not_found:%s" % chunk_id]}
		var chunk: Dictionary = chunks[chunk_index]
		chunk.state = "dirty"; chunk.materialized = true; chunk.workspace_chunk = "ground/chunks/%s.json" % chunk_id
		chunks[chunk_index] = chunk
		var operations: Array = operations_by_chunk.get(chunk_id, [])
		var operation := {"op": operation_type, "tile": [tile.x, tile.y]}
		if operation_type == "paint_tile": operation["asset_id"] = asset_id
		operations.append(operation)
		operations_by_chunk[chunk_id] = operations
		changed_chunks[chunk_id] = true
	manifest.chunks = chunks
	state.operations_by_chunk = operations_by_chunk
	var dirty_chunks: Array = state.dirty_chunks
	for chunk_id: String in changed_chunks:
		if not dirty_chunks.has(chunk_id): dirty_chunks.append(chunk_id)
		var chunk_path := workspace_root(document).path_join("ground/chunks/%s.json" % chunk_id)
		var write_chunk := _write_json_atomic(chunk_path, {"schema_version": GROUND_SCHEMA_VERSION, "chunk_id": chunk_id, "operations": operations_by_chunk[chunk_id]})
		if not write_chunk.ok: return write_chunk
	dirty_chunks.sort(); state.dirty_chunks = dirty_chunks
	var save_result := save_manifest_and_state(str(initialized.manifest_path), manifest, str(initialized.state_path), state)
	if not save_result.ok: return save_result
	return {"ok": true, "painted_count": paints.size(), "dirty_count": dirty_chunks.size(), "state": state, "manifest": manifest}


static func tile_overrides(state: Dictionary) -> Dictionary:
	var overrides := {}
	for chunk_id: String in state.get("operations_by_chunk", {}):
		for operation: Dictionary in state.operations_by_chunk.get(chunk_id, []):
			var tile: Array = operation.get("tile", [])
			if tile.size() != 2:
				continue
			var key := "%d,%d" % [int(tile[0]), int(tile[1])]
			if str(operation.get("op", "")) == "paint_tile":
				overrides[key] = str(operation.get("asset_id", ""))
			elif str(operation.get("op", "")) == "erase_tile":
				overrides.erase(key)
	return overrides


static func normalized_ground_image(asset_id: String) -> Image:
	if _normalized_ground_image_cache.has(asset_id):
		return _normalized_ground_image_cache[asset_id]
	var asset := MapAssetCatalogService.find_asset(asset_id)
	var image_path := str(asset.get("image", ""))
	if image_path.is_empty():
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://" + image_path))
	if image == null or image.is_empty():
		return null
	var visible_rect := image.get_used_rect()
	if visible_rect.size.x > 0 and visible_rect.size.y > 0 and visible_rect != Rect2i(Vector2i.ZERO, image.get_size()):
		image = image.get_region(visible_rect)
	if image.get_size() != Vector2i(64, 32):
		image.resize(64, 32, Image.INTERPOLATE_BILINEAR)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var diamond_distance := absf((float(x) + 0.5 - 32.0) / 32.0) + absf((float(y) + 0.5 - 16.0) / 16.0)
			if diamond_distance > 1.0:
				var pixel := image.get_pixel(x, y)
				pixel.a = 0.0
				image.set_pixel(x, y, pixel)
	_normalized_ground_image_cache[asset_id] = image
	return image


static func save_manifest_and_state(manifest_path: String, manifest: Dictionary, state_path: String, state: Dictionary) -> Dictionary:
	var write_manifest := _write_json_atomic(manifest_path, manifest)
	if not write_manifest.ok:
		return write_manifest
	return _write_json_atomic(state_path, state)


static func _record_operation(document: Dictionary, tile: Vector2i, operation_data: Dictionary) -> Dictionary:
	var initialized := initialize(document)
	if not initialized.ok:
		return initialized
	var design_size := _design_size(document)
	if not MapEditorCoordinate.contains_tile(tile, design_size):
		return {"ok": false, "errors": ["tile_out_of_bounds"]}
	if str(operation_data.get("op", "")) == "paint_tile" and str(operation_data.get("asset_id", "")).is_empty():
		return {"ok": false, "errors": ["asset_id_missing"]}
	var manifest: Dictionary = initialized.manifest
	var state: Dictionary = initialized.state
	var chunk_size := Vector2i(int(manifest.chunk_size_px[0]), int(manifest.chunk_size_px[1]))
	var ground_px := MapEditorCoordinate.cell_center_to_ground_px(tile, design_size)
	var grid := MapEditorCoordinate.chunk_grid_for_ground_px(ground_px, chunk_size)
	var chunk_id := chunk_id_for_grid(grid)
	var chunks: Array = manifest.chunks
	var found := false
	for index in chunks.size():
		var chunk: Dictionary = chunks[index]
		if str(chunk.chunk_id) == chunk_id:
			chunk.state = "dirty"
			chunk.materialized = true
			chunk.workspace_chunk = "ground/chunks/%s.json" % chunk_id
			chunks[index] = chunk
			found = true
			break
	if not found:
		return {"ok": false, "errors": ["chunk_not_found"]}
	manifest.chunks = chunks
	var operations_by_chunk: Dictionary = state.operations_by_chunk
	var operations: Array = operations_by_chunk.get(chunk_id, [])
	var operation := operation_data.duplicate(true)
	operation["tile"] = [tile.x, tile.y]
	operations.append(operation)
	operations_by_chunk[chunk_id] = operations
	state.operations_by_chunk = operations_by_chunk
	var dirty_chunks: Array = state.dirty_chunks
	if not dirty_chunks.has(chunk_id):
		dirty_chunks.append(chunk_id)
		dirty_chunks.sort()
	state.dirty_chunks = dirty_chunks
	var root := workspace_root(document)
	var chunk_path := root.path_join("ground/chunks/%s.json" % chunk_id)
	var write_chunk := _write_json_atomic(chunk_path, {"schema_version": GROUND_SCHEMA_VERSION, "chunk_id": chunk_id, "operations": operations})
	if not write_chunk.ok:
		return write_chunk
	var save_result := save_manifest_and_state(str(initialized.manifest_path), manifest, str(initialized.state_path), state)
	if not save_result.ok:
		return save_result
	return {"ok": true, "chunk_id": chunk_id, "ground_px": ground_px, "dirty_count": dirty_chunks.size(), "manifest": manifest, "state": state}


static func workspace_root(document: Dictionary) -> String:
	return str(document.get("editor_meta", {}).get("workspace", "res://map_editor_workspace/%s" % document.get("map_id", "unknown")))


static func chunk_id_for_grid(grid: Vector2i) -> String:
	return "c_%d_%d" % [grid.x, grid.y]


static func _new_manifest(document: Dictionary) -> Dictionary:
	var design_size := _design_size(document)
	var pixel_size := MapEditorCoordinate.ground_image_size(design_size)
	var ground: Dictionary = document.ground
	var chunk_size := Vector2i(int(ground.chunk_size[0]), int(ground.chunk_size[1]))
	var columns := ceili(float(pixel_size.x) / float(chunk_size.x))
	var rows := ceili(float(pixel_size.y) / float(chunk_size.y))
	var default_fill_asset_id := str(ground.get("blank_fill_asset_id", ""))
	var blank_chunk_policy := str(ground.get("blank_chunk_policy", "transparent_until_painted"))
	var chunks: Array = []
	for y in rows:
		for x in columns:
			var position := Vector2i(x * chunk_size.x, y * chunk_size.y)
			var extent := Vector2i(mini(chunk_size.x, pixel_size.x - position.x), mini(chunk_size.y, pixel_size.y - position.y))
			chunks.append({
				"chunk_id": chunk_id_for_grid(Vector2i(x, y)), "grid": [x, y], "rect_px": [position.x, position.y, extent.x, extent.y],
				"state": "virtual", "materialized": false, "fill_asset_id": default_fill_asset_id,
			})
	return {
		"schema_version": GROUND_SCHEMA_VERSION, "map_id": document.map_id, "design_size": [design_size.x, design_size.y],
		"ground_pixel_size": [pixel_size.x, pixel_size.y], "chunk_size_px": [chunk_size.x, chunk_size.y],
		"chunk_grid_size": [columns, rows], "blank_chunk_policy": blank_chunk_policy,
		"default_fill_asset_id": default_fill_asset_id,
		"coordinate_contract_id": MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID,
		"chunks": chunks,
	}


static func _sync_document_ground_contract(document: Dictionary, root: String) -> void:
	var design_size := _design_size(document)
	var ground: Dictionary = document.get("ground", {})
	var origin := MapEditorCoordinate.origin_px(design_size)
	ground["origin_px"] = [origin.x, origin.y]
	ground["tile_anchor_mode"] = "cell_center"
	ground["coordinate_contract_id"] = MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
	ground["workspace_manifest"] = root.path_join("ground").path_join(MANIFEST_FILE)
	ground["workspace_state"] = root.path_join("ground").path_join(STATE_FILE)
	document["ground"] = ground


static func _sync_coordinate_contract(manifest: Dictionary, state: Dictionary) -> Dictionary:
	var manifest_changed := str(manifest.get("coordinate_contract_id", "")) != MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
	var state_changed := str(state.get("coordinate_contract_id", "")) != MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
	manifest["coordinate_contract_id"] = MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
	state["coordinate_contract_id"] = MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
	var dirty_chunks: Array = state.get("dirty_chunks", [])
	var chunks: Array = manifest.get("chunks", [])
	for index in chunks.size():
		var chunk: Dictionary = chunks[index]
		if (
			bool(chunk.get("materialized", false))
			and not str(chunk.get("preview_png", "")).is_empty()
			and str(chunk.get("baked_coordinate_contract_id", "")) != MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
		):
			var chunk_id := str(chunk.get("chunk_id", ""))
			if not chunk_id.is_empty() and not dirty_chunks.has(chunk_id):
				dirty_chunks.append(chunk_id)
				state_changed = true
			if str(chunk.get("state", "")) != "dirty":
				chunk["state"] = "dirty"
				chunks[index] = chunk
				manifest_changed = true
	dirty_chunks.sort()
	state["dirty_chunks"] = dirty_chunks
	manifest["chunks"] = chunks
	return {"manifest_changed": manifest_changed, "state_changed": state_changed}


static func _sync_blank_policy(document: Dictionary, manifest: Dictionary) -> bool:
	var ground: Dictionary = document.get("ground", {})
	var expected_fill := str(ground.get("blank_fill_asset_id", ""))
	var expected_policy := str(ground.get("blank_chunk_policy", "transparent_until_painted"))
	var changed := str(manifest.get("default_fill_asset_id", "")) != expected_fill or str(manifest.get("blank_chunk_policy", "")) != expected_policy
	manifest["default_fill_asset_id"] = expected_fill
	manifest["blank_chunk_policy"] = expected_policy
	var chunks: Array = manifest.get("chunks", [])
	for index in chunks.size():
		var chunk: Dictionary = chunks[index]
		if not bool(chunk.get("materialized", false)) and str(chunk.get("fill_asset_id", "")) != expected_fill:
			chunk["fill_asset_id"] = expected_fill
			chunks[index] = chunk
			changed = true
	manifest["chunks"] = chunks
	return changed


static func _design_size(document: Dictionary) -> Vector2i:
	var size: Array = document.get("design", {}).get("design_size", [64, 64])
	return Vector2i(int(size[0]), int(size[1]))


static func _read_json(path: String) -> Dictionary:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	if not FileAccess.file_exists(resolved):
		return {}
	var file := FileAccess.open(resolved, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


static func _write_json_atomic(path: String, value: Dictionary) -> Dictionary:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var directory := resolved.get_base_dir()
	var mkdir_error := DirAccess.make_dir_recursive_absolute(directory)
	if mkdir_error != OK:
		return {"ok": false, "errors": ["ground_mkdir_failed:%d" % mkdir_error]}
	var temporary := resolved + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["ground_temp_open_failed"]}
	file.store_string(JSON.stringify(value, "  ", true, true) + "\n")
	file.flush()
	file.close()
	var parsed := _read_json(temporary)
	if parsed.is_empty():
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "errors": ["ground_temp_verify_failed"]}
	var backup := resolved + ".bak"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(resolved):
		var backup_error := DirAccess.rename_absolute(resolved, backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "errors": ["ground_backup_failed:%d" % backup_error]}
	var rename_error := DirAccess.rename_absolute(temporary, resolved)
	if rename_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, resolved)
		return {"ok": false, "errors": ["ground_promote_failed:%d" % rename_error]}
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	return {"ok": true, "path": path}
