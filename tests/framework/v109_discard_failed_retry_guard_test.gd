extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

const ROOT := "user://b16_discard_retry_guard"
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
	PlayerState.active_profile_id = "b16_discard_retry"
	PlayerState.character_name = "丢弃失败重试合同"
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.inventory = [{"name": "疾风药水", "count": 3, "instance_id": "b16-discard-target"}]
	PlayerState.recalculate_stats(false)
	PlayerState.test_mode = false
	check(PlayerState.save_game(), "baseline profile is durably saved")
	var profile_path := PlayerState._profile_path(PlayerState.active_profile_id)
	var disk_before := FileAccess.get_file_as_string(profile_path)

	# Queue a real item snapshot, then make its explicit retry fail. This is
	# the same accepted-save owner used by normal item transactions.
	check(PlayerState._queue_character_snapshot_save(), "official item save is accepted")
	PlayerState.test_mode = true
	PlayerState._save_blocked_profile_id = PlayerState.active_profile_id
	PlayerState._before_state_transaction()
	check(bool(PlayerState._item_save_failed), "failed item-save retry is retained")
	check(PlayerState._item_save_revision > PlayerState._item_saved_revision,
		"failed item-save revision remains outstanding")

	# Remove the injected fault to distinguish the guard from a second write
	# failure. The discard must still refuse while the earlier revision is not
	# durable, preserving both memory and the disk document.
	PlayerState._test_force_atomic_write_failure = false
	var memory_before: Array = PlayerState.inventory.duplicate(true)
	var result: Dictionary = PlayerState.destroy_inventory_indices([0])
	check(not bool(result.get("success", false)) and str(result.get("reason", "")) == "save_failed",
		"discard rejects after failed prior save retry")
	check(PlayerState.inventory == memory_before, "discard guard preserves in-memory inventory")
	check(FileAccess.get_file_as_string(profile_path) == disk_before,
		"discard guard preserves the durable profile")

	# Clear the block and complete the same outstanding revision through the
	# formal background owner. A recovered revision may then be discarded, and
	# this final operation must be visible in the real profile bytes.
	PlayerState._save_blocked_profile_id = ""
	PlayerState.test_mode = false
	check(PlayerState._start_item_save(true), "failed item save can be recovered by its owner")
	PlayerState._json_persistence.drain()
	check(not PlayerState._item_save_failed and PlayerState._item_save_revision <= PlayerState._item_saved_revision,
		"recovered item revision is durably closed")
	var recovered: Dictionary = PlayerState.destroy_inventory_indices([0])
	check(bool(recovered.get("success", false)) and int(recovered.get("destroyed", 0)) == 1,
		"discard succeeds after the prior revision is durable")
	var disk_after := FileAccess.get_file_as_string(profile_path)
	check(disk_after != disk_before, "successful discard changes the real profile bytes")
	var persisted_after: Dictionary = PlayerState._read_json(profile_path)
	var target_present := false
	for raw: Variant in persisted_after.get("inventory", []):
		if raw is Dictionary and str((raw as Dictionary).get("instance_id", "")) == "b16-discard-target":
			target_present = true
	check(not target_present, "successful discard removes the target from the real profile")
	PlayerState.load_save()
	var reloaded_target_present := false
	for raw: Variant in PlayerState.inventory:
		if raw is Dictionary and str((raw as Dictionary).get("instance_id", "")) == "b16-discard-target":
			reloaded_target_present = true
	check(not reloaded_target_present, "successful discard survives real reload")
	PlayerState._save_blocked_profile_id = ""

	PlayerState.test_mode = true
	var valid := proof.write_receipt("v109_discard_failed_retry_guard_test", checks, failures.size())
	if not valid:
		failures.append("receipt failed")
	print("V109_DISCARD_FAILED_RETRY_GUARD_", "PASS" if valid and failures.is_empty() else "FAIL",
		" checks=", checks, " failures=", failures)
	get_tree().quit(0 if valid and failures.is_empty() else 1)
