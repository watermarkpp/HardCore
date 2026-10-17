extends RefCounted
const Coordinator := preload("res://scripts/features/runtime/feature_resource_owner_coordinator.gd")
const Primitives := preload("res://scripts/features/runtime/feature_resource_owner_primitives.gd")
const Budget := preload("res://scripts/gameplay/enemy/enemy_owner_streaming_budget.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")

static func validate_required(owner: RefCounted, transport: RefCounted, shared_budget: RefCounted, clock: RefCounted, boot: Dictionary, process_scope: RefCounted) -> Dictionary:
	var errors: Array[String] = []
	var thread := OS.get_thread_caller_id()
	if thread == OS.get_main_thread_id(): errors.append("real_feature_resource_s_owner_required")
	if owner == null or owner is Resource: errors.append("owner_local_core_required")
	else:
		for method: String in ["owner_thread_id","fault","retain_feature_resource_publication","release_feature_resource_retention","feature_resource_retention_supports_path"]:
			if not owner.has_method(method): errors.append("missing_feature_resource_owner_service:"+method)
		if owner.has_method("owner_thread_id") and owner.owner_thread_id()!=thread: errors.append("feature_resource_core_owner_mismatch")
	if not shared_budget is Budget or not shared_budget.resource_continuations_configured(): errors.append("same_configured_streaming_owner_budget_required")
	for provider: RefCounted in [transport,shared_budget,clock]:
		if provider == null or not provider.has_method("owner_thread_id") or provider.owner_thread_id() != thread: errors.append("feature_resource_dependency_owner_mismatch")
	if transport != null:
		for method: String in ["next_original_operation_sequence","completed_original_operation_sequence","next_original_call_ordinal","capabilities","exchange_original_primitive","ordered_main_prefix"]:
			if not transport.has_method(method): errors.append("missing_unified_native_transport_service:"+method)
	if clock == null or not clock.has_method("get_ticks_usec"): errors.append("actual_wall_clock_required")
	if process_scope == null or process_scope is Resource: errors.append("canonical_service_process_scope_required")
	else:
		for method: String in ["owner_thread_id","is_inside_world","is_queued_for_retirement","can_process","set_process_processing_enabled","process_enabled"]:
			if not process_scope.has_method(method): errors.append("missing_service_process_scope_method:"+method)
		if process_scope.has_method("owner_thread_id") and process_scope.owner_thread_id() != thread: errors.append("service_process_scope_owner_mismatch")
	if not Gate.has_active_reader() or not Registry._loaded or Registry._result.get("success") != true or not Registry._result.is_read_only(): errors.append("actual_published_canonical_resource_declarations_required")
	for key: String in ["lease_owner","scene_tree"]:
		var descriptor: Variant = boot.get(key)
		if not descriptor is Dictionary or descriptor.size()!=5 or descriptor.get("contract_id") != "feature.main.reference.v1" or not descriptor.get("token_id") is int or int(descriptor.get("token_id",0)) <= 0 or not descriptor.get("object_id") is int or int(descriptor.get("object_id",0))<=0 or not descriptor.get("bridge_generation") is int or int(descriptor.get("bridge_generation",0))<=0 or not descriptor.get("native_types") is Array:
			errors.append("real_main_registered_reference_required:"+key)
		elif (key=="lease_owner" and "Node" not in descriptor.native_types) or (key=="scene_tree" and "SceneTree" not in descriptor.native_types):
			errors.append("actual_main_reference_type_required:"+key)
	var manifest: Variant=boot.get("source_callback_manifest")
	if not boot.get("original_idle_handoff") is Dictionary: errors.append("actual_original_Main_coordinator_idle_handoff_required")
	if not manifest is Dictionary or manifest.get("captured")!=true or not manifest.get("scope_id") is int or int(manifest.get("scope_id",0))<=0 or not manifest.get("process_priority") is int or not manifest.get("tree_ordinal") is int or not manifest.get("lazy_birth_entry") is String or str(manifest.get("lazy_birth_entry","")).is_empty():
		errors.append("captured_original_lazy_birth_process_callback_manifest_required")
	return {"success":errors.is_empty(),"errors":errors}

static func create(owner: RefCounted, transport: RefCounted, shared_budget: RefCounted, clock: RefCounted, boot: Dictionary, process_scope: RefCounted) -> Dictionary:
	var checked := validate_required(owner,transport,shared_budget,clock,boot,process_scope)
	if not checked.success: return checked
	var primitives := Primitives.new()
	if not primitives.configure_owner(owner,transport,shared_budget,clock,boot): return {"success":false,"errors":["feature_resource_primitives_admission_rejected"]}
	var coordinator := Coordinator.new()
	if not coordinator.configure_original_idle_handoff(boot.original_idle_handoff): return {"success":false,"errors":["original_Main_coordinator_idle_handoff_rejected"]}
	if not coordinator.configure_owner(primitives,shared_budget,process_scope): return {"success":false,"errors":["feature_resource_coordinator_owner_rejected"]}
	return {"success":true,"errors":[],"coordinator":coordinator,"primitives":primitives}
