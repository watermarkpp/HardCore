extends "res://scripts/gameplay/actors/enemy_shared_state.gd"
## Same original static algorithm instance retained by SourceSession. A world
## handoff rebinds provider/access only; no cache/queue/policy reset is inserted.
const WorkingGraph := preload("res://scripts/gameplay/world/world_runtime_working_graph.gd")
const ORIGINAL_SOURCE_SHA256 := "fd355ba5bbfb9d8f6b047049fbbd54b23260990169dbe3ac45bc5670ba48e265"
var _original_handoff: Dictionary = {}
var _original_handoff_installed := false
var _original_initial_construction := false
func configure_original_handoff(publication: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner_thread or _configured or _original_initial_construction or _original_handoff_installed or not _original_handoff.is_empty(): return false
	if publication.get("contract_id") == "world.enemy.shared_state.initial.v1":
		if publication.size() != 2 or publication.get("source_sha256") != ORIGINAL_SOURCE_SHA256: return false
		_original_initial_construction = true
		return true
	if OS.get_thread_caller_id() != _owner_thread or _original_handoff_installed or not _original_handoff.is_empty() or publication.size() != 3 or publication.get("contract_id") != "world.enemy.shared_state.handoff.v1" or publication.get("source_sha256") != ORIGINAL_SOURCE_SHA256 or not publication.get("fields") is Dictionary: return false
	var kinds := {
		"_crowd_query_candidate_count": [TYPE_INT],
		"_crowd_steering_evaluation_count": [TYPE_INT],
		"_retarget_full_scan_count": [TYPE_INT],
		"_retarget_decision_count": [TYPE_INT],
		"_target_grid_last_refresh_msec": [TYPE_INT],
		"_target_grid": [TYPE_DICTIONARY],
		"_target_grid_node_ids": [TYPE_DICTIONARY],
		"_target_grid_group_scan_count": [TYPE_INT],
		"_target_grid_candidate_count": [TYPE_INT],
		"_background_ai_evaluation_count": [TYPE_INT],
		"_background_fast_path_skip_count": [TYPE_INT],
		"_foreground_ai_tick_count": [TYPE_INT],
		"_background_deep_sleep_entry_count": [TYPE_INT],
		"_background_deep_sleep_wakeup_count": [TYPE_INT],
		"_physics_move_count": [TYPE_INT],
		"_environment_guard_check_count": [TYPE_INT],
		"_runtime_map_id_property_list_scan_count": [TYPE_INT],
		"_hc_shared_goal_cache": [TYPE_DICTIONARY],
		"_hc_shared_goal_cache_order": [TYPE_ARRAY],
		"_movement_authority_loaded": [TYPE_BOOL],
		"_movement_authority_load_failed": [TYPE_BOOL],
		"_movement_authority_by_id": [TYPE_DICTIONARY],
		"_attack_range_policy_loaded": [TYPE_BOOL],
		"_attack_range_policy_load_failed": [TYPE_BOOL],
		"_attack_range_policy_by_id": [TYPE_DICTIONARY],
		"_pursuit_process_budget_mode": [TYPE_STRING],
		"_pursuit_process_budget_stats": [TYPE_DICTIONARY],
		"_new_step_decision_interval_ms": [TYPE_INT],
		"_owner_decision_interval_ms": [TYPE_NIL, TYPE_INT],
		"_owner_optional_budget_enabled": [TYPE_NIL, TYPE_BOOL],
		"_ordinary_contact_instant_settle_enabled": [TYPE_NIL, TYPE_BOOL],
		"_ordinary_attack_visual_move_override_enabled": [TYPE_NIL, TYPE_BOOL],
		"_residual_phase_probe_enabled": [TYPE_BOOL],
		"_residual_phase_probe_totals": [TYPE_DICTIONARY],
		"_residual_phase_probe_calls": [TYPE_DICTIONARY],
		"_residual_phase_probe_source": [TYPE_STRING],
		"_attack_ab_mode": [TYPE_STRING],
		"_attack_ab_epoch": [TYPE_INT],
		"_attack_ab_epoch_attempts": [TYPE_INT],
		"_attack_ab_epoch_starts": [TYPE_INT],
		"_attack_ab_prune_epoch": [TYPE_INT],
		"_attack_ab_stats": [TYPE_DICTIONARY],
		"_attack_ab_queue": [TYPE_ARRAY],
		"_attack_ab_test_epoch_override": [TYPE_INT],
		"_hc_shared_static_query_tick": [TYPE_INT],
		"_hc_shared_safe_zone_tick_cache": [TYPE_DICTIONARY],
		"_hc_shared_world_tick_cache": [TYPE_DICTIONARY],
		"_hc_shared_walkable_tick_cache": [TYPE_DICTIONARY],
		"compute_optimization_test_mode": [TYPE_INT],
		"compute_optimization_shadow_checks": [TYPE_INT],
		"compute_optimization_shadow_missing_identities": [TYPE_INT],
		"compute_optimization_shadow_mismatches": [TYPE_INT],
		"compute_optimization_shadow_supersets": [TYPE_INT],
		"compute_optimization_shadow_first_mismatch": [TYPE_DICTIONARY]}
	var values: Dictionary = publication.fields
	if values.size() != kinds.size(): return false
	for key: String in kinds:
		if not values.has(key) or typeof(values.get(key)) not in kinds[key]: return false
	var restored: Dictionary = WorkingGraph.restore_runtime_roots(values)
	if restored.get("ok") != true: return false
	_original_handoff = restored.value
	return true
func bind_current_world(bindings: Dictionary, links: Object) -> bool:
	if OS.get_thread_caller_id() != _owner_thread or (not _original_handoff_installed and not _original_initial_construction and _original_handoff.is_empty()) or links == null: return false
	if not _configured:
		if not configure(bindings, links): return false
		for key: String in _original_handoff:
			if key == "_attack_ab_queue": _attack_ab_queue.assign(_original_handoff[key])
			else: set(key, _original_handoff[key])
		_original_handoff_installed = true
		_original_handoff = {}
		_original_initial_construction = false
	else:
		services = bindings
		actor_links = links
	return _original_handoff_installed
func original_handoff_applied() -> bool: return _original_handoff_installed
