extends "res://scripts/gameplay/world/world_root_map_loading.gd"
const SourceNPCModel := preload("res://scripts/gameplay/actors/npc_actor_model.gd")
const SourcePortalModel := preload("res://scripts/gameplay/actors/zone_portal_model.gd")
const PortalRuntime := preload("res://scripts/map_editor/map_portal_runtime_service.gd")
const PortalGuard := preload("res://scripts/map_editor/map_portal_travel_guard.gd")
const Workset := preload("res://scripts/gameplay/world/world_interactable_workset.gd")
const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
var _session_header_printed: Variant:
	get: return _world.interactables.header_already_printed()
	set(value): _world.interactables.mark_header_command_accepted(value)
func _spawn_npc(position: Vector2, display_name: String, kind: String, stock: Array = [], stock_key := "", appearance := -1, map_center_override: Variant = null) -> void:
	if _collecting_staged_actor_plan:
		_submit_staged_actor_descriptor("npc", {
			"position": position,
			"display_name": display_name,
			"kind": kind,
			"stock": stock,
			"stock_key": stock_key,
			"appearance": appearance,
			"map_center_override": map_center_override,
		})
		return
	var npc: Variant = _world.create_interactable_at_original_constructor(&"npc")
	var map_center := _current_map_center_screen_position_px() if map_center_override == null else Vector2(map_center_override)
	if npc == null: _source_fail("interactable_constructor_failed"); return
	npc.setup(display_name, kind, stock, stock_key, appearance, map_center)
	npc.global_position = position
	if not _world.enter_interactable_at_original_child_boundary(npc): _source_fail("interactable_original_child_entry_failed")

func _spawn_portal(position: Vector2, target_zone: String, label_text: String) -> void:
	if _collecting_staged_actor_plan:
		_submit_staged_actor_descriptor("zone_portal", {
			"position": position,
			"target_zone": target_zone,
			"label_text": label_text,
		})
		return
	var portal: Variant = _world.create_interactable_at_original_constructor(&"zone_portal")
	if portal == null: _source_fail("interactable_constructor_failed"); return
	portal.setup(target_zone, label_text)
	portal.global_position = position
	if not _world.enter_interactable_at_original_child_boundary(portal): _source_fail("interactable_original_child_entry_failed")

func _spawn_map_portal(
	position: Vector2,
	target_map_id: int,
	label_text: String,
	portal_data: Dictionary = {}
) -> void:
	if _collecting_staged_actor_plan:
		_submit_staged_actor_descriptor("map_portal", {
			"position": position,
			"target_map_id": target_map_id,
			"label_text": label_text,
			"portal_data": portal_data,
		})
		return
	var portal: Variant = _world.create_interactable_at_original_constructor(&"zone_portal")
	if portal == null: _source_fail("interactable_constructor_failed"); return
	portal.setup_map(target_map_id, label_text, portal_data)
	portal.global_position = position
	if not _world.enter_interactable_at_original_child_boundary(portal): _source_fail("interactable_original_child_entry_failed")

func _try_interact() -> void:
	if not gameplay_input_is_enabled(): return
	var nearest: Object
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(
		player.global_position
	)
	var nearest_distance_gu := (
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			105.0
		)
	)
	for node: Object in _world.skill_actors.actors_in_group(&"interactable"):
		if not node is SourceNPCModel and not node is SourcePortalModel:
			continue
		var distance_gu := GroundUnitSpaceScript.distance_gu(
			origin_ground_gu,
			_canonical_screen_px_to_ground_gu(node.global_position)
		)
		if distance_gu < nearest_distance_gu:
			nearest = node
			nearest_distance_gu = distance_gu
	if nearest == null:
		hud.show_error_message("附近没有可交互目标")
		return
	nearest.interact(self)

func change_zone(zone_name: String, initial := false) -> void:
	var target_map_id: Variant = -1
	var map_data: Dictionary = _world.owner_services.GameData.get_map(zone_name)
	if zone_name == "比奇城":
		map_data = _world.owner_services.GameData.get_map_by_id(_world.owner_services.GameData.service_runtime_map_id(0))
	if not map_data.is_empty():
		target_map_id = int(map_data.get("mapId", -1))
	var operation: Variant = Callable(self, "_change_zone_immediate").bind(zone_name, initial)
	if _should_animate_map_transition(initial):
		_begin_map_transition(operation, target_map_id)
	else:
		operation.call()

func travel_to_map(map_id: int) -> void:
	_request_map_travel(map_id)

