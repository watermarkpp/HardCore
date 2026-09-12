extends Node

const Visual := preload("res://scripts/ui_item_selection_visual.gd")
const Lifecycle := preload("res://scripts/ui_item_selection_lifecycle.gd")
var checks := 0
var failures: Array[String] = []
var finished := false
var start_us := 0

class SelectionFixture:
	extends Control
	const SelectionVisual := preload("res://scripts/ui_item_selection_visual.gd")
	var selected := false
	var selected_ref: Dictionary = {}
	var buy_request_locked := true
	var inventory_sentinel := {"instance_id": "fixture:keep", "count": 1}
	var clears := 0
	var item := Button.new()
	func _init() -> void:
		size = Vector2(300, 200)
		item.size = Vector2(80, 50)
		item.toggle_mode = true
		add_child(item)
	func choose() -> void:
		selected = true
		selected_ref = {"instance_id": "fixture:keep"}
		SelectionVisual.apply(item, true, &"Button", &"Button")
	func _ui_dismiss_selection() -> void:
		clears += 1
		selected = false
		selected_ref.clear()
		SelectionVisual.apply(item, false, &"Button", &"Button")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _ready() -> void:
	start_us = Time.get_ticks_usec()
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not finished and Time.get_ticks_usec() - start_us > 5000000:
		failures.append("SMOKE_RUNTIME_ABORT_OR_TIMEOUT")
		finish()

func _run() -> void:
	# Direct proof: detached cleanup must change semantics/toggle, NOT return
	# early merely because the button no longer belongs to a viewport.
	var detached := Button.new()
	detached.toggle_mode = true
	Visual.apply(detached, true, &"Button", &"Button")
	for i in range(32):
		Visual.apply(detached, false, &"Button", &"Button")
	expect(not detached.button_pressed, "DETACHED_TOGGLE_CLEARED")
	expect(not bool(detached.get_meta("ui_selection_authoritative_pressed", true)), "DETACHED_AUTHORITATIVE_META_CLEARED")
	detached.free()

	var ancestor := Control.new()
	add_child(ancestor)
	var panel := SelectionFixture.new()
	ancestor.add_child(panel)
	var lifecycle = Lifecycle.attach(panel)
	await get_tree().process_frame
	for i in range(3):
		panel.choose()
		var old_epoch: int = lifecycle.epoch
		ancestor.hide()
		expect(not panel.selected and panel.selected_ref.is_empty() and not panel.item.button_pressed, "ANCESTOR_HIDE_CLEARS_" + str(i))
		expect(not lifecycle.allows_presentation(old_epoch), "OLD_EPOCH_REJECTED_" + str(i))
		ancestor.show()
		expect(not panel.selected and not panel.item.button_pressed, "REOPEN_CLEAN_" + str(i))
		panel.choose()
		expect(panel.selected, "FIRST_NEW_SELECTION_WORKS_" + str(i))
		panel.item.grab_focus()
		panel._ui_dismiss_selection()
		expect(not panel.item.has_focus(), "ATTACHED_FOCUS_CLEARED_" + str(i))
		panel.choose()
		ancestor.remove_child(panel)
		expect(not panel.selected and panel.selected_ref.is_empty(), "TREE_EXIT_CLEARS_" + str(i))
		# Deliberately repeat the leaving callback after all descendants are out.
		lifecycle._on_leaving()
		expect(not panel.item.button_pressed and not lifecycle._clearing, "DETACHED_REPEATED_CLEANUP_" + str(i))
		expect(panel.buy_request_locked and int(panel.inventory_sentinel.count) == 1, "NO_TRANSACTION_OR_INVENTORY_MUTATION_" + str(i))
		ancestor.add_child(panel)
		await get_tree().process_frame
		expect(not panel.selected, "REENTER_CLEAN_" + str(i))
	ancestor.queue_free()
	await get_tree().process_frame
	finish()

func finish() -> void:
	if finished:
		return
	finished = true
	print("R31_SELECTION_DETACH_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
