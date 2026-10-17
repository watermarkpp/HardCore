extends "res://scripts/gameplay/world/world_root_view_helpers.gd"
const WorldBootstrapCoordinator := preload("res://scripts/gameplay/world/world_map_loading_coordinator.gd")
const MONSTER_PREFETCH_TIMEOUT_MSEC := 8000
const INPUT_LOCK_MAP_TRANSITION_LOCAL := INPUT_LOCK_MAP_TRANSITION
const DEFAULT_BOSS_RESPAWN_SECONDS := SourceMonsterRespawnPolicy.BOSS_SECONDS
const SourceMonsterRespawnPolicy := preload("res://scripts/monster_respawn_policy.gd")
const INPUT_LOCK_MAP_TRANSITION := &"map_transition"
const MonsterTerrainNavigationPolicyScript := preload("res://scripts/monster_terrain_navigation_policy.gd")
const LoadingTransitionOverlay := preload("res://scripts/loading_transition_overlay.gd")
const MapPolicy := preload("res://scripts/gameplay/world/world_map_teleport_policy_owner.gd")
const GothicBichCampBuilderScript := preload("res://scripts/layers/presentation/gothic_bich_camp_builder.gd")
func _await_actual_interactable_Loading_ready(coordinator: RefCounted,generation: int,transition_id: String) -> bool:
	if _world.interactables==null: return _source_fail("MISSING_actual_interactable_Loading_owner")
	while not _world.interactables.original_loading_visuals_ready():
		if _world.is_faulted() or not _world_pipeline_owner_current(coordinator,generation,transition_id): return false
		await _world.profile_runtime.next_service()
	return true

var MapTeleportRuntimePolicyScript: RefCounted
var _active_map_transition_id: Variant:
	get: return _fields.read_source_field(&"_active_map_transition_id")
	set(value): _fields.write_source_field(&"_active_map_transition_id",value)
var _active_portal_claim_id: Variant:
	get: return _fields.read_source_field(&"_active_portal_claim_id")
	set(value): _fields.write_source_field(&"_active_portal_claim_id",value)
var _active_portal_claim_transition_serial: Variant:
	get: return _fields.read_source_field(&"_active_portal_claim_transition_serial")
	set(value): _fields.write_source_field(&"_active_portal_claim_transition_serial",value)
var _bich_camp_layout: Variant:
	get: return _fields.read_source_field(&"_bich_camp_layout")
	set(value): _fields.write_source_field(&"_bich_camp_layout",value)
var _combat_spatial_index: Variant:
	get: return _fields.read_source_field(&"_combat_spatial_index")
	set(value): _fields.write_source_field(&"_combat_spatial_index",value)
var _last_monster_prefetch_status: Variant:
	get: return _fields.read_source_field(&"_last_monster_prefetch_status")
	set(value): _fields.write_source_field(&"_last_monster_prefetch_status",value)
var _map_failure_recovery_active: Variant:
	get: return _fields.read_source_field(&"_map_failure_recovery_active")
	set(value): _fields.write_source_field(&"_map_failure_recovery_active",value)
var _map_transition_environment_replaced: Variant:
	get: return _fields.read_source_field(&"_map_transition_environment_replaced")
	set(value): _fields.write_source_field(&"_map_transition_environment_replaced",value)
var _map_transition_serial: Variant:
	get: return _fields.read_source_field(&"_map_transition_serial")
	set(value): _fields.write_source_field(&"_map_transition_serial",value)
var _monster_prefetch_enabled: Variant:
	get: return _fields.read_source_field(&"_monster_prefetch_enabled")
	set(value): _fields.write_source_field(&"_monster_prefetch_enabled",value)
var _ready_world_map_id: Variant:
	get: return _fields.read_source_field(&"_ready_world_map_id")
	set(value): _fields.write_source_field(&"_ready_world_map_id",value)
var _ready_world_zone_generation: Variant:
	get: return _fields.read_source_field(&"_ready_world_zone_generation")
	set(value): _fields.write_source_field(&"_ready_world_zone_generation",value)
var _safe_zone_revision: Variant:
	get: return _fields.read_source_field(&"_safe_zone_revision")
	set(value): _fields.write_source_field(&"_safe_zone_revision",value)
var _streaming_coordinator: Variant:
	get: return _fields.read_source_field(&"_streaming_coordinator")
	set(value): _fields.write_source_field(&"_streaming_coordinator",value)
var _town_music_controller: Variant:
	get: return _fields.read_source_field(&"_town_music_controller")
	set(value): _fields.write_source_field(&"_town_music_controller",value)
var _world_camera: Variant:
	get: return _fields.read_source_field(&"_world_camera")
	set(value): _fields.write_source_field(&"_world_camera",value)
var _world_context: Variant:
	get: return _fields.read_source_field(&"_world_context")
	set(value): _fields.write_source_field(&"_world_context",value)
var current_map_data: Variant:
	get: return _fields.read_source_field(&"current_map_data")
	set(value): _fields.write_source_field(&"current_map_data",value)
var projection_rejection_reason: Variant:
	get: return _fields.read_source_field(&"projection_rejection_reason")
	set(value): _fields.write_source_field(&"projection_rejection_reason",value)
var reference_audit_mode: Variant:
	get: return _fields.read_source_field(&"reference_audit_mode")
	set(value): _fields.write_source_field(&"reference_audit_mode",value)
var _map_loading_port: RefCounted
var _map_background: RefCounted
var _map_source_helpers: Dictionary
var background: RefCounted:
	get: return _map_background
func install_original_map_loading_port(port: RefCounted, actual_background: RefCounted, publication: Dictionary) -> bool:
	if _map_loading_port != null or port.owner_thread_id() != owner_thread_id() or actual_background.owner_thread_id() != owner_thread_id(): return false
	if not _world.original_source_session().has_method("can_commit_original_source_map_arrival_context") or not _world.original_source_session().can_commit_original_source_map_arrival_context(self,_world,publication): return _source_fail("MISSING_actual_dynamic_Source_map_context")
	var supplied: Dictionary = _world.original_source_session().original_map_source_root_helpers(self).duplicate(false)
	for name: StringName in ["_preload_map_loot_icons", "_prewarm_learned_skill_visuals", "_warm_fire_wall_render_path"]:
		var cb: Variant = supplied.get(name)
		if not cb is Callable or not cb.is_valid() or cb.get_object() != self or cb.get_method() != name: return _source_fail("MISSING_actual_SourceRoot_map_helper",{"method":name})

	supplied[&"_active_skill_workset_candidates"] = Callable(self,&"_active_skill_workset_candidates")
	supplied[&"_print_session_diagnostics_header"] = Callable(self,&"_print_session_diagnostics_header")
	supplied[&"_spawn_map_portal"] = Callable(self,&"_spawn_map_portal")
	supplied[&"_spawn_npc"] = Callable(self,&"_spawn_npc")
	supplied[&"_spawn_portal"] = Callable(self,&"_spawn_portal")
	# Store only names: bound Callables would retain this RefCounted Root itself.
	for method: StringName in ["_active_skill_workset_candidates","_preload_map_loot_icons","_prewarm_learned_skill_visuals","_print_session_diagnostics_header","_spawn_map_portal","_spawn_npc","_spawn_portal","_warm_fire_wall_render_path"]:
		if not has_method(method): return _source_fail("MISSING_actual_SourceRoot_map_helper",{"method":method})
		_map_source_helpers[method] = method
	_map_loading_port = port; _map_background = actual_background
	MapTeleportRuntimePolicyScript = MapPolicy.new()
	if not MapTeleportRuntimePolicyScript.configure_owner(_world.environment_factory.runtime_maps): return false
	return true
func original_map_coordinator_generation() -> int:
	return int(_world_bootstrap_coordinator.generation) if _world_bootstrap_coordinator != null else -1
func original_map_coordinator_is_current(generation: int) -> bool:
	return _world_bootstrap_coordinator != null and _world_bootstrap_coordinator.is_generation_current(generation)
func original_map_loading_transport() -> RefCounted: return _map_loading_port.transport() if _map_loading_port != null else null

func _source_travel_to_service_home(
	red_name := false,
	initial := false,
	fallback_zone := "",
	after_arrival := Callable()
) -> bool:
	# P1-002/004: always route through coordinator pipeline
	var service_map_id: Variant = _world.owner_services.GameData.service_home_map_id(red_name)
	var runtime_map_id: Variant = _world.owner_services.GameData.service_runtime_map_id(service_map_id)
	var home_result: Variant = _resolve_bich_home()
	if not bool(home_result.get("valid", false)):
		_handle_home_resolution_failure(&"travel_to_service_home", home_result)
		return false
	var operation: Variant = Callable(self, "_complete_service_home_travel").bind(
		red_name, initial, fallback_zone, after_arrival
	)
	return _begin_map_transition(operation, runtime_map_id)



func _complete_service_home_travel(
	red_name: bool,
	initial: bool,
	fallback_zone: String,
	after_arrival: Callable
) -> void:
	_travel_to_service_home_immediate(red_name, initial, fallback_zone)
	if after_arrival.is_valid():
		after_arrival.call()



func _travel_to_service_home_immediate(
	red_name := false,
	initial := false,
	fallback_zone := ""
) -> void:
	var home: Variant = _resolve_bich_home()
	if not bool(home.get("valid", false)):
		_handle_home_resolution_failure(&"service_home_immediate", home)
		return
	var service_map_id: Variant = _world.owner_services.GameData.service_home_map_id(red_name)
	var runtime_map_id: Variant = _world.owner_services.GameData.service_runtime_map_id(service_map_id)
	var map_data: Variant = _world.owner_services.GameData.get_map_by_id(runtime_map_id)
	if not map_data.is_empty():
		_load_zone(str(map_data.get("name", "比奇省")), initial, map_data)
		if not red_name and service_map_id == 0:
			# 服务端(289,618)直接进入700×700原MAP统一坐标，不再压缩到场景中心。
			_set_player_world_position(home.get("position_px", Vector2.ZERO) as Vector2)
			player.velocity = Vector2.ZERO
			_relocate_main_pets_after_map_arrival()
			background.set_focus_position(player.global_position)
	else:
		# 红名地图3尚未进入项目地图表；保留显式回退，不伪造服务端映射。
		var resolved_fallback: Variant = fallback_zone
		if resolved_fallback.is_empty():
			resolved_fallback = "比奇省" if not red_name else "比奇郊外"
		_change_zone_immediate(resolved_fallback, initial)



func _change_zone_immediate(zone_name: String, initial := false) -> void:
	if zone_name == "比奇城":
		# 旧样板把“比奇城”画成独立伪地图；经典客户端中城镇属于0.map的比奇省。
		# 保留旧调用兼容，但统一进入服务端地图0所映射的运行地图4。
		var bich_map: Variant = _world.owner_services.GameData.get_map_by_id(_world.owner_services.GameData.service_runtime_map_id(0))
		var home: Variant = _resolve_bich_home()
		if not bool(home.get("valid", false)):
			_handle_home_resolution_failure(&"change_zone_bich", home)
			return
		_load_zone(str(bich_map.get("name", "比奇省")), initial, bich_map)
		_set_player_world_position(home.get("position_px", Vector2.ZERO) as Vector2)
		player.velocity = Vector2.ZERO
		_relocate_main_pets_after_map_arrival()
		background.set_focus_position(player.global_position)
		return
	_load_zone(zone_name, initial, _world.owner_services.GameData.get_map(zone_name))



