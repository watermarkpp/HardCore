class_name MapEditorFormalAuthorityCompositionService
extends RefCounted

const MapEditorTypesScript := preload(
	"res://scripts/map_editor/map_editor_types.gd"
)
const ConnectionPolicyService := preload(
	"res://scripts/map_editor/map_editor_connection_policy_service.gd"
)

const IDENTITY_PATH := (
	"res://assets/data/map_design/map_identity_registry.json"
)
const PORTAL_NETWORK_PATH := (
	"res://assets/data/map_design/map_portal_network.json"
)
const WORKSPACE_ROOT := "res://map_editor_workspace/"
const IDENTITY_CONTRACT_ID := "hardcore.formal_map_identity.v1"
const NETWORK_CONTRACT_ID := "hardcore.formal_map_portal_network.v1"

## Focused-test seams. Production always reads the tracked authorities and
## read-only target endpoint geometry from map_editor_workspace.
static var _test_authority_override_enabled := false
static var _test_identity_registry: Dictionary = {}
static var _test_portal_network: Dictionary = {}
static var _test_documents_by_map_id: Dictionary = {}


static func test_override_authorities(
	identity_registry: Dictionary,
	portal_network: Dictionary,
	documents_by_map_id: Dictionary
) -> void:
	_test_authority_override_enabled = true
	_test_identity_registry = identity_registry.duplicate(true)
	_test_portal_network = portal_network.duplicate(true)
	_test_documents_by_map_id = documents_by_map_id.duplicate(true)


static func reset_test_overrides() -> void:
	_test_authority_override_enabled = false
	_test_identity_registry = {}
	_test_portal_network = {}
	_test_documents_by_map_id = {}


static func compose_for_runtime(source_document: Dictionary) -> Dictionary:
	var identity_registry := (
		_test_identity_registry.duplicate(true)
		if _test_authority_override_enabled
		else _read_json(IDENTITY_PATH, "identity_registry")
	)
	if identity_registry.is_empty():
		return {"ok": false, "errors": ["identity_registry_unreadable"]}
	var portal_network := (
		_test_portal_network.duplicate(true)
		if _test_authority_override_enabled
		else _read_json(PORTAL_NETWORK_PATH, "portal_network")
	)
	if portal_network.is_empty():
		return {"ok": false, "errors": ["portal_network_unreadable"]}
	return compose(
		source_document,
		identity_registry,
		portal_network,
		_test_documents_by_map_id if _test_authority_override_enabled else {}
	)


