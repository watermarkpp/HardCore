extends SceneTree

## Per-map transactional publisher for the reviewed v2 monster placement batch.
## Default is dry-run.  --publish promotes each map independently through the
## frozen MapEditorBuildRuntimeService transaction.

const MANIFEST_PATH := "res://assets/data/map_design/map_monster_placement_plans_v2/manifest.json"
const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const TARGET_STATUS := "CANDIDATE_WRITTEN"

static var _build_service: Variant = null
static var _runtime_bridge: Variant = null
static var _runtime_map_service: Variant = null

var _publish := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for argument: String in args:
		if argument not in ["--publish", "--dry-run"]:
			_fail("unsupported_argument:%s" % argument)
			return
	if args.has("--publish") and args.has("--dry-run"):
		_fail("publish_and_dry_run_are_mutually_exclusive")
		return
	_publish = args.has("--publish")
	_run.call_deferred()


func _run() -> void:
	if not _ensure_services():
		_fail("formal_services_unreadable")
		return
	var manifest := _read_json(MANIFEST_PATH)
	var rows: Variant = manifest.get("maps", [])
	if (
		str(manifest.get("contract_id", ""))
			!= "hardcore.map_monster_placement_batch.v1"
		or not rows is Array
		or rows.size() != 67
	):
		_fail("placement_manifest_invalid")
		return
	var targets: Array[Dictionary] = []
	for raw: Variant in rows:
		if not raw is Dictionary:
			_fail("placement_manifest_map_invalid")
			return
		var row: Dictionary = raw
		if str(row.get("status", "")) == TARGET_STATUS:
			targets.append(row)
	if targets.size() != 66:
		_fail("placement_target_count_mismatch:%d" % targets.size())
		return
	var before_registry_sha := _file_sha256(REGISTRY_PATH)
	var results: Array[Dictionary] = []
	for row: Dictionary in targets:
		var result := _process_one(row)
		results.append(result)
		if not bool(result.get("ok", false)):
			_fail("map_failed:%s:%s" % [str(row.get("map_id", "")), str(result)])
			return
	var registry := _read_json(REGISTRY_PATH)
	var marker := (
		"MAP_MONSTER_PLACEMENT_BATCH_PUBLISH_PASS"
		if _publish
		else "MAP_MONSTER_PLACEMENT_BATCH_DRY_RUN_PASS"
	)
	print("%s %s" % [marker, JSON.stringify({
		"ok": true,
		"mode": "publish" if _publish else "dry_run",
		"map_count": results.size(),
		"registry_map_count": registry.get("maps", []).size(),
		"registry_sha256_before": before_registry_sha,
		"registry_sha256_after": _file_sha256(REGISTRY_PATH),
		"results": results,
	})])
	quit(0)


func _process_one(row: Dictionary) -> Dictionary:
	var map_id := str(row.get("map_id", ""))
	var legacy := str(row.get("legacy_map_id", ""))
	var runtime_map_id := int(row.get("runtime_map_id", -1))
	var source_path := "res://map_editor_workspace/%s/%s.editor.json" % [legacy, legacy]
	var source_sha := _file_sha256(source_path)
	if source_sha != str(row.get("candidate_sha256", "")):
		return {"ok": false, "reason": "source_candidate_hash_mismatch", "actual": source_sha}
	var document := _read_json(source_path)
	if (
		document.is_empty()
		or str(document.get("map_id", "")) != legacy
		or int(document.get("runtime_map_id", -1)) <= 0
	):
		return {"ok": false, "reason": "source_identity_invalid"}
	var source_spawn_errors := _spawn_errors(document.get("layers", {}), map_id)
	if not source_spawn_errors.is_empty():
		return {"ok": false, "reason": "source_spawn_invalid", "errors": source_spawn_errors}
	var candidate: Dictionary = _build_service.build_formal_candidate(document)
	if not bool(candidate.get("ok", false)):
		return {"ok": false, "reason": "formal_build_failed", "errors": candidate.get("errors", [])}
	if (
		str(candidate.get("map_key", "")) != map_id
		or int(candidate.get("formal_identity", {}).get("runtime_map_id", -1)) != runtime_map_id
	):
		return {"ok": false, "reason": "formal_identity_mismatch"}
	var runtime: Dictionary = candidate.get("runtime", {})
	var runtime_spawn_errors := _spawn_errors(runtime.get("semantics", {}), map_id)
	if not runtime_spawn_errors.is_empty():
		return {"ok": false, "reason": "runtime_spawn_invalid", "errors": runtime_spawn_errors}
	if _spawn_signature(document.get("layers", {})) != _spawn_signature(runtime.get("semantics", {})):
		return {"ok": false, "reason": "runtime_spawn_semantics_mismatch"}
	if _file_sha256(source_path) != source_sha:
		return {"ok": false, "reason": "source_mutated_during_build"}
	var result := {
		"ok": true,
		"map_id": map_id,
		"runtime_map_id": runtime_map_id,
		"build_sha256": str(candidate.get("build_sha256", "")),
		"monster_spawn_count": document.get("layers", {}).get("monster_spawn", []).size(),
		"boss_spawn_count": document.get("layers", {}).get("boss_spawn", []).size(),
		"published": false,
	}
	if not _publish:
		return result
	var published: Dictionary = _build_service.publish_runtime_release(
		str(candidate.get("candidate_path", "")),
		runtime_map_id,
		candidate.get("document_binding", {}),
		REGISTRY_PATH,
		map_id
	)
	if not bool(published.get("success", false)):
		return {"ok": false, "reason": "formal_publish_failed", "details": published}
	if _file_sha256(source_path) != source_sha:
		return {"ok": false, "reason": "source_mutated_during_publish"}
	var loaded: Dictionary = _runtime_map_service.load_runtime(
		str(_build_service.default_runtime_path(map_id))
	)
	if (
		not bool(loaded.get("ok", false))
		or str(loaded.get("runtime", {}).get("build_sha256", ""))
			!= str(candidate.get("build_sha256", ""))
		or not _runtime_bridge.is_formal_playable(runtime_map_id)
	):
		return {"ok": false, "reason": "formal_post_publish_verify_failed"}
	result["published"] = true
	result["approval_revision"] = int(published.get("approval_revision", 0))
	return result


func _spawn_errors(layers: Dictionary, map_id: String) -> Array[String]:
	var errors: Array[String] = []
	var ids: Dictionary = {}
	for layer: String in ["monster_spawn", "boss_spawn"]:
		var entries: Variant = layers.get(layer, [])
		if not entries is Array:
			errors.append("layer_not_array:%s" % layer)
			continue
		for raw: Variant in entries:
			if not raw is Dictionary:
				errors.append("entry_not_object:%s" % layer)
				continue
			var entry: Dictionary = raw
			var monster_id := int(entry.get("monster_id", -1))
			if monster_id <= 0 or monster_id == 159:
				errors.append("monster_id_forbidden:%s:%d" % [layer, monster_id])
			if ids.has(monster_id):
				errors.append("duplicate_monster_id:%d" % monster_id)
			ids[monster_id] = true
			if int(entry.get("count", 0)) != 1 or int(entry.get("max_alive", 0)) != 1:
				errors.append("one_of_each_contract:%d" % monster_id)
			if str(entry.get("semantic_id", "")).find(map_id) < 0:
				errors.append("semantic_id_map_binding:%d" % monster_id)
	return errors


func _spawn_signature(layers: Dictionary) -> Array:
	var result: Array = []
	for layer: String in ["monster_spawn", "boss_spawn"]:
		for raw: Variant in layers.get(layer, []):
			if raw is Dictionary:
				var entry: Dictionary = raw
				result.append([
					layer,
					int(entry.get("monster_id", -1)),
					str(entry.get("classification", "")),
					str(entry.get("semantic_id", "")),
					str(entry.get("spawn_group_id", "")),
					entry.get("tile", []),
					int(entry.get("count", 0)),
					int(entry.get("max_alive", 0)),
					str(entry.get("respawn_policy_id", "")),
				])
	return result


static func _ensure_services() -> bool:
	if _build_service == null:
		_build_service = load("res://scripts/map_editor/map_editor_build_runtime_service.gd")
	if _runtime_bridge == null:
		_runtime_bridge = load("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
	if _runtime_map_service == null:
		_runtime_map_service = load("res://scripts/map_editor/map_editor_runtime_map_service.gd")
	return _build_service != null and _runtime_bridge != null and _runtime_map_service != null


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _file_sha256(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(mini(1048576, file.get_length() - file.get_position())))
	file.close()
	return context.finish().hex_encode()


func _fail(message: String) -> void:
	push_error("MAP_MONSTER_PLACEMENT_BATCH_FAILED %s" % message)
	quit(1)
