extends Node

const TEST_PROFILE_ID := "production_wizard_canonical_only_v1"
const FIXTURE_MONSTER_ID := 19
## Authored world_bich_province monster_id=19 spawn tile [40, 13].
const FIXTURE_GROUND_POSITION := Vector2(40.5, 13.5)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_profile_directory: String = PlayerState.profile_directory
	var original_profile_index_path: String = PlayerState.profile_index_path
	var original_shared_warehouse_path: String = PlayerState.shared_warehouse_path
	var original_transaction_path: String = PlayerState.shared_warehouse_transaction_log_path
	var original_test_mode: bool = PlayerState.test_mode
	var original_active_profile_id: String = PlayerState.active_profile_id
	var original_warehouse_inventory: Array = PlayerState.warehouse_inventory.duplicate(true)
	var original_shared_initialized: bool = PlayerState._shared_warehouse_initialized
	var original_warehouse_locked: bool = PlayerState._warehouse_transaction_locked
	var original_persistence_in_progress: bool = PlayerState._persistence_transaction_in_progress
	var original_save_blocked_profile_id: String = PlayerState._save_blocked_profile_id
	var original_save_blocked_reason: String = PlayerState._save_blocked_reason
	var test_root := "user://production_profile_hud_route_test_%d_%d" % [
		Time.get_ticks_usec(),
		OS.get_process_id(),
	]
	var test_profile_directory := test_root.path_join("characters")
	var test_profile_index := test_root.path_join("character_profiles.json")
	var test_shared_warehouse_path := test_root.path_join("shared_warehouse.json")
	var test_transaction_path := test_root.path_join("shared_warehouse.transaction.json")
	PlayerState.test_mode = true
	PlayerState.active_profile_id = ""
	PlayerState.profile_directory = test_profile_directory
	PlayerState.profile_index_path = test_profile_index
	PlayerState.shared_warehouse_path = test_shared_warehouse_path
	PlayerState.shared_warehouse_transaction_log_path = test_transaction_path
	PlayerState.warehouse_inventory = []
	PlayerState._shared_warehouse_initialized = false
	PlayerState._warehouse_transaction_locked = false
	PlayerState._persistence_transaction_in_progress = false
	PlayerState._save_blocked_profile_id = ""
	PlayerState._save_blocked_reason = ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_profile_directory))
	var profile_path := test_profile_directory.path_join("%s.json" % TEST_PROFILE_ID)
	assert(PlayerState._write_json_atomic(profile_path, {
		"save_version": PlayerState.SAVE_VERSION,
		"profile_id": TEST_PROFILE_ID,
		"character_name": "生产链路法师",
		"updated_at": int(Time.get_unix_time_from_system()),
		"level": 50,
		"profession": "法师",
		"gender": "男",
		"later_content_enabled": false,
		"game_mode_id": "classic_176",
		"experience": 0,
		"gold": 0,
		"inventory": [],
		"warehouse_inventory": [],
		"equipment": {},
		# This is deliberately canonical-only. request_skill must not depend on
		# the deprecated Chinese-name dictionary being populated.
		"learned_skills": {},
		"skill_progression": {
			"contract_id": "skills.progression.cn_mir2_176.v1",
			"skills": {
				"wizard.lightning": {"rank": 3, "current_proficiency": 0},
			},
		},
		"quick_slots": ["雷电术", "", "", ""],
		"warrior_runtime_state": {},
		"quest_states": {},
		"content_packages": ContentLayers.enabled_package_ids(),
		"content_schema_version": 1,
		"map_id": 4,
		"position": [0.0, 0.0],
	}), "不能创建隔离的非 test_mode 角色存档")
	PlayerState.test_mode = false
	assert(PlayerState.select_character(TEST_PROFILE_ID), "非 test_mode 角色存档不能被正式入口选中")
	assert(PlayerState.learned_skills.is_empty(), "测试前提失效：旧中文技能字典不应被自动填充")
	assert(PlayerState.is_skill_learned("雷电术"), "canonical-only 存档没有被识别为已学习雷电术")

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_formal_world(game)
	var caster: PlayerCharacter = game.player
	caster.current_mp = 100
	var caster_ground: Vector2 = FIXTURE_GROUND_POSITION - Vector2(2.0, 0.0)
	var caster_position: Vector2 = game._canonical_ground_gu_to_screen_px(caster_ground)
	var target_position: Vector2 = game._canonical_ground_gu_to_screen_px(FIXTURE_GROUND_POSITION)
	assert(caster_position.is_finite() and target_position.is_finite(), "HUD canonical fixture needs a finite map projection")
	game._set_player_world_position(caster_position)
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			caster_ground,
			game._active_safe_zones,
		)
			and not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
				FIXTURE_GROUND_POSITION,
				game._active_safe_zones,
			),
		"HUD canonical fixture must be outside the authored safe area"
	)
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = caster.global_position + Vector2(3000, 3000)
	var target: EnemyActor = _make_enemy(game, caster, target_position)
	game.locked_target = target
	game._set_magic_locked_target(target, true)
	game._skill_cast_target = target
	var emitted_skill_names: Array[String] = []
	caster.skill_requested.connect(func(skill_name: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void:
		emitted_skill_names.append(skill_name)
	)
	var hp_before := target.current_hp
	var mp_before := caster.current_mp
	assert(
		game.hud.attack_ring_skill_buttons.size() >= 1,
		"正式HUD技能环必须先构造攻击环按钮"
	)
	var skill_button: Button = game.hud.attack_ring_skill_buttons[0]
	assert(
		str(game.hud.attack_ring_skill_icons[0].get_meta("skill_name", "")) == "雷电术",
		"canonical-only profile did not populate the formal first attack-ring slot"
	)
	var skill_touch := InputEventScreenTouch.new()
	skill_touch.index = 7001
	skill_touch.position = skill_button.size * 0.5
	skill_touch.pressed = true
	skill_button.call("_gui_input", skill_touch)
	skill_touch.pressed = false
	skill_button.call("_gui_input", skill_touch)
	await get_tree().create_timer(0.8).timeout
	if target.current_hp >= hp_before:
		print(
			("PROFILE_HUD_LIGHTNING_FAILURE emitted=%s target_px=%s target_ground=%s "
			+ "caster_ground=%s runtime_map=%d target_map=%d projection=%s spatial=%d safe=%s "
			+ "in_range=%s hp_before=%d hp_after=%d mp_before=%d mp_after=%d "
			+ "projection_rejection=%s missing_projection=%d")
			% [
				str(emitted_skill_names),
				str(target.global_position),
				str(game._canonical_screen_px_to_ground_gu(target.global_position)),
				str(game._canonical_screen_px_to_ground_gu(caster.global_position)),
				int(game.get("current_map_id")),
				target.runtime_map_id,
				str(target.projection_ready()),
				target.spatial_actor_runtime_id,
				str(WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(FIXTURE_GROUND_POSITION, game._active_safe_zones)),
				str(game._is_magic_target_in_range(target)),
				hp_before,
				target.current_hp,
				mp_before,
				caster.current_mp,
				str(game.projection_rejection_reason),
				game.missing_projection_rejection_count,
			]
		)
	assert(
		emitted_skill_names == ["雷电术"],
		"真实 HUD 按键没有经 Player.request_skill 发出唯一技能请求"
	)
	assert(
		target.current_hp < hp_before,
		"非 test_mode 角色的 HUD 技能请求没有进入 canonical GameRoot 结算"
	)
	assert(caster.current_mp == mp_before - 15, "真实 HUD 链路没有按 canonical rank3 唯一扣除 15 MP")

	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	PlayerState.test_mode = true
	PlayerState.active_profile_id = ""
	_remove_exact_file(profile_path)
	_remove_exact_file(profile_path + ".bak")
	_remove_exact_file(profile_path + ".tmp")
	_remove_exact_file(test_profile_index)
	_remove_exact_file(test_profile_index + ".bak")
	_remove_exact_file(test_profile_index + ".tmp")
	_remove_exact_file(test_shared_warehouse_path)
	_remove_exact_file(test_shared_warehouse_path + ".bak")
	_remove_exact_file(test_shared_warehouse_path + ".tmp")
	_remove_exact_file(test_transaction_path)
	_remove_exact_file(test_transaction_path + ".bak")
	_remove_exact_file(test_transaction_path + ".tmp")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_profile_directory))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_root))
	PlayerState.profile_directory = original_profile_directory
	PlayerState.profile_index_path = original_profile_index_path
	PlayerState.shared_warehouse_path = original_shared_warehouse_path
	PlayerState.shared_warehouse_transaction_log_path = original_transaction_path
	PlayerState.active_profile_id = original_active_profile_id
	PlayerState.test_mode = original_test_mode
	PlayerState.warehouse_inventory = original_warehouse_inventory
	PlayerState._shared_warehouse_initialized = original_shared_initialized
	PlayerState._warehouse_transaction_locked = original_warehouse_locked
	PlayerState._persistence_transaction_in_progress = original_persistence_in_progress
	PlayerState._save_blocked_profile_id = original_save_blocked_profile_id
	PlayerState._save_blocked_reason = original_save_blocked_reason
	print("PRODUCTION_PROFILE_HUD_CANONICAL_ROUTE_PASS: non-test profile -> HUD -> Player -> canonical runtime")
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var canonical_data: Dictionary = GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"HUD canonical fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	var enemy: EnemyActor = game._spawn_enemy(
		canonical_data,
		position,
		false,
		-1.0,
		{
			"respawn_enabled": false,
			"spawn_slot_id": "test:profile_hud:19",
		},
	)
	assert(
		enemy != null
			and enemy.monster_id == FIXTURE_MONSTER_ID
			and not enemy.is_boss
			and enemy.runtime_map_id == int(game.get("current_map_id"))
			and enemy.projection_ready()
			and enemy.spatial_actor_runtime_id > 0,
		"HUD canonical fixture must use the formal exact-ID mapped spawn"
	)
	enemy.max_hp = 9999
	enemy.current_hp = enemy.max_hp
	enemy.control_time = 60.0
	assert(
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and enemy.can_receive_damage(),
		"HUD canonical fixture target must survive exact-ID admission"
	)
	return enemy


func _wait_for_formal_world(game: Node) -> void:
	var deadline_ms: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline_ms:
		var current_map_id: int = int(game.get("current_map_id"))
		var input_enabled: bool = bool(game.call("gameplay_input_is_enabled"))
		if current_map_id >= 0 and input_enabled:
			break
		await get_tree().process_frame
	assert(
		int(game.get("current_map_id")) == GameData.service_runtime_map_id(0),
		"HUD canonical fixture must wait for the formal mapped world"
	)
	assert(not game._active_safe_zones.is_empty(), "HUD canonical fixture needs the formal safe-zone context")


func _remove_exact_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
