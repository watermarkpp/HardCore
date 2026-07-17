extends Node


func _ready() -> void:
	var document := MapEditorTypes.new_map("stage1_ground_test", 991001, "Stage1 Ground Test", Vector2i(64, 64))
	var run_id := str(Time.get_ticks_usec())
	document.editor_meta.workspace = "user://mse_stage1_ground_test_%s" % run_id
	var initialized := MapEditorGroundService.initialize(document)
	assert(initialized.ok, str(initialized.get("errors", [])))
	var manifest: Dictionary = initialized.manifest
	var state: Dictionary = initialized.state
	assert(manifest.ground_pixel_size == [4096, 2048])
	assert(manifest.chunk_grid_size == [4, 2])
	assert(manifest.chunks.size() == 8)
	assert(state.dirty_chunks.is_empty())
	for chunk: Dictionary in manifest.chunks:
		assert(chunk.state == "virtual" and not chunk.materialized)
	var paint := MapEditorGroundService.record_tile_paint(document, Vector2i(32, 32), "ground.dark_grass.001")
	assert(paint.ok, str(paint.get("errors", [])))
	assert(paint.dirty_count == 1)
	assert(paint.chunk_id == "c_2_1")
	var reloaded := MapEditorGroundService.initialize(document)
	assert(reloaded.ok)
	assert(reloaded.state.dirty_chunks == ["c_2_1"])
	var dirty := false
	for chunk: Dictionary in reloaded.manifest.chunks:
		if chunk.chunk_id == "c_2_1":
			dirty = chunk.state == "dirty" and chunk.materialized
	assert(dirty)
	var bich := MapEditorTypes.new_map_from_catalog("bich_province")
	bich.editor_meta.workspace = "user://mse_stage1_bich_test_%s" % run_id
	var bich_ground := MapEditorGroundService.initialize(bich)
	assert(bich_ground.ok)
	assert(bich_ground.manifest.ground_pixel_size == [5120, 2560])
	assert(bich_ground.manifest.chunk_grid_size == [5, 3])
	assert(bich_ground.manifest.chunks.size() == 15)
	assert(bich_ground.state.dirty_chunks.is_empty())
	print("MSE_STAGE1_GROUND_PASS")
	get_tree().quit(0)
