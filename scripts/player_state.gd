extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const EquipmentTestLoadoutCatalogScript = preload("res://scripts/equipment_test_loadout_catalog.gd")
const TestCharacterSkillProfilesScript = preload("res://scripts/test_character_skill_profiles.gd")
const SkillLoadoutRulesScript = preload("res://scripts/skill_loadout_rules.gd")
const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const SkillProgressionServiceScript := preload("res://scripts/skills/skill_progression_service.gd")
const SkillRngScript := preload("res://scripts/skills/skill_rng.gd")

signal profile_changed
signal inventory_changed
signal equipment_changed
signal skills_changed
signal skill_progression_changed(snapshot: Dictionary)
signal quick_slots_changed(change: Dictionary)
signal warrior_runtime_state_changed(snapshot: Dictionary)
signal consumable_requested(item_name: String)
signal scroll_requested(item_name: String)
signal quests_changed
signal profession_changed(profession: String)

const SAVE_VERSION := 8
const SAVE_PATH := "user://player_save_v03.json"
const LEGACY_SAVE_PATH := "user://player_save_v02.json"
const PROFILE_INDEX_PATH := "user://character_profiles.json"
const PROFILE_DIRECTORY := "user://characters"
const TEST_ROSTER_RESET_MARKER_PATH := "user://test_roster_v2_reset.json"
const AUTOSAVE_INTERVAL := 30.0
const WARRIOR_RUNTIME_CONTRACT_ID := "gameplay.warrior.skill_runtime.v2"
const TEST_CHARACTER_ROSTER_CONTRACT_ID := "test.character.roster.full_equipment_skills.v2"
const TEST_ROSTER_RESET_CONTRACT_ID := "test.character.roster.reset.v2"
const CURRENT_CONTENT_SCHEMA_VERSION := 2
const CANONICAL_MATERIAL_ITEMS := {
	"grey_powder": "灰色药粉",
	"yellow_powder": "黄色药粉",
	"amulet": "护身符",
}
const SKILL_BUTTON_ASSIGNMENTS_CONTRACT_ID := "gameplay.skill.button_assignments.v3"
const WORLD_POSITION_CONTRACT_ID := (
	"save.world_position.screen_px_with_ground_gu.v1"
)
const SKILL_SLOT_GROUP_CENTER := "center"
const SKILL_SLOT_GROUP_ATTACK := "attack"
const SKILL_SLOT_GROUP_ATTACK_RING := "attack_ring"
const CENTER_SKILL_SLOT_COUNT := 4
const ATTACK_SKILL_SLOT_COUNT := 1
const ATTACK_RING_SKILL_SLOT_COUNT := 6
const EQUIPMENT_SLOTS: Array[String] = ["武器", "衣服", "头盔", "项链", "左手镯", "右手镯", "左戒指", "右戒指"]
const VERIFIED_EXPERIENCE_1_TO_22 := {
	1: 100, 2: 200, 3: 300, 4: 400, 5: 600, 6: 900, 7: 1200, 8: 1700, 9: 2500,
	10: 6000, 11: 8000, 12: 10000, 13: 15000, 14: 30000, 15: 40000, 16: 50000,
	17: 70000, 18: 100000, 19: 120000, 20: 140000, 21: 250000, 22: 300000,
}

var level := 1
var profession := "战士"
var gender := "男"
var later_content_enabled := false
var game_mode_id := "classic_176"
var experience := 0
var gold := 0
var inventory: Array = []
var warehouse_inventory: Array = []
var equipment: Dictionary = {
	"武器": {}, "衣服": {}, "头盔": {}, "项链": {},
	"左手镯": {}, "右手镯": {}, "左戒指": {}, "右戒指": {},
}
var learned_skills: Dictionary = {}
var _skill_progression: RefCounted = SkillProgressionServiceScript.new()
var quick_slots: Array[String] = ["", "", "", ""]
var attack_skill_slots: Array[String] = [""]
var attack_ring_slots: Array[String] = ["", "", "", "", "", ""]
var warrior_runtime_state: Dictionary = {}
var quest_states: Dictionary = {}
var saved_map_id := 4
var saved_position := Vector2.ZERO
var saved_ground_position_gu := Vector2.ZERO
var saved_ground_position_gu_valid := false
var computed_stats: Dictionary = {}
var computed_special_effects: Dictionary = {}
var test_mode := false
var active_profile_id := ""
var character_name := ""
var _autosave_elapsed := 0.0
var profile_index_path := PROFILE_INDEX_PATH
var profile_directory := PROFILE_DIRECTORY
var test_roster_reset_marker_path := TEST_ROSTER_RESET_MARKER_PATH


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		_commit_save()


func _process(delta: float) -> void:
	if test_mode or active_profile_id.is_empty():
		return
	_autosave_elapsed += delta
	if _autosave_elapsed >= AUTOSAVE_INTERVAL:
		_autosave_elapsed = 0.0
		save_game()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROFILE_DIRECTORY))
	_migrate_single_save_to_profile()
	if OS.is_debug_build() and DisplayServer.get_name() != "headless":
		if ProjectSettings.get_setting("hardcore/debug/enable_qa_test_roster", false):
			prepare_qa_test_roster_v2()
	reset_progress(false)
	recalculate_stats()


func reset_progress(emit_updates := true) -> void:
	level = 1
	profession = "战士"
	gender = "男"
	later_content_enabled = false
	game_mode_id = "classic_176"
	experience = 0
	gold = 0
	inventory = []
	warehouse_inventory = []
	equipment = _empty_equipment()
	learned_skills = {}
	_skill_progression.load_snapshot({})
	quick_slots = ["", "", "", ""]
	attack_skill_slots = [""]
	attack_ring_slots = ["", "", "", "", "", ""]
	warrior_runtime_state = _default_warrior_runtime_state()
	quest_states = {}
	saved_map_id = 4
	saved_position = Vector2.ZERO
	saved_ground_position_gu = Vector2.ZERO
	saved_ground_position_gu_valid = false
	recalculate_stats()
	if emit_updates:
		profession_changed.emit(profession)
		inventory_changed.emit()
		equipment_changed.emit()
		skills_changed.emit()
		skill_progression_changed.emit(_skill_progression.snapshot())
		quests_changed.emit()
		profile_changed.emit()


func select_profession(value: String) -> String:
	if not ProfessionRules.is_valid_profession(value):
		return "无效职业：%s" % value
	if profession == value:
		return "当前职业已经是%s" % value
	profession = value
	for skill_name: Variant in learned_skills.keys():
		var profile := ProfessionRules.skill_profile(str(skill_name))
		if not profile.is_empty() and str(profile.get("profession", "")) != profession:
			learned_skills.erase(skill_name)
	_skill_progression.load_snapshot(learned_skills)
	for index in range(quick_slots.size()):
		if not learned_skills.has(quick_slots[index]):
			quick_slots[index] = ""
	for index in range(attack_skill_slots.size()):
		if not is_skill_learned(attack_skill_slots[index]):
			attack_skill_slots[index] = ""
	for index in range(attack_ring_slots.size()):
		if not is_skill_learned(attack_ring_slots[index]):
			attack_ring_slots[index] = ""
	_sync_legacy_quick_slots_from_ring()
	if profession != "战士":
		warrior_runtime_state = _default_warrior_runtime_state()
	var returned_items: Array[String] = []
	for slot: String in equipment.keys():
		var equipped_record: Variant = equipment[slot]
		var equipped_name := str(equipped_record.get("name", "")) if equipped_record is Dictionary else str(equipped_record)
		if equipped_name.is_empty():
			continue
		var item := GameData.get_item(equipped_name)
		var item_profession := str(item.get("profession", "通用"))
		if item_profession not in ["", "通用", profession]:
			if equipped_record is Dictionary:
				inventory.append(equipped_record.duplicate(true))
			else:
				returned_items.append(equipped_name)
			equipment[slot] = {}
	for returned_name: String in returned_items:
		add_item(returned_name)
	recalculate_stats()
	profession_changed.emit(profession)
	inventory_changed.emit()
	equipment_changed.emit()
	skills_changed.emit()
	profile_changed.emit()
	_commit_save()
	return "职业已切换为%s" % profession


func set_later_content_enabled(enabled: bool) -> void:
	later_content_enabled = enabled
	ContentLayers.set_expansion_enabled("later_176_content", enabled)
	profile_changed.emit()
	_commit_save()


func add_item(item_name: String, amount := 1) -> void:
	var catalog_item := GameData.get_item_record(item_name)
	var kind := str(catalog_item.get("kind", "unknown"))
	if kind == "currency":
		add_gold(int(catalog_item.get("currencyAmount", 10)) * amount)
		return
	if kind == "equipment" or not bool(catalog_item.get("stackable", true)):
		for count in range(maxi(1, amount)):
			inventory.append(_make_item_instance(item_name, catalog_item))
		inventory_changed.emit()
		_commit_save()
		return
	for stack: Variant in inventory:
		if stack is Dictionary and stack.get("name", "") == item_name:
			stack["count"] = int(stack.get("count", 0)) + amount
			inventory_changed.emit()
			_commit_save()
			return
	inventory.append({"name": item_name, "count": amount})
	inventory_changed.emit()
	_commit_save()


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	profile_changed.emit()
	_commit_save()


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	profile_changed.emit()
	_commit_save()
	return true


func has_item(item_name: String, amount := 1) -> bool:
	return item_count(item_name) >= amount


func item_count(item_name: String) -> int:
	var total := 0
	for stack: Variant in inventory:
		if stack is Dictionary and stack.get("name", "") == item_name:
			total += int(stack.get("count", 0))
	return total


