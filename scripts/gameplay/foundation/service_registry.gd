extends RefCounted

const Handle := preload("res://scripts/gameplay/foundation/service_handle.gd")
const ProcessScope := preload("res://scripts/gameplay/foundation/service_process_scope.gd")
const WorldContext := preload("res://scripts/layers/runtime/execution/world_context.gd")
const ActorRegistry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
const KINDS: Array[StringName] = [&"polygon_pursuit_driver", &"path_scheduler", &"monster_visual", &"node_timer", &"feature_resource_preparation", &"m30_summon_queue", &"loot_runtime_manager", &"player_visual"]
const SCOPE_FIELDS := {
	"runtime_present": TYPE_BOOL, "life_generation": TYPE_INT,
	"inside_world": TYPE_BOOL, "queued_for_retirement": TYPE_BOOL,
	"parent_scope_id": TYPE_INT, "can_process": TYPE_BOOL,
	"process_processing_enabled": TYPE_BOOL, "physics_processing_enabled": TYPE_BOOL,
	"ordinary_p_enabled": TYPE_BOOL, "raw_h_enabled": TYPE_BOOL, "physics_priority": TYPE_INT,
}
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var _context_ref: WeakRef
var _scopes_ref: WeakRef
var _faults_ref: WeakRef
var _handles: Dictionary = {}
var _process_views: Dictionary = {}

func owner_thread_id() -> int:
	return _owner_thread

func _owned() -> bool:
	return _configured and OS.get_thread_caller_id() == _owner_thread and _owner_thread != OS.get_main_thread_id()

func _fault(code: String, details: Dictionary) -> void:
	var sink: Object = _faults_ref.get_ref() if _faults_ref != null else null
	if sink != null and OS.get_thread_caller_id() == _owner_thread:
		sink.fault(code, details)

func configure_owner(context: RefCounted, scope_provider: RefCounted, fault_sink: RefCounted) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread or _owner_thread == OS.get_main_thread_id():
		return false
	if context == null or context.get_script() != WorldContext or not context.has_method("capture_world") or not context.has_method("matches_world"):
		return false
	# Original context must delegate to the actual S ActorRegistry. A legacy
	# WorldContext backed by Main Nodes is explicitly rejected.
	var registry: Variant = context.get("_domain_registry")
	if not registry is RefCounted or registry is Resource or registry.get_script() != ActorRegistry or registry.get("_owner_thread") != _owner_thread or context.capture_world().is_empty():
		return false
	for port: RefCounted in [scope_provider, fault_sink]:
		if port == null or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id() != _owner_thread:
			return false
	for method: String in ["service_scope_view", "queue_service_retirement", "service_retirement_allowed", "service_final_free_allowed"]:
		if not scope_provider.has_method(method):
			return false
	if not fault_sink.has_method("fault"):
		return false
	_context_ref = weakref(context)
	_scopes_ref = weakref(scope_provider)
	_faults_ref = weakref(fault_sink)
	_configured = true
	return true

func capture_world() -> Dictionary:
	var context: RefCounted = _context_ref.get_ref() as RefCounted if _context_ref != null else null
	if not _owned() or context == null:
		_fault("service_world_context_unavailable", {})
		return {}
	var world: Dictionary = context.capture_world()
	if world.size() != 5 or world.get("contract_id") != "hardcore.execution.world_context.v1":
		_fault("service_original_world_identity_unavailable", {})
		return {}
	return world

## Called at original Node.new() position BEFORE WorldCore constructs the
## RefCounted driver/scheduler implementation. Root constructs/owns scope.
func allocate_service(kind: StringName, source_scope: RefCounted) -> Object:
	if not _owned() or kind not in KINDS or source_scope == null or source_scope is Resource or not source_scope.has_method("owner_thread_id") or source_scope.owner_thread_id() != _owner_thread:
		_fault("service_birth_invalid", {"kind": String(kind)})
		return null
	var handle: Object = Handle.new(self, source_scope, kind)
	var id: int = handle.get_instance_id()
	if id <= 0 or _handles.has(id):
		handle.free()
		_fault("service_birth_identity_conflict", {"id": id})
		return null
	_handles[id] = handle
	var view: Dictionary = read_service_scope(handle)
	if view.is_empty() or not view.runtime_present:
		_handles.erase(id)
		handle.free()
		_fault("service_birth_scope_invalid", {"id": id, "kind": String(kind)})
		return null
	return handle

## Original for_tree sets priority AFTER Node.new. Call this at that exact
## assignment/enter boundary, never require priority100 before identity birth.
func validate_priority100_scheduler(id: int) -> bool:
	var handle: Object = resolve_service(id)
	if handle == null or handle.kind() != &"path_scheduler" or handle.physics_priority() != 100:
		_fault("service_scheduler_priority100_missing", {"id": id})
		return false
	return true

func bind_service_model(handle: Object, model: RefCounted) -> bool:
	if not _owned() or handle == null or handle is Node or handle is RefCounted or _handles.get(handle.get_instance_id()) != handle or not handle.bind_model(model):
		_fault("service_model_binding_invalid", {})
		return false
	return true

func resolve_service(id: int) -> Object:
	if not _owned() or id <= 0:
		return null
	var handle: Object = _handles.get(id)
	return handle if is_instance_valid(handle) and handle.runtime_object_is_present() else null

