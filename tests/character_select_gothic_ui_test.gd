extends Node

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
	for profile_id: String in launcher.profile_cards:
		assert(launcher.profile_cards[profile_id].ai_button.disabled, "AI teammate card buttons must remain disabled")
		assert(launcher.profile_cards[profile_id].ai_button.theme_type_variation == &"GothicCharacterAIStatusButton", "AI 队友状态没有使用配套近方形框")
		assert(launcher.profile_cards[profile_id].main_button.theme_type_variation in [&"GothicCharacterProfileButton", &"GothicCharacterSelectedProfileButton"], "人物主卡没有使用配套横向框")
	assert(launcher.teammate_status_label.text == "AI队友功能暂未开放", "AI disabled status text mismatch")
	for profession_name: String in launcher.profession_buttons:
		var profession_button: Button = launcher.profession_buttons[profession_name]
		assert(profession_button.theme_type_variation in [&"GothicCharacterProfessionButton", &"GothicCharacterSelectedProfessionButton"], "职业选择没有使用专用协调框")
		var text_minimum := profession_button.get_minimum_size()
		assert(profession_button.size.x + 0.5 >= text_minimum.x and profession_button.size.y + 0.5 >= text_minimum.y, "职业选择框没有完整包住三行文字：button=%s minimum=%s" % [profession_button.size, text_minimum])
	if not launcher.profile_cards.is_empty():
		var main_profile_id := str(launcher.profile_cards.keys()[0])
		launcher._select_main_profile(main_profile_id)
		await get_tree().process_frame
		var paper_doll := launcher.get_node_or_null("CenteredContent/CharacterPreviewPanel/PreviewStage/PreviewVisualRoot/RuntimePaperDoll") as Control
		assert(paper_doll != null and not paper_doll.center_on_opaque_bounds, "main character paper doll preview regressed")
		assert(paper_doll.position == Vector2.ZERO and paper_doll.size == launcher.preview_visual_root.size, "paper doll must fill preview root")

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
