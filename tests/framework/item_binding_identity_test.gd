extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const HUD := preload("res://scripts/hud.gd")
const Registry := preload("res://scripts/identity/entity_registry.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: errors.append(label)
func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var root := "user://item_binding_identity_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = root.path_join("shared.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory)) == OK,
		"owned isolated profile directory is created before real file tests")
	PlayerState.active_profile_id = "item-binding-identity"
	PlayerState.character_name = "物品绑定验收"
	PlayerState.add_item("太阳水", 2)
	PlayerState.add_item("金创药(小量)", 1)
	var item_id: String = GameData.item_entity_id("太阳水")
	check(not item_id.is_empty(), "actual existing potion has a typed registered identity")
	var assigned: Dictionary = PlayerState.assign_quick_item_slot(0, item_id)
	check(bool(assigned.get("ok", false)) and PlayerState.quick_item_slots[0] == item_id,
		"formal binding uses actual inventory identity instead of comparing display name")
	var before := PlayerState.quick_item_slots.duplicate()
	check(not bool(PlayerState.assign_quick_item_slot(1, "太阳水").get("ok", false)) and PlayerState.quick_item_slots == before,
		"formal assignment rejects a display name without changing another slot")
	check(PlayerState.quick_item_slot_name(0) == "太阳水", "display accessor projects the registered item name")
	var hud := HUD.new()
	hud.set_item_quick_slots(PlayerState.quick_item_slots_snapshot())
	check(hud.item_quick_slots == PlayerState.quick_item_slots, "HUD mirrors formal item identities")
	var candidates: Array = hud._item_quick_slot_candidates()
	var matched := false
	for candidate: Dictionary in candidates:
		if candidate.get("entity_id", "") == item_id:
			matched = candidate.get("item_name", "") == "太阳水" and int(candidate.count) == 2
	check(matched, "actual picker carries typed ID with independent display and count")
	PlayerState.inventory.reverse()
	var used: Dictionary = PlayerState.use_quick_item_slot(0, item_id)
	check(bool(used.get("ok", false)) and PlayerState.item_count("太阳水") == 1,
		"actual potion use resolves the same ID after inventory reordering")
	var used_count := PlayerState.item_count("太阳水")
	var mismatch: Dictionary = PlayerState.use_quick_item_slot(0, "太阳水")
	check(not bool(mismatch.get("ok", false)) and PlayerState.item_count("太阳水") == used_count,
		"display text cannot authorize a stale use request")
	var saved: Dictionary = PlayerState._prepare_character_save_payload(false).duplicate(true)
	check(saved.get("item_button_assignments", {}) == {"contract_id": "gameplay.item.quick_slots.v2", "slots": [item_id, "", "", ""]},
		"actual writer emits the versioned formal item binding contract")
	for bad_id: String in ["太阳水", "hc.item.999999", "hc.profession.wizard"]:
		var candidate := saved.duplicate(true)
		candidate.item_button_assignments = {"contract_id": "gameplay.item.quick_slots.v2", "slots": [bad_id, "", "", ""]}
		var validation: Dictionary = PlayerState._validate_profile_document_status(candidate, PlayerState.active_profile_id, false)
		check(not bool(validation.valid) and bool(validation.terminal), "unknown or cross-kind saved item binding stops aggregate recovery " + bad_id)
	var legacy := PlayerState._normalized_quick_item_slots(["太阳水", 123, null, "未知物品"])
	check(legacy == [item_id, "", "", ""], "explicit old binding migration preserves known candidates and old unbound layout semantics")
	var malformed: Array[Dictionary] = []
	for field: String in ["contract_id", "slots"]:
		var candidate := saved.duplicate(true)
		candidate.item_button_assignments[field] = 123
		malformed.append(candidate)
	var future := saved.duplicate(true)
	future.item_button_assignments.contract_id = "gameplay.item.quick_slots.v99"
	malformed.append(future)
	var projection_conflict := saved.duplicate(true)
	projection_conflict.quick_item_slots = "malformed"
	malformed.append(projection_conflict)
	for candidate: Dictionary in malformed:
		var status: Dictionary = PlayerState._validate_profile_document_status(candidate, PlayerState.active_profile_id, false)
		check(not bool(status.valid) and bool(status.terminal), "malformed or future formal item bindings reject before backup recovery")
	# Real file recovery must preserve the unsupported aggregate rather than
	# importing a valid older binding from its backup and overwriting it.
	var path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var raw := JSON.stringify(future, "  ") + "\n"
	var backup := JSON.stringify(saved, "\t") + "\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "owned primary binding fixture opens")
	if file != null:
		file.store_string(raw)
		file.close()
	file = FileAccess.open(path + ".bak", FileAccess.WRITE)
	check(file != null, "owned backup binding fixture opens")
	if file != null:
		file.store_string(backup)
		file.close()
	var inventory_before := PlayerState.inventory.duplicate(true)
	var slots_before := PlayerState.quick_item_slots.duplicate()
	PlayerState.test_mode = false
	PlayerState.load_save()
	check(not bool(PlayerState.last_load_result.get("success", false)) and PlayerState.inventory == inventory_before \
		and PlayerState.quick_item_slots == slots_before, "real future binding load preserves the live aggregate")
	check(FileAccess.get_file_as_string(path) == raw and FileAccess.get_file_as_string(path + ".bak") == backup,
		"future binding primary and older backup preserve every raw byte")
	check(PlayerState._prepare_character_save_payload(false).is_empty(), "future binding aggregate remains write locked")
	file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(saved))
		file.close()
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success", false)) and PlayerState.quick_item_slots[0] == item_id,
		"actual formal binding reload restores its sole ID owner")
	PlayerState.test_mode = true
	# A legacy display label cannot override an already available typed record.
	var index: int = PlayerState._inventory_index_by_entity_id(item_id)
	check(index >= 0, "same registered potion remains available after reload")
	if index >= 0:
		var emitted_ids: Array[String] = []
		PlayerState.consumable_requested.connect(func(entity_id: String) -> void: emitted_ids.append(entity_id))
		# add_item still accepts old name-only records at its explicit legacy
		# boundary. This separate test supplies an actual registered identity,
		# rather than pretending a renamed name-only record contains one.
		var registered := Registry.resolve(item_id)
		PlayerState.inventory[index]["item_id" if registered.kind == "item" else "service_index"] = int(registered.legacy_id)
		check(GameData.item_entity_id(PlayerState.inventory[index]) == item_id, "typed use fixture carries the exact registered catalog identity")
		PlayerState.inventory[index].name = "金创药(小量)"
		var count_before: int = PlayerState.item_count_by_entity_id(item_id)
		var identity_use: Dictionary = PlayerState.use_quick_item_slot(0, item_id)
		check(bool(identity_use.get("ok", false)) and PlayerState.item_count_by_entity_id(item_id) == count_before - 1 \
			and emitted_ids == [item_id], "typed inventory identity selects and dispatches its actual ID despite a changed display label")
	hud.free()
	if not proof.write_receipt("item_binding_identity_test", checks, errors.size()): errors.append("receipt")
	print("ITEM_BINDING_IDENTITY_%s checks=%d errors=%s" % ["PASS" if errors.is_empty() else "FAIL", checks, str(errors)])
	get_tree().quit(0 if errors.is_empty() else 1)
