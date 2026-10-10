extends Node

const SaveService := preload("res://scripts/map_editor/map_editor_save_service.gd")
const BuildService := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const AppScript := preload("res://scripts/map_editor/map_editor_app.gd")
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
	var nonce := Time.get_ticks_usec()
	var workspace := "user://b18_approval_workspace_%d/" % nonce
	var formal_root := "user://b18_approval_formal_%d/" % nonce
	var registry := "user://b18_approval_registry_%d.json" % nonce
	SaveService.test_workspace_root_override = workspace
	BuildService.test_formal_runtime_root_override = formal_root
	Bridge.test_override_release_registry_path(registry)
	var document := Fixtures.make_document("b18_approval_map", 991218, "B18 Approval Map")
	(document.design as Dictionary)["map_type"] = "outdoor_field"
	var app = AppScript.new()
	app.load_default_workspace_on_ready = false
	app.persist_last_document_path = false
	add_child(app)
	await get_tree().process_frame
	var document_path := workspace.path_join("b18_approval_map/b18_approval_map.editor.json")
	app._adopt_new_document(document, "B18 fixture", document_path)
	var saved := app._save_current_document()
	check(bool(saved.get("ok", false)), "real editor save creates durable document proof")
	check(app._document_ready_for_build_or_publish(), "saved document is admitted before approval")
	var approval := BuildService.approve_for_runtime(app.current_document)
	check(bool(approval.get("ok", false)), "runtime approval validates saved document")
	check(app._document_ready_for_build_or_publish(), "approval does not invalidate saved proof")
	var candidate := BuildService.build_candidate(app.current_document)
	check(bool(candidate.get("ok", false)), "approved document builds a real candidate")
	check(BuildService.candidate_matches_document(candidate, app.current_document), "candidate binding matches approved document")
	Fixtures.write_registry(registry, [])
	var published := BuildService.publish_runtime_release(str(candidate.get("candidate_path", "")), 991218, candidate.get("document_binding", {}), registry, "b18_approval_map")
	check(bool(published.get("success", false)), "saved approval candidate publishes successfully")
	# A subsequent unsaved edit remains outside the durable proof and cannot publish.
	app.current_document["display_name"] = "未保存编辑"
	check(not app._document_ready_for_build_or_publish(), "unsaved authoring edit rejects build and publish")
	app.current_document_path = workspace.path_join("wrong-name.editor.json")
	var failed_save := app._save_current_document()
	check(not bool(failed_save.get("ok", false)), "invalid save target is rejected")
	check(not app._document_ready_for_build_or_publish(), "failed save keeps publish gate closed")
	app.queue_free()
	await get_tree().process_frame
	SaveService.test_workspace_root_override = ""
	BuildService.test_formal_runtime_root_override = ""
	Bridge.reset_release_registry_override()
	if not proof.write_receipt("v109_map_editor_approval_lifecycle_test", checks, failures.size()): failures.append("receipt")
	print("V109_MAP_EDITOR_APPROVAL_LIFECYCLE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
