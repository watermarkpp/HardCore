extends Node

const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const CompositionService := preload(
	"res://scripts/map_editor/map_editor_formal_authority_composition_service.gd"
)
const JsonCodec := preload(
	"res://scripts/map_editor/map_editor_json_codec.gd"
)

const SOURCE_CANONICAL := "formal_source"
const SOURCE_LEGACY := "legacy_source"
const SOURCE_RUNTIME := 910101
const SOURCE_LEGACY_RUNTIME := 101
const TARGET_CANONICAL := "formal_target"
const TARGET_LEGACY := "legacy_target"
const TARGET_RUNTIME := 910102
const TARGET_LEGACY_RUNTIME := 102
const SOURCE_PORTAL := "map_exit_source"
const TARGET_PORTAL := "map_exit_target"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	CompositionService.reset_test_overrides()
	var source := _source_document()
	var target := _target_document()
	var identity := _identity_registry()
	var network := _network()
	var raw_before := JsonCodec.encode(source)
	var raw_copy := source.duplicate(true)

	CompositionService.test_override_authorities(
		identity, network, {TARGET_CANONICAL: target}
	)
	var composed := CompositionService.compose_for_runtime(source)
	assert(bool(composed.get("ok", false)), str(composed.get("errors", [])))
	var formal: Dictionary = composed.document
	assert(int(formal.schema_version) == 5)
	assert(str(formal.map_id) == SOURCE_CANONICAL)
	assert(int(formal.runtime_map_id) == SOURCE_RUNTIME)
	var portal: Dictionary = formal.layers.map_exit_points[0]
	assert(str(portal.display_name) == "玩家保留的出口名")
	assert(str(portal.target_map_key) == TARGET_CANONICAL)
	assert(int(portal.target_map_id) == TARGET_RUNTIME)
	assert(str(portal.target_portal_id) == TARGET_PORTAL)
	assert(str(portal.reciprocal_exit_id) == TARGET_PORTAL)
	assert(str(portal.connection_pair_id) == "pair.synthetic")
	assert(portal.target_tile == [17, 19])
	assert(not portal.has("return_unlock_distance_tiles"))
	assert(float(portal.return_unlock_distance_gu) == 1.5)
	assert(JsonCodec.encode(source) == raw_before)
	assert(source == raw_copy)

	var candidate := BuildService.build_formal_candidate(source)
	assert(bool(candidate.get("ok", false)), str(candidate.get("errors", [])))
	assert(bool(candidate.get("formal_authority_composed", false)))
	assert(str(candidate.get("map_key", "")) == SOURCE_CANONICAL)
	assert(
		str(candidate.get("candidate_path", "")).begins_with(
			"res://outputs/map_runtime_candidates/"
		)
	)
	assert(not str(candidate.candidate_path).begins_with(BuildService.RUNTIME_ROOT))
	assert(JsonCodec.encode(source) == raw_before)
	var runtime_portal: Dictionary = (
		candidate.runtime.semantics.map_exit_points[0]
	)
	assert(not runtime_portal.has("return_unlock_distance_tiles"))
	assert(float(runtime_portal.return_unlock_distance_gu) == 1.5)
	assert(BuildService.candidate_matches_document(candidate, source))

	var changed_source := source.duplicate(true)
	changed_source.layers.map_exit_points[0].display_name = "已修改的出口名"
	assert(not BuildService.candidate_matches_document(candidate, changed_source))
	var moved_target := target.duplicate(true)
	moved_target.layers.map_exit_points[0].tile = [18, 19]
	CompositionService.test_override_authorities(
		identity, network, {TARGET_CANONICAL: moved_target}
	)
	assert(
		not BuildService.candidate_matches_document(candidate, source),
		"candidate must be stale when recomposed target geometry changes"
	)

	var missing_network := network.duplicate(true)
	missing_network.connections[0].a_portal_id = "unknown_source_portal"
	CompositionService.test_override_authorities(
		identity, missing_network, {TARGET_CANONICAL: target}
	)
	var missing := CompositionService.compose_for_runtime(source)
	assert(not bool(missing.get("ok", false)))
	assert(_has_error(missing, "source_portal_endpoint_missing_from_network"))

	var ambiguous_network := network.duplicate(true)
	ambiguous_network.connections.append(network.connections[0].duplicate(true))
	ambiguous_network.logical_connection_count = 2
	ambiguous_network.bidirectional_pair_count = 2
	CompositionService.test_override_authorities(
		identity, ambiguous_network, {TARGET_CANONICAL: target}
	)
	var ambiguous := CompositionService.compose_for_runtime(source)
	assert(not bool(ambiguous.get("ok", false)))
	assert(_has_error(ambiguous, "portal_network_endpoint_ambiguous"))

	var wrong_target := target.duplicate(true)
	wrong_target.runtime_map_id = 999
	CompositionService.test_override_authorities(
		identity, network, {TARGET_CANONICAL: wrong_target}
	)
	var mismatch := CompositionService.compose_for_runtime(source)
	assert(not bool(mismatch.get("ok", false)))
	assert(_has_error(mismatch, "portal_target_document_runtime_mismatch"))

	CompositionService.reset_test_overrides()
	print("MAP_EDITOR_FORMAL_AUTHORITY_COMPOSITION_PASS")
	get_tree().quit(0)


