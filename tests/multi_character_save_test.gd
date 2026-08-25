extends Node

const TEST_DIRECTORY := "user://character_test_profiles"
const TEST_INDEX := "user://character_test_index.json"


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
	var warrior_name := ProfessionRules.profession_display_name("warrior")
	assert(PlayerState.create_character("长风", warrior_name, "男").is_empty())
	var first_id: String = PlayerState.active_profile_id
	PlayerState.level = 12
	PlayerState.gold = 3456
	var fire_sword_name := ProfessionRules.skill_display_name("warrior.fire_sword")
	var wild_rush_name := ProfessionRules.skill_display_name("warrior.wild_rush")
	PlayerState.learned_skills = {fire_sword_name: 3, wild_rush_name: 3}
	var slot_result := SkillLoadoutRules.assign_button_slot(
		PlayerState.skill_button_assignments_snapshot(),
		PlayerState.learned_skills,
		{
			"contract_id": "ui.skill.button_assignment.v3",
			"slot_group": "attack_ring",
			"slot_index": 2,
			"skill_id": "warrior.wild_rush",
		}
	)
	assert(PlayerState.apply_skill_button_assignment(slot_result))
	assert(PlayerState.apply_warrior_runtime_state({
		"contract_id": "gameplay.warrior.skill_runtime.v2",
		"toggles": {
			"warrior.thrusting": true,
			"warrior.half_moon": false,
			"warrior.fire_sword.auto_enabled": true,
		},
		"cooldowns": {"warrior.fire_sword.ready_remaining_ms": 4321},
	}))
	var field_ground_position_gu := Vector2(17.25, 8.5)
	PlayerState.update_world_location(
		217,
		Vector2(321.5, -84.0),
		field_ground_position_gu
	)
	assert(PlayerState.save_game())

	assert(PlayerState.create_character("红叶", warrior_name, "女").is_empty())
	var second_id: String = PlayerState.active_profile_id
	assert(first_id != second_id, "profile ids must be unique")
	assert(
		not bool(
			PlayerState.warrior_runtime_state_for_restore().toggles[
				"warrior.fire_sword.auto_enabled"
			]
		)
	)
	assert(
		PlayerState.taoist_main_pet_runtime_states_for_restore().slots.is_empty(),
		"new profile inherited summon slots"
	)
	var second_path := TEST_DIRECTORY + "/" + second_id + ".json"
	var missing_field_payload: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(second_path)
	)
	assert(missing_field_payload is Dictionary)
	assert(int(missing_field_payload.get("save_version", 0)) == PlayerState.SAVE_VERSION)
	assert(not (missing_field_payload as Dictionary).has("taoist_main_pet_runtime_state"))
	assert(not (missing_field_payload as Dictionary).has("taoist_main_pet_runtime_states"))
	PlayerState.load_save()
	assert(
		PlayerState.taoist_main_pet_runtime_states_for_restore().slots.is_empty(),
		"current save without summon fields did not load compatibly"
	)

	# Character creation remains warrior-only. Switch this existing profile to
	# the supported Taoist runtime before attaching two typed summon snapshots.
	PlayerState.profession = ProfessionRules.profession_display_name("taoist")
	var skeleton_snapshot := _summon_snapshot(
		"skeleton",
		"taoist.summon_skeleton",
		412,
		520,
		51,
		3456.25,
		"skeleton"
	)
	var divine_snapshot := _summon_snapshot(
		"divine_beast",
		"taoist.summon_divine_beast",
		731,
		840,
		88,
		4567.5,
		"divine"
	)

	# Migrate the faulty short-lived APK's singular key into its typed slot.
	var legacy_payload := (missing_field_payload as Dictionary).duplicate(true)
	legacy_payload["profession"] = PlayerState.profession
	legacy_payload["taoist_main_pet_runtime_state"] = skeleton_snapshot
	_write_json(second_path, legacy_payload)
	PlayerState.load_save()
	_assert_summon_snapshot_equal(
		PlayerState.taoist_main_pet_runtime_state_for_restore("skeleton"),
		skeleton_snapshot
	)
	assert(
		PlayerState.taoist_main_pet_runtime_state_for_restore(
			"divine_beast"
		).is_empty()
	)

	var dual_states := {
		"contract_id": "skills.summon.persistence.runtime_states.v1",
		"slots": {
			"skeleton": skeleton_snapshot,
			"divine_beast": divine_snapshot,
		},
	}
	assert(PlayerState.apply_taoist_main_pet_runtime_states(dual_states))
	assert(PlayerState.save_game(), "dual summon state was not saved")
	var rewritten_payload: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(second_path)
	)
	assert(rewritten_payload is Dictionary)
	assert(not (rewritten_payload as Dictionary).has("taoist_main_pet_runtime_state"))
	assert((rewritten_payload as Dictionary).has("taoist_main_pet_runtime_states"))

	var profiles: Array[Dictionary] = PlayerState.list_characters()
	assert(profiles.size() == 2)
	assert(PlayerState.select_character(first_id))
	assert(
		PlayerState.character_name == "长风"
		and PlayerState.level == 12
		and PlayerState.gold == 3456
	)
	assert(PlayerState.taoist_main_pet_runtime_states_for_restore().slots.is_empty())
	assert(PlayerState.attack_ring_slots[2] == wild_rush_name)
	assert(PlayerState.quick_slots[2] == wild_rush_name)
	var restored_runtime := PlayerState.warrior_runtime_state_for_restore()
	assert(bool(restored_runtime.toggles["warrior.fire_sword.auto_enabled"]))
	assert(not restored_runtime.cooldowns.has("warrior.fire_sword.ready_remaining_ms"))
	assert(
		PlayerState.saved_map_id == 217
		and PlayerState.saved_position.is_equal_approx(Vector2(321.5, -84.0))
	)
	assert(
		PlayerState.saved_ground_position_gu_valid
		and PlayerState.saved_ground_position_gu.is_equal_approx(
			field_ground_position_gu
		)
	)
	var expected_home := MapCoordinateMapper.source_to_world(
		Vector2(289, 618), Vector2i(700, 700)
	)
	var expected_home_ground_gu := Vector2(289, 618)
	assert(PlayerState.save_safe_logout(4, expected_home, expected_home_ground_gu))
	PlayerState.saved_map_id = 217
	PlayerState.saved_position = Vector2.ZERO
	PlayerState.saved_ground_position_gu = Vector2.ZERO
	PlayerState.saved_ground_position_gu_valid = false
	assert(PlayerState.select_character(first_id))
	assert(
		PlayerState.saved_map_id == 4
		and PlayerState.saved_position.is_equal_approx(expected_home)
	)
	assert(
		PlayerState.saved_ground_position_gu_valid
		and PlayerState.saved_ground_position_gu.is_equal_approx(
			expected_home_ground_gu
		)
	)
	assert(FileAccess.file_exists(TEST_DIRECTORY + "/" + first_id + ".json.bak"))

	assert(PlayerState.select_character(second_id))
	_assert_summon_snapshot_equal(
		PlayerState.taoist_main_pet_runtime_state_for_restore("skeleton"),
		skeleton_snapshot
	)
	_assert_summon_snapshot_equal(
		PlayerState.taoist_main_pet_runtime_state_for_restore("divine_beast"),
		divine_snapshot
	)
	# This is only a CharacterSelect UI construction smoke.
	# CharacterSelect intentionally suppresses the asynchronous main-scene
	# preload while PlayerState.test_mode is true.  Running that production
	# background preload and immediately queue_free()/quit() creates a teardown
	# race unrelated to profile persistence.
	var launcher_test_mode_before := PlayerState.test_mode
	PlayerState.test_mode = true
	var launcher: Node = load("res://scenes/character_select.tscn").instantiate()
	add_child(launcher)
	await get_tree().process_frame
	assert(launcher.get("list_box") != null and launcher.get("name_input") != null)
	launcher.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = launcher_test_mode_before

	PlayerState.profile_directory = old_directory
	PlayerState.profile_index_path = old_index
	PlayerState.test_mode = old_test_mode
	PlayerState.active_profile_id = ""
	_cleanup()
	print(
		"MULTI_CHARACTER_SAVE_PASS: profile isolation, legacy singular migration, "
		+ "typed dual summon save, atomic backup, safe logout"
	)
	get_tree().quit(0)


func _summon_snapshot(
	summon_id: String,
	skill_id: String,
	current_hp: int,
	max_hp: int,
	pet_growth_exp: int,
	remaining_lifetime: float,
	buff_suffix: String
) -> Dictionary:
	return {
		"contract_id": "skills.summon.persistence.runtime_state.v1",
		"alive": true,
		"runtime_state": "FOLLOW_OWNER",
		"summon_id": summon_id,
		"skill_id": skill_id,
		"skill_rank": 3,
		"owner_level": 40,
		"current_hp": current_hp,
		"max_hp": max_hp,
		"summon_exp_level": 3,
		"maximum_pet_level": 7,
		"pet_growth_exp": pet_growth_exp,
		"remaining_lifetime": remaining_lifetime,
		"stealth": {
			"remaining_seconds": 7.5,
			"buff_id": "buff.test.%s.stealth" % buff_suffix,
		},
		"physical_defence": {
			"bonus": 4,
			"remaining_seconds": 8.5,
			"buff_id": "buff.test.%s.defense" % buff_suffix,
		},
		"magic_defence": {
			"bonus": 5,
			"remaining_seconds": 9.5,
			"buff_id": "buff.test.%s.magic_defense" % buff_suffix,
		},
	}


func _assert_summon_snapshot_equal(actual: Dictionary, expected: Dictionary) -> void:
	for key: String in [
		"contract_id", "alive", "runtime_state", "summon_id", "skill_id",
		"skill_rank", "owner_level", "current_hp", "max_hp",
		"summon_exp_level", "maximum_pet_level", "pet_growth_exp",
		"remaining_lifetime",
	]:
		assert(actual.get(key) == expected.get(key), "summon field mismatch: %s" % key)
	for buff_key: String in ["stealth", "physical_defence", "magic_defence"]:
		var actual_buff: Dictionary = actual.get(buff_key, {})
		var expected_buff: Dictionary = expected.get(buff_key, {})
		for field: String in ["bonus", "remaining_seconds", "buff_id"]:
			if expected_buff.has(field):
				assert(
					actual_buff.get(field) == expected_buff.get(field),
					"summon buff mismatch: %s.%s" % [buff_key, field]
				)


func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "could not open singular migration fixture")
	file.store_string(JSON.stringify(payload))
	file.close()


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path := TEST_INDEX + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_directory):
		var directory := DirAccess.open(TEST_DIRECTORY)
		if directory != null:
			for file_name: String in directory.get_files():
				DirAccess.remove_absolute(absolute_directory.path_join(file_name))
		DirAccess.remove_absolute(absolute_directory)
