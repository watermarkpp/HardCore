extends Node

## Debug-only early resource-pack loader for the physical Device Lab.
##
## It runs before gameplay autoloads and scenes, allowing a tiny, host-built
## PCK to replace selected res:// scripts, assets, or data on the next launch.
## The endpoint is deliberately declarative: one fixed manifest, one fixed
## private directory, a bounded pack, and a required SHA-256 identity.

const PATCH_DIR := "user://device_lab/patches"
const ACTIVE_MANIFEST := PATCH_DIR + "/active.json"
const MAX_PATCH_BYTES := 64 * 1024 * 1024
const HASH_CHUNK_BYTES := 64 * 1024
const MANIFEST_VERSION := 1
const BUILD_INFO_PATH := "res://assets/generated/build_info.json"

var loaded_patch_id := ""
var loaded_patch_sha256 := ""
var load_error := ""
var _load_attempted := false

## Test-only path overrides. The physical Device Lab manifest remains at the
## fixed ACTIVE_MANIFEST path; tests use an isolated user:// directory.
var patch_dir_for_test := ""
var active_manifest_for_test := ""
var build_info_path_for_test := ""


func _init() -> void:
	if _load_attempted or not OS.is_debug_build():
		return
	_load_attempted = true
	_load_active_patch()


func _load_active_patch() -> void:
	var manifest_path := _active_manifest_path()
	if not FileAccess.file_exists(manifest_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		load_error = "manifest_json"
		return
	var manifest := parsed as Dictionary
	if int(manifest.get("schemaVersion", 0)) != MANIFEST_VERSION:
		load_error = "manifest_version"
		return
	# A full APK update already contains the earlier hotfixes. Never mount a
	# retained patch built for another APK over its newer gameplay scripts.
	var build_info_path := build_info_path_for_test if not build_info_path_for_test.is_empty() else BUILD_INFO_PATH
	if not FileAccess.file_exists(build_info_path):
		load_error = "build_identity_missing"
		return
	var build_parser := JSON.new()
	if build_parser.parse(FileAccess.get_file_as_string(build_info_path)) != OK:
		load_error = "build_identity_invalid"
		return
	var build_info: Variant = build_parser.data
	if not build_info is Dictionary or not _is_git_commit(build_info.get("git_head", null)):
		load_error = "build_identity_invalid"
		return
	var apk_commit: String = build_info["git_head"]
	set_meta("apk_base_commit", apk_commit)
	if not patch_matches_base(manifest, apk_commit):
		load_error = "patch_base_mismatch"
		set_meta("obsolete_patch_cleanup_error", _discard_obsolete_patch(manifest))
		return
	var patch_id := str(manifest.get("patchId", ""))
	var file_name := str(manifest.get("file", ""))
	var expected_hash := str(manifest.get("sha256", "")).to_upper()
	var expected_size := int(manifest.get("size", -1))
	if not _safe_token(patch_id) or not _safe_pack_name(file_name):
		load_error = "manifest_identity"
		return
	if not _is_sha256(expected_hash):
		load_error = "manifest_hash"
		return
	if expected_size <= 0 or expected_size > MAX_PATCH_BYTES:
		load_error = "manifest_size"
		return
	var pack_path := _patch_dir_path().path_join(file_name)
	if not FileAccess.file_exists(pack_path):
		load_error = "pack_missing"
		return
	var inspection := inspect_pack_file(pack_path, expected_size, expected_hash)
	if not bool(inspection.get("ok", false)):
		load_error = str(inspection.get("error", "pack_validation_failed"))
		return
	# ProjectSettings.load_resource_pack reopens the path. The same-handle size
	# check above closes the read-before-load gap; a filesystem race between this
	# check and the engine's reopen remains outside this script's boundary.
	if not ProjectSettings.load_resource_pack(pack_path, true):
		load_error = "pack_load_failed"
		return
	loaded_patch_id = patch_id
	loaded_patch_sha256 = expected_hash
	set_meta("device_lab_patch_id", patch_id)
	set_meta("device_lab_patch_sha256", expected_hash)


static func patch_matches_base(manifest: Dictionary, apk_commit: String) -> bool:
	return not apk_commit.is_empty() and str(manifest.get("baseCommit", "")) == apk_commit


static func _is_git_commit(value: Variant) -> bool:
	if not value is String or value.length() != 40:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true


func _discard_obsolete_patch(manifest: Dictionary) -> Error:
	# APK replacement preserves user://. Retire only the old active PCK and its
	# manifest inside the fixed private patch directory; never walk user data.
	var file_name := str(manifest.get("file", ""))
	if not _safe_pack_name(file_name):
		return ERR_INVALID_DATA
	var pack_path := _patch_dir_path().path_join(file_name)
	if FileAccess.file_exists(pack_path):
		var pack_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(pack_path))
		if pack_error != OK:
			return pack_error # Remain rejected; retry cleanup on the next launch.
	var manifest_path := _active_manifest_path()
	if FileAccess.file_exists(manifest_path):
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest_path))
	return OK


