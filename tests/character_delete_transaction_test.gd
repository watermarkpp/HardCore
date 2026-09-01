extends Node

const TEST_DIRECTORY := "user://character_delete_transaction_profiles"
const TEST_INDEX := "user://character_delete_transaction_index.json"
const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	var old_directory: String = PlayerState.profile_directory
	var old_index: String = PlayerState.profile_index_path
	var old_test_mode: bool = PlayerState.test_mode
	var old_force_failure: bool = PlayerState._test_force_atomic_write_failure
	var old_active_id: String = PlayerState.active_profile_id
	var old_character_name: String = PlayerState.character_name
	PlayerState.profile_directory = TEST_DIRECTORY
	PlayerState.profile_index_path = TEST_INDEX
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = false

	assert(PlayerState.create_character("保留人物", "战士", "男").is_empty())
	var preserved_id: String = PlayerState.active_profile_id
	assert(PlayerState.create_character("删除人物", "法师", "男").is_empty())
	var deleted_id: String = PlayerState.active_profile_id
	assert(PlayerState.save_game(), "failed to prepare deleted-profile backup")
	# Give every supported target sidecar a unique payload; deletion must never
	# touch the other profile's bytes.
	var preserved_path := TEST_DIRECTORY + "/" + preserved_id + ".json"
	var preserved_bytes := FileAccess.get_file_as_bytes(preserved_path)
	for suffix: String in [".tmp", ".corrupt.tmp"]:
		_write_text(TEST_DIRECTORY + "/" + deleted_id + ".json" + suffix, "delete-sidecar" + suffix)
	assert(FileAccess.file_exists(TEST_DIRECTORY + "/" + deleted_id + ".json.bak"), "delete fixture backup missing")

	var hall: Control = load("res://scenes/character_select.tscn").instantiate()
	hall.suppress_scene_change_for_test = true
	add_child(hall)
	await get_tree().process_frame
	hall._select_main_profile(deleted_id)
	assert(not hall.delete_button.disabled, "selected profile must enable delete")
	hall._request_delete_selected_character()
	assert(hall.delete_confirmation.visible, "delete confirmation did not open")
	assert(hall.delete_confirmation.message_label.text.contains("删除人物"), "confirmation must name the exact selected character")
	hall.delete_confirmation._cancel()
	assert(FileAccess.file_exists(TEST_DIRECTORY + "/" + deleted_id + ".json"), "cancel deleted the profile")
	assert(PlayerState.list_characters().size() == 2, "cancel changed the roster")

	# Invalid and successful creation publish status only through Message; the
	# action itself must stay visually static with no transient feedback state.
	hall.name_input.text = ""
	hall._create_character()
	assert(hall.message_label.text == "角色名不能为空")
	_assert_static_create_action(hall)
	hall.name_input.text = "新人物"
	hall._create_character()
	assert(hall.message_label.text.contains("角色创建成功"))
	_assert_static_create_action(hall)
	var newly_created_id: String = PlayerState.active_profile_id

	# Force the index transaction to fail. No target file or index membership may
	# change before the authoritative index commit succeeds.
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = true
	var failed := PlayerState.delete_character_profile(deleted_id)
	assert(not bool(failed.get("success", false)) and failed.reason == "profile_index_write_failed")
	assert(FileAccess.file_exists(TEST_DIRECTORY + "/" + deleted_id + ".json"), "failed index write deleted profile bytes")
	assert(_index_has(deleted_id), "failed index write removed profile membership")
	PlayerState._test_force_atomic_write_failure = false

	# Confirm removes exactly the captured profile, preserves other profile bytes,
	# and selects a valid fallback in the hall.
	hall._select_main_profile(deleted_id)
	hall._request_delete_selected_character()
	hall.delete_confirmation._confirm()
	await get_tree().process_frame
	for suffix: String in ["", ".bak", ".tmp", ".corrupt.tmp"]:
		assert(not FileAccess.file_exists(TEST_DIRECTORY + "/" + deleted_id + ".json" + suffix), "deleted profile sidecar survived: %s" % suffix)
	assert(FileAccess.get_file_as_bytes(preserved_path) == preserved_bytes, "unrelated profile bytes changed")
	assert(not _index_has(deleted_id), "deleted profile remains indexed")
	# The ordinary writable fixture must complete all sidecar cleanup.  A future
	# cleanup warning remains a committed success so the UI can still refresh to
	# the authoritative index state.
	var missing_result := PlayerState.delete_character_profile(deleted_id)
	assert(not bool(missing_result.get("success", false)) and missing_result.reason == "profile_not_found")
	assert(not hall.selected_main_profile_id.is_empty() and hall.selected_main_profile_id != deleted_id, "valid fallback was not selected")
	assert(not hall.delete_button.disabled, "fallback selection must keep delete enabled")

	# Delete every remaining profile through the same exact-ID transaction.  The
	# last removal must leave an empty, disabled hall rather than a stale id.
	for profile: Dictionary in PlayerState.list_characters():
		var profile_id := str(profile.get("id", ""))
		if profile_id == hall.selected_main_profile_id:
			hall._request_delete_selected_character()
			hall.delete_confirmation._confirm()
			await get_tree().process_frame
		else:
			var direct_result := PlayerState.delete_character_profile(profile_id)
			assert(bool(direct_result.get("success", false)))
			assert(bool(direct_result.get("cleanup_complete", false)))
			hall._refresh_profiles()
	assert(PlayerState.list_characters().is_empty())
	assert(hall.selected_main_profile_id.is_empty())
	assert(hall.delete_button.disabled and hall.enter_button.disabled)
	assert(newly_created_id != deleted_id and preserved_id != deleted_id)

	hall.queue_free()
	PlayerState._test_force_atomic_write_failure = old_force_failure
	PlayerState.test_mode = old_test_mode
	PlayerState.profile_directory = old_directory
	PlayerState.profile_index_path = old_index
	PlayerState.active_profile_id = old_active_id
	PlayerState.character_name = old_character_name
	_cleanup()
	print("CHARACTER_DELETE_TRANSACTION_PASS: static create action; exact confirmed delete, cancel, fallback, last-profile and atomic failure guards")
	get_tree().quit(0)


func _assert_static_create_action(hall: Control) -> void:
	assert(hall.create_button.text == "创建角色")
	assert(not hall.create_button.has_meta(GothicUIThemeScript.BUTTON_FEEDBACK_META_STATE), "create action exposed transient feedback")


func _index_has(profile_id: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_INDEX))
	if not parsed is Dictionary:
		return false
	for entry: Variant in (parsed as Dictionary).get("profiles", []):
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == profile_id:
			return true
	return false


func _write_text(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "failed to prepare sidecar fixture")
	file.store_string(contents)
	file.close()


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak", ".corrupt.tmp"]:
		var index_path := TEST_INDEX + suffix
		if FileAccess.file_exists(index_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path))
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if not DirAccess.dir_exists_absolute(absolute_directory):
		return
	var directory := DirAccess.open(TEST_DIRECTORY)
	if directory != null:
		for file_name: String in directory.get_files():
			DirAccess.remove_absolute(absolute_directory.path_join(file_name))
	DirAccess.remove_absolute(absolute_directory)
