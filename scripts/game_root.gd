extends Node2D

const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")
const CombatResolutionRulesScript := preload("res://scripts/combat_resolution_rules.gd")
const MapCoordinateMapperScript := preload("res://scripts/map_coordinate_mapper.gd")
const GothicBichCampBuilderScript := preload("res://scripts/layers/presentation/gothic_bich_camp_builder.gd")
const MapEditorRuntimeBridgeScript := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const MapPortalRuntimeServiceScript := preload("res://scripts/map_editor/map_portal_runtime_service.gd")
const MapPortalTravelGuardScript := preload("res://scripts/map_editor/map_portal_travel_guard.gd")
const MapDiamondCameraConstraintScript := preload("res://scripts/map_editor/map_diamond_camera_constraint_service.gd")
const MapRuntimeCollisionGeometryScript := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const MonsterVisualScript := preload("res://scripts/monster_visual.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SystemMenuPanelScript := preload("res://scripts/system_menu_panel.gd")
const SkillLoadoutRulesScript := preload("res://scripts/skill_loadout_rules.gd")
const SkillInputPolicyScript := preload("res://scripts/skill_input_policy.gd")
const SkillRuntimeRouterScript := preload("res://scripts/skills/skill_runtime_router.gd")
const SkillCastRequestScript := preload("res://scripts/skills/skill_cast_request.gd")
const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const CombatDirectionSpaceScript := preload("res://scripts/skills/combat_direction_space.gd")
const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)
const CombatReleaseGeometryScript := preload("res://scripts/skills/combat_release_geometry.gd")
const WarriorMeleeGeometryScript := preload("res://scripts/skills/warrior_melee_geometry.gd")
const WarriorMeleeDiagnosticScript := preload("res://scripts/skills/warrior_melee_diagnostic.gd")
const CombatRuntimeServiceScript := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const CombatDiagnosticLogScript := preload("res://scripts/layers/runtime/combat_diagnostic_log.gd")
const CasterSkillRuntimeScript := preload("res://scripts/caster_skill_runtime.gd")
const CasterSpellGeometryScript := preload("res://scripts/skills/caster_spell_geometry.gd")
const SpellTargetLockPolicyScript := preload(
	"res://scripts/skills/spell_target_lock_policy.gd"
)
const DEFAULT_NORMAL_RESPAWN_SECONDS := 180.0
const DEFAULT_BOSS_RESPAWN_SECONDS := 3600.0
const MONSTER_PREFETCH_TIMEOUT_MSEC := 8000
const CANONICAL_MATERIAL_ITEMS := {
	"grey_powder": "灰色药粉",
	"yellow_powder": "黄色药粉",
	"amulet": "护身符",
}
const SKILL_PRODUCTION_ADAPTER_CONTRACT := "skills.production_adaptation.hardcore.v1"
const ATTACK_LOCK_CONTRACT := "combat.attack_lock.euclidean_gu.v2"
const ATTACK_LOCK_RANGE_GU := 10.0
const MELEE_LOCK_IMPACT_POLICY_ID := "combat.melee_lock.facing_priority_nonexclusive.v1"
const WILD_RUSH_SKILL_ID := "warrior.wild_rush"
const FIRE_WALL_SKILL_ID := "wizard.fire_wall"
const ATTACK_INPUT_TICKET_CONTRACT_ID := "combat.input.attack_ticket.touch_lifecycle.v1"
const MAX_BUFFERED_MOBILE_ATTACK_TICKETS := 32
const SKILL_INPUT_TICKET_CONTRACT_ID := (
	"combat.input.skill_ticket.cooldown_coalesce_hold_repeat.v2"
)
const SKILL_HOLD_REPEAT_THRESHOLD_MS := 300
const MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS := 0.10
const MAGIC_SHIELD_AUTO_REFRESH_EXPIRY_LEAD_SECONDS := 0.60
const SAFE_ZONE_ACTOR_PADDING_GU := 0.05
const BOSS_SURROUNDED_NEIGHBOR_RADIUS_GU := 1.65
const ACTOR_LANDING_CLEARANCE_GU := 0.25
const ENEMY_LANDING_CLEARANCE_GU := 0.125
const SAFE_RING_TELEPORT_DISTANCES_GU := [
	5.625,
	4.5,
	3.375,
	2.25,
	1.125,
]
const RANDOM_TELEPORT_MIN_DISTANCE_GU := 3.0
const RANDOM_TELEPORT_MAX_DISTANCE_GU := 16.25
const RANDOM_TELEPORT_ACTOR_CLEARANCE_GU := 0.25
const CASTER_GEOMETRY_VISUAL_CONTRACT_ID := "skills.visual.geometry_cells.world_projection.v1"
const CANONICAL_WIZARD_GEOMETRY_SKILLS := [
	"wizard.hellfire",
	"wizard.hell_lightning",
	"wizard.laser",
]
const CONTINUOUS_WIZARD_LINE_SKILLS := [
	"wizard.hellfire",
	"wizard.laser",
]

var player: PlayerCharacter
var _world_camera: Camera2D
var hud: GameHUD
var background: WorldBackground
var current_zone := ""
var current_map_id := -1
var current_map_data: Dictionary = {}
var _zone_generation := 0
var _rng := RandomNumberGenerator.new()
var locked_target: EnemyActor
var manual_target_lock := false
var magic_locked_target: EnemyActor
var manual_magic_target_lock := false
var auto_target_enabled := true
var _mobile_attack_held := false
var _queued_mobile_attack_tickets: Array[int] = []
var _active_mobile_attack_tokens: Dictionary = {}
var _legacy_mobile_attack_token := 0
var _next_synthetic_attack_token := -1
var _active_skill_inputs: Dictionary = {}
var _next_skill_input_sequence := 1
var _skill_input_retry_remaining := 0.0
var _keyboard_bound_skill_token := 0
var _magic_shield_auto_enabled := false
var _magic_shield_auto_retry_remaining := 0.0
var _queued_mobile_attacks: int:
	get:
		return _queued_mobile_attack_tickets.size()
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
var _monster_prefetch_enabled := true
var _last_monster_prefetch_status: Dictionary = {}
var _combat_runtime: Node = CombatRuntimeServiceScript.new()
var _canonical_cast_serial := 0
var _canonical_fire_charge_expires_ms := 0
var _skill_cast_target: EnemyActor
var _melee_diagnostic_serial := 0
var _pending_melee_diagnostic: Dictionary = {}
var _active_physical_hit_diagnostics: Array[Dictionary] = []


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
	player.restore_warrior_runtime_state(PlayerState.warrior_runtime_state_for_restore())

	_world_camera = Camera2D.new()
	_world_camera.name = "WorldCamera"
	_world_camera.position_smoothing_enabled = true
	_world_camera.position_smoothing_speed = 7.0
	_world_camera.zoom = Vector2.ONE * ArtSpec.CAMERA_ZOOM
	player.add_child(_world_camera)

	hud = GameHUD.new()
	hud.movement_changed.connect(player.set_touch_vector)
	hud.attack_input_started.connect(_on_mobile_attack_input_started)
	hud.attack_input_ended.connect(_on_mobile_attack_input_ended)
	hud.attack_input_cancelled.connect(_on_mobile_attack_input_cancelled)
	hud.skill_input_started.connect(_on_skill_input_started)
	hud.skill_input_ended.connect(_on_skill_input_ended)
	hud.skill_input_cancelled.connect(_on_skill_input_cancelled)
	hud.interact_pressed.connect(_try_interact)
	hud.skill_slot_pressed.connect(_use_skill_slot)
	hud.map_travel_requested.connect(travel_to_map)
	hud.target_switch_pressed.connect(_cycle_target)
	hud.auto_target_changed.connect(_set_auto_target_enabled)
	hud.special_action_pressed.connect(_on_special_action_pressed)
	hud.skill_button_assignment_requested.connect(_on_skill_button_assignment_requested)
	add_child(hud)
	hud.set_skill_button_assignments(PlayerState.skill_button_assignments_snapshot())
	player.resources_changed.connect(hud.update_resources)
	# 重登始终从服务端HomeMap出生。该规则不依赖退出回调，Android强杀后同样安全回城。
	travel_to_service_home(false, true)
	_record_player_world_location()
	_on_player_stats_changed(player.current_hp, player.max_hp)
	hud.update_warrior_states(player.warrior_state_snapshot())
	_build_system_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		call_deferred("_show_system_menu")
	elif what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if is_instance_valid(hud):
			hud.cancel_attack_inputs(&"application_interrupted")
			hud.cancel_skill_inputs(&"application_interrupted")
		_cancel_all_mobile_attack_inputs(true)
		_cancel_all_skill_inputs(true)
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_cancel_all_mobile_attack_inputs(true)
		_cancel_all_skill_inputs(true)
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
	_expire_canonical_fire_charge_if_needed()
	_constrain_player_foot_to_runtime_ground()
	background.set_focus_position(player.global_position)
	_update_world_camera_constraint(delta)
	_update_portal_arrival_guard()
	_enforce_bich_safe_zone()
	_update_boss_world_mechanics(delta)
	_record_player_world_location()
	_validate_locked_target()
	_update_target_hud()
	_process_skill_input_actions(delta)
	_process_magic_shield_auto_refresh(delta)
	_warrior_hud_timer -= delta
	_movement_target_refresh_remaining = maxf(0.0, _movement_target_refresh_remaining - delta)
	if _warrior_hud_timer <= 0.0:
		_warrior_hud_timer = 0.2
		PlayerState.apply_warrior_runtime_state(player.warrior_runtime_state_for_save())
		hud.update_warrior_states(player.warrior_state_snapshot())
	var bound_attack_skill := PlayerState.skill_name_for_slot(
		PlayerState.SKILL_SLOT_GROUP_ATTACK,
		0
	)
	if bound_attack_skill.is_empty():
		if Input.is_action_just_pressed("attack"):
			_submit_mobile_attack_ticket(_allocate_synthetic_attack_token())
		if not _queued_mobile_attack_tickets.is_empty():
			_drain_next_mobile_attack_ticket()
		elif _mobile_attack_held or Input.is_action_pressed("attack"):
			_request_mobile_attack()
	else:
		_queued_mobile_attack_tickets.clear()
		if Input.is_action_just_pressed("attack"):
			_keyboard_bound_skill_token = _allocate_synthetic_attack_token()
			_on_skill_input_started(
				PlayerState.SKILL_SLOT_GROUP_ATTACK,
				0,
				_keyboard_bound_skill_token,
				-4,
				&"keyboard"
			)
		if Input.is_action_just_released("attack") and _keyboard_bound_skill_token != 0:
			_on_skill_input_ended(
				PlayerState.SKILL_SLOT_GROUP_ATTACK,
				0,
				_keyboard_bound_skill_token,
				-4,
				&"keyboard"
			)
			_keyboard_bound_skill_token = 0
	if Input.is_action_just_pressed("interact"):
		_try_interact()
	for index in range(4):
		if Input.is_action_just_pressed("skill_%d" % (index + 1)):
			_use_quick_slot(index)


func _constrain_player_foot_to_runtime_ground() -> bool:
	if (
		not is_instance_valid(player)
		or not MapEditorRuntimeBridgeScript.has_runtime_map(current_map_id)
	):
		return false
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	var raw_size: Array = runtime.get("design", {}).get("design_size", [])
	if raw_size.size() != 2:
		return false
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var corrected := (
		MapRuntimeCollisionGeometryScript.project_player_foot_inside_boundary(
			player.global_position, design_size
		)
	)
	if corrected.is_equal_approx(player.global_position):
		return false
	player.global_position = corrected
	player.velocity = Vector2.ZERO
	PlayerState.update_world_location(
		current_map_id,
		corrected,
		_canonical_screen_px_to_ground_gu(corrected)
	)
	return true


func _update_world_camera_constraint(delta := 1.0 / 60.0) -> void:
	if not is_instance_valid(_world_camera) or not is_instance_valid(player):
		return
	var base_zoom := Vector2.ONE * ArtSpec.CAMERA_ZOOM
	if not MapEditorRuntimeBridgeScript.has_runtime_map(current_map_id):
		_world_camera.zoom = base_zoom
		_world_camera.position = Vector2.ZERO
		return
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	var raw_size: Array = runtime.get("design", {}).get("design_size", [])
	if raw_size.size() != 2:
		_world_camera.zoom = base_zoom
		_world_camera.position = Vector2.ZERO
		return
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var viewport_half := get_viewport().get_visible_rect().size * 0.5
	var target := MapDiamondCameraConstraintScript.resolve_soft_follow(
		design_size, viewport_half, base_zoom, player.global_position
	)
	var target_zoom: Vector2 = target.get("recommended_zoom", base_zoom)
	var zoom_alpha := 1.0 - exp(-6.0 * maxf(0.0, delta))
	var resolved_zoom := _world_camera.zoom.lerp(target_zoom, zoom_alpha)
	resolved_zoom.x = clampf(
		resolved_zoom.x, ArtSpec.CAMERA_ZOOM,
		MapDiamondCameraConstraintScript.DEFAULT_MAXIMUM_ZOOM
	)
	resolved_zoom.y = resolved_zoom.x
	# Re-resolve the position at the zoom actually displayed this frame. This
	# keeps the player inside the +/-14% screen band even while zoom is easing.
	var result := MapDiamondCameraConstraintScript.resolve_soft_follow(
		design_size, viewport_half, resolved_zoom, player.global_position,
		resolved_zoom.x
	)
	_world_camera.zoom = resolved_zoom
	_world_camera.global_position = Vector2(
		result.get("center", player.global_position)
	)


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
	PlayerState.apply_warrior_runtime_state(player.warrior_runtime_state_for_save())
	var home_map_id := GameData.service_home_runtime_map_id(false)
	var home_screen_position_px := _bich_home_screen_position_px()
	return PlayerState.save_safe_logout(
		home_map_id,
		home_screen_position_px,
		_ground_position_gu_for_map(home_map_id, home_screen_position_px)
	)


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
		player.global_position = _bich_home_screen_position_px()
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
		var service_map_id := GameData.service_home_map_id(red_name)
		return _begin_map_transition(
			operation, GameData.service_runtime_map_id(service_map_id)
		)
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
			player.global_position = _bich_home_screen_position_px()
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
		return _begin_map_transition(operation, map_id)
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
	var current_ground_gu := (
		MapEditorRuntimeBridgeScript.screen_position_px_to_ground_position_gu(
			current_runtime, player.global_position
		)
		if not current_runtime.is_empty()
		else Vector2.ZERO
	)
	if not MapPortalTravelGuardScript.can_activate(
		_portal_guard_state,
		_portal_guard_key(current_map_id, portal_id),
		Time.get_ticks_msec(),
		current_ground_gu,
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
		if _begin_map_transition(operation, target_map_id):
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
	var arrival_ground_gu := MapEditorRuntimeBridgeScript.cell_to_ground_position_gu(
		[target_tile.x, target_tile.y]
	)
	var arrival_position := (
		MapEditorRuntimeBridgeScript.ground_position_gu_to_screen_position_px(
			target_runtime,
			arrival_ground_gu
		)
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


func _begin_map_transition(operation: Callable, target_map_id := -1) -> bool:
	if _map_transition_in_progress or not operation.is_valid():
		return false
	_map_transition_serial += 1
	_active_map_transition_id = "map:%d:%d" % [
		Time.get_ticks_msec(),
		_map_transition_serial,
	]
	_map_transition_in_progress = true
	_run_map_transition(_active_map_transition_id, operation, target_map_id)
	return true


func _run_map_transition(
	transition_id: String,
	operation: Callable,
	target_map_id: int
) -> void:
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
	_last_monster_prefetch_status.clear()
	if _monster_prefetch_enabled and target_map_id >= 0:
		_last_monster_prefetch_status = MonsterVisualScript.begin_map_prefetch(
			_monster_ids_for_map(target_map_id)
		)
		var prefetch_deadline := (
			Time.get_ticks_msec() + MONSTER_PREFETCH_TIMEOUT_MSEC
		)
		while (
			_map_transition_in_progress
			and _active_map_transition_id == transition_id
			and not bool(_last_monster_prefetch_status.get("complete", false))
			and Time.get_ticks_msec() < prefetch_deadline
		):
			await get_tree().process_frame
			_last_monster_prefetch_status = MonsterVisualScript.poll_streaming()
	elif _monster_prefetch_enabled:
		MonsterVisualScript.release_map_pins()
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


func _monster_ids_for_map(map_id: int) -> Array[int]:
	var content: Dictionary = {}
	if MapEditorRuntimeBridgeScript.has_runtime_map(map_id):
		content = MapEditorRuntimeBridgeScript.game_content_for_map(map_id)
	if content.is_empty() and RegionContent.has_map(map_id):
		content = RegionContent.get_map_content(map_id)
	var result: Array[int] = []
	var seen := {}
	for group_name: String in ["spawns", "bosses"]:
		for raw_entry: Variant in content.get(group_name, []):
			if not raw_entry is Dictionary:
				continue
			var entry: Dictionary = raw_entry
			var monster_id := int(entry.get(
				"monster_id", entry.get("monsterId", -1)
			))
			if monster_id < 0 or seen.has(monster_id):
				continue
			seen[monster_id] = true
			result.append(monster_id)
	return result


func _valid_portal_request(request: Dictionary) -> bool:
	return (
		bool(request.get("ok", false))
		and int(request.get("target_map_id", -1)) >= 0
		and not str(request.get("target_map_key", "")).is_empty()
		and not str(request.get("target_portal_id", "")).is_empty()
		and str(request.get("arrival_guard_policy_id", "")) == MapPortalTravelGuardScript.POLICY_ID
		and is_equal_approx(float(request.get("return_minimum_seconds", 0.0)), 3.0)
		and is_equal_approx(
			float(request.get("return_unlock_distance_gu", -1.0)),
			MapPortalTravelGuardScript.UNLOCK_DISTANCE_GU
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
		MapEditorRuntimeBridgeScript.screen_position_px_to_ground_position_gu(
			runtime,
			player.global_position
		)
	)


func route_arrival_position(destination_map_id: int, source_map_id: int) -> Vector2:
	if MapEditorRuntimeBridgeScript.has_runtime_map(destination_map_id):
		return MapEditorRuntimeBridgeScript.portal_screen_position_px(
			destination_map_id, "", source_map_id
		)
	var content := RegionContent.get_map_content(destination_map_id)
	for portal: Dictionary in content.get("portals", []):
		if int(portal.get("target_map_id", -1)) == source_map_id:
			var portal_screen_px: Vector2 = portal.get("position", Vector2.ZERO)
			var interior_target_screen_px := (
				_bich_home_screen_position_px()
				if destination_map_id == 4
				else Vector2.ZERO
			)
			var portal_ground_gu := (
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
					portal_screen_px
				)
			)
			var interior_target_ground_gu := (
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
					interior_target_screen_px
				)
			)
			var inward_direction_ground_gu := (
				GroundUnitSpaceScript.normalized_ground_direction(
					portal_ground_gu,
					interior_target_ground_gu
				)
			)
			var arrival_offset_gu := (
				CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
					140.0
				)
			)
			return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				portal_ground_gu + inward_direction_ground_gu * arrival_offset_gu
			)
	return _bich_home_screen_position_px() if destination_map_id == 4 else Vector2.ZERO


