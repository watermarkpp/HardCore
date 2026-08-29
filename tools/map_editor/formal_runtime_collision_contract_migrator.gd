class_name FormalRuntimeCollisionContractMigrator
extends RefCounted

## Exact, fail-closed migration for an already-published formal runtime.
##
## This deliberately does not rebuild a candidate or read editor/visual data.
## It changes only collision.coordinate_contract_id and the resulting
## build_sha256, then advances the matching release approval revision.

const JsonCodec := preload(
	"res://scripts/map_editor/map_editor_json_codec.gd"
)
const RuntimeCollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

const REGISTRY_PATH := (
	"res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
)
const RUNTIME_ROOT := "res://assets/data/runtime/map_editor/"
const EXPECTED_FORMAL_MAP_COUNT := 67
const REGISTRY_CONTRACT_ID := "mse.map.runtime.release.v1"
const LEGACY_COLLISION_CONTRACT_ID := (
	"map_editor_runtime_collision_geometry_v2"
)
const TEMP_SUFFIX := ".formal_collision_contract_migration.tmp"
const BACKUP_SUFFIX := ".formal_collision_contract_migration.bak"

## Test-only transaction seam. A negative value is disabled. A non-negative
## value fails after that many successful promotions and exercises rollback.
var test_fail_after_promotions := -1


static func parse_cli_args(args: PackedStringArray) -> Dictionary:
	if args.is_empty():
		return {"ok": false, "error": "explicit_selection_required"}
	var all_formal := false
	var map_key := ""
	for argument: String in args:
		if argument == "--all-formal":
			if all_formal:
				return {"ok": false, "error": "duplicate_all_formal"}
			all_formal = true
		elif argument.begins_with("--map="):
			if not map_key.is_empty():
				return {"ok": false, "error": "duplicate_map"}
			map_key = argument.trim_prefix("--map=")
			if not _safe_map_key(map_key):
				return {"ok": false, "error": "unsafe_map_key"}
		else:
			return {"ok": false, "error": "unknown_argument:%s" % argument}
	if all_formal == (not map_key.is_empty()):
		return {"ok": false, "error": "exactly_one_selection_required"}
	return {
		"ok": true,
		"selection": (
			{"all_formal": true}
			if all_formal
			else {"map_key": map_key}
		),
	}


