class_name MapEditorGroundService
extends RefCounted

const GROUND_SCHEMA_VERSION := 1
const MANIFEST_FILE := "ground_manifest.json"
const STATE_FILE := "ground_state.json"
const WRITE_SET_SCHEMA_VERSION := 1
const WRITE_SET_FILE := ".ground_write_set.json"
static var _normalized_ground_image_cache: Dictionary = {}


static func initialize(document: Dictionary) -> Dictionary:
	var errors := MapEditorTypes.validate_document(document)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var root := workspace_root(document)
	_sync_document_ground_contract(document, root)
	var manifest_path := root.path_join("ground").path_join(MANIFEST_FILE)
	var state_path := root.path_join("ground").path_join(STATE_FILE)
	var recovery := _recover_pending_write_set(root, str(document.get("map_id", "")))
	if not recovery.ok:
		return recovery
	var manifest_read := _read_json_checked(manifest_path)
	var state_read := _read_json_checked(state_path)
	var manifest_exists := bool(manifest_read.exists)
	var state_exists := bool(state_read.exists)
	if (manifest_exists and not manifest_read.valid) or (state_exists and not state_read.valid):
		return {"ok": false, "errors": ["ground_primary_corrupt"]}
	if (manifest_exists and (manifest_read.value as Dictionary).is_empty()) or (state_exists and (state_read.value as Dictionary).is_empty()):
		return {"ok": false, "errors": ["ground_primary_corrupt"]}
	if manifest_exists != state_exists:
		return {"ok": false, "errors": ["ground_primary_pair_incomplete"]}
	if not manifest_exists and _has_ground_artifacts(root):
		return {"ok": false, "errors": ["ground_primary_missing_with_artifacts"]}
	var manifest: Dictionary = manifest_read.value
	var manifest_changed := false
	if manifest.is_empty():
		manifest = _new_manifest(document)
		manifest_changed = true
	elif _sync_blank_policy(document, manifest):
		manifest_changed = true
	var state: Dictionary = state_read.value
	var state_changed := false
	if state.is_empty():
		state = {"schema_version": GROUND_SCHEMA_VERSION, "map_id": document.map_id, "dirty_chunks": [], "operations_by_chunk": {}}
		state_changed = true
	var contract_sync := _sync_coordinate_contract(
		manifest, state, _design_size(document)
	)
	manifest_changed = manifest_changed or bool(contract_sync.manifest_changed)
	state_changed = state_changed or bool(contract_sync.state_changed)
	if manifest_changed or state_changed:
		var write_set: Array[Dictionary] = []
		if manifest_changed:
			write_set.append({"path": manifest_path, "value": manifest})
		if state_changed:
			write_set.append({"path": state_path, "value": state})
		var write_result := _commit_write_set(root, str(document.get("map_id", "")), write_set)
		if not write_result.ok:
			return write_result
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
		var chunk_id := chunk_id_for_tile(tile, design_size, chunk_size)
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
	var write_set: Array[Dictionary] = []
	for chunk_id: String in changed_chunks:
		if not dirty_chunks.has(chunk_id): dirty_chunks.append(chunk_id)
		var chunk_path := workspace_root(document).path_join("ground/chunks/%s.json" % chunk_id)
		write_set.append({"path": chunk_path, "value": {"schema_version": GROUND_SCHEMA_VERSION, "chunk_id": chunk_id, "operations": operations_by_chunk[chunk_id]}})
	dirty_chunks.sort(); state.dirty_chunks = dirty_chunks
	write_set.append({"path": str(initialized.manifest_path), "value": manifest})
	write_set.append({"path": str(initialized.state_path), "value": state})
	var save_result := _commit_write_set(workspace_root(document), str(document.get("map_id", "")), write_set)
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
	var root := manifest_path.get_base_dir().get_base_dir()
	var map_id := str(manifest.get("map_id", state.get("map_id", "")))
	return _commit_write_set(root, map_id, [
		{"path": manifest_path, "value": manifest},
		{"path": state_path, "value": state},
	])


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
	var chunk_id := chunk_id_for_tile(tile, design_size, chunk_size)
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
	var write_set: Array[Dictionary] = [
		{"path": chunk_path, "value": {"schema_version": GROUND_SCHEMA_VERSION, "chunk_id": chunk_id, "operations": operations}},
		{"path": str(initialized.manifest_path), "value": manifest},
		{"path": str(initialized.state_path), "value": state},
	]
	var save_result := _commit_write_set(root, str(document.get("map_id", "")), write_set)
	if not save_result.ok:
		return save_result
	return {"ok": true, "chunk_id": chunk_id, "ground_px": ground_px, "dirty_count": dirty_chunks.size(), "manifest": manifest, "state": state}


