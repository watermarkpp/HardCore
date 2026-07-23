extends Node

const TEST_DIRECTORY := "user://character_select_touch_profiles"
const TEST_INDEX := "user://character_select_touch_index.json"

var _old_directory := ""
var _old_index := ""
var _old_test_mode := false
var _old_viewport_size := Vector2i.ZERO


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_prepare_profiles()
	_old_viewport_size = get_tree().root.size
	get_tree().root.size = Vector2i(2664, 1200)
	var launcher: Control = load("res://scenes/character_select.tscn").instantiate()
	launcher.suppress_scene_change_for_test = true
	add_child(launcher)
	await get_tree().process_frame
	await get_tree().process_frame

	assert(get_tree().root.size == Vector2i(2664, 1200), "人物选择触控专项没有运行在2664x1200视口")
	assert(
		launcher.profile_scroll.get_meta("touch_scroll_contract", "") == launcher.ROSTER_TOUCH_SCROLL_CONTRACT_ID,
		"角色列表没有声明稳定触摸拖动契约"
	)
	assert(launcher.profile_cards.size() == 11, "触摸滚动夹具没有覆盖超过首屏的角色列表")
	var scroll_bar: VScrollBar = launcher.profile_scroll.get_v_scroll_bar()
	assert(scroll_bar.max_value > scroll_bar.page, "11个角色没有形成可滚动内容")

	launcher._select_main_profile("touch_01")
	var initial_main: String = launcher.selected_main_profile_id
	var touch_start: Vector2 = launcher.profile_scroll.get_global_rect().get_center()
	var touch_press := InputEventScreenTouch.new()
	touch_press.index = 7
	touch_press.position = touch_start
	touch_press.pressed = true
	launcher._input(touch_press)
	var touch_drag := InputEventScreenDrag.new()
	touch_drag.index = 7
	touch_drag.position = touch_start - Vector2(0, 190)
	launcher._input(touch_drag)
	var touch_release := InputEventScreenTouch.new()
	touch_release.index = 7
	touch_release.position = touch_drag.position
	touch_release.pressed = false
	launcher._input(touch_release)
	assert(not launcher._roster_drag_candidate, "触摸松手后仍残留拖动候选状态")
	assert(launcher.profile_scroll.scroll_vertical > 0, "手指向上拖动没有让角色列表向下滚动")
	(launcher.profile_cards["touch_00"].main_button as Button).pressed.emit()
	assert(launcher.selected_main_profile_id == initial_main, "拖动松手误触发了主角色选择")

	launcher._set_ai_teammate_enabled(true)
	launcher._select_ai_profile("touch_02")
	var initial_ai: String = launcher.selected_ai_profile_id
	launcher._begin_roster_drag(Vector2(600, 600), 8)
	launcher._update_roster_drag(Vector2(600, 430))
	launcher._finish_roster_drag()
	(launcher.profile_cards["touch_03"].ai_button as Button).pressed.emit()
	assert(launcher.selected_ai_profile_id == initial_ai, "拖动松手误触发了AI伙伴按钮")

	await get_tree().create_timer(0.5).timeout
	launcher._begin_roster_drag(Vector2(600, 600), 9)
	launcher._update_roster_drag(Vector2(600, 594))
	assert(not launcher._finish_roster_drag(), "阈值内轻微移动被错误识别为拖动")
	(launcher.profile_cards["touch_00"].main_button as Button).pressed.emit()
	assert(launcher.selected_main_profile_id == "touch_00", "正常点击因触摸拖动逻辑而失效")
	(launcher.profile_cards["touch_03"].ai_button as Button).pressed.emit()
	assert(launcher.selected_ai_profile_id == "touch_03", "正常AI伙伴按钮点击因拖动互斥逻辑而失效")

	launcher._begin_roster_drag(Vector2(600, 300), 10)
	launcher._update_roster_drag(Vector2(600, 3000))
	launcher._finish_roster_drag()
	assert(launcher.profile_scroll.scroll_vertical == 0, "角色列表向上边界产生越界滚动")
	await get_tree().create_timer(0.5).timeout
	launcher._begin_roster_drag(Vector2(600, 900), 11)
	launcher._update_roster_drag(Vector2(600, -5000))
	launcher._finish_roster_drag()
	var maximum_scroll := int(round(scroll_bar.max_value - scroll_bar.page))
	assert(
		abs(launcher.profile_scroll.scroll_vertical - maximum_scroll) <= 1,
		"角色列表向下边界没有被ScrollContainer正确约束"
	)

	launcher.queue_free()
	get_tree().root.size = _old_viewport_size
	_restore_profiles()
	print("CHARACTER_SELECT_TOUCH_SCROLL_PASS：2664x1200直接拖动、点击互斥、AI按钮和上下边界正常")
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
	var profiles: Array = []
	var professions := ["战士", "法师", "道士"]
	for index in range(11):
		var profile := {
			"id": "touch_%02d" % index,
			"name": "触控%02d" % index,
			"profession": professions[index % professions.size()],
			"gender": "男",
			"level": 20 + index,
			"updated_at": 500 - index,
		}
		profiles.append(profile)
		_write_json(TEST_DIRECTORY + "/" + str(profile.id) + ".json", _profile_payload(profile))
	_write_json(TEST_INDEX, {"version": 1, "profiles": profiles})
	PlayerState.active_profile_id = "touch_00"
	assert(PlayerState.select_character("touch_00"), "无法载入角色列表触控夹具")


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
	assert(file != null, "无法写入角色列表触控夹具")
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