func migrate(selection: Dictionary, options := {}) -> Dictionary:
	var configuration := _configuration(options)
	if not bool(configuration.get("ok", false)):
		return configuration
	var selection_error := _validate_selection(selection)
	if not selection_error.is_empty():
		return _failure(selection_error)
	var registry_path := str(configuration.registry_path)
	var runtime_root := str(configuration.runtime_root)
	var expected_count := int(configuration.expected_formal_count)
	var registry_read := _read_dictionary(registry_path)
	if not bool(registry_read.get("ok", false)):
		return registry_read
	var registry: Dictionary = registry_read.value
	var registry_text := str(registry_read.text)
	var preflight := _preflight_registry(
		registry, runtime_root, expected_count
	)
	if not bool(preflight.get("ok", false)):
		return preflight
	var targets := _selected_targets(
		preflight.targets, selection
	)
	if targets.is_empty():
		return _failure("selected_map_not_formal")
	var all_formal := bool(selection.get("all_formal", false))
	for target: Dictionary in targets:
		if str(target.collision_contract_id) != LEGACY_COLLISION_CONTRACT_ID:
			return _failure(
				"target_contract_not_legacy:%s:%s"
				% [str(target.map_key), str(target.collision_contract_id)]
			)
	if all_formal and targets.size() != expected_count:
		return _failure("all_formal_target_count_mismatch")

	var next_registry := registry.duplicate(true)
	var writes: Array[Dictionary] = []
	var changes: Array[Dictionary] = []
	for target: Dictionary in targets:
		var before_runtime: Dictionary = target.runtime
		var next_runtime := before_runtime.duplicate(true)
		var collision: Dictionary = next_runtime.get("collision", {})
		collision["coordinate_contract_id"] = (
			RuntimeCollisionGeometry.CONTRACT_ID
		)
		next_runtime["collision"] = collision
		var runtime_text_result := _migrated_runtime_text(
			str(target.runtime_text),
			str(target.old_build_sha256)
		)
		if not bool(runtime_text_result.get("ok", false)):
			return _failure(
				"runtime_text_migration_failed:%s:%s"
				% [
					str(target.map_key),
					str(runtime_text_result.get("error", "unknown")),
				]
			)
		var next_hash := str(runtime_text_result.new_build_sha256)
		next_runtime["build_sha256"] = next_hash
		var next_runtime_parsed: Variant = JSON.parse_string(
			str(runtime_text_result.text)
		)
		if not next_runtime_parsed is Dictionary or next_runtime_parsed != next_runtime:
			return _failure("runtime_text_payload_mismatch:%s" % str(target.map_key))
		var delta_error := _runtime_delta_error(
			before_runtime, next_runtime
		)
		if not delta_error.is_empty():
			return _failure(
				"runtime_delta_invalid:%s:%s"
				% [str(target.map_key), delta_error]
			)
		var registry_index := int(target.registry_index)
		var old_entry: Dictionary = registry.maps[registry_index]
		var next_entry: Dictionary = next_registry.maps[registry_index]
		next_entry["approved_build_sha256"] = next_hash
		next_entry["approval_revision"] = (
			int(old_entry.get("approval_revision", 0)) + 1
		)
		next_registry.maps[registry_index] = next_entry
		writes.append({
			"path": str(target.runtime_path),
			"text": str(runtime_text_result.text),
		})
		changes.append({
			"registry_index": registry_index,
			"map_key": str(target.map_key),
			"runtime_map_id": int(target.runtime_map_id),
			"old_build_sha256": str(target.old_build_sha256),
			"new_build_sha256": next_hash,
			"old_approval_revision": int(
				old_entry.get("approval_revision", 0)
			),
			"new_approval_revision": int(
				next_entry.get("approval_revision", 0)
			),
		})
	var registry_delta_error := _registry_delta_error(
		registry, next_registry, targets
	)
	if not registry_delta_error.is_empty():
		return _failure("registry_delta_invalid:%s" % registry_delta_error)
	var registry_text_result := _migrated_registry_text(
		registry_text, registry, changes
	)
	if not bool(registry_text_result.get("ok", false)):
		return _failure(
			"registry_text_migration_failed:%s"
			% str(registry_text_result.get("error", "unknown"))
		)
	writes.append({
		"path": registry_path,
		"text": str(registry_text_result.text),
	})
	var commit := _commit_transaction(writes)
	if not bool(commit.get("ok", false)):
		return commit
	var verify := _verify_committed(
		registry_path, next_registry, targets, changes
	)
	if not bool(verify.get("ok", false)):
		var rollback := _rollback_committed(commit.get("committed", []))
		return _failure(
			"post_commit_verify_failed:%s:rollback=%s"
			% [str(verify.get("error", "unknown")), str(rollback)]
		)
	_cleanup_backups(commit.get("committed", []))
	return {
		"ok": true,
		"changed_count": changes.size(),
		"registry_path": registry_path,
		"target_contract_id": RuntimeCollisionGeometry.CONTRACT_ID,
		"changes": changes,
	}


static func runtime_build_sha256(runtime: Dictionary) -> String:
	var checksum_source := runtime.duplicate(true)
	checksum_source["build_sha256"] = ""
	return _sha256(JsonCodec.encode(checksum_source))


func _configuration(options: Dictionary) -> Dictionary:
	var registry_path := str(options.get("registry_path", REGISTRY_PATH))
	var runtime_root := str(options.get("runtime_root", RUNTIME_ROOT))
	var expected_count := int(options.get(
		"expected_formal_count", EXPECTED_FORMAL_MAP_COUNT
	))
	if not _safe_virtual_file(registry_path):
		return _failure("unsafe_registry_path")
	if not _safe_virtual_root(runtime_root):
		return _failure("unsafe_runtime_root")
	if expected_count <= 0:
		return _failure("invalid_expected_formal_count")
	return {
		"ok": true,
		"registry_path": registry_path,
		"runtime_root": runtime_root,
		"expected_formal_count": expected_count,
	}


func _validate_selection(selection: Dictionary) -> String:
	var all_formal := bool(selection.get("all_formal", false))
	var map_key := str(selection.get("map_key", ""))
	if all_formal == (not map_key.is_empty()):
		return "exactly_one_selection_required"
	if not map_key.is_empty() and not _safe_map_key(map_key):
		return "unsafe_map_key"
	return ""


func _preflight_registry(
	registry: Dictionary,
	runtime_root: String,
	expected_count: int
) -> Dictionary:
	if int(registry.get("schema_version", 0)) != 1:
		return _failure("registry_schema_invalid")
	if str(registry.get("registry_contract_id", "")) != REGISTRY_CONTRACT_ID:
		return _failure("registry_contract_invalid")
	var raw_maps: Variant = registry.get("maps", null)
	if not raw_maps is Array:
		return _failure("registry_maps_invalid")
	var maps: Array = raw_maps
	if maps.size() != expected_count:
		return _failure(
			"formal_map_count:%d/%d" % [maps.size(), expected_count]
		)
	var seen_keys := {}
	var seen_ids := {}
	var seen_paths := {}
	var targets: Array[Dictionary] = []
	for index in maps.size():
		var raw_entry: Variant = maps[index]
		if not raw_entry is Dictionary:
			return _failure("registry_entry_invalid:%d" % index)
		var entry: Dictionary = raw_entry
		var map_key := str(entry.get("map_key", ""))
		var runtime_map_id_value: Variant = entry.get("runtime_map_id", null)
		var runtime_map_id := int(runtime_map_id_value)
		var runtime_path := str(entry.get("runtime_path", ""))
		if not _safe_map_key(map_key):
			return _failure("registry_map_key_invalid:%d" % index)
		if not _is_positive_json_integer(runtime_map_id_value):
			return _failure("registry_runtime_map_id_invalid:%s" % map_key)
		if seen_keys.has(map_key):
			return _failure("registry_map_key_duplicate:%s" % map_key)
		if seen_ids.has(runtime_map_id):
			return _failure("registry_runtime_map_id_duplicate:%d" % runtime_map_id)
		if seen_paths.has(runtime_path):
			return _failure("registry_runtime_path_duplicate:%s" % runtime_path)
		seen_keys[map_key] = true
		seen_ids[runtime_map_id] = true
		seen_paths[runtime_path] = true
		var expected_path := runtime_root.path_join(
			map_key + ".runtime.json"
		)
		if runtime_path != expected_path:
			return _failure("registry_runtime_path_mismatch:%s" % map_key)
		var approved_hash := str(entry.get("approved_build_sha256", ""))
		if not _is_lower_sha256(approved_hash):
			return _failure("registry_approved_hash_invalid:%s" % map_key)
		if not _is_positive_json_integer(
			entry.get("approval_revision", null)
		):
			return _failure("registry_approval_revision_invalid:%s" % map_key)
		var release_state := str(entry.get("release_state", ""))
		if release_state not in [
			"implemented_playable", "implemented_staging"
		]:
			return _failure("registry_release_state_invalid:%s" % map_key)
		var runtime_read := _read_dictionary(runtime_path, true)
		if not bool(runtime_read.get("ok", false)):
			return _failure(
				"runtime_read_failed:%s:%s"
				% [map_key, str(runtime_read.get("error", "unknown"))]
			)
		var runtime: Dictionary = runtime_read.value
		var source: Variant = runtime.get("source", null)
		if not source is Dictionary:
			return _failure("runtime_source_invalid:%s" % map_key)
		if str(source.get("map_id", "")) != map_key:
			return _failure("runtime_map_key_mismatch:%s" % map_key)
		var source_runtime_id: Variant = source.get("runtime_map_id", null)
		if (
			not _is_positive_json_integer(source_runtime_id)
			or int(source_runtime_id) != runtime_map_id
		):
			return _failure("runtime_map_id_mismatch:%s" % map_key)
		var collision: Variant = runtime.get("collision", null)
		if not collision is Dictionary:
			return _failure("runtime_collision_invalid:%s" % map_key)
		var collision_contract := str(
			collision.get("coordinate_contract_id", "")
		)
		if collision_contract not in [
			LEGACY_COLLISION_CONTRACT_ID,
			RuntimeCollisionGeometry.CONTRACT_ID,
		]:
			return _failure(
				"runtime_collision_contract_invalid:%s:%s"
				% [map_key, collision_contract]
			)
		var claimed_hash := str(runtime.get("build_sha256", ""))
		if not _is_lower_sha256(claimed_hash):
			return _failure("runtime_build_hash_invalid:%s" % map_key)
		var computed_hash := runtime_build_sha256(runtime)
		if computed_hash != claimed_hash:
			return _failure("runtime_build_hash_mismatch:%s" % map_key)
		var source_hash := _runtime_text_build_sha256(
			str(runtime_read.canonical_text), claimed_hash
		)
		if not bool(source_hash.get("ok", false)):
			return _failure(
				"runtime_build_text_invalid:%s:%s"
				% [map_key, str(source_hash.get("error", "unknown"))]
			)
		if str(source_hash.sha256) != claimed_hash:
			return _failure("runtime_build_text_hash_mismatch:%s" % map_key)
		if approved_hash != claimed_hash:
			return _failure("registry_runtime_hash_mismatch:%s" % map_key)
		targets.append({
			"registry_index": index,
			"map_key": map_key,
			"runtime_map_id": runtime_map_id,
			"runtime_path": runtime_path,
			"runtime": runtime,
			"runtime_text": str(runtime_read.canonical_text),
			"old_build_sha256": claimed_hash,
			"collision_contract_id": collision_contract,
		})
	return {"ok": true, "targets": targets}


func _selected_targets(
	formal_targets: Array, selection: Dictionary
) -> Array[Dictionary]:
	if bool(selection.get("all_formal", false)):
		return formal_targets.duplicate()
	var requested := str(selection.get("map_key", ""))
	for target: Dictionary in formal_targets:
		if str(target.map_key) == requested:
			return [target]
	return []


func _runtime_delta_error(before: Dictionary, after: Dictionary) -> String:
	if str(after.get("build_sha256", "")) == str(
		before.get("build_sha256", "")
	):
		return "build_hash_unchanged"
	var restored := after.duplicate(true)
	restored["build_sha256"] = before.get("build_sha256", "")
	var collision: Dictionary = restored.get("collision", {})
	collision["coordinate_contract_id"] = before.get(
		"collision", {}
	).get("coordinate_contract_id", "")
	restored["collision"] = collision
	return "" if restored == before else "payload_changed_outside_allowlist"


func _registry_delta_error(
	before: Dictionary,
	after: Dictionary,
	targets: Array
) -> String:
	var restored := after.duplicate(true)
	for target: Dictionary in targets:
		var index := int(target.registry_index)
		var restored_entry: Dictionary = restored.maps[index]
		var before_entry: Dictionary = before.maps[index]
		restored_entry["approved_build_sha256"] = before_entry.get(
			"approved_build_sha256", ""
		)
		restored_entry["approval_revision"] = before_entry.get(
			"approval_revision", 0
		)
		restored.maps[index] = restored_entry
	return "" if restored == before else "registry_changed_outside_allowlist"


func _runtime_text_build_sha256(
	runtime_text: String,
	claimed_hash: String
) -> Dictionary:
	var blanked := _replace_json_string_field_once(
		runtime_text, "build_sha256", claimed_hash, ""
	)
	if not bool(blanked.get("ok", false)):
		return blanked
	return {
		"ok": true,
		"sha256": _sha256(str(blanked.text)),
	}


