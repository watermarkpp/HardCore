extends RefCounted

const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")

# Main-only weak provenance index. It owns no Resource, work queue or service
# cadence; physical leases remain their existing owners of actual references.
static var _original_physical_leases: Dictionary = {}
var _original_physical_lease_id := 0

var _domain_thread := 0
var _domain_publication: Dictionary = {}
var _domain_retention := 0
var _domain_paths: Array = []
var _domain_owner := WeakRef.new()
var _signature := ""
var _catalog_revision := ""
var _enabled_modules: Array = []
var _resources: Dictionary = {}
var _owner: WeakRef
var _diagnostics: Dictionary = {}

static func requirements(catalog: Dictionary, enabled: Array) -> Dictionary:
	var paths := {}
	var selected := enabled.duplicate()
	selected.sort()
	for id: Variant in selected:
		if not id is String or not catalog.get("modules", {}).has(id):
			return {"success":false, "errors":["feature_resource_unknown_module"]}
		var module: Dictionary = catalog.modules[id]
		for dependency: String in module.requires:
			if dependency not in selected:
				return {"success":false, "errors":["feature_disabled_dependency:" + id + ":" + dependency]}
		for path: String in module.resource_dependencies: paths[path] = true
	var ordered: Array = paths.keys()
	ordered.sort()
	return {"success":true, "paths":ordered, "catalog_revision":catalog.get("revision", ""), "enabled_modules":selected,
		"signature":JSON.stringify([catalog.get("revision", ""), selected, ordered]).sha256_text(), "errors":[]}

static func issue(plan: Dictionary, resources: Dictionary, owner: Node, diagnostics: Dictionary) -> RefCounted:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return null
	if not bool(plan.get("success", false)) or resources.size() != plan.paths.size(): return null
	for path: String in plan.paths:
		var resource: Variant = resources.get(path)
		if not Registry.valid_resource(path, resource):
			return null
	var result := new()
	result._signature = plan.signature
	result._catalog_revision = plan.catalog_revision
	result._enabled_modules = plan.enabled_modules.duplicate()
	result._enabled_modules.make_read_only()
	result._resources = resources.duplicate(false)
	result._resources.make_read_only()
	result._owner = weakref(owner)
	result._diagnostics = diagnostics.duplicate(true)
	result._original_physical_lease_id = result.get_instance_id()
	_original_physical_leases[result._original_physical_lease_id] = weakref(result)
	return result

func valid_for(catalog: Dictionary, enabled: Array) -> bool:
	var plan := requirements(catalog, enabled)
	return bool(plan.success) and plan.signature == _signature and plan.paths.size() == (_domain_paths.size() if is_domain() else _resources.size())

func resource_at(path: String) -> Resource:
	if is_domain():
		_domain_owner.get_ref().call("fault", "feature_resource_object_access_from_s", {"path":path})
		return null
	return _resources.get(path)

static func supports_bindings(resources: RefCounted, bindings: Array) -> bool:
	# A typed lease alone is insufficient: every declared possible cue must
	# already be held before acceptance or a one-shot producer claim.
	for binding: Dictionary in bindings:
		var definition: Dictionary = binding.definition
		if not definition.has("cue_id"): continue
		var required := preload("res://scripts/features/presentation/cue_definitions.gd").requirements(definition.cue_id)
		if not required.success: return false
		for path: String in required.paths:
			if resources == null or not resources.supports_path(path): return false
	return true

func diagnostics() -> Dictionary:
	return _diagnostics.duplicate(true)

