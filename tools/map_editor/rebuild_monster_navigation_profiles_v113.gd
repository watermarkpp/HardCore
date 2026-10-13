extends Node

## Exact-map maintenance entry. All runtime bytes are generated and published
## by the editor build service; authored sources are read-only inputs.
const Build := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const PolyBuild := preload("res://scripts/map_editor/polygon/poly_build.gd")
const Ground := preload("res://scripts/map_editor/map_editor_ground_service.gd")
const Wall := preload("res://scripts/map_editor/map_editor_wall_render_publish_service.gd")
const REGISTRY := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const CONTRACT := "isometric_cell_center_64x32_v2"

func _ready() -> void:
	# The test host calls execute() without adding this tool to the tree.
	var result := execute(OS.get_environment("HARDCORE_NAVIGATION_MANIFEST"), int(OS.get_environment("HARDCORE_NAVIGATION_MAP_ID")), OS.get_environment("HARDCORE_NAVIGATION_OUTPUT_DIR"))
	print("NAVIGATION_PUBLICATION_", "PASS" if result.ok else "FAIL", " ", JSON.stringify(result))
	get_tree().quit(0 if result.ok else 1)

func execute(manifest_path: String, map_id: int, output_dir: String) -> Dictionary:
	if manifest_path.is_empty() or output_dir.is_empty() or map_id <= 0:
		return _failed("explicit_manifest_map_and_output_required")
	var manifest := _read(manifest_path)
	if str(manifest.get("schema", "")) != "hardcore.navigation_rebuild.v113.v1" or manifest.get("maps", []).size() != 67:
		return _failed("authorized_67_map_manifest_invalid")
	var selected: Dictionary = {}
	var seen: Dictionary = {}
	var preserved: Dictionary = {}
	for row: Dictionary in manifest.maps:
		var id := int(row.get("map_id", -1))
		var key := str(row.get("map_key", ""))
		if id <= 0 or seen.has(id) or key.is_empty() or key.get_file() != key or key.contains(".."):
			return _failed("manifest_identity_invalid")
		seen[id] = true
		if str(row.get("runtime", "")) != "assets/data/runtime/map_editor/%s.runtime.json" % key or str(row.get("source", "")) != "map_editor_workspace/%s/%s.editor.json" % [key, key]:
			return _failed("manifest_path_outside_exact_map")
		if id == map_id:
			selected = row
		else:
			preserved["res://" + str(row.runtime)] = FileAccess.get_sha256("res://" + str(row.runtime))
	if selected.is_empty():
		return _failed("map_not_authorized")
	var map_key := str(selected.map_key)
	var source := "res://" + str(selected.source)
	var runtime_path := "res://" + str(selected.runtime)
	if FileAccess.get_sha256(source) != str(selected.source_sha256) or FileAccess.get_sha256(runtime_path) != str(selected.runtime_sha256):
		return _failed("source_or_runtime_drift_from_manifest")
	var registry_before := _read(REGISTRY)
	var registry_ids: Dictionary = {}
	for entry: Dictionary in registry_before.get("maps", []):
		if str(entry.get("release_state", "")) == "implemented_playable":
			registry_ids[int(entry.runtime_map_id)] = str(entry.map_key)
	for row: Dictionary in manifest.maps:
		if str(registry_ids.get(int(row.map_id), "")) != str(row.map_key):
			return _failed("manifest_not_bound_to_published_registry")
	var document := _read(source)
	var upgraded := MapEditorTypes.upgrade_document(document)
	if upgraded != document:
		return _failed("authoring_upgrade_would_change_document")
	if str(document.get("map_id", "")) != map_key or int(document.get("runtime_map_id", -1)) != map_id:
		return _failed("source_identity_mismatch")
	var ground_check := _capture_ground_inputs(document, source)
	if not ground_check.ok:
		return ground_check
	preserved.merge(ground_check.hashes)
	var before := _read(runtime_path)
	var visual_path := "res://assets/data/runtime/map_editor/%s.visual.json" % map_key
	var visual := _read(visual_path)
	var visual_check := _validate_frozen_visual(document, visual, before)
	if not visual_check.ok:
		return visual_check
	preserved[visual_path] = FileAccess.get_sha256(visual_path)
	for chunk: Dictionary in visual.get("chunks", []):
		var path := "res://" + str(chunk.get("image", ""))
		if FileAccess.get_sha256(path) != str(chunk.get("sha256", "")):
			return _failed("visual_chunk_hash_mismatch")
		preserved[path] = FileAccess.get_sha256(path)
	var wall_path := "res://assets/data/runtime/map_editor/wall_render_plans/%s.wall_render_plan.json" % map_key
	var old_wall := _read(wall_path)
	var candidate := Build.build_navigation_candidate(source, str(selected.source_sha256), runtime_path, str(selected.runtime_sha256))
	if not candidate.ok:
		return _failed(str(candidate.get("reason", "formal_navigation_candidate_failed")), candidate.get("errors", []))
	var differences: Array[String] = []
	_diff(_non_navigation(before), _non_navigation(candidate.runtime), "runtime", differences)
	if not differences.is_empty():
		return _failed("unexpected_non_navigation_candidate_difference", differences)
	var changed_inputs := _changed(preserved)
	if not changed_inputs.is_empty():
		return _failed("protected_input_changed_during_build", changed_inputs)
	var published := Build.publish_runtime_release(str(candidate.candidate_path), map_id, candidate.document_binding, REGISTRY, map_key)
	if not bool(published.get("success", false)):
		return _failed("formal_publication_failed", [JSON.stringify(published)])
	# Runtime+registry are now committed by the existing transaction. A later
	# wall failure is explicit partial publication for the controller to recover.
	if not old_wall.is_empty():
		var wall_publisher := Wall.new()
		wall_publisher.plan_directory = output_dir.path_join("wall_candidate")
		wall_publisher.staging_directory = output_dir.path_join("wall_staging")
		var wall_result := wall_publisher.publish_map(map_key)
		if wall_result.has("error"):
			return _failed("runtime_published_wall_candidate_failed", [str(wall_result.error)])
		var new_wall := _read(wall_publisher.plan_directory.path_join(map_key + ".wall_render_plan.json"))
		var old_wall_content := old_wall.duplicate(true)
		var new_wall_content := new_wall.duplicate(true)
		old_wall_content.erase("source_runtime_json_sha256")
		new_wall_content.erase("source_runtime_json_sha256")
		differences.clear()
		_diff(old_wall_content, new_wall_content, "wall", differences)
		if not differences.is_empty():
			return _failed("runtime_published_unexpected_wall_content_difference", differences)
		# The formal publisher already generated and fully verified this candidate.
		# Its normal stage/commit operations install exactly those verified bytes.
		wall_publisher.plan_directory = Wall.PLAN_DIR
		var wall_error := wall_publisher._stage_plan_document(map_key, new_wall)
		if wall_error.is_empty():
			wall_error = wall_publisher._commit_plan_document(map_key)
		if not wall_error.is_empty():
			return _failed("runtime_published_wall_commit_failed", [wall_error])
	var after := _read(runtime_path)
	differences.clear()
	_diff(_non_navigation(before), _non_navigation(after), "runtime", differences)
	var final_check := PolyBuild.validate_monster_coverage(after)
	if not final_check.ok:
		return _failed("post_publish_navigation_invalid", final_check.errors)
	var registry_after := _read(REGISTRY)
	_diff(_other_registry(registry_before, map_id), _other_registry(registry_after, map_id), "sibling_registry", differences)
	differences.append_array(_changed(preserved))
	if not differences.is_empty():
		return _failed("post_publish_preservation_failed", differences)
	return {"ok": true, "status": "PASS", "map_id": map_id, "map_key": map_key,
		"manifest_sha256": FileAccess.get_sha256(manifest_path), "source_sha256": FileAccess.get_sha256(source),
		"runtime_before_sha256": selected.runtime_sha256, "runtime_after_sha256": FileAccess.get_sha256(runtime_path),
		"candidate_path": candidate.candidate_path, "build_sha256": after.build_sha256,
		"navigation_update_binding": candidate.navigation_update_binding,
		"body_inventory_sha256": final_check.body_inventory_sha256,
		"visual_editor_provenance": {"recorded_sha256": visual.get("source_editor_document_sha256", ""),
			"current_sha256": FileAccess.get_sha256(source),
			"matches_current_bytes": str(visual.get("source_editor_document_sha256", "")) == FileAccess.get_sha256(source),
			"ground_manifest_and_chunk_content": "PASS", "ground_state_projection": "PASS",
			"ground_state_recorded_sha256": visual.get("source_ground_state_sha256", ""),
			"ground_state_current_sha256": FileAccess.get_sha256(str(document.ground.workspace_state)),
			"ground_state_runtime_before_sha256": before.get("source", {}).get("candidate_binding", {}).get("ground_state_sha256", ""),
			"ground_state_byte_hash_matches_record": str(visual.get("source_ground_state_sha256", "")) == FileAccess.get_sha256(str(document.ground.workspace_state)),
			"visual_bytes_preserved": true},
		"preserved_inputs": preserved, "wall_result": "PASS" if not old_wall.is_empty() else "NOT_RUN"}

