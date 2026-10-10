extends Node

signal expansion_state_changed(package_id: String, enabled: bool)
signal initial_load_finished(success: bool)
signal feature_catalog_changed

const FeatureCatalog := preload("res://scripts/features/compilation/feature_catalog.gd")
const FeatureAuthority := preload("res://scripts/features/adapters/feature_authority.gd")
const PlainGraph := preload("res://scripts/features/contracts/plain_graph.gd")
const PreparedContentConfiguration := preload("res://scripts/layers/runtime/prepared_content_configuration.gd")
const FEATURE_REGISTRY := "res://assets/data/features/module_registry.json"
const FEATURE_AUTHORING_ROOT := "res://assets/data/features/"
var _feature_catalog := FeatureCatalog.new()
var _feature_authority: Dictionary = {}
var _feature_bindings: Array = []
var _enabled_feature_modules: Array = []
var feature_load_errors: Array = []
var _feature_publication_in_progress := false
var _feature_commit_in_progress := false
var _feature_preparation_sequence := 0
var _feature_resource_lease: RefCounted
var _feature_resource_service: Node

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
var last_expansion_error := ""
var _expansion_commit_in_progress := false
var configuration_revision := 0


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
	configuration_revision += 1
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
	if not _feature_reload_boundary(): return false
	var result := _read_feature_candidate(registry_path)
	if result.is_empty(): return false
	return _publish_feature_configuration(result.candidate, result.authority, result.bindings, result.enabled)


func _feature_reload_boundary() -> bool:
	if _feature_publication_in_progress:
		feature_load_errors = ["feature_publication_in_progress"]
		return false
	# Definition/code registration belongs to startup or the interval after the
	# old world has completed its exit barrier, not a live map/attack callback.
	if bool(PlayerState.feature_publication_context().world_active):
		feature_load_errors = ["feature_directory_requires_world_retirement"]
		return false
	return true


func reload_feature_catalog_async(registry_path: String = FEATURE_REGISTRY) -> bool:
	if not _feature_reload_boundary(): return false
	var result := _read_feature_candidate(registry_path)
	if result.is_empty(): return false
	_feature_preparation_sequence += 1
	var sequence := _feature_preparation_sequence
	var profile: String = PlayerState.active_profile_id
	_feature_publication_in_progress = true
	var service := _feature_resources()
	var ready: Dictionary = await service.prepare(result.candidate.catalog(), result.enabled)
	if sequence != _feature_preparation_sequence: return false
	if not bool(ready.success):
		_feature_publication_in_progress = false
		feature_load_errors = ready.errors
		return false
	return await _await_feature_application(service, Callable(self,"_apply_prepared_feature_candidate").bind(result, ready.lease, sequence, profile), sequence)


func _await_feature_application(service: Node, callback: Callable, sequence: int) -> bool:
	var success: bool = await service.apply_ready(callback)
	# Direct service cancellation may terminate a queued application before
	# its callback clears this request's lock. Never unlock a newer producer.
	if sequence == _feature_preparation_sequence and _feature_publication_in_progress:
		_feature_publication_in_progress = false
		feature_load_errors = ["feature_resource_application_cancelled"]
	return success


func _feature_resources() -> Node:
	if _feature_resource_service == null:
		_feature_resource_service = preload("res://scripts/features/runtime/feature_resource_preparation.gd").new()
		add_child(_feature_resource_service)
	return _feature_resource_service

## Transfer already-issued threaded ResourceLoader claims from a retiring
## scene owner into the shared feature service. The service never re-requests
## the path; it polls and joins the supplied user claims under its retirement
## budget.
func retire_threaded_resource_claims(path: String, claim_count: int) -> bool:
	if path.is_empty() or claim_count <= 0:
		return false
	return bool(_feature_resources().retire_threaded_resource_claims(path, claim_count))

func threaded_resource_claim_diagnostics() -> Dictionary:
	if _feature_resource_service == null:
		return {"accepted":0, "transferred":0, "get":0, "missing":0, "pending":0}
	return _feature_resource_service.threaded_claim_diagnostics()