func _request_map_travel(map_id: int) -> bool:
	if not gameplay_input_is_enabled(): return false
	map_id = _world.owner_services.GameData.service_runtime_map_id(map_id)
	# FREEZE-P0.2: refuse travel before the transition when the target map has
	# no formal projection profile; never load_zone into a half-broken world.
	var travel_profile: Variant = _resolve_projection_profile_for_map(map_id)
	if not bool(travel_profile.get("success", false)):
		missing_projection_rejection_count += 1
		projection_rejection_reason = str(
			travel_profile.get("reason", "")
		)
		hud.show_error_message("当前地图投影暂不可用（%d）" % map_id)
		return false
	var map_data: Variant = _world.owner_services.GameData.get_map_by_id(map_id)
	if map_data.is_empty():
		hud.show_error_message("地图数据不存在：%d" % map_id)
		return false
	if current_map_id == map_id:
		return false
	var operation: Variant = Callable(self, "_travel_to_map_immediate").bind(map_id)
	if _should_animate_map_transition(false):
		return _begin_map_transition(operation, map_id)
	return bool(operation.call())

func _travel_to_map_immediate(map_id: int) -> bool:
	var map_data: Variant = _world.owner_services.GameData.get_map_by_id(map_id)
	if map_data.is_empty() or current_map_id == map_id:
		return false
	# Resolve Home before _load_zone tears down the source world. The staged
	# pipeline already has this gate; synchronous travel must fail closed too.
	if map_id == BICH_RUNTIME_MAP_ID:
		var home_result: Variant = _resolve_bich_home()
		if not bool(home_result.get("valid", false)):
			_handle_home_resolution_failure(&"sync_travel_arrival", home_result)
			return false
	map_data = _runtime_named_map_data(map_data)
	var source_map_id: Variant = current_map_id
	_load_zone(str(map_data.get("name", "未命名地图")), false, map_data)
	if current_map_id == map_id:
		_set_player_world_position(route_arrival_position(map_id, source_map_id))
		player.velocity = Vector2.ZERO
		_relocate_main_pets_after_map_arrival()
		background.set_focus_position(player.global_position)
	return current_map_id == map_id

func travel_via_portal(portal: Object, fresh_activation := true) -> bool:
	if not gameplay_input_is_enabled():
		return false
	if str(portal.portal_data.get("portal_contract_id", "")) != PortalRuntime.PORTAL_CONTRACT_ID:
		return _request_map_travel(portal.target_map_id)
	var portal_id: Variant = str(portal.portal_data.get("source_portal_id", ""))
	var current_runtime: Variant = _world.environment_factory.runtime_maps.load_map(current_map_id)
	var endpoint: Variant = PortalRuntime.endpoint_by_id(
		current_runtime, portal_id
	)
	if endpoint.is_empty():
		hud.show_error_message("传送节点端点不存在", 1.5)
		return false
	var current_ground_gu: Variant = (
		_world.environment_factory.runtime_maps.screen_position_px_to_ground_position_gu(
			current_runtime, player.global_position
		)
		if not current_runtime.is_empty()
		else Vector2.ZERO
	)
	if not PortalGuard.can_activate(
		_portal_guard_state,
		_portal_guard_key(current_map_id, portal_id),
		Time.get_ticks_msec(),
		current_ground_gu,
		fresh_activation
	):
		hud.show_error_message("传送节点尚未稳定，请稍候或先离开入口", 1.5)
		return false
	var request: Variant = PortalRuntime.travel_request(endpoint)
	if not _valid_portal_request(request):
		hud.show_error_message("传送节点配置无效", 1.5)
		return false
	if not PortalGuard.begin_travel(_portal_guard_state):
		return false
	var portal_claim_id: Variant = PortalGuard.active_claim_id(
		_portal_guard_state
	)
	_active_portal_claim_id = portal_claim_id
	var target_map_id: Variant = int(request.get("target_map_id", -1))
	var map_data: Variant = _world.owner_services.GameData.get_map_by_id(target_map_id)
	if map_data.is_empty():
		_cancel_portal_travel_claim(portal_claim_id)
		hud.show_error_message("地图数据不存在：%d" % target_map_id)
		return false
	var target_runtime: Variant = _world.environment_factory.runtime_maps.load_map(target_map_id)
	var target_portal_id: Variant = str(request.get("target_portal_id", ""))
	var target_endpoint: Variant = PortalRuntime.endpoint_by_id(
		target_runtime, target_portal_id
	)
	if target_runtime.is_empty() or target_endpoint.is_empty():
		_cancel_portal_travel_claim(portal_claim_id)
		hud.show_error_message("目标地图或目标门点不可用", 1.5)
		return false
	if str(target_runtime.get("source", {}).get("map_id", "")) != str(request.get("target_map_key", "")):
		_cancel_portal_travel_claim(portal_claim_id)
		hud.show_error_message("目标地图标识不匹配", 1.5)
		return false
	var target_tile: Variant = _portal_tile(target_endpoint.get("tile", []))
	if target_tile == Vector2.INF or target_tile != _portal_tile(request.get("target_tile", [])):
		_cancel_portal_travel_claim(portal_claim_id)
		hud.show_error_message("目标门点坐标不匹配", 1.5)
		return false
	map_data = _runtime_named_map_data(map_data)
	var operation: Variant = Callable(self, "_complete_portal_travel").bind(
		target_map_id,
		map_data,
		target_runtime,
		target_portal_id,
		target_tile,
		portal_claim_id
	)
	if _should_animate_map_transition(false):
		if _begin_map_transition(operation, target_map_id, portal_claim_id):
			return true
		_cancel_portal_travel_claim(portal_claim_id)
		return false
	return bool(operation.call())

