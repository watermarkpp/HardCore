extends Node

## Publish the complete formal-map identity registry through the production
## Build Candidate -> Validate -> Publish transaction. Authoring documents are
## loaded and upgraded in memory only; this tool never rewrites them.

const IDENTITY_PATH := "res://assets/data/map_design/map_identity_registry.json"
const PORTAL_NETWORK_PATH := "res://assets/data/map_design/map_portal_network.json"
const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const BuildService := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const MapEditorTypes := preload("res://scripts/map_editor/map_editor_types.gd")
const ContentCatalog := preload("res://scripts/map_editor/map_editor_content_catalog_service.gd")
const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const RespawnPolicy := preload("res://scripts/monster_respawn_policy.gd")

const EXPECTED_MAPS := 67
const EXPECTED_MONSTER_SPAWNS := 1607
const EXPECTED_BOSS_SPAWNS := 273
const EXPECTED_RUNTIME_MONSTER_SPAWNS := 1604
const EXPECTED_RUNTIME_BOSS_SPAWNS := 276

var _errors: Array[String] = []


func _ready() -> void:
	var identity := _read_json(IDENTITY_PATH)
	var identity_maps: Variant = identity.get("maps", [])
	if (
		str(identity.get("contract_id", "")) != "hardcore.formal_map_identity.v1"
		or not identity_maps is Array
		or identity_maps.size() != EXPECTED_MAPS
	):
		_fail("formal_map_identity_invalid")
		return
	if not _write_json_atomic(REGISTRY_PATH, {
		"schema_version": 1,
		"registry_contract_id": "mse.map.runtime.release.v1",
		"maps": [],
	}):
		_fail("release_registry_reset_failed")
		return
	RuntimeBridge.invalidate_release_registry()

	var expected_ids: Array[int] = []
	var source_monsters := 0
	var source_bosses := 0
	for raw_entry: Variant in identity_maps:
		if not raw_entry is Dictionary:
			_errors.append("identity_entry_invalid")
			continue
		var entry: Dictionary = raw_entry
		var map_key := str(entry.get("map_id", ""))
		var runtime_map_id := int(entry.get("runtime_map_id", -1))
		if map_key.is_empty() or runtime_map_id <= 0:
			_errors.append("identity_fields_invalid:%s" % map_key)
			continue
		expected_ids.append(runtime_map_id)
		var editor_path := (
			"res://map_editor_workspace/%s/%s.editor.json"
			% [map_key, map_key]
		)
		var raw_document := _read_json(editor_path)
		if raw_document.is_empty():
			_errors.append("editor_document_missing:%s" % editor_path)
			continue
		if str(raw_document.get("map_id", "")) != map_key:
			_errors.append("editor_identity_mismatch:%s" % map_key)
			continue
		var layers: Dictionary = raw_document.get("layers", {})
		source_monsters += (layers.get("monster_spawn", []) as Array).size()
		source_bosses += (layers.get("boss_spawn", []) as Array).size()
		var document := MapEditorTypes.upgrade_document(raw_document)
		# The identity registry is the frozen runtime identity authority. Three
		# legacy v4 Chiyue documents still carry shared source locator IDs; bind
		# the upgraded in-memory candidate to its canonical ID without rewriting
		# the user's authoring document.
		document["runtime_map_id"] = runtime_map_id
		document["display_name"] = str(entry.get("display_name", ""))
		_canonicalize_spawn_layers(document)
		_normalize_portal_units(document)
		_bind_portal_network(document, identity_maps)
		ContentCatalog.canonicalize_document_npc_labels(document)
		var approval := BuildService.approve_for_runtime(document)
		if not bool(approval.get("ok", false)):
			_errors.append(
				"approval_failed:%s:%s"
				% [map_key, str(approval.get("errors", []))]
			)
			continue
		var candidate := BuildService.build_candidate(document)
		if not bool(candidate.get("ok", false)):
			_errors.append(
				"build_failed:%s:%s"
				% [map_key, str(candidate.get("errors", []))]
			)
			continue
		var published := BuildService.publish_runtime_release(
			str(candidate.get("candidate_path", "")),
			runtime_map_id,
			candidate.get("document_binding", {}),
			REGISTRY_PATH,
			map_key
		)
		if not bool(published.get("success", false)):
			_errors.append("publish_failed:%s:%s" % [map_key, str(published)])

	if not _errors.is_empty():
		_fail(";".join(_errors))
		return
	expected_ids.sort()
	var released := RuntimeBridge.released_map_ids()
	if released != expected_ids:
		_fail("released_ids_mismatch")
		return
	var runtime_monsters := 0
	var runtime_bosses := 0
	for runtime_map_id: int in released:
		if not RuntimeBridge.is_formal_playable(runtime_map_id):
			_errors.append("runtime_not_playable:%d" % runtime_map_id)
			continue
		var runtime := RuntimeBridge.load_map(runtime_map_id)
		var semantics: Dictionary = runtime.get("semantics", {})
		runtime_monsters += (semantics.get("monster_spawn", []) as Array).size()
		runtime_bosses += (semantics.get("boss_spawn", []) as Array).size()
	if (
		source_monsters != EXPECTED_MONSTER_SPAWNS
		or source_bosses != EXPECTED_BOSS_SPAWNS
		or runtime_monsters != EXPECTED_RUNTIME_MONSTER_SPAWNS
		or runtime_bosses != EXPECTED_RUNTIME_BOSS_SPAWNS
	):
		_errors.append(
			"placement_totals_mismatch:source=%d/%d:runtime=%d/%d"
			% [source_monsters, source_bosses, runtime_monsters, runtime_bosses]
		)
	if not _errors.is_empty():
		_fail(";".join(_errors))
		return
	print(
		"MAP_FORMAL_RELEASE_PUBLISH_PASS maps=%d monster=%d boss=%d total=%d"
		% [released.size(), runtime_monsters, runtime_bosses, runtime_monsters + runtime_bosses]
	)
	get_tree().quit(0)


