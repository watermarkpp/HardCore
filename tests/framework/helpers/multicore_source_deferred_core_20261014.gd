extends RefCounted

signal source_signal(label: String)
class FreedReceiver extends Object:
	var source: WeakRef
	func rejected_call() -> void:
		source.get_ref()._freed_receiver_called = true

var _host: Object
var _owner := OS.get_thread_caller_id()
var _trace: Array[String] = []
var _actual_owner := true
var _before_flush_empty := true
var _freed_receiver_called := false
var _reentrant_refused := false
var _done := false
var _configured := false

func _init(host: Object, _bootstrap: Dictionary) -> void:
	_host = host
	_configured = host.source_deferred_queue_configured()
	source_signal.connect(_record, Object.CONNECT_DEFERRED)
	source_signal.emit("signal")
	_record.call_deferred("plain")
	var receiver := FreedReceiver.new()
	receiver.source = weakref(self)
	receiver.rejected_call.call_deferred()
	receiver.free()
	_before_flush_empty = _trace.is_empty()

func _record(label: String) -> void:
	_actual_owner = _actual_owner and OS.get_thread_caller_id() == _owner and _owner != OS.get_main_thread_id()
	_trace.append(label)
	if label == "signal":
		_record.call_deferred("nested")
		_reentrant_refused = not _host.flush_source_deferred(&"H", &"H_GROUP:end_group")

func on_inputs(_domain: String, _packets: Array) -> bool:
	return true

func on_phase(phase: String, _frame: Dictionary) -> bool:
	if _done:
		return true
	if phase == "H_GROUP":
		_before_flush_empty = _before_flush_empty and _trace.is_empty()
		if not _host.flush_source_deferred(&"H", &"H_GROUP:end_group"):
			return false
	if phase == "P_GROUP":
		_record.call_deferred("process_frame")
		if not _host.flush_source_deferred(&"P", &"P_GROUP:after_process_frame"):
			return false
		_record.call_deferred("process_group")
		if not _host.flush_source_deferred(&"P", &"P_GROUP:end_group"):
			return false
	if phase == "PUBLISH":
		_done = true
		return _host.publish_snapshot({"source_queue_done":true, "configured":_configured,
			"actual_owner":_actual_owner, "before_flush_empty":_before_flush_empty,
			"receiver_free_skipped":not _freed_receiver_called,
			"original_order":_trace == ["signal", "plain", "nested", "process_frame", "process_group"],
			"reentrant_refused":_reentrant_refused, "empty":not _host.has_original_deferred_calls()}, [])
	return true

func close_session() -> bool:
	return _done and not _host.has_original_deferred_calls()
