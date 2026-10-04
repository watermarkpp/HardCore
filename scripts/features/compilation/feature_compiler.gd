extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Cues := preload("res://scripts/features/presentation/cue_definitions.gd")
const Handlers := preload("res://scripts/features/handlers/handler_registry.gd")
const BUILTIN_HANDLERS := Handlers.IDS
const MODULE_REQUIRED := ["schema_version", "module_id", "module_version", "core_api_version",
	"requires", "conflicts", "capabilities", "handlers", "resource_dependencies", "cost", "mechanics", "tests"]
const MODULE_OPTIONAL := ["default_enabled", "scope", "activation_boundary", "content_hash"]

# Complete derived child work is assessed before any action is promised.
# This pure helper does not itself publish handlers or grant runtime admission.
static func compile_child_capacity(request: Variant, limits: Variant) -> Dictionary:
	return preload("res://scripts/features/compilation/child_capacity_proof.gd").compile(request,limits)

# This is a compiler of immutable derived records. Canonical base definitions
# remain owned by ContentLayers and their existing rules, never by this catalog.
static func compile(modules: Array, contributions: Array, authority: Dictionary) -> Dictionary:
	var catalog_result := compile_catalog(modules, authority)
	if not bool(catalog_result.success):
		return catalog_result
	return compile_loadout(catalog_result.catalog, contributions, authority)

