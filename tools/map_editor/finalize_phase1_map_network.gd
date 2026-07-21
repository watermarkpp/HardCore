extends SceneTree

const ConnectionPolicyService := preload(
	"res://scripts/map_editor/map_editor_connection_policy_service.gd"
)

const NETWORK_VERSION_ID := "phase1_finished_map_network_v1"
const ONE_WAY_REASON := "尸王殿只允许进入，离开必须使用回城功能或死亡回城"
const MARKER_PATH := (
	"res://assets/data/runtime/map_editor/"
	+ "phase1_map_network.manual_ready.json"
)
const MINE_1_PATH := (
	"res://map_editor_workspace/bich_mine_1/bich_mine_1.editor.json"
)
const MINE_2_PATH := (
	"res://map_editor_workspace/bich_mine_2/bich_mine_2.editor.json"
)
const MAP_IDS := [
	"bich_province",
	"wooma_forest",
	"wooma_temple_1",
	"wooma_temple_2",
	"wooma_temple_3",
	"orc_tomb_1",
	"orc_tomb_2",
	"orc_tomb_3",
	"bich_mine_1",
	"bich_mine_2",
	"corpse_king_hall",
]
const MODIFIED_MAP_IDS := [
	"bich_province",
	"wooma_forest",
	"wooma_temple_1",
	"wooma_temple_2",
	"wooma_temple_3",
	"orc_tomb_1",
	"orc_tomb_2",
	"orc_tomb_3",
	"bich_mine_1",
	"bich_mine_2",
	"corpse_king_hall",
]