func route_next_target(map_id: int) -> Dictionary:
	var content := RegionContent.get_map_content(map_id)
	if map_id == 221 and not content.get("bosses", []).is_empty():
		return {"position": content.get("bosses", [])[0].get("position", Vector2.ZERO), "label": "骷髅精灵Boss房"}
	var portals: Array = content.get("portals", [])
	if not portals.is_empty():
		var portal: Dictionary = portals[-1]
		return {"position": portal.get("position", Vector2.ZERO), "label": str(portal.get("label", "区域出口"))}
	return {}


func _bich_home_screen_position_px() -> Vector2:
	var editor_home := MapEditorRuntimeBridgeScript.home_screen_position_px()
	if editor_home != Vector2.ZERO:
		return editor_home
	var content := RegionContent.get_map_content(4)
	return content.get("runtime_home_position", MapCoordinateMapperScript.source_to_world(Vector2(289, 618), Vector2i(700, 700)))


func _bich_portal_screen_position_px_to(target_map_id: int) -> Vector2:
	for portal: Dictionary in RegionContent.get_map_content(4).get("portals", []):
		if int(portal.get("target_map_id", -1)) == target_map_id:
			return portal.get("position", _bich_home_screen_position_px())
	return _bich_home_screen_position_px()


func _load_zone(zone_name: String, initial: bool, map_data: Dictionary) -> void:
	if zone_name == current_zone and not initial:
		if map_data.is_empty() or int(map_data.get("mapId", -1)) == current_map_id:
			return
	_zone_generation += 1
	_active_safe_zones.clear()
	_cancel_all_combat_targets()
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
		player.global_position = _bich_home_screen_position_px() if current_map_id == 4 else Vector2.ZERO
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
			var center_screen_px: Vector2 = spawn.get("screen_position_px", Vector2.ZERO)
			var radius_gu := maxf(0.0, float(spawn.get("radius_gu", 0.0)))
			for copy_index in maxi(1,count):
				var offset_ground_gu := Vector2.ZERO
				if count > 1 and radius_gu > 0.0:
					var radial_fraction := sqrt(
						float(copy_index + 1) / float(count)
					)
					offset_ground_gu = (
						Vector2.from_angle(float(copy_index) * TAU / float(count))
						* radius_gu
						* radial_fraction
					)
				var offset_screen_px := (
					GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
						offset_ground_gu
					)
				)
				var raw_group: Dictionary = spawn.get("spawn_group", {})
				var group_id := str(spawn.get(
					"spawnGroupId",
					raw_group.get("id", "editor:%d:%d" % [current_map_id, int(content.get("spawns", []).find(spawn))])
				))
				_spawn_enemy(
					monster,
					center_screen_px + offset_screen_px,
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
			spawn.get("screen_position_px", Vector2.ZERO),
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
		_spawn_npc(npc_data.get("screen_position_px", Vector2.ZERO), name, role, stock, stock_key, int(npc_data.get("appearance", -1)), content.get("map_center_screen_position_px", _current_map_center_screen_position_px()))
	for portal: Dictionary in content.get("portals", []):
		_spawn_map_portal(
			portal.get("screen_position_px", Vector2.ZERO),
			int(portal.get("target_map_id", -1)),
			str(portal.get("label", "地图入口")),
			portal
		)


func _spawn_authored_map_content(content: Dictionary) -> void:
	var camp_layout := _bich_camp_layout if current_map_id == 4 else {}
	var camp_home := _bich_home_screen_position_px()
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
		var current_ground_gu := _canonical_screen_px_to_ground_gu(
			node.global_position
		)
		var padding_gu: float = (
			float(node.combat_radius_gu) + SAFE_ZONE_ACTOR_PADDING_GU
		)
		var legal_ground_gu := (
			WorldSpatialRulesScript.project_outside_safe_zones_ground_gu(
				current_ground_gu,
				_active_safe_zones,
				padding_gu
			)
		)
		if not legal_ground_gu.is_equal_approx(current_ground_gu):
			node.global_position = _canonical_ground_gu_to_screen_px(
				legal_ground_gu
			)
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
	var map_center := _current_map_center_screen_position_px() if map_center_override == null else Vector2(map_center_override)
	npc.setup(display_name, kind, stock, stock_key, appearance, map_center)
	npc.global_position = position
	add_child(npc)


func _current_map_center_screen_position_px() -> Vector2:
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


func _request_mobile_attack() -> bool:
	var target := _ensure_attack_locked_target()
	var facing_before := player.facing
	var touch_before := player.touch_vector
	var movement_was_active := player.movement_input_active
	if not player.can_start_attack():
		return false
	var attack_direction := player.facing.normalized()
	if is_instance_valid(target):
		attack_direction = _face_locked_target()
	var melee_mode := _selected_warrior_melee_mode()
	var target_instance_id := target.get_instance_id() if is_instance_valid(target) else 0
	var input_release_geometry := CombatReleaseGeometryScript.resolve(
		player.global_position,
		attack_direction,
		target_instance_id,
		target.global_position if is_instance_valid(target) else Vector2.ZERO,
		is_instance_valid(target),
		true,
		CombatReleaseGeometryScript.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
	)
	attack_direction = Vector2(
		input_release_geometry.get("direction_screen_px", attack_direction)
	).normalized()
	var input_has_hittable_target := _has_melee_hittable_target(
		attack_direction,
		melee_mode,
		input_release_geometry
	)
	var diagnostic := _build_melee_input_diagnostic(
		target,
		melee_mode,
		attack_direction,
		input_release_geometry,
		input_has_hittable_target,
		facing_before,
		touch_before,
		movement_was_active
	)
	var accepted := player.request_attack_toward(
		attack_direction,
		input_has_hittable_target,
		target_instance_id
	)
	if accepted:
		diagnostic["event"] = "attack_input_accepted"
		diagnostic["facing_after_input"] = player.facing
		diagnostic["facing_after_input_index"] = ArtSpec.direction_index(player.facing)
		_pending_melee_diagnostic = diagnostic.duplicate(true)
		CombatDiagnosticLogScript.record(diagnostic)
	else:
		diagnostic["event"] = "attack_input_rejected"
		diagnostic["reject_code"] = "PLAYER_REQUEST_REJECTED"
		CombatDiagnosticLogScript.record(diagnostic)
	return accepted


func _build_melee_input_diagnostic(
	target: EnemyActor,
	mode: String,
	attack_direction: Vector2,
	release_geometry: Dictionary,
	has_hittable_target: bool,
	facing_before: Vector2,
	touch_before: Vector2,
	movement_was_active: bool
) -> Dictionary:
	_melee_diagnostic_serial += 1
	var target_valid := is_instance_valid(target)
	var target_world := target.global_position if target_valid else Vector2.ZERO
	var target_ground_gu := (
		_canonical_screen_px_to_ground_gu(target_world)
		if target_valid
		else Vector2.ZERO
	)
	var input_direction_index := _melee_direction_index(
		attack_direction,
		release_geometry
	)
	var actor_ground_gu := _canonical_screen_px_to_ground_gu(player.global_position)
	var target_candidate := (
		WarriorMeleeDiagnosticScript.explain_footprint_candidate(
			actor_ground_gu,
			target_ground_gu,
			target.combat_radius_gu,
			input_direction_index,
			mode
		)
		if target_valid
		else {}
	)
	if target_valid:
		target_candidate["angle_quantization_audit"] = (
			WarriorMeleeDiagnosticScript.audit_ground_delta_gu(
				target_ground_gu - actor_ground_gu
			)
		)
	return {
		"action_id": "player:%d:melee:%d" % [
			player.get_instance_id(),
			_melee_diagnostic_serial,
		],
		"map_id": current_map_id,
		"requested_mode": mode,
		"actor_id": player.get_instance_id(),
		"actor_screen_px_at_input": player.global_position,
		"actor_ground_gu_at_input": actor_ground_gu,
		"locked_target_id": target.get_instance_id() if target_valid else 0,
		"locked_target_name": str(target.display_name) if target_valid else "",
		"target_screen_px_at_input": target_world,
		"target_ground_gu_at_input": target_ground_gu,
		"facing_before_input": facing_before,
		"facing_before_input_index": ArtSpec.direction_index(facing_before),
		"touch_vector_at_input": touch_before,
		"movement_input_active_at_input": movement_was_active,
		"attack_direction_screen_px_at_input": attack_direction,
		"attack_direction_index_at_input": input_direction_index,
		"attack_direction_tile_step_at_input": (
			WarriorMeleeGeometryScript.facing_tile_step(input_direction_index)
		),
		"direction_loop_audit_at_input": (
			WarriorMeleeDiagnosticScript.audit_direction(input_direction_index)
		),
		"locked_target_candidate_at_input": target_candidate,
		"expected_visual_row_at_input": ArtSpec.mir2_client_direction_row(attack_direction),
		"visual_row_before_input": player.visual.current_direction if player.visual != null else -1,
		"has_hittable_target_at_input": has_hittable_target,
		"release_policy_at_input": release_geometry.duplicate(true),
	}


func _request_primary_attack_action() -> void:
	var bound_skill := PlayerState.skill_name_for_slot(
		PlayerState.SKILL_SLOT_GROUP_ATTACK,
		0
	)
	if bound_skill.is_empty():
		_request_mobile_attack()
		return
	_use_skill_slot(PlayerState.SKILL_SLOT_GROUP_ATTACK, 0)


func _selected_warrior_melee_mode() -> String:
	if player.fire_sword_enabled:
		return WarriorMeleeGeometryScript.SKILL_FIRE
	if player.half_moon_enabled and PlayerState.is_skill_learned("warrior.half_moon"):
		return WarriorMeleeGeometryScript.SKILL_HALF_MOON
	if player.thrusting_enabled and PlayerState.is_skill_learned("warrior.thrusting"):
		return WarriorMeleeGeometryScript.SKILL_THRUST
	return WarriorMeleeGeometryScript.SKILL_NORMAL


func _has_melee_hittable_target(
	direction: Vector2,
	mode := "",
	release_geometry: Dictionary = {}
) -> bool:
	if direction.length_squared() <= 0.01:
		return false
	var resolved_mode := mode if not mode.is_empty() else _selected_warrior_melee_mode()
	var primary_targets := _physical_primary_targets(
		player.global_position,
		direction.normalized(),
		resolved_mode,
		release_geometry
	)
	if not primary_targets.is_empty():
		return true
	if resolved_mode == WarriorMeleeGeometryScript.SKILL_THRUST:
		return not _thrust_secondary_targets(
			player.global_position,
			direction.normalized(),
			primary_targets,
			release_geometry
		).is_empty()
	if resolved_mode == WarriorMeleeGeometryScript.SKILL_HALF_MOON:
		return not _half_moon_secondary_targets(
			player.global_position,
			direction.normalized(),
			primary_targets,
			release_geometry
		).is_empty()
	return false


func _allocate_synthetic_attack_token() -> int:
	var token := _next_synthetic_attack_token
	_next_synthetic_attack_token -= 1
	return token


func _submit_mobile_attack_ticket(press_token: int) -> void:
	if press_token == 0 or press_token in _queued_mobile_attack_tickets:
		return
	if _queued_mobile_attack_tickets.is_empty() and _request_mobile_attack():
		return
	if _queued_mobile_attack_tickets.size() >= MAX_BUFFERED_MOBILE_ATTACK_TICKETS:
		return
	_queued_mobile_attack_tickets.append(press_token)


func _drain_next_mobile_attack_ticket() -> bool:
	if _queued_mobile_attack_tickets.is_empty():
		return false
	if not _request_mobile_attack():
		return false
	_queued_mobile_attack_tickets.pop_front()
	return true


func _refresh_mobile_attack_held() -> void:
	_mobile_attack_held = false
	for value in _active_mobile_attack_tokens.values():
		if bool(value):
			_mobile_attack_held = true
			return


func _on_mobile_attack_input_started(
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if press_token == 0 or _active_mobile_attack_tokens.has(press_token):
		return
	var ordinary_attack := PlayerState.skill_name_for_slot(
		PlayerState.SKILL_SLOT_GROUP_ATTACK,
		0
	).is_empty()
	if not ordinary_attack:
		_on_skill_input_started(
			PlayerState.SKILL_SLOT_GROUP_ATTACK,
			0,
			press_token,
			touch_id,
			source
		)
		return
	_active_mobile_attack_tokens[press_token] = true
	_refresh_mobile_attack_held()
	if ordinary_attack:
		_submit_mobile_attack_ticket(press_token)
		return
	_queued_mobile_attack_tickets.clear()
	_request_primary_attack_action()


func _on_mobile_attack_input_ended(
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if not _active_mobile_attack_tokens.has(press_token):
		_on_skill_input_ended(
			PlayerState.SKILL_SLOT_GROUP_ATTACK,
			0,
			press_token,
			touch_id,
			source
		)
		return
	_active_mobile_attack_tokens.erase(press_token)
	_refresh_mobile_attack_held()


func _on_mobile_attack_input_cancelled(
	press_token: int,
	touch_id: int,
	source: StringName,
	reason: StringName
) -> void:
	if not _active_mobile_attack_tokens.has(press_token):
		_on_skill_input_cancelled(
			PlayerState.SKILL_SLOT_GROUP_ATTACK,
			0,
			press_token,
			touch_id,
			source,
			reason
		)
		return
	_active_mobile_attack_tokens.erase(press_token)
	_queued_mobile_attack_tickets.erase(press_token)
	_refresh_mobile_attack_held()


func _cancel_all_mobile_attack_inputs(clear_tickets := false) -> void:
	_active_mobile_attack_tokens.clear()
	_mobile_attack_held = false
	_legacy_mobile_attack_token = 0
	if clear_tickets:
		_queued_mobile_attack_tickets.clear()


func _skill_input_key(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int
) -> String:
	return "%s:%d:%d:%d" % [slot_group, slot_index, press_token, touch_id]


func _on_skill_input_started(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if press_token == 0:
		return
	var input_key := _skill_input_key(
		slot_group, slot_index, press_token, touch_id
	)
	if _active_skill_inputs.has(input_key):
		return
	var skill_name := PlayerState.skill_name_for_slot(slot_group, slot_index)
	if skill_name.is_empty():
		hud.show_message("技能栏为空")
		return
	var metadata := SkillInputPolicyScript.metadata(skill_name)
	if metadata.is_empty() or bool(metadata.get("passive", false)):
		return
	var entry := {
		"contract_id": SKILL_INPUT_TICKET_CONTRACT_ID,
		"input_key": input_key,
		"slot_group": slot_group,
		"slot_index": slot_index,
		"press_token": press_token,
		"touch_id": touch_id,
		"source": source,
		"skill_name": skill_name,
		"skill_id": str(metadata.get("skill_id", "")),
		"repeatable": bool(metadata.get("repeatable_offensive_spell", false)),
		"started_at_ms": Time.get_ticks_msec(),
		"sequence": _next_skill_input_sequence,
	}
	_next_skill_input_sequence += 1
	_active_skill_inputs[input_key] = entry
	if bool(metadata.get("toggle", false)):
		# Keep the physical input active until UP/CANCEL so duplicate DOWN events
		# from the same touch cannot flip a toggle twice.
		_handle_toggle_skill_input(skill_name)
		return
	_submit_skill_input_ticket(entry)


func _on_skill_input_ended(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	_source: StringName
) -> void:
	_active_skill_inputs.erase(
		_skill_input_key(slot_group, slot_index, press_token, touch_id)
	)


func _on_skill_input_cancelled(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	_source: StringName,
	_reason: StringName
) -> void:
	var input_key := _skill_input_key(
		slot_group, slot_index, press_token, touch_id
	)
	_active_skill_inputs.erase(input_key)


func _cancel_all_skill_inputs(clear_tickets := false) -> void:
	_active_skill_inputs.clear()
	_keyboard_bound_skill_token = 0
	# Kept as an API-compatible argument for callers that clear attack and skill
	# input together. Skill clicks are no longer buffered past their physical
	# lifetime, so there are no deferred skill tickets to clear.
	if clear_tickets:
		_skill_input_retry_remaining = 0.0


func _submit_skill_input_ticket(entry: Dictionary) -> void:
	# One physical DOWN makes exactly one immediate attempt. A busy cast gate
	# coalesces all additional taps during that interval instead of storing them
	# for forced release later. Continuous casting is owned exclusively by the
	# still-active press in _process_skill_input_actions().
	_try_release_skill(str(entry.get("skill_name", "")), true)


func _process_skill_input_actions(delta: float) -> void:
	_skill_input_retry_remaining = maxf(
		0.0, _skill_input_retry_remaining - delta
	)
	if _skill_input_retry_remaining > 0.0:
		return
	_skill_input_retry_remaining = 0.05
	var repeat_entry: Dictionary = {}
	var now_ms := Time.get_ticks_msec()
	for raw_entry: Variant in _active_skill_inputs.values():
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if not bool(entry.get("repeatable", false)):
			continue
		if (
			now_ms - int(entry.get("started_at_ms", now_ms))
			< SKILL_HOLD_REPEAT_THRESHOLD_MS
		):
			continue
		if (
			repeat_entry.is_empty()
			or int(entry.get("sequence", 0))
			< int(repeat_entry.get("sequence", 0))
		):
			repeat_entry = entry
	if not repeat_entry.is_empty():
		_try_release_skill(str(repeat_entry.get("skill_name", "")), false)


func _handle_toggle_skill_input(skill_name: String) -> void:
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name)
	if stable_skill_id != "wizard.magic_shield":
		_try_release_skill(skill_name, true)
		return
	_magic_shield_auto_enabled = not _magic_shield_auto_enabled
	if not _magic_shield_auto_enabled:
		hud.show_message("魔法盾自动补盾：关", 1.5)
		return
	hud.show_message("魔法盾自动补盾：开", 1.5)
	_magic_shield_auto_retry_remaining = 0.0
	_process_magic_shield_auto_refresh(
		MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS
	)


func _process_magic_shield_auto_refresh(delta: float) -> void:
	if not _magic_shield_auto_enabled or not is_instance_valid(player):
		return
	_magic_shield_auto_retry_remaining = maxf(
		0.0, _magic_shield_auto_retry_remaining - delta
	)
	if _magic_shield_auto_retry_remaining > 0.0:
		return
	_magic_shield_auto_retry_remaining = MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS
	if not player.magic_shield_requires_refresh(
		PlayerCharacter.MAGIC_SHIELD_AUTO_REFRESH_RATIO,
		MAGIC_SHIELD_AUTO_REFRESH_EXPIRY_LEAD_SECONDS
	):
		return
	_try_release_skill(
		SkillDataLoaderScript.display_name("wizard.magic_shield"),
		false
	)


func _on_mobile_attack_pressed() -> void:
	if _legacy_mobile_attack_token != 0:
		return
	_legacy_mobile_attack_token = _allocate_synthetic_attack_token()
	_on_mobile_attack_input_started(
		_legacy_mobile_attack_token,
		-3,
		&"legacy"
	)


func _on_mobile_attack_released() -> void:
	if _legacy_mobile_attack_token == 0:
		_cancel_all_mobile_attack_inputs(false)
		return
	var press_token := _legacy_mobile_attack_token
	_legacy_mobile_attack_token = 0
	_on_mobile_attack_input_ended(press_token, -3, &"legacy")


func _ensure_attack_locked_target(excluded: EnemyActor = null) -> EnemyActor:
	if _is_attack_target_in_range(locked_target) and locked_target != excluded:
		return locked_target
	if locked_target != null:
		_cancel_target()
	if not auto_target_enabled:
		return null
	var candidates := _attack_lock_candidates(excluded)
	_set_attack_locked_target(
		candidates[0] if not candidates.is_empty() else null,
		false
	)
	return locked_target


func _ensure_combat_target(
	excluded: EnemyActor = null,
	_maximum_range_gu := ATTACK_LOCK_RANGE_GU
) -> EnemyActor:
	return _ensure_attack_locked_target(excluded)


func _refresh_auto_target(
	_maximum_range_gu := ATTACK_LOCK_RANGE_GU,
	excluded: EnemyActor = null
) -> EnemyActor:
	var candidates := _attack_lock_candidates(excluded)
	_set_attack_locked_target(
		candidates[0] if not candidates.is_empty() else null,
		false
	)
	return locked_target


func _set_attack_locked_target(target: EnemyActor, manual := false) -> void:
	if target != null and not _is_attack_target_in_range(target):
		target = null
	locked_target = target
	manual_target_lock = manual and is_instance_valid(target)
	_refresh_target_highlights()
	_update_target_hud()


func _set_locked_target(target: EnemyActor, manual := false) -> void:
	_set_attack_locked_target(target, manual)


func _attack_lock_candidates(excluded: EnemyActor = null) -> Array[EnemyActor]:
	var ranked: Array[Dictionary] = []
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(
		player.global_position
	)
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if not value is EnemyActor:
			continue
		var enemy := value as EnemyActor
		if enemy == excluded or not _is_attack_target_in_range(enemy):
			continue
		var target_ground_gu := _canonical_screen_px_to_ground_gu(
			enemy.global_position
		)
		ranked.append({
			"target": enemy,
			"contract_id": ATTACK_LOCK_CONTRACT,
			"origin_ground_gu": origin_ground_gu,
			"target_ground_gu": target_ground_gu,
			"distance_squared_gu": GroundUnitSpaceScript.distance_squared_gu(
				origin_ground_gu,
				target_ground_gu
			),
			"instance_id": enemy.get_instance_id(),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance_squared_gu := float(
			a.get("distance_squared_gu", INF)
		)
		var b_distance_squared_gu := float(
			b.get("distance_squared_gu", INF)
		)
		if not is_equal_approx(a_distance_squared_gu, b_distance_squared_gu):
			return a_distance_squared_gu < b_distance_squared_gu
		return int(a.get("instance_id", 0)) < int(b.get("instance_id", 0))
	)
	var result: Array[EnemyActor] = []
	for entry: Dictionary in ranked:
		result.append(entry.get("target") as EnemyActor)
	return result


func _uses_magic_lock_domain() -> bool:
	return ProfessionRules.profession_id(PlayerState.profession) in [
		"wizard",
		"taoist",
	]


func _spell_lock_ground_gu(screen_position_px: Vector2) -> Vector2:
	return _canonical_screen_px_to_ground_gu(screen_position_px)


func _spell_lock_distance_gu(target: EnemyActor) -> float:
	if not is_instance_valid(target):
		return SpellTargetLockPolicyScript.LOCK_RANGE_GU + 1.0
	return SpellTargetLockPolicyScript.distance_gu(
		_spell_lock_ground_gu(player.global_position),
		_spell_lock_ground_gu(target.global_position)
	)


func _is_magic_target_in_range(target: EnemyActor) -> bool:
	return (
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.current_hp > 0
		and SpellTargetLockPolicyScript.is_within_lock_range(
			_spell_lock_ground_gu(player.global_position),
			_spell_lock_ground_gu(target.global_position)
		)
	)


func _spell_lock_candidates(excluded: EnemyActor = null) -> Array[EnemyActor]:
	var raw_candidates: Array[Dictionary] = []
	var origin_ground_gu := _spell_lock_ground_gu(player.global_position)
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if not value is EnemyActor:
			continue
		var enemy := value as EnemyActor
		if enemy == excluded or not _is_magic_target_in_range(enemy):
			continue
		raw_candidates.append({
			"target": enemy,
			"origin_ground_gu": origin_ground_gu,
			"target_ground_gu": _spell_lock_ground_gu(enemy.global_position),
			"instance_id": enemy.get_instance_id(),
		})
	var result: Array[EnemyActor] = []
	for ranked: Dictionary in SpellTargetLockPolicyScript.ordered_candidates(
		raw_candidates
	):
		result.append(ranked.get("target") as EnemyActor)
	return result


func _set_magic_locked_target(target: EnemyActor, manual := false) -> void:
	if target != null and not _is_magic_target_in_range(target):
		target = null
	magic_locked_target = target
	manual_magic_target_lock = manual and is_instance_valid(target)
	_refresh_target_highlights()
	_update_target_hud()


func _active_display_target() -> EnemyActor:
	return magic_locked_target if _uses_magic_lock_domain() else locked_target


func _refresh_target_highlights() -> void:
	var active_target := _active_display_target()
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor and is_instance_valid(value):
			(value as EnemyActor).set_targeted(value == active_target)


func _attack_lock_distance_gu(target: EnemyActor) -> float:
	if not is_instance_valid(target):
		return ATTACK_LOCK_RANGE_GU + 1.0
	return GroundUnitSpaceScript.distance_gu(
		_canonical_screen_px_to_ground_gu(player.global_position),
		_canonical_screen_px_to_ground_gu(target.global_position)
	)


func _is_attack_target_in_range(target: EnemyActor) -> bool:
	return (
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.current_hp > 0
		and _attack_lock_distance_gu(target)
		<= ATTACK_LOCK_RANGE_GU + GroundUnitSpaceScript.EPSILON_GU
	)


func _on_enemy_target_requested(enemy: EnemyActor) -> void:
	if _uses_magic_lock_domain() and _is_magic_target_in_range(enemy):
		_set_magic_locked_target(enemy, true)
		_skill_cast_target = enemy
		_face_skill_cast_target()
	elif not _uses_magic_lock_domain() and _is_attack_target_in_range(enemy):
		_set_attack_locked_target(enemy, true)
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
	var blocking_radius_gu := maxf(
		BOSS_SURROUNDED_NEIGHBOR_RADIUS_GU,
		enemy.combat_radius_gu * 2.5
	)
	var enemy_ground_gu := _canonical_screen_px_to_ground_gu(
		enemy.global_position
	)
	var candidates: Array = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("combat_targets")
	candidates.append(player)
	for value: Variant in candidates:
		if not value is Node2D or value == enemy or not is_instance_valid(value):
			continue
		var node := value as Node2D
		var instance_key := str(node.get_instance_id())
		if seen.has(instance_key):
			continue
		var node_ground_gu := _canonical_screen_px_to_ground_gu(
			node.global_position
		)
		if not GroundUnitSpaceScript.is_within_range_gu(
			enemy_ground_gu,
			node_ground_gu,
			blocking_radius_gu
		):
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
			1.5,
			6.0,
			WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
				ArtSpec.MONSTER_COLLISION_RADIUS_PX
			),
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


func _on_boss_relocation_requested(enemy: EnemyActor, radius_gu: float) -> void:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return
	if int(enemy.get_meta("zone_generation", -1)) != _zone_generation:
		return
	var destination := _find_valid_enemy_landing(
		enemy.global_position,
		1.5,
		maxf(1.5, radius_gu),
		enemy.combat_radius_gu,
		enemy
	)
	if destination == enemy.global_position:
		return
	enemy.global_position = destination
	enemy.velocity = Vector2.ZERO


func _find_valid_enemy_landing(
	origin_screen_px: Vector2,
	minimum_distance_gu: float,
	maximum_distance_gu: float,
	combat_radius_gu: float,
	ignored_enemy: EnemyActor
) -> Vector2:
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(
		origin_screen_px
	)
	var footprint_radius_px := (
		WorldSpatialRulesScript.actor_screen_radius_px_from_combat_radius_gu(
			combat_radius_gu
		)
	)
	for _attempt in range(96):
		var candidate_ground_gu := (
			origin_ground_gu
			+ Vector2.from_angle(_rng.randf_range(0.0, TAU))
			* _rng.randf_range(minimum_distance_gu, maximum_distance_gu)
		)
		if WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			candidate_ground_gu,
			_active_safe_zones
		):
			continue
		var candidate_screen_px := _canonical_ground_gu_to_screen_px(
			candidate_ground_gu
		)
		if WorldSpatialRulesScript.environment_blocks_actor_screen_px(
			background,
			candidate_screen_px,
			footprint_radius_px
		):
			continue
		var player_combat_radius_gu := (
			WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
				ArtSpec.PLAYER_COLLISION_RADIUS_PX
			)
		)
		if (
			is_instance_valid(player)
			and GroundUnitSpaceScript.distance_gu(
				_canonical_screen_px_to_ground_gu(player.global_position),
				candidate_ground_gu
			)
			< combat_radius_gu
			+ player_combat_radius_gu
			+ ACTOR_LANDING_CLEARANCE_GU
		):
			continue
		var occupied := false
		for value: Variant in get_tree().get_nodes_in_group("enemies"):
			if not value is EnemyActor or value == ignored_enemy or value.is_queued_for_deletion():
				continue
			var other := value as EnemyActor
			if GroundUnitSpaceScript.distance_gu(
				_canonical_screen_px_to_ground_gu(other.global_position),
				candidate_ground_gu
			) < combat_radius_gu + other.combat_radius_gu + ENEMY_LANDING_CLEARANCE_GU:
				occupied = true
				break
		if not occupied:
			return candidate_screen_px
	return origin_screen_px


func _cycle_target() -> void:
	_validate_locked_target()
	var magic_domain := _uses_magic_lock_domain()
	var candidates := (
		_spell_lock_candidates()
		if magic_domain
		else _attack_lock_candidates()
	)
	if candidates.is_empty():
		if magic_domain:
			_cancel_magic_target()
		else:
			_cancel_target()
		hud.show_message(
			"周围12格内没有可锁定目标"
			if magic_domain
			else "周围10格内没有可锁定目标"
		)
		return
	var next_index := 0
	var current_target := magic_locked_target if magic_domain else locked_target
	var current_index := candidates.find(current_target)
	if current_index >= 0:
		next_index = (current_index + 1) % candidates.size()
	if magic_domain:
		_set_magic_locked_target(candidates[next_index], true)
		_skill_cast_target = magic_locked_target
		_face_skill_cast_target()
	else:
		_set_attack_locked_target(candidates[next_index], true)
		_face_locked_target()


func _set_auto_target_enabled(enabled: bool) -> void:
	auto_target_enabled = enabled
	hud.set_auto_target_enabled(enabled)
	if enabled:
		if _uses_magic_lock_domain():
			_cancel_magic_target()
		else:
			_cancel_target()
	else:
		if _uses_magic_lock_domain():
			manual_magic_target_lock = is_instance_valid(magic_locked_target)
		else:
			manual_target_lock = is_instance_valid(locked_target)
		_update_target_hud()


func _on_player_moved(_position: Vector2, _facing: Vector2) -> void:
	_validate_locked_target()


func _on_player_death_requested() -> void:
	_cancel_all_combat_targets()
	_magic_shield_auto_enabled = false
	if is_instance_valid(hud):
		hud.cancel_attack_inputs(&"player_death")
		hud.cancel_skill_inputs(&"player_death")
	_cancel_all_mobile_attack_inputs(true)
	_cancel_all_skill_inputs(true)
	var accepted := travel_to_service_home(
		false,
		false,
		"比奇省",
		Callable(self, "_finish_death_revival")
	)
	if not accepted:
		call_deferred("_on_player_death_requested")


func _finish_death_revival() -> void:
	player.global_position = _bich_home_screen_position_px()
	player.velocity = Vector2.ZERO
	background.set_focus_position(player.global_position)
	_record_player_world_location()
	PlayerState.save_game()
	if hud != null:
		hud.show_message("你已在最近的城镇复活", 2.0)


func _cancel_target() -> void:
	locked_target = null
	manual_target_lock = false
	_refresh_target_highlights()
	_update_target_hud()


func _cancel_magic_target() -> void:
	magic_locked_target = null
	manual_magic_target_lock = false
	_skill_cast_target = null
	_refresh_target_highlights()
	_update_target_hud()


func _cancel_all_combat_targets() -> void:
	locked_target = null
	manual_target_lock = false
	magic_locked_target = null
	manual_magic_target_lock = false
	_skill_cast_target = null
	_refresh_target_highlights()
	_update_target_hud()


func _validate_locked_target() -> void:
	if locked_target != null and not _is_attack_target_in_range(locked_target):
		_cancel_target()
	if magic_locked_target != null and not _is_magic_target_in_range(magic_locked_target):
		_cancel_magic_target()


func _face_locked_target() -> Vector2:
	if not _is_attack_target_in_range(locked_target):
		return player.facing.normalized()
	var direction_resolution := CombatDirectionSpaceScript.resolve_world_delta(
		locked_target.global_position - player.global_position
	)
	var direction := Vector2(
		direction_resolution.get("projected_world_direction", player.facing)
	).normalized()
	if direction.length_squared() > 0.01:
		player.set_combat_facing(direction)
	return direction


func _ensure_skill_cast_target(excluded: EnemyActor = null) -> EnemyActor:
	if _is_magic_target_in_range(magic_locked_target) and magic_locked_target != excluded:
		_skill_cast_target = magic_locked_target
		return _skill_cast_target
	if magic_locked_target != null:
		_cancel_magic_target()
	if not auto_target_enabled:
		_skill_cast_target = null
		return null
	var candidates := _spell_lock_candidates(excluded)
	_set_magic_locked_target(
		candidates[0] if not candidates.is_empty() else null,
		false
	)
	_skill_cast_target = magic_locked_target
	return _skill_cast_target


func _face_skill_cast_target() -> Vector2:
	if not _is_magic_target_in_range(_skill_cast_target):
		return player.facing.normalized()
	var direction_screen_px := player.global_position.direction_to(
		_skill_cast_target.global_position
	)
	if direction_screen_px.length_squared() > 0.01:
		direction_screen_px = CombatRuntime.face_target_screen_px(
			player,
			_skill_cast_target
		)
	return direction_screen_px


func _select_wild_rush_target() -> EnemyActor:
	if _is_attack_target_in_range(locked_target):
		# A live lock is authoritative. An ineligible, over-level, boss, or
		# out-of-reach lock must make this cast invalid instead of silently
		# redirecting the charge to a different nearby monster.
		return locked_target if _wild_rush_target_is_eligible(locked_target) else null
	var player_ground_gu := _canonical_screen_px_to_ground_gu(player.global_position)
	var best: EnemyActor
	var best_distance_gu := INF
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor:
			continue
		var enemy: EnemyActor = node
		if not _wild_rush_target_is_eligible(enemy):
			continue
		var enemy_ground_gu := _canonical_screen_px_to_ground_gu(enemy.global_position)
		var distance_gu := GroundUnitSpaceScript.distance_gu(
			player_ground_gu,
			enemy_ground_gu
		)
		if distance_gu < best_distance_gu:
			best = enemy
			best_distance_gu = distance_gu
	return best


func _wild_rush_target_is_eligible(target: EnemyActor) -> bool:
	if (
		not is_instance_valid(target)
		or target.is_queued_for_deletion()
		or target.current_hp <= 0
		or target.is_boss
		or bool(target.get_meta("immovable", false))
		or int(target.monster_data.get("level", target.level)) >= PlayerState.level
	):
		return false
	if (
		WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			_canonical_screen_px_to_ground_gu(player.global_position),
			_active_safe_zones
		)
		or WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			_canonical_screen_px_to_ground_gu(target.global_position),
			_active_safe_zones
		)
	):
		return false
	return WarriorMeleeGeometryScript.wild_rush_target_is_adjacent(
		_canonical_screen_px_to_ground_gu(player.global_position),
		_canonical_screen_px_to_ground_gu(target.global_position)
	)


