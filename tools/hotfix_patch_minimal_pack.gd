extends SceneTree

## Host-side PCKPacker and fresh resource-loader verifier for the XP/town
## Device Lab hotfix.  The verifier is intentionally usable from a sandbox
## project that contains no source files: every res:// lookup must resolve from
## the supplied base PCK followed by the minimal patch.

const HASH_CHUNK_BYTES := 64 * 1024
const CACHE_MODE_IGNORE := ResourceLoader.CACHE_MODE_IGNORE

const EXPECTED_CLASS_CACHE_COUNT := 182
const EXPECTED_XP_SOURCE_LEVEL_1 := 100
const EXPECTED_XP_THRESHOLD_LEVEL_1 := 10
const EXPECTED_FLAME_SIZE_SCALE := 0.75
const EXPECTED_MUSIC_LENGTH_SECONDS := 48.181406
const MUSIC_LENGTH_TOLERANCE_SECONDS := 0.05

const EXPECTED_SCRIPTS := [
	"res://scripts/game_root.gd",
	"res://scripts/hud.gd",
	"res://scripts/player_state.gd",
	"res://scripts/player_visual.gd",
	"res://scripts/town_music_controller.gd",
	"res://scripts/ui_level_up_preview.gd",
]
const EXPECTED_REMAPS := [
	"res://scripts/town_music_controller.gd.remap",
	"res://scripts/ui_level_up_preview.gd.remap",
]
const EXPECTED_AUDIO := [
	"res://assets/audio/town/main_city_bgm.ogg",
	"res://assets/audio/town/main_city_bgm.ogg.import",
	"res://assets/audio/town/main_city_bgm.source.json",
	"res://.godot/imported/main_city_bgm.ogg-0266bce75d6e2d820dbb960ab2ff9c87.oggvorbisstr",
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := _argument(args, "--mode")
	if mode == "verify":
		# With --main-pack the production autoloads are constructed after the
		# SceneTree script's _init.  Defer until DeviceLabPatch and the remaining
		# service singletons are present, while retaining a fresh process.
		call_deferred("_run_deferred_verify", args)
		return
	var exit_code := 1
	if mode == "pack":
		exit_code = _pack(_argument(args, "--manifest"), _argument(args, "--pack"))
	else:
		printerr("HOTFIX_PATCH_MINIMAL_ERROR unknown mode")
	quit(exit_code)


func _run_deferred_verify(args: PackedStringArray) -> void:
	var exit_code := _verify(
		_argument(args, "--base"),
		_argument(args, "--patch"),
		_argument(args, "--result"),
	)
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
	if relative.is_empty() or relative.contains("\\") or relative.contains(":"):
		return false
	for segment in relative.split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true


func _read_manifest(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _hash_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "bytes": 0, "sha256": ""}
	var total := int(file.get_length())
	var read_bytes := 0
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return {"ok": false, "bytes": 0, "sha256": ""}
	while read_bytes < total:
		var chunk_size := mini(HASH_CHUNK_BYTES, total - read_bytes)
		var chunk := file.get_buffer(chunk_size)
		if chunk.size() != chunk_size:
			file.close()
			return {"ok": false, "bytes": read_bytes + chunk.size(), "sha256": ""}
		hashing.update(chunk)
		read_bytes += chunk.size()
	file.close()
	return {
		"ok": true,
		"bytes": read_bytes,
		"sha256": hashing.finish().hex_encode().to_upper(),
	}


func _pack(manifest_path: String, pack_path: String) -> int:
	var manifest := _read_manifest(manifest_path)
	var raw_entries: Variant = manifest.get("entries", [])
	if manifest.is_empty() or not raw_entries is Array or pack_path.is_empty():
		printerr("HOTFIX_PATCH_MINIMAL_ERROR malformed pack manifest")
		return 2
	var packer := PCKPacker.new()
	var start_error := packer.pck_start(pack_path)
	if start_error != OK:
		printerr("HOTFIX_PATCH_MINIMAL_ERROR pck_start=%d" % start_error)
		return 3
	var seen := {}
	var bytes_total := 0
	for raw_entry: Variant in raw_entries:
		if not raw_entry is Dictionary:
			printerr("HOTFIX_PATCH_MINIMAL_ERROR malformed entry")
			return 4
		var entry: Dictionary = raw_entry
		var resource_path := str(entry.get("resourcePath", ""))
		var source_path := str(entry.get("sourcePath", ""))
		var expected_bytes := int(entry.get("bytes", -1))
		var expected_sha := str(entry.get("sha256", "")).to_upper()
		if (
			not _safe_resource_path(resource_path)
			or source_path.is_empty()
			or expected_bytes < 0
			or expected_sha.length() != 64
			or seen.has(resource_path)
			or not FileAccess.file_exists(source_path)
		):
			printerr("HOTFIX_PATCH_MINIMAL_ERROR invalid entry=%s" % resource_path)
			return 5
		var actual := _hash_file(source_path)
		if (
			not bool(actual.get("ok", false))
			or int(actual.get("bytes", -1)) != expected_bytes
			or str(actual.get("sha256", "")) != expected_sha
		):
			printerr("HOTFIX_PATCH_MINIMAL_ERROR source mismatch=%s" % resource_path)
			return 6
		var add_error := packer.add_file(resource_path, source_path)
		if add_error != OK:
			printerr(
				"HOTFIX_PATCH_MINIMAL_ERROR add_file=%d path=%s"
				% [add_error, resource_path]
			)
			return 7
		seen[resource_path] = true
		bytes_total += expected_bytes
	var flush_error := packer.flush()
	if flush_error != OK:
		printerr("HOTFIX_PATCH_MINIMAL_ERROR flush=%d" % flush_error)
		return 8
	print(
		"HOTFIX_PATCH_MINIMAL_PACK_PASS resources=%d bytes=%d"
		% [seen.size(), bytes_total]
	)
	return 0


func _fresh_load(path: String, type_hint := "") -> Resource:
	return ResourceLoader.load(path, type_hint, CACHE_MODE_IGNORE)


func _write_result(path: String, result: Dictionary) -> void:
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()


func _fail_result(path: String, reason: String, result := {}) -> int:
	var failure: Dictionary = result.duplicate(true)
	failure["ok"] = false
	failure["error"] = reason
	_write_result(path, failure)
	printerr("HOTFIX_PATCH_MINIMAL_VERIFY_FAIL %s" % reason)
	return 10


func _verify(base_path: String, patch_path: String, result_path: String) -> int:
	var result := {
		"ok": false,
		"method": "fresh_sandbox_resource_loader_base_then_patch_cache_mode_ignore",
		"basePath": base_path,
		"patchPath": patch_path,
		"baseLoaded": false,
		"patchLoaded": false,
		"resources": {},
		"classCache": {},
		"xp": {},
		"sfx": {},
		"effect": {},
		"music": {},
		"sourceFallback": {},
	}
	if base_path.is_empty() or patch_path.is_empty():
		return _fail_result(result_path, "pack_arguments", result)
	result["baseLoaded"] = ProjectSettings.load_resource_pack(base_path, true)
	if not bool(result["baseLoaded"]):
		return _fail_result(result_path, "base_pack_load_failed", result)
	result["patchLoaded"] = ProjectSettings.load_resource_pack(patch_path, true)
	if not bool(result["patchLoaded"]):
		return _fail_result(result_path, "patch_pack_load_failed", result)

	var source_guard_dir := _argument(OS.get_cmdline_user_args(), "--source-guard")
	if source_guard_dir.is_empty():
		return _fail_result(result_path, "source_guard_missing", result)
	var source_absent := true
	for script_path in EXPECTED_SCRIPTS:
		if FileAccess.file_exists(source_guard_dir.path_join(script_path.substr(6))):
			source_absent = false
			break
	result["sourceFallback"] = {
		"sourceGuardDir": source_guard_dir,
		"sourceScriptsAbsentOnDisk": source_absent,
		"cacheMode": "CACHE_MODE_IGNORE",
	}
	if not source_absent:
		return _fail_result(result_path, "sandbox_contains_source_fallback", result)

	var loaded_scripts := {}
	var script_failures: Array[String] = []
	for script_path in EXPECTED_SCRIPTS:
		var script := _fresh_load(script_path, "Script")
		var loaded := script != null
		loaded_scripts[script_path] = loaded
		if not loaded:
			script_failures.append(script_path)
	result["resources"] = {
		"scripts": loaded_scripts,
		"scriptFailures": script_failures,
	}
	if not script_failures.is_empty():
		return _fail_result(result_path, "compiled_script_load_failed", result)

	var cache_text := FileAccess.get_file_as_string(
		"res://.godot/global_script_class_cache.cfg"
	)
	var cache_class_count := cache_text.count("\"class\": &\"")
	result["classCache"] = {
		"loaded": not cache_text.is_empty(),
		"classCount": cache_class_count,
		"expectedClassCount": EXPECTED_CLASS_CACHE_COUNT,
		"hasTownMusicController": cache_text.contains(
			"\"class\": &\"TownMusicController\""
		),
		"hasUILevelUpPreview": cache_text.contains(
			"\"class\": &\"UILevelUpPreview\""
		),
		"townPath": cache_text.contains(
			"\"path\": \"res://scripts/town_music_controller.gd\""
		),
		"levelUpPath": cache_text.contains(
			"\"path\": \"res://scripts/ui_level_up_preview.gd\""
		),
	}
	if (
		cache_class_count != EXPECTED_CLASS_CACHE_COUNT
		or not bool(result["classCache"]["hasTownMusicController"])
		or not bool(result["classCache"]["hasUILevelUpPreview"])
	):
		return _fail_result(result_path, "class_cache_contract_failed", result)

	var remap_results := {}
	for remap_path in EXPECTED_REMAPS:
		remap_results[remap_path] = FileAccess.file_exists(remap_path)
	result["resources"]["remaps"] = remap_results
	for remap_path in EXPECTED_REMAPS:
		if not bool(remap_results[remap_path]):
			return _fail_result(result_path, "remap_missing", result)

	var ui_script := _fresh_load("res://scripts/ui_level_up_preview.gd", "Script")
	var ui_constants: Dictionary = ui_script.get_script_constant_map()
	var flame_scale := float(ui_constants.get("FLAME_SIZE_SCALE", -1.0))
	result["effect"] = {
		"flameSizeScale": flame_scale,
		"expectedFlameSizeScale": EXPECTED_FLAME_SIZE_SCALE,
		"constantVerified": is_equal_approx(flame_scale, EXPECTED_FLAME_SIZE_SCALE),
	}
	if not bool(result["effect"]["constantVerified"]):
		return _fail_result(result_path, "level_up_effect_scale_failed", result)

	# The sandbox declares the production autoload names, while its first
	# bootstrap autoload mounts base then patch before any of those scripts are
	# instantiated.  Use that real GameData autoload rather than a fabricated
	# singleton: this proves the compiled PlayerState bytecode resolves the
	# project's actual global service contract.
	var game_data: Node = get_root().get_node_or_null("GameData") as Node
	if game_data == null:
		return _fail_result(result_path, "service_reference_autoload_missing", result)
	if not bool(game_data.ensure_loaded()):
		return _fail_result(result_path, "service_reference_load_failed", result)
	var player_state_script: Script = _fresh_load("res://scripts/player_state.gd", "Script") as Script
	if player_state_script == null:
		return _fail_result(result_path, "player_state_load_failed", result)
	var player_state: Node = get_root().get_node_or_null("PlayerState") as Node
	if player_state == null:
		return _fail_result(result_path, "player_state_autoload_missing", result)
	player_state.level = 1
	var source_xp := int(game_data.service_exp_to_next_level(1))
	var gameplay_threshold := int(player_state.experience_to_next_level())
	var scale_constants: Dictionary = player_state_script.get_script_constant_map()
	var threshold_scale := float(scale_constants.get("GAMEPLAY_EXPERIENCE_THRESHOLD_SCALE", -1.0))
	var threshold_minimum := int(scale_constants.get("GAMEPLAY_EXPERIENCE_THRESHOLD_MINIMUM", -1))
	result["xp"] = {
		"sourceLevel1": source_xp,
		"gameplayThresholdLevel1": gameplay_threshold,
		"expectedSourceLevel1": EXPECTED_XP_SOURCE_LEVEL_1,
		"expectedGameplayThresholdLevel1": EXPECTED_XP_THRESHOLD_LEVEL_1,
		"thresholdScale": threshold_scale,
		"thresholdMinimum": threshold_minimum,
		"serviceTableUnchangedProof": source_xp == EXPECTED_XP_SOURCE_LEVEL_1,
		"scaledThresholdProof": gameplay_threshold == EXPECTED_XP_THRESHOLD_LEVEL_1,
		"scaleConstantProof": is_equal_approx(threshold_scale, 0.10),
		"minimumConstantProof": threshold_minimum == 1,
	}
	if (
		not bool(result["xp"]["serviceTableUnchangedProof"])
		or not bool(result["xp"]["scaledThresholdProof"])
		or not bool(result["xp"]["scaleConstantProof"])
		or not bool(result["xp"]["minimumConstantProof"])
	):
		return _fail_result(result_path, "xp_threshold_contract_failed", result)

	var music_stream := _fresh_load(
		"res://assets/audio/town/main_city_bgm.ogg",
		"AudioStream",
	) as AudioStream
	var music_length: float = music_stream.get_length() if music_stream != null else -1.0
	var source_record: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://assets/audio/town/main_city_bgm.source.json"
		)
	)
	result["music"] = {
		"streamLoaded": music_stream != null,
		"lengthSeconds": music_length,
		"expectedLengthSeconds": EXPECTED_MUSIC_LENGTH_SECONDS,
		"lengthVerified": music_stream != null and absf(music_length - EXPECTED_MUSIC_LENGTH_SECONDS) <= MUSIC_LENGTH_TOLERANCE_SECONDS,
		"sourceRecordLoaded": source_record is Dictionary,
		"sourceRecordDurationSeconds": float((source_record as Dictionary).get("runtimeDurationSeconds", -1.0)) if source_record is Dictionary else -1.0,
	}
	if not bool(result["music"]["lengthVerified"]) or not bool(result["music"]["sourceRecordLoaded"]):
		return _fail_result(result_path, "town_music_contract_failed", result)

	var player_visual_script: Script = _fresh_load(
		"res://scripts/player_visual.gd",
		"Script",
	) as Script
	var player_visual_constants: Dictionary = player_visual_script.get_script_constant_map()
	var skill_audio_enabled := bool(
		player_visual_constants.get("SKILL_AUDIO_ENABLED", true)
	)
	# The base pack keeps the imported SFX stream available.  The hotfix only
	# proves the actor-level playback gate is false; it must not delete the
	# existing stream or import metadata.
	var representative_sfx_path := "res://assets/audio/warrior/51.wav"
	var representative_sfx := _fresh_load(representative_sfx_path, "AudioStream")
	result["sfx"] = {
		"representativePath": representative_sfx_path,
		"representativeBaseStreamLoaded": representative_sfx != null,
		"skillAudioEnabled": skill_audio_enabled,
		"skillAudioGateVerifiedFalse": not skill_audio_enabled,
	}
	if (
		not bool(result["sfx"]["representativeBaseStreamLoaded"])
		or not bool(result["sfx"]["skillAudioGateVerifiedFalse"])
	):
		return _fail_result(result_path, "sfx_gate_contract_failed", result)

	result["ok"] = true
	_write_result(result_path, result)
	print("HOTFIX_PATCH_MINIMAL_VERIFY_PASS " + JSON.stringify(result))
	return 0
