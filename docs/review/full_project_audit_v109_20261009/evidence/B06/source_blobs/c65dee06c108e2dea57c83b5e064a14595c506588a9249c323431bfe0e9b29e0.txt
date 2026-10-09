extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const GroundService := preload("res://scripts/map_editor/map_editor_ground_service.gd")

var proof := Proof.new()
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)


func _sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(file.get_buffer(file.get_length()))
	file.close()
	return hashing.finish().hex_encode()


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(value, "  ", true, true) + "\n")
	file.close()


func _make_journal(root: String, map_id: String, entries: Array[Dictionary]) -> void:
	_write_json(root.path_join("ground/.ground_write_set.json"), {
		"schema_version": 1,
		"map_id": map_id,
		"generation": "123_456",
		"entries": entries,
	})


func _run() -> void:
	var document := MapEditorTypes.new_map(
		"ground_txn_contract_20261010", 998410, "Ground transaction contract", Vector2i(8, 8)
	)
	var root := "user://ground_txn_contract_%d" % Time.get_ticks_usec()
	document.editor_meta.workspace = root
	var initial := GroundService.initialize(document)
	_check(bool(initial.ok), "initial ground workspace initializes")
	if not bool(initial.ok):
		_finish()
		return
	var actual_batch := GroundService.record_tile_paint_batch(document, [
		{"op": "paint_tile", "tile": [2, 2], "asset_id": "ground.dark_grass.001"},
	])
	_check(bool(actual_batch.ok), "real batch mutation commits the complete ground write set")
	if not bool(actual_batch.ok):
		_finish()
		return
	initial = GroundService.initialize(document)
	_check(bool(initial.ok), "post-batch workspace reopens")
	var manifest_path := ProjectSettings.globalize_path(str(initial.manifest_path)).replace("\\", "/")
	var state_path := ProjectSettings.globalize_path(str(initial.state_path)).replace("\\", "/")
	var baseline_manifest := GroundService._read_json(manifest_path)
	var baseline_state := GroundService._read_json(state_path)
	var manifest_new := baseline_manifest.duplicate(true)
	manifest_new["fixture_revision"] = 1
	var state_new := baseline_state.duplicate(true)
	state_new["fixture_revision"] = 1
	var manifest_tmp := manifest_path + ".txn.123_456"
	var state_tmp := state_path + ".txn.123_456"
	_write_json(manifest_tmp, manifest_new)
	_write_json(state_tmp, state_new)
	var entries: Array[Dictionary] = [
		{
			"relative_path": "ground_manifest.json",
			"temporary_path": manifest_tmp,
			"backup_path": manifest_path + ".txnbackup.123_456",
			"base_sha256": _sha256(manifest_path),
			"new_sha256": _sha256(manifest_tmp),
		},
		{
			"relative_path": "ground_state.json",
			"temporary_path": state_tmp,
			"backup_path": state_path + ".txnbackup.123_456",
			"base_sha256": _sha256(state_path),
			"new_sha256": _sha256(state_tmp),
		},
	]
	# Simulate an interruption after only manifest promotion. The recovery
	# path, rather than a test-only alternate writer, must finish the set.
	DirAccess.rename_absolute(manifest_path, manifest_path + ".txnbackup.123_456")
	DirAccess.rename_absolute(manifest_tmp, manifest_path)
	_make_journal(root, str(document.map_id), entries)
	var resumed := GroundService.initialize(document)
	_check(bool(resumed.ok), "partial promotion resumes from the committed intent")
	_check(int(resumed.manifest.get("fixture_revision", 0)) == 1, "recovery keeps intended manifest")
	_check(int(resumed.state.get("fixture_revision", 0)) == 1, "recovery promotes intended state")
	var repeated := GroundService.initialize(document)
	_check(bool(repeated.ok), "completed recovery is idempotent")
	_check(not FileAccess.file_exists(root.path_join("ground/.ground_write_set.json")), "completed intent is removed")

	# A missing primary is recoverable only when the valid base is retained in
	# the intent backup; no blind empty reinitialization is allowed.
	var state_base := GroundService._read_json(state_path)
	var state_next := state_base.duplicate(true)
	state_next["fixture_revision"] = 2
	var state_next_tmp := state_path + ".txn.123_456"
	_write_json(state_next_tmp, state_next)
	var state_backup := state_path + ".txnbackup.123_456"
	DirAccess.rename_absolute(state_path, state_backup)
	_make_journal(root, str(document.map_id), [{
		"relative_path": "ground_state.json",
		"temporary_path": state_next_tmp,
		"backup_path": state_backup,
		"base_sha256": _sha256(state_backup),
		"new_sha256": _sha256(state_next_tmp),
	}])
	var missing_recovered := GroundService.initialize(document)
	_check(bool(missing_recovered.ok), "missing primary recovers from valid intent base")
	_check(int(missing_recovered.state.get("fixture_revision", 0)) == 2, "missing primary selects intended new state")

	# A third manual version must block and leave the manual bytes untouched.
	var blocked_tmp := manifest_path + ".txn.123_456"
	var blocked_value := GroundService._read_json(manifest_path)
	blocked_value["fixture_revision"] = 3
	_write_json(blocked_tmp, blocked_value)
	var manual_value := GroundService._read_json(manifest_path)
	manual_value["manual_edit"] = "newer"
	_write_json(manifest_path, manual_value)
	_make_journal(root, str(document.map_id), [{
		"relative_path": "ground_manifest.json",
		"temporary_path": blocked_tmp,
		"backup_path": manifest_path + ".txnbackup.123_456",
		"base_sha256": "0".repeat(64),
		"new_sha256": _sha256(blocked_tmp),
	}])
	var blocked := GroundService.initialize(document)
	_check(not bool(blocked.ok), "third version returns explicit blocked recovery")
	_check(str(GroundService._read_json(manifest_path).get("manual_edit", "")) == "newer", "newer manual bytes remain untouched")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("ground/.ground_write_set.json")))
	DirAccess.remove_absolute(blocked_tmp)
	var manual_hash := _sha256(manifest_path)
	_make_journal(root, str(document.map_id), [{
		"relative_path": "../outside.json",
		"temporary_path": manifest_path + ".txn.123_456",
		"backup_path": manifest_path + ".txnbackup.123_456",
		"base_sha256": manual_hash,
		"new_sha256": manual_hash,
	}])
	var path_blocked := GroundService.initialize(document)
	_check(not bool(path_blocked.ok), "path traversal intent is rejected before file operations")
	_check(_sha256(manifest_path) == manual_hash, "path rejection preserves primary bytes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("ground/.ground_write_set.json")))
	var arbitrary_temp := ProjectSettings.globalize_path(root.path_join("ground/arbitrary.json"))
	_write_json(arbitrary_temp, GroundService._read_json(manifest_path))
	_make_journal(root, str(document.map_id), [{
		"relative_path": "ground_manifest.json",
		"temporary_path": arbitrary_temp,
		"backup_path": manifest_path + ".txnbackup.123_456",
		"base_sha256": manual_hash,
		"new_sha256": _sha256(arbitrary_temp),
	}])
	var arbitrary_blocked := GroundService.initialize(document)
	_check(not bool(arbitrary_blocked.ok), "absolute arbitrary temp is rejected")
	_check(_sha256(manifest_path) == manual_hash, "arbitrary temp rejection preserves primary bytes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("ground/.ground_write_set.json")))
	DirAccess.remove_absolute(arbitrary_temp)
	var valid_temp := manifest_path + ".txn.123_456"
	var valid_backup := manifest_path + ".txnbackup.123_456"
	_write_json(valid_temp, GroundService._read_json(manifest_path))
	_write_json(valid_backup, {"third_party": true})
	_make_journal(root, str(document.map_id), [{
		"relative_path": "ground_manifest.json",
		"temporary_path": valid_temp,
		"backup_path": valid_backup,
		"base_sha256": manual_hash,
		"new_sha256": _sha256(valid_temp),
	}])
	var backup_blocked := GroundService.initialize(document)
	_check(not bool(backup_blocked.ok), "changed backup is rejected before promotion")
	_check(_sha256(manifest_path) == manual_hash, "changed backup rejection preserves primary bytes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("ground/.ground_write_set.json")))
	DirAccess.remove_absolute(valid_temp)
	DirAccess.remove_absolute(valid_backup)
	_write_json(root.path_join("ground/.ground_write_set.json"), {
		"schema_version": 1,
		"map_id": str(document.map_id),
		"generation": "123_456",
		"entries": {"not": "an array"},
	})
	var shape_blocked := GroundService.initialize(document)
	_check(not bool(shape_blocked.ok), "dictionary entries intent is rejected")
	_check(shape_blocked.get("errors", []).has("ground_txn_entries_invalid"), "valid JSON schema reaches the entries shape guard")
	_check(_sha256(manifest_path) == manual_hash, "dictionary entries rejection preserves primary bytes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("ground/.ground_write_set.json")))
	for invalid_schema: Variant in ["1", true, 1.5]:
		_write_json(root.path_join("ground/.ground_write_set.json"), {
			"schema_version": invalid_schema, "map_id": str(document.map_id),
			"generation": "123_456", "entries": [],
		})
		var invalid_identity := GroundService.initialize(document)
		_check(not bool(invalid_identity.ok) and invalid_identity.get("errors", []).has("ground_txn_identity_corrupt"), "nonnumeric or fractional schema fails the identity guard")
		_check(_sha256(manifest_path) == manual_hash, "invalid schema preserves primary bytes")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("ground/.ground_write_set.json")))
	var duplicate_tmp := manifest_path + ".txn.123_456"
	_write_json(duplicate_tmp, GroundService._read_json(manifest_path))
	_make_journal(root, str(document.map_id), [
		{"relative_path": "ground_manifest.json", "temporary_path": duplicate_tmp, "backup_path": manifest_path + ".txnbackup.123_456", "base_sha256": manual_hash, "new_sha256": _sha256(duplicate_tmp)},
		{"relative_path": "ground_manifest.json", "temporary_path": duplicate_tmp, "backup_path": manifest_path + ".txnbackup.123_456", "base_sha256": manual_hash, "new_sha256": _sha256(duplicate_tmp)},
	])
	var duplicate_blocked := GroundService.initialize(document)
	_check(not bool(duplicate_blocked.ok), "duplicate target intent is rejected before promotion")
	_check(_sha256(manifest_path) == manual_hash, "duplicate target rejection preserves primary bytes")

	_finish()


func _finish() -> void:
	var ok := proof.write_receipt("map_editor_ground_transaction_20261010_test", proof.records.size(), failures.size())
	print("MAP_EDITOR_GROUND_TRANSACTION_%s checks=%d failures=%s" % ["PASS" if ok and failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if ok and failures.is_empty() else 1)
