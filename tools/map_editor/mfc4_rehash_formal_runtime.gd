extends SceneTree

## MFC-4F: Recompute formal runtime build_sha256 after explicit respawn_policy_id
## authoring was added to the formal runtime JSONs, then sync the Release Registry
## approved_build_sha256. Runtime JSON is the formal monster-spawn source of truth
## (all 11 formal editor.json documents carry monster_spawn=[] while the published
## runtimes carry the real spawn data), so the rebuild re-hashes the runtime in
## place instead of recompiling from the disconnected editor documents.
##
## This tool deliberately avoids preloading integration-owned bridge/build classes
## (they reference the GameData autoload singleton which is unavailable under
## --script). It re-implements only the canonical JSON encoding + SHA256 used by
## MapEditorJsonCodec/MapEditorBuildRuntimeService._sha256 so the hashes match
## production exactly.

const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const RUNTIME_ROOT := "res://assets/data/runtime/map_editor/"


func _init() -> void:
	var registry := _read_json(REGISTRY_PATH)
	var maps: Variant = registry.get("maps", [])
	if not maps is Array:
		_fail("registry_maps_invalid")
		return
	var errors: Array[String] = []
	var updated := {}
	for raw: Variant in maps:
		if not raw is Dictionary:
			errors.append("registry_map_entry_invalid")
			continue
		var entry: Dictionary = raw
		var map_key := str(entry.get("map_key", ""))
		var runtime_map_id := int(entry.get("runtime_map_id", -1))
		var runtime_path := str(entry.get("runtime_path", ""))
		if runtime_path.is_empty() or not FileAccess.file_exists(runtime_path):
			errors.append("runtime_file_missing:%s" % runtime_path)
			continue
		var runtime := _read_json(runtime_path)
		if runtime.is_empty():
			errors.append("runtime_json_invalid:%s" % runtime_path)
			continue
		var old_hash := str(runtime.get("build_sha256", ""))
		runtime["build_sha256"] = ""
		var new_hash := _sha256(_encode(runtime))
		runtime["build_sha256"] = new_hash
		var write := _write_text(runtime_path, _encode(runtime))
		if not write:
			errors.append("runtime_write_failed:%s" % runtime_path)
			continue
		entry["approved_build_sha256"] = new_hash
		updated[map_key] = {
			"runtime_map_id": runtime_map_id,
			"old": old_hash,
			"new": new_hash,
			"changed": old_hash != new_hash,
		}
	# Validate registry shape after update (same contract as production validator).
	var schema_errors := _validate_registry(registry)
	if not schema_errors.is_empty():
		errors.append("invalid_registry_after_update:%s" % ";".join(schema_errors))
	if not _write_json_atomic(REGISTRY_PATH, registry):
		errors.append("registry_write_failed")
	if not errors.is_empty():
		_fail(";".join(errors))
		return
	# Post-verification: every updated runtime must re-load and hash-match its
	# registry approval, and the runtime file must carry the policy data.
	for map_key: String in updated:
		var info: Dictionary = updated[map_key]
		var path := RUNTIME_ROOT + map_key + ".runtime.json"
		var runtime := _read_json(path)
		if runtime.is_empty():
			errors.append("verify_reload_failed:%s" % map_key)
			continue
		runtime["build_sha256"] = ""
		var verify_hash := _sha256(_encode(runtime))
		runtime["build_sha256"] = verify_hash
		if verify_hash != str(info.new):
			errors.append("verify_hash_mismatch:%s" % map_key)
		var spawns: Array = runtime.get("semantics", {}).get("monster_spawn", [])
		var missing_policy := 0
		for spawn: Variant in spawns:
			if spawn is Dictionary and not str((spawn as Dictionary).get("respawn_policy_id", "")).is_empty():
				continue
			if spawn is Dictionary:
				missing_policy += 1
		if missing_policy > 0:
			errors.append("verify_missing_policy:%s:%d" % [map_key, missing_policy])
		print(
			"MFC4_REHASH map=%s rid=%d changed=%s old=%s new=%s spawns=%d"
			% [map_key, info.runtime_map_id, info.changed, info.old, info.new, spawns.size()]
		)
	if not errors.is_empty():
		_fail(";".join(errors))
		return
	print("MFC4_REHASH_PASS maps=%d" % updated.size())
	quit(0)


## Production-equivalent canonical JSON encoding:
## JSON.stringify(_canonicalize(value), "  ", true, true) + "\n"
func _encode(value: Variant) -> String:
	return JSON.stringify(_canonicalize(value), "  ", true, true) + "\n"


func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for key: Variant in keys:
			result[key] = _canonicalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonicalize(item))
		return result
	return value


func _sha256(text: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(text.to_utf8_buffer())
	return hashing.finish().hex_encode()


func _validate_registry(registry: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(registry.get("schema_version", 0)) != 1:
		errors.append("unsupported_schema_version")
	if str(registry.get("registry_contract_id", "")) != "mse.map.runtime.release.v1":
		errors.append("invalid_registry_contract_id")
	var maps: Array = registry.get("maps", [])
	var ids := {}
	var keys := {}
	for raw_entry: Variant in maps:
		if not raw_entry is Dictionary:
			errors.append("invalid_entry")
			continue
		var entry: Dictionary = raw_entry
		var mid := int(entry.get("runtime_map_id", -1))
		var map_key := str(entry.get("map_key", ""))
		if mid <= 0:
			errors.append("invalid_runtime_map_id")
		if ids.has(mid):
			errors.append("duplicate_runtime_map_id")
		ids[mid] = true
		if map_key.is_empty():
			errors.append("missing_map_key")
		if keys.has(map_key):
			errors.append("duplicate_map_key")
		keys[map_key] = true
		if str(entry.get("runtime_path", "")).is_empty():
			errors.append("missing_runtime_path")
		if str(entry.get("approved_build_sha256", "")).is_empty():
			errors.append("missing_approved_hash")
		var release_state := str(entry.get("release_state", ""))
		if release_state != "implemented_playable" and release_state != "implemented_staging":
			errors.append("unknown_release_state")
	return errors


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _write_json_atomic(path: String, value: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var tmp := absolute + ".mfc4_tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(_encode(value))
	file.close()
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	var promote := DirAccess.rename_absolute(tmp, absolute)
	return promote == OK


func _fail(message: String) -> void:
	push_error("MFC4_REHASH_FAILED %s" % message)
	quit(1)
