extends Node

const DeviceLabRuntimeScript := preload("res://scripts/device_lab_runtime.gd")
const LayoutLoader := preload("res://scripts/ui_runtime_layout_overrides.gd")
const InventoryPanelScript := preload("res://scripts/inventory_panel.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_protocol_rejection()
	await _test_player_state_roundtrip()
	await _test_chiyue_test_roster_append_only()
	await _test_external_profile_guards()
	_test_bounded_snapshot()
	await _test_transaction_rollback()
	await _test_ui_checkpoint_rollback()
	await _test_mailbox_roundtrip()
	_test_nonce_and_outbox_guards()
	_test_debug_gate()
	_test_powershell_contract()
	print("DEVICE_LAB_RUNTIME_PASS protocol snapshot bounded dynamic_inventory runtime_text")
	get_tree().quit(0)


func _test_protocol_rejection() -> void:
	var status := {
		"schemaVersion": 1,
		"nonce": "status_001",
		"action": "status",
		"allowlist": ["device_lab.v1", "status"],
	}
	assert(DeviceLabRuntimeScript.validate_command(status).get("ok", false), "valid status command rejected")
	for action: String in ["reset_diagnostics", "read_diagnostics", "stop_diagnostics"]:
		var diagnostics_command := {
			"schemaVersion": DeviceLabRuntimeScript.PROTOCOL_VERSION,
			"nonce": "diagnostics_%s" % action,
			"action": action,
			"allowlist": [DeviceLabRuntimeScript.ALLOWLIST_ID, action],
		}
		assert(
			DeviceLabRuntimeScript.validate_command(diagnostics_command).get("ok", false),
			"valid diagnostics command rejected: %s" % action,
		)
	var traversal := status.duplicate(true)
	traversal["path"] = "user://device_lab/inbox/../save.json"
	traversal["size"] = 1
	traversal["checksum"] = "0".repeat(64)
	assert(not bool(DeviceLabRuntimeScript.validate_command(traversal).get("ok", false)), "path traversal accepted")
	var oversized := status.duplicate(true)
	oversized["action"] = "apply_ui_profile"
	oversized["allowlist"] = ["device_lab.v1", "apply_ui_profile"]
	oversized["profile"] = "inventory"
	oversized["path"] = "user://device_lab/inbox/layout_status_001.json"
	oversized["size"] = DeviceLabRuntimeScript.MAX_PAYLOAD_BYTES + 1
	oversized["checksum"] = "0".repeat(64)
	assert(DeviceLabRuntimeScript.validate_command(oversized).get("error", "") == "payload_size", "oversized payload accepted")
	var unknown := status.duplicate(true)
	unknown["action"] = "execute_script"
	assert(DeviceLabRuntimeScript.validate_command(unknown).get("error", "") == "unknown_action", "unknown action accepted")
	var unknown_field := status.duplicate(true)
	unknown_field["unexpected"] = true
	assert(str(DeviceLabRuntimeScript.validate_command(unknown_field).get("error", "")).begins_with("unknown_field"), "unknown command field accepted")
	var weak_allowlist := status.duplicate(true)
	weak_allowlist["allowlist"] = ["status"]
	assert(DeviceLabRuntimeScript.validate_command(weak_allowlist).get("error", "") == "allowlist", "weak allowlist accepted")
	var bad_hash := oversized.duplicate(true)
	bad_hash["size"] = 4
	bad_hash["checksum"] = "NOT_A_HASH"
	assert(DeviceLabRuntimeScript.validate_command(bad_hash).get("error", "") == "payload_checksum", "bad hash format accepted")
	var root_dir := DirAccess.open("user://")
	assert(root_dir != null and root_dir.make_dir_recursive("device_lab/inbox") == OK, "test mailbox directory unavailable")
	var payload_path := "user://device_lab/inbox/layout_status_001.json"
	var payload_file := FileAccess.open(payload_path, FileAccess.WRITE)
	payload_file.store_string("{}")
	payload_file.close()
	var runtime := DeviceLabRuntimeScript.new()
	var mismatch := runtime.call("_load_external_contract", {
		"profile": "inventory",
		"path": payload_path,
		"size": 2,
		"checksum": "0".repeat(64),
	}) as Dictionary
	assert(mismatch.get("error", "") == "payload_checksum_mismatch", "payload hash mismatch accepted")
	DirAccess.remove_absolute(payload_path)
	var player_apply := {
		"schemaVersion": 1,
		"nonce": "player_001",
		"action": "apply_player_state",
		"allowlist": ["device_lab.v1", "apply_player_state"],
		"path": "user://device_lab/inbox/player_player_001.json",
		"size": 2,
		"checksum": "0".repeat(64),
	}
	assert(DeviceLabRuntimeScript.validate_command(player_apply).get("ok", false), "valid player-state command rejected")
	var ensure_chiyue := {
		"schemaVersion": 1,
		"nonce": "chiyue_roster_001",
		"action": "ensure_chiyue_test_roster",
		"allowlist": ["device_lab.v1", "ensure_chiyue_test_roster"],
	}
	assert(
		DeviceLabRuntimeScript.validate_command(ensure_chiyue).get("ok", false),
		"valid Chiyue roster command rejected",
	)
	var unknown_player_field := player_apply.duplicate(true)
	unknown_player_field["profile"] = "inventory"
	assert(str(DeviceLabRuntimeScript.validate_command(unknown_player_field).get("error", "")).begins_with("unknown_field"), "player-state command accepted unknown field")


func _test_player_state_roundtrip() -> void:
	const TEST_DIRECTORY := "user://device_lab_runtime_profiles"
	const TEST_INDEX := "user://device_lab_runtime_profile_index.json"
	var old_directory: String = PlayerState.profile_directory
	var old_index: String = PlayerState.profile_index_path
	var old_test_mode: bool = PlayerState.test_mode
	var old_active: String = PlayerState.active_profile_id
	_cleanup_player_state_fixture(TEST_DIRECTORY, TEST_INDEX)
	PlayerState.profile_directory = TEST_DIRECTORY
	PlayerState.profile_index_path = TEST_INDEX
	PlayerState.test_mode = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	PlayerState.active_profile_id = "device_lab_test_profile"
	PlayerState.character_name = "实验室存档"
	PlayerState.reset_progress(false)
	PlayerState.level = 7
	PlayerState.gold = 321
	PlayerState.recalculate_stats()
	assert(PlayerState.save_game(), "device-lab fixture save failed")
	var exported: Dictionary = PlayerState.device_lab_active_save_document()
	assert(str(exported.get("profile_id", "")) == PlayerState.active_profile_id, "exported profile identity mismatch")
	var edited := exported.duplicate(true)
	edited["gold"] = 654321
	edited["level"] = 8
	var applied: Dictionary = PlayerState.device_lab_apply_save_document(edited)
	assert(bool(applied.get("ok", false)), "valid player-state replacement failed")
	assert(PlayerState.gold == 654321 and PlayerState.level == 8, "player-state replacement did not reload runtime")
	var invalid := edited.duplicate(true)
	invalid["profile_id"] = "wrong_profile"
	var invalid_result: Dictionary = PlayerState.device_lab_apply_save_document(invalid)
	assert(not bool(invalid_result.get("ok", true)) and PlayerState.gold == 654321, "invalid player-state replacement mutated runtime")
	var runtime := DeviceLabRuntimeScript.new()
	add_child(runtime)
	runtime.call("_ensure_mailbox_dirs")
	var checkpoint: String = str(runtime.call("_create_player_checkpoint", "roundtrip_checkpoint"))
	assert(not checkpoint.is_empty(), "player checkpoint was not created")
	var changed := PlayerState.device_lab_active_save_document()
	changed["gold"] = 111
	assert(bool(PlayerState.device_lab_apply_save_document(changed).get("ok", false)), "pre-rollback mutation failed")
	var restored: Dictionary = runtime.call("_rollback_player_state", {"nonce": "rollback_test", "checkpoint": checkpoint})
	assert(bool(restored.get("ok", false)) and PlayerState.gold == 654321, "checkpoint rollback did not restore player state")
	PlayerState.profile_directory = old_directory
	PlayerState.profile_index_path = old_index
	PlayerState.active_profile_id = old_active
	PlayerState.test_mode = old_test_mode
	_cleanup_player_state_fixture(TEST_DIRECTORY, TEST_INDEX)


func _cleanup_player_state_fixture(directory_path: String, index_path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(index_path + suffix)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory_path)):
		var directory := DirAccess.open(directory_path)
		if directory != null:
			for file_name: String in directory.get_files():
				DirAccess.remove_absolute(directory_path + "/" + file_name)
		DirAccess.remove_absolute(directory_path)


