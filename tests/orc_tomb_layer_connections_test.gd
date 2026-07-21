extends Node

const MAP_IDS := ["orc_tomb_1", "orc_tomb_2", "orc_tomb_3"]
const RUNTIME_IDS := [217, 218, 221]
const DISPLAY_NAMES := ["兽人古墓一层", "兽人古墓二层", "兽人古墓三层"]


func _ready() -> void:
	var documents: Array[Dictionary] = []
	for index in MAP_IDS.size():
		var map_id: String = MAP_IDS[index]
		var loaded := MapEditorLoadService.load_document(
			MapEditorSaveService.default_path(map_id)
		)
		assert(loaded.ok, "%s:%s" % [map_id, loaded.get("errors", [])])
		var document: Dictionary = loaded.document
		assert(int(document.runtime_map_id) == RUNTIME_IDS[index])
		assert(str(document.display_name) == DISPLAY_NAMES[index])
		assert(document.layers.map_entrance_points.is_empty())
		assert(document.layers.map_exit_points.size() == [2, 2, 1][index])
		var ground := MapEditorGroundService.initialize(document)
		assert(ground.ok, "%s:%s" % [map_id, ground.get("errors", [])])
		documents.append(document)
	_assert_pair(documents[0], documents[1], "orc_tomb_1_2_pair_v1")
	_assert_pair(documents[1], documents[2], "orc_tomb_2_3_pair_v1")
	_assert_pair_to_bich(documents[0])
	print("ORC_TOMB_LAYER_CONNECTIONS_PASS maps=3 pairs=3 size=38x38")
	get_tree().quit(0)


func _assert_pair(source: Dictionary, target: Dictionary, pair_id: String) -> void:
	var forward := _pair_endpoint(source, pair_id)
	var reverse := _pair_endpoint(target, pair_id)
	assert(str(forward.target_map_key) == str(target.map_id))
	assert(str(forward.target_portal_id) == str(reverse.semantic_id))
	assert(str(reverse.target_map_key) == str(source.map_id))
	assert(str(reverse.target_portal_id) == str(forward.semantic_id))


func _assert_pair_to_bich(floor_one: Dictionary) -> void:
	var endpoint := _pair_endpoint(floor_one, "bich_orc_tomb_1_pair_v2")
	assert(str(endpoint.target_map_key) == "bich_province")
	assert(int(endpoint.target_map_id) == 4)


func _pair_endpoint(document: Dictionary, pair_id: String) -> Dictionary:
	for endpoint: Dictionary in document.layers.map_exit_points:
		if str(endpoint.get("connection_pair_id", "")) == pair_id:
			return endpoint
	assert(false, pair_id)
	return {}