func _init() -> void:
	var mine_1 := _load(MINE_1_PATH)
	if mine_1.is_empty():
		return
	var mine_2 := _load_or_clone_mine_2(mine_1)
	if mine_2.is_empty():
		return
	var documents := {"bich_mine_1": mine_1, "bich_mine_2": mine_2}
	for map_id: String in MAP_IDS:
		if documents.has(map_id):
			continue
		var document := _load(MapEditorSaveService.default_path(map_id))
		if document.is_empty():
			return
		documents[map_id] = document

	var bich_bottom := _promote_bich_bottom_exit(documents.bich_province)
	if bich_bottom.is_empty():
		return

	var links := [
		{
			"source": "bich_province", "source_exit": "map_exit_000001",
			"target": "wooma_forest", "target_seed": "map_entrance_000001",
			"pair": "bich_wooma_forest_pair_v2",
			"forward": "前往沃玛森林", "reverse": "返回比奇省",
			"forward_id": "bich_north_to_wooma_forest_v2",
			"reverse_id": "wooma_forest_to_bich_v1",
		},
		{
			"source": "bich_province", "source_exit": "map_exit_000002",
			"target": "orc_tomb_1", "target_seed": "map_entrance_000001",
			"pair": "bich_orc_tomb_1_pair_v2",
			"forward": "进入兽人古墓一层", "reverse": "返回比奇省",
			"forward_id": "bich_east_to_orc_tomb_1_v3",
			"reverse_id": "orc_tomb_1_to_bich_v1",
		},
		{
			"source": "orc_tomb_1", "source_exit": "map_exit_000001",
			"target": "orc_tomb_2", "target_seed": "map_entrance_000001",
			"pair": "orc_tomb_1_2_pair_v1",
			"forward": "前往兽人古墓二层", "reverse": "返回兽人古墓一层",
			"forward_id": "orc_tomb_1_to_2_v1",
			"reverse_id": "orc_tomb_2_to_1_v1",
		},
		{
			"source": "orc_tomb_2", "source_exit": "map_exit_000001",
			"target": "orc_tomb_3", "target_seed": "map_entrance_000001",
			"pair": "orc_tomb_2_3_pair_v1",
			"forward": "前往兽人古墓三层", "reverse": "返回兽人古墓二层",
			"forward_id": "orc_tomb_2_to_3_v1",
			"reverse_id": "orc_tomb_3_to_2_v1",
		},
	]
	for link: Dictionary in links:
		var result := ConnectionPolicyService.configure_bidirectional(
			documents[str(link.source)],
			str(link.source_exit),
			"",
			documents[str(link.target)],
			str(link.target_seed),
			str(link.pair),
			str(link.forward),
			str(link.reverse),
			str(link.forward_id),
			str(link.reverse_id)
		)
		if not bool(result.get("ok", false)):
			_fail("connection_failed:%s:%s" % [link.pair, result.get("errors", [])])
			return

	var endpoint_links := [
		{
			"source": "bich_province", "source_exit": str(bich_bottom.semantic_id),
			"target": "bich_mine_1", "target_exit": "map_exit_000001",
			"pair": "bich_mine_1_pair_v1",
			"forward": "进入矿区一层", "reverse": "返回比奇省",
			"forward_id": "bich_bottom_to_mine_1_v1",
			"reverse_id": "bich_mine_1_to_province_v1",
		},
		{
			"source": "bich_mine_1", "source_exit": "map_exit_000002",
			"target": "bich_mine_2", "target_exit": "map_exit_000001",
			"pair": "bich_mine_1_2_pair_v1",
			"forward": "前往矿区二层", "reverse": "返回矿区一层",
			"forward_id": "bich_mine_1_to_2_v1",
			"reverse_id": "bich_mine_2_to_1_v1",
		},
	]
	for link: Dictionary in endpoint_links:
		var result := ConnectionPolicyService.configure_bidirectional_endpoints(
			documents[str(link.source)],
			str(link.source_exit),
			documents[str(link.target)],
			str(link.target_exit),
			str(link.pair),
			str(link.forward),
			str(link.reverse),
			str(link.forward_id),
			str(link.reverse_id)
		)
		if not bool(result.get("ok", false)):
			_fail("endpoint_connection_failed:%s:%s" % [link.pair, result.get("errors", [])])
			return

	var corpse_result := ConnectionPolicyService.configure_one_way_to_arrival(
		documents.bich_mine_2,
		"map_exit_000002",
		documents.corpse_king_hall,
		"map_exit_000001",
		"进入尸王殿",
		"bich_mine_2_to_corpse_king_hall_one_way_v1",
		ONE_WAY_REASON
	)
	if not bool(corpse_result.get("ok", false)):
		_fail("corpse_one_way_failed:%s" % corpse_result.get("errors", []))
		return

	var reciprocal_errors := (
		ConnectionPolicyService.validate_reciprocal_pairs(documents)
	)
	if not reciprocal_errors.is_empty():
		_fail("reciprocal_validation:%s" % reciprocal_errors)
		return

	var runtimes := {}
	for map_id: String in MAP_IDS:
		var document: Dictionary = documents[map_id]
		_mark_phase1(document)
		if map_id in MODIFIED_MAP_IDS:
			var runtime := _save_and_build(document)
			if runtime.is_empty():
				return
			runtimes[map_id] = runtime
		else:
			var loaded := MapEditorRuntimeMapService.load_runtime(
				MapEditorBuildRuntimeService.default_runtime_path(map_id)
			)
			if not bool(loaded.get("ok", false)):
				_fail("runtime_load_failed:%s:%s" % [map_id, loaded.get("errors", [])])
				return
			runtimes[map_id] = loaded.runtime

	var network_errors := MapPortalRuntimeService.validate_network(runtimes)
	if not network_errors.is_empty():
		_fail("runtime_network_validation:%s" % network_errors)
		return
	if not _write_marker(documents, runtimes):
		return
	if not _refresh_wooma_route_marker(runtimes):
		return
	print(
		"PHASE1_MAP_NETWORK_FINALIZED "
		+ "route=4<->406<->408->1578 "
		+ "default=bidirectional corpse_exit=town_or_death_only "
		+ "maps=11 pairs=9 one_way=1"
	)
	quit(0)


func _load(path: String) -> Dictionary:
	var loaded := MapEditorLoadService.load_document(path)
	if not bool(loaded.get("ok", false)):
		_fail("load_failed:%s:%s" % [path, loaded.get("errors", [])])
		return {}
	return loaded.document