func _apply_prepared_feature_candidate(result: Dictionary, resource_lease: RefCounted, sequence: int, profile: String) -> bool:
	if sequence != _feature_preparation_sequence: return false
	_feature_publication_in_progress = false
	if PlayerState.active_profile_id != profile or not _feature_reload_boundary():
		feature_load_errors = ["feature_resource_preparation_stale"]
		return false
	return _publish_feature_configuration(result.candidate, result.authority, result.bindings, result.enabled, resource_lease)


func cancel_feature_resource_preparation() -> void:
	# Synchronous promotion is no longer a cancellable preparation. Its
	# notification retains the publication lock and reports the committed result.
	if _feature_commit_in_progress or (_feature_resource_service != null and _feature_resource_service.is_applying()): return
	_feature_preparation_sequence += 1
	_feature_publication_in_progress = false
	if _feature_resource_service != null: _feature_resource_service.cancel_all()


func _read_feature_candidate(registry_path: String) -> Dictionary:
	if not _feature_authoring_path(registry_path):
		feature_load_errors = ["untrusted_feature_registry_path:" + registry_path]
		return {}
	var registry := _read_json(registry_path)
	var errors: Array[String] = []
	var compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
	if not compiler._keys(registry, ["schema_version", "modules", "bindings"], [], errors, "feature_registry") \
		or registry.get("schema_version") != 1 or not registry.get("modules") is Array or not registry.get("bindings") is Array:
		feature_load_errors = ["invalid_feature_registry"]
		return {}
	var declarations := preload("res://scripts/features/compilation/feature_resource_registry.gd").declarations()
	if not bool(declarations.success):
		feature_load_errors = declarations.errors
		return {}
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
		return {}
	var bindings := PlainGraph.capture(registry.bindings)
	if not bool(bindings.success):
		feature_load_errors = bindings.errors
		return {}
	var seen := {}
	for binding: Variant in bindings.value:
		if not binding is Dictionary:
			errors.append("feature_binding_not_dictionary")
			continue
		var kind: Variant = binding.get("kind")
		if not kind is String or kind not in ["item", "embedded_item", "affix", "skill", "rule"]:
			errors.append("feature_binding_unknown_kind")
			continue
		var key: String = "item_id" if kind in ["item", "embedded_item"] else ("affix_id" if kind=="affix" else ("skill_id" if kind == "skill" else "rule_id"))
		if not compiler._keys(binding, ["module_id", "kind", "mechanic_id", key], [], errors, "feature_binding"):
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
		if kind == "affix":
			var definition: Dictionary=preload("res://scripts/features/adapters/contribution_source_rules.gd").affix_definition(binding.affix_id) if binding.affix_id is String else {}
			if definition.is_empty() or definition.stat not in authority.stat_keys:
				errors.append("feature_binding_unknown_affix")
		if kind == "rule" and (not binding.rule_id is String or not compiler._stable_id(binding.rule_id)):
			errors.append("feature_binding_unknown_rule")
		var handle := JSON.stringify(binding)
		if seen.has(handle):
			errors.append("duplicate_feature_binding")
		seen[handle] = true
	if not errors.is_empty():
		feature_load_errors = errors
		return {}
	var enabled: Array = []
	for id: String in candidate.catalog().modules:
		if bool(candidate.catalog().modules[id].get("default_enabled", false)):
			enabled.append(id)
	return {"candidate":candidate, "authority":authority, "bindings":bindings.value, "enabled":enabled}


func _publish_feature_configuration(candidate: RefCounted, authority: Dictionary, bindings: Array, enabled: Array, resource_lease: RefCounted = null) -> bool:
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
		"bindings":bindings, "enabled_modules":enabled, "resource_lease":resource_lease}
	var prepared: Dictionary = PlayerState._prepare_feature_configuration(configuration)
	if not bool(prepared.success):
		feature_load_errors = prepared.errors
		_feature_publication_in_progress = false
		return false
	# No yield or callbacks between these assignments. Observers see both the
	# effective directory and the validated actor result in the same generation.
	_feature_commit_in_progress = true
	_feature_catalog = candidate
	_feature_authority = authority
	_feature_bindings = bindings
	_enabled_feature_modules = enabled
	_feature_resource_lease = resource_lease
	PlayerState._commit_feature_configuration(prepared)
	feature_load_errors = []
	feature_catalog_changed.emit()
	_feature_commit_in_progress = false
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
	var result := _feature_enabled_candidate(id, enabled)
	if result.is_empty(): return false
	var retained: RefCounted = null
	if not enabled and _feature_resource_lease != null:
		retained = _feature_resource_lease.retain_subset(result.candidate.catalog(), result.enabled)
	return _publish_feature_configuration(result.candidate, result.authority, result.bindings, result.enabled, retained)


func _feature_enabled_candidate(id: String, enabled: bool) -> Dictionary:
	if _feature_publication_in_progress:
		feature_load_errors = ["feature_publication_in_progress"]
		return {}
	if not ensure_feature_catalog() or not _feature_catalog.catalog().modules.has(id):
		return {}
	var candidate := _enabled_feature_modules.duplicate()
	if enabled == candidate.has(id):
		return {}
	if enabled:
		var context := PlayerState.feature_publication_context()
		var boundary: String = _feature_catalog.catalog().modules[id].get("activation_boundary", "startup")
		if not bool(context.world_ready) or (boundary == "startup" and bool(context.world_active)):
			feature_load_errors = ["feature_activation_boundary:" + id + ":" + boundary]
			return {}
		candidate.append(id)
	else:
		candidate.erase(id)
	candidate.sort()
	return {"candidate":_feature_catalog, "authority":_feature_authority, "bindings":_feature_bindings, "enabled":candidate}


func set_feature_module_enabled_async(id: String, enabled: bool) -> bool:
	if not enabled: return set_feature_module_enabled(id, false)
	var result := _feature_enabled_candidate(id, enabled)
	if result.is_empty(): return false
	var context := PlayerState.feature_publication_context()
	if not bool(context.scope_ready):
		feature_load_errors = ["feature_resource_preparation_scope_unavailable"]
		return false
	_feature_preparation_sequence += 1
	var sequence := _feature_preparation_sequence
	var scope: Dictionary = context.scope
	_feature_publication_in_progress = true
	var service := _feature_resources()
	var ready: Dictionary = await service.prepare(result.candidate.catalog(), result.enabled)
	if sequence != _feature_preparation_sequence: return false
	if not bool(ready.success):
		_feature_publication_in_progress = false
		feature_load_errors = ready.errors
		return false
	return await _await_feature_application(service, Callable(self,"_apply_prepared_feature_module").bind(id, enabled, result, ready.lease, sequence, scope), sequence)


func _apply_prepared_feature_module(id: String, enabled: bool, result: Dictionary, resource_lease: RefCounted, sequence: int, scope: Dictionary) -> bool:
	if sequence != _feature_preparation_sequence: return false
	_feature_publication_in_progress = false
	var current := _feature_enabled_candidate(id, enabled)
	var context := PlayerState.feature_publication_context()
	if current.is_empty() or not bool(context.scope_ready) or context.scope != scope or not is_same(result.candidate, _feature_catalog):
		feature_load_errors = ["feature_resource_preparation_stale"]
		return false
	return _publish_feature_configuration(result.candidate, result.authority, result.bindings, result.enabled, resource_lease)


func feature_configuration() -> Dictionary:
	if not ensure_feature_catalog():
		return {}
	return {"catalog":_feature_catalog.catalog(), "authority":_feature_authority,
		"bindings":_feature_bindings, "enabled_modules":_enabled_feature_modules.duplicate(), "resource_lease":_feature_resource_lease}


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
	var requested := enabled_expansions.duplicate()
	requested[package_id] = enabled
	return apply_expansion_configuration(requested)


func prepare_expansion_configuration(requested: Dictionary) -> RefCounted:
	last_expansion_error = ""
	if _expansion_commit_in_progress:
		last_expansion_error = "content_configuration_commit_in_progress"
		return null
	if not is_loaded() or not is_instance_valid(GameData):
		last_expansion_error = "content_layers_not_ready"
		return null
	if requested.size() != enabled_expansions.size():
		last_expansion_error = "content_configuration_packages_invalid"
		return null
	for package_id: Variant in requested:
		if not package_id is String or not enabled_expansions.has(package_id) or not requested[package_id] is bool:
			last_expansion_error = "content_configuration_packages_invalid"
			return null
	var prepared := PreparedContentConfiguration.new()
	prepared.owner = weakref(self)
	prepared.expected_expansions = enabled_expansions.duplicate()
	prepared.database_revision = GameData.database_revision
	prepared.database_loaded = GameData.is_loaded()
	prepared.layer_revision = configuration_revision
	prepared.requested_expansions = requested.duplicate()
	if requested == enabled_expansions and GameData.is_loaded():
		return prepared
	var merged := _build_merged_configuration(requested)
	var database_result := GameData.prepare_database_candidate(merged.database)
	if not bool(database_result.success):
		last_expansion_error = str(database_result.error)
		return null
	prepared.merged_database = merged.database
	prepared.merge_diagnostics = merged.diagnostics
	prepared.database_candidate = database_result.candidate
	return prepared


