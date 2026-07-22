extends Node

const MAPS := [
	["bich_mine_1", 406, 7],
	["bich_mine_2", 408, 7],
	["corpse_king_hall", 1578, 2],
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
			== "phase1_mine_editor_runtime_visual_v1"
		)
		assert(str(visual.map_id) == map_id)
		assert(int(visual.runtime_map_id) == int(expected[1]))
		assert(bool(visual.coverage.complete))
		assert(int(visual.coverage.packaged_chunk_count) == int(expected[2]))
		assert(visual.chunks.size() == int(expected[2]))
		for chunk: Dictionary in visual.chunks:
			var path := "res://" + str(chunk.image)
			assert(FileAccess.file_exists(path), path)
			assert(ResourceLoader.exists(path), path)
			assert(FileAccess.get_sha256(path) == str(chunk.sha256), path)
		total_chunks += int(expected[2])
	assert(total_chunks == 16)
	print(
		"PHASE1_MINE_RUNTIME_VISUAL_PASS maps=406,408,1578 "
		+ "chunks=16 packageable=true"
	)
	get_tree().quit(0)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed
