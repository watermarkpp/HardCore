extends SceneTree

## One-shot, reversible migration for the formal map release set.
##
## The canonical monster catalog is the only identity authority.  Active map
## documents keep only a positive integer `monster_id`; prefixed legacy
## `monster_id`, `boss_id`, and `content_id` values are never published.  A
## canonical record that is unresolved, not editor/runtime allowed, or placed
## in the wrong semantic layer is moved to the versioned quarantine report
## instead of being guessed or silently remapped.

const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const CANONICAL_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
const QUARANTINE_PATH := "res://assets/data/runtime/map_editor/map_spawn_identity_quarantine_v1.json"
const LAYERS := ["monster_spawn", "boss_spawn"]

const JsonCodec := preload("res://scripts/map_editor/map_editor_json_codec.gd")

static var _transaction_counter := 0

var _apply := false
var _rebuild_formal := false
var _canonical_by_id: Dictionary = {}
var _registry: Dictionary = {}
var _quarantine: Array[Dictionary] = []
var _existing_quarantine: Dictionary = {}
var _errors: Array[String] = []
var _map_reports: Array[Dictionary] = []
var _pending_writes: Array[Dictionary] = []
var _inject_write_failure := false


func _init() -> void:
	# Godot keeps arguments after the `--` separator in user args.  Some
	# launches (notably the PowerShell test wrapper) expose only the full
	# command line, so accept both forms without silently defaulting to a
	# destructive mode.
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	_apply = args.has("--apply")
	_rebuild_formal = args.has("--rebuild-formal")
	_inject_write_failure = args.has("--inject-write-failure")
	if not _apply and not args.has("--check"):
		_fail("usage: --check or --apply [--rebuild-formal]")
		return
	var canonical := _read_json(CANONICAL_PATH)
	if canonical.is_empty():
		_fail("canonical_catalog_missing")
		return
	var canonical_entries: Array = canonical.get("entries", [])
	if canonical_entries.is_empty() and canonical.get("entries_by_id", {}) is Dictionary:
		canonical_entries = (canonical.get("entries_by_id", {}) as Dictionary).values()
	for raw: Variant in canonical_entries:
		if raw is Dictionary:
			var numeric_id := int(raw.get("monster_id", -1))
			if numeric_id > 0:
				_canonical_by_id[str(numeric_id)] = raw
	_registry = _read_json(REGISTRY_PATH)
	if _registry.is_empty():
		_fail("release_registry_missing")
		return
	_existing_quarantine = _read_json(QUARANTINE_PATH)
	_run.call_deferred()


func _run() -> void:
	var maps: Array = _registry.get("maps", [])
	if maps.size() != 11:
		_errors.append("expected_11_release_maps:%d" % maps.size())
	for raw_map: Variant in maps:
		if not raw_map is Dictionary:
			_errors.append("invalid_registry_map_entry")
			continue
		var map_entry: Dictionary = raw_map
		var map_key := str(map_entry.get("map_key", ""))
		var runtime_path := str(map_entry.get("runtime_path", ""))
		var editor_path := "res://map_editor_workspace/%s/%s.editor.json" % [map_key, map_key]
		if not runtime_path.begins_with("res://assets/data/runtime/map_editor/"):
			_errors.append("runtime_path_outside_formal_root:%s" % map_key)
			continue
		var runtime_result := _migrate_file(runtime_path, "semantics", map_key, "runtime")
		var editor_result := _migrate_file(editor_path, "layers", map_key, "editor")
		_map_reports.append({
			"map_key": map_key,
			"runtime_path": runtime_path,
			"editor_path": editor_path,
			"runtime": runtime_result,
			"editor": editor_result,
		})
	if _apply and (not _quarantine.is_empty() or _existing_quarantine.is_empty()):
		var report := _build_quarantine_report()
		_queue_json_write(QUARANTINE_PATH, report)
	if not _apply:
		_validate_existing_quarantine_report()
		if not _quarantine.is_empty():
			_errors.append("active_records_require_quarantine_apply:%d" % _quarantine.size())
	if _rebuild_formal and not _apply:
		_errors.append("rebuild_requires_apply")
	if _apply:
		# No destination is touched until every map has been parsed, all
		# semantic comparisons have passed, and the pending plan is complete.
		if not _errors.is_empty():
			_fail(";".join(_errors))
			return
		if not _commit_pending_writes():
			_errors.append("apply_transaction_failed")
			_fail(";".join(_errors))
			return
		if _rebuild_formal:
			_rebuild_all_formal_maps()
	if _errors.is_empty():
		if _apply:
			print("MAP_SPAWN_IDENTITY_APPLY_PASS maps=%d quarantined=%d rebuild=%s" % [_map_reports.size(), _quarantine.size(), _rebuild_formal])
		else:
			print("MAP_SPAWN_IDENTITY_CHECK_PASS maps=%d quarantined=%d" % [_map_reports.size(), _quarantine.size()])
		quit(0)
		return
	_fail(";".join(_errors))


