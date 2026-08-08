class_name MapEditorBuildRuntimeService
extends RefCounted

const ConnectionPolicyService := preload(
	"res://scripts/map_editor/map_editor_connection_policy_service.gd"
)
const RuntimeCollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const UnitLegacyAdapter := preload(
	"res://scripts/map_editor/map_editor_unit_legacy_adapter.gd"
)
const RuntimeMapService := preload(
	"res://scripts/map_editor/map_editor_runtime_map_service.gd"
)
const RuntimeBridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const JsonCodec := preload("res://scripts/map_editor/map_editor_json_codec.gd")

const LEGACY_RUNTIME_SCHEMA_VERSION := UnitLegacyAdapter.LEGACY_RUNTIME_SCHEMA_VERSION
const RUNTIME_SCHEMA_VERSION := UnitLegacyAdapter.RUNTIME_SCHEMA_VERSION
const RUNTIME_ROOT := "res://assets/data/runtime/map_editor/"
const DEFAULT_RELEASE_REGISTRY_PATH := (
	"res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
)
## FREEZE-P0.3R: Build Candidates are NEVER written to the formal runtime
## directory. outputs/ is gitignored and candidates are keyed by build hash.
const CANDIDATE_ROOT := "res://outputs/map_runtime_candidates/"

## FREEZE-P0.3R test/dev seams only - all false in production.
static var test_fail_runtime_promote := false
static var test_fail_registry_commit := false
static var test_fail_post_publish_verify := false
## FREEZE-P0.3R test/dev seam: redirect formal runtime promotion to a scratch
## root (e.g. user://) so tests never write the tracked formal runtime dir.
static var test_formal_runtime_root_override := ""


static func approve_for_runtime(document: Dictionary) -> Dictionary:
	var validation := validate_for_runtime(document)
	if not validation.ok:
		return validation
	var meta: Dictionary = document.get("editor_meta", {})
	meta["runtime_approved"] = true
	meta["runtime_approved_revision"] = int(meta.get("revision", 1))
	document["editor_meta"] = meta
	return {"ok": true, "validation": validation}