func remove_item(item_name: String, amount := 1) -> bool:
	if amount <= 0 or not has_item(item_name, amount):
		return false
	var remaining := amount
	var index := inventory.size() - 1
	while index >= 0 and remaining > 0:
		var stack: Dictionary = inventory[index]
		if stack.get("name", "") == item_name:
			var count := int(stack.get("count", 0))
			var consumed := mini(count, remaining)
			count -= consumed
			remaining -= consumed
			if count <= 0:
				inventory.remove_at(index)
			else:
				stack["count"] = count
		index -= 1
	inventory_changed.emit()
	_commit_save()
	return true


func use_inventory_index(index: int) -> String:
	if index < 0 or index >= inventory.size():
		return "请先选择物品"
	var item_name := str(inventory[index].get("name", ""))
	var item := GameData.get_item_record(item_name)
	var kind := str(item.get("kind", ""))
	var effect := str(item.get("useEffect", ""))
	if kind == "skill_book":
		return learn_skill(item_name)
	if item.get("usable", true) == false:
		return "%s当前没有可执行的本地规则" % item_name
	if kind == "scroll":
		if effect in ["blessing_oil", "repair_oil", "war_god_oil"]:
			var weapon_value: Variant = equipment.get("武器", {})
			if not weapon_value is Dictionary or weapon_value.is_empty():
				return "需要先装备武器"
			if effect in ["repair_oil", "war_god_oil"] and int(weapon_value.get("durability", 0)) >= int(weapon_value.get("max_durability", 1)):
				return "武器无需修复"
		if remove_item(item_name):
			scroll_requested.emit(item_name)
			return "使用：%s" % item_name
		return "物品数量不足"
	if kind != "consumable":
		return "%s当前不可使用" % item_name
	if item_name == "祝福油":
		var weapon_value: Variant = equipment.get("武器", {})
		if not weapon_value is Dictionary or weapon_value.is_empty():
			return "需要先装备武器"
	if remove_item(item_name):
		consumable_requested.emit(item_name)
		return "使用：%s" % item_name
	return "物品数量不足"


func apply_weapon_repair_oil(full_repair: bool) -> String:
	var weapon_value: Variant = equipment.get("武器", {})
	if not weapon_value is Dictionary or weapon_value.is_empty():
		return "需要先装备武器"
	var current := int(weapon_value.get("durability", 0))
	var maximum := maxi(1, int(weapon_value.get("max_durability", 1)))
	if current >= maximum:
		return "武器无需修复"
	if full_repair:
		weapon_value["durability"] = maximum
	else:
		# Crystal RepairOil repairs a bounded portion and slightly reduces the
		# maximum durability.  Runtime durability is stored in whole display
		# points, so the 5000/30 service-unit loss rounds to at least one point.
		var repaired := mini(maximum, current + 5)
		var maximum_loss := maxi(1, int(ceil(float(repaired - current) / 30.0)))
		maximum = maxi(repaired, maximum - maximum_loss)
		weapon_value["max_durability"] = maximum
		weapon_value["durability"] = mini(repaired, maximum)
	recalculate_stats()
	equipment_changed.emit()
	profile_changed.emit()
	_commit_save()
	return "武器已完全修复" if full_repair else "武器已部分修复"


func _make_item_instance(item_name: String, catalog_item: Dictionary) -> Dictionary:
	var instance := {"name": item_name, "count": 1}
	if str(catalog_item.get("kind", "")) == "equipment":
		var maximum := maxi(1, int(catalog_item.get("maxDurability", 1)))
		instance["durability"] = maximum
		instance["max_durability"] = maximum
		instance["instance_id"] = "%d_%d" % [Time.get_ticks_usec(), inventory.size()]
		if str(catalog_item.get("category", "")) == "武器":
			instance["weapon_luck"] = 0
			instance["weapon_curse"] = 0
	return instance


func apply_blessing_oil(rng: RandomNumberGenerator) -> String:
	var weapon_value: Variant = equipment.get("武器", {})
	if not weapon_value is Dictionary or weapon_value.is_empty():
		return "需要先装备武器"
	var item := GameData.get_item(str(weapon_value.get("name", "")))
	var attack_min := int(item.get("attackMin", 0) if item.get("attackMin", null) != null else 0)
	var attack_max := int(item.get("attackMax", attack_min) if item.get("attackMax", null) != null else attack_min)
	var luck := int(weapon_value.get("weapon_luck", 0))
	var unlucky_roll := rng.randi_range(0, EquipmentRulesScript.BLESSING_UNLUCKY_RATE - 1)
	var success_roll := 0
	if unlucky_roll != 1:
		var denominator := EquipmentRulesScript.blessing_success_denominator(luck, attack_min, attack_max)
		success_roll = rng.randi_range(0, denominator - 1) if denominator > 1 else 0
	return apply_blessing_oil_with_rolls(unlucky_roll, success_roll)


func apply_blessing_oil_with_rolls(unlucky_roll: int, success_roll: int) -> String:
	var weapon_value: Variant = equipment.get("武器", {})
	if not weapon_value is Dictionary or weapon_value.is_empty():
		return "需要先装备武器"
	var item := GameData.get_item(str(weapon_value.get("name", "")))
	var attack_min := int(item.get("attackMin", 0) if item.get("attackMin", null) != null else 0)
	var attack_max := int(item.get("attackMax", attack_min) if item.get("attackMax", null) != null else attack_min)
	var luck := int(weapon_value.get("weapon_luck", 0))
	var curse := int(weapon_value.get("weapon_curse", 0))
	var outcome := EquipmentRulesScript.blessing_outcome(luck, curse, attack_min, attack_max, unlucky_roll, success_roll)
	weapon_value["weapon_luck"] = int(outcome.get("luck", luck))
	weapon_value["weapon_curse"] = int(outcome.get("curse", curse))
	recalculate_stats()
	equipment_changed.emit()
	profile_changed.emit()
	_commit_save()
	match str(outcome.get("result", "ineffective")):
		"cursed": return "祝福油失败：武器受到诅咒"
		"improved": return "祝福油生效：武器幸运改善"
		_: return "祝福油无效"


func lose_gold_percent(rate: float) -> int:
	var lost := mini(gold, int(round(gold * clampf(rate, 0.0, 1.0))))
	gold -= lost
	profile_changed.emit()
	_commit_save()
	return lost


func add_experience(amount: int) -> void:
	experience += maxi(0, amount)
	while experience >= experience_to_next_level():
		experience -= experience_to_next_level()
		level += 1
		recalculate_stats()
	profile_changed.emit()
	_commit_save()


func experience_to_next_level() -> int:
	if GameData != null and not GameData.service_reference.is_empty():
		return GameData.service_exp_to_next_level(level)
	if VERIFIED_EXPERIENCE_1_TO_22.has(level):
		return int(VERIFIED_EXPERIENCE_1_TO_22[level])
	# 23级以上尚未完成多源核验，暂沿用保守占位曲线并在验收报告中标记。
	return 300000 + maxi(0, level - 22) * 100000


func equip_inventory_index(index: int, preferred_slot := "") -> String:
	if index < 0 or index >= inventory.size():
		return "请先选择物品"
	var inventory_record: Dictionary = inventory[index]
	var item_name := str(inventory_record.get("name", ""))
	var item := GameData.get_item(item_name)
	if item.is_empty():
		return "%s不是可穿戴装备" % item_name
	var category := str(item.get("category", ""))
	var slot := _choose_equipment_slot(category, preferred_slot)
	if slot.is_empty():
		return "当前版本尚未开放该装备槽"
	var item_profession := EquipmentRulesScript.effective_profession(item)
	if item_profession not in ["", "通用", profession]:
		return "%s只能由%s装备" % [item_name, item_profession]
	var required_gender := EquipmentRulesScript.required_gender(item)
	if not required_gender.is_empty() and required_gender != gender:
		return "该装备仅限%s性角色" % required_gender
	var requirement_error := EquipmentRulesScript.requirement_error(item, level, computed_stats)
	if not requirement_error.is_empty():
		return requirement_error
	var item_weight := maxi(0, int(item.get("weight", 0)))
	if category == "武器":
		var max_hand := EquipmentRulesScript.max_hand_weight(profession, level)
		if item_weight > max_hand:
			return "手持重量不足：需要%d，上限%d" % [item_weight, max_hand]
	else:
		var prospective_wear := current_wear_weight(slot) + item_weight
		var max_wear := EquipmentRulesScript.max_wear_weight(profession, level)
		if prospective_wear > max_wear:
			return "穿戴重量不足：需要%d，上限%d" % [prospective_wear, max_wear]
	var previous: Variant = equipment.get(slot, {})
	if previous is Dictionary and not previous.is_empty():
		inventory[index] = previous.duplicate(true)
	elif not previous is Dictionary and not str(previous).is_empty():
		inventory[index] = _make_item_instance(str(previous), GameData.get_item_record(str(previous)))
	else:
		inventory.remove_at(index)
	equipment[slot] = inventory_record.duplicate(true)
	recalculate_stats()
	inventory_changed.emit()
	equipment_changed.emit()
	profile_changed.emit()
	_commit_save()
	return "已装备：%s" % item_name


func unequip_slot(slot: String) -> String:
	if slot not in EQUIPMENT_SLOTS:
		return "无效装备槽"
	var equipped_value: Variant = equipment.get(slot, {})
	if not equipped_value is Dictionary or equipped_value.is_empty():
		return "%s为空" % slot
	inventory.append(equipped_value.duplicate(true))
	equipment[slot] = {}
	recalculate_stats()
	inventory_changed.emit()
	equipment_changed.emit()
	profile_changed.emit()
	_commit_save()
	return "已卸下：%s" % str(equipped_value.get("name", ""))


