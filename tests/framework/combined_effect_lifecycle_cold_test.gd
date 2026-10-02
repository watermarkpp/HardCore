extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const EXPECTED := "res://outputs/test_logs/framework/combined_effect_lifecycle_expected.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(not PlayerState.test_mode,"cold process uses actual persistence")
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED)) if FileAccess.file_exists(EXPECTED) else null
	check(expected is Dictionary,"successful live producer supplied explicit expectation")
	if not expected is Dictionary: _finish(); return
	check(expected.source_content_sha256 == OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"cold source matches the producing test source")
	check(expected.producer_run_id != OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"independent native process has a distinct execution receipt")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"actual cold startup migration succeeds")
	check(PlayerState.select_character(expected.profile_id),"actual combined-workload profile loads")
	check(PlayerState.experience == int(expected.experience),"all thirty kill rewards survive native cold restart exactly once")
	check(PlayerState._world_clock_generation == expected.generation,"cold replay keeps the exact saved world ledger generation")
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,"cold replay consumes all persistence receipts")
	_finish()
func _finish() -> void:
	if not proof.write_receipt("combined_effect_lifecycle_cold_test",checks,failures.size()): failures.append("receipt")
	print("COMBINED_EFFECT_LIFECYCLE_COLD_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
