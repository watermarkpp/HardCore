extends RefCounted
const Session := preload("res://scripts/gameplay/source/source_session.gd")

const PROVIDER_ABI := {
	"failure":["record_fatal_source_fault"],
	"source_frames":["initialize_original_selected_world","dispatch_original_session_inputs","dispatch_original_session_phase","dispatch_original_close_process_boundary","prepare_original_source_session_close","close_original_source_session"],
	"admission":["bind_original_source_endpoint","verify_original_unselected_startup_source","prepare_original_profile_source_handoff","commit_original_profile_source_handoff","abort_original_profile_source_handoff","verify_original_loading_boundary","verify_actual_loading_pinned_closure","release_original_loading_pins"],
	"directory":["prepare_directory"],
	"live_feature":["admit_original_live_feature_continuations","commit_original_live_feature_reply","original_ticket_lease_obligations_retired","prepare_original_profile_feature_resources","apply_original_profile_feature_ready","retain_original_feature_publication","release_original_feature_retention","original_feature_retention_supports_path","original_feature_is_applying","cancel_original_feature_requests"]}

static func validate_required(host: Object, boot: Dictionary, services: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var thread := OS.get_thread_caller_id()
	if thread == OS.get_main_thread_id(): errors.append("actual_s_construction_required")
	if not ClassDB.class_exists("HardCoreGameplayGlobalRandom"): errors.append("actual_original_native_global_rng_required")
	if host == null or not host.is_class("HardCoreSimulationHost"): errors.append("actual_native_host_required")
	else:
		for method: String in ["current_clock_frame","current_host_paused","current_host_time_scale","capabilities","bind_original_world_context","finish_original_call_site","submit_live_original_resource","poll_live_original_resource","settle_live_original_resource","retire_live_original_resource","stage_original_main_prefix","ordered_main_prefix","next_original_operation_sequence","completed_original_operation_sequence","next_original_call_ordinal","exchange_original_primitive"]:
			if not host.has_method(method): errors.append("missing_actual_host_service:"+method)
	if not _runtime_boot_is_plain(boot): errors.append("plain_source_boot_required")
	if boot.get("contract_id") != "hardcore.source.session.boot.v1": errors.append("source_boot_contract_required")
	for field: String in ["session_id","journal_generation"]:
		if not boot.get(field) is int or int(boot.get(field,0)) <= 0: errors.append("positive_source_boot_integer:"+field)
	for field: String in ["project_settings","feature_process_scope","profile_process_scope","original_persistent_process_scopes","feature_resources","loading_source_site","engagement_handoff","enemy_shared_handoff","enemy_audio_handoff","global_random_handoff","source_admission_scope"]:
		if not boot.get(field) is Dictionary: errors.append("required_source_boot_publication:"+field)
	if not boot.get("profile_state_handoff") is Dictionary: errors.append("actual_selected_profile_handoff_required_before_Host_start")
	if not boot.get("first_world_boot") is Dictionary: errors.append("actual_prepared_first_world_boot_required_before_Host_start")
	if boot.get("profile_state_handoff") is Dictionary:
		for field: String in ["profile_publication","profile_state_handoff","content_snapshot","source_commit_receipt"]:
			if not boot.get(field) is Dictionary: errors.append("actual_loaded_profile_publication_required:"+field)
	var settings: Variant = boot.get("project_settings")
	if settings is Dictionary:
		for key: String in ["hardcore/performance/frame_optional_budget_usec","hardcore/performance/frame_progress_budget_usec"]:
			if not settings.get(key) is int or int(settings.get(key,0)) <= 0: errors.append("original_project_budget_setting_required:"+key)
	for name: String in PROVIDER_ABI:
		var provider: Variant = services.get(name)
		if not provider is RefCounted or provider is Resource or not provider.has_method("owner_thread_id") or provider.owner_thread_id() != thread:
			errors.append("actual_s_provider_missing_or_foreign:"+name)
			continue
		for method: String in PROVIDER_ABI[name]:
			if not provider.has_method(method): errors.append("required_source_provider_method:"+name+"."+method)
	if not ProfileSourceMethodsExist(): errors.append("promoted_original_profile_create_loaded_required")
	return {"success":errors.is_empty(),"errors":errors}

static func _runtime_boot_is_plain(boot: Dictionary) -> bool:
	# Runtime positions and geometry retain their actual Vector2/Vector2i types.
	# Content/save JSON validation stays strict at its independent boundary.
	if not ClassDB.class_exists("HardCoreContentValueGraph"): return false
	var native: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	if native == null: return false
	var checked: Dictionary = native.call("validate", boot, false)
	return checked.get("success", false) == true

static func ProfileSourceMethodsExist() -> bool:
	# Static script method exists only after exact frozen handoff promotion.
	var source: Script = preload("res://scripts/gameplay/profile/profile_owner_factory.gd")
	for method: Dictionary in source.get_script_method_list():
		if method.get("name")=="create_loaded" and (int(method.get("flags",0)) & METHOD_FLAG_STATIC)!=0:
			return true
	return false

static func create(host: Object, boot: Dictionary, services: Dictionary) -> Dictionary:
	var checked := validate_required(host, boot, services)
	if not checked.success: return checked
	var session := Session.new()
	if not session.initialize(host, boot, services):
		# Main may already have physically committed even if the Source suffix
		# failed. Retain that exact partial owner for staged close; initialization
		# failure alone is not authority to undo an admitted Main handoff.
		return {"success":false,"errors":["actual_source_session_admission_rejected"],"faulted_session":session}
	return {"success":true,"session":session,"profile_owner":session.original_profile_owner()}
