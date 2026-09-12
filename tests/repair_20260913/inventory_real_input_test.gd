extends Node

const Common := preload("res://tests/r6_1_review/real_panel_matrix_common.gd")
var failures: Array[String] = []
var panel: InventoryPanel

func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func settle() -> void:
	for unused in range(4):
		await get_tree().process_frame

func send_touch(point: Vector2, down: bool, pointer := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.position = get_viewport().get_final_transform() * point
	event.index = pointer
	event.pressed = down
	get_viewport().push_input(event)

func send_mouse(point: Vector2, down: bool, emulated := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = get_viewport().get_final_transform() * point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	if emulated:
		event.device = InputEvent.DEVICE_ID_EMULATION
	get_viewport().push_input(event)

func point_for(index: int) -> Vector2:
	var button := panel._bag_cells[index].get_child(0) as Control
	return button.get_global_transform_with_canvas() * (button.size * 0.5)

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

func _run() -> void:
	if not Common.ensure_data():
		get_tree().quit(1)
		return
	PlayerState.reset_progress()
	PlayerState.inventory = [Common.seed_record("木剑"), Common.seed_record("金疮药(小量)")]
	var hud := GameHUD.new()
	add_child(hud)
	await settle()
	hud._toggle_inventory()
	panel = hud.inventory_panel
	await settle()
	for opening in range(2):
		for route in ["touch", "mouse", "touch_then_emulated", "emulated_then_touch"]:
			panel._ui_dismiss_selection()
			var point := point_for(0)
			var guard := panel._bag_cells[0].get_child(0).get_node("HCActivationOnce")
			var before := int(guard.get("accepted_count"))
			match route:
				"touch":
					send_touch(point, true)
					send_touch(point, false)
				"mouse":
					send_mouse(point, true)
					send_mouse(point, false)
				"touch_then_emulated":
					send_touch(point, true)
					send_mouse(point, true, true)
					send_touch(point, false)
					send_mouse(point, false, true)
				"emulated_then_touch":
					send_mouse(point, true, true)
					send_touch(point, true)
					send_mouse(point, false, true)
					send_touch(point, false)
			await settle()
			var accepted := int(guard.get("accepted_count")) - before
			print("INVENTORY_ROUTE opening=%d route=%s accepted=%d selected=%d duplicate=%d" % [opening, route, accepted, panel.selected_inventory_index, int(guard.get("duplicate_count"))])
			expect(accepted == 1 and panel.selected_inventory_index == 0, "%s opening %d selects once" % [route, opening])
			expect(panel.item_detail_presenter.visible and panel.item_detail_presenter.modulate.a > 0.0, "%s detail visible" % route)
		hud._toggle_inventory()
		await settle()
		hud._toggle_inventory()
		await settle()
	hud.queue_free()
	await settle()
	for message in failures:
		push_error(message)
	print("INVENTORY_REAL_INPUT_%s failures=%d" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
