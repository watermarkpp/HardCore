extends Node

## Publish the complete formal-map identity registry through the production
## Build Candidate -> Validate -> Publish transaction. Authoring documents are
## loaded and upgraded in memory only; this tool never rewrites them.

const IDENTITY_PATH := "res://assets/data/map_design/map_identity_registry.json"
const PORTAL_NETWORK_PATH := "res://assets/data/map_design/map_portal_network.json"
const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const BuildService := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const MapEditorTypes := preload("res://scripts/map_editor/map_editor_types.gd")
const MapEditorCoordinate := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const ContentCatalog := preload("res://scripts/map_editor/map_editor_content_catalog_service.gd")
const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const RespawnPolicy := preload("res://scripts/monster_respawn_policy.gd")

const EXPECTED_MAPS := 67
const EXPECTED_MONSTER_SPAWNS := 1607
const EXPECTED_BOSS_SPAWNS := 273
const EXPECTED_RUNTIME_MONSTER_SPAWNS := 1604
const EXPECTED_RUNTIME_BOSS_SPAWNS := 276
const VISUAL_CONTRACT_ID := "mse.map.runtime.visual.v1"
const GROUND_CHUNK_STORE_CONTRACT_ID := "mse.map.runtime.ground_chunk_store.sha256.v1"
const GROUND_COORDINATE_CONTRACT_ID := MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
const FORMAL_GROUND_CHUNK_ROOT := (
	"res://assets/data/runtime/map_editor/formal_ground_chunks/sha256"
)
const VISUAL_ROOT := "res://assets/data/runtime/map_editor/"

var _errors: Array[String] = []
var _visual_records: Dictionary = {}
var _visual_chunk_store: Dictionary = {}
var _visual_chunk_reference_count := 0


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
		var visual := _publish_formal_visual(
			map_key,
			runtime_map_id,
			editor_path
		)
		if not bool(visual.get("ok", false)):
			_errors.append(
				"visual_publish_failed:%s:%s"
				% [map_key, str(visual.get("errors", []))]
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
	if _visual_records.size() != released.size():
		_fail(
			"visual_release_count_mismatch:%d/%d"
			% [_visual_records.size(), released.size()]
		)
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
		"MAP_FORMAL_RELEASE_PUBLISH_PASS maps=%d visuals=%d monster=%d boss=%d total=%d visual_chunks=%d unique_visual_chunks=%d dedup_reused=%d"
		% [
			released.size(),
			_visual_records.size(),
			runtime_monsters,
			runtime_bosses,
			runtime_monsters + runtime_bosses,
			_visual_chunk_reference_count,
			_visual_chunk_store.size(),
			_visual_chunk_reference_count - _visual_chunk_store.size(),
		]
	)
	get_tree().quit(0)


