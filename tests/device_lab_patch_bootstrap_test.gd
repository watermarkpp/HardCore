extends Node

const PatchBootstrap := preload("res://scripts/device_lab_patch_bootstrap.gd")

const TEST_ROOT_PREFIX := "user://device_lab_patch_bootstrap_b08_"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(PatchBootstrap.patch_matches_base({"baseCommit": "new-apk"}, "new-apk"))
	assert(not PatchBootstrap.patch_matches_base({"baseCommit": "old-apk"}, "new-apk"))
	assert(not PatchBootstrap.patch_matches_base({}, "new-apk"))
	assert(not PatchBootstrap.patch_matches_base({}, ""))
	assert(PatchBootstrap.MAX_PATCH_BYTES == 64 * 1024 * 1024, "patch size ceiling changed")
	assert(PatchBootstrap.HASH_CHUNK_BYTES <= 64 * 1024, "patch hash chunk exceeds 64 KiB")
	assert(PatchBootstrap._safe_token("skill_flash_fix_v1"), "valid patch token rejected")
	assert(PatchBootstrap._safe_token("patch-1.2"), "digits/dash/dot patch token rejected")
	assert(not PatchBootstrap._safe_token("../escape"), "traversal patch token accepted")
	assert(not PatchBootstrap._safe_token("bad name"), "space in patch token accepted")
	assert(PatchBootstrap._safe_pack_name("skill_fix_v1.pck"), "valid PCK name rejected")
	assert(not PatchBootstrap._safe_pack_name("skill_fix_v1.zip"), "non-PCK name accepted")
	assert(PatchBootstrap._is_sha256("A".repeat(64)), "valid SHA-256 rejected")
	assert(not PatchBootstrap._is_sha256("G".repeat(64)), "non-hex SHA-256 accepted")
	assert(not PatchBootstrap._is_sha256("A".repeat(63)), "short SHA-256 accepted")
	assert(ProjectSettings.get_setting("autoload/DeviceLabPatch", "") == "*res://scripts/device_lab_patch_bootstrap.gd", "early Device Lab patch autoload missing")
	var bootstrap_source := FileAccess.get_file_as_string("res://scripts/device_lab_patch_bootstrap.gd")
	assert(bootstrap_source.contains("func _init() -> void:"), "resource patch must mount in the first autoload _init")
	assert(bootstrap_source.contains("not OS.is_debug_build()"), "resource patch loader must retain its Debug-only gate")
	assert(not bootstrap_source.contains("func _enter_tree() -> void:"), "resource patch mount must not wait until _enter_tree")
	assert(not bootstrap_source.contains("func _ready() -> void:"), "resource patch mount must not wait until _ready")
	var content_layers := str(ProjectSettings.get_setting("autoload/ContentLayers", ""))
	var autoload_section := FileAccess.get_file_as_string("res://project.godot").get_slice("[autoload]", 1).get_slice("[", 0)
	assert(autoload_section.find("DeviceLabPatch=") < autoload_section.find("ContentLayers="), "patch loader must run before gameplay autoloads: %s" % content_layers)
	_run_bounded_pack_validation()
	print("DEVICE_LAB_PATCH_BOOTSTRAP_PASS strict_manifest init_mount early_autoload bounded_stream isolated_fixtures")
	get_tree().quit(0)