func _validate_frozen_visual(document: Dictionary, visual: Dictionary, published_runtime: Dictionary) -> Dictionary:
	# Ground's historical editor hash also covers nonvisual edits. Navigation
	# maintenance preserves it as provenance; actual ground bindings and every
	# packaged pixel chunk must still match the current saved ground authority.
	var expected_fields := {"visual_contract_id": "mse.map.runtime.visual.v1", "source_authority": "user_authored_baked_ground", "map_id": document.map_id, "runtime_map_id": document.runtime_map_id, "design_size": document.design.design_size}
	var field_errors: Array[String] = []
	for field: String in expected_fields:
		if visual.get(field, null) != expected_fields[field]:
			field_errors.append("field=%s map=%s expected=%s actual=%s" % [field, document.map_id, JSON.stringify(expected_fields[field]), JSON.stringify(visual.get(field, null))])
	if not field_errors.is_empty():
		return _failed("visual_identity_or_geometry_contract_mismatch", field_errors)
	var manifest_path := str(document.ground.workspace_manifest)
	var state_path := str(document.ground.workspace_state)
	var actual_manifest_sha := FileAccess.get_sha256(manifest_path)
	var recorded_manifest_sha := str(visual.get("source_ground_manifest_sha256", ""))
	if recorded_manifest_sha != actual_manifest_sha:
		return _failed("visual_ground_authority_binding_mismatch", ["field=source_ground_manifest_sha256 map=%s recorded=%s current=%s" % [document.map_id, recorded_manifest_sha, actual_manifest_sha]])
	var recorded_state_sha := str(visual.get("source_ground_state_sha256", ""))
	if recorded_state_sha.length() != 64 or not recorded_state_sha.is_valid_hex_number():
		return _failed("visual_ground_state_provenance_invalid", ["field=source_ground_state_sha256 map=%s recorded=%s" % [document.map_id, recorded_state_sha]])
	var state := _read(state_path)
	if str(state.get("map_id", "")) != str(document.map_id) or str(state.get("coordinate_contract_id", "")) != CONTRACT or not state.get("dirty_chunks", []).is_empty():
		return _failed("current_ground_state_identity_or_dirty_mismatch", ["map=%s path=%s fields=%s" % [document.map_id, state_path, JSON.stringify({"map_id": state.get("map_id", null), "coordinate_contract_id": state.get("coordinate_contract_id", null), "dirty_chunks": state.get("dirty_chunks", null)})]])
	# An operation journal's bytes may differ while its final painted map is
	# identical. Require the actual formal projection to match the published
	# ground, in addition to all unchanged manifest and PNG bytes below.
	var ground_differences: Array[String] = []
	_diff(published_runtime.get("ground", {}).get("tile_overrides", {}), Ground.tile_overrides(state), "ground.tile_overrides", ground_differences)
	if not ground_differences.is_empty():
		ground_differences.push_front("field=source_ground_state_sha256 map=%s recorded=%s current=%s" % [document.map_id, recorded_state_sha, FileAccess.get_sha256(state_path)])
		return _failed("current_ground_projection_differs_from_published_runtime", ground_differences)
	var manifest := _read(manifest_path)
	if visual.get("ground_pixel_size", []) != manifest.get("ground_pixel_size", []) or str(visual.get("ground_coordinate_contract_id", "")) != CONTRACT:
		return _failed("visual_ground_coordinate_mismatch", ["map=%s ground_pixel_size expected=%s actual=%s ground_coordinate_contract_id expected=%s actual=%s" % [document.map_id, str(manifest.get("ground_pixel_size", [])), str(visual.get("ground_pixel_size", [])), CONTRACT, str(visual.get("ground_coordinate_contract_id", ""))]])
	var expected: Dictionary = {}
	for chunk: Dictionary in manifest.get("chunks", []):
		if not bool(chunk.get("materialized", false)):
			continue
		var preview := Ground.workspace_root(document).path_join(str(chunk.get("preview_png", "")))
		expected[str(chunk.get("chunk_id", ""))] = {"rect_px": chunk.get("rect_px", []), "sha256": FileAccess.get_sha256(preview)}
	var observed: Dictionary = {}
	for chunk: Dictionary in visual.get("chunks", []):
		var id := str(chunk.get("chunk_id", ""))
		if id.is_empty() or observed.has(id) or not expected.has(id) or chunk.get("rect_px", []) != expected[id].rect_px or str(chunk.get("sha256", "")) != str(expected[id].sha256):
			return _failed("visual_chunk_differs_from_saved_ground", ["map=%s chunk_id=%s duplicate=%s expected=%s actual=%s" % [document.map_id, id, str(observed.has(id)), JSON.stringify(expected.get(id, {})), JSON.stringify(chunk)]])
		observed[id] = true
	if observed.size() != expected.size() or expected.is_empty():
		return _failed("visual_ground_chunk_coverage_mismatch", ["map=%s materialized=%d observed=%d" % [document.map_id, expected.size(), observed.size()]])
	return {"ok": true}

