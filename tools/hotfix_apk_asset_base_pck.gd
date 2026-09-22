extends SceneTree

## Build and independently verify a PCK made from the Android APK assets tree.
## This is a host-side helper; it is not a runtime project component.

const HASH_CHUNK_BYTES := 64 * 1024


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := _argument(args, "--mode")
	var manifest_path := _argument(args, "--manifest")
	var pack_path := _argument(args, "--pack")
	var exit_code := 1
	if mode == "pack":
		exit_code = _pack(manifest_path, pack_path)
	elif mode == "verify":
		var result_path := _argument(args, "--result")
		var sentinel := _argument(args, "--sentinel")
		exit_code = _verify(manifest_path, pack_path, result_path, sentinel)
	else:
		printerr("HOTFIX_APK_ASSET_BASE_ERROR unknown mode")
	quit(exit_code)


func _argument(args: PackedStringArray, key: String) -> String:
	var prefix := key + "="
	for argument in args:
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return ""


func _safe_resource_path(path: String) -> bool:
	if not path.begins_with("res://"):
		return false
	var relative := path.substr(6)
	# GDScript String literals cannot safely carry an embedded NUL.  Inspect
	# the UTF-8 bytes instead so malformed manifest paths fail closed without
	# emitting parser warnings for every resource.
	if relative.is_empty() or relative.contains("\\") or relative.contains(":") or relative.to_utf8_buffer().has(0):
		return false
	for segment in relative.split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true


func _parse_manifest_line(line: String) -> Dictionary:
	var columns := line.split("\t", false)
	if columns.size() != 4:
		return {}
	var resource_path := columns[0]
	var source_path := columns[1]
	var expected_bytes := int(columns[2])
	var expected_hash := columns[3].to_upper()
	if not _safe_resource_path(resource_path) or source_path.is_empty() or expected_bytes < 0:
		return {}
	if expected_hash.length() != 64:
		return {}
	for character in expected_hash:
		if not ((character >= "0" and character <= "9") or (character >= "A" and character <= "F")):
			return {}
	return {
		"resource_path": resource_path,
		"source_path": source_path,
		"bytes": expected_bytes,
		"sha256": expected_hash,
	}


func _open_manifest(path: String) -> FileAccess:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	return FileAccess.open(path, FileAccess.READ)


func _pack(manifest_path: String, pack_path: String) -> int:
	var manifest := _open_manifest(manifest_path)
	if manifest == null or pack_path.is_empty():
		printerr("HOTFIX_APK_ASSET_BASE_ERROR pack arguments")
		return 2
	var packer := PCKPacker.new()
	var start_error := packer.pck_start(pack_path)
	if start_error != OK:
		printerr("HOTFIX_APK_ASSET_BASE_ERROR pck_start=%d" % start_error)
		return 3
	var count := 0
	var total_bytes: int = 0
	while not manifest.eof_reached():
		var line := manifest.get_line()
		if line.is_empty():
			continue
		var row := _parse_manifest_line(line)
		if row.is_empty():
			printerr("HOTFIX_APK_ASSET_BASE_ERROR malformed manifest line=%d" % (count + 1))
			return 4
		var add_error := packer.add_file(row["resource_path"], row["source_path"])
		if add_error != OK:
			printerr("HOTFIX_APK_ASSET_BASE_ERROR add_file=%d path=%s" % [add_error, row["resource_path"]])
			return 5
		count += 1
		total_bytes += int(row["bytes"])
	manifest.close()
	var flush_error := packer.flush()
	if flush_error != OK:
		printerr("HOTFIX_APK_ASSET_BASE_ERROR flush=%d" % flush_error)
		return 6
	print("HOTFIX_APK_ASSET_BASE_PACK_PASS resources=%d bytes=%d" % [count, total_bytes])
	return 0


func _hash_file(file: FileAccess) -> Dictionary:
	var expected_length := int(file.get_length())
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return {"ok": false, "bytes": 0, "sha256": ""}
	var bytes_read := 0
	while bytes_read < expected_length:
		var chunk_size := mini(HASH_CHUNK_BYTES, expected_length - bytes_read)
		var chunk := file.get_buffer(chunk_size)
		if chunk.size() != chunk_size:
			return {"ok": false, "bytes": bytes_read + chunk.size(), "sha256": ""}
		hashing.update(chunk)
		bytes_read += chunk.size()
	var actual_hash := hashing.finish().hex_encode().to_upper()
	return {"ok": true, "bytes": bytes_read, "sha256": actual_hash}


func _write_result(path: String, result: Dictionary) -> void:
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result))
		file.close()


func _verify(manifest_path: String, pack_path: String, result_path: String, sentinel: String) -> int:
	var failure := {"ok": false, "error": "", "resourceCount": 0, "resourceBytes": 0}
	if manifest_path.is_empty() or pack_path.is_empty() or not FileAccess.file_exists(pack_path):
		failure["error"] = "pack_missing"
		_write_result(result_path, failure)
		printerr("HOTFIX_APK_ASSET_BASE_ERROR pack_missing")
		return 2
	if not ProjectSettings.load_resource_pack(pack_path, true):
		failure["error"] = "load_resource_pack_failed"
		_write_result(result_path, failure)
		printerr("HOTFIX_APK_ASSET_BASE_ERROR load_resource_pack_failed")
		return 3
	if sentinel.is_empty() or not FileAccess.file_exists(sentinel):
		failure["error"] = "sentinel_not_mounted"
		_write_result(result_path, failure)
		printerr("HOTFIX_APK_ASSET_BASE_ERROR sentinel_not_mounted")
		return 4
	var manifest := _open_manifest(manifest_path)
	if manifest == null:
		failure["error"] = "manifest_missing"
		_write_result(result_path, failure)
		printerr("HOTFIX_APK_ASSET_BASE_ERROR manifest_missing")
		return 5
	var count := 0
	var total_bytes: int = 0
	while not manifest.eof_reached():
		var line := manifest.get_line()
		if line.is_empty():
			continue
		var row := _parse_manifest_line(line)
		if row.is_empty():
			failure["error"] = "malformed_manifest"
			_write_result(result_path, failure)
			printerr("HOTFIX_APK_ASSET_BASE_ERROR malformed_manifest")
			return 6
		var resource_file := FileAccess.open(row["resource_path"], FileAccess.READ)
		if resource_file == null:
			failure["error"] = "resource_missing:%s" % row["resource_path"]
			_write_result(result_path, failure)
			printerr("HOTFIX_APK_ASSET_BASE_ERROR resource_missing=%s" % row["resource_path"])
			return 7
		var actual := _hash_file(resource_file)
		resource_file.close()
		if not bool(actual["ok"]) or int(actual["bytes"]) != int(row["bytes"]) or str(actual["sha256"]) != str(row["sha256"]):
			failure["error"] = "resource_mismatch:%s" % row["resource_path"]
			failure["actualBytes"] = actual["bytes"]
			failure["actualSha256"] = actual["sha256"]
			_write_result(result_path, failure)
			printerr("HOTFIX_APK_ASSET_BASE_ERROR resource_mismatch=%s" % row["resource_path"])
			return 8
		count += 1
		total_bytes += int(row["bytes"])
	var result := {
		"ok": true,
		"method": "fresh_process_load_resource_pack_replace_true_fileaccess_sha256",
		"resourceCount": count,
		"resourceBytes": total_bytes,
		"sentinel": sentinel,
	}
	_write_result(result_path, result)
	print("HOTFIX_APK_ASSET_BASE_VERIFY_PASS resources=%d bytes=%d" % [count, total_bytes])
	return 0
