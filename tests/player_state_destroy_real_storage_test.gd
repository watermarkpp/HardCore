extends Node

## Real-storage deletion regression for PlayerState.destroy_inventory_indices.
##
## ui_r5_delete_test proves the transaction flow against an extracted fault
## seam with a boolean commit stub. This test complements it with the real
## persistence layer inside an isolated user:// fixture root (the runner
## redirects user data into this worktree, so real player saves are never
## touched):
##   1. fixture -> real save_game() -> successful destroy -> REAL reload:
##      the deletion is durable, stack counts / instance ids survive, and
##      every non-inventory document field (equipment, warehouse, gold, ...)
##      is unchanged.
##   2. destroy under the existing save-failure injection boundary
##      (test_mode + _test_force_atomic_write_failure): exact memory rollback,
##      no success signals, on-disk bytes identical, and a real reload still
##      shows the untouched items.
##   3. the atomic write boundary itself fails cleanly: save_game() returns
##      false and the on-disk document is byte-identical.

var failures: Array[String] = []
var checks := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


var _fixture_root := ""


func _ready() -> void:
	_run.call_deferred()


func _fixture_inventory() -> Array:
	return [
		{"name": "疾风药水", "count": 3},
		{"name": "金创药(小量)", "count": 5, "instance_id": "fixture-stack-1"},
		{"name": "木剑", "count": 1},
	]


func _setup_isolated_fixture() -> String:
	var test_root := "user://destroy_real_storage_%d" % Time.get_ticks_usec()
	_fixture_root = test_root
	PlayerState.profile_directory = test_root.path_join("characters")
	PlayerState.profile_index_path = test_root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = test_root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = test_root.path_join("shared.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "destroy_real_storage_test"
	PlayerState.character_name = "真实存储删除回归"
	PlayerState.inventory = _fixture_inventory()
	PlayerState.gold = 7777
	return PlayerState._profile_path(PlayerState.active_profile_id)


func _run() -> void:
	assert(GameData.ensure_loaded())
	var profile_path := _setup_isolated_fixture()

	var inventory_signals := [0]
	var profile_signals := [0]
	var on_inventory_changed := func() -> void: inventory_signals[0] += 1
	var on_profile_changed := func() -> void: profile_signals[0] += 1
	PlayerState.inventory_changed.connect(on_inventory_changed)
	PlayerState.profile_changed.connect(on_profile_changed)

	# The fixture must be persisted by the REAL save path, not the stub.
	PlayerState.test_mode = false
	expect(PlayerState.save_game(), "夹具真实保存必须成功")
	expect(FileAccess.file_exists(profile_path), "真实存档文件必须存在")
	var document_before: Dictionary = PlayerState._read_json(profile_path)
	expect(not document_before.is_empty(), "存档文档必须可读")
	expect(int(document_before.get("gold", -1)) == 7777, "金币必须进入真实存档")

	# ── Phase 1: successful destroy with a real on-disk commit + real reload ──
	inventory_signals[0] = 0
	profile_signals[0] = 0
	var result: Dictionary = PlayerState.destroy_inventory_indices([0, 2])
	expect(
		bool(result.get("success", false)) and int(result.get("destroyed", 0)) == 2,
		"真实保存路径下批量丢弃必须成功",
	)
	expect(inventory_signals[0] == 1 and profile_signals[0] == 1, "成功信号必须各恰好发出一次")
	expect(
		PlayerState.item_count("疾风药水") == 0 and PlayerState.item_count("木剑") == 0,
		"被丢弃堆叠必须从内存消失",
	)

	PlayerState.load_save()
	expect(
		PlayerState.item_count("疾风药水") == 0 and PlayerState.item_count("木剑") == 0,
		"真实重载后丢弃必须已持久化",
	)
	expect(PlayerState.item_count("金创药(小量)") == 5, "未丢弃堆叠的数量必须完整保留")
	var reloaded_stack := {}
	for record: Variant in PlayerState.inventory:
		if record is Dictionary and str(record.get("instance_id", "")) == "fixture-stack-1":
			reloaded_stack = record
	expect(not reloaded_stack.is_empty(), "堆叠实例 ID 必须在真实重载后保留")
	expect(int(reloaded_stack.get("count", 0)) == 5, "重载后的堆叠数量必须一致")
	var document_after: Dictionary = PlayerState._read_json(profile_path)
	expect(int(document_after.get("gold", -1)) == 7777, "删除不得误改金币")
	for key: String in ["equipment", "warehouse_inventory", "learned_skills", "quick_slots", "quick_item_slots"]:
		var before_value: Variant = document_before.get(key, "___missing___")
		var after_value: Variant = document_after.get(key, "___missing___")
		expect(
			JSON.stringify(after_value) == JSON.stringify(before_value),
			"删除不得误改 %s（%s → %s）" % [key, JSON.stringify(before_value), JSON.stringify(after_value)],
		)

	# ── Phase 2: injected save failure at the existing boundary ──
	PlayerState.inventory = _fixture_inventory()
	PlayerState.test_mode = false
	expect(PlayerState.save_game(), "失败用例基线必须真实保存成功")
	var disk_baseline := FileAccess.get_file_as_string(profile_path)
	var memory_baseline: Array = PlayerState.inventory.duplicate(true)
	expect(PlayerState.item_count("木剑") == 1, "失败用例基线必须包含目标堆叠")

	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = true
	inventory_signals[0] = 0
	profile_signals[0] = 0
	var failed: Dictionary = PlayerState.destroy_inventory_indices([1])
	expect(
		not bool(failed.get("success", false)) and str(failed.get("reason", "")) == "save_failed",
		"保存失败必须返回 save_failed 且不算成功",
	)
	expect(PlayerState.inventory == memory_baseline, "失败后内存必须精确回滚（含堆叠数量与实例 ID）")
	expect(inventory_signals[0] == 0 and profile_signals[0] == 0, "失败不得发出任何成功信号")
	expect(
		FileAccess.get_file_as_string(profile_path) == disk_baseline,
		"失败后磁盘存档必须字节不变",
	)
	PlayerState.test_mode = false
	PlayerState.load_save()
	expect(PlayerState.item_count("金创药(小量)") == 5, "真实重载必须仍看到未删除的堆叠")
	expect(
		PlayerState.item_count("疾风药水") == 3 and PlayerState.item_count("木剑") == 1,
		"失败删除不得持久化任何丢弃",
	)

	# ── Phase 3: the atomic write boundary itself fails fail-closed ──
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = true
	var disk_before_boundary := FileAccess.get_file_as_string(profile_path)
	expect(not PlayerState.save_game(), "注入边界下真实 save_game 必须失败")
	expect(
		FileAccess.get_file_as_string(profile_path) == disk_before_boundary,
		"原子写失败后磁盘文档必须字节不变",
	)
	PlayerState._test_force_atomic_write_failure = false
	PlayerState.test_mode = true

	PlayerState.inventory_changed.disconnect(on_inventory_changed)
	PlayerState.profile_changed.disconnect(on_profile_changed)
	for failure: String in failures:
		push_error("DESTROY_REAL_STORAGE: " + failure)
	# Test hygiene: drop the timestamped fixture root so repeated runs do not
	# accumulate dirs under the runner's isolated user://. Failed asserts abort
	# above and keep the scene for diagnosis. Best-effort: a cleanup failure is
	# hygiene noise, not a contract failure.
	_remove_recursive(ProjectSettings.globalize_path(_fixture_root))
	print(
		"DESTROY_REAL_STORAGE_%s checks=%d failures=%d"
		% ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()]
	)
	get_tree().quit(0 if failures.is_empty() else 1)


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
