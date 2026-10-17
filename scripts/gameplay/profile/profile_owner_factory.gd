extends RefCounted

const Profile := preload("res://scripts/gameplay/profile/profile_model.gd")
const Content := preload("res://scripts/gameplay/content/content_query_core.gd")
const FeaturePort := preload("res://scripts/gameplay/profile/profile_feature_port.gd")
const RuntimePort := preload("res://scripts/gameplay/profile/profile_runtime_port.gd")
const ModeCore := preload("res://scripts/gameplay/profile/profile_mode_core.gd")
const ExpansionCore := preload("res://scripts/gameplay/profile/profile_expansion_core.gd")
const DiagnosticsPort := preload("res://scripts/gameplay/profile/profile_diagnostics_port.gd")
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Resources := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const LegacyPersistenceBudget := preload("res://scripts/gameplay/profile/legacy_persistence_budget.gd")
const REQUIRED_OWNER_METHODS := ["profile_world_paused","fault","retain_feature_resource_publication","release_feature_resource_retention","feature_resource_retention_supports_path","prepare_profile_feature_resources","apply_profile_feature_ready","profile_feature_is_applying","cancel_profile_feature_resources","prepare_profile_feature_directory"]

static func validate_required(owner: RefCounted, publication: Dictionary, content_snapshot: Dictionary, persistence_budget: RefCounted) -> Dictionary:
	var errors: Array[String] = []
	if OS.get_thread_caller_id() == OS.get_main_thread_id(): errors.append("real_profile_simulation_owner_required")
	if owner == null or owner is Resource: errors.append("owner_local_core_required")
	else:
		for method: String in REQUIRED_OWNER_METHODS:
			if not owner.has_method(method): errors.append("missing_profile_service:"+method)
		for method: String in RuntimePort.REQUIRED_OWNER_METHODS:
			if not owner.has_method(method): errors.append("missing_profile_world_service:"+method)
	if persistence_budget == null or persistence_budget is LegacyPersistenceBudget or persistence_budget is Resource: errors.append("original_s_persistence_budget_required")
	else:
		for method: String in ["mark_pending","begin","end","release"]:
			if not persistence_budget.has_method(method): errors.append("missing_persistence_budget_service:"+method)
	if not Graph.validate(publication).success: errors.append("profile_publication_plain_values_required")
	if publication.get("contract_id") != "profile.owner.publication.v1" or publication.get("loaded") != true: errors.append("canonical_loaded_profile_publication_required")
	for field: String in ["enabled_expansions","merged_database","modes","expansion_candidates","features","diagnostics_policy","catalog_lease"]:
		if not publication.get(field) is Dictionary: errors.append("profile_publication_missing:"+field)
	for field: String in ["configuration_revision","database_revision"]:
		if not publication.get(field) is int or int(publication.get(field,-1)) < 0: errors.append("profile_publication_revision_invalid:"+field)
	if not publication.get("merge_diagnostics") is Array or not publication.get("active_mode") is String: errors.append("profile_publication_state_invalid")
	if not errors.is_empty(): return {"success":false,"errors":errors}
	if not Gate.owns_reader(publication.catalog_lease) or publication.catalog_lease != content_snapshot.get("catalog_lease"): errors.append("same_canonical_catalog_reader_required")
	if publication.database_revision != content_snapshot.get("database_revision"): errors.append("profile_content_database_revision_mismatch")
	if not publication.modes.has(publication.active_mode): errors.append("profile_active_mode_unknown")
	for id: Variant in publication.enabled_expansions:
		if not id is String or not publication.enabled_expansions[id] is bool: errors.append("profile_package_schema_invalid")
	if not errors.is_empty(): return {"success":false,"errors":errors}
	for id: Variant in publication.modes:
		var mode: Variant = publication.modes[id]
		if not id is String or not mode is Dictionary or not mode.get("enabledPackages",[]) is Array:
			errors.append("profile_mode_schema_invalid")
			continue
		for package_id: Variant in mode.get("enabledPackages",[]):
			if not package_id is String or not publication.enabled_expansions.has(package_id): errors.append("profile_mode_package_unknown")
	var configurations: Array = [{}]
	for id: String in publication.enabled_expansions:
		var next: Array = []
		for request: Dictionary in configurations:
			for enabled: bool in [false,true]:
				var candidate := request.duplicate()
				candidate[id] = enabled
				next.append(candidate)
		configurations = next
	for request: Dictionary in configurations:
		var key := ExpansionCore.configuration_key(request)
		if not publication.expansion_candidates.has(key):
			errors.append("canonical_package_candidate_missing:"+key)
			continue
		var candidate: Variant = publication.expansion_candidates[key]
		if not candidate is Dictionary or not candidate.get("success") is bool: errors.append("canonical_package_candidate_invalid:"+key)
		elif bool(candidate.success):
			if not candidate.get("merged_database") is Dictionary or not candidate.get("merge_diagnostics") is Array or not candidate.get("database_candidate") is Dictionary:
				errors.append("canonical_package_candidate_state_invalid:"+key)
			else:
				var database: Dictionary = candidate.database_candidate
				if database.get("contract_id") != "profile.database.candidate.v1" or not bool(database.get("validated_canonical",false)) or not database.get("fields") is Dictionary:
					errors.append("canonical_database_candidate_invalid:"+key)
				elif database.fields.size() != Content.PROFILE_DATABASE_FIELDS.size() or Graph.fingerprint(database.fields) != database.get("fields_sha256"):
					errors.append("canonical_database_candidate_fingerprint_invalid:"+key)
				else:
					for field: String in Content.PROFILE_DATABASE_FIELDS:
						if not database.fields.has(field): errors.append("canonical_database_candidate_field_missing:"+field)
		elif not candidate.get("error") is String or str(candidate.error).is_empty(): errors.append("canonical_candidate_failure_missing_reason:"+key)
	for field: String in ["catalog","authority","resource_publication"]:
		if not publication.features.get(field) is Dictionary: errors.append("profile_feature_publication_invalid:"+field)
	for field: String in ["bindings","enabled_modules"]:
		if not publication.features.get(field) is Array: errors.append("profile_feature_publication_invalid:"+field)
	for field: String in ["enabled","detail_enabled"]:
		if not publication.diagnostics_policy.get(field) is bool: errors.append("profile_diagnostics_policy_invalid:"+field)
	if publication.diagnostics_policy.get("detail_mode") not in ["frame_only","full"]: errors.append("profile_diagnostics_mode_invalid")
	if publication.diagnostics_policy.get("contract_id") != "profile.diagnostics.policy.v1" or (bool(publication.diagnostics_policy.get("detail_enabled",false)) and not bool(publication.diagnostics_policy.get("enabled",false))): errors.append("profile_diagnostics_publication_invalid")
	if errors.is_empty():
		var catalog: Dictionary = publication.features.catalog
		if not catalog.get("modules") is Dictionary or not catalog.get("mechanics") is Dictionary or not catalog.get("revision") is String or str(catalog.revision).is_empty():
			errors.append("profile_compiled_feature_catalog_required")
		else:
			for module_id: Variant in catalog.modules:
				var module: Variant = catalog.modules[module_id]
				if not module_id is String or not module is Dictionary or not module.get("requires") is Array or not module.get("resource_dependencies") is Array:
					errors.append("profile_compiled_feature_module_invalid")
					continue
				for dependency: Variant in module.requires:
					if not dependency is String: errors.append("profile_feature_dependency_invalid")
				for path: Variant in module.resource_dependencies:
					if not path is String: errors.append("profile_feature_resource_path_invalid")
	if errors.is_empty():
		var plan := Resources.requirements(publication.features.catalog,publication.features.enabled_modules)
		if not plan.success: errors.append_array(plan.errors)
		elif not plan.paths.is_empty():
			var resource: Dictionary = publication.features.resource_publication
			if resource.get("contract_id") != "hardcore.feature.resource_publication.v1" or not resource.get("publication_id") is int or int(resource.get("publication_id",0)) <= 0 \
				or resource.get("signature") != plan.signature or resource.get("catalog_revision") != plan.catalog_revision or resource.get("enabled_modules") != plan.enabled_modules or resource.get("paths") != plan.paths:
				errors.append("profile_feature_resource_publication_mismatch")
	return {"success":errors.is_empty(),"errors":errors}