func _migrate_file(path: String, container_key: String, map_key: String, file_kind: String) -> Dictionary:
	var original := _read_json(path)
	if original.is_empty():
		_errors.append("%s_missing:%s" % [file_kind, path])
		return {"ok": false, "path": path, "changed": false, "active": 0, "quarantined": 0}
	var document := original.duplicate(true)
	var container: Dictionary = document.get(container_key, {})
	var original_container: Dictionary = original.get(container_key, {})
	var changed := false
	var active := 0
	var quarantined := 0
	var source_sha := FileAccess.get_sha256(path)
	for layer: String in LAYERS:
		var source_entries: Array = original_container.get(layer, [])
		var kept: Array = []
		for index in source_entries.size():
			var raw: Variant = source_entries[index]
			if not raw is Dictionary:
				_errors.append("%s_non_dictionary:%s:%s:%d" % [file_kind, map_key, layer, index])
				continue
			var source_entry: Dictionary = raw
			var identity := _entry_identity(source_entry)
			var numeric_id := int(identity.get("monster_id", -1))
			var canonical: Dictionary = _canonical_by_id.get(str(numeric_id), {})
			var reasons: Array[String] = []
			if not bool(identity.get("ok", false)):
				reasons.append(str(identity.get("reason", "invalid_identity_fields")))
			if numeric_id <= 0:
				reasons.append("invalid_monster_id")
			elif canonical.is_empty():
				reasons.append("canonical_monster_id_missing")
			else:
				var classification := str(canonical.get("classification", ""))
				var expected_layer := _canonical_layer(canonical)
				if expected_layer.is_empty():
					reasons.append("canonical_classification_unresolved")
				elif expected_layer != layer:
					reasons.append("canonical_placement_mismatch:%s" % expected_layer)
				var placement: Dictionary = canonical.get("editor_placement", {})
				if not bool(placement.get("allowed", false)):
					reasons.append("editor_placement_not_allowed")
				if not bool(canonical.get("runtime_allowed", false)):
					reasons.append("runtime_not_allowed")
				if str(canonical.get("status", "")) not in ["", "formal"]:
					reasons.append("canonical_status:%s" % str(canonical.get("status", "")))
				var appearance: Dictionary = canonical.get("appearance_profile", {})
				if not appearance.is_empty() and str(appearance.get("status", "formal")) != "formal":
					reasons.append("appearance_not_formal")
				var drop_policy: Dictionary = canonical.get("drop_policy", {})
				if bool(drop_policy.get("hostile_requires_non_empty", false)) and int(drop_policy.get("entry_count", 0)) <= 0:
					reasons.append("drop_profile_empty")
			# In check mode a record that is semantically resolvable but still
			# carries a legacy prefix/alias or a redundant boss flag is not a
			# clean active record.  Apply mode migrates it below.
			if not _apply and reasons.is_empty():
				reasons.append_array(_active_identity_contract_errors(source_entry))
			if not reasons.is_empty():
				if not _apply:
					_errors.append("active_identity_contract:%s:%s:%d:%s" % [path, layer, index, ";".join(reasons)])
				_quarantine.append({
					"map_key": map_key,
					"file_kind": file_kind,
					"source_path": path,
					"source_file_sha256_before": source_sha,
					"layer": layer,
					"index": index,
					"reason": ";".join(reasons),
					"monster_id_observed": numeric_id,
					"canonical": _canonical_summary(canonical),
					"original_entry_sha256": _sha256_text(JsonCodec.encode(source_entry)),
					"original_entry": source_entry,
				})
				quarantined += 1
				changed = true
				continue
			var migrated := source_entry.duplicate(true)
			migrated["monster_id"] = numeric_id
			migrated.erase("boss_id")
			migrated.erase("content_id")
			# `is_boss` is derived by the canonical runtime bridge from the
			# stable monster_id and placement layer.  Persisting a second flag
			# would allow the two identities to drift, so remove it entirely.
			migrated.erase("is_boss")
			kept.append(migrated)
			active += 1
			if not _identity_equal(source_entry, migrated):
				changed = true
				if not _non_identity_equal(source_entry, migrated):
					_errors.append("semantic_fields_changed:%s:%s:%d" % [path, layer, index])
		container[layer] = kept
		document[container_key] = container
	if _apply and changed:
		_queue_json_write(path, document)
	return {
		"ok": true,
		"path": path,
		"source_file_sha256_before": source_sha,
		"changed": changed,
		"active": active,
		"quarantined": quarantined,
	}


