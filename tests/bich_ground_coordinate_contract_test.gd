extends Node


func _ready() -> void:
	var document_result := MapEditorLoadService.load_document(
		"res://map_editor_workspace/bich_province/bich_province.editor.json"
	)
	assert(document_result.ok, str(document_result.get("errors", [])))
	var document: Dictionary = document_result.document
	var initialized := MapEditorGroundService.initialize(document)
	assert(initialized.ok, str(initialized.get("errors", [])))
	assert(initialized.manifest.coordinate_contract_id == MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID)
	assert(initialized.state.coordinate_contract_id == MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID)
	assert(initialized.state.dirty_chunks.is_empty())

	var operation_counts := {}
	for chunk_id: String in initialized.state.operations_by_chunk:
		operation_counts[chunk_id] = (initialized.state.operations_by_chunk[chunk_id] as Array).size()
	var materialized_count := 0
	for chunk: Dictionary in initialized.manifest.chunks:
		if not bool(chunk.get("materialized", false)):
			continue
		materialized_count += 1
		assert(chunk.state == "materialized", str(chunk.chunk_id))
		assert(
			chunk.baked_coordinate_contract_id == MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID,
			str(chunk.chunk_id)
		)
		assert(
			int(chunk.baked_operation_count) == int(operation_counts.get(str(chunk.chunk_id), 0)),
			str(chunk.chunk_id)
		)
		var png_path := MapEditorGroundService.workspace_root(document).path_join(str(chunk.preview_png))
		assert(FileAccess.file_exists(png_path), png_path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(png_path))
		var rect: Array = chunk.rect_px
		assert(image.get_size() == Vector2i(int(rect[2]), int(rect[3])), str(chunk.chunk_id))
	assert(materialized_count == 13)

	var preview := MapEditorCanvasPreview.new()
	add_child(preview)
	preview.set_document(document)
	preview.set_ground_state(initialized.state)
	assert(preview._baked_ground_chunks.size() == 13)
	print("BICH_GROUND_COORDINATE_CONTRACT_PASS chunks=13 dirty=0")
	get_tree().quit(0)
