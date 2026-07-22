extends Node

const MAPS := [
	["wooma_forest", 268, 8],
	["wooma_temple_1", 313, 6],
	["wooma_temple_2", 314, 6],
	["wooma_temple_3", 315, 6],
]


func _ready() -> void:
	var total_chunks := 0
	for expected: Array in MAPS:
		var map_id := str(expected[0])
		var runtime_map_id := int(expected[1])
		var expected_chunk_count := int(expected[2])
		var visual := _read_json(
			"res://assets/data/runtime/map_editor/%s.visual.json"
			% map_id
		)
		assert(
			str(visual.visual_contract_id)
			== "wooma_editor_runtime_visual_v1"
		)
		assert(str(visual.map_id) == map_id)
		assert(int(visual.runtime_map_id) == runtime_map_id)
		assert(bool(visual.coverage.complete))
		assert(
			int(visual.coverage.required_chunk_count)
			== expected_chunk_count
		)
		assert(
			int(visual.coverage.packaged_chunk_count)
			== expected_chunk_count
		)
		assert(visual.chunks.size() == expected_chunk_count)
		for chunk: Dictionary in visual.chunks:
			var image_path := "res://" + str(chunk.image)
			assert(FileAccess.file_exists(image_path), image_path)
			assert(ResourceLoader.exists(image_path), image_path)
			assert(
				FileAccess.get_sha256(image_path) == str(chunk.sha256),
				image_path
			)
		total_chunks += expected_chunk_count
	assert(total_chunks == 26)
	print(
		"WOOMA_RUNTIME_VISUAL_PUBLISH_PASS "
		+ "contract=wooma_editor_runtime_visual_v1 "
		+ "maps=268,313,314,315 chunks=26 packageable=true"
	)
	get_tree().quit(0)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed
