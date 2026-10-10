extends Node

const BuildService := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const Fixtures := preload("res://tests/helpers/map_runtime_transaction_test_fixtures.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Fixtures.reset_seams()
	var nonce := Time.get_ticks_usec()
	var map_key := "b18_cleanup_retry_map"
	var map_id := 991219
	var registry := "user://b18_cleanup_retry_registry_%d.json" % nonce
	var formal_root := "user://b18_cleanup_retry_formal_%d/" % nonce
	BuildService.test_formal_runtime_root_override = formal_root
	Bridge.test_override_release_registry_path(registry)
	var document := Fixtures.make_document(map_key, map_id, "B18 Cleanup Retry Map")
	var approval := BuildService.approve_for_runtime(document)
	check(bool(approval.get("ok", false)), "cleanup fixture approval succeeds")
	var candidate_a := BuildService.build_candidate(document)
	check(bool(candidate_a.get("ok", false)), "cleanup fixture candidate A builds")
	Fixtures.write_registry(registry, [])
	var first := BuildService.publish_runtime_release(
		str(candidate_a.get("candidate_path", "")), map_id,
		BuildService.document_binding(document), registry, map_key
	)
	check(bool(first.get("success", false)), "baseline release A succeeds")

	Fixtures.mutate_and_bake(document)
	var candidate_b := BuildService.build_candidate(document)
	check(bool(candidate_b.get("ok", false)), "cleanup fixture candidate B builds")
	var formal_path := BuildService.default_runtime_path(map_key)
	var absolute_formal := ProjectSettings.globalize_path(formal_path)
	var intent_path := ProjectSettings.globalize_path(registry) + ".publish_intent.json"
	var registry_restore_backup := ProjectSettings.globalize_path(registry) + ".restore_bak"
	BuildService.test_fail_registry_backup_cleanup = true
	BuildService.test_remove_fail_from_call = 2
	BuildService._reset_injection_counters()
	var failed_cleanup := BuildService.publish_runtime_release(
		str(candidate_b.get("candidate_path", "")), map_id,
		BuildService.document_binding(document), registry, map_key
	)
	check(not bool(failed_cleanup.get("success", false)), "cleanup failure is reported")
	check(str(failed_cleanup.get("reason", "")) == "publish_cleanup_failed", "cleanup failure has precise reason")
	check(not FileAccess.file_exists(absolute_formal + ".bak"), "formal cleanup completes before registry failure")
	check(FileAccess.file_exists(registry_restore_backup), "registry restore backup remains after failed cleanup")
	check(FileAccess.file_exists(intent_path), "publish intent remains after failed cleanup")

	# A second recovery attempt may itself fail; the intent and verified backup
	# must remain available for a later retry.
	BuildService.test_remove_fail_from_call = 1
	BuildService._reset_injection_counters()
	var retry_cleanup_failed := BuildService.publish_runtime_release(
		str(candidate_b.get("candidate_path", "")), map_id,
		BuildService.document_binding(document), registry, map_key
	)
	check(not bool(retry_cleanup_failed.get("success", false)), "recovery cleanup failure is reported")
	check(str(retry_cleanup_failed.get("reason", "")) == "publish_recovery_cleanup_failed", "recovery cleanup failure has precise reason")
	check(FileAccess.file_exists(registry_restore_backup) and FileAccess.file_exists(intent_path), "recovery failure preserves registry backup and intent")

	var verified_registry_backup := _read_bytes(registry_restore_backup)
	_write_bytes(registry_restore_backup, "wrong registry backup".to_utf8_buffer())
	BuildService.test_remove_fail_from_call = 0
	BuildService._reset_injection_counters()
	var wrong_hash := BuildService.publish_runtime_release(
		str(candidate_b.get("candidate_path", "")), map_id,
		BuildService.document_binding(document), registry, map_key
	)
	check(not bool(wrong_hash.get("success", false)), "wrong registry backup hash is rejected")
	check(str(wrong_hash.get("reason", "")) == "publish_recovery_cleanup_failed", "wrong registry backup reports cleanup failure")
	check(FileAccess.file_exists(intent_path), "wrong registry backup preserves intent")
	_write_bytes(registry_restore_backup, verified_registry_backup)
	var retried := BuildService.publish_runtime_release(
		str(candidate_b.get("candidate_path", "")), map_id,
		BuildService.document_binding(document), registry, map_key
	)
	check(bool(retried.get("success", false)), "retry completes committed pair")
	check(str(retried.get("recovered", "")) == "already_committed", "retry uses durable pair recovery")
	check(not FileAccess.file_exists(absolute_formal + ".bak"), "retry leaves no formal backup")
	check(not FileAccess.file_exists(registry_restore_backup), "retry removes verified registry backup")
	check(not FileAccess.file_exists(intent_path), "retry retires intent only after cleanup")

	BuildService.test_fail_registry_backup_cleanup = false
	var idempotent := BuildService.publish_runtime_release(
		str(candidate_b.get("candidate_path", "")), map_id,
		BuildService.document_binding(document), registry, map_key
	)
	check(bool(idempotent.get("success", false)), "normal publish remains idempotent")
	check(not FileAccess.file_exists(registry_restore_backup) and not FileAccess.file_exists(intent_path), "normal publish leaves no recovery residue")

	Fixtures.reset_seams()
	BuildService.test_remove_fail_from_call = 0
	BuildService.test_fail_registry_backup_cleanup = false
	BuildService._reset_injection_counters()
	Bridge.reset_release_registry_override()
	BuildService.test_formal_runtime_root_override = ""
	if not proof.write_receipt("v109_map_editor_cleanup_retry_test", checks, failures.size()): failures.append("receipt")
	print("V109_MAP_EDITOR_CLEANUP_RETRY_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	check(file != null, "backup bytes readable")
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "backup bytes writable")
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()
