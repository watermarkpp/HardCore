class_name MapEditorChunkBakeService
extends RefCounted

const BAKE_SCHEMA_VERSION := 1
static func bake_dirty_chunks(document: Dictionary) -> Dictionary:
	var initialized := MapEditorGroundService.initialize(document)
	if not initialized.ok:
		return initialized
	var manifest: Dictionary = initialized.manifest
	var state: Dictionary = initialized.state
	var dirty_chunks: Array = state.get("dirty_chunks", [])
	if dirty_chunks.is_empty():
		return {"ok": true, "baked_chunks": [], "message": "no_dirty_chunks"}
	var overrides := MapEditorGroundService.tile_overrides(state)
	var default_fill_asset_id := str(document.get("ground", {}).get("blank_fill_asset_id", ""))
	var design_size := _design_size(document)
	var root := MapEditorGroundService.workspace_root(document)
	var chunks: Array = manifest.chunks
	var baked: Array = []
	var preview_entries: Array = []
	for chunk_id: String in dirty_chunks:
		var chunk_index := _find_chunk_index(chunks, chunk_id)
		if chunk_index < 0:
			return {"ok": false, "errors": ["dirty_chunk_missing:%s" % chunk_id]}
		var chunk: Dictionary = chunks[chunk_index]
		var output_path := root.path_join("ground/baked_preview/%s.png" % chunk_id)
		var bake := _bake_chunk_png(chunk, design_size, overrides, default_fill_asset_id, output_path)
		if not bake.ok:
			return bake
		chunk.state = "materialized"
		chunk.materialized = true
		chunk.preview_png = "ground/baked_preview/%s.png" % chunk_id
		chunk.baked_operation_count = state.operations_by_chunk.get(chunk_id, []).size()
		chunk.baked_default_fill_asset_id = default_fill_asset_id
		chunks[chunk_index] = chunk
		baked.append(chunk_id)
		preview_entries.append({"chunk_id": chunk_id, "preview_png": chunk.preview_png, "operation_count": chunk.baked_operation_count})
	manifest.chunks = chunks
	state.dirty_chunks = []
	var preview_manifest_path := root.path_join("ground/baked_preview/bake_manifest.json")
	var preview_manifest := {"schema_version": BAKE_SCHEMA_VERSION, "map_id": document.map_id, "chunks": preview_entries}
	var preview_write := MapEditorGroundService._write_json_atomic(preview_manifest_path, preview_manifest)
	if not preview_write.ok:
		return preview_write
	var save_result := MapEditorGroundService.save_manifest_and_state(str(initialized.manifest_path), manifest, str(initialized.state_path), state)
	if not save_result.ok:
		return save_result
	return {"ok": true, "baked_chunks": baked, "preview_manifest": preview_manifest_path}


static func _bake_chunk_png(chunk: Dictionary, design_size: Vector2i, overrides: Dictionary, default_fill_asset_id: String, output_path: String) -> Dictionary:
	var rect: Array = chunk.rect_px
	if rect.size() != 4:
		return {"ok": false, "errors": ["invalid_chunk_rect"]}
	var rect_position := Vector2i(int(rect[0]), int(rect[1]))
	var rect_size := Vector2i(int(rect[2]), int(rect[3]))
	var image := Image.create(rect_size.x, rect_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var candidate := _candidate_tile_rect(rect_position, rect_size, design_size)
	var cache := {}
	for y in range(candidate.position.y, candidate.end.y + 1):
		for x in range(candidate.position.x, candidate.end.x + 1):
			if x < 0 or y < 0 or x >= design_size.x or y >= design_size.y:
				continue
			var asset_id := str(overrides.get("%d,%d" % [x, y], default_fill_asset_id))
			if asset_id.is_empty():
				continue
			var tile_image: Image = _asset_image(asset_id, cache)
			if tile_image == null:
				return {"ok": false, "errors": ["tile_image_missing:%s" % asset_id]}
			var center := MapEditorCoordinate.tile_to_ground_px(Vector2(x, y), design_size)
			var destination := Vector2i(roundi(center.x) - 32 - rect_position.x, roundi(center.y) - 16 - rect_position.y)
			var destination_rect := Rect2i(destination, tile_image.get_size())
			var intersection := destination_rect.intersection(Rect2i(Vector2i.ZERO, rect_size))
			if intersection.size.x <= 0 or intersection.size.y <= 0:
				continue
			var source_rect := Rect2i(intersection.position - destination, intersection.size)
			image.blend_rect(tile_image, source_rect, intersection.position)
	var resolved := ProjectSettings.globalize_path(output_path) if output_path.begins_with("res://") or output_path.begins_with("user://") else output_path
	var mkdir_error := DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
	if mkdir_error != OK:
		return {"ok": false, "errors": ["bake_mkdir_failed:%d" % mkdir_error]}
	var temporary := resolved.get_basename() + ".tmp.png"
	var save_error := image.save_png(temporary)
	if save_error != OK:
		return {"ok": false, "errors": ["bake_png_save_failed:%d" % save_error]}
	var backup := resolved + ".bak"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(resolved):
		var backup_error := DirAccess.rename_absolute(resolved, backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "errors": ["bake_backup_failed:%d" % backup_error]}
	var promote_error := DirAccess.rename_absolute(temporary, resolved)
	if promote_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, resolved)
		return {"ok": false, "errors": ["bake_promote_failed:%d" % promote_error]}
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	return {"ok": true, "path": output_path}


static func _candidate_tile_rect(rect_position: Vector2i, rect_size: Vector2i, design_size: Vector2i) -> Rect2i:
	var corners := [
		Vector2(rect_position) - Vector2(64, 32), Vector2(rect_position + Vector2i(rect_size.x, 0)) - Vector2(64, 32),
		Vector2(rect_position + rect_size) + Vector2(64, 32), Vector2(rect_position + Vector2i(0, rect_size.y)) + Vector2(64, 32),
	]
	var min_tile := Vector2(INF, INF)
	var max_tile := Vector2(-INF, -INF)
	for corner: Vector2 in corners:
		var tile := MapEditorCoordinate.ground_px_to_tile(corner, design_size)
		min_tile = min_tile.min(tile)
		max_tile = max_tile.max(tile)
	return Rect2i(Vector2i(floori(min_tile.x), floori(min_tile.y)), Vector2i(ceili(max_tile.x - min_tile.x) + 1, ceili(max_tile.y - min_tile.y) + 1))


static func _asset_image(asset_id: String, cache: Dictionary) -> Image:
	if cache.has(asset_id):
		return cache[asset_id]
	var asset := MapAssetCatalogService.find_asset(asset_id)
	var image_path := str(asset.get("image", ""))
	if image_path.is_empty():
		for candidate: Dictionary in MapAssetCatalogService.all_assets():
			if str(candidate.get("asset_type", "")) == "ground_brush":
				image_path = str(candidate.get("image", ""))
				break
	if image_path.is_empty():
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://" + image_path))
	if image != null and image.get_size() != Vector2i(64, 32):
		image.resize(64, 32, Image.INTERPOLATE_BILINEAR)
	cache[asset_id] = image
	return image


static func _find_chunk_index(chunks: Array, chunk_id: String) -> int:
	for index in chunks.size():
		if str(chunks[index].get("chunk_id", "")) == chunk_id:
			return index
	return -1


static func _design_size(document: Dictionary) -> Vector2i:
	var size: Array = document.design.design_size
	return Vector2i(int(size[0]), int(size[1]))
