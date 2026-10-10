extends Node

const WarehousePanelScript := preload("res://scripts/warehouse_panel.gd")
const DropInstanceRules := preload("res://scripts/item_drop_instance_rules.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

var proof := Proof.new()
var errors: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(GameData.ensure_loaded())
	var stack_catalog := _stack_catalog()
	check(not stack_catalog.is_empty(), "stackable non-equipment fixture exists")
	var equipment_catalog := _equipment_catalog()
	check(not equipment_catalog.is_empty(), "equipment fixture exists")
	var stack_name := str(stack_catalog.get("name", ""))
	var stack19 := {"name": stack_name, "count": 19}
	PlayerState.inventory = [stack19]
	for index in range(99):
		# Fill every slot with the same legal stackable record. This keeps the
		# owner test about slot admission/merge, without introducing equipment
		# weight or unique-instance semantics into the capacity case.
		PlayerState.inventory.append({"name": stack_name, "count": 1})
	PlayerState.warehouse_inventory = [{"name": stack_name, "count": 1}]
	var panel := WarehousePanelScript.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_panel()
	panel._select_item("stash", 0)
	check(not panel.withdraw_button.disabled, "full 100-slot bag allows a same-stack warehouse withdrawal")
	panel._withdraw()
	while panel._transfer_pending:
		await get_tree().process_frame
	check(int(PlayerState.inventory[0].get("count", 0)) == 20, "real owner merges 19 plus 1 into the existing stack")
	check(PlayerState.warehouse_inventory.is_empty(), "merged withdrawal consumes the warehouse source")

	# A real accepted A transaction must still settle, while a close/reopen and
	# new B selection advances the presentation epoch/version and survives A's
	# completion callback.
	PlayerState.inventory = []
	var item_a := DropInstanceRules.create_instance(equipment_catalog, "b20-a")
	var item_b := DropInstanceRules.create_instance(equipment_catalog, "b20-b")
	PlayerState.warehouse_inventory = [item_a, item_b]
	panel.refresh()
	panel.open_panel()
	panel._select_item("stash", 0)
	var b_id := str(item_b.get("instance_id", ""))
	panel._withdraw()
	panel.hide()
	panel.open_panel()
	panel._select_item("stash", 1)
	while panel._transfer_pending:
		await get_tree().process_frame
	var selected_ids := panel.selected_stash_refs.map(func(ref: Dictionary) -> String: return str(ref.get("instance_id", "")))
	check(b_id in selected_ids, "new B selection survives old A receipt")
	check(PlayerState.warehouse_inventory.size() == 2 and PlayerState.warehouse_inventory[0].is_empty() and str(PlayerState.warehouse_inventory[1].get("instance_id", "")) == b_id, "accepted A transfer settles exactly once")
	check(not panel._transfer_pending, "old accepted transaction releases pending state")

	# The previous eight checks intentionally cover the synchronous test-mode
	# compatibility component. Exercise the actual prepared IO owner separately
	# so the lifecycle assertions cannot pass before an async receipt exists.
	await _run_prepared_lifecycle_cases(panel, equipment_catalog)

	panel.queue_free()
	await get_tree().process_frame
	var receipt_ok := proof.write_receipt("warehouse_panel_trade_contract_20261010_test", checks, errors.size())
	if not receipt_ok:
		errors.append("receipt write failed")
	print(("FRAMEWORK_WAREHOUSE_PANEL_TRADE_CONTRACT_PASS" if errors.is_empty() else "FRAMEWORK_WAREHOUSE_PANEL_TRADE_CONTRACT_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)

func _stack_catalog() -> Dictionary:
	for item: Dictionary in GameData.item_catalog:
		if bool(item.get("stackable", false)) and str(item.get("kind", "")) != "equipment" and int(item.get("maxStack", 1)) >= 20 and float(item.get("weight", 0)) <= 0.0 and str(item.get("name", "")) == str(item.get("serviceName", item.get("name", ""))):
			return item
	return {}

func _equipment_catalog() -> Dictionary:
	for item: Dictionary in GameData.item_catalog:
		if str(item.get("kind", "")) == "equipment":
			return item
	return {}


func _run_prepared_lifecycle_cases(panel: WarehousePanel, equipment_catalog: Dictionary) -> void:
	var root := "user://b20_warehouse_async_%d" % Time.get_ticks_usec()
	panel._ui_dismiss_selection()
	panel.hide()
	PlayerState.test_mode = false
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = root.path_join("shared.transaction.json")
	PlayerState.active_profile_id = "b20-owner"
	PlayerState._shared_warehouse_initialized = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.reset_progress(false)
	var empty_shared := PlayerState._shared_warehouse_empty_document()
	empty_shared["legacy_migration"]["completed"] = true
	check(PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, empty_shared), "prepared fixture creates isolated shared authority")
	PlayerState._shared_warehouse_initialized = true
	check(PlayerState.save_game(false), "prepared fixture creates isolated profile authority")

	var item_a := DropInstanceRules.create_instance(equipment_catalog, "b20-async-a")
	var item_b := DropInstanceRules.create_instance(equipment_catalog, "b20-async-b")
	PlayerState.inventory = []
	PlayerState.warehouse_inventory = [item_a, item_b]
	check(PlayerState.save_game(false), "prepared withdraw fixture persists profile before submit")
	check(PlayerState._write_shared_warehouse(PlayerState.warehouse_inventory), "prepared withdraw fixture persists warehouse before submit")
	panel.refresh()
	panel.open_panel()
	panel._select_item("stash", 0)
	panel._withdraw()
	check(panel._transfer_pending, "prepared withdraw remains pending before async receipt")
	# Same-window reselection while the accepted receipt is still pending.
	panel._select_item("stash", 0)
	panel._select_item("stash", 1)
	var b_id := str(item_b.get("instance_id", ""))
	check(_selected_only(panel, b_id) and _detail_shows(panel, str(item_b.get("name", ""))), "prepared withdraw shows B detail during pending A receipt")
	while panel._transfer_pending:
		await get_tree().process_frame
	var selected_ids := panel.selected_stash_refs.map(func(ref: Dictionary) -> String: return str(ref.get("instance_id", "")))
	check(b_id in selected_ids, "prepared withdraw preserves B selection after A receipt")
	check(_selected_only(panel, b_id) and _detail_shows(panel, str(item_b.get("name", ""))), "prepared withdraw keeps B detail after A receipt")
	check(PlayerState.inventory.size() == 1 and str(PlayerState.inventory[0].get("instance_id", "")) == str(item_a.get("instance_id", "")), "prepared withdraw settles A once")
	check(PlayerState.warehouse_inventory.size() == 2 and PlayerState.warehouse_inventory[0].is_empty() and str(PlayerState.warehouse_inventory[1].get("instance_id", "")) == b_id, "prepared withdraw consumes A source only")
	check(not panel._transfer_pending, "prepared withdraw releases pending after receipt")

	var item_c := DropInstanceRules.create_instance(equipment_catalog, "b20-async-c")
	var item_d := DropInstanceRules.create_instance(equipment_catalog, "b20-async-d")
	PlayerState.inventory = [item_c]
	PlayerState.warehouse_inventory = [{}, item_d]
	check(PlayerState.save_game(false), "prepared deposit fixture persists profile before submit")
	check(PlayerState._write_shared_warehouse(PlayerState.warehouse_inventory), "prepared deposit fixture persists warehouse before submit")
	panel.refresh()
	panel.open_panel()
	panel._select_item("bag", 0)
	panel._deposit()
	check(panel._transfer_pending, "prepared deposit remains pending before async receipt")
	panel.hide()
	panel.open_panel()
	panel._select_item("stash", 1)
	var d_id := str(item_d.get("instance_id", ""))
	check(_selected_only(panel, d_id) and _detail_shows(panel, str(item_d.get("name", ""))), "prepared deposit shows B detail after close and reopen")
	while panel._transfer_pending:
		await get_tree().process_frame
	selected_ids = panel.selected_stash_refs.map(func(ref: Dictionary) -> String: return str(ref.get("instance_id", "")))
	check(d_id in selected_ids, "prepared deposit preserves B selection after C receipt")
	check(_selected_only(panel, d_id) and _detail_shows(panel, str(item_d.get("name", ""))), "prepared deposit keeps B detail after C receipt")
	check(PlayerState.inventory.is_empty(), "prepared deposit settles C once")
	check(PlayerState.warehouse_inventory.size() == 2 and str(PlayerState.warehouse_inventory[0].get("instance_id", "")) == str(item_c.get("instance_id", "")) and str(PlayerState.warehouse_inventory[1].get("instance_id", "")) == d_id, "prepared deposit writes C and preserves B source")
	check(not panel._transfer_pending, "prepared deposit releases pending after receipt")


func _selected_only(panel: WarehousePanel, expected_id: String) -> bool:
	if panel.selected_stash_refs.size() != 1:
		return false
	return str(panel.selected_stash_refs[0].get("instance_id", "")) == expected_id


func _detail_shows(panel: WarehousePanel, expected_name: String) -> bool:
	if panel.item_detail_presenter == null or not panel.item_detail_presenter.visible:
		return false
	var title := str(panel.item_detail_presenter.title_label.text)
	var body := str(panel.item_detail_presenter.detail_label.text)
	return not expected_name.is_empty() and title.contains(expected_name) and not body.is_empty()
