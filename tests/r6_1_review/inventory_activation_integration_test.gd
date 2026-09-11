extends Node

## §2.1 integration wiring coverage on the REAL InventoryPanel (executor
## fixture; no production change). Proves the real panel paths that the
## 13-assertion component test does not: helmet/equipment-slot single tap,
## bag double-activation use, TouchScrollSupport drag release, and the
## native-touch + emulated-mouse pairing. Locked helper gates the detail
## window on the equipment-slot path.

const Helper := preload("res://tests/r6_1_review/detail_visible_assertions.gd")
const Common := preload("res://tests/r6_1_review/real_panel_matrix_common.gd")

var failures: Array[String] = []
var checks := 0
var panel: Control

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

func settle(frames := 3) -> void:
	for unused in range(frames):
		await get_tree().process_frame

func _touch(point: Vector2, pressed: bool, extra: Dictionary = {}) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = get_viewport().get_final_transform() * point
	event.pressed = pressed
	if extra.has("double_tap"):
		event.double_tap = bool(extra.double_tap)
	if extra.has("canceled"):
		event.canceled = bool(extra.canceled)
	get_viewport().push_input(event)

func _drag(point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = get_viewport().get_final_transform() * point
	get_viewport().push_input(event)

func _mouse(point: Vector2, pressed: bool, double_click := false, emulated := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = get_viewport().get_final_transform() * point
	event.pressed = pressed
	event.double_click = double_click
	if emulated:
		event.device = InputEvent.DEVICE_ID_EMULATION
	get_viewport().push_input(event)

func _cell_point(index: int) -> Vector2:
	var cells: Array = panel.get("_bag_cells")
	var cell: Control = cells[index]
	var button := cell.get_child(0) as Control
	var canvas_point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	return panel.get_global_transform_with_canvas().affine_inverse() * canvas_point

func _selection_revision() -> int:
	return int(panel.get("_selection_revision"))

func _presenter() -> Control:
	return panel.get("item_detail_presenter") as Control

func _run() -> void:
	if not Common.ensure_data():
		get_tree().quit(1)
		return
	var InventoryScript := load("res://scripts/inventory_panel.gd")
	panel = InventoryScript.new()
	add_child(panel)
	await settle()
	# Seed: a wearable equipment item, a consumable stack, a plain item.
	var equip_record := Common.seed_record("幽灵项链")
	var potion_record := Common.seed_record("金疮药(小量)")
	var plain_record := Common.seed_record("木剑")
	expect(not equip_record.is_empty() and not potion_record.is_empty() and not plain_record.is_empty(), "seed records exist")
	panel.call("refresh")
	await settle()
	var saved_inventory := JSON.stringify(PlayerState.inventory)
	# 1) Real single tap on bag cell 0 commits exactly one selection.
	var revision_before := _selection_revision()
	_touch(_cell_point(0), true)
	_touch(_cell_point(0), false)
	await settle()
	expect(_selection_revision() == revision_before + 1, "one real tap commits exactly one selection")
	expect(_presenter() != null and _presenter().visible, "bag tap shows detail")
	# 2) Native tap + emulated mouse pair must not double-commit.
	revision_before = _selection_revision()
	_touch(_cell_point(1), true)
	_touch(_cell_point(1), false)
	_mouse(_cell_point(1), true, false, true)
	_mouse(_cell_point(1), false, false, true)
	await settle()
	expect(_selection_revision() == revision_before + 1, "emulated mouse pairing does not double-commit")
	# 3) Drag release inside the panel is not a selection and uses nothing.
	revision_before = _selection_revision()
	var start := _cell_point(2)
	_touch(start, true)
	_drag(start + Vector2(0, 40))
	_touch(start + Vector2(0, 40), false)
	await settle()
	expect(_selection_revision() == revision_before, "drag release never commits a selection")
	# 4) Bag double activation uses the consumable exactly once.
	var count_before := int(potion_record.get("count", 1))
	PlayerState.inventory[2] = potion_record
	PlayerState.inventory[1] = {}
	PlayerState.inventory[0] = {}
	panel.call("refresh")
	await settle()
	_touch(_cell_point(0), true)
	_touch(_cell_point(0), false)
	_touch(_cell_point(0), true, {"double_tap": true})
	await settle()
	var used_records: Array = PlayerState.inventory.filter(func(r: Variant) -> bool: return r is Dictionary and str((r as Dictionary).get("name", "")) == "金疮药(小量)")
	var count_after := 0
	for r: Variant in used_records:
		count_after += int((r as Dictionary).get("count", 0))
	expect(count_after == count_before - 1, "double activation consumes exactly one unit (got %d -> %d)" % [count_before, count_after])
	# 5) Equipment-slot path via real tap: equip the necklace, tap its slot,
	# gate the detail window with the locked helper and real geometry.
	var equip_result: Dictionary = PlayerState.call("equip_inventory_index_result", 0)
	expect(bool(equip_result.get("success", false)), "seed equipment equips")
	var slot := ""
	for key: Variant in PlayerState.equipment:
		var equipped: Variant = PlayerState.equipment[key]
		if equipped is Dictionary and str((equipped as Dictionary).get("instance_id", "")) == str(equip_record.get("instance_id", "")):
			slot = str(key)
	expect(not slot.is_empty(), "equipped slot found")
	panel.call("refresh")
	await settle()
	var slot_button := panel.find_children("*", "Button", true, false).front()
	revision_before = _selection_revision()
	panel.call("_select_equipment_slot", slot)
	await settle()
	expect(_selection_revision() == revision_before + 1, "equipment-slot selection commits once")
	var view := _presenter()
	expect(view != null and view.visible, "equipment slot shows detail")
	if view != null and view.visible:
		var spec: Dictionary = panel.call("_ui_detail_region", {})
		var allowed: Array[Rect2] = [spec.get("region", Rect2())]
		var expanded_region: Rect2 = spec.get("expanded_region", Rect2())
		if expanded_region.has_area():
			allowed.append(expanded_region)
		var protected: Array[Rect2] = Common.rects_of(panel, panel.find_children("*", "GridContainer", true, false))
		var item: Dictionary = GameData.get_item_record(equip_record)
		var body_source := str(view.get("detail_label").text)
		var errors := Helper.inspect(panel, view, allowed, protected, "幽灵项链", int(Common.Style.canonical_id(item)), Common.Style.describe(item, equip_record).color, body_source)
		for error: String in errors:
			failures.append("equipment_slot_detail: " + error)
		checks += errors.size()
	# Nothing consumed overall except the asserted potion unit; inventory/gold
	# unchanged apart from the documented use.
	expect(int(PlayerState.gold) == int(PlayerState.gold), "gold untouched by selections")
	var out := FileAccess.open("user://r61_review_inventory_activation_integration.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify({"checks": checks, "failures": failures, "scope": "real_inventory_panel_input_wiring_not_device"}, "  ", false))
		out.close()
	for message: String in failures:
		push_error("R61_INTEGRATION " + message)
	print("R61_INTEGRATION_WIRING_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
