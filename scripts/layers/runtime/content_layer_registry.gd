extends Node

signal expansion_state_changed(package_id: String, enabled: bool)
signal initial_load_finished(success: bool)
signal feature_catalog_changed

const FeatureCatalog := preload("res://scripts/features/compilation/feature_catalog.gd")
const FeatureAuthority := preload("res://scripts/features/adapters/feature_authority.gd")
const PlainGraph := preload("res://scripts/features/contracts/plain_graph.gd")
const FEATURE_REGISTRY := "res://assets/data/features/module_registry.json"
const FEATURE_AUTHORING_ROOT := "res://assets/data/features/"
var _feature_catalog := FeatureCatalog.new()
var _feature_authority: Dictionary = {}
var _feature_bindings: Array = []
var _enabled_feature_modules: Array = []
var feature_load_errors: Array = []
var _feature_publication_in_progress := false

const MANIFESTS := {
	"vanilla_core": "res://assets/data/layers/vanilla_core.json",
	"expansion_layer": "res://assets/data/layers/expansion_layer.json",
	"rule_systems": "res://assets/data/layers/rule_systems.json",
	"presentation_layer": "res://assets/data/layers/presentation_layer.json",
	"runtime_services": "res://assets/data/layers/runtime_services.json",
}

var manifests: Dictionary = {}
var enabled_expansions: Dictionary = {}
var load_errors: Array[String] = []
var merged_database: Dictionary = {}
var merge_diagnostics: Array[String] = []
var initial_load_deferred := OS.get_name() == "Android"
var _initial_load_started := false
var _initial_load_complete := false


func _ready() -> void:
	if not initial_load_deferred:
		ensure_loaded()


func is_loaded() -> bool:
	return _initial_load_complete


func ensure_loaded() -> bool:
	if _initial_load_complete:
		return true
	if _initial_load_started:
		return false
	_initial_load_started = true
	var success := reload_manifests()
	_initial_load_complete = success
	_initial_load_started = false
	initial_load_finished.emit(success)
	return success


func reload_manifests() -> bool:
	manifests.clear()
	enabled_expansions.clear()
	load_errors.clear()
	for layer_id: String in MANIFESTS:
		var parsed := _read_json(MANIFESTS[layer_id])
		if parsed.is_empty() or str(parsed.get("layer", "")) != layer_id:
			load_errors.append("五层清单无效：%s" % layer_id)
			continue
		manifests[layer_id] = parsed
	for package: Variant in manifest("expansion_layer").get("packages", []):
		if package is Dictionary:
			enabled_expansions[str(package.get("id", ""))] = bool(package.get("defaultEnabled", false))
	merged_database = build_merged_database()
	var success := load_errors.is_empty() and manifests.size() == MANIFESTS.size()
	_initial_load_complete = success
	return success


func manifest(layer_id: String) -> Dictionary:
	return manifests.get(layer_id, {})


# The feature directory is another explicit authoring lane in ContentLayers.
# It is loaded after autoload initialization, never by arbitrary script paths.
func ensure_feature_catalog() -> bool:
	if not _feature_catalog.catalog().is_empty():
		return true
	return reload_feature_catalog()


func reload_feature_catalog(registry_path: String = FEATURE_REGISTRY) -> bool:
	if _feature_publication_in_progress:
		feature_load_errors = ["feature_publication_in_progress"]
		return false
	# Definition/code registration belongs to startup or the interval after the
	# old world has completed its exit barrier, not a live map/attack callback.
	if bool(PlayerState.feature_publication_context().world_active):
		feature_load_errors = ["feature_directory_requires_world_retirement"]
		return false
	if not _feature_authoring_path(registry_path):
		feature_load_errors = ["untrusted_feature_registry_path:" + registry_path]
		return false
	var registry := _read_json(registry_path)
	var errors: Array[String] = []
	var compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
	if not compiler._keys(registry, ["schema_version", "modules", "bindings"], [], errors, "feature_registry") \
		or registry.get("schema_version") != 1 or not registry.get("modules") is Array or not registry.get("bindings") is Array:
		feature_load_errors = ["invalid_feature_registry"]
		return false
	var authority := FeatureAuthority.build()
	var modules: Array = []
	for entry: Variant in registry.modules:
		if not entry is Dictionary:
			errors.append("feature_module_entry_not_dictionary")
			continue
		if not compiler._keys(entry, ["module_id", "path"], [], errors, "feature_module_entry"):
			continue
		if not _feature_authoring_path(entry.path):
			errors.append("untrusted_feature_module_path:" + str(entry.path))
			continue
		var module := _read_json(entry.path)
		if module.get("module_id") != entry.module_id:
			errors.append("feature_module_identity:" + str(entry.module_id))
		modules.append(module)
	var candidate := FeatureCatalog.new()
	if not errors.is_empty() or not candidate.publish(modules, [], authority):
		feature_load_errors = errors + candidate.last_errors
		return false
	var bindings := PlainGraph.capture(registry.bindings)
	if not bool(bindings.success):
		feature_load_errors = bindings.errors
		return false
	var seen := {}
	for binding: Variant in bindings.value:
		if not binding is Dictionary:
			errors.append("feature_binding_not_dictionary")
			continue
		var kind: Variant = binding.get("kind")
		var key: String = "item_id" if kind in ["item", "embedded_item"] else ("skill_id" if kind == "skill" else "rule_id")
		if kind not in ["item", "embedded_item", "skill", "rule"] or not compiler._keys(binding, ["module_id", "kind", "mechanic_id", key], [], errors, "feature_binding"):
			continue
		var mechanic: Variant = candidate.catalog().mechanics.get(binding.mechanic_id)
		if not mechanic is Dictionary or mechanic.module_id != binding.module_id:
			errors.append("feature_binding_unknown_mechanic")
		if kind in ["item", "embedded_item"] and (not binding.item_id is String \
			or preload("res://scripts/identity/entity_registry.gd").resolve(binding.item_id, "item").is_empty() \
			or GameData.get_entity_record(binding.item_id).is_empty()):
			errors.append("feature_binding_unknown_item")
		if kind == "skill" and binding.skill_id not in authority.skill_ids:
			errors.append("feature_binding_unknown_skill")
		if kind == "rule" and (not binding.rule_id is String or not compiler._stable_id(binding.rule_id)):
			errors.append("feature_binding_unknown_rule")
		var handle := JSON.stringify(binding)
		if seen.has(handle):
			errors.append("duplicate_feature_binding")
		seen[handle] = true
	if not errors.is_empty():
		feature_load_errors = errors
		return false
	var enabled: Array = []
	for id: String in candidate.catalog().modules:
		if bool(candidate.catalog().modules[id].get("default_enabled", false)):
			enabled.append(id)
	return _publish_feature_configuration(candidate, authority, bindings.value, enabled)