## Parse only the identity representations that the legacy maps actually
## used.  In particular, never split an arbitrary dotted string: accepting
## `garbage.64` or `64.5` would silently attach a spawn to the wrong monster.
static func _parse_identity_value(value: Variant) -> int:
	if value is bool:
		return -1
	if value is int:
		return int(value) if int(value) > 0 else -1
	if value is float:
		if value != value or value == INF or value == -INF or value != floor(value):
			return -1
		var integral := int(value)
		return integral if integral > 0 else -1
	if not value is String:
		return -1
	var token := value as String
	if token != token.strip_edges():
		return -1
	var regex := RegEx.new()
	if regex.compile("^(monster|boss)\\.[0-9]+$") != OK:
		return -1
	if regex.search(token) == null:
		return -1
	var digits := token.get_slice(".", 1)
	var integral_string := digits.to_int()
	return integral_string if integral_string > 0 else -1


## Resolve all identity fields and fail closed if a document carries two
## disagreeing aliases.  The caller records the complete original entry in
## quarantine, so a future migration can be audited/replayed.
static func _entry_identity(entry: Dictionary) -> Dictionary:
	var fields: Array[Dictionary] = []
	for key: String in ["monster_id", "boss_id", "content_id"]:
		if not entry.has(key):
			continue
		var parsed := _parse_identity_value(entry.get(key))
		if parsed <= 0:
			return {"ok": false, "reason": "invalid_identity_field:%s" % key, "monster_id": -1}
		fields.append({"key": key, "monster_id": parsed})
	if fields.is_empty():
		return {"ok": false, "reason": "missing_identity_fields", "monster_id": -1}
	var expected := int(fields[0].get("monster_id", -1))
	for field: Dictionary in fields:
		if int(field.get("monster_id", -1)) != expected:
			return {"ok": false, "reason": "conflicting_identity_fields", "monster_id": -1, "fields": fields}
	return {"ok": true, "monster_id": expected, "fields": fields}


