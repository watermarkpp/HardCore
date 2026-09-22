extends SceneTree

## Follow-up PCK packer/verifier.  The Python wrapper supplies the accepted
## 12-entry payload closure; this script only performs Godot PCKPacker output
## and a fresh --main-pack base + active patch ResourceLoader verification.

const HASH_CHUNK_BYTES := 64 * 1024
const CACHE_MODE_IGNORE := ResourceLoader.CACHE_MODE_IGNORE

const EXPECTED_CLASS_CACHE_COUNT := 182
const EXPECTED_XP_SOURCE_LEVEL_1 := 100
const EXPECTED_XP_THRESHOLD_LEVEL_1 := 10
const EXPECTED_DEATH_LEVEL := 7
const EXPECTED_DEATH_THRESHOLD := 120
const EXPECTED_DEATH_PENALTY := 12
const EXPECTED_VOLUME_LINEAR := 0.70
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
	"res://scripts/device_lab_runtime.gd",
]
const EXPECTED_REMAPS := [
	"res://scripts/town_music_controller.gd.remap",
	"res://scripts/ui_level_up_preview.gd.remap",
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := _argument(args, "--mode")
	if mode == "verify":
		# DeviceLabPatch mounts the active follow-up patch after the base
		# --main-pack has started.  Verify only after autoload construction.
		call_deferred("_run_deferred_verify", args)
		return
	var exit_code := 1
	if mode == "pack":
		exit_code = _pack(_argument(args, "--manifest"), _argument(args, "--pack"))
	else:
		printerr("HOTFIX_PATCH_FOLLOWUP_ERROR unknown mode")
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
		printerr("HOTFIX_PATCH_FOLLOWUP_ERROR malformed pack manifest")
		return 2
	var packer := PCKPacker.new()
	var start_error := packer.pck_start(pack_path)
	if start_error != OK:
		printerr("HOTFIX_PATCH_FOLLOWUP_ERROR pck_start=%d" % start_error)
		return 3
	var seen := {}
	var bytes_total := 0
	for raw_entry: Variant in raw_entries:
		if not raw_entry is Dictionary:
			printerr("HOTFIX_PATCH_FOLLOWUP_ERROR malformed entry")
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
			printerr("HOTFIX_PATCH_FOLLOWUP_ERROR invalid entry=%s" % resource_path)
			return 5
		var actual := _hash_file(source_path)
		if (
			not bool(actual.get("ok", false))
			or int(actual.get("bytes", -1)) != expected_bytes
			or str(actual.get("sha256", "")) != expected_sha
		):
			printerr("HOTFIX_PATCH_FOLLOWUP_ERROR source mismatch=%s" % resource_path)
			return 6
		var add_error := packer.add_file(resource_path, source_path)
		if add_error != OK:
			printerr("HOTFIX_PATCH_FOLLOWUP_ERROR add_file=%d path=%s" % [add_error, resource_path])
			return 7
		seen[resource_path] = true
		bytes_total += expected_bytes
	var flush_error := packer.flush()
	if flush_error != OK:
		printerr("HOTFIX_PATCH_FOLLOWUP_ERROR flush=%d" % flush_error)
		return 8
	print("HOTFIX_PATCH_FOLLOWUP_PACK_PASS resources=%d bytes=%d" % [seen.size(), bytes_total])
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
	printerr("HOTFIX_PATCH_FOLLOWUP_VERIFY_FAIL %s" % reason)
	return 10


func _verify(base_path: String, patch_path: String, result_path: String) -> int:
	var result := {
		"ok": false,
		"method": "fresh_main_pack_base_then_followup_active_patch_cache_mode_ignore",
		"basePath": base_path,
		"patchPath": patch_path,
		"baseLoaded": false,
		"patchLoaded": false,
		"resources": {},
		"classCache": {},
		"xp": {},
		"deathPenalty": {},
		"music": {},
		"sfx": {},
		"effect": {},
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
	var world_script := _fresh_load("res://scripts/game_root.gd", "Script") as Script
	var same_map_guard_present := false
	for method: Dictionary in world_script.get_script_method_list():
		if str(method.get("name", "")) == "_begin_monster_transition_prefetch":
			same_map_guard_present = true
	result["sameMapGuardPresent"] = same_map_guard_present
	if not same_map_guard_present:
		return _fail_result(result_path, "same_map_guard_missing", result)

	var cache_text := FileAccess.get_file_as_string("res://.godot/global_script_class_cache.cfg")
	var cache_class_count := cache_text.count("\"class\": &\"")
	result["classCache"] = {
		"loaded": not cache_text.is_empty(),
		"classCount": cache_class_count,
		"expectedClassCount": EXPECTED_CLASS_CACHE_COUNT,
		"hasTownMusicController": cache_text.contains("\"class\": &\"TownMusicController\""),
		"hasUILevelUpPreview": cache_text.contains("\"class\": &\"UILevelUpPreview\""),
		"hasDeviceLabRuntime": cache_text.contains("\"class\": &\"DeviceLabRuntime\""),
		"baselinePreservedPolicy": true,
	}
	if (
		cache_class_count != EXPECTED_CLASS_CACHE_COUNT
		or not bool(result["classCache"]["hasTownMusicController"])
		or not bool(result["classCache"]["hasUILevelUpPreview"])
		or not bool(result["classCache"]["hasDeviceLabRuntime"])
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

	var game_data: Node = get_root().get_node_or_null("GameData") as Node
	if game_data == null:
		return _fail_result(result_path, "service_reference_autoload_missing", result)
	if not bool(game_data.ensure_loaded()):
		return _fail_result(result_path, "service_reference_load_failed", result)
	var player_state_script: Script = _fresh_load("res://scripts/player_state.gd", "Script") as Script
	var player_state: Node = get_root().get_node_or_null("PlayerState") as Node
	if player_state_script == null or player_state == null:
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

	var old_test_mode := bool(player_state.test_mode)
	var old_failure := bool(player_state._test_force_atomic_write_failure)
	var old_level := int(player_state.level)
	var old_experience := int(player_state.experience)
	player_state.test_mode = true
	player_state._test_force_atomic_write_failure = false
	player_state.level = EXPECTED_DEATH_LEVEL
	var death_threshold := int(player_state.experience_to_next_level())
	var expected_death_loss := int(floor(float(death_threshold) * 0.10))
	player_state.experience = 500
	var high_lost := int(player_state.apply_death_experience_penalty())
	var high_after := int(player_state.experience)
	player_state.experience = 20
	var low_lost := int(player_state.apply_death_experience_penalty())
	var low_after := int(player_state.experience)
	player_state.experience = 0
	var zero_lost := int(player_state.apply_death_experience_penalty())
	var zero_after := int(player_state.experience)
	player_state.test_mode = old_test_mode
	player_state._test_force_atomic_write_failure = old_failure
	player_state.level = old_level
	player_state.experience = old_experience
	result["deathPenalty"] = {
		"level": EXPECTED_DEATH_LEVEL,
		"threshold": death_threshold,
		"expectedThreshold": EXPECTED_DEATH_THRESHOLD,
		"expectedLoss": expected_death_loss,
		"expectedLossConstant": EXPECTED_DEATH_PENALTY,
		"highBefore": 500,
		"highLost": high_lost,
		"highAfter": high_after,
		"lowBefore": 20,
		"lowLost": low_lost,
		"lowAfter": low_after,
		"zeroLost": zero_lost,
		"zeroAfter": zero_after,
		"sameThresholdLossProof": high_lost == expected_death_loss and low_lost == expected_death_loss,
		"noNegativeProof": zero_lost == 0 and zero_after == 0 and low_after >= 0 and high_after >= 0,
		"verified": death_threshold == EXPECTED_DEATH_THRESHOLD and expected_death_loss == EXPECTED_DEATH_PENALTY and high_lost == EXPECTED_DEATH_PENALTY and low_lost == EXPECTED_DEATH_PENALTY and high_after == 488 and low_after == 8 and zero_lost == 0 and zero_after == 0,
	}
	if not bool(result["deathPenalty"]["verified"]):
		return _fail_result(result_path, "death_penalty_contract_failed", result)

	var town_script: Script = _fresh_load("res://scripts/town_music_controller.gd", "Script") as Script
	var town_constants: Dictionary = town_script.get_script_constant_map()
	var volume_linear := float(town_constants.get("DEFAULT_VOLUME_LINEAR", -1.0))
	var music_stream := _fresh_load("res://assets/audio/town/main_city_bgm.ogg", "AudioStream") as AudioStream
	var music_length: float = music_stream.get_length() if music_stream != null else -1.0
	var source_record: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/town/main_city_bgm.source.json"))
	var source_record_duration := -1.0
	if source_record is Dictionary:
		var source_data: Variant = (source_record as Dictionary).get("source", {})
		var conversion_data: Variant = (source_record as Dictionary).get("conversion", {})
		if source_data is Dictionary:
			source_record_duration = float((source_data as Dictionary).get("durationSeconds", -1.0))
		if source_record_duration < 0.0 and conversion_data is Dictionary:
			source_record_duration = float((conversion_data as Dictionary).get("runtimeDurationSeconds", -1.0))
	result["music"] = {
		"defaultVolumeLinear": volume_linear,
		"expectedVolumeLinear": EXPECTED_VOLUME_LINEAR,
		"volumeVerified": is_equal_approx(volume_linear, EXPECTED_VOLUME_LINEAR),
		"streamLoaded": music_stream != null,
		"lengthSeconds": music_length,
		"expectedLengthSeconds": EXPECTED_MUSIC_LENGTH_SECONDS,
		"lengthVerified": music_stream != null and absf(music_length - EXPECTED_MUSIC_LENGTH_SECONDS) <= MUSIC_LENGTH_TOLERANCE_SECONDS,
		"sourceRecordLoaded": source_record is Dictionary,
		"sourceRecordDurationSeconds": source_record_duration,
	}
	if not bool(result["music"]["volumeVerified"]) or not bool(result["music"]["lengthVerified"]) or not bool(result["music"]["sourceRecordLoaded"]):
		return _fail_result(result_path, "town_music_contract_failed", result)

	var player_visual_script: Script = _fresh_load("res://scripts/player_visual.gd", "Script") as Script
	var player_visual_constants: Dictionary = player_visual_script.get_script_constant_map()
	var skill_audio_enabled := bool(player_visual_constants.get("SKILL_AUDIO_ENABLED", true))
	var representative_sfx_path := "res://assets/audio/warrior/51.wav"
	var representative_sfx := _fresh_load(representative_sfx_path, "AudioStream")
	result["sfx"] = {
		"representativePath": representative_sfx_path,
		"representativeBaseStreamLoaded": representative_sfx != null,
		"skillAudioEnabled": skill_audio_enabled,
		"skillAudioGateVerifiedFalse": not skill_audio_enabled,
	}
	if not bool(result["sfx"]["representativeBaseStreamLoaded"]) or not bool(result["sfx"]["skillAudioGateVerifiedFalse"]):
		return _fail_result(result_path, "sfx_gate_contract_failed", result)

	result["ok"] = true
	_write_result(result_path, result)
	print("HOTFIX_PATCH_FOLLOWUP_VERIFY_PASS " + JSON.stringify(result))
	return 0