func _capture_ground_inputs(document: Dictionary, source: String) -> Dictionary:
	var root := Ground.workspace_root(document)
	if FileAccess.file_exists(root.path_join(Ground.WRITE_SET_FILE)):
		return _failed("ground_pending_write_transaction")
	var manifest_path := root.path_join("ground/ground_manifest.json")
	var state_path := root.path_join("ground/ground_state.json")
	var manifest := _read(manifest_path)
	var state := _read(state_path)
	if manifest.is_empty() or state.is_empty():
		return _failed("ground_primary_missing")
	# Predict and reject initialization writes before calling BuildService.
	var changed_blank := Ground._sync_blank_policy(document, manifest.duplicate(true))
	var size_data: Array = document.design.design_size
	var changed_contract := Ground._sync_coordinate_contract(manifest.duplicate(true), state.duplicate(true), Vector2i(int(size_data[0]), int(size_data[1])))
	if changed_blank or changed_contract.manifest_changed or changed_contract.state_changed:
		return _failed("ground_initialization_would_write")
	var hashes := {source: FileAccess.get_sha256(source), manifest_path: FileAccess.get_sha256(manifest_path), state_path: FileAccess.get_sha256(state_path)}
	for chunk: Dictionary in manifest.get("chunks", []):
		var preview := str(chunk.get("preview_png", ""))
		if preview.is_empty():
			continue
		if preview.contains("..") or not preview.begins_with("ground/"):
			return _failed("ground_preview_path_invalid")
		var path := root.path_join(preview)
		if not FileAccess.file_exists(path):
			return _failed("ground_preview_missing")
		hashes[path] = FileAccess.get_sha256(path)
	return {"ok": true, "hashes": hashes}