func _test_chiyue_test_roster_append_only() -> void:
	var test_root := "user://device_lab_chiyue_roster_%d" % Time.get_ticks_usec()
	var test_directory := test_root + "/characters"
	var test_index := test_root + "/character_profiles.json"
	var old_directory: String = PlayerState.profile_directory
	var old_index: String = PlayerState.profile_index_path
	var old_test_mode: bool = PlayerState.test_mode
	var old_failure_injection: bool = PlayerState._test_force_atomic_write_failure
	PlayerState.profile_directory = test_directory
	PlayerState.profile_index_path = test_index
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_directory))

	var user_profile_id := "user_preserved_character"
	var user_profile := {
		"profile_id": user_profile_id,
		"character_name": "保留的用户角色",
		"profession": "战士",
		"gold": 7654321,
	}
	assert(PlayerState._write_json_atomic(
		PlayerState._profile_path(user_profile_id),
		user_profile
	))
	var user_index_entry := {
		"id": user_profile_id,
		"name": "保留的用户角色",
		"profession": "战士",
		"gender": "男",
		"level": 47,
		"updated_at": 123456,
	}
	assert(PlayerState._write_json_atomic(test_index, {
		"version": 1,
		"profiles": [user_index_entry],
	}))

	var warrior_loadout := EquipmentTestLoadoutCatalog.get_loadout("战士", "chiyue")
	var warrior_skills := TestCharacterSkillProfiles.qa_v2_profile_for_character(
		"warrior",
		"chiyue"
	)
	var warrior_id := "test.character.warrior.chiyue.v2"
	var warrior_entry := {
		"id": warrior_id,
		"name": str(warrior_skills.get("character_name", warrior_id)),
		"profession": "战士",
		"gender": str(warrior_loadout.get("gender", "男")),
		"level": 50,
		"updated_at": 222222,
	}
	var warrior_payload := PlayerState._test_character_payload(
		warrior_loadout,
		warrior_skills,
		warrior_entry,
		222222
	)
	warrior_payload["gold"] = 24681357
	assert(PlayerState._write_json_atomic(
		PlayerState._profile_path(warrior_id),
		warrior_payload
	))
	var user_bytes_before := FileAccess.get_file_as_bytes(
		PlayerState._profile_path(user_profile_id)
	)
	var warrior_bytes_before := FileAccess.get_file_as_bytes(
		PlayerState._profile_path(warrior_id)
	)

	var runtime := DeviceLabRuntimeScript.new()
	add_child(runtime)
	var first: Dictionary = await runtime.call("_execute", {
		"action": "ensure_chiyue_test_roster",
	})
	assert(bool(first.get("ok", false)), "Chiyue roster append failed: %s" % first)
	assert(int(first.get("created", -1)) == 2)
	assert(int(first.get("indexed", -1)) == 3)
	assert(int(first.get("existing", -1)) == 1)
	assert(int(first.get("total", -1)) == 3)
	assert(first.get("profile_ids", []) == PlayerState.CHIYUE_TEST_PROFILE_IDS)
	assert(
		FileAccess.get_file_as_bytes(PlayerState._profile_path(user_profile_id))
		== user_bytes_before,
		"existing user profile bytes changed",
	)
	assert(
		FileAccess.get_file_as_bytes(PlayerState._profile_path(warrior_id))
		== warrior_bytes_before,
		"existing Chiyue profile bytes changed",
	)
	var index_after_first := PlayerState._read_json(test_index)
	var indexed_ids: Array[String] = []
	for value: Variant in index_after_first.get("profiles", []):
		assert(value is Dictionary)
		indexed_ids.append(str((value as Dictionary).get("id", "")))
	assert(indexed_ids.count(user_profile_id) == 1)
	for target_id: String in PlayerState.CHIYUE_TEST_PROFILE_IDS:
		assert(indexed_ids.count(target_id) == 1)
	var preserved_user_index: Dictionary = index_after_first.get("profiles", [])[0]
	assert(preserved_user_index.size() == user_index_entry.size())
	for key: String in user_index_entry:
		var before_value: Variant = user_index_entry[key]
		var after_value: Variant = preserved_user_index.get(key, "")
		if before_value is int or before_value is float:
			assert(is_equal_approx(float(after_value), float(before_value)))
		else:
			assert(str(after_value) == str(before_value))
	assert(indexed_ids.size() == 4, "unexpected Wooma/Zuma test profiles were indexed")
	var files := DirAccess.get_files_at(test_directory)
	var profile_json_files: Array[String] = []
	for file_name: String in files:
		if file_name.ends_with(".json") and not file_name.ends_with(".bak"):
			profile_json_files.append(file_name)
	assert(profile_json_files.size() == 4, "only user plus three Chiyue profiles may exist")
	for forbidden_tier: String in ["woma", "zuma"]:
		for file_name: String in profile_json_files:
			assert(not file_name.contains(".%s." % forbidden_tier))

	var profile_bytes_before_repeat := {}
	for profile_id: String in [user_profile_id] + PlayerState.CHIYUE_TEST_PROFILE_IDS:
		profile_bytes_before_repeat[profile_id] = FileAccess.get_file_as_bytes(
			PlayerState._profile_path(profile_id)
		)
	var index_bytes_before_repeat := FileAccess.get_file_as_bytes(test_index)
	var second: Dictionary = await runtime.call("_execute", {
		"action": "ensure_chiyue_test_roster",
	})
	assert(bool(second.get("ok", false)), "idempotent Chiyue roster call failed")
	assert(int(second.get("created", -1)) == 0)
	assert(int(second.get("indexed", -1)) == 0)
	assert(int(second.get("existing", -1)) == 3)
	assert(int(second.get("total", -1)) == 3)
	assert(FileAccess.get_file_as_bytes(test_index) == index_bytes_before_repeat)
	for profile_id: String in profile_bytes_before_repeat:
		assert(
			FileAccess.get_file_as_bytes(PlayerState._profile_path(profile_id))
			== profile_bytes_before_repeat[profile_id]
		)

	var failure_root := test_root + "/failure"
	PlayerState.profile_directory = failure_root + "/characters"
	PlayerState.profile_index_path = failure_root + "/character_profiles.json"
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(PlayerState.profile_directory)
	)
	PlayerState._test_force_atomic_write_failure = true
	var failed: Dictionary = await runtime.call("_execute", {
		"action": "ensure_chiyue_test_roster",
	})
	assert(not bool(failed.get("ok", true)), "write failure reported success")
	assert(int(failed.get("created", -1)) == 0)
	assert(int(failed.get("indexed", -1)) == 0)
	assert(int(failed.get("existing", -1)) == 0)
	assert(int(failed.get("total", -1)) == 3)
	assert(DirAccess.get_files_at(PlayerState.profile_directory).is_empty())

	runtime.queue_free()
	PlayerState.profile_directory = old_directory
	PlayerState.profile_index_path = old_index
	PlayerState.test_mode = old_test_mode
	PlayerState._test_force_atomic_write_failure = old_failure_injection


func _test_external_profile_guards() -> void:
	var root := Control.new()
	root.name = "InventoryRoot"
	root.size = Vector2(100, 100)
	add_child(root)
	var bag := Control.new()
	bag.name = "BagPanel"
	bag.size = Vector2(100, 100)
	root.add_child(bag)
	var scroll := Control.new()
	scroll.name = "InventoryScroll"
	scroll.size = Vector2(100, 100)
	bag.add_child(scroll)
	var grid := Control.new()
	grid.name = "ItemGrid"
	grid.size = Vector2(100, 100)
	scroll.add_child(grid)
	var dynamic_cell := Control.new()
	dynamic_cell.name = "InventoryCell_000"
	dynamic_cell.position = Vector2(4, 4)
	dynamic_cell.size = Vector2(20, 20)
	grid.add_child(dynamic_cell)
	var dynamic_button := Button.new()
	dynamic_button.name = "ItemButton"
	dynamic_button.position = Vector2(2, 2)
	dynamic_button.size = Vector2(16, 16)
	grid.get_child(0).add_child(dynamic_button)
	var runtime_label := Label.new()
	runtime_label.name = "RuntimeText"
	runtime_label.text = "live inventory sentinel"
	runtime_label.set_meta("calibration_runtime_text", true)
	root.add_child(runtime_label)
	var before_dynamic := Rect2(dynamic_button.position, dynamic_button.size)
	var contract := {
		"schemaVersion": LayoutLoader.SCHEMA_VERSION,
		"profiles": {
			"inventory": {
				"logicalDesignSize": [100.0, 100.0],
				"nodes": {
					"BagPanel": {"logicalRect": [1.0, 1.0, 90.0, 90.0], "visible": true},
					"BagPanel/InventoryScroll/ItemGrid/InventoryCell_000/ItemButton": {"logicalRect": [30.0, 30.0, 30.0, 30.0], "visible": true},
					"RuntimeText": {"logicalRect": [10.0, 10.0, 70.0, 20.0], "text": "stale saved text", "visible": true},
				},
			},
		},
	}
	assert(LayoutLoader.validate_external_profile("inventory", contract).get("ok", false), "valid external profile rejected")
	var invalid_entry := contract.duplicate(true)
	invalid_entry["profiles"]["inventory"]["nodes"]["RuntimeText"]["script"] = "res://evil.gd"
	assert(not LayoutLoader.validate_external_profile("inventory", invalid_entry).get("ok", false), "unknown entry property accepted")
	LayoutLoader.apply_profile(root, "inventory", contract)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(Rect2(dynamic_button.position, dynamic_button.size).is_equal_approx(before_dynamic), "dynamic inventory child received external geometry")
	assert(runtime_label.text == "live inventory sentinel", "runtime text was overwritten by external profile")


func _test_bounded_snapshot() -> void:
	var root := Node2D.new()
	root.name = "SnapshotRoot"
	add_child(root)
	var bag := Control.new()
	bag.name = "BagPanel"
	root.add_child(bag)
	var scroll := Control.new()
	scroll.name = "InventoryScroll"
	bag.add_child(scroll)
	var grid := Control.new()
	grid.name = "ItemGrid"
	scroll.add_child(grid)
	for index in range(400):
		var cell := Control.new()
		cell.name = "InventoryCell_%03d" % index
		grid.add_child(cell)
	for index in range(400):
		var actor := Node2D.new()
		actor.name = "Actor_%03d" % index
		actor.position = Vector2(index, index)
		root.add_child(actor)
	var snapshot := DeviceLabRuntimeScript.build_snapshot(root)
	assert((snapshot["controls"] as Array).size() <= DeviceLabRuntimeScript.MAX_SNAPSHOT_CONTROLS, "control snapshot exceeded bound")
	assert((snapshot["node2d"] as Array).size() <= DeviceLabRuntimeScript.MAX_SNAPSHOT_NODE2D, "Node2D snapshot exceeded bound")
	assert(not JSON.stringify(snapshot).to_lower().contains("inventorycell"), "snapshot leaked full dynamic inventory")
	assert(snapshot.has("window") and snapshot.has("player") and snapshot.has("scene"), "snapshot summary fields missing")
	var monster_streaming: Variant = snapshot.get("monster_streaming", null)
	assert(monster_streaming is Dictionary, "monster streaming snapshot missing")
	for field: String in DeviceLabRuntimeScript.MONSTER_STREAMING_DIAGNOSTIC_FIELDS:
		assert((monster_streaming as Dictionary).has(field), "monster streaming diagnostic field missing: %s" % field)
		var streaming_value: Variant = (monster_streaming as Dictionary).get(field)
		assert(streaming_value is int or streaming_value is float, "monster streaming diagnostic field is not numeric: %s" % field)
		assert(float(streaming_value) >= 0.0, "monster streaming diagnostic field is negative: %s" % field)
	var performance: Variant = snapshot.get("performance", null)
	assert(performance is Dictionary, "performance snapshot missing")
	assert(is_equal_approx(DeviceLabRuntimeScript._seconds_to_milliseconds(0.25), 250.0), "seconds-to-ms conversion is incorrect")
	assert(DeviceLabRuntimeScript._seconds_to_milliseconds(-1.0) == 0.0, "negative seconds were not clamped")
	var performance_fields := [
		"fps",
		"process_ms",
		"physics_process_ms",
		"node_count",
		"object_count",
		"resource_count",
		"render_objects",
		"render_primitives",
		"draw_calls",
		"video_mem",
		"texture_mem",
		"buffer_mem",
	]
	for field: String in performance_fields:
		assert((performance as Dictionary).has(field), "performance field missing: %s" % field)
		var value: Variant = (performance as Dictionary).get(field)
		assert(value is int or value is float, "performance field is not numeric: %s" % field)
		assert(float(value) >= 0.0, "performance field is negative: %s" % field)
	var camera := Camera2D.new()
	camera.name = "WorldCamera"
	camera.zoom = Vector2(1.25, 1.25)
	root.add_child(camera)
	var camera_snapshot := DeviceLabRuntimeScript.build_snapshot(root)
	assert(camera_snapshot["scene"].get("camera_zoom", -1.0) == 1.25, "WorldCamera zoom missing from snapshot")
	var enemy_nodes: Array[Node2D] = []
	for index in range(DeviceLabRuntimeScript.MAX_SNAPSHOT_ENEMY_ACTIVITY_SCAN + 4):
		var enemy := Node2D.new()
		enemy.name = "TelemetryEnemy_%03d" % index
		enemy.add_to_group("enemies")
		root.add_child(enemy)
		enemy_nodes.append(enemy)
	var enemy_activity: Variant = DeviceLabRuntimeScript.build_snapshot(root).get("enemy_activity", null)
	assert(enemy_activity is Dictionary, "enemy activity snapshot missing")
	for field: String in [
		"total",
		"visible",
		"within_1600_px",
		"within_2000_px",
		"visual_resources_active",
		"background_ai_eligible",
		"inspected",
	]:
		assert((enemy_activity as Dictionary).has(field), "enemy activity field missing: %s" % field)
		var value: Variant = (enemy_activity as Dictionary).get(field)
		assert(value is int or value is float, "enemy activity field is not numeric: %s" % field)
		assert(float(value) >= 0.0, "enemy activity field is negative: %s" % field)
	assert(int((enemy_activity as Dictionary).get("total", -1)) == enemy_nodes.size(), "enemy activity total mismatch")
	assert(int((enemy_activity as Dictionary).get("inspected", -1)) <= DeviceLabRuntimeScript.MAX_SNAPSHOT_ENEMY_ACTIVITY_SCAN, "enemy activity scan exceeded bound")
	assert(int((enemy_activity as Dictionary).get("visible", -1)) <= int((enemy_activity as Dictionary).get("inspected", -1)), "visible count exceeded inspected bound")
	var enemy_diagnostics: Variant = (enemy_activity as Dictionary).get("enemy_diagnostics", null)
	assert(enemy_diagnostics is Dictionary, "enemy diagnostics snapshot missing")
	for field: String in DeviceLabRuntimeScript.ENEMY_DIAGNOSTIC_FIELDS:
		assert((enemy_diagnostics as Dictionary).has(field), "enemy diagnostic field missing: %s" % field)
		var value: Variant = (enemy_diagnostics as Dictionary).get(field)
		assert(value is int or value is float, "enemy diagnostic field is not numeric: %s" % field)
		assert(float(value) >= 0.0, "enemy diagnostic field is negative: %s" % field)
	for control: Dictionary in snapshot["controls"] as Array:
		assert(control.has("textHash") and control.has("runtime_text"), "control redaction fields missing")


func _test_transaction_rollback() -> void:
	var root := Control.new()
	root.name = "TransactionRoot"
	root.size = Vector2(100, 100)
	add_child(root)
	var bag := Control.new()
	bag.name = "BagPanel"
	bag.position = Vector2(7, 8)
	bag.size = Vector2(40, 40)
	root.add_child(bag)
	var runtime_label := Label.new()
	runtime_label.name = "RuntimeText"
	runtime_label.position = Vector2(50, 5)
	runtime_label.size = Vector2(40, 15)
	runtime_label.text = "transaction sentinel"
	root.add_child(runtime_label)
	var contract := {
		"schemaVersion": LayoutLoader.SCHEMA_VERSION,
		"profiles": {
			"inventory": {
				"logicalDesignSize": [100.0, 100.0],
				"nodes": {
					"BagPanel": {"logicalRect": [20.0, 20.0, 60.0, 60.0], "visible": true},
					"RuntimeText": {"logicalRect": [10.0, 10.0, 70.0, 20.0], "text": "must not write", "visible": true},
				},
			},
		},
	}
	var before := Rect2(bag.position, bag.size)
	# A second loader invocation changes the target token while the external
	# transaction is awaiting a frame; the first transaction must roll back.
	call_deferred("_compete_profile", root, contract)
	var result: Dictionary = await LayoutLoader.apply_external_profile_transaction(root, "inventory", contract)
	assert(not bool(result.get("ok", true)), "token change incorrectly reported success")
	assert(bool(result.get("rolledBack", false)), "failed transaction did not report rollback")
	assert(Rect2(bag.position, bag.size).is_equal_approx(before), "failed transaction did not restore geometry")
	assert(runtime_label.text == "transaction sentinel", "transaction touched runtime text")


func _compete_profile(root: Control, contract: Dictionary) -> void:
	LayoutLoader.apply_profile(root, "inventory", contract)


func _test_ui_checkpoint_rollback() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var panel := InventoryPanelScript.new()
	add_child(panel)
	await get_tree().process_frame
	var bag := panel.get_node("BagPanel") as Control
	var before := Rect2(bag.position, bag.size)
	var moved := Rect2(before.position + Vector2(9, 7), before.size - Vector2(11, 5))
	var contract := {
		"schemaVersion": LayoutLoader.SCHEMA_VERSION,
		"profiles": {
			"inventory": {
				"logicalDesignSize": [panel.size.x, panel.size.y],
				"nodes": {
					"BagPanel": {"logicalRect": [moved.position.x, moved.position.y, moved.size.x, moved.size.y], "visible": true},
				},
			},
		},
	}
	var runtime := DeviceLabRuntimeScript.new().configure(self)
	add_child(runtime)
	runtime.call("_ensure_mailbox_dirs")
	var applied: Dictionary = await runtime.call("_apply_ui_profile", {
		"nonce": "ui_checkpoint_apply",
		"profile": "inventory",
		"layout": contract,
	})
	assert(bool(applied.get("ok", false)), "checkpointed UI patch failed")
	assert(Rect2(bag.position, bag.size).is_equal_approx(moved), "UI patch geometry did not apply")
	var checkpoint := str(applied.get("checkpoint", ""))
	assert(not checkpoint.is_empty(), "UI patch did not return checkpoint")
	var restored: Dictionary = await runtime.call("_rollback_ui_profile", {
		"nonce": "ui_checkpoint_restore",
		"checkpoint": checkpoint,
	})
	assert(bool(restored.get("ok", false)), "UI checkpoint rollback failed")
	assert(Rect2(bag.position, bag.size).is_equal_approx(before), "UI checkpoint did not restore original geometry")
	panel.queue_free()


func _test_nonce_and_outbox_guards() -> void:
	var runtime := DeviceLabRuntimeScript.new()
	add_child(runtime)
	var nonce := "nonce_guard_%d" % Time.get_ticks_msec()
	var first: Variant = runtime.call("_write_result", nonce, {"ok": true, "value": "first"})
	var second: Variant = runtime.call("_write_result", nonce, {"ok": true, "value": "second"})
	assert(bool(first), "first result write failed")
	assert(not bool(second), "duplicate result overwrote existing nonce")
	var result_path := DeviceLabRuntimeScript.OUTBOX_DIR + "/result_%s.json" % nonce
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path))
	assert(str(saved.get("value", "")) == "first", "duplicate nonce changed old result")
	runtime.call("_remember_nonce", nonce)
	var pending := {
		"schemaVersion": DeviceLabRuntimeScript.PROTOCOL_VERSION,
		"nonce": nonce,
		"action": "status",
		"allowlist": [DeviceLabRuntimeScript.ALLOWLIST_ID, "status"],
	}
	var pending_file := FileAccess.open(DeviceLabRuntimeScript.PENDING_PATH, FileAccess.WRITE)
	pending_file.store_string(JSON.stringify(pending))
	pending_file.close()
	await runtime.call("_poll_inbox")
	var replay_saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path))
	assert(str(replay_saved.get("value", "")) == "first", "nonce replay overwrote original result")
	DirAccess.remove_absolute(result_path)
	var oversized: Variant = runtime.call("_write_result", "oversized_%d" % Time.get_ticks_msec(), {"payload": "x".repeat(DeviceLabRuntimeScript.MAX_RESULT_BYTES)})
	assert(not bool(oversized), "oversized result was emitted")
	var files_before := DirAccess.get_files_at(DeviceLabRuntimeScript.OUTBOX_DIR)
	for index in range(DeviceLabRuntimeScript.MAX_OUTBOX_ENTRIES + 8):
		var path := DeviceLabRuntimeScript.OUTBOX_DIR + "/result_prune_%03d.json" % index
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("{}")
		file.close()
	runtime.call("_prune_outbox")
	var files_after := DirAccess.get_files_at(DeviceLabRuntimeScript.OUTBOX_DIR)
	var result_count := 0
	for name: String in files_after:
		if name.begins_with("result_") and name.ends_with(".json"):
			result_count += 1
	assert(result_count <= DeviceLabRuntimeScript.MAX_OUTBOX_ENTRIES, "outbox prune exceeded entry bound")


func _test_debug_gate() -> void:
	var runtime := DeviceLabRuntimeScript.new()
	runtime.set_debug_gate_for_test(false)
	add_child(runtime)
	await get_tree().process_frame
	assert(not runtime.mailbox_initialized_for_test(), "non-debug Device Lab initialized mailbox")


func _test_powershell_contract() -> void:
	var source := FileAccess.get_file_as_string("res://tools/device_lab.ps1")
	assert(source.contains("ValidatePattern('^$|^[A-Za-z0-9._:-]{1,128}$')"), "PS serial safety regex missing")
	assert(source.contains("ValidatePattern('^[A-Za-z][A-Za-z0-9_]*"), "PS package id safety regex missing")
	assert(source.contains("Device Lab mailbox is busy; refusing to overwrite"), "PS pending overwrite guard missing")
	assert(source.contains("Move-Item -LiteralPath $hostTemp -Destination $targetPath -Force"), "PS pull atomic move missing")
	assert(source.contains("$DeviceLabPrivateRoot = 'files/device_lab'"), "PS Android user:// private root mapping missing")
	assert(source.contains("$result = $text | ConvertFrom-Json"), "PS pull result validation missing")
	assert(not source.contains("ConvertFrom-Json -Depth"), "PS tool must remain compatible with Windows PowerShell 5.1")
	assert(source.contains("Invoke-Adb -Arguments @('pull', $remoteScreenshot, $target)"), "PS screenshot must use binary-safe adb pull")
	assert(source.contains("'export_player_state' { $result.document; break }"), "PS player-state export routing missing")
	assert(source.contains("'ensure_chiyue_test_roster'"), "PS Chiyue roster action missing")
	assert(source.contains("'repair_diagnostics' { $result; break }"), "PS repair diagnostics export routing missing")
	assert(source.contains("'reset_diagnostics'"), "PS reset diagnostics action missing")
	assert(source.contains("'read_diagnostics'"), "PS read diagnostics action missing")
	assert(source.contains("'stop_diagnostics'"), "PS stop diagnostics action missing")
	assert(source.contains("'reset_diagnostics' { $result.performance_diagnostics; break }"), "PS reset diagnostics output routing missing")
	assert(source.contains("'read_diagnostics' { $result.performance_diagnostics; break }"), "PS read diagnostics output routing missing")
	assert(source.contains("'stop_diagnostics' { $result.performance_diagnostics; break }"), "PS stop diagnostics output routing missing")
	assert(source.contains("ConvertTo-Json -Depth 100"), "PS structured export must preserve nested save data")


func _test_mailbox_roundtrip() -> void:
	# Each runner invocation reuses its isolated user:// directory. Remove only
	# this test's prior mailbox identity state so a previous successful run does
	# not correctly trigger the production replay guard on the next run.
	DirAccess.remove_absolute(DeviceLabRuntimeScript.PENDING_PATH)
	DirAccess.remove_absolute(DeviceLabRuntimeScript.PROCESSING_PATH)
	DirAccess.remove_absolute(DeviceLabRuntimeScript.NONCE_HISTORY_PATH)
	var inbox := DirAccess.open("user://device_lab/inbox")
	var outbox := DirAccess.open("user://device_lab/outbox")
	assert(inbox != null and outbox != null, "mailbox directories missing")
	var nonce := "test_roundtrip_%d" % Time.get_ticks_msec()
	var pending := {
		"schemaVersion": DeviceLabRuntimeScript.PROTOCOL_VERSION,
		"nonce": nonce,
		"action": "status",
		"allowlist": [DeviceLabRuntimeScript.ALLOWLIST_ID, "status"],
	}
	var file := FileAccess.open(DeviceLabRuntimeScript.PENDING_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(pending))
	file.close()
	var runtime := DeviceLabRuntimeScript.new()
	add_child(runtime)
	await runtime.call("_poll_inbox")
	var result_path := DeviceLabRuntimeScript.OUTBOX_DIR + "/result_%s.json" % nonce
	assert(FileAccess.file_exists(result_path), "mailbox result missing")
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path))
	assert(result is Dictionary and bool((result as Dictionary).get("ok", false)), "mailbox status failed")
	assert(str((result as Dictionary).get("nonce", "")) == nonce, "mailbox result nonce missing")
	assert(not FileAccess.file_exists(DeviceLabRuntimeScript.PROCESSING_PATH), "processing command was not removed")
	DirAccess.remove_absolute(result_path)
