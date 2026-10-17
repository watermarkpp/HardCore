extends RefCounted

signal expansion_state_changed(package_id: String, enabled: bool)
signal feature_catalog_changed
signal database_reloaded
const Prepared := preload("res://scripts/gameplay/profile/profile_prepared_content.gd")
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Resources := preload("res://scripts/features/contracts/feature_resource_lease.gd")
var _thread := OS.get_thread_caller_id()
var _profile: WeakRef
var _owner: WeakRef
var _runtime: RefCounted
var _content: RefCounted
var _candidates: Dictionary
var _feature_catalog: Dictionary
var _feature_authority: Dictionary
var _feature_bindings: Array
var _enabled_feature_modules: Array
var _feature_resource_lease: RefCounted
var enabled_expansions: Dictionary
var merged_database: Dictionary
var merge_diagnostics: Array
var configuration_revision: int
var feature_load_errors: Array = []
var last_expansion_error := ""
var _expansion_commit_in_progress := false
var _feature_publication_in_progress := false
var _feature_commit_in_progress := false
var _feature_preparation_sequence := 0
var _loaded := false

func _init(published: Dictionary, content: RefCounted, profile: RefCounted, runtime: RefCounted, owner: RefCounted) -> void:
	assert(OS.get_thread_caller_id() != OS.get_main_thread_id())
	_profile = weakref(profile)
	_owner = weakref(owner)
	_runtime = runtime
	_content = content
	_candidates = published.expansion_candidates
	enabled_expansions = published.enabled_expansions.duplicate()
	merged_database = published.merged_database
	merge_diagnostics = published.merge_diagnostics
	configuration_revision = int(published.configuration_revision)
	_loaded = bool(published.loaded)
	_feature_catalog = published.features.catalog
	_feature_authority = published.features.authority
	_feature_bindings = published.features.bindings
	_enabled_feature_modules = published.features.enabled_modules.duplicate()
	var plan := Resources.requirements(_feature_catalog,_enabled_feature_modules)
	assert(plan.success)
	if not plan.paths.is_empty():
		_feature_resource_lease = Resources.issue_domain(plan,published.features.resource_publication,owner,{"bootstrap":true})
		assert(_feature_resource_lease != null, "original Main resource lease must be retained before S admission")

func _assert_owner() -> void:
	assert(OS.get_thread_caller_id() == _thread and _profile.get_ref() != null and _owner.get_ref() != null)

static func configuration_key(requested: Dictionary) -> String:
	var ids: Array = requested.keys()
	ids.sort()
	var pairs: Array = []
	for id: String in ids: pairs.append([id,requested[id]])
	return JSON.stringify(pairs)

func is_loaded() -> bool:
	_assert_owner()
	return _loaded

func prepare_expansion_configuration(requested: Dictionary) -> RefCounted:
	_assert_owner()
	last_expansion_error = ""
	if _expansion_commit_in_progress:
		last_expansion_error = "content_configuration_commit_in_progress"
		return null
	if not is_loaded() or _content == null:
		last_expansion_error = "content_layers_not_ready"
		return null
	if requested.size() != enabled_expansions.size():
		last_expansion_error = "content_configuration_packages_invalid"
		return null
	for package_id: Variant in requested:
		if not package_id is String or not enabled_expansions.has(package_id) or not requested[package_id] is bool:
			last_expansion_error = "content_configuration_packages_invalid"
			return null
	var prepared := Prepared.new()
	prepared.owner = weakref(self)
	prepared.expected_expansions = enabled_expansions.duplicate()
	prepared.database_revision = _content.source_revision
	prepared.database_loaded = _content.is_loaded()
	prepared.layer_revision = configuration_revision
	prepared.requested_expansions = requested.duplicate()
	if requested == enabled_expansions and _content.is_loaded(): return prepared
	var key := configuration_key(requested)
	if not _candidates.has(key):
		last_expansion_error = "content_configuration_canonical_preparation_required"
		_owner.get_ref().fault(last_expansion_error,{"configuration":requested})
		return null
	var canonical: Dictionary = _candidates[key]
	if not bool(canonical.success):
		last_expansion_error = str(canonical.error)
		return null
	prepared.merged_database = canonical.merged_database
	prepared.merge_diagnostics = canonical.merge_diagnostics
	prepared.database_candidate = canonical.database_candidate
	return prepared

