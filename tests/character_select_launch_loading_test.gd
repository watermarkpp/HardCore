extends Node

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const TEST_DIRECTORY := "user://character_launch_loading_profiles"
const TEST_INDEX := "user://character_launch_loading_index.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	var old_directory: String = PlayerState.profile_directory
	var old_index: String = PlayerState.profile_index_path
	var old_test_mode: bool = PlayerState.test_mode
	PlayerState.profile_directory = TEST_DIRECTORY
	PlayerState.profile_index_path = TEST_INDEX
	PlayerState.test_mode = false
	assert(PlayerState.create_character("首帧", "战士", "男").is_empty())
	var profile_id := PlayerState.active_profile_id
	var hall_theme_started := Time.get_ticks_usec()
	var hall_theme := GothicUIThemeScript.build_character_hall()
	var first_hall_theme_ms := float(Time.get_ticks_usec() - hall_theme_started) / 1000.0
	assert(first_hall_theme_ms < 1500.0, "cold character hall theme build regressed: %.3f ms" % first_hall_theme_ms)
	hall_theme_started = Time.get_ticks_usec()
	assert(GothicUIThemeScript.build_character_hall() == hall_theme, "character hall theme must be shared")
	assert(float(Time.get_ticks_usec() - hall_theme_started) / 1000.0 < 100.0, "shared character hall theme lookup regressed")
	for variation in [
		&"GothicCharacterProfileButton",
		&"GothicCharacterSelectedProfileButton",
		&"GothicCharacterProfessionButton",
		&"GothicCharacterSelectedProfessionButton",
		&"GothicCharacterAIStatusButton",
		&"GothicCharacterLaunchButton",
		&"GothicComponentButton",
	]:
		assert(hall_theme.has_stylebox("normal", variation), "character hall theme missing %s" % variation)

	var launcher: Control = load("res://scenes/character_select.tscn").instantiate()
	launcher.suppress_scene_change_for_test = true
	add_child(launcher)
	await get_tree().process_frame
	assert(not launcher.launch_loading_overlay.visible, "Loading must start hidden")
	print("[CharacterLaunchPreloadBeforeLaunch] ", JSON.stringify({
		"path": launcher._launch_scene_preload_path,
		"state": str(launcher._launch_scene_preload_state),
		"request_count": launcher._launch_scene_preload_request_count,
		"code": launcher.launch_code_preparation_diagnostic(),
	}))
	assert(launcher._launch_scene_preload_path == launcher.launch_scene_path, "hall did not establish the launch preload target")
	assert(str(launcher._launch_scene_preload_state) in ["idle", "requested", "ready"], "launch preload entered an invalid state before code preparation")

	# Reset the authority marker after the hall has selected its default profile.
	# The launch call must not hydrate it again until Loading has been made visible
	# and the first render/process frame has been yielded.
	PlayerState.active_profile_id = ""
	launcher.selected_main_profile_id = profile_id
	launcher._enter_selected_character()
	assert(launcher._launch_in_progress, "launch must enter busy state synchronously")
	assert(not launcher.enter_button.disabled, "expensive button feedback must wait until Loading has been drawn")
	assert(launcher.enter_button.theme_type_variation == "GothicCharacterHallEnterGemButton", "launch action must keep the accepted character-hall enter frame")
	assert(launcher.launch_loading_overlay.visible, "Loading must be visible in the click frame")
	assert(is_equal_approx(launcher.launch_loading_overlay.modulate.a, 1.0), "Loading root must be opaque in the launch click frame")
	assert(is_equal_approx(launcher.launch_loading_overlay.shade.color.a, 1.0), "Loading shade must fully hide the character hall")
	assert(not launcher.launch_loading_overlay.progress_percent.visible, "角色选择前置准备不应显示无世界总量依据的百分比")
	assert(launcher.launch_loading_overlay.progress_stage.text == "准备进入世界", "角色选择Loading首帧阶段文案异常")
	assert(PlayerState.active_profile_id.is_empty(), "profile hydration ran before the Loading frame")

	# A duplicate activation during the yielded frame must not submit again.
	launcher._enter_selected_character()
	# The architecture's code publication hashes 681 executable chunks before
	# it may submit a scene request. Preserve the existing real-consumer 25s
	# code-preparation bound and the separate original 600-frame scene bound.
	# All work is performed by the original production consumer under cover.
	var code_deadline := Time.get_ticks_msec() + 25000
	while launcher.last_launch_request.is_empty() and launcher._launch_in_progress and Time.get_ticks_msec() < code_deadline:
		await get_tree().process_frame
	assert(not launcher.last_launch_request.is_empty(), "real covered code preparation did not admit launch within its existing real-consumer deadline: %s" % launcher.launch_code_preparation_diagnostic())
	assert(ContentLayers.is_internal_code_retention_current(launcher._launch_code_result, launcher), "covered preparation did not retain its real code lease")
	var launch_ready_wait_frames := 0
	while (
		launcher.last_launch_request.is_empty()
		or not launcher._launch_scene_preload_resource is PackedScene
	) and launch_ready_wait_frames < 600:
		await get_tree().process_frame
		launch_ready_wait_frames += 1
	assert(launch_ready_wait_frames < 600 and not launcher.last_launch_request.is_empty(),
		"launch did not reach its real preload completion within the existing 600-frame bound: %s" %
		str({"code": launcher._launch_code_diagnostic, "preload": launcher._launch_scene_preload_state,
			"message": launcher.message_label.text, "busy": launcher._launch_in_progress}))
	assert(launcher.enter_button.disabled, "launch button must lock after Loading has been presented")
	assert(launcher.enter_button.get_meta("gothic_feedback_state", "") == "transition", "launch action must stay highlighted until Loading takes over")
	assert(launcher.enter_button.get_theme_color("font_color") == GothicUIThemeScript.CHARACTER_TRANSITION_FONT, "launch transition must use the restrained warm-gold text cue")
	assert(launcher.enter_button.get_theme_constant("outline_size") == 2, "launch transition must add only a restrained text outline")
	assert(PlayerState.active_profile_id == profile_id, "profile hydration did not run beneath Loading")
	assert(launcher.last_launch_request.main_profile_id == profile_id, "launch request was not completed")
	assert(launcher.launch_loading_overlay.visible, "Loading disappeared before scene handoff")
	assert(launch_ready_wait_frames < 600, "launch did not reach its real preload completion within the existing 600-frame bound")
	assert(launcher._launch_scene_preload_resource is PackedScene, "launch did not cache a PackedScene")
	var cached_launch_scene: PackedScene = launcher._launch_scene_preload_resource
	var waited_launch_scene: PackedScene = await launcher._wait_for_launch_scene_preload()
	assert(waited_launch_scene == cached_launch_scene, "launch preload wait did not reuse the cached PackedScene")
	assert(launcher._launch_scene_preload_request_count == 1, "cached launch issued a duplicate preload request")

	# A failed launch restores the control instead of trapping the player behind
	# Loading. Use a fresh launcher so the successful test remains immutable.
	launcher.queue_free()
	await get_tree().process_frame
	var failed_launcher: Control = load("res://scenes/character_select.tscn").instantiate()
	failed_launcher.suppress_scene_change_for_test = true
	add_child(failed_launcher)
	await get_tree().process_frame
	failed_launcher.selected_main_profile_id = "missing_profile"
	failed_launcher._enter_selected_character()
	assert(failed_launcher.launch_loading_overlay.visible, "failed launch did not show Loading first")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not failed_launcher._launch_in_progress, "failed launch did not clear busy state")
	assert(not failed_launcher.launch_loading_overlay.visible, "failed launch left Loading visible")
	assert("存档" in failed_launcher.message_label.text, "failed launch did not show a readable reason")
	assert(not failed_launcher.enter_button.disabled, "failed launch did not restore the launch button")

	failed_launcher.queue_free()
	await get_tree().process_frame
	var missing_scene_launcher: Control = load("res://scenes/character_select.tscn").instantiate()
	missing_scene_launcher.launch_scene_path = "res://scenes/__missing_character_launch__.tscn"
	add_child(missing_scene_launcher)
	await get_tree().process_frame
	assert(str(missing_scene_launcher._launch_scene_preload_state) == "failed", "missing launch scene did not fail its background preload")
	assert(missing_scene_launcher._launch_scene_preload_request_count == 0, "missing launch scene must fail before issuing a threaded request")
	missing_scene_launcher.selected_main_profile_id = profile_id
	missing_scene_launcher._enter_selected_character()
	assert(missing_scene_launcher.launch_loading_overlay.visible, "scene failure did not show Loading first")
	var failure_wait_frames := 0
	while missing_scene_launcher._launch_in_progress and failure_wait_frames < 600:
		await get_tree().process_frame
		failure_wait_frames += 1
	assert(failure_wait_frames < 600, "missing scene failure did not recover within the existing launch bound")
	assert(not missing_scene_launcher._launch_in_progress, "scene failure did not clear busy state")
	assert(not missing_scene_launcher.launch_loading_overlay.visible, "scene failure left Loading visible")
	assert(not missing_scene_launcher.enter_button.disabled, "scene failure did not restore the launch button")
	assert("重试" in missing_scene_launcher.message_label.text, "scene failure did not show a readable reason")

	missing_scene_launcher.queue_free()
	PlayerState.profile_directory = old_directory
	PlayerState.profile_index_path = old_index
	PlayerState.test_mode = old_test_mode
	PlayerState.active_profile_id = ""
	_cleanup()
	print("CHARACTER_SELECT_LAUNCH_LOADING_PASS: cold hall theme %.3f ms, threaded preload/cached PackedScene handoff, Loading-first hydration, and failure recovery" % first_hall_theme_ms)
	get_tree().quit(0)


func _cleanup() -> void:
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_directory):
		var directory := DirAccess.open(absolute_directory)
		if directory != null:
			for file_name in directory.get_files():
				DirAccess.remove_absolute(absolute_directory.path_join(file_name))
		DirAccess.remove_absolute(absolute_directory)
	var absolute_index := ProjectSettings.globalize_path(TEST_INDEX)
	if FileAccess.file_exists(absolute_index):
		DirAccess.remove_absolute(absolute_index)