static func _active_identity_contract_errors(entry: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var active_id: Variant = entry.get("monster_id", null)
	# JSON decoding in Godot may materialize an integral token as float.  Keep
	# that representation valid (the runtime bridge applies the same finite,
	# integral check), but never allow a string/prefixed alias in active data.
	if active_id is String or active_id is bool or _parse_identity_value(active_id) <= 0:
		errors.append("monster_id_must_be_positive_integer")
	for key: String in ["boss_id", "content_id", "is_boss"]:
		if entry.has(key):
			errors.append("legacy_identity_field:%s" % key)
	return errors


func _canonical_layer(canonical: Dictionary) -> String:
	var classification := str(canonical.get("classification", ""))
	var placement: Dictionary = canonical.get("editor_placement", {})
	var explicit := str(placement.get("placement_kind", ""))
	if explicit in LAYERS:
		return explicit
	if classification in ["elite", "boss"]:
		return "boss_spawn"
	if classification == "ordinary":
		return "monster_spawn"
	return ""


func _identity_equal(before: Dictionary, after: Dictionary) -> bool:
	return (
		_identity_field_equal(before.get("monster_id", null), after.get("monster_id", null))
		and _identity_field_equal(before.get("boss_id", null), after.get("boss_id", null))
		and _identity_field_equal(before.get("content_id", null), after.get("content_id", null))
		and _identity_field_equal(before.get("is_boss", null), after.get("is_boss", null))
	)


func _identity_field_equal(before: Variant, after: Variant) -> bool:
	if typeof(before) != typeof(after):
		return false
	return before == after


func _non_identity_equal(before: Dictionary, after: Dictionary) -> bool:
	var a := before.duplicate(true)
	var b := after.duplicate(true)
	for key: String in ["monster_id", "boss_id", "content_id", "is_boss"]:
		a.erase(key)
		b.erase(key)
	return JsonCodec.encode(a) == JsonCodec.encode(b)


func _canonical_summary(canonical: Dictionary) -> Dictionary:
	return {
		"monster_id": int(canonical.get("monster_id", -1)),
		"canonical_name": str(canonical.get("canonical_name", "")),
		"classification": str(canonical.get("classification", "")),
		"editor_allowed": bool(canonical.get("editor_placement", {}).get("allowed", false)),
		"runtime_allowed": bool(canonical.get("runtime_allowed", false)),
		"placement_kind": _canonical_layer(canonical),
		"status": str(canonical.get("status", "")),
	}


func _validate_existing_quarantine_report() -> void:
	if _existing_quarantine.is_empty():
		_errors.append("quarantine_report_missing")
		return
	if int(_existing_quarantine.get("schema_version", -1)) != 1:
		_errors.append("quarantine_report_schema_invalid")
	if str(_existing_quarantine.get("report_id", "")) != "map_spawn_identity_quarantine_v1":
		_errors.append("quarantine_report_id_invalid")
	if str(_existing_quarantine.get("migration_contract", "")) != "canonical_monster_id_only_v1":
		_errors.append("quarantine_report_contract_invalid")
	var entries: Variant = _existing_quarantine.get("entries", null)
	if not entries is Array:
		_errors.append("quarantine_report_entries_invalid")
		return
	var seen: Dictionary = {}
	for raw: Variant in entries:
		if not raw is Dictionary:
			_errors.append("quarantine_report_entry_not_dictionary")
			continue
		var item: Dictionary = raw
		for key: String in ["map_key", "file_kind", "source_path", "source_file_sha256_before", "layer", "index", "reason", "original_entry_sha256", "original_entry"]:
			if not item.has(key):
				_errors.append("quarantine_report_missing_field:%s" % key)
		var key_id := "%s|%s|%s|%s" % [str(item.get("map_key", "")), str(item.get("file_kind", "")), str(item.get("layer", "")), str(item.get("index", ""))]
		if seen.has(key_id):
			_errors.append("quarantine_report_duplicate:%s" % key_id)
		seen[key_id] = true
		var original: Variant = item.get("original_entry", null)
		if not original is Dictionary:
			_errors.append("quarantine_report_original_entry_invalid:%s" % key_id)
			continue
		var expected_hash := _sha256_text(JsonCodec.encode(original))
		if str(item.get("original_entry_sha256", "")).to_lower() != expected_hash.to_lower():
			_errors.append("quarantine_report_original_hash_mismatch:%s" % key_id)
		if str(item.get("reason", "")).strip_edges().is_empty():
			_errors.append("quarantine_report_reason_missing:%s" % key_id)
		if int(item.get("index", -1)) < 0:
			_errors.append("quarantine_report_index_invalid:%s" % key_id)


func _build_quarantine_report() -> Dictionary:
	return {
		"schema_version": 1,
		"report_id": "map_spawn_identity_quarantine_v1",
		"migration_contract": "canonical_monster_id_only_v1",
		"source_registry_path": REGISTRY_PATH,
		"source_canonical_catalog_path": CANONICAL_PATH,
		"entry_count": _quarantine.size(),
		"entries": _quarantine,
	}


func _queue_json_write(path: String, value: Dictionary) -> void:
	_pending_writes.append({"path": path, "text": JsonCodec.encode(value)})


func _commit_pending_writes() -> bool:
	if _pending_writes.is_empty():
		return true
	var injection := 1 if _inject_write_failure else -1
	var result := atomic_replace_text_files(_pending_writes, injection)
	if not bool(result.get("ok", false)):
		_errors.append("apply_transaction:%s" % str(result.get("reason", "unknown")))
		return false
	_pending_writes.clear()
	return true


## Replace a set of exact JSON files as one reversible transaction.  All temp
## files are prepared and parsed before any destination is renamed.  If a
## later rename fails (or the test seam injects one), every already-promoted
## destination is restored byte-for-byte from its captured original.
static func atomic_replace_text_files(plans: Array[Dictionary], inject_failure_after := -1) -> Dictionary:
	if plans.is_empty():
		return {"ok": true, "replaced": 0}
	var states: Array[Dictionary] = []
	var seen_paths: Dictionary = {}
	_transaction_counter += 1
	var nonce := "%d_%d" % [Time.get_ticks_usec(), _transaction_counter]
	for plan: Dictionary in plans:
		var path := str(plan.get("path", ""))
		if path.is_empty() or seen_paths.has(path):
			_cleanup_atomic_states(states)
			return {"ok": false, "reason": "duplicate_or_empty_path"}
		seen_paths[path] = true
		var absolute := _absolute_path_static(path)
		var original_exists := FileAccess.file_exists(absolute)
		var original_bytes := PackedByteArray()
		if original_exists:
			var original_file := FileAccess.open(absolute, FileAccess.READ)
			if original_file == null:
				_cleanup_atomic_states(states)
				return {"ok": false, "reason": "original_open_failed:%s" % path}
			original_bytes = original_file.get_buffer(original_file.get_length())
			original_file.close()
		var temp := absolute + ".identity_migration_tmp." + nonce
		var backup := absolute + ".identity_migration_bak." + nonce
		var text := str(plan.get("text", ""))
		var parsed: Variant = JSON.parse_string(text)
		if not parsed is Dictionary:
			_cleanup_atomic_states(states)
			return {"ok": false, "reason": "new_json_invalid:%s" % path}
		var file := FileAccess.open(temp, FileAccess.WRITE)
		if file == null:
			_cleanup_atomic_states(states)
			return {"ok": false, "reason": "temp_open_failed:%s" % path}
		file.store_string(text)
		file.flush()
		file.close()
		states.append({
			"path": path,
			"absolute": absolute,
			"temp": temp,
			"backup": backup,
			"original_exists": original_exists,
			"original_bytes": original_bytes,
			"backed_up": false,
			"promoted": false,
		})
	var promoted_count := 0
	for state: Dictionary in states:
		var absolute := str(state.get("absolute", ""))
		var backup := str(state.get("backup", ""))
		if bool(state.get("original_exists", false)):
			var backup_error := DirAccess.rename_absolute(absolute, backup)
			if backup_error != OK:
				var rollback_ok := _rollback_atomic_states(states)
				return {"ok": false, "reason": "rollback_failed" if not rollback_ok else "backup_failed:%s:%d" % [state.get("path", ""), backup_error], "rollback_ok": rollback_ok}
			state["backed_up"] = true
		var promote_error := DirAccess.rename_absolute(str(state.get("temp", "")), absolute)
		if promote_error != OK:
			var rollback_ok := _rollback_atomic_states(states)
			return {"ok": false, "reason": "rollback_failed" if not rollback_ok else "promote_failed:%s:%d" % [state.get("path", ""), promote_error], "rollback_ok": rollback_ok}
		state["promoted"] = true
		promoted_count += 1
		if inject_failure_after >= 0 and promoted_count >= inject_failure_after:
			var rollback_ok := _rollback_atomic_states(states)
			return {"ok": false, "reason": "rollback_failed" if not rollback_ok else "injected_failure_after:%d" % promoted_count, "rollback_ok": rollback_ok}
	var cleanup_warnings: Array[String] = []
	for state: Dictionary in states:
		var backup := str(state.get("backup", ""))
		if FileAccess.file_exists(backup):
			var backup_error := DirAccess.remove_absolute(backup)
			if backup_error != OK:
				cleanup_warnings.append("backup_cleanup_failed:%s:%d" % [state.get("path", ""), backup_error])
		var temp := str(state.get("temp", ""))
		if FileAccess.file_exists(temp):
			var temp_error := DirAccess.remove_absolute(temp)
			if temp_error != OK:
				cleanup_warnings.append("temp_cleanup_failed:%s:%d" % [state.get("path", ""), temp_error])
	return {"ok": true, "replaced": states.size(), "cleanup_warnings": cleanup_warnings}


static func _cleanup_atomic_states(states: Array[Dictionary]) -> void:
	for state: Dictionary in states:
		var temp := str(state.get("temp", ""))
		var backup := str(state.get("backup", ""))
		if not temp.is_empty() and FileAccess.file_exists(temp):
			DirAccess.remove_absolute(temp)
		if not backup.is_empty() and FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)