func apply_prepared_expansion_configuration(prepared: RefCounted, commit_profile: Callable = Callable()) -> bool:
	_assert_owner()
	last_expansion_error = ""
	if _expansion_commit_in_progress or not prepared is Prepared:
		last_expansion_error = "content_configuration_invalid_or_busy"
		return false
	if prepared.consumed or prepared.owner == null or prepared.owner.get_ref() != self or not is_loaded() or _content == null:
		last_expansion_error = "content_configuration_stale"
		return false
	if prepared.expected_expansions != enabled_expansions or prepared.database_revision != _content.source_revision or prepared.database_loaded != _content.is_loaded() or prepared.layer_revision != configuration_revision:
		last_expansion_error = "content_configuration_stale"
		return false
	var previous := enabled_expansions
	var reload: bool = not prepared.database_candidate.is_empty()
	_expansion_commit_in_progress = true
	if reload and not _content.adopt_profile_database_candidate(prepared.database_candidate,prepared.database_revision):
		_expansion_commit_in_progress = false
		last_expansion_error = "content_configuration_candidate_invalid"
		return false
	if reload:
		enabled_expansions = prepared.requested_expansions
		merged_database = prepared.merged_database
		merge_diagnostics = prepared.merge_diagnostics
		configuration_revision += 1
		prepared.database_candidate = {}
	prepared.consumed = true
	if commit_profile.is_valid(): commit_profile.call()
	for package_id: String in enabled_expansions:
		if bool(previous[package_id]) != bool(enabled_expansions[package_id]):
			expansion_state_changed.emit(package_id,bool(enabled_expansions[package_id]))
	if reload: database_reloaded.emit()
	_expansion_commit_in_progress = false
	last_expansion_error = ""
	return true

func apply_expansion_configuration(requested: Dictionary, commit_profile: Callable = Callable()) -> bool:
	var prepared := prepare_expansion_configuration(requested)
	return prepared != null and apply_prepared_expansion_configuration(prepared,commit_profile)

func enabled_package_ids() -> Array[String]:
	_assert_owner()
	var result: Array[String] = []
	for package_id: String in enabled_expansions:
		if bool(enabled_expansions[package_id]): result.append(package_id)
	result.sort()
	return result

func feature_configuration() -> Dictionary:
	_assert_owner()
	return {"catalog":_feature_catalog,"authority":_feature_authority,"bindings":_feature_bindings,"enabled_modules":_enabled_feature_modules.duplicate(),"resource_lease":_feature_resource_lease}

func notify_profile_feature_changed() -> void:
	_assert_owner()
	# Keep the original observer math on the same model while the reverse
	# publication edge remains weak.
	_profile.get_ref()._on_feature_catalog_changed()

func _publish_feature_configuration(catalog: Dictionary, authority: Dictionary, bindings: Array, enabled: Array, resource_lease: RefCounted = null) -> bool:
	_assert_owner()
	if _feature_publication_in_progress:
		feature_load_errors = ["feature_publication_in_progress"]
		return false
	for selected: String in enabled:
		for dependency: String in catalog.modules[selected].requires:
			if dependency not in enabled:
				feature_load_errors = ["feature_disabled_dependency:" + selected + ":" + dependency]
				return false
	_feature_publication_in_progress = true
	var configuration := {"catalog":catalog,"authority":authority,"bindings":bindings,"enabled_modules":enabled,"resource_lease":resource_lease}
	var prepared: Dictionary = _profile.get_ref()._prepare_feature_configuration(configuration)
	if not bool(prepared.success):
		feature_load_errors = prepared.errors
		_feature_publication_in_progress = false
		return false
	_feature_commit_in_progress = true
	_feature_catalog = catalog
	_feature_authority = authority
	_feature_bindings = bindings
	_enabled_feature_modules = enabled
	_feature_resource_lease = resource_lease
	_profile.get_ref()._commit_feature_configuration(prepared)
	feature_load_errors = []
	feature_catalog_changed.emit()
	_feature_commit_in_progress = false
	_feature_publication_in_progress = false
	return true

func _feature_enabled_candidate(id: String, enabled: bool) -> Dictionary:
	_assert_owner()
	if _feature_publication_in_progress:
		feature_load_errors = ["feature_publication_in_progress"]
		return {}
	if not _feature_catalog.modules.has(id): return {}
	var candidate := _enabled_feature_modules.duplicate()
	if enabled == candidate.has(id): return {}
	if enabled:
		var context: Dictionary = _profile.get_ref().feature_publication_context()
		var boundary: String = _feature_catalog.modules[id].get("activation_boundary","startup")
		if not bool(context.world_ready) or (boundary == "startup" and bool(context.world_active)):
			feature_load_errors = ["feature_activation_boundary:" + id + ":" + boundary]
			return {}
		candidate.append(id)
	else: candidate.erase(id)
	candidate.sort()
	return {"candidate":_feature_catalog,"authority":_feature_authority,"bindings":_feature_bindings,"enabled":candidate}

func set_feature_module_enabled(id: String, enabled: bool) -> bool:
	var result := _feature_enabled_candidate(id,enabled)
	if result.is_empty(): return false
	var retained: RefCounted = null
	if not enabled and _feature_resource_lease != null:
		retained = _feature_resource_lease.retain_subset(result.candidate,result.enabled)
	return _publish_feature_configuration(result.candidate,result.authority,result.bindings,result.enabled,retained)

func set_feature_module_enabled_async(id: String, enabled: bool) -> bool:
	if not enabled: return set_feature_module_enabled(id,false)
	var result := _feature_enabled_candidate(id,enabled)
	if result.is_empty(): return false
	var context: Dictionary = _profile.get_ref().feature_publication_context()
	if not bool(context.scope_ready):
		feature_load_errors = ["feature_resource_preparation_scope_unavailable"]
		return false
	_feature_preparation_sequence += 1
	var sequence := _feature_preparation_sequence
	var scope: Dictionary = context.scope
	_feature_publication_in_progress = true
	# Root suspends at this original service.prepare call until genuine Main
	# resource facts arrive. Its apply_ready barrier remains the original
	# budgeted S application queue; neither service runs on a shadow M state.
	var ready: Dictionary = await _owner.get_ref().prepare_profile_feature_resources(result.candidate,result.enabled,sequence,scope)
	if sequence != _feature_preparation_sequence: return false
	if not bool(ready.success):
		_feature_publication_in_progress = false
		feature_load_errors = ready.errors
		return false
	var plan := Resources.requirements(result.candidate,result.enabled)
	var lease: RefCounted = _lease_from_prepared_ready(ready,result.candidate,result.enabled) if not plan.paths.is_empty() else null
	if not plan.paths.is_empty() and lease == null:
		_feature_publication_in_progress = false
		feature_load_errors = ["feature_resource_preparation_required"]
		return false
	var success: bool = await _owner.get_ref().apply_profile_feature_ready(Callable(self,"_apply_prepared_feature_module").bind(id,enabled,result,lease,sequence,scope))
	if sequence == _feature_preparation_sequence and _feature_publication_in_progress:
		_feature_publication_in_progress = false
		feature_load_errors = ["feature_resource_application_cancelled"]
	return success