func _source_document() -> Dictionary:
	var document := MapEditorTypes.new_map(
		SOURCE_LEGACY,
		SOURCE_LEGACY_RUNTIME,
		"Synthetic Source",
		Vector2i(32, 32)
	)
	document.editor_meta.workspace = (
		"user://formal_composition_source_%d" % Time.get_ticks_usec()
	)
	var ground := MapEditorGroundService.initialize(document)
	assert(bool(ground.get("ok", false)), str(ground.get("errors", [])))
	document.schema_version = 4
	document.layers.map_exit_points = [_portal(
		SOURCE_PORTAL, [6, 5], "玩家保留的出口名"
	)]
	return document


func _target_document() -> Dictionary:
	var document := MapEditorTypes.new_map(
		TARGET_LEGACY,
		TARGET_LEGACY_RUNTIME,
		"Synthetic Target",
		Vector2i(32, 32)
	)
	document.layers.map_exit_points = [_portal(
		TARGET_PORTAL, [17, 19], "目标入口"
	)]
	return document


func _portal(portal_id: String, tile: Array, display_name: String) -> Dictionary:
	return {
		"kind": "map_exit",
		"semantic_id": portal_id,
		"exit_id": portal_id,
		"tile": tile.duplicate(true),
		"content_layer": "personal_expansion",
		"runtime_export": true,
		"trigger_on_enter": true,
		"blocks_movement": false,
		"display_name": display_name,
		"target_configured": false,
		"target_map_id": "",
		"return_unlock_distance_tiles": 1.5,
	}


func _identity_registry() -> Dictionary:
	return {
		"contract_id": "hardcore.formal_map_identity.v1",
		"formal_map_count": 2,
		"maps": [
			{
				"map_id": SOURCE_CANONICAL,
				"runtime_map_id": SOURCE_RUNTIME,
				"legacy_map_id": SOURCE_LEGACY,
				"legacy_runtime_map_id": SOURCE_LEGACY_RUNTIME,
			},
			{
				"map_id": TARGET_CANONICAL,
				"runtime_map_id": TARGET_RUNTIME,
				"legacy_map_id": TARGET_LEGACY,
				"legacy_runtime_map_id": TARGET_LEGACY_RUNTIME,
			},
		],
	}


func _network() -> Dictionary:
	return {
		"contract_id": "hardcore.formal_map_portal_network.v1",
		"identity_contract_id": "hardcore.formal_map_identity.v1",
		"formal_map_count": 2,
		"logical_connection_count": 1,
		"bidirectional_pair_count": 1,
		"one_way_connection_count": 0,
		"formal_portal_endpoint_count": 2,
		"connections": [
			{
				"mode": "bidirectional",
				"pair_id": "pair.synthetic",
				"a_map_id": SOURCE_CANONICAL,
				"a_portal_id": SOURCE_PORTAL,
				"b_map_id": TARGET_CANONICAL,
				"b_portal_id": TARGET_PORTAL,
			},
		],
	}


func _has_error(result: Dictionary, prefix: String) -> bool:
	for raw: Variant in result.get("errors", []):
		if str(raw).begins_with(prefix):
			return true
	return false
