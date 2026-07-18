extends Node

const TEST_DIRECTORY := "user://character_select_gothic_profiles"
const TEST_INDEX := "user://character_select_gothic_index.json"
const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/character_launch_contract_v1.json"

var _old_directory := ""
var _old_index := ""
var _old_test_mode := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_prepare_profiles()
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary, "人物启动契约无法解析")
	assert(contract.get("contractId", "") == "ui.character.launch.v1", "人物启动契约 ID 不稳定")
	assert(contract.get("professionIds", []) == ["warrior", "wizard", "taoist"], "人物创建职业稳定 ID 不完整")
	var launcher: Control = load("res://scenes/character_select.tscn").instantiate()
	launcher.suppress_scene_change_for_test = true
	add_child(launcher)
	await get_tree().process_frame

	assert(launcher.theme != null, "正式人物大厅没有使用公共哥特 Theme")
	assert(launcher.get_node("RosterPanel").theme_type_variation == "GothicInsetFrame", "人物列表没有使用公共内框")
	assert(launcher.get_node("CharacterPreviewPanel").theme_type_variation == "GothicInsetFrame", "人物预览没有使用公共内框")
	assert(launcher.get_node("CreationPanel").theme_type_variation == "GothicInsetFrame", "创建人物没有使用公共内框")
	assert(launcher.list_box != null and launcher.name_input != null, "旧版人物选择兼容入口丢失")
	assert(launcher.profile_cards.size() == 3, "人物列表没有显示三个独立档案")
	assert(launcher.profession_buttons.size() == 3, "创建人物没有显示三职业")
	assert(not launcher.profession_buttons["战士"].disabled, "战士创建按钮被错误禁用")
	assert(not launcher.profession_buttons["法师"].disabled, "法师创建按钮仍处于旧版锁定状态")
	assert(not launcher.profession_buttons["道士"].disabled, "道士创建按钮仍处于旧版锁定状态")
	assert(launcher.profession_buttons["法师"].get_meta("profession_id", "") == "wizard", "法师职业稳定 ID 错误")
	assert(launcher.gender_buttons.size() == 2, "创建人物缺少男女选择")

	launcher._select_main_profile("wizard_01")
	assert(launcher.selected_main_profile_id == "wizard_01", "任意角色没有成功切换为主角色")
	assert(PlayerState.active_profile_id == "wizard_01" and PlayerState.profession == "法师", "选择主角色没有读取对应档案")
	launcher._set_ai_teammate_enabled(true)
	launcher._select_ai_profile("taoist_01")
	assert(launcher.selected_ai_profile_id == "taoist_01", "第二角色没有成功选择为 AI 队友")
	assert(launcher.profile_cards["wizard_01"].ai_button.disabled, "主角色不应允许同时设为自己的 AI 队友")
	var request: Dictionary = launcher.build_launch_request()
	assert(request.contract_id == "ui.character.launch.v1", "启动请求契约 ID 错误")
	assert(request.main_profile_id == "wizard_01", "启动请求主角色错误")
	assert(request.ai_teammate_enabled and request.ai_teammate_profile_id == "taoist_01", "启动请求 AI 队友错误")
	assert(request.ai_control_mode == "companion_ai", "AI 队友控制模式错误")

	launcher._set_ai_teammate_enabled(false)
	request = launcher.build_launch_request()
	assert(not request.ai_teammate_enabled and request.ai_teammate_profile_id.is_empty(), "关闭 AI 队友后启动请求仍携带第二角色")
	launcher._set_ai_teammate_enabled(true)
	launcher._select_main_profile("taoist_01")
	assert(launcher.selected_main_profile_id == "taoist_01", "原 AI 队友不能切换为主角色")
	assert(launcher.selected_ai_profile_id.is_empty(), "AI 队友切换为主角色后没有解除重复选择")
	launcher._select_ai_profile("warrior_01")
	launcher._enter_selected_character()
	assert(launcher.last_launch_request.main_profile_id == "taoist_01", "进入游戏没有使用当前主角色")
	assert(launcher.last_launch_request.ai_teammate_profile_id == "warrior_01", "进入游戏没有使用当前 AI 队友")
	assert(
		get_tree().root.get_meta(launcher.LAUNCH_CONTEXT_META, {}).get("contract_id", "") == "ui.character.launch.v1",
		"人物启动请求没有写入临时场景上下文"
	)

	launcher.name_input.text = "星火"
	launcher._select_creation_profession("法师")
	launcher._select_creation_gender("女")
	var creation_request: Dictionary = launcher.build_creation_request()
	assert(creation_request.contract_id == "ui.character.creation.v1", "人物创建请求契约 ID 错误")
	assert(creation_request.profession_id == "wizard" and creation_request.gender == "女", "人物创建请求没有保留法师/女性选择")
	assert(creation_request.character_name == "星火", "人物创建请求没有保留角色名")

	launcher.queue_free()
	_restore_profiles()
	print("CHARACTER_SELECT_GOTHIC_UI_PASS：哥特大厅、任意主角色、可选 AI 队友和三职业创建请求均正常")
	get_tree().quit(0)


func _prepare_profiles() -> void:
	_cleanup()
	_old_directory = PlayerState.profile_directory
	_old_index = PlayerState.profile_index_path
	_old_test_mode = PlayerState.test_mode
	PlayerState.profile_directory = TEST_DIRECTORY
	PlayerState.profile_index_path = TEST_INDEX
	PlayerState.test_mode = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	var profiles := [
		{"id": "warrior_01", "name": "北辰", "profession": "战士", "gender": "男", "level": 26, "updated_at": 300},
		{"id": "wizard_01", "name": "星火", "profession": "法师", "gender": "女", "level": 22, "updated_at": 200},
		{"id": "taoist_01", "name": "青灯", "profession": "道士", "gender": "男", "level": 18, "updated_at": 100},
	]
	for profile: Dictionary in profiles:
		_write_json(TEST_DIRECTORY + "/" + str(profile.id) + ".json", _profile_payload(profile))
	_write_json(TEST_INDEX, {"version": 1, "profiles": profiles})
	PlayerState.active_profile_id = "warrior_01"
	assert(PlayerState.select_character("warrior_01"), "无法载入人物大厅主角色夹具")


func _profile_payload(profile: Dictionary) -> Dictionary:
	return {
		"save_version": PlayerState.SAVE_VERSION,
		"profile_id": profile.id,
		"character_name": profile.name,
		"updated_at": profile.updated_at,
		"level": profile.level,
		"profession": profile.profession,
		"gender": profile.gender,
		"later_content_enabled": false,
		"game_mode_id": "classic_176",
		"experience": 0,
		"gold": 1000,
		"inventory": [],
		"warehouse_inventory": [],
		"equipment": {},
		"learned_skills": {},
		"quick_slots": ["", "", "", ""],
		"quest_states": {},
		"content_packages": [],
		"content_schema_version": 1,
		"map_id": 4,
		"position": [0.0, 0.0],
	}


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "无法写入人物大厅测试夹具")
	file.store_string(JSON.stringify(value, "\t"))
	file.close()


func _restore_profiles() -> void:
	PlayerState.profile_directory = _old_directory
	PlayerState.profile_index_path = _old_index
	PlayerState.test_mode = _old_test_mode
	PlayerState.active_profile_id = ""
	_cleanup()


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var index_path := TEST_INDEX + suffix
		if FileAccess.file_exists(index_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path))
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_directory):
		var directory := DirAccess.open(TEST_DIRECTORY)
		if directory != null:
			for file_name: String in directory.get_files():
				DirAccess.remove_absolute(absolute_directory.path_join(file_name))
		DirAccess.remove_absolute(absolute_directory)