## FREEZE-P0.3R: Publish Runtime Release is a TRANSACTION over the formal
## runtime artifact + the Release Registry. Input is a Build Candidate file.
## Flow: load candidate -> validate -> map_key check -> prepare formal temp ->
## validate formal temp -> prepare registry -> validate registry -> promote
## formal runtime (backup A) -> commit registry -> invalidate caches ->
## post-publish verify -> success. Any failure rolls back to A + Registry A.
static func publish_runtime_release(
	candidate_runtime_path: String,
	runtime_map_id: int,
	registry_path := DEFAULT_RELEASE_REGISTRY_PATH,
	map_key_override := ""
) -> Dictionary:
	if runtime_map_id <= 0 or candidate_runtime_path.is_empty():
		return {"success": false, "reason": "invalid_publish_args"}
	var loaded := RuntimeMapService.load_runtime(candidate_runtime_path)
	if not loaded.ok:
		return {
			"success": false,
			"reason": "runtime_invalid",
			"errors": loaded.errors,
		}
	var runtime: Dictionary = loaded.runtime
	var map_key := str(runtime.get("source", {}).get("map_id", ""))
	if map_key.is_empty():
		return {"success": false, "reason": "runtime_map_key_missing"}
	if not map_key_override.is_empty() and map_key_override != map_key:
		return {"success": false, "reason": "runtime_map_key_mismatch"}
	var approved_hash := str(runtime.get("build_sha256", ""))
	if approved_hash.is_empty():
		return {"success": false, "reason": "runtime_build_hash_missing"}
	var old_registry := _read_registry(registry_path)
	var registry: Dictionary = old_registry.duplicate(true)
	var maps: Array = registry.get("maps", [])
	var previous_revision := 0
	var updated := false
	var formal_path := default_runtime_path(map_key)
	for i in range(maps.size()):
		if int(maps[i].get("runtime_map_id", -1)) == runtime_map_id:
			previous_revision = int(maps[i].get("approval_revision", 0))
			maps[i] = _release_entry(
				runtime_map_id,
				map_key,
				approved_hash,
				formal_path,
				previous_revision
			)
			updated = true
			break
	if not updated:
		maps.append(
			_release_entry(
				runtime_map_id, map_key, approved_hash, formal_path, 0
			)
		)
	registry["maps"] = maps
	var schema_errors := RuntimeBridge.validate_release_registry(registry)
	if not schema_errors.is_empty():
		return {
			"success": false,
			"reason": "invalid_release_registry",
			"errors": schema_errors,
		}
	# Promote the formal runtime artifact first (tmp -> verify -> backup -> promote).
	var promote := _promote_runtime(candidate_runtime_path, formal_path)
	if not promote.ok:
		return {
			"success": false,
			"reason": "runtime_promote_failed",
			"errors": promote.errors,
		}
	var backup_path := str(promote.get("backup_path", ""))
	# Commit the registry; on failure roll back the formal artifact.
	if test_fail_registry_commit or not _write_registry_atomic(
		registry_path, registry
	):
		_restore_runtime(formal_path, backup_path)
		return {"success": false, "reason": "registry_write_failed"}
	# Cache invalidate then post-publish verification. Publish never returns
	# success unless the published build is actually formal playable.
	RuntimeBridge.invalidate_release_registry()
	var post_ok := (
		not test_fail_post_publish_verify
		and RuntimeBridge.is_formal_playable(runtime_map_id)
		and str(
			RuntimeBridge.load_map(runtime_map_id).get("build_sha256", "")
		) == approved_hash
	)
	if not post_ok:
		_restore_runtime(formal_path, backup_path)
		_write_registry_atomic(registry_path, old_registry)
		RuntimeBridge.invalidate_release_registry()
		return {"success": false, "reason": "post_publish_verify_failed"}
	if (
		not backup_path.is_empty()
		and FileAccess.file_exists(backup_path)
	):
		DirAccess.remove_absolute(backup_path)
	return {
		"success": true,
		"runtime_map_id": runtime_map_id,
		"map_key": map_key,
		"approved_build_sha256": approved_hash,
		"release_state": "implemented_playable",
		"approval_revision": previous_revision + 1,
		"formal_playable": true,
	}


static func _release_entry(
	runtime_map_id: int,
	map_key: String,
	approved_hash: String,
	runtime_path: String,
	previous_revision: int
) -> Dictionary:
	return {
		"runtime_map_id": runtime_map_id,
		"map_key": map_key,
		"display_name": map_key,
		"runtime_path": runtime_path,
		"release_state": "implemented_playable",
		"approved_build_sha256": approved_hash,
		"approval_source": "published_via_publish_runtime_release",
		"approval_revision": previous_revision + 1,
	}


