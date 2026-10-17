extends RefCounted
## Actual Main loaded publications and existing shared state only. The caller
## owns catalog publication, physical Feature lease, original scope/life facts,
## generation/capacity policy, and the Math handoff fence. No new authority here.
const Observe:=preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
const Canonical:=preload("res://scripts/gameplay/profile/profile_publication.gd")
const CatalogGate:=preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const LegacyEnemy:=preload("res://scripts/gameplay/actors/enemy_legacy_context.gd")
const SharedOwner:=preload("res://scripts/gameplay/world/world_owner_enemy_shared.gd")
const ProfileView:=preload("res://scripts/gameplay/world/world_profile_ui_view.gd")
const SHARED_FIELDS: Array[String]=["_crowd_query_candidate_count", "_crowd_steering_evaluation_count", "_retarget_full_scan_count", "_retarget_decision_count", "_target_grid_last_refresh_msec", "_target_grid", "_target_grid_node_ids", "_target_grid_group_scan_count", "_target_grid_candidate_count", "_background_ai_evaluation_count", "_background_fast_path_skip_count", "_foreground_ai_tick_count", "_background_deep_sleep_entry_count", "_background_deep_sleep_wakeup_count", "_physics_move_count", "_environment_guard_check_count", "_runtime_map_id_property_list_scan_count", "_hc_shared_goal_cache", "_hc_shared_goal_cache_order", "_movement_authority_loaded", "_movement_authority_load_failed", "_movement_authority_by_id", "_attack_range_policy_loaded", "_attack_range_policy_load_failed", "_attack_range_policy_by_id", "_pursuit_process_budget_mode", "_pursuit_process_budget_stats", "_new_step_decision_interval_ms", "_owner_decision_interval_ms", "_owner_optional_budget_enabled", "_ordinary_contact_instant_settle_enabled", "_ordinary_attack_visual_move_override_enabled", "_residual_phase_probe_enabled", "_residual_phase_probe_totals", "_residual_phase_probe_calls", "_residual_phase_probe_source", "_attack_ab_mode", "_attack_ab_epoch", "_attack_ab_epoch_attempts", "_attack_ab_epoch_starts", "_attack_ab_prune_epoch", "_attack_ab_stats", "_attack_ab_queue", "_attack_ab_test_epoch_override", "_hc_shared_static_query_tick", "_hc_shared_safe_zone_tick_cache", "_hc_shared_world_tick_cache", "_hc_shared_walkable_tick_cache", "compute_optimization_test_mode", "compute_optimization_shadow_checks", "compute_optimization_shadow_missing_identities", "compute_optimization_shadow_mismatches", "compute_optimization_shadow_supersets", "compute_optimization_shadow_first_mismatch"]
var _facade: Node
var _feature_main: RefCounted
var _fields: RefCounted
var _canonical_prepared: Dictionary
var _catalog_lease: Dictionary
var _feature_publication: Dictionary
func owner_thread_id() -> int:return OS.get_main_thread_id()
func prepare_original_selected_session_front(blueprint: Dictionary,prepared: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _fields==null or not _fields.has_method("prepare_actual_original_session_front"): return Observe.missing("actual_Main_session_front_producer_required")
	return _fields.prepare_actual_original_session_front(blueprint,prepared)
func configure_main(facade: Node,feature_main: RefCounted,canonical_prepared: Dictionary,catalog_lease: Dictionary,feature_publication: Dictionary,actual_fields: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _facade!=null or not is_instance_valid(facade) or not facade.is_inside_tree() or facade!=facade.get_tree().root.get_node_or_null("PlayerState") or facade.get_script()!=preload("res://scripts/player_state.gd"):return false
	if feature_main==null or feature_main.get_script()!=preload("res://scripts/features/runtime/feature_resource_main_primitives.gd") or actual_fields==null or not actual_fields.has_method("capture_actual_original_selected_session_fields"):return false
	if canonical_prepared.get("success")!=true or not canonical_prepared.get("publication") is Dictionary or not CatalogGate.is_active(catalog_lease):return false
	_facade=facade;_feature_main=feature_main;_canonical_prepared=canonical_prepared;_catalog_lease=catalog_lease;_feature_publication=feature_publication;_fields=actual_fields;return true
static func capture_original_enemy_shared_initialization() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return Observe.missing("actual_Main_shared_capture_required")
	var code: Script = preload("res://scripts/gameplay/actors/enemy_shared_state.gd")
	if code.get_source_code().sha256_text() != SharedOwner.ORIGINAL_SOURCE_SHA256: return Observe.missing("original_Enemy_shared_source_changed")
	var context: RefCounted = LegacyEnemy._main_context
	if context == null:
		# Nothing was constructed on Main. S executes the SAME original fresh
		# constructor/configure at its own owner; do not create a fake Main
		# shared instance merely to copy defaults back over S configuration.
		return Observe.capture({"contract_id":"world.enemy.shared_state.initial.v1", "source_sha256":SharedOwner.ORIGINAL_SOURCE_SHA256})
	if context.shared == null: return Observe.missing("actual_Main_enemy_shared_initialization_incomplete")
	var values: Dictionary = {}
	for field: String in SHARED_FIELDS: values[field] = context.shared.get(field)
	for field: String in ["_target_grid","_target_grid_node_ids","_attack_ab_queue"]:
		if not values[field].is_empty(): return Observe.missing("actual_legacy_actor_identity_job_handoff_required",{"field":field,"actual_pending_values":values[field]})
	return Observe.capture({"contract_id":"world.enemy.shared_state.handoff.v1", "source_sha256":SharedOwner.ORIGINAL_SOURCE_SHA256, "fields":values})

func capture_actual_existing_shared_handoffs() -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _feature_main==null:return Observe.missing("actual_Main_shared_capture_required")
	var shared: Dictionary = capture_original_enemy_shared_initialization()
	if shared.get("success") != true: return shared
	var audio: Dictionary={"contract_id":"world.enemy.audio_shared.handoff.v1","_audio_runtime_service":null,"_audio_service_retry_after_msec":EnemyActor._audio_service_retry_after_msec,"_audio_service_lookup_count":EnemyActor._audio_service_lookup_count,"_audio_service_now_override_msec":EnemyActor._audio_service_now_override_msec}
	if EnemyActor._audio_runtime_service!=null:
		if not is_instance_valid(EnemyActor._audio_runtime_service):return Observe.missing("actual_cached_Main_audio_reference_invalid")
		var descriptor: Variant=_feature_main.export_boot_value(EnemyActor._audio_runtime_service)
		if not descriptor is Dictionary:return Observe.missing("actual_registered_Main_audio_descriptor_required")
		audio._audio_runtime_service=descriptor
	var engagement: Dictionary={"_active":AoeEngagementWindow._active,"_reported":AoeEngagementWindow._reported,"_cast_start_usec":AoeEngagementWindow._cast_start_usec,"_deadline_ms":AoeEngagementWindow._deadline_ms,"_cast_to_field_ms":AoeEngagementWindow._cast_to_field_ms,"_cast_to_tick_ms":AoeEngagementWindow._cast_to_tick_ms,"_cast_to_death_ms":AoeEngagementWindow._cast_to_death_ms,"_frame_intervals_ms":AoeEngagementWindow._frame_intervals_ms,"_frames_dropped":AoeEngagementWindow._frames_dropped,"_last_report":AoeEngagementWindow._last_report}
	return Observe.capture({"enemy_shared_handoff":shared.publication,"enemy_audio_handoff":audio,"engagement_handoff":{"contract_id":"world.aoe_engagement.handoff.v1","fields":engagement}})
func capture_original_selected_session_boot_fields(blueprint: Dictionary,prepared: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _facade==null or prepared.get("success")!=true:return Observe.missing("actual_selected_prepared_Profile_required")
	var gate: RefCounted=_facade.get("_source_domain_gate")
	if gate==null or gate.state()!="PREPARED":return Observe.missing("actual_Main_prepared_and_uncommitted_Profile_gate")
	var receipt: Dictionary=prepared.get("receipt",{})
	var handoff: Dictionary=prepared.get("state_publication",{})
	var model: RefCounted=_facade.get("_model")
	if model==null or receipt.get("facade_id")!=_facade.get_instance_id() or receipt.get("model_id")!=model.get_instance_id() or handoff.get("active_profile_id")!=blueprint.get("world",{}).get("profile_id") or handoff.get("source_witness",{}).get("model_object_id")!=model.get_instance_id():return Observe.missing("actual_loaded_Profile_same_receiver_identity")
	if not CatalogGate.is_active(_catalog_lease) or _canonical_prepared.publication.get("configuration_revision")!=ContentLayers.configuration_revision or _canonical_prepared.publication.get("database_revision")!=GameData.database_revision:return Observe.missing("actual_catalog_publication_revision_required")
	var features: Dictionary=ContentLayers.feature_configuration()
	var lease: Variant=features.get("resource_lease")
	if not _feature_publication.is_empty():
		var id: Variant=_feature_publication.get("publication_id")
		var publications: Dictionary=_feature_main.get("_publications")
		if not id is int or not publications.has(id) or publications[id].publication!=_feature_publication or not publications[id].lease is WeakRef or not is_same(publications[id].lease.get_ref(),lease):return Observe.missing("actual_same_Main_vault_Feature_publication_lease_required")
	var front: Dictionary = prepare_original_selected_session_front(blueprint,prepared)
	if front.get("success") != true or not front.get("front") is Dictionary: return Observe.missing("actual_same_prepared_Session_front_required",front)
	var same: Dictionary = front.front
	if same.get("prepared_receipt") != receipt or same.get("world") != blueprint.get("world"): return Observe.missing("actual_Session_front_identity_changed")
	var profile: Dictionary = same.get("profile_publication",{})
	var content: Dictionary = same.get("content_snapshot",{})
	if profile.is_empty() or content.is_empty():return Observe.missing("actual_loaded_canonical_Profile_Content_publications")
	if not profile.is_read_only() or not content.is_read_only() or profile.get("catalog_lease") != _catalog_lease or content.get("catalog_lease") != _catalog_lease or profile.get("database_revision") != GameData.database_revision or content.get("database_revision") != GameData.database_revision or profile.get("configuration_revision") != ContentLayers.configuration_revision or profile.get("features",{}).get("resource_publication") != _feature_publication: return Observe.missing("actual_same_immutable_Profile_Content_seals_required")
	var origins: Dictionary=prepared.get("original_persistent_process_scopes",{})
	for key: String in ["profile","feature","profile_receipts"]:
		if origins.get(key,{}).get("success")!=true:return Observe.missing("actual_pre_disable_persistent_process_scope:"+key)
	var observed: Dictionary={"profile_publication":profile,"content_snapshot":content,"profile_state_handoff":handoff,"source_commit_receipt":receipt,"project_settings":Observe.settings(),"original_persistent_process_scopes":origins,"profile_process_scope":origins.profile.scope,"feature_process_scope":origins.feature.scope}
	var captured: Dictionary=capture_actual_existing_shared_handoffs()
	if captured.get("success")!=true:return Observe.missing("actual_shared_static_handoff_incomplete",{"loaded_publications":observed,"shared":captured})
	observed.merge(captured.publication)
	var supplied: Dictionary=_fields.capture_actual_original_selected_session_fields(blueprint,prepared)
	if supplied.get("success")!=true or not supplied.get("fields") is Dictionary or supplied.get("prepared_receipt")!=receipt:return Observe.missing("actual_selected_session_identity_scope_loading_RNG_policy_producer",{"actual_loaded_publications":observed,"actual_fields":supplied})
	var boot: Dictionary=supplied.fields.duplicate(true)
	for key: String in ["session_id","journal_generation"]:
		if not boot.get(key) is int or boot[key]<=0:return Observe.missing("actual_positive_session_authority:"+key,observed)
	for key: String in ["project_settings","feature_resources","loading_source_site","feature_live_reservation_usec","streaming_live_reservation_usec"]:
		if not boot.get(key) is Dictionary:return Observe.missing("actual_session_field_producer:"+key,observed)
	if boot.loading_source_site.get("world_context")!=blueprint.get("world") or boot.loading_source_site.get("clock_epoch")!=0 or boot.loading_source_site.get("bootstrap")!=true:return Observe.missing("actual_epoch0_session_Loading_site",observed)
	for key: String in ["release_reference","release_retention"]:
		if not boot.feature_live_reservation_usec.get(key) is int or boot.feature_live_reservation_usec[key]<0:return Observe.missing("actual_feature_live_reservation_policy:"+key,observed)
	for key: StringName in preload("res://scripts/gameplay/enemy/enemy_owner_resource_primitives.gd").LIVE_OPERATIONS:
		if not boot.streaming_live_reservation_usec.get(key) is int or boot.streaming_live_reservation_usec[key]<0:return Observe.missing("actual_streaming_live_reservation_policy:"+String(key),observed)
	if prepared.get("resource_idle_state",{}).get("contract_id") != "hardcore.feature.coordinator.idle_handoff.v1": return Observe.missing("actual_prepared_Main_coordinator_idle_handoff")
	boot.feature_resources = boot.feature_resources.duplicate(true)
	boot.feature_resources.original_idle_handoff = prepared.resource_idle_state
	var settings: Dictionary=boot.project_settings.duplicate(true)
	settings.merge(observed.project_settings,true)
	observed.project_settings=settings
	boot.merge(observed,true)
	boot.erase("profile_scope_observation")
	boot.contract_id="hardcore.source.session.boot.v1"
	var view: Dictionary=supplied.get("actual_loaded_profile_view",{})
	if view.get("session_id")!=boot.session_id or view.get("profile_model_id")!=model.get_instance_id() or view.get("handoff_identity")!=ProfileView.original_handoff_identity(handoff) or view.get("origin")!="actual_Main_loaded_before_adoption" or view.get("world_context")!=blueprint.world:return Observe.missing("actual_Main_loaded_readonly_Profile_view",observed)
	# These two exact readonly publications were already sealed by their actual
	# catalog owners and verified above. Capture only the new Session envelope
	# metadata; the final Native boot capture still owns the complete draft.
	boot.erase("profile_publication"); boot.erase("content_snapshot")
	var copied: Dictionary=Observe.capture(boot)
	if copied.get("success") != true: return copied
	var publication: Dictionary = copied.publication.duplicate(false)
	publication["profile_publication"] = profile
	publication["content_snapshot"] = content
	publication.make_read_only()
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"SESSION_PROVIDER_REUSED_ACTUAL_SEALED_CONTENT")
	return {"success":true,"boot":publication,"actual_loaded_profile_view":view,"actual_source_fields_receipt":supplied}