func retain_subset(catalog: Dictionary, enabled: Array) -> RefCounted:
	if is_domain(): return _retain_domain_subset(catalog, enabled)
	# Withdrawal can only retain already accepted modules/resources from the
	# same catalog. This cannot authorize a new grant or acquire a new path.
	var plan := requirements(catalog, enabled)
	if not bool(plan.success) or plan.catalog_revision != _catalog_revision or plan.paths.is_empty(): return null
	for id: String in plan.enabled_modules:
		if id not in _enabled_modules: return null
	var retained := {}
	for path: String in plan.paths:
		if not _resources.has(path): return null
		retained[path] = _resources[path]
	var owner: Node = _owner.get_ref() if _owner != null else null
	if not is_instance_valid(owner) or owner.is_queued_for_deletion(): return null
	return issue(plan, retained, owner, {"requested":0,"cache_hits":retained.size(),"threaded_completed":0,"joined_requests":0})

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _original_physical_lease_id != 0:
		# Drop only our weak index entry; the original retirement below still
		# owns and returns every physical Resource/Script exactly once.
		_original_physical_leases.erase(_original_physical_lease_id)
		_original_physical_lease_id = 0
	if what == NOTIFICATION_PREDELETE and _domain_code_main_lease != null:
		_domain_code_main_lease = null # Actual Main Lease PREDELETE returns original retirement facts in-place.
		_domain_code_resource = null
		return
	if what == NOTIFICATION_PREDELETE and _domain_retention > 0:
		assert(OS.get_thread_caller_id() == _domain_thread)
		var domain_owner: RefCounted = _domain_owner.get_ref() as RefCounted
		assert(domain_owner != null, "feature resource owner must outlive its admitted retention")
		if domain_owner != null and not bool(domain_owner.call("release_feature_resource_retention", _domain_publication.publication_id, _domain_retention)):
			domain_owner.call("fault", "feature_resource_retirement_not_accepted", {"retention_id":_domain_retention})
		_domain_retention = 0
		return
	if what != NOTIFICATION_PREDELETE or _owner == null or (_resources.is_empty() and _retained_code_resource == null): return
	var owner: Node = _owner.get_ref()
	if is_instance_valid(owner) and not owner.is_queued_for_deletion():
		var held: Dictionary = _resources.duplicate(false)
		if _retained_code_resource != null:
			held[_retained_code_resource.resource_path] = _retained_code_resource
		owner.retire_resources(held)


var _code_plan: RefCounted

static func issue_code_inputs(plan: RefCounted, resources: Dictionary, owner: Node, diagnostics: Dictionary) -> RefCounted:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return null
	if plan == null or not bool(plan.is_verified()) or resources.size() != plan.paths().size():
		return null
	for path: String in plan.paths():
		if not bool(plan.valid_asset(path, resources.get(path))):
			return null
	var result := new()
	result._code_plan = plan
	result._signature = plan.signature()
	result._resources = resources.duplicate(false)
	result._resources.make_read_only()
	result._owner = weakref(owner)
	result._diagnostics = diagnostics.duplicate(true)
	result._original_physical_lease_id = result.get_instance_id()
	_original_physical_leases[result._original_physical_lease_id] = weakref(result)
	return result

func valid_for_code(plan: RefCounted) -> bool:
	if _domain_code_main_lease != null: return bool(_domain_code_main_lease.valid_for_code(plan))
	if plan == null or _code_plan == null or not is_same(plan, _code_plan) or not bool(plan.is_verified()) or plan.signature() != _signature or _resources.size() != plan.paths().size():
		return false
	for path: String in plan.paths():
		if not bool(plan.valid_asset(path, _resources.get(path))):
			return false
	return true


# The same input lease pins the actual already-collected Script. No path cache,
# JSON certificate, or fresh acquisition entitlement is created by retention.
var _retained_code_resource: Script
var _retained_code_consumer: WeakRef
var _retained_code_source := ""
var _retained_shader_code: Dictionary = {}

func attach_loaded_code_resource(plan: RefCounted, resource: Object, consumer: Object, service: Object) -> bool:
	if _domain_code_main_lease != null:
		var accepted: bool = bool(_domain_code_main_lease.attach_loaded_code_resource(plan,resource,consumer,service))
		if accepted: _domain_code_resource = resource
		return accepted
	if _retained_code_resource != null:
		return is_same(plan, _code_plan) and loaded_code_retention_current(resource, consumer, service)
	if _owner == null or not is_same(_owner.get_ref(), service) or not valid_for_code(plan) or not bool(plan.valid_target(resource)) or not is_instance_valid(consumer):
		return false
	_retained_code_resource = resource as Script
	_retained_code_source = _retained_code_resource.source_code
	_retained_code_consumer = weakref(consumer)
	for path: String in _resources:
		_retained_shader_code[path] = (_resources[path] as Shader).code
	return true

func loaded_code_retention_current(resource: Object, consumer: Object, service: Object) -> bool:
	if _domain_code_main_lease != null: return bool(_domain_code_main_lease.loaded_code_retention_current(resource,consumer,service))
	if _owner == null or not is_same(_owner.get_ref(), service) or _code_plan == null or not bool(_code_plan.is_verified()) or _retained_code_consumer == null or not is_same(_retained_code_consumer.get_ref(), consumer) or not is_instance_valid(consumer) or not consumer.is_inside_tree() or consumer.is_queued_for_deletion():
		return false
	if _retained_code_resource == null or not is_same(resource, _retained_code_resource) or not is_same(ResourceLoader.get_cached_ref(_code_plan.target_path()), _retained_code_resource) or _retained_code_resource.source_code != _retained_code_source:
		return false
	for path: String in _resources:
		if not is_same(ResourceLoader.get_cached_ref(path), _resources[path]) or (_resources[path] as Shader).code != _retained_shader_code.get(path):
			return false
	return true

