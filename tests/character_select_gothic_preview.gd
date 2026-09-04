extends Node

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const OUTPUT_PATH := "res://outputs/visual_acceptance/character_select/character_select_ai_teammate_v1.png"
const WIDE_OUTPUT_PATH := "res://outputs/visual_acceptance/final_consistency/character_select_2400x1080.png"
const TEST_DIRECTORY := "user://character_select_gothic_preview_profiles"
const TEST_INDEX := "user://character_select_gothic_preview_index.json"


func _ready() -> void:
	_prepare_profiles()
	var launcher: Control = load("res://scenes/character_select.tscn").instantiate()
	add_child(launcher)
	await get_tree().process_frame
	# Exercise the same production selection path used by the live hall, then
	# apply only the official transition feedback API.  This intentionally does
	# not invoke _enter_selected_character(), so the capture compares a normal
	# 创建角色 button with a transition-state 进入 HardCore button without a
	# Loading overlay or a scene change.
	launcher._select_main_profile("warrior_preview")
	launcher._select_creation_profession("战士")
	var cards_normal_preview := OS.get_environment("UI_PREVIEW_CARDS_NORMAL") == "1"
	if cards_normal_preview:
		for profile_id: String in launcher.profile_cards:
			var profile_button: Button = launcher.profile_cards[profile_id].main_button
			GothicUIThemeScript.set_character_selection_feedback(
				profile_button,
				false,
				&"GothicCharacterProfileButton",
				&"GothicCharacterSelectedProfileButton",
				"character.profile",
			)
		for profession_name: String in launcher.profession_buttons:
			GothicUIThemeScript.set_character_selection_feedback(
				launcher.profession_buttons[profession_name],
				false,
				&"GothicCharacterProfessionButton",
				&"GothicCharacterSelectedProfessionButton",
				"character.profession",
			)
	var transition_preview := OS.get_environment("UI_PREVIEW_NORMAL") != "1"
	if transition_preview:
		GothicUIThemeScript.set_button_feedback(
			launcher.enter_button,
			GothicUIThemeScript.BUTTON_FEEDBACK_TRANSITION,
			"character.launch.preview",
		)
	await get_tree().process_frame
	await get_tree().process_frame
	var output_path := WIDE_OUTPUT_PATH if OS.get_environment("UI_WIDE_CAPTURE") == "1" else OUTPUT_PATH
	if not transition_preview:
		output_path = output_path.replace(".png", "_normal.png")
	if cards_normal_preview:
		output_path = output_path.replace(".png", "_cards_normal.png")
	var output_dir := ProjectSettings.globalize_path(output_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output_path))
	assert(error == OK, "无法保存人物选择与 AI 队友哥特样板")
	print(
		"CHARACTER_SELECT_GOTHIC_PREVIEW_CAPTURE_PASS output=%s transition=%s create_text=%s profile=%s profession=%s" % [
			output_path,
			str(launcher.enter_button.get_meta(GothicUIThemeScript.BUTTON_FEEDBACK_META_STATE, "normal")),
			launcher.create_button.text,
			launcher.selected_main_profile_id,
			launcher.selected_creation_profession,
		]
	)
	get_tree().quit(0)


func _prepare_profiles() -> void:
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(absolute_directory)
	PlayerState.profile_directory = TEST_DIRECTORY
	PlayerState.profile_index_path = TEST_INDEX
	PlayerState.test_mode = false
	var profiles := [
		{"id": "warrior_preview", "name": "北辰", "profession": "战士", "gender": "男", "level": 26, "updated_at": 300},
		{"id": "wizard_preview", "name": "星火", "profession": "法师", "gender": "男", "level": 22, "updated_at": 200},
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