func _complete_portal_travel(
	target_map_id: int,
	map_data: Dictionary,
	target_runtime: Dictionary,
	target_portal_id: String,
	target_tile: Vector2,
	portal_claim_id: String
) -> bool:
	if portal_claim_id != PortalGuard.active_claim_id(_portal_guard_state):
		return false
	_load_zone(str(map_data.get("name", "未命名地图")), false, map_data)
	if current_map_id != target_map_id:
		_cancel_portal_travel_claim(portal_claim_id)
		return false
	var arrival_ground_gu: Variant = _world.environment_factory.runtime_maps.cell_to_ground_position_gu(
		[target_tile.x, target_tile.y]
	)
	var arrival_position: Variant = (
		_world.environment_factory.runtime_maps.ground_position_gu_to_screen_position_px(
			target_runtime,
			arrival_ground_gu
		)
	)
	_set_player_world_position(arrival_position)
	player.velocity = Vector2.ZERO
	_relocate_main_pets_after_map_arrival()
	background.set_focus_position(player.global_position)
	PortalGuard.finish_arrival(
		_portal_guard_state,
		_portal_guard_key(target_map_id, target_portal_id),
		Time.get_ticks_msec(),
		arrival_ground_gu
	)
	_active_portal_claim_id = ""
	_active_portal_claim_transition_serial = -1
	return true

func _valid_portal_request(request: Dictionary) -> bool:
	return (
		bool(request.get("ok", false))
		and int(request.get("target_map_id", -1)) >= 0
		and not str(request.get("target_map_key", "")).is_empty()
		and not str(request.get("target_portal_id", "")).is_empty()
		and str(request.get("arrival_guard_policy_id", "")) == PortalGuard.POLICY_ID
		and is_equal_approx(float(request.get("return_minimum_seconds", 0.0)), 3.0)
		and is_equal_approx(
			float(request.get("return_unlock_distance_gu", -1.0)),
			PortalGuard.UNLOCK_DISTANCE_GU
		)
		and bool(request.get("single_flight", false))
	)

func _portal_tile(raw_tile: Variant) -> Vector2:
	if not raw_tile is Array or raw_tile.size() != 2:
		return Vector2.INF
	return Vector2(float(raw_tile[0]), float(raw_tile[1]))

func _portal_guard_key(map_id: int, portal_id: String) -> String:
	return "%d:%s" % [map_id, portal_id]

func _should_animate_map_transition(initial: bool) -> bool:
	return (
		not initial
		and not _world.profile.test_mode
		and is_instance_valid(hud)
		and hud.has_method("begin_loading_transition")
		and hud.has_method("finish_loading_transition")
		and hud.has_signal("loading_transition_covered")
	)

func play_npc_interaction_voice(service_id: String) -> void:
	if is_instance_valid(_audio_runtime_service):
		_audio_runtime_service.play_npc_interaction_success(service_id, {"map_id": current_map_id})

func _active_skill_workset_candidates() -> Array[String]:
	var raw: Array = []
	raw.append_array(
		_world.profile.skill_slots_for_group(
			_world.profile.SKILL_SLOT_GROUP_ATTACK
		)
	)
	raw.append_array(
		_world.profile.skill_slots_for_group(
			_world.profile.SKILL_SLOT_GROUP_ATTACK_RING
		)
	)
	var display_names: Array = []
	for identity: Variant in raw:
		display_names.append(SkillDataLoaderScript.display_name(str(identity)))
	return Workset.workset_skill_order(display_names, 7)


## PERF-R2 R8: thread-pump texture paths with a REAL absolute deadline.
## No synchronous load() ever runs on this budget path: paths are admitted
## through load_threaded_request, polled every frame, and only a
## THREAD_LOAD_LOADED status may call load_threaded_get. The deadline stops
## new admissions; already-in-flight completions are still collected so no
## threaded work is wasted or leaked.

func _print_session_diagnostics_header() -> void:
	if _session_header_printed:
		return
	if not _world.interactables.print_session_diagnostics():
		_source_fail("actual_session_diagnostics_admission_failed")
		return
	_session_header_printed = true