## FREEZE-P0.3R: promote a validated candidate into the formal runtime path.
## tmp -> verify -> backup old -> promote; keeps the .bak until post-publish
## verification so the caller can roll back.
static func _promote_runtime(
	candidate_path: String,
	formal_path: String
) -> Dictionary:
	var absolute_formal := _absolute_path(formal_path)
	var tmp := absolute_formal + ".publish_tmp"
	var backup := absolute_formal + ".bak"
	var candidate_file := FileAccess.open(candidate_path, FileAccess.READ)
	if candidate_file == null:
		return {"ok": false, "errors": ["candidate_open_failed"]}
	var content := candidate_file.get_as_text()
	candidate_file.close()
	var mkdir := DirAccess.make_dir_recursive_absolute(
		absolute_formal.get_base_dir()
	)
	if mkdir != OK:
		return {"ok": false, "errors": ["runtime_mkdir_failed:%d" % mkdir]}
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["formal_temp_open_failed"]}
	file.store_string(content)
	file.flush()
	file.close()
	# The formal temp must pass the full runtime validator before promotion.
	var verify := RuntimeMapService.load_runtime(tmp)
	if not verify.ok:
		DirAccess.remove_absolute(tmp)
		return {
			"ok": false,
			"errors": ["formal_temp_validation_failed", str(verify.errors)],
		}
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(absolute_formal):
		var backup_error := DirAccess.rename_absolute(
			absolute_formal, backup
		)
		if backup_error != OK:
			DirAccess.remove_absolute(tmp)
			return {
				"ok": false,
				"errors": ["formal_backup_failed:%d" % backup_error],
			}
	if test_fail_runtime_promote:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute_formal)
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "errors": ["injected_runtime_promote_failure"]}
	var promote_error := DirAccess.rename_absolute(tmp, absolute_formal)
	if promote_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute_formal)
		DirAccess.remove_absolute(tmp)
		return {
			"ok": false,
			"errors": ["formal_promote_failed:%d" % promote_error],
		}
	return {
		"ok": true,
		"backup_path": (
			backup
			if FileAccess.file_exists(backup)
			else ""
		),
	}


static func _restore_runtime(formal_path: String, backup_path: String) -> void:
	var absolute_formal := _absolute_path(formal_path)
	if (
		not backup_path.is_empty()
		and FileAccess.file_exists(backup_path)
	):
		if FileAccess.file_exists(absolute_formal):
			DirAccess.remove_absolute(absolute_formal)
		DirAccess.rename_absolute(backup_path, absolute_formal)
	elif FileAccess.file_exists(absolute_formal):
		DirAccess.remove_absolute(absolute_formal)


static func _absolute_path(path: String) -> String:
	return (
		ProjectSettings.globalize_path(path)
		if path.begins_with("res://") or path.begins_with("user://")
		else path
	)


static func _read_registry(registry_path: String) -> Dictionary:
	if FileAccess.file_exists(registry_path):
		var file := FileAccess.open(registry_path, FileAccess.READ)
		var parsed: Variant = (
			JSON.parse_string(file.get_as_text())
			if file != null
			else null
		)
		if file != null:
			file.close()
		if parsed is Dictionary:
			return parsed
	return {
		"schema_version": 1,
		"registry_contract_id": "mse.map.runtime.release.v1",
		"maps": [],
	}


static func _write_registry_atomic(
	registry_path: String,
	registry: Dictionary
) -> bool:
	var absolute_dst := (
		ProjectSettings.globalize_path(registry_path)
		if registry_path.begins_with("res://") or registry_path.begins_with("user://")
		else registry_path
	)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(
		absolute_dst.get_base_dir()
	)
	if mkdir_error != OK:
		return false
	var absolute_tmp := absolute_dst + ".tmp"
	var file := FileAccess.open(absolute_tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JsonCodec.encode(registry))
	file.flush()
	file.close()
	var verify_file := FileAccess.open(absolute_tmp, FileAccess.READ)
	var verify_ok := (
		verify_file != null
		and JSON.parse_string(verify_file.get_as_text()) is Dictionary
	)
	if verify_file != null:
		verify_file.close()
	if not verify_ok:
		DirAccess.remove_absolute(absolute_tmp)
		return false
	var backup := absolute_dst + ".bak"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(absolute_dst):
		var backup_error := DirAccess.rename_absolute(absolute_dst, backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_tmp)
			return false
	var promote_error := DirAccess.rename_absolute(absolute_tmp, absolute_dst)
	if promote_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute_dst)
		return false
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	return true


