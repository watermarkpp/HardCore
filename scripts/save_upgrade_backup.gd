extends RefCounted

## Raw before-image custody only. PlayerState remains the business owner and
## JsonPersistenceService remains the canonical profile/warehouse writer.
const CONTRACT := "hardcore.save.upgrade.framework_identity.v1"
const DIRECTORY := "save_upgrades/framework_identity_v1"
var root := ""
var archive := ""
var manifest: Dictionary = {}
var reason := ""

func prepare(account_root: String, sources: Array[String]) -> bool:
	root = account_root.trim_suffix("/")
	archive = root.path_join(DIRECTORY)
	reason = ""
	var manifest_path := archive.path_join("manifest.json")
	if FileAccess.file_exists(manifest_path):
		var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not loaded is Dictionary or loaded.get("contract_id") != CONTRACT or loaded.get("schema_version") != 1 or not loaded.get("files") is Dictionary:
			return _fail("upgrade_backup_manifest_invalid")
		manifest = loaded
		return verify()
	var files: Array[String] = []
	for source: String in sources:
		if not _collect(source, files): return false
	files.sort()
	var entries: Dictionary = {}
	for source: String in files:
		if not source.begins_with(root + "/"): return _fail("upgrade_backup_outside_account")
		var relative := source.trim_prefix(root + "/")
		if not _safe_relative(relative): return _fail("upgrade_backup_invalid_path")
		var target := archive.path_join("original").path_join(relative)
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir())) != OK:
			return _fail("upgrade_backup_directory_failed")
		var file := FileAccess.open(source, FileAccess.READ)
		if file == null: return _fail("upgrade_backup_source_open_failed")
		var size := file.get_length()
		file.close()
		var digest := FileAccess.get_sha256(source)
		if digest.length() != 64 or DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target)) != OK:
			return _fail("upgrade_backup_copy_failed")
		if FileAccess.get_sha256(target) != digest or FileAccess.get_sha256(source) != digest:
			return _fail("upgrade_backup_hash_mismatch")
		entries[relative] = {"size":size, "sha256":digest}
	manifest = {"contract_id":CONTRACT, "schema_version":1, "files":entries,
		"created_at":int(Time.get_unix_time_from_system())}
	if not _create_json(manifest_path, manifest): return _fail("upgrade_backup_manifest_write_failed")
	return verify()

func verify() -> bool:
	for relative: Variant in manifest.get("files", {}):
		if not relative is String or not _safe_relative(relative): return _fail("upgrade_backup_invalid_path")
		var entry: Variant = manifest.files[relative]
		if not entry is Dictionary or not entry.get("sha256") is String or entry.sha256.length() != 64:
			return _fail("upgrade_backup_manifest_invalid")
		var file := FileAccess.open(archive.path_join("original").path_join(relative), FileAccess.READ)
		if file == null: return _fail("upgrade_backup_missing")
		var size := file.get_length()
		file.close()
		if size != entry.get("size") or FileAccess.get_sha256(archive.path_join("original").path_join(relative)) != entry.sha256:
			return _fail("upgrade_backup_hash_mismatch")
	return true

func completion_status() -> Dictionary:
	var path := archive.path_join("completed.json")
	if not FileAccess.file_exists(path): return {"valid":true, "completed":false}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or value.get("contract_id") != CONTRACT or value.get("schema_version") != 1 or value.get("manifest_sha256") != FileAccess.get_sha256(archive.path_join("manifest.json")):
		return {"valid":false, "completed":false}
	return {"valid":true, "completed":true}

func complete(profile_ids: Array) -> bool:
	if not verify(): return false
	var value := {"contract_id":CONTRACT, "schema_version":1, "profiles":profile_ids.duplicate(),
		"manifest_sha256":FileAccess.get_sha256(archive.path_join("manifest.json")),
		"completed_at":int(Time.get_unix_time_from_system())}
	if not _create_json(archive.path_join("completed.json"), value): return _fail("upgrade_completion_write_failed")
	return bool(completion_status().completed)

func _collect(source: String, files: Array[String]) -> bool:
	if FileAccess.file_exists(source):
		if not files.has(source): files.append(source)
		return true
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(source)): return true
	var directory := DirAccess.open(source)
	if directory == null: return _fail("upgrade_backup_directory_unavailable")
	for name: String in directory.get_files():
		if not _collect(source.path_join(name), files): return false
	for name: String in directory.get_directories():
		if not _collect(source.path_join(name), files): return false
	return true

func _safe_relative(path: String) -> bool:
	return not path.is_empty() and not path.is_absolute_path() and not path.contains("\\") and ":" not in path and ".." not in path.split("/") and "." not in path.split("/")

func _create_json(path: String, value: Dictionary) -> bool:
	if FileAccess.file_exists(path): return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK: return false
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return false
	var serialized := JSON.stringify(value, "\t")
	file.store_string(serialized)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(temp) != serialized: return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path)) == OK and FileAccess.get_file_as_string(path) == serialized

func _fail(value: String) -> bool:
	reason = value
	return false
