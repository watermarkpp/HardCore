extends Node

var uses: Array[int] = []

func _ready() -> void:
	_run.call_deferred()

func _touch(id: int, pressed: bool, point: Vector2, cancelled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.pressed = pressed
	event.position = point
	event.canceled = cancelled
	get_viewport().push_input(event, true)

func _drag(id: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = id
	event.position = point
	get_viewport().push_input(event, true)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.add_item("太阳水", 20)
	var hud := GameHUD.new()
	add_child(hud)
	hud.set_item_quick_slots([GameData.item_entity_id("太阳水"), GameData.item_entity_id("太阳水"), "", ""])
	hud.item_quick_slot_use_requested.connect(func(slot: int, _id: String) -> void: uses.append(slot))
	await get_tree().process_frame
	await get_tree().process_frame
	var slot: Button = hud.hud_item_buttons[0]
	var point := slot.get_global_rect().get_center()
	print("SLOT_GEOMETRY ", slot.get_global_rect(), " icon=", hud.item_quick_slot_icons[0].get_global_rect())
	_touch(0, true, hud.movement_joystick.get_global_rect().get_center() + Vector2(25, 0))
	_touch(1, true, hud.attack_button.get_global_rect().get_center())
	_touch(2, true, point)
	_touch(2, false, point)
	print("MULTITOUCH_STATE uses=", uses, " movement=", hud.movement_joystick.input_state_snapshot(), " attack=", hud.attack_button.active_input_count())
	assert(uses == [0], "quick tap lost while moving and holding attack")
	assert(hud.movement_joystick.input_state_snapshot().pointer_id == 0)
	assert(hud.attack_button.active_input_count() == 1)
	var utility_counts := {"interact": 0, "switch": 0}
	hud.interact_pressed.connect(func() -> void: utility_counts.interact += 1)
	hud.target_switch_pressed.connect(func() -> void: utility_counts.switch += 1)
	var utility_root: Control = hud.get_node("MobileSafeRoot")
	var interact: Control = utility_root.get_node("InteractButton")
	var switch_target: Control = utility_root.get_node("SwitchTargetButton")
	_touch(7, true, interact.get_global_rect().get_center())
	_touch(7, false, interact.get_global_rect().get_center())
	_touch(7, true, switch_target.get_global_rect().get_center())
	_touch(7, false, switch_target.get_global_rect().get_center())
	assert(utility_counts.interact == 1 and utility_counts.switch == 1, "utility taps lost while joystick and attack held")
	_touch(7, true, switch_target.get_global_rect().get_center())
	_touch(7, false, Vector2.ZERO)
	assert(utility_counts.switch == 1, "outside utility release activated target switch")
	# A synthetic mouse event from the same touch must not duplicate the tap.
	var emulated := InputEventMouseButton.new()
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.position = interact.get_global_rect().get_center()
	emulated.pressed = true
	get_viewport().push_input(emulated, true)
	emulated.pressed = false
	get_viewport().push_input(emulated, true)
	assert(utility_counts.interact == 1, "emulated mouse duplicated utility action")
	# A canceled touch must never consume a potion.
	_touch(3, true, point)
	_touch(3, false, point, true)
	assert(uses == [0], "OS-canceled quick-slot touch incorrectly used an item")
	# A real tap can slide inside the same visible cell while other fingers hold.
	_touch(3, true, point - Vector2(8, 0))
	_drag(3, point + Vector2(8, 0))
	_touch(3, false, point + Vector2(8, 0))
	assert(uses == [0, 0], "in-cell finger drift was discarded")
	# Independent quick-slot fingers must not replace each other's ownership.
	var second := hud.hud_item_buttons[1].get_global_rect().get_center()
	_touch(3, true, point)
	_touch(4, true, second)
	_touch(3, false, point)
	_touch(4, false, second)
	assert(uses == [0, 0, 0, 1], "overlapping quick taps lost a pointer")
	_touch(3, true, point)
	_drag(3, point + Vector2(0, 100))
	_touch(3, false, point)
	assert(uses.size() == 4, "drag out and back wrongly used an item")
	_touch(3, true, point)
	_touch(3, false, point + Vector2(100, 0))
	assert(hud._item_slot_presses.is_empty(), "outside release left a pending pointer")
	_touch(1, false, hud.attack_button.get_global_rect().get_center())
	_touch(1, true, hud.attack_ring_skill_buttons[0].get_global_rect().get_center())
	_touch(3, true, second)
	_touch(3, false, second)
	assert(uses.size() == 5 and uses.back() == 1, "quick tap lost while holding skill")
	assert(hud.attack_ring_skill_buttons[0].active_input_count() == 1)
	_touch(1, false, Vector2.ZERO)
	# Asymmetric safe area and a stretched physical viewport use the same live
	# transforms as hit testing; old screen coordinates cannot remain cached.
	var safe_root: Control = hud.get_node("MobileSafeRoot")
	safe_root.offset_left = 73
	safe_root.offset_right = -77
	hud._apply_center_alignment_delta(2)
	await get_tree().process_frame
	assert(is_equal_approx(hud.warrior_state_label.get_global_rect().get_center().x, (safe_root.get_node("IntegratedHUDChassis") as Control).get_global_rect().get_center().x), "warrior label drifted after safe-area resize")
	point = slot.get_global_rect().get_center()
	_touch(3, true, point)
	_touch(3, false, point)
	assert(uses.size() == 6, "quick slot hit area drifted after safe-area layout")
	get_window().size = Vector2i(2664, 1200)
	await get_tree().process_frame
	assert(is_equal_approx(hud.warrior_state_label.get_global_rect().get_center().x, (safe_root.get_node("IntegratedHUDChassis") as Control).get_global_rect().get_center().x), "warrior label drifted after physical viewport resize")
	point = slot.get_global_rect().get_center()
	var physical := get_viewport().get_final_transform() * point
	var physical_event := InputEventScreenTouch.new()
	physical_event.index = 9
	physical_event.position = physical
	physical_event.pressed = true
	get_viewport().push_input(physical_event, false)
	physical_event.pressed = false
	get_viewport().push_input(physical_event, false)
	assert(uses.size() == 7, "physical-pixel touch did not map to resized logical slot")
	# The visible metal rim is part of the slot, beyond the old 40px black well.
	_touch(9, true, point + Vector2(24, 0))
	_touch(9, false, point + Vector2(24, 0))
	assert(uses.size() == 8 and uses.back() == 0, "visible slot rim rejected a tap")
	# Focus/map cancellation cannot leak a later release into item use.
	_touch(3, true, point)
	hud.cancel_movement_input()
	_touch(3, false, point)
	assert(uses.size() == 8 and hud._item_slot_presses.is_empty())
	_touch(3, true, point)
	await get_tree().create_timer(0.55).timeout
	assert(hud.item_quick_slot_menu.visible, "long-press picker no longer opens")
	_touch(3, false, point)
	assert(uses.size() == 8, "long press also consumed an item")
	hud.item_quick_slot_menu.hide()
	_touch(0, false, Vector2.ZERO)
	hud.queue_free()
	await get_tree().process_frame
	print("HUD_MULTITOUCH_QUICK_ITEMS_PASS")
	get_tree().quit(0)
