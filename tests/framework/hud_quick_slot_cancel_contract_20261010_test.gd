extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const FormalWorldFixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")

var proof := Proof.new()
var failures: Array[String] = []
var use_events: Array[int] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)
		push_error("B05-001: " + label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _touch(index: int, pressed: bool, position: Vector2, cancelled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	event.canceled = cancelled
	get_viewport().push_input(event, true)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.add_item("太阳水", 20)
	var game: Root = Root.new()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	await FormalWorldFixture.wait_for_formal_world(self, game, "hud_quick_slot_cancel")
	var hud: GameHUD = game.hud
	check(is_instance_valid(hud) and not hud.hud_item_buttons.is_empty(), "formal GameRoot exposes the live HUD slot")
	if not is_instance_valid(hud) or hud.hud_item_buttons.is_empty():
		_finish(game)
		return
	var item_id: String = GameData.item_entity_id("太阳水")
	var assignment: Dictionary = PlayerState.assign_quick_item_slot(0, item_id)
	check(bool(assignment.get("ok", false)), "formal PlayerState accepts the quick-slot binding")
	var binding_deadline: int = Time.get_ticks_msec() + 3000
	while hud.item_quick_slots.is_empty() or hud.item_quick_slots[0] != item_id:
		if Time.get_ticks_msec() >= binding_deadline:
			break
		await get_tree().process_frame
	check(not hud.item_quick_slots.is_empty() and hud.item_quick_slots[0] == item_id,
		"formal GameRoot synchronizes the PlayerState quick-slot binding")
	hud.item_quick_slot_use_requested.connect(func(slot: int, _item_id: String) -> void: use_events.append(slot))
	await get_tree().process_frame
	var slot: Button = hud.hud_item_buttons[0]
	var point: Vector2 = slot.get_global_rect().get_center()
	var bound_id: String = hud.item_quick_slots[0]
	_touch(40, true, point)
	_touch(40, false, point)
	await get_tree().process_frame
	check(use_events == [0], "formal READY HUD admits an ordinary quick-slot DOWN/UP")
	use_events.clear()

	_touch(41, true, point)
	game._show_system_menu()
	check(get_tree().paused, "system menu owns the pause")
	await get_tree().create_timer(0.55, true).timeout
	game._hide_system_menu()
	_touch(41, false, point)
	await get_tree().process_frame
	check(use_events.is_empty(), "menu boundary cancels old quick-slot UP and long-press")
	check(hud._item_slot_presses.is_empty(), "menu boundary clears transient slot pointers")
	check(hud._item_slot_long_press_timer.is_stopped(), "menu boundary stops the shared long-press timer")
	check(hud.item_quick_slots[0] == bound_id, "menu boundary preserves the slot binding")

	# Focus-out is an interrupt, not a permanent focus state. Pair it with the
	# real resumed notification before testing the next admitted DOWN, and use
	# the live button transform after the modal/focus transitions.
	_touch(42, true, point)
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_touch(42, false, point)
	game._notification(NOTIFICATION_APPLICATION_RESUMED)
	await get_tree().process_frame
	check(use_events.is_empty(), "focus boundary cancels old quick-slot UP")

	point = slot.get_global_rect().get_center()
	_touch(43, true, point)
	game._cancel_map_transition_movement_input()
	_touch(43, false, point)
	await get_tree().process_frame
	check(use_events.is_empty(), "map transition boundary cancels old quick-slot UP")

	point = slot.get_global_rect().get_center()
	_touch(44, true, point)
	_touch(44, false, point)
	await get_tree().process_frame
	check(use_events == [0], "fresh quick-slot DOWN/UP emits exactly one use")
	check(hud.item_quick_slots[0] == bound_id, "fresh use does not change the slot binding")
	_finish(game)

func _finish(game: Node) -> void:
	if is_instance_valid(game):
		game.queue_free()
	# Let queued exits and the formal Root teardown unwind before writing the
	# receipt and quitting. Keeping this as a deferred callback avoids leaving
	# an awaited _finish continuation alive at SceneTree.quit().
	call_deferred("_finish_after_cleanup")

func _finish_after_cleanup() -> void:
	var receipt_ok: bool = proof.write_receipt("hud_quick_slot_cancel_contract_20261010_test", proof.records.size(), failures.size())
	var ok: bool = failures.is_empty() and receipt_ok
	print("HUD_QUICK_SLOT_CANCEL_CONTRACT_%s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