func _migrated_runtime_text(
	runtime_text: String,
	old_build_hash: String
) -> Dictionary:
	var contract_replaced := _replace_json_string_field_once(
		runtime_text,
		"coordinate_contract_id",
		LEGACY_COLLISION_CONTRACT_ID,
		RuntimeCollisionGeometry.CONTRACT_ID
	)
	if not bool(contract_replaced.get("ok", false)):
		return contract_replaced
	var blanked := _replace_json_string_field_once(
		str(contract_replaced.text),
		"build_sha256",
		old_build_hash,
		""
	)
	if not bool(blanked.get("ok", false)):
		return blanked
	var new_hash := _sha256(str(blanked.text))
	var finalized := _replace_json_string_field_once(
		str(contract_replaced.text),
		"build_sha256",
		old_build_hash,
		new_hash
	)
	if not bool(finalized.get("ok", false)):
		return finalized
	return {
		"ok": true,
		"text": str(finalized.text),
		"new_build_sha256": new_hash,
	}


func _migrated_registry_text(
	registry_text: String,
	before_registry: Dictionary,
	changes: Array
) -> Dictionary:
	var updated_text := registry_text
	for raw_change: Variant in changes:
		var change: Dictionary = raw_change
		var map_key := str(change.map_key)
		var map_key_token := (
			JSON.stringify("map_key") + ": " + JSON.stringify(map_key)
		)
		if updated_text.count(map_key_token) != 1:
			return _failure("registry_map_key_token_count:%s" % map_key)
		var token_index := updated_text.find(map_key_token)
		var span := _json_object_span_containing(updated_text, token_index)
		if not bool(span.get("ok", false)):
			return _failure("registry_entry_span_invalid:%s" % map_key)
		var start := int(span.start)
		var end := int(span.end)
		var entry_text := updated_text.substr(start, end - start)
		var hash_replaced := _replace_json_string_field_once(
			entry_text,
			"approved_build_sha256",
			str(change.old_build_sha256),
			str(change.new_build_sha256)
		)
		if not bool(hash_replaced.get("ok", false)):
			return _failure(
				"registry_hash_field_invalid:%s:%s"
				% [map_key, str(hash_replaced.get("error", "unknown"))]
			)
		var revision_replaced := _replace_json_integer_field_preserving_style(
			str(hash_replaced.text),
			"approval_revision",
			int(change.old_approval_revision),
			int(change.new_approval_revision)
		)
		if not bool(revision_replaced.get("ok", false)):
			return _failure(
				"registry_revision_field_invalid:%s:%s"
				% [map_key, str(revision_replaced.get("error", "unknown"))]
			)
		updated_text = (
			updated_text.left(start)
			+ str(revision_replaced.text)
			+ updated_text.substr(end)
		)
	var reparsed: Variant = JSON.parse_string(updated_text)
	if not reparsed is Dictionary:
		return _failure("registry_text_json_invalid")
	var payload_delta_error := _registry_delta_error(
		before_registry, reparsed, changes
	)
	if not payload_delta_error.is_empty():
		return _failure("registry_text_payload_mismatch:%s" % payload_delta_error)
	for raw_change: Variant in changes:
		var change: Dictionary = raw_change
		var entry: Dictionary = reparsed.maps[int(change.registry_index)]
		if str(entry.get("approved_build_sha256", "")) != str(
			change.new_build_sha256
		):
			return _failure("registry_text_hash_mismatch:%s" % str(change.map_key))
		if int(entry.get("approval_revision", 0)) != int(
			change.new_approval_revision
		):
			return _failure("registry_text_revision_mismatch:%s" % str(change.map_key))
	return {"ok": true, "text": updated_text}


static func _replace_json_string_field_once(
	text: String,
	field: String,
	old_value: String,
	new_value: String
) -> Dictionary:
	var before := (
		JSON.stringify(field) + ": " + JSON.stringify(old_value)
	)
	if text.count(before) != 1:
		return _failure("json_string_field_token_count:%s" % field)
	var after := (
		JSON.stringify(field) + ": " + JSON.stringify(new_value)
	)
	return {"ok": true, "text": text.replace(before, after)}


static func _replace_json_integer_field_preserving_style(
	text: String,
	field: String,
	old_value: int,
	new_value: int
) -> Dictionary:
	var prefix := JSON.stringify(field) + ": "
	var integer_token := prefix + str(old_value) + ","
	var float_token := prefix + str(old_value) + ".0,"
	var integer_count := text.count(integer_token)
	var float_count := text.count(float_token)
	if integer_count + float_count != 1:
		return _failure("json_integer_field_token_count:%s" % field)
	var old_token := float_token if float_count == 1 else integer_token
	var new_token := (
		prefix + str(new_value) + ".0,"
		if float_count == 1
		else prefix + str(new_value) + ","
	)
	return {"ok": true, "text": text.replace(old_token, new_token)}