func _load_or_clone_mine_2(mine_1: Dictionary) -> Dictionary:
	if FileAccess.file_exists(MINE_2_PATH):
		return _load(MINE_2_PATH)
	var copy_ok := _copy_directory(
		"res://map_editor_workspace/bich_mine_1/ground",
		"res://map_editor_workspace/bich_mine_2/ground"
	)
	if not copy_ok:
		return {}
	for relative_path: String in [
		"ground/ground_manifest.json",
		"ground/ground_state.json",
		"ground/baked_preview/bake_manifest.json",
	]:
		var path := "res://map_editor_workspace/bich_mine_2/" + relative_path
		var value := _read_json(path)
		if value.is_empty():
			_fail("mine_2_ground_json_missing:%s" % path)
			return {}
		value["map_id"] = "bich_mine_2"
		var write := MapEditorGroundService._write_json_atomic(path, value)
		if not bool(write.get("ok", false)):
			_fail("mine_2_ground_json_write_failed:%s" % write.get("errors", []))
			return {}
	var mine_2 := mine_1.duplicate(true)
	mine_2["map_id"] = "bich_mine_2"
	mine_2["runtime_map_id"] = 408
	mine_2["display_name"] = "矿区二层"
	var meta: Dictionary = mine_2.editor_meta
	meta["blank_template_id"] = "blank.bich_mine_2"
	meta["workspace"] = "res://map_editor_workspace/bich_mine_2"
	meta["revision"] = 1
	meta["clone_source_map_id"] = "bich_mine_1"
	meta["clone_policy_id"] = "user_exact_map_copy_v1"
	meta.erase("runtime_approved")
	meta.erase("runtime_approved_revision")
	mine_2["editor_meta"] = meta
	for key: String in [
		"chunk_manifest", "paint_manifest", "paint_state",
		"source_manifest", "workspace_manifest", "workspace_state",
	]:
		mine_2.ground[key] = str(mine_2.ground.get(key, "")).replace(
			"bich_mine_1", "bich_mine_2"
		)
	var reference: Dictionary = mine_2.get("source_reference", {})
	reference["cloned_from_map_id"] = "bich_mine_1"
	reference["clone_policy_id"] = "user_exact_map_copy_v1"
	mine_2["source_reference"] = reference
	return mine_2


func _promote_bich_bottom_exit(bich: Dictionary) -> Dictionary:
	for endpoint: Dictionary in bich.layers.map_exit_points:
		if str(endpoint.get("official_connection_id", "")) == "bich_bottom_to_mine_1_v1":
			return endpoint
		if str(endpoint.get("semantic_id", "")) == "map_exit_000003":
			return endpoint
	var bottom_door: Dictionary = {}
	for door: Dictionary in bich.layers.door_points:
		if str(door.get("semantic_id", "")) == "door_000004":
			bottom_door = door
			break
	if bottom_door.is_empty() or _tile(bottom_door) != Vector2i(7, 74):
		_fail("bich_lowest_exit_marker_missing_or_moved")
		return {}
	bich.layers.door_points.erase(bottom_door)
	var endpoint := bottom_door.duplicate(true)
	endpoint.merge(ConnectionPolicyService.new_exit_defaults(), true)
	endpoint.erase("door_id")
	endpoint["kind"] = "map_exit"
	endpoint["semantic_id"] = "map_exit_000003"
	endpoint["exit_id"] = "map_exit_000003"
	endpoint["semantic_role"] = "map_portal_endpoint"
	endpoint["portal_role"] = "bidirectional_endpoint"
	endpoint["display_name"] = "进入矿区一层"
	endpoint["target_configured"] = false
	bich.layers.map_exit_points.append(endpoint)
	return endpoint


func _mark_phase1(document: Dictionary) -> void:
	var meta: Dictionary = document.get("editor_meta", {})
	if str(meta.get("phase1_network_version_id", "")) != NETWORK_VERSION_ID:
		meta["revision"] = int(meta.get("revision", 1)) + 1
	meta["phase1_network_version_id"] = NETWORK_VERSION_ID
	meta["connection_policy_id"] = ConnectionPolicyService.POLICY_ID
	meta["portal_contract_id"] = ConnectionPolicyService.PORTAL_CONTRACT_ID
	meta["default_connection_mode"] = "bidirectional"
	meta["phase1_map_production_complete"] = true
	if str(document.map_id) == "corpse_king_hall":
		meta["exit_policy"] = "town_scroll_or_death_only"
		meta["one_way_exception_id"] = "corpse_king_hall_one_way_v1"
	document["editor_meta"] = meta


func _save_and_build(document: Dictionary) -> Dictionary:
	var bake := MapEditorChunkBakeService.bake_dirty_chunks(document)
	if not bool(bake.get("ok", false)):
		_fail("bake_failed:%s:%s" % [document.map_id, bake.get("errors", [])])
		return {}
	var approval := MapEditorBuildRuntimeService.approve_for_runtime(document)
	if not bool(approval.get("ok", false)):
		_fail("approval_failed:%s:%s" % [document.map_id, approval.get("errors", [])])
		return {}
	var save := MapEditorSaveService.save_document(
		document, MapEditorSaveService.default_path(str(document.map_id))
	)
	if not bool(save.get("ok", false)):
		_fail("save_failed:%s:%s" % [document.map_id, save.get("errors", [])])
		return {}
	var build := MapEditorBuildRuntimeService.build(document)
	if not bool(build.get("ok", false)):
		_fail("build_failed:%s:%s" % [document.map_id, build.get("errors", [])])
		return {}
	return build.runtime


