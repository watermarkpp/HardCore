extends Node

const TEST_ROOT := "user://production_profile_hud_route_test"
const TEST_PROFILE_DIRECTORY := TEST_ROOT + "/characters"
const TEST_PROFILE_INDEX := TEST_ROOT + "/character_profiles.json"
const TEST_PROFILE_ID := "production_wizard_canonical_only_v1"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_profile_directory: String = PlayerState.profile_directory
	var original_profile_index_path: String = PlayerState.profile_index_path
	var original_test_mode: bool = PlayerState.test_mode
	var original_active_profile_id: String = PlayerState.active_profile_id
	PlayerState.test_mode = true
	PlayerState.active_profile_id = ""
	PlayerState.profile_directory = TEST_PROFILE_DIRECTORY
	PlayerState.profile_index_path = TEST_PROFILE_INDEX
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_PROFILE_DIRECTORY))
	var profile_path := "%s/%s.json" % [TEST_PROFILE_DIRECTORY, TEST_PROFILE_ID]
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
	var caster: PlayerCharacter = game.player
	caster.current_mp = 100
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = caster.global_position + Vector2(3000, 3000)
	var target := _make_enemy(game, caster, caster.global_position + Vector2(80, 0))
	game.locked_target = target
	var emitted_skill_names: Array[String] = []
	caster.skill_requested.connect(func(skill_name: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void:
		emitted_skill_names.append(skill_name)
	)
	var hp_before := target.current_hp
	var mp_before := caster.current_mp
	game.hud.quick_buttons[0].pressed.emit()
	await get_tree().create_timer(0.8).timeout
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
	_remove_exact_file(TEST_PROFILE_INDEX)
	_remove_exact_file(TEST_PROFILE_INDEX + ".bak")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE_DIRECTORY))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ROOT))
	PlayerState.profile_directory = original_profile_directory
	PlayerState.profile_index_path = original_profile_index_path
	PlayerState.active_profile_id = original_active_profile_id
	PlayerState.test_mode = original_test_mode
	print("PRODUCTION_PROFILE_HUD_CANONICAL_ROUTE_PASS: non-test profile -> HUD -> Player -> canonical runtime")
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "HUD canonical 目标",
		"hp": 9999,
		"attackMin": 1,
		"attackMax": 1,
		"level": 1,
		"anti_magic_points": 0,
		"magic_defense_min": 0,
		"magic_defense_max": 0,
	}, caster, false)
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	return enemy


func _remove_exact_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
