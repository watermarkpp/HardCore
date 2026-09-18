extends Node

## Equipment/unequip central-notice real-input acceptance (R2).
## Slot-tap equips drive the real touch path (bag tap -> slot tap); the
## context-action handler covers the remaining production equip entries and
## unequip. Every committed action reports exactly one central notice whose
## item name carries its official UIItemNameStyle color.

const Common := preload("res://tests/r6_1_review/real_panel_matrix_common.gd")
const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")

var failures: Array[String] = []
var hud: GameHUD
var panel: InventoryPanel


func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func settle() -> void:
	for _index in range(4):
		await get_tree().process_frame


func send_touch(point: Vector2, down: bool, pointer := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.position = get_viewport().get_final_transform() * point
	event.index = pointer
	event.pressed = down
	get_viewport().push_input(event)


func center_of(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func point_for(index: int) -> Vector2:
	var button := panel._bag_cells[index].get_child(0) as Control
	return center_of(button)


func tap_bag(index: int) -> void:
	var point := point_for(index)
	send_touch(point, true)
	send_touch(point, false)
	await settle()


func tap_slot(slot: String) -> void:
	var point := center_of(panel.equipment_buttons[slot] as Control)
	send_touch(point, true)
	send_touch(point, false)
	await settle()


func reset_fixture_state() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 60
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	PlayerState.inventory = []
	PlayerState.equipment = {}
	PlayerState.recalculate_stats(false)
	# Pin AFTER the recalc: the requirement authorities read computed_stats,
	# so the success baseline must exceed every catalog requirement.
	PlayerState.computed_stats["attack_max"] = 9999
	PlayerState.computed_stats["magic_max"] = 9999
	PlayerState.computed_stats["tao_max"] = 9999
	if panel != null:
		panel._ui_dismiss_selection()


func place_in_bag(item_name: String) -> bool:
	var record := GameData.get_item(item_name)
	if record.is_empty():
		return false
	var instance := PlayerState._make_item_instance(item_name, record)
	if instance.is_empty():
		return false
	PlayerState.inventory.append(instance)
	return true


func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()


func _run() -> void:
	if not Common.ensure_data():
		get_tree().quit(1)
		return
	reset_fixture_state()
	hud = GameHUD.new()
	add_child(hud)
	await settle()
	hud._toggle_inventory()
	panel = hud.inventory_panel
	await settle()
	expect(panel != null and panel.visible, "inventory panel open")
	expect(hud.notice_presenter != null, "central notice presenter present")

	# --- Real-input multi-rarity equip (木剑/龙之戒指/力量戒指/圣战戒指/麻痹戒指)
	for item_name in ["木剑", "龙之戒指", "力量戒指", "圣战戒指", "麻痹戒指"]:
		reset_fixture_state()
		var record := GameData.get_item(item_name)
		expect(not record.is_empty(), "fixture record exists: " + item_name)
		if record.is_empty():
			continue
		var profession := str(EquipmentRulesScript.effective_profession(record))
		if not profession in ["", "通用", "战士"]:
			continue
		if str(EquipmentRulesScript.required_gender(record)) == "女":
			continue
		expect(place_in_bag(item_name), "instance placed: " + item_name)
		panel.refresh()
		await settle()
		await tap_bag(0)
		var slots: Array = panel._slots_for_category(str(record.get("category", "")))
		expect(not slots.is_empty(), "%s has an allowed slot" % item_name)
		if slots.is_empty():
			continue
		await tap_slot(str(slots[0]))
		await settle()
		var slot_name := str(slots[0])
		var committed: Dictionary = PlayerState.equipment.get(slot_name, {}) if PlayerState.equipment.get(slot_name, {}) is Dictionary else {}
		expect(str(committed.get("name", "")) == item_name, "%s actually committed to %s" % [item_name, slot_name])
		expect(hud.notice_presenter.full_text() == "已装备 " + item_name, "%s central equip notice (got [%s])" % [item_name, hud.notice_presenter.full_text()])
		expect(hud.notice_presenter.prefix_label.text == "已装备 ", "%s prefix text" % item_name)
		expect(hud.notice_presenter.item_label.visible, "%s item label visible with panel open" % item_name)
		expect(hud.notice_presenter.item_label.is_visible_in_tree(), "%s notice visible above the open bag" % item_name)
		expect(hud.notice_presenter.queue_size() == 0, "%s exactly one notice (no queue)" % item_name)
		# The style authority owns the color; the prefix never inherits it.
		var style: Dictionary = NameStyle.describe(record, {})
		expect(hud.notice_presenter.item_label.get_theme_color("font_color") == style.get("color"), "%s item color from UIItemNameStyle" % item_name)
		expect(hud.notice_presenter.prefix_label.get_theme_color("font_color") == hud.notice_presenter.NOTICE_TEXT_COLOR, "%s prefix keeps plain color" % item_name)

	# --- Production context-action equip entry reports once ------------------
	reset_fixture_state()
	expect(place_in_bag("井中月"), "井中月 placed")
	panel.refresh()
	await settle()
	var context_ok := false
	for attempt in range(2):
		panel._on_context_action(_next_action_id({"action": "equip", "index": 0, "slot": "武器"}))
		await settle()
		context_ok = str((PlayerState.equipment.get("武器", {}) as Dictionary).get("name", "")) == "井中月"
		if context_ok:
			break
		reset_fixture_state()
		expect(place_in_bag("井中月"), "井中月 replaced for context retry")
		panel.refresh()
		await settle()
	expect(context_ok, "context-action equip commits 井中月")
	expect(hud.notice_presenter.full_text() == "已装备 井中月", "context equip shows one central notice")
	expect(hud.notice_presenter.queue_size() == 0, "context equip never queues a second notice")

	# --- Replacement shows ONLY the new equip (one action, one notice) -------
	expect(place_in_bag("裁决之杖"), "裁决之杖 placed for replace")
	panel.refresh()
	await settle()
	# 井中月 was consumed from the bag by the previous equip, so the new
	# weapon occupies slot 0.
	panel._on_context_action(_next_action_id({"action": "equip", "index": 0, "slot": "武器"}))
	await settle()
	expect(str((PlayerState.equipment.get("武器", {}) as Dictionary).get("name", "")) == "裁决之杖", "replace commits the new weapon")
	expect(hud.notice_presenter.full_text() == "已装备 裁决之杖", "replace reports only the new equip")
	expect(hud.notice_presenter.queue_size() == 0, "replace never shows an extra unequip notice")

	# --- Context-action unequip reports once with the official style ---------
	panel._on_context_action(_next_action_id({"action": "unequip", "slot": "武器"}))
	await settle()
	expect((PlayerState.equipment.get("武器", {}) as Dictionary).is_empty(), "unequip commits: weapon slot empty")
	expect(hud.notice_presenter.full_text() == "已卸下 裁决之杖", "unequip shows one central notice")
	expect(hud.notice_presenter.queue_size() == 0, "unequip never queues a second notice")

	# --- Production double-tap activation entry reports once -----------------
	reset_fixture_state()
	expect(place_in_bag("井中月"), "井中月 placed for activation entry")
	panel.refresh()
	await settle()
	panel._activate_inventory_index(0)
	await settle()
	expect(str((PlayerState.equipment.get("武器", {}) as Dictionary).get("name", "")) == "井中月", "activation equip commits")
	expect(hud.notice_presenter.full_text() == "已装备 井中月", "activation equip shows one central notice")

	hud.queue_free()
	await settle()
	if failures.is_empty():
		print("EQUIPMENT_SUCCESS_NOTICE_REAL_INPUT_PASS: touch equip x5 rarities, context equip/replace/unequip, activation entry")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("EQUIPMENT_SUCCESS_NOTICE_REAL_INPUT_FAIL: " + failure)
		get_tree().quit(1)


const NameStyle := preload("res://scripts/ui_item_name_style.gd")
var _action_ids := 0


func _next_action_id(action: Dictionary) -> int:
	# Register the action exactly the way the context menu does, so the
	# production handler resolves it.
	_action_ids += 1
	panel._context_actions[_action_ids] = action
	return _action_ids
