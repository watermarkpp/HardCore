extends Node


func _ready() -> void:
	_assert_design_alignment(Vector2i(80, 80))
	_assert_design_alignment(Vector2i(38, 38))
	var v15_asset := MapAssetCatalogService.find_asset("v1_5.a001_07")
	assert(not v15_asset.is_empty())
	assert(bool(v15_asset.get("resolved_from_tracked_staging", false)))
	assert(FileAccess.file_exists("res://" + str(v15_asset.image)))
	await _assert_legacy_bake_migration()
	print("MSE_GROUND_COORDINATE_CONTRACT_PASS sizes=80x80,38x38 legacy_rebaked=1")
	get_tree().quit(0)


func _assert_design_alignment(design_size: Vector2i) -> void:
	for cell: Vector2i in [
		Vector2i.ZERO,
		Vector2i(1, 1),
		Vector2i(design_size.x / 2, design_size.y / 2),
		design_size - Vector2i.ONE,
	]:
		var grid_top := MapEditorCoordinate.tile_to_ground_px(Vector2(cell), design_size)
		var center := MapEditorCoordinate.cell_center_to_ground_px(Vector2(cell), design_size)
		var texture_rect := MapEditorCoordinate.cell_texture_rect_ground_px(Vector2(cell), design_size)
		var polygon := MapEditorCoordinate.cell_polygon_ground_px(cell, design_size)
		var polygon_center := Vector2.ZERO
		for point: Vector2 in polygon:
			polygon_center += point
		polygon_center /= float(polygon.size())
		assert(center.is_equal_approx(polygon_center))
		assert(texture_rect.get_center().is_equal_approx(center))
		assert((texture_rect.position + Vector2(MapEditorCoordinate.HALF_TILE_W, 0.0)).is_equal_approx(grid_top))
		assert(MapEditorCoordinate.ground_px_to_cell(center, design_size) == cell)


func _assert_legacy_bake_migration() -> void:
	var document := MapEditorTypes.new_map(
		"ground_coordinate_contract",
		990182,
		"Ground Coordinate Contract",
		Vector2i(4, 4)
	)
	document.ground.blank_fill_asset_id = ""
	document.editor_meta.workspace = "user://mse_ground_contract_%s" % Time.get_ticks_usec()
	var paint := MapEditorGroundService.record_tile_paint(
		document,
		Vector2i(1, 1),
		"ground.dark_grass.001"
	)
	assert(paint.ok, str(paint.get("errors", [])))
	assert(MapEditorChunkBakeService.bake_dirty_chunks(document).ok)
	var initialized := MapEditorGroundService.initialize(document)
	assert(initialized.ok)
	var chunk: Dictionary = initialized.manifest.chunks[0]
	var baked_path := MapEditorGroundService.workspace_root(document).path_join(str(chunk.preview_png))
	var baked_image := Image.load_from_file(ProjectSettings.globalize_path(baked_path))
	var expected_rect := MapEditorCoordinate.cell_texture_rect_ground_px(Vector2(1, 1), Vector2i(4, 4))
	assert(baked_image.get_used_rect().position.y == roundi(expected_rect.position.y))

	var legacy_manifest: Dictionary = initialized.manifest.duplicate(true)
	legacy_manifest.erase("coordinate_contract_id")
	legacy_manifest.chunks[0].erase("baked_coordinate_contract_id")
	assert(MapEditorGroundService._write_json_atomic(str(initialized.manifest_path), legacy_manifest).ok)
	var legacy_state: Dictionary = initialized.state.duplicate(true)
	legacy_state.erase("coordinate_contract_id")
	legacy_state.dirty_chunks = []
	assert(MapEditorGroundService._write_json_atomic(str(initialized.state_path), legacy_state).ok)

	var migrated := MapEditorGroundService.initialize(document)
	assert(migrated.ok)
	assert(migrated.state.dirty_chunks == ["c_0_0"])
	assert(migrated.manifest.chunks[0].state == "dirty")
	var preview := MapEditorCanvasPreview.new()
	add_child(preview)
	preview.set_document(document)
	preview.set_ground_state(migrated.state)
	assert(preview._baked_ground_chunks.is_empty())

	var rebake := MapEditorChunkBakeService.bake_dirty_chunks(document)
	assert(rebake.ok, str(rebake.get("errors", [])))
	var reopened := MapEditorGroundService.initialize(document)
	assert(reopened.state.dirty_chunks.is_empty())
	assert(reopened.manifest.chunks[0].baked_coordinate_contract_id == MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID)
	preview.reload_ground_state(reopened.state)
	assert(preview._baked_ground_chunks.size() == 1)
	preview.queue_free()
