extends Node

const ConnectionPolicyService := preload(
	"res://scripts/map_editor/map_editor_connection_policy_service.gd"
)
const PortalTravelGuard := preload(
	"res://scripts/map_editor/map_portal_travel_guard.gd"
)
const PortalRuntimeService := preload(
	"res://scripts/map_editor/map_portal_runtime_service.gd"
)

const MAP_IDS := [
	"wooma_forest",
	"wooma_temple_1",
	"wooma_temple_2",
	"wooma_temple_3",
]
const ROUTE_VERSION_ID := "wooma_temple_user_route_v3_unified_portals"


func _ready() -> void:
	var policy := ConnectionPolicyService.policy()
	assert(str(policy.policy_id) == ConnectionPolicyService.POLICY_ID)
	assert(str(policy.default_connection_mode) == "bidirectional")
	assert(
		str(policy.portal_contract_id)
		== ConnectionPolicyService.PORTAL_CONTRACT_ID
	)
	assert(bool(policy.one_way_requires_explicit_override))
	assert(bool(policy.one_way_reason_required))
	var runtime_contract := _read_json(
		"res://assets/data/map_design/map_portal_runtime_contract.json"
	)
	assert(str(runtime_contract.contract_id) == "map_portal_runtime_contract_v1")
	assert(str(runtime_contract.arrival_guard_policy_id) == PortalTravelGuard.POLICY_ID)
	assert(bool(runtime_contract.single_flight))

	var blank := MapEditorTypes.new_map_from_blank_template(
		"blank.wooma_temple_1"
	)
	var fresh_exit := MapEditorGameplaySemanticService.add_entry(
		blank,
		"map_exit",
		Vector2i(1, 1),
		{}
	)
	assert(fresh_exit.ok)
	assert(str(fresh_exit.entry.connection_mode) == "bidirectional")
	assert(not bool(fresh_exit.entry.one_way))
	assert(
		str(fresh_exit.entry.arrival_reentry_policy_id)
		== ConnectionPolicyService.ARRIVAL_REENTRY_POLICY_ID
	)
	fresh_exit.entry["target_configured"] = true
	fresh_exit.entry["target_map_id"] = 999
	var incomplete_errors := (
		ConnectionPolicyService.validate_document(blank)
	)
	assert("connection_pair_id_required:map_exit_000001" in incomplete_errors)
	assert("target_portal_id_required:map_exit_000001" in incomplete_errors)
	assert("reciprocal_exit_id_required:map_exit_000001" in incomplete_errors)
	var rejected_one_way := (
		ConnectionPolicyService.configure_explicit_one_way(
			fresh_exit.entry,
			""
		)
	)
	assert(not rejected_one_way.ok)
	assert(
		ConnectionPolicyService.configure_explicit_one_way(
			fresh_exit.entry,
			"剧情单向坠落测试"
		).ok
	)

	var documents := {}
	var runtimes := {}
	var directed_exit_count := 0
	var pair_ids := {}
	for map_id: String in MAP_IDS:
		var loaded := MapEditorLoadService.load_document(
			MapEditorSaveService.default_path(map_id)
		)
		assert(loaded.ok, "%s:%s" % [map_id, loaded.get("errors", [])])
		var document: Dictionary = loaded.document
		assert(str(document.editor_meta.route_version_id) == ROUTE_VERSION_ID)
		assert(
			str(document.editor_meta.connection_policy_id)
			== ConnectionPolicyService.POLICY_ID
		)
		assert(
			ConnectionPolicyService.validate_document(
				document
			).is_empty()
		)
		documents[map_id] = document
		var runtime_loaded := MapEditorRuntimeMapService.load_runtime(
			MapEditorBuildRuntimeService.default_runtime_path(map_id)
		)
		assert(runtime_loaded.ok, str(runtime_loaded.get("errors", [])))
		runtimes[map_id] = runtime_loaded.runtime
		for map_exit: Dictionary in document.layers.map_exit_points:
			if str(map_exit.get("connection_policy_id", "")) != ConnectionPolicyService.POLICY_ID:
				continue
			if not bool(map_exit.get("target_configured", false)):
				continue
			if not str(map_exit.get("connection_pair_id", "")).begins_with("wooma_"):
				continue
			directed_exit_count += 1
			pair_ids[str(map_exit.connection_pair_id)] = true
			assert(not bool(map_exit.one_way))
			assert(str(map_exit.connection_mode) == "bidirectional")
			assert(bool(map_exit.requires_leave_before_retrigger))
			assert(
				str(map_exit.arrival_reentry_policy_id)
				== ConnectionPolicyService.ARRIVAL_REENTRY_POLICY_ID
			)
	assert(directed_exit_count == 6)
	assert(pair_ids.size() == 3)
	# The complete phase-one network, including the new Bich and mine branches,
	# is validated by phase1_map_network_test. This test remains scoped to the
	# three Wooma route pairs.
	var first_request := PortalRuntimeService.travel_request(
		PortalRuntimeService.endpoints(runtimes.wooma_forest)[0]
	)
	assert(first_request.ok)
	assert(str(first_request.target_map_key) == "wooma_temple_1")
	assert(str(first_request.target_portal_id) == "map_exit_000002")
	assert(bool(first_request.single_flight))
	_assert_pair(documents, "wooma_forest_temple_1_pair_v1", "wooma_forest", "wooma_temple_1")
	_assert_pair(documents, "wooma_temple_1_2_pair_v1", "wooma_temple_1", "wooma_temple_2")
	_assert_pair(documents, "wooma_temple_2_leader_hall_pair_v1", "wooma_temple_2", "wooma_temple_3")
	_assert_no_overlapping_portals(documents)
	_assert_arrival_guard()
	_assert_editor_uses_unified_portal_language()

	var marker := _read_json(
		"res://assets/data/runtime/map_editor/"
		+ "wooma_temple_route.manual_ready.json"
	)
	assert(str(marker.route_version_id) == ROUTE_VERSION_ID)
	assert(str(marker.default_connection_mode) == "bidirectional")
	assert(marker.connection_pairs.size() == 3)
	assert(marker.connections.size() == 6)
	print(
		"MAP_BIDIRECTIONAL_CONNECTION_POLICY_PASS "
		+ "default=bidirectional pairs=3 endpoints=6 overlap=0 guard=3s_or_1.5tiles"
	)
	get_tree().quit(0)


