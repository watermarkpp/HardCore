extends Node

const TEST_DIRECTORY := "user://character_select_paper_doll_profiles"
const TEST_INDEX := "user://character_select_paper_doll_index.json"

var _old_directory := ""
var _old_index := ""
var _old_test_mode := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_prepare_profiles()
	var launcher: Control = load("res://scenes/character_select.tscn").instantiate()
	launcher.suppress_scene_change_for_test = true
	add_child(launcher)
	await get_tree().process_frame

	assert(launcher.selected_main_profile_id == "warrior_equipped")
	var preview_root: Control = launcher.preview_visual_root
	assert(preview_root.get_child_count() == 1, "人物选择页同时挂载了多套纸娃娃")
	var paper_doll: EquipmentCharacterPreview = preview_root.get_child(0)
	assert(paper_doll.position == Vector2.ZERO)
	assert(paper_doll.size == preview_root.size, "人物选择页纸娃娃没有填满预览容器")
	assert(paper_doll.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(paper_doll.presentation_mode == "classic_avatar", "人物选择页必须默认使用透明原客户端纸娃娃")
	assert(not paper_doll.uses_world_avatar(), "人物选择页不得使用低清世界人物图集")
	assert(not paper_doll.uses_original_client_stage(), "人物选择页错误加载完整Prguse装备页")
	_assert_classic_avatar_only(paper_doll, "战士人物选择页")
	assert(
		str(paper_doll._equipment_snapshot.get("衣服", {}).get("name", ""))
		== "战神盔甲(男)",
		"人物选择页没有读取选中人物档案的衣服"
	)

	# Deliberately poison the global runtime equipment. Rebuilding the preview
	# must still use the selected archive rather than whichever profile happens
	# to be resident in PlayerState.
	PlayerState.equipment["衣服"] = {"name": "布衣(男)"}
	launcher._refresh_character_preview()
	paper_doll = preview_root.get_child(0)
	assert(
		str(paper_doll._equipment_snapshot.get("衣服", {}).get("name", ""))
		== "战神盔甲(男)",
		"人物选择页错误使用了 PlayerState.equipment 代替选中档案"
	)
	assert(paper_doll.get_meta("preview_profile_id", "") == "warrior_equipped")
	assert(
		paper_doll.get_meta("preview_source", "")
		== "selected_profile_save_equipment"
	)

	launcher._select_main_profile("wizard_equipped")
	await get_tree().process_frame
	assert(preview_root.get_child_count() == 1, "切换人物后旧纸娃娃没有移除")
	paper_doll = preview_root.get_child(0)
	assert(paper_doll.profession_name == "法师")
	assert(paper_doll.presentation_mode == "classic_avatar", "切换人物后没有保持透明原客户端纸娃娃")
	_assert_classic_avatar_only(paper_doll, "法师人物选择页")
	assert(
		str(paper_doll._equipment_snapshot.get("衣服", {}).get("name", ""))
		== "恶魔长袍(男)",
		"切换人物后纸娃娃没有立即切换到该档案装备"
	)

	launcher.queue_free()
	_restore_profiles()
	print("CHARACTER_SELECT_PAPER_DOLL_PROFILE_PASS")
	get_tree().quit(0)


func _assert_classic_avatar_only(preview: EquipmentCharacterPreview, label: String) -> void:
	assert(preview.has_renderable_assets(), "%s缺少透明原客户端人物底图" % label)
	assert(preview.has_renderable_hair(), "%s缺少男性纸娃娃头发" % label)
	assert(preview.original_stage_draw_commands().is_empty(), "%s错误绘制完整装备页背景或槽位" % label)
	assert(preview._body_texture != null, "%s没有衣服层" % label)
	assert(preview._weapon_texture != null, "%s没有武器层" % label)
	assert(preview._helmet_texture != null, "%s没有头盔层" % label)


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
		{
			"id": "warrior_equipped",
			"name": "赤月战士",
			"profession": "战士",
			"gender": "男",
			"level": 50,
			"updated_at": 200,
		},
		{
			"id": "wizard_equipped",
			"name": "祖玛法师",
			"profession": "法师",
			"gender": "男",
			"level": 50,
			"updated_at": 100,
		},
	]
	_write_json(
		TEST_DIRECTORY + "/warrior_equipped.json",
		_profile_payload(profiles[0], {
			"衣服": {"name": "战神盔甲(男)"},
			"武器": {"name": "裁决之杖"},
			"头盔": {"name": "黑铁头盔"},
		})
	)
	_write_json(
		TEST_DIRECTORY + "/wizard_equipped.json",
		_profile_payload(profiles[1], {
			"衣服": {"name": "恶魔长袍(男)"},
			"武器": {"name": "骨玉权杖"},
			"头盔": {"name": "法神头盔"},
		})
	)
	_write_json(TEST_INDEX, {"version": 1, "profiles": profiles})
	PlayerState.active_profile_id = "warrior_equipped"
	assert(PlayerState.select_character("warrior_equipped"))


func _profile_payload(profile: Dictionary, equipment: Dictionary) -> Dictionary:
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
		"gold": 0,
		"inventory": [],
		"warehouse_inventory": [],
		"equipment": equipment,
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
	assert(file != null)
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
