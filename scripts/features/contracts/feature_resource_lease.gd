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
	if what != NOTIFICATION_PREDELETE or _owner == null or _resources.is_empty(): return
	var owner: Node = _owner.get_ref()
	if is_instance_valid(owner) and not owner.is_queued_for_deletion():
		owner.retire_resources(_resources)
