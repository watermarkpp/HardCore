extends Node

const MAPS := [
	["orc_tomb_1", 217],
	["orc_tomb_2", 218],
	["orc_tomb_3", 221],
]


func _ready() -> void:
	var total_chunks := 0
	for expected: Array in MAPS:
		var map_id := str(expected[0])
		var visual := _read_json(
			"res://assets/data/runtime/map_editor/%s.visual.json" % map_id
		)
		assert(
			str(visual.visual_contract_id)
			== "orc_tomb_editor_runtime_visual_v1"
		)
		assert(str(visual.map_id) == map_id)
		assert(int(visual.runtime_map_id) == int(expected[1]))
		assert(not str(visual.source_editor_document_sha256).is_empty())
		assert(not str(visual.source_ground_manifest_sha256).is_empty())
		assert(bool(visual.coverage.complete))
		assert(int(visual.coverage.source_chunk_count) == 6)
		assert(int(visual.coverage.required_chunk_count) == 5)
		assert(int(visual.coverage.packaged_chunk_count) == 5)
		assert(visual.chunks.size() == 5)
		for chunk: Dictionary in visual.chunks:
			var image_path := "res://" + str(chunk.image)
			assert(FileAccess.file_exists(image_path), image_path)
			assert(ResourceLoader.exists(image_path), image_path)
			assert(
				FileAccess.get_sha256(image_path) == str(chunk.sha256),
				image_path
			)
		total_chunks += visual.chunks.size()
	assert(total_chunks == 15)
	print(
		"ORC_TOMB_RUNTIME_VISUAL_PUBLISH_PASS "
		+ "contract=orc_tomb_editor_runtime_visual_v1 "
		+ "maps=217,218,221 chunks=15 legacy_fallback=false"
	)
	get_tree().quit(0)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed
