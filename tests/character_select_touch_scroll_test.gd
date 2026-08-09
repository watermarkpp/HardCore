extends Node

const TouchScrollSupportScript := preload("res://scripts/touch_scroll_support.gd")

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
	assert(
		launcher.profile_scroll.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID,
		"角色列表未接入共享触摸滚动策略"
	)
	var support := get_tree().root.get_node_or_null("TouchScrollSupport")
	assert(support != null, "共享 TouchScrollSupport 未由角色选择 attach_tree 创建")

	# 共享服务内部路径：向上拖内容应滚动，松手后服务状态复位。
	var touch_start: Vector2 = launcher.profile_scroll.get_global_rect().get_center()
	support.call("_begin_drag_candidate", touch_start, 7)
	var drag_position := touch_start - Vector2(0, 190)
	support.call("_continue_drag", drag_position, Vector2(0, -190))
	assert(launcher.profile_scroll.scroll_vertical > 0, "手指向上拖动没有让角色列表向下滚动")
	assert(bool(support.get("_dragging")), "共享服务应处于拖动状态")
	support.call("_end_drag")
	assert(
		int(support.get("_active_touch_index")) == -1 and not bool(support.get("_dragging")),
		"触摸松手后共享服务仍残留拖动状态"
	)

	# 真实 GUI 触摸路径：拖动期间角色卡 pressed 不得触发，选择不得被误改。
	launcher.profile_scroll.scroll_vertical = 0
	await get_tree().process_frame
	var main_card_button: Button = launcher.profile_cards["touch_00"].main_button as Button
	var card_presses: Array[int] = [0]
	main_card_button.pressed.connect(func() -> void: card_presses[0] += 1)
	var window_scale: Vector2 = Vector2(get_window().size) / get_viewport().get_visible_rect().size
	var card_center := main_card_button.get_global_rect().get_center()
	var gui_down := InputEventScreenTouch.new()
	gui_down.index = 8
	gui_down.pressed = true
	gui_down.position = card_center * window_scale
	get_viewport().push_input(gui_down)
	assert(main_card_button.button_pressed, "触摸按下未到达角色卡按钮")
	var gui_drag := InputEventScreenDrag.new()
	gui_drag.index = 8
	gui_drag.position = (card_center + Vector2(0, 16)) * window_scale
	gui_drag.relative = Vector2(0, 16) * window_scale.y
	get_viewport().push_input(gui_drag)
	support.call("_input", gui_drag)
	var gui_up := InputEventScreenTouch.new()
	gui_up.index = 8
	gui_up.pressed = false
	gui_up.position = gui_drag.position
	get_viewport().push_input(gui_up)
	support.call("_input", gui_up)
	assert(card_presses[0] == 0, "拖动松手误触发了角色卡点击")
	assert(launcher.selected_main_profile_id == initial_main, "拖动后主角色选择被误改")
	# 正常点击不受拖动逻辑影响。
	main_card_button.pressed.emit()
	assert(launcher.selected_main_profile_id == "touch_00", "正常点击角色卡未能选择")
	launcher._set_ai_teammate_enabled(true)
	(launcher.profile_cards["touch_01"].ai_button as Button).pressed.emit()
	assert(launcher.selected_ai_profile_id == "touch_01", "正常AI队友按钮点击失败")

	# 边界与阈值：大拖向下停在底部，大拖向上回到顶部，阈值内不滚动。
	var maximum_scroll := int(round(scroll_bar.max_value - scroll_bar.page))
	support.call("_begin_drag_candidate", touch_start, 9)
	support.call("_continue_drag", touch_start - Vector2(0, 5000), Vector2(0, -5000))
	assert(
		absf(float(launcher.profile_scroll.scroll_vertical) - float(maximum_scroll)) <= 1.0,
		"角色列表向下滚动未到达底部边界"
	)
	support.call("_end_drag")
	support.call("_begin_drag_candidate", touch_start, 10)
	support.call("_continue_drag", touch_start + Vector2(0, 5000), Vector2(0, 5000))
	assert(launcher.profile_scroll.scroll_vertical == 0, "角色列表向上滚动越过顶部边界未被正确约束")
	support.call("_end_drag")
	var threshold_start: int = launcher.profile_scroll.scroll_vertical
	support.call("_begin_drag_candidate", touch_start, 11)
	support.call("_continue_drag", touch_start + Vector2(0, 4), Vector2(0, 4))
	assert(launcher.profile_scroll.scroll_vertical == threshold_start, "阈值内轻微移动被错误识别为滚动")
	support.call("_end_drag")
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
