extends RefCounted

## Capability view for existing FrameBudget's RefCounted process-owner ABI.
## This view does not mint identity and does not retain a Handle/model/registry.
var _owner_thread := OS.get_thread_caller_id()
var _registry_ref: WeakRef
var _service_id := 0

func _init(registry: RefCounted, service_id: int) -> void:
	_registry_ref = weakref(registry)
	_service_id = service_id

func owner_thread_id() -> int:
	return _owner_thread

func service_id() -> int:
	return _service_id

func _handle() -> Object:
	if OS.get_thread_caller_id() != _owner_thread:
		return null
	var registry: RefCounted = _registry_ref.get_ref() as RefCounted if _registry_ref != null else null
	return registry.resolve_service(_service_id) if registry != null else null

func runtime_object_is_present() -> bool:
	return _handle() != null

func is_inside_world() -> bool:
	var handle: Object = _handle()
	return handle.is_inside_world() if handle != null else false

func is_queued_for_retirement() -> bool:
	var handle: Object = _handle()
	return handle.is_queued_for_retirement() if handle != null else true

func can_process() -> bool:
	var handle: Object = _handle()
	return handle.can_process() if handle != null else false

func process_enabled() -> bool:
	var handle: Object = _handle()
	return handle.process_enabled() if handle != null else false

func physics_enabled() -> bool:
	var handle: Object = _handle()
	return handle.physics_enabled() if handle != null else false

func ordinary_p_enabled() -> bool:
	var handle: Object = _handle()
	return handle.ordinary_p_enabled() if handle != null else false

func raw_h_enabled() -> bool:
	var handle: Object = _handle()
	return handle.raw_h_enabled() if handle != null else false

func parent_scope_id() -> int:
	var handle: Object = _handle()
	return handle.parent_scope_id() if handle != null else 0