func _publish_formal_visual(
	map_key: String,
	runtime_map_id: int,
	editor_path: String
) -> Dictionary:
	# The editor workspace is a user-frozen authority. Read its baked manifest
	# and state directly; never initialize, rebake, or otherwise write it here.
	var workspace_root := "res://map_editor_workspace/%s" % map_key
	var manifest_path := workspace_root + "/ground/ground_manifest.json"
	var state_path := workspace_root + "/ground/ground_state.json"
	var manifest := _read_json(manifest_path)
	var state := _read_json(state_path)
	if manifest.is_empty():
		return {"ok": false, "errors": ["ground_manifest_missing"]}
	if state.is_empty():
		return {"ok": false, "errors": ["ground_state_missing"]}
	if str(manifest.get("map_id", "")) != map_key:
		return {"ok": false, "errors": ["ground_manifest_map_id_mismatch"]}
	if str(state.get("map_id", "")) != map_key:
		return {"ok": false, "errors": ["ground_state_map_id_mismatch"]}
	if str(manifest.get("coordinate_contract_id", "")) != GROUND_COORDINATE_CONTRACT_ID:
		return {"ok": false, "errors": ["ground_manifest_coordinate_contract_invalid"]}
	if str(state.get("coordinate_contract_id", "")) != GROUND_COORDINATE_CONTRACT_ID:
		return {"ok": false, "errors": ["ground_state_coordinate_contract_invalid"]}
	var raw_dirty_chunks: Variant = state.get("dirty_chunks", [])
	if not raw_dirty_chunks is Array:
		return {"ok": false, "errors": ["ground_state_dirty_chunks_invalid"]}
	var dirty_chunks: Array = raw_dirty_chunks
	if not dirty_chunks.is_empty():
		return {"ok": false, "errors": ["ground_dirty_chunks_must_be_baked"]}
	var raw_chunks: Variant = manifest.get("chunks", [])
	if not raw_chunks is Array:
		return {"ok": false, "errors": ["ground_manifest_chunks_invalid"]}
	var chunks: Array = raw_chunks
	var design_size := _vector2i_field(manifest, "design_size")
	var ground_pixel_size := _vector2i_field(manifest, "ground_pixel_size")
	if design_size == Vector2i.ZERO or ground_pixel_size == Vector2i.ZERO:
		return {"ok": false, "errors": ["ground_manifest_size_invalid"]}
	var expected_pixel_size := MapEditorCoordinate.ground_image_size(design_size)
	if ground_pixel_size != expected_pixel_size:
		return {"ok": false, "errors": ["ground_pixel_size_mismatch"]}
	var editor_sha := FileAccess.get_sha256(editor_path)
	var manifest_sha := FileAccess.get_sha256(manifest_path)
	var state_sha := FileAccess.get_sha256(state_path)
	if editor_sha.length() != 64 or manifest_sha.length() != 64 or state_sha.length() != 64:
		return {"ok": false, "errors": ["ground_authority_hash_missing"]}
	var packaged_chunks: Array = []
	var seen_chunk_ids := {}
	for raw_chunk: Variant in chunks:
		if not raw_chunk is Dictionary:
			return {"ok": false, "errors": ["ground_chunk_invalid"]}
		var chunk: Dictionary = raw_chunk
		var chunk_id := str(chunk.get("chunk_id", ""))
		if chunk_id.is_empty() or seen_chunk_ids.has(chunk_id):
			return {"ok": false, "errors": ["ground_chunk_id_invalid:%s" % chunk_id]}
		seen_chunk_ids[chunk_id] = true
		if not bool(chunk.get("materialized", false)):
			if not str(chunk.get("preview_png", "")).is_empty():
				return {"ok": false, "errors": ["virtual_chunk_has_preview:%s" % chunk_id]}
			continue
		if str(chunk.get("state", "")) != "materialized":
			return {"ok": false, "errors": ["materialized_chunk_state_invalid:%s" % chunk_id]}
		if str(chunk.get("baked_coordinate_contract_id", "")) != GROUND_COORDINATE_CONTRACT_ID:
			return {"ok": false, "errors": ["baked_coordinate_contract_invalid:%s" % chunk_id]}
		if dirty_chunks.has(chunk_id):
			return {"ok": false, "errors": ["materialized_chunk_dirty:%s" % chunk_id]}
		var raw_rect: Variant = chunk.get("rect_px", [])
		if not raw_rect is Array or (raw_rect as Array).size() != 4:
			return {"ok": false, "errors": ["ground_chunk_rect_invalid:%s" % chunk_id]}
		var rect: Array = raw_rect
		var rect_position := Vector2i(int(rect[0]), int(rect[1]))
		var rect_size := Vector2i(int(rect[2]), int(rect[3]))
		if (
			rect_position.x < 0
			or rect_position.y < 0
			or rect_size.x <= 0
			or rect_size.y <= 0
			or rect_position.x + rect_size.x > ground_pixel_size.x
			or rect_position.y + rect_size.y > ground_pixel_size.y
		):
			return {"ok": false, "errors": ["ground_chunk_extent_invalid:%s" % chunk_id]}
		var preview_path := str(chunk.get("preview_png", ""))
		if not _is_safe_preview_path(preview_path):
			return {"ok": false, "errors": ["ground_preview_path_invalid:%s" % chunk_id]}
		var source_path := workspace_root + "/" + preview_path
		if not FileAccess.file_exists(source_path):
			return {"ok": false, "errors": ["ground_preview_missing:%s" % source_path]}
		var source_sha := FileAccess.get_sha256(source_path)
		if source_sha.length() != 64:
			return {"ok": false, "errors": ["ground_preview_hash_missing:%s" % chunk_id]}
		var image_check := _validate_ground_png(source_path, rect_size)
		if not bool(image_check.get("ok", false)):
			return {"ok": false, "errors": [str(image_check.get("error", "ground_png_invalid"))]}
		var stored := _ensure_formal_ground_chunk(source_path, source_sha)
		if not bool(stored.get("ok", false)):
			return stored
		packaged_chunks.append({
			"chunk_id": chunk_id,
			"rect_px": rect.duplicate(),
			"image": str(stored.get("image", "")),
			"sha256": source_sha,
		})
		_visual_chunk_reference_count += 1
	if packaged_chunks.is_empty():
		return {"ok": false, "errors": ["publishable_ground_missing"]}
	var visual := {
		"schema_version": 1,
		"visual_contract_id": VISUAL_CONTRACT_ID,
		"map_id": map_key,
		"runtime_map_id": runtime_map_id,
		"source_authority": "user_authored_baked_ground",
		"source_editor_document_sha256": editor_sha,
		"source_ground_manifest_sha256": manifest_sha,
		"source_ground_state_sha256": state_sha,
		"design_size": [design_size.x, design_size.y],
		"ground_coordinate_contract_id": GROUND_COORDINATE_CONTRACT_ID,
		"ground_pixel_size": [ground_pixel_size.x, ground_pixel_size.y],
		"ground_pixel_center": [
			MapEditorCoordinate.ground_pixel_center(design_size).x,
			MapEditorCoordinate.ground_pixel_center(design_size).y,
		],
		"base_color": _base_color_for_map(map_key),
		"guard_band_px": _guard_band_for_map(map_key),
		"render_mode": "batched_canvas_draw",
		"chunk_store": {
			"contract_id": GROUND_CHUNK_STORE_CONTRACT_ID,
			"root": FORMAL_GROUND_CHUNK_ROOT.trim_prefix("res://"),
			"deduplication": "sha256",
		},
		"coverage": {
			"source_chunk_count": chunks.size(),
			"required_chunk_count": packaged_chunks.size(),
			"packaged_chunk_count": packaged_chunks.size(),
			"complete": true,
		},
		"chunks": packaged_chunks,
	}
	var visual_path := VISUAL_ROOT + "%s.visual.json" % map_key
	var write := _write_json_atomic(visual_path, visual)
	if not write:
		return {"ok": false, "errors": ["visual_manifest_write_failed:%s" % map_key]}
	_visual_records[map_key] = {
		"runtime_map_id": runtime_map_id,
		"path": visual_path,
		"sha256": FileAccess.get_sha256(visual_path),
		"chunk_count": packaged_chunks.size(),
	}
	return {"ok": true, "chunk_count": packaged_chunks.size()}