func learn_skill(skill_name: String) -> String:
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name)
	if stable_skill_id.is_empty():
		return "技能数据不存在"
	var skill := GameData.get_skill(skill_name, 0)
	if skill.is_empty():
		return "技能数据不存在"
	var skill_profession := str(skill.get("profession", ""))
	if not skill_profession.is_empty() and skill_profession != profession:
		return "%s只能由%s学习" % [skill_name, skill_profession]
	if not has_item(skill_name):
		return "背包中缺少《%s》技能书" % skill_name
	var learn_result: Dictionary = _skill_progression.learn(stable_skill_id, level)
	if not bool(learn_result.get("accepted", false)):
		match str(learn_result.get("outcome", "")):
			"max":
				return "%s已达到最高等级" % skill_name
			"level_requirement":
				return "需要人物等级%d" % int(learn_result.get("required_level", 1))
			_:
				return "技能学习失败：%s" % str(learn_result.get("reason", "unknown"))
	remove_item(skill_name)
	var base_rank := int(learn_result.get("base_rank", 0))
	learned_skills[skill_name] = base_rank
	var outcome := str(learn_result.get("outcome", ""))
	if outcome == "learned" and SkillLoadoutRulesScript.assignment_candidate(stable_skill_id).get(
		"bindable_to_skill_slot",
		false
	):
		for index in range(attack_ring_slots.size()):
			if attack_ring_slots[index].is_empty():
				attack_ring_slots[index] = skill_name
				break
		_sync_legacy_quick_slots_from_ring()
	recalculate_stats()
	skills_changed.emit()
	skill_progression_changed.emit(_skill_progression.snapshot())
	profile_changed.emit()
	_commit_save()
	match outcome:
		"upgraded":
			return "技能提升：%s（当前%d级）" % [skill_name, base_rank]
		_:
			return "已学会：%s" % skill_name


func is_skill_learned(skill_name: String) -> bool:
	return (
		learned_skills.has(skill_name)
		or _skill_progression.is_learned(SkillDataLoaderScript.stable_skill_id(skill_name))
	)


func accept_quest(quest_id: String) -> String:
	var quest := GameData.get_bich_quest(quest_id)
	if quest.is_empty():
		return "未知任务"
	if quest_states.has(quest_id):
		var existing_status := str(quest_states[quest_id].get("status", ""))
		return "任务奖励已经领取" if existing_status == "claimed" else "任务已经接受"
	var prerequisite := str(quest.get("prerequisite", ""))
	if not prerequisite.is_empty() and str(quest_states.get(prerequisite, {}).get("status", "")) != "claimed":
		return "前置任务尚未完成"
	var progress := {}
	for objective_name: String in quest.get("objectives", {}).get("kills", {}).keys():
		progress[objective_name] = 0
	quest_states[quest_id] = {"status": "active", "progress": progress}
	quests_changed.emit()
	_commit_save()
	return "已接受任务：%s" % quest.get("name", quest_id)


func record_kill(monster_name: String) -> void:
	var changed := false
	for quest_id: String in quest_states.keys():
		var state: Dictionary = quest_states[quest_id]
		if str(state.get("status", "")) != "active":
			continue
		var quest := GameData.get_bich_quest(quest_id)
		if quest.is_empty():
			continue
		var progress: Dictionary = state.get("progress", {})
		var requirements: Dictionary = quest.get("objectives", {}).get("kills", {})
		for objective_name: String in requirements.keys():
			if not _quest_monster_matches(monster_name, objective_name):
				continue
			var required := int(requirements[objective_name])
			progress[objective_name] = mini(required, int(progress.get(objective_name, 0)) + 1)
			changed = true
		state["progress"] = progress
		if _quest_objectives_complete(quest, state):
			state["status"] = "ready"
	if changed:
		quests_changed.emit()
		_commit_save()


func claim_quest(quest_id: String) -> String:
	if not quest_states.has(quest_id):
		return "尚未接受任务"
	var state: Dictionary = quest_states[quest_id]
	if state.get("status", "") == "claimed":
		return "奖励已经领取"
	var quest := GameData.get_bich_quest(quest_id)
	if quest.is_empty() or not _quest_objectives_complete(quest, state):
		return "任务尚未完成"
	state["status"] = "claimed"
	state["claimed_at_unix"] = int(Time.get_unix_time_from_system())
	var rewards: Dictionary = quest.get("rewards", {})
	gold = maxi(0, gold + int(rewards.get("gold", 0)))
	for reward: Variant in rewards.get("items", []):
		if reward is Dictionary:
			_grant_quest_item_without_commit(str(reward.get("name", "")), maxi(1, int(reward.get("count", 1))))
	inventory_changed.emit()
	profile_changed.emit()
	quests_changed.emit()
	_commit_save()
	return "已领取：%s" % quest_reward_label(quest_id)


func quest_progress(quest_id: String) -> int:
	var progress: Variant = quest_states.get(quest_id, {}).get("progress", {})
	if progress is Dictionary:
		var total := 0
		for value: Variant in progress.values():
			total += int(value)
		return total
	return int(progress)


func current_bich_quest_id() -> String:
	for value: Variant in GameData.get_bich_quests():
		if not value is Dictionary:
			continue
		var quest_id := str(value.get("id", ""))
		var status := str(quest_states.get(quest_id, {}).get("status", ""))
		if status in ["active", "ready"]:
			return quest_id
		if status == "claimed":
			continue
		var prerequisite := str(value.get("prerequisite", ""))
		if prerequisite.is_empty() or str(quest_states.get(prerequisite, {}).get("status", "")) == "claimed":
			return quest_id
	return ""


func quest_objective_lines(quest_id: String) -> Array[String]:
	var result: Array[String] = []
	var quest := GameData.get_bich_quest(quest_id)
	var state: Dictionary = quest_states.get(quest_id, {})
	var progress: Dictionary = state.get("progress", {}) if state.get("progress", {}) is Dictionary else {}
	for objective_name: String in quest.get("objectives", {}).get("kills", {}).keys():
		result.append("消灭%s %d/%d" % [objective_name.trim_suffix("*"), int(progress.get(objective_name, 0)), int(quest.get("objectives", {}).get("kills", {})[objective_name])])
	return result


func quest_reward_label(quest_id: String) -> String:
	var rewards: Dictionary = GameData.get_bich_quest(quest_id).get("rewards", {})
	var parts: Array[String] = []
	if int(rewards.get("gold", 0)) > 0:
		parts.append("%d金币" % int(rewards.get("gold", 0)))
	for reward: Variant in rewards.get("items", []):
		if reward is Dictionary:
			parts.append("%s×%d" % [reward.get("name", ""), int(reward.get("count", 1))])
	return "、".join(parts)


func _quest_monster_matches(monster_name: String, objective_name: String) -> bool:
	return monster_name.begins_with(objective_name.trim_suffix("*")) if objective_name.ends_with("*") else monster_name == objective_name


func _quest_objectives_complete(quest: Dictionary, state: Dictionary) -> bool:
	var progress: Dictionary = state.get("progress", {}) if state.get("progress", {}) is Dictionary else {}
	for objective_name: String in quest.get("objectives", {}).get("kills", {}).keys():
		if int(progress.get(objective_name, 0)) < int(quest.get("objectives", {}).get("kills", {})[objective_name]):
			return false
	return not quest.get("objectives", {}).get("kills", {}).is_empty()


func _grant_quest_item_without_commit(item_name: String, amount: int) -> void:
	if item_name.is_empty() or amount <= 0:
		return
	var catalog_item := GameData.get_item_record(item_name)
	if str(catalog_item.get("kind", "")) == "equipment" or not bool(catalog_item.get("stackable", true)):
		for count in range(amount):
			inventory.append(_make_item_instance(item_name, catalog_item))
		return
	for stack: Variant in inventory:
		if stack is Dictionary and stack.get("name", "") == item_name:
			stack["count"] = int(stack.get("count", 0)) + amount
			return
	inventory.append({"name": item_name, "count": amount})


func _migrate_quest_states() -> void:
	if quest_states.has("beginner_gear") and not quest_states.has("bich_beginner_gear"):
		var legacy: Dictionary = quest_states["beginner_gear"]
		var legacy_progress := mini(3, int(legacy.get("progress", 0)))
		var legacy_status := str(legacy.get("status", "active"))
		quest_states["bich_beginner_gear"] = {
			"status": "claimed" if legacy_status == "claimed" else ("ready" if legacy_progress >= 3 else "active"),
			"progress": {"稻草人": legacy_progress},
		}
		quest_states.erase("beginner_gear")
	for quest_id: String in quest_states.keys():
		var quest := GameData.get_bich_quest(quest_id)
		if quest.is_empty():
			continue
		var state: Dictionary = quest_states[quest_id]
		if not state.get("progress", {}) is Dictionary:
			var first_objective := str(quest.get("objectives", {}).get("kills", {}).keys()[0]) if not quest.get("objectives", {}).get("kills", {}).is_empty() else ""
			state["progress"] = {first_objective: int(state.get("progress", 0))} if not first_objective.is_empty() else {}
		if str(state.get("status", "")) == "active" and _quest_objectives_complete(quest, state):
			state["status"] = "ready"


func recalculate_stats() -> void:
	var base := ProfessionRules.stats_for_level(profession, level)
	computed_special_effects = {}
	var set_powers := {"magic_blood": 0, "rainbow_demon": 0}
	var set_pieces := {"magic_blood": {}, "rainbow_demon": {}}
	var result := {
		"max_hp": int(base.get("max_hp", 120)),
		"max_mp": int(base.get("max_mp", 40)),
		"attack_min": int(base.get("attack_min", 2)),
		"attack_max": int(base.get("attack_max", 5)),
		"magic_min": 0,
		"magic_max": 0,
		"tao_min": 0,
		"tao_max": 0,
		"defense_min": 0,
		"defense_max": 0,
		"magic_defense_min": 0,
		"magic_defense_max": 0,
		"accuracy": WarriorCombatMath.BASE_HIT,
		"agility": WarriorCombatMath.BASE_AGILITY,
		"luck": 0,
		"max_wear_weight": EquipmentRulesScript.max_wear_weight(profession, level),
		"max_hand_weight": EquipmentRulesScript.max_hand_weight(profession, level),
		"wear_weight": current_wear_weight(),
		"critical_chance": 0.0,
		"critical_damage_multiplier": 1.5,
		"anti_magic_points": CombatResolutionRules.BASE_CHARACTER_ANTI_MAGIC_POINTS,
		"magic_evasion_percent": CombatResolutionRules.anti_magic_display_percent(CombatResolutionRules.BASE_CHARACTER_ANTI_MAGIC_POINTS),
		"attack_speed_tier": 0,
		"attack_speed_percent": 0.0,
		"cast_speed_percent": 0.0,
		"skill_level_bonuses": {},
		"skill_level_affix": {},
	}
	var skill_level_affix_records: Array = []
	for slot: String in equipment.keys():
		var equipped_value: Variant = equipment[slot]
		var item_name := str(equipped_value.get("name", "")) if equipped_value is Dictionary else str(equipped_value)
		if item_name.is_empty():
			continue
		if equipped_value is Dictionary and int(equipped_value.get("durability", 1)) <= 0:
			continue
		var item := GameData.get_item(item_name)
		if item.is_empty():
			continue
		## Affix input is an immutable snapshot of the catalog record with the
		## equipped instance's own modifiers merged in. When the instance
		## carries a `modifiers` container it is authoritative (full override of
		## the catalog set), so one item can never contribute the same affixes
		## twice. Without instance modifiers the catalog set is used unchanged.
		var affix_input := item.duplicate(true)
		var instance_modifiers: Variant = (
			equipped_value.get("modifiers")
			if equipped_value is Dictionary
			else null
		)
		if instance_modifiers != null:
			if instance_modifiers is Dictionary or instance_modifiers is Array:
				affix_input["modifiers"] = instance_modifiers.duplicate(true)
			else:
				affix_input["modifiers"] = instance_modifiers
		skill_level_affix_records.append(affix_input)
		_add_nullable_stat(result, "attack_min", item.get("attackMin", null))
		_add_nullable_stat(result, "attack_max", item.get("attackMax", null))
		_add_nullable_stat(result, "magic_min", item.get("magicMin", null))
		_add_nullable_stat(result, "magic_max", item.get("magicMax", null))
		_add_nullable_stat(result, "tao_min", item.get("taoMin", null))
		_add_nullable_stat(result, "tao_max", item.get("taoMax", null))
		_add_nullable_stat(result, "defense_min", item.get("defenseMin", null))
		_add_nullable_stat(result, "defense_max", item.get("defenseMax", null))
		_add_nullable_stat(result, "magic_defense_min", item.get("mdefMin", null))
		_add_nullable_stat(result, "magic_defense_max", item.get("mdefMax", null))
		_add_nullable_stat(result, "accuracy", item.get("accuracy", null))
		_add_nullable_stat(result, "agility", item.get("agility", null))
		result["luck"] = int(result.get("luck", 0)) + EquipmentRulesScript.equipment_luck_contribution(
			item,
			equipped_value if equipped_value is Dictionary else {},
			slot == "武器",
		)
		_add_nullable_stat(result, "max_hp", item.get("hpBonus", null))
		_add_nullable_stat(result, "max_mp", item.get("mpBonus", null))
		_add_nullable_stat(result, "life_steal_percent", item.get("lifeStealPercent", null))
		if item.has("magicEvasionPoints"):
			_add_nullable_stat(result, "anti_magic_points", item.get("magicEvasionPoints", null))
		elif item.has("magicEvasionPercent"):
			_add_nullable_stat(
				result,
				"anti_magic_points",
				CombatResolutionRules.anti_magic_points_from_display_percent(int(item.magicEvasionPercent))
			)
		_add_nullable_stat(result, "attack_speed_tier", item.get("attackSpeedTier", null))
		var modifiers: Variant = affix_input.get("modifiers", null)
		if modifiers is Array:
			result = ModifierEffectRuntime.apply_modifiers(result, modifiers, {
				"profession": profession, "level": level, "slot": slot,
			})
		if modifiers is Dictionary:
			result["critical_chance"] = float(result.get("critical_chance", 0.0)) + float(modifiers.get("criticalChance", 0.0))
			result["critical_damage_multiplier"] = float(result.get("critical_damage_multiplier", 1.5)) + float(modifiers.get("criticalDamageBonus", 0.0))
			result["anti_magic_points"] = int(result.get("anti_magic_points", 0)) + int(modifiers.get("antiMagicPoints", 0))
			result["anti_magic_points"] = int(result.get("anti_magic_points", 0)) + CombatResolutionRules.anti_magic_points_from_display_percent(int(modifiers.get("magicEvasionPercent", 0)))
			result["attack_speed_tier"] = int(result.get("attack_speed_tier", 0)) + int(modifiers.get("attackSpeedTier", 0))
			result["attack_speed_percent"] = float(result.get("attack_speed_percent", 0.0)) + float(modifiers.get("attackSpeedPercent", 0.0))
			result["cast_speed_percent"] = float(result.get("cast_speed_percent", 0.0)) + float(modifiers.get("castSpeedPercent", 0.0))
		var special := EquipmentRulesScript.special_effect_for(item)
		if not special.is_empty() and bool(special.get("runtime", false)):
			var effect_id := str(special.get("id", ""))
			computed_special_effects[effect_id] = {"slot": slot, "item": item_name, "label": special.get("label", effect_id)}
		var set_piece := EquipmentRulesScript.set_piece_for(item)
		if not set_piece.is_empty():
			var set_id := str(set_piece.get("set", ""))
			set_powers[set_id] = int(set_powers.get(set_id, 0)) + int(set_piece.get("power", 0))
			set_pieces[set_id][str(set_piece.get("piece", ""))] = true
	result["skill_level_affix"] = EquipmentRulesScript.aggregate_skill_level_affix_records(
		skill_level_affix_records
	)
	if computed_special_effects.has("double_weight"):
		result["max_wear_weight"] = int(result.get("max_wear_weight", 0)) * 2
		result["max_hand_weight"] = int(result.get("max_hand_weight", 0)) * 2
	var magic_blood_power := int(set_powers.get("magic_blood", 0))
	if set_pieces["magic_blood"].size() == 3:
		magic_blood_power += 50
	if magic_blood_power > 0:
		magic_blood_power = mini(magic_blood_power, maxi(0, int(result.get("max_mp", 0)) - 1))
		result["max_mp"] = int(result.get("max_mp", 0)) - magic_blood_power
		result["max_hp"] = int(result.get("max_hp", 0)) + magic_blood_power
		computed_special_effects["magic_blood"] = {"power": magic_blood_power, "pieces": set_pieces["magic_blood"].size()}
	var rainbow_power := int(set_powers.get("rainbow_demon", 0))
	if rainbow_power > 0:
		result["life_steal_percent"] = int(result.get("life_steal_percent", 0)) + rainbow_power
		computed_special_effects["rainbow_demon"] = {"power": rainbow_power, "pieces": set_pieces["rainbow_demon"].size()}
	if set_pieces["rainbow_demon"].size() == 3:
		result["accuracy"] = int(result.get("accuracy", 0)) + 2
	result["anti_magic_points"] = clampi(int(result.get("anti_magic_points", CombatResolutionRules.BASE_CHARACTER_ANTI_MAGIC_POINTS)), 0, CombatResolutionRules.ANTI_MAGIC_ROLL_SIDES)
	result["magic_evasion_percent"] = CombatResolutionRules.anti_magic_display_percent(int(result.anti_magic_points))
	result["attack_speed_tier"] = int(result.get("attack_speed_tier", 0))
	computed_stats = result
	profile_changed.emit()


func has_special_effect(effect_id: String) -> bool:
	return computed_special_effects.has(effect_id)


func effective_skill_level(skill_name: String) -> int:
	_ensure_skill_progression_matches_legacy()
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name)
	if not _skill_progression.is_learned(stable_skill_id):
		## Equipment can never enable an unlearned skill.
		return 0
	return _skill_progression.effective_rank(
		stable_skill_id,
		_equipment_skill_level_bonus(stable_skill_id)
	)


func _equipment_skill_level_bonus(stable_skill_id: String) -> int:
	var affix: Dictionary = computed_stats.get("skill_level_affix", {})
	var contributions: Dictionary = affix.get("contributions", {})
	var bonus := 0
	bonus += maxi(0, int(contributions.get("all", 0)))
	var profession_scope := "profession:%s" % ProfessionRules.profession_id(profession)
	bonus += maxi(0, int(contributions.get(profession_scope, 0)))
	var skill_scope := "skill:%s" % stable_skill_id
	bonus += maxi(0, int(contributions.get(skill_scope, 0)))
	for raw_name: Variant in affix.get("legacy", {}):
		if SkillDataLoaderScript.stable_skill_id(str(raw_name)) == stable_skill_id:
			bonus += maxi(0, int(affix["legacy"][raw_name]))
	return bonus


func skill_progression_snapshot() -> Dictionary:
	_ensure_skill_progression_matches_legacy()
	return _skill_progression.snapshot()


