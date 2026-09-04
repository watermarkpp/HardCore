extends SceneTree

const ConnectionPolicyService := preload(
	"res://scripts/map_editor/map_editor_connection_policy_service.gd"
)

const ROUTE_VERSION_ID := "wooma_temple_user_route_v3_unified_portals"
const MARKER_PATH := (
	"res://assets/data/runtime/map_editor/"
	+ "wooma_temple_route.manual_ready.json"
)
const MAP_IDS := [
	"wooma_forest",
	"wooma_temple_1",
	"wooma_temple_2",
	"wooma_temple_3",
]


func _init() -> void:
	var documents := {}
	for map_id: String in MAP_IDS:
		var loaded := MapEditorLoadService.load_document(
			MapEditorSaveService.default_path(map_id)
		)
		if not bool(loaded.get("ok", false)):
			_fail("load_failed:%s:%s" % [map_id, loaded.get("errors", [])])
			return
		documents[map_id] = loaded.document

	var links := [
		{
			"source": "wooma_forest",
			"target": "wooma_temple_1",
			"source_exit": "map_exit_000001",
			"pair_id": "wooma_forest_temple_1_pair_v1",
			"forward_name": "进入沃玛寺庙一层",
			"reverse_name": "返回沃玛森林",
			"forward_id": "wooma_forest_top_to_temple_1_v2",
			"reverse_id": "wooma_temple_1_to_forest_v1",
		},
		{
			"source": "wooma_temple_1",
			"target": "wooma_temple_2",
			"source_exit": "map_exit_000001",
			"pair_id": "wooma_temple_1_2_pair_v1",
			"forward_name": "前往沃玛寺庙二层",
			"reverse_name": "返回沃玛寺庙一层",
			"forward_id": "wooma_temple_1_to_2_v2",
			"reverse_id": "wooma_temple_2_to_1_v1",
		},
		{
			"source": "wooma_temple_2",
			"target": "wooma_temple_3",
			"source_exit": "map_exit_000001",
			"pair_id": "wooma_temple_2_leader_hall_pair_v1",
			"forward_name": "进入沃玛教主大厅",
			"reverse_name": "返回沃玛寺庙二层",
			"forward_id": "wooma_temple_2_to_leader_hall_v2",
			"reverse_id": "wooma_leader_hall_to_temple_2_v1",
		},
	]
	for link: Dictionary in links:
		var source: Dictionary = documents[str(link.source)]
		var target: Dictionary = documents[str(link.target)]
		var result := ConnectionPolicyService.configure_bidirectional(
			source,
			str(link.source_exit),
			"map_entrance_000001",
			target,
			"map_entrance_000001",
			str(link.pair_id),
			str(link.forward_name),
			str(link.reverse_name),
			str(link.forward_id),
			str(link.reverse_id)
		)
		if not bool(result.get("ok", false)):
			_fail("connect_failed:%s:%s" % [link.pair_id, result.get("errors", [])])
			return

	var reciprocal_errors := (
		ConnectionPolicyService.validate_reciprocal_pairs(
			documents
		)
	)
	if not reciprocal_errors.is_empty():
		_fail("reciprocal_validation:%s" % reciprocal_errors)
		return

	var runtimes := {}
	for map_id: String in MAP_IDS:
		var document: Dictionary = documents[map_id]
		var meta: Dictionary = document.get("editor_meta", {})
		if str(meta.get("route_version_id", "")) != ROUTE_VERSION_ID:
			meta["revision"] = int(meta.get("revision", 1)) + 1
		meta["route_version_id"] = ROUTE_VERSION_ID
		meta["connection_policy_id"] = (
			ConnectionPolicyService.POLICY_ID
		)
		meta["portal_contract_id"] = (
			ConnectionPolicyService.PORTAL_CONTRACT_ID
		)
		meta["default_connection_mode"] = "bidirectional"
		document["editor_meta"] = meta
		var runtime := _save_and_build(document)
		if runtime.is_empty():
			return
		runtimes[map_id] = runtime

	var marker := {
		"schema_version": 2,
		"route_version_id": ROUTE_VERSION_ID,
		"connection_policy_id": ConnectionPolicyService.POLICY_ID,
		"portal_contract_id": ConnectionPolicyService.PORTAL_CONTRACT_ID,
		"default_connection_mode": "bidirectional",
		"arrival_reentry_policy_id": (
			ConnectionPolicyService.ARRIVAL_REENTRY_POLICY_ID
		),
		"return_minimum_seconds": (
			ConnectionPolicyService.RETURN_MINIMUM_SECONDS
		),
		"return_unlock_distance_gu": (
			ConnectionPolicyService.RETURN_UNLOCK_DISTANCE_GU
		),
		"return_requires_fresh_activation": true,
		"travel_request_single_flight": true,
		"status": "user_requested_unified_bidirectional_portals",
		"maps": [],
		"connection_pairs": [],
		"connections": [],
	}
	for map_id: String in MAP_IDS:
		var document: Dictionary = documents[map_id]
		marker.maps.append({
			"map_id": map_id,
			"runtime_map_id": int(document.runtime_map_id),
			"display_name": str(document.display_name),
			"runtime_build_sha256": str(runtimes[map_id].build_sha256),
		})
		for map_exit: Dictionary in document.layers.map_exit_points:
			if str(map_exit.get("connection_policy_id", "")) != ConnectionPolicyService.POLICY_ID:
				continue
			if not bool(map_exit.get("target_configured", false)):
				continue
			marker.connections.append(_connection_summary(document, map_exit))
	for link: Dictionary in links:
		marker.connection_pairs.append({
			"connection_pair_id": str(link.pair_id),
			"maps": [str(link.source), str(link.target)],
			"mode": "bidirectional",
		})
	var write := MapEditorGroundService._write_json_atomic(
		MARKER_PATH,
		marker
	)
	if not bool(write.get("ok", false)):
		_fail("marker_write_failed:%s" % write.get("errors", []))
		return
	print(
		"WOOMA_TEMPLE_UNIFIED_PORTAL_ROUTE_PASS "
		+ "pairs=3 endpoints=6 overlap=0 route=268<->313<->314<->315"
	)
	quit(0)