func _canonicalize_spawn_layers(document: Dictionary) -> void:
	# The user's placements and coordinates are frozen, but three authoring rows
	# predate the canonical elite/boss layer contract. Rebind only their runtime
	# semantic lane in memory so production never drops a valid placement.
	var layers: Dictionary = document.get("layers", {})
	var normalized := {
		"monster_spawn": [],
		"boss_spawn": [],
	}
	for source_layer: String in ["monster_spawn", "boss_spawn"]:
		for raw_entry: Variant in layers.get(source_layer, []):
			if not raw_entry is Dictionary:
				_errors.append(
					"spawn_entry_invalid:%s:%s"
					% [str(document.get("map_id", "")), source_layer]
				)
				continue
			var spawn: Dictionary = raw_entry
			var monster_id := int(spawn.get("monster_id", -1))
			var canonical := ContentCatalog.find_any_monster(monster_id)
			var target_layer := str(canonical.get("placement_kind", ""))
			if target_layer not in ["monster_spawn", "boss_spawn"]:
				_errors.append(
					"spawn_identity_unresolved:%s:%d"
					% [str(document.get("map_id", "")), monster_id]
				)
				continue
			_apply_current_respawn_authority(
				spawn, canonical, target_layer, str(document.get("map_id", ""))
			)
			normalized[target_layer].append(spawn)
	layers["monster_spawn"] = normalized["monster_spawn"]
	layers["boss_spawn"] = normalized["boss_spawn"]
	document["layers"] = layers


func _apply_current_respawn_authority(
	spawn: Dictionary,
	canonical: Dictionary,
	target_layer: String,
	map_key: String
) -> void:
	var classification := str(canonical.get("classification", ""))
	var spawn_classification := str(
		canonical.get("spawn_classification", "")
	)
	var policy_id := ""
	if spawn_classification == RespawnPolicy.SPECIAL_NORMAL:
		policy_id = RespawnPolicy.SPECIAL_NORMAL
	elif target_layer == "boss_spawn":
		policy_id = (
			RespawnPolicy.BOSS
			if classification == "boss"
			else RespawnPolicy.ELITE
		)
	else:
		policy_id = (
			RespawnPolicy.BEGINNER_OUTDOOR
			if map_key.begins_with("world_")
			else RespawnPolicy.NORMAL_CAVE
		)
	spawn["respawn_policy_id"] = policy_id
	spawn["respawn_seconds"] = RespawnPolicy.seconds_for(policy_id)
	spawn["respawn_random_seconds"] = 0.0


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _normalize_portal_units(document: Dictionary) -> void:
	var layers: Dictionary = document.get("layers", {})
	for layer_name: String in ["door_points", "map_exit_points"]:
		var entries: Variant = layers.get(layer_name, [])
		if not entries is Array:
			continue
		for raw_endpoint: Variant in entries:
			if not raw_endpoint is Dictionary:
				continue
			var endpoint: Dictionary = raw_endpoint
			if (
				float(endpoint.get("return_unlock_distance_gu", 0.0)) <= 0.0
				and float(endpoint.get("return_unlock_distance_tiles", 0.0)) > 0.0
			):
				endpoint["return_unlock_distance_gu"] = float(
					endpoint.get("return_unlock_distance_tiles", 0.0)
				)
			endpoint.erase("return_unlock_distance_tiles")