func _begin_map_transition(
	operation: Callable,
	target_map_id := -1,
	portal_claim_id := ""
) -> bool:
	if _map_transition_in_progress or not operation.is_valid():
		return false
	if not is_instance_valid(player):
		return false
	var revival_authorized: Variant = _death_revival_request_in_flight and not _active_death_id.is_empty()
	if (player._dead or player.current_hp <= 0) and not revival_authorized:
		return false
	_map_transition_serial += 1
	if not portal_claim_id.is_empty():
		_active_portal_claim_transition_serial = _map_transition_serial
	var combat_token: Variant = "map-combat:%d" % _map_transition_serial
	if not player.begin_combat_transition(combat_token, revival_authorized):
		return false
	_world_bootstrap_coordinator.begin_map_transition(target_map_id)
	_world_bootstrap_coordinator.advance(WorldBootstrapCoordinator.Stage.SHOW_LOADING)
	_active_map_transition_id = "map:%d:%d" % [
		_world.clock_ports.get_ticks_msec(),
		_map_transition_serial,
	]
	_fields.write_source_field(&"map_combat_transition_token",combat_token)
	_map_transition_in_progress = true
	_map_transition_environment_replaced = false
	if is_instance_valid(_town_music_controller):
		_town_music_controller.begin_map_transition(target_map_id, _active_map_transition_id)
	# A new transition takes over the retained terminal map lock, if any.
	if not _gameplay_input_locks.has(INPUT_LOCK_MAP_TRANSITION_LOCAL):
		_acquire_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)
	_cancel_map_transition_movement_input()
	_run_map_transition(_active_map_transition_id, operation, target_map_id)
	return true



func _begin_monster_transition_prefetch(target_map_id: int) -> Dictionary:
	# Same-map Home/revival/teleport keeps the existing EnemyActors: _load_zone
	# returns without rebuilding that world. Do not fence their visual leases
	# merely because a Loading transition is shown. A real map change (or first
	# bootstrap) still starts a new generation and rejects stale actors.
	if target_map_id == current_map_id and target_map_id >= 0 and not _world_bootstrap_in_progress:
		return {"complete": true, "preserved_world": true}
	return _streaming_coordinator.begin_map_prefetch(
		_monster_ids_for_map(target_map_id), _world_bootstrap_in_progress
	)