func resolve_service_model(id: int) -> RefCounted:
	var handle: Object = resolve_service(id)
	return handle.model() if handle != null else null

## Original streaming subscriber check needs Node presence and queued status
## separately. A missing positive ID is canonical registry absence. When
## present=false, callers must short-circuit before using queued qualification.
func service_qualification(id: int) -> Dictionary:
	if not _owned() or id <= 0:
		_fault("service_qualification_identity_invalid", {"id": id})
		return {}
	var handle: Object = _handles.get(id)
	if not is_instance_valid(handle):
		var absent := {"present": false, "queued_for_retirement": false}
		absent.make_read_only()
		return absent
	var view: Dictionary = read_service_scope(handle)
	if view.is_empty():
		return {}
	var result := {"present": handle.runtime_object_is_present(),
		"queued_for_retirement": view.queued_for_retirement}
	result.make_read_only()
	return result

func service_model_runtime_present(model: RefCounted) -> bool:
	if not _owned() or model == null:
		return false
	for id: int in _handles:
		var handle: Object = _handles[id]
		if is_instance_valid(handle) and handle.model() == model:
			return handle.runtime_object_is_present()
	return false

func report_premature_model_release(id: int) -> void:
	if _owned():
		_fault("service_model_released_before_original_boundary", {"id": id})

func read_service_scope(handle: Object) -> Dictionary:
	if not _owned() or not is_instance_valid(handle) or handle is Node or handle is RefCounted or _handles.get(handle.get_instance_id()) != handle:
		return {}
	var provider: RefCounted = _scopes_ref.get_ref() as RefCounted if _scopes_ref != null else null
	var scope: RefCounted = handle.source_scope()
	if provider == null or scope == null:
		_fault("service_source_scope_unavailable", {"id": handle.get_instance_id()})
		return {}
	var view: Variant = provider.service_scope_view(scope, handle.get_instance_id(), handle.kind())
	if not view is Dictionary:
		_fault("service_source_scope_invalid", {"id": handle.get_instance_id()})
		return {}
	for field: String in SCOPE_FIELDS:
		if not view.has(field) or typeof(view[field]) != SCOPE_FIELDS[field]:
			_fault("service_source_scope_field_missing", {"id": handle.get_instance_id(), "field": field})
			return {}
	if view.life_generation <= 0 or view.parent_scope_id < 0:
		_fault("service_source_scope_life_parent_invalid", {"id": handle.get_instance_id()})
		return {}
	# Read-only observation. No flag is inferred from another or cached here.
	var result: Dictionary = {}
	for field: String in SCOPE_FIELDS:
		result[field] = view[field]
	result.make_read_only()
	return result

func process_scope_for_service(id: int) -> RefCounted:
	if resolve_service(id) == null:
		return null
	if not _process_views.has(id):
		_process_views[id] = ProcessScope.new(self, id)
	return _process_views[id]

func queue_service_retirement(id: int) -> bool:
	var handle: Object = resolve_service(id)
	var provider: RefCounted = _scopes_ref.get_ref() as RefCounted if _scopes_ref != null else null
	if handle == null or provider == null:
		return false
	var accepted: Variant = provider.queue_service_retirement(handle.source_scope(), id)
	if not accepted is bool:
		_fault("service_queue_boundary_invalid_result", {"id": id})
		return false
	return accepted

## Root invokes original Driver.retire/reset + job-access.unregister_driver,
## or Scheduler.retire budget unbind, BEFORE this exact source boundary.
func begin_service_retirement(id: int) -> bool:
	var handle: Object = resolve_service(id)
	var provider: RefCounted = _scopes_ref.get_ref() as RefCounted if _scopes_ref != null else null
	if handle == null or provider == null:
		_fault("service_original_retirement_boundary_not_ready", {"id": id})
		return false
	var allowed: Variant = provider.service_retirement_allowed(handle.source_scope(), id, handle.model())
	if not allowed is bool or not allowed:
		_fault("service_original_retirement_boundary_not_ready", {"id": id})
		return false
	return handle.begin_retirement()

## No lease/timer/automatic queue clearing extends service lifetime. Provider
## authorizes the actual source final-free point even if model-owned accepted
## task records remain; WorldCore then releases that model at the same point.
func final_free_service(id: int) -> bool:
	if not _owned():
		return false
	var handle: Object = _handles.get(id)
	var provider: RefCounted = _scopes_ref.get_ref() as RefCounted if _scopes_ref != null else null
	if not is_instance_valid(handle) or not handle.is_retiring() or provider == null:
		_fault("service_original_final_free_boundary_not_ready", {"id": id})
		return false
	var allowed: Variant = provider.service_final_free_allowed(handle.source_scope(), id, handle.model())
	if not allowed is bool or not allowed:
		_fault("service_original_final_free_boundary_not_ready", {"id": id})
		return false
	_process_views.erase(id)
	_handles.erase(id)
	# Match existing ActorRegistry manual positive ObjectID retirement.
	handle.free()
	return true

func remaining_service_count() -> int:
	return _handles.size() if _owned() else -1

func close_at_original_boundary() -> bool:
	if not _owned() or not _handles.is_empty():
		_fault("service_close_with_unretired_original_objects", {"remaining": _handles.size()})
		return false
	_process_views.clear()
	_configured = false
	return true
