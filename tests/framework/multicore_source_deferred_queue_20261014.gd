extends Node

const Core := preload("res://tests/framework/helpers/multicore_source_deferred_core_20261014.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _host: Object
var _checks := 0
var _failed := 0
var _closing := false
var _deadline := 0

func _check(value: bool, label: String) -> void:
	_checks += 1
	_failed += 0 if value else 1
	_proof.record(value, label)

func _ready() -> void:
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var available: bool = _host.has_method("source_deferred_queue_configured") and _host.has_method("flush_source_deferred") and _host.has_method("has_original_deferred_calls")
	_check(available, "actual native source queue ABI")
	if not available:
		_finish()
		return
	var max_mb: int = int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb", 32))
	var config := {"physics_hz":60, "max_epochs_per_turn":8, "timer_capacity":16,
		"input_capacity":16, "event_capacity":16, "bridge_generation":83,
		"source_process_frame":Engine.get_process_frames(), "source_physics_frame":Engine.get_physics_frames(),
		"primitive_request_capacity":65536, "primitive_result_capacity":65536,
		"source_deferred_max_pages":int(max_mb * 1024 * 1024 / 4096)}
	_check(_host.start_clock_fixture(Core, {}, config), "real Godot S source queue fixture start")
	_deadline = Time.get_ticks_usec() + 5000000

func _process(_delta: float) -> void:
	if _host == null or _deadline == 0:
		return
	if Time.get_ticks_usec() > _deadline:
		_check(false, "source queue completes within fixture deadline")
		_finish()
		return
	if not _closing:
		var frame: Dictionary = _host.acquire_presentation(0, 16)
		if frame.get("frame", {}).get("source_queue_done", false):
			var facts: Dictionary = frame.frame
			_check(facts.configured, "real thread-local override installed")
			_check(facts.actual_owner, "every deferred callback runs on original S")
			_check(facts.original_order, "signal and ordinary calls preserve FIFO including appended calls")
			_check(facts.receiver_free_skipped, "freed receiver does not execute queued method")
			_check(facts.empty, "queue fully drained at original checkpoints")
			_check(facts.before_flush_empty, "deferred callbacks do not execute before checkpoint")
			_check(facts.reentrant_refused, "nested flush does not alter original FIFO")
			_host.request_close()
			_closing = true
	if _closing and _host.close_and_join():
		_check(_host.status().close_quiescent and _host.status().join_complete, "actual owner quiescence and asynchronous join")
		_finish()

func _finish() -> void:
	var written: bool = _proof.write_receipt("multicore_source_deferred_queue_20261014", _checks, _failed)
	print("MULTICORE_SOURCE_DEFERRED_QUEUE_", "PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