static func validate_for_runtime(document: Dictionary) -> Dictionary:
	var errors := MapEditorTypes.validate_document(document)
	var warnings: Array[String] = []
	var initialized := MapEditorGroundService.initialize(document)
	if not initialized.ok:
		errors.append_array(initialized.get("errors", []))
	else:
		if not (initialized.state.get("dirty_chunks", []) as Array).is_empty():
			errors.append("ground_dirty_chunks_must_be_baked")
		if not (initialized.manifest.get("chunks", []) as Array).all(func(chunk: Dictionary) -> bool: return str(chunk.get("state", "")) != "dirty"):
			errors.append("ground_manifest_contains_dirty_chunk")
	var seen_semantic_ids := {}
	for entry: Dictionary in MapEditorGameplaySemanticService.all_entries(document):
		var semantic_id := str(entry.get("semantic_id", ""))
		if semantic_id.is_empty() or seen_semantic_ids.has(semantic_id):
			errors.append("duplicate_or_missing_semantic_id:%s" % semantic_id)
		seen_semantic_ids[semantic_id] = true
		var tile: Array = entry.get("tile", [])
		if tile.size() != 2:
			errors.append("semantic_tile_missing:%s" % semantic_id)
		if str(entry.get("kind", "")) == "door" and str(entry.get("target_map_id", "")).strip_edges().is_empty():
			errors.append("door_target_map_required:%s" % semantic_id)
		if str(entry.get("kind", "")) == "map_exit" and str(entry.get("target_map_id", "")).strip_edges().is_empty():
			errors.append("map_exit_target_map_required:%s" % semantic_id)
	errors.append_array(
		ConnectionPolicyService.validate_document(document)
	)
	var walkability := MapEditorCollisionService.build_walkability(document)
	if int(walkability.get("walkable_count", 0)) <= 0:
		errors.append("map_has_no_walkable_tile")
	if MapEditorInstanceService.all_instances(document).filter(func(instance: Dictionary) -> bool: return not bool(instance.get("runtime_export", true))).size() > 0:
		warnings.append("non_runtime_instances_excluded")
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "walkability": walkability}


## FREEZE-P0.3R: Build Candidate. NEVER mutates the formal runtime artifact or
## the Release Registry; candidates land in outputs/map_runtime_candidates/
## keyed by build hash and never enter gameplay by themselves.
static func build_candidate(document: Dictionary) -> Dictionary:
	if not bool(document.get("editor_meta", {}).get("runtime_approved", false)):
		return {"ok": false, "errors": ["runtime_approval_required"]}
	var validation := validate_for_runtime(document)
	if not validation.ok:
		return validation
	var runtime := _compile_runtime_with_hash(document, validation)
	var map_key := str(document.get("map_id", "unknown"))
	var build_hash := str(runtime.get("build_sha256", ""))
	var candidate_path := CANDIDATE_ROOT + map_key + "/" + build_hash + ".runtime.json"
	var write := _write_atomic(candidate_path, runtime)
	if not write.ok:
		return write
	return {
		"ok": true,
		"candidate_path": candidate_path,
		"map_key": map_key,
		"build_sha256": build_hash,
		"validation": validation,
		"runtime": runtime,
		"warnings": validation.warnings,
	}


static func build(document: Dictionary, output_path := "") -> Dictionary:
	## FREEZE-P0.3R: default output is the Build Candidate directory, never the
	## formal runtime path. Explicit output_path remains only for legacy dev
	## tools/tests and is never used by the production MSE flow.
	if output_path.is_empty():
		return build_candidate(document)
	if not bool(document.get("editor_meta", {}).get("runtime_approved", false)):
		return {"ok": false, "errors": ["runtime_approval_required"]}
	var validation := validate_for_runtime(document)
	if not validation.ok:
		return validation
	var runtime := _compile_runtime_with_hash(document, validation)
	var write := _write_atomic(output_path, runtime)
	if not write.ok:
		return write
	return {"ok": true, "path": output_path, "runtime": runtime, "warnings": validation.warnings}


static func _compile_runtime_with_hash(
	document: Dictionary,
	validation: Dictionary
) -> Dictionary:
	var runtime := _compile(document, validation.walkability)
	var normalized: Variant = JSON.parse_string(MapEditorJsonCodec.encode(runtime))
	if normalized is Dictionary:
		runtime = normalized
	runtime["build_sha256"] = ""
	runtime["build_sha256"] = _sha256(MapEditorJsonCodec.encode(runtime))
	return runtime


static func default_runtime_path(map_id: String) -> String:
	var root := (
		test_formal_runtime_root_override
		if not test_formal_runtime_root_override.is_empty()
		else RUNTIME_ROOT
	)
	return root + map_id + ".runtime.json"


static func _compile(document: Dictionary, walkability: Dictionary) -> Dictionary:
	var initialized := MapEditorGroundService.initialize(document)
	var state: Dictionary = initialized.state
	var semantic_layers := {}
	for layer: String in [
		"npc_points", "monster_spawn", "boss_spawn", "door_points",
		"map_entrance_points", "map_exit_points", "respawn_points",
		"safe_area", "light", "region_trigger",
	]:
		var runtime_entries:Array=[]
		for source_entry:Dictionary in document.layers.get(layer,[]):
			var entry:=UnitLegacyAdapter.editor_semantic_to_runtime_v2(source_entry)
			for editor_key:String in ["placeholder_instance_id","editor_visual_asset_id","editor_visual_only","selection_shape","selectable","movable"]:entry.erase(editor_key)
			runtime_entries.append(entry)
		semantic_layers[layer] = runtime_entries
	var instances: Array = []
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if bool(instance.get("runtime_export", true)):
			instances.append(instance.duplicate(true))
	var blocked: Array = walkability.get("blocked_tiles", {}).keys()
	blocked.sort()
	var output := {
		"runtime_schema_version": RUNTIME_SCHEMA_VERSION,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"projection_contract_id": GroundUnitSpaceScript.PROJECTION_CONTRACT_ID,
		"source": {"map_id": document.map_id, "editor_schema_version": document.schema_version, "revision": document.editor_meta.get("revision", 1), "content_layer": document.content_layer},
		"design": document.design.duplicate(true),
		"ground": {"ground_mode": document.ground.ground_mode, "default_fill_asset_id": document.ground.blank_fill_asset_id, "tile_overrides": MapEditorGroundService.tile_overrides(state)},
		"instances": instances,
		"collision": {
			"coordinate_contract_id": RuntimeCollisionGeometry.CONTRACT_ID,
			"physics_source_id": RuntimeCollisionGeometry.PHYSICS_SOURCE_ID,
			"blocked_tiles": blocked,
			"blocked_count": blocked.size(),
			"manual_shapes": document.layers.get("collision", []).duplicate(true),
			"erased_cells": document.layers.get("collision_erase", []).duplicate(true),
		},
		"semantics": semantic_layers,
	}
	output["build_sha256"] = ""
	return output


static func _write_atomic(path: String, value: Dictionary) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var mkdir := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if mkdir != OK:
		return {"ok": false, "errors": ["runtime_mkdir_failed:%d" % mkdir]}
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["runtime_temp_open_failed"]}
	file.store_string(MapEditorJsonCodec.encode(value))
	file.flush()
	file.close()
	var verify := FileAccess.open(temporary, FileAccess.READ)
	if verify == null:
		return {"ok": false, "errors": ["runtime_temp_verify_failed"]}
	var parsed: Variant = JSON.parse_string(verify.get_as_text())
	verify.close()
	if not parsed is Dictionary:
		return {"ok": false, "errors": ["runtime_temp_verify_failed"]}
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	var promote := DirAccess.rename_absolute(temporary, absolute)
	return {"ok": promote == OK, "path": path, "errors": [] if promote == OK else ["runtime_promote_failed:%d" % promote]}


static func _sha256(text: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(text.to_utf8_buffer())
	return hashing.finish().hex_encode()