func transfer_loaded_code_retention(resource: Object, previous: Object, next_consumer: Object, service: Object) -> bool:
	if _domain_code_main_lease != null: return bool(_domain_code_main_lease.transfer_loaded_code_retention(resource,previous,next_consumer,service))
	if not loaded_code_retention_current(resource, previous, service) or not bool(_code_plan.transfer_loaded_retention_context(previous, next_consumer, service)):
		return false
	_retained_code_consumer = weakref(next_consumer)
	return loaded_code_retention_current(resource, next_consumer, service)


func is_domain() -> bool: return _domain_retention > 0

func supports_path(path: String) -> bool:
	if not is_domain(): return Registry.valid_resource(path, resource_at(path))
	assert(OS.get_thread_caller_id() == _domain_thread)
	return path in _domain_paths and bool(_domain_owner.get_ref().call("feature_resource_retention_supports_path", _domain_publication.publication_id, _domain_retention, path))

func domain_publication() -> Dictionary:
	assert(is_domain() and OS.get_thread_caller_id() == _domain_thread)
	return _domain_publication

func domain_retention_id() -> int:
	assert(is_domain() and OS.get_thread_caller_id() == _domain_thread)
	return _domain_retention

static func issue_domain(plan: Dictionary, publication: Dictionary, owner: RefCounted, diagnostics: Dictionary) -> RefCounted:
	const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
	if OS.get_thread_caller_id() == OS.get_main_thread_id() or owner == null or owner is Resource or plan.get("success") != true:
		return null
	for method: String in ["retain_feature_resource_publication", "release_feature_resource_retention", "feature_resource_retention_supports_path", "fault"]:
		if not owner.has_method(method): return null
	if not publication.get("publication_id") is int or publication.publication_id <= 0 or publication.get("contract_id") != "hardcore.feature.resource_publication.v1" \
		or publication.get("signature") != plan.get("signature") or publication.get("catalog_revision") != plan.get("catalog_revision") \
		or publication.get("enabled_modules") != plan.get("enabled_modules") or publication.get("paths") != plan.get("paths"):
		return null
	var captured := Graph.capture(publication)
	if not captured.success: return null
	var retained: Variant = owner.call("retain_feature_resource_publication", captured.value)
	if not retained is Dictionary or retained.get("success") != true or not retained.get("retention_id") is int or retained.retention_id <= 0: return null
	var result := new()
	result._domain_thread = OS.get_thread_caller_id()
	result._domain_owner = weakref(owner)
	result._domain_publication = captured.value
	result._domain_retention = retained.retention_id
	result._domain_paths = plan.paths.duplicate()
	result._domain_paths.make_read_only()
	result._signature = plan.signature
	result._catalog_revision = plan.catalog_revision
	result._enabled_modules = plan.enabled_modules.duplicate()
	result._enabled_modules.make_read_only()
	result._diagnostics = diagnostics.duplicate(true)
	for path: String in result._domain_paths:
		if not result.supports_path(path): return null
	return result

static func issue_domain_preaccepted(plan: Dictionary, publication: Dictionary, owner: RefCounted, diagnostics: Dictionary, main_reference: RefCounted, retention: int) -> RefCounted:
	# LIVE construction consumes an actual earlier Main grant and every actual
	# path-support receipt. It never performs a synchronous Main acquisition.
	if OS.get_thread_caller_id() == OS.get_main_thread_id() or owner == null or main_reference == null or retention <= 0 or plan.get("success") != true: return null
	if publication.size() != 6 or publication.get("contract_id") != "hardcore.feature.resource_publication.v1" or publication.get("publication_id",0) <= 0 or publication.get("signature") != plan.get("signature") or publication.get("catalog_revision") != plan.get("catalog_revision") or publication.get("enabled_modules") != plan.get("enabled_modules") or publication.get("paths") != plan.get("paths"): return null
	for path: String in plan.paths:
		if not owner.feature_resource_retention_supports_path(publication.publication_id,retention,path): return null
	var captured: Dictionary = preload("res://scripts/features/contracts/plain_graph.gd").capture(publication)
	if captured.get("success") != true: return null
	var result: RefCounted = new()
	result._domain_thread = OS.get_thread_caller_id(); result._domain_owner = weakref(owner)
	result._domain_publication = captured.value; result._domain_retention = retention
	result._domain_paths = plan.paths.duplicate(); result._domain_paths.make_read_only()
	result._signature = plan.signature; result._catalog_revision = plan.catalog_revision
	result._enabled_modules = plan.enabled_modules.duplicate(); result._enabled_modules.make_read_only()
	result._diagnostics = diagnostics.duplicate(true); result._domain_main_reference = main_reference
	return result