func _bind_portal_network(document: Dictionary, identity_maps: Array) -> void:
	var network := _read_json(PORTAL_NETWORK_PATH)
	var current_key := str(document.get("map_id", ""))
	for raw_connection: Variant in network.get("connections", []):
		if not raw_connection is Dictionary:
			continue
		var connection: Dictionary = raw_connection
		var mode := str(connection.get("mode", ""))
		if mode == "bidirectional":
			var a_key := str(connection.get("a_map_id", ""))
			var b_key := str(connection.get("b_map_id", ""))
			if current_key == a_key:
				_configure_bidirectional_endpoint(
				document,
				str(connection.get("a_portal_id", "")),
				b_key,
				str(connection.get("b_portal_id", "")),
				str(connection.get("pair_id", "")),
				"forward",
				identity_maps
			)
			elif current_key == b_key:
				_configure_bidirectional_endpoint(
				document,
				str(connection.get("b_portal_id", "")),
				a_key,
				str(connection.get("a_portal_id", "")),
				str(connection.get("pair_id", "")),
				"reverse",
				identity_maps
			)
		elif mode == "one_way":
			var source_key := str(connection.get("source_map_id", ""))
			var target_key := str(connection.get("target_map_id", ""))
			if current_key == source_key:
				_configure_one_way_source(
					document,
					str(connection.get("source_portal_id", "")),
					target_key,
					str(connection.get("target_portal_id", "")),
					identity_maps
				)
			elif current_key == target_key:
				_configure_arrival_endpoint(
					document,
					str(connection.get("target_portal_id", ""))
				)


func _configure_bidirectional_endpoint(
	document: Dictionary,
	portal_id: String,
	target_map_key: String,
	target_portal_id: String,
	pair_id: String,
	direction: String,
	identity_maps: Array
) -> void:
	var endpoint := _endpoint(document, portal_id)
	if endpoint.is_empty():
		_errors.append("portal_endpoint_missing:%s:%s" % [document.map_id, portal_id])
		return
	_apply_portal_defaults(endpoint)
	endpoint["portal_role"] = "bidirectional_endpoint"
	endpoint["connection_mode"] = "bidirectional"
	endpoint["one_way"] = false
	endpoint.erase("arrival_only")
	endpoint.erase("explicit_one_way_reason")
	endpoint["target_configured"] = true
	endpoint["target_map_id"] = _runtime_id_for_key(identity_maps, target_map_key)
	endpoint["target_map_key"] = target_map_key
	endpoint["target_portal_id"] = target_portal_id
	endpoint["target_entrance_id"] = target_portal_id
	endpoint["target_tile"] = _endpoint_tile(target_map_key, target_portal_id)
	endpoint["official_connection_id"] = "portal.%s.%s" % [document.map_id, portal_id]
	endpoint["connection_pair_id"] = pair_id
	endpoint["connection_direction"] = direction
	endpoint["source_map_key"] = str(document.map_id)
	endpoint["reciprocal_exit_id"] = target_portal_id
	endpoint["reciprocal_map_key"] = target_map_key


