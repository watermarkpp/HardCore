extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

class SwitchAtReceipt extends "res://scripts/gameplay/profile/profile_model.gd":
	var armed := false
	var witness: Dictionary = {}
	func _record_background_json_receipt(receipt: Dictionary) -> void:
		if armed and bool(receipt.get("success", false)) and str(receipt.identity.path) == _profile_path("old_owner"):
			armed = false
			witness = {"actual_promoted": FileAccess.get_file_as_bytes(str(receipt.identity.path)) == receipt.bytes,
				"generation": _atomic_write_generation, "bytes": _validated_profile_bytes,
				"path": _validated_profile_path}
			active_profile_id = "new_owner"
			gold = 777
			inventory = []
			warehouse_inventory = []
		super._record_background_json_receipt(receipt)

class FixtureState extends "res://scripts/player_state.gd":
	func _init() -> void:
		super(SwitchAtReceipt.new())
	func _ready() -> void:
		set_process(false)

var proof = Proof.new()
var failures: Array[String] = []
var checks := 0
func _ready() -> void:
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)
func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	await _case(false)
	await _case(true)
	if not proof.write_receipt("multicore_warehouse_late_receipt_20261014", checks, failures.size()): failures.append("receipt")
	print("MULTICORE_WAREHOUSE_LATE_RECEIPT_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _case(bank: bool) -> void:
	var state := FixtureState.new()
	var model: Variant = state.profile_core_for_owner()
	var root := "user://warehouse_late_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.shared_warehouse_path = root.path_join("shared.json")
	state.shared_warehouse_transaction_log_path = root.path_join("shared.transaction.json")
	state.active_profile_id = "old_owner"
	state.test_mode = false
	add_child(state)
	state.reset_progress(false)
	state.level = 50
	state.gold = state.BANK_TRANSFER_AMOUNT * 3 if bank else 0
	state.recalculate_stats(false)
	var item := ItemDropInstanceRules.create_instance(GameData.get_item_record({"item_id":81}), "v115_warehouse_late")
	assert(not item.is_empty())
	state.inventory = [item]
	state.warehouse_inventory = []
	state._shared_warehouse_initialized = true
	var shared := {"schema_version":state.SHARED_WAREHOUSE_SCHEMA_VERSION,
		"contract_id":state.SHARED_WAREHOUSE_CONTRACT_ID,"revision":1,"warehouse_inventory":[],
		"legacy_migration":{"completed":true,"contract_id":state.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID,"sources":{}}}
	assert(state._write_json_atomic(state.shared_warehouse_path, shared))
	assert(state.save_game(false))
	model.armed = true
	var result: Dictionary
	if bank:
		result = await state.transfer_shared_gold_prepared(true, "v115_warehouse_late_bank", 1)
	else:
		result = await state.transfer_warehouse_prepared("deposit", [0], [0])
	state._json_persistence.drain()
	check(not model.witness.is_empty() and bool(model.witness.get("actual_promoted", false)), "switch occurs after the real profile file promotion before owner receipt recording")
	check(state.gold == 777 and state.inventory.is_empty() and state.warehouse_inventory.is_empty(), "old warehouse transfer does not apply to the current role")
	check(state._atomic_write_generation == int(model.witness.get("generation", -1)), "old warehouse receipt cannot advance current write generation")
	check(state._validated_profile_bytes == model.witness.get("bytes") and state._validated_profile_path == str(model.witness.get("path")), "old warehouse receipt cannot replace current validated bytes")
	check(bool(result.get("success", false)) and bool(result.get("saved", false)) and not bool(result.get("active_state_applied", true)), "public warehouse result retains irreversible durable success for its old owner")
	var disk_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state._profile_path("old_owner")))
	var disk_shared: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state.shared_warehouse_path))
	var stored := 0
	for row: Variant in disk_shared.warehouse_inventory:
		if row is Dictionary and str(row.get("instance_id", "")) == str(item.instance_id): stored += 1
	var held := 0
	for row: Variant in disk_profile.inventory:
		if row is Dictionary and str(row.get("instance_id", "")) == str(item.instance_id): held += 1
	if bank:
		check(stored == 0 and held == 1 and int(disk_shared.get("bank_gold", -1)) == state.BANK_TRANSFER_AMOUNT and int(disk_profile.gold) == state.BANK_TRANSFER_AMOUNT * 2, "real bank transfer conserves old-owner gold and preserves its complete item")
	else:
		check(stored == 1 and held == 0, "real durable warehouse and old profile contain one transferred item")
	var facts: Array[Dictionary] = state.persistence_receipt_snapshot()
	check(facts.size() == 1 and str(facts[0].identity.get("profile_id", "")) == "old_owner" and facts[0].path == state._profile_path("old_owner"), "warehouse durable fact carries its original profile identity until acknowledgement")
	check(not FileAccess.file_exists(state.shared_warehouse_transaction_log_path) and not state._warehouse_transaction_locked, "accepted warehouse barrier completes its original journal cleanup")
	state.active_profile_id = ""
	state.free()