func _retain_domain_subset(catalog: Dictionary, enabled: Array) -> RefCounted:
	assert(OS.get_thread_caller_id() == _domain_thread)
	var plan := requirements(catalog, enabled)
	if not bool(plan.success) or plan.catalog_revision != _catalog_revision or plan.paths.is_empty(): return null
	for id: String in plan.enabled_modules:
		if id not in _enabled_modules: return null
	for path: String in plan.paths:
		if not supports_path(path): return null
	var subset := _domain_publication.duplicate(false)
	subset["signature"] = plan.signature
	subset["enabled_modules"] = plan.enabled_modules
	subset["paths"] = plan.paths
	return issue_domain(plan, subset, _domain_owner.get_ref(), {"requested":0,"cache_hits":plan.paths.size(),"threaded_completed":0,"joined_requests":0})

## Same canonical FeatureResourceLease Script, actual Main CodePlan/lease
## references encoded by the unique feature primitive vault. Never shaders
## or Scripts masquerading as S resources. The same original Main lease
## validates, pins, transfers and retires the actual acquired refs.
var _domain_code_main_lease: RefCounted
var _domain_code_resource: Object
var _domain_main_reference: RefCounted
static func issue_code_inputs_domain(plan: RefCounted, main_lease: RefCounted, diagnostics: Dictionary) -> RefCounted:
	if OS.get_thread_caller_id() == OS.get_main_thread_id() or plan == null or main_lease == null or not bool(plan.is_verified()): return null
	var result := new()
	result._code_plan = plan
	result._domain_code_main_lease = main_lease
	result._signature = plan.signature()
	result._diagnostics = diagnostics.duplicate(true)
	return result

static func issue_code_inputs_domain_preaccepted(plan: RefCounted, main_lease: RefCounted, signature_value: String, diagnostics: Dictionary) -> RefCounted:
	# The originating Coordinator verifies the actual Main issue/valid_for_code
	# replies before construction. Calling the proxy here would reopen a scalar
	# external exchange and replay part of the original code job.
	if OS.get_thread_caller_id() == OS.get_main_thread_id() or plan == null or main_lease == null or signature_value.is_empty(): return null
	var result: RefCounted = new()
	result._code_plan = plan; result._domain_code_main_lease = main_lease
	result._signature = signature_value; result._diagnostics = diagnostics.duplicate(true)
	return result


static func capture_original_physical_owner_leases(owner: Node) -> Array:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not is_instance_valid(owner): return []
	var result: Array = []
	for id: int in _original_physical_leases.keys():
		var lease: RefCounted = _original_physical_leases[id].get_ref()
		if lease == null:
			_original_physical_leases.erase(id)
			continue
		if lease._original_physical_lease_id == id and lease._owner != null and lease._owner.get_ref() == owner:
			result.append(lease)
	return result

static func rebind_original_physical_owner(previous: Node, successor: Node, expected: Array) -> bool:
	# Low-level physical-reference transaction. Its caller must separately prove
	# Source admission and original coordinator quiescence; success here is NOT
	# a claim that S has accepted any new retirement job.
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not is_instance_valid(previous) or not is_instance_valid(successor) or previous == successor: return false
	if not previous.is_inside_tree() or previous.is_queued_for_deletion() or not successor.is_inside_tree() or successor.is_queued_for_deletion() or previous.get_tree() != successor.get_tree(): return false
	if not successor.has_method("retire_resources"): return false
	var actual: Array = capture_original_physical_owner_leases(previous)
	if actual.size() != expected.size(): return false
	var seen: Dictionary = {}
	for value: Variant in expected:
		if not value is RefCounted or not actual.has(value): return false
		var id: int = value.get_instance_id()
		if seen.has(id) or value._original_physical_lease_id != id or value.is_domain() or value._domain_code_main_lease != null or value._owner == null or value._owner.get_ref() != previous: return false
		seen[id] = true
	# Validation of the entire set precedes any mutation; no await, callback,
	# load/get, Resource duplication or gameplay write occurs in this loop.
	for lease: RefCounted in actual: lease._owner = weakref(successor)
	return true
