extends Node

const Feedback := preload("res://scripts/loot_feedback_layer.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures += 1
		print("HC_TEST_FAIL ", label)

func event(index: int) -> Dictionary:
	return {"event_type": "pickup_success", "item_name": "queued-%d" % index, "receipt_sequence": index}

func _ready() -> void:
	var layer := Feedback.new()
	add_child(layer)
	# Component-owner clock coverage, not a real-time pickup/writer load or FPS
	# claim. Keep the formal default duration; feed elapsed time to its owner.
	layer.set_process(false)
	layer.show_feedback_batch([event(0), event(1), event(2), event(3)])
	var ordered := true
	var default_duration_preserved := true
	var visible_reference_preserved := true
	var bounded := true
	var peak_backing_records := 0
	for cycle in range(120):
		ordered = ordered and layer.toast_entries.size() == 1 and int(layer.toast_entries[0].receipt_sequence) == cycle
		default_duration_preserved = default_duration_preserved and is_equal_approx(float(layer.toast_entries[0].remaining), Feedback.DEFAULT_DURATION)
		var current: Dictionary = layer.toast_entries[0]
		layer._process(1.0)
		layer.show_feedback(event(cycle + 4))
		visible_reference_preserved = visible_reference_preserved and layer.toast_entries[0] == current and is_equal_approx(float(current.remaining), 1.4)
		# Arrivals do not extend the current message; one expiry activates just
		# one next message. A long frame likewise cannot skip the unseen tail.
		layer._process(20.0 if cycle == 7 else 1.4)
		peak_backing_records = maxi(peak_backing_records, layer._pending_pickup_feedback.size())
		bounded = bounded and layer._pending_pickup_feedback.size() <= 3
	check(ordered, "120 consumer cycles preserve exactly-once FIFO with constant pending tail")
	check(default_duration_preserved, "each newly displayed notice retains default 2.4 seconds")
	check(visible_reference_preserved, "arrival preserves current visible reference and remaining time")
	check(bounded, "consumed prefix retires while tail stays 3; peak backing records=%d" % peak_backing_records)
	check(layer.toast_container.get_child_count() == 3, "fixed UI controls survive sustained queue")
	layer.show_feedback({"event_type":"pickup_failed", "item_name":"control", "reason":"背包已满"})
	check(int(layer.toast_entries[0].receipt_sequence) == 120, "failure notice does not reorder successful pickups")
	for index in range(120, 124):
		check(layer.toast_entries.size() == 1 and int(layer.toast_entries[0].receipt_sequence) == index, "drain pending sequence %d" % index)
		layer._process(2.4)
	check(layer.toast_entries.is_empty() and layer._pending_pickup_feedback.is_empty(), "complete drain releases every queue record")
	layer.show_feedback_batch([event(200), event(201)])
	layer.clear_feedback()
	layer._process(20.0)
	check(layer.toast_entries.is_empty() and layer._pending_pickup_feedback.is_empty(), "explicit clear retires visible and pending records")
	layer.show_feedback(event(300))
	check(int(layer.toast_entries[0].receipt_sequence) == 300, "next session has no stale prefix")
	var owner: WeakRef = weakref(layer)
	layer.queue_free()
	await get_tree().process_frame
	check(not is_instance_valid(owner.get_ref()), "layer destruction retires queue owner")
	if not proof.write_receipt("v109_loot_feedback_retention_test", proof.records.size(), failures):
		failures += 1
	print("V109_LOOT_FEEDBACK_RETENTION_%s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)