static func workspace_root(document: Dictionary) -> String:
	return str(document.get("editor_meta", {}).get("workspace", "res://map_editor_workspace/%s" % document.get("map_id", "unknown")))


static func chunk_id_for_grid(grid: Vector2i) -> String:
	return "c_%d_%d" % [grid.x, grid.y]


static func chunk_id_for_tile(
	tile: Vector2i,
	design_size: Vector2i,
	chunk_size: Vector2i
) -> String:
	return chunk_id_for_grid(
		MapEditorCoordinate.chunk_grid_for_ground_px(
			MapEditorCoordinate.cell_center_to_ground_px(tile, design_size),
			chunk_size
		)
	)


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


static func _sync_coordinate_contract(
	manifest: Dictionary,
	state: Dictionary,
	design_size: Vector2i
) -> Dictionary:
	var manifest_contract_before := str(manifest.get("coordinate_contract_id", ""))
	var state_contract_before := str(state.get("coordinate_contract_id", ""))
	var contract_changed := (
		manifest_contract_before != MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
		or state_contract_before != MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
	)
	var manifest_changed := contract_changed
	var state_changed := contract_changed
	manifest["coordinate_contract_id"] = MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
	state["coordinate_contract_id"] = MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
	if contract_changed:
		var chunk_size := _manifest_chunk_size(manifest)
		if chunk_size.x > 0 and chunk_size.y > 0:
			state_changed = (
				_repartition_operations_by_chunk(
					state, design_size, chunk_size
				)
				or state_changed
			)
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
	if contract_changed:
		# The cell-center raster moved north by 16px.  Any operation bucket may
		# therefore have a different chunk owner; keep every resulting bucket
		# dirty until it is rebaked under v2.
		for raw_chunk_id: Variant in state.get("operations_by_chunk", {}).keys():
			var chunk_id := str(raw_chunk_id)
			if not chunk_id.is_empty() and not dirty_chunks.has(chunk_id):
				dirty_chunks.append(chunk_id)
				state_changed = true
	dirty_chunks.sort()
	state["dirty_chunks"] = dirty_chunks
	manifest["chunks"] = chunks
	return {"manifest_changed": manifest_changed, "state_changed": state_changed}


static func _manifest_chunk_size(manifest: Dictionary) -> Vector2i:
	var raw_chunk_size: Variant = manifest.get("chunk_size_px", [])
	if not raw_chunk_size is Array or (raw_chunk_size as Array).size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(raw_chunk_size[0]), int(raw_chunk_size[1]))


static func _repartition_operations_by_chunk(
	state: Dictionary,
	design_size: Vector2i,
	chunk_size: Vector2i
) -> bool:
	var original: Dictionary = state.get("operations_by_chunk", {})
	var repartitioned: Dictionary = {}
	for raw_bucket: Variant in original.keys():
		var bucket_id := str(raw_bucket)
		var raw_operations: Variant = original.get(raw_bucket, [])
		if not raw_operations is Array:
			repartitioned[bucket_id] = raw_operations
			continue
		for raw_operation: Variant in raw_operations:
			var target_bucket := bucket_id
			if raw_operation is Dictionary:
				var raw_tile: Variant = raw_operation.get("tile", [])
				if raw_tile is Array and (raw_tile as Array).size() == 2:
					var tile := Vector2i(
						int(raw_tile[0]), int(raw_tile[1])
					)
					if MapEditorCoordinate.contains_tile(tile, design_size):
						target_bucket = chunk_id_for_tile(
							tile, design_size, chunk_size
						)
			var target_operations: Array = repartitioned.get(
				target_bucket, []
			)
			target_operations.append(raw_operation)
			repartitioned[target_bucket] = target_operations
	if repartitioned == original:
		return false
	state["operations_by_chunk"] = repartitioned
	return true


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
	var checked := _read_json_checked(path)
	return checked.value if checked.valid else {}


static func _read_json_checked(path: String) -> Dictionary:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	if not FileAccess.file_exists(resolved):
		return {"exists": false, "valid": true, "value": {}}
	var file := FileAccess.open(resolved, FileAccess.READ)
	if file == null:
		return {"exists": true, "valid": false, "value": {}}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return {"exists": true, "valid": parsed is Dictionary, "value": parsed if parsed is Dictionary else {}}


static func _file_sha256(path: String) -> String:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	if not FileAccess.file_exists(resolved):
		return ""
	var file := FileAccess.open(resolved, FileAccess.READ)
	if file == null:
		return ""
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(file.get_buffer(file.get_length()))
	file.close()
	return hashing.finish().hex_encode()