func _non_navigation(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result.erase("build_sha256")
	if result.get("collision", null) is Dictionary:
		result.collision.erase("navigation")
	return result

func _other_registry(value: Dictionary, selected_id: int) -> Dictionary:
	var result := value.duplicate(true)
	result.maps = result.get("maps", []).filter(func(row: Dictionary) -> bool: return int(row.get("runtime_map_id", -1)) != selected_id)
	return result

func _diff(a: Variant, b: Variant, path: String, out: Array[String]) -> void:
	if a is Dictionary and b is Dictionary:
		var keys: Dictionary = {}
		for key: Variant in a: keys[key] = true
		for key: Variant in b: keys[key] = true
		for key: Variant in keys:
			if not a.has(key) or not b.has(key):
				out.append(path + "." + str(key))
			else:
				_diff(a[key], b[key], path + "." + str(key), out)
	elif a is Array and b is Array:
		if a.size() != b.size():
			out.append(path + ".length")
		else:
			for i: int in range(a.size()): _diff(a[i], b[i], "%s[%d]" % [path, i], out)
	elif a != b:
		out.append(path)

func _changed(hashes: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for path: String in hashes:
		if FileAccess.get_sha256(path) != str(hashes[path]): result.append(path)
	return result

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _failed(reason: String, errors: Array = []) -> Dictionary:
	return {"ok": false, "status": "FAIL", "reason": reason, "errors": errors}
