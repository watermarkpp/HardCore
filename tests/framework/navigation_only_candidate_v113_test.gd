extends Node

## Rebuilding navigation must never reproject released spawn/ground data.
const Build := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const Codec := preload("res://scripts/map_editor/map_editor_json_codec.gd")
const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "navigation_only_candidate_v113_test"
const SOURCE := "res://map_editor_workspace/hidden_abyss_domain/hidden_abyss_domain.editor.json"
const BASELINE := "res://assets/data/runtime/map_editor/hidden_abyss_domain.runtime.json"
var proof := Proof.new()
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value: failures.append(label)

func run() -> void:
	var service := Build.new()
	check(service.has_method("build_navigation_candidate"), "formal navigation-only candidate API exists")
	if not service.has_method("build_navigation_candidate"):
		finish()
		return
	var source_sha := FileAccess.get_sha256(SOURCE)
	var baseline_sha := FileAccess.get_sha256(BASELINE)
	var before: Dictionary = Codec.decode(FileAccess.get_file_as_string(BASELINE))
	var candidate: Dictionary = service.call("build_navigation_candidate", SOURCE, source_sha, BASELINE, baseline_sha)
	check(bool(candidate.get("ok", false)), "formal exact-source navigation candidate builds: " + str(candidate.get("errors", [])))
	if bool(candidate.get("ok", false)):
		var roundtrip: Dictionary = Codec.decode(FileAccess.get_file_as_string(str(candidate.candidate_path)))
		check(_without_navigation(roundtrip) == _without_navigation(before), "all released nonnavigation fields survive byte-codec projection unchanged")
		check(roundtrip.semantics == before.semantics, "all published spawn and respawn fields preserved")
		check(roundtrip.source == before.source, "released source binding preserved")
		check(service.has_method("validate_navigation_candidate_binding"), "formal navigation provenance guard exists")
		if service.has_method("validate_navigation_candidate_binding"):
			var valid: Dictionary = service.call("validate_navigation_candidate_binding", roundtrip, BASELINE, SOURCE)
			check(bool(valid.get("ok", false)), "serialized candidate validates against exact released baseline and saved authoring")
			var changed: Dictionary = roundtrip.duplicate(true)
			changed.semantics.boss_spawn[0].respawn_seconds = -4321.0
			var rejected: Dictionary = service.call("validate_navigation_candidate_binding", changed, BASELINE, SOURCE)
			check(not bool(rejected.get("ok", true)), "publication provenance guard rejects altered released respawn fields")
			changed = roundtrip.duplicate(true)
			changed.collision.navigation.clearance_gu = 0.0
			rejected = service.call("validate_navigation_candidate_binding", changed, BASELINE, SOURCE)
			check(not bool(rejected.get("ok", true)), "publication provenance guard rejects changed navigation payload fingerprint")
			var promoted_path := "user://navigation_candidate_already_promoted.runtime.json"
			_write(promoted_path, roundtrip)
			var recovered: Dictionary = service.call("validate_navigation_candidate_binding", roundtrip, promoted_path, SOURCE)
			check(bool(recovered.get("ok", false)) and bool(recovered.get("already_promoted", false)), "byte-identical promoted candidate remains eligible for formal transaction recovery")
	var stale_base: Dictionary = service.call("build_navigation_candidate", SOURCE, source_sha, BASELINE, "0".repeat(64))
	check(not bool(stale_base.get("ok", true)) and str(stale_base.get("reason", "")) == "navigation_baseline_changed", "stale baseline byte hash rejected before generating candidate")
	var source_doc: Dictionary = Codec.decode(FileAccess.get_file_as_string(SOURCE))
	var scratch_source := "user://navigation_candidate_mutated_source.editor.json"
	var mutated: Dictionary = source_doc.duplicate(true)
	var mutated_polygons := 0
	var mutated_points := 0
	for polygon: Dictionary in mutated.layers.collision:
		if str(polygon.get("collision_id", "")) == "poly_000008":
			mutated_polygons += 1
			for point: Array in polygon.data.points:
				point[0] = float(point[0]) + 0.25
				mutated_points += 1
	check(mutated_polygons == 1 and mutated_points == 7, "fixture moves exactly the saved central-stone polygon and all seven vertices")
	var original_geometry := Author.prepare(source_doc)
	var mutated_geometry := Author.prepare(mutated)
	check(bool(original_geometry.ok) and bool(mutated_geometry.ok) and original_geometry.entries != mutated_geometry.entries and original_geometry.parts != mutated_geometry.parts, "fixture remains valid and changes real authored polygon and convex collision projection")
	_write(scratch_source, mutated)
	var stale_source: Dictionary = service.call("build_navigation_candidate", scratch_source, source_sha, BASELINE, baseline_sha)
	check(not bool(stale_source.get("ok", true)) and str(stale_source.get("reason", "")) == "navigation_authoring_source_changed", "changed saved source bytes reject stale authoring hash")
	var geometry: Dictionary = service.call("build_navigation_candidate", scratch_source, FileAccess.get_sha256(scratch_source), BASELINE, baseline_sha)
	print("NAVIGATION_CHANGED_AUTHORING_RESULT ", JSON.stringify({"ok": geometry.get("ok", false), "reason": geometry.get("reason", ""), "errors": geometry.get("errors", [])}))
	check(not bool(geometry.get("ok", true)) and str(geometry.get("reason", "")) == "navigation_authoring_collision_mismatch", "validly hashed but changed authoring obstacle cannot ride along with navigation")
	if bool(candidate.get("ok", false)) and service.has_method("validate_navigation_candidate_binding"):
		var roundtrip: Dictionary = Codec.decode(FileAccess.get_file_as_string(str(candidate.candidate_path)))
		var stale: Dictionary = service.call("validate_navigation_candidate_binding", roundtrip, BASELINE, scratch_source)
		check(not bool(stale.get("ok", true)), "source mutation after candidate build rejected at publication boundary")
		var scratch_base := "user://navigation_candidate_mutated_baseline.runtime.json"
		var altered_base: Dictionary = before.duplicate(true)
		altered_base.semantics.boss_spawn[0].count = 2.0
		_write(scratch_base, altered_base)
		stale = service.call("validate_navigation_candidate_binding", roundtrip, scratch_base, SOURCE)
		check(not bool(stale.get("ok", true)), "baseline mutation after candidate build rejected at publication boundary")
	if bool(candidate.get("ok", false)):
		_test_missing_formal_recovery(candidate)
	check(FileAccess.get_sha256(SOURCE) == source_sha, "real authoring bytes preserved")
	check(FileAccess.get_sha256(BASELINE) == baseline_sha, "real released runtime bytes preserved")
	finish()

func _test_missing_formal_recovery(candidate: Dictionary) -> void:
	# Only copies under this invocation's isolated user:// directory are moved.
	# Existing seams redirect both publication and formal readiness checks.
	var root := "user://navigation_missing_formal_%d/" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var key := "hidden_abyss_domain"
	var formal := root + key + ".runtime.json"
	var backup := formal + ".bak"
	var registry_path := root + "registry.json"
	var intent_path := registry_path + ".publish_intent.json"
	var temporary := formal + ".publish_tmp"
	_write_bytes(formal, FileAccess.get_file_as_bytes(BASELINE))
	var real_registry_sha := FileAccess.get_sha256(Build.DEFAULT_RELEASE_REGISTRY_PATH)
	var registry := Codec.decode(FileAccess.get_file_as_string(Build.DEFAULT_RELEASE_REGISTRY_PATH))
	for row: Dictionary in registry.maps:
		if int(row.runtime_map_id) == 918005:
			row.runtime_path = formal
	_write(registry_path, registry)
	Build.test_formal_runtime_root_override = root
	Bridge.test_override_release_registry_path(registry_path)
	Build.test_crash_after_runtime_promote = true
	var crashed := Build.publish_runtime_release(str(candidate.candidate_path), 918005, candidate.document_binding, registry_path, key)
	Build.test_crash_after_runtime_promote = false
	check(str(crashed.get("reason", "")) == "injected_process_crash_after_runtime_promote", "real publication seam leaves a durable navigation intent and old backup")
	if str(crashed.get("reason", "")) != "injected_process_crash_after_runtime_promote":
		print("NAVIGATION_RECOVERY_SETUP_RESULT ", JSON.stringify(crashed))
		_reset_recovery_seams()
		return
	# The intent is still phase=prepared, as at the earlier rename boundary.
	# Move the scratch promoted candidate back to its validated temp location
	# to reproduce formal -> .bak completed, temp -> formal not yet executed.
	var moved := DirAccess.rename_absolute(ProjectSettings.globalize_path(formal), ProjectSettings.globalize_path(temporary))
	check(moved == OK and not FileAccess.file_exists(formal) and FileAccess.get_sha256(backup) == FileAccess.get_sha256(BASELINE), "fixture reaches missing formal with exact old backup and validated candidate temp")
	var intent_bytes := FileAccess.get_file_as_bytes(intent_path)
	var intent := Codec.decode(intent_bytes.get_string_from_utf8())
	var backup_bytes := FileAccess.get_file_as_bytes(backup)
	var paths: Array[String] = [formal, backup, temporary, registry_path, intent_path]
	var missing_intent := intent_path + ".held"
	DirAccess.rename_absolute(ProjectSettings.globalize_path(intent_path), ProjectSettings.globalize_path(missing_intent))
	var before := _file_state(paths)
	var rejected := Build.publish_runtime_release(str(candidate.candidate_path), 918005, candidate.document_binding, registry_path, key)
	check(not bool(rejected.get("success", true)) and before == _file_state(paths), "missing formal without durable intent is rejected without changing any transaction file")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(missing_intent), ProjectSettings.globalize_path(intent_path))
	for field: String in ["old_runtime_file_sha256", "new_runtime_file_sha256"]:
		var malformed := intent.duplicate(true)
		malformed[field] = "0".repeat(64)
		_write(intent_path, malformed)
		before = _file_state(paths)
		rejected = Build.publish_runtime_release(str(candidate.candidate_path), 918005, candidate.document_binding, registry_path, key)
		check(not bool(rejected.get("success", true)) and before == _file_state(paths), "mismatched durable intent %s is rejected without recovery writes" % field)
	_write_bytes(intent_path, intent_bytes)
	_write_bytes(backup, backup_bytes + "\n".to_utf8_buffer())
	before = _file_state(paths)
	rejected = Build.publish_runtime_release(str(candidate.candidate_path), 918005, candidate.document_binding, registry_path, key)
	check(not bool(rejected.get("success", true)) and before == _file_state(paths), "unknown backup bytes are rejected without recovery writes")
	_write_bytes(backup, backup_bytes)
	var recovered := Build.publish_runtime_release(str(candidate.candidate_path), 918005, candidate.document_binding, registry_path, key)
	print("NAVIGATION_MISSING_FORMAL_RECOVERY_RESULT ", JSON.stringify(recovered))
	check(bool(recovered.get("success", false)), "formal publication recovers exact old backup from durable intent then publishes navigation candidate")
	check(FileAccess.file_exists(formal) and FileAccess.get_sha256(formal) == FileAccess.get_sha256(str(candidate.candidate_path)), "recovered formal artifact is the exact validated navigation candidate")
	var final_registry := Codec.decode(FileAccess.get_file_as_string(registry_path))
	var final_approved := ""
	for row: Dictionary in final_registry.get("maps", []):
		if int(row.runtime_map_id) == 918005:
			final_approved = str(row.approved_build_sha256)
	check(final_approved == str(candidate.build_sha256) and Bridge.is_formal_playable(918005), "recovered registry and actual formal readiness approve the candidate")
	check(not FileAccess.file_exists(backup) and not FileAccess.file_exists(temporary) and not FileAccess.file_exists(intent_path), "successful recovery cleans exact transaction backup temp and intent")
	_reset_recovery_seams()
	check(FileAccess.get_sha256(Build.DEFAULT_RELEASE_REGISTRY_PATH) == real_registry_sha, "real release registry bytes preserved by isolated recovery test")

func _reset_recovery_seams() -> void:
	Build.test_crash_after_runtime_promote = false
	Build.test_formal_runtime_root_override = ""
	Bridge.reset_release_registry_override()

func _file_state(paths: Array[String]) -> Dictionary:
	var state := {}
	for path: String in paths:
		state[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	return state

func _write_bytes(path: String, value: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(value)
	file.close()

func _without_navigation(runtime: Dictionary) -> Dictionary:
	var copy := runtime.duplicate(true)
	copy.erase("build_sha256")
	copy.collision.erase("navigation")
	return copy

func _write(path: String, value: Dictionary) -> void:
	FileAccess.open(path, FileAccess.WRITE).store_string(Codec.encode(value))

func finish() -> void:
	var receipt_ok := proof.write_receipt(SCENE_ID, checks, failures.size())
	print("NAVIGATION_ONLY_CANDIDATE_V113_", "PASS" if failures.is_empty() and receipt_ok else "FAIL", " checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() and receipt_ok else 1)
