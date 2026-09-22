extends RefCounted
## R3: prepare a clean slate without importing the historical cell union.
## The caller owns the existing CommandStack transaction. This service never
## mutates its input, saves a map, publishes a release, or edits the catalog.
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Binding := preload("res://scripts/map_editor/polygon/poly_instance_binding.gd")
const Codec := preload("res://scripts/map_editor/map_editor_json_codec.gd")
const CONTRACT := "hc.map.collision_reset.v1"
## Only the backup envelope is versioned; the map/reset authority is unchanged.
const BACKUP_CONTRACT := "hc.map.collision_reset_backup.raw_json.v2"
const BACKUP_ROOT := "res://outputs/polygon_collision_resets"
static var test_fail_backup := false

static func fingerprint(document: Dictionary) -> String:
	return Codec.encode(document).sha256_text()

static func summary(document: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var raw_layers: Variant = document.get("layers", null)
	var raw_design: Variant = document.get("design", null)
	var raw_meta: Variant = document.get("editor_meta", null)
	if not raw_layers is Dictionary or not raw_design is Dictionary or not raw_meta is Dictionary:
		return {"ok": false, "errors": ["reset_document_structure_invalid"]}
	var layers: Dictionary = raw_layers
	var design: Dictionary = raw_design
	if Geo.parse_size(design.get("design_size", [])) == Vector2i.ZERO:
		errors.append("reset_design_size_invalid")
	if str(document.get("map_id", "")).is_empty():
		errors.append("reset_map_id_missing")
	var raw_id: Variant = document.get("runtime_map_id", null)
	if not Geo.numeric(raw_id) or float(raw_id) <= 0.0 or float(raw_id) != floorf(float(raw_id)):
		errors.append("reset_runtime_map_id_invalid")
	var raw_entries: Variant = layers.get("collision", null)
	var raw_erased: Variant = layers.get("collision_erase", [])
	if not raw_entries is Array or not raw_erased is Array:
		return {"ok": false, "errors": ["reset_collision_layers_invalid"]}
	var entries: Array = raw_entries
	var erased: Array = raw_erased
	var polygon_count: int = 0
	var legacy_count: int = 0
	var bound_count: int = 0
	var generated_count: int = 0
	var seen: Dictionary = {}
	for raw: Variant in entries:
		if not raw is Dictionary:
			errors.append("reset_collision_entry_invalid")
			continue
		if Geo.enabled(document) and str(raw.get("source", "")) != "legacy_final":
			polygon_count += 1
		else:
			legacy_count += 1
	for instance: Dictionary in Binding.instances(document):
		var id: String = str(instance.get("instance_id", ""))
		if id.is_empty() or seen.has(id):
			errors.append("reset_instance_id_missing_or_duplicate:%s" % id)
		seen[id] = true
		if str(instance.get("collision_policy", "none")) != "none":
			generated_count += 1
		if instance.has(Binding.FIELD):
			var local: Variant = instance[Binding.FIELD]
			if not local is Array:
				errors.append("reset_bound_collection_invalid:%s" % id)
			else:
				bound_count += (local as Array).size()
	return {"ok": errors.is_empty(), "errors": errors,
		"map_name": str(document.get("display_name", document.get("map_id", ""))),
		"map_id": str(document.get("map_id", "")),
		"map_polygons": polygon_count, "bound_polygons": bound_count,
		"legacy_shapes": legacy_count, "legacy_erase_cells": erased.size(),
		"instance_policy_sources": generated_count,
		"boundary_preserved": true, "safe_area_rules_preserved": true}

static func plan(document: Dictionary, source_path: String) -> Dictionary:
	var counts: Dictionary = summary(document)
	if not bool(counts.get("ok", false)):
		return counts
	var legacy: Variant = null
	if not Geo.enabled(document):
		# Read the effective old cells AFTER erasure, only for the backup.
		# They are NEVER inserted into the clean candidate.
		legacy = MapEditorCollisionService.build_walkability(document)
		if not legacy is Dictionary or not legacy.get("blocked_tiles", null) is Dictionary:
			return {"ok": false, "errors": ["reset_legacy_backup_unavailable"]}
	var document_json: String = Codec.encode(document)
	var before_hash: String = document_json.sha256_text()
	var candidate: Dictionary = document.duplicate(true)
	candidate.layers["collision"] = []
	candidate.layers["collision_erase"] = []
	for instance: Dictionary in Binding.instances(candidate):
		# Includes non-exported instances: enabling one later must not revive
		# an old bound contour. All visual and semantic fields stay untouched.
		instance.erase(Binding.FIELD)
	var meta: Dictionary = candidate.editor_meta
	meta.erase("collision_migration_contract_id")
	meta.erase("collision_migration_blocked_count")
	meta.erase("collision_backup_path")
	meta["collision_authority"] = Geo.AUTHORITY
	meta["collision_reset_contract_id"] = CONTRACT
	meta["revision"] = int(meta.get("revision", 1)) + 1
	meta["runtime_approved"] = false
	candidate.editor_meta = meta
	var payload: Dictionary = {
		"contract_id": CONTRACT, "backup_contract_id": BACKUP_CONTRACT,
		# Preserve the exact pre-reset JSON text. JSON.parse converts numbers
		# to float, so a parsed Dictionary cannot reproduce these byte hashes.
		"document_json": document_json,
		"document_sha256": before_hash, "source_document_path": source_path,
		"revision": int(document.editor_meta.get("revision", 1)),
		"collision_authority": str(document.editor_meta.get("collision_authority", "legacy_cells")),
		"effective_legacy_walkability": legacy, "summary": counts,
		"legacy_backup_role": "effective_after_erasure" if legacy != null else "not_applicable_polygon_authority",
		"base_commit": "6312d0ba69682fb1424739788b18bb8b39db174b"}
	return {"ok": true, "errors": [], "candidate": candidate,
		"before_fingerprint": before_hash, "backup_payload": payload, "summary": counts}

## Validate the exact serialized document, NOT encode(parse(document)).
## The decoded Dictionary is a convenience view. Recovery must write the
## returned document_json verbatim to preserve original numeric spelling.
static func validate_backup_payload(payload: Dictionary) -> Dictionary:
	if str(payload.get("contract_id", "")) != CONTRACT or str(payload.get("backup_contract_id", "")) != BACKUP_CONTRACT:
		return {"ok": false, "errors": ["reset_backup_contract_unsupported"]}
	var raw_json: Variant = payload.get("document_json", null)
	var raw_hash: Variant = payload.get("document_sha256", null)
	if not raw_json is String or not raw_hash is String:
		return {"ok": false, "errors": ["reset_backup_payload_invalid"]}
	var document_json: String = raw_json
	var claimed_hash: String = raw_hash
	if not _is_sha256(claimed_hash) or document_json.sha256_text() != claimed_hash:
		return {"ok": false, "errors": ["reset_backup_document_hash_mismatch"]}
	var parser: JSON = JSON.new()
	if parser.parse(document_json) != OK or not parser.data is Dictionary:
		return {"ok": false, "errors": ["reset_backup_document_json_invalid"]}
	var document: Dictionary = parser.data
	var checked: Dictionary = summary(document)
	if not bool(checked.get("ok", false)):
		return checked
	return {"ok": true, "errors": [], "document_json": document_json,
		"document_sha256": claimed_hash, "document": document, "payload": payload}

static func _is_sha256(value: String) -> bool:
	return value.length() == 64 and value == value.to_lower() and value.is_valid_hex_number()

## Read-only recovery verification: first the WHOLE file's content-addressed
## name (including legacy walkability/metadata), then the original document.
## Old R3/v1 backups are never rewritten, deleted, or silently rehashed.
static func _bytes_sha256(value: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()

static func read_backup(path: String) -> Dictionary:
	var filename: String = path.get_file()
	var expected: String = filename.trim_prefix("before_").trim_suffix(".json")
	if not _is_sha256(expected) or filename != "before_%s.json" % expected:
		return {"ok": false, "errors": ["reset_backup_filename_invalid"]}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["reset_backup_read_failed"]}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	# Reject corrupted/truncated bytes before UTF-8 decoding can log an engine
	# error (a partial Chinese character is a normal truncation possibility).
	if _bytes_sha256(bytes) != expected:
		return {"ok": false, "errors": ["reset_backup_file_hash_mismatch"]}
	var text: String = bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		return {"ok": false, "errors": ["reset_backup_file_hash_mismatch"]}
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {"ok": false, "errors": ["reset_backup_json_invalid"]}
	var checked: Dictionary = validate_backup_payload(parser.data)
	if not bool(checked.get("ok", false)):
		return checked
	checked["path"] = path
	checked["sha256"] = expected
	return checked

## Detect a file at the requested directory OR any missing parent before
## DirAccess.make_dir_recursive_absolute can emit an engine ERROR. This is a
## real filesystem preflight, not a test-only exemption. Races/permissions
## are still checked by the actual mkdir/write/readback path below.
static func _backup_directory_preflight(directory: String) -> Dictionary:
	var cursor: String = ProjectSettings.globalize_path(directory).simplify_path()
	if cursor.is_empty() or not cursor.is_absolute_path():
		return {"ok": false, "errors": ["reset_backup_directory_invalid"]}
	while not cursor.is_empty():
		if FileAccess.file_exists(cursor):
			return {"ok": false, "errors": ["reset_backup_path_is_file"], "path": cursor}
		if DirAccess.dir_exists_absolute(cursor):
			return {"ok": true, "errors": []}
		var parent: String = cursor.get_base_dir()
		if parent.is_empty() or parent == cursor:
			return {"ok": false, "errors": ["reset_backup_directory_unavailable"]}
		cursor = parent
	return {"ok": false, "errors": ["reset_backup_directory_unavailable"]}

static func _verified_backup_result(path: String) -> Dictionary:
	var verified: Dictionary = read_backup(path)
	if not bool(verified.get("ok", false)):
		return verified
	return {"ok": true, "errors": [], "path": path, "sha256": verified.sha256}

static func _file_matches_bytes(path: String, expected: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	if file.get_length() != expected.size():
		file.close()
		return false
	var actual: PackedByteArray = file.get_buffer(expected.size())
	file.close()
	return actual == expected

static func write_backup(payload: Dictionary, root: String = BACKUP_ROOT) -> Dictionary:
	if test_fail_backup:
		return {"ok": false, "errors": ["reset_test_backup_failure"]}
	var validated: Dictionary = validate_backup_payload(payload)
	if not bool(validated.get("ok", false)):
		return validated
	var document: Dictionary = validated.document
	var text: String = Codec.encode(payload)
	var expected_bytes: PackedByteArray = text.to_utf8_buffer()
	if root.is_empty():
		return {"ok": false, "errors": ["reset_backup_directory_invalid"]}
	var directory: String = root.path_join(str(document.map_id).validate_filename().replace(".", "_"))
	var preflight: Dictionary = _backup_directory_preflight(directory)
	if not bool(preflight.get("ok", false)):
		return preflight
	var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK:
		return {"ok": false, "errors": ["reset_backup_directory_failed:%d" % error]}
	var path: String = directory.path_join("before_%s.json" % text.sha256_text())
	if FileAccess.file_exists(path):
		if _file_matches_bytes(path, expected_bytes):
			return _verified_backup_result(path)
		return {"ok": false, "errors": ["reset_backup_existing_mismatch"]}
	var temporary: String = path + ".tmp_%d" % Time.get_ticks_usec()
	if FileAccess.file_exists(temporary):
		return {"ok": false, "errors": ["reset_backup_temporary_exists"]}
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["reset_backup_open_failed"]}
	file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or not _file_matches_bytes(temporary, expected_bytes):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return {"ok": false, "errors": ["reset_backup_readback_mismatch"]}
	# Never overwrite a backup which appeared while writing this temporary.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return {"ok": false, "errors": ["reset_backup_destination_appeared"]}
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return {"ok": false, "errors": ["reset_backup_promote_failed:%d" % error]}
	if not _file_matches_bytes(path, expected_bytes):
		return {"ok": false, "errors": ["reset_backup_readback_mismatch"]}
	# Do not let the controller mutate the map until the ON-DISK backup has
	# passed both exact byte verification and the production recovery reader.
	return _verified_backup_result(path)
