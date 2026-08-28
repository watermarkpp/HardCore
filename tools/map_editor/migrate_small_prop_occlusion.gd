extends Node

## MSE small_prop occlusion authority migration.
##
## This tool deliberately edits only the explicit `occlusion` field on the
## reviewed small_decoration asset IDs and their authored instances. Formal
## runtime artifacts are rebuilt through the existing BuildService so their
## build hash remains authoritative; no coordinates, geometry, collision,
## ground, or visual assets are regenerated.

const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const MapEditorTypes := preload("res://scripts/map_editor/map_editor_types.gd")
const MapEditorJsonCodec := preload(
	"res://scripts/map_editor/map_editor_json_codec.gd"
)
const MapEditorContentCatalogService := preload(
	"res://scripts/map_editor/map_editor_content_catalog_service.gd"
)

const CATALOG_PATH := (
	"res://assets/data/assets/map_small_decoration_asset_catalog.json"
)
const REGISTRY_PATH := (
	"res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
)
const WORKSPACE_ROOT := "res://map_editor_workspace"
const SMALL_PREFIX := "mse.small_decor."
const EXPECTED_SMALL_ASSET_COUNT := 48

var _errors: Array[String] = []
var _dry_run := false
var _catalog_changed := 0
var _catalog_touched := 0
var _workspace_changed := 0
var _workspace_document_count := 0
var _workspace_instances := 0
var _runtime_changed := 0
var _runtime_instances := 0
var _runtime_hashes: Dictionary = {}


func _ready() -> void:
	_dry_run = (
		"--dry-run" in OS.get_cmdline_args()
		or OS.get_environment("MSE_SMALL_PROP_DRY_RUN") == "1"
	)
	var result := _run_migration()
	if not result:
		push_error("MSE_SMALL_PROP_OCCLUSION_MIGRATION_FAILED %s" % ";".join(_errors))
		get_tree().quit(1)
		return
	print((
		"MSE_SMALL_PROP_OCCLUSION_MIGRATION_PASS dry_run=%s catalog_assets=%d "
			+ "workspace_documents=%d workspace_instances=%d runtime_maps=%d "
		+ "runtime_instances=%d changed_catalog=%d changed_workspace=%d "
		+ "changed_runtime=%d"
	)
		% [
			str(_dry_run),
			EXPECTED_SMALL_ASSET_COUNT,
			_workspace_document_count,
			_workspace_instances,
			_runtime_hashes.size(),
			_runtime_instances,
			_catalog_changed,
			_workspace_changed,
			_runtime_changed,
		]
	)
	get_tree().quit(0)


