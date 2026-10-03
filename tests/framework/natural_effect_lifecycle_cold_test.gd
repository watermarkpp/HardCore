extends Node

const Gate := preload("res://tests/framework/helpers/native_producer_gate.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const EXPECTED := "res://outputs/test_logs/framework/natural_effect_lifecycle_expected.json"
const PRODUCER := "res://outputs/test_logs/framework/natural_effect_lifecycle_test.result.json"
@export var resource_backed := false
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(not PlayerState.test_mode,"cold process uses actual persistence")
	var expected_path := "res://outputs/test_logs/framework/feature_resource_natural_expected.json" if resource_backed else EXPECTED
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(expected_path)) if FileAccess.file_exists(expected_path) else null
	check(expected is Dictionary,"successful live producer supplied explicit expectation")
	if not expected is Dictionary: _finish(); return
	var valid := Gate.accepts(expected,"feature_resource_natural_test" if resource_backed else "natural_effect_lifecycle_test")
	check(valid,"cold expectation binds the runner-confirmed successful native producer in this invocation")
	if not valid: _finish(); return
	check(expected.source_content_sha256 == OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"cold source matches the producing test source")
	check(expected.producer_run_id != OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"independent native process has a distinct execution receipt")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"actual cold startup migration succeeds")
	check(PlayerState.select_character(expected.profile_id),"actual combined-workload profile loads")
	check(PlayerState.experience == int(expected.experience),"exact world and thirty fixture kill rewards survive native cold restart without extra credit")
	check(PlayerState._world_clock_generation == expected.generation,"cold replay retains the saved generation marker; this fixture permits the legacy empty namespace")
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,"cold replay consumes all persistence receipts")
	_finish()
func _finish() -> void:
	if not proof.write_receipt("feature_resource_natural_cold_test" if resource_backed else "natural_effect_lifecycle_cold_test",checks,failures.size()): failures.append("receipt")
	print("NATURAL_EFFECT_LIFECYCLE_COLD_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