func _assert_pair(
	documents: Dictionary,
	pair_id: String,
	first_map_id: String,
	second_map_id: String
) -> void:
	var directions := {}
	for map_id: String in [first_map_id, second_map_id]:
		for map_exit: Dictionary in documents[map_id].layers.map_exit_points:
			if str(map_exit.get("connection_pair_id", "")) != pair_id:
				continue
			directions[str(map_exit.connection_direction)] = map_exit
	assert(directions.has("forward"))
	assert(directions.has("reverse"))
	assert(
		str(directions.forward.reciprocal_exit_id)
		== str(directions.reverse.semantic_id)
	)
	assert(
		str(directions.reverse.reciprocal_exit_id)
		== str(directions.forward.semantic_id)
	)
	assert(
		str(directions.forward.target_portal_id)
		== str(directions.reverse.semantic_id)
	)
	assert(
		str(directions.reverse.target_portal_id)
		== str(directions.forward.semantic_id)
	)


func _assert_no_overlapping_portals(documents: Dictionary) -> void:
	for map_id: String in documents:
		var document: Dictionary = documents[map_id]
		var entrance_tiles := {}
		for entrance: Dictionary in document.layers.map_entrance_points:
			entrance_tiles[str(entrance.tile)] = true
		for endpoint: Dictionary in document.layers.map_exit_points:
			if str(endpoint.get("portal_contract_id", "")) != ConnectionPolicyService.PORTAL_CONTRACT_ID:
				continue
			assert(not entrance_tiles.has(str(endpoint.tile)))


func _assert_arrival_guard() -> void:
	var state := PortalTravelGuard.new_state()
	assert(PortalTravelGuard.begin_travel(state))
	assert(not PortalTravelGuard.begin_travel(state))
	PortalTravelGuard.finish_arrival(
		state, "map_exit_000002", 1000, Vector2(20, 41)
	)
	assert(
		not PortalTravelGuard.can_activate(
			state, "map_exit_000002", 2500, Vector2(20, 41), true
		)
	)
	assert(
		not PortalTravelGuard.can_activate(
			state, "map_exit_000002", 5000, Vector2(20, 41), false
		)
	)
	assert(
		PortalTravelGuard.can_activate(
			state, "map_exit_000002", 4000, Vector2(20, 41), true
		)
	)
	PortalTravelGuard.finish_arrival(
		state, "map_exit_000002", 6000, Vector2(20, 41)
	)
	assert(
		PortalTravelGuard.can_activate(
			state, "map_exit_000002", 6100, Vector2(21.5, 41), true
		)
	)


func _assert_editor_uses_unified_portal_language() -> void:
	var scene := load("res://scenes/tools/mafa_scene_editor.tscn") as PackedScene
	var editor := scene.instantiate() as MapEditorApp
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	var labels := {}
	for index in editor.semantic_kind_option.item_count:
		labels[str(editor.semantic_kind_option.get_item_metadata(index))] = (
			editor.semantic_kind_option.get_item_text(index)
		)
	assert(str(labels.map_exit) == "地图传送点（默认双向）")
	assert(str(labels.map_entrance) == "独立到达点（特殊用途）")
	editor.queue_free()


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed
