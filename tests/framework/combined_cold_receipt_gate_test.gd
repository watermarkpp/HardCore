extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const EXPECTED_PATH := "res://outputs/test_logs/framework/combined_effect_lifecycle_expected.json"
const PRODUCER_PATH := "res://outputs/test_logs/framework/combined_effect_lifecycle_test.result.json"
const HANDOFF_PATH := "res://outputs/test_logs/framework/native_handoffs.json"
var proof := Proof.new()
var failures: Array[String] = []
class ColdProbe extends "res://tests/framework/combined_effect_lifecycle_cold_test.gd":
	var completed := false
	func _ready() -> void: pass
	func _finish() -> void: completed = true
class LiveProofProbe extends "res://tests/framework/combined_effect_lifecycle_test.gd":
	func _ready() -> void: pass

func check(value: bool, label: String) -> void:
	proof.record(value,label)
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	check(not PlayerState.test_mode,"real persistence enabled inside dedicated prelaunch APPDATA")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"startup gate completed")
	check(PlayerState.create_character("冷启动回执门禁","hc.profession.wizard").is_empty(),"real disposable profile created")
	check(PlayerState.save_game(true,true,true),"real profile persisted before evidence failure")
	var saved_files := {}
	for path: String in [EXPECTED_PATH,PRODUCER_PATH,HANDOFF_PATH]:
		saved_files[path] = {"exists":FileAccess.file_exists(path),"bytes":FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}
	var expected := {"profile_id":PlayerState.active_profile_id,"experience":PlayerState.experience,
		"generation":PlayerState._world_clock_generation,"producer_run_id":"gate-fixture-producer",
		"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID")}
	var profile_path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var profile_sha := FileAccess.get_sha256(profile_path)
	for scenario: String in ["current_failed","old_invocation","wrong_run","wrong_source","wrong_scene",
		"same_consumer_run","missing_receipt","truncated_receipt","failed_count","missing_handoff",
		"native_failed","native_not_exited","handoff_wrong_run","handoff_wrong_source","handoff_wrong_scene","handoff_wrong_hash"]:
		var e := expected.duplicate(true)
		var producer := {"schema_version":1,"status":"PASS","run_id":e.producer_run_id,"scene_id":"combined_effect_lifecycle_test",
			"source_content_sha256":e.source_content_sha256,"invocation_id":e.invocation_id,
			"count":1,"passed":1,"failed":0,"reported_checks":1,"reported_failures":0,
			"checks":[{"id":1,"label":"owned fixture evidence","passed":true}]}
		if scenario == "current_failed":
			producer.status = "FAIL"; producer.passed = 0; producer.failed = 1; producer.reported_failures = 1
			producer.checks[0].passed = false
		elif scenario == "old_invocation":
			e.invocation_id = "previous-native-invocation"; producer.invocation_id = e.invocation_id
		elif scenario == "wrong_run": producer.run_id = "different-current-producer"
		elif scenario == "wrong_source": producer.source_content_sha256 = "different-source"
		elif scenario == "wrong_scene": producer.scene_id = "different_scene"
		elif scenario == "same_consumer_run":
			e.producer_run_id = OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"); producer.run_id = e.producer_run_id
		elif scenario == "failed_count": producer.failed = 1
		_write(EXPECTED_PATH,e); _write(PRODUCER_PATH,producer)
		var entry := {"scene_id":"combined_effect_lifecycle_test","run_id":e.producer_run_id,
			"source_content_sha256":e.source_content_sha256,"process_exited":true,"effective_exit_code":0,
			"result":"PASS","receipt_sha256":FileAccess.get_sha256(PRODUCER_PATH)}
		var handoff := {"schema_version":1,"invocation_id":e.invocation_id,"source_content_sha256":e.source_content_sha256,
			"producers":{"combined_effect_lifecycle_test":entry}}
		if scenario == "native_failed": entry.effective_exit_code = 1; entry.result = "FAIL"
		elif scenario == "native_not_exited": entry.process_exited = false
		elif scenario == "handoff_wrong_run": entry.run_id = "old-successful-producer"
		elif scenario == "handoff_wrong_source": entry.source_content_sha256 = "different-source"
		elif scenario == "handoff_wrong_scene": entry.scene_id = "different_scene"
		elif scenario == "handoff_wrong_hash": entry.receipt_sha256 = "different-receipt"
		_write(HANDOFF_PATH,handoff)
		if scenario == "missing_receipt": DirAccess.remove_absolute(ProjectSettings.globalize_path(PRODUCER_PATH))
		elif scenario == "truncated_receipt":
			var truncated := FileAccess.open(PRODUCER_PATH,FileAccess.WRITE)
			truncated.store_string("{\"status\":\"PASS\""); truncated.close()
		elif scenario == "missing_handoff": DirAccess.remove_absolute(ProjectSettings.globalize_path(HANDOFF_PATH))
		PlayerState.experience = 733
		var probe := ColdProbe.new()
		probe._run()
		check(probe.completed and not probe.failures.is_empty(),"actual cold entry rejects stale or failed producer before recovery: "+scenario)
		check(PlayerState.experience == 733 and FileAccess.get_sha256(profile_path) == profile_sha,
			"rejected evidence cannot select a profile or mutate its in-memory/durable state: "+scenario)
		probe.free()
	# Exercise the actual evidence writer against an owned directory: opening
	# it as a file must fail and cannot turn an older expectation into success.
	var before_write := FileAccess.get_file_as_bytes(EXPECTED_PATH)
	var blocked_output := "user://combined-owned-evidence-write-failure"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked_output)) == OK,"owned evidence-write fault directory exists")
	var live_probe := LiveProofProbe.new()
	live_probe._write(blocked_output,expected)
	check(live_probe.failures.size() == 1 and not live_probe.proof.records[0].passed
		and FileAccess.get_file_as_bytes(EXPECTED_PATH) == before_write,"actual evidence write failure is recorded and never promotes an older expectation")
	live_probe.free()
	for path: String in saved_files:
		if saved_files[path].exists:
			var file := FileAccess.open(path,FileAccess.WRITE)
			file.store_buffer(saved_files[path].bytes); file.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	PlayerState.test_mode = true
	proof.write_receipt("combined_cold_receipt_gate_test",proof.records.size(),failures.size())
	print("COMBINED_COLD_RECEIPT_GATE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",proof.records.size(),str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _write(path: String,value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()