func apply_skill_proficiency_event(skill_name_or_id: String, event_id: String, seed_value: int) -> Dictionary:
	## HardCore v2: proficiency is disabled. This compatibility entry point is a
	## pure no-op: it never mutates progression, emits growth signals or writes
	## the save.
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name_or_id)
	return _skill_progression.apply_proficiency_event(
		stable_skill_id,
		event_id,
		level,
		SkillRngScript.new(seed_value)
	)


func canonical_skill_resource_context(stable_skill_id: String, current_mana: int) -> Dictionary:
	var materials := {}
	for material_id: String in CANONICAL_MATERIAL_ITEMS:
		materials[material_id] = item_count(str(CANONICAL_MATERIAL_ITEMS[material_id]))
	var definition := SkillDataLoaderScript.skill(stable_skill_id)
	var selected_material := str(definition.get("resource", {}).get("item", ""))
	if stable_skill_id == "taoist.poison":
		selected_material = (
			"grey_powder"
			if int(materials.get("grey_powder", 0)) > 0
			else "yellow_powder"
		)
	var result := {
		"mana": maxi(0, int(current_mana)),
		"materials": materials,
		"selected_material": selected_material,
	}
	## Dual defence: when both taoist.defense and taoist.magic_defense are
	## learned (base rank 0 counts as learned in HardCore v2), any
	## preflight/release quote must price the combination in one transaction
	## with each skill's currently-effective rank (0 or equipment-extended).
	## Equipment can never enable an unlearned partner.
	if stable_skill_id in ["taoist.defense", "taoist.magic_defense"]:
		var partner_skill_id := (
			"taoist.magic_defense"
			if stable_skill_id == "taoist.defense"
			else "taoist.defense"
		)
		if is_skill_learned(partner_skill_id):
			result["dual_defense_context"] = {
				"partner_skill_id": partner_skill_id,
				"partner_rank": effective_skill_level(partner_skill_id),
			}
	return result


func canonical_material_item_name(material_id: String) -> String:
	return str(CANONICAL_MATERIAL_ITEMS.get(material_id, ""))


func _ensure_skill_progression_matches_legacy() -> void:
	var snapshot: Dictionary = _skill_progression.snapshot()
	var canonical_skills: Dictionary = snapshot.get("skills", {})
	var legacy_missing := false
	for raw_name: Variant in learned_skills:
		var stable_skill_id := SkillDataLoaderScript.stable_skill_id(str(raw_name))
		if (
			not stable_skill_id.is_empty()
			and (
				not canonical_skills.has(stable_skill_id)
				or int(canonical_skills.get(stable_skill_id, {}).get("rank", -1)) != clampi(int(learned_skills[raw_name]), 0, 3)
			)
		):
			legacy_missing = true
			break
	if legacy_missing or (canonical_skills.is_empty() and not learned_skills.is_empty()):
		_skill_progression.load_snapshot(learned_skills)


func _sync_legacy_learned_skills_from_progression() -> void:
	var canonical_skills: Dictionary = _skill_progression.snapshot().get("skills", {})
	var migrated: Dictionary = {}
	for stable_skill_id: Variant in canonical_skills:
		var display_name := SkillDataLoaderScript.display_name(str(stable_skill_id))
		if display_name.is_empty():
			continue
		var entry: Dictionary = canonical_skills[stable_skill_id]
		migrated[display_name] = clampi(int(entry.get("rank", 0)), 0, 3)
	learned_skills = migrated


func available_special_actions() -> Array[String]:
	var actions: Array[String] = []
	for effect_id: String in ["teleport", "flame_skill", "recovery_skill"]:
		if has_special_effect(effect_id):
			actions.append(effect_id)
	return actions


func damage_special_effect_item(effect_id: String, amount := 1) -> void:
	var source: Dictionary = computed_special_effects.get(effect_id, {})
	var slot := str(source.get("slot", ""))
	if not slot.is_empty():
		damage_equipment_durability(slot, amount)


func _add_nullable_stat(target: Dictionary, key: String, value: Variant) -> void:
	if value != null:
		target[key] = int(target.get(key, 0)) + int(value)


func current_wear_weight(excluded_slot := "") -> int:
	var total := 0
	for slot: String in equipment.keys():
		if slot == excluded_slot or slot == "武器":
			continue
		var equipped_value: Variant = equipment.get(slot, {})
		var item_name := str(equipped_value.get("name", "")) if equipped_value is Dictionary else str(equipped_value)
		if item_name.is_empty():
			continue
		total += maxi(0, int(GameData.get_item(item_name).get("weight", 0)))
	return total


func _slots_for_category(category: String) -> Array[String]:
	match category:
		"武器": return ["武器"]
		"盔甲": return ["衣服"]
		"头盔": return ["头盔"]
		"项链": return ["项链"]
		"手镯": return ["左手镯", "右手镯"]
		"戒指": return ["左戒指", "右戒指"]
		_: return []


func _choose_equipment_slot(category: String, preferred_slot := "") -> String:
	var slots := _slots_for_category(category)
	if not preferred_slot.is_empty() and preferred_slot in slots:
		return preferred_slot
	for slot: String in slots:
		var value: Variant = equipment.get(slot, {})
		if value is Dictionary and value.is_empty():
			return slot
	return slots[0] if not slots.is_empty() else ""


func _empty_equipment() -> Dictionary:
	var result := {}
	for slot: String in EQUIPMENT_SLOTS:
		result[slot] = {}
	return result


func _equipment_instance_from_saved(saved_value: Variant) -> Dictionary:
	if saved_value is Dictionary:
		return saved_value.duplicate(true)
	if not str(saved_value).is_empty():
		return _make_item_instance(str(saved_value), GameData.get_item_record(str(saved_value)))
	return {}


func migrate_equipment_slots(saved_equipment: Dictionary) -> Dictionary:
	var migrated := _empty_equipment()
	for slot: String in EQUIPMENT_SLOTS:
		if saved_equipment.has(slot):
			migrated[slot] = _equipment_instance_from_saved(saved_equipment[slot])
	if migrated["左手镯"].is_empty() and saved_equipment.has("手镯"):
		migrated["左手镯"] = _equipment_instance_from_saved(saved_equipment["手镯"])
	if migrated["左戒指"].is_empty() and saved_equipment.has("戒指"):
		migrated["左戒指"] = _equipment_instance_from_saved(saved_equipment["戒指"])
	return migrated


func damage_equipment_durability(slot: String, amount := 1) -> void:
	var equipped: Variant = equipment.get(slot, {})
	if not equipped is Dictionary or equipped.is_empty():
		return
	var old_value := int(equipped.get("durability", 0))
	var new_value := maxi(0, old_value - maxi(0, amount))
	if new_value == old_value:
		return
	equipped["durability"] = new_value
	if new_value == 0:
		recalculate_stats()
	equipment_changed.emit()
	profile_changed.emit()
	_commit_save()


func repair_cost() -> int:
	var total := 0
	for equipped: Variant in equipment.values():
		if not equipped is Dictionary or equipped.is_empty():
			continue
		var item := GameData.get_item(str(equipped.get("name", "")))
		total += EquipmentRulesScript.repair_cost(item, int(equipped.get("durability", 0)), int(equipped.get("max_durability", 1)))
	return total


func repair_all_equipment() -> String:
	var cost := repair_cost()
	if cost <= 0:
		return "装备无需维修"
	if not spend_gold(cost):
		return "维修需要%d金币" % cost
	for equipped: Variant in equipment.values():
		if equipped is Dictionary and not equipped.is_empty():
			equipped["durability"] = int(equipped.get("max_durability", 1))
	recalculate_stats()
	equipment_changed.emit()
	profile_changed.emit()
	_commit_save()
	return "全部装备维修完成，花费%d金币" % cost


func _profile_path(profile_id: String) -> String:
	return "%s/%s.json" % [profile_directory, profile_id]


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}


func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var temporary := path + ".tmp"
	var backup := path + ".bak"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temp := ProjectSettings.globalize_path(temporary)
	var absolute_backup := ProjectSettings.globalize_path(backup)
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(absolute_backup)
		DirAccess.rename_absolute(absolute_path, absolute_backup)
	var result := DirAccess.rename_absolute(absolute_temp, absolute_path)
	if result != OK and FileAccess.file_exists(backup):
		DirAccess.rename_absolute(absolute_backup, absolute_path)
	return result == OK


func save_game() -> void:
	if active_profile_id.is_empty():
		return
	_ensure_skill_progression_matches_legacy()
	if not _write_json_atomic(_profile_path(active_profile_id), {
		"save_version": SAVE_VERSION,
		"profile_id": active_profile_id,
		"character_name": character_name,
		"updated_at": int(Time.get_unix_time_from_system()),
		"level": level,
		"profession": profession,
		"gender": gender,
		"later_content_enabled": later_content_enabled,
		"game_mode_id": game_mode_id,
		"experience": experience,
		"gold": gold,
		"inventory": inventory,
		"warehouse_inventory": warehouse_inventory,
		"equipment": equipment,
		"learned_skills": learned_skills,
		"skill_progression": _skill_progression.snapshot(),
		"quick_slots": quick_slots,
		"skill_button_assignments": skill_button_assignments_snapshot(),
		"warrior_runtime_state": warrior_runtime_state,
		"quest_states": quest_states,
		"content_packages": ContentLayers.enabled_package_ids(),
		"content_schema_version": CURRENT_CONTENT_SCHEMA_VERSION,
		"map_id": saved_map_id,
		"position": [saved_position.x, saved_position.y],
		"position_space_contract_id": WORLD_POSITION_CONTRACT_ID,
		"position_screen_px": [saved_position.x, saved_position.y],
		"position_ground_gu": (
			[saved_ground_position_gu.x, saved_ground_position_gu.y]
			if saved_ground_position_gu_valid
			else []
		),
	}):
		push_warning("无法安全写入角色存档：%s" % active_profile_id)
	_update_profile_index()