func apply_prepared_expansion_configuration(prepared: RefCounted, commit_profile: Callable = Callable()) -> bool:
	last_expansion_error = ""
	if _expansion_commit_in_progress or not prepared is PreparedContentConfiguration:
		last_expansion_error = "content_configuration_invalid_or_busy"
		return false
	if prepared.consumed or not is_instance_valid(prepared.owner) or prepared.owner.get_ref() != self or not is_loaded() or not is_instance_valid(GameData):
		last_expansion_error = "content_configuration_stale"
		return false
	if prepared.expected_expansions != enabled_expansions or prepared.database_revision != GameData.database_revision or prepared.database_loaded != GameData.is_loaded() or prepared.layer_revision != configuration_revision:
		last_expansion_error = "content_configuration_stale"
		return false
	var previous := enabled_expansions
	var reload := is_instance_valid(prepared.database_candidate)
	_expansion_commit_in_progress = true
	if reload and not GameData.adopt_database_candidate(prepared.database_candidate):
		_expansion_commit_in_progress = false
		last_expansion_error = "content_configuration_candidate_invalid"
		return false
	if reload:
		enabled_expansions = prepared.requested_expansions
		merged_database = prepared.merged_database
		merge_diagnostics = prepared.merge_diagnostics
		configuration_revision += 1
		prepared.database_candidate.free()
		prepared.database_candidate = null
	prepared.consumed = true
	if commit_profile.is_valid():
		commit_profile.call()
	# All owners are committed before any observer receives a notification.
	for package_id: String in enabled_expansions:
		if bool(previous[package_id]) != bool(enabled_expansions[package_id]):
			expansion_state_changed.emit(package_id, bool(enabled_expansions[package_id]))
	if reload:
		GameData.announce_database_reload()
	_expansion_commit_in_progress = false
	last_expansion_error = ""
	return true


func apply_expansion_configuration(requested: Dictionary, commit_profile: Callable = Callable()) -> bool:
	var prepared := prepare_expansion_configuration(requested)
	return prepared != null and apply_prepared_expansion_configuration(prepared, commit_profile)


func is_expansion_enabled(package_id: String) -> bool:
	return bool(enabled_expansions.get(package_id, false))


func active_skin() -> Dictionary:
	var presentation := manifest("presentation_layer")
	return presentation.get("skins", {}).get(str(presentation.get("activeSkin", "")), {})


func build_merged_database(user_override: Dictionary = {}) -> Dictionary:
	var candidate := _build_merged_configuration(enabled_expansions, user_override)
	merge_diagnostics = candidate.diagnostics
	return candidate.database


func _build_merged_configuration(expansions: Dictionary, user_override: Dictionary = {}) -> Dictionary:
	var diagnostics: Array[String] = []
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
		if not bool(expansions.get(package_id, false)):
			continue
		merged["activeExpansions"].append(package_id)
		_apply_expansion_package(merged, package, diagnostics)
	_apply_user_override(merged, user_override)
	return {"database": merged, "diagnostics": diagnostics}


func _apply_expansion_package(merged: Dictionary, package: Dictionary, diagnostics: Variant = null) -> void:
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
					_merge_record(merged[table_id], record, table_id, merge_policy, str(package.get("id", "")), diagnostics)


func _merge_record(target: Array, record: Dictionary, table_id: String, merge_policy: String, package_id: String, diagnostics: Variant = null) -> void:
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
		var destination: Array = merge_diagnostics if diagnostics == null else diagnostics
		destination.append("扩展冲突被拒绝：%s/%s/%s" % [package_id, table_id, record_id])
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