func _build_wild_rush_path_plan(target: EnemyActor) -> Dictionary:
	var result := {
		"contract_id": WarriorMeleeGeometryScript.WILD_RUSH_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"eligible": false,
		"dynamic_blocker_in_corridor": false,
		"static_clear_distance_gu": 0.0,
		"resolved_push_distance_gu": 0.0,
	}
	if not _wild_rush_target_is_eligible(target):
		return result
	var player_ground_gu := _canonical_screen_px_to_ground_gu(player.global_position)
	var target_ground_gu := _canonical_screen_px_to_ground_gu(target.global_position)
	var direction_ground_gu := WarriorMeleeGeometryScript.wild_rush_direction_ground_gu(
		player_ground_gu,
		target_ground_gu
	)
	var direction_index := WarriorMeleeGeometryScript.direction_index_for_ground_delta_gu(
		direction_ground_gu
	)
	var direction_step := WarriorMeleeGeometryScript.facing_tile_step(direction_index)
	var dynamic_blocked := _wild_rush_has_dynamic_blocker(
		target,
		target_ground_gu,
		direction_ground_gu
	)
	var static_clear_distance_gu := _wild_rush_static_clear_distance_gu(
		target,
		player_ground_gu,
		target_ground_gu,
		direction_ground_gu
	)
	result.merge({
		"eligible": true,
		"direction_index": direction_index,
		"direction_step": direction_step,
		"direction_ground_gu": direction_ground_gu,
		"player_origin_ground_gu": player_ground_gu,
		"target_origin_ground_gu": target_ground_gu,
		"dynamic_blocker_in_corridor": dynamic_blocked,
		"static_clear_distance_gu": static_clear_distance_gu,
		"resolved_push_distance_gu": (
			0.0 if dynamic_blocked else static_clear_distance_gu
		),
	}, true)
	return result


