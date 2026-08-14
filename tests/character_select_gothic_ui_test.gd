extends Node

const AdaptiveButtonStyleBoxScript := preload("res://scripts/adaptive_button_style_box.gd")

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var old_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	var launcher: Control = load("res://scenes/character_select.tscn").instantiate()
	launcher.suppress_scene_change_for_test = true
	add_child(launcher)
	await get_tree().process_frame

	assert(launcher.ai_teammate_toggle.disabled, "AI teammate toggle must remain disabled")
	assert(not launcher.ai_teammate_toggle.button_pressed, "AI teammate toggle must remain false")
	launcher._set_ai_teammate_enabled(true)
	launcher._select_ai_profile("any_profile")
	assert(not launcher.ai_teammate_enabled and launcher.selected_ai_profile_id.is_empty(), "direct AI calls must remain disabled")
	var selected_profile_count := 0
	for profile_id: String in launcher.profile_cards:
		var profile_button: Button = launcher.profile_cards[profile_id].main_button
		assert(launcher.profile_cards[profile_id].ai_button.disabled, "AI teammate card buttons must remain disabled")
		assert(launcher.profile_cards[profile_id].ai_button.theme_type_variation == &"GothicCharacterAIStatusButton", "AI 队友状态没有使用配套近方形框")
		assert(launcher.profile_cards[profile_id].main_button.theme_type_variation in [&"GothicCharacterProfileButton", &"GothicCharacterSelectedProfileButton"], "人物主卡没有使用配套横向框")
		if profile_button.theme_type_variation == &"GothicCharacterSelectedProfileButton":
			selected_profile_count += 1
			var selected_style := profile_button.get_theme_stylebox("normal") as AdaptiveButtonStyleBoxScript
			assert(selected_style != null and selected_style.feedback_layered, "selected character card must use its source-derived interior layer")
			assert(selected_style.feedback_background_styles.size() > 0 and selected_style.feedback_frame_styles.size() > 0, "selected character card must cache both feedback layers")
	assert(selected_profile_count <= 1, "character cards must be a single-select group")
	assert(launcher.teammate_status_label.text == "AI队友功能暂未开放", "AI disabled status text mismatch")
	for profession_name: String in launcher.profession_buttons:
		var profession_button: Button = launcher.profession_buttons[profession_name]
		assert(profession_button.toggle_mode and profession_button.button_group == launcher.profession_button_group, "profession cards must share one persistent single-select ButtonGroup")
		assert(profession_button.theme_type_variation in [&"GothicCharacterProfessionButton", &"GothicCharacterSelectedProfessionButton"], "职业选择没有使用专用协调框")
		var text_minimum := profession_button.get_minimum_size()
		assert(profession_button.size.x + 0.5 >= text_minimum.x and profession_button.size.y + 0.5 >= text_minimum.y, "职业选择框没有完整包住三行文字：button=%s minimum=%s" % [profession_button.size, text_minimum])
	launcher._select_creation_profession("法师")
	var selected_profession_count := 0
	for profession_name: String in launcher.profession_buttons:
		var profession_button: Button = launcher.profession_buttons[profession_name]
		if profession_button.theme_type_variation == &"GothicCharacterSelectedProfessionButton":
			selected_profession_count += 1
			assert(profession_button.button_pressed, "selected profession card must retain its pressed state")
			var selected_style := profession_button.get_theme_stylebox("normal") as AdaptiveButtonStyleBoxScript
			assert(selected_style != null and selected_style.feedback_layered, "selected profession card must use its source-derived interior layer")
			assert(selected_style.feedback_background_styles.size() > 0 and selected_style.feedback_frame_styles.size() > 0, "selected profession card must cache both feedback layers")
	assert(selected_profession_count == 1, "profession cards must be a single-select group")
	assert(launcher.create_button.text == "创建角色", "create action must keep its own label")
	assert(launcher.create_button.theme_type_variation == &"GothicCharacterLaunchButton", "create action must reuse the layered launch frame")
	if not launcher.profile_cards.is_empty():
		var main_profile_id := str(launcher.profile_cards.keys()[0])
		launcher._select_main_profile(main_profile_id)
		await get_tree().process_frame
		var paper_doll := launcher.get_node_or_null("CenteredContent/CharacterPreviewPanel/PreviewStage/PreviewVisualRoot/RuntimePaperDoll") as Control
		assert(paper_doll != null and not paper_doll.center_on_opaque_bounds, "main character paper doll preview regressed")
		assert(paper_doll.position == Vector2.ZERO and paper_doll.size == launcher.preview_visual_root.size, "paper doll must fill preview root")
		assert(launcher.create_button.text == "创建角色", "selecting a character must not change create action text")
		assert(launcher.message_label.text.contains("已选择主角色"), "selection status text must remain owned by the status label")
		if launcher.profile_cards.size() > 1:
			var alternate_profile_id := str(launcher.profile_cards.keys()[1])
			launcher._select_main_profile(alternate_profile_id)
			assert(launcher.profile_cards[alternate_profile_id].main_button.theme_type_variation == &"GothicCharacterSelectedProfileButton", "character selection did not persist on the newly selected card")
			assert(launcher.profile_cards[main_profile_id].main_button.theme_type_variation == &"GothicCharacterProfileButton", "character selection left more than one profile card selected")

	launcher.selected_main_profile_id = "main_profile"
	var launch_request: Dictionary = launcher.build_launch_request()
	assert(launch_request.main_profile_id == "main_profile", "main profile must remain in launch request")
	assert(not launch_request.ai_teammate_enabled, "launch request must disable AI teammate")
	assert(launch_request.ai_teammate_profile_id.is_empty(), "launch request must clear AI teammate id")
	assert(launch_request.ai_control_mode == "disabled", "launch request AI mode mismatch")

	launcher.name_input.text = "星火"
	launcher._select_creation_profession("法师")
	var creation_request: Dictionary = launcher.build_creation_request()
	assert(creation_request.character_name == "星火", "creation request must preserve character name")
	assert(creation_request.profession_id == "wizard", "creation request must preserve profession")
	assert(creation_request.gender == "男", "creation request must preserve fixed gender")
	assert(not creation_request.ai_teammate_enabled and creation_request.ai_teammate_profile_id.is_empty(), "creation request must clear AI teammate")

	launcher.queue_free()
	PlayerState.test_mode = old_test_mode
	print("CHARACTER_SELECT_GOTHIC_UI_PASS: AI teammate temporarily disabled; main selection and creation contracts remain valid")
	get_tree().quit(0)