static func compose(
	source_document: Dictionary,
	identity_registry: Dictionary,
	portal_network: Dictionary,
	documents_by_map_id: Dictionary = {}
) -> Dictionary:
	if source_document.is_empty():
		return {"ok": false, "errors": ["source_document_required"]}
	var identity_result := _identity_index(identity_registry)
	if not bool(identity_result.get("ok", false)):
		return identity_result
	var identity_match := _resolve_identity(
		source_document, identity_result.get("identities", [])
	)
	if not bool(identity_match.get("ok", false)):
		return identity_match
	var identity: Dictionary = identity_match.identity
	var network_result := _network_index(
		portal_network, identity_result.by_canonical
	)
	if not bool(network_result.get("ok", false)):
		return network_result

	# Upgrade only a recursive copy. The raw editor authority is never approved,
	# renamed, normalized, saved or otherwise mutated by build-time composition.
	var composed := MapEditorTypesScript.upgrade_document(
		source_document.duplicate(true)
	)
	if int(composed.get("schema_version", -1)) != MapEditorTypesScript.SCHEMA_VERSION:
		return {"ok": false, "errors": ["formal_upgrade_failed"]}
	composed["map_id"] = str(identity.map_id)
	composed["runtime_map_id"] = int(identity.runtime_map_id)
	composed["legacy_map_id"] = str(identity.legacy_map_id)
	composed["legacy_runtime_map_id"] = int(identity.legacy_runtime_map_id)

	var layers: Dictionary = composed.get("layers", {})
	var endpoints: Variant = layers.get("map_exit_points", [])
	if not endpoints is Array:
		return {"ok": false, "errors": ["map_exit_points_not_array"]}
	var current_map_id := str(identity.map_id)
	var seen := {}
	var composed_endpoints: Array = []
	for raw_endpoint: Variant in endpoints:
		if not raw_endpoint is Dictionary:
			return {"ok": false, "errors": ["map_exit_endpoint_not_object"]}
		var endpoint: Dictionary = raw_endpoint.duplicate(true)
		var endpoint_id_result := _endpoint_id(endpoint)
		if not bool(endpoint_id_result.get("ok", false)):
			return endpoint_id_result
		var portal_id := str(endpoint_id_result.portal_id)
		var key := _endpoint_key(current_map_id, portal_id)
		if seen.has(key):
			return {
				"ok": false,
				"errors": ["source_portal_endpoint_ambiguous:%s" % key],
			}
		seen[key] = true
		if not network_result.endpoints.has(key):
			return {
				"ok": false,
				"errors": ["source_portal_endpoint_missing_from_network:%s" % key],
			}
		var descriptor: Dictionary = network_result.endpoints[key]
		var overlay := _overlay_endpoint(
			endpoint,
			descriptor,
			identity_result.by_canonical,
			documents_by_map_id
		)
		if not bool(overlay.get("ok", false)):
			return overlay
		composed_endpoints.append(overlay.endpoint)

	for network_key: String in network_result.endpoints:
		var descriptor: Dictionary = network_result.endpoints[network_key]
		if str(descriptor.source_map_id) == current_map_id and not seen.has(network_key):
			return {
				"ok": false,
				"errors": ["network_portal_endpoint_missing_from_source:%s" % network_key],
			}
	layers["map_exit_points"] = composed_endpoints
	composed["layers"] = layers
	var meta: Dictionary = composed.get("editor_meta", {})
	meta["formal_authority_composition_id"] = (
		"map.editor.formal_authority_composition.v1"
	)
	meta["formal_identity_contract_id"] = IDENTITY_CONTRACT_ID
	meta["formal_portal_network_contract_id"] = NETWORK_CONTRACT_ID
	composed["editor_meta"] = meta
	return {
		"ok": true,
		"document": composed,
		"identity": identity.duplicate(true),
		"source_map_id": str(source_document.get("map_id", "")),
		"formal_map_id": current_map_id,
		"formal_runtime_map_id": int(identity.runtime_map_id),
		"composed_portal_count": composed_endpoints.size(),
		"authority": {
			"identity_contract_id": IDENTITY_CONTRACT_ID,
			"portal_network_contract_id": NETWORK_CONTRACT_ID,
		},
	}


static func _identity_index(registry: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if str(registry.get("contract_id", "")) != IDENTITY_CONTRACT_ID:
		errors.append("identity_contract_mismatch")
	var maps: Variant = registry.get("maps", [])
	if not maps is Array:
		errors.append("identity_maps_not_array")
		return {"ok": false, "errors": errors}
	var declared_count := int(registry.get("formal_map_count", maps.size()))
	if declared_count != maps.size():
		errors.append("identity_formal_map_count_mismatch")
	var by_canonical := {}
	var by_legacy := {}
	var runtime_ids := {}
	var identities: Array = []
	for index in range(maps.size()):
		var raw: Variant = maps[index]
		if not raw is Dictionary:
			errors.append("identity_not_object:%d" % index)
			continue
		var entry: Dictionary = raw
		var canonical := str(entry.get("map_id", "")).strip_edges()
		var legacy := str(entry.get("legacy_map_id", "")).strip_edges()
		var runtime_id := int(entry.get("runtime_map_id", -1))
		var legacy_runtime_id := int(entry.get("legacy_runtime_map_id", -1))
		if canonical.is_empty() or legacy.is_empty() or runtime_id <= 0 or legacy_runtime_id <= 0:
			errors.append("identity_fields_invalid:%d" % index)
			continue
		if by_canonical.has(canonical) or by_legacy.has(legacy):
			errors.append("identity_key_ambiguous:%s:%s" % [canonical, legacy])
			continue
		# Canonical runtime IDs are globally unique. Historical provisional
		# runtime IDs are not: exact legacy map key + legacy runtime ID is the
		# only accepted legacy identity tuple.
		if runtime_ids.has(runtime_id):
			errors.append("identity_runtime_id_ambiguous:%d" % index)
			continue
		var normalized := entry.duplicate(true)
		by_canonical[canonical] = normalized
		by_legacy[legacy] = normalized
		runtime_ids[runtime_id] = true
		identities.append(normalized)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"identities": identities,
		"by_canonical": by_canonical,
		"by_legacy": by_legacy,
	}


