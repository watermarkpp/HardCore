extends RefCounted

# An acquisition operation for the existing FeatureResourcePreparation queue.
# Owns no Node, _process, cache, native request, timer, or retirement queue.
# Call only inside that service's already-open feature_resources quantum.
# The returned strong ref belongs to the caller, including a failed validation;
# the caller must deliver it into an existing held lease or retire_resources.
static func acquire_shader(plan: RefCounted, scope: RefCounted, consumer: Node, generation: int, path: String, existing_job: Dictionary) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return _result(false, "code_input_wrong_thread", null, "", false, started_usec)
	if plan == null or scope == null or not plan.has_method("is_verified") or not plan.has_method("paths") or not plan.has_method("valid_asset"):
		return _result(false, "code_input_plan_or_scope_missing", null, "", false, started_usec)
	if not bool(plan.is_verified()) or path not in plan.paths() or not path.ends_with(".gdshader"):
		return _result(false, "code_input_not_verified_shader", null, "", false, started_usec)
	if not scope.has_method("valid_for") or not bool(scope.valid_for(consumer, generation)):
		return _result(false, "code_input_cover_or_generation_expired", null, "", false, started_usec)
	# Do not borrow another async participant's retrieval right or mix initial
	# main-thread construction with an already accepted threaded asset job.
	if bool(existing_job.get("started", false)) or (not existing_job.is_empty() and existing_job.get("type") != "Shader"):
		return _result(false, "code_input_existing_job_mode_conflict", null, "", false, started_usec)
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return _result(false, "code_input_native_asset_job_mode_conflict", null, "", false, started_usec)
	var cache_before := ResourceLoader.has_cached(path)
	var resource: Resource = ResourceLoader.get_cached_ref(path)
	var mode := "cache_hits" if resource != null else "main_thread_input"
	if resource == null:
		resource = ResourceLoader.load(path, "Shader", ResourceLoader.CACHE_MODE_REUSE)
	if resource == null:
		return _result(false, "code_input_load_failed:" + path, null, mode, cache_before, started_usec)
	if not bool(scope.valid_for(consumer, generation)) or not bool(plan.is_verified()):
		return _result(false, "code_input_owner_or_residency_expired", resource, mode, cache_before, started_usec)
	if not bool(plan.valid_asset(path, resource)):
		return _result(false, "code_input_source_type_or_code_changed:" + path, resource, mode, cache_before, started_usec)
	return _result(true, "", resource, mode, cache_before, started_usec)

static func _result(success: bool, error: String, resource: Resource, mode: String, cache_before: bool, started_usec: int) -> Dictionary:
	return {"success": success, "errors": [] if success else [error], "resource": resource, "mode": mode,
		"cache_before": cache_before, "elapsed_usec": Time.get_ticks_usec() - started_usec,
		"actual_class": resource.get_class() if resource != null else "", "resource_path": resource.resource_path if resource != null else "",
		"resource_instance_id": resource.get_instance_id() if resource != null else 0,
		"fixture_or_operation_native_request_calls": 0, "fixture_or_operation_native_get_calls": 0}
