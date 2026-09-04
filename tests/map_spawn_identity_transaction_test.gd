extends Node

const Migration := preload("res://tools/map_editor/migrate_map_spawn_identity.gd")


func _ready() -> void:
	var root := "user://map_spawn_identity_transaction_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var first := "%s/first.json" % root
	var second := "%s/second.json" % root
	_write(first, {"version": 1, "value": "first"})
	_write(second, {"version": 1, "value": "second"})
	var before_first := FileAccess.get_sha256(first)
	var before_second := FileAccess.get_sha256(second)
	var failed := Migration.atomic_replace_text_files(
		[
			{"path": first, "text": '{"version":2,"value":"new-first"}'},
			{"path": second, "text": '{"version":2,"value":"new-second"}'},
		],
		1
	)
	assert(not bool(failed.get("ok", false)), str(failed))
	assert(FileAccess.get_sha256(first) == before_first, "first target changed after injected failure")
	assert(FileAccess.get_sha256(second) == before_second, "second target changed after injected failure")
	_assert_no_transaction_residue(root)
	var duplicate_plans: Array[Dictionary] = [
		{"path": first, "text": '{"version":2,"value":"duplicate-a"}'},
		{"path": first, "text": '{"version":2,"value":"duplicate-b"}'},
	]
	_assert_prepare_failure(duplicate_plans, first, second, before_first, before_second, root)
	var empty_path_plans: Array[Dictionary] = [
		{"path": first, "text": '{"version":2,"value":"empty-a"}'},
		{"path": "", "text": '{"version":2,"value":"empty-b"}'},
	]
	_assert_prepare_failure(empty_path_plans, first, second, before_first, before_second, root)
	var succeeded := Migration.atomic_replace_text_files(
		[
			{"path": first, "text": '{"version":2,"value":"new-first"}'},
			{"path": second, "text": '{"version":2,"value":"new-second"}'},
		]
	)
	assert(bool(succeeded.get("ok", false)), str(succeeded))
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(first)).get("version", -1)) == 2)
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(second)).get("version", -1)) == 2)
	_assert_no_transaction_residue(root)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(second))
	print("MAP_SPAWN_IDENTITY_TRANSACTION_PASS rollback_hashes_unchanged=true")
	get_tree().quit()


func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(value))
	file.close()


func _assert_no_transaction_residue(root: String) -> void:
	var directory := DirAccess.open(ProjectSettings.globalize_path(root))
	assert(directory != null)
	for filename: String in directory.get_files():
		assert(not filename.contains(".identity_migration_tmp."), "temporary migration file remained: %s" % filename)
		assert(not filename.contains(".identity_migration_bak."), "backup migration file remained: %s" % filename)


func _assert_prepare_failure(plans: Array[Dictionary], first: String, second: String, before_first: String, before_second: String, root: String) -> void:
	var invalid_result := Migration.atomic_replace_text_files(plans)
	assert(not bool(invalid_result.get("ok", false)), str(invalid_result))
	assert(FileAccess.get_sha256(first) == before_first, "first target changed during prepare failure")
	assert(FileAccess.get_sha256(second) == before_second, "second target changed during prepare failure")
	_assert_no_transaction_residue(root)