static func _resolve_identity(
	document: Dictionary,
	identities: Array
) -> Dictionary:
	var source_map_id := str(document.get("map_id", "")).strip_edges()
	var matches: Array = []
	for raw: Variant in identities:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if source_map_id in [str(entry.map_id), str(entry.legacy_map_id)]:
			matches.append(entry)
	if matches.size() != 1:
		return {
			"ok": false,
			"errors": [
				"formal_identity_not_unique:%s:%d"
				% [source_map_id, matches.size()]
			],
		}
	var identity: Dictionary = matches[0]
	var expected_runtime_id := (
		int(identity.runtime_map_id)
		if source_map_id == str(identity.map_id)
		else int(identity.legacy_runtime_map_id)
	)
	if int(document.get("runtime_map_id", -1)) != expected_runtime_id:
		return {
			"ok": false,
			"errors": ["formal_identity_runtime_mismatch:%s" % source_map_id],
		}
	return {"ok": true, "identity": identity}


static func _network_index(
	network: Dictionary,
	identities_by_canonical: Dictionary
) -> Dictionary:
	var errors: Array[String] = []
	if str(network.get("contract_id", "")) != NETWORK_CONTRACT_ID:
		errors.append("portal_network_contract_mismatch")
	if str(network.get("identity_contract_id", "")) != IDENTITY_CONTRACT_ID:
		errors.append("portal_network_identity_contract_mismatch")
	if int(network.get("formal_map_count", identities_by_canonical.size())) != identities_by_canonical.size():
		errors.append("portal_network_formal_map_count_mismatch")
	var connections: Variant = network.get("connections", [])
	if not connections is Array:
		errors.append("portal_network_connections_not_array")
		return {"ok": false, "errors": errors}
	if int(network.get("logical_connection_count", connections.size())) != connections.size():
		errors.append("portal_network_connection_count_mismatch")
	var endpoint_index := {}
	var bidirectional_count := 0
	var one_way_count := 0
	for index in range(connections.size()):
		var raw: Variant = connections[index]
		if not raw is Dictionary:
			errors.append("portal_network_connection_not_object:%d" % index)
			continue
		var connection: Dictionary = raw
		var mode := str(connection.get("mode", ""))
		if mode == "bidirectional":
			bidirectional_count += 1
			var pair_id := str(connection.get("pair_id", "")).strip_edges()
			if pair_id.is_empty():
				errors.append("portal_network_pair_id_required:%d" % index)
				continue
			_add_network_endpoint(endpoint_index, errors, {
				"source_map_id": str(connection.get("a_map_id", "")),
				"source_portal_id": str(connection.get("a_portal_id", "")),
				"target_map_id": str(connection.get("b_map_id", "")),
				"target_portal_id": str(connection.get("b_portal_id", "")),
				"mode": mode,
				"pair_id": pair_id,
				"direction": "forward",
			}, identities_by_canonical)
			_add_network_endpoint(endpoint_index, errors, {
				"source_map_id": str(connection.get("b_map_id", "")),
				"source_portal_id": str(connection.get("b_portal_id", "")),
				"target_map_id": str(connection.get("a_map_id", "")),
				"target_portal_id": str(connection.get("a_portal_id", "")),
				"mode": mode,
				"pair_id": pair_id,
				"direction": "reverse",
			}, identities_by_canonical)
		elif mode == "one_way":
			one_way_count += 1
			var source_map := str(connection.get("source_map_id", ""))
			var source_portal := str(connection.get("source_portal_id", ""))
			var target_map := str(connection.get("target_map_id", ""))
			var target_portal := str(connection.get("target_portal_id", ""))
			_add_network_endpoint(endpoint_index, errors, {
				"source_map_id": source_map,
				"source_portal_id": source_portal,
				"target_map_id": target_map,
				"target_portal_id": target_portal,
				"mode": mode,
			}, identities_by_canonical)
			_add_network_endpoint(endpoint_index, errors, {
				"source_map_id": target_map,
				"source_portal_id": target_portal,
				"target_map_id": source_map,
				"target_portal_id": source_portal,
				"mode": "arrival_only",
			}, identities_by_canonical)
		else:
			errors.append("portal_network_mode_unsupported:%d:%s" % [index, mode])
	if int(network.get("bidirectional_pair_count", bidirectional_count)) != bidirectional_count:
		errors.append("portal_network_bidirectional_count_mismatch")
	if int(network.get("one_way_connection_count", one_way_count)) != one_way_count:
		errors.append("portal_network_one_way_count_mismatch")
	if int(network.get("formal_portal_endpoint_count", endpoint_index.size())) != endpoint_index.size():
		errors.append("portal_network_endpoint_count_mismatch")
	return {"ok": errors.is_empty(), "errors": errors, "endpoints": endpoint_index}


static func _add_network_endpoint(
	endpoint_index: Dictionary,
	errors: Array[String],
	descriptor: Dictionary,
	identities_by_canonical: Dictionary
) -> void:
	var source_map := str(descriptor.get("source_map_id", "")).strip_edges()
	var source_portal := str(descriptor.get("source_portal_id", "")).strip_edges()
	var target_map := str(descriptor.get("target_map_id", "")).strip_edges()
	var target_portal := str(descriptor.get("target_portal_id", "")).strip_edges()
	if (
		source_map.is_empty() or source_portal.is_empty()
		or target_map.is_empty() or target_portal.is_empty()
	):
		errors.append("portal_network_endpoint_fields_invalid")
		return
	if not identities_by_canonical.has(source_map) or not identities_by_canonical.has(target_map):
		errors.append("portal_network_endpoint_identity_missing:%s:%s" % [source_map, target_map])
		return
	var key := _endpoint_key(source_map, source_portal)
	if endpoint_index.has(key):
		errors.append("portal_network_endpoint_ambiguous:%s" % key)
		return
	endpoint_index[key] = descriptor.duplicate(true)


static func _overlay_endpoint(
	endpoint: Dictionary,
	descriptor: Dictionary,
	identities_by_canonical: Dictionary,
	documents_by_map_id: Dictionary
) -> Dictionary:
	var source_map_id := str(descriptor.source_map_id)
	var source_portal_id := str(descriptor.source_portal_id)
	var target_map_id := str(descriptor.target_map_id)
	var target_portal_id := str(descriptor.target_portal_id)
	var mode := str(descriptor.mode)
	var display_name: Variant = endpoint.get("display_name", "")
	endpoint.merge(ConnectionPolicyService.new_exit_defaults(), true)
	endpoint["display_name"] = display_name
	endpoint["kind"] = "map_exit"
	endpoint["semantic_id"] = source_portal_id
	endpoint["exit_id"] = source_portal_id
	endpoint["source_map_key"] = source_map_id
	endpoint["official_connection_id"] = (
		"portal.%s.%s" % [source_map_id, source_portal_id]
	)
	# The composed v5 document stays exclusively in the formal GU contract.
	# ConnectionPolicyService retains legacy-field compatibility at its own
	# v4 validation boundary; formal build input never reintroduces tiles.
	endpoint["return_unlock_distance_gu"] = (
		ConnectionPolicyService.RETURN_UNLOCK_DISTANCE_TILES
	)
	if mode == "arrival_only":
		_configure_arrival_only(endpoint)
		return {"ok": true, "endpoint": endpoint}
	var target_identity: Dictionary = identities_by_canonical[target_map_id]
	var target_tile_result := _target_portal_tile(
		target_identity, target_portal_id, documents_by_map_id
	)
	if not bool(target_tile_result.get("ok", false)):
		return target_tile_result
	endpoint["target_configured"] = true
	endpoint["target_map_id"] = int(target_identity.runtime_map_id)
	endpoint["target_map_key"] = target_map_id
	endpoint["target_portal_id"] = target_portal_id
	endpoint["target_entrance_id"] = target_portal_id
	endpoint["target_tile"] = target_tile_result.tile.duplicate(true)
	endpoint.erase("arrival_only")
	endpoint.erase("exit_policy")
	if mode == "bidirectional":
		endpoint["connection_mode"] = "bidirectional"
		endpoint["one_way"] = false
		endpoint["portal_role"] = "bidirectional_endpoint"
		endpoint["connection_pair_id"] = str(descriptor.pair_id)
		endpoint["connection_direction"] = str(descriptor.direction)
		endpoint["reciprocal_exit_id"] = target_portal_id
		endpoint["reciprocal_map_key"] = target_map_id
		endpoint.erase("explicit_one_way_reason")
	else:
		endpoint["connection_mode"] = "one_way"
		endpoint["one_way"] = true
		endpoint["portal_role"] = "one_way_endpoint"
		endpoint["explicit_one_way_reason"] = (
			"terminal_dungeon_has_no_return_portal"
		)
		for field: String in [
			"connection_pair_id",
			"connection_direction",
			"reciprocal_exit_id",
			"reciprocal_map_key",
		]:
			endpoint.erase(field)
	return {"ok": true, "endpoint": endpoint}