func _ensure_formal_ground_chunk(source_path: String, source_sha: String) -> Dictionary:
	var image_path := "%s/%s.png" % [FORMAL_GROUND_CHUNK_ROOT, source_sha]
	var absolute_destination := ProjectSettings.globalize_path(image_path)
	var mkdir := DirAccess.make_dir_recursive_absolute(absolute_destination.get_base_dir())
	if mkdir != OK:
		return {"ok": false, "errors": ["ground_chunk_store_mkdir_failed:%d" % mkdir]}
	if (
		not FileAccess.file_exists(image_path)
		or FileAccess.get_sha256(image_path) != source_sha
	):
		if FileAccess.file_exists(image_path):
			DirAccess.remove_absolute(absolute_destination)
		var copy := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(source_path), absolute_destination
		)
		if copy != OK:
			return {"ok": false, "errors": ["ground_chunk_store_copy_failed:%d" % copy]}
		if FileAccess.get_sha256(image_path) != source_sha:
			return {"ok": false, "errors": ["ground_chunk_store_hash_mismatch"]}
	_visual_chunk_store[source_sha] = image_path
	return {"ok": true, "image": image_path.trim_prefix("res://")}


func _validate_ground_png(path: String, expected_size: Vector2i) -> Dictionary:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return {"ok": false, "error": "ground_png_invalid:%s" % path}
	if image.get_size() != expected_size:
		return {
			"ok": false,
			"error": "ground_png_size_mismatch:%s:%s/%s" % [
				path, image.get_size(), expected_size
			],
		}
	return {"ok": true}


func _is_safe_preview_path(path: String) -> bool:
	return (
		path.begins_with("ground/baked_preview/")
		and not path.contains("..")
		and not path.contains("\\")
		and path.get_file().ends_with(".png")
	)


func _vector2i_field(value: Dictionary, field: String) -> Vector2i:
	var raw: Variant = value.get(field, [])
	if not raw is Array or (raw as Array).size() != 2:
		return Vector2i.ZERO
	var values: Array = raw
	return Vector2i(int(values[0]), int(values[1]))


func _base_color_for_map(map_key: String) -> String:
	if map_key == "world_bich_province":
		return "#465827"
	if map_key == "bich_corpse_king_hall":
		return "#120e0d"
	if map_key.begins_with("bich_orc_tomb_"):
		return "#16120e"
	if map_key.begins_with("wooma_temple_"):
		return "#17130f"
	if map_key.begins_with("world_") or map_key.begins_with("fengmo_"):
		return "#182018"
	if map_key.begins_with("cangyue_"):
		return "#18252b"
	if map_key.begins_with("chiyue_"):
		return "#17121c"
	if map_key.begins_with("wooma_"):
		return "#172016"
	if map_key.begins_with("bich_mine_"):
		return "#151311"
	if map_key.begins_with("hidden_"):
		return "#141116"
	return "#16120e"


func _guard_band_for_map(map_key: String) -> float:
	return 1536.0 if map_key == "world_bich_province" else 512.0


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
