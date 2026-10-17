extends Object

## Distinct canonical service ObjectID. No ActorHandle inheritance, HP, RNG,
## actor life writer, world counter or RefCounted ID stands in for a Node ID.
const CONTRACT_ID := "hardcore.execution.service_identity.v1"
var _owner_thread := OS.get_thread_caller_id()
var _registry_ref: WeakRef
var _scope_ref: WeakRef
var _model_ref: WeakRef
var _kind: StringName
var _bound := false
var _registered := true
var _retiring := false

func _init(registry: RefCounted, scope: RefCounted, kind: StringName) -> void:
	_registry_ref = weakref(registry)
	_scope_ref = weakref(scope)
	_kind = kind

func owner_thread_id() -> int:
	return _owner_thread

func _owned() -> bool:
	return OS.get_thread_caller_id() == _owner_thread

func _registry() -> RefCounted:
	return _registry_ref.get_ref() as RefCounted if _registry_ref != null else null

func source_scope() -> RefCounted:
	return _scope_ref.get_ref() as RefCounted if _owned() and _scope_ref != null else null

func bind_model(value: RefCounted) -> bool:
	if not _owned() or _bound or _retiring or value == null or value is Resource or not value.has_method("owner_thread_id") or value.owner_thread_id() != _owner_thread:
		return false
	_model_ref = weakref(value)
	_bound = true
	return true

func model() -> RefCounted:
	return _model_ref.get_ref() as RefCounted if _owned() and _model_ref != null else null

func kind() -> StringName:
	return _kind if _owned() else &""

func _view() -> Dictionary:
	var registry: RefCounted = _registry()
	if not _owned() or registry == null:
		return {}
	return registry.read_service_scope(self)

func runtime_object_is_present() -> bool:
	if not _owned() or _retiring:
		return false
	var present := bool(_view().get("runtime_present", false))
	if _bound and model() == null:
		var registry: RefCounted = _registry()
		if present and registry != null:
			registry.report_premature_model_release(get_instance_id())
		return false
	return present

func is_registered() -> bool:
	return _owned() and _registered and runtime_object_is_present()

func is_inside_world() -> bool:
	return runtime_object_is_present() and bool(_view().get("inside_world", false))

func is_queued_for_retirement() -> bool:
	if not _owned():
		return true
	return bool(_view().get("queued_for_retirement", false))

func current_life() -> int:
	return int(_view().get("life_generation", 0)) if runtime_object_is_present() else 0

func parent_scope_id() -> int:
	return int(_view().get("parent_scope_id", 0)) if runtime_object_is_present() else 0

func can_process() -> bool:
	return runtime_object_is_present() and bool(_view().get("can_process", false))

func process_enabled() -> bool:
	return runtime_object_is_present() and bool(_view().get("process_processing_enabled", false))

func physics_enabled() -> bool:
	return runtime_object_is_present() and bool(_view().get("physics_processing_enabled", false))

func ordinary_p_enabled() -> bool:
	return runtime_object_is_present() and bool(_view().get("ordinary_p_enabled", false))

func raw_h_enabled() -> bool:
	return runtime_object_is_present() and bool(_view().get("raw_h_enabled", false))

func physics_priority() -> int:
	return int(_view().get("physics_priority", 0)) if runtime_object_is_present() else 0

func identity() -> Dictionary:
	var registry: RefCounted = _registry()
	if not runtime_object_is_present() or registry == null:
		return {}
	var world: Dictionary = registry.capture_world()
	if world.is_empty():
		return {}
	var result := {"contract_id": CONTRACT_ID, "service_id": get_instance_id(),
		"kind": String(_kind), "life_generation": current_life(), "world": world}
	result.make_read_only()
	return result

func runtime_service_view() -> Dictionary:
	if not runtime_object_is_present():
		return {}
	var view: Dictionary = _view().duplicate(false)
	view["service_id"] = get_instance_id()
	view["kind"] = String(_kind)
	view.make_read_only()
	return view

func begin_retirement() -> bool:
	if not _owned() or _retiring:
		return false
	_registered = false
	_retiring = true
	# Do not touch accepted model jobs, queue, callbacks or scope flags here.
	return true

func is_retiring() -> bool:
	return _owned() and _retiring
