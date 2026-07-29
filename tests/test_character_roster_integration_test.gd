extends Node

const TEST_ROOT := "user://test_character_roster_integration"


func _ready() -> void:
	var old_index: String = PlayerState.profile_index_path
	var old_directory: String = PlayerState.profile_directory
	var old_marker: String = PlayerState.test_roster_reset_marker_path
	var unique_suffix := "%d_%d" % [Time.get_ticks_usec(), randi()]
	PlayerState.profile_directory = "%s/%s/characters" % [TEST_ROOT, unique_suffix]
	PlayerState.profile_index_path = "%s/%s/index.json" % [TEST_ROOT, unique_suffix]
	PlayerState.test_roster_reset_marker_path = "%s/%s/reset_marker.json" % [TEST_ROOT, unique_suffix]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	assert(PlayerState._write_json_atomic(
		PlayerState._profile_path("legacy_test_character"),
		{"profile_id": "legacy_test_character", "character_name": "旧测试人物"}
	))
	assert(PlayerState._write_json_atomic(PlayerState.profile_index_path, {
		"version": 1,
		"profiles": [{"id": "legacy_test_character", "name": "旧测试人物"}],
	}))

	var first := PlayerState.prepare_qa_test_roster_v2()
	assert(bool(first.get("ok", false)))
	assert(bool(first.get("reset_performed", false)))
	assert(str(first.get("contract_id", "")) == PlayerState.TEST_CHARACTER_ROSTER_CONTRACT_ID)
	assert(int(first.get("created", 0)) == 9)
	assert(int(first.get("indexed", 0)) == 9)
	assert(not FileAccess.file_exists(PlayerState._profile_path("legacy_test_character")))
	assert(not str(first.get("archive_path", "")).is_empty())
	var profiles := PlayerState.list_characters()
	assert(profiles.size() == 9)

	var profession_counts := {"战士": 0, "法师": 0, "道士": 0}
	var total_equipment_slots := 0
	var total_learned_skills := 0
	for profile: Dictionary in profiles:
		var profile_id := str(profile.get("id", ""))
		var payload := PlayerState._read_json(PlayerState._profile_path(profile_id))
		var profession := str(payload.get("profession", ""))
		profession_counts[profession] = int(profession_counts.get(profession, 0)) + 1
		assert(str(payload.get("test_contracts", {}).get("roster", "")) == PlayerState.TEST_CHARACTER_ROSTER_CONTRACT_ID)
		assert(int(payload.get("level", 0)) >= 50)
		var equipment: Dictionary = payload.get("equipment", {})
		assert(equipment.size() == 8)
		for slot: String in PlayerState.EQUIPMENT_SLOTS:
			assert(not str(equipment.get(slot, {}).get("name", "")).is_empty())
			total_equipment_slots += 1
		var learned_skills: Dictionary = payload.get("learned_skills", {})
		var quick_slots: Array = payload.get("quick_slots", [])
		var assignments: Dictionary = payload.get("skill_button_assignments", {})
		assert(learned_skills.size() == _expected_skill_count(profession))
		assert(quick_slots.size() == 4)
		assert(str(assignments.get("contract_id", "")) == PlayerState.SKILL_BUTTON_ASSIGNMENTS_CONTRACT_ID)
		assert(assignments.get("center", []).size() == 4)
		assert(assignments.get("attack_ring", []).size() == 3)
		for skill_name: Variant in quick_slots:
			assert(learned_skills.has(str(skill_name)))
		total_learned_skills += learned_skills.size()
		assert(PlayerState.select_character(profile_id))
		assert(PlayerState.profession == profession)
		assert(PlayerState.equipment.size() == 8)
		assert(PlayerState.learned_skills.size() == _expected_skill_count(profession))
		assert(PlayerState.quick_slots.size() == 4)

	var preserved_profile_id := "test.character.warrior.woma.v2"
	var preserved_payload := PlayerState._read_json(PlayerState._profile_path(preserved_profile_id))
	preserved_payload["gold"] = 1234567
	assert(PlayerState._write_json_atomic(PlayerState._profile_path(preserved_profile_id), preserved_payload))
	var second := PlayerState.prepare_qa_test_roster_v2()
	assert(bool(second.get("ok", false)))
	assert(not bool(second.get("reset_performed", true)))
	assert(int(second.get("created", -1)) == 0)
	assert(int(second.get("indexed", -1)) == 0)
	assert(int(PlayerState._read_json(PlayerState._profile_path(preserved_profile_id)).get("gold", 0)) == 1234567)
	assert(profession_counts == {"战士": 3, "法师": 3, "道士": 3})
	assert(total_equipment_slots == 72)
	assert(total_learned_skills == 99)

	PlayerState.profile_index_path = old_index
	PlayerState.profile_directory = old_directory
	PlayerState.test_roster_reset_marker_path = old_marker
	print("TEST_CHARACTER_ROSTER_INTEGRATION_PASS profiles=9 equipment_slots=72 learned_skills=99 reset_v2=true")
	get_tree().quit()


func _expected_skill_count(profession: String) -> int:
	match profession:
		"战士":
			return 6
		"法师":
			return 14
		"道士":
			return 13
	return 0