func _apply_prepared_feature_module(id: String, enabled: bool, result: Dictionary, lease: RefCounted, sequence: int, scope: Dictionary) -> bool:
	if sequence != _feature_preparation_sequence: return false
	_feature_publication_in_progress = false
	var current := _feature_enabled_candidate(id,enabled)
	var context: Dictionary = _profile.get_ref().feature_publication_context()
	if current.is_empty() or not bool(context.scope_ready) or context.scope != scope or not is_same(result.candidate,_feature_catalog):
		feature_load_errors = ["feature_resource_preparation_stale"]
		return false
	return _publish_feature_configuration(result.candidate,result.authority,result.bindings,result.enabled,lease)

func cancel_feature_resource_preparation() -> void:
	_assert_owner()
	if _feature_commit_in_progress or bool(_owner.get_ref().profile_feature_is_applying()): return
	_feature_preparation_sequence += 1
	_feature_publication_in_progress = false
	_owner.get_ref().cancel_profile_feature_resources()

func _feature_reload_boundary() -> bool:
	_assert_owner()
	if _feature_publication_in_progress:
		feature_load_errors = ["feature_publication_in_progress"]
		return false
	if bool(_profile.get_ref().feature_publication_context().world_active):
		feature_load_errors = ["feature_directory_requires_world_retirement"]
		return false
	return true

func reload_feature_catalog_async(registry_path: String) -> bool:
	if not _feature_reload_boundary(): return false
	# Definition/code parsing may write the existing published static catalogs.
	# Root must retire the previous host/readers before the real Main canonical
	# compilation barrier; the returned publication contains values only.
	var result: Dictionary = await _owner.get_ref().prepare_profile_feature_directory(registry_path)
	if not bool(result.success):
		feature_load_errors = result.errors
		return false
	if not _feature_reload_boundary(): return false
	_feature_preparation_sequence += 1
	var sequence := _feature_preparation_sequence
	var profile: String = _profile.get_ref().active_profile_id
	_feature_publication_in_progress = true
	var ready: Dictionary = await _owner.get_ref().prepare_profile_feature_resources(result.candidate,result.enabled,sequence,{"profile_id":profile,"owners":{}})
	if sequence != _feature_preparation_sequence: return false
	if not bool(ready.success):
		_feature_publication_in_progress = false
		feature_load_errors = ready.errors
		return false
	var plan := Resources.requirements(result.candidate,result.enabled)
	var lease: RefCounted = _lease_from_prepared_ready(ready,result.candidate,result.enabled) if not plan.paths.is_empty() else null
	if not plan.paths.is_empty() and lease == null:
		_feature_publication_in_progress = false
		feature_load_errors = ["feature_resource_preparation_required"]
		return false
	var success: bool = await _owner.get_ref().apply_profile_feature_ready(Callable(self,"_apply_prepared_feature_candidate").bind(result,lease,sequence,profile))
	if sequence == _feature_preparation_sequence and _feature_publication_in_progress:
		_feature_publication_in_progress = false
		feature_load_errors = ["feature_resource_application_cancelled"]
	return success

func _apply_prepared_feature_candidate(result: Dictionary, lease: RefCounted, sequence: int, profile: String) -> bool:
	if sequence != _feature_preparation_sequence: return false
	_feature_publication_in_progress = false
	if _profile.get_ref().active_profile_id != profile or not _feature_reload_boundary():
		feature_load_errors = ["feature_resource_preparation_stale"]
		return false
	return _publish_feature_configuration(result.candidate,result.authority,result.bindings,result.enabled,lease)

func _lease_from_prepared_ready(ready: Dictionary, catalog: Dictionary, enabled: Array) -> RefCounted:
	# The canonical coordinator already issued/retains this exact Main-backed
	# S lease. Reissuing drops that reference and creates a second retention.
	var value: Variant = ready.get("lease")
	if not value is RefCounted or value.get_script() != Resources:
		return null
	var lease: RefCounted = value
	if not lease.is_domain() or not lease.valid_for(catalog, enabled):
		return null
	if lease._domain_thread != _thread or lease._domain_owner.get_ref() == null:
		return null
	return lease