func load_save() -> void:
	var load_path := _profile_path(active_profile_id) if not active_profile_id.is_empty() else SAVE_PATH
	if not FileAccess.file_exists(load_path):
		reset_progress(false)
		return
	var file := FileAccess.open(load_path, FileAccess.READ)
	var serialized := file.get_as_text() if file != null else ""
	if file != null:
		# Windows keeps the source file locked while FileAccess is alive. Close it
		# before a version migration atomically renames the same profile to .bak.
		file.close()
	var parsed: Variant = JSON.parse_string(serialized)
	if not parsed is Dictionary:
		reset_progress(false)
		return
	level = maxi(1, int(parsed.get("level", 1)))
	profession = str(parsed.get("profession", "战士"))
	if not ProfessionRules.is_valid_profession(profession):
		profession = "战士"
	gender = str(parsed.get("gender", "男"))
	if gender not in ["男", "女"]:
		gender = "男"
	later_content_enabled = bool(parsed.get("later_content_enabled", false))
	game_mode_id = str(parsed.get("game_mode_id", "classic_176"))
	if not GameModes.apply_mode(game_mode_id):
		game_mode_id = "classic_176"
		GameModes.apply_mode(game_mode_id)
	ContentLayers.set_expansion_enabled("later_176_content", later_content_enabled)
	experience = maxi(0, int(parsed.get("experience", 0)))
	gold = maxi(0, int(parsed.get("gold", 0)))
	inventory = parsed.get("inventory", [])
	warehouse_inventory = parsed.get("warehouse_inventory", [])
	var saved_equipment: Dictionary = parsed.get("equipment", {})
	equipment = migrate_equipment_slots(saved_equipment)
	learned_skills = parsed.get("learned_skills", {})
	var progression_load: Dictionary = _skill_progression.load_snapshot(
		parsed.get("skill_progression", learned_skills)
	)
	if bool(progression_load.get("migrated_legacy", false)) or not parsed.has("skill_progression"):
		_sync_legacy_learned_skills_from_progression()
	var saved_slots: Array = parsed.get("quick_slots", ["", "", "", ""])
	_restore_skill_button_assignments(parsed.get("skill_button_assignments", {}), saved_slots)
	warrior_runtime_state = _normalized_warrior_runtime_state(parsed.get("warrior_runtime_state", {}))
	quest_states = parsed.get("quest_states", {})
	saved_map_id = int(parsed.get("map_id", 4))
	var position_data: Variant = parsed.get(
		"position_screen_px",
		parsed.get("position", [0.0, 0.0])
	)
	if position_data is Array and position_data.size() >= 2:
		saved_position = Vector2(float(position_data[0]), float(position_data[1]))
	else:
		saved_position = Vector2.ZERO
	var ground_position_data: Variant = parsed.get("position_ground_gu", [])
	saved_ground_position_gu_valid = (
		str(parsed.get("position_space_contract_id", ""))
		== WORLD_POSITION_CONTRACT_ID
		and ground_position_data is Array
		and ground_position_data.size() >= 2
	)
	if saved_ground_position_gu_valid:
		saved_ground_position_gu = Vector2(
			float(ground_position_data[0]),
			float(ground_position_data[1])
		)
	else:
		# Version 6 and older store only screen PX. Their value remains valid for
		# rendering and map restoration; GameRoot supplies the matching absolute
		# ground GU coordinate after the map runtime is loaded.
		saved_ground_position_gu = Vector2.ZERO
	character_name = str(parsed.get("character_name", character_name))
	_migrate_quest_states()
	if (
		load_path == LEGACY_SAVE_PATH
		or not parsed.has("skill_progression")
		or not parsed.has("skill_button_assignments")
		or int(parsed.get("save_version", 0)) < SAVE_VERSION
		or str(
			parsed.get("skill_button_assignments", {}).get("contract_id", "")
			if parsed.get("skill_button_assignments", {}) is Dictionary
			else ""
		) != SKILL_BUTTON_ASSIGNMENTS_CONTRACT_ID
		or int(parsed.get("content_schema_version", 0)) < CURRENT_CONTENT_SCHEMA_VERSION
	):
		_commit_save()
	recalculate_stats()


