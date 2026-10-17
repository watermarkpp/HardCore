extends Node

# Contract-level fixture for the native transport. It deliberately checks the
# ownership protocol rather than claiming a production simulation integration.
func _ready() -> void:
	var root := "res://native/hardcore_simulation/"
	var batch := _read(root + "batch_executor.h")
	var types := _read(root + "batch_types.h")
	var bridge := _read(root + "presentation_bridge.h")
	var batch_cpp := _read(root + "batch_executor.cpp")
	var bridge_cpp := _read(root + "presentation_bridge.cpp")
	var checks := 0
	checks += _require(types, "UNCLAIMED, RUNNING, READY, CONSUMED, RETIRED", "batch state sequence")
	checks += _require(batch, "dispatch_ready", "fixed stage dispatch API")
	checks += _require(batch, "poll_published", "nonblocking poll API")
	checks += _require(batch, "cancel_unclaimed", "unclaimed-only cancellation API")
	checks += _require(batch, "complete_claimed", "S completion API")
	checks += _require(batch_cpp, "is_group_task_completed", "WorkerThreadPool completion polling")
	checks += _require(batch_cpp, "compare_exchange_strong(expected, BatchState::RUNNING", "single CAS claim")
	checks += _require(batch_cpp, "state.store(BatchState::READY", "ready only after kernel")
	checks += _require(batch_cpp, "active_.size() >= capacity_", "explicit capacity failure")
	checks += _require(bridge, "FREE, WRITING, PUBLISHED, READING", "three-slot states")
	checks += _require(bridge, "last_effect_ordinal", "snapshot event watermark")
	checks += _require(bridge_cpp, "min_tick", "caller supplied minimum tick")
	checks += _require(bridge_cpp, "events_.erase", "event retirement only after ack")
	checks += _forbid(batch + batch_cpp + bridge + bridge_cpp, "Callable", "no Callable transport")
	checks += _forbid(batch + batch_cpp + bridge + bridge_cpp, "Node", "no Node transport")
	print("multicore_batch_transport_20261013 checks=" + str(checks))
	get_tree().quit(0 if checks == 15 else 1)

func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()

func _require(text: String, needle: String, label: String) -> int:
	if text.find(needle) < 0:
		push_error("MISSING: " + label)
		return 0
	return 1

func _forbid(text: String, needle: String, label: String) -> int:
	if text.find(needle) >= 0:
		push_error("FORBIDDEN: " + label)
		return 0
	return 1