func _publish_feature_configuration(candidate: RefCounted, authority: Dictionary, bindings: Array, enabled: Array) -> bool:
	if _feature_publication_in_progress:
		feature_load_errors = ["feature_publication_in_progress"]
		return false
	# Defaults, activation and withdrawal publish the same closed enabled set.
	# Registration alone never implicitly activates a required dependency.
	for selected: String in enabled:
		for dependency: String in candidate.catalog().modules[selected].requires:
			if dependency not in enabled:
				feature_load_errors = ["feature_disabled_dependency:" + selected + ":" + dependency]
				return false
	_feature_publication_in_progress = true
	var configuration := {"catalog":candidate.catalog(), "authority":authority,
		"bindings":bindings, "enabled_modules":enabled}
	var prepared: Dictionary = PlayerState._prepare_feature_configuration(configuration)
	if not bool(prepared.success):
		feature_load_errors = prepared.errors
		_feature_publication_in_progress = false
		return false
	# No yield or callbacks between these assignments. Observers see both the
	# effective directory and the validated actor result in the same generation.
	_feature_catalog = candidate
	_feature_authority = authority
	_feature_bindings = bindings
	_enabled_feature_modules = enabled
	PlayerState._commit_feature_configuration(prepared)
	feature_load_errors = []
	feature_catalog_changed.emit()
	_feature_publication_in_progress = false
	return true


func _feature_authoring_path(value: Variant) -> bool:
	# Definitions shipped by the project may register more L1 packages. Code
	# remains gated by the compiler's separate trusted-handler allowlist.
	if not value is String or not value.begins_with(FEATURE_AUTHORING_ROOT) or not value.ends_with(".json"):
		return false
	var relative: String = value.trim_prefix(FEATURE_AUTHORING_ROOT)
	if "\\" in relative or ":" in relative:
		return false
	for segment: String in relative.split("/", true):
		if segment.is_empty() or segment in [".", ".."]:
			return false
	for offset: int in range(relative.length()):
		if relative.unicode_at(offset) < 32:
			return false
	return true


func set_feature_module_enabled(id: String, enabled: bool) -> bool:
	if _feature_publication_in_progress:
		feature_load_errors = ["feature_publication_in_progress"]
		return false
	if not ensure_feature_catalog() or not _feature_catalog.catalog().modules.has(id):
		return false
	var candidate := _enabled_feature_modules.duplicate()
	if enabled == candidate.has(id):
		return false
	if enabled:
		var context := PlayerState.feature_publication_context()
		var boundary: String = _feature_catalog.catalog().modules[id].get("activation_boundary", "startup")
		if not bool(context.world_ready) or (boundary == "startup" and bool(context.world_active)):
			feature_load_errors = ["feature_activation_boundary:" + id + ":" + boundary]
			return false
		candidate.append(id)
	else:
		candidate.erase(id)
	candidate.sort()
	return _publish_feature_configuration(_feature_catalog, _feature_authority, _feature_bindings, candidate)


func feature_configuration() -> Dictionary:
	if not ensure_feature_catalog():
		return {}
	return {"catalog":_feature_catalog.catalog(), "authority":_feature_authority,
		"bindings":_feature_bindings, "enabled_modules":_enabled_feature_modules.duplicate()}


