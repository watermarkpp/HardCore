extends Node2D

const TargetingSystem := preload("res://scripts/targeting_system.gd")
const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")
const MapCoordinateMapperScript := preload("res://scripts/map_coordinate_mapper.gd")
const GothicBichCampBuilderScript := preload("res://scripts/layers/presentation/gothic_bich_camp_builder.gd")
const MapEditorRuntimeBridgeScript := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const MapPortalRuntimeServiceScript := preload("res://scripts/map_editor/map_portal_runtime_service.gd")
const MapPortalTravelGuardScript := preload("res://scripts/map_editor/map_portal_travel_guard.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const SystemMenuPanelScript := preload("res://scripts/system_menu_panel.gd")
const DEFAULT_NORMAL_RESPAWN_SECONDS := 180.0
const DEFAULT_BOSS_RESPAWN_SECONDS := 3600.0

var player: PlayerCharacter
var hud: GameHUD
var background: WorldBackground
var current_zone := ""
var current_map_id := -1
var current_map_data: Dictionary = {}
var _zone_generation := 0
var _rng := RandomNumberGenerator.new()
var locked_target: EnemyActor
var manual_target_lock := false
var auto_target_enabled := true
var _mobile_attack_held := false
var _warrior_hud_timer := 0.0
var _system_menu_layer: CanvasLayer
var _system_menu_panel: Control
var _movement_target_refresh_remaining := 0.0
var _bich_camp_layout: Dictionary = {}
var _active_safe_zones: Array = []
var _runtime_spawn_serial := 0
var _portal_guard_state := MapPortalTravelGuardScript.new_state()
var _map_transition_in_progress := false
var _map_transition_serial := 0
var _active_map_transition_id := ""


func _ready() -> void:
	y_sort_enabled = true
	_rng.randomize()
	_bich_camp_layout = GothicBichCampBuilderScript.load_layout()
	_register_input_actions()
	background = WorldBackground.new()
	add_child(background)

	player = PlayerCharacter.new()
	player.name = "Player"
	player.attack_requested.connect(_on_player_attack)
	player.environment_blocker = background
	player.skill_requested.connect(_on_player_skill)
	player.warrior_skill_state_changed.connect(_on_warrior_skill_state_changed)
	player.stats_changed.connect(_on_player_stats_changed)
	player.movement_performed.connect(_on_player_moved)
	player.death_requested.connect(_on_player_death_requested)
	PlayerState.consumable_requested.connect(_on_consumable_used)
	PlayerState.scroll_requested.connect(_on_scroll_used)
	add_child(player)

	var camera := Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.zoom = Vector2.ONE * ArtSpec.CAMERA_ZOOM
	player.add_child(camera)

	hud = GameHUD.new()
	hud.movement_changed.connect(player.set_touch_vector)
	hud.attack_pressed.connect(_on_mobile_attack_pressed)
	hud.attack_released.connect(_on_mobile_attack_released)
	hud.interact_pressed.connect(_try_interact)
	hud.skill_pressed.connect(_use_quick_slot)
	hud.map_travel_requested.connect(travel_to_map)
	hud.target_switch_pressed.connect(_cycle_target)
	hud.auto_target_changed.connect(_set_auto_target_enabled)
	hud.special_action_pressed.connect(_on_special_action_pressed)
	add_child(hud)
	player.resources_changed.connect(hud.update_resources)
	# 重登始终从服务端HomeMap出生。该规则不依赖退出回调，Android强杀后同样安全回城。
	travel_to_service_home(false, true)
	PlayerState.update_world_location(current_map_id, player.global_position)
	_on_player_stats_changed(player.current_hp, player.max_hp)
	hud.update_warrior_states(player.warrior_state_snapshot())
	_build_system_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		call_deferred("_show_system_menu")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_prepare_safe_logout()
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _system_menu_panel != null and _system_menu_panel.visible:
			_hide_system_menu()
		else:
			_show_system_menu()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	background.set_focus_position(player.global_position)
	_update_portal_arrival_guard()
	_enforce_bich_safe_zone()
	_update_boss_world_mechanics(delta)
	PlayerState.update_world_location(current_map_id, player.global_position)
	_validate_locked_target()
	_update_target_hud()
	_warrior_hud_timer -= delta
	_movement_target_refresh_remaining = maxf(0.0, _movement_target_refresh_remaining - delta)
	if _warrior_hud_timer <= 0.0:
		_warrior_hud_timer = 0.2
		hud.update_warrior_states(player.warrior_state_snapshot())
	if _mobile_attack_held or Input.is_action_pressed("attack"):
		_request_mobile_attack()
	if Input.is_action_just_pressed("interact"):
		_try_interact()
	for index in range(4):
		if Input.is_action_just_pressed("skill_%d" % (index + 1)):
			_use_quick_slot(index)


func _register_input_actions() -> void:
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("move_up", [KEY_W, KEY_UP])
	_add_key_action("move_down", [KEY_S, KEY_DOWN])
	_add_key_action("attack", [KEY_SPACE, KEY_J])
	_add_key_action("interact", [KEY_E])
	_add_key_action("skill_1", [KEY_1])
	_add_key_action("skill_2", [KEY_2])
	_add_key_action("skill_3", [KEY_3])
	_add_key_action("skill_4", [KEY_4])


func _add_key_action(action: StringName, keycodes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for code: int in keycodes:
		var event := InputEventKey.new()
		event.physical_keycode = code
		InputMap.action_add_event(action, event)


func _build_system_menu() -> void:
	_system_menu_layer = CanvasLayer.new()
	_system_menu_layer.layer = 200
	add_child(_system_menu_layer)
	_system_menu_panel = SystemMenuPanelScript.new()
	_system_menu_panel.name = "SystemMenuPanel"
	_system_menu_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_system_menu_panel.visible = false
	_system_menu_panel.continue_requested.connect(_hide_system_menu)
	_system_menu_panel.return_to_character_select_requested.connect(_return_to_character_select)
	_system_menu_panel.save_and_exit_requested.connect(_exit_game)
	_system_menu_panel.audio_setting_changed.connect(_on_system_menu_audio_setting_changed)
	_system_menu_layer.add_child(_system_menu_panel)
	_system_menu_panel.set_audio_settings(
		_audio_bus_enabled("Music"),
		_audio_bus_enabled("SFX")
	)


func _show_system_menu() -> void:
	if _system_menu_panel == null:
		return
	_system_menu_panel.open_menu()
	get_tree().paused = true


func _hide_system_menu() -> void:
	get_tree().paused = false
	if _system_menu_panel != null:
		_system_menu_panel.close_menu()


func _audio_bus_enabled(bus_name: StringName) -> bool:
	var bus_index := AudioServer.get_bus_index(bus_name)
	return bus_index < 0 or not AudioServer.is_bus_mute(bus_index)


func _on_system_menu_audio_setting_changed(request: Dictionary) -> void:
	if str(request.get("contract_id", "")) != "ui.audio.setting.v1":
		return
	var setting_id := str(request.get("setting_id", ""))
	var bus_name := "Music" if setting_id == "audio.music.enabled" else "SFX"
	if setting_id not in ["audio.music.enabled", "audio.sfx.enabled"]:
		return
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, not bool(request.get("enabled", true)))


func _prepare_safe_logout() -> bool:
	return PlayerState.save_safe_logout(GameData.service_home_runtime_map_id(false), _bich_home_world_position())


func _return_to_character_select() -> void:
	_prepare_safe_logout()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _exit_game() -> void:
	_prepare_safe_logout()
	get_tree().paused = false
	get_tree().quit()


func change_zone(zone_name: String, initial := false) -> void:
	var operation := Callable(self, "_change_zone_immediate").bind(zone_name, initial)
	if _should_animate_map_transition(initial):
		_begin_map_transition(operation)
	else:
		operation.call()


func _change_zone_immediate(zone_name: String, initial := false) -> void:
	if zone_name == "比奇城":
		# 旧样板把“比奇城”画成独立伪地图；经典客户端中城镇属于0.map的比奇省。
		# 保留旧调用兼容，但统一进入服务端地图0所映射的运行地图4。
		var bich_map := GameData.get_map_by_id(GameData.service_runtime_map_id(0))
		_load_zone(str(bich_map.get("name", "比奇省")), initial, bich_map)
		player.global_position = _bich_home_world_position()
		player.velocity = Vector2.ZERO
		background.set_focus_position(player.global_position)
		return
	_load_zone(zone_name, initial, GameData.get_map(zone_name))


func travel_to_service_home(
	red_name := false,
	initial := false,
	fallback_zone := "",
	after_arrival := Callable()
) -> bool:
	var operation := Callable(self, "_complete_service_home_travel").bind(
		red_name, initial, fallback_zone, after_arrival
	)
	if _should_animate_map_transition(initial):
		return _begin_map_transition(operation)
	operation.call()
	return true


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
	var service_map_id := GameData.service_home_map_id(red_name)
	var runtime_map_id := GameData.service_runtime_map_id(service_map_id)
	var map_data := GameData.get_map_by_id(runtime_map_id)
	if not map_data.is_empty():
		_load_zone(str(map_data.get("name", "比奇省")), initial, map_data)
		if not red_name and service_map_id == 0:
			# 服务端(289,618)直接进入700×700原MAP统一坐标，不再压缩到场景中心。
			player.global_position = _bich_home_world_position()
			player.velocity = Vector2.ZERO
			background.set_focus_position(player.global_position)
	else:
		# 红名地图3尚未进入项目地图表；保留显式回退，不伪造服务端映射。
		var resolved_fallback := fallback_zone
		if resolved_fallback.is_empty():
			resolved_fallback = "比奇省" if not red_name else "比奇郊外"
		_change_zone_immediate(resolved_fallback, initial)


func travel_to_map(map_id: int) -> void:
	_request_map_travel(map_id)


func _request_map_travel(map_id: int) -> bool:
	var map_data := GameData.get_map_by_id(map_id)
	if map_data.is_empty():
		hud.show_message("地图数据不存在：%d" % map_id)
		return false
	if current_map_id == map_id:
		return false
	var operation := Callable(self, "_travel_to_map_immediate").bind(map_id)
	if _should_animate_map_transition(false):
		return _begin_map_transition(operation)
	return bool(operation.call())


func _travel_to_map_immediate(map_id: int) -> bool:
	var map_data := GameData.get_map_by_id(map_id)
	if map_data.is_empty() or current_map_id == map_id:
		return false
	map_data = _runtime_named_map_data(map_data)
	var source_map_id := current_map_id
	_load_zone(str(map_data.get("name", "未命名地图")), false, map_data)
	if current_map_id == map_id:
		player.global_position = route_arrival_position(map_id, source_map_id)
		player.velocity = Vector2.ZERO
		background.set_focus_position(player.global_position)
	return current_map_id == map_id


func travel_via_portal(portal: ZonePortal, fresh_activation := true) -> bool:
	if str(portal.portal_data.get("portal_contract_id", "")) != MapPortalRuntimeServiceScript.PORTAL_CONTRACT_ID:
		return _request_map_travel(portal.target_map_id)
	var portal_id := str(portal.portal_data.get("source_portal_id", ""))
	var current_runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	var endpoint := MapPortalRuntimeServiceScript.endpoint_by_id(
		current_runtime, portal_id
	)
	if endpoint.is_empty():
		hud.show_message("传送节点端点不存在", 1.5)
		return false
	var current_tile := (
		MapEditorRuntimeBridgeScript.world_to_tile(
			current_runtime, player.global_position
		)
		if not current_runtime.is_empty()
		else Vector2.ZERO
	)
	if not MapPortalTravelGuardScript.can_activate(
		_portal_guard_state,
		_portal_guard_key(current_map_id, portal_id),
		Time.get_ticks_msec(),
		current_tile,
		fresh_activation
	):
		hud.show_message("传送节点尚未稳定，请稍候或先离开入口", 1.5)
		return false
	var request := MapPortalRuntimeServiceScript.travel_request(endpoint)
	if not _valid_portal_request(request):
		hud.show_message("传送节点配置无效", 1.5)
		return false
	if not MapPortalTravelGuardScript.begin_travel(_portal_guard_state):
		return false
	var target_map_id := int(request.get("target_map_id", -1))
	var map_data := GameData.get_map_by_id(target_map_id)
	if map_data.is_empty():
		_portal_guard_state["travel_in_flight"] = false
		hud.show_message("地图数据不存在：%d" % target_map_id)
		return false
	var target_runtime := MapEditorRuntimeBridgeScript.load_map(target_map_id)
	var target_portal_id := str(request.get("target_portal_id", ""))
	var target_endpoint := MapPortalRuntimeServiceScript.endpoint_by_id(
		target_runtime, target_portal_id
	)
	if target_runtime.is_empty() or target_endpoint.is_empty():
		_portal_guard_state["travel_in_flight"] = false
		hud.show_message("目标地图或目标门点不可用", 1.5)
		return false
	if str(target_runtime.get("source", {}).get("map_id", "")) != str(request.get("target_map_key", "")):
		_portal_guard_state["travel_in_flight"] = false
		hud.show_message("目标地图标识不匹配", 1.5)
		return false
	var target_tile := _portal_tile(target_endpoint.get("tile", []))
	if target_tile == Vector2.INF or target_tile != _portal_tile(request.get("target_tile", [])):
		_portal_guard_state["travel_in_flight"] = false
		hud.show_message("目标门点坐标不匹配", 1.5)
		return false
	map_data = _runtime_named_map_data(map_data)
	var operation := Callable(self, "_complete_portal_travel").bind(
		target_map_id,
		map_data,
		target_runtime,
		target_portal_id,
		target_tile
	)
	if _should_animate_map_transition(false):
		if _begin_map_transition(operation):
			return true
		_portal_guard_state["travel_in_flight"] = false
		return false
	return bool(operation.call())


func _complete_portal_travel(
	target_map_id: int,
	map_data: Dictionary,
	target_runtime: Dictionary,
	target_portal_id: String,
	target_tile: Vector2
) -> bool:
	_load_zone(str(map_data.get("name", "未命名地图")), false, map_data)
	if current_map_id != target_map_id:
		_portal_guard_state["travel_in_flight"] = false
		return false
	var arrival_position := MapEditorRuntimeBridgeScript.tile_to_world(
		target_runtime, [target_tile.x, target_tile.y]
	)
	player.global_position = arrival_position
	player.velocity = Vector2.ZERO
	background.set_focus_position(player.global_position)
	MapPortalTravelGuardScript.finish_arrival(
		_portal_guard_state,
		_portal_guard_key(target_map_id, target_portal_id),
		Time.get_ticks_msec(),
		target_tile
	)
	return true


func _should_animate_map_transition(initial: bool) -> bool:
	return (
		not initial
		and not PlayerState.test_mode
		and is_instance_valid(hud)
		and hud.has_method("begin_loading_transition")
		and hud.has_method("finish_loading_transition")
		and hud.has_signal("loading_transition_covered")
	)


func _begin_map_transition(operation: Callable) -> bool:
	if _map_transition_in_progress or not operation.is_valid():
		return false
	_map_transition_serial += 1
	_active_map_transition_id = "map:%d:%d" % [
		Time.get_ticks_msec(),
		_map_transition_serial,
	]
	_map_transition_in_progress = true
	_run_map_transition(_active_map_transition_id, operation)
	return true


func _run_map_transition(transition_id: String, operation: Callable) -> void:
	hud.begin_loading_transition(transition_id)
	while _map_transition_in_progress and _active_map_transition_id == transition_id:
		var request: Dictionary = await hud.loading_transition_covered
		if (
			str(request.get("contract_id", "")) == LoadingTransitionOverlay.CONTRACT_ID
			and str(request.get("transition_id", "")) == transition_id
		):
			break
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	operation.call()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	hud.finish_loading_transition()
	_active_map_transition_id = ""
	_map_transition_in_progress = false


func _valid_portal_request(request: Dictionary) -> bool:
	return (
		bool(request.get("ok", false))
		and int(request.get("target_map_id", -1)) >= 0
		and not str(request.get("target_map_key", "")).is_empty()
		and not str(request.get("target_portal_id", "")).is_empty()
		and str(request.get("arrival_guard_policy_id", "")) == MapPortalTravelGuardScript.POLICY_ID
		and is_equal_approx(float(request.get("return_minimum_seconds", 0.0)), 3.0)
		and is_equal_approx(
			float(request.get("return_unlock_distance_tiles", 0.0)),
			MapPortalTravelGuardScript.UNLOCK_DISTANCE_TILES
		)
		and bool(request.get("single_flight", false))
	)


func _portal_tile(raw_tile: Variant) -> Vector2:
	if not raw_tile is Array or raw_tile.size() != 2:
		return Vector2.INF
	return Vector2(float(raw_tile[0]), float(raw_tile[1]))


func _portal_guard_key(map_id: int, portal_id: String) -> String:
	return "%d:%s" % [map_id, portal_id]


func _runtime_named_map_data(map_data: Dictionary) -> Dictionary:
	var resolved := map_data.duplicate(true)
	var map_id := int(resolved.get("mapId", -1))
	if MapEditorRuntimeBridgeScript.has_runtime_map(map_id):
		var content := MapEditorRuntimeBridgeScript.game_content_for_map(map_id)
		if not content.is_empty():
			resolved["name"] = str(content.get("name", resolved.get("name", "未命名地图")))
	return resolved


func _update_portal_arrival_guard() -> void:
	var locked_key := str(_portal_guard_state.get("locked_portal_id", ""))
	if locked_key.is_empty() or bool(_portal_guard_state.get("travel_in_flight", false)):
		return
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	if runtime.is_empty():
		return
	MapPortalTravelGuardScript.clear_lock_after_departure(
		_portal_guard_state,
		locked_key,
		MapEditorRuntimeBridgeScript.world_to_tile(runtime, player.global_position)
	)


func route_arrival_position(destination_map_id: int, source_map_id: int) -> Vector2:
	if MapEditorRuntimeBridgeScript.has_runtime_map(destination_map_id):
		return MapEditorRuntimeBridgeScript.portal_position(
			destination_map_id, "", source_map_id
		)
	var content := RegionContent.get_map_content(destination_map_id)
	for portal: Dictionary in content.get("portals", []):
		if int(portal.get("target_map_id", -1)) == source_map_id:
			var portal_position: Vector2 = portal.get("position", Vector2.ZERO)
			var interior_target := _bich_home_world_position() if destination_map_id == 4 else Vector2.ZERO
			return portal_position + portal_position.direction_to(interior_target) * 140.0
	return _bich_home_world_position() if destination_map_id == 4 else Vector2.ZERO


func route_next_target(map_id: int) -> Dictionary:
	var content := RegionContent.get_map_content(map_id)
	if map_id == 221 and not content.get("bosses", []).is_empty():
		return {"position": content.get("bosses", [])[0].get("position", Vector2.ZERO), "label": "骷髅精灵Boss房"}
	var portals: Array = content.get("portals", [])
	if not portals.is_empty():
		var portal: Dictionary = portals[-1]
		return {"position": portal.get("position", Vector2.ZERO), "label": str(portal.get("label", "区域出口"))}
	return {}


func _bich_home_world_position() -> Vector2:
	var editor_home := MapEditorRuntimeBridgeScript.home_position()
	if editor_home != Vector2.ZERO:
		return editor_home
	var content := RegionContent.get_map_content(4)
	return content.get("runtime_home_position", MapCoordinateMapperScript.source_to_world(Vector2(289, 618), Vector2i(700, 700)))


func _bich_portal_position_to(target_map_id: int) -> Vector2:
	for portal: Dictionary in RegionContent.get_map_content(4).get("portals", []):
		if int(portal.get("target_map_id", -1)) == target_map_id:
			return portal.get("position", _bich_home_world_position())
	return _bich_home_world_position()


func _load_zone(zone_name: String, initial: bool, map_data: Dictionary) -> void:
	if zone_name == current_zone and not initial:
		if map_data.is_empty() or int(map_data.get("mapId", -1)) == current_map_id:
			return
	_zone_generation += 1
	_active_safe_zones.clear()
	_cancel_target()
	for node: Node in get_tree().get_nodes_in_group("zone_content"):
		if is_instance_valid(node):
			node.queue_free()
	current_zone = zone_name
	current_map_data = map_data.duplicate(true)
	current_map_id = int(map_data.get("mapId", -1)) if not map_data.is_empty() else -1
	background.set_zone_data(zone_name, current_map_data)
	hud.set_zone_name("比奇营地 · 安全区" if current_map_id == 4 else zone_name)
	if zone_name == "比奇城":
		player.global_position = Vector2(0, 80)
		_spawn_city_content()
	elif zone_name == "比奇郊外":
		player.global_position = Vector2.ZERO
		_spawn_outskirts_content()
	else:
		player.global_position = _bich_home_world_position() if current_map_id == 4 else Vector2.ZERO
		_spawn_database_zone_content(current_map_data)
	player.velocity = Vector2.ZERO
	background.set_focus_position(player.global_position)
	_on_player_stats_changed(player.current_hp, player.max_hp)
	hud.show_message("进入%s" % zone_name, 1.5)


func _spawn_database_zone_content(map_data: Dictionary) -> void:
	if map_data.is_empty():
		_spawn_outskirts_content()
		return
	var map_id := int(map_data.get("mapId", -1))
	if MapEditorRuntimeBridgeScript.has_runtime_map(map_id):
		var editor_content := (
			MapEditorRuntimeBridgeScript.game_content_for_map(map_id)
		)
		if not editor_content.is_empty():
			_spawn_editor_runtime_content(editor_content)
			return
	if RegionContent.has_map(map_id):
		_spawn_authored_map_content(RegionContent.get_map_content(map_id))
		return
	var region := str(map_data.get("region", ""))
	var recommended_level := 18
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
	var boss_ids := {}
	for boss: Variant in GameData.bosses:
		if boss is Dictionary:
			boss_ids[int(boss.get("monsterId", -1))] = true
	var candidates: Array = []
	for monster: Variant in GameData.monsters:
		if not monster is Dictionary or boss_ids.has(int(monster.get("monsterId", -1))):
			continue
		var monster_level := int(monster.get("level", 1))
		if monster_level >= maxi(1, recommended_level - 12) and monster_level <= recommended_level + 8:
			candidates.append(monster)
	if candidates.is_empty():
		candidates = GameData.monsters.duplicate()
	var positions := [Vector2(-250, -130), Vector2(230, -150), Vector2(-390, 90), Vector2(380, 80), Vector2(-180, 260), Vector2(190, 250), Vector2(-520, -250), Vector2(520, 250)]
	var seed_value := absi(int(map_data.get("mapId", 1)))
	for index in range(mini(positions.size(), candidates.size())):
		var candidate: Dictionary = candidates[(seed_value + index * 17) % candidates.size()]
		_spawn_enemy(candidate, positions[index], false)
	var spawned_boss_bases := {}
	var boss_offset := 0
	for boss: Variant in GameData.get_bosses_for_map(map_data):
		if not boss is Dictionary:
			continue
		var base_name := str(boss.get("baseName", boss.get("name", "Boss")))
		if spawned_boss_bases.has(base_name):
			continue
		spawned_boss_bases[base_name] = true
		_spawn_enemy(boss, Vector2(650 + boss_offset * 120, -260 + boss_offset * 110), true)
		boss_offset += 1
		if boss_offset >= 2:
			break
	_spawn_portal(Vector2(0, 390), "比奇城", "返回比奇城（临时门点）")


func _spawn_editor_runtime_content(content: Dictionary) -> void:
	_active_safe_zones = content.get("safe_areas", []).duplicate(true)
	for spawn: Dictionary in content.get("spawns", []):
		var monster := GameData.get_monster_by_id(int(spawn.get("monster_id",-1)))
		if monster.is_empty():monster=GameData.get_monster(str(spawn.get("name","")))
		if not monster.is_empty():
			var count:=mini(int(spawn.get("count",1)),int(spawn.get("max_alive",spawn.get("count",1))))
			var center:Vector2=spawn.get("position",Vector2.ZERO);var radius:=float(spawn.get("radius_tiles",0))*20.0
			for copy_index in maxi(1,count):
				var offset:=Vector2.ZERO if count<=1 else Vector2.from_angle(float(copy_index)*TAU/float(count))*minf(radius,32.0+float(copy_index)*12.0)
				var raw_group: Dictionary = spawn.get("spawn_group", {})
				var group_id := str(spawn.get(
					"spawnGroupId",
					raw_group.get("id", "editor:%d:%d" % [current_map_id, int(content.get("spawns", []).find(spawn))])
				))
				_spawn_enemy(
					monster,
					center + offset,
					false,
					float(spawn.get("respawn_seconds", 60)),
					{
						"spawn_group_id": group_id,
						"spawn_slot_id": "%s:%d" % [group_id, copy_index],
						"respawn_evidence": spawn.get("respawnEvidence", {"status": "map_editor_authored"}),
						"respawn_random_seconds": float(spawn.get("respawn_random_seconds", 0.0)),
					}
				)
	for spawn: Dictionary in content.get("bosses", []):
		var boss := GameData.get_monster_by_id(
			int(spawn.get("monster_id", -1))
		)
		if boss.is_empty():
			boss = GameData.get_monster(str(spawn.get("name", "")))
		if boss.is_empty():
			continue
		var raw_group: Dictionary = spawn.get("spawn_group", {})
		var group_id := str(raw_group.get(
			"spawn_group_id",
			"editor:%d:boss:%d" % [
				current_map_id,
				int(content.get("bosses", []).find(spawn)),
			]
		))
		_spawn_enemy(
			boss,
			spawn.get("position", Vector2.ZERO),
			true,
			float(spawn.get("respawn_seconds", DEFAULT_BOSS_RESPAWN_SECONDS)),
			{
				"spawn_group_id": group_id,
				"spawn_slot_id": "%s:0" % group_id,
				"respawn_evidence": {
					"status": "map_editor_authored",
				},
			}
		)
	for npc_data: Dictionary in content.get("npcs", []):
		var role := str(npc_data.get("kind", "dialogue"))
		var name := str(npc_data.get("name", "NPC"))
		var stock_key := str(npc_data.get("stock", ""))
		var stock: Array = []
		match stock_key:
			"general": stock = _general_shop_stock()
			"starter_gear": stock = _starter_gear_stock()
			"books": stock = _build_skill_book_stock(PlayerState.profession)
		_spawn_npc(npc_data.get("position", Vector2.ZERO), name, role, stock, stock_key, int(npc_data.get("appearance", -1)), content.get("map_center_world", _current_map_center_world()))
	for portal: Dictionary in content.get("portals", []):
		_spawn_map_portal(
			portal.get("position", Vector2.ZERO),
			int(portal.get("target_map_id", -1)),
			str(portal.get("label", "地图入口")),
			portal
		)


func _spawn_authored_map_content(content: Dictionary) -> void:
	var camp_layout := _bich_camp_layout if current_map_id == 4 else {}
	var camp_home := _bich_home_world_position()
	for spawn: Variant in content.get("spawns", []):
		if not spawn is Dictionary:
			continue
		var monster := GameData.get_monster_by_id(int(spawn.get("monsterId", -1)))
		if monster.is_empty():
			monster = GameData.get_monster(str(spawn.get("name", "")))
		if not monster.is_empty():
			if spawn.has("display_name"):
				monster = monster.duplicate(true)
				monster["name"] = str(spawn.get("display_name", monster.get("name", "怪物")))
			var spawn_position: Vector2 = spawn.get("position", Vector2.ZERO)
			if current_map_id == 4:
				var copies := int(camp_layout.get("fieldSpawnCopies", 4))
				var radii: Array = camp_layout.get("fieldSpawnRadii", [940, 1180, 1460, 1740])
				var spawn_index := int(content.get("spawns", []).find(spawn))
				for copy_index in range(copies):
					var angle := float(spawn_index * copies + copy_index) * TAU / float(maxi(1, content.get("spawns", []).size() * copies))
					var radius := float(radii[copy_index % radii.size()])
					var group_id := str(spawn.get("spawnGroupId", "map:%d:spawn:%d" % [current_map_id, spawn_index]))
					_spawn_enemy(
						monster,
						camp_home + Vector2.RIGHT.rotated(angle) * radius,
						false,
						float(spawn.get("respawn_seconds", DEFAULT_NORMAL_RESPAWN_SECONDS)),
						{
							"spawn_group_id": group_id,
							"spawn_slot_id": "%s:%d" % [group_id, copy_index],
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
					"spawn_group_id": str(spawn.get("spawnGroupId", "")),
					"respawn_evidence": spawn.get("respawnEvidence", {}),
					"respawn_random_seconds": float(spawn.get("respawn_random_seconds", 0.0)),
				}
			)
	for boss_spawn: Variant in content.get("bosses", []):
		if not boss_spawn is Dictionary:
			continue
		var boss := GameData.get_monster_by_id(int(boss_spawn.get("monsterId", -1)))
		if boss.is_empty():
			boss = GameData.get_monster(str(boss_spawn.get("name", "")))
		if not boss.is_empty():
			_spawn_enemy(
				boss,
				boss_spawn.get("position", Vector2(560, 230)),
				true,
				float(boss_spawn.get("respawn_seconds", DEFAULT_BOSS_RESPAWN_SECONDS)),
				{
					"spawn_group_id": str(boss_spawn.get("spawnGroupId", "")),
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
			"books": stock = _build_skill_book_stock(PlayerState.profession)
		var npc_name := str(npc_data.get("name", "NPC"))
		var npc_position: Vector2 = npc_data.get("position", Vector2.ZERO)
		if current_map_id == 4 and camp_layout.get("npcSlots", {}).has(npc_name):
			npc_position = camp_home + GothicBichCampBuilderScript._vector(camp_layout.npcSlots[npc_name])
		_spawn_npc(npc_position, npc_name, str(npc_data.get("kind", "shop")), stock, str(npc_data.get("stock", "")), int(npc_data.get("appearance", -1)))
	if current_map_id == 4:
		_spawn_npc(camp_home + GothicBichCampBuilderScript._vector(camp_layout.npcSlots.get("仓库管理员", [-520, 185])), "仓库管理员", "warehouse")
	for portal: Variant in content.get("portals", []):
		if portal is Dictionary:
			_spawn_map_portal(portal.get("position", Vector2.ZERO), int(portal.get("target_map_id", -1)), str(portal.get("label", "地图入口")))


func _enforce_bich_safe_zone() -> void:
	if current_map_id != 4:
		return
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or not is_instance_valid(node):
			continue
		var legal_position := WorldSpatialRulesScript.project_outside_safe_zones(node.global_position, _active_safe_zones, node.collision_radius + 2.0)
		if legal_position != node.global_position:
			node.global_position = legal_position
			node.velocity = Vector2.ZERO


func _general_shop_stock() -> Array:
	return [
		{"name": "金创药(小量)", "price": 20, "description": "恢复生命值的基础药品。"},
		{"name": "魔法药(小量)", "price": 20, "description": "恢复魔法值的基础药品。"},
		{"name": "回城卷", "price": 100, "description": "返回服务端HomeMap=0的比奇省安全区。"},
	]


func _starter_gear_stock() -> Array:
	var names := ["木剑", "乌木剑", "青铜剑", "铁剑", "八荒", "凌风", "海魂", "偃月", "半月", "降魔", "轻型盔甲(男)", "中型盔甲(男)", "青铜头盔"]
	var stock: Array = []
	for item_name: String in names:
		var item := GameData.get_item(item_name)
		if item.is_empty():
			continue
		var required_level := int(item.get("reqLevel", 1) if item.get("reqLevel", null) != null else 1)
		stock.append({"name": item_name, "price": maxi(50, required_level * required_level * 3), "description": "%s级成长装备。" % required_level})
	return stock


func _mid_gear_stock() -> Array:
	var names := ["炼狱", "魔杖", "银蛇", "重盔甲(男)", "魔法长袍(男)", "灵魂战衣(男)", "骷髅头盔", "降妖除魔戒指"]
	var stock: Array = []
	for item_name: String in names:
		var item := GameData.get_item(item_name)
		if not item.is_empty():
			var required_level := int(item.get("reqLevel", 25) if item.get("reqLevel", null) != null else 25)
			stock.append({"name": item_name, "price": maxi(1500, required_level * required_level * 8), "description": "盟重阶段成长装备。"})
	return stock


func _spawn_outskirts_content() -> void:
	var spawn_plan := [
		["稻草人", Vector2(-320, 170), false], ["多钩猫", Vector2(310, 125), false],
		["钉耙猫", Vector2(430, -35), false], ["森林雪人", Vector2(-470, -170), false],
		["食人花", Vector2(520, 160), false],
		["骷髅精灵", Vector2(670, 280), true],
	]
	for entry: Array in spawn_plan:
		var monster := GameData.get_monster(entry[0])
		if monster.is_empty():
			monster = {"monsterId": 0, "name": entry[0], "hp": 20, "attackMin": 1, "attackMax": 2}
		_spawn_enemy(monster, entry[1], entry[2])
	_spawn_portal(Vector2(560, -305), "比奇城", "进入比奇城")


func _spawn_city_content() -> void:
	var general_stock := [
		{"name": "金创药(小量)", "price": 20, "description": "恢复生命值的基础药品。"},
		{"name": "魔法药(小量)", "price": 20, "description": "恢复魔法值的基础药品。"},
		{"name": "木剑", "price": 50, "description": "新手武器。"},
		{"name": "布衣", "price": 80, "description": "新手防具。"},
	]
	var book_stock := _build_skill_book_stock(PlayerState.profession)
	_spawn_npc(Vector2(-250, -60), "杂货商", "shop", general_stock)
	_spawn_npc(Vector2(250, -60), "书店老板", "shop", book_stock)
	_spawn_npc(Vector2(0, -255), "武馆教头", "trainer")
	_spawn_npc(Vector2(-420, 210), "比奇老兵", "quest")
	_spawn_portal(Vector2(0, 390), "比奇郊外", "前往比奇郊外")


func _build_skill_book_stock(profession: String) -> Array:
	var stock: Array = []
	for skill: Variant in GameData.get_profession_skills(profession):
		if not skill is Dictionary:
			continue
		var required_level := int(skill.get("requiredCharacterLevel", 1))
		stock.append({
			"name": str(skill.get("skillName", "技能书")),
			"price": maxi(50, required_level * required_level / 2),
			"description": "%s%d级技能书。" % [profession, required_level],
		})
	return stock


func _spawn_npc(position: Vector2, display_name: String, kind: String, stock: Array = [], stock_key := "", appearance := -1, map_center_override: Variant = null) -> void:
	var npc := NPCActor.new()
	var map_center := _current_map_center_world() if map_center_override == null else Vector2(map_center_override)
	npc.setup(display_name, kind, stock, stock_key, appearance, map_center)
	npc.global_position = position
	add_child(npc)


func _current_map_center_world() -> Vector2:
	var source_size := Vector2i.ZERO
	if current_map_data.has("source_size"):
		source_size = Vector2i(current_map_data.get("source_size", Vector2i.ZERO))
	if source_size == Vector2i.ZERO and RegionContent.has_map(current_map_id):
		source_size = Vector2i(RegionContent.get_map_content(current_map_id).get("source_size", Vector2i.ZERO))
	if source_size != Vector2i.ZERO:
		return MapCoordinateMapperScript.source_to_world((Vector2(source_size) - Vector2.ONE) * 0.5, source_size)
	return Vector2.ZERO


func _spawn_portal(position: Vector2, target_zone: String, label_text: String) -> void:
	var portal := ZonePortal.new()
	portal.setup(target_zone, label_text)
	portal.global_position = position
	add_child(portal)


func _spawn_map_portal(
	position: Vector2,
	target_map_id: int,
	label_text: String,
	portal_data: Dictionary = {}
) -> void:
	var portal := ZonePortal.new()
	portal.setup_map(target_map_id, label_text, portal_data)
	portal.global_position = position
	add_child(portal)


func _spawn_enemy(
	monster_data: Dictionary,
	spawn_position: Vector2,
	is_boss: bool,
	respawn_seconds := -1.0,
	spawn_context: Dictionary = {}
) -> EnemyActor:
	_runtime_spawn_serial += 1
	var context := spawn_context.duplicate(true)
	var slot_id := str(context.get("spawn_slot_id", context.get("spawn_group_id", "")))
	if slot_id.is_empty():
		slot_id = "runtime:%d:%d" % [_zone_generation, _runtime_spawn_serial]
	context["spawn_slot_id"] = slot_id
	var effective_respawn := float(respawn_seconds)
	if effective_respawn <= 0.0:
		effective_respawn = DEFAULT_BOSS_RESPAWN_SECONDS if is_boss else DEFAULT_NORMAL_RESPAWN_SECONDS
	context["respawn_base_seconds"] = effective_respawn
	context["respawn_random_seconds"] = maxf(0.0, float(context.get("respawn_random_seconds", 0.0)))
	var enemy := EnemyActor.new()
	enemy.setup(monster_data, player, is_boss)
	enemy.global_position = spawn_position
	enemy.set_meta("spawn_position", spawn_position)
	enemy.set_meta("spawn_is_boss", is_boss)
	enemy.set_meta("respawn_seconds", effective_respawn)
	enemy.set_meta("respawn_random_seconds", float(context["respawn_random_seconds"]))
	enemy.set_meta("respawn_enabled", bool(context.get("respawn_enabled", true)))
	enemy.set_meta("spawn_slot_id", slot_id)
	enemy.set_meta("spawn_group_id", str(context.get("spawn_group_id", slot_id)))
	enemy.set_meta("spawn_context", context)
	enemy.set_meta("summoner_spawn_slot", str(context.get("summoner_spawn_slot", "")))
	enemy.set_meta("zone_generation", _zone_generation)
	enemy.set_meta("safe_zones", _active_safe_zones.duplicate(true))
	enemy.environment_blocker = background
	enemy.add_to_group("zone_content")
	enemy.died.connect(_on_enemy_died)
	enemy.target_requested.connect(_on_enemy_target_requested)
	enemy.summon_requested.connect(_on_boss_summon_requested)
	enemy.relocation_requested.connect(_on_boss_relocation_requested)
	add_child(enemy)
	return enemy


func _request_mobile_attack() -> void:
	if not player.can_start_attack():
		return
	var target := _ensure_combat_target()
	if is_instance_valid(target):
		player.request_attack_toward(player.global_position.direction_to(target.global_position))
		return
	player.request_attack_toward(player.facing)


func _on_mobile_attack_pressed() -> void:
	_mobile_attack_held = true
	_request_mobile_attack()


func _on_mobile_attack_released() -> void:
	_mobile_attack_held = false


func _ensure_combat_target(excluded: EnemyActor = null, maximum_distance := TargetingSystem.DEFAULT_SEARCH_RADIUS) -> EnemyActor:
	if auto_target_enabled:
		return _refresh_auto_target(maximum_distance, excluded)
	if not TargetingSystem.is_valid_target(locked_target, player.global_position) or locked_target == excluded:
		return null
	return locked_target


func _refresh_auto_target(maximum_distance := TargetingSystem.DEFAULT_SEARCH_RADIUS, excluded: EnemyActor = null) -> EnemyActor:
	var selected := TargetingRuntime.select_auto(get_tree().get_nodes_in_group("enemies"), player.global_position, player.facing, excluded, maximum_distance) as EnemyActor
	_set_locked_target(selected, false)
	return locked_target


func _set_locked_target(target: EnemyActor, manual := false) -> void:
	if is_instance_valid(locked_target) and locked_target != target:
		locked_target.set_targeted(false)
	locked_target = target
	manual_target_lock = manual and is_instance_valid(target)
	if is_instance_valid(locked_target):
		locked_target.set_targeted(true)
	_update_target_hud()


func _on_enemy_target_requested(enemy: EnemyActor) -> void:
	if TargetingSystem.is_valid_target(enemy, player.global_position):
		_set_locked_target(enemy, not auto_target_enabled)
		_face_locked_target()


func _update_boss_world_mechanics(delta: float) -> void:
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if not value is EnemyActor:
			continue
		var enemy := value as EnemyActor
		if not enemy.is_boss or enemy.is_queued_for_deletion():
			continue
		var relocation: Dictionary = enemy.boss_rule.get("mechanics", {}).get("surroundedRelocation", {})
		if not bool(relocation.get("enabled", false)):
			continue
		var remaining := float(enemy.get_meta("relocation_check_remaining", 0.0)) - delta
		if remaining > 0.0:
			enemy.set_meta("relocation_check_remaining", remaining)
			continue
		enemy.set_meta("relocation_check_remaining", maxf(0.25, float(relocation.get("checkSeconds", 10.0))))
		enemy.request_surrounded_relocation(_blocking_neighbor_count(enemy))


func _blocking_neighbor_count(enemy: EnemyActor) -> int:
	var seen: Dictionary = {}
	var count := 0
	var blocking_radius := maxf(ArtSpec.TILE_SIZE * 1.65, enemy.collision_radius * 2.5)
	var candidates: Array = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("combat_targets")
	candidates.append(player)
	for value: Variant in candidates:
		if not value is Node2D or value == enemy or not is_instance_valid(value):
			continue
		var node := value as Node2D
		var instance_key := str(node.get_instance_id())
		if seen.has(instance_key) or node.global_position.distance_to(enemy.global_position) > blocking_radius:
			continue
		seen[instance_key] = true
		count += 1
	return count


func _on_boss_summon_requested(enemy: EnemyActor, monster_ids: Array, count: int, max_active: int) -> void:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or monster_ids.is_empty():
		return
	if int(enemy.get_meta("zone_generation", -1)) != _zone_generation:
		return
	var owner_slot := str(enemy.get_meta("spawn_slot_id", ""))
	var active := 0
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor and not value.is_queued_for_deletion():
			if str(value.get_meta("summoner_spawn_slot", "")) == owner_slot:
				active += 1
	var allowed := mini(maxi(0, count), maxi(0, max_active - active))
	for index in range(allowed):
		var monster_id := int(monster_ids[index % monster_ids.size()])
		var monster := GameData.get_monster_by_id(monster_id)
		if monster.is_empty():
			continue
		var landing := _find_valid_enemy_landing(
			enemy.global_position,
			ArtSpec.TILE_SIZE * 1.5,
			ArtSpec.TILE_SIZE * 6.0,
			ArtSpec.MONSTER_COLLISION_RADIUS,
			null
		)
		if landing == enemy.global_position:
			continue
		_spawn_enemy(
			monster,
			landing,
			false,
			DEFAULT_NORMAL_RESPAWN_SECONDS,
			{
				"spawn_group_id": "%s:summons" % owner_slot,
				"respawn_enabled": false,
				"summoner_spawn_slot": owner_slot,
				"summon_monster_id": monster_id,
			}
		)


func _on_boss_relocation_requested(enemy: EnemyActor, radius_cells: int) -> void:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return
	if int(enemy.get_meta("zone_generation", -1)) != _zone_generation:
		return
	var destination := _find_valid_enemy_landing(
		enemy.global_position,
		ArtSpec.TILE_SIZE * 1.5,
		maxf(ArtSpec.TILE_SIZE * 1.5, float(radius_cells) * ArtSpec.TILE_SIZE),
		enemy.collision_radius,
		enemy
	)
	if destination == enemy.global_position:
		return
	enemy.global_position = destination
	enemy.velocity = Vector2.ZERO


func _find_valid_enemy_landing(
	origin: Vector2,
	minimum_distance: float,
	maximum_distance: float,
	radius: float,
	ignored_enemy: EnemyActor
) -> Vector2:
	for _attempt in range(96):
		var candidate := origin + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(minimum_distance, maximum_distance)
		if WorldSpatialRulesScript.point_inside_safe_zones(candidate, _active_safe_zones):
			continue
		if WorldSpatialRulesScript.environment_blocks_actor(background, candidate, radius):
			continue
		if is_instance_valid(player) and player.global_position.distance_to(candidate) < radius + ArtSpec.PLAYER_COLLISION_RADIUS + 12.0:
			continue
		var occupied := false
		for value: Variant in get_tree().get_nodes_in_group("enemies"):
			if not value is EnemyActor or value == ignored_enemy or value.is_queued_for_deletion():
				continue
			var other := value as EnemyActor
			if other.global_position.distance_to(candidate) < radius + other.collision_radius + 6.0:
				occupied = true
				break
		if not occupied:
			return candidate
	return origin


func _cycle_target() -> void:
	if auto_target_enabled:
		hud.show_message("关闭自动选怪后才能手动换敌")
		return
	var candidates := TargetingRuntime.front_targets(get_tree().get_nodes_in_group("enemies"), player.global_position, player.facing)
	if candidates.is_empty():
		hud.show_message("人物正面没有可切换目标")
		return
	var next_index := 0
	var current_index := candidates.find(locked_target)
	if current_index >= 0:
		next_index = (current_index + 1) % candidates.size()
	_set_locked_target(candidates[next_index] as EnemyActor, true)
	_face_locked_target()


func _set_auto_target_enabled(enabled: bool) -> void:
	auto_target_enabled = enabled
	hud.set_auto_target_enabled(enabled)
	if enabled:
		_cancel_target()
	else:
		manual_target_lock = is_instance_valid(locked_target)
		_update_target_hud()


func _on_player_moved(_position: Vector2, _facing: Vector2) -> void:
	# 自动模式只在攻击/攻击技能按下时选怪；移动立即释放自动锁定。
	if auto_target_enabled and is_instance_valid(locked_target):
		_cancel_target()


func _on_player_death_requested() -> void:
	_cancel_target()
	var accepted := travel_to_service_home(
		false,
		false,
		"比奇省",
		Callable(self, "_finish_death_revival")
	)
	if not accepted:
		call_deferred("_on_player_death_requested")


func _finish_death_revival() -> void:
	player.global_position = _bich_home_world_position()
	player.velocity = Vector2.ZERO
	background.set_focus_position(player.global_position)
	PlayerState.update_world_location(current_map_id, player.global_position)
	PlayerState.save_game()
	if hud != null:
		hud.show_message("你已在最近的城镇复活", 2.0)


func _cancel_target() -> void:
	if is_instance_valid(locked_target):
		locked_target.set_targeted(false)
	locked_target = null
	manual_target_lock = false
	if is_instance_valid(hud):
		hud.update_target("", 0, 0, false, auto_target_enabled)


func _validate_locked_target() -> void:
	if locked_target != null and not TargetingSystem.is_valid_target(locked_target, player.global_position):
		_cancel_target()


func _face_locked_target() -> Vector2:
	if not TargetingSystem.is_valid_target(locked_target, player.global_position):
		return player.facing.normalized()
	var direction := player.global_position.direction_to(locked_target.global_position)
	if direction.length_squared() > 0.01:
		direction = CombatRuntime.face_target(player, locked_target)
	return direction


func _update_target_hud() -> void:
	if not is_instance_valid(hud):
		return
	if TargetingSystem.is_valid_target(locked_target, player.global_position):
		hud.update_target(locked_target.display_name, locked_target.current_hp, locked_target.max_hp, manual_target_lock, auto_target_enabled)
	else:
		hud.update_target("", 0, 0, false, auto_target_enabled)


func _try_interact() -> void:
	var nearest: Node2D
	var nearest_distance := 105.0
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not node is Node2D:
			continue
		var distance := player.global_position.distance_to(node.global_position)
		if distance < nearest_distance:
			nearest = node
			nearest_distance = distance
	if nearest == null:
		hud.show_message("附近没有可交互目标")
		return
	nearest.interact(self)


func _use_quick_slot(index: int) -> void:
	if index < 0 or index >= PlayerState.quick_slots.size():
		return
	var skill_name := PlayerState.quick_slots[index]
	if skill_name.is_empty():
		hud.show_message("快捷栏%d为空" % (index + 1))
		return
	var learned_level := PlayerState.effective_skill_level(skill_name)
	var profile := ProfessionRules.skill_combat_profile(skill_name, learned_level)
	if _skill_needs_target(str(profile.get("cast_type", "melee"))):
		_ensure_combat_target(null, float(profile.get("search_range", TargetingSystem.DEFAULT_SEARCH_RADIUS)))
		_face_locked_target()
	if not player.request_skill(skill_name):
		hud.show_message("技能冷却中或魔法不足")


func _on_player_attack(origin: Vector2, direction: Vector2, damage: int) -> void:
	var context := player.consume_attack_context()
	var mode := str(context.get("mode", "normal"))
	var level := int(context.get("skill_level", 0))
	var primary := _physical_primary_target(origin, direction, 105.0)
	var hit_any := false
	if primary != null:
		var primary_damage := damage
		if mode == "slaying":
			primary_damage = WarriorCombatMath.slaying_damage(damage, level)
		elif mode == "fire":
			primary_damage = WarriorCombatMath.fire_sword_damage(damage, level)
		hit_any = _apply_physical_hit(primary, primary_damage)
	if mode == "thrust":
		var second := _thrust_secondary_target(origin, direction, primary)
		if second != null:
			hit_any = _apply_physical_hit(second, WarriorCombatMath.thrust_secondary_damage(damage, level)) or hit_any
	elif mode == "half_moon":
		for secondary: EnemyActor in _half_moon_targets(origin, direction, primary):
			hit_any = _apply_physical_hit(secondary, WarriorCombatMath.half_moon_secondary_damage(damage, level)) or hit_any
	_show_attack_flash(origin, direction, hit_any, Color(1.0, 0.72, 0.25))


func _on_special_action_pressed(effect_id: String) -> void:
	if not PlayerState.has_special_effect(effect_id):
		hud.show_message("特殊装备已失效")
		return
	match effect_id:
		"teleport":
			if _try_safe_ring_teleport():
				hud.show_message("传送戒指：安全位移")
			else:
				hud.show_message("前方没有合法传送落点")
		"flame_skill":
			if not player.spend_mana(5):
				hud.show_message("火球需要5点魔法")
				return
			var direction := _face_locked_target()
			if direction == Vector2.ZERO:
				direction = player.facing.normalized()
			var low := maxi(1, int(PlayerState.computed_stats.get("magic_min", 0)))
			var high := maxi(low, int(PlayerState.computed_stats.get("magic_max", low)))
			_spawn_projectile(player.global_position, direction, _rng.randi_range(low, high), 360.0, Color(1.0, 0.30, 0.08))
			hud.show_message("火焰戒指：火球")
		"recovery_skill":
			if not player.spend_mana(5):
				hud.show_message("治愈需要5点魔法")
				return
			var amount := maxi(12, int(PlayerState.level / 2) + int(PlayerState.computed_stats.get("tao_max", 0)) * 2)
			player.restore_health(amount)
			hud.show_message("防御戒指：恢复%d生命" % amount)


func _try_safe_ring_teleport() -> bool:
	var direction := player.facing.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	for distance: float in [180.0, 144.0, 108.0, 72.0, 36.0]:
		var motion := direction * distance
		if not player.test_move(player.global_transform, motion):
			player.global_position += motion
			player.velocity = Vector2.ZERO
			player.movement_performed.emit(player.global_position, player.facing)
			return true
	return false


func _on_warrior_skill_state_changed(_skill_name: String, _enabled: bool, message: String) -> void:
	if hud != null:
		hud.show_message(message, 1.5)
		hud.update_warrior_states(player.warrior_state_snapshot())


func _on_player_skill(skill_name: String, origin: Vector2, direction: Vector2, damage: int) -> void:
	var learned_level := PlayerState.effective_skill_level(skill_name)
	var profile := ProfessionRules.skill_combat_profile(skill_name, learned_level)
	if profile.is_empty():
		hud.show_message("技能运行时尚未登记：%s" % skill_name)
		return
	var cast_type := str(profile.get("cast_type", "melee"))
	if _skill_needs_target(cast_type):
		_ensure_combat_target()
		direction = _face_locked_target()
	if skill_name == "野蛮冲撞" and PlayerState.profession == "战士":
		var rushed := _execute_wild_rush(direction, learned_level)
		_show_attack_flash(origin, direction, rushed, Color(0.96, 0.62, 0.18))
		hud.show_message("野蛮冲撞" if rushed else "野蛮冲撞受阻", 1.0)
		return
	var multiplier := float(profile.get("multiplier", 1.0))
	var attack_range := float(profile.get("range", 105.0))
	var radial := cast_type in ["area", "ground_dot"]
	var effect_color := Color(1.0, 0.22, 0.05) if PlayerState.profession == "战士" else (Color(0.28, 0.62, 1.0) if PlayerState.profession == "法师" else Color(0.45, 0.92, 0.55))
	var final_damage := WarriorCombatMath.active_skill_damage(skill_name, damage, learned_level) if PlayerState.profession == "战士" else maxi(1, int(round(damage * multiplier)))
	var hit_any := false
	match cast_type:
		"dash": player.global_position += direction * 92.0
		"teleport": player.global_position += direction * attack_range
		"heal", "heal_area":
			player.restore_health(final_damage)
			multiplier = 0.0
		"projectile", "execute":
			_spawn_projectile(origin, direction, final_damage, attack_range, effect_color)
			multiplier = 0.0
			hit_any = true
		"poison":
			_spawn_projectile(origin, direction, final_damage, attack_range, effect_color, "poison", maxi(1, int(final_damage / 3)), 8.0)
			multiplier = 0.0
			hit_any = true
		"control":
			_spawn_projectile(origin, direction, 0, attack_range, effect_color, "charm", 0, 6.0)
			multiplier = 0.0
			hit_any = true
		"ground_dot":
			_spawn_ground_effect(origin + direction * minf(attack_range, 175.0), final_damage, 74.0, 5.0, effect_color)
			multiplier = 0.0
			hit_any = true
		"knockback":
			for node: Node in get_tree().get_nodes_in_group("enemies"):
				if node is EnemyActor and node.global_position.distance_to(origin) <= attack_range:
					node.global_position += (node.global_position - origin).normalized() * 80.0
			multiplier = 0.0
		"shield":
			player.apply_magic_shield(12.0, 0.35)
			multiplier = 0.0
		"stealth", "stealth_area":
			player.apply_stealth(10.0)
			multiplier = 0.0
		"magic_defense_buff", "defense_buff":
			player.apply_defense_buff(15.0, maxi(1, int(PlayerState.level / 8)))
			multiplier = 0.0
		"root_area":
			for node: Node in get_tree().get_nodes_in_group("enemies"):
				if node is EnemyActor and node.global_position.distance_to(origin + direction * 120.0) <= 115.0:
					node.apply_control(5.0)
			multiplier = 0.0
		"summon":
			_spawn_summon("神兽" if skill_name == "召唤神兽" else "骷髅", maxi(PlayerState.level, damage))
			multiplier = 0.0
		"inspect":
			var inspected := _nearest_enemy(origin, attack_range)
			if inspected != null:
				hud.show_message("%s：生命%d/%d" % [inspected.display_name, inspected.current_hp, inspected.max_hp], 2.0)
			multiplier = 0.0
	if multiplier > 0.0:
		hit_any = _damage_enemies(origin, direction, final_damage, radial, attack_range, PlayerState.profession == "战士")
	_show_attack_flash(origin, direction, hit_any, effect_color)
	hud.show_message("施放：%s" % skill_name, 1.0)


func _skill_needs_target(cast_type: String) -> bool:
	return cast_type not in ["passive", "heal", "heal_area", "shield", "stealth", "stealth_area", "magic_defense_buff", "defense_buff", "summon", "teleport"]


func _spawn_projectile(origin: Vector2, direction: Vector2, damage: int, travel_range: float, color: Color, effect := "damage", effect_strength := 0, effect_duration := 0.0) -> void:
	var projectile := SkillProjectile.new()
	projectile.setup(origin + direction * 24.0, direction, damage, travel_range, color, effect, effect_strength, effect_duration)
	add_child(projectile)


func _spawn_ground_effect(position: Vector2, damage: int, radius: float, duration: float, color: Color) -> void:
	var ground_effect := GroundSkillEffect.new()
	ground_effect.setup(position, damage, radius, duration, color)
	add_child(ground_effect)


func _spawn_summon(summon_name: String, power: int) -> void:
	for node: Node in get_tree().get_nodes_in_group("summons"):
		if node is SummonActor and node.owner_player == player:
			node.queue_free()
	var summon := SummonActor.new()
	summon.setup(player, summon_name, power)
	summon.global_position = player.global_position + player.facing.orthogonal() * 42.0
	add_child(summon)


func _nearest_enemy(origin: Vector2, maximum_distance: float) -> EnemyActor:
	var nearest: EnemyActor
	var nearest_distance := maximum_distance
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion():
			continue
		var distance := origin.distance_to(node.global_position)
		if distance < nearest_distance:
			nearest = node
			nearest_distance = distance
	return nearest


func _damage_enemies(origin: Vector2, direction: Vector2, damage: int, radial: bool, attack_range := 105.0, physical_accuracy := false) -> bool:
	var hit_any := false
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion():
			continue
		var offset: Vector2 = node.global_position - origin
		var in_arc := offset.normalized().dot(direction) > -0.05 or offset.length() < 42.0
		if offset.length() <= attack_range and (radial or in_arc):
			if physical_accuracy and not PlayerState.test_mode:
				var accuracy := int(PlayerState.computed_stats.get("accuracy", WarriorCombatMath.BASE_HIT))
				if not WarriorCombatMath.roll_hit(accuracy, node.agility, _rng):
					continue
			node.take_damage(damage)
			hit_any = true
	return hit_any


func _physical_primary_target(origin: Vector2, direction: Vector2, maximum_distance: float) -> EnemyActor:
	if TargetingSystem.is_valid_target(locked_target, origin):
		var locked_offset := locked_target.global_position - origin
		if locked_offset.length() <= maximum_distance and (locked_offset.normalized().dot(direction) > -0.05 or locked_offset.length() < 42.0):
			return locked_target
	var nearest: EnemyActor
	var nearest_distance := maximum_distance
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion():
			continue
		var offset: Vector2 = node.global_position - origin
		if offset.length() <= nearest_distance and offset.normalized().dot(direction) > 0.25:
			nearest = node
			nearest_distance = offset.length()
	return nearest


func _apply_physical_hit(enemy: EnemyActor, damage: int) -> bool:
	if enemy == null or enemy.is_queued_for_deletion():
		return false
	if not PlayerState.test_mode:
		var accuracy := int(PlayerState.computed_stats.get("accuracy", WarriorCombatMath.BASE_HIT))
		if not WarriorCombatMath.roll_hit(accuracy, enemy.agility, _rng):
			return false
	enemy.take_damage(maxi(1, damage), player)
	var life_steal_percent := int(PlayerState.computed_stats.get("life_steal_percent", 0))
	var recovered := int(float(maxi(1, damage)) * float(life_steal_percent) / 100.0)
	if recovered >= 2:
		player.restore_health(recovered)
	if PlayerState.has_special_effect("paralysis") and EquipmentRulesScript.paralysis_succeeds(enemy.anti_poison, _rng.randi_range(0, maxi(1, enemy.anti_poison + 5) - 1)):
		enemy.apply_control(5.0)
	return true


func _thrust_secondary_target(origin: Vector2, direction: Vector2, excluded: EnemyActor) -> EnemyActor:
	var result: EnemyActor
	var nearest_projection := INF
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node == excluded or node.is_queued_for_deletion():
			continue
		var offset: Vector2 = node.global_position - origin
		var projection := offset.dot(direction)
		var side_distance := absf(offset.cross(direction))
		if projection >= 105.0 and projection <= 195.0 and side_distance <= 34.0 and projection < nearest_projection:
			result = node
			nearest_projection = projection
	return result


func _half_moon_targets(origin: Vector2, direction: Vector2, excluded: EnemyActor) -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	for offset_index: int in WarriorCombatMath.HALF_MOON_DIRECTION_OFFSETS:
		var ray := direction.rotated(float(offset_index) * PI / 4.0)
		var cell_center := origin + ray * 74.0
		var best: EnemyActor
		var best_distance := 48.0
		for node: Node in get_tree().get_nodes_in_group("enemies"):
			if not node is EnemyActor or node == excluded or node in result or node.is_queued_for_deletion():
				continue
			var enemy := node as EnemyActor
			var distance: float = enemy.global_position.distance_to(cell_center)
			if distance < best_distance:
				best = enemy
				best_distance = distance
		if best != null:
			result.append(best)
	return result


func _execute_wild_rush(direction: Vector2, skill_level: int) -> bool:
	if direction.length_squared() < 0.01:
		return false
	var normalized := direction.normalized()
	var cell_distance := 50.0
	var max_cells := WarriorCombatMath.wild_rush_max_cells(skill_level)
	var moved := false
	for step in range(max_cells):
		var next_position := player.global_position + normalized * cell_distance
		if background.is_environment_point_blocked(next_position):
			break
		var blocker := _enemy_at_position(next_position, null)
		if blocker != null:
			var target_level := int(blocker.monster_data.get("level", blocker.level))
			var threshold := WarriorCombatMath.wild_rush_success_threshold(skill_level, PlayerState.level, target_level)
			if blocker.is_boss or threshold <= 0 or _rng.randi_range(0, 19) >= threshold:
				break
			var pushed_position := blocker.global_position + normalized * cell_distance
			if background.is_environment_point_blocked(pushed_position) or _enemy_at_position(pushed_position, blocker) != null:
				break
			blocker.global_position = pushed_position
			var remaining := maxi(0, max_cells - step - 1)
			var damage_base := (remaining + 1) * 10
			blocker.take_damage(damage_base + _rng.randi_range(0, damage_base - 1))
		player.global_position = next_position
		moved = true
	return moved


func _enemy_at_position(position: Vector2, excluded: EnemyActor) -> EnemyActor:
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node != excluded and not node.is_queued_for_deletion():
			if node.global_position.distance_to(position) <= node.collision_radius + ArtSpec.PLAYER_COLLISION_RADIUS:
				return node
	return null


func _show_attack_flash(origin: Vector2, direction: Vector2, hit: bool, color: Color) -> void:
	# Removed: the prototype drew a three-point V on every attack and also
	# overlaid the final Magic.wil skill effects.  Finished combat art is owned
	# by PlayerVisual; attacks without formal art deliberately show no fallback.
	return


func _on_enemy_died(enemy: EnemyActor, monster_data: Dictionary) -> void:
	if enemy == locked_target:
		locked_target = null
		manual_target_lock = false
		_update_target_hud()
	var death_position := enemy.global_position
	var spawn_position: Vector2 = enemy.get_meta("spawn_position", death_position)
	var was_boss: bool = enemy.get_meta("spawn_is_boss", false)
	var generation: int = enemy.get_meta("zone_generation", _zone_generation)
	var configured_respawn := float(enemy.get_meta("respawn_seconds", -1.0))
	var configured_random_respawn := float(enemy.get_meta("respawn_random_seconds", 0.0))
	var respawn_enabled := bool(enemy.get_meta("respawn_enabled", true))
	var spawn_context: Dictionary = enemy.get_meta("spawn_context", {}).duplicate(true)
	var monster_id := int(monster_data.get("monsterId", 0))
	PlayerState.record_kill(str(monster_data.get("name", "")))
	PlayerState.add_experience(int(monster_data.get("exp", 0)))
	var drop_roll := LootRuntime.roll_monster_drops(monster_id, str(monster_data.get("name", "")), _rng, 6)
	for item_name: String in drop_roll.get("items", []):
		_spawn_loot(item_name, death_position + Vector2(_rng.randf_range(-34, 34), _rng.randf_range(-18, 18)))
	if not bool(drop_roll.get("configured", false)) and _rng.randf() < 0.55:
		var common_loot := ["金币", "金创药(小量)", "魔法药(小量)", "木剑"]
		_spawn_loot(common_loot[_rng.randi_range(0, common_loot.size() - 1)], death_position)
	if not respawn_enabled:
		return
	var respawn_seconds := configured_respawn if configured_respawn > 0.0 else (DEFAULT_BOSS_RESPAWN_SECONDS if was_boss else DEFAULT_NORMAL_RESPAWN_SECONDS)
	var respawn_wait_seconds := respawn_seconds
	if configured_random_respawn > 0.0:
		respawn_wait_seconds = maxf(
			60.0,
			respawn_seconds - configured_random_respawn + _rng.randf_range(0.0, configured_random_respawn * 2.0)
		)
	_respawn_later(monster_data.duplicate(true), spawn_position, was_boss, respawn_wait_seconds, generation, spawn_context)


func _spawn_loot(item_name: String, position: Vector2) -> void:
	var loot := LootPickup.new()
	loot.setup(item_name, player)
	loot.global_position = position
	loot.add_to_group("zone_content")
	loot.collected.connect(_on_loot_collected)
	add_child(loot)


func _on_loot_collected(item_name: String) -> void:
	PlayerState.add_item(item_name)
	hud.show_loot(item_name)


func _on_player_stats_changed(current_hp: int, max_hp: int) -> void:
	if hud != null:
		hud.update_hp(current_hp, max_hp)


func _on_consumable_used(item_name: String) -> void:
	var item := GameData.get_item_record(item_name)
	var effect := str(item.get("useEffect", ""))
	var restored_hp := int(item.get("restoreHealth", 0))
	var restored_mp := int(item.get("restoreMana", 0))
	if effect == "delayed_restore" and (restored_hp > 0 or restored_mp > 0):
		player.queue_potion_restore(restored_hp, restored_mp)
	elif effect == "restore_both" and (restored_hp > 0 or restored_mp > 0):
		player.restore_health(restored_hp)
		player.restore_mana(restored_mp)
	elif effect == "temporary_buff":
		var duration := maxf(1.0, float(item.get("durationMinutes", 1)) * 60.0)
		var stats: Dictionary = item.get("stats", {})
		player.apply_defense_buff(duration, maxi(int(stats.get("MaxAC", 0)), int(stats.get("MaxMAC", 0))))
	elif "金创药" in item_name:
		player.restore_health(80 if "强效" in item_name else (35 if "中量" in item_name else 20))
	elif "魔法药" in item_name:
		player.restore_mana(100 if "强效" in item_name else (45 if "中量" in item_name else 30))
	elif "太阳水" in item_name:
		var amount := 100 if "强效" in item_name else 50
		player.restore_health(amount)
		player.restore_mana(amount)
	elif item_name == "疗伤药":
		player.restore_health(120)
	elif item_name == "万年雪霜":
		player.restore_health(150)
		player.restore_mana(150)
	elif "神水" in item_name:
		player.restore_health(30)
		player.restore_mana(30)
		player.apply_defense_buff(60.0, 2)
	elif item_name == "祝福油":
		hud.show_message(PlayerState.apply_blessing_oil(_rng))
		return
	hud.show_message("使用了%s" % item_name)


func _on_scroll_used(item_name: String) -> void:
	var item := GameData.get_item_record(item_name)
	var effect := str(item.get("useEffect", ""))
	if effect in ["town_teleport", "dungeon_escape"] or item_name == "回城卷":
		travel_to_service_home(false, false, "比奇省")
	elif effect == "random_teleport" or "随机" in item_name:
		var destination := _find_valid_random_teleport_position(player.global_position)
		if destination == player.global_position:
			hud.show_message("附近没有可用传送落点")
			return
		player.global_position = destination
	elif effect == "blessing_oil":
		hud.show_message(PlayerState.apply_blessing_oil(_rng))
		return
	elif effect == "repair_oil":
		hud.show_message(PlayerState.apply_weapon_repair_oil(false))
		return
	elif effect == "war_god_oil":
		hud.show_message(PlayerState.apply_weapon_repair_oil(true))
		return
	hud.show_message("使用了%s" % item_name)


func _find_valid_random_teleport_position(origin: Vector2) -> Vector2:
	# Every candidate goes through the same world boundary/obstacle contract as
	# movement and monster spawning.  A scroll can never bypass black borders.
	for _attempt in range(96):
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(96.0, 520.0)
		var candidate := origin + Vector2.from_angle(angle) * distance
		if WorldSpatialRulesScript.environment_blocks_actor(background, candidate, ArtSpec.PLAYER_COLLISION_RADIUS):
			continue
		var occupied := false
		for enemy_value: Variant in get_tree().get_nodes_in_group("enemies"):
			if enemy_value is Node2D and (enemy_value as Node2D).global_position.distance_to(candidate) < 34.0:
				occupied = true
				break
		if not occupied:
			return candidate
	return origin


func _respawn_later(
	monster_data: Dictionary,
	spawn_position: Vector2,
	is_boss: bool,
	seconds: float,
	generation: int,
	spawn_context: Dictionary = {}
) -> void:
	await get_tree().create_timer(seconds).timeout
	if not is_inside_tree() or generation != _zone_generation:
		return
	var slot_id := str(spawn_context.get("spawn_slot_id", ""))
	if not slot_id.is_empty() and _spawn_slot_is_alive(slot_id, generation):
		return
	_spawn_enemy(
		monster_data,
		spawn_position,
		is_boss,
		float(spawn_context.get("respawn_base_seconds", seconds)),
		spawn_context
	)


func _spawn_slot_is_alive(slot_id: String, generation: int) -> bool:
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor and not value.is_queued_for_deletion():
			if str(value.get_meta("spawn_slot_id", "")) == slot_id and int(value.get_meta("zone_generation", -1)) == generation:
				return true
	return false
