extends Node

const ConnectionPolicyService := preload(
	"res://scripts/map_editor/map_editor_connection_policy_service.gd"
)
const PortalRuntimeService := preload(
	"res://scripts/map_editor/map_portal_runtime_service.gd"
)
const MAP_IDS := [
	"bich_province", "wooma_forest", "wooma_temple_1",
	"wooma_temple_2", "wooma_temple_3", "orc_tomb_1",
	"orc_tomb_2", "orc_tomb_3", "bich_mine_1",
	"bich_mine_2", "corpse_king_hall",
]
const NETWORK_VERSION_ID := "phase1_finished_map_network_v1"


func _ready() -> void:
	var documents := {}
	var runtimes := {}
	var pair_ids := {}
	var bidirectional_endpoints := 0
	var one_way_endpoints := 0
	for map_id: String in MAP_IDS:
		var loaded := MapEditorLoadService.load_document(
			MapEditorSaveService.default_path(map_id)
		)
		assert(loaded.ok, "%s:%s" % [map_id, loaded.get("errors", [])])
		var document: Dictionary = loaded.document
		assert(bool(document.editor_meta.runtime_approved), map_id)
		assert(
			str(document.editor_meta.phase1_network_version_id)
			== NETWORK_VERSION_ID,
			map_id
		)
		assert(
			ConnectionPolicyService.validate_document(document).is_empty(),
			map_id
		)
		documents[map_id] = document
		var runtime_loaded := MapEditorRuntimeMapService.load_runtime(
			MapEditorBuildRuntimeService.default_runtime_path(map_id)
		)
		assert(runtime_loaded.ok, map_id)
		runtimes[map_id] = runtime_loaded.runtime
		for endpoint: Dictionary in document.layers.map_exit_points:
			if not bool(endpoint.get("target_configured", false)):
				continue
			assert(
				str(endpoint.connection_policy_id)
				== ConnectionPolicyService.POLICY_ID,
				"%s:%s" % [map_id, endpoint.semantic_id]
			)
			if bool(endpoint.get("one_way", false)):
				one_way_endpoints += 1
				assert(map_id == "bich_mine_2")
				assert(str(endpoint.target_map_key) == "corpse_king_hall")
				assert(str(endpoint.connection_mode) == "one_way")
				continue
			bidirectional_endpoints += 1
			assert(str(endpoint.connection_mode) == "bidirectional")
			assert(not bool(endpoint.one_way))
			pair_ids[str(endpoint.connection_pair_id)] = true

	assert(bidirectional_endpoints == 18)
	assert(pair_ids.size() == 9)
	assert(one_way_endpoints == 1)
	assert(
		ConnectionPolicyService.validate_reciprocal_pairs(documents).is_empty()
	)
	assert(PortalRuntimeService.validate_network(runtimes).is_empty())
	_assert_mine_copy(documents.bich_mine_1, documents.bich_mine_2)
	_assert_bich_bottom_exit(documents.bich_province)
	_assert_corpse_hall_lock_in(documents.corpse_king_hall)
	_assert_marker()
	print(
		"PHASE1_MAP_NETWORK_PASS maps=11 pairs=9 endpoints=18 "
		+ "route=4<->406<->408->1578 corpse_exit=town_or_death_only"
	)
	get_tree().quit(0)


func _assert_mine_copy(mine_1: Dictionary, mine_2: Dictionary) -> void:
	assert(int(mine_1.runtime_map_id) == 406)
	assert(int(mine_2.runtime_map_id) == 408)
	assert(str(mine_2.editor_meta.clone_source_map_id) == "bich_mine_1")
	assert(mine_1.design == mine_2.design)
	for layer: String in [
		"terrain_base", "terrain_front", "object_base", "object_front",
		"collision", "collision_erase", "monster_spawn", "boss_spawn",
		"npc_points", "safe_area", "light", "region_trigger",
	]:
		assert(mine_1.layers.get(layer, []) == mine_2.layers.get(layer, []), layer)
	var mine_1_manifest := _read_json(
		"res://map_editor_workspace/bich_mine_1/ground/ground_manifest.json"
	)
	var mine_2_manifest := _read_json(
		"res://map_editor_workspace/bich_mine_2/ground/ground_manifest.json"
	)
	assert(mine_1_manifest.chunks.size() == mine_2_manifest.chunks.size())
	for index in mine_1_manifest.chunks.size():
		var first: Dictionary = mine_1_manifest.chunks[index]
		var second: Dictionary = mine_2_manifest.chunks[index]
		assert(first.rect_px == second.rect_px)
		if str(first.get("preview_png", "")).is_empty():
			continue
		assert(
			FileAccess.get_sha256(
				"res://map_editor_workspace/bich_mine_1/" + str(first.preview_png)
			) == FileAccess.get_sha256(
				"res://map_editor_workspace/bich_mine_2/" + str(second.preview_png)
			)
		)


func _assert_bich_bottom_exit(bich: Dictionary) -> void:
	var bottom: Dictionary = {}
	for endpoint: Dictionary in bich.layers.map_exit_points:
		if str(endpoint.get("official_connection_id", "")) == "bich_bottom_to_mine_1_v1":
			bottom = endpoint
	assert(not bottom.is_empty())
	assert(bottom.tile == [7.0, 74.0])
	assert(str(bottom.target_map_key) == "bich_mine_1")
	assert(int(bottom.target_map_id) == 406)


func _assert_corpse_hall_lock_in(corpse: Dictionary) -> void:
	var active_portals := 0
	var arrival_anchors := 0
	for endpoint: Dictionary in corpse.layers.map_exit_points:
		if bool(endpoint.get("target_configured", false)):
			active_portals += 1
		if bool(endpoint.get("arrival_only", false)):
			arrival_anchors += 1
			assert(not bool(endpoint.trigger_on_enter))
			assert(str(endpoint.exit_policy) == "town_scroll_or_death_only")
	assert(active_portals == 0)
	assert(arrival_anchors == 1)
	assert(str(corpse.editor_meta.exit_policy) == "town_scroll_or_death_only")


func _assert_marker() -> void:
	var marker := _read_json(
		"res://assets/data/runtime/map_editor/phase1_map_network.manual_ready.json"
	)
	assert(str(marker.network_version_id) == NETWORK_VERSION_ID)
	assert(bool(marker.phase1_map_production_complete))
	assert(str(marker.default_connection_mode) == "bidirectional")
	assert(int(marker.bidirectional_pair_count) == 9)
	assert(int(marker.one_way_exception_count) == 1)
	assert(str(marker.one_way_exceptions[0].target_map_key) == "corpse_king_hall")
	assert(str(marker.one_way_exceptions[0].exit_policy) == "town_scroll_or_death_only")


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed
