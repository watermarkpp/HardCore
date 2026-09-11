extends Node

## §2.1 integration wiring coverage on the REAL InventoryPanel (executor
## fixture; no production change). Proves the real panel paths that the
## 13-assertion component test does not: bag single tap commits once, native
## touch + emulated mouse pairing does not double-commit, bag double
## activation consumes exactly one unit, equipment-slot detail path, and a
## TouchScrollSupport drag release selects nothing. Commit counts come from
## the UIActivationOnce guard's accepted_count (the real semantic selection
## counter); the locked helper gates the equipment-slot detail window.

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
	# Canvas-space point of the button center (the touch bridge then maps it
	# into window coordinates for push_input).
	return button.get_global_transform_with_canvas() * (button.size * 0.5)

func _guard(index: int) -> Node:
	var cells: Array = panel.get("_bag_cells")
	return (cells[index].get_child(0)).get_node_or_null("HCActivationOnce")

func _accepted(index: int) -> int:
	var guard := _guard(index)
	return int(guard.get("accepted_count")) if guard != null else -1

func _presenter() -> Control:
	return panel.get("item_detail_presenter") as Control

func _run() -> void:
	if not Common.ensure_data():
		get_tree().quit(1)
		return
	var InventoryScript := load("res://scripts/inventory_panel.gd")
	panel = InventoryScript.new()
	add_child(panel)
	# The panel's visibility is owned by its host; force it visible like the
	# real game host does before any input wiring can reach the cells.
	panel.visible = true
	await settle()
	# Seed: a consumable stack for the use path and a plain item for taps.
	var potion_record := Common.seed_record("金疮药(小量)")
	var potion_record2 := Common.seed_record("金疮药(小量)")
	var plain_record := Common.seed_record("木剑")
	expect(not potion_record.is_empty() and not potion_record2.is_empty() and not plain_record.is_empty(), "seed records exist")
	potion_record["count"] = int(potion_record.get("count", 1)) + int(potion_record2.get("count", 1))
	PlayerState.inventory = [potion_record, plain_record]
	panel.call("refresh")
	await settle()
	# 1) Real single tap on bag cell 0 commits exactly one selection.
	var accepted_before := _accepted(0)
	_touch(_cell_point(0), true)
	_touch(_cell_point(0), false)
	await settle()
	expect(_accepted(0) == accepted_before + 1, "one real tap commits exactly one selection (accepted=%d)" % _accepted(0))
	expect(_presenter() != null and _presenter().visible, "bag tap shows detail")
	# 2) Native tap + emulated mouse pair must not double-commit.
	accepted_before = _accepted(1)
	_touch(_cell_point(1), true)
	_touch(_cell_point(1), false)
	_mouse(_cell_point(1), true, false, true)
	_mouse(_cell_point(1), false, false, true)
	await settle()
	expect(_accepted(1) == accepted_before + 1, "emulated mouse pairing does not double-commit (accepted=%d)" % _accepted(1))
	# 3) Bag double activation uses the consumable exactly once. Cell 0 holds
	# the potion stack with count 2; the use path must remove exactly one.
	var count_before := int((PlayerState.inventory[0] as Dictionary).get("count", 0))
	_touch(_cell_point(0), true)
	_touch(_cell_point(0), false)
	_touch(_cell_point(0), true, {"double_tap": true})
	await settle()
	var count_after := 0
	for r: Variant in PlayerState.inventory:
		if r is Dictionary and str((r as Dictionary).get("name", "")) == "金疮药(小量)":
			count_after += int((r as Dictionary).get("count", 0))
	expect(count_after == count_before - 1, "double activation consumes exactly one unit (got %d -> %d)" % [count_before, count_after])
	# 4) Equipment-slot path: equip the first low-level candidate the
	# authoritative rules accept (a level-1 warrior rejects high-level gear by
	# design), then select its slot and gate the detail with the locked helper.
	panel.call("_ui_dismiss_selection")
	await settle()
	var equip_name := ""
	var equip_record := {}
	var equip_slot := ""
	for candidate: String in ["木剑", "草鞋", "布衣(男)", "短剑", "皮腰带", "牛角戒指"]:
		var seeded: Dictionary = Common.seed_record(candidate)
		if seeded.is_empty():
			continue
		var saved := PlayerState.inventory
		PlayerState.inventory = [seeded]
		var result: Dictionary = PlayerState.call("equip_inventory_index_result", 0)
		if bool(result.get("success", false)):
			equip_name = candidate
			equip_record = seeded
			for key: Variant in PlayerState.equipment:
				var equipped: Variant = PlayerState.equipment[key]
				if equipped is Dictionary and str((equipped as Dictionary).get("instance_id", "")) == str(seeded.get("instance_id", "")):
					equip_slot = str(key)
			break
		PlayerState.inventory = saved
	expect(not equip_name.is_empty(), "a low-level candidate equips (got %s)" % equip_name)
	expect(not equip_slot.is_empty(), "equipped slot found")
	panel.call("refresh")
	await settle()
	panel.call("_select_equipment_slot", equip_slot)
	await settle()
	# An already-equipped slot tap selects the slot and shows the equipped
	# item's detail (no bag source selection is consumed at this point).
	expect(str(panel.get("selected_equipment_slot")) == equip_slot, "equipment-slot selection set")
	var view := _presenter()
	expect(view != null and view.visible, "equipment slot shows detail")
	if view != null and view.visible:
		# Production equipment-zone details are placed against the equipment
		# region contract, not the bag-side region.
		var spec: Dictionary = panel.call("_ui_detail_region", {"presentation_zone": "equipment", "slot": equip_slot})
		var allowed: Array[Rect2] = [spec.get("region", Rect2())]
		var expanded_region: Rect2 = spec.get("expanded_region", Rect2())
		if expanded_region.has_area():
			allowed.append(expanded_region)
		var protected: Array[Rect2] = Common.rects_of(panel, panel.find_children("*", "GridContainer", true, false))
		var item: Dictionary = GameData.get_item_record(equip_record)
		var body_source := str(view.get("detail_label").text)
		var actual_diag: Rect2 = Common.HelperRects.rect_in(panel, view)
		print("R61_DIAG equip_detail actual=%s base=%s expanded=%s snapshot_rect=%s" % [actual_diag, str(spec.get("region", Rect2())), str(expanded_region), str((view.call("debug_layout_snapshot") as Dictionary).get("rect", ""))])
		var errors: Array[String] = Helper.inspect(panel, view, allowed, protected, equip_name, int(Common.Style.canonical_id(item)), Common.Style.describe(item, equip_record).color, body_source)
		for error: String in errors:
			failures.append("equipment_slot_detail: " + error)
		checks += errors.size()
	# 5) LAST: drag release inside the panel selects nothing (drag state is
	# intentionally left alone afterwards so it cannot poison other steps).
	panel.call("_ui_dismiss_selection")
	await settle()
	var accepted_before_drag := _accepted(1)
	var start := _cell_point(1)
	_touch(start, true)
	_drag(start + Vector2(0, 40))
	_touch(start + Vector2(0, 40), false)
	await settle()
	expect(_accepted(1) == accepted_before_drag, "drag release never commits a selection")
	var out := FileAccess.open("user://r61_review_inventory_activation_integration.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify({"checks": checks, "failures": failures, "scope": "real_inventory_panel_input_wiring_not_device"}, "  ", false))
		out.close()
	for message: String in failures:
		push_error("R61_INTEGRATION " + message)
	print("R61_INTEGRATION_WIRING_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