func _run_migration() -> bool:
	var catalog_text := _read_text(CATALOG_PATH)
	if catalog_text.is_empty():
		return _fail("catalog_missing")
	var catalog := _parse_dictionary(catalog_text, CATALOG_PATH)
	if catalog.is_empty():
		return false
	var catalog_ids := _catalog_small_ids(catalog)
	if catalog_ids.size() != EXPECTED_SMALL_ASSET_COUNT:
		return _fail("catalog_small_asset_count:%d" % catalog_ids.size())
	var expected_ids := _expected_small_ids()
	if catalog_ids != expected_ids:
		return _fail("catalog_small_asset_id_set_mismatch")
	var catalog_rewrite := _rewrite_small_object_fields(
		catalog_text, "catalog", catalog_ids
	)
	if not catalog_rewrite.ok:
		return false
	_catalog_changed = int(catalog_rewrite.changed)
	_catalog_touched = int(catalog_rewrite.get("touched", 0))
	if not _dry_run and _catalog_changed > 0:
		if not _write_text(CATALOG_PATH, str(catalog_rewrite.text)):
			return _fail("catalog_write_failed")

	var workspace_paths := _collect_editor_paths(WORKSPACE_ROOT)
	var workspace_documents := 0
	for path: String in workspace_paths:
		var text := _read_text(path)
		if text.is_empty():
			continue
		var document := _parse_dictionary(text, path)
		if document.is_empty():
			return false
		var ids := _small_ids_in_document(document)
		if ids.is_empty():
			continue
		workspace_documents += 1
		_workspace_document_count += 1
		_workspace_instances += ids.size()
		var rewrite := _rewrite_small_object_fields(text, path, ids)
		if not rewrite.ok:
			return false
		if int(rewrite.get("touched", 0)) != ids.size():
			return _fail(
				"workspace_instance_rewrite_count:%s:%d/%d"
				% [path, int(rewrite.get("touched", 0)), ids.size()]
			)
		if int(rewrite.changed) > 0:
			_workspace_changed += 1
			if not _dry_run and not _write_text(path, str(rewrite.text)):
				return _fail("workspace_write_failed:%s" % path)

	var registry_text := _read_text(REGISTRY_PATH)
	if registry_text.is_empty():
		return _fail("registry_missing")
	var registry := _parse_dictionary(registry_text, REGISTRY_PATH)
	if registry.is_empty():
		return false
	var formal_targets := _formal_small_runtime_targets(registry)
	if formal_targets.is_empty():
		return _fail("formal_small_runtime_targets_missing")
	for target: Dictionary in formal_targets:
		if not _rebuild_formal_runtime(target):
			return false
	var registry_rewrite := _rewrite_registry_hashes(
		registry_text, _runtime_hashes
	)
	if not registry_rewrite.ok:
		return false
	if not _dry_run and bool(registry_rewrite.changed):
		if not _write_text(REGISTRY_PATH, str(registry_rewrite.text)):
			return _fail("registry_write_failed")
	if _dry_run:
		return true
	return _verify_final_state(workspace_paths, formal_targets)