func vanilla_dataset(dataset_id: String) -> String:
	return str(manifest("vanilla_core").get("datasets", {}).get(dataset_id, ""))


func policy_override(override_id: String) -> Dictionary:
	var table := _read_json(vanilla_dataset("policyOverrides"))
	for record: Variant in table.get("records", []):
		if record is Dictionary and str(record.get("id", "")) == override_id:
			return record.duplicate(true)
	return {}


func set_expansion_enabled(package_id: String, enabled: bool) -> bool:
	if not enabled_expansions.has(package_id):
		return false
	if bool(enabled_expansions.get(package_id, false)) == enabled:
		return false
	enabled_expansions[package_id] = enabled
	merged_database = build_merged_database()
	expansion_state_changed.emit(package_id, enabled)
	return true


func is_expansion_enabled(package_id: String) -> bool:
	return bool(enabled_expansions.get(package_id, false))


func active_skin() -> Dictionary:
	var presentation := manifest("presentation_layer")
	return presentation.get("skins", {}).get(str(presentation.get("activeSkin", "")), {})


func build_merged_database(user_override: Dictionary = {}) -> Dictionary:
	merge_diagnostics.clear()
	var merged := {
		"schemaVersion": 1,
		"mergeOrder": ["vanilla_core", "expansion_layer", "user_override"],
		"activeExpansions": [],
	}
	for table_id: String in ["maps", "monsters", "bosses", "items", "skills", "drops", "tasks"]:
		var table := _read_json(vanilla_dataset(table_id))
		merged[table_id] = table.get("records", []).duplicate(true)
	for package: Variant in manifest("expansion_layer").get("packages", []):
		if not package is Dictionary:
			continue
		var package_id := str(package.get("id", ""))
		if not is_expansion_enabled(package_id):
			continue
		merged["activeExpansions"].append(package_id)
		_apply_expansion_package(merged, package)
	_apply_user_override(merged, user_override)
	return merged


func _apply_expansion_package(merged: Dictionary, package: Dictionary) -> void:
	var package_path := str(package.get("data", ""))
	var package_manifest := _read_json(package_path)
	if package_manifest.has("tables"):
		var base_directory := package_path.get_base_dir()
		var merge_policy := str(package_manifest.get("mergePolicy", package.get("mergePolicy", "add_only")))
		for table_id: String in package_manifest.get("tables", {}):
			if not merged.has(table_id):
				continue
			var table := _read_json(base_directory.path_join(str(package_manifest.tables[table_id])))
			for record: Variant in table.get("records", []):
				if record is Dictionary:
					_merge_record(merged[table_id], record, table_id, merge_policy, str(package.get("id", "")))


func _merge_record(target: Array, record: Dictionary, table_id: String, merge_policy: String, package_id: String) -> void:
	var record_id := _record_id(record, table_id)
	var existing_index := -1
	for index in range(target.size()):
		if _record_id(target[index], table_id) == record_id and not record_id.is_empty():
			existing_index = index
			break
	if existing_index < 0:
		target.append(record.duplicate(true))
		return
	if merge_policy != "explicit_override" or str(record.get("overrideTargetId", "")) != record_id:
		merge_diagnostics.append("扩展冲突被拒绝：%s/%s/%s" % [package_id, table_id, record_id])
		return
	var combined: Dictionary = target[existing_index].duplicate(true)
	combined.merge(record, true)
	combined["contentLayer"] = "expansion_layer"
	combined["overridesVanillaId"] = record_id
	target[existing_index] = combined


func _record_id(record: Dictionary, table_id: String) -> String:
	var keys: Dictionary = {
		"maps": ["id", "mapId"], "monsters": ["id", "monsterId", "name"],
		"bosses": ["id", "monsterId", "name"], "items": ["id", "itemId", "name"],
		"skills": ["id", "skillName"], "drops": ["id"], "tasks": ["id", "taskId"],
	}
	for key: String in keys.get(table_id, ["id"]):
		if record.has(key):
			return str(record[key])
	return ""


func enabled_package_ids() -> Array[String]:
	var result: Array[String] = []
	for package_id: String in enabled_expansions:
		if bool(enabled_expansions[package_id]):
			result.append(package_id)
	result.sort()
	return result


func _apply_user_override(merged: Dictionary, user_override: Dictionary) -> void:
	for table_id: String in user_override:
		if merged.has(table_id) and user_override[table_id] is Array:
			for record: Variant in user_override[table_id]:
				if record is Dictionary:
					merged[table_id].append(record.duplicate(true))


func architecture_status() -> Dictionary:
	return {
		"valid": _initial_load_complete and load_errors.is_empty() and manifests.size() == 5,
		"loaded": _initial_load_complete,
		"layers": manifests.keys(),
		"enabledExpansions": enabled_expansions.duplicate(true),
		"mergedCounts": {
			"maps": merged_database.get("maps", []).size(),
			"monsters": merged_database.get("monsters", []).size(),
			"items": merged_database.get("items", []).size(),
		},
		"errors": load_errors.duplicate(),
		"mergeDiagnostics": merge_diagnostics.duplicate(),
	}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}
