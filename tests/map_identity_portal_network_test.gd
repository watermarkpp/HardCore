extends Node

const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const IDENTITY_PATH := "res://assets/data/map_design/map_identity_registry.json"
const NETWORK_PATH := "res://assets/data/map_design/map_portal_network.json"


func _ready() -> void:
	var identity := _read_json(IDENTITY_PATH)
	var network := _read_json(NETWORK_PATH)
	assert(str(identity.get("contract_id", "")) == "hardcore.formal_map_identity.v1")
	assert(str(network.get("contract_id", "")) == "hardcore.formal_map_portal_network.v1")
	var maps: Array = identity.get("maps", [])
	assert(maps.size() == 67, "formal identity registry must contain 67 maps")
	assert((network.get("connections", []) as Array).size() == 66)
	assert(int(network.get("bidirectional_pair_count", -1)) == 51)
	assert(int(network.get("one_way_connection_count", -1)) == 15)

	var documents := {}
	var runtime_ids := {}
	var legacy_ids := {}
	for raw_entry: Variant in maps:
		assert(raw_entry is Dictionary)
		var entry: Dictionary = raw_entry
		var map_id := str(entry.get("map_id", ""))
		var runtime_map_id := int(entry.get("runtime_map_id", -1))
		var legacy_map_id := str(entry.get("legacy_map_id", ""))
		assert(not map_id.is_empty() and not documents.has(map_id))
		assert(runtime_map_id >= 910001 and runtime_map_id <= 918006)
		assert(not runtime_ids.has(runtime_map_id))
		assert(not legacy_ids.has(legacy_map_id))
		runtime_ids[runtime_map_id] = true
		legacy_ids[legacy_map_id] = true
		var runtime := Bridge.load_map(runtime_map_id)
		assert(not runtime.is_empty(), "formal runtime missing: %d" % runtime_map_id)
		assert(str(runtime.get("source", {}).get("map_id", "")) == map_id)
		assert(int(runtime.get("source", {}).get("runtime_map_id", -1)) == runtime_map_id)
		documents[map_id] = runtime

	var endpoint_index := {}
	var bidirectional := 0
	var one_way := 0
	var arrival := 0
	for map_id: String in documents:
		var document: Dictionary = documents[map_id]
		for raw_door: Variant in document.get("semantics", {}).get("door_points", []):
			if raw_door is Dictionary:
				assert(str(raw_door.get("semantic_role", "")) != "map_portal")
		for raw_endpoint: Variant in document.get("semantics", {}).get("map_exit_points", []):
			assert(raw_endpoint is Dictionary)
			var endpoint: Dictionary = raw_endpoint
			var portal_id := str(endpoint.get("semantic_id", ""))
			var key := "%s::%s" % [map_id, portal_id]
			assert(not portal_id.is_empty() and not endpoint_index.has(key))
			endpoint_index[key] = endpoint
			match str(endpoint.get("connection_mode", "")):
				"bidirectional": bidirectional += 1
				"one_way": one_way += 1
				"arrival_only": arrival += 1
				_: assert(false, "unclassified formal portal: %s" % key)
	assert(endpoint_index.size() == 132)
	assert(bidirectional == 102 and one_way == 15 and arrival == 15)

	for key: String in endpoint_index:
		var endpoint: Dictionary = endpoint_index[key]
		var mode := str(endpoint.get("connection_mode", ""))
		if mode == "arrival_only":
			assert(not bool(endpoint.get("target_configured", true)))
			assert(not bool(endpoint.get("trigger_on_enter", true)))
			assert(int(endpoint.get("target_map_id", 0)) == -1)
			continue
		var target_map_key := str(endpoint.get("target_map_key", ""))
		var target_portal_id := str(endpoint.get("target_portal_id", ""))
		var target_key := "%s::%s" % [target_map_key, target_portal_id]
		assert(endpoint_index.has(target_key), "portal target missing: %s" % key)
		var target: Dictionary = endpoint_index[target_key]
		assert(endpoint.get("target_tile", []) == target.get("tile", []))
		if mode == "bidirectional":
			var source_map_key := key.get_slice("::", 0)
			var source_portal_id := key.get_slice("::", 1)
			assert(str(target.get("target_map_key", "")) == source_map_key)
			assert(str(target.get("target_portal_id", "")) == source_portal_id)
			assert(str(target.get("connection_pair_id", "")) == str(endpoint.get("connection_pair_id", "")))
		else:
			assert(str(target.get("connection_mode", "")) == "arrival_only")

	var dungeon_labels := {
		"world_bich_province::map_exit_000002": ["兽人古墓", "bich_orc_tomb_f1"],
		"world_bich_province::map_exit_000003": ["比奇矿区", "bich_mine_f1"],
		"world_snake_valley::map_exit_000003": ["山谷矿区", "snake_mine_passage_1"],
		"world_mengzhong_province::map_exit_000002": ["石墓", "mengzhong_stone_tomb_f1"],
		"world_mengzhong_province::map_exit_000003": ["祖玛寺庙", "mengzhong_zuma_temple_f1"],
		"world_mengzhong_province::map_exit_000005": ["死亡山谷", "mengzhong_death_valley_dungeon"],
		"world_wooma_forest::map_exit_000001": ["沃玛寺庙", "wooma_temple_f1"],
		"world_fengmo_valley::map_exit_000002": ["封魔矿区", "fengmo_forked_path"],
		"world_white_day_gate::map_exit_000002": ["赤月峡谷", "chiyue_valley"],
		"world_cangyue_island::map_exit_000001": ["牛魔寺庙", "cangyue_bull_temple_f1"],
		"world_cangyue_island::map_exit_000002": ["骨魔洞", "cangyue_bone_cave_f1"],
	}
	for key: String in dungeon_labels:
		var expected: Array = dungeon_labels[key]
		var endpoint: Dictionary = endpoint_index[key]
		assert(str(endpoint.get("display_name", "")) == str(expected[0]))
		assert(str(endpoint.get("target_map_key", "")) == str(expected[1]))
	var forked: Dictionary = documents["fengmo_forked_path"]
	var fork_targets := {}
	for raw_endpoint: Variant in forked.get("semantics", {}).get("map_exit_points", []):
		fork_targets[str(raw_endpoint.get("target_map_key", ""))] = true
	assert(fork_targets.keys().size() == 2)
	assert(fork_targets.has("world_fengmo_valley"))
	assert(fork_targets.has("fengmo_light_corridor"))

	await get_tree().process_frame
	print("MAP_IDENTITY_PORTAL_NETWORK_PASS maps=67 endpoints=132 pairs=51 one_way=15 arrival=15")
	get_tree().quit(0)


func _endpoint(document: Dictionary, portal_id: String) -> Dictionary:
	for raw_endpoint: Variant in document.get("layers", {}).get("map_exit_points", []):
		if raw_endpoint is Dictionary and str(raw_endpoint.get("semantic_id", "")) == portal_id:
			return raw_endpoint
	return {}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