func _save_and_build(document: Dictionary) -> Dictionary:
	var bake := MapEditorChunkBakeService.bake_dirty_chunks(document)
	if not bool(bake.get("ok", false)):
		_fail("bake_failed:%s:%s" % [document.map_id, bake.get("errors", [])])
		return {}
	var approval := MapEditorBuildRuntimeService.approve_for_runtime(document)
	if not bool(approval.get("ok", false)):
		_fail("approval_failed:%s:%s" % [document.map_id, approval.get("errors", [])])
		return {}
	var saved := MapEditorSaveService.save_document(
		document,
		MapEditorSaveService.default_path(str(document.map_id))
	)
	if not bool(saved.get("ok", false)):
		_fail("save_failed:%s:%s" % [document.map_id, saved.get("errors", [])])
		return {}
	var built := MapEditorBuildRuntimeService.build(document)
	if not bool(built.get("ok", false)):
		_fail("build_failed:%s:%s" % [document.map_id, built.get("errors", [])])
		return {}
	return built.runtime


func _connection_summary(
	document: Dictionary,
	map_exit: Dictionary
) -> Dictionary:
	return {
		"source_map_id": str(document.map_id),
		"source_runtime_map_id": int(document.runtime_map_id),
		"exit_id": str(map_exit.semantic_id),
		"exit_tile": map_exit.tile.duplicate(),
		"target_map_id": int(map_exit.target_map_id),
		"target_map_key": str(map_exit.target_map_key),
		"target_entrance_id": str(map_exit.target_entrance_id),
		"target_portal_id": str(map_exit.target_portal_id),
		"target_tile": map_exit.target_tile.duplicate(),
		"connection_pair_id": str(map_exit.connection_pair_id),
		"connection_direction": str(map_exit.connection_direction),
		"reciprocal_exit_id": str(map_exit.reciprocal_exit_id),
		"official_connection_id": str(map_exit.official_connection_id),
		"arrival_reentry_policy_id": str(
			map_exit.arrival_reentry_policy_id
		),
		"return_minimum_seconds": float(
			map_exit.return_minimum_seconds
		),
		"return_unlock_distance_gu": float(
			map_exit.return_unlock_distance_gu
		),
	}


func _fail(message: String) -> void:
	push_error("WOOMA_TEMPLE_BIDIRECTIONAL_ROUTE_FAILED %s" % message)
	quit(1)