static func _rollback_atomic_states(states: Array[Dictionary]) -> bool:
	var rollback_ok := true
	for state: Dictionary in states:
		var absolute := str(state.get("absolute", ""))
		var temp := str(state.get("temp", ""))
		var backup := str(state.get("backup", ""))
		if FileAccess.file_exists(temp):
			if DirAccess.remove_absolute(temp) != OK:
				rollback_ok = false
		if bool(state.get("promoted", false)) and FileAccess.file_exists(absolute):
			if DirAccess.remove_absolute(absolute) != OK:
				rollback_ok = false
		if bool(state.get("backed_up", false)) and FileAccess.file_exists(backup):
			var restore_error := DirAccess.rename_absolute(backup, absolute)
			if restore_error != OK:
				rollback_ok = false
		elif bool(state.get("promoted", false)) and not bool(state.get("original_exists", false)):
			if FileAccess.file_exists(absolute):
				if DirAccess.remove_absolute(absolute) != OK:
					rollback_ok = false
		# Never delete a backup that could not be restored.  It is the only
		# recoverable copy when a rename fails.
		if FileAccess.file_exists(backup):
			rollback_ok = false
	return rollback_ok


static func _absolute_path_static(path: String) -> String:
	return (
		ProjectSettings.globalize_path(path)
		if path.begins_with("res://") or path.begins_with("user://")
		else path
	)