static func _json_object_span_containing(
	text: String,
	needle_index: int
) -> Dictionary:
	var stack: Array[int] = []
	var in_string := false
	var escaped := false
	for index in text.length():
		var code := text.unicode_at(index)
		if in_string:
			if escaped:
				escaped = false
			elif code == 92:
				escaped = true
			elif code == 34:
				in_string = false
			continue
		if code == 34:
			in_string = true
		elif code == 123:
			stack.append(index)
		elif code == 125:
			if stack.is_empty():
				return _failure("json_object_stack_underflow")
			var start: int = stack.pop_back()
			if start <= needle_index and needle_index < index:
				return {"ok": true, "start": start, "end": index + 1}
	return _failure("json_object_span_not_found")


func _commit_transaction(writes: Array[Dictionary]) -> Dictionary:
	var prepared: Array[Dictionary] = []
	for write: Dictionary in writes:
		var path := str(write.path)
		var absolute := ProjectSettings.globalize_path(path)
		var temporary := absolute + TEMP_SUFFIX
		var backup := absolute + BACKUP_SUFFIX
		if FileAccess.file_exists(temporary) or FileAccess.file_exists(backup):
			_cleanup_prepared(prepared)
			return _failure("stale_transaction_artifact:%s" % path)
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file == null:
			_cleanup_prepared(prepared)
			return _failure("temporary_open_failed:%s" % path)
		file.store_string(str(write.text))
		file.flush()
		file.close()
		if _read_text_absolute(temporary) != str(write.text):
			DirAccess.remove_absolute(temporary)
			_cleanup_prepared(prepared)
			return _failure("temporary_verify_failed:%s" % path)
		prepared.append({
			"path": path,
			"absolute": absolute,
			"temporary": temporary,
			"backup": backup,
			"expected_text": str(write.text),
		})
	var committed: Array[Dictionary] = []
	for prepared_write: Dictionary in prepared:
		if (
			test_fail_after_promotions >= 0
			and committed.size() >= test_fail_after_promotions
		):
			_cleanup_uncommitted(prepared, committed.size())
			var rollback := _rollback_committed(committed)
			return _failure(
				"forced_commit_failure:rollback=%s" % str(rollback)
			)
		var absolute := str(prepared_write.absolute)
		var temporary := str(prepared_write.temporary)
		var backup := str(prepared_write.backup)
		if DirAccess.rename_absolute(absolute, backup) != OK:
			_cleanup_uncommitted(prepared, committed.size())
			var rollback := _rollback_committed(committed)
			return _failure(
				"backup_promote_failed:%s:rollback=%s"
				% [str(prepared_write.path), str(rollback)]
			)
		if DirAccess.rename_absolute(temporary, absolute) != OK:
			var current_restored := (
				DirAccess.rename_absolute(backup, absolute) == OK
			)
			if FileAccess.file_exists(temporary):
				DirAccess.remove_absolute(temporary)
			_cleanup_uncommitted(prepared, committed.size() + 1)
			var rollback := _rollback_committed(committed)
			return _failure(
				"runtime_promote_failed:%s:rollback=%s"
				% [
					str(prepared_write.path),
					str(current_restored and rollback),
				]
			)
		committed.append(prepared_write)
	for committed_write: Dictionary in committed:
		if _read_text_absolute(str(committed_write.absolute)) != str(
			committed_write.expected_text
		):
			var rollback := _rollback_committed(committed)
			return _failure(
				"commit_verify_failed:%s:rollback=%s"
				% [str(committed_write.path), str(rollback)]
			)
	return {"ok": true, "committed": committed}


