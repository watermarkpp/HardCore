extends RefCounted
const CanonicalServiceProcessScope := preload("res://scripts/gameplay/foundation/service_process_scope.gd")

## All actor identities are canonical Handles viewed through the existing
## Enemy access object. Only explicitly admitted nonactor process owners use
## a weak reference; they can never supply an actor ID or actor state.
var _owner := OS.get_thread_caller_id()
var _base: RefCounted
var _qualification_ref: WeakRef
var _qualification: RefCounted:
	get: return _qualification_ref.get_ref() if _qualification_ref != null else null
var _process_owners: Dictionary = {}
var _configured := false

class ProcessLink:
	extends RefCounted
	var owner_ref: WeakRef

func configure_owner(base: RefCounted, qualification: RefCounted) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner:
		push_error("service actor adapter configured twice or from another owner")
		return false
	for provider in [base, qualification]:
		if provider == null or not provider.has_method("owner_thread_id") or provider.owner_thread_id() != _owner:
			push_error("service actor adapter requires same-owner providers")
			return false
	for method in [&"canonical", &"view", &"capture", &"resolve", &"is_present", &"read_property", &"supports", &"invoke_call"]:
		if not base.has_method(method):
			push_error("base actor access ABI missing: " + str(method))
			return false
	for method in [&"actor_process_enabled", &"actor_is_character_body"]:
		if not qualification.has_method(method):
			push_error("independent actor qualification ABI missing: " + str(method))
			return false
	_base = base
	_qualification_ref = weakref(qualification)
	_configured = true
	return true

func owner_thread_id() -> int:
	return _owner

func _owned() -> void:
	assert(_configured and OS.get_thread_caller_id() == _owner)

func register_process_owner(value: RefCounted) -> bool:
	_owned()
	if value == null or not value.has_method("owner_thread_id") or value.owner_thread_id() != _owner:
		push_error("process owner must belong to the service owner")
		return false
	for method in [&"is_inside_world", &"is_queued_for_retirement", &"can_process", &"process_enabled", &"physics_enabled"]:
		if not value.has_method(method):
			push_error("process owner qualification missing: " + str(method))
			return false
	# WeakRef itself is the key: no separate actor/runtime ID is minted.
	for reference: WeakRef in _process_owners:
		if reference.get_ref() == value:
			return true
	_process_owners[weakref(value)] = true
	return true

func _is_process_owner(value: Object) -> bool:
	for reference: WeakRef in _process_owners:
		if reference.get_ref() == value and value != null:
			return true
	return false

func present(value: Variant) -> bool:
	_owned()
	if value == null:
		return false
	assert(value is Object and not value is Node and not value is Resource)
	if _is_process_owner(value):
		if value.get_script() == CanonicalServiceProcessScope:
			return value.runtime_object_is_present()
		return is_instance_valid(value)
	# A stale actor view resolves to null through its ActorLink. Other values
	# are checked for canonical registration, never accepted as plain Objects.
	return _base.canonical(value) != null and _base.is_present(value)

func capture(value: Object) -> RefCounted:
	_owned()
	if value == null:
		return null
	if _is_process_owner(value):
		var result := ProcessLink.new()
		result.owner_ref = weakref(value)
		return result
	return _base.capture(value)

func resolve(link: RefCounted) -> Object:
	_owned()
	if link == null:
		return null
	if link is ProcessLink:
		return (link as ProcessLink).owner_ref.get_ref()
	return _base.resolve(link)

func runtime_id(value: Object) -> int:
	_owned()
	assert(not _is_process_owner(value), "a service process owner is not an actor")
	var handle: Object = _base.canonical(value)
	assert(handle != null and handle.get_instance_id() > 0)
	return handle.get_instance_id()

func inside(value: Object) -> bool:
	_owned()
	if _is_process_owner(value): return value.is_inside_world()
	return _base.canonical(value).is_inside_world()

func queued(value: Object) -> bool:
	_owned()
	if _is_process_owner(value): return value.is_queued_for_retirement()
	return _base.canonical(value).is_queued_for_retirement()

func can_process(value: Object) -> bool:
	_owned()
	if _is_process_owner(value): return value.can_process()
	return _base.canonical(value).can_process()

func physics_enabled(value: Object) -> bool:
	_owned()
	if _is_process_owner(value): return value.physics_enabled()
	return _base.canonical(value).is_physics_processing_enabled()

func process_enabled(value: Object) -> bool:
	_owned()
	if _is_process_owner(value): return value.process_enabled()
	return _qualification.actor_process_enabled(_base.canonical(value))

func is_character_body(value: Object) -> bool:
	_owned()
	return _qualification.actor_is_character_body(_base.canonical(value))

func read(value: Object, key: StringName) -> Variant:
	_owned()
	return _base.read_property(value, key)

func supports(value: Object, method: StringName) -> bool:
	_owned()
	return _base.supports(_base.view(_base.canonical(value)), method)

func invoke(value: Object, arguments: Array) -> Variant:
	_owned()
	assert(not arguments.is_empty())
	assert(supports(value, StringName(arguments[0])), "unknown Enemy owner callback")
	return _base.invoke_call(_base.view(_base.canonical(value)), arguments)

func property_list(value: Object) -> Array[Dictionary]:
	_owned()
	return _base.view(_base.canonical(value)).get_property_list()
