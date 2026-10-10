extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

const ROOT := "user://b16_stack_contract"
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

func _configure_isolated_storage() -> void:
	PlayerState.profile_directory = ROOT.path_join("characters")
	PlayerState.profile_index_path = ROOT.path_join("profiles.json")
	PlayerState.shared_warehouse_path = ROOT.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = ROOT.path_join("shared.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "b16_stack"
	PlayerState.character_name = "堆叠合同回归"
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.recalculate_stats(false)
	PlayerState.test_mode = false

func _stack_counts(item_name: String) -> Array[int]:
	var counts: Array[int] = []
	for raw: Variant in PlayerState.inventory:
		if raw is Dictionary and str((raw as Dictionary).get("name", "")) == item_name:
			counts.append(int((raw as Dictionary).get("count", 0)))
	return counts

func _total_counts(item_name: String) -> int:
	var total := 0
	for count: int in _stack_counts(item_name):
		total += count
	return total

func _stack_identities_match(item_name: String) -> bool:
	var expected := GameData.item_entity_id(item_name)
	for raw: Variant in PlayerState.inventory:
		if raw is Dictionary and str((raw as Dictionary).get("name", "")) == item_name:
			if GameData.item_entity_id(raw) != expected:
				return false
	return not expected.is_empty()

func _assert_saved_inventory(label: String) -> void:
	var saved: Dictionary = PlayerState._read_json(PlayerState._profile_path(PlayerState.active_profile_id))
	var saved_counts: Array[int] = []
	for raw: Variant in saved.get("inventory", []):
		if raw is Dictionary and str((raw as Dictionary).get("name", "")) == "太阳水":
			saved_counts.append(int((raw as Dictionary).get("count", 0)))
	check(saved_counts == _stack_counts("太阳水"), label)

func _run() -> void:
	_configure_isolated_storage()
	var potion := GameData.get_item_record("太阳水")
	var max_stack := int(potion.get("maxStack", potion.get("max_stack", 0)))
	check(not GameData.item_entity_id("太阳水").is_empty(), "registered 太阳水 identity is stable")
	check(max_stack == 20, "registered 太阳水 maxStack is 20")

	# Official receive path creates 20+1 in two legal receives; organize must
	# retain two legal stacks rather than creating a count-21 stack.
	var first := PlayerState.receive("太阳水", 20)
	var second := PlayerState.receive("太阳水", 1)
	check(bool(first.get("success", false)) and bool(second.get("success", false)),
		"official receive accepts 20 and 1")
	check(_stack_counts("太阳水") == [20, 1], "receive leaves a full stack and remainder")
	var organized := PlayerState.sort_inventory_deterministic()
	check(bool(organized.get("success", false)), "official auto-organize succeeds")
	check(_stack_counts("太阳水") == [20, 1], "auto-organize never merges beyond maxStack")
	check(_total_counts("太阳水") == 21, "20+1 preserves total quantity")
	check(_stack_identities_match("太阳水"), "each organized stack keeps the registered identity")
	_assert_saved_inventory("organized stack counts survive profile serialization")

	# Larger receive stays bounded and deterministic after a second organize.
	PlayerState.inventory = []
	check(bool(PlayerState.receive("太阳水", 50).get("success", false)),
		"official receive accepts a 50 item batch")
	check(_stack_counts("太阳水") == [20, 20, 10], "50 receives as three bounded stacks")
	var weight_before_50 := PlayerState.inventory_weight()
	check(bool(PlayerState.sort_inventory_deterministic().get("success", false)),
		"organize of three bounded stacks succeeds")
	check(_stack_counts("太阳水") == [20, 20, 10] and _total_counts("太阳水") == 50,
		"50 remains three bounded stacks without amount loss")
	check(PlayerState.inventory_weight() == weight_before_50,
		"organize preserves total inventory weight")
	check(_stack_identities_match("太阳水"), "each 50-item stack keeps the registered identity")

	PlayerState.inventory = []
	check(bool(PlayerState.receive("太阳水", 2).get("success", false)),
		"official receive accepts first positive partial stack")
	check(bool(PlayerState.receive("太阳水", 3).get("success", false)),
		"official receive accepts second positive partial stack")
	check(bool(PlayerState.sort_inventory_deterministic().get("success", false)),
		"organize of positive partial stacks succeeds")
	check(_stack_counts("太阳水") == [5] and _total_counts("太阳水") == 5,
		"2+3 merges to one legal stack")

	# Equipment remains independently owned and durable through organize/save;
	# it must never merge with itself or with another nonstackable instance.
	PlayerState.inventory = []
	check(bool(PlayerState.receive("木剑", 1).get("success", false)),
		"first durable equipment receive succeeds")
	check(bool(PlayerState.receive("木剑", 1).get("success", false)),
		"second durable equipment receive succeeds")
	var before_equipment: Array = PlayerState.inventory.duplicate(true)
	check(before_equipment.size() == 2, "two nonstackable equipment instances occupy two slots")
	check(str(before_equipment[0].get("instance_id", "")) != str(before_equipment[1].get("instance_id", "")),
		"equipment instance identities are independent before organize")
	var durability_before := [before_equipment[0].get("durability", null), before_equipment[1].get("durability", null)]
	check(bool(PlayerState.sort_inventory_deterministic().get("success", false)),
		"organize of durable equipment succeeds")
	check(PlayerState.inventory.size() == 2, "organize keeps both nonstackable equipment slots")
	check(str(PlayerState.inventory[0].get("instance_id", "")) != str(PlayerState.inventory[1].get("instance_id", "")),
		"organize preserves independent equipment identities")
	check([PlayerState.inventory[0].get("durability", null), PlayerState.inventory[1].get("durability", null)] == durability_before,
		"organize preserves durable equipment values")
	var saved_equipment: Dictionary = PlayerState._read_json(PlayerState._profile_path(PlayerState.active_profile_id))
	check((saved_equipment.get("inventory", []) as Array).size() == 2,
		"serialized profile keeps both equipment records")

	PlayerState.test_mode = true
	var valid := proof.write_receipt("v109_stack_contract_test", checks, failures.size())
	if not valid:
		failures.append("receipt failed")
	print("V109_STACK_CONTRACT_", "PASS" if valid and failures.is_empty() else "FAIL",
		" checks=", checks, " failures=", failures)
	get_tree().quit(0 if valid and failures.is_empty() else 1)