func apply_quick_slot_assignment(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return false
	if result.get("assignments", null) is Dictionary:
		return apply_skill_button_assignment(result)
	var change: Dictionary = result.get("change", {})
	if str(change.get("contract_id", "")) != "gameplay.skill.quick_slot_assignment.v1":
		return false
	var slots_value: Variant = result.get("slots", [])
	if not slots_value is Array or slots_value.size() != quick_slots.size():
		return false
	var next_slots: Array[String] = []
	for value: Variant in slots_value:
		var skill_name := str(value)
		if not skill_name.is_empty() and not learned_skills.has(skill_name):
			return false
		next_slots.append(skill_name)
	var migrated := SkillLoadoutRulesScript.normalize_assignments({}, next_slots)
	attack_skill_slots = _normalized_skill_slot_array(
		migrated.get(SKILL_SLOT_GROUP_ATTACK, []),
		ATTACK_SKILL_SLOT_COUNT
	)
	attack_ring_slots = _normalized_skill_slot_array(
		migrated.get(SKILL_SLOT_GROUP_ATTACK_RING, []),
		ATTACK_RING_SKILL_SLOT_COUNT
	)
	_sync_legacy_quick_slots_from_ring()
	quick_slots_changed.emit(change.duplicate(true))
	skills_changed.emit()
	profile_changed.emit()
	_commit_save()
	return true


func apply_skill_button_assignment(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return false
	var change: Dictionary = result.get("change", {})
	if str(change.get("contract_id", "")) != SKILL_BUTTON_ASSIGNMENTS_CONTRACT_ID:
		return false
	var assignments_value: Variant = result.get("assignments", {})
	if not assignments_value is Dictionary:
		return false
	var normalized := _normalized_skill_button_assignments(assignments_value, quick_slots)
	var next_attack := _normalized_skill_slot_array(
		normalized.get(SKILL_SLOT_GROUP_ATTACK, []),
		ATTACK_SKILL_SLOT_COUNT
	)
	var next_ring := _normalized_skill_slot_array(
		normalized.get(SKILL_SLOT_GROUP_ATTACK_RING, []),
		ATTACK_RING_SKILL_SLOT_COUNT
	)
	for skill_name: String in next_attack + next_ring:
		if not skill_name.is_empty() and not is_skill_learned(skill_name):
			return false
	attack_skill_slots = next_attack
	attack_ring_slots = next_ring
	_sync_legacy_quick_slots_from_ring()
	quick_slots_changed.emit(change.duplicate(true))
	skills_changed.emit()
	profile_changed.emit()
	_commit_save()
	return true


func skill_button_assignments_snapshot() -> Dictionary:
	return {
		"contract_id": SKILL_BUTTON_ASSIGNMENTS_CONTRACT_ID,
		SKILL_SLOT_GROUP_ATTACK: attack_skill_slots.duplicate(),
		SKILL_SLOT_GROUP_ATTACK_RING: attack_ring_slots.duplicate(),
		"migration": "native_v3",
	}


func skill_slots_for_group(slot_group: String) -> Array[String]:
	if slot_group == SKILL_SLOT_GROUP_ATTACK:
		return attack_skill_slots.duplicate()
	if slot_group == SKILL_SLOT_GROUP_ATTACK_RING:
		return attack_ring_slots.duplicate()
	# Read-only compatibility for old keyboard skill_1..skill_4 callers.
	return quick_slots.duplicate()


func skill_name_for_slot(slot_group: String, slot_index: int) -> String:
	var slots := skill_slots_for_group(slot_group)
	if slot_index < 0 or slot_index >= slots.size():
		return ""
	return slots[slot_index]


func _restore_skill_button_assignments(assignments_value: Variant, legacy_center: Array) -> void:
	var normalized := _normalized_skill_button_assignments(assignments_value, legacy_center)
	attack_skill_slots = _normalized_skill_slot_array(
		normalized.get(SKILL_SLOT_GROUP_ATTACK, []),
		ATTACK_SKILL_SLOT_COUNT
	)
	attack_ring_slots = _normalized_skill_slot_array(
		normalized.get(SKILL_SLOT_GROUP_ATTACK_RING, []),
		ATTACK_RING_SKILL_SLOT_COUNT
	)
	_sync_legacy_quick_slots_from_ring()


func _normalized_skill_button_assignments(assignments_value: Variant, legacy_center: Array) -> Dictionary:
	var source := SkillLoadoutRulesScript.normalize_assignments(assignments_value, legacy_center)
	return {
		"contract_id": SKILL_BUTTON_ASSIGNMENTS_CONTRACT_ID,
		SKILL_SLOT_GROUP_ATTACK: _normalized_skill_slot_array(
			source.get(SKILL_SLOT_GROUP_ATTACK, []),
			ATTACK_SKILL_SLOT_COUNT
		),
		SKILL_SLOT_GROUP_ATTACK_RING: _normalized_skill_slot_array(
			source.get(SKILL_SLOT_GROUP_ATTACK_RING, []),
			ATTACK_RING_SKILL_SLOT_COUNT
		),
		"migration": str(source.get("migration", "native_v3")),
	}


func _normalized_skill_slot_array(value: Variant, expected_size: int) -> Array[String]:
	var result: Array[String] = []
	var source: Array = value if value is Array else []
	for index in range(expected_size):
		result.append(str(source[index]) if index < source.size() else "")
	return result


func _sync_legacy_quick_slots_from_ring() -> void:
	quick_slots = ["", "", "", ""]
	for index in range(mini(quick_slots.size(), attack_ring_slots.size())):
		quick_slots[index] = attack_ring_slots[index]


func apply_warrior_runtime_state(snapshot: Dictionary, persist := false) -> bool:
	var normalized := _normalized_warrior_runtime_state(snapshot)
	if normalized.is_empty():
		return false
	warrior_runtime_state = normalized
	warrior_runtime_state_changed.emit(warrior_runtime_state.duplicate(true))
	if persist:
		profile_changed.emit()
		_commit_save()
	return true


func warrior_runtime_state_for_restore() -> Dictionary:
	return warrior_runtime_state.duplicate(true)


func _normalized_warrior_runtime_state(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary or str(snapshot.get("contract_id", "")) != WARRIOR_RUNTIME_CONTRACT_ID:
		return _default_warrior_runtime_state()
	var toggles: Dictionary = snapshot.get("toggles", {})
	return {
		"contract_id": WARRIOR_RUNTIME_CONTRACT_ID,
		"toggles": {
			"warrior.thrusting": bool(toggles.get("warrior.thrusting", false)),
			"warrior.half_moon": bool(toggles.get("warrior.half_moon", false)),
			"warrior.fire_sword.auto_enabled": bool(
				toggles.get("warrior.fire_sword.auto_enabled", false)
			),
		},
		# Only the user's toggle is persisted. An in-flight charge and cooldown
		# are still discarded so loading never creates a free prepared hit.
		"cooldowns": {},
	}


func _default_warrior_runtime_state() -> Dictionary:
	return {
		"contract_id": WARRIOR_RUNTIME_CONTRACT_ID,
		"toggles": {
			"warrior.thrusting": false,
			"warrior.half_moon": false,
			"warrior.fire_sword.auto_enabled": false,
		},
		"cooldowns": {},
	}


func update_world_location(
	map_id: int,
	screen_position_px: Vector2,
	ground_position_gu: Variant = null
) -> void:
	if active_profile_id.is_empty():
		return
	saved_map_id = map_id
	saved_position = screen_position_px
	if ground_position_gu is Vector2:
		saved_ground_position_gu = ground_position_gu
		saved_ground_position_gu_valid = true
	else:
		saved_ground_position_gu = Vector2.ZERO
		saved_ground_position_gu_valid = false


func save_safe_logout(
	home_map_id: int,
	home_screen_position_px: Vector2,
	home_ground_position_gu: Variant = null
) -> bool:
	if active_profile_id.is_empty():
		return false
	saved_map_id = home_map_id
	saved_position = home_screen_position_px
	if home_ground_position_gu is Vector2:
		saved_ground_position_gu = home_ground_position_gu
		saved_ground_position_gu_valid = true
	else:
		saved_ground_position_gu = Vector2.ZERO
		saved_ground_position_gu_valid = false
	save_game()
	return FileAccess.file_exists(_profile_path(active_profile_id))


func list_characters() -> Array[Dictionary]:
	var index := _read_json(profile_index_path)
	var result: Array[Dictionary] = []
	for entry: Variant in index.get("profiles", []):
		if entry is Dictionary and FileAccess.file_exists(_profile_path(str(entry.get("id", "")))):
			result.append(entry.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("updated_at", 0)) > int(b.get("updated_at", 0)))
	return result


func prepare_qa_test_roster_v2() -> Dictionary:
	var marker := _read_json(test_roster_reset_marker_path)
	var reset_performed := false
	var archive_path := ""
	if str(marker.get("contract_id", "")) != TEST_ROSTER_RESET_CONTRACT_ID:
		var archive_result := _archive_current_test_profiles()
		if not bool(archive_result.get("ok", false)):
			return {
				"ok": false,
				"contract_id": TEST_CHARACTER_ROSTER_CONTRACT_ID,
				"reason": str(archive_result.get("reason", "archive_failed")),
			}
		reset_performed = true
		archive_path = str(archive_result.get("archive_path", ""))
	var roster_result := ensure_equipment_skill_test_roster()
	var profiles := list_characters()
	var ready := profiles.size() == 9 and int(roster_result.get("total", 0)) == 9
	if ready:
		_write_json_atomic(test_roster_reset_marker_path, {
			"contract_id": TEST_ROSTER_RESET_CONTRACT_ID,
			"roster_contract_id": TEST_CHARACTER_ROSTER_CONTRACT_ID,
			"reset_at": int(Time.get_unix_time_from_system()),
			"archive_path": archive_path if reset_performed else str(marker.get("archive_path", "")),
			"profile_count": profiles.size(),
		})
	roster_result["ok"] = ready
	roster_result["reset_performed"] = reset_performed
	roster_result["archive_path"] = archive_path
	return roster_result


func _archive_current_test_profiles() -> Dictionary:
	var timestamp := "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var archive_root := profile_directory.get_base_dir().path_join("test_roster_archives").path_join(timestamp)
	var archive_characters := archive_root.path_join("characters")
	var archive_absolute := ProjectSettings.globalize_path(archive_characters)
	if DirAccess.make_dir_recursive_absolute(archive_absolute) != OK:
		return {"ok": false, "reason": "archive_directory_failed"}
	var source_absolute := ProjectSettings.globalize_path(profile_directory)
	if DirAccess.dir_exists_absolute(source_absolute):
		var source_directory := DirAccess.open(profile_directory)
		if source_directory == null:
			return {"ok": false, "reason": "profile_directory_open_failed"}
		for file_name: String in source_directory.get_files():
			var source_path := source_absolute.path_join(file_name)
			var target_path := archive_absolute.path_join(file_name)
			if DirAccess.rename_absolute(source_path, target_path) != OK:
				return {"ok": false, "reason": "profile_archive_failed", "file": file_name}
		DirAccess.remove_absolute(source_absolute)
	for root_path: String in [
		profile_index_path,
		profile_index_path + ".bak",
		profile_index_path + ".tmp",
		SAVE_PATH,
		SAVE_PATH + ".bak",
		SAVE_PATH + ".tmp",
		LEGACY_SAVE_PATH,
		LEGACY_SAVE_PATH + ".bak",
		LEGACY_SAVE_PATH + ".tmp",
	]:
		if not FileAccess.file_exists(root_path):
			continue
		var target_name := root_path.get_file()
		var target_path := ProjectSettings.globalize_path(archive_root.path_join(target_name))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(root_path), target_path) != OK:
			return {"ok": false, "reason": "root_save_archive_failed", "file": root_path}
	DirAccess.make_dir_recursive_absolute(source_absolute)
	active_profile_id = ""
	character_name = ""
	return {
		"ok": true,
		"archive_path": archive_root,
	}


func ensure_equipment_skill_test_roster() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_directory))
	var index := _read_json(profile_index_path)
	var profiles: Array = index.get("profiles", [])
	var existing_index_ids := {}
	for profile_value: Variant in profiles:
		if profile_value is Dictionary:
			existing_index_ids[str(profile_value.get("id", ""))] = true
	var created := 0
	var indexed := 0
	var now := int(Time.get_unix_time_from_system())
	for loadout_value: Variant in EquipmentTestLoadoutCatalogScript.loadouts():
		if not loadout_value is Dictionary:
			continue
		var loadout: Dictionary = loadout_value
		var skill_tier := _skill_tier_for_equipment_tier(str(loadout.get("tierId", "")))
		var skill_profile := TestCharacterSkillProfilesScript.qa_v2_profile_for_character(
			str(loadout.get("profession", "")),
			skill_tier
		)
		if skill_profile.is_empty():
			continue
		var profile_id := str(skill_profile.get("character_profile_id", ""))
		if profile_id.is_empty():
			continue
		var character_level := maxi(
			int(loadout.get("level", 1)),
			int(skill_profile.get("minimum_character_level", 1))
		)
		var profile_entry := {
			"id": profile_id,
			"name": str(skill_profile.get("character_name", profile_id)),
			"profession": str(loadout.get("profession", "")),
			"gender": str(loadout.get("gender", "男")),
			"level": character_level,
			"updated_at": now,
		}
		if not FileAccess.file_exists(_profile_path(profile_id)):
			var payload := _test_character_payload(loadout, skill_profile, profile_entry, now)
			if _write_json_atomic(_profile_path(profile_id), payload):
				created += 1
		if not existing_index_ids.has(profile_id) and FileAccess.file_exists(_profile_path(profile_id)):
			profiles.append(profile_entry)
			existing_index_ids[profile_id] = true
			indexed += 1
	if indexed > 0:
		_write_json_atomic(profile_index_path, {"version": 1, "profiles": profiles})
	return {
		"contract_id": TEST_CHARACTER_ROSTER_CONTRACT_ID,
		"created": created,
		"indexed": indexed,
		"total": EquipmentTestLoadoutCatalogScript.loadouts().size(),
	}


func _skill_tier_for_equipment_tier(equipment_tier: String) -> String:
	return "woma" if equipment_tier == "wooma" else equipment_tier


