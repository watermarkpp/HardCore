extends Node

const OUTPUT_PATH := "res://outputs/visual_acceptance/character_select/character_select_ai_teammate_v1.png"
const TEST_DIRECTORY := "user://character_select_gothic_preview_profiles"
const TEST_INDEX := "user://character_select_gothic_preview_index.json"


func _ready() -> void:
	_prepare_profiles()
	var launcher: Control = load("res://scenes/character_select.tscn").instantiate()
	add_child(launcher)
	await get_tree().process_frame
	launcher._set_ai_teammate_enabled(true)
	launcher._select_ai_profile("taoist_preview")
	await get_tree().process_frame
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	assert(error == OK, "无法保存人物选择与 AI 队友哥特样板")
	print("CHARACTER_SELECT_GOTHIC_PREVIEW_CAPTURE_PASS output=%s" % OUTPUT_PATH)
	get_tree().quit(0)


func _prepare_profiles() -> void:
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(absolute_directory)
	PlayerState.profile_directory = TEST_DIRECTORY
	PlayerState.profile_index_path = TEST_INDEX
	PlayerState.test_mode = false
	var profiles := [
		{"id": "warrior_preview", "name": "北辰", "profession": "战士", "gender": "男", "level": 26, "updated_at": 300},
		{"id": "wizard_preview", "name": "星火", "profession": "法师", "gender": "女", "level": 22, "updated_at": 200},
		{"id": "taoist_preview", "name": "青灯", "profession": "道士", "gender": "男", "level": 18, "updated_at": 100},
	]
	for profile: Dictionary in profiles:
		var equipment := {}
		if str(profile.id) == "warrior_preview":
			equipment = {
				"武器": {"name": "裁决之杖"},
				"衣服": {"name": "战神盔甲(男)"},
				"头盔": {"name": "黑铁头盔"},
			}
		_write_json(TEST_DIRECTORY + "/" + str(profile.id) + ".json", {
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
			"equipment": equipment,
			"learned_skills": {},
			"quick_slots": ["", "", "", ""],
			"quest_states": {},
			"content_packages": [],
			"content_schema_version": 1,
			"map_id": 4,
			"position": [0.0, 0.0],
		})
	_write_json(TEST_INDEX, {"version": 1, "profiles": profiles})
	PlayerState.active_profile_id = "warrior_preview"
	PlayerState.select_character("warrior_preview")


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "无法写入人物大厅预览夹具")
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
