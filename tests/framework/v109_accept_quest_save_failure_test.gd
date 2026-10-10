extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

const ROOT := "user://b16_accept_quest_save_failure"
const QUEST_ID := "bich_beginner_gear"
var proof := Proof.new()
var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.profile_directory = ROOT.path_join("characters")
	PlayerState.profile_index_path = ROOT.path_join("profiles.json")
	PlayerState.shared_warehouse_path = ROOT.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = ROOT.path_join("shared.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "b16_accept_quest"
	PlayerState.character_name = "接受任务存档合同"
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.quest_states = {}
	PlayerState.recalculate_stats(false)
	PlayerState.test_mode = false
	check(PlayerState.save_game(), "baseline profile is durably saved")
	var profile_path := PlayerState._profile_path(PlayerState.active_profile_id)
	var disk_before := FileAccess.get_file_as_string(profile_path)
	var notifications := [0]
	var on_quests_changed := func() -> void: notifications[0] += 1
	PlayerState.quests_changed.connect(on_quests_changed)

	# Existing synchronous test seam forces the real accept transaction's save
	# barrier to fail; the failed attempt must roll back state and notification.
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = true
	var failed_message := PlayerState.accept_quest(QUEST_ID)
	check("存档失败" in failed_message, "failed accept reports save failure")
	check(not PlayerState.quest_states.has(QUEST_ID), "failed accept restores quest state")
	check(not notifications[0], "failed accept emits no quest notification")
	check(FileAccess.get_file_as_string(profile_path) == disk_before,
		"failed accept leaves durable profile unchanged")

	# Clear the fault and use the same official entry point. This must publish
	# exactly once after a real profile write and survive a reload.
	PlayerState._test_force_atomic_write_failure = false
	PlayerState.test_mode = false
	var accepted_message := PlayerState.accept_quest(QUEST_ID)
	check(accepted_message.begins_with("已接受任务"), "successful accept reports acceptance")
	check(str(PlayerState.quest_states.get(QUEST_ID, {}).get("status", "")) == "active",
		"successful accept publishes active state")
	check(notifications[0] == 1, "successful accept emits exactly once")
	var disk_after := FileAccess.get_file_as_string(profile_path)
	check(disk_after != disk_before, "successful accept changes the real profile bytes")
	PlayerState.load_save()
	check(str(PlayerState.quest_states.get(QUEST_ID, {}).get("status", "")) == "active",
		"successful accept survives real reload")

	PlayerState.quests_changed.disconnect(on_quests_changed)
	PlayerState.test_mode = true
	var valid := proof.write_receipt("v109_accept_quest_save_failure_test", checks, failures.size())
	if not valid:
		failures.append("receipt failed")
	print("V109_ACCEPT_QUEST_SAVE_FAILURE_", "PASS" if valid and failures.is_empty() else "FAIL",
		" checks=", checks, " failures=", failures)
	get_tree().quit(0 if valid and failures.is_empty() else 1)
