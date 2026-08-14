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

	# Reset the authority marker after the hall has selected its default profile.
	# The launch call must not hydrate it again until Loading has been made visible
	# and the first render/process frame has been yielded.
	PlayerState.active_profile_id = ""
	launcher.selected_main_profile_id = profile_id
	launcher._enter_selected_character()
	assert(launcher._launch_in_progress, "launch must enter busy state synchronously")
	assert(not launcher.enter_button.disabled, "expensive button feedback must wait until Loading has been drawn")
	assert(launcher.enter_button.theme_type_variation == "GothicCharacterLaunchButton", "launch action must use the character-specific transition frame")
	assert(launcher.launch_loading_overlay.visible, "Loading must be visible in the click frame")
	assert(PlayerState.active_profile_id.is_empty(), "profile hydration ran before the Loading frame")

	# A duplicate activation during the yielded frame must not submit again.
	launcher._enter_selected_character()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(launcher.enter_button.disabled, "launch button must lock after Loading has been presented")
	assert(launcher.enter_button.get_meta("gothic_feedback_state", "") == "transition", "launch action must stay highlighted until Loading takes over")
	assert(launcher.enter_button.get_theme_color("font_color") == GothicUIThemeScript.CHARACTER_TRANSITION_FONT, "launch transition must use the restrained warm-gold text cue")
	assert(launcher.enter_button.get_theme_constant("outline_size") == 2, "launch transition must add only a restrained text outline")
	assert(PlayerState.active_profile_id == profile_id, "profile hydration did not run beneath Loading")
	assert(launcher.last_launch_request.main_profile_id == profile_id, "launch request was not completed")
	assert(launcher.launch_loading_overlay.visible, "Loading disappeared before scene handoff")

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
	missing_scene_launcher.selected_main_profile_id = profile_id
	missing_scene_launcher._enter_selected_character()
	assert(missing_scene_launcher.launch_loading_overlay.visible, "scene failure did not show Loading first")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
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
	print("CHARACTER_SELECT_LAUNCH_LOADING_PASS: cold hall theme %.3f ms, shared reuse, Loading-first hydration, and failure recovery" % first_hall_theme_ms)
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
