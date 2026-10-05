extends RefCounted

const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")

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
	return result

func valid_for(catalog: Dictionary, enabled: Array) -> bool:
	var plan := requirements(catalog, enabled)
	return bool(plan.success) and plan.signature == _signature and plan.paths.size() == _resources.size()

func resource_at(path: String) -> Resource:
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
			if resources == null or not Registry.valid_resource(path,resources.resource_at(path)): return false
	return true

func diagnostics() -> Dictionary:
	return _diagnostics.duplicate(true)

func retain_subset(catalog: Dictionary, enabled: Array) -> RefCounted:
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
	if what != NOTIFICATION_PREDELETE or _owner == null or (_resources.is_empty() and _retained_code_resource == null): return
	var owner: Node = _owner.get_ref()
	if is_instance_valid(owner) and not owner.is_queued_for_deletion():
		var held: Dictionary = _resources.duplicate(false)
		if _retained_code_resource != null:
			held[_retained_code_resource.resource_path] = _retained_code_resource
		owner.retire_resources(held)


var _code_plan: RefCounted

static func issue_code_inputs(plan: RefCounted, resources: Dictionary, owner: Node, diagnostics: Dictionary) -> RefCounted:
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
	return result

func valid_for_code(plan: RefCounted) -> bool:
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

func attach_loaded_code_resource(plan: RefCounted, resource: Resource, consumer: Node, service: Node) -> bool:
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

func loaded_code_retention_current(resource: Resource, consumer: Node, service: Node) -> bool:
	if _owner == null or not is_same(_owner.get_ref(), service) or _code_plan == null or not bool(_code_plan.is_verified()) or _retained_code_consumer == null or not is_same(_retained_code_consumer.get_ref(), consumer) or not is_instance_valid(consumer) or not consumer.is_inside_tree() or consumer.is_queued_for_deletion():
		return false
	if _retained_code_resource == null or not is_same(resource, _retained_code_resource) or not is_same(ResourceLoader.get_cached_ref(_code_plan.target_path()), _retained_code_resource) or _retained_code_resource.source_code != _retained_code_source:
		return false
	for path: String in _resources:
		if not is_same(ResourceLoader.get_cached_ref(path), _resources[path]) or (_resources[path] as Shader).code != _retained_shader_code.get(path):
			return false
	return true

func transfer_loaded_code_retention(resource: Resource, previous: Node, next_consumer: Node, service: Node) -> bool:
	if not loaded_code_retention_current(resource, previous, service) or not bool(_code_plan.transfer_loaded_retention_context(previous, next_consumer, service)):
		return false
	_retained_code_consumer = weakref(next_consumer)
	return loaded_code_retention_current(resource, next_consumer, service)