static func compile_catalog(modules: Array, authority: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if not _authority_valid(authority, errors):
		return _failure(errors)
	var owned := Graph.capture(modules)
	if not bool(owned.success):
		return _failure(owned.errors)
	var by_module := {}
	var mechanics := {}
	for candidate: Variant in owned.value:
		if not candidate is Dictionary:
			errors.append("module_not_dictionary")
			continue
		if not _keys(candidate, MODULE_REQUIRED, MODULE_OPTIONAL, errors, "module"):
			continue
		var module: Dictionary = candidate
		var module_id := str(module.get("module_id", ""))
		if not module.module_id is String or not _stable_id(module_id):
			errors.append("invalid_module_id:" + module_id)
		if by_module.has(module_id):
			errors.append("duplicate_module_id:" + module_id)
			continue
		by_module[module_id] = module
		if not _integer(module.schema_version, 1, 1) or not _integer(module.module_version, 1, 2147483647):
			errors.append("unsupported_module_version:" + module_id)
		if not _integer(module.core_api_version, 1, 2147483647) or module.core_api_version != authority.core_api_version:
			errors.append("incompatible_core_api:" + module_id)
		for list_key: String in ["requires", "conflicts", "capabilities", "handlers", "resource_dependencies", "tests"]:
			_strings(module[list_key], errors, module_id + ":" + list_key)
		if module.has("default_enabled") and not module.default_enabled is bool:
			errors.append("invalid_default_enabled:" + module_id)
		if module.has("scope") and module.scope not in ["global", "character", "world", "equipment"]:
			errors.append("invalid_scope:" + module_id)
		if module.has("activation_boundary") and module.activation_boundary not in ["startup", "world_ready"]:
			errors.append("invalid_activation_boundary:" + module_id)
		if module.has("content_hash"):
			if not _hash_valid(module.content_hash):
				errors.append("invalid_content_hash:" + module_id)
			else:
				var hash_input := module.duplicate(false)
				hash_input.erase("content_hash")
				if JSON.stringify(hash_input).sha256_text() != module.content_hash:
					errors.append("content_hash_mismatch:" + module_id)
		if not errors.is_empty():
			continue
		for capability: String in module.capabilities:
			if capability not in authority.capabilities:
				errors.append("ungranted_capability:" + capability)
		for handler: String in module.handlers:
			if handler not in BUILTIN_HANDLERS or handler not in authority.handler_ids:
				errors.append("untrusted_handler:" + handler)
		for path: String in module.resource_dependencies:
			if path not in authority.resource_paths:
				errors.append("missing_declared_resource:" + path)
		_validate_cost(module.cost, authority, errors, module_id)
		if not errors.is_empty():
			continue
		if not module.mechanics is Array:
			errors.append("mechanics_not_array:" + module_id)
			continue
		for mechanic: Variant in module.mechanics:
			if not mechanic is Dictionary:
				errors.append("mechanic_not_dictionary:" + module_id)
				continue
			if not _mechanic_valid(mechanic, module, authority, errors):
				continue
			var mechanic_id: String = mechanic.mechanic_id
			if mechanics.has(mechanic_id):
				errors.append("implicit_mechanic_override:" + mechanic_id)
				continue
			mechanics[mechanic_id] = {"module_id": module_id, "definition": mechanic, "cost": module.cost}
	for module_id: String in by_module:
		var module: Dictionary = by_module[module_id]
		if not module.requires is Array or not module.conflicts is Array:
			continue
		for dependency: Variant in module.requires:
			if not dependency is String or not by_module.has(dependency):
				errors.append("missing_dependency:" + str(dependency))
		for conflict: Variant in module.conflicts:
			if by_module.has(conflict):
				errors.append("module_conflict:" + module_id + ":" + str(conflict))
	var visiting := {}
	var visited := {}
	for module_id: String in by_module:
		_visit_dependency(module_id, by_module, visiting, visited, errors, 0)
	if errors.is_empty():
		for entry: Dictionary in mechanics.values():
			if entry.definition.has("cue_id") and not _cue_closure_valid(entry.module_id,entry.definition.cue_id,by_module):
				errors.append("missing_cue_resource_closure:" + entry.definition.cue_id)
	if not errors.is_empty():
		return _failure(errors)
	var catalog := {"schema_version": 1, "modules": by_module, "mechanics": mechanics,
		"revision": JSON.stringify(owned.value).sha256_text()}
	var frozen := Graph.capture(catalog)
	if not bool(frozen.success):
		return _failure(frozen.errors)
	return {"success": true, "catalog": frozen.value, "errors": []}

static func compile_loadout(catalog: Dictionary, contributions: Array, authority: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if not _authority_valid(authority, errors):
		return _failure(errors)
	if not _keys(catalog, ["schema_version", "modules", "mechanics", "revision"], [], errors, "catalog"):
		return _failure(errors)
	if catalog.schema_version != 1 or not catalog.modules is Dictionary or not catalog.mechanics is Dictionary or not _hash_valid(catalog.revision):
		return _failure(["invalid_compiled_catalog"])
	if contributions.size() > int(authority.max_sources):
		return _failure(["source_capacity"])
	var owned := Graph.capture(contributions)
	if not bool(owned.success):
		return _failure(owned.errors)
	var bindings := []
	var seen := {}
	for input: Variant in owned.value:
		if not input is Dictionary:
			errors.append("contribution_not_dictionary")
			continue
		if not _keys(input, ["source", "mechanic_id"], [], errors, "contribution"):
			continue
		if not input.mechanic_id is String or not catalog.mechanics.has(input.mechanic_id):
			errors.append("unknown_mechanic:" + str(input.mechanic_id))
			continue
		if not input.source is Dictionary:
			errors.append("source_not_dictionary")
			continue
		if not _keys(input.source,
			["slot", "instance_id", "mechanic_id"], ["extension_id"], errors, "source"):
			continue
		var source: Dictionary = input.source
		for key: String in source:
			if not source[key] is String or source[key].is_empty():
				errors.append("invalid_source_field:" + key)
		if source.mechanic_id != input.mechanic_id:
			errors.append("source_mechanic_mismatch")
		var handle := source_handle(source)
		if seen.has(handle):
			errors.append("duplicate_source_handle:" + handle)
		seen[handle] = true
		var selected := _selected_entry(catalog, input.mechanic_id, authority, errors)
		if not selected.is_empty():
			bindings.append({"source": source, "handle": handle, "mechanic": selected})
	if not errors.is_empty():
		return _failure(errors)
	bindings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.handle < b.handle)
	var bundle := {"catalog_revision": catalog.revision, "stat_operations": [], "skill_operations": {},
		"event_index": {}, "tags": {}, "capabilities": {}, "sources": {},
		"cost": {"commands_per_event": 0, "states_per_target": 0}}
	for binding: Dictionary in bindings:
		var definition: Dictionary = binding.mechanic.definition
		bundle.sources[binding.handle] = binding.source
		for tag: String in definition.tags:
			bundle.tags[tag] = int(bundle.tags.get(tag, 0)) + 1
		bundle.cost.commands_per_event += int(binding.mechanic.cost.commands_per_event)
		bundle.cost.states_per_target += int(binding.mechanic.cost.states_per_target)
		match definition.kind:
			"stat":
				for operation: Dictionary in definition.operations:
					var bound := operation.duplicate(false)
					bound["source"] = binding.source
					bundle.stat_operations.append(bound)
			"skill":
				for operation: Dictionary in definition.operations:
					var list: Array = bundle.skill_operations.get(operation.skill_id, [])
					var bound := operation.duplicate(false)
					bound["source"] = binding.source
					list.append(bound)
					bundle.skill_operations[operation.skill_id] = list
			"trigger":
				var event_key := event_index_key(definition.event, definition.skill_id)
				var list: Array = bundle.event_index.get(event_key, [])
				list.append({"definition": definition, "source": binding.source, "handle": binding.handle})
				bundle.event_index[event_key] = list
			"capability":
				bundle.capabilities[definition.capability] = int(bundle.capabilities.get(definition.capability, 0)) + 1
	if bundle.cost.commands_per_event > authority.max_commands_per_event or bundle.cost.states_per_target > authority.max_states_per_target:
		return _failure(["active_combination_capacity"])
	bundle["revision"] = (str(catalog.revision) + JSON.stringify(owned.value)).sha256_text()
	var frozen := Graph.capture(bundle)
	if not bool(frozen.success):
		return _failure(frozen.errors)
	return {"success": true, "bundle": frozen.value, "errors": []}

static func source_handle(source: Dictionary) -> String:
	return JSON.stringify([source.get("slot", ""), source.get("instance_id", ""),
		source.get("extension_id", ""), source.get("mechanic_id", "")])

static func event_index_key(event: String, skill_id: String) -> String:
	return event + ":" + skill_id

# Validate only referenced records. An inactive 10k-entry catalog never enters
# a hit lookup or this active-source traversal. Public callers may supply an
# untrusted dictionary, so a malformed entry must fail rather than crash.
static func _selected_entry(catalog: Dictionary, id: String, authority: Dictionary, errors: Array[String]) -> Dictionary:
	var raw: Variant = catalog.mechanics.get(id)
	if not raw is Dictionary or not _keys(raw, ["module_id", "definition", "cost"], [], errors, "compiled_entry"):
		errors.append("invalid_compiled_entry:" + id)
		return {}
	if not raw.module_id is String or not catalog.modules.get(raw.module_id) is Dictionary:
		errors.append("missing_selected_module:" + id)
		return {}
	var module: Dictionary = catalog.modules[raw.module_id]
	if not module.get("capabilities") is Array or not module.get("handlers") is Array or not module.get("cost") is Dictionary:
		errors.append("invalid_selected_module:" + id)
		return {}
	var header := Graph.capture({"capabilities":module.capabilities,"handlers":module.handlers,"cost":module.cost})
	var entry := Graph.capture(raw)
	if not bool(header.success) or not bool(entry.success):
		errors.append_array(header.errors)
		errors.append_array(entry.errors)
		return {}
	var initial := errors.size()
	_strings(header.value.capabilities, errors, "selected_capabilities")
	_strings(header.value.handlers, errors, "selected_handlers")
	for permission: Variant in header.value.capabilities:
		if permission not in authority.capabilities:
			errors.append("ungranted_selected_permission:" + str(permission))
	for handler: Variant in header.value.handlers:
		if handler not in BUILTIN_HANDLERS or handler not in authority.handler_ids:
			errors.append("untrusted_selected_handler:" + str(handler))
	_validate_cost(entry.value.cost, authority, errors, id)
	if entry.value.cost != header.value.cost:
		errors.append("selected_cost_mismatch:" + id)
	if not entry.value.definition is Dictionary or str(entry.value.definition.get("mechanic_id", "")) != id:
		errors.append("selected_mechanic_identity:" + id)
	else:
		_mechanic_valid(entry.value.definition, header.value, authority, errors)
		if entry.value.definition.has("cue_id") and entry.value.definition.cue_id is String \
			and not _cue_closure_valid(raw.module_id,entry.value.definition.cue_id,catalog.modules):
			errors.append("missing_selected_cue_resource_closure:" + id)
	return entry.value if errors.size() == initial else {}

static func _cue_closure_valid(module_id: String, cue_id: String, modules: Dictionary) -> bool:
	var required := Cues.requirements(cue_id)
	if not required.success: return false
	var paths := {}
	var visited := {}
	var pending: Array = [module_id]
	while not pending.is_empty():
		var id: Variant = pending.pop_back()
		if not id is String: return false
		if visited.has(id): continue
		visited[id] = true
		var module: Variant = modules.get(id)
		if not module is Dictionary or not module.get("resource_dependencies") is Array or not module.get("requires") is Array: return false
		for path: Variant in module.resource_dependencies:
			if not path is String: return false
			paths[path] = true
		pending.append_array(module.requires)
	for path: String in required.paths:
		if not paths.has(path): return false
	return true

static func _mechanic_valid(value: Dictionary, module: Dictionary, authority: Dictionary, errors: Array[String]) -> bool:
	var initial := errors.size()
	var kind: Variant = value.get("kind")
	var required := ["mechanic_id", "kind", "tags"]
	match kind:
		"stat", "skill": required.append("operations")
		"trigger": required.append_array(["event", "skill_id", "handler_id", "source_classes", "dedup", "config", "lifecycle"])
		"capability": required.append("capability")
		_: errors.append("unknown_mechanic_kind:" + str(kind)); return false
	if not _keys(value, required, ["cue_id"] if kind == "trigger" else [], errors, "mechanic"):
		return false
	if not value.mechanic_id is String or not _stable_id(value.mechanic_id):
		errors.append("invalid_mechanic_id")
	_strings(value.tags, errors, "mechanic_tags")
	if authority.has("tag_keys") and value.tags is Array:
		for tag: Variant in value.tags:
			if tag not in authority.tag_keys:
				errors.append("unknown_tag:" + str(tag))
	match kind:
		"stat", "skill":
			var permission := "stats.contribute" if kind == "stat" else "skills.modify"
			if permission not in module.capabilities:
				errors.append("missing_mechanic_permission:" + permission)
			if not value.operations is Array or value.operations.is_empty():
				errors.append("invalid_operations")
			else:
				for operation: Variant in value.operations:
					_validate_operation(operation, kind, authority, errors)
		"trigger":
			var contract := Handlers.contract(str(value.handler_id))
			if contract.is_empty():
				errors.append("unknown_handler_contract"); return false
			if value.has("cue_id") and (not value.cue_id is String or Cues.definition(value.cue_id).is_empty()):
				errors.append("unknown_trigger_cue")
			if value.has("cue_id") and not contract.cue:
				errors.append("unsupported_handler_cue")
			if value.handler_id not in module.handlers or value.handler_id not in BUILTIN_HANDLERS:
				errors.append("undeclared_trigger_handler")
			for permission: String in contract.capabilities:
				if permission not in module.capabilities: errors.append("missing_trigger_permission:"+permission)
			if value.event != "damage_committed" or value.skill_id not in authority.skill_ids:
				errors.append("unknown_trigger_event_or_skill")
			if value.source_classes != ["direct"] or value.dedup != "per_target_per_release":
				errors.append("unsupported_trigger_chain")
			if value.lifecycle != contract.lifecycle:
				errors.append("unsupported_effect_lifecycle")
			if module.cost is Dictionary and (
				float(module.cost.get("commands_per_event", 0)) < int(contract.commands)
				or float(module.cost.get("states_per_target", 0)) < int(contract.states)):
				errors.append("undeclared_trigger_capacity")
			if value.handler_id == "hc.ignite.v1": _validate_ignite_config(value.config, errors)
			else: _validate_lifesteal_config(value.config,errors)
		"capability":
			if "actor.capabilities" not in module.capabilities or value.capability not in authority.get("actor_capability_ids", []):
				errors.append("unknown_actor_capability")
	return errors.size() == initial

static func _validate_operation(input: Variant, kind: String, authority: Dictionary, errors: Array[String]) -> void:
	if not input is Dictionary:
		errors.append("operation_not_dictionary")
		return
	var required := ["stat", "op", "value"] if kind == "stat" else ["skill_id", "field", "op", "value"]
	if not _keys(input, required, [], errors, "operation"):
		return
	if input.op not in ["add", "multiply"] or not _number(input.value):
		errors.append("invalid_numeric_operation")
	if input.op == "multiply" and _number(input.value) and float(input.value) < 0.0:
		errors.append("negative_multiplier")
	if kind == "stat":
		if input.stat not in authority.stat_keys:
			errors.append("unknown_stat:" + str(input.stat))
	else:
		if input.skill_id not in authority.skill_ids or input.field not in authority.get("skill_fields", []):
			errors.append("unknown_skill_or_field")

static func _validate_lifesteal_config(input: Variant, errors: Array[String]) -> void:
	if not input is Dictionary:
		errors.append("lifesteal_not_dictionary"); return
	if not _keys(input,["fraction"],[],errors,"lifesteal"): return
	if not _number(input.fraction) or float(input.fraction) <= 0 or float(input.fraction) > 1:
		errors.append("invalid_lifesteal_fraction")

static func _validate_ignite_config(input: Variant, errors: Array[String]) -> void:
	if not input is Dictionary:
		errors.append("ignite_not_dictionary")
		return
	if not _keys(input, ["chance", "fraction", "period_usec", "duration_usec", "max_ticks"], [], errors, "ignite"):
		return
	if not _number(input.chance) or float(input.chance) < 0.0 or float(input.chance) > 1.0:
		errors.append("invalid_proc_chance")
	if not _number(input.fraction) or float(input.fraction) <= 0.0 or float(input.fraction) > 1.0:
		errors.append("invalid_periodic_fraction")
	if not _integer(input.period_usec, 1, 2147483647) or not _integer(input.duration_usec, 1, 2147483647) or not _integer(input.max_ticks, 1, 1024):
		errors.append("invalid_periodic_time")
	elif int(input.duration_usec) < int(input.period_usec) or int(input.duration_usec) / int(input.period_usec) > int(input.max_ticks) or int(input.duration_usec) % int(input.period_usec) != 0:
		errors.append("periodic_tick_capacity")

static func _validate_cost(input: Variant, authority: Dictionary, errors: Array[String], label: String) -> void:
	if not input is Dictionary:
		errors.append("cost_not_dictionary:" + label)
		return
	if not _keys(input, ["commands_per_event", "states_per_target"], [], errors, "cost"):
		return
	for key: String in ["commands_per_event", "states_per_target"]:
		if not _integer(input[key], 0, 2147483647) or input[key] > authority["max_" + key]:
			errors.append("declared_capacity:" + label + ":" + key)

static func _visit_dependency(id: String, modules: Dictionary, visiting: Dictionary, visited: Dictionary, errors: Array[String], depth: int) -> void:
	if visited.has(id) or not modules.has(id):
		return
	if visiting.has(id) or depth > 64:
		errors.append("dependency_cycle_or_depth:" + id)
		return
	visiting[id] = true
	if modules[id].requires is Array:
		for dependency: Variant in modules[id].requires:
			if dependency is String:
				_visit_dependency(dependency, modules, visiting, visited, errors, depth + 1)
	visiting.erase(id)
	visited[id] = true

static func _authority_valid(value: Dictionary, errors: Array[String]) -> bool:
	if not _keys(value, ["core_api_version", "stat_keys", "skill_ids", "capabilities", "handler_ids", "resource_paths", "max_commands_per_event", "max_states_per_target", "max_sources"],
		["tag_keys", "skill_fields", "actor_capability_ids"], errors, "authority"):
		return false
	for key: String in ["core_api_version", "max_commands_per_event", "max_states_per_target", "max_sources"]:
		if not _integer(value[key], 1 if key == "core_api_version" else 0, 2147483647):
			errors.append("invalid_authority_capacity:" + key)
	for key: String in ["stat_keys", "skill_ids", "capabilities", "handler_ids", "resource_paths"]:
		_strings(value[key], errors, "authority:" + key)
	for key: String in ["tag_keys", "skill_fields", "actor_capability_ids"]:
		if value.has(key):
			_strings(value[key], errors, "authority:" + key)
	return errors.is_empty()

static func _hash_valid(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true

static func _keys(value: Dictionary, required: Array, optional: Array, errors: Array[String], label: String) -> bool:
	var initial := errors.size()
	for key: Variant in value:
		if key not in required and key not in optional:
			errors.append("unknown_" + label + "_field:" + str(key))
	for key: String in required:
		if not value.has(key):
			errors.append("missing_" + label + "_field:" + key)
	return errors.size() == initial

static func _strings(value: Variant, errors: Array[String], label: String) -> void:
	if not value is Array:
		errors.append("not_string_array:" + label)
		return
	var seen := {}
	for item: Variant in value:
		if not item is String:
			errors.append("invalid_string:" + label)
			continue
		if item.is_empty() or seen.has(item):
			errors.append("invalid_or_duplicate_string:" + label)
		seen[item] = true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _stable_id(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$")
	return pattern.search(value) != null

static func _failure(errors: Array) -> Dictionary:
	return {"success": false, "errors": errors, "catalog": {}, "bundle": {}}