func _wild_rush_has_dynamic_blocker(
	target: EnemyActor,
	target_ground_gu: Vector2,
	direction_ground_gu: Vector2
) -> bool:
	var forward_ground_gu := direction_ground_gu.normalized()
	var side_ground_gu := Vector2(-forward_ground_gu.y, forward_ground_gu.x)
	var target_radius_gu := target.combat_radius_gu
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node == target:
			continue
		var other: EnemyActor = node
		if other.is_queued_for_deletion() or other.current_hp <= 0:
			continue
		var delta_ground_gu := (
			_canonical_screen_px_to_ground_gu(other.global_position)
			- target_ground_gu
		)
		var forward_distance_gu := delta_ground_gu.dot(forward_ground_gu)
		var lateral_distance_gu := absf(delta_ground_gu.dot(side_ground_gu))
		var other_radius_gu := other.combat_radius_gu
		if (
			forward_distance_gu > WarriorMeleeGeometryScript.EPSILON
			and forward_distance_gu - other_radius_gu
			<= WarriorMeleeGeometryScript.WILD_RUSH_PUSH_DISTANCE_GU
				+ WarriorMeleeGeometryScript.EPSILON
			and lateral_distance_gu
			<= target_radius_gu + other_radius_gu + WarriorMeleeGeometryScript.EPSILON
		):
			return true
	return false


func _wild_rush_static_clear_distance_gu(
	target: EnemyActor,
	player_ground_gu: Vector2,
	target_ground_gu: Vector2,
	direction_ground_gu: Vector2
) -> float:
	const SAMPLE_STEP_GU := 0.25
	var maximum_distance_gu := WarriorMeleeGeometryScript.WILD_RUSH_PUSH_DISTANCE_GU
	var sample_count := ceili(maximum_distance_gu / SAMPLE_STEP_GU)
	var last_clear_distance_gu := 0.0
	for sample_index: int in range(1, sample_count + 1):
		var distance_gu := minf(
			float(sample_index) * SAMPLE_STEP_GU,
			maximum_distance_gu
		)
		var motion_ground_gu := direction_ground_gu * distance_gu
		var player_destination := _canonical_ground_gu_to_screen_px(
			player_ground_gu + motion_ground_gu
		)
		var target_destination := _canonical_ground_gu_to_screen_px(
			target_ground_gu + motion_ground_gu
		)
		if (
			WorldSpatialRulesScript.environment_blocks_actor_screen_px(
				background,
				player_destination,
				ArtSpec.PLAYER_COLLISION_RADIUS_PX
			)
			or WorldSpatialRulesScript.environment_blocks_actor_screen_px(
				background,
				target_destination,
				target.collision_radius_px
			)
		):
			return last_clear_distance_gu
		last_clear_distance_gu = distance_gu
	return last_clear_distance_gu


func _apply_wild_rush_displacement(
	target: EnemyActor,
	effect: Dictionary,
	target_context: Dictionary
) -> bool:
	var distance_gu := clampf(
		float(effect.get("resolved_push_distance_gu", 0.0)),
		0.0,
		WarriorMeleeGeometryScript.WILD_RUSH_PUSH_DISTANCE_GU
	)
	if distance_gu <= 0.0 or bool(target_context.get("dynamic_blocker_in_corridor", false)):
		return false
	var direction_ground_gu: Vector2 = target_context.get(
		"direction_ground_gu", Vector2.ZERO
	)
	if (
		direction_ground_gu.length_squared()
		<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
	):
		return false
	var motion_ground_gu := direction_ground_gu.normalized() * distance_gu
	var player_destination := _canonical_ground_gu_to_screen_px(
		_canonical_screen_px_to_ground_gu(player.global_position)
		+ motion_ground_gu
	)
	var target_destination := _canonical_ground_gu_to_screen_px(
		_canonical_screen_px_to_ground_gu(target.global_position)
		+ motion_ground_gu
	)
	if (
		WorldSpatialRulesScript.environment_blocks_actor_screen_px(
			background,
			player_destination,
			ArtSpec.PLAYER_COLLISION_RADIUS_PX
		)
		or WorldSpatialRulesScript.environment_blocks_actor_screen_px(
			background,
			target_destination,
			target.collision_radius_px
		)
	):
		return false
	# Both destinations were preflighted before either actor is mutated. This is
	# one coupled transaction: partial single-actor movement is forbidden.
	target.global_position = target_destination
	player.global_position = player_destination
	player.velocity = Vector2.ZERO
	player.movement_performed.emit(player.global_position, player.facing)
	return true


func _update_target_hud() -> void:
	if not is_instance_valid(hud):
		return
	var magic_domain := _uses_magic_lock_domain()
	var active_target := magic_locked_target if magic_domain else locked_target
	var target_valid := (
		_is_magic_target_in_range(active_target)
		if magic_domain
		else _is_attack_target_in_range(active_target)
	)
	if target_valid:
		hud.update_target(
			active_target.display_name,
			active_target.current_hp,
			active_target.max_hp,
			manual_magic_target_lock if magic_domain else manual_target_lock,
			auto_target_enabled
		)
	else:
		hud.update_target("", 0, 0, false, auto_target_enabled)


func _try_interact() -> void:
	var nearest: Node2D
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(
		player.global_position
	)
	var nearest_distance_gu := (
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			105.0
		)
	)
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not node is Node2D:
			continue
		var distance_gu := GroundUnitSpaceScript.distance_gu(
			origin_ground_gu,
			_canonical_screen_px_to_ground_gu(node.global_position)
		)
		if distance_gu < nearest_distance_gu:
			nearest = node
			nearest_distance_gu = distance_gu
	if nearest == null:
		hud.show_message("附近没有可交互目标")
		return
	nearest.interact(self)


func _use_quick_slot(index: int) -> void:
	_use_skill_slot(PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, index)


func _use_skill_slot(slot_group: String, slot_index: int) -> void:
	var skill_name := PlayerState.skill_name_for_slot(slot_group, slot_index)
	if skill_name.is_empty():
		var group_label := (
			"攻击键"
			if slot_group == PlayerState.SKILL_SLOT_GROUP_ATTACK
			else "攻击环%d" % (slot_index + 1)
		)
		hud.show_message("%s为空" % group_label)
		return
	var metadata := SkillInputPolicyScript.metadata(skill_name)
	if bool(metadata.get("toggle", false)):
		_handle_toggle_skill_input(skill_name)
		return
	_try_release_skill(skill_name, true)


func _try_release_skill(skill_name: String, show_failure := true) -> StringName:
	if skill_name.is_empty() or not PlayerState.is_skill_learned(skill_name):
		if show_failure:
			hud.show_message("技能尚未学习")
		return &"rejected"
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name)
	var definition := SkillDataLoaderScript.skill(stable_skill_id)
	if definition.is_empty():
		return &"rejected"
	var learned_level := PlayerState.effective_skill_level(skill_name)
	var profile := ProfessionRules.skill_combat_profile(skill_name, learned_level)
	var mana_costs: Array = definition.get("mp_cost_by_rank", [])
	var mana_cost := (
		int(mana_costs[clampi(learned_level, 0, mana_costs.size() - 1)])
		if not mana_costs.is_empty()
		else 0
	)
	if player.current_mp < mana_cost:
		if show_failure:
			hud.show_message("魔法不足")
		return &"rejected"
	_skill_cast_target = null
	if stable_skill_id == WILD_RUSH_SKILL_ID:
		_skill_cast_target = _select_wild_rush_target()
		if _skill_cast_target == null:
			if show_failure:
				hud.show_message("附近没有可冲撞的低级普通怪物")
			return &"rejected"
		_face_skill_cast_target()
	elif _skill_needs_target(str(profile.get("cast_type", "melee"))):
		_ensure_skill_cast_target(null)
		_face_skill_cast_target()
	if _definition_requires_hostile_target(definition):
		if not is_instance_valid(_skill_cast_target):
			if show_failure:
				hud.show_message("法术需要有效目标")
			return &"rejected"
		if not _spell_definition_allows_target(definition, _skill_cast_target):
			if show_failure:
				hud.show_message("目标超出该法术的有效范围")
			return &"rejected"
	var locked_skill_target_id := (
		_skill_cast_target.get_instance_id()
		if is_instance_valid(_skill_cast_target)
		else 0
	)
	if not player.request_skill(skill_name, locked_skill_target_id):
		if show_failure:
			hud.show_message("技能动作或冷却尚未结束")
		return &"busy"
	if stable_skill_id.begins_with("warrior."):
		_skill_cast_target = null
	return &"accepted"


func _definition_requires_hostile_target(definition: Dictionary) -> bool:
	if str(definition.get("skill_id", "")) == FIRE_WALL_SKILL_ID:
		return true
	var target: Dictionary = definition.get("target", {})
	var relation := str(target.get("relation", ""))
	if not relation.contains("hostile"):
		return false
	var mode := str(target.get("mode", ""))
	return (
		mode != "facing_line"
		and not mode.contains("surrounding")
		and not mode.contains("ground")
		and not mode.begins_with("self")
	)


func _spell_definition_allows_target(
	definition: Dictionary,
	target: EnemyActor
) -> bool:
	if not _is_magic_target_in_range(target):
		return false
	var geometry: Dictionary = definition.get("geometry", {})
	var maximum_range_gu := float(
		geometry.get("maximum_range_gu", 0.0)
	)
	return SpellTargetLockPolicyScript.spell_range_allows_target(
		_spell_lock_ground_gu(player.global_position),
		_spell_lock_ground_gu(target.global_position),
		maximum_range_gu
	)


func _on_skill_button_assignment_requested(request: Dictionary) -> void:
	var result := (
		SkillLoadoutRulesScript.clear_button_slot(
			PlayerState.skill_button_assignments_snapshot(),
			request
		)
		if bool(request.get("clear", false))
		else SkillLoadoutRulesScript.assign_button_slot(
			PlayerState.skill_button_assignments_snapshot(),
			PlayerState.learned_skills,
			request
		)
	)
	if not bool(result.get("ok", false)):
		hud.show_message("技能栏配置失败：%s" % str(result.get("reason", "invalid_request")))
		return
	if not PlayerState.apply_skill_button_assignment(result):
		hud.show_message("技能栏配置未能保存")
		return
	if is_instance_valid(hud):
		hud.cancel_attack_inputs(&"skill_assignment_changed")
		hud.cancel_skill_inputs(&"skill_assignment_changed")
	_cancel_all_mobile_attack_inputs(true)
	_cancel_all_skill_inputs(true)
	hud.set_skill_button_assignments(PlayerState.skill_button_assignments_snapshot())
	var change: Dictionary = result.get("change", {})
	var group_label := (
		"攻击键"
		if str(change.get("slot_group", "")) == PlayerState.SKILL_SLOT_GROUP_ATTACK
		else "攻击环%d" % (int(change.get("slot_index", 0)) + 1)
	)
	if str(change.get("operation", "")) == "clear":
		hud.show_message(
			"%s已恢复普通攻击" % group_label
			if group_label == "攻击键"
			else "%s已清空" % group_label,
			1.5
		)
	else:
		hud.show_message(
			"已将%s配置到%s" % [
				str(change.get("skill_name", "技能")),
				group_label,
			],
			1.5
		)


func _on_player_attack(origin: Vector2, direction: Vector2, damage: int) -> void:
	var context := player.consume_attack_context()
	var diagnostic := _pending_melee_diagnostic.duplicate(true)
	_pending_melee_diagnostic.clear()
	_active_physical_hit_diagnostics.clear()
	var release_geometry: Dictionary = context.get("release_geometry", {})
	if not release_geometry.is_empty():
		origin = release_geometry.get("origin_screen_px", origin)
		direction = release_geometry.get("direction_screen_px", direction)
	_expire_canonical_fire_charge_if_needed()
	var body_selection := context.duplicate(true)
	var selection_mode := str(body_selection.get("mode", WarriorMeleeGeometryScript.SKILL_NORMAL))
	if Time.get_ticks_msec() < _canonical_fire_charge_expires_ms:
		selection_mode = WarriorMeleeGeometryScript.SKILL_FIRE
	var primary_targets := _physical_primary_targets(
		origin,
		direction,
		selection_mode,
		release_geometry
	)
	var eligible_target_count := primary_targets.size()
	if selection_mode == WarriorMeleeGeometryScript.SKILL_THRUST:
		eligible_target_count += _thrust_secondary_targets(
			origin,
			direction,
			primary_targets,
			release_geometry
		).size()
	elif selection_mode == WarriorMeleeGeometryScript.SKILL_HALF_MOON:
		eligible_target_count += _half_moon_secondary_targets(
			origin,
			direction,
			primary_targets,
			release_geometry
		).size()
	var has_eligible_target := eligible_target_count > 0
	var consumes_armed_fire := false
	if not primary_targets.is_empty() and Time.get_ticks_msec() < _canonical_fire_charge_expires_ms:
		body_selection["mode"] = "fire"
		body_selection["selected_body_mode"] = "fire"
		body_selection["skill_name"] = "烈火剑法"
		body_selection["skill_level"] = PlayerState.effective_skill_level("烈火剑法")
		body_selection["direct_toggle_release"] = false
		consumes_armed_fire = true

	var hit_effect := SkillInputPolicyScript.resolve_warrior_hit_effect(
		body_selection,
		{
			"learned_skills": PlayerState.learned_skills,
			"toggles": {
				"warrior.fire_sword": player.fire_sword_enabled,
				"warrior.half_moon": player.half_moon_enabled,
				"warrior.thrusting": player.thrusting_enabled,
			},
			"has_combat_target": has_eligible_target,
			"current_mp": player.current_mp,
			"fire_rank": PlayerState.effective_skill_level("烈火剑法"),
			"half_moon_rank": PlayerState.effective_skill_level("半月弯刀"),
		}
	)
	var effect_mode := str(hit_effect.get("effect_mode", ""))
	if consumes_armed_fire and effect_mode == "fire":
		_set_canonical_fire_charge_expires_at(0)
	var melee_modifiers := SkillRuntimeRouterScript.resolve_warrior_melee_modifiers({
		"body_mode": effect_mode,
		"basic_sword_learned": PlayerState.is_skill_learned("基本剑术"),
		"basic_sword_rank": PlayerState.effective_skill_level("基本剑术"),
		"slaying_learned": PlayerState.is_skill_learned("攻杀剑术"),
		"slaying_rank": PlayerState.effective_skill_level("攻杀剑术"),
		"valid_melee_swing": has_eligible_target,
		"seed": _next_canonical_seed(),
	})
	var modified_base_damage := (
		damage
		+ int(melee_modifiers.get("flat_dc_bonus_before_body_formula", 0))
	)
	var post_body_damage_bonus := int(
		melee_modifiers.get("flat_damage_bonus_after_body_formula", 0)
	)
	var accuracy_bonus := int(melee_modifiers.get("flat_accuracy_bonus", 0))
	var hit_any := false
	var canonical_resolution := "rejected"
	if effect_mode in ["thrust", "half_moon", "fire"]:
		var melee_resolution := _execute_canonical_melee(
			effect_mode,
			origin,
			direction,
			modified_base_damage,
			post_body_damage_bonus,
			accuracy_bonus,
			bool(body_selection.get("direct_toggle_release", false)),
			release_geometry
		)
		hit_any = bool(melee_resolution.get("hit_any", false))
		canonical_resolution = str(melee_resolution.get("resolution", "rejected"))
	elif effect_mode == "normal":
		if not primary_targets.is_empty():
			var target := primary_targets[0]
			hit_any = _apply_physical_hit(
				target,
				modified_base_damage + post_body_damage_bonus,
				accuracy_bonus
			)
			canonical_resolution = "hit" if hit_any else "miss"
	if SkillInputPolicyScript.fire_direct_release_consumes_cooldown(
		body_selection,
		hit_effect,
		canonical_resolution
	):
		player.commit_fire_sword_cooldown()
	_commit_warrior_melee_modifier_events(melee_modifiers)
	if (
		bool(melee_modifiers.get("slaying_proc", false))
		and player.visual != null
		and player.visual.has_method("play_passive_proc_effect")
	):
		player.visual.call("play_passive_proc_effect", "攻杀剑术", 0.24)
	if effect_mode == "fire" and hud != null:
		hud.update_warrior_states(player.warrior_state_snapshot())
	_show_attack_flash(origin, direction, hit_any, Color(1.0, 0.72, 0.25))
	_record_melee_release_diagnostic(
		diagnostic,
		context,
		release_geometry,
		origin,
		direction,
		selection_mode,
		effect_mode,
		primary_targets,
		eligible_target_count,
		has_eligible_target,
		canonical_resolution,
		hit_any
	)


func _record_melee_release_diagnostic(
	diagnostic: Dictionary,
	context: Dictionary,
	release_geometry: Dictionary,
	origin: Vector2,
	direction: Vector2,
	selection_mode: String,
	effect_mode: String,
	primary_targets: Array[EnemyActor],
	eligible_target_count: int,
	has_eligible_target: bool,
	canonical_resolution: String,
	hit_any: bool
) -> void:
	# Direct unit-test calls deliberately have no input trace. Avoid turning the
	# existing test suite into noisy production telemetry while retaining a
	# complete record for every real mobile/keyboard attack action.
	if diagnostic.is_empty() and PlayerState.test_mode:
		return
	if diagnostic.is_empty():
		_melee_diagnostic_serial += 1
		diagnostic = {
			"action_id": "player:%d:melee:%d" % [
				player.get_instance_id(),
				_melee_diagnostic_serial,
			],
			"actor_id": player.get_instance_id(),
			"map_id": current_map_id,
			"trace_origin": "release_without_input_trace",
		}
	var release_direction_index := _melee_direction_index(
		direction,
		release_geometry
	)
	diagnostic["event"] = "attack_release_resolved"
	diagnostic["body_context"] = context.duplicate(true)
	diagnostic["release_geometry"] = release_geometry.duplicate(true)
	diagnostic["actor_screen_px_at_release"] = origin
	diagnostic["actor_ground_gu_at_release"] = _canonical_screen_px_to_ground_gu(origin)
	diagnostic["release_direction_screen_px"] = direction
	diagnostic["release_direction_index"] = release_direction_index
	diagnostic["release_direction_tile_step"] = (
		WarriorMeleeGeometryScript.facing_tile_step(release_direction_index)
	)
	diagnostic["direction_loop_audit_at_release"] = (
		WarriorMeleeDiagnosticScript.audit_direction(release_direction_index)
	)
	diagnostic["expected_visual_row_at_release"] = ArtSpec.mir2_client_direction_row(direction)
	diagnostic["actual_visual_row_at_release"] = (
		player.visual.current_direction if player.visual != null else -1
	)
	diagnostic["visual_geometry_direction_match"] = (
		player.visual == null
		or player.visual.current_direction == ArtSpec.mir2_client_direction_row(direction)
	)
	diagnostic["player_facing_at_release"] = player.facing
	diagnostic["player_facing_index_at_release"] = ArtSpec.direction_index(player.facing)
	diagnostic["input_release_direction_match"] = (
		int(diagnostic.get("attack_direction_index_at_input", release_direction_index))
		== release_direction_index
	)
	diagnostic["selection_mode"] = selection_mode
	diagnostic["effect_mode"] = effect_mode
	diagnostic["selection_candidate_decisions"] = _melee_candidate_diagnostics(
		origin,
		release_direction_index,
		selection_mode,
		primary_targets
	)
	diagnostic["effect_candidate_decisions"] = _melee_candidate_diagnostics(
		origin,
		release_direction_index,
		effect_mode,
		primary_targets
	)
	diagnostic["primary_target_ids"] = _enemy_instance_ids(primary_targets)
	diagnostic["eligible_target_count"] = eligible_target_count
	diagnostic["has_eligible_target"] = has_eligible_target
	diagnostic["canonical_resolution"] = canonical_resolution
	diagnostic["physical_hit_attempts"] = _active_physical_hit_diagnostics.duplicate(true)
	diagnostic["result_code"] = _melee_diagnostic_result_code(
		has_eligible_target,
		canonical_resolution,
		hit_any,
		_active_physical_hit_diagnostics
	)
	diagnostic["damage_applied"] = hit_any
	CombatDiagnosticLogScript.record(diagnostic)


func _melee_candidate_diagnostics(
	origin: Vector2,
	direction_index: int,
	mode: String,
	primary_targets: Array[EnemyActor]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin)
	var resolved_mode := (
		mode
		if mode in [
			WarriorMeleeGeometryScript.SKILL_NORMAL,
			WarriorMeleeGeometryScript.SKILL_FIRE,
			WarriorMeleeGeometryScript.SKILL_HALF_MOON,
			WarriorMeleeGeometryScript.SKILL_THRUST,
		]
		else WarriorMeleeGeometryScript.SKILL_NORMAL
	)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion() or node.current_hp <= 0:
			continue
		var enemy := node as EnemyActor
		var explanation := WarriorMeleeDiagnosticScript.explain_footprint_candidate(
			origin_ground_gu,
			_canonical_screen_px_to_ground_gu(enemy.global_position),
			enemy.combat_radius_gu,
			direction_index,
			resolved_mode
		)
		explanation["angle_quantization_audit"] = (
			WarriorMeleeDiagnosticScript.audit_ground_delta_gu(
				_canonical_screen_px_to_ground_gu(enemy.global_position) - origin_ground_gu
			)
		)
		explanation["target_id"] = enemy.get_instance_id()
		explanation["target_name"] = enemy.display_name
		explanation["target_world"] = enemy.global_position
		explanation["selected_as_primary"] = enemy in primary_targets
		if (
			float(explanation.get("distance_gu", INF))
			> float(explanation.get("effective_reach_gu", 0.0)) + 1.0
			and not bool(explanation.get("footprint_accepted", false))
			and not bool(explanation["selected_as_primary"])
		):
			continue
		result.append(explanation)
	return result


func _enemy_instance_ids(enemies: Array[EnemyActor]) -> Array[int]:
	var result: Array[int] = []
	for enemy: EnemyActor in enemies:
		if is_instance_valid(enemy):
			result.append(enemy.get_instance_id())
	return result


func _melee_direction_index(
	direction: Vector2,
	release_geometry: Dictionary = {}
) -> int:
	var resolved_index := int(release_geometry.get("direction_index", -1))
	if resolved_index >= 0 and resolved_index < 8:
		return resolved_index
	return ArtSpec.direction_index(direction)


func _melee_diagnostic_result_code(
	has_eligible_target: bool,
	canonical_resolution: String,
	hit_any: bool,
	hit_attempts: Array[Dictionary]
) -> String:
	if hit_any:
		return "HIT_COMMITTED"
	if not has_eligible_target:
		return "GEOMETRY_NO_ELIGIBLE_TARGET"
	if canonical_resolution == "rejected":
		return "CANONICAL_SKILL_REJECTED"
	for attempt: Dictionary in hit_attempts:
		if str(attempt.get("result_code", "")) == "DAMAGE_COMMIT_FAILED":
			return "DAMAGE_COMMIT_FAILED"
	for attempt: Dictionary in hit_attempts:
		if str(attempt.get("result_code", "")) == "ACCURACY_MISS":
			return "ACCURACY_MISS"
	return "NO_DAMAGE_UNCLASSIFIED"


func _commit_warrior_melee_modifier_events(modifiers: Dictionary) -> void:
	for raw_event: Variant in modifiers.get("proficiency_events", []):
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event
		var skill_id := str(event.get("skill_id", ""))
		var event_id := str(event.get("event", ""))
		if skill_id.is_empty() or event_id.is_empty():
			continue
		PlayerState.apply_skill_proficiency_event(
			skill_id,
			event_id,
			_next_canonical_seed()
		)


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
			_skill_cast_target = null
			_ensure_skill_cast_target(null)
			var direction := _face_skill_cast_target()
			if direction == Vector2.ZERO:
				direction = player.facing.normalized()
			var low := maxi(1, int(PlayerState.computed_stats.get("magic_min", 0)))
			var high := maxi(low, int(PlayerState.computed_stats.get("magic_max", low)))
			_spawn_projectile(
				player.global_position,
				direction,
				_rng.randi_range(low, high),
				float(
					SkillDataLoaderScript.skill("wizard.fireball")
					.get("geometry", {})
					.get("maximum_range_gu", 0.0)
				),
				Color(1.0, 0.30, 0.08),
				"damage",
				0,
				0.0,
				"wizard.fireball"
			)
			_skill_cast_target = null
			hud.show_message("火焰戒指：火球")
		"recovery_skill":
			if not player.spend_mana(5):
				hud.show_message("治愈需要5点魔法")
				return
			var amount := maxi(12, int(PlayerState.level / 2) + int(PlayerState.computed_stats.get("tao_max", 0)) * 2)
			player.restore_health(amount)
			hud.show_message("防御戒指：恢复%d生命" % amount)


func _try_safe_ring_teleport() -> bool:
	var direction_screen_px := player.facing.normalized()
	if direction_screen_px == Vector2.ZERO:
		direction_screen_px = Vector2.DOWN
	var direction_ground := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	for distance_gu: float in SAFE_RING_TELEPORT_DISTANCES_GU:
		var motion_screen_px := (
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				direction_ground * distance_gu
			)
		)
		if not player.test_move(player.global_transform, motion_screen_px):
			player.global_position += motion_screen_px
			player.velocity = Vector2.ZERO
			player.movement_performed.emit(player.global_position, player.facing)
			return true
	return false


func _on_warrior_skill_state_changed(_skill_name: String, _enabled: bool, message: String) -> void:
	PlayerState.apply_warrior_runtime_state(player.warrior_runtime_state_for_save(), true)
	if hud != null:
		hud.show_message(message, 1.5)
		hud.update_warrior_states(player.warrior_state_snapshot())


func _on_player_skill(skill_name: String, origin: Vector2, direction: Vector2, damage: int) -> void:
	var skill_context := player.consume_skill_context()
	var release_geometry: Dictionary = skill_context.get("release_geometry", {})
	if not release_geometry.is_empty():
		origin = release_geometry.get("origin_screen_px", origin)
		direction = release_geometry.get("direction_screen_px", direction)
		var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name)
		var release_target := _combat_release_target(release_geometry)
		if (
			not CombatReleaseGeometryScript.target_centered_spatial_policy_id(
				stable_skill_id
			).is_empty()
			and not _is_magic_target_in_range(release_target)
		):
			# Target-centred area spells retain the selected monster identity only
			# so its live, manually calibrated footpoint can be sampled here. If
			# that exact instance dies, despawns or leaves the 12-tile spell-lock
			# domain during windup, reject the cast instead of degrading to the
			# generic ground/direction fallback used by untargeted area spells.
			_skill_cast_target = null
			hud.show_message("锁定目标已失效，技能未释放", 1.5)
			return
		_skill_cast_target = release_target
	var execution := _execute_canonical_skill(
		skill_name,
		origin,
		direction,
		damage,
		{},
		true,
		not release_geometry.is_empty()
	)
	var hit_any := bool(execution.get("effect_success", false))
	if not bool(execution.get("accepted", false)):
		hud.show_message("技能释放失败：%s" % str(execution.get("reason", "runtime_rejected")), 1.5)
		return
	var effect_color := Color(1.0, 0.22, 0.05) if PlayerState.profession == "战士" else (Color(0.28, 0.62, 1.0) if PlayerState.profession == "法师" else Color(0.45, 0.92, 0.55))
	_show_attack_flash(origin, direction, hit_any, effect_color)
	if skill_name == "烈火剑法":
		hud.update_warrior_states(player.warrior_state_snapshot())
	hud.show_message("施放：%s" % skill_name, 1.0)


func _execute_canonical_skill(
	skill_name: String,
	origin: Vector2,
	direction: Vector2,
	client_damage: int,
	extra_target_context: Dictionary = {},
	apply_effects := true,
	authoritative_cast_target := false
) -> Dictionary:
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name)
	var definition := SkillDataLoaderScript.skill(stable_skill_id)
	if definition.is_empty():
		_skill_cast_target = null
		return {"accepted": false, "effect_success": false, "reason": "unknown_skill"}
	var rank := PlayerState.effective_skill_level(skill_name)
	var target_context := _canonical_target_context(
		definition,
		origin,
		direction,
		not authoritative_cast_target
	)
	target_context.merge(extra_target_context, true)
	var cast_target := _skill_cast_target
	var request_facing := _canonical_facing_for_skill(stable_skill_id, direction)
	if stable_skill_id == WILD_RUSH_SKILL_ID and cast_target != null:
		var rush_plan := _build_wild_rush_path_plan(cast_target)
		if bool(rush_plan.get("eligible", false)):
			target_context.merge(rush_plan, true)
			request_facing = rush_plan.get("direction_step", request_facing)
	var resource_context := _canonical_resource_context(stable_skill_id)
	var request := SkillCastRequestScript.create(
		stable_skill_id,
		rank,
		PlayerState.level,
		_canonical_screen_px_to_grid_cell(origin),
		request_facing,
		target_context,
		resource_context,
		_next_canonical_seed()
	)
	request["client_claimed_damage"] = client_damage
	var result := SkillRuntimeRouterScript.execute(request)
	result["adapter_contract"] = SKILL_PRODUCTION_ADAPTER_CONTRACT
	result["adapter_bindings"] = [
		"combat_resolution",
		"inventory_resources",
		"map_tile_geometry",
		"target_relations",
		"buff_runtime",
		"taoist_main_pet",
	]
	if not bool(result.get("accepted", false)):
		_skill_cast_target = null
		return result
	if bool(result.get("resource_commit", false)) and not _commit_canonical_resources(result):
		result["accepted"] = false
		result["effect_success"] = false
		result["reason"] = "resource_commit_failed"
		_skill_cast_target = null
		return result
	if apply_effects:
		_apply_canonical_effects(result, origin, direction, target_context, cast_target)
	var proficiency_event := str(result.get("proficiency_event", ""))
	if not proficiency_event.is_empty():
		PlayerState.apply_skill_proficiency_event(
			stable_skill_id,
			proficiency_event,
			_next_canonical_seed()
		)
	_skill_cast_target = null
	return result


func _execute_canonical_melee(
	mode: String,
	origin: Vector2,
	direction: Vector2,
	base_damage: int,
	post_body_damage_bonus: int,
	accuracy_bonus: int,
	direct_toggle_release := false,
	release_geometry: Dictionary = {}
) -> Dictionary:
	var skill_name: String = {
		"thrust": "刺杀剑术",
		"half_moon": "半月弯刀",
		"fire": "烈火剑法",
	}.get(mode, "")
	if skill_name.is_empty():
		return {"accepted": false, "hit_any": false, "resolution": "rejected"}
	var primary_targets := _physical_primary_targets(
		origin,
		direction,
		mode,
		release_geometry
	)
	var thrust_secondaries: Array[EnemyActor] = []
	var half_moon_secondaries: Array[EnemyActor] = []
	var eligible_target_count := primary_targets.size()
	if mode == "thrust":
		thrust_secondaries = _thrust_secondary_targets(
			origin,
			direction,
			primary_targets,
			release_geometry
		)
		eligible_target_count += thrust_secondaries.size()
	elif mode == "half_moon":
		half_moon_secondaries = _half_moon_secondary_targets(
			origin,
			direction,
			primary_targets,
			release_geometry
		)
		eligible_target_count += half_moon_secondaries.size()
	var extra := {
		"has_target": eligible_target_count > 0,
		"line_of_sight": eligible_target_count > 0,
		"valid_melee_swing": eligible_target_count > 0,
		"eligible_target_count": eligible_target_count,
		"charge_consumed": mode == "fire" and not primary_targets.is_empty(),
		"direct_toggle_release": (
			mode == "fire"
			and not primary_targets.is_empty()
			and direct_toggle_release
		),
	}
	var result := _execute_canonical_skill(skill_name, origin, direction, base_damage, extra, false)
	if not bool(result.get("accepted", false)):
		return {"accepted": false, "hit_any": false, "resolution": "rejected"}
	var hit_any := false
	for raw_effect: Variant in result.get("effects", []):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		match str(effect.get("type", "")):
			"melee_hit":
				var targets: Array[EnemyActor] = (
					primary_targets
					if int(effect.get("cell", 1)) == 1
					else thrust_secondaries
				)
				for target: EnemyActor in targets:
					hit_any = _apply_physical_hit(
						target,
						roundi(float(base_damage) * float(effect.get("multiplier", 1.0)))
						+ post_body_damage_bonus,
						accuracy_bonus
					) or hit_any
			"melee_arc":
				for primary: EnemyActor in primary_targets:
					hit_any = _apply_physical_hit(
						primary,
						roundi(float(base_damage) * float(effect.get("primary_multiplier", 1.0)))
						+ post_body_damage_bonus,
						accuracy_bonus
					) or hit_any
				for secondary: EnemyActor in half_moon_secondaries:
					hit_any = _apply_physical_hit(
						secondary,
						roundi(float(base_damage) * float(effect.get("side_multiplier", 1.0)))
						+ post_body_damage_bonus,
						accuracy_bonus
					) or hit_any
			"next_melee_charge":
				if not primary_targets.is_empty():
					var target := primary_targets[0]
					hit_any = _apply_physical_hit(
						target,
						roundi(float(base_damage) * float(effect.get("damage_multiplier", 1.0)))
						+ post_body_damage_bonus,
						accuracy_bonus
					)
	return {
		"accepted": true,
		"hit_any": hit_any,
		"resolution": "hit" if hit_any else "miss",
	}


func _canonical_basic_sword_bonus(origin: Vector2, direction: Vector2, valid_swing: bool) -> int:
	if not PlayerState.is_skill_learned("基本剑术"):
		return 0
	var result := _execute_canonical_skill(
		"基本剑术",
		origin,
		direction,
		0,
		{"valid_melee_swing": valid_swing}
	)
	for raw_effect: Variant in result.get("effects", []):
		if raw_effect is Dictionary and str(raw_effect.get("type", "")) == "passive_stat_modifier":
			return int(raw_effect.get("value", 0))
	return 0


func _canonical_target_context(
	definition: Dictionary,
	origin: Vector2,
	direction: Vector2,
	allow_auto_target := true
) -> Dictionary:
	var target_contract: Dictionary = definition.get("target", {})
	var target_mode := str(target_contract.get("mode", ""))
	var target_relation := str(target_contract.get("relation", ""))
	var friendly_cast := target_relation.contains("friendly") or target_mode in ["self", "self_or_friendly_single"]
	var search_range_gu := SpellTargetLockPolicyScript.LOCK_RANGE_GU
	if allow_auto_target and not friendly_cast and target_mode not in ["self", "self_stat", "self_summon", "self_next_melee_charge", "self_random_destination", "caster_surrounding_area", "surrounding_units"]:
		_ensure_skill_cast_target(null)
	var target := _skill_cast_target if not friendly_cast and is_instance_valid(_skill_cast_target) else null
	var target_within_skill_range := (
		target != null and _spell_definition_allows_target(definition, target)
	)
	var independent_geometry_target := (
		str(definition.get("skill_id", "")) != FIRE_WALL_SKILL_ID
		and (
			target_mode == "facing_line"
			or target_mode.contains("surrounding")
			or target_mode.contains("ground")
			or target_mode.begins_with("self")
		)
	)
	var hostile_target_required := _definition_requires_hostile_target(definition)
	var usable_target := (
		target != null
		and (not target_relation.contains("hostile") or target_within_skill_range)
	)
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin)
	var direction_ground_gu := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		direction
	)
	if (
		direction_ground_gu.length_squared()
		<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
	):
		direction_ground_gu = GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			player.facing
		)
	direction_ground_gu = direction_ground_gu.normalized()
	var maximum_range_gu := float(
		definition.get("geometry", {}).get("maximum_range_gu", 0.0)
	)
	var fallback_distance_gu := (
		maximum_range_gu
		if maximum_range_gu > 0.0
		else search_range_gu
	)
	var fallback_target_ground_gu := (
		origin_ground_gu + direction_ground_gu * fallback_distance_gu
	)
	var fallback_target_tile := Vector2i(
		roundi(fallback_target_ground_gu.x),
		roundi(fallback_target_ground_gu.y)
	)
	if maximum_range_gu > 0.0:
		fallback_target_tile = Vector2i(
			roundi(fallback_target_ground_gu.x),
			roundi(fallback_target_ground_gu.y)
		)
	var context := {
		"has_target": usable_target or independent_geometry_target or friendly_cast,
		"line_of_sight": usable_target or independent_geometry_target or friendly_cast,
		"friendly": friendly_cast,
		"hostile": usable_target and not friendly_cast,
		"spell_lock_contract": SpellTargetLockPolicyScript.CONTRACT_ID,
		"spell_lock_range_gu": SpellTargetLockPolicyScript.LOCK_RANGE_GU,
		"target_within_skill_range": target_within_skill_range,
		"target_tile": _canonical_screen_px_to_grid_cell(
			target.global_position
			if usable_target
			else _canonical_grid_cell_to_screen_px(fallback_target_tile)
		),
		"primary_stat_roll": _canonical_primary_stat_roll(str(definition.get("class", ""))),
		"actual_hp_missing": player.max_hp - player.current_hp,
		"friendly_missing_hp": [player.max_hp - player.current_hp],
		"affected_friendly_count": 1,
		"friendly_targets": [{"level": PlayerState.level}],
		"map_allows_random_teleport": true,
		"destination_valid": true,
		"spawn_tile_valid": true,
		"has_main_pet": _canonical_main_pet() != null,
		"current_pet_count": get_tree().get_nodes_in_group("summons").size(),
		"caster_max_hp": player.max_hp,
	}
	var destination := _find_valid_random_teleport_position(origin)
	context["destination_valid"] = destination != origin
	context["destination_tile"] = _canonical_screen_px_to_grid_cell(destination)
	if target != null:
		var monster_data: Dictionary = target.monster_data
		context.merge({
			"target_level": int(monster_data.get("level", target.level)),
			"target_is_boss": target.is_boss,
			"target_immovable": target.is_boss,
			"target_is_monster": true,
			"target_is_undead": bool(monster_data.get("undead", monster_data.get("isUndead", false))),
			"target_tameable": not target.is_boss,
			"target_has_other_master": false,
			"target_max_hp": target.max_hp,
			"target_poison_resist": target.anti_poison,
			"target_is_living": target.current_hp > 0,
			"actual_hp_missing": target.max_hp - target.current_hp,
		}, true)
	var nearby: Array[Dictionary] = []
	var adjacent_ring_cells: Array[Vector2i] = []
	if str(definition.get("geometry", {}).get("shape", "")) == "adjacent_ring":
		var caster_tile := _canonical_screen_px_to_grid_cell(origin)
		for ring_y: int in range(-1, 2):
			for ring_x: int in range(-1, 2):
				if ring_x != 0 or ring_y != 0:
					adjacent_ring_cells.append(
						caster_tile + Vector2i(ring_x, ring_y)
					)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if (
			not node is EnemyActor
			or node.is_queued_for_deletion()
			or not GroundUnitSpaceScript.is_within_range_gu(
				origin_ground_gu,
				_canonical_screen_px_to_ground_gu(node.global_position),
				search_range_gu
			)
		):
			continue
		if (
			not adjacent_ring_cells.is_empty()
			and not bool(CasterSpellGeometryScript.declared_cells_intersect_actor_footprint(
				adjacent_ring_cells,
				_canonical_screen_px_to_ground_gu(node.global_position),
				node.combat_radius_gu
			).get("intersects", false))
		):
			continue
		nearby.append({
			"instance_id": node.get_instance_id(),
			"level": node.level,
			"is_boss": node.is_boss,
			"immovable": node.is_boss,
			"path_blocked": background.is_environment_point_blocked(
				_canonical_ground_gu_to_screen_px(
					_canonical_screen_px_to_ground_gu(node.global_position)
					+ (
						_canonical_screen_px_to_ground_gu(node.global_position)
						- origin_ground_gu
					).normalized()
				)
			),
			"hostile_monster": true,
			"control_immune": node.is_boss,
			"within_level_gate": node.level <= PlayerState.level,
		})
	context["targets"] = nearby
	return context


func _canonical_resource_context(stable_skill_id: String) -> Dictionary:
	var materials := {}
	for material_id: String in CANONICAL_MATERIAL_ITEMS:
		materials[material_id] = PlayerState.item_count(str(CANONICAL_MATERIAL_ITEMS[material_id]))
	var definition := SkillDataLoaderScript.skill(stable_skill_id)
	var selected_material := str(definition.get("resource", {}).get("item", ""))
	if stable_skill_id == "taoist.poison":
		selected_material = "grey_powder" if int(materials.grey_powder) > 0 else "yellow_powder"
	return {
		"mana": player.current_mp,
		"materials": materials,
		"selected_material": selected_material,
	}


func _commit_canonical_resources(result: Dictionary) -> bool:
	var quote: Dictionary = result.get("resource_quote", {})
	var mana_cost := maxi(0, int(quote.get("mp_cost", 0)))
	var material_id := str(quote.get("material_id", ""))
	var material_amount := maxi(0, int(quote.get("material_amount", 0)))
	var item_name := str(CANONICAL_MATERIAL_ITEMS.get(material_id, ""))
	if player.current_mp < mana_cost:
		return false
	if material_amount > 0 and (item_name.is_empty() or PlayerState.item_count(item_name) < material_amount):
		return false
	if not player.spend_mana(mana_cost):
		return false
	if material_amount > 0 and not PlayerState.remove_item(item_name, material_amount):
		player.restore_mana(mana_cost)
		return false
	return true


func _apply_canonical_effects(
	result: Dictionary,
	origin: Vector2,
	direction: Vector2,
	target_context: Dictionary,
	target: EnemyActor = null
) -> void:
	var stable_skill_id := str(result.get("skill_id", ""))
	if not is_instance_valid(target):
		target = null
	var target_position := _canonical_grid_cell_to_screen_px(
		target_context.get("target_tile", _canonical_screen_px_to_grid_cell(origin))
	)
	var geometry_effect := _canonical_primary_damage_effect(result)
	var effective_geometry_cells := _canonical_effective_spell_geometry_cells(
		stable_skill_id,
		result.get("geometry_cells", []),
		geometry_effect
	)
	var continuous_line_strip := _canonical_continuous_line_strip(
		stable_skill_id,
		geometry_effect,
		origin,
		direction
	)
	_spawn_canonical_cast_visual(
		stable_skill_id,
		origin,
		direction,
		target,
		target_position,
		effective_geometry_cells,
		continuous_line_strip
	)
	for raw_effect: Variant in result.get("effects", []):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		var effect_type := str(effect.get("type", ""))
		match effect_type:
			"projectile_damage", "talisman_projectile_damage":
				var projectile_maximum_distance_gu := float(
					SkillDataLoaderScript.skill(stable_skill_id)
					.get("geometry", {})
					.get("maximum_range_gu", 0.0)
				)
				_spawn_projectile(
					origin,
					direction,
					int(effect.get("raw_power", 0)),
					projectile_maximum_distance_gu,
					Color(0.28, 0.62, 1.0) if stable_skill_id.begins_with("wizard.") else Color(0.45, 0.92, 0.55),
					"damage",
					0,
					0.0,
					stable_skill_id
				)
			"targeted_sky_strike", "line_damage", "piercing_line_damage", "area_damage", "caster_centered_area_damage":
				var raw_power := int(effect.get("raw_power_after_race", effect.get("raw_power", 0)))
				var damage_origin := (
					_canonical_grid_cell_to_screen_px(target_context.get("target_tile", Vector2i.ZERO))
					if effect_type == "area_damage"
					else origin
				)
				_apply_canonical_spell_damage(
					stable_skill_id,
					raw_power,
					damage_origin,
					direction,
					effect_type,
					target,
					effective_geometry_cells,
					effect,
					continuous_line_strip
				)
			"persistent_ground_damage":
				_spawn_canonical_ground_field(
					stable_skill_id,
					result.get("geometry_cells", []),
					target_position,
					effect
				)
			"dedicated_heal":
				player.restore_health(int(effect.get("actual_hp_restored", 0)))
			"dedicated_area_heal":
				var restored_by_target: Array = effect.get("actual_hp_restored_by_target", [])
				if not restored_by_target.is_empty():
					player.restore_health(int(restored_by_target[0]))
			"adjacent_push":
				var repulsion_target := _canonical_effect_enemy(effect)
				if repulsion_target != null and bool(effect.get("displaced", false)):
					var source_ground_gu := _canonical_screen_px_to_ground_gu(origin)
					var target_ground_gu := _canonical_screen_px_to_ground_gu(
						repulsion_target.global_position
					)
					var push_direction_ground_gu := (
						target_ground_gu - source_ground_gu
					).normalized()
					_apply_canonical_displacement_screen_px(
						repulsion_target,
						GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
							push_direction_ground_gu
							* float(effect.get("push_distance_gu", 1.0))
						)
					)
			"level_gated_push":
				if target != null and bool(effect.get("displaced", false)):
					_apply_wild_rush_displacement(target, effect, target_context)
			"self_damage":
				_combat_runtime.apply_damage(player, int(effect.get("amount", 1)))
			"server_random_teleport":
				if bool(effect.get("moved", false)):
					var destination := _canonical_grid_cell_to_screen_px(
						effect.get("destination", Vector2i.ZERO)
					)
					if _apply_canonical_player_teleport(destination):
						_spawn_canonical_teleport_arrival(
							stable_skill_id,
							destination,
							direction
						)
			"refreshable_damage_reduction_buff":
				player.apply_magic_shield(float(effect.get("duration_seconds", 1)), float(effect.get("damage_reduction", 0.0)))
			"monster_aggro_stealth", "area_monster_aggro_stealth":
				player.apply_stealth(float(effect.get("duration_seconds", 1)))
			"friendly_defence_buff":
				player.apply_defense_buff(float(effect.get("duration_seconds", 1)), int(effect.get("flat_bonus", 1)))
			"poison_resolution":
				if target != null and not bool(effect.get("resisted", false)):
					_apply_canonical_poison(target, effect)
			"temptation_resolution":
				if target != null:
					_apply_canonical_temptation(target, effect)
			"holy_word_resolution":
				if target != null and bool(effect.get("instant_kill", false)):
					_combat_runtime.apply_enemy_physical_damage(target, target.current_hp, player)
			"hp_information_reveal":
				if target != null and bool(effect.get("revealed", false)):
					hud.show_message("%s：生命%d/%d" % [target.display_name, target.current_hp, target.max_hp], 2.0)
			"monster_boundary_control":
				if int(effect.get("trapped_count", 0)) > 0:
					var boundary_center_screen_px := _canonical_grid_cell_to_screen_px(
						target_context.get("target_tile", Vector2i.ZERO)
					)
					var boundary_radius_gu := maxf(
						0.0,
						float(effect.get("radius_gu", 0.0))
					)
					for node: Node in get_tree().get_nodes_in_group("enemies"):
						if (
							node is EnemyActor
							and _ground_circle_intersects_enemy_footprint_gu(
								boundary_center_screen_px,
								boundary_radius_gu,
								node
							)
						):
							node.apply_control(float(effect.get("duration_seconds", 1)))
			"main_pet_spawn", "recall_existing_main_pet":
				_apply_canonical_main_pet(effect, stable_skill_id)
			"next_melee_charge":
				_set_canonical_fire_charge_expires_at(
					Time.get_ticks_msec() + maxi(1, int(effect.get("charge_lifetime_ms", 10000)))
				)


func _canonical_effect_enemy(effect: Dictionary) -> EnemyActor:
	var instance_id := int(effect.get("target_instance_id", 0))
	if instance_id <= 0:
		return null
	var candidate := instance_from_id(instance_id)
	if (
		candidate is EnemyActor
		and is_instance_valid(candidate)
		and candidate.is_inside_tree()
		and not candidate.is_queued_for_deletion()
	):
		return candidate as EnemyActor
	return null


func _set_canonical_fire_charge_expires_at(expires_at_ms: int) -> void:
	_canonical_fire_charge_expires_ms = maxi(0, expires_at_ms)
	if player != null:
		player.set_fire_sword_charge_display(_canonical_fire_charge_expires_ms)


func _expire_canonical_fire_charge_if_needed() -> void:
	if (
		_canonical_fire_charge_expires_ms > 0
		and Time.get_ticks_msec() >= _canonical_fire_charge_expires_ms
	):
		_set_canonical_fire_charge_expires_at(0)


func _apply_canonical_spell_damage(
	stable_skill_id: String,
	raw_power: int,
	origin: Vector2,
	direction: Vector2,
	effect_type: String,
	primary: EnemyActor,
	raw_geometry_cells: Variant = [],
	effect: Dictionary = {},
	continuous_line_strip: Dictionary = {}
) -> bool:
	var targets: Array[EnemyActor] = []
	var has_declared_geometry_cells := (
		raw_geometry_cells is Array
		and not (raw_geometry_cells as Array).is_empty()
	)
	if stable_skill_id in CANONICAL_WIZARD_GEOMETRY_SKILLS or has_declared_geometry_cells:
		targets = _canonical_spell_geometry_targets(
			stable_skill_id,
			raw_geometry_cells,
			effect,
			continuous_line_strip
		)
	elif effect_type == "targeted_sky_strike" and primary != null:
		targets.append(primary)
	elif primary != null and effect_type not in ["area_damage", "caster_centered_area_damage"]:
		targets.append(primary)
	else:
		var radial: bool = effect_type in ["area_damage", "caster_centered_area_damage"]
		var radius_gu := maxf(0.0, float(effect.get("radius_gu", 0.0)))
		if not radial or radius_gu <= 0.0:
			return false
		for node: Node in get_tree().get_nodes_in_group("enemies"):
			if not node is EnemyActor or node.is_queued_for_deletion():
				continue
			var enemy := node as EnemyActor
			if _ground_circle_intersects_enemy_footprint_gu(
				origin,
				radius_gu,
				enemy
			):
				targets.append(enemy)
	var hit_any := false
	for enemy: EnemyActor in targets:
		var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
			enemy,
			stable_skill_id,
			raw_power,
			player,
			_rng,
			Callable(self, "_resolve_magic_defense")
		)
		hit_any = bool(resolution.get("success", false)) or hit_any
	return hit_any


func _canonical_primary_damage_effect(result: Dictionary) -> Dictionary:
	for raw_effect: Variant in result.get("effects", []):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		if str(effect.get("type", "")) in [
			"line_damage",
			"piercing_line_damage",
			"area_damage",
			"caster_centered_area_damage",
		]:
			return effect
	return {}


func _canonical_effective_spell_geometry_cells(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	effect: Dictionary
) -> Array[Vector2i]:
	var definition := SkillDataLoaderScript.skill(stable_skill_id)
	var geometry: Dictionary = definition.get("geometry", {}).duplicate(true)
	if effect.has("stops_on_terrain"):
		geometry["stops_on_terrain"] = bool(effect.stops_on_terrain)
	return CasterSpellGeometryScript.effective_cells(
		stable_skill_id,
		geometry,
		raw_geometry_cells,
		Callable(self, "_canonical_spell_cell_is_terrain_blocked")
	)


func _canonical_continuous_line_strip(
	stable_skill_id: String,
	effect: Dictionary,
	origin_screen_px: Vector2,
	direction_screen_px: Vector2
) -> Dictionary:
	if (
		stable_skill_id not in CONTINUOUS_WIZARD_LINE_SKILLS
		or str(effect.get("line_geometry_contract", ""))
		!= CasterSpellGeometryScript.CONTINUOUS_AIM_LINE_CONTRACT_ID
	):
		return {}
	var definition := SkillDataLoaderScript.skill(stable_skill_id)
	var geometry: Dictionary = definition.get("geometry", {})
	var effect_length_gu := maxf(
		0.0,
		float(effect.get("effect_length_gu", geometry.get("effect_length_gu", 0.0)))
	)
	var effect_width_gu := maxf(
		0.0001,
		float(effect.get("effect_width_gu", geometry.get("effect_width_gu", 1.0)))
	)
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin_screen_px)
	var direction_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	var strip := CasterSpellGeometryScript.continuous_line_strip(
		origin_ground_gu,
		origin_ground_gu + direction_ground_gu,
		direction_screen_px,
		effect_length_gu,
		effect_width_gu
	)
	if bool(effect.get("stops_on_terrain", geometry.get("stops_on_terrain", false))):
		var unblocked_length_gu := _canonical_continuous_line_unblocked_length_gu(strip)
		if unblocked_length_gu < effect_length_gu:
			strip = CasterSpellGeometryScript.continuous_line_strip(
				origin_ground_gu,
				origin_ground_gu + direction_ground_gu,
				direction_screen_px,
				unblocked_length_gu,
				effect_width_gu
			)
			strip["terrain_truncated"] = true
			strip["source_effect_length_gu"] = effect_length_gu
	strip["integration_contract_id"] = (
		"gameplay.wizard.continuous_line.damage_visual_terrain_shared.v1"
	)
	return strip


