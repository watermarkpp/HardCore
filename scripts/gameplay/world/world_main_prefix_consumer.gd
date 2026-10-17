extends RefCounted

## Sole Main consumer for normal/cold/LIVE source-journal prefixes. Actual
## rendering/resource executor owns Node writes; this object owns no gameplay.
var _host: Object
var _dispatcher: Object
var _held: Dictionary = {}
var _next_event := 0
var _fault: Dictionary = {}

func _init(host: Object, dispatcher: Object) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	assert(host != null and dispatcher != null)
	assert(host.has_method("acquire_original_main_prefix"))
	assert(dispatcher.has_method("apply_original_main_journal_event"))
	_host = host
	_dispatcher = dispatcher

func apply_prefix(prefix: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	if not _fault.is_empty(): return {"status":"INVALID", "error":_fault}
	if _held.is_empty():
		var replies: Dictionary=flush_original_main_replies()
		if replies.get("status")!="READY": return replies
	if not _held.is_empty() and _held.main_prefix != prefix:
		return {"status":"BUSY"}
	if _held.is_empty():
		var delta: Dictionary = _host.acquire_original_main_prefix(prefix)
		if delta.is_empty(): return {"status":"BUSY"}
		if delta.get("main_prefix") != prefix or not delta.get("events") is Array:
			_fault = {"kind":"native_actual_prefix_delta_invalid"}
			return {"status":"INVALID", "error":_fault}
		_held = delta
		_next_event = 0
	while _next_event < _held.events.size():
		var event: Dictionary = _held.events[_next_event]
		var actual: Variant = _dispatcher.apply_original_main_journal_event(event)
		if actual is Dictionary:
			if actual.get("status")=="PENDING": return {"status":"PENDING"}
			actual=actual.get("status")=="APPLIED" and actual.get("success")==true
		if not actual is bool or not actual:
			# Preserve the native claim and the exact partial cursor. No retry
			# replays an earlier Node write or acknowledges an unapplied event.
			_fault = {"kind":"actual_main_journal_event_failed", "ordinal":event.get("ordinal")}
			return {"status":"INVALID", "error":_fault}
		_next_event += 1
	return {"status":"APPLIED", "main_prefix":_held.main_prefix}

func confirm_prefix_acknowledged(prefix: Dictionary, actual_native_receipt: Dictionary={}) -> bool:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	if _held.is_empty() or _held.main_prefix != prefix or _next_event != _held.events.size() or not _fault.is_empty():
		return false
	# Forward only the actual caller's Native ACK. The map executor verifies it
	# against the accepted effect; an effect/callback/empty queue is no ACK.
	if _dispatcher.has_method("confirm_original_main_prefix_acknowledged"):
		if not _dispatcher.confirm_original_main_prefix_acknowledged(prefix,actual_native_receipt): return false
	_held = {}
	_next_event = 0
	return true

func has_pending() -> bool:
	return not _held.is_empty() or (_dispatcher.has_method("has_pending_original_main_replies") and _dispatcher.has_pending_original_main_replies())

func failure() -> Dictionary:
	return _fault.duplicate(true)

func actual_current_original_event() -> Dictionary:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	return _held.events[_next_event].duplicate(true) if not _held.is_empty() and _next_event<_held.events.size() else {}
func flush_original_main_replies() -> Dictionary:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	return _dispatcher.flush_original_main_replies() if _dispatcher.has_method("flush_original_main_replies") else {"status":"READY"}


func actual_current_original_prefix() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _held.is_empty() or _next_event >= _held.events.size(): return {}
	return _held.main_prefix.duplicate(true)