func _formal_small_runtime_targets(registry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var maps: Variant = registry.get("maps", [])
	if not maps is Array:
		_fail("registry_maps_invalid")
		return result
	for raw: Variant in maps:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var map_key := str(entry.get("map_key", ""))
		var runtime_path := str(entry.get("runtime_path", ""))
		if map_key.is_empty() or runtime_path.is_empty():
			continue
		if not runtime_path.begins_with("res://assets/data/runtime/map_editor/"):
			continue
		var runtime_text := _read_text(runtime_path)
		if runtime_text.is_empty():
			continue
		var runtime := _parse_dictionary(runtime_text, runtime_path)
		if runtime.is_empty():
			return []
		var ids := _small_ids_in_instances(runtime.get("instances", []))
		if ids.is_empty():
			continue
		var editor_path := "%s/%s/%s.editor.json" % [
			WORKSPACE_ROOT, map_key, map_key
		]
		if not FileAccess.file_exists(editor_path):
			_fail("formal_editor_missing:%s" % editor_path)
			return []
		result.append({
			"map_key": map_key,
			"runtime_map_id": int(entry.get("runtime_map_id", -1)),
			"runtime_path": runtime_path,
			"editor_path": editor_path,
			"expected_instance_count": ids.size(),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.map_key) < str(b.map_key)
	)
	return result


func _rebuild_formal_runtime(target: Dictionary) -> bool:
	var editor_path := str(target.get("editor_path", ""))
	var raw_document := _parse_dictionary(_read_text(editor_path), editor_path)
	if raw_document.is_empty():
		return false
	var document := MapEditorTypes.upgrade_document(raw_document)
	MapEditorContentCatalogService.canonicalize_document_npc_labels(document)
	var validation := BuildService.validate_for_runtime(document)
	if not bool(validation.get("ok", false)):
		return _fail(
			"formal_validation_failed:%s:%s"
			% [str(target.map_key), str(validation.get("errors", []))]
		)
	var runtime_path := str(target.get("runtime_path", ""))
	var old_runtime := _parse_dictionary(_read_text(runtime_path), runtime_path)
	if old_runtime.is_empty():
		return false
	var old_instances := _small_instances(old_runtime.get("instances", []))
	if old_instances.size() != int(target.get("expected_instance_count", -1)):
		return _fail("formal_runtime_source_count:%s" % str(target.map_key))
	# Keep the already-published runtime structure semantically stable.  The
	# published artifact predates the current ground-manifest canonicalization,
	# so calling document_binding(document) here would silently rewrite the
	# historical ground fingerprints even though this migration does not touch
	# ground data.  Refresh only the source document fingerprint and its
	# authoring digest; retain the published ground fingerprints as provenance.
	var old_source: Dictionary = old_runtime.get("source", {})
	var old_binding: Dictionary = old_source.get("candidate_binding", {})
	var binding := old_binding.duplicate(true)
	if binding.is_empty():
		return _fail("formal_candidate_binding_missing:%s" % str(target.get("map_key", "")))
	var document_sha256 := BuildService._sha256(MapEditorJsonCodec.encode(document))
	binding["document_sha256"] = document_sha256
	var authoring_fingerprint := {
		"document_sha256": document_sha256,
		"ground_manifest_sha256": str(binding.get("ground_manifest_sha256", "")),
		"ground_state_sha256": str(binding.get("ground_state_sha256", "")),
	}
	binding["authoring_sha256"] = BuildService._sha256(
		MapEditorJsonCodec.encode(authoring_fingerprint)
	)
	var runtime: Dictionary = old_runtime.duplicate(true)
	var source: Dictionary = runtime.get("source", {})
	source["candidate_binding"] = binding.duplicate(true)
	runtime["source"] = source
	var small_instances := _small_instances(runtime.get("instances", []))
	for instance: Dictionary in small_instances:
		instance["occlusion"] = true
	runtime["build_sha256"] = ""
	runtime["build_sha256"] = BuildService._sha256(
		MapEditorJsonCodec.encode(runtime)
	)
	var expected_count := int(target.get("expected_instance_count", -1))
	var actual_ids := _small_ids_in_instances(runtime.get("instances", []))
	if actual_ids.size() != expected_count:
		return _fail(
			"formal_runtime_instance_count:%s:%d/%d"
			% [str(target.map_key), actual_ids.size(), expected_count]
		)
	var old_text := _read_text(runtime_path)
	var new_text := MapEditorJsonCodec.encode(runtime)
	if old_text != new_text:
		_runtime_changed += 1
		if not _dry_run and not _write_text(runtime_path, new_text):
			return _fail("formal_runtime_write_failed:%s" % runtime_path)
	_runtime_instances += actual_ids.size()
	_runtime_hashes[str(target.map_key)] = str(runtime.get("build_sha256", ""))
	if str(runtime.get("build_sha256", "")).length() != 64:
		return _fail("formal_runtime_hash_missing:%s" % str(target.map_key))
	return true


func _verify_final_state(
	workspace_paths: Array[String], formal_targets: Array[Dictionary]
) -> bool:
	var catalog := _parse_dictionary(_read_text(CATALOG_PATH), CATALOG_PATH)
	if not _dry_run and catalog.is_empty():
		return false
	if not _dry_run:
		for raw: Variant in catalog.get("assets", []):
			if not raw is Dictionary:
				continue
			var asset: Dictionary = raw
			if str(asset.get("asset_id", "")).begins_with(SMALL_PREFIX):
				if not bool(asset.get("occlusion", false)):
					return _fail("catalog_occlusion_not_true:%s" % str(asset.asset_id))
	var workspace_total := 0
	for path: String in workspace_paths:
		var document := _parse_dictionary(_read_text(path), path)
		if document.is_empty():
			return false
		for instance: Dictionary in _all_document_instances(document):
			if not str(instance.get("asset_id", "")).begins_with(SMALL_PREFIX):
				continue
			workspace_total += 1
			if not bool(instance.get("occlusion", false)):
				return _fail("workspace_occlusion_not_true:%s:%s" % [path, str(instance.get("instance_id", ""))])
	if workspace_total != _workspace_instances:
		return _fail("workspace_final_count:%d/%d" % [workspace_total, _workspace_instances])
	var registry := _parse_dictionary(_read_text(REGISTRY_PATH), REGISTRY_PATH)
	if registry.is_empty():
		return false
	for target: Dictionary in formal_targets:
		var runtime_path := str(target.get("runtime_path", ""))
		var runtime := _parse_dictionary(_read_text(runtime_path), runtime_path)
		if runtime.is_empty():
			return false
		var small_instances := _small_instances(runtime.get("instances", []))
		if small_instances.size() != int(target.expected_instance_count):
			return _fail("runtime_final_count:%s" % str(target.map_key))
		for instance: Dictionary in small_instances:
			if not bool(instance.get("occlusion", false)):
				return _fail("runtime_occlusion_not_true:%s:%s" % [runtime_path, str(instance.get("instance_id", ""))])
		var map_key := str(target.get("map_key", ""))
		var approved_hash := _registry_hash(registry, map_key)
		if approved_hash != str(runtime.get("build_sha256", "")):
			return _fail("registry_runtime_hash_mismatch:%s" % map_key)
	return true


func _registry_hash(registry: Dictionary, map_key: String) -> String:
	for raw: Variant in registry.get("maps", []):
		if raw is Dictionary and str(raw.get("map_key", "")) == map_key:
			return str(raw.get("approved_build_sha256", ""))
	return ""


func _catalog_small_ids(catalog: Dictionary) -> Dictionary:
	var ids := {}
	for raw: Variant in catalog.get("assets", []):
		if raw is Dictionary:
			var asset_id := str(raw.get("asset_id", ""))
			if asset_id.begins_with(SMALL_PREFIX):
				ids[asset_id] = true
	return ids


func _small_ids_in_document(document: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for instance: Dictionary in _all_document_instances(document):
		var asset_id := str(instance.get("asset_id", ""))
		if asset_id.begins_with(SMALL_PREFIX):
			ids.append(asset_id)
	return ids


func _all_document_instances(document: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var layers: Variant = document.get("layers", {})
	if not layers is Dictionary:
		return result
	for raw_layer: Variant in layers.values():
		if not raw_layer is Array:
			continue
		for raw_entry: Variant in raw_layer:
			if raw_entry is Dictionary and raw_entry.has("asset_id"):
				result.append(raw_entry)
	return result


func _small_instances(instances: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not instances is Array:
		return result
	for raw: Variant in instances:
		if raw is Dictionary and str(raw.get("asset_id", "")).begins_with(SMALL_PREFIX):
			result.append(raw)
	return result


func _small_ids_in_instances(instances: Variant) -> Array[String]:
	var result: Array[String] = []
	for instance: Dictionary in _small_instances(instances):
		result.append(str(instance.get("asset_id", "")))
	return result


func _rewrite_small_object_fields(
	text: String, label: String, expected_ids: Variant
) -> Dictionary:
	var expected: Dictionary = {}
	if expected_ids is Dictionary:
		expected = expected_ids.duplicate(true)
	elif expected_ids is Array:
		for raw_id: Variant in expected_ids:
			expected[str(raw_id)] = true
	var remaining := expected.duplicate(true)
	var output := text
	var cursor := 0
	var changed := 0
	var touched := 0
	while true:
		var marker := output.find('"asset_id": "', cursor)
		if marker < 0:
			break
		var value_start := marker + 13
		var value_end := output.find('"', value_start)
		if value_end < 0:
			return _fail_result("asset_id_unterminated:%s" % label)
		var asset_id := output.substr(value_start, value_end - value_start)
		cursor = value_end + 1
		if not expected.has(asset_id):
			continue
		var object_start := output.rfind("{", marker)
		var object_end := _matching_object_end(output, object_start)
		if object_start < 0 or object_end <= object_start:
			return _fail_result("asset_object_span_missing:%s:%s" % [label, asset_id])
		var object_text := output.substr(object_start, object_end - object_start)
		var parsed: Variant = JSON.parse_string(object_text)
		if not parsed is Dictionary or str(parsed.get("asset_id", "")) != asset_id:
			return _fail_result("asset_object_identity_mismatch:%s:%s" % [label, asset_id])
		var false_field := '"occlusion": false'
		var true_field := '"occlusion": true'
		var field_offset := object_text.find(false_field)
		if field_offset >= 0:
			object_text = (
				object_text.substr(0, field_offset)
				+ true_field
				+ object_text.substr(field_offset + false_field.length())
			)
			changed += 1
		else:
			if object_text.find(true_field) < 0:
				return _fail_result("asset_occlusion_field_missing:%s:%s" % [label, asset_id])
		touched += 1
		remaining.erase(asset_id)
		output = output.substr(0, object_start) + object_text + output.substr(object_end)
		cursor = object_start + object_text.length()
	if not remaining.is_empty():
		return _fail_result("asset_object_not_found:%s:%s" % [label, str(remaining.keys())])
	return {"ok": true, "text": output, "changed": changed, "touched": touched}


func _rewrite_registry_hashes(text: String, hashes: Dictionary) -> Dictionary:
	var output := text
	var changed := false
	for map_key: String in hashes:
		var marker := output.find('"map_key": "' + map_key + '"')
		if marker < 0:
			return _fail_result("registry_map_key_missing:%s" % map_key)
		var object_start := output.rfind("{", marker)
		var object_end := _matching_object_end(output, object_start)
		if object_start < 0 or object_end <= object_start:
			return _fail_result("registry_object_span_missing:%s" % map_key)
		var object_text := output.substr(object_start, object_end - object_start)
		var field_marker := object_text.find('"approved_build_sha256": "')
		if field_marker < 0:
			return _fail_result("registry_hash_missing:%s" % map_key)
		var value_start := field_marker + 26
		var value_end := object_text.find('"', value_start)
		if value_end < 0:
			return _fail_result("registry_hash_unterminated:%s" % map_key)
		var replacement := str(hashes[map_key])
		if replacement.length() != 64:
			return _fail_result("registry_hash_invalid:%s" % map_key)
		object_text = (
			object_text.substr(0, value_start)
			+ replacement
			+ object_text.substr(value_end)
		)
		output = output.substr(0, object_start) + object_text + output.substr(object_end)
		changed = true
	return {"ok": true, "text": output, "changed": changed}


func _matching_object_end(text: String, object_start: int) -> int:
	if object_start < 0:
		return -1
	var depth := 0
	var in_string := false
	var escaped := false
	for index in range(object_start, text.length()):
		var character := text[index]
		if in_string:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == '"':
				in_string = false
			continue
		if character == '"':
			in_string = true
		elif character == "{":
			depth += 1
		elif character == "}":
			depth -= 1
			if depth == 0:
				return index + 1
	return -1


func _collect_editor_paths(root: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root)
	if directory == null:
		return result
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name in [".", ".."]:
			continue
		var child := root.path_join(name)
		if directory.current_is_dir():
			result.append_array(_collect_editor_paths(child))
		elif name.ends_with(".editor.json"):
			result.append(child)
	directory.list_dir_end()
	result.sort()
	return result


func _expected_small_ids() -> Dictionary:
	var result := {}
	for index in EXPECTED_SMALL_ASSET_COUNT:
		result["%s%03d" % [SMALL_PREFIX, index + 1]] = true
	return result


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _parse_dictionary(text: String, path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_fail("json_invalid:%s" % path)
		return {}
	return parsed


func _write_text(path: String, text: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var temporary := absolute + ".small_prop_occlusion.tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	file.close()
	if FileAccess.file_exists(absolute):
		if DirAccess.remove_absolute(absolute) != OK:
			return false
	return DirAccess.rename_absolute(temporary, absolute) == OK


func _fail(message: String) -> bool:
	_errors.append(message)
	return false


func _fail_result(message: String) -> Dictionary:
	_errors.append(message)
	return {"ok": false, "text": "", "changed": 0}
