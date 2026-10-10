extends Node

const WarehousePanelScript := preload("res://scripts/warehouse_panel.gd")
const DropInstanceRules := preload("res://scripts/item_drop_instance_rules.gd")
const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
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
	PlayerState.test_mode = false
	assert(GameData.ensure_loaded())
	var catalog := _equipment_catalog()
	check(not catalog.is_empty(), "feedback fixture has equipment catalog")
	var panel := WarehousePanelScript.new()
	add_child(panel)
	await get_tree().process_frame
	_setup_isolated_authority()
	var pair := _distinct_instance_pair(catalog)
	check(not pair.is_empty(), "feedback fixture has same-name instances with distinct attributes")
	PlayerState.inventory = []
	PlayerState.warehouse_inventory = [pair[0], pair[1]]
	check(PlayerState.save_game(false), "feedback fixture persists profile")
	check(PlayerState._write_shared_warehouse(PlayerState.warehouse_inventory), "feedback fixture persists warehouse")
	panel.refresh()
	panel.open_panel()
	panel._select_item("stash", 0)
	var a_body := _detail_body(panel)
	panel._withdraw()
	check(panel._transfer_pending, "accepted A withdrawal remains pending")
	# A is still in flight: selecting B advances the presentation version.
	panel._select_item("stash", 0)
	panel._select_item("stash", 1)
	var b_body := _detail_body(panel)
	check(not a_body.is_empty() and not b_body.is_empty() and a_body != b_body, "B detail is instance-specific and rejects stale A body")
	while panel._transfer_pending:
		await get_tree().process_frame
	check(_feedback_state(panel.withdraw_button).is_empty(), "stale A receipt retires only its own busy feedback")
	check(_selected_id(panel) == str(pair[1].get("instance_id", "")), "B selection survives A receipt")
	check(_detail_body(panel) == b_body, "B detail remains after stale A receipt")

	# Repeat through close/reopen: old receipt must not clear a new request's state.
	var pair2 := _distinct_instance_pair(catalog, "feedback-reopen")
	PlayerState.inventory = []
	PlayerState.warehouse_inventory = [pair2[0], pair2[1]]
	check(PlayerState.save_game(false), "reopen fixture persists profile")
	check(PlayerState._write_shared_warehouse(PlayerState.warehouse_inventory), "reopen fixture persists warehouse")
	panel.refresh()
	panel.open_panel()
	panel._select_item("stash", 0)
	var c_body := _detail_body(panel)
	panel._withdraw()
	check(panel._transfer_pending, "accepted C withdrawal remains pending")
	panel.hide()
	while panel._transfer_pending:
		await get_tree().process_frame
	panel.open_panel()
	await get_tree().process_frame
	panel._select_item("stash", 1)
	check(_feedback_state(panel.withdraw_button).is_empty(), "close/reopen receipt leaves withdrawal feedback non-busy")

	panel.queue_free()
	await get_tree().process_frame
	var receipt_ok := proof.write_receipt("v109_warehouse_feedback_generation_test", checks, errors.size())
	if not receipt_ok:
		errors.append("receipt write failed")
	print(("V109_WAREHOUSE_FEEDBACK_GENERATION_PASS" if errors.is_empty() else "V109_WAREHOUSE_FEEDBACK_GENERATION_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)

func _setup_isolated_authority() -> void:
	var root := "user://v109_warehouse_feedback_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = root.path_join("shared.transaction.json")
	PlayerState.active_profile_id = "feedback-owner"
	PlayerState._shared_warehouse_initialized = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.reset_progress(false)
	var empty_shared := PlayerState._shared_warehouse_empty_document()
	empty_shared["legacy_migration"]["completed"] = true
	check(PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, empty_shared), "feedback fixture creates shared authority")
	PlayerState._shared_warehouse_initialized = true

func _equipment_catalog() -> Dictionary:
	for item: Dictionary in GameData.item_catalog:
		if str(item.get("kind", "")) == "equipment":
			return item
	return {}

func _distinct_instance_pair(catalog: Dictionary, prefix := "feedback") -> Array[Dictionary]:
	var first := DropInstanceRules.create_instance(catalog, prefix + "-a-0")
	for index in range(1, 32):
		var second := DropInstanceRules.create_instance(catalog, "%s-b-%d" % [prefix, index])
		if not first.is_empty() and not second.is_empty() and _instance_detail_key(first) != _instance_detail_key(second):
			return [first, second]
	return []

func _instance_detail_key(instance: Dictionary) -> String:
	return "%s|%s|%s|%s" % [str(instance.get("durability", "")), str(instance.get("max_durability", "")), JSON.stringify(instance.get("modifiers", [])), JSON.stringify(instance.get("affix", {}))]

func _detail_body(panel: WarehousePanel) -> String:
	if panel.item_detail_presenter == null:
		return ""
	return str(panel.item_detail_presenter.detail_label.text)

func _feedback_state(button: BaseButton) -> String:
	if button == null or not button.has_meta(GothicUIThemeScript.BUTTON_FEEDBACK_META_STATE):
		return ""
	return str(button.get_meta(GothicUIThemeScript.BUTTON_FEEDBACK_META_STATE, ""))

func _selected_id(panel: WarehousePanel) -> String:
	if panel.selected_stash_refs.size() != 1:
		return ""
	return str(panel.selected_stash_refs[0].get("instance_id", ""))