func _rebuild_all_formal_maps() -> void:
	# Keep this migration tool independent from the integration-owned runtime
	# bridge.  The existing formal Build/Publish service is invoked in a clean
	# child Godot process after the identity files are applied, so a transient
	# bridge compile failure cannot partially mutate this migration.
	var snapshot := _capture_formal_snapshot()
	if snapshot.is_empty():
		_errors.append("formal_snapshot_failed")
		return
	var executable := OS.get_executable_path()
	var output: Array[String] = []
	var exit_code := OS.execute(
		executable,
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--scene", "res://tools/map_editor/rebuild_formal_map_releases.tscn"],
		output,
		true,
	)
	if exit_code != 0:
		if not _restore_formal_snapshot(snapshot):
			_errors.append("formal_snapshot_restore_failed")
		_errors.append("rebuild_formal_child_failed:%d:%s" % [exit_code, "\n".join(output)])


func _capture_formal_snapshot() -> Dictionary:
	var files: Array[Dictionary] = []
	var registry_bytes := _read_file_bytes(REGISTRY_PATH)
	if registry_bytes.is_empty():
		return {}
	files.append({"path": REGISTRY_PATH, "bytes": registry_bytes})
	for raw_map: Variant in _registry.get("maps", []):
		if not raw_map is Dictionary:
			return {}
		var path := str(raw_map.get("runtime_path", ""))
		var bytes := _read_file_bytes(path)
		if path.is_empty() or bytes.is_empty():
			return {}
		files.append({"path": path, "bytes": bytes})
	return {"files": files}


func _restore_formal_snapshot(snapshot: Dictionary) -> bool:
	var plans: Array[Dictionary] = []
	for raw: Variant in snapshot.get("files", []):
		if not raw is Dictionary:
			return false
		var item: Dictionary = raw
		var bytes: PackedByteArray = item.get("bytes", PackedByteArray())
		plans.append({"path": str(item.get("path", "")), "text": bytes.get_string_from_utf8()})
	var restored := atomic_replace_text_files(plans)
	if not bool(restored.get("ok", false)):
		return false
	for raw: Variant in snapshot.get("files", []):
		var item: Dictionary = raw
		var path := str(item.get("path", ""))
		if FileAccess.get_sha256(path) != _sha256_bytes(item.get("bytes", PackedByteArray())):
			return false
	return true


func _read_file_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _write_json(path: String, value: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JsonCodec.encode(value))
	file.flush()
	file.close()
	return true


func _sha256_text(text: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(text.to_utf8_buffer())
	return hashing.finish().hex_encode()


func _fail(message: String) -> void:
	push_error("MAP_SPAWN_IDENTITY_MIGRATION_FAILED %s" % message)
	quit(1)