static func create(owner: RefCounted, publication: Dictionary, content_snapshot: Dictionary, persistence_budget: RefCounted) -> Dictionary:
	var checked := validate_required(owner,publication,content_snapshot,persistence_budget)
	if not checked.success: return checked
	var copied := Graph.capture(publication)
	if not copied.success: return {"success":false,"errors":copied.errors}
	var content_port: RefCounted = Content.create_content_port(content_snapshot)
	if content_port == null: return {"success":false,"errors":["profile_content_owner_creation_failed"]}
	var profile := Profile.new()
	var runtime := RuntimePort.new(owner)
	var source := ExpansionCore.new(copied.value,content_port._source,profile,runtime,owner)
	var requirements := Resources.requirements(copied.value.features.catalog,copied.value.features.enabled_modules)
	if not requirements.paths.is_empty() and source._feature_resource_lease == null:
		return {"success":false,"errors":["profile_feature_real_resource_retention_failed"]}
	var features := FeaturePort.new(source,true)
	var modes := ModeCore.new(copied.value,source,profile)
	var diagnostics := DiagnosticsPort.new(copied.value.diagnostics_policy)
	profile.configure_ports(content_port,features,modes,runtime,diagnostics,"simulation",persistence_budget)
	# Same original observer callback and same owner-local ProfileModel.
	source.feature_catalog_changed.connect(source.notify_profile_feature_changed)
	return {"success":true,"profile":profile,"content":content_port,"features":features,"feature_source":source,"modes":modes,"runtime":runtime,"diagnostics":diagnostics}

static func create_loaded(owner: RefCounted, publication: Dictionary, content_snapshot: Dictionary, persistence_budget: RefCounted, state_publication: Dictionary) -> Dictionary:
	var result := create(owner,publication,content_snapshot,persistence_budget)
	if not result.success: return result
	var lease: RefCounted=result.feature_source._feature_resource_lease if bool(state_publication.get("resource",{}).get("present",false)) else null
	var adopted := preload("res://scripts/gameplay/profile/profile_state_handoff.gd").adopt_owner(result.profile,state_publication,lease)
	if not adopted.ok: return {"success":false,"errors":adopted.errors}
	result["loaded_state_adoption"] = adopted
	return result
