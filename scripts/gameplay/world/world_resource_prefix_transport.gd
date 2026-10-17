extends RefCounted

## Decorates the real native transport only to bind the single journal producer.
## Resource endpoint continues to own its original budget scope and local stack.
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _host: Object
var _pending_prefix: Dictionary = {}

func _init(world: RefCounted, host: Object) -> void:
	assert(_owner != OS.get_main_thread_id() and host.is_class("HardCoreSimulationHost"))
	_world = weakref(world)
	_host = host
func owner_thread_id() -> int: return _owner
func capabilities() -> Dictionary: return _host.capabilities()
func next_original_operation_sequence() -> int: return _host.next_original_operation_sequence()
func completed_original_operation_sequence() -> int: return _host.completed_original_operation_sequence()
func ordered_main_prefix() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner and _pending_prefix.is_empty())
	_pending_prefix = _world.get_ref().freeze_original_main_prefix()
	if _pending_prefix.is_empty() or not _host.stage_original_main_prefix(_pending_prefix):
		_world.get_ref().fault("resource_original_main_prefix_rejected", {})
		return {}
	return _host.ordered_main_prefix()
func exchange_original_primitive(request: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner and not _pending_prefix.is_empty())
	var reply: Dictionary = _host.exchange_original_primitive(request)
	if not _world.get_ref().ack_original_main_prefix(reply.get("native_main_prefix_receipt", {}), _pending_prefix):
		_world.get_ref().fault("resource_original_main_prefix_ack_rejected", {})
		return {}
	_pending_prefix = {}
	return reply

func next_original_call_ordinal(site: Dictionary) -> int: return int(_host.next_original_call_ordinal(site))

func finish_original_call_site(site: Dictionary) -> bool: return _host.finish_original_call_site(site)

func is_original_operation_completed(identity: Dictionary) -> bool: return _host.is_original_operation_completed(identity)