func _run_map_transition(
	transition_id: String,
	operation: Callable,
	target_map_id: int
) -> void:
	hud.begin_loading_transition(transition_id)
	# perf(R13-D1): total-loading timing profile. Read-only diagnostics only;
	# the production execution order below is untouched. Covered = the moment
	# the overlay confirmed coverage (loading_transition_covered); total = the
	# moment the loading cover lift starts (fade excluded).
	var r13_mode: Variant = "map_transition"
	if _world_bootstrap_in_progress:
		r13_mode = "initial_world"
	var r13_loading_profile: Variant = {
		"mode": r13_mode,
		"transition_id": transition_id,
		"target_map_id": target_map_id,
		"covered_usec": 0,
		"monster_prefetch_ms": 0.0,
		"world_pipeline_ms": 0.0,
		"actor_spawn_ms": 0.0,
		"skill_workset_ms": 0.0,
		"render_warm_ms": 0.0,
		"ui_panels_ms": 0.0,
		"finalize_ms": 0.0,
	}
	var r13_stage_started_usec: Variant = _world.clock_ports.get_ticks_usec()
	if not _world.profile.test_mode:
		while _map_transition_in_progress and _active_map_transition_id == transition_id:
			var request: Dictionary = await hud.loading_transition_covered
			if (
				str(request.get("contract_id", "")) == LoadingTransitionOverlay.CONTRACT_ID
				and str(request.get("transition_id", "")) == transition_id
			):
				r13_loading_profile["covered_usec"] = _world.clock_ports.get_ticks_usec()
				break
	else:
		# Test mode skips the real covered await; anchor at begin for the
		# stage decomposition (diagnostics only).
		r13_loading_profile["covered_usec"] = r13_stage_started_usec
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	if not await _map_loading_port.begin_original_map_loading(transition_id,_world_bootstrap_coordinator.generation,target_map_id):
		var admission: RefCounted = _map_loading_port.transport().get("_admission")
		_world.fault("actual_map_Loading_admission_missing",admission.actual_original_missing_boundary())
		return
	hud.update_loading_progress(transition_id, 0.05, "准备场景")
	# The player-visible bar reports completed loading stages; UI construction
	# is included in the initial covered window after the world becomes ready.
	_last_monster_prefetch_status.clear()
	r13_stage_started_usec = _world.clock_ports.get_ticks_usec()
	if not await _map_source_helper__preload_map_loot_icons(target_map_id):
		_world.fault("actual_map_loot_icon_prewarm_failed",{})
		return
	if _world.profile.test_mode:
		_last_monster_prefetch_status = {"complete": true}
	elif _monster_prefetch_enabled and target_map_id >= 0:
		_last_monster_prefetch_status = (
			_begin_monster_transition_prefetch(target_map_id)
		)
		var prefetch_deadline: Variant = (
			_world.clock_ports.get_ticks_msec() + MONSTER_PREFETCH_TIMEOUT_MSEC
		)
		while (
			_map_transition_in_progress
			and _active_map_transition_id == transition_id
			and not bool(_last_monster_prefetch_status.get("complete", false))
			and _world.clock_ports.get_ticks_msec() < prefetch_deadline
		):
			await _world.profile_runtime.next_service()
			_last_monster_prefetch_status = (
				_streaming_coordinator.poll_once(int(_world.current_clock_frame().source_process_frame))
			)
	elif _monster_prefetch_enabled:
		_streaming_coordinator.release_map_pins()
	r13_loading_profile["monster_prefetch_ms"] = (
		float(_world.clock_ports.get_ticks_usec() - r13_stage_started_usec) / 1000.0
	)
	hud.update_loading_progress(transition_id, 0.22, "资源已准备")
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	# HC-P1-004: stage the world build through the coordinator budget queues
	# (resource scope -> threaded prefetch -> map items -> collisions). The
	# operation below only performs zone arrival (content spawn + player
	# placement); WorldBackground.set_zone_data() skips the rebuild because the
	# environment was already staged-built for the same map.
	r13_stage_started_usec = _world.clock_ports.get_ticks_usec()
	var built_ok: Variant = await _run_world_build_pipeline(target_map_id, transition_id)
	# A cancelled old pipeline also returns false; only its current owner
	# may update the HUD or route a genuine failure through recovery.
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	r13_loading_profile["world_pipeline_ms"] = (
		float(_world.clock_ports.get_ticks_usec() - r13_stage_started_usec) / 1000.0
	)
	if built_ok:
		hud.update_loading_progress(transition_id, 0.58, "地图已建立")
	if not built_ok:
		# P0-3: pre-arrival failure - the coordinator is already FAILED and
		# the old world is untouched. Own the whole FAILED transition through
		# the central recovery function instead of stranding the transition
		# lock, the player combat token and the Loading overlay.
		_fail_map_transition(&"pre_arrival_keep_world")
		return
	r13_stage_started_usec = _world.clock_ports.get_ticks_usec()
	_world_bootstrap_coordinator.begin_actor_collection(Callable(self, "_validate_queued_actor_descriptor"))
	_collecting_staged_actor_plan = true
	_staged_actor_source_index = 0
	_staged_actor_spawn_failure_reason = ""
	operation.call()
	_collecting_staged_actor_plan = false
	_world_bootstrap_coordinator.close_actor_collection()
	_feature_target_bound.sync_world(_world_context.capture_world())
	if not _staged_actor_spawn_failure_reason.is_empty() or not _feature_target_bound.seal():
		_world_bootstrap_coordinator.finish(false, "published_birth_plan_failed")
		_fail_map_transition(&"post_arrival_safe_home")
		return
	if _world.profile.test_mode:
		# Preserve the established deterministic synchronous travel hook while
		# exercising the identical descriptor handler and slice accounting.
		_world_bootstrap_coordinator.process_actor_queue_blocking(
			Callable(self, "_spawn_staged_actor_descriptor"),
			_bootstrap_max_items_per_frame(),
			_bootstrap_slice_budget_ms()
		)
	else:
		await _world_bootstrap_coordinator.process_actor_queue(
			Callable(self, "_spawn_staged_actor_descriptor"),
			_bootstrap_max_items_per_frame(),
			_bootstrap_slice_budget_ms()
		)
	r13_loading_profile["actor_spawn_ms"] = (
		float(_world.clock_ports.get_ticks_usec() - r13_stage_started_usec) / 1000.0
	)
	hud.update_loading_progress(transition_id, 0.75, "人物和怪物已就位")
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	var actor_summary: Variant = _world_bootstrap_coordinator.ready_contract_summary()
	if (
		int(actor_summary.get("failed_actors", 0)) != 0
		or int(actor_summary.get("duplicate_actors", 0)) != 0
		or int(actor_summary.get("planned_actors", 0))
		!= int(actor_summary.get("spawned_actors", 0))
		+ int(actor_summary.get("deferred_actors", 0))
	):
		_world_bootstrap_coordinator.finish(false, "actor_spawn_plan_failed")
		# P0-3: the world was already swapped by operation.call(), so this
		# is a post-arrival failure - recover through the safe home instead
		# of stranding the lock/token/Loading over an incomplete world.
		_fail_map_transition(&"post_arrival_safe_home")
		return
	if not await _await_actual_interactable_Loading_ready(_world_bootstrap_coordinator,_world_bootstrap_coordinator.generation,transition_id): return
	if not _world.profile.test_mode:
		await _world.profile_runtime.next_service()
		if required_owner_service(&"WorldBootstrapResources").display_server_name() != "headless":
			await required_owner_service(&"WorldMapLoadingVisualBarrier").original_frame_post_draw()
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	_world_bootstrap_coordinator.advance(WorldBootstrapCoordinator.Stage.FINALIZE)
	# P0-3b: route_arrival_position never consults environment collision
	# (the collision layer does not exist yet at selection time), so a map
	# whose routed arrival point sits on an environment-blocked cell used
	# to hard-fail the ready contract even though the world itself is
	# complete. With collision built, relocate the player to the nearest
	# unblocked point before validating; the blocked-arrival invariant the
	# contract enforces ("the player never stands inside a wall") is then
	# satisfied in the freshly built world instead of discarding the whole
	# transition.
	_maybe_relocate_blocked_arrival()
	if _check_world_ready_contract():
		_relocate_main_pets_after_map_arrival()
		# FW-COLD (perf-smoothness-r1 C-R1): thread-pumped, deadline-aware
		# prewarm of the ACTUAL bound workset under the loading overlay. The
		# first real cast of every workset skill must be a pure texture-cache
		# hit. Loading-phase work only: damage, spatial index and fire wall
		# systems are untouched.
		r13_stage_started_usec = _world.clock_ports.get_ticks_usec()
		var r13_workset_diag: Dictionary = (
			await _map_source_helper__prewarm_learned_skill_visuals()
		)
		if r13_workset_diag.get("success") != true:
			_world.fault("actual_map_skill_workset_prewarm_failed",r13_workset_diag)
			return
		r13_loading_profile["skill_workset_ms"] = (
			float(_world.clock_ports.get_ticks_usec() - r13_stage_started_usec) / 1000.0
		)
		hud.update_loading_progress(transition_id, 0.76, "技能资源已准备")
		# FW-COLD2 Phase B + PERF-R2 R7/C8: the GPU render warm is bound to
		# the workset - a warrior/taoist without fire wall bound never pays
		# for fire-wall warm-up here. R14-C7 + R14-C-R1 P0-11..16: the warm
		# covers every workset skill's prewarmed facing sequence under a hard
		# ~1s budget and reports a structured result merged into
		# [LOADING-TOTAL].
		r13_stage_started_usec = _world.clock_ports.get_ticks_usec()
		var r13_render_warm_diag: Dictionary = {}
		if not _map_source_helper__active_skill_workset_candidates().is_empty():
			r13_render_warm_diag = await _map_source_helper__warm_fire_wall_render_path()
			if r13_render_warm_diag.get("success") != true:
				_world.fault("actual_map_render_warm_failed",r13_render_warm_diag)
				return
		r13_loading_profile["render_warm_ms"] = (
			float(_world.clock_ports.get_ticks_usec() - r13_stage_started_usec) / 1000.0
		)
		hud.update_loading_progress(transition_id, 0.80, "画面已准备")
		r13_loading_profile["render_warm_diag"] = r13_render_warm_diag
		if not _map_transition_in_progress or _active_map_transition_id != transition_id:
			return
		if _world_bootstrap_in_progress and hud.has_method("prewarm_all_panels"):
			hud.update_loading_progress(transition_id, 0.81, "准备界面")
			r13_stage_started_usec = _world.clock_ports.get_ticks_usec()
			await hud.prewarm_all_panels(_system_menu_panel)
			# Initial Loading has a bounded window for inventory icons as well.
			# The HUD advances one batch per frame and survives map teardown
			# without a suspended icon-prewarm coroutine.
			if not hud._catalog_icon_prewarm_complete:
				hud._start_catalog_icon_prewarm(false)
			var catalog_deadline_msec: Variant = int(
				float(r13_loading_profile.get("covered_usec", 0)) / 1000.0
			) + 9000
			while (
				_map_transition_in_progress
				and _active_map_transition_id == transition_id
				and not hud._catalog_icon_prewarm_complete
				and _world.clock_ports.get_ticks_msec() < catalog_deadline_msec
			):
				await _world.profile_runtime.next_service()
			r13_loading_profile["ui_panels_ms"] = (
				float(_world.clock_ports.get_ticks_usec() - r13_stage_started_usec) / 1000.0
			)
			if not hud.all_panels_are_prewarmed():
				push_warning("Loading ended with incomplete UI panel prewarm; the background retry remains available")
			if not hud._catalog_icon_prewarm_complete:
				push_warning("Loading ended with item icons still prewarming in background")
			if not _map_transition_in_progress or _active_map_transition_id != transition_id:
				return
		# perf(R13-D2): Finalize restarts its own timer HERE - it must never
		# include the render-warm span (stages do not overlap).
		r13_stage_started_usec = _world.clock_ports.get_ticks_usec()
		if is_instance_valid(_town_music_controller):
			_town_music_controller.set_map_context(
				current_map_id,
				_active_safe_zones,
				_canonical_screen_px_to_ground_gu(player.global_position),
				transition_id
			)
		# Release the world first. Reusable UI then warms invisibly in small,
		# frame-separated batches; this keeps Loading and gameplay input responsive
		# while removing the one-time cost from the player's first panel click.
		# perf-smoothness-r1 Phase C: map-transition READY releases the loading
		# window the same way the initial-world READY does.
		required_owner_service(&"WorldBootstrapPipeline").set_loading_window_active(false)
		# perf(R13-D1): finalize = READY release tail (music context + window
		# close) up to the finish_loading_transition call. Total = covered ->
		# finish, the player-visible Loading duration (fade excluded). Bootstrap
		# stage data comes from the coordinator's own non-destructive
		# diagnostic - no second implementation.
		r13_loading_profile["finalize_ms"] = (
			float(_world.clock_ports.get_ticks_usec() - r13_stage_started_usec) / 1000.0
		)
		var r13_bootstrap_diag: Dictionary = (
			_world_bootstrap_coordinator.diagnostic
		)
		var r13_total_usec: int = maxi(
			1,
			_world.clock_ports.get_ticks_usec() - int(r13_loading_profile.get("covered_usec", 0)),
		)
		r13_loading_profile["total_ms"] = float(r13_total_usec) / 1000.0
		if OS.is_debug_build():
			print("[LOADING-TOTAL] ", JSON.stringify({
				"mode": r13_loading_profile.get("mode", ""),
				"transition_id": str(r13_loading_profile.get("transition_id", "")),
				"target_map_id": int(r13_loading_profile.get("target_map_id", -1)),
				"monster_prefetch_ms": float(r13_loading_profile.get("monster_prefetch_ms", 0.0)),
				"world_pipeline_ms": float(r13_loading_profile.get("world_pipeline_ms", 0.0)),
				"actor_spawn_ms": float(r13_loading_profile.get("actor_spawn_ms", 0.0)),
				"skill_workset_ms": float(r13_loading_profile.get("skill_workset_ms", 0.0)),
				"render_warm_ms": float(r13_loading_profile.get("render_warm_ms", 0.0)),
				"ui_panels_ms": float(r13_loading_profile.get("ui_panels_ms", 0.0)),
				"catalog_icon_prewarm_complete": hud._catalog_icon_prewarm_complete,
				"render_warm": {
					"skills_considered": int(
						r13_render_warm_diag.get("skills_considered", 0)
					),
					"skills_warmed": int(
						r13_render_warm_diag.get("skills_warmed", 0)
					),
					"frames_drawn": int(
						r13_render_warm_diag.get("frames_drawn", 0)
					),
					"budget_exhausted": bool(
						r13_render_warm_diag.get("budget_exhausted", false)
					),
					"elapsed_ms": float(
						r13_render_warm_diag.get("elapsed_ms", 0.0)
					),
					"lease_refcount_before": int(
						r13_render_warm_diag.get("lease_refcount_before", 0)
					),
					"lease_refcount_after": int(
						r13_render_warm_diag.get("lease_refcount_after", 0)
					),
				},
				"finalize_ms": float(r13_loading_profile.get("finalize_ms", 0.0)),
				"total_ms": float(r13_loading_profile.get("total_ms", 0.0)),
				"prewarm_deadline_exceeded": bool(
					r13_workset_diag.get("deadline_exceeded", false)
				),
				"prewarm_tail_after_deadline_ms": float(
					r13_workset_diag.get("tail_after_deadline_ms", 0.0)
				),
				"stage_elapsed_ms": r13_bootstrap_diag.get("stage_elapsed_ms", {}),
				"map_slice_count": int(r13_bootstrap_diag.get("map_slice_count", 0)),
				"collision_slice_count": int(r13_bootstrap_diag.get("collision_slice_count", 0)),
				"actor_slice_count": int(r13_bootstrap_diag.get("actor_slice_count", 0)),
				"map_max_slice_ms": float(r13_bootstrap_diag.get("map_max_slice_ms", 0.0)),
				"collision_max_slice_ms": float(r13_bootstrap_diag.get("collision_max_slice_ms", 0.0)),
				"actor_max_slice_ms": float(r13_bootstrap_diag.get("actor_max_slice_ms", 0.0)),
				"actor_max_item_ms": float(r13_bootstrap_diag.get("actor_max_item_ms", 0.0)),
			}))
		if not await _map_loading_port.finish_original_map_loading():
			_world.fault("actual_map_Loading_close_or_resident_pin_transfer_missing",{})
			return
		hud.update_loading_progress(transition_id, 1.0, "进入游戏")
		hud.finish_loading_transition()
		# FRAME-STALL discipline (remote review 2026-09-16): arm the generic
		# long-frame probe only now - loading has ended and the prewarm
		# baseline has printed - so bootstrap spikes cannot consume it.
		_first_combat_probe_armed = true
		_map_source_helper__print_session_diagnostics_header()
		if _world.profile.test_mode and hud.loading_transition_overlay != null:
			# Test-mode fast path hides the fade overlay immediately so tests
			# can assert the bootstrap completed without waiting the fade tween.
			hud.loading_transition_overlay.hide()
			hud.loading_transition_overlay.modulate.a = 1.0
		_active_map_transition_id = ""
		_map_transition_in_progress = false
		# Same-map home/revival/teleport preserves this world and creates no
		# new actor descriptors. Only a previously successful READY may certify
		# that exact retained generation on a later transition.
		_ready_world_map_id = current_map_id
		_ready_world_zone_generation = _zone_generation
		_map_failure_recovery_active = false
		_map_transition_environment_replaced = false
		var bootstrap_profile: Variant = _world_bootstrap_coordinator.finish(
			true, "map_transition_ready"
		)
		if OS.is_debug_build() and _world_bootstrap_in_progress:
			print("[WorldBootstrapProfile] ", JSON.stringify({
				"total_ms": float(bootstrap_profile.get("total_duration_ms", 0.0)),
				"stages_ms": bootstrap_profile.get("stage_elapsed_ms", {}),
				"map_slices": int(bootstrap_profile.get("map_slice_count", 0)),
				"collision_slices": int(bootstrap_profile.get("collision_slice_count", 0)),
				"actor_slices": int(bootstrap_profile.get("actor_slice_count", 0)),
				"planned_actors": int(bootstrap_profile.get("planned_actors", 0)),
				"spawned_actors": int(bootstrap_profile.get("spawned_actors", 0)),
				"deferred_actors": int(bootstrap_profile.get("deferred_actors", 0)),
				"failed_actors": int(bootstrap_profile.get("failed_actors", 0)),
				"duplicate_actors": int(bootstrap_profile.get("duplicate_actors", 0)),
				"actor_total_ms": float(bootstrap_profile.get("actor_total_ms", 0.0)),
				"actor_max_item_ms": float(bootstrap_profile.get("actor_max_item_ms", 0.0)),
				"actor_max_slice_ms": float(bootstrap_profile.get("actor_max_slice_ms", 0.0)),
				"max_slice_ms": float(bootstrap_profile.get("max_slice_ms", 0.0)),
				"hud": hud.panel_prewarm_diagnostic(),
			}))
		# Cancel again immediately before READY releases the lock. This covers a
		# release delivered during the lock as well as a release lost entirely.
		_cancel_map_transition_movement_input()
		player.finish_combat_transition(str(_fields.read_source_field(&"map_combat_transition_token")))
		_release_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)
		if not _world.profile.test_mode and hud.has_method("start_budgeted_panel_prewarm"):
			hud.start_budgeted_panel_prewarm(_system_menu_panel)
	else:
		# P0-3: READY contract failed after the world swap (post-arrival).
		# The player must never act on an incomplete world, but the FAILED
		# transition may not strand its lock/token/Loading either - hand the
		# whole thing to the central recovery owner (safe home).
		_world_bootstrap_coordinator.finish(false, "ready_contract_failed")
		_fail_map_transition(&"post_arrival_safe_home")


## P0-3b: nearest-unblocked-point relocation for a blocked routed arrival.
## Only relocates a living player whose current position is actually
## environment-blocked; every other condition is left to the normal ready
## contract / failure paths. Bounded spiral search keeps the relocation
## deterministic and cheap.

func _run_world_build_pipeline(map_id: int, transition_id: String) -> bool:
	var coordinator: Variant = _world_bootstrap_coordinator
	if coordinator == null or not is_instance_valid(background):
		return false
	var generation: Variant = coordinator.generation
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false

	# 1) COLLECT_REQUIREMENTS also clears the old real environment. Record
	# this ownership boundary before preparation, including failure returns.
	coordinator.advance(WorldBootstrapCoordinator.Stage.COLLECT_REQUIREMENTS)
	var target_map_data: Dictionary = {}
	if map_id >= 0:
		target_map_data = _world.owner_services.GameData.get_map_by_id(map_id)
	if target_map_data.is_empty():
		target_map_data = {"mapId": map_id, "name": "未命名地图"}
	_map_transition_environment_replaced = true
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false
	var prepared: Dictionary = await background.prepare_map_build(
		map_id, coordinator, target_map_data
	)
	if not bool(prepared.get("ok", false)):
		coordinator.finish(false, "prepare_map_build_failed")
		return false
	var arrival_result: Variant = _pipeline_arrival_position(map_id)
	if not bool(arrival_result.get("valid", false)):
		_handle_home_resolution_failure(&"world_pipeline_arrival", arrival_result)
		coordinator.finish(false, "missing_target_arrival")
		return false
	background.set_pending_arrival_position(
		arrival_result.get("position_px", Vector2.ZERO) as Vector2
	)

	# 2) REQUEST_RESOURCES -> 3) WAIT_RESOURCES
	coordinator.advance(WorldBootstrapCoordinator.Stage.REQUEST_RESOURCES)
	await coordinator.request_threaded_prefetch()
	coordinator.advance(WorldBootstrapCoordinator.Stage.WAIT_RESOURCES)
	if _world.profile.test_mode:
		if not await coordinator.poll_threaded_prefetch_blocking():
			coordinator.finish(false, "prefetch_timeout")
			return false
	else:
		while true:
			if not _world_pipeline_owner_current(coordinator, generation, transition_id):
				return false
			if await coordinator.poll_threaded_prefetch():
				break
			await _world.profile_runtime.next_service()
	if coordinator.has_failed_required_resource():
		coordinator.finish(false, "prefetch_failed_required_resource")
		return false
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false

	# WALL-P1R C4: the descriptor queue is handed over only after
	# WAIT_RESOURCES (and the required-resource gate) completed, so
	# submit_staged_build's optimized/legacy mode selection can verify the
	# prefetched derived textures. The resource manifest was fully built
	# during prepare_map_build; nothing needs the queue before this point.
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false
	if not await background.submit_staged_build():
		coordinator.finish(false,"actual_Loading_publication_or_visual_selection_failed")
		return false

	# 4) BUILD_MAP: one atomic map unit per queue task, frame-budgeted.
	coordinator.advance(WorldBootstrapCoordinator.Stage.BUILD_MAP)
	var max_items: Variant = _bootstrap_max_items_per_frame()
	var budget_ms: Variant = _bootstrap_slice_budget_ms()
	coordinator.defer_between_slices = not _world.profile.test_mode
	await coordinator.process_map_queue(
		Callable(background, "build_one_map_item"), max_items, budget_ms
	)
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false
	if coordinator.has_unexpected_sync_load():
		coordinator.finish(false, "unexpected_sync_load_during_build_map")
		return false
	if coordinator.planned_map_item_count != coordinator.built_map_item_count:
		coordinator.finish(false, "map_item_count_mismatch")
		return false

	# 5) BUILD_COLLISION: one atomic collision unit per queue task.
	coordinator.advance(WorldBootstrapCoordinator.Stage.BUILD_COLLISION)
	await coordinator.process_collision_queue(
		Callable(background, "build_one_collision"), max_items, budget_ms
	)
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false
	if coordinator.has_unexpected_sync_load():
		coordinator.finish(false, "unexpected_sync_load_during_build_collision")
		return false
	if coordinator.failed_collision_count > 0:
		coordinator.finish(false, "collision_build_failed")
		return false
	if coordinator.planned_collision_count != coordinator.built_collision_count:
		coordinator.finish(false, "collision_count_mismatch")
		return false

	# 6) SPAWN_ACTORS: the arrival operation records production actor
	# descriptors after this pipeline returns. GameRoot then drains that exact
	# plan with the same frame budget before FINALIZE/READY.
	coordinator.advance(WorldBootstrapCoordinator.Stage.SPAWN_ACTORS)
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false
	if not await background.finish_map_build():
		coordinator.finish(false,"actual_visual_finish_failed")
		return false
	return true



func _world_pipeline_owner_current(
	coordinator: RefCounted,
	generation: int,
	transition_id: String
) -> bool:
	## Every async resume and environment mutation belongs to both the
	## transition and the coordinator generation.  Generation alone is not
	## sufficient: timeout/recovery can retire it before a new generation starts.
	return (
		is_instance_valid(coordinator)
		and coordinator.is_generation_current(generation)
		and _map_transition_in_progress
		and _active_map_transition_id == transition_id
	)



func _bootstrap_max_items_per_frame() -> int:
	return int(_source_publication.original_map_loading_settings.max_items_per_frame)



func _bootstrap_slice_budget_ms() -> float:
	return float(_source_publication.original_map_loading_settings.slice_budget_ms)



func _pipeline_arrival_position(map_id: int) -> Dictionary:
	if map_id == BICH_RUNTIME_MAP_ID:
		return _resolve_bich_home()
	return {
		"valid": true,
		"position_px": route_arrival_position(map_id, current_map_id),
		"source": "route_arrival",
		"reason": "",
	}



func _maybe_relocate_blocked_arrival() -> void:
	if player == null or not is_instance_valid(player):
		return
	if not is_instance_valid(background):
		return
	if bool(player._dead) or int(player.current_hp) <= 0:
		return
	if not background.is_environment_point_blocked(player.global_position):
		return
	var origin: Variant = player.global_position
	var best: Variant = Vector2.INF
	var radius: Variant = 24.0
	while radius <= 320.0 and best == Vector2.INF:
		var steps: Variant = maxi(8, int(radius / 4.0))
		for i: int in steps:
			var angle: Variant = TAU * float(i) / float(steps)
			var candidate: Variant = origin + Vector2(cos(angle), sin(angle)) * radius
			if not background.is_environment_point_blocked(candidate):
				best = candidate
				break
		radius += 24.0
	if best == Vector2.INF:
		return
	_set_player_world_position(best)
	player.velocity = Vector2.ZERO
	if is_instance_valid(background):
		background.set_focus_position(player.global_position)
	print("[MapTransition] blocked arrival point; relocated player to nearest unblocked point (%.0f, %.0f)" % [best.x, best.y])


## P0-3: single owner for a FAILED map transition. Every FAILED path funnels
## here; no implicit combat token, map-transition lock or Loading overlay may
## survive the call. Callers must have already finished the coordinator with
## the concrete failure reason (this function reads it for the user message).
## pre_arrival_keep_world: the old world is still current - keep it playable
## and surface a retryable error.
## post_arrival_safe_home: the world was swapped but is not contract-ready -
## relocate the player to the resolved safe home so an incomplete map is
## never handed to gameplay input.

func _check_world_ready_contract() -> bool:
	if _world.is_faulted() or _world.interactables == null or not _world.interactables.original_loading_visuals_ready(): return false
	var coordinator: Variant = _world_bootstrap_coordinator
	if coordinator == null or not is_instance_valid(background):
		return false
	var summary: Variant = coordinator.ready_contract_summary()
	var birth_plan: Variant = feature_world_capacity_bound()
	if not bool(birth_plan.get("sealed", false)) or not bool(birth_plan.get("proved", false)):
		return false
	# FREEZE-P0.2: gameplay is only reachable in a projection-ready world. The
	# formal map profile gate keeps legacy Vector2 wrappers out of broken maps.
	var ready_profile: Variant = _resolve_projection_profile_for_map(current_map_id)
	if not bool(ready_profile.get("success", false)):
		missing_projection_rejection_count += 1
		projection_rejection_reason = str(ready_profile.get("reason", ""))
		return false

	if not coordinator.is_generation_current(int(summary.get("generation", -1))):
		return false
	if int(summary.get("map_id", -1)) != current_map_id:
		return false
	if background.environment_node_count() <= 0 and background.editor_runtime_chunk_texture_count() <= 0:
		return false
	if int(summary.get("planned_map_item_count", 0)) != int(summary.get("built_map_item_count", 0)):
		return false
	if int(summary.get("planned_collision_count", 0)) != int(summary.get("built_collision_count", 0)):
		return false
	if int(summary.get("failed_collision_count", 0)) != 0:
		return false
	if (
		int(summary.get("planned_actors", 0))
		!= int(summary.get("spawned_actors", 0))
		+ int(summary.get("deferred_actors", 0))
	):
		return false
	if int(summary.get("failed_actors", 0)) != 0:
		return false
	if int(summary.get("duplicate_actors", 0)) != 0:
		return false
	if int(summary.get("unexpected_sync_load_count", 0)) != 0:
		return false
	if not is_instance_valid(player):
		return false
	if background.is_environment_point_blocked(player.global_position):
		return false
	if not is_instance_valid(_world_camera):
		return false
	if (
		is_instance_valid(hud)
		and (int(hud._last_hp) != int(player.current_hp)
			or int(hud._last_max_hp) != int(player.max_hp))
	):
		return false
	# Necessary gameplay actors / door points must be present when the map
	# content declares them.
	var content: Dictionary = {}
	if _world.environment_factory.runtime_maps.has_runtime_map(current_map_id):
		content = _world.environment_factory.runtime_maps.game_content_for_map(current_map_id)
	if content.is_empty() and _world.environment_factory.runtime_maps.has_map(current_map_id):
		content = _world.environment_factory.catalog.get_map_content(current_map_id)
	var declares_content: bool = (
		not (content.get("spawns", []) as Array).is_empty()
		or not (content.get("bosses", []) as Array).is_empty()
		or not (content.get("npcs", []) as Array).is_empty()
		or not (content.get("portals", []) as Array).is_empty()
	)
	# The generation's actor plan accounts for live AND persisted respawn
	# slots above. Boss-only maps are correctly empty until their deadline;
	# scene-wide groups also include queued old-map nodes, making this gate
	# intermittently reject the same valid save depending on load timing.
	var retained_ready_world: Variant = (
		_ready_world_map_id == current_map_id
		and _ready_world_zone_generation == _zone_generation
	)
	if declares_content and int(summary.get("planned_actors", 0)) <= 0 and not retained_ready_world:
		return false
	return true



func route_arrival_position(destination_map_id: int, source_map_id: int) -> Vector2:
	if _world.environment_factory.runtime_maps.has_runtime_map(destination_map_id):
		return _world.environment_factory.runtime_maps.portal_screen_position_px(
			destination_map_id, "", source_map_id
		)
	var content: Variant = _world.environment_factory.catalog.get_map_content(destination_map_id)
	for portal: Dictionary in content.get("portals", []):
		if int(portal.get("target_map_id", -1)) == source_map_id:
			var portal_screen_px: Vector2 = portal.get("position", Vector2.ZERO)
			var interior_target_screen_px: Variant = (
				_bich_home_position_px_if_valid()
				if destination_map_id == BICH_RUNTIME_MAP_ID
				else Vector2.ZERO
			)
			var portal_ground_gu: Variant = (
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
					portal_screen_px
				)
			)
			var interior_target_ground_gu: Variant = (
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
					interior_target_screen_px
				)
			)
			var inward_direction_ground_gu: Variant = (
				GroundUnitSpaceScript.normalized_ground_direction(
					portal_ground_gu,
					interior_target_ground_gu
				)
			)
			var arrival_offset_gu: Variant = (
				CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
					140.0
				)
			)
			return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				portal_ground_gu + inward_direction_ground_gu * arrival_offset_gu
			)
	return (
		_bich_home_position_px_if_valid()
		if destination_map_id == BICH_RUNTIME_MAP_ID
		else Vector2.ZERO
	)



func _load_zone(zone_name: String, initial: bool, map_data: Dictionary) -> void:
	# FREEZE-P0.2R: formal gameplay only loads implemented (runtime-built)
	# maps. Reference/planned maps (e.g. 248/338/401/478) must never enter a
	# half-broken world through the formal loader.
	var target_map_id: Variant = (
		int(map_data.get("mapId", -1))
		if not map_data.is_empty()
		else _world.owner_services.GameData.service_runtime_map_id(0)
	)
	if (
		target_map_id >= 0
		and not _world.environment_factory.runtime_maps.is_formal_playable(target_map_id)
		and not reference_audit_mode
	):
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpaceScript.REASON_MAP_NOT_IMPLEMENTED
		)
		return
	if zone_name == current_zone and not initial:
		if map_data.is_empty() or int(map_data.get("mapId", -1)) == current_map_id:
			return
	if not _world.has_method("commit_original_source_map_arrival_context") or not _world.original_source_session().has_method("can_commit_original_source_map_arrival_context"):
		_world.fault("MISSING_actual_dynamic_Source_map_context",{})
		return
	_zone_generation += 1
	_cancel_respawn_wakeups()
	_cancel_pending_enemy_deaths_for_generation_change()
	if _loot_pickup_runtime_manager != null:
		_loot_pickup_runtime_manager.clear_map(current_map_id)
	_active_safe_zones.clear()
	_active_enemy_cache.clear()
	_active_boss_cache.clear()
	_player_combat_enemy_ids.clear()
	_safe_zone_enforcement_remaining = 0.0
	_cancel_all_combat_targets()
	if _combat_spatial_index != null and current_map_id >= 0:
		# Actors are queued for deletion below; clear the old map partition now so
		# a transition cannot expose stale candidates before their exit callbacks.
		_combat_spatial_index.clear_map(current_map_id)
	# Preserve the live summon before zone_content is queued for deletion. The
	# destination map restores the same gameplay state beside the owner.
	_world.profile.apply_taoist_main_pet_runtime_states(_capture_taoist_main_pet_runtime_states())
	for node: Object in _world.skill_actors.actors_in_group(&"zone_content"):
		if is_instance_valid(node):
			_world.defer_original_actor_free(node)
	if _ground_effect_manager != null:
		# Every zone_content node (including ground effect visuals) is freed
		# above; their manager registrations must not survive into the next map.
		_ground_effect_manager.clear_all()
	# FireWall field controllers are not zone_content members; free them
	# explicitly so no field (or registry entry) crosses a map transition.
	_clear_fire_wall_field_registry()
	current_zone = zone_name
	current_map_data = map_data.duplicate(true)
	_passive_wake_candidates.clear()
	_passive_wake_cursor = 0
	_passive_wake_query_pending = true
	var retained_player_emitter: Dictionary = {}
	if is_instance_valid(player):
		retained_player_emitter = _passive_wake_emitters.get(_world.skill_actors.runtime_actor_id(player), {})
	_passive_wake_emitters.clear()
	if not retained_player_emitter.is_empty():
		retained_player_emitter["dirty"] = false
		retained_player_emitter["map_id"] = current_map_id
		retained_player_emitter["generation"] = _zone_generation
		_passive_wake_emitters[_world.skill_actors.runtime_actor_id(player)] = retained_player_emitter
	_passive_wake_emitter_queue.clear()
	_passive_wake_active_emitter_id = 0
	_passive_wake_dirty = false
	_passive_wake_max_extent_gu = 0.0
	_passive_wake_extent_map_id = -1
	_passive_wake_extent_generation = -1
	current_map_id = int(map_data.get("mapId", -1)) if not map_data.is_empty() else -1
	if map_data.is_empty():
		# Q1-B: legacy zones without a database map entry (for example the
		# outskirts playground) belong to the client 0.map home realm (runtime
		# map 4). Snapshot consumers receive a formal runtime map id instead of
		# -1, so STRICT_V2 absolute snapshots stay valid.
		current_map_id = _world.owner_services.GameData.service_runtime_map_id(0)
	if not _world.commit_original_source_map_arrival_context(self,current_map_id,_zone_generation):
		_world.fault("actual_dynamic_Source_map_context_commit_failed",{})
		return
	if is_instance_valid(player):
		_register_passive_wake_emitter(player)
	_mark_passive_monster_wakeup_dirty()
	if _loot_pickup_runtime_manager != null:
		_loot_pickup_runtime_manager.configure_map(
			current_map_id,
			_zone_generation,
			Callable(self, "_canonical_screen_px_to_ground_gu"),
			Callable(self, "_canonical_ground_gu_to_screen_px"),
		)
	_begin_safe_zone_context(current_map_id)
	_monster_terrain_navigation_context = (
		_world.environment_factory.terrain_navigation.build_context(
			current_map_id,
			_world.environment_factory.runtime_maps.load_map(current_map_id),
			MonsterTerrainNavigationPolicyScript.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		)
	)
	background.set_zone_data(zone_name, current_map_data)
	hud.set_zone_name(
		"比奇营地 · 安全区"
		if current_map_id == BICH_RUNTIME_MAP_ID
		else zone_name
	)
	if zone_name == "比奇城":
		_set_player_world_position(Vector2(0, 80))
		_spawn_city_content()
	elif zone_name == "比奇郊外":
		_set_player_world_position(Vector2.ZERO)
		_spawn_outskirts_content()
	else:
		if current_map_id == BICH_RUNTIME_MAP_ID:
			var home: Variant = _resolve_bich_home()
			if bool(home.get("valid", false)):
				_set_player_world_position(home.get(
					"position_px", Vector2.ZERO
				) as Vector2)
			else:
				_handle_home_resolution_failure(&"load_zone_arrival", home)
		else:
			_set_player_world_position(Vector2.ZERO)
		_spawn_database_zone_content(current_map_data)
	_refresh_player_safe_zone_cache(true)
	player.velocity = Vector2.ZERO
	background.set_focus_position(player.global_position)
	_restore_persisted_taoist_main_pet_if_needed()
	_on_player_stats_changed(player.current_hp, player.max_hp)
	hud.show_message("进入%s" % zone_name, 1.5)



func _spawn_database_zone_content(map_data: Dictionary) -> void:
	if map_data.is_empty():
		_spawn_outskirts_content()
		return
	var map_id: Variant = int(map_data.get("mapId", -1))
	# FREEZE-P0.2R: never seed an unbuilt map with WorldContent/reference
	# placeholder spawns in formal gameplay; the authored data is preserved for
	# migration/audit/reference use only.
	if (
		not _world.environment_factory.runtime_maps.is_formal_playable(map_id)
		and not reference_audit_mode
	):
		return
	if _world.environment_factory.runtime_maps.has_runtime_map(map_id):
		var editor_content: Variant = (
			_world.environment_factory.runtime_maps.game_content_for_map(map_id)
		)
		if not editor_content.is_empty():
			_spawn_editor_runtime_content(editor_content)
			return
	if _world.environment_factory.runtime_maps.has_map(map_id):
		_spawn_authored_map_content(_world.environment_factory.catalog.get_map_content(map_id))
		return
	var region: Variant = str(map_data.get("region", ""))
	var recommended_level: Variant = 18
	if "比奇" in region:
		recommended_level = 10
	elif "毒蛇" in region:
		recommended_level = 16
	elif "沃玛" in region:
		recommended_level = 22
	elif "盟重" in region:
		recommended_level = 28
	elif "封魔" in region:
		recommended_level = 32
	elif "白日门" in region:
		recommended_level = 35
	elif "苍月" in region:
		recommended_level = 38
	# A formal map without an editor/authored spawn plan remains empty.  The
	# legacy region/level/base-name guesses could select the wrong variant and
	# are no longer a production monster source.
	_map_source_helper__spawn_portal(Vector2(0, 390), "比奇城", "返回比奇城（临时门点）")



func _spawn_editor_runtime_content(content: Dictionary) -> void:
	_compile_active_safe_zones(content.get("safe_areas", []))
	var editor_spawn_index: Variant = -1
	for spawn: Dictionary in content.get("spawns", []):
		editor_spawn_index += 1
		var monster_id: Variant = _world.owner_services.GameData.canonical_monster_id(
			spawn.get("monster_id", null)
		)
		var monster: Variant = _world.owner_services.GameData.get_monster_by_id(monster_id)
		if not monster.is_empty():
			var count:=mini(int(spawn.get("count",1)),int(spawn.get("max_alive",spawn.get("count",1))))
			var center_screen_px: Vector2 = spawn.get("screen_position_px", Vector2.ZERO)
			var radius_gu: Variant = maxf(0.0, float(spawn.get("radius_gu", 0.0)))
			for copy_index in maxi(1,count):
				var offset_ground_gu: Variant = Vector2.ZERO
				if count > 1 and radius_gu > 0.0:
					var radial_fraction: Variant = sqrt(
						float(copy_index + 1) / float(count)
					)
					offset_ground_gu = (
						Vector2.from_angle(float(copy_index) * TAU / float(count))
						* radius_gu
						* radial_fraction
					)
				var offset_screen_px: Variant = (
					GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
						offset_ground_gu
					)
				)
				var raw_group: Dictionary = spawn.get("spawn_group", {})
				var group_id: Variant = str(spawn.get(
					"spawnGroupId",
					raw_group.get("id", "editor:%d:%d" % [current_map_id, editor_spawn_index])
				))
				_spawn_enemy(
					monster,
					center_screen_px + offset_screen_px,
					false,
					float(spawn.get("respawn_seconds", 60)),
					{
						"spawn_group_id": group_id,
						"spawn_slot_id": "%s:%d" % [group_id, copy_index],
						"respawn_policy_id": str(spawn.get("respawn_policy_id", "")),
						"respawn_evidence": spawn.get("respawnEvidence", {"status": "map_editor_authored"}),
						"respawn_random_seconds": float(spawn.get("respawn_random_seconds", 0.0)),
					}
				)
	var editor_boss_index: Variant = -1
	for spawn: Dictionary in content.get("bosses", []):
		editor_boss_index += 1
		var boss_id: Variant = _world.owner_services.GameData.canonical_monster_id(
			spawn.get("monster_id", null)
		)
		var boss: Variant = _world.owner_services.GameData.get_monster_by_id(boss_id)
		if boss.is_empty():
			continue
		var raw_group: Dictionary = spawn.get("spawn_group", {})
		var group_id: Variant = str(raw_group.get(
			"spawn_group_id",
			"editor:%d:boss:%d" % [
				current_map_id,
				editor_boss_index,
			]
		))
		_spawn_enemy(
			boss,
			spawn.get("screen_position_px", Vector2.ZERO),
			true,
			float(spawn.get("respawn_seconds", DEFAULT_BOSS_RESPAWN_SECONDS)),
			{
				"spawn_group_id": group_id,
				"spawn_slot_id": "%s:0" % group_id,
				"respawn_policy_id": str(spawn.get("respawn_policy_id", "")),
				"respawn_evidence": {
					"status": "map_editor_authored",
				},
			}
		)
	for npc_data: Dictionary in content.get("npcs", []):
		var role: Variant = str(npc_data.get("kind", "dialogue"))
		var name: Variant = str(npc_data.get("name", "NPC"))
		var stock_key: Variant = str(npc_data.get("stock", ""))
		var stock: Array = []
		match stock_key:
			"general": stock = _general_shop_stock()
			"starter_gear": stock = _starter_gear_stock()
			"medicine": stock = _medicine_shop_stock()
			"books": stock = _build_skill_book_stock(_world.profile.profession_id)
		_map_source_helper__spawn_npc(npc_data.get("screen_position_px", Vector2.ZERO), name, role, stock, stock_key, int(npc_data.get("appearance", -1)), content.get("map_center_screen_position_px", _current_map_center_screen_position_px()))
	for portal: Dictionary in content.get("portals", []):
		_map_source_helper__spawn_map_portal(
			portal.get("screen_position_px", Vector2.ZERO),
			int(portal.get("target_map_id", -1)),
			str(portal.get("label", "地图入口")),
			portal
		)



func _spawn_authored_map_content(content: Dictionary) -> void:
	if content.has("safe_areas"):
		_compile_active_safe_zones(content.get("safe_areas", []))
	var camp_layout: Variant = (
		_bich_camp_layout if current_map_id == BICH_RUNTIME_MAP_ID else {}
	)
	var camp_home: Variant = Vector2.ZERO
	if current_map_id == BICH_RUNTIME_MAP_ID:
		var home: Variant = _resolve_bich_home()
		if not bool(home.get("valid", false)):
			_handle_home_resolution_failure(&"camp_spawn", home)
			return
		camp_home = home.get("position_px", Vector2.ZERO) as Vector2
	var authored_spawn_index: Variant = -1
	for spawn: Variant in content.get("spawns", []):
		authored_spawn_index += 1
		if not spawn is Dictionary:
			continue
		var monster_id: Variant = _world.owner_services.GameData.canonical_monster_id(
			spawn.get("monster_id", null)
		)
		var monster: Variant = _world.owner_services.GameData.get_monster_by_id(monster_id)
		if not monster.is_empty():
			var spawn_position: Vector2 = spawn.get("position", Vector2.ZERO)
			var group_id: Variant = str(spawn.get(
				"spawnGroupId",
				"map:%d:spawn:%d" % [current_map_id, authored_spawn_index]
			))
			if current_map_id == BICH_RUNTIME_MAP_ID:
				var copies: Variant = int(camp_layout.get("fieldSpawnCopies", 4))
				var radii: Array = camp_layout.get("fieldSpawnRadii", [940, 1180, 1460, 1740])
				for copy_index in range(copies):
					var angle: Variant = float(authored_spawn_index * copies + copy_index) * TAU / float(maxi(1, content.get("spawns", []).size() * copies))
					var radius: Variant = float(radii[copy_index % radii.size()])
					_spawn_enemy(
						monster,
						camp_home + Vector2.RIGHT.rotated(angle) * radius,
						false,
						float(spawn.get("respawn_seconds", DEFAULT_NORMAL_RESPAWN_SECONDS)),
						{
							"spawn_group_id": group_id,
							"spawn_slot_id": "%s:%d" % [group_id, copy_index],
							"respawn_policy_id": str(spawn.get("respawn_policy_id", "")),
							"respawn_evidence": spawn.get("respawnEvidence", {}),
							"respawn_random_seconds": float(spawn.get("respawn_random_seconds", 0.0)),
						}
					)
				continue
			_spawn_enemy(
				monster,
				spawn_position,
				false,
				float(spawn.get("respawn_seconds", DEFAULT_NORMAL_RESPAWN_SECONDS)),
				{
					"spawn_group_id": group_id,
					"spawn_slot_id": "%s:0" % group_id,
					"respawn_policy_id": str(spawn.get("respawn_policy_id", "")),
					"respawn_evidence": spawn.get("respawnEvidence", {}),
					"respawn_random_seconds": float(spawn.get("respawn_random_seconds", 0.0)),
				}
			)
	var authored_boss_index: Variant = -1
	for boss_spawn: Variant in content.get("bosses", []):
		authored_boss_index += 1
		if not boss_spawn is Dictionary:
			continue
		var boss_id: Variant = _world.owner_services.GameData.canonical_monster_id(
			boss_spawn.get("monster_id", null)
		)
		var boss: Variant = _world.owner_services.GameData.get_monster_by_id(boss_id)
		if not boss.is_empty():
			var boss_group_id: Variant = str(boss_spawn.get(
				"spawnGroupId",
				"map:%d:boss:%d" % [current_map_id, authored_boss_index]
			))
			_spawn_enemy(
				boss,
				boss_spawn.get("position", Vector2(560, 230)),
				true,
				float(boss_spawn.get("respawn_seconds", DEFAULT_BOSS_RESPAWN_SECONDS)),
				{
					"spawn_group_id": boss_group_id,
					"spawn_slot_id": "%s:0" % boss_group_id,
					"respawn_policy_id": str(boss_spawn.get("respawn_policy_id", "")),
					"respawn_evidence": boss_spawn.get("respawnEvidence", {}),
					"respawn_random_seconds": float(boss_spawn.get("respawn_random_seconds", 0.0)),
				}
			)
	for npc_data: Variant in content.get("npcs", []):
		if not npc_data is Dictionary:
			continue
		var stock: Array = []
		match str(npc_data.get("stock", "")):
			"general": stock = _general_shop_stock()
			"starter_gear": stock = _starter_gear_stock()
			"mid_gear": stock = _mid_gear_stock()
			"medicine": stock = _medicine_shop_stock()
			"books": stock = _build_skill_book_stock(_world.profile.profession_id)
		var npc_name: Variant = str(npc_data.get("name", "NPC"))
		var npc_position: Vector2 = npc_data.get("position", Vector2.ZERO)
		if (
			current_map_id == BICH_RUNTIME_MAP_ID
			and camp_layout.get("npcSlots", {}).has(npc_name)
		):
			npc_position = camp_home + GothicBichCampBuilderScript._vector(camp_layout.npcSlots[npc_name])
		_map_source_helper__spawn_npc(npc_position, npc_name, str(npc_data.get("kind", "shop")), stock, str(npc_data.get("stock", "")), int(npc_data.get("appearance", -1)))
	if current_map_id == BICH_RUNTIME_MAP_ID:
		_map_source_helper__spawn_npc(camp_home + GothicBichCampBuilderScript._vector(camp_layout.npcSlots.get("仓库管理员", [-520, 185])), "仓库管理员", "warehouse")
	for portal: Variant in content.get("portals", []):
		if portal is Dictionary:
			_map_source_helper__spawn_map_portal(portal.get("position", Vector2.ZERO), int(portal.get("target_map_id", -1)), str(portal.get("label", "地图入口")))



func _monster_ids_for_map(map_id: int) -> Array[int]:
	var content: Dictionary = {}
	if _world.environment_factory.runtime_maps.has_runtime_map(map_id):
		content = _world.environment_factory.runtime_maps.game_content_for_map(map_id)
	if content.is_empty() and _world.environment_factory.runtime_maps.has_map(map_id):
		content = _world.environment_factory.catalog.get_map_content(map_id)
	var result: Array[int] = []
	var seen: Variant = {}
	for group_name: String in ["spawns", "bosses"]:
		for raw_entry: Variant in content.get(group_name, []):
			if not raw_entry is Dictionary:
				continue
			var entry: Dictionary = raw_entry
			var raw_id: Variant = entry.get("monster_id", null)
			var monster_id: Variant = _world.owner_services.GameData.canonical_monster_id(raw_id)
			if (
				monster_id <= 0
				or _world.owner_services.GameData.get_canonical_monster_entry(
					monster_id, "runtime"
				).is_empty()
				or seen.has(monster_id)
			):
				continue
			seen[monster_id] = true
			result.append(monster_id)
	return result



func _runtime_named_map_data(map_data: Dictionary) -> Dictionary:
	var resolved: Variant = map_data.duplicate(true)
	var map_id: Variant = int(resolved.get("mapId", -1))
	if _world.environment_factory.runtime_maps.has_runtime_map(map_id):
		var content: Variant = _world.environment_factory.runtime_maps.game_content_for_map(map_id)
		if not content.is_empty():
			resolved["name"] = str(content.get("name", resolved.get("name", "未命名地图")))
	return resolved



func _begin_safe_zone_context(runtime_map_id: int) -> void:
	_safe_zone_revision += 1
	_safe_zone_context = {
		"contract_id": WorldSpatialRulesScript.SAFE_ZONE_CONTEXT_CONTRACT_ID,
		"map_id": runtime_map_id,
		"revision": _safe_zone_revision,
		"generation": _zone_generation,
		"valid": true,
		"failure_reason": "",
		"zones": [],
		"aabb_ground_gu": Rect2(),
	}
	_active_safe_zones = _safe_zone_context["zones"]
	_safe_zone_candidate_scratch.clear()
	_safe_zone_query_scratch.clear()
	_safe_zone_candidate_stamp_serial = 0
	_invalidate_player_safe_zone_cache()



func _compile_active_safe_zones(raw_zones: Variant) -> void:
	_safe_zone_context = WorldSpatialRulesScript.compile_safe_zone_context(
		current_map_id,
		_safe_zone_revision,
		_zone_generation,
		raw_zones,
	)
	_active_safe_zones = _safe_zone_context.get("zones", []) as Array
	if not bool(_safe_zone_context.get("valid", false)):
		# Invalid formal authored geometry is a map-data error. Keep the active
		# set empty and let all safe-zone consumers fail closed; never reinterpret
		# a malformed polygon as a circle or infer a shape from screen bounds.
		_active_safe_zones.clear()
		_safe_zone_context["zones"] = _active_safe_zones
	_invalidate_player_safe_zone_cache()



func _invalidate_player_safe_zone_cache() -> void:
	_world_skill_runtime()._invalidate_player_safe_zone_cache()



func _bich_home_position_px_if_valid() -> Vector2:
	var resolved: Variant = _resolve_bich_home()
	if not bool(resolved.get("valid", false)):
		return Vector2.INF
	return resolved.get("position_px", Vector2.ZERO) as Vector2



func _current_map_center_screen_position_px() -> Vector2:
	var source_size: Variant = Vector2i.ZERO
	if current_map_data.has("source_size"):
		source_size = Vector2i(current_map_data.get("source_size", Vector2i.ZERO))
	if source_size == Vector2i.ZERO and _world.environment_factory.runtime_maps.has_map(current_map_id):
		source_size = Vector2i(_world.environment_factory.catalog.get_map_content(current_map_id).get("source_size", Vector2i.ZERO))
	if source_size != Vector2i.ZERO:
		return MapCoordinateMapperScript.source_to_world((Vector2(source_size) - Vector2.ONE) * 0.5, source_size)
	return Vector2.ZERO



func _general_shop_stock() -> Array:
	return _world.owner_services.GameData.merchant_stock("general")



func _starter_gear_stock() -> Array:
	return _world.owner_services.GameData.merchant_stock("starter_gear")



func _medicine_shop_stock() -> Array:
	return _world.owner_services.GameData.merchant_stock("medicine")



func _mid_gear_stock() -> Array:
	# Fail closed until the stable stock key is mapped to an exact primary NPC
	# [Trade] script.  Guessed/project-authored inventories are forbidden.
	return _world.owner_services.GameData.merchant_stock("mid_gear")



func _build_skill_book_stock(profession: String) -> Array:
	var allowed: Variant = {}
	for skill: Variant in _world.owner_services.GameData.get_profession_skills(profession):
		if not skill is Dictionary:
			continue
		allowed[str(skill.get("skillName", ""))] = true
	var stock: Array = []
	for raw_entry: Variant in _world.owner_services.GameData.merchant_stock("books"):
		if raw_entry is Dictionary and allowed.has(str(raw_entry.get("name", ""))):
			stock.append(raw_entry)
	return stock



