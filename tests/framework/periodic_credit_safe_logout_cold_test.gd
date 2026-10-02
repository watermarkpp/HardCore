extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const EXPECTED_PATH := "res://outputs/test_logs/framework/periodic_credit_safe_logout_expected.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(not PlayerState.test_mode,"new native process uses actual production persistence")
	var exists: bool = FileAccess.file_exists(EXPECTED_PATH) and FileAccess.file_exists("res://outputs/test_logs/framework/periodic_credit_safe_logout_test.result.json")
	check(exists,"cold expectation and producer receipt exist")
	if not exists: _finish(); return
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PATH))
	var producer: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://outputs/test_logs/framework/periodic_credit_safe_logout_test.result.json"))
	var valid: bool = expected is Dictionary and producer is Dictionary and producer.get("status") == "PASS" \
		and producer.get("run_id") == expected.get("producer_run_id") \
		and expected.get("source_content_sha256") == OS.get_environment("HARDCORE_R3_CONTENT_SHA256")
	check(valid,"cold expectation binds the successful live producer and this exact source set")
	if not valid: _finish(); return
	check(PlayerState.profile_directory == expected.profile_directory and PlayerState.shared_warehouse_path == expected.shared_warehouse_path,"cold process retains the same actual production storage authority")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"cold process completes official startup preflight before role selection")
	check(PlayerState.select_character(expected.profile_b),"B loaded through real profile service in independent process")
	check(PlayerState.experience == int(expected.xp_b) and PlayerState.quest_states == expected.quests_b,"cold B has neither A experience nor A quest progress")
	check(PlayerState._world_clock_generation == expected.generation_b,"cold B retains its own world-clock generation")
	check(PlayerState.select_character(expected.profile_a),"A loaded through real profile/world death-ledger recovery")
	check(PlayerState.experience == int(expected.xp_a),"cold A retains exactly one canonical periodic kill gain")
	check(int(PlayerState.quest_states.get("bich_beginner_gear",{}).get("progress",{}).get("稻草人",-1)) == 1,"cold A retains exactly one quest objective gain")
	check(PlayerState._world_clock_generation == expected.generation_a,"cold A retains its original world-clock generation")
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,"independent process has no unfinished profile/world receipt")
	print("PERIODIC_CREDIT_SAFE_LOGOUT_COLD_TRACE "+JSON.stringify({"profile_a":expected.profile_a,"profile_b":expected.profile_b,
		"xp_a":PlayerState.experience,"a_profile_sha256":FileAccess.get_sha256(PlayerState._profile_path(expected.profile_a)),
		"b_profile_sha256":FileAccess.get_sha256(PlayerState._profile_path(expected.profile_b)),"load_result":PlayerState.last_load_result}))
	_finish()
func _finish() -> void:
	if not proof.write_receipt("periodic_credit_safe_logout_cold_test",checks,failures.size()): failures.append("receipt")
	print("PERIODIC_CREDIT_SAFE_LOGOUT_COLD_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