static func _has_ground_artifacts(root: String) -> bool:
	var ground_dir := ProjectSettings.globalize_path(root.path_join("ground")).replace("\\", "/")
	var dir := DirAccess.open(ground_dir)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry not in [".", "..", WRITE_SET_FILE] and not (entry == "chunks" and dir.current_is_dir() and _directory_is_empty(ground_dir.path_join(entry))):
			dir.list_dir_end()
			return true
		entry = dir.get_next()
	dir.list_dir_end()
	return false


static func _directory_is_empty(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return true
	dir.list_dir_begin()
	var entry := dir.get_next()
	var empty := entry.is_empty()
	dir.list_dir_end()
	return empty


static func _commit_write_set(root: String, map_id: String, write_set: Array[Dictionary]) -> Dictionary:
	if write_set.is_empty():
		return {"ok": true}
	var ground_dir := ProjectSettings.globalize_path(root.path_join("ground")).replace("\\", "/")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ground_dir)
	if mkdir_error != OK:
		return {"ok": false, "errors": ["ground_mkdir_failed:%d" % mkdir_error]}
	var journal_path := ground_dir.path_join(WRITE_SET_FILE)
	if FileAccess.file_exists(journal_path):
		return {"ok": false, "errors": ["ground_write_set_pending"]}
	var token := "%d_%d" % [Time.get_ticks_usec(), randi()]
	var entries: Array[Dictionary] = []
	for item: Dictionary in write_set:
		var target := ProjectSettings.globalize_path(str(item.path)).replace("\\", "/")
		var relative := target.trim_prefix(ground_dir + "/")
		if not _valid_write_set_relative_path(relative):
			_cleanup_write_set_entries(entries)
			return {"ok": false, "errors": ["ground_txn_target_outside_workspace"]}
		var target_dir_error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if target_dir_error != OK:
			_cleanup_write_set_entries(entries)
			return {"ok": false, "errors": ["ground_txn_target_dir_failed:%d" % target_dir_error]}
		var temporary := target + ".txn." + token
		var encoded := JSON.stringify(item.value, "  ", true, true) + "\n"
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file == null:
			_cleanup_write_set_entries(entries)
			return {"ok": false, "errors": ["ground_txn_temp_open_failed"]}
		file.store_string(encoded); file.flush(); file.close()
		var checked := _read_json_checked(temporary)
		if not checked.valid:
			_cleanup_write_set_entries(entries)
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "errors": ["ground_txn_temp_verify_failed"]}
		entries.append({
			"relative_path": relative,
			"temporary_path": temporary,
			"backup_path": target + ".txnbackup." + token,
			"base_sha256": _file_sha256_or_missing(target),
			"new_sha256": _file_sha256(temporary),
		})
	var journal := {"schema_version": WRITE_SET_SCHEMA_VERSION, "map_id": map_id, "generation": token, "entries": entries}
	var journal_file := FileAccess.open(journal_path, FileAccess.WRITE)
	if journal_file == null:
		_cleanup_write_set_entries(entries)
		return {"ok": false, "errors": ["ground_txn_journal_open_failed"]}
	journal_file.store_string(JSON.stringify(journal, "  ", true, true) + "\n"); journal_file.flush(); journal_file.close()
	return _recover_pending_write_set(root, map_id)