func _write_marker(documents: Dictionary, runtimes: Dictionary) -> bool:
	var maps: Array = []
	var connections: Array = []
	var pair_ids := {}
	var one_way_count := 0
	for map_id: String in MAP_IDS:
		var document: Dictionary = documents[map_id]
		maps.append({
			"map_id": map_id,
			"runtime_map_id": int(document.runtime_map_id),
			"display_name": str(document.display_name),
			"runtime_build_sha256": str(runtimes[map_id].build_sha256),
		})
		for endpoint: Dictionary in document.layers.map_exit_points:
			if not bool(endpoint.get("target_configured", false)):
				continue
			if str(endpoint.get("connection_policy_id", "")) != ConnectionPolicyService.POLICY_ID:
				continue
			connections.append({
				"source_map_key": map_id,
				"source_runtime_map_id": int(document.runtime_map_id),
				"source_portal_id": str(endpoint.semantic_id),
				"source_tile": endpoint.tile.duplicate(),
				"target_map_key": str(endpoint.target_map_key),
				"target_map_id": int(endpoint.target_map_id),
				"target_portal_id": str(endpoint.target_portal_id),
				"target_tile": endpoint.target_tile.duplicate(),
				"connection_mode": str(endpoint.connection_mode),
				"connection_pair_id": str(endpoint.get("connection_pair_id", "")),
			})
			if bool(endpoint.get("one_way", false)):
				one_way_count += 1
			else:
				pair_ids[str(endpoint.connection_pair_id)] = true
	var marker := {
		"schema_version": 1,
		"network_version_id": NETWORK_VERSION_ID,
		"connection_policy_id": ConnectionPolicyService.POLICY_ID,
		"portal_contract_id": ConnectionPolicyService.PORTAL_CONTRACT_ID,
		"default_connection_mode": "bidirectional",
		"phase1_map_production_complete": true,
		"maps": maps,
		"connections": connections,
		"bidirectional_pair_count": pair_ids.size(),
		"one_way_exception_count": one_way_count,
		"one_way_exceptions": [{
			"exception_id": "corpse_king_hall_one_way_v1",
			"source_map_key": "bich_mine_2",
			"target_map_key": "corpse_king_hall",
			"target_arrival_portal_id": "map_exit_000001",
			"exit_policy": "town_scroll_or_death_only",
			"reason": ONE_WAY_REASON,
		}],
	}
	var write := MapEditorGroundService._write_json_atomic(MARKER_PATH, marker)
	if not bool(write.get("ok", false)):
		_fail("marker_write_failed:%s" % write.get("errors", []))
		return false
	return true


func _refresh_wooma_route_marker(runtimes: Dictionary) -> bool:
	var path := (
		"res://assets/data/runtime/map_editor/"
		+ "wooma_temple_route.manual_ready.json"
	)
	var marker := _read_json(path)
	if marker.is_empty():
		_fail("wooma_route_marker_missing")
		return false
	for map_summary: Dictionary in marker.get("maps", []):
		var map_id := str(map_summary.get("map_id", ""))
		if runtimes.has(map_id):
			map_summary["runtime_build_sha256"] = str(
				runtimes[map_id].build_sha256
			)
	var write := MapEditorGroundService._write_json_atomic(path, marker)
	if not bool(write.get("ok", false)):
		_fail("wooma_route_marker_refresh_failed:%s" % write.get("errors", []))
		return false
	return true


func _copy_directory(source: String, target: String) -> bool:
	var source_absolute := ProjectSettings.globalize_path(source)
	var target_absolute := ProjectSettings.globalize_path(target)
	var mkdir := DirAccess.make_dir_recursive_absolute(target_absolute)
	if mkdir != OK:
		_fail("copy_mkdir_failed:%s:%d" % [target, mkdir])
		return false
	var directory := DirAccess.open(source_absolute)
	if directory == null:
		_fail("copy_source_missing:%s" % source)
		return false
	for file_name: String in directory.get_files():
		var copy := DirAccess.copy_absolute(
			source_absolute.path_join(file_name),
			target_absolute.path_join(file_name)
		)
		if copy != OK:
			_fail("copy_file_failed:%s:%d" % [file_name, copy])
			return false
	for directory_name: String in directory.get_directories():
		if not _copy_directory(
			source.path_join(directory_name),
			target.path_join(directory_name)
		):
			return false
	return true


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _tile(entry: Dictionary) -> Vector2i:
	var raw: Array = entry.get("tile", [0, 0])
	return Vector2i(int(raw[0]), int(raw[1]))


func _fail(message: String) -> void:
	push_error("PHASE1_MAP_NETWORK_FINALIZE_FAILED %s" % message)
	quit(1)