static func _configure_arrival_only(endpoint: Dictionary) -> void:
	endpoint["portal_role"] = "arrival_only_endpoint"
	endpoint["semantic_role"] = "map_portal_arrival_anchor"
	endpoint["connection_mode"] = "arrival_only"
	endpoint["one_way"] = false
	endpoint["arrival_only"] = true
	endpoint["trigger_on_enter"] = false
	endpoint["target_configured"] = false
	endpoint["target_map_id"] = -1
	endpoint["explicit_one_way_reason"] = (
		"terminal_dungeon_has_no_return_portal"
	)
	endpoint["exit_policy"] = "town_scroll_or_death_only"
	for field: String in [
		"connection_pair_id",
		"connection_direction",
		"reciprocal_exit_id",
		"reciprocal_map_key",
		"target_map_key",
		"target_portal_id",
		"target_entrance_id",
		"target_tile",
		"official_connection_id",
		"source_map_key",
	]:
		endpoint.erase(field)


static func _target_portal_tile(
	target_identity: Dictionary,
	target_portal_id: String,
	documents_by_map_id: Dictionary
) -> Dictionary:
	var canonical_map_id := str(target_identity.map_id)
	var target_document: Dictionary = {}
	if documents_by_map_id.has(canonical_map_id):
		var raw: Variant = documents_by_map_id[canonical_map_id]
		if raw is Dictionary:
			target_document = raw
	else:
		var legacy_map_id := str(target_identity.legacy_map_id)
		var path := "%s%s/%s.editor.json" % [
			WORKSPACE_ROOT, legacy_map_id, legacy_map_id,
		]
		target_document = _read_json(path, "portal_target_document")
	if target_document.is_empty():
		return {
			"ok": false,
			"errors": ["portal_target_document_unreadable:%s" % canonical_map_id],
		}
	var source_key := str(target_document.get("map_id", ""))
	if source_key not in [canonical_map_id, str(target_identity.legacy_map_id)]:
		return {
			"ok": false,
			"errors": ["portal_target_document_identity_mismatch:%s" % canonical_map_id],
		}
	var expected_runtime_id := (
		int(target_identity.runtime_map_id)
		if source_key == canonical_map_id
		else int(target_identity.legacy_runtime_map_id)
	)
	if int(target_document.get("runtime_map_id", -1)) != expected_runtime_id:
		return {
			"ok": false,
			"errors": ["portal_target_document_runtime_mismatch:%s" % canonical_map_id],
		}
	var target_layers: Variant = target_document.get("layers", {})
	if not target_layers is Dictionary:
		return {
			"ok": false,
			"errors": ["portal_target_layers_invalid:%s" % canonical_map_id],
		}
	var target_endpoints: Variant = target_layers.get("map_exit_points", [])
	if not target_endpoints is Array:
		return {
			"ok": false,
			"errors": ["portal_target_endpoints_invalid:%s" % canonical_map_id],
		}
	var matches: Array = []
	for raw_endpoint: Variant in target_endpoints:
		if not raw_endpoint is Dictionary:
			continue
		var endpoint_id_result := _endpoint_id(raw_endpoint)
		if (
			bool(endpoint_id_result.get("ok", false))
			and str(endpoint_id_result.portal_id) == target_portal_id
		):
			matches.append(raw_endpoint)
	if matches.size() != 1:
		return {
			"ok": false,
			"errors": [
				"portal_target_endpoint_not_unique:%s:%s:%d"
				% [canonical_map_id, target_portal_id, matches.size()]
			],
		}
	var tile: Variant = matches[0].get("tile", [])
	if not tile is Array or tile.size() != 2:
		return {
			"ok": false,
			"errors": ["portal_target_tile_invalid:%s:%s" % [canonical_map_id, target_portal_id]],
		}
	return {"ok": true, "tile": tile.duplicate(true)}


static func _endpoint_id(endpoint: Dictionary) -> Dictionary:
	var semantic_id := str(endpoint.get("semantic_id", "")).strip_edges()
	var exit_id := str(endpoint.get("exit_id", "")).strip_edges()
	if semantic_id.is_empty() and exit_id.is_empty():
		return {"ok": false, "errors": ["portal_endpoint_id_required"]}
	if not semantic_id.is_empty() and not exit_id.is_empty() and semantic_id != exit_id:
		return {
			"ok": false,
			"errors": ["portal_semantic_exit_id_mismatch:%s:%s" % [semantic_id, exit_id]],
		}
	return {"ok": true, "portal_id": semantic_id if not semantic_id.is_empty() else exit_id}


static func _endpoint_key(map_id: String, portal_id: String) -> String:
	return "%s::%s" % [map_id, portal_id]


static func _read_json(path: String, _label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