func _configure_one_way_source(
	document: Dictionary,
	portal_id: String,
	target_map_key: String,
	target_portal_id: String,
	identity_maps: Array
) -> void:
	var endpoint := _endpoint(document, portal_id)
	if endpoint.is_empty():
		_errors.append("portal_endpoint_missing:%s:%s" % [document.map_id, portal_id])
		return
	_apply_portal_defaults(endpoint)
	endpoint["portal_role"] = "one_way_endpoint"
	endpoint["connection_mode"] = "one_way"
	endpoint["one_way"] = true
	endpoint["explicit_one_way_reason"] = "terminal_dungeon_has_no_return_portal"
	endpoint["target_configured"] = true
	endpoint["target_map_id"] = _runtime_id_for_key(identity_maps, target_map_key)
	endpoint["target_map_key"] = target_map_key
	endpoint["target_portal_id"] = target_portal_id
	endpoint["target_entrance_id"] = target_portal_id
	endpoint["target_tile"] = _endpoint_tile(target_map_key, target_portal_id)
	endpoint["official_connection_id"] = "portal.%s.%s" % [document.map_id, portal_id]
	endpoint["source_map_key"] = str(document.map_id)
	for field: String in [
		"connection_pair_id", "connection_direction", "reciprocal_exit_id",
		"reciprocal_map_key", "arrival_only", "exit_policy",
	]:
		endpoint.erase(field)


func _configure_arrival_endpoint(document: Dictionary, portal_id: String) -> void:
	var endpoint := _endpoint(document, portal_id)
	if endpoint.is_empty():
		_errors.append("portal_endpoint_missing:%s:%s" % [document.map_id, portal_id])
		return
	_apply_portal_defaults(endpoint)
	endpoint["portal_role"] = "arrival_only_endpoint"
	endpoint["semantic_role"] = "map_portal_arrival_anchor"
	endpoint["connection_mode"] = "arrival_only"
	endpoint["one_way"] = false
	endpoint["arrival_only"] = true
	endpoint["trigger_on_enter"] = false
	endpoint["target_configured"] = false
	endpoint["target_map_id"] = -1
	endpoint["explicit_one_way_reason"] = "terminal_dungeon_has_no_return_portal"
	endpoint["exit_policy"] = "town_scroll_or_death_only"
	for field: String in [
		"connection_pair_id", "connection_direction", "reciprocal_exit_id",
		"reciprocal_map_key", "target_map_key", "target_portal_id",
		"target_entrance_id", "target_tile", "official_connection_id",
		"source_map_key",
	]:
		endpoint.erase(field)


func _apply_portal_defaults(endpoint: Dictionary) -> void:
	endpoint["kind"] = "map_exit"
	endpoint["exit_id"] = str(endpoint.get("semantic_id", ""))
	endpoint["connection_policy_id"] = "map_connection_unified_bidirectional_v2"
	endpoint["portal_contract_id"] = "unified_map_portal_endpoint_v1"
	endpoint["semantic_role"] = "map_portal_endpoint"
	endpoint["arrival_reentry_policy_id"] = "portal_arrival_guard_v2"
	endpoint["arrival_locks_current_portal"] = true
	endpoint["requires_leave_before_retrigger"] = true
	endpoint["return_minimum_seconds"] = 3.0
	endpoint["return_unlock_distance_gu"] = 1.5
	endpoint.erase("return_unlock_distance_tiles")
	endpoint["return_requires_fresh_activation"] = true
	endpoint["travel_request_single_flight"] = true
	endpoint["trigger_on_enter"] = true
	endpoint["blocks_movement"] = false
	endpoint["runtime_export"] = true


func _endpoint(document: Dictionary, portal_id: String) -> Dictionary:
	for raw_endpoint: Variant in document.get("layers", {}).get("map_exit_points", []):
		if (
			raw_endpoint is Dictionary
			and str(raw_endpoint.get("semantic_id", "")) == portal_id
		):
			return raw_endpoint
	return {}


func _endpoint_tile(map_key: String, portal_id: String) -> Array:
	var path := "res://map_editor_workspace/%s/%s.editor.json" % [map_key, map_key]
	var document := MapEditorTypes.upgrade_document(_read_json(path))
	var endpoint := _endpoint(document, portal_id)
	return endpoint.get("tile", []).duplicate()


func _runtime_id_for_key(identity_maps: Array, map_key: String) -> int:
	for raw_identity: Variant in identity_maps:
		if (
			raw_identity is Dictionary
			and str(raw_identity.get("map_id", "")) == map_key
		):
			return int(raw_identity.get("runtime_map_id", -1))
	return -1


func _write_json_atomic(path: String, value: Dictionary) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var temp_path := absolute_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  ") + "\n")
	file.close()
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	return DirAccess.rename_absolute(temp_path, absolute_path) == OK


func _fail(message: String) -> void:
	push_error("MAP_FORMAL_RELEASE_PUBLISH_FAILED %s" % message)
	get_tree().quit(1)
