extends Node

const Feedback := preload("res://scripts/loot_feedback_layer.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var layer := Feedback.new()
	add_child(layer)
	layer.set_process(false)
	var events: Array = []
	for index in 30:
		events.append({"event_type": "pickup_success", "item_name": "FIFO-%02d" % index, "duration": 0.5})
	layer.show_feedback_batch(events)
	for index in 30:
		assert(layer.toast_entries.size() == 1, "display exactly one committed pickup at a time")
		assert(layer.toast_entries[0].item_name == "FIFO-%02d" % index, "no reversed, dropped, duplicated or skipped pickup messages")
		assert(layer.toast_labels[0].text.contains("FIFO-%02d" % index))
		assert(layer.toast_container.get_child_count() == 3, "reuse fixed UI controls; never allocate per queued pickup")
		if index == 5:
			layer.show_feedback({"event_type": "pickup_failed", "item_name": "full", "reason": "背包已满"})
			assert(layer.toast_entries[0].item_name == "FIFO-05", "failure overlay must not reorder accepted pickups")
		# A long frame must not consume unseen messages in a while loop.
		layer._process(10.0 if index == 7 else 0.51)
	assert(layer.toast_entries.is_empty() and not layer.toast_panels[0].visible)
	layer.show_feedback_batch(events)
	layer.clear_feedback()
	layer._process(1.0)
	assert(layer.toast_entries.is_empty(), "explicit clear must retire every queued notice")
	layer.show_feedback({"item_name": "new-session", "duration": 0.5})
	assert(layer.toast_entries[0].item_name == "new-session")
	layer.queue_free()
	print("LOOT_FEEDBACK_FIFO_PASS count=30 fixed_controls/ordered/no_loss/no_long_frame_skip/clear")
	get_tree().quit(0)