func _run_bounded_pack_validation() -> void:
	var test_root := "%s%d" % [TEST_ROOT_PREFIX, Time.get_ticks_usec()]
	var absolute_root := ProjectSettings.globalize_path(test_root)
	assert(DirAccess.make_dir_recursive_absolute(absolute_root) == OK, "isolated patch fixture directory creation failed")

	var missing_bootstrap := _bootstrap_for(test_root)
	_write_manifest(
		missing_bootstrap.active_manifest_for_test,
		{
			"schemaVersion": 1,
			"patchId": "missing_fixture",
			"file": "missing.pck",
			"size": 1,
			"sha256": "A".repeat(64),
		},
	)
	missing_bootstrap._load_active_patch()
	assert(missing_bootstrap.load_error == "pack_missing", "missing pack was not rejected: %s" % missing_bootstrap.load_error)

	var mismatch_path := test_root.path_join("manifest_mismatch.pck")
	_write_bytes(mismatch_path, PackedByteArray([1, 2, 3, 4]))
	var mismatch_bootstrap := _bootstrap_for(test_root)
	_write_manifest(
		mismatch_bootstrap.active_manifest_for_test,
		{
			"schemaVersion": 1,
			"patchId": "size_mismatch_fixture",
			"file": "manifest_mismatch.pck",
			"size": 5,
			"sha256": "A".repeat(64),
		},
	)
	mismatch_bootstrap._load_active_patch()
	assert(mismatch_bootstrap.load_error == "pack_size_mismatch", "manifest size mismatch was not rejected: %s" % mismatch_bootstrap.load_error)

	var hashbad_path := test_root.path_join("hash_bad.pck")
	_write_bytes(hashbad_path, PackedByteArray([5, 6, 7, 8]))
	var hashbad_bootstrap := _bootstrap_for(test_root)
	_write_manifest(
		hashbad_bootstrap.active_manifest_for_test,
		{
			"schemaVersion": 1,
			"patchId": "hash_bad_fixture",
			"file": "hash_bad.pck",
			"size": 4,
			"sha256": "A".repeat(64),
		},
	)
	hashbad_bootstrap._load_active_patch()
	assert(hashbad_bootstrap.load_error == "pack_hash_mismatch", "hash mismatch was not rejected: %s" % hashbad_bootstrap.load_error)

	var oversize_path := test_root.path_join("oversize_sparse.pck")
	_write_sparse_file(oversize_path, PatchBootstrap.MAX_PATCH_BYTES + 1)
	var oversize_bootstrap := _bootstrap_for(test_root)
	_write_manifest(
		oversize_bootstrap.active_manifest_for_test,
		{
			"schemaVersion": 1,
			"patchId": "oversize_fixture",
			"file": "oversize_sparse.pck",
			# Keep the manifest itself within the accepted range so validation
			# reaches the actual same-handle file-length check.
			"size": PatchBootstrap.MAX_PATCH_BYTES,
			"sha256": "A".repeat(64),
		},
	)
	oversize_bootstrap._load_active_patch()
	assert(oversize_bootstrap.load_error == "pack_too_large", "oversize sparse pack was not rejected: %s" % oversize_bootstrap.load_error)

	var good_pack_path := test_root.path_join("good_fixture.pck")
	var marker_path := test_root.path_join("good_fixture_marker.txt")
	_write_text(marker_path, "B08 bounded stream fixture")
	var packer := PCKPacker.new()
	assert(packer.pck_start(good_pack_path) == OK, "good PCK fixture creation failed")
	assert(packer.add_file("res://__device_lab_b08_fixture_marker.txt", marker_path) == OK, "good PCK fixture entry creation failed")
	assert(packer.flush() == OK, "good PCK fixture flush failed")
	var good_file := FileAccess.open(good_pack_path, FileAccess.READ)
	assert(good_file != null, "good PCK fixture could not be reopened")
	var good_size := int(good_file.get_length())
	good_file.close()
	var good_hash := _stream_sha256(good_pack_path)
	var inspection := PatchBootstrap.inspect_pack_file(good_pack_path, good_size, good_hash)
	assert(bool(inspection.get("ok", false)), "valid PCK stream inspection failed: %s" % inspection)
	assert(int(inspection.get("bytes_read", -1)) == good_size, "valid PCK was not read exactly once in bounded chunks")

	var good_bootstrap := _bootstrap_for(test_root)
	_write_manifest(
		good_bootstrap.active_manifest_for_test,
		{
			"schemaVersion": 1,
			"patchId": "good_fixture",
			"file": "good_fixture.pck",
			"size": good_size,
			"sha256": good_hash,
		},
	)
	good_bootstrap._load_active_patch()
	assert(good_bootstrap.load_error.is_empty(), "valid PCK was not mounted: %s" % good_bootstrap.load_error)
	assert(good_bootstrap.loaded_patch_id == "good_fixture", "loaded patch id was not preserved")
	assert(good_bootstrap.loaded_patch_sha256 == good_hash, "loaded patch hash was not preserved")
	assert(FileAccess.file_exists("res://__device_lab_b08_fixture_marker.txt"), "valid PCK did not mount its fixture entry")

	_cleanup_tree(absolute_root)


func _bootstrap_for(test_root: String) -> Node:
	var bootstrap := PatchBootstrap.new()
	bootstrap.patch_dir_for_test = test_root
	bootstrap.active_manifest_for_test = test_root.path_join("active.json")
	return bootstrap


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "fixture text file could not be opened: %s" % path)
	file.store_string(value)
	file.close()


func _write_bytes(path: String, value: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "fixture binary file could not be opened: %s" % path)
	file.store_buffer(value)
	file.close()


func _write_sparse_file(path: String, length: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "sparse fixture file could not be opened: %s" % path)
	file.seek(length - 1)
	file.store_8(0)
	file.close()


func _write_manifest(path: String, manifest: Dictionary) -> void:
	if FileAccess.file_exists("res://generated/build_info.json"):
		var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/build_info.json"))
		manifest["baseCommit"] = str(info.get("git_head", ""))
	_write_text(path, JSON.stringify(manifest))


func _stream_sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "hash fixture file could not be opened: %s" % path)
	var hashing := HashingContext.new()
	assert(hashing.start(HashingContext.HASH_SHA256) == OK, "fixture hash context could not start")
	var length := int(file.get_length())
	var bytes_read := 0
	while bytes_read < length:
		var chunk_size := mini(PatchBootstrap.HASH_CHUNK_BYTES, length - bytes_read)
		var chunk := file.get_buffer(chunk_size)
		assert(chunk.size() == chunk_size, "fixture hash short read")
		hashing.update(chunk)
		bytes_read += chunk.size()
	file.close()
	return hashing.finish().hex_encode().to_upper()


func _cleanup_tree(absolute_root: String) -> void:
	var directory := DirAccess.open(absolute_root)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := absolute_root.path_join(entry)
			if directory.current_is_dir():
				_cleanup_tree(child)
			else:
				DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(absolute_root)
