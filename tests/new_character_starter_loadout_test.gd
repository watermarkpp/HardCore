extends Node

const TEST_DIRECTORY := "user://new_character_starter_loadout_profiles"
const TEST_INDEX := "user://new_character_starter_loadout_index.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	var old_directory: String = PlayerState.profile_directory
	var old_index: String = PlayerState.profile_index_path
	var old_test_mode: bool = PlayerState.test_mode
	var old_force_failure: bool = PlayerState._test_force_atomic_write_failure
	PlayerState.profile_directory = TEST_DIRECTORY
	PlayerState.profile_index_path = TEST_INDEX
	PlayerState.test_mode = false
	PlayerState._test_force_atomic_write_failure = false

	var created_ids: Array[String] = []
	for profession: String in ProfessionRules.PROFESSIONS:
		for gender: String in ["男", "女"]:
			var character_name := "初始装备%s%s" % [profession, gender]
			assert(PlayerState.create_character(character_name, profession, gender).is_empty())
			var profile_id := PlayerState.active_profile_id
			assert(not profile_id.is_empty(), "new character did not receive a profile id")
			assert(profile_id not in created_ids, "profile id collision")
			created_ids.append(profile_id)
			assert(PlayerState.level == 1)
			assert(PlayerState.inventory.is_empty(), "starter equipment must be equipped, not duplicated in bag")
			assert(PlayerState.warehouse_inventory.is_empty())
			var weapon: Dictionary = PlayerState.equipment.get("武器", {})
			var armor: Dictionary = PlayerState.equipment.get("衣服", {})
			assert(str(weapon.get("name", "")) == "木剑")
			assert(str(armor.get("name", "")) == ("布衣(男)" if gender == "男" else "布衣(女)"))
			assert(not str(weapon.get("instance_id", "")).is_empty())
			assert(not str(armor.get("instance_id", "")).is_empty())
			assert(weapon.get("instance_id") != armor.get("instance_id"), "starter instance ids must be unique")
			assert(int(weapon.get("durability_raw", 0)) > 0)
			assert(int(armor.get("durability_raw", 0)) > 0)
			assert(PlayerState.equipment.get("圣物", {}).is_empty(), "relic slot must remain reserved")
			assert(PlayerState.equipment.get("徽章", {}).is_empty(), "badge slot must remain reserved")
			var weapon_item := GameData.get_item("木剑")
			var armor_item := GameData.get_item(str(armor.get("name", "")))
			assert(not weapon_item.is_empty() and not armor_item.is_empty(), "starter records must come from primary item data")
			assert(int(weapon_item.get("weight", 0)) <= EquipmentRules.max_hand_weight(profession, 1))
			assert(int(armor_item.get("weight", 0)) <= EquipmentRules.max_wear_weight(profession, 1))
			var persisted: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_DIRECTORY + "/" + profile_id + ".json"))
			assert(persisted is Dictionary)
			assert((persisted as Dictionary).get("equipment", {}).get("武器", {}).get("name", "") == "木剑")
			var saved_weapon_id := str((persisted as Dictionary).get("equipment", {}).get("武器", {}).get("instance_id", ""))
			assert(saved_weapon_id == str(weapon.get("instance_id", "")))
			assert(PlayerState.select_character(profile_id))
			assert(str(PlayerState.equipment.get("武器", {}).get("instance_id", "")) == saved_weapon_id)

	# A duplicate name must not allocate a second profile or mutate the active one.
	var duplicate_id := PlayerState.active_profile_id
	var duplicate_error := PlayerState.create_character("初始装备战士男", "战士", "男")
	assert(duplicate_error == "角色名已存在")
	assert(PlayerState.active_profile_id == duplicate_id)
	assert(PlayerState.list_characters().size() == created_ids.size())

	# Invalid requests fail closed without touching the current character.
	assert(PlayerState.create_character("非法职业", "不存在职业", "男") == "职业无效")
	assert(PlayerState.create_character("非法性别", "战士", "未知") == "性别无效")
	assert(PlayerState.active_profile_id == duplicate_id)

	# Simulate an atomic profile write failure.  The new character must not leave
	# an orphan profile and the previous runtime must be restored byte-for-byte
	# for the fields touched by reset_progress/create_character.
	var before_failure_equipment := PlayerState.equipment.duplicate(true)
	var before_failure_inventory := PlayerState.inventory.duplicate(true)
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = true
	var failure_error := PlayerState.create_character("写入失败角色", "道士", "女")
	assert(failure_error == "角色存档失败，角色未创建")
	assert(PlayerState.active_profile_id == duplicate_id)
	assert(PlayerState.equipment == before_failure_equipment)
	assert(PlayerState.inventory == before_failure_inventory)
	assert(PlayerState.list_characters().size() == created_ids.size())
	PlayerState._test_force_atomic_write_failure = old_force_failure
	PlayerState.test_mode = old_test_mode
	PlayerState.profile_directory = old_directory
	PlayerState.profile_index_path = old_index
	_cleanup()
	print("NEW_CHARACTER_STARTER_LOADOUT_PASS: legal wood sword/sex armor, unique instances, persistence, duplicate and atomic failure guards")
	get_tree().quit(0)


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
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
