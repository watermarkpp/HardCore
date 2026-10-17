extends RefCounted

## A scheduler job belongs either to a canonical actor or to the original
## polygon driver's independent canonical service Object. Never alias them.
var _owner := OS.get_thread_caller_id()
var _actors: RefCounted
var _services: RefCounted
var _drivers: Dictionary = {}
var _configured := false

class ServiceLink:
	extends RefCounted
	var source_id: int

func configure_owner(actor_access: RefCounted, service_registry: RefCounted) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner:
		push_error("navigation job access configured twice or on another owner")
		return false
	for provider in [actor_access, service_registry]:
		if provider == null or not provider.has_method("owner_thread_id") or provider.owner_thread_id() != _owner:
			push_error("navigation access requires same-owner canonical registries")
			return false
	if not service_registry.has_method("resolve_service"):
		push_error("canonical service registry resolve_service is missing")
		return false
	_actors = actor_access
	_services = service_registry
	_configured = true
	return true

func owner_thread_id() -> int:
	return _owner

func register_driver(service_handle: Object, driver: RefCounted) -> bool:
	assert(_configured and OS.get_thread_caller_id() == _owner)
	if service_handle == null or service_handle is Node or service_handle is RefCounted:
		push_error("polygon driver requires independent canonical Object handle")
		return false
	var source_id := service_handle.get_instance_id()
	if source_id <= 0 or _services.resolve_service(source_id) != service_handle or _drivers.has(source_id):
		push_error("unknown, duplicate or noncanonical polygon service identity")
		return false
	if driver == null or driver.owner_thread_id() != _owner:
		push_error("polygon driver belongs to another owner")
		return false
	_drivers[source_id] = weakref(driver)
	return true

func unregister_driver(service_handle: Object, driver: RefCounted) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	var source_id := service_handle.get_instance_id()
	assert(_drivers.has(source_id) and _drivers[source_id].get_ref() == driver)
	_drivers.erase(source_id)

func _driver_id(value: Object) -> int:
	for source_id: int in _drivers:
		if _drivers[source_id].get_ref() == value and value != null:
			return source_id
	return 0

func present(value: Object) -> bool:
	assert(_configured and OS.get_thread_caller_id() == _owner)
	if value == null: return false
	var source_id := _driver_id(value)
	if source_id > 0: return _services.resolve_service(source_id) != null
	return _actors.canonical(value) != null and _actors.is_present(value)

func runtime_id(value: Object) -> int:
	assert(_configured and OS.get_thread_caller_id() == _owner)
	var source_id := _driver_id(value)
	if source_id > 0:
		assert(_services.resolve_service(source_id) != null)
		return source_id
	var handle: Object = _actors.canonical(value)
	assert(handle != null and handle.get_instance_id() > 0)
	return handle.get_instance_id()

func capture(value: Object) -> RefCounted:
	var source_id := _driver_id(value)
	if source_id > 0:
		var link := ServiceLink.new()
		link.source_id = source_id
		return link
	return _actors.capture(value)

func resolve(link: RefCounted) -> Object:
	assert(_configured and OS.get_thread_caller_id() == _owner)
	if link is ServiceLink:
		if _services.resolve_service(link.source_id) == null or not _drivers.has(link.source_id):
			return null
		return _drivers[link.source_id].get_ref()
	return _actors.resolve(link)

func queued(value: Object) -> bool:
	var source_id := _driver_id(value)
	if source_id > 0:
		return _services.resolve_service(source_id).is_queued_for_retirement()
	return _actors.canonical(value).is_queued_for_retirement()

func invoke(value: Object, args: Array) -> Variant:
	assert(_configured and OS.get_thread_caller_id() == _owner and args.size() > 0)
	if _driver_id(value) > 0:
		assert(args[0] in [&"_hc_path_job_current", &"_hc_path_completed"])
		return value.callv(StringName(args[0]), args.slice(1))
	return _actors.invoke_call(_actors.view(_actors.canonical(value)), args)
