extends RefCounted
## Stable injected endpoint. Only Loading may use the original parked stack.
## LIVE uses the separate immutable-ticket APIs on the same Host/ledger.
var _owner := OS.get_thread_caller_id()
var _session: WeakRef
var _host: Object
var _prefix_transport: RefCounted
func _init(session: RefCounted, host: Object, initial_transport: RefCounted) -> void:
	_session = weakref(session)
	_host = host
	_prefix_transport = initial_transport
func owner_thread_id() -> int: return _owner
func capabilities() -> Dictionary: return _host.capabilities()
func bind_current(transport: RefCounted) -> bool:
	if OS.get_thread_caller_id() != _owner or transport == null or transport.owner_thread_id() != _owner: return false
	_prefix_transport = transport
	return true
func next_original_operation_sequence() -> int: return _host.next_original_operation_sequence()
func completed_original_operation_sequence() -> int: return _host.completed_original_operation_sequence()
func next_original_call_ordinal(site: Dictionary) -> int: return _host.next_original_call_ordinal(site)
func ordered_main_prefix() -> Dictionary: return _prefix_transport.ordered_main_prefix()
func exchange_original_primitive(request: Dictionary) -> Dictionary:
	if not _session.get_ref().cold_resource_calls_allowed():
		_session.get_ref().fault("live_original_resource_park_forbidden", {"operation": request.get("operation")})
		assert(false, "LIVE caller must use accepted async continuation")
		return {}
	return _prefix_transport.exchange_original_primitive(request)
func finish_original_call_site(site: Dictionary) -> bool: return _host.finish_original_call_site(site)

func is_original_operation_completed(identity: Dictionary) -> bool: return _host.is_original_operation_completed(identity)