func _verify_committed(
	registry_path: String,
	expected_registry: Dictionary,
	targets: Array,
	changes: Array
) -> Dictionary:
	var registry_read := _read_dictionary(registry_path)
	if not bool(registry_read.get("ok", false)):
		return _failure("registry_reload_failed")
	var normalized_expected: Variant = JSON.parse_string(
		JsonCodec.encode(expected_registry)
	)
	if not normalized_expected is Dictionary:
		return _failure("registry_expected_normalization_failed")
	if registry_read.value != normalized_expected:
		return _failure("registry_reload_mismatch")
	for index in targets.size():
		var target: Dictionary = targets[index]
		var runtime_read := _read_dictionary(
			str(target.runtime_path), true
		)
		if not bool(runtime_read.get("ok", false)):
			return _failure("runtime_reload_failed:%s" % str(target.map_key))
		var runtime: Dictionary = runtime_read.value
		if str(runtime.get("build_sha256", "")) != str(
			changes[index].new_build_sha256
		):
			return _failure("runtime_reload_hash_mismatch:%s" % str(target.map_key))
		if str(runtime.get("collision", {}).get(
			"coordinate_contract_id", ""
		)) != RuntimeCollisionGeometry.CONTRACT_ID:
			return _failure("runtime_reload_contract_mismatch:%s" % str(target.map_key))
	return {"ok": true}


func _rollback_committed(committed: Array) -> bool:
	var ok := true
	var reversed := committed.duplicate()
	reversed.reverse()
	for raw: Variant in reversed:
		var committed_write: Dictionary = raw
		var absolute := str(committed_write.absolute)
		var backup := str(committed_write.backup)
		if FileAccess.file_exists(absolute):
			if DirAccess.remove_absolute(absolute) != OK:
				ok = false
		if FileAccess.file_exists(backup):
			if DirAccess.rename_absolute(backup, absolute) != OK:
				ok = false
	return ok


func _cleanup_backups(committed: Array) -> void:
	for raw: Variant in committed:
		var backup := str((raw as Dictionary).backup)
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)


func _cleanup_prepared(prepared: Array) -> void:
	for raw: Variant in prepared:
		var temporary := str((raw as Dictionary).temporary)
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(temporary)


func _cleanup_uncommitted(prepared: Array, start_index: int) -> void:
	for index in range(start_index, prepared.size()):
		var temporary := str((prepared[index] as Dictionary).temporary)
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(temporary)


func _read_dictionary(path: String, require_canonical := false) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("file_missing:%s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("file_open_failed:%s" % path)
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _failure("json_invalid:%s" % path)
	var canonical_text := JsonCodec.encode(parsed)
	if require_canonical:
		# Git may materialize tracked JSON as CRLF on Windows. Permit only that
		# transport-level difference; every other byte-level canonical mismatch
		# remains fail-closed. Hashing and migrated output always use canonical LF.
		var normalized_newlines := text.replace("\r\n", "\n")
		if normalized_newlines.contains("\r"):
			return _failure("json_newline_style_invalid:%s" % path)
		if canonical_text != normalized_newlines:
			return _failure("json_not_canonical:%s" % path)
	return {
		"ok": true,
		"value": parsed,
		"text": text,
		"canonical_text": canonical_text,
	}


func _read_text_absolute(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


static func _safe_map_key(value: String) -> bool:
	if value.is_empty() or value.length() > 96:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var letter := code >= 97 and code <= 122
		var digit := code >= 48 and code <= 57
		if not (letter or digit or code == 95):
			return false
	return true


static func _safe_virtual_file(path: String) -> bool:
	return (
		(path.begins_with("res://") or path.begins_with("user://"))
		and not path.contains("..")
		and path.ends_with(".json")
	)


static func _safe_virtual_root(path: String) -> bool:
	return (
		(path.begins_with("res://") or path.begins_with("user://"))
		and not path.contains("..")
		and path.ends_with("/")
	)


static func _is_lower_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not (
			(code >= 48 and code <= 57)
			or (code >= 97 and code <= 102)
		):
			return false
	return true


static func _is_positive_json_integer(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var numeric := float(value)
	return numeric > 0.0 and numeric == floor(numeric)


static func _sha256(text: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(text.to_utf8_buffer())
	return hashing.finish().hex_encode()


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
