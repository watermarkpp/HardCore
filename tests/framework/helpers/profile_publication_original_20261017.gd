extends RefCounted

## MAIN ONLY. Compile all exact Boolean package configurations through the
## original unpublished merge and GameData parser. This is preparation, with
## no adopt, mode mutation, profile callback or notification on Main.
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Queries := preload("res://scripts/gameplay/content/content_query_core.gd")
const Expansions := preload("res://scripts/gameplay/profile/profile_expansion_core.gd")
const ResourceLease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const CONTRACT := "profile.owner.publication.v1"

static func prepare_canonical() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not Gate.write_allowed(): return {"success":false,"error":"profile_canonical_main_prepare_barrier_required"}
	if not ContentLayers.is_loaded() or not GameData.is_loaded() or not ContentLayers.ensure_feature_catalog(): return {"success":false,"error":"profile_canonical_sources_not_ready"}
	if ContentLayers._expansion_commit_in_progress or ContentLayers._feature_publication_in_progress or ContentLayers._feature_commit_in_progress:
		return {"success":false,"error":"profile_canonical_sources_busy"}
	var package_ids: Array = ContentLayers.enabled_expansions.keys()
	package_ids.sort()
	var requests: Array = [{}]
	for id: String in package_ids:
		var next: Array = []
		for request: Dictionary in requests:
			var disabled := request.duplicate()
			disabled[id] = false
			next.append(disabled)
			var enabled := request.duplicate()
			enabled[id] = true
			next.append(enabled)
		requests = next
	var candidates := {}
	for requested: Dictionary in requests:
		var merged: Dictionary = ContentLayers._build_merged_configuration(requested)
		var failure := ""
		for diagnostic: Variant in merged.diagnostics:
			if str(diagnostic).begins_with("ERROR:"):
				failure = str(diagnostic).substr(6)
				break
		var key := Expansions.configuration_key(requested)
		if not failure.is_empty():
			candidates[key] = {"success":false,"error":failure}
			continue
		var result: Dictionary = GameData.prepare_database_candidate(merged.database)
		if not bool(result.success):
			candidates[key] = {"success":false,"error":str(result.error)}
			continue
		var candidate: Node = result.candidate
		var fields := {}
		for field: String in Queries.PROFILE_DATABASE_FIELDS: fields[field] = candidate.get(field)
		var captured := Graph.capture(fields)
		candidate.free()
		if not captured.success: return {"success":false,"error":"profile_database_candidate_not_plain","errors":captured.errors}
		candidates[key] = {"success":true,"merged_database":merged.database,"merge_diagnostics":merged.diagnostics,
			"database_candidate":{"contract_id":"profile.database.candidate.v1","validated_canonical":true,"fields":captured.value,"fields_sha256":Graph.fingerprint(captured.value)}}
	var features: Dictionary = ContentLayers.feature_configuration()
	if features.is_empty(): return {"success":false,"error":"profile_feature_directory_not_ready"}
	var plan := ResourceLease.requirements(features.catalog,features.enabled_modules)
	if not plan.success: return {"success":false,"error":"profile_feature_resource_plan_invalid","errors":plan.errors}
	if not plan.paths.is_empty() and (not features.resource_lease is RefCounted or features.resource_lease.get_script() != ResourceLease or not features.resource_lease.valid_for(features.catalog,features.enabled_modules)):
		return {"success":false,"error":"profile_feature_main_resource_preparation_required"}
	var publication := {"contract_id":CONTRACT,"loaded":true,"enabled_expansions":ContentLayers.enabled_expansions,
		"merged_database":ContentLayers.merged_database,"merge_diagnostics":ContentLayers.merge_diagnostics,
		"configuration_revision":ContentLayers.configuration_revision,"database_revision":GameData.database_revision,
		"modes":GameModes.modes,"active_mode":GameModes.active_mode,"expansion_candidates":candidates,
		"features":{"catalog":features.catalog,"authority":features.authority,"bindings":features.bindings,"enabled_modules":features.enabled_modules},
		"diagnostics_policy":capture_diagnostics_policy()}
	var copied := Graph.capture(publication)
	if not copied.success: return {"success":false,"error":"profile_publication_not_plain","errors":copied.errors}
	return {"success":true,"publication":copied.value}

static func seal(prepared: Dictionary, catalog_lease: Dictionary, feature_resource_publication: Dictionary = {}) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not Gate.is_active(catalog_lease): return {}
	if not bool(prepared.get("success",false)) or not prepared.get("publication") is Dictionary: return {}
	var publication: Dictionary = prepared.publication.duplicate(true)
	publication["catalog_lease"] = catalog_lease
	publication.features["resource_publication"] = feature_resource_publication
	var plan := ResourceLease.requirements(publication.features.catalog,publication.features.enabled_modules)
	if not plan.success: return {}
	if not plan.paths.is_empty():
		if feature_resource_publication.get("contract_id") != "hardcore.feature.resource_publication.v1" or feature_resource_publication.get("signature") != plan.signature: return {}
	var captured := Graph.capture(publication)
	return captured.value if captured.success else {}

static func prepare_feature_directory(registry_path: String) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not Gate.write_allowed():
		return {"success":false,"errors":["profile_feature_canonical_main_prepare_barrier_required"]}
	# Reuse the complete original authoring-path, compiler, dependency,
	# definition/code and authority admission. Do not register or publish a
	# renamed legacy Node as the S FeatureCore.
	var result: Dictionary = ContentLayers._read_feature_candidate(registry_path)
	if result.is_empty(): return {"success":false,"errors":ContentLayers.feature_load_errors.duplicate()}
	var captured := Graph.capture({"success":true,"candidate":result.candidate.catalog(),"authority":result.authority,"bindings":result.bindings,"enabled":result.enabled})
	return captured.value if captured.success else {"success":false,"errors":captured.errors}

static func capture_diagnostics_policy() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {}
	var result := {"contract_id":"profile.diagnostics.policy.v1","enabled":RuntimeDiagnostics.performance_enabled(),"detail_enabled":RuntimeDiagnostics.performance_detail_enabled(),"detail_mode":RuntimeDiagnostics.device_lab_detail_mode()}
	result.make_read_only()
	return result