func _canonical_continuous_line_unblocked_length_gu(
	line_strip: Dictionary
) -> float:
	var effect_length_gu := maxf(
		0.0,
		float(line_strip.get("effect_length_gu", 0.0))
	)
	if effect_length_gu <= 0.0:
		return 0.0
	var origin_ground_gu: Vector2 = line_strip.get(
		"origin_ground_gu", Vector2.ZERO
	)
	var direction_ground_gu: Vector2 = line_strip.get(
		"direction_ground_gu", Vector2.DOWN
	)
	# Quarter-step centreline sampling is a deterministic supercover for the
	# continuous ray. It catches cells crossed between integer sample points,
	# while the damage width remains independent from terrain traversal.
	const SAMPLE_STEP_GU := 0.25
	var sample_count := ceili(effect_length_gu / SAMPLE_STEP_GU)
	var last_clear_distance_gu := 0.0
	for sample_index: int in range(1, sample_count + 1):
		var distance_gu := minf(
			float(sample_index) * SAMPLE_STEP_GU,
			effect_length_gu
		)
		var sample_ground_gu := (
			origin_ground_gu + direction_ground_gu * distance_gu
		)
		var sample_cell := Vector2i(
			roundi(sample_ground_gu.x),
			roundi(sample_ground_gu.y)
		)
		if _canonical_spell_cell_is_terrain_blocked(sample_cell):
			return last_clear_distance_gu
		last_clear_distance_gu = distance_gu
	return last_clear_distance_gu


func _canonical_spell_cell_is_terrain_blocked(cell: Vector2i) -> bool:
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	if not runtime.is_empty():
		return runtime.get("collision", {}).get("blocked_tiles", []).has(
			"%d,%d" % [cell.x, cell.y]
		)
	return (
		background != null
		and background.has_method("is_environment_point_blocked")
		and bool(background.call(
			"is_environment_point_blocked",
			_canonical_grid_cell_to_screen_px(cell)
		))
	)


func _canonical_spell_geometry_targets(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	effect: Dictionary,
	continuous_line_strip: Dictionary = {}
) -> Array[EnemyActor]:
	var geometry_cells: Array[Vector2i] = []
	if raw_geometry_cells is Array:
		for raw_cell: Variant in raw_geometry_cells:
			if raw_cell is Vector2i:
				geometry_cells.append(raw_cell)
	var targets: Array[EnemyActor] = []
	# Hellfire is a five-tile, one-tile-wide area line. `pierces_units` controls
	# whether units stop the visual/line traversal; it must not turn the area
	# damage into a single-target spell. A negative limit means every hostile
	# footprint intersecting the formal geometry is selected.
	# Both canonical line spells affect every intersecting monster. Limiting the
	# result to the nominal number of cells makes stacked or large-footprint
	# monsters visually intersect the line without receiving damage.
	var maximum_targets := (
		-1
		if stable_skill_id in CONTINUOUS_WIZARD_LINE_SKILLS
		else maxi(0, int(effect.get("maximum_targets", geometry_cells.size())))
	)
	if maximum_targets == 0:
		return targets
	if (
		stable_skill_id in CONTINUOUS_WIZARD_LINE_SKILLS
		and str(continuous_line_strip.get("contract_id", ""))
		== CasterSpellGeometryScript.CONTINUOUS_AIM_LINE_CONTRACT_ID
	):
		var origin_ground_gu: Vector2 = continuous_line_strip.get(
			"origin_ground_gu", Vector2.ZERO
		)
		var direction_ground_gu: Vector2 = continuous_line_strip.get(
			"direction_ground_gu", Vector2.DOWN
		)
		var candidates: Array[Dictionary] = []
		for node: Node in get_tree().get_nodes_in_group("enemies"):
			if (
				not node is EnemyActor
				or node.is_queued_for_deletion()
				or (node as EnemyActor).current_hp <= 0
			):
				continue
			var enemy := node as EnemyActor
			if not CasterSpellGeometryScript.target_footprint_intersects_continuous_line(
				continuous_line_strip,
				_enemy_footprint_polygon_ground_gu(enemy)
			):
				continue
			var enemy_ground_gu := _canonical_screen_px_to_ground_gu(
				enemy.global_position
			)
			candidates.append({
				"enemy": enemy,
				"distance_along_line_gu": (
					(enemy_ground_gu - origin_ground_gu).dot(
						direction_ground_gu
					)
				),
			})
		candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var left_distance := float(left.get("distance_along_line_gu", INF))
			var right_distance := float(right.get("distance_along_line_gu", INF))
			if not is_equal_approx(left_distance, right_distance):
				return left_distance < right_distance
			return (
				(left.get("enemy") as EnemyActor).get_instance_id()
				< (right.get("enemy") as EnemyActor).get_instance_id()
			)
		)
		for candidate: Dictionary in candidates:
			targets.append(candidate.get("enemy") as EnemyActor)
			if maximum_targets > 0 and targets.size() >= maximum_targets:
				break
		return targets
	var selected_instance_ids := {}
	for cell: Vector2i in geometry_cells:
		var cell_targets: Array[EnemyActor] = []
		for node: Node in get_tree().get_nodes_in_group("enemies"):
			if not node is EnemyActor or node.is_queued_for_deletion():
				continue
			var enemy := node as EnemyActor
			if selected_instance_ids.has(enemy.get_instance_id()):
				continue
			var contact := CasterSpellGeometryScript.declared_cells_intersect_actor_footprint(
				[cell],
				_canonical_screen_px_to_ground_gu(enemy.global_position),
				enemy.combat_radius_gu
			)
			if bool(contact.get("intersects", false)):
				cell_targets.append(enemy)
		cell_targets.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
			return a.get_instance_id() < b.get_instance_id()
		)
		for enemy: EnemyActor in cell_targets:
			targets.append(enemy)
			selected_instance_ids[enemy.get_instance_id()] = true
			if maximum_targets > 0 and targets.size() >= maximum_targets:
				return targets
	return targets


func _enemy_footprint_polygon_ground_gu(enemy: EnemyActor) -> PackedVector2Array:
	if not is_instance_valid(enemy):
		return PackedVector2Array()
	return CasterSpellGeometryScript.actor_footprint_polygon_ground_gu(
		_canonical_screen_px_to_ground_gu(enemy.global_position),
		enemy.combat_radius_gu
	)


func _ground_circle_intersects_enemy_footprint_gu(
	center_screen_px: Vector2,
	radius_gu: float,
	enemy: EnemyActor
) -> bool:
	if not is_instance_valid(enemy):
		return false
	var center_ground_gu := _canonical_screen_px_to_ground_gu(center_screen_px)
	var enemy_center_ground_gu := _canonical_screen_px_to_ground_gu(
		enemy.global_position
	)
	var enemy_radius_gu := enemy.combat_radius_gu
	return GroundUnitSpaceScript.is_within_range_gu(
		center_ground_gu,
		enemy_center_ground_gu,
		maxf(0.0, radius_gu) + enemy_radius_gu
	)


func _spawn_canonical_ground_field(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	fallback_position: Vector2,
	effect: Dictionary
) -> void:
	var positions: Array[Vector2] = []
	var coverage_cells: Array[Vector2i] = []
	if raw_geometry_cells is Array:
		for raw_cell: Variant in raw_geometry_cells:
			if raw_cell is Vector2i:
				positions.append(_canonical_grid_cell_to_screen_px(raw_cell))
				coverage_cells.append(raw_cell)
	if positions.is_empty():
		positions.append(fallback_position)
	for index: int in range(positions.size()):
		_spawn_canonical_ground_effect(
			stable_skill_id,
			positions[index],
			effect,
			true,
			coverage_cells[index] if index < coverage_cells.size() else null
		)


func _spawn_canonical_ground_effect(
	stable_skill_id: String,
	position: Vector2,
	effect: Dictionary,
	applies_damage := true,
	coverage_cell: Variant = null
) -> void:
	var ground_effect := GroundSkillEffect.new()
	ground_effect.setup_ground_unit_effect(
		position,
		maxi(0, int(effect.get("raw_power", 0))),
		maxf(0.0, float(effect.get("radius_gu", 0.5))),
		maxf(0.1, float(effect.get("duration_seconds", 1))),
		Color(0.45, 0.72, 1.0),
		stable_skill_id,
		maxf(0.05, float(effect.get("tick_interval_ms", 1000)) / 1000.0),
		74.0
	)
	ground_effect.configure_runtime_resolution(
		player,
		(
			Callable(self, "_apply_canonical_ground_tick").bind(stable_skill_id)
			if applies_damage
			else Callable(self, "_ignore_canonical_ground_visual_tick")
		),
		applies_damage,
		(
			Callable(self, "_canonical_ground_cell_contains_enemy").bind(
				coverage_cell
			)
			if coverage_cell is Vector2i
			else Callable()
		)
	)
	add_child(ground_effect)


func _canonical_ground_cell_contains_enemy(
	enemy: EnemyActor,
	coverage_cell: Vector2i
) -> bool:
	return (
		is_instance_valid(enemy)
		and bool(CasterSpellGeometryScript.declared_cells_intersect_actor_footprint(
			[coverage_cell],
			_canonical_screen_px_to_ground_gu(enemy.global_position),
			enemy.combat_radius_gu
		).get("intersects", false))
	)


func _ignore_canonical_ground_visual_tick(
	_enemy: EnemyActor,
	_raw_power: int
) -> void:
	pass


func _apply_canonical_ground_tick(enemy: EnemyActor, raw_power: int, stable_skill_id: String) -> void:
	_combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		stable_skill_id,
		raw_power,
		player,
		_rng,
		Callable(self, "_resolve_magic_defense")
	)


func _apply_canonical_displacement_screen_px(
	actor: Node2D,
	displacement_screen_px: Vector2
) -> bool:
	if not is_instance_valid(actor):
		return false
	var destination_screen_px := actor.global_position + displacement_screen_px
	var collision_radius_px: float = (
		actor.collision_radius_px
		if actor is EnemyActor
		else ArtSpec.PLAYER_COLLISION_RADIUS_PX
	)
	if WorldSpatialRulesScript.environment_blocks_actor_screen_px(
		background,
		destination_screen_px,
		collision_radius_px
	):
		return false
	actor.global_position = destination_screen_px
	return true


func _apply_canonical_player_teleport(destination: Vector2) -> bool:
	if destination == Vector2.ZERO or WorldSpatialRulesScript.environment_blocks_actor_screen_px(background, destination, ArtSpec.PLAYER_COLLISION_RADIUS_PX):
		return false
	player.global_position = destination
	player.velocity = Vector2.ZERO
	player.movement_performed.emit(player.global_position, player.facing)
	return true


func _apply_canonical_poison(target: EnemyActor, effect: Dictionary) -> void:
	var duration := float(effect.get("duration_seconds", 1))
	if str(effect.get("poison_type", "")) == "green_poison":
		target.apply_poison(int(effect.get("damage_per_tick", 1)), duration)
	else:
		var reduction := maxi(int(effect.get("flat_ac_reduction", 0)), int(effect.get("flat_mac_reduction", 0)))
		target.set_meta("canonical_red_poison", {
			"contract_id": "buff.taoist.red_poison.v1",
			"flat_reduction": reduction,
			"expires_at_ms": Time.get_ticks_msec() + roundi(duration * 1000.0),
		})


func _apply_canonical_temptation(target: EnemyActor, effect: Dictionary) -> void:
	match str(effect.get("outcome", "no_effect")):
		"rooted":
			target.apply_control(float(effect.get("duration_seconds", 1)))
		"confused", "tamed":
			target.apply_charm(float(effect.get("duration_seconds", float(effect.get("loyalty_duration_ms", 1000)) / 1000.0)))
		"instant_kill":
			_combat_runtime.apply_enemy_physical_damage(target, target.current_hp, player)


func _canonical_main_pet() -> SummonActor:
	for node: Node in get_tree().get_nodes_in_group("summons"):
		if node is SummonActor and node.owner_player == player and bool(node.get_meta("taoist_main_pet", false)):
			return node
	return null


func _apply_canonical_main_pet(effect: Dictionary, stable_skill_id: String) -> void:
	var existing := _canonical_main_pet()
	if str(effect.get("type", "")) == "recall_existing_main_pet" and existing != null:
		existing.global_position = _summon_spawn_screen_position_px()
		return
	if existing != null or not bool(effect.get("spawned", false)):
		return
	var summon_name := "神兽" if str(effect.get("template_id", "")) == "divine_beast" else "骷髅"
	var summon := SummonActor.new()
	summon.setup(
		player,
		summon_name,
		maxi(1, _canonical_primary_stat_roll("taoist")),
		int(effect.get("initial_pet_level", 0)),
		stable_skill_id,
		PlayerState.level
	)
	summon.set_meta("taoist_main_pet", true)
	summon.set_meta("taoist_main_pet_contract", "skills.taoist_main_pet.v1")
	summon.global_position = _summon_spawn_screen_position_px()
	add_child(summon)


func _summon_spawn_screen_position_px() -> Vector2:
	var player_ground_gu := _canonical_screen_px_to_ground_gu(
		player.global_position
	)
	var facing_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			player.facing
		).normalized()
	)
	if (
		facing_ground_gu.length_squared()
		<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
	):
		facing_ground_gu = Vector2(1.0, 1.0).normalized()
	var side_direction_ground_gu := Vector2(
		-facing_ground_gu.y,
		facing_ground_gu.x
	)
	var summon_offset_gu := (
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			42.0
		)
	)
	return _canonical_ground_gu_to_screen_px(
		player_ground_gu + side_direction_ground_gu * summon_offset_gu
	)


func _spawn_canonical_cast_visual(
	stable_skill_id: String,
	origin: Vector2,
	direction: Vector2,
	target: EnemyActor,
	target_position: Vector2,
	raw_geometry_cells: Variant = [],
	continuous_line_strip: Dictionary = {}
) -> void:
	if not stable_skill_id.begins_with("wizard.") and not stable_skill_id.begins_with("taoist."):
		return
	var visual_profile := CasterSkillVisualRegistry.profile(stable_skill_id)
	if (
		not CasterSkillVisualRegistry.is_runtime_ready(stable_skill_id)
		or str(visual_profile.get("role", "")) in [
			CasterSkillVisualRegistry.ROLE_PROJECTILE,
			CasterSkillVisualRegistry.ROLE_GROUND_EFFECT,
			CasterSkillVisualRegistry.ROLE_SUMMON_ACTOR,
		]
	):
		return
	var geometry_grid_cells: Array[Vector2i] = []
	var geometry_screen_points_px: Array[Vector2] = []
	if (
		str(continuous_line_strip.get("contract_id", ""))
		== CasterSpellGeometryScript.CONTINUOUS_AIM_LINE_CONTRACT_ID
	):
		geometry_screen_points_px = (
			CasterSpellGeometryScript.continuous_line_world_points(
				continuous_line_strip,
				Callable(self, "_canonical_ground_gu_to_screen_px")
			)
		)
	elif raw_geometry_cells is Array:
		for raw_cell: Variant in raw_geometry_cells:
			if raw_cell is Vector2i:
				geometry_grid_cells.append(raw_cell)
				geometry_screen_points_px.append(_canonical_grid_cell_to_screen_px(raw_cell))
	var visual_plan := {
		"success": true,
		"skill_id": stable_skill_id,
		"operation": "canonical_visual_only",
		"visual": visual_profile,
		"visual_duration": CasterSkillVisualRegistry.animation_duration(stable_skill_id),
		"area_radius": 72.0,
		"canonical_geometry_contract": CASTER_GEOMETRY_VISUAL_CONTRACT_ID,
		"geometry_origin_screen_px": origin,
		"geometry_grid_cells": geometry_grid_cells,
		"geometry_screen_points_px": geometry_screen_points_px,
	}
	for visual_node: Node2D in CasterSkillRuntimeScript.create_cast_nodes(
		visual_plan,
		origin,
		target_position,
		direction,
		Color.WHITE,
		target,
		player,
		_canonical_primary_stat_roll("taoist"),
		PlayerState.level
	):
		add_child(visual_node)


func _spawn_canonical_teleport_arrival(
	stable_skill_id: String,
	destination: Vector2,
	direction: Vector2
) -> void:
	if stable_skill_id != "wizard.teleport":
		return
	var visual_profile := CasterSkillVisualRegistry.profile(stable_skill_id)
	var visual_plan := {
		"success": true,
		"skill_id": stable_skill_id,
		"operation": "canonical_visual_only",
		"visual": visual_profile,
		"visual_duration": CasterSkillVisualRegistry.animation_duration(
			stable_skill_id,
			"arrival"
		),
		"area_radius": 72.0,
	}
	var arrival := CasterSkillRuntimeScript.create_visual(
		visual_plan,
		destination,
		direction,
		player,
		"arrival"
	)
	if arrival != null:
		add_child(arrival)


func _record_player_world_location() -> void:
	if not is_instance_valid(player):
		return
	PlayerState.update_world_location(
		current_map_id,
		player.global_position,
		_ground_position_gu_for_map(current_map_id, player.global_position)
	)


func _ground_position_gu_for_map(
	map_id: int,
	screen_position_px: Vector2
) -> Vector2:
	var runtime := MapEditorRuntimeBridgeScript.load_map(map_id)
	if not runtime.is_empty():
		return MapEditorRuntimeBridgeScript.screen_position_px_to_ground_position_gu(
			runtime,
			screen_position_px
		)
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		screen_position_px
	)


func _canonical_screen_px_to_grid_cell(screen_position_px: Vector2) -> Vector2i:
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	if runtime.is_empty():
		# Legacy/no-runtime maps must use the same 64x32 isometric basis as
		# fractional actor footpoints. The old 48x24 orthogonal fallback made one
		# world position resolve to two different tiles, separating target-centred
		# spell geometry from the monster footprint that selected it.
		var ground_position_gu := (
			GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
				screen_position_px
			)
		)
		return Vector2i(
			roundi(ground_position_gu.x),
			roundi(ground_position_gu.y)
		)
	var ground_position_gu := (
		MapEditorRuntimeBridgeScript.screen_position_px_to_ground_position_gu(
			runtime,
			screen_position_px
		)
	)
	return Vector2i(
		roundi(ground_position_gu.x),
		roundi(ground_position_gu.y)
	)