func _patch_dir_path() -> String:
	return patch_dir_for_test if not patch_dir_for_test.is_empty() else PATCH_DIR


func _active_manifest_path() -> String:
	return active_manifest_for_test if not active_manifest_for_test.is_empty() else ACTIVE_MANIFEST


static func inspect_pack_file(
	pack_path: String,
	expected_size: int,
	expected_hash: String,
) -> Dictionary:
	if not FileAccess.file_exists(pack_path):
		return {"ok": false, "error": "pack_missing", "bytes_read": 0}
	var file := FileAccess.open(pack_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "pack_open_failed", "bytes_read": 0}
	var initial_length := int(file.get_length())
	# Reject the actual file length before allocating any content buffer.
	if initial_length > MAX_PATCH_BYTES:
		return {
			"ok": false,
			"error": "pack_too_large",
			"actual_size": initial_length,
			"bytes_read": 0,
		}
	if initial_length <= 0:
		return {
			"ok": false,
			"error": "pack_size_invalid",
			"actual_size": initial_length,
			"bytes_read": 0,
		}
	if initial_length != expected_size:
		return {
			"ok": false,
			"error": "pack_size_mismatch",
			"actual_size": initial_length,
			"bytes_read": 0,
		}

	var hashing := HashingContext.new()
	var hash_error := hashing.start(HashingContext.HASH_SHA256)
	if hash_error != OK:
		return {
			"ok": false,
			"error": "hash_init_failed",
			"actual_size": initial_length,
			"bytes_read": 0,
		}
	var bytes_read := 0
	while bytes_read < initial_length:
		var chunk_size := mini(HASH_CHUNK_BYTES, initial_length - bytes_read)
		var chunk := file.get_buffer(chunk_size)
		if chunk.size() != chunk_size:
			return {
				"ok": false,
				"error": "pack_short_read",
				"actual_size": initial_length,
				"bytes_read": bytes_read + chunk.size(),
			}
		bytes_read += chunk.size()
		if bytes_read > MAX_PATCH_BYTES:
			return {
				"ok": false,
				"error": "pack_read_limit",
				"actual_size": initial_length,
				"bytes_read": bytes_read,
			}
		hashing.update(chunk)

	var ending_length := int(file.get_length())
	if ending_length != initial_length or bytes_read != initial_length:
		return {
			"ok": false,
			"error": "pack_changed_during_read",
			"actual_size": ending_length,
			"bytes_read": bytes_read,
		}
	var actual_hash := hashing.finish().hex_encode().to_upper()
	if actual_hash != expected_hash.to_upper():
		return {
			"ok": false,
			"error": "pack_hash_mismatch",
			"actual_size": ending_length,
			"bytes_read": bytes_read,
			"actual_hash": actual_hash,
		}
	return {
		"ok": true,
		"error": "",
		"actual_size": ending_length,
		"bytes_read": bytes_read,
		"actual_hash": actual_hash,
	}


static func _safe_token(value: String) -> bool:
	if value.is_empty() or value.length() > 96 or value.contains(".."):
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var ascii_letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var ascii_digit := code >= 48 and code <= 57
		if not (ascii_letter or ascii_digit or code in [45, 46, 95]):
			return false
	return true


static func _safe_pack_name(value: String) -> bool:
	return _safe_token(value) and value.ends_with(".pck")


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 70)):
			return false
	return true
