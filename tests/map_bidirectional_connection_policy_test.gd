extends Node

const ConnectionPolicyService := preload(
	"res://scripts/map_editor/map_editor_connection_policy_service.gd"
)

const MAP_IDS := [
	"wooma_forest",
	"wooma_temple_1",
	"wooma_temple_2",
	"wooma_temple_3",
]
const ROUTE_VERSION_ID := "wooma_temple_user_route_v2_bidirectional"


func _ready() -> void:
	var policy := ConnectionPolicyService.policy()
	assert(str(policy.policy_id) == ConnectionPolicyService.POLICY_ID)
	assert(str(policy.default_connection_mode) == "bidirectional")
	assert(bool(policy.one_way_requires_explicit_override))
	assert(bool(policy.one_way_reason_required))

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
		for map_exit: Dictionary in document.layers.map_exit_points:
			if str(map_exit.get("connection_policy_id", "")) != ConnectionPolicyService.POLICY_ID:
				continue
			if not bool(map_exit.get("target_configured", false)):
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
	assert(
		ConnectionPolicyService.validate_reciprocal_pairs(
			documents
		).is_empty()
	)
	_assert_pair(documents, "wooma_forest_temple_1_pair_v1", "wooma_forest", "wooma_temple_1")
	_assert_pair(documents, "wooma_temple_1_2_pair_v1", "wooma_temple_1", "wooma_temple_2")
	_assert_pair(documents, "wooma_temple_2_leader_hall_pair_v1", "wooma_temple_2", "wooma_temple_3")

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
		+ "default=bidirectional pairs=3 exits=6 one_way=explicit_only"
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


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed
