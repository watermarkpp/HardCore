extends SceneTree

## Single-purpose formal publisher for the approved monster-placement pilot.
## Default mode is dry-run. Production publication requires an explicit
## `--publish` user argument or HARDCORE_MAP_MONSTER_PILOT_PUBLISH=1.

const JsonCodec := preload(
	"res://scripts/map_editor/map_editor_json_codec.gd"
)

## A --script launch compiles before project global classes are registered.
## Load the cross-system services after the SceneTree is initialized so the
## headless command has no false GameData compile diagnostics.
static var _build_service: Variant = null
static var _runtime_map_service: Variant = null
static var _runtime_bridge: Variant = null

const CANONICAL_MAP_ID := "fengmo_purgatory_corridor"
const LEGACY_MAP_ID := "gmhl_purgatory_corridor"
const CANONICAL_RUNTIME_MAP_ID := 914007
const LEGACY_RUNTIME_MAP_ID := 99455
const EDITOR_PATH := (
	"res://map_editor_workspace/gmhl_purgatory_corridor/"
	+ "gmhl_purgatory_corridor.editor.json"
)
const REGISTRY_PATH := (
	"res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
)
const IDENTITY_PATH := (
	"res://assets/data/map_design/map_identity_registry.json"
)
const NETWORK_PATH := (
	"res://assets/data/map_design/map_portal_network.json"
)
const EXPECTED_EDITOR_SHA256 := (
	"9c97baeabe5069c962bf5ba38e66bf1ae9a196b66ff72182851365e7aac40aad"
)
const EXPECTED_REGISTRY_SHA256 := (
	"3eefa27ba2c12d09c4817edf4ba60c57c8f18e044502e55edf4e2fc10ee40d4d"
)
const EXPECTED_IDENTITY_SHA256 := (
	"7e50073a4a20918e234587af284f009ff92b9d6d845ad46dfc997be60d9128d8"
)
const EXPECTED_NETWORK_SHA256 := (
	"2847952e26609b484fae02f0a5874244b1ba1dfdce3827d7aea3268d464114a9"
)
const EXPECTED_CANDIDATE_SHA256 := (
	"c3f88e3fc868ecf05bee29c320482c79cf767faa37b264bee1596e9466382b91"
)
const MISSING_HASH := "missing"
const EXPECTED_SPAWNS := [
	[112, "monster_spawn", "ordinary", "monster_spawn.auto.v1.fengmo_purgatory_corridor.000112", "auto:v1:fengmo_purgatory_corridor:ordinary:000112"],
	[128, "monster_spawn", "ordinary", "monster_spawn.auto.v1.fengmo_purgatory_corridor.000128", "auto:v1:fengmo_purgatory_corridor:ordinary:000128"],
	[129, "monster_spawn", "ordinary", "monster_spawn.auto.v1.fengmo_purgatory_corridor.000129", "auto:v1:fengmo_purgatory_corridor:ordinary:000129"],
	[132, "monster_spawn", "ordinary", "monster_spawn.auto.v1.fengmo_purgatory_corridor.000132", "auto:v1:fengmo_purgatory_corridor:ordinary:000132"],
	[138, "monster_spawn", "ordinary", "monster_spawn.auto.v1.fengmo_purgatory_corridor.000138", "auto:v1:fengmo_purgatory_corridor:ordinary:000138"],
	[148, "monster_spawn", "ordinary", "monster_spawn.auto.v1.fengmo_purgatory_corridor.000148", "auto:v1:fengmo_purgatory_corridor:ordinary:000148"],
	[150, "monster_spawn", "ordinary", "monster_spawn.auto.v1.fengmo_purgatory_corridor.000150", "auto:v1:fengmo_purgatory_corridor:ordinary:000150"],
	[153, "monster_spawn", "ordinary", "monster_spawn.auto.v1.fengmo_purgatory_corridor.000153", "auto:v1:fengmo_purgatory_corridor:ordinary:000153"],
	[156, "monster_spawn", "ordinary", "monster_spawn.auto.v1.fengmo_purgatory_corridor.000156", "auto:v1:fengmo_purgatory_corridor:ordinary:000156"],
	[152, "boss_spawn", "elite", "boss_spawn.auto.v1.fengmo_purgatory_corridor.000152", "auto:v1:fengmo_purgatory_corridor:elite:000152"],
	[155, "boss_spawn", "elite", "boss_spawn.auto.v1.fengmo_purgatory_corridor.000155", "auto:v1:fengmo_purgatory_corridor:elite:000155"],
]

var _publish := false
var _startup_error := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for argument: String in args:
		if argument not in ["--publish", "--dry-run"]:
			_startup_error = "unsupported_argument:%s" % argument
			break
	if args.has("--publish") and args.has("--dry-run"):
		_startup_error = "publish_and_dry_run_are_mutually_exclusive"
	var environment_value := OS.get_environment(
		"HARDCORE_MAP_MONSTER_PILOT_PUBLISH"
	).strip_edges().to_lower()
	if environment_value not in ["", "0", "false", "1", "true"]:
		_startup_error = "invalid_publish_environment_value"
	var environment_publish := environment_value in ["1", "true"]
	if environment_publish and args.has("--dry-run"):
		_startup_error = "publish_environment_conflicts_with_dry_run"
	_publish = args.has("--publish") or environment_publish
	_run.call_deferred()


func _run() -> void:
	if not _startup_error.is_empty():
		_fail(_startup_error)
		return
	if not _ensure_services():
		_fail("formal_services_unreadable")
		return
	if not _build_service.test_formal_runtime_root_override.is_empty():
		_fail("production_runtime_override_forbidden")
		return
	var result := _execute(
		_publish, REGISTRY_PATH, EXPECTED_REGISTRY_SHA256
	)
	if not bool(result.get("ok", false)):
		_fail(str(result.get("reason", "unknown_failure")), result)
		return
	var marker := (
		"MAP_MONSTER_PLACEMENT_PILOT_PUBLISH_PASS"
		if _publish
		else "MAP_MONSTER_PLACEMENT_PILOT_PUBLISH_DRY_RUN_PASS"
	)
	print("%s %s" % [marker, JsonCodec.encode(result)])
	quit(0)


## Focused-test seam: still locks the real canonical pilot/editor/authorities,
## but redirects the transactional registry and runtime artifact to user://.
static func test_execute_scratch(
	publish: bool,
	registry_path: String,
	runtime_root: String
) -> Dictionary:
	if (
		not registry_path.begins_with("user://")
		or not runtime_root.begins_with("user://")
	):
		return _failure("scratch_paths_must_use_user")
	if not _ensure_services():
		return _failure("formal_services_unreadable")
	_build_service.test_formal_runtime_root_override = runtime_root
	_runtime_bridge.test_override_release_registry_path(registry_path)
	var result := _execute(
		publish, registry_path, _file_sha256(registry_path)
	)
	_runtime_bridge.reset_release_registry_override()
	_build_service.test_formal_runtime_root_override = ""
	return result


static func _execute(
	publish: bool,
	registry_path: String,
	expected_registry_sha256: String
) -> Dictionary:
	if not _ensure_services():
		return _failure("formal_services_unreadable")
	var runtime_path: String = str(
		_build_service.default_runtime_path(CANONICAL_MAP_ID)
	)
	var preflight := {
		"editor": {"path": EDITOR_PATH, "sha256": _file_sha256(EDITOR_PATH)},
		"registry": {"path": registry_path, "sha256": _file_sha256(registry_path)},
		"runtime": {"path": runtime_path, "sha256": _file_sha256(runtime_path)},
		"identity": {"path": IDENTITY_PATH, "sha256": _file_sha256(IDENTITY_PATH)},
		"network": {"path": NETWORK_PATH, "sha256": _file_sha256(NETWORK_PATH)},
	}
	if str(preflight.editor.sha256) != EXPECTED_EDITOR_SHA256:
		return _failure("editor_source_hash_mismatch", preflight)
	if str(preflight.registry.sha256) != expected_registry_sha256:
		return _failure("release_registry_baseline_drift", preflight)
	if str(preflight.runtime.sha256) != MISSING_HASH:
		return _failure("pilot_runtime_baseline_drift", preflight)
	if str(preflight.identity.sha256) != EXPECTED_IDENTITY_SHA256:
		return _failure("identity_authority_hash_mismatch", preflight)
	if str(preflight.network.sha256) != EXPECTED_NETWORK_SHA256:
		return _failure("portal_network_authority_hash_mismatch", preflight)

	var source_bytes := _read_bytes(EDITOR_PATH)
	var document := _read_json(EDITOR_PATH)
	if document.is_empty():
		return _failure("editor_source_unreadable", preflight)
	if (
		str(document.get("map_id", "")) != LEGACY_MAP_ID
		or int(document.get("runtime_map_id", -1)) != LEGACY_RUNTIME_MAP_ID
	):
		return _failure("editor_source_identity_mismatch", preflight)
	var source_spawn_errors := _spawn_errors(document.get("layers", {}))
	if not source_spawn_errors.is_empty():
		return _failure("editor_spawn_contract_mismatch", {
			"preflight": preflight,
			"errors": source_spawn_errors,
		})
	var registry_before := _read_json(registry_path)
	if registry_before.is_empty():
		return _failure("release_registry_unreadable", preflight)
	var target_before := _target_registry_entries(registry_before)
	if not target_before.is_empty():
		return _failure("pilot_registry_entry_already_exists", preflight)

	var candidate: Dictionary = _build_service.build_formal_candidate(document)
	if not bool(candidate.get("ok", false)):
		return _failure("formal_candidate_build_failed", {
			"preflight": preflight,
			"errors": candidate.get("errors", []),
		})
	if (
		str(candidate.get("map_key", "")) != CANONICAL_MAP_ID
		or int(candidate.get("formal_identity", {}).get("runtime_map_id", -1))
			!= CANONICAL_RUNTIME_MAP_ID
	):
		return _failure("formal_candidate_identity_mismatch", preflight)
	var candidate_hash := str(candidate.get("build_sha256", ""))
	if candidate_hash != EXPECTED_CANDIDATE_SHA256:
		return _failure("formal_candidate_hash_mismatch", {
			"preflight": preflight,
			"actual_candidate_sha256": candidate_hash,
			"expected_candidate_sha256": EXPECTED_CANDIDATE_SHA256,
		})
	var runtime: Dictionary = candidate.get("runtime", {})
	var runtime_spawn_errors := _spawn_errors(runtime.get("semantics", {}))
	if not runtime_spawn_errors.is_empty():
		return _failure("runtime_spawn_contract_mismatch", {
			"preflight": preflight,
			"errors": runtime_spawn_errors,
		})
	var protected_after_build := _protected_hashes(registry_path, runtime_path)
	if _read_bytes(EDITOR_PATH) != source_bytes:
		return _failure("editor_source_changed_during_build", protected_after_build)
	if (
		str(protected_after_build.registry_sha256)
			!= str(preflight.registry.sha256)
		or str(protected_after_build.runtime_sha256)
			!= str(preflight.runtime.sha256)
	):
		return _failure("formal_state_changed_during_candidate_build", {
			"preflight": preflight,
			"post_build": protected_after_build,
		})
	var evidence := {
		"preflight": preflight,
		"candidate_path": candidate.get("candidate_path", ""),
		"candidate_sha256": candidate_hash,
		"ordinary_count": 9,
		"boss_count": 2,
		"runtime_map_id": CANONICAL_RUNTIME_MAP_ID,
	}
	if not publish:
		evidence["ok"] = true
		evidence["mode"] = "dry_run"
		evidence["postcondition"] = protected_after_build
		return evidence

	var published: Dictionary = _build_service.publish_runtime_release(
		str(candidate.get("candidate_path", "")),
		CANONICAL_RUNTIME_MAP_ID,
		candidate.get("document_binding", {}),
		registry_path,
		CANONICAL_MAP_ID
	)
	if not bool(published.get("success", false)):
		return _failure("formal_publish_failed", {
			"preflight": preflight,
			"publish_result": published,
		})
	if _read_bytes(EDITOR_PATH) != source_bytes:
		return _failure("editor_source_changed_during_publish", preflight)
	var authority_after := _protected_hashes(registry_path, runtime_path)
	if (
		str(authority_after.editor_sha256) != EXPECTED_EDITOR_SHA256
		or str(authority_after.identity_sha256) != EXPECTED_IDENTITY_SHA256
		or str(authority_after.network_sha256) != EXPECTED_NETWORK_SHA256
	):
		return _failure("protected_authority_changed_during_publish", {
			"preflight": preflight,
			"post_publish": authority_after,
		})
	var registry_after := _read_json(registry_path)
	var registry_delta := _verify_registry_delta(
		registry_before, registry_after, candidate_hash, runtime_path
	)
	if not bool(registry_delta.get("ok", false)):
		return _failure("release_registry_delta_invalid", registry_delta)
	var loaded: Dictionary = _runtime_map_service.load_runtime(runtime_path)
	if not bool(loaded.get("ok", false)):
		return _failure("published_runtime_invalid", loaded)
	if str(loaded.runtime.get("build_sha256", "")) != candidate_hash:
		return _failure("published_runtime_hash_mismatch", loaded)
	_runtime_bridge.invalidate_release_registry()
	if not _runtime_bridge.is_formal_playable(CANONICAL_RUNTIME_MAP_ID):
		return _failure("published_runtime_not_formal_playable")
	if (
		str(_runtime_bridge.load_map(CANONICAL_RUNTIME_MAP_ID).get(
			"build_sha256", ""
		)) != candidate_hash
	):
		return _failure("formal_runtime_consumer_hash_mismatch")
	evidence["ok"] = true
	evidence["mode"] = "publish"
	evidence["publish_result"] = published
	evidence["registry_delta"] = registry_delta
	evidence["postcondition"] = authority_after
	return evidence


static func _spawn_errors(layers: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var actual := {}
	var semantic_ids := {}
	var group_ids := {}
	for layer_name: String in ["monster_spawn", "boss_spawn"]:
		var entries: Variant = layers.get(layer_name, [])
		if not entries is Array:
			errors.append("spawn_layer_not_array:%s" % layer_name)
			continue
		for raw: Variant in entries:
			if not raw is Dictionary:
				errors.append("spawn_entry_not_object:%s" % layer_name)
				continue
			var entry: Dictionary = raw
			var semantic_id := str(entry.get("semantic_id", ""))
			var group_id := str(entry.get("spawn_group_id", ""))
			if semantic_id.is_empty() or semantic_ids.has(semantic_id):
				errors.append("spawn_semantic_id_invalid:%s" % semantic_id)
			if group_id.is_empty() or group_ids.has(group_id):
				errors.append("spawn_group_id_invalid:%s" % group_id)
			semantic_ids[semantic_id] = true
			group_ids[group_id] = true
			actual[semantic_id] = [
				int(entry.get("monster_id", -1)),
				str(entry.get("kind", "")),
				str(entry.get("classification", "")),
				group_id,
			]
	if (layers.get("monster_spawn", []) as Array).size() != 9:
		errors.append("ordinary_count_mismatch")
	if (layers.get("boss_spawn", []) as Array).size() != 2:
		errors.append("boss_count_mismatch")
	for expected: Array in EXPECTED_SPAWNS:
		var semantic_id := str(expected[3])
		var expected_value := [
			int(expected[0]), str(expected[1]), str(expected[2]), str(expected[4]),
		]
		if not actual.has(semantic_id) or actual[semantic_id] != expected_value:
			errors.append("stable_spawn_mismatch:%s" % semantic_id)
	if actual.size() != EXPECTED_SPAWNS.size():
		errors.append("unexpected_spawn_identity_count:%d" % actual.size())
	return errors


static func _verify_registry_delta(
	before: Dictionary,
	after: Dictionary,
	candidate_hash: String,
	runtime_path: String
) -> Dictionary:
	var before_maps: Array = before.get("maps", [])
	var after_maps: Array = after.get("maps", [])
	if after_maps.size() != before_maps.size() + 1:
		return _failure("registry_map_count_delta_invalid")
	var target_entries := _target_registry_entries(after)
	if target_entries.size() != 1:
		return _failure("registry_target_entry_not_unique")
	var target: Dictionary = target_entries[0]
	if (
		str(target.get("map_key", "")) != CANONICAL_MAP_ID
		or int(target.get("runtime_map_id", -1)) != CANONICAL_RUNTIME_MAP_ID
		or str(target.get("approved_build_sha256", "")) != candidate_hash
		or str(target.get("runtime_path", "")) != runtime_path
		or str(target.get("release_state", "")) != "implemented_playable"
	):
		return _failure("registry_target_entry_invalid", target)
	if (
		JsonCodec.encode(_registry_without_target(before))
		!= JsonCodec.encode(_registry_without_target(after))
	):
		return _failure("registry_non_target_entries_changed")
	return {
		"ok": true,
		"before_count": before_maps.size(),
		"after_count": after_maps.size(),
		"target_entry": target,
	}


static func _target_registry_entries(registry: Dictionary) -> Array:
	var matches: Array = []
	for raw: Variant in registry.get("maps", []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if (
			str(entry.get("map_key", "")) == CANONICAL_MAP_ID
			or int(entry.get("runtime_map_id", -1)) == CANONICAL_RUNTIME_MAP_ID
		):
			matches.append(entry)
	return matches


static func _registry_without_target(registry: Dictionary) -> Dictionary:
	var result := registry.duplicate(true)
	var maps: Array = []
	for raw: Variant in result.get("maps", []):
		if not raw is Dictionary:
			maps.append(raw)
			continue
		if (
			str(raw.get("map_key", "")) == CANONICAL_MAP_ID
			or int(raw.get("runtime_map_id", -1)) == CANONICAL_RUNTIME_MAP_ID
		):
			continue
		maps.append(raw)
	result["maps"] = maps
	return result


static func _protected_hashes(
	registry_path: String,
	runtime_path: String
) -> Dictionary:
	return {
		"editor_sha256": _file_sha256(EDITOR_PATH),
		"registry_sha256": _file_sha256(registry_path),
		"runtime_sha256": _file_sha256(runtime_path),
		"identity_sha256": _file_sha256(IDENTITY_PATH),
		"network_sha256": _file_sha256(NETWORK_PATH),
	}


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_bytes(path).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


static func _read_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


static func _file_sha256(path: String) -> String:
	if not FileAccess.file_exists(path):
		return MISSING_HASH
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(_read_bytes(path))
	return context.finish().hex_encode()


static func _ensure_services() -> bool:
	if _build_service == null:
		_build_service = load(
			"res://scripts/map_editor/map_editor_build_runtime_service.gd"
		)
	if _runtime_map_service == null:
		_runtime_map_service = load(
			"res://scripts/map_editor/map_editor_runtime_map_service.gd"
		)
	if _runtime_bridge == null:
		_runtime_bridge = load(
			"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
		)
	return (
		_build_service != null
		and _runtime_map_service != null
		and _runtime_bridge != null
	)


static func _failure(reason: String, evidence: Variant = {}) -> Dictionary:
	return {"ok": false, "reason": reason, "evidence": evidence}


func _fail(message: String, evidence: Variant = {}) -> void:
	push_error(
		"MAP_MONSTER_PLACEMENT_PILOT_PUBLISH_FAILED %s %s"
		% [message, JsonCodec.encode(evidence)]
	)
	quit(1)