static func _recover_pending_write_set(root: String, map_id: String) -> Dictionary:
	var ground_dir := ProjectSettings.globalize_path(root.path_join("ground")).replace("\\", "/")
	var journal_path := ground_dir.path_join(WRITE_SET_FILE)
	if not FileAccess.file_exists(journal_path):
		return {"ok": true}
	var journal_read := _read_json_checked(journal_path)
	if not journal_read.valid:
		return {"ok": false, "errors": ["ground_txn_identity_corrupt"]}
	var journal: Dictionary = journal_read.value
	var raw_schema: Variant = journal.get("schema_version", null)
	var raw_map_id: Variant = journal.get("map_id", null)
	var raw_generation: Variant = journal.get("generation", null)
	if not (raw_schema is int or raw_schema is float) or typeof(raw_map_id) != TYPE_STRING or typeof(raw_generation) != TYPE_STRING:
		return {"ok": false, "errors": ["ground_txn_identity_corrupt"]}
	if not is_finite(float(raw_schema)) or float(raw_schema) != floorf(float(raw_schema)):
		return {"ok": false, "errors": ["ground_txn_identity_corrupt"]}
	var generation := str(raw_generation)
	var generation_pattern := RegEx.new()
	generation_pattern.compile("^[0-9]+_[0-9]+$")
	if int(raw_schema) != WRITE_SET_SCHEMA_VERSION or str(raw_map_id) != map_id or generation_pattern.search(generation) == null:
		return {"ok": false, "errors": ["ground_txn_identity_mismatch"]}
	var raw_entries: Variant = journal.get("entries", null)
	if not raw_entries is Array:
		return {"ok": false, "errors": ["ground_txn_entries_invalid"]}
	var entries: Array = raw_entries
	if entries.is_empty():
		return {"ok": false, "errors": ["ground_txn_empty"]}
	var seen_paths := {}
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			return {"ok": false, "errors": ["ground_txn_entry_invalid"]}
		var entry: Dictionary = raw_entry
		var relative_path := str(entry.get("relative_path", ""))
		if not _valid_write_set_relative_path(relative_path) or seen_paths.has(relative_path):
			return {"ok": false, "errors": ["ground_txn_path_invalid"]}
		seen_paths[relative_path] = true
		var target := ground_dir.path_join(relative_path)
		var expected_temp := target + ".txn." + generation
		var expected_backup := target + ".txnbackup." + generation
		if str(entry.get("temporary_path", "")) != expected_temp or str(entry.get("backup_path", "")) != expected_backup:
			return {"ok": false, "errors": ["ground_txn_path_invalid"]}
		var current := _file_sha256_or_missing(target)
		var base := str(entry.get("base_sha256", ""))
		var intended := str(entry.get("new_sha256", ""))
		if not _valid_write_set_hash(base, true) or not _valid_write_set_hash(intended, false):
			return {"ok": false, "errors": ["ground_txn_hash_invalid"]}
		var temporary := str(entry.get("temporary_path", ""))
		var backup := str(entry.get("backup_path", ""))
		if FileAccess.file_exists(temporary) and _file_sha256(temporary) != intended:
			return {"ok": false, "errors": ["ground_txn_temp_changed"]}
		if FileAccess.file_exists(backup) and _file_sha256(backup) != base:
			return {"ok": false, "errors": ["ground_txn_backup_changed"]}
		if current == intended:
			continue
		if current == "MISSING" and _file_sha256(backup) == base:
			current = base
		if current != base:
			return {"ok": false, "errors": ["ground_txn_third_version:%s" % str(entry.get("relative_path", ""))]}
		if temporary.is_empty() or not FileAccess.file_exists(temporary) or _file_sha256(temporary) != intended:
			return {"ok": false, "errors": ["ground_txn_intended_missing:%s" % str(entry.get("relative_path", ""))]}
	for raw_entry: Variant in entries:
		var entry: Dictionary = raw_entry
		var target := ground_dir.path_join(str(entry.get("relative_path", "")))
		if _file_sha256_or_missing(target) == str(entry.get("new_sha256", "")):
			continue
		var promote_temp := str(entry.get("temporary_path", ""))
		var promote_backup := str(entry.get("backup_path", ""))
		if FileAccess.file_exists(target):
			var backup_error := DirAccess.rename_absolute(target, promote_backup)
			if backup_error != OK:
				return {"ok": false, "errors": ["ground_txn_backup_failed:%d" % backup_error]}
		var promote_error := DirAccess.rename_absolute(promote_temp, target)
		if promote_error != OK:
			if FileAccess.file_exists(promote_backup):
				DirAccess.rename_absolute(promote_backup, target)
			return {"ok": false, "errors": ["ground_txn_promote_failed:%d" % promote_error]}
	for raw_entry: Variant in entries:
		var cleanup_temp := str((raw_entry as Dictionary).get("temporary_path", ""))
		if FileAccess.file_exists(cleanup_temp):
			DirAccess.remove_absolute(cleanup_temp)
		var cleanup_backup := str((raw_entry as Dictionary).get("backup_path", ""))
		if FileAccess.file_exists(cleanup_backup):
			if _file_sha256(cleanup_backup) != str((raw_entry as Dictionary).get("base_sha256", "")):
				return {"ok": false, "errors": ["ground_txn_backup_changed"]}
			DirAccess.remove_absolute(cleanup_backup)
	DirAccess.remove_absolute(journal_path)
	return {"ok": true}


static func _cleanup_write_set_entries(entries: Array) -> void:
	for raw_entry: Variant in entries:
		var temporary := str((raw_entry as Dictionary).get("temporary_path", ""))
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(temporary)


static func _file_sha256_or_missing(path: String) -> String:
	return _file_sha256(path) if FileAccess.file_exists(ProjectSettings.globalize_path(path)) else "MISSING"


static func _valid_write_set_hash(value: String, allow_missing: bool) -> bool:
	if allow_missing and value == "MISSING":
		return true
	return value.length() == 64 and value.is_valid_hex_number()


static func _valid_write_set_relative_path(value: String) -> bool:
	if value.is_empty() or value.begins_with("/") or value.contains("..") or value.contains("\\"):
		return false
	if value in [MANIFEST_FILE, STATE_FILE]:
		return true
	var chunk_pattern := RegEx.new()
	chunk_pattern.compile("^chunks/c_-?[0-9]+_-?[0-9]+\\.json$")
	return chunk_pattern.search(value) != null


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
