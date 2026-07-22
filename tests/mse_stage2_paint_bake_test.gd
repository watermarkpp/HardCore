extends Node


func _ready() -> void:
	var document := MapEditorTypes.new_map("stage2_paint_test", 991002, "Stage2 Paint Test", Vector2i(64, 64))
	var run_id := str(Time.get_ticks_usec())
	document.editor_meta.workspace = "user://mse_stage2_paint_%s" % run_id
	var initial := MapEditorGroundService.initialize(document)
	assert(initial.ok)
	assert(initial.state.dirty_chunks.is_empty())
	var first := MapEditorGroundService.record_tile_paint(document, Vector2i(32, 32), "ground.dark_grass.001")
	assert(first.ok and first.chunk_id == "c_2_1" and first.dirty_count == 1)
	var second := MapEditorGroundService.record_tile_paint(document, Vector2i(33, 32), "ground.mud.001")
	assert(second.ok and second.dirty_count == 1)
	var overrides := MapEditorGroundService.tile_overrides(second.state)
	assert(overrides.get("32,32", "") == "ground.dark_grass.001")
	assert(overrides.get("33,32", "") == "ground.mud.001")
	var erase := MapEditorGroundService.record_tile_erase(document, Vector2i(33, 32))
	assert(erase.ok)
	overrides = MapEditorGroundService.tile_overrides(erase.state)
	assert(not overrides.has("33,32"))
	var bake := MapEditorChunkBakeService.bake_dirty_chunks(document)
	assert(bake.ok, str(bake.get("errors", [])))
	assert(bake.baked_chunks == ["c_2_1"])
	var reopened := MapEditorGroundService.initialize(document)
	assert(reopened.ok and reopened.state.dirty_chunks.is_empty())
	var materialized := {}
	for chunk: Dictionary in reopened.manifest.chunks:
		if chunk.chunk_id == "c_2_1": materialized = chunk
	assert(materialized.get("state", "") == "materialized")
	assert(materialized.get("baked_coordinate_contract_id", "") == MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID)
	var output := MapEditorGroundService.workspace_root(document).path_join(str(materialized.preview_png))
	assert(FileAccess.file_exists(output))
	var baked_image := Image.load_from_file(ProjectSettings.globalize_path(output))
	assert(baked_image.get_size() == Vector2i(1024, 1024))
	var preview_manifest := MapEditorGroundService._read_json(
		MapEditorGroundService.workspace_root(document).path_join("ground/baked_preview/bake_manifest.json")
	)
	assert(preview_manifest.get("coordinate_contract_id", "") == MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID)
	assert(MapEditorChunkBakeService.bake_dirty_chunks(document).get("message", "") == "no_dirty_chunks")
	print("MSE_STAGE2_PAINT_BAKE_PASS")
	get_tree().quit(0)