func _test_character_payload(loadout: Dictionary, skill_profile: Dictionary, profile_entry: Dictionary, now: int) -> Dictionary:
	var equipment_data := {}
	var equipment_names := EquipmentTestLoadoutCatalogScript.equipment_names(loadout)
	for slot: String in EQUIPMENT_SLOTS:
		var item_name := str(equipment_names.get(slot, ""))
		equipment_data[slot] = _developer_item(
			item_name,
			"%s.%s" % [str(skill_profile.get("character_profile_id", "")), slot]
		)
	var runtime_defaults: Dictionary = skill_profile.get("runtime_defaults", {})
	var warrior_state := _default_warrior_runtime_state()
	if str(runtime_defaults.get("contract_id", "")) == WARRIOR_RUNTIME_CONTRACT_ID:
		warrior_state = _normalized_warrior_runtime_state(runtime_defaults)
	var assignments := SkillLoadoutRulesScript.normalize_assignments(
		skill_profile.get("button_assignments", {})
	)
	var ring_slots: Array = assignments.get(SKILL_SLOT_GROUP_ATTACK_RING, [])
	var legacy_slots: Array = []
	for index in range(CENTER_SKILL_SLOT_COUNT):
		legacy_slots.append(str(ring_slots[index]) if index < ring_slots.size() else "")
	return {
		"save_version": SAVE_VERSION,
		"profile_id": str(profile_entry.get("id", "")),
		"character_name": str(profile_entry.get("name", "")),
		"updated_at": now,
		"level": int(profile_entry.get("level", 1)),
		"profession": str(profile_entry.get("profession", "")),
		"gender": str(profile_entry.get("gender", "男")),
		"later_content_enabled": false,
		"game_mode_id": "classic_176",
		"experience": 0,
		"gold": 1000000,
		"inventory": [
			{"name": "强效太阳水", "count": 99},
			{"name": "魔法药(中量)", "count": 99},
		],
		"warehouse_inventory": [],
		"equipment": equipment_data,
		"learned_skills": skill_profile.get("learned_skills", {}).duplicate(true),
		"quick_slots": legacy_slots,
		"skill_button_assignments": assignments.duplicate(true),
		"warrior_runtime_state": warrior_state,
		"test_runtime_defaults": runtime_defaults.duplicate(true),
		"test_contracts": {
			"roster": TEST_CHARACTER_ROSTER_CONTRACT_ID,
			"equipment": str(loadout.get("loadoutId", "")),
			"skills": str(skill_profile.get("template_id", "")),
		},
		"quest_states": {},
		"content_packages": ContentLayers.enabled_package_ids(),
		"content_schema_version": CURRENT_CONTENT_SCHEMA_VERSION,
		"map_id": 4,
		"position": [0.0, 0.0],
		"position_space_contract_id": WORLD_POSITION_CONTRACT_ID,
		"position_screen_px": [0.0, 0.0],
		"position_ground_gu": [],
	}


func ensure_developer_test_character()->void:
	var profile_id:="developer_warrior_30"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_directory))
	var equipment_data:={
		"武器":_developer_item("木剑","dev_weapon"),"衣服":_developer_item("布衣(男)","dev_armor"),
		"头盔":_developer_item("精灵头盔","dev_helmet"),"项链":_developer_item("传统项链","dev_necklace"),
		"左手镯":_developer_item("铁手镯","dev_bracelet_l"),"右手镯":_developer_item("铁手镯","dev_bracelet_r"),
		"左戒指":_developer_item("古铜戒指","dev_ring_l"),"右戒指":_developer_item("古铜戒指","dev_ring_r"),
	}
	var all_skills:={}
	for skill:Variant in GameData.get_profession_skills("战士"):
		if skill is Dictionary:all_skills[str(skill.get("skillName",""))]=3
	var slots:Array[String]=["攻杀剑术","刺杀剑术","半月弯刀","烈火剑法"]
	var now:=int(Time.get_unix_time_from_system())
	var payload:={"save_version":SAVE_VERSION,"profile_id":profile_id,"character_name":"测试战士30级","updated_at":now,"level":30,"profession":"战士","gender":"男","later_content_enabled":false,"game_mode_id":"classic_176","experience":0,"gold":100000,"inventory":[],"warehouse_inventory":[],"equipment":equipment_data,"learned_skills":all_skills,"quick_slots":slots,"quest_states":{},"content_packages":ContentLayers.enabled_package_ids(),"content_schema_version":CURRENT_CONTENT_SCHEMA_VERSION,"map_id":4,"position":[0.0,0.0]}
	payload.merge(_default_world_position_fields(), true)
	if not _write_json_atomic(_profile_path(profile_id),payload):return
	var index:=_read_json(profile_index_path);var profiles:Array=index.get("profiles",[])
	var replaced:=false
	for profile_offset in profiles.size():
		if str(profiles[profile_offset].get("id",""))==profile_id:profiles[profile_offset]={"id":profile_id,"name":"测试战士30级","profession":"战士","gender":"男","level":30,"updated_at":now};replaced=true;break
	if not replaced:profiles.append({"id":profile_id,"name":"测试战士30级","profession":"战士","gender":"男","level":30,"updated_at":now})
	_write_json_atomic(profile_index_path,{"version":1,"profiles":profiles})


func _developer_item(item_name:String,instance_id:String)->Dictionary:
	var item:=GameData.get_item_record(item_name);var maximum:=maxi(1,int(item.get("maxDurability",1)))
	var result:={"name":item_name,"count":1,"durability":maximum,"max_durability":maximum,"instance_id":instance_id}
	if str(item.get("category",""))=="武器":result.merge({"weapon_luck":0,"weapon_curse":0})
	return result


func ensure_zuma_test_character() -> void:
	var profile_id := "developer_zuma_warrior_40"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_directory))
	var equipment_data := {
		"武器": _developer_item("裁决之杖", "zuma_weapon"),
		"衣服": _developer_item("战神盔甲(男)", "zuma_armor"),
		"头盔": _developer_item("黑铁头盔", "zuma_helmet"),
		"项链": _developer_item("绿色项链", "zuma_necklace"),
		"左手镯": _developer_item("骑士手镯", "zuma_bracelet_l"),
		"右手镯": _developer_item("骑士手镯", "zuma_bracelet_r"),
		"左戒指": _developer_item("力量戒指", "zuma_ring_l"),
		"右戒指": _developer_item("力量戒指", "zuma_ring_r"),
	}
	var all_skills := {}
	for skill: Variant in GameData.get_profession_skills("战士"):
		if skill is Dictionary:
			all_skills[str(skill.get("skillName", ""))] = 3
	var now := int(Time.get_unix_time_from_system())
	var payload := {
		"save_version": SAVE_VERSION, "profile_id": profile_id, "character_name": "祖玛套装测试号",
		"updated_at": now, "level": 40, "profession": "战士", "gender": "男",
		"later_content_enabled": false, "game_mode_id": "classic_176", "experience": 0,
		"gold": 100000, "inventory": [{"name": "太阳水", "count": 10}], "warehouse_inventory": [],
		"equipment": equipment_data, "learned_skills": all_skills,
		"quick_slots": ["攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法"], "quest_states": {},
		"content_packages": ContentLayers.enabled_package_ids(), "content_schema_version": CURRENT_CONTENT_SCHEMA_VERSION,
		"map_id": 4, "position": [0.0, 0.0],
	}
	payload.merge(_default_world_position_fields(), true)
	if not _write_json_atomic(_profile_path(profile_id), payload):
		return
	var index := _read_json(profile_index_path)
	var profiles: Array = index.get("profiles", [])
	var entry := {"id": profile_id, "name": "祖玛套装测试号", "profession": "战士", "gender": "男", "level": 40, "updated_at": now}
	var replaced := false
	for profile_offset in profiles.size():
		if str(profiles[profile_offset].get("id", "")) == profile_id:
			profiles[profile_offset] = entry
			replaced = true
			break
	if not replaced:
		profiles.append(entry)
	_write_json_atomic(profile_index_path, {"version": 1, "profiles": profiles})


func _default_world_position_fields() -> Dictionary:
	return {
		"position": [0.0, 0.0],
		"position_space_contract_id": WORLD_POSITION_CONTRACT_ID,
		"position_screen_px": [0.0, 0.0],
		"position_ground_gu": [],
	}


func create_character(new_name: String, new_profession := "战士", new_gender := "男") -> String:
	var clean_name := new_name.strip_edges().substr(0, 12)
	if clean_name.is_empty():
		return "角色名不能为空"
	if new_profession != "战士":
		return "当前版本仅开放战士"
	if new_gender not in ["男", "女"]:
		return "性别无效"
	active_profile_id = "%d_%d" % [int(Time.get_unix_time_from_system()), randi_range(1000, 9999)]
	character_name = clean_name
	reset_progress(false)
	profession = new_profession
	gender = new_gender
	recalculate_stats()
	save_game()
	return ""


func select_character(profile_id: String) -> bool:
	if not FileAccess.file_exists(_profile_path(profile_id)):
		return false
	active_profile_id = profile_id
	load_save()
	_autosave_elapsed = 0.0
	return true


func _update_profile_index() -> void:
	var profiles := list_characters()
	var found := false
	for entry: Dictionary in profiles:
		if str(entry.get("id", "")) == active_profile_id:
			entry.merge({"name": character_name, "profession": profession, "gender": gender, "level": level, "updated_at": int(Time.get_unix_time_from_system())}, true)
			found = true
	if not found:
		profiles.append({"id": active_profile_id, "name": character_name, "profession": profession, "gender": gender, "level": level, "updated_at": int(Time.get_unix_time_from_system())})
	_write_json_atomic(profile_index_path, {"version": 1, "profiles": profiles})


func _migrate_single_save_to_profile() -> void:
	if not list_characters().is_empty():
		return
	var legacy_path := SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else LEGACY_SAVE_PATH
	if not FileAccess.file_exists(legacy_path):
		return
	var old_data := _read_json(legacy_path)
	if old_data.is_empty():
		return
	active_profile_id = "legacy_01"
	character_name = str(old_data.get("character_name", "旧角色"))
	old_data["profile_id"] = active_profile_id
	old_data["character_name"] = character_name
	old_data["updated_at"] = int(Time.get_unix_time_from_system())
	_write_json_atomic(_profile_path(active_profile_id), old_data)
	_update_profile_index()
	active_profile_id = ""
	character_name = ""


func _commit_save() -> void:
	if not test_mode:
		save_game()