# Internal framework code entries are distinct from gameplay FeatureModules.
# Only this code-owned generated source registers targets, never caller JSON.
const AndroidExportData := preload("res://scripts/features/generated/internal_code_android_export_data.gd")
const InternalCodeData := preload("res://scripts/features/generated/internal_code_preparation_catalog_data.gd")
const InternalCodeScope := preload("res://scripts/features/contracts/loading_preparation_scope.gd")
var _internal_code_entries: Dictionary = {}
var _internal_code_metadata: Dictionary = {}
var _internal_code_revision := ""
signal internal_code_catalogue_finished(success: bool)
var _internal_code_publication_pending := false
var internal_code_errors: Array = []
var internal_code_publication_diagnostic: Dictionary = {}

func is_internal_code_publication_boundary_current(sequence: int) -> bool:
	return sequence == _feature_preparation_sequence and not _feature_publication_in_progress and not bool(PlayerState.feature_publication_context().world_active)

func code_preparation_export_contract() -> Dictionary:
	if OS.get_name() != "Android" or not AndroidExportData.AVAILABLE or AndroidExportData.SEAL_JSON.sha256_text() != AndroidExportData.SEAL_SHA256:
		return {}
	var seal := AndroidExportData.read_bundle()
	if seal.get("source_bundle_json_sha256") != InternalCodeData.BUNDLE_JSON.sha256_text() or seal.get("producer_sha256") != InternalCodeData.PRODUCER_SHA256 or not InternalCodeData.REGISTERED_TARGETS.has(seal.get("entry_id")):
		return {}
	return seal

func code_preparation_export_seal_sha256() -> String:
	return AndroidExportData.SEAL_SHA256 if not code_preparation_export_contract().is_empty() else ""

func code_preparation_export_identity(entry_id: String) -> Dictionary:
	var seal := code_preparation_export_contract()
	if seal.is_empty() or seal.get("entry_id") != entry_id or not _internal_code_entries.has(entry_id): return {}
	return {"seal": seal, "seal_sha256": AndroidExportData.SEAL_SHA256}

func _publish_internal_code_catalogue(scope: RefCounted, consumer_ref: WeakRef, generation: int, sequence: int) -> bool:
	var began := Time.get_ticks_usec()
	var consumer: Node = consumer_ref.get_ref() if consumer_ref != null else null
	if not is_internal_code_publication_boundary_current(sequence) or scope == null or not is_instance_valid(consumer) or not bool(scope.valid_for(consumer, generation)) or not (_feature_resources().code_publication_export_current(scope, consumer, generation, AndroidExportData.SEAL_SHA256) if OS.get_name() == "Android" else _feature_resources().code_publication_image_current(scope, consumer, generation, InternalCodeData.ENGINE_BINARY_SHA256)):
		internal_code_errors = ["internal_code_publication_cover_or_image_unproved"]
		return false
	if not _feature_reload_boundary():
		internal_code_errors = ["internal_code_publication_requires_retired_world"]
		return false
	if InternalCodeData.BUNDLE_UTF8_BYTES > 65536 or InternalCodeData.BUNDLE_JSON.to_utf8_buffer().size() != InternalCodeData.BUNDLE_UTF8_BYTES:
		internal_code_errors = ["internal_code_catalogue_byte_capacity"]
		return false
	var bundle := InternalCodeData.read_bundle()
	if bundle.get("schema_version") != 1 or bundle.get("contract_id") != "hc.internal_code_preparation.catalogue.candidate.v1" or bundle.get("runtime_mode") != "pc_editor_text":
		internal_code_errors = ["internal_code_catalogue_contract"]
		return false
	if not bundle.get("engine") is Dictionary or not bundle.engine.get("version") is Dictionary or not bundle.get("entries") is Dictionary:
		internal_code_errors = ["internal_code_catalogue_shape"]
		return false
	# PC retains runtime image hashing. Android uses the separately reviewed
	# build seal plus actual capabilities/context checks in the same service.
	if OS.get_name() not in ["Windows", "Android"] or bundle.engine.version.get("hash") != Engine.get_version_info().get("hash") or (OS.get_name() == "Windows" and bundle.engine.get("binary_sha256") != InternalCodeData.ENGINE_BINARY_SHA256) or (OS.get_name() == "Android" and code_preparation_export_contract().is_empty()):
		internal_code_errors = ["internal_code_runtime_image_or_platform_mismatch"]
		return false
	if bundle.get("producer_sha256") != InternalCodeData.PRODUCER_SHA256 or not bundle.get("input_artifacts") is Array or bundle.input_artifacts.size() != 3:
		internal_code_errors = ["internal_code_generated_producer_binding"]
		return false
	if bundle.entries.size() != 1 or bundle.entries.size() != InternalCodeData.REGISTERED_TARGETS.size():
		internal_code_errors = ["internal_code_registration_set_mismatch"]
		return false
	for id: String in InternalCodeData.REGISTERED_TARGETS:
		var plan_value: Variant = bundle.entries.get(id)
		if not plan_value is Dictionary:
			internal_code_errors = ["internal_code_missing_registered_plan:" + id]
			return false
		var plan: Dictionary = plan_value
		if plan.get("status") != "PASS" or plan.get("errors") != [] or plan.get("target_path") != InternalCodeData.REGISTERED_TARGETS[id] or plan.get("producer_id") != "hc.code_preparation.lexical_subset.candidate.v1" or plan.get("scope") != "supported_gdscript_compile_inputs" or not plan.get("source_fingerprints") is Dictionary:
			internal_code_errors = ["internal_code_registered_plan_rejected:" + id]
			return false
		if plan.source_fingerprints.get("producer") != InternalCodeData.PRODUCER_SHA256 or (OS.get_name() == "Windows" and (FileAccess.get_sha256("res://project.godot") != plan.source_fingerprints.get("project.godot") or FileAccess.get_sha256("res://.godot/global_script_class_cache.cfg") != plan.source_fingerprints.get("class_cache"))):
			internal_code_errors = ["internal_code_registration_or_source_context_changed:" + id]
			return false
	var captured := PlainGraph.capture(bundle.entries, 8192, 32)
	if not captured.success:
		internal_code_errors = ["internal_code_catalogue_not_plain_or_capacity"]
		return false
	var serialized := JSON.stringify(captured.value, "", true)
	if serialized.to_utf8_buffer().size() > 65536 or not bool(scope.valid_for(consumer, generation)):
		internal_code_errors = ["internal_code_catalogue_byte_capacity"]
		return false
	# Same ContentLayers owner/sequence, only after its existing boundary gate.
	_feature_preparation_sequence += 1
	_internal_code_entries = captured.value
	_internal_code_revision = serialized.sha256_text()
	_internal_code_metadata = {}
	for id: String in _internal_code_entries:
		var plan: Dictionary = _internal_code_entries[id]
		_internal_code_metadata[id] = {"entry_id": id, "target_path": plan.target_path, "source_revision": _internal_code_revision,
			"plan_sha256": JSON.stringify(plan, "", true).sha256_text(), "producer_sha256": InternalCodeData.PRODUCER_SHA256, "runtime_mode": "android_controller_sealed_export" if OS.get_name() == "Android" else "pc_editor_text", "export_seal_sha256": AndroidExportData.SEAL_SHA256 if OS.get_name() == "Android" else ""}
	_internal_code_metadata.make_read_only()
	internal_code_errors = []
	internal_code_publication_diagnostic = {"elapsed_usec": Time.get_ticks_usec() - began, "generation": _feature_preparation_sequence, "source_revision": _internal_code_revision, "runtime_mode": "android_controller_sealed_export" if OS.get_name() == "Android" else "pc_editor_text", "runtime_native_image_sha": "MISSING" if OS.get_name() == "Android" else InternalCodeData.ENGINE_BINARY_SHA256, "native_token_device_acceptance": "NOT_RUN"}
	return true

func ensure_internal_code_catalogue_async(scope: RefCounted, consumer: Node, generation: int) -> bool:
	if scope == null or not is_same(scope.get_script(), InternalCodeScope) or not is_instance_valid(consumer) or not bool(scope.valid_for(consumer, generation)):
		internal_code_errors = ["internal_code_publication_loading_scope_unavailable"]
		return false
	if not _internal_code_entries.is_empty():
		return true
	if _internal_code_publication_pending:
		var success: bool = await internal_code_catalogue_finished
		return success and bool(scope.valid_for(consumer, generation))
	if not _feature_reload_boundary():
		internal_code_errors = ["internal_code_publication_requires_retired_world"]
		return false
	# Image hashing is 256KiB per existing application quantum. The final
	# <=64KiB catalogue capture is indivisible, measured, and covered Loading.
	_internal_code_publication_pending = true
	var sequence := _feature_preparation_sequence
	var android_contract := code_preparation_export_contract() if OS.get_name() == "Android" else {}
	var result: Dictionary = await _feature_resources().prepare_code_publication(AndroidExportData.SEAL_SHA256 if OS.get_name() == "Android" else InternalCodeData.ENGINE_BINARY_SHA256, AndroidExportData.SEAL_JSON.to_utf8_buffer().size() if OS.get_name() == "Android" else InternalCodeData.ENGINE_BINARY_BYTES,
		Callable(self, "_publish_internal_code_catalogue").bind(scope, weakref(consumer), generation, sequence), scope, consumer, generation, sequence, android_contract)
	var success: bool = bool(result.success) and bool(scope.valid_for(consumer, generation))
	if not success and internal_code_errors.is_empty():
		internal_code_errors = result.get("errors", ["internal_code_publication_cancelled"])
	_internal_code_publication_pending = false
	internal_code_catalogue_finished.emit(success)
	return success

func code_preparation_published_entry(entry_id: String) -> Dictionary:
	if not _internal_code_entries.has(entry_id):
		return {}
	var metadata: Dictionary = _internal_code_metadata[entry_id].duplicate(false)
	metadata["generation"] = _feature_preparation_sequence
	return metadata

func is_code_preparation_publication_current(entry_id: String, generation: int, source_revision: String, plan_sha256: String) -> bool:
	if generation != _feature_preparation_sequence or source_revision != _internal_code_revision or _feature_publication_in_progress or not _internal_code_entries.has(entry_id):
		return false
	return _internal_code_metadata[entry_id].plan_sha256 == plan_sha256

func prepare_internal_code_entry(entry_id: String, overlay: Control, consumer: Node, generation: int) -> Dictionary:
	if not InternalCodeData.REGISTERED_TARGETS.has(entry_id):
		return {"success": false, "errors": ["internal_code_entry_unregistered"], "lease": null}
	var scope: RefCounted = InternalCodeScope.issue(overlay, consumer, generation)
	if scope == null:
		return {"success": false, "errors": ["internal_code_loading_scope_unavailable"], "lease": null}
	if not await ensure_internal_code_catalogue_async(scope, consumer, generation):
		return {"success": false, "errors": internal_code_errors.duplicate(), "lease": null}
	return await _feature_resources().prepare_code_inputs(_internal_code_entries[entry_id], entry_id, self, scope, consumer, generation)

func request_internal_prepared_script(prepared: Dictionary, consumer: Node, generation: int) -> Dictionary:
	return await _feature_resources().request_code_script(prepared, consumer, generation)

func cancel_internal_code_owner(consumer: Node, generation: int) -> void:
	if _feature_resource_service != null:
		_feature_resource_service.cancel_code_owner(consumer, generation)

func retire_internal_code_result(result: Dictionary) -> void:
	if _feature_resource_service != null:
		_feature_resource_service.retire_code_result(result)


func is_internal_code_retention_current(result: Dictionary, consumer: Node) -> bool:
	return is_instance_valid(_feature_resource_service) and _feature_resource_service.code_result_retention_current(result, consumer)

func transfer_internal_code_retention(result: Dictionary, previous: Node, next_consumer: Node) -> bool:
	return is_instance_valid(_feature_resource_service) and _feature_resource_service.transfer_code_result_retention(result, previous, next_consumer)

func change_scene_with_internal_code_retention(result: Dictionary, consumer: Node, scene: PackedScene) -> int:
	return _feature_resource_service.change_scene_with_code_retention(result, consumer, scene) if is_instance_valid(_feature_resource_service) else ERR_UNAVAILABLE

func claim_internal_code_world_retention(consumer: Node) -> Dictionary:
	return _feature_resource_service.claim_code_world_handoff(consumer) if is_instance_valid(_feature_resource_service) else {}