func _canonical_screen_px_to_ground_gu(screen_position_px: Vector2) -> Vector2:
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	if not runtime.is_empty():
		return MapEditorRuntimeBridgeScript.screen_position_px_to_ground_position_gu(
			runtime,
			screen_position_px
		)
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		screen_position_px
	)


func _canonical_ground_gu_to_screen_px(ground_position_gu: Vector2) -> Vector2:
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	if not runtime.is_empty():
		return MapEditorRuntimeBridgeScript.ground_position_gu_to_screen_position_px(
			runtime,
			ground_position_gu
		)
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		ground_position_gu
	)


func _canonical_grid_cell_to_screen_px(grid_cell: Variant) -> Vector2:
	var tile := Vector2i(grid_cell) if grid_cell is Vector2i else Vector2i.ZERO
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	if runtime.is_empty():
		return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			Vector2(tile)
		)
	return MapEditorRuntimeBridgeScript.ground_position_gu_to_screen_position_px(
		runtime,
		Vector2(tile)
	)


func _canonical_facing(direction: Vector2) -> Vector2i:
	if direction.length_squared() < 0.01:
		return Vector2i.DOWN
	return Vector2i(signi(roundi(direction.x)), signi(roundi(direction.y)))


func _canonical_facing_for_skill(skill_id: String, direction: Vector2) -> Vector2i:
	if skill_id in ["warrior.thrusting", "warrior.half_moon", "warrior.fire_sword"]:
		return WarriorMeleeGeometryScript.facing_tile_step(ArtSpec.direction_index(direction))
	if skill_id in CANONICAL_WIZARD_GEOMETRY_SKILLS:
		return CasterSpellGeometryScript.canonical_facing_from_world_direction(direction)
	return _canonical_facing(direction)


func _canonical_primary_stat_roll(profession_id: String) -> int:
	var minimum_key := "tao_min" if profession_id == "taoist" else ("magic_min" if profession_id == "wizard" else "attack_min")
	var maximum_key := "tao_max" if profession_id == "taoist" else ("magic_max" if profession_id == "wizard" else "attack_max")
	var minimum := int(PlayerState.computed_stats.get(minimum_key, 0))
	var maximum := maxi(minimum, int(PlayerState.computed_stats.get(maximum_key, minimum)))
	return _rng.randi_range(minimum, maximum)


func _next_canonical_seed() -> int:
	_canonical_cast_serial += 1
	return hash([Time.get_ticks_msec(), _canonical_cast_serial, PlayerState.active_profile_id])


func _skill_needs_target(cast_type: String) -> bool:
	return cast_type not in ["passive", "heal", "heal_area", "shield", "stealth", "stealth_area", "magic_defense_buff", "defense_buff", "summon", "teleport"]


func _spawn_projectile(
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	damage: int,
	maximum_distance_gu: float,
	color: Color,
	effect := "damage",
	effect_strength := 0,
	effect_duration := 0.0,
	source_skill_id := ""
) -> void:
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(source_skill_id)
	var formal_maximum_distance_gu := maxf(0.0, maximum_distance_gu)
	if not stable_skill_id.is_empty():
		var definition := SkillDataLoaderScript.skill(stable_skill_id)
		var configured_maximum_distance_gu := float(
			definition.get("geometry", {}).get("maximum_range_gu", 0.0)
		)
		if configured_maximum_distance_gu > 0.0:
			formal_maximum_distance_gu = configured_maximum_distance_gu
	var direction_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	if (
		direction_ground_gu.length_squared()
		<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
	):
		direction_ground_gu = Vector2(1.0, -1.0).normalized()
	var visual_direction_screen_px := direction_screen_px.normalized()
	if visual_direction_screen_px.length_squared() <= 0.000001:
		visual_direction_screen_px = (
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				direction_ground_gu
			).normalized()
		)
	var projectile := SkillProjectile.new()
	projectile.setup_ground_unit_projectile(
		origin_screen_px,
		direction_ground_gu,
		formal_maximum_distance_gu,
		damage,
		CombatUnitLegacyAdapterScript.PROJECTILE_SPEED_GU_PER_SEC,
		CombatUnitLegacyAdapterScript.PROJECTILE_RADIUS_GU,
		visual_direction_screen_px * 24.0,
		color,
		effect,
		effect_strength,
		effect_duration,
		source_skill_id
	)
	projectile.configure_runtime_resolution(player, Callable(self, "_resolve_magic_defense"))
	add_child(projectile)


func _damage_enemies(
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	damage: int,
	radial: bool,
	attack_range_gu := 1.5,
	physical_accuracy := false,
	source_skill_id := ""
) -> bool:
	var hit_any := false
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin_screen_px)
	var direction_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion():
			continue
		var target_ground_gu := _canonical_screen_px_to_ground_gu(
			node.global_position
		)
		var offset_ground_gu := target_ground_gu - origin_ground_gu
		var in_arc := (
			offset_ground_gu.length_squared()
			<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
			or offset_ground_gu.normalized().dot(direction_ground_gu) > -0.05
		)
		if (
			_ground_circle_intersects_enemy_footprint_gu(
				origin_screen_px,
				attack_range_gu,
				node
			)
			and (radial or in_arc)
		):
			if physical_accuracy and not PlayerState.test_mode:
				var accuracy := int(PlayerState.computed_stats.get("accuracy", WarriorCombatMath.BASE_HIT))
				if not WarriorCombatMath.roll_hit(accuracy, node.agility, _rng):
					continue
			var resolved_damage := damage
			if CombatResolutionRulesScript.anti_magic_eligible(source_skill_id):
				var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
					node,
					source_skill_id,
					damage,
					player,
					_rng,
					Callable(self, "_resolve_magic_defense")
				)
				resolved_damage = int(resolution.get("final_damage", 0))
				if resolved_damage > 0:
					hit_any = true
				continue
			if resolved_damage <= 0:
				continue
			hit_any = _combat_runtime.apply_enemy_physical_damage(node, resolved_damage, player) or hit_any
	return hit_any


func _resolve_magic_defense(_skill_id: String, damage_after_anti_magic: int, target_stats: Dictionary) -> int:
	var defense_min := int(
		target_stats.get(
			"magic_defense_min",
			target_stats.get("mdefMin", target_stats.get("MinMAC", 0))
		)
	)
	var defense_max := int(
		target_stats.get(
			"magic_defense_max",
			target_stats.get("mdefMax", target_stats.get("MaxMAC", defense_min))
		)
	)
	defense_min = maxi(0, defense_min)
	defense_max = maxi(defense_min, defense_max)
	return maxi(0, damage_after_anti_magic - _rng.randi_range(defense_min, defense_max))


func _combat_release_target(release_geometry: Dictionary) -> EnemyActor:
	var target_instance_id := int(release_geometry.get("locked_target_instance_id", 0))
	if target_instance_id <= 0 or not bool(
		release_geometry.get("locked_target_valid_at_release", false)
	):
		return null
	var candidate := instance_from_id(target_instance_id)
	if (
		not candidate is EnemyActor
		or not is_instance_valid(candidate)
		or candidate.is_queued_for_deletion()
		or candidate.current_hp <= 0
	):
		return null
	return candidate as EnemyActor


func _physical_primary_target(
	origin: Vector2,
	direction: Vector2,
	mode := "normal",
	release_geometry: Dictionary = {}
) -> EnemyActor:
	var targets := _physical_primary_targets(origin, direction, mode, release_geometry)
	return targets[0] if not targets.is_empty() else null


func _physical_primary_targets(
	origin: Vector2,
	direction: Vector2,
	mode := "normal",
	release_geometry: Dictionary = {}
) -> Array[EnemyActor]:
	# The attack lock owns facing and priority only. Actual damage rights are
	# rebuilt from live footpoints and the selected melee geometry at release.
	# This deliberately overrides the single-target candidate filter used by
	# caster projectiles without changing their shared release contract.
	var result: Array[EnemyActor] = []
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin)
	var direction_index := _melee_direction_index(direction, release_geometry)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion() or node.current_hp <= 0:
			continue
		var enemy := node as EnemyActor
		if not _is_primary_melee_candidate(enemy, origin_ground_gu, direction_index, mode):
			continue
		result.append(enemy)
	_sort_melee_targets(result, origin_ground_gu, release_geometry)
	return result


func _sort_melee_targets(
	targets: Array[EnemyActor],
	origin_ground_gu: Vector2,
	release_geometry: Dictionary
) -> void:
	var locked_instance_id := int(release_geometry.get("locked_target_instance_id", 0))
	if locked_instance_id <= 0 and _is_attack_target_in_range(locked_target):
		locked_instance_id = locked_target.get_instance_id()
	targets.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
		var a_locked := a.get_instance_id() == locked_instance_id
		var b_locked := b.get_instance_id() == locked_instance_id
		if a_locked != b_locked:
			return a_locked
		var a_distance_gu := GroundUnitSpaceScript.distance_gu(
			origin_ground_gu,
			_canonical_screen_px_to_ground_gu(a.global_position)
		)
		var b_distance_gu := GroundUnitSpaceScript.distance_gu(
			origin_ground_gu,
			_canonical_screen_px_to_ground_gu(b.global_position)
		)
		if not is_equal_approx(a_distance_gu, b_distance_gu):
			return a_distance_gu < b_distance_gu
		return a.get_instance_id() < b.get_instance_id()
	)


func _is_primary_melee_candidate(
	enemy: EnemyActor,
	origin_ground_gu: Vector2,
	direction_index: int,
	mode: String
) -> bool:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.current_hp <= 0:
		return false
	var target_ground_gu := _canonical_screen_px_to_ground_gu(enemy.global_position)
	if mode == WarriorMeleeGeometryScript.SKILL_THRUST:
		return WarriorMeleeGeometryScript.thrust_footprint_slot_gu(
			origin_ground_gu,
			target_ground_gu,
			enemy.combat_radius_gu,
			direction_index
		) == 1
	if mode == WarriorMeleeGeometryScript.SKILL_HALF_MOON:
		return WarriorMeleeGeometryScript.half_moon_footprint_relative_sector_gu(
			origin_ground_gu,
			target_ground_gu,
			enemy.combat_radius_gu,
			direction_index
		) == 0
	return WarriorMeleeGeometryScript.footprint_intersects_mode_gu(
		origin_ground_gu,
		target_ground_gu,
		enemy.combat_radius_gu,
		direction_index,
		mode
	)


func _apply_physical_hit(enemy: EnemyActor, damage: int, accuracy_bonus := 0) -> bool:
	if enemy == null or enemy.is_queued_for_deletion():
		return false
	var accuracy := int(
		PlayerState.computed_stats.get("accuracy", WarriorCombatMath.BASE_HIT)
	) + accuracy_bonus
	var target_agility := maxi(1, enemy.agility)
	var hit_roll := -1
	var hit_probability := WarriorCombatMath.hit_probability(accuracy, target_agility)
	if not PlayerState.test_mode:
		hit_roll = _rng.randi_range(0, target_agility - 1)
		if not WarriorCombatMath.hit_succeeds(accuracy, target_agility, hit_roll):
			_active_physical_hit_diagnostics.append({
				"target_id": enemy.get_instance_id(),
				"target_name": enemy.display_name,
				"accuracy": accuracy,
				"accuracy_bonus": accuracy_bonus,
				"target_agility": target_agility,
				"hit_roll": hit_roll,
				"hit_probability": hit_probability,
				"test_mode_bypass": false,
				"requested_damage": maxi(1, damage),
				"result_code": "ACCURACY_MISS",
			})
			return false
	var hp_before := enemy.current_hp
	if not _combat_runtime.apply_enemy_physical_damage(enemy, maxi(1, damage), player):
		_active_physical_hit_diagnostics.append({
			"target_id": enemy.get_instance_id(),
			"target_name": enemy.display_name,
			"accuracy": accuracy,
			"accuracy_bonus": accuracy_bonus,
			"target_agility": target_agility,
			"hit_roll": hit_roll,
			"hit_probability": hit_probability,
			"test_mode_bypass": PlayerState.test_mode,
			"requested_damage": maxi(1, damage),
			"hp_before": hp_before,
			"hp_after": enemy.current_hp,
			"result_code": "DAMAGE_COMMIT_FAILED",
		})
		return false
	_active_physical_hit_diagnostics.append({
		"target_id": enemy.get_instance_id(),
		"target_name": enemy.display_name,
		"accuracy": accuracy,
		"accuracy_bonus": accuracy_bonus,
		"target_agility": target_agility,
		"hit_roll": hit_roll,
		"hit_probability": hit_probability,
		"test_mode_bypass": PlayerState.test_mode,
		"requested_damage": maxi(1, damage),
		"hp_before": hp_before,
		"hp_after": enemy.current_hp,
		"actual_hp_delta": maxi(0, hp_before - enemy.current_hp),
		"result_code": "HIT_COMMITTED",
	})
	var life_steal_percent := int(PlayerState.computed_stats.get("life_steal_percent", 0))
	var recovered := int(float(maxi(1, damage)) * float(life_steal_percent) / 100.0)
	if recovered >= 2:
		player.restore_health(recovered)
	if PlayerState.has_special_effect("paralysis") and EquipmentRulesScript.paralysis_succeeds(enemy.anti_poison, _rng.randi_range(0, maxi(1, enemy.anti_poison + 5) - 1)):
		enemy.apply_control(5.0)
	return true


func _thrust_secondary_targets(
	origin: Vector2,
	direction: Vector2,
	excluded_targets: Array[EnemyActor],
	release_geometry: Dictionary = {}
) -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin)
	var direction_index := _melee_direction_index(direction, release_geometry)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node in excluded_targets or node.is_queued_for_deletion() or node.current_hp <= 0:
			continue
		var enemy := node as EnemyActor
		var target_ground_gu := _canonical_screen_px_to_ground_gu(enemy.global_position)
		if WarriorMeleeGeometryScript.thrust_footprint_slot_gu(
			origin_ground_gu,
			target_ground_gu,
			enemy.combat_radius_gu,
			direction_index
		) != 2:
			continue
		result.append(enemy)
	_sort_melee_targets(result, origin_ground_gu, release_geometry)
	return result


func _half_moon_secondary_targets(
	origin: Vector2,
	direction: Vector2,
	excluded_targets: Array[EnemyActor],
	release_geometry: Dictionary = {}
) -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin)
	var direction_index := _melee_direction_index(direction, release_geometry)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node in excluded_targets or node.is_queued_for_deletion() or node.current_hp <= 0:
			continue
		var enemy := node as EnemyActor
		var target_ground_gu := _canonical_screen_px_to_ground_gu(enemy.global_position)
		var relative_sector := WarriorMeleeGeometryScript.half_moon_footprint_relative_sector_gu(
			origin_ground_gu,
			target_ground_gu,
			enemy.combat_radius_gu,
			direction_index
		)
		if relative_sector == -1 or relative_sector == 0:
			continue
		result.append(enemy)
	_sort_melee_targets(result, origin_ground_gu, release_geometry)
	return result


func _execute_wild_rush(_direction: Vector2, _skill_level: int) -> bool:
	# Compatibility/test entrypoint. Production reaches the same planner through
	# the canonical skill router; input direction and rank cannot alter geometry.
	var target := _select_wild_rush_target()
	if target == null:
		return false
	var plan := _build_wild_rush_path_plan(target)
	var resolved_distance_gu := float(plan.get("resolved_push_distance_gu", 0.0))
	return _apply_wild_rush_displacement(
		target,
		{
			"resolved_push_distance_gu": resolved_distance_gu,
			"displaced": resolved_distance_gu > 0.0,
		},
		plan
	)


func _show_attack_flash(origin: Vector2, direction: Vector2, hit: bool, color: Color) -> void:
	# Removed: the prototype drew a three-point V on every attack and also
	# overlaid the final Magic.wil skill effects.  Finished combat art is owned
	# by PlayerVisual; attacks without formal art deliberately show no fallback.
	return


func _on_enemy_died(enemy: EnemyActor, monster_data: Dictionary) -> void:
	if enemy == locked_target:
		_cancel_target()
	if enemy == magic_locked_target:
		_cancel_magic_target()
	if enemy == _skill_cast_target:
		_skill_cast_target = null
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


func _find_valid_random_teleport_position(origin_screen_px: Vector2) -> Vector2:
	# Every candidate goes through the same world boundary/obstacle contract as
	# movement and monster spawning.  A scroll can never bypass black borders.
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(
		origin_screen_px
	)
	var player_combat_radius_gu := (
		WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			ArtSpec.PLAYER_COLLISION_RADIUS_PX
		)
	)
	for _attempt in range(96):
		var angle := _rng.randf_range(0.0, TAU)
		var distance_gu := _rng.randf_range(
			RANDOM_TELEPORT_MIN_DISTANCE_GU,
			RANDOM_TELEPORT_MAX_DISTANCE_GU
		)
		var candidate_ground_gu := (
			origin_ground_gu + Vector2.from_angle(angle) * distance_gu
		)
		var candidate_screen_px := _canonical_ground_gu_to_screen_px(
			candidate_ground_gu
		)
		if WorldSpatialRulesScript.environment_blocks_actor_screen_px(
			background,
			candidate_screen_px,
			ArtSpec.PLAYER_COLLISION_RADIUS_PX
		):
			continue
		var occupied := false
		for enemy_value: Variant in get_tree().get_nodes_in_group("enemies"):
			if not enemy_value is EnemyActor:
				continue
			var enemy := enemy_value as EnemyActor
			if GroundUnitSpaceScript.distance_gu(
				_canonical_screen_px_to_ground_gu(enemy.global_position),
				candidate_ground_gu
			) < (
				player_combat_radius_gu
				+ enemy.combat_radius_gu
				+ RANDOM_TELEPORT_ACTOR_CLEARANCE_GU
			):
				occupied = true
				break
		if not occupied:
			return candidate_screen_px
	return origin_screen_px


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