func _spawn_city_content() -> void:
	var general_stock: Variant = _general_shop_stock()
	var book_stock: Variant = _build_skill_book_stock(_world.profile.profession_id)
	_map_source_helper__spawn_npc(Vector2(-250, -60), "杂货商", "shop", general_stock, "general")
	_map_source_helper__spawn_npc(Vector2(250, -60), "书店老板", "shop", book_stock, "books")
	_map_source_helper__spawn_npc(Vector2(0, -255), "武馆教头", "trainer")
	_map_source_helper__spawn_npc(Vector2(-420, 210), "比奇老兵", "quest")
	_map_source_helper__spawn_portal(Vector2(0, 390), "比奇郊外", "前往比奇郊外")



func _spawn_outskirts_content() -> void:
	var spawn_plan: Variant = [
		[21, Vector2(-320, 170)], [24, Vector2(310, 125)],
		[26, Vector2(430, -35)], [28, Vector2(-470, -170)],
		[30, Vector2(520, 160)],
		[56, Vector2(670, 280)],
	]
	for spawn_index in range(spawn_plan.size()):
		var entry: Array = spawn_plan[spawn_index]
		var monster: Variant = _world.owner_services.GameData.get_monster_by_id(int(entry[0]))
		if not monster.is_empty():
			var group_id: Variant = "outskirts:%d:spawn:%d" % [current_map_id, spawn_index]
			var policy: Variant = MonsterRespawnPolicyScript.resolve(
				"", str(monster.get("classification", "")),
				DEFAULT_NORMAL_RESPAWN_SECONDS,
				str(monster.get("spawn_classification", ""))
			)
			_spawn_enemy(
				monster,
				entry[1],
				false,
				DEFAULT_NORMAL_RESPAWN_SECONDS,
				{
					"spawn_group_id": group_id,
					"spawn_slot_id": "%s:0" % group_id,
					"respawn_policy_id": str(policy.get("policy_id", "")),
				}
			)
	_map_source_helper__spawn_portal(Vector2(560, -305), "比奇城", "进入比奇城")



func _clear_fire_wall_field_registry() -> void:
	_world_skill_runtime()._clear_fire_wall_field_registry()



func _restore_persisted_taoist_main_pet_if_needed(allow_deferred_arrival: bool = false) -> bool:
	return _world_skill_runtime()._restore_persisted_taoist_main_pet_if_needed(allow_deferred_arrival)



func _on_map_teleport_availability_requested(map_ids: Array) -> void:
	if not is_instance_valid(hud):
		return
	hud.set_map_teleport_availability(
		MapTeleportRuntimePolicyScript.rules_for_maps(
			map_ids,
			Callable(self, "_map_teleport_item_count_by_id"),
		)
	)



func _on_map_teleport_requested(request: Dictionary) -> void:
	if not gameplay_input_is_enabled() or _map_transition_in_progress:
		return
	var selected_map_id: Variant = int(request.get("selected_map_id", -1))
	var rule: Variant = MapTeleportRuntimePolicyScript.rule_for_map(
		selected_map_id,
		Callable(self, "_map_teleport_item_count_by_id"),
	)
	if not MapTeleportRuntimePolicyScript.request_matches_rule(request, rule):
		if is_instance_valid(hud):
			hud.set_map_teleport_availability({selected_map_id: rule})
			hud.show_error_message(
				UIErrorFeedbackScript.user_message(
					str(rule.get("reason", "传送条件已经失效"))
				)
			)
		return
	var destination_map_id: Variant = int(rule.get("destination_map_id", -1))
	var travel_profile: Variant = _resolve_projection_profile_for_map(destination_map_id)
	if not bool(travel_profile.get("success", false)):
		missing_projection_rejection_count += 1
		projection_rejection_reason = str(travel_profile.get("reason", ""))
		hud.show_error_message("目标地图投影暂不可用（%d）" % destination_map_id)
		return
	var map_data: Variant = _world.owner_services.GameData.get_map_by_id(destination_map_id)
	if map_data.is_empty():
		hud.show_error_message("地图数据不存在：%d" % destination_map_id)
		return
	var operation: Variant = Callable(self, "_teleport_to_map_immediate").bind(
		destination_map_id,
		str(rule.get("arrival_anchor_id", "")),
	)
	if not _begin_map_transition(operation, destination_map_id):
		hud.show_error_message("当前无法开始传送")



func _teleport_to_map_immediate(map_id: int, arrival_anchor_id: String) -> bool:
	var arrival: Variant = MapTeleportRuntimePolicyScript.resolve_arrival(
		map_id,
		arrival_anchor_id,
	)
	if not bool(arrival.get("valid", false)):
		return false
	var map_data: Variant = _world.owner_services.GameData.get_map_by_id(map_id)
	if map_data.is_empty():
		return false
	map_data = _runtime_named_map_data(map_data)
	_load_zone(str(map_data.get("name", "未命名地图")), false, map_data)
	if current_map_id != map_id:
		return false
	_set_player_world_position(arrival.get("position_px", Vector2.ZERO) as Vector2)
	player.velocity = Vector2.ZERO
	_relocate_main_pets_after_map_arrival()
	background.set_focus_position(player.global_position)
	_record_player_world_location()
	return true



func _map_teleport_item_count_by_id(item_id: int) -> int:
	if item_id <= 0:
		return 0
	var total: Variant = 0
	for raw_record: Variant in _world.profile.inventory:
		if not raw_record is Dictionary or (raw_record as Dictionary).is_empty():
			continue
		var record: Dictionary = raw_record
		var catalog_item: Variant = _world.owner_services.GameData.get_item_record(record)
		if int(catalog_item.get("itemId", -1)) == item_id:
			total += maxi(0, int(record.get("count", 1)))
	return total



func _on_revival_requested(request: Dictionary) -> bool:
	if _active_death_id.is_empty() or _death_revival_request_in_flight:
		return false
	if str(request.get("contract_id", "")) != DEATH_REVIVAL_CONTRACT_ID:
		return false
	if str(request.get("death_id", "")) != _active_death_id:
		return false
	if (
		str(request.get("option_slot", "")) != "town"
		or str(request.get("method_id", "")) != "revive.nearest_town"
	):
		return false
	_death_revival_request_in_flight = true
	var accepted: Variant = _source_travel_to_service_home(
		false,
		_map_failure_recovery_active,
		"比奇省",
		Callable(self, "_finish_death_revival")
	)
	if accepted:
		return true
	_death_revival_request_in_flight = false
	if is_instance_valid(hud):
		hud.apply_revival_result({
			"success": false,
			"message": "复活位置暂不可用",
			"revival_options": _death_revival_context().get("revival_options", []),
		})
	return false



func _finish_death_revival() -> void:
	var home: Variant = _resolve_bich_home()
	if not bool(home.get("valid", false)):
		# Keep the death state; never revive at a source-map current position.
		_handle_home_resolution_failure(&"death_revival", home)
		_death_revival_request_in_flight = false
		if is_instance_valid(hud):
			hud.apply_revival_result({
				"success": false,
				"message": "复活位置暂不可用",
				"revival_options": _death_revival_context().get("revival_options", []),
			})
		return
	_set_player_world_position(home.get("position_px", Vector2.ZERO) as Vector2)
	player.velocity = Vector2.ZERO
	player.complete_death_revival()
	_relocate_main_pets_after_map_arrival()
	background.set_focus_position(player.global_position)
	_record_player_world_location()
	_world.profile.save_game()
	_death_experience_penalty_applied = false
	_active_death_id = ""
	_death_revival_request_in_flight = false
	if _gameplay_input_locks.has(INPUT_LOCK_PLAYER_DEATH):
		_release_gameplay_input_lock(INPUT_LOCK_PLAYER_DEATH)
	if is_instance_valid(hud):
		hud.apply_revival_result({"success": true, "message": "已经复活"})
		hud.show_message("你已在最近的城镇复活", 2.0)



func _death_revival_context() -> Dictionary:
	return {
		"contract_id": DEATH_REVIVAL_CONTRACT_ID,
		"flow_id": DEATH_REVIVAL_FLOW_ID,
		"death_id": _active_death_id,
		"message": "你倒在了%s" % (current_zone if not current_zone.is_empty() else "冒险途中"),
		"loss_text": "死亡损失：经验 10%",
		"revival_options": [
			{
				"option_slot": "town",
				"method_id": "revive.nearest_town",
				"label": "最近城镇复活",
				"enabled": true,
				"countdown_seconds": 0,
				"hint": "返回比奇省安全区",
			},
			{
				"option_slot": "special",
				"method_id": "revive.special.scroll",
				"label": "特殊复活",
				"enabled": false,
				"countdown_seconds": 0,
				"reason": "特殊复活暂不可用",
			},
		],
	}



func _request_production_town_revival() -> bool:
	if _active_death_id.is_empty() or _death_revival_request_in_flight:
		return false
	return _on_revival_requested({
		"contract_id": DEATH_REVIVAL_CONTRACT_ID,
		"death_id": _active_death_id,
		"option_slot": "town",
		"method_id": "revive.nearest_town",
	})



func _handle_home_resolution_failure(
	action: StringName,
	result: Dictionary
) -> void:
	var diagnostic: Variant = {
		"action": str(action),
		"reason": str(result.get("reason", "home_resolution_failed")),
		"home_source": str(result.get("source", "")),
		"current_map_id": current_map_id,
		"player_position": (
			player.global_position if is_instance_valid(player) else Vector2.ZERO
		),
		"timestamp": _world.clock_ports.get_ticks_msec(),
	}
	_fields.write_source_field(&"home_resolution_failure_diagnostic",diagnostic)
	_report_safe_logout_error(
		action,
		str(result.get("reason", "home_resolution_failed"))
	)
	if is_instance_valid(hud) and hud.has_method("show_error_message"):
		# Player-readable Chinese only; the raw resolution reason is retained
		# in the diagnostic above and in push_error via the reporter.
		hud.show_error_message("无法确定安全返回位置。", 2.0)



func _cancel_respawn_wakeups() -> void:
	# Preserve the original SceneTreeTimer clock while this world is live.
	# Retirement revokes dispatch first, then lets SceneTree reclaim timers on
	# its next idle pass instead of retaining dead-world wakeups for 5-60 min.
	var retiring: Array = _respawn_wakeups.values()
	_respawn_wakeups.clear()
	for wakeup: RefCounted in retiring:
		wakeup.time_left = 0.0



func _fail_map_transition(recovery_policy: StringName) -> void:
	var failed_transition_serial: Variant = _map_transition_serial
	# The failed transition still owns its accepted Main effects, loader tokens
	# and exact scope. Complete that boundary before hiding its cover or allowing
	# safe-home recovery to open another scope; no timer substitutes for IO.
	var actual_transport: RefCounted = original_map_loading_transport()
	if actual_transport != null and not actual_transport.get("_scope").is_empty():
		while actual_transport.has_pending_original_map_continuation():
			await actual_transport._next_source_p()
		if not await _map_loading_port.finish_original_map_loading():
			_world.fault("actual_failed_Map_scope_retained_before_recovery",{"transition_id":_active_map_transition_id,"generation":original_map_coordinator_generation()})
			return
	if _world.current_clock_frame().get("closing_session") == true: return
	# A portal operation owns its single-flight claim across the whole async
	# transition. Retire only that claim when the transition fails before the
	# bound operation reaches _complete_portal_travel.
	if _active_portal_claim_transition_serial == failed_transition_serial:
		_cancel_portal_travel_claim(_active_portal_claim_id)
	# prepare_map_build clears the prior real environment before arrival.
	# After that boundary a pre-arrival failure cannot keep it playable.
	if recovery_policy == &"pre_arrival_keep_world" and _map_transition_environment_replaced:
		recovery_policy = &"post_arrival_safe_home"
	var coordinator: Variant = _world_bootstrap_coordinator
	var reason: Variant = "map_transition_failed"
	if coordinator != null and is_instance_valid(coordinator):
		reason = str(coordinator.diagnostic.get("failure_reason", reason))
	if player != null and is_instance_valid(player):
		player.finish_combat_transition(str(_fields.read_source_field(&"map_combat_transition_token")))
	_cancel_map_transition_movement_input()
	_active_map_transition_id = ""
	_map_transition_in_progress = false
	if _map_failure_recovery_active:
		# The failed destination was already unsafe. A failed real home build
		# cannot restore it, release input, or recursively start another home.
		_map_failure_recovery_active = false
		if not _gameplay_input_locks.has(INPUT_LOCK_MAP_TRANSITION_LOCAL):
			_acquire_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)
		if is_instance_valid(hud):
			hud.finish_loading_transition()
			hud.show_error_message("安全区域加载失败，请重新进入游戏。", 4.0)
		print("[MapTransition] terminal safe-home failure reason=%s" % reason)
		return
	if is_instance_valid(hud):
		hud.finish_loading_transition()
		if recovery_policy == &"pre_arrival_keep_world":
			hud.show_error_message("地图切换失败，已保留当前区域，可稍后重试。", 4.0)
		elif recovery_policy == &"post_arrival_safe_home":
			hud.show_error_message("地图加载未完成，正在送回安全点。", 4.0)
		else:
			hud.show_error_message("地图切换失败，请稍后重试。", 4.0)
	print("[MapTransition] FAILED reason=%s policy=%s" % [reason, str(recovery_policy)])
	if recovery_policy == &"post_arrival_safe_home":
		_map_failure_recovery_active = true
		# A player killed during the failed arrival goes through the
		# production death revival (home relocation + death state cleanup);
		# a living player goes through the plain safe-home relocation. An
		# in-flight death flow (hp 0, _dead not yet set) gets a short settle
		# window so the revival sees the real state; the transition lock is
		# only released after the recovery finished.
		if player != null and is_instance_valid(player):
			# Death settlement is queued and may land after the transition
			# already ended (the arrival fight can kill the player while the
			# ready-contract check is still running); give it a bounded
			# window to land so the recovery picks the right branch.
			var death_settle: Variant = _world.clock_ports.get_ticks_msec() + 5000
			while (
				int(player.current_hp) <= 0
				and not bool(player._dead)
				and _world.clock_ports.get_ticks_msec() < death_settle
			):
				await _world.create_timer(0.05,true).timeout
			# A real death-UI transition may take ownership during the settle
			# await. The old failure cannot release that new owner's lock.
			if _map_transition_serial != failed_transition_serial or not _map_failure_recovery_active:
				return
			print("[MapTransition] recovery state dead=%s hp=%d" % [
				str(player._dead), int(player.current_hp),
			])
			# The FAILED transition's own lock must go before a new home
			# transition can acquire it; the recovery transition re-owns
			# the lock and releases it through its own READY/FAILED path.
			if _gameplay_input_locks.has(INPUT_LOCK_MAP_TRANSITION_LOCAL):
				_release_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)
			var recovery_started: Variant = false
			if bool(player._dead):
				# Formal production town revival: full home travel +
				# _finish_death_revival completion boundary (no bare
				# teleport - the player must land in the home WORLD).
				recovery_started = _request_production_town_revival()
			else:
				recovery_started = _source_travel_to_service_home(
					false, true, "比奇省", Callable()
				)
			if recovery_started:
				print("[MapTransition] safe-home recovery transition started")
				return
		# No recovery exists: the current incomplete world stays closed.
		_map_failure_recovery_active = false
		if not _gameplay_input_locks.has(INPUT_LOCK_MAP_TRANSITION_LOCAL):
			_acquire_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)
		if is_instance_valid(hud):
			hud.show_error_message("安全区域加载失败，请重新进入游戏。", 4.0)
		return
	# pre_arrival_keep_world (and future title-return): the current world is
	# safe to hand back to gameplay input, so the transition lock goes away.
	_release_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)



func _cancel_portal_travel_claim(claim_id: String) -> void:
	if claim_id.is_empty():
		return
	MapPortalTravelGuardScript.cancel_travel(_portal_guard_state, claim_id)
	if _active_portal_claim_id == claim_id:
		_active_portal_claim_id = ""
		_active_portal_claim_transition_serial = -1


## P0-3: formal production town revival for a dead player - constructs the
## revival request and hands it to the production handler, which owns the
## home travel, the revival completion boundary and the death-lock release.

func _resolve_projection_profile_for_map(map_id: int) -> Dictionary:
	return _world_skill_runtime()._resolve_projection_profile_for_map(map_id)



func _validate_queued_actor_descriptor(descriptor: Dictionary) -> bool:
	if not _collecting_staged_actor_plan:
		return false
	var actor_type: Variant = str(descriptor.get("actor_type", ""))
	if actor_type != "enemy":
		return actor_type in ["npc", "zone_portal", "map_portal"]
	var payload: Dictionary = descriptor.get("payload", {})
	var position: Variant = payload.get("position")
	var seconds: Variant = payload.get("respawn_seconds", -1.0)
	var raw_context: Variant = payload.get("spawn_context", {})
	if not position is Vector2 or not position.is_finite() \
		or (not seconds is int and not seconds is float) or not is_finite(float(seconds)) \
		or not raw_context is Dictionary:
		return false
	var context: Dictionary = raw_context
	var slot: Variant = str(context.get("spawn_slot_id", context.get("spawn_group_id", "")))
	if slot.is_empty():
		return false
	return _feature_target_bound.declared_base_matches(
		_strict_runtime_monster_id(payload), position, float(seconds), context, str(descriptor.get("actor_id", "")))



func _spawn_staged_actor_descriptor(descriptor: Dictionary) -> Dictionary:
	var actor_type: Variant = str(descriptor.get("actor_type", ""))
	var payload: Dictionary = descriptor.get("payload", {})
	match actor_type:
		"enemy":
			var monster_id: Variant = int(payload.get("monster_id", -1))
			var monster: Variant = {"monster_id": monster_id}
			_staged_actor_spawn_failure_reason = ""
			var enemy: Variant = _spawn_enemy(
				monster,
				payload.get("position", Vector2.ZERO),
				bool(payload.get("is_boss", false)),
				float(payload.get("respawn_seconds", -1.0)),
				payload.get("spawn_context", {})
			)
			if not _staged_actor_spawn_failure_reason.is_empty():
				return {
					"ok": false,
					"reason": _staged_actor_spawn_failure_reason,
				}
			# A persisted death may deliberately schedule this slot for later. The
			# descriptor was still handled successfully even though no node exists yet.
			return {"ok": true, "materialized": enemy != null}
		"npc":
			_map_source_helper__spawn_npc(
				payload.get("position", Vector2.ZERO),
				str(payload.get("display_name", "NPC")),
				str(payload.get("kind", "dialogue")),
				payload.get("stock", []),
				str(payload.get("stock_key", "")),
				int(payload.get("appearance", -1)),
				payload.get("map_center_override", null)
			)
			return {"ok": true, "materialized": true}
		"zone_portal":
			_map_source_helper__spawn_portal(
				payload.get("position", Vector2.ZERO),
				str(payload.get("target_zone", "")),
				str(payload.get("label_text", ""))
			)
			return {"ok": true, "materialized": true}
		"map_portal":
			_map_source_helper__spawn_map_portal(
				payload.get("position", Vector2.ZERO),
				int(payload.get("target_map_id", -1)),
				str(payload.get("label_text", "")),
				payload.get("portal_data", {})
			)
			return {"ok": true, "materialized": true}
		_:
			return {"ok": false, "reason": "unknown_actor_type"}



func _map_source_helper__active_skill_workset_candidates() -> Variant:
	return call(_map_source_helpers[&"_active_skill_workset_candidates"])

func _map_source_helper__preload_map_loot_icons(map_id: int) -> Variant:
	return await call(_map_source_helpers[&"_preload_map_loot_icons"], map_id)

func _map_source_helper__prewarm_learned_skill_visuals() -> Variant:
	return await call(_map_source_helpers[&"_prewarm_learned_skill_visuals"])

func _map_source_helper__print_session_diagnostics_header() -> Variant:
	return call(_map_source_helpers[&"_print_session_diagnostics_header"])

func _map_source_helper__spawn_map_portal(
	position: Vector2,
	target_map_id: int,
	label_text: String,
	portal_data: Dictionary = {}
) -> Variant:
	return call(_map_source_helpers[&"_spawn_map_portal"], position, target_map_id, label_text, portal_data)

func _map_source_helper__spawn_npc(position: Vector2, display_name: String, kind: String, stock: Array = [], stock_key := "", appearance := -1, map_center_override: Variant = null) -> Variant:
	return call(_map_source_helpers[&"_spawn_npc"], position, display_name, kind, stock, stock_key, appearance, map_center_override)

func _map_source_helper__spawn_portal(position: Vector2, target_zone: String, label_text: String) -> Variant:
	return call(_map_source_helpers[&"_spawn_portal"], position, target_zone, label_text)

func _map_source_helper__warm_fire_wall_render_path() -> Variant:
	return await call(_map_source_helpers[&"_warm_fire_wall_render_path"])

func _capture_original_map_warm_request(operation: String, map_id: int) -> Dictionary:
	var workset: Array[String] = []
	var names: Array[String] = []
	if operation == "loot_icons": names = _world.loot.possible_item_names_for_monster_ids(_monster_ids_for_map(map_id))
	else: workset.assign(call(&"_active_skill_workset_candidates"))
	var facing := Vector2.DOWN
	var position := Vector2.ZERO
	if is_instance_valid(player): facing = player.facing; position = player.global_position
	var request := {"contract_id":"hardcore.source.map_warm_request.v1","world_context":_world.current_world_identity(),
		"source_root_id":get_instance_id(),"owner_session_id":_world.original_source_session().original_budget_session_id(),
		"transition_id":str(_active_map_transition_id),"coordinator_generation":original_map_coordinator_generation(),
		"map_id":map_id,"operation":operation,"workset":workset,"facing":facing,"player_position_px":position,"item_names":names}
	var captured: Dictionary = preload("res://scripts/gameplay/world/world_environment_value_graph.gd").copy_and_seal(request)
	return captured.value if captured.ok else {}

func _execute_original_map_warm(operation: String, map_id: int) -> Dictionary:
	var session: RefCounted = _world.original_source_session()
	var provider: RefCounted = session.get("_services").get("WorldUiLoading")
	if provider == null or provider.owner_thread_id() != owner_thread_id() or not provider.has_method("execute_original_map_warm"): return {"success":false,"status":"INVALID","error":"actual_same_Session_map_warm_provider_required"}
	var request: Dictionary = _capture_original_map_warm_request(operation,map_id)
	if request.is_empty(): return {"success":false,"status":"INVALID","error":"actual_Source_map_warm_input_capture_failed"}
	return await provider.execute_original_map_warm(request)

func _preload_map_loot_icons(map_id: int) -> bool:
	if map_id < 0: return true # Exact original no-map branch starts no icon work.
	var result: Dictionary = await _execute_original_map_warm("loot_icons",map_id)
	return result.get("success") == true and result.get("stage") == "ORIGINAL_LOOT_ICON_REQUESTS_SUBMITTED"

func _prewarm_learned_skill_visuals() -> Dictionary:
	return await _execute_original_map_warm("workset",int(current_map_id))

func _warm_fire_wall_render_path() -> Dictionary:
	return await _execute_original_map_warm("render",int(current_map_id))
