extends Node

## Isolated config-schema regression for AudioPreferences._read_valid.
##
## The persisted volume file must be validated with the same strict type
## contract the writer emits: meta/version must be a true TYPE_INT 2 before any
## numeric conversion. A float 2.9, a string "2", a bool, an array or a
## dictionary must all be rejected instead of being truncated/converted first.
## Every fixture writes to a dedicated user:// subdirectory via the test-owned
## storage_path override; the real account preference file is never touched.

const AudioPreferencesScript := preload("res://scripts/audio_preferences.gd")
const TEST_ROOT := "user://audio_preferences_strict_test"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_ROOT)
	# Each sub-assert is a coroutine (it awaits frames); they MUST be awaited
	# sequentially. A bare call suspends at its first await and returns, so the
	# sub-asserts would otherwise all resume interleaved after _run finishes —
	# racing on shared fixture state and truncated by quit().
	await _assert_version_type_contract()
	await _assert_backup_fallback_and_double_corruption()
	await _assert_zero_levels_and_restore()
	await _assert_save_failure_keeps_dirty_and_data()
	# Test hygiene: the fixture root is test-owned; remove it so repeated runs
	# do not accumulate stale config files under the runner's isolated user://.
	# A failed assert aborts above and keeps the scene for diagnosis.
	_remove_recursive(ProjectSettings.globalize_path(TEST_ROOT))
	print("AUDIO_PREFERENCES_STRICT_CONFIG_PASS")
	get_tree().quit(0)


func _remove_recursive(absolute_path: String) -> void:
	var dir := DirAccess.open(absolute_path)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				if dir.current_is_dir():
					_remove_recursive(absolute_path.path_join(entry))
				else:
					dir.remove(entry)
			entry = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(absolute_path)


func _make_prefs(storage_path: String) -> Node:
	var prefs: Node = AudioPreferencesScript.new()
	prefs.storage_path = storage_path
	add_child(prefs)
	return prefs


func _write_cfg(path: String, version: Variant, music: Variant, sfx: Variant) -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", version)
	config.set_value("audio", "music_volume", music)
	config.set_value("audio", "sfx_volume", sfx)
	assert(config.save(path) == OK, "测试夹具写配置失败：" + path)


func _write_versionless_cfg(path: String, music: Variant, sfx: Variant) -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music_volume", music)
	config.set_value("audio", "sfx_volume", sfx)
	assert(config.save(path) == OK, "测试夹具写配置失败：" + path)


func _assert_version_type_contract() -> void:
	var main_path := TEST_ROOT + "/version_contract.cfg"
	# Writer contract: integer 2 must keep loading.
	_write_cfg(main_path, 2, 0.75, 0.5)
	var prefs := _make_prefs(main_path)
	assert(
		is_equal_approx(float(prefs.music_volume), 0.75)
		and is_equal_approx(float(prefs.sfx_volume), 0.5),
		"合法整数 version=2 与数值区间内的音量必须加载",
	)
	prefs.queue_free()
	await get_tree().process_frame

	# Each of these malformed version payloads must reject the whole file.
	var malformed: Array[Variant] = [2.9, "2", true, [2], {"version": 2}]
	for version: Variant in malformed:
		_write_cfg(main_path, version, 0.9, 0.9)
		var rejecting := _make_prefs(main_path)
		assert(
			is_equal_approx(float(rejecting.music_volume), float(rejecting._initial_level(&"Music")))
			and is_equal_approx(float(rejecting.sfx_volume), float(rejecting._initial_level(&"SFX"))),
			"version=%s 必须被整体拒绝，不得截断/转换后放行" % str(version),
		)
		assert(rejecting._read_valid(main_path).is_empty(), "version=%s 的 _read_valid 必须返回空" % str(version))
		rejecting.dirty = false
		rejecting.queue_free()
		await get_tree().process_frame

	# A file without any meta/version key must be rejected as well.
	_write_versionless_cfg(main_path, 0.9, 0.9)
	var versionless := _make_prefs(main_path)
	assert(versionless._read_valid(main_path).is_empty(), "缺失 meta/version 必须返回空")
	versionless.dirty = false
	versionless.queue_free()
	await get_tree().process_frame
	print("AUDIO_PREFERENCES_STRICT_VERSION_CONTRACT_OK")


func _assert_backup_fallback_and_double_corruption() -> void:
	var main_path := TEST_ROOT + "/backup_case.cfg"
	var backup_path := main_path + ".bak"
	_write_cfg(main_path, "2", 0.1, 0.1)
	_write_cfg(backup_path, 2, 0.3, 0.4)
	var recovered := _make_prefs(main_path)
	assert(
		is_equal_approx(float(recovered.music_volume), 0.3)
		and is_equal_approx(float(recovered.sfx_volume), 0.4),
		"主文件无效但备份有效时必须从备份恢复",
	)
	assert(bool(recovered.dirty), "备份恢复后必须保持 dirty 以便回写主文件")
	recovered.dirty = false
	recovered.queue_free()
	await get_tree().process_frame

	_write_cfg(main_path, [2], 0.1, 0.1)
	_write_cfg(backup_path, {"v": 2}, 0.3, 0.4)
	var both_bad := _make_prefs(main_path)
	assert(
		both_bad._read_valid(main_path).is_empty() and both_bad._read_valid(backup_path).is_empty(),
		"两个文件均无效时读取必须都为空",
	)
	assert(
		float(both_bad.music_volume) >= 0.0 and float(both_bad.music_volume) <= 1.0
		and float(both_bad.sfx_volume) >= 0.0 and float(both_bad.sfx_volume) <= 1.0,
		"双坏档时必须落到默认/总线初始音量，不得越界",
	)
	both_bad.dirty = false
	both_bad.queue_free()
	await get_tree().process_frame
	print("AUDIO_PREFERENCES_STRICT_BACKUP_OK")


func _assert_zero_levels_and_restore() -> void:
	var main_path := TEST_ROOT + "/zero_restore.cfg"
	_write_cfg(main_path, 2, 0, 0)
	var zeroed := _make_prefs(main_path)
	assert(
		is_equal_approx(float(zeroed.music_volume), 0.0)
		and is_equal_approx(float(zeroed.sfx_volume), 0.0),
		"合法的零音量必须被加载",
	)
	zeroed.set_level("music", 0.6)
	zeroed.set_level("sfx", 0.8)
	assert(int(zeroed.flush()) == OK, "合法目录下 flush 必须成功")
	zeroed.queue_free()
	await get_tree().process_frame

	var restored := _make_prefs(main_path)
	assert(
		is_equal_approx(float(restored.music_volume), 0.6)
		and is_equal_approx(float(restored.sfx_volume), 0.8),
		"重新实例化后必须恢复上次保存的音量",
	)
	restored.dirty = false
	restored.queue_free()
	await get_tree().process_frame
	print("AUDIO_PREFERENCES_STRICT_ZERO_RESTORE_OK")


func _assert_save_failure_keeps_dirty_and_data() -> void:
	# Successful baseline first: the on-disk file carries known-good values.
	var good_root := TEST_ROOT + "/fail_case"
	DirAccess.make_dir_recursive_absolute(good_root)
	var main_path := good_root + "/main.cfg"
	_write_cfg(main_path, 2, 0.25, 0.35)
	var prefs := _make_prefs(main_path)
	assert(
		is_equal_approx(float(prefs.music_volume), 0.25)
		and is_equal_approx(float(prefs.sfx_volume), 0.35),
		"保存失败用例的基线数据必须先成功加载",
	)
	prefs.dirty = false

	# Force the flush I/O boundary to fail by pointing storage at a directory
	# that does not exist. No production save protocol is modified.
	var broken_path := TEST_ROOT + "/fail_case_missing_dir/main.cfg"
	prefs.storage_path = broken_path
	prefs.set_level("music", 0.9)
	var failures: Array[int] = []
	prefs.save_failed.connect(func(error_code: int) -> void: failures.append(error_code))
	var flush_error := int(prefs.flush())
	assert(flush_error != OK, "目录缺失时 flush 必须失败")
	assert(bool(prefs.dirty), "保存失败后必须保持 dirty，数据不得静默丢失")
	assert(failures.size() == 1, "保存失败信号必须恰好发出一次")
	assert(int(prefs.last_save_error) == flush_error, "last_save_error 必须记录真实错误码")
	var on_disk := ConfigFile.new()
	assert(on_disk.load(main_path) == OK, "原主文件必须原样保留")
	assert(
		is_equal_approx(float(on_disk.get_value("audio", "music_volume", -1.0)), 0.25)
		and is_equal_approx(float(on_disk.get_value("audio", "sfx_volume", -1.0)), 0.35),
		"保存失败后磁盘上的原有效数据不得被破坏",
	)
	prefs.dirty = false
	prefs.queue_free()
	await get_tree().process_frame
	print("AUDIO_PREFERENCES_STRICT_SAVE_FAILURE_OK")
