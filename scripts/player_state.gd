extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const EquipmentTestLoadoutCatalogScript = preload("res://scripts/equipment_test_loadout_catalog.gd")
const TestCharacterSkillProfilesScript = preload("res://scripts/test_character_skill_profiles.gd")
const SkillLoadoutRulesScript = preload("res://scripts/skill_loadout_rules.gd")
const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const SkillProgressionServiceScript := preload("res://scripts/skills/skill_progression_service.gd")
const SkillRngScript := preload("res://scripts/skills/skill_rng.gd")
const PricingServiceScript := preload("res://scripts/pricing_service.gd")
const WorldMonsterRespawnStateScript := preload(
	"res://scripts/world_monster_respawn_state.gd"
)

signal profile_changed
signal inventory_changed
signal equipment_changed
signal skills_changed
signal skill_progression_changed(snapshot: Dictionary)
signal quick_slots_changed(change: Dictionary)
signal quick_item_slots_changed(change: Dictionary)
signal warrior_runtime_state_changed(snapshot: Dictionary)
signal consumable_requested(item_name: String)
signal scroll_requested(item_name: String)
signal quests_changed
signal profession_changed(profession: String)

const SAVE_VERSION := 10
const SAVE_PATH := "user://player_save_v03.json"
const LEGACY_SAVE_PATH := "user://player_save_v02.json"
const PROFILE_INDEX_PATH := "user://character_profiles.json"
const PROFILE_DIRECTORY := "user://characters"
const TEST_ROSTER_RESET_MARKER_PATH := "user://test_roster_v2_reset.json"
const AUTOSAVE_INTERVAL := 30.0
const WARRIOR_RUNTIME_CONTRACT_ID := "gameplay.warrior.skill_runtime.v2"
const TAOIST_MAIN_PET_PERSISTENCE_CONTRACT_ID := (
	"skills.summon.persistence.runtime_state.v1"
)
const TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID := (
	"skills.summon.persistence.runtime_states.v1"
)
const TEST_CHARACTER_ROSTER_CONTRACT_ID := "test.character.roster.full_equipment_skills.v2"
const TEST_ROSTER_RESET_CONTRACT_ID := "test.character.roster.reset.v2"
const CHIYUE_TEST_PROFILE_IDS: Array[String] = [
	"test.character.warrior.chiyue.v2",
	"test.character.wizard.chiyue.v2",
	"test.character.taoist.chiyue.v2",
]
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
const QUICK_ITEM_SLOTS_CONTRACT_ID := "gameplay.item.quick_slots.v1"
const QUICK_ITEM_SLOT_COUNT := 4
const SAVE_RESULT_CONTRACT_ID := "player_state.save_result.v1"
const DEVICE_LAB_SAVE_CONTRACT_ID := "device_lab.player_save.v1"
const DEATH_EXPERIENCE_PENALTY_CONTRACT_ID := "player_state.death_experience_penalty.v1"
const PRICING_CONTRACT_ID := PricingServiceScript.CONTRACT_ID
const DURABILITY_CONTRACT_ID := "equipment.durability.raw_authority.v1"
const DURABILITY_EVENT_WEAPON_PHYSICAL_HIT := (
	"equipment.durability.weapon_physical_hit.v1"
)
const DURABILITY_EVENT_INCOMING_PHYSICAL_STRUCK := (
	"equipment.durability.incoming_physical_struck.v1"
)
const DURABILITY_RAW_UNITS_PER_DISPLAY := 1000
const DURABILITY_INCOMING_EXTENSION_POLICY := (
	"project_slots_relic_badge_use_same_one_in_eight_physical_wear.v1"
)
const SHOP_SELL_CONTRACT_ID := PRICING_CONTRACT_ID
const QUEST_ABANDON_CONTRACT_ID := "gameplay.quest.abandon_authority.v1"
const WAREHOUSE_SORT_CONTRACT_ID := "gameplay.warehouse.sort_authority.v1"
const WAREHOUSE_CAPACITY := 500
const INVENTORY_CAPACITY := 100
const INVENTORY_WEIGHT_CONTRACT_ID := "gameplay.inventory.weight_authority.v1"
const INVENTORY_WEIGHT_REJECTION := "超过负重，无法拾取。"
const INVENTORY_SLOT_REJECTION := "背包空间不足。"
const WAREHOUSE_TRANSFER_CONTRACT_ID := "gameplay.warehouse.transfer_authority.v1"
const SHARED_WAREHOUSE_SCHEMA_VERSION := 1
const SHARED_WAREHOUSE_CONTRACT_ID := "player_state.shared_warehouse.v1"
const SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID := "player_state.shared_warehouse.legacy_merge.v1"
const SHARED_WAREHOUSE_DEFAULT_PATH := "user://shared_warehouse.json"
const SHARED_WAREHOUSE_TRANSACTION_LOG_PATH := "user://shared_warehouse.transaction.json"
const MAX_SAFE_WEIGHT := 9223372036854775807
const SHOP_SELL_HIGH_VALUE_PRICE := 10000
const EQUIPMENT_SLOTS: Array[String] = ["武器", "衣服", "头盔", "项链", "左手镯", "右手镯", "左戒指", "右戒指", "圣物", "徽章"]
const STARTER_LOADOUT_CONTRACT_ID := "gameplay.character.starter_loadout.v1"
const CHARACTER_DELETE_CONTRACT_ID := "player_state.character.delete.v1"
const STARTER_WEAPON_ITEM_NAME := "木剑"
const STARTER_ARMOR_BY_GENDER := {"男": "布衣(男)", "女": "布衣(女)"}
const VERIFIED_EXPERIENCE_1_TO_22 := {
	1: 100, 2: 200, 3: 300, 4: 400, 5: 600, 6: 900, 7: 1200, 8: 1700, 9: 2500,
	10: 6000, 11: 8000, 12: 10000, 13: 15000, 14: 30000, 15: 40000, 16: 50000,
	17: 70000, 18: 100000, 19: 120000, 20: 140000, 21: 250000, 22: 300000,
}
const TEMPORARY_ITEM_BUFF_CONTRACT_ID := "gameplay.item.temporary_stat_buff.v1"
const TEMPORARY_ITEM_BUFF_ALLOWED_STATS := {
    "max_hp": true, "max_mp": true, "attack_max": true,
    "magic_max": true, "tao_max": true, "attack_speed_tier": true,
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
## The public warehouse is account-scoped, never character-scoped.  The path
## is overridable only by isolated tests; production always uses the default.
var shared_warehouse_path := SHARED_WAREHOUSE_DEFAULT_PATH
var shared_warehouse_transaction_log_path := SHARED_WAREHOUSE_TRANSACTION_LOG_PATH
var _shared_warehouse_initialized := false
var _warehouse_transaction_locked := false
var _persistence_transaction_in_progress := false
var _test_fail_shared_write := false
var _test_fail_profile_write := false
var _test_fail_warehouse_rollback_write := false
var equipment: Dictionary = {
	"武器": {}, "衣服": {}, "头盔": {}, "项链": {},
	"左手镯": {}, "右手镯": {}, "左戒指": {}, "右戒指": {}, "圣物": {}, "徽章": {},
}
var learned_skills: Dictionary = {}
var _skill_progression: RefCounted = SkillProgressionServiceScript.new()
var quick_slots: Array[String] = ["", "", "", ""]
var quick_item_slots: Array[String] = ["", "", "", ""]
var equip_cycle_cursor: Dictionary = {"戒指": "左戒指", "手镯": "左手镯"}
var attack_skill_slots: Array[String] = [""]
var attack_ring_slots: Array[String] = ["", "", "", "", "", ""]
var warrior_runtime_state: Dictionary = {}
var taoist_main_pet_runtime_states: Dictionary = {
	"contract_id": TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID,
	"slots": {},
}
var quest_states: Dictionary = {}
var world_monster_respawn_state: Dictionary = (
	WorldMonsterRespawnStateScript.empty_snapshot()
)
var saved_map_id := 910001
var saved_position := Vector2.ZERO
var saved_ground_position_gu := Vector2.ZERO
var saved_ground_position_gu_valid := false
var computed_stats: Dictionary = {}
var computed_special_effects: Dictionary = {}
var test_mode := false
var durability_event_commit_count := 0
var _durability_rng := RandomNumberGenerator.new()
var active_profile_id := ""
var character_name := ""
var _autosave_elapsed := 0.0
var profile_index_path := PROFILE_INDEX_PATH
var profile_directory := PROFILE_DIRECTORY
var test_roster_reset_marker_path := TEST_ROSTER_RESET_MARKER_PATH
var last_save_result: Dictionary = {
	"contract_id": SAVE_RESULT_CONTRACT_ID,
	"success": false,
	"reason": "not_attempted",
}
var last_load_result: Dictionary = {
	"contract_id": SAVE_RESULT_CONTRACT_ID,
	"success": false,
	"reason": "not_attempted",
}
var _consumed_shop_sell_quote_ids: Dictionary = {}
var _loot_batch_debug: Dictionary = {"plan_scans": 0, "initial_weight_scans": 0, "save_commits": 0}
var _item_instance_serial := 0
var _test_transaction_counters: Dictionary = {"commit_attempts": 0, "profile_signals": 0, "inventory_signals": 0, "quest_signals": 0}
var _consumed_shop_buy_quote_ids: Dictionary = {}
var _shop_buy_quote_serial := 0
var _shop_pricing_session_nonce := ""
var last_receive_result: Dictionary = {
	"contract_id": INVENTORY_WEIGHT_CONTRACT_ID,
	"success": false,
	"reason": "not_attempted",
}
var _taoist_main_pets_persistence_provider := Callable()
# Test-only failure injection. Production ignores it unless test_mode is true.
var _test_force_atomic_write_failure := false
var temporary_item_buffs: Dictionary = {}
var temporary_item_buff_revision := 0



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
	_shop_pricing_session_nonce = "%d:%d" % [Time.get_ticks_usec(), randi()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROFILE_DIRECTORY))
	_migrate_single_save_to_profile()
	_recover_shared_warehouse_transaction()
	_initialize_shared_warehouse()
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
	# reset_progress is character-local.  Never clear the account warehouse.
	if test_mode and not _shared_warehouse_test_isolation_enabled():
		warehouse_inventory = []
	elif _shared_warehouse_initialized:
		warehouse_inventory = _shared_warehouse_read_inventory()
	else:
		warehouse_inventory = []
	equipment = _empty_equipment()
	learned_skills = {}
	_skill_progression.load_snapshot({})
	quick_slots = ["", "", "", ""]
	quick_item_slots = ["", "", "", ""]
	equip_cycle_cursor = _default_equip_cycle_cursor()
	attack_skill_slots = [""]
	attack_ring_slots = ["", "", "", "", "", ""]
	warrior_runtime_state = _default_warrior_runtime_state()
	taoist_main_pet_runtime_states = _empty_taoist_main_pet_runtime_states()
	quest_states = {}
	world_monster_respawn_state = WorldMonsterRespawnStateScript.empty_snapshot()
	_consumed_shop_sell_quote_ids.clear()
	_consumed_shop_buy_quote_ids.clear()
	_shop_buy_quote_serial = 0
	durability_event_commit_count = 0
	temporary_item_buffs = {}
	temporary_item_buff_revision = 0
	if _shop_pricing_session_nonce.is_empty():
		_shop_pricing_session_nonce = "%d:%d" % [Time.get_ticks_usec(), randi()]
	saved_map_id = 910001
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
		quick_item_slots_changed.emit({
			"contract_id": QUICK_ITEM_SLOTS_CONTRACT_ID,
			"reset": true,
			"slots": quick_item_slots.duplicate(),
		})
		quests_changed.emit()
		profile_changed.emit()


func select_profession(value: String) -> String:
	if not ProfessionRules.is_valid_profession(value):
		return "无效职业：%s" % value
	if profession == value:
		return "当前职业已经是%s" % value
	# Profession changes can invalidate equipped items. Preflight all returned
	# instances against the *final* equipment effect set and bag cap before
	# mutating the character, so a full/overweight bag cannot partially switch
	# profession or silently delete an item.
	var incompatible_slots: Array[String] = []
	var incompatible_records: Array[Dictionary] = []
	for slot: String in equipment.keys():
		var equipped_record: Variant = equipment[slot]
		var equipped_name := str(equipped_record.get("name", "")) if equipped_record is Dictionary else str(equipped_record)
		if equipped_name.is_empty():
			continue
		var item := GameData.get_item(equipped_name)
		var item_profession := EquipmentRulesScript.effective_profession(item)
		if item_profession not in ["", "通用", value]:
			incompatible_slots.append(slot)
			incompatible_records.append(
				equipped_record.duplicate(true)
				if equipped_record is Dictionary
				else _make_item_instance(equipped_name, GameData.get_item_record(equipped_name))
			)
	var profession_before := profession
	var equipment_before := equipment.duplicate(true)
	var stats_before := computed_stats.duplicate(true)
	var effects_before := computed_special_effects.duplicate(true)
	var planned_inventory := inventory.duplicate(true)
	if not incompatible_records.is_empty():
		profession = value
		for slot: String in incompatible_slots:
			equipment[slot] = {}
		recalculate_stats()
		for returned_record: Dictionary in incompatible_records:
			var preview := _build_receive_result_for_record(returned_record, planned_inventory)
			if not bool(preview.get("success", false)):
				profession = profession_before
				equipment = equipment_before
				computed_stats = stats_before
				computed_special_effects = effects_before
				return str(preview.get("message", INVENTORY_WEIGHT_REJECTION))
			planned_inventory = (preview.get("inventory", planned_inventory) as Array).duplicate(true)
		profession = profession_before
		equipment = equipment_before
		computed_stats = stats_before
		computed_special_effects = effects_before
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
	for slot: String in equipment.keys():
		var equipped_record: Variant = equipment[slot]
		var equipped_name := str(equipped_record.get("name", "")) if equipped_record is Dictionary else str(equipped_record)
		if equipped_name.is_empty():
			continue
		var item := GameData.get_item(equipped_name)
		var item_profession := EquipmentRulesScript.effective_profession(item)
		if item_profession not in ["", "通用", profession]:
			equipment[slot] = {}
	inventory = planned_inventory
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


## Public inventory entry point. All gameplay paths (loot, shops, quests and
## warehouse withdrawal) must use this atomic authority instead of appending
## records directly.
func add_item(item_name: String, amount := 1) -> Dictionary:
	return receive(item_name, amount)


## A cheap, side-effect-free preflight. The detailed rejection is retained in
## `last_receive_result` for UI/diagnostics while the boolean keeps old callers
## source-compatible.
func can_receive(item_name: String, amount := 1) -> bool:
	last_receive_result = _build_receive_result(item_name, amount, inventory)
	return bool(last_receive_result.get("success", false))


func can_receive_record(record: Dictionary) -> bool:
	last_receive_result = _build_receive_result_for_record(record, inventory)
	return bool(last_receive_result.get("success", false))


func receive(item_name: String, amount := 1, commit := true) -> Dictionary:
	var before_inventory := inventory.duplicate(true)
	var before_gold := gold
	var result := _build_receive_result(item_name, amount, inventory)
	if not bool(result.get("success", false)):
		last_receive_result = result
		return result
	_apply_receive_result(result)
	if commit and not _commit_save():
		inventory = before_inventory
		gold = before_gold
		last_receive_result = _receive_failure("save_failed", "物品和金币均未改变。")
		return last_receive_result
	last_receive_result = result
	if bool(result.get("inventory_changed", false)):
		inventory_changed.emit()
	if int(result.get("gold_delta", 0)) != 0:
		profile_changed.emit()
	return result


## Internal variant used by buy/quest/warehouse transactions. It shares the
## same preflight and plan builder but defers the enclosing transaction's save.
func _add_item_without_commit(item_name: String, amount: int) -> bool:
	var result := receive(item_name, amount, false)
	return bool(result.get("success", false))


func receive_record(record: Dictionary, commit := true) -> Dictionary:
	var before_inventory := inventory.duplicate(true)
	var before_gold := gold
	var result := _build_receive_result_for_record(record, inventory)
	if not bool(result.get("success", false)):
		last_receive_result = result
		return result
	_apply_receive_result(result)
	if commit and not _commit_save():
		inventory = before_inventory
		gold = before_gold
		last_receive_result = _receive_failure("save_failed", "物品未改变。")
		return last_receive_result
	last_receive_result = result
	if bool(result.get("inventory_changed", false)):
		inventory_changed.emit()
	return result


func _build_receive_result(item_name: String, amount: int, base_inventory: Array) -> Dictionary:
	var catalog_item := GameData.get_item_record(item_name)
	if catalog_item.is_empty():
		return _receive_failure("unknown_item", "物品无效。")
	if amount <= 0:
		return _receive_failure("invalid_amount", "数量无效。")
	var kind := str(catalog_item.get("kind", "unknown"))
	if kind == "currency":
		return {
			"contract_id": INVENTORY_WEIGHT_CONTRACT_ID,
			"success": true,
			"reason": "",
			"inventory": base_inventory.duplicate(true),
			"inventory_changed": false,
			"gold_delta": int(catalog_item.get("currencyAmount", 1)) * amount,
			"weight_before": inventory_weight(base_inventory),
			"weight_after": inventory_weight(base_inventory),
		}
	return _build_receive_result_for_template(item_name, amount, catalog_item, base_inventory, {})


func _build_receive_result_for_record(record: Dictionary, base_inventory: Array) -> Dictionary:
	var item_name := str(record.get("name", ""))
	var amount := maxi(1, int(record.get("count", 1)))
	var catalog_item := GameData.get_item_record(item_name)
	if catalog_item.is_empty() or item_name.is_empty():
		return _receive_failure("unknown_item", "物品无效。")
	return _build_receive_result_for_template(item_name, amount, catalog_item, base_inventory, record)


func _build_receive_result_for_template(
	item_name: String,
	amount: int,
	catalog_item: Dictionary,
	base_inventory: Array,
	template: Dictionary
) -> Dictionary:
	if amount <= 0:
		return _receive_failure("invalid_amount", "数量无效。")
	var next_inventory: Array = base_inventory.duplicate(true)
	var is_stackable := bool(catalog_item.get("stackable", false)) and str(catalog_item.get("kind", "")) != "equipment"
	var max_stack := _max_stack_for_item(catalog_item) if is_stackable else 1
	var remaining := amount
	if is_stackable:
		for index in range(next_inventory.size()):
			var existing: Variant = next_inventory[index]
			if not existing is Dictionary or str(existing.get("name", "")) != item_name or not _inventory_records_mergeable(existing, template if not template.is_empty() else {"name": item_name, "count": 1}):
				continue
			var available := maxi(0, max_stack - int(existing.get("count", 0)))
			if available <= 0:
				continue
			var moved := mini(available, remaining)
			existing["count"] = int(existing.get("count", 0)) + moved
			remaining -= moved
			if remaining <= 0:
				break
	while remaining > 0:
		if inventory_occupied_count(next_inventory) >= INVENTORY_CAPACITY:
			return _receive_failure("inventory_full", INVENTORY_SLOT_REJECTION)
		var moved := mini(remaining, max_stack) if is_stackable else 1
		var new_record: Dictionary
		if not template.is_empty() and not is_stackable:
			new_record = template.duplicate(true)
			new_record["count"] = 1
		elif str(catalog_item.get("kind", "")) == "equipment":
			new_record = _make_item_instance(item_name, catalog_item)
		else:
			new_record = {"name": item_name, "count": moved}
		if not _place_inventory_record_in_first_free_slot(next_inventory, new_record):
			return _receive_failure("inventory_full", INVENTORY_SLOT_REJECTION)
		remaining -= moved
	var weight_before := inventory_weight(base_inventory)
	var weight_after := inventory_weight(next_inventory)
	var max_weight := max_inventory_weight()
	# Compatibility rule: an old save may already exceed the new cap, but no
	# operation may increase that burden. This also lets a swap/unequip preserve
	# an existing overweight state when the resulting weight is not higher.
	if weight_after > max_weight and weight_after > weight_before:
		return _receive_failure("overweight", INVENTORY_WEIGHT_REJECTION, weight_before, weight_after, max_weight)
	return {
		"contract_id": INVENTORY_WEIGHT_CONTRACT_ID,
		"success": true,
		"reason": "",
		"inventory": next_inventory,
		"inventory_changed": next_inventory != base_inventory,
		"gold_delta": 0,
		"weight_before": weight_before,
		"weight_after": weight_after,
		"max_weight": max_weight,
	}


func _receive_failure(reason: String, message: String, before := -1, after := -1, maximum := -1) -> Dictionary:
	return {
		"contract_id": INVENTORY_WEIGHT_CONTRACT_ID,
		"success": false,
		"reason": reason,
		"message": message,
		"inventory_changed": false,
		"gold_delta": 0,
		"weight_before": before if before >= 0 else inventory_weight(inventory),
		"weight_after": after if after >= 0 else inventory_weight(inventory),
		"max_weight": maximum if maximum >= 0 else max_inventory_weight(),
	}


func _apply_receive_result(result: Dictionary) -> void:
	if result.get("inventory", null) is Array:
		inventory = (result.get("inventory") as Array).duplicate(true)
	gold = maxi(0, gold + int(result.get("gold_delta", 0)))


func _max_stack_for_item(catalog_item: Dictionary) -> int:
	return maxi(1, int(catalog_item.get("maxStack", catalog_item.get("max_stack", 1))))


func can_receive_batch(rewards: Array) -> bool:
	var simulation := _build_receive_batch_result(rewards, inventory)
	last_receive_result = simulation
	return bool(simulation.get("success", false))


func receive_batch(rewards: Array, commit := true) -> Dictionary:
	var before_inventory := inventory.duplicate(true)
	var before_gold := gold
	var result := _build_receive_batch_result(rewards, inventory)
	if not bool(result.get("success", false)):
		last_receive_result = result
		return result
	_apply_receive_result(result)
	if commit and not _commit_save():
		inventory = before_inventory
		gold = before_gold
		last_receive_result = _receive_failure("save_failed", "奖励和金币均未改变。")
		return last_receive_result
	last_receive_result = result
	if bool(result.get("inventory_changed", false)):
		inventory_changed.emit()
	if int(result.get("gold_delta", 0)) != 0:
		profile_changed.emit()
	return result


func _build_receive_batch_result(rewards: Array, base_inventory: Array) -> Dictionary:
	var next_inventory := base_inventory.duplicate(true)
	var gold_delta := 0
	for raw_reward: Variant in rewards:
		if not raw_reward is Dictionary:
			continue
		var reward: Dictionary = raw_reward
		var item_name := str(reward.get("name", ""))
		var amount := maxi(1, int(reward.get("count", reward.get("amount", 1))))
		var result := _build_receive_result(item_name, amount, next_inventory)
		if not bool(result.get("success", false)):
			return result
		next_inventory = (result.get("inventory", next_inventory) as Array).duplicate(true)
		gold_delta += int(result.get("gold_delta", 0))
	return {
		"contract_id": INVENTORY_WEIGHT_CONTRACT_ID,
		"success": true,
		"reason": "",
		"inventory": next_inventory,
		"inventory_changed": next_inventory != base_inventory,
		"gold_delta": gold_delta,
		"weight_before": inventory_weight(base_inventory),
		"weight_after": inventory_weight(next_inventory),
		"max_weight": max_inventory_weight(),
	}


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


## Inventory arrays preserve absolute slot identity. Empty dictionaries are
## holes, not items; trailing holes are trimmed only to keep saves compact.
func inventory_occupied_count(records: Array = inventory) -> int:
	var total := 0
	for record: Variant in records:
		if _inventory_slot_is_occupied(record):
			total += 1
	return total


func warehouse_occupied_count(records: Array = warehouse_inventory) -> int:
	var total := 0
	for record: Variant in records:
		if _inventory_slot_is_occupied(record):
			total += 1
	return total


func _inventory_slot_is_occupied(record: Variant) -> bool:
	if record is Dictionary:
		return not (record as Dictionary).is_empty()
	return record != null and not str(record).is_empty()


func _first_free_inventory_slot(records: Array) -> int:
	for index in range(mini(records.size(), INVENTORY_CAPACITY)):
		if not _inventory_slot_is_occupied(records[index]):
			return index
	return records.size() if records.size() < INVENTORY_CAPACITY else -1


func _place_inventory_record_in_first_free_slot(records: Array, record: Variant) -> bool:
	var slot := _first_free_inventory_slot(records)
	if slot < 0:
		return false
	var stored: Variant = record.duplicate(true) if record is Dictionary else record
	if slot < records.size():
		records[slot] = stored
	else:
		records.append(stored)
	return true


func _clear_inventory_slot(records: Array, index: int) -> void:
	if index < 0 or index >= records.size():
		return
	records[index] = {}
	_trim_inventory_empty_tail(records)


func _trim_inventory_empty_tail(records: Array = inventory) -> void:
	while not records.is_empty() and not _inventory_slot_is_occupied(records.back()):
		records.pop_back()


func remove_item(item_name: String, amount := 1) -> bool:
	if amount <= 0 or not has_item(item_name, amount):
		return false
	var remaining := amount
	var index := inventory.size() - 1
	while index >= 0 and remaining > 0:
		var raw_stack: Variant = inventory[index]
		if raw_stack is Dictionary and not (raw_stack as Dictionary).is_empty() and raw_stack.get("name", "") == item_name:
			var stack: Dictionary = raw_stack
			var count := int(stack.get("count", 0))
			var consumed := mini(count, remaining)
			count -= consumed
			remaining -= consumed
			if count <= 0:
				inventory[index] = {}
			else:
				stack["count"] = count
		index -= 1
	_trim_inventory_empty_tail()
	inventory_changed.emit()
	_commit_save()
	return true


func _consume_inventory_index(index: int, amount := 1) -> bool:
	if index < 0 or index >= inventory.size() or amount <= 0:
		return false
	var raw_record: Variant = inventory[index]
	if not raw_record is Dictionary or (raw_record as Dictionary).is_empty():
		return false
	var record: Dictionary = raw_record
	var count := maxi(1, int(record.get("count", 1)))
	if amount > count:
		return false
	if amount == count:
		_clear_inventory_slot(inventory, index)
	else:
		record["count"] = count - amount
	inventory_changed.emit()
	_commit_save()
	return true


func destroy_inventory_indices(indices: Array) -> Dictionary:
	var targets: Array[int] = []
	for raw_index: Variant in indices:
		var index := int(raw_index)
		if index < 0 or index >= inventory.size() or not _inventory_slot_is_occupied(inventory[index]) or index in targets:
			return {"success": false, "destroyed": 0, "reason": "invalid_inventory_index"}
		targets.append(index)
	if targets.is_empty():
		return {"success": true, "destroyed": 0, "reason": "empty_selection"}
	for index: int in targets:
		inventory[index] = {}
	_trim_inventory_empty_tail()
	inventory_changed.emit()
	profile_changed.emit()
	_commit_save()
	return {"success": true, "destroyed": targets.size(), "reason": ""}


func sort_inventory_deterministic() -> Dictionary:
	var decorated: Array = []
	for index in range(inventory.size()):
		var record: Variant = inventory[index]
		if record is Dictionary and not (record as Dictionary).is_empty():
			var item := GameData.get_item_record(str(record.get("name", "")))
			decorated.append({"record": record, "index": index, "key": "%s|%s|%s|%08d" % [str(item.get("kind", "")), str(item.get("category", "")), str(record.get("name", "")), index]})
		elif _inventory_slot_is_occupied(record):
			decorated.append({"record": record, "index": index, "key": "!opaque|%08d" % index})
	decorated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["key"]) < str(b["key"]))
	var sorted_inventory: Array = []
	for entry: Dictionary in decorated:
		var record: Variant = entry["record"]
		if record is Dictionary and not sorted_inventory.is_empty() and sorted_inventory.back() is Dictionary and _inventory_records_mergeable(sorted_inventory.back(), record) and sorted_inventory.back().get("name", "") == record.get("name", ""):
			sorted_inventory.back()["count"] = int(sorted_inventory.back().get("count", 1)) + int(record.get("count", 1))
		else:
			sorted_inventory.append(record)
	var changed := sorted_inventory != inventory
	if changed:
		inventory = sorted_inventory
		inventory_changed.emit()
		profile_changed.emit()
		_commit_save()
	return {"success": true, "changed": changed, "count": inventory_occupied_count()}


func _inventory_records_mergeable(a: Dictionary, b: Dictionary) -> bool:
	for key: Variant in a.keys():
		if str(key) not in ["name", "count"]:
			return false
	for key: Variant in b.keys():
		if str(key) not in ["name", "count"]:
			return false
	var item := GameData.get_item_record(str(a.get("name", "")))
	if str(a.get("name", "")) != str(b.get("name", "")) or not bool(item.get("stackable", false)) or str(item.get("kind", "")) == "equipment":
		return false
	for key: String in ["instance_id", "durability", "max_durability", "durability_raw", "max_durability_raw", "modifiers", "random_stats", "bind", "bound"]:
		if a.has(key) or b.has(key):
			return false
	return true


func shop_sell_quotes(items: Array) -> Dictionary:
	var quotes: Dictionary = {}
	for raw_item: Variant in items:
		if not raw_item is Dictionary:
			continue
		var request: Dictionary = raw_item
		var quote := _shop_sell_quote(request)
		var quote_key := str(request.get("quote_key", ""))
		if quote_key.is_empty():
			quote_key = str(quote.get("quote_key", ""))
		if not quote_key.is_empty():
			quotes[quote_key] = quote
	return quotes


func shop_buy_quotes(stock: Array, context := {}) -> Array:
	_shop_buy_quote_serial += 1
	return _build_shop_buy_quotes(stock, context, _shop_buy_quote_serial)


func _build_shop_buy_quotes(stock: Array, context: Dictionary, quote_serial: int) -> Array:
	var quotes: Array = []
	for stock_index in range(stock.size()):
		var raw_entry: Variant = stock[stock_index]
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var item_name := str(entry.get("name", ""))
		var entry_context: Dictionary = context.duplicate(true)
		entry_context.merge(entry.get("merchant_context", {}), true)
		var pack_count := maxi(1, int(entry.get("pack_count", 1)))
		var pricing_quote := PricingServiceScript.quote_buy(
			GameData.get_item_price_record(item_name), pack_count, entry_context
		)
		var quote_id := ""
		if bool(pricing_quote.get("valid", false)):
			quote_id = "%s:%s" % [PRICING_CONTRACT_ID, JSON.stringify([
				_shop_pricing_session_nonce, active_profile_id, quote_serial, stock_index, item_name, pricing_quote,
			]).sha256_text().substr(0, 24)]
		var result: Dictionary = pricing_quote.duplicate(true)
		result.merge({
			"stock_index": stock_index,
			"stock_key": str(entry.get("offer_id", "stock:%d:%s" % [stock_index, item_name])),
			"quote_id": quote_id,
			"description": str(entry.get("description", "")),
			"merchant_id": str(entry.get("merchant_id", entry_context.get("merchant_id", ""))),
			"pack_count": pack_count,
		}, true)
		quotes.append(result)
	return quotes


func buy_shop_item(request: Dictionary, stock: Array, context := {}) -> Dictionary:
	var stock_index := int(request.get("stock_index", -1))
	if stock_index < 0 or stock_index >= stock.size():
		return _shop_buy_result(false, "购买商品已经变化，请重新选择。", stock, context)
	var current_quotes := _build_shop_buy_quotes(stock, context, _shop_buy_quote_serial)
	var quote: Dictionary = {}
	for candidate: Variant in current_quotes:
		if candidate is Dictionary and int(candidate.get("stock_index", -1)) == stock_index:
			quote = candidate
			break
	var quote_id := str(request.get("quote_id", ""))
	if not bool(quote.get("valid", false)) or quote_id.is_empty() or quote_id != str(quote.get("quote_id", "")):
		return _shop_buy_result(false, "购买报价已失效，请重新选择商品。", stock, context)
	if (
		str(request.get("item_name", quote.get("item_name", ""))) != str(quote.get("item_name", ""))
		or str(request.get("stock_key", quote.get("stock_key", ""))) != str(quote.get("stock_key", ""))
		or str(request.get("merchant_id", quote.get("merchant_id", ""))) != str(quote.get("merchant_id", ""))
	):
		return _shop_buy_result(false, "购买商品已经变化，请重新选择。", stock, context)
	if _consumed_shop_buy_quote_ids.has(quote_id):
		return _shop_buy_result(false, "该购买报价已经处理，不能重复提交。", stock, context)
	var quantity := int(request.get("quantity", 1))
	if quantity != int(quote.get("pack_count", 1)):
		return _shop_buy_result(false, "购买数量无效。", stock, context)
	var total_price := int(quote.get("total_price", 0))
	if total_price <= 0 or gold < total_price:
		return _shop_buy_result(false, "金币不足。", stock, context)
	var inventory_before := inventory.duplicate(true)
	var gold_before := gold
	gold -= total_price
	if not _add_item_without_commit(str(quote.get("item_name", "")), quantity):
		gold = gold_before
		inventory = inventory_before
		return _shop_buy_result(false, "背包空间不足或者超过最大负重。", stock, context)
	inventory_changed.emit()
	profile_changed.emit()
	if not _commit_save():
		inventory = inventory_before
		gold = gold_before
		inventory_changed.emit()
		profile_changed.emit()
		return _shop_buy_result(false, "购买存档失败，物品和金币均未改变。", stock, context)
	_consumed_shop_buy_quote_ids[quote_id] = true
	return _shop_buy_result(true, "购买成功：%s" % str(quote.get("item_name", "物品")), stock, context)


func _shop_buy_result(success: bool, message: String, stock: Array, context: Dictionary) -> Dictionary:
	return {
		"contract_id": PRICING_CONTRACT_ID,
		"success": success,
		"message": message,
		"quotes": shop_buy_quotes(stock, context),
	}


func sell_inventory_item(request: Dictionary) -> Dictionary:
	if request.get("batch", null) is Array:
		return sell_inventory_items(request.get("batch", []))
	var merchant_id := str(request.get("merchant_id", ""))
	var quote := _shop_sell_quote(request)
	var quote_id := str(request.get("quote_id", ""))
	if (
		not bool(quote.get("sellable", false))
		or quote_id.is_empty()
		or quote_id != str(quote.get("quote_id", ""))
	):
		return _shop_sell_result(false, "出售报价已失效，请重新选择物品。", merchant_id)
	if _consumed_shop_sell_quote_ids.has(quote_id):
		return _shop_sell_result(false, "该出售报价已经处理，不能重复提交。", merchant_id)
	var inventory_index := int(request.get("inventory_index", -1))
	var amount := int(request.get("amount", 0))
	if (
		inventory_index < 0
		or inventory_index >= inventory.size()
		or amount <= 0
		or amount > int(quote.get("max_quantity", 0))
	):
		return _shop_sell_result(false, "出售数量或背包位置无效。", merchant_id)
	var record: Variant = inventory[inventory_index]
	if not record is Dictionary or (record as Dictionary).is_empty():
		return _shop_sell_result(false, "物品状态已变化，出售已取消。", merchant_id)
	var inventory_before := inventory.duplicate(true)
	var gold_before := gold
	var current_count := maxi(1, int((record as Dictionary).get("count", 1)))
	if amount > current_count:
		return _shop_sell_result(false, "出售数量超过当前背包库存。", merchant_id)
	if amount >= current_count:
		_clear_inventory_slot(inventory, inventory_index)
	else:
		(record as Dictionary)["count"] = current_count - amount
	gold = maxi(0, gold + int(quote.get("unit_price", 0)) * amount)
	if not _commit_save():
		inventory = inventory_before
		gold = gold_before
		return _shop_sell_result(false, "出售存档失败，物品和金币均未改变。", merchant_id)
	_consumed_shop_sell_quote_ids[quote_id] = true
	if test_mode:
		_test_transaction_counters["inventory_signals"] = int(_test_transaction_counters.get("inventory_signals", 0)) + 1
		_test_transaction_counters["profile_signals"] = int(_test_transaction_counters.get("profile_signals", 0)) + 1
	inventory_changed.emit()
	profile_changed.emit()
	return _shop_sell_result(
		true,
		"已出售%s ×%d，获得%d金币。" % [
			str(quote.get("item_name", "物品")),
			amount,
			int(quote.get("unit_price", 0)) * amount,
		],
		merchant_id
	)


func sell_inventory_items(requests: Array) -> Dictionary:
	var result := {"contract_id": SHOP_SELL_CONTRACT_ID, "success": false, "message": "批量出售失败。", "quotes": {}}
	if requests.is_empty():
		result["message"] = "没有可出售物品。"
		return result
	var ordered := requests.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("inventory_index", -1)) > int(b.get("inventory_index", -1)))
	var merchant_id := str(ordered[0].get("merchant_id", ""))
	if GameData.merchant_context_by_id(merchant_id).is_empty():
		result["message"] = "商人状态已变化。"
		return result
	var inventory_before := inventory.duplicate(true)
	var gold_before := gold
	var consumed_before := _consumed_shop_sell_quote_ids.duplicate(true)
	var working_inventory := inventory.duplicate(true)
	var total_gold := 0
	var used_quotes: Array[String] = []
	for raw_request: Variant in ordered:
		if not raw_request is Dictionary:
			result["message"] = "出售请求无效。"
			return result
		var request: Dictionary = raw_request
		if str(request.get("merchant_id", "")) != merchant_id:
			result["message"] = "不能跨商人批量出售。"
			return result
		var quote := _shop_sell_quote(request)
		var quote_id := str(request.get("quote_id", ""))
		if not bool(quote.get("sellable", false)) or quote_id.is_empty() or quote_id != str(quote.get("quote_id", "")) or _consumed_shop_sell_quote_ids.has(quote_id) or quote_id in used_quotes:
			result["message"] = "出售报价已失效，请重新选择物品。"
			return result
		var index := int(request.get("inventory_index", -1))
		var amount := int(request.get("amount", 0))
		if index < 0 or index >= working_inventory.size() or not working_inventory[index] is Dictionary or (working_inventory[index] as Dictionary).is_empty():
			result["message"] = "出售数量或背包位置无效。"
			return result
		var record: Dictionary = working_inventory[index]
		var current_count := maxi(1, int(record.get("count", 1)))
		if amount <= 0 or amount > current_count or amount > int(quote.get("max_quantity", 0)):
			result["message"] = "出售数量超过当前背包库存。"
			return result
		if amount >= current_count:
			working_inventory[index] = {}
		else:
			record["count"] = current_count - amount
		total_gold += int(quote.get("unit_price", 0)) * amount
		used_quotes.append(quote_id)
	_trim_inventory_empty_tail(working_inventory)
	inventory = working_inventory
	gold = maxi(0, gold + total_gold)
	if not _commit_save():
		inventory = inventory_before
		gold = gold_before
		_consumed_shop_sell_quote_ids = consumed_before
		result["message"] = "出售存档失败，物品和金币均未改变。"
		return result
	for quote_id: String in used_quotes:
		_consumed_shop_sell_quote_ids[quote_id] = true
	if test_mode:
		_test_transaction_counters["inventory_signals"] = int(_test_transaction_counters.get("inventory_signals", 0)) + 1
		_test_transaction_counters["profile_signals"] = int(_test_transaction_counters.get("profile_signals", 0)) + 1
	inventory_changed.emit()
	profile_changed.emit()
	result["success"] = true
	result["message"] = "已批量出售%d项物品，获得%d金币。" % [used_quotes.size(), total_gold]
	result["quotes"] = shop_sell_quotes(_current_shop_sell_quote_items(merchant_id))
	return result


func test_transaction_debug_reset() -> void:
	_test_transaction_counters = {"commit_attempts": 0, "profile_signals": 0, "inventory_signals": 0, "quest_signals": 0}


func test_transaction_debug_snapshot() -> Dictionary:
	return _test_transaction_counters.duplicate(true)


func _shop_sell_quote(request: Dictionary) -> Dictionary:
	var inventory_index := int(request.get("inventory_index", -1))
	var requested_key := str(request.get("quote_key", ""))
	var rejection := {
		"contract_id": SHOP_SELL_CONTRACT_ID,
		"quote_key": requested_key,
		"quote_id": "",
		"sellable": false,
		"unit_price": 0,
		"max_quantity": 0,
		"reason": "物品状态已变化。",
		"requires_confirmation": false,
		"risk_flags": [],
		"warning": "",
	}
	if inventory_index < 0 or inventory_index >= inventory.size():
		return rejection
	var raw_record: Variant = inventory[inventory_index]
	if not raw_record is Dictionary or (raw_record as Dictionary).is_empty():
		return rejection
	var record: Dictionary = raw_record
	var merchant_id := str(request.get("merchant_id", ""))
	var merchant_stock_key := str(request.get("merchant_stock_key", ""))
	var merchant_context := GameData.merchant_context(merchant_stock_key) if not merchant_stock_key.is_empty() else {}
	if merchant_context.is_empty():
		merchant_context = GameData.merchant_context_by_id(merchant_id)
	var authoritative_merchant_id := str(merchant_context.get("merchant_id", ""))
	if (
		merchant_id.is_empty()
		or merchant_context.is_empty()
		or authoritative_merchant_id.is_empty()
		or authoritative_merchant_id != merchant_id
	):
		rejection["reason"] = "商人状态已变化。"
		return rejection
	var item_name := str(record.get("name", ""))
	var instance_id := str(record.get("instance_id", ""))
	var expected_key := (
		"instance:%s" % instance_id
		if not instance_id.is_empty()
		else "inventory:%d" % inventory_index
	)
	if (
		requested_key != expected_key
		or str(request.get("item_name", item_name)) != item_name
		or str(request.get("instance_id", instance_id)) != instance_id
	):
		return rejection
	var catalog := GameData.get_item_record(item_name)
	var base_price := _shop_sell_base_price(item_name, catalog)
	var count := maxi(1, int(record.get("count", 1)))
	var pricing_quote := PricingServiceScript.quote_sell(
		GameData.get_item_price_record(item_name), catalog, record, 1, merchant_context
	)
	if not bool(pricing_quote.get("valid", false)):
		rejection["reason"] = str(pricing_quote.get("reason", "该物品不能出售。"))
		return rejection
	var unit_price := int(pricing_quote.get("unit_price", 0))
	var risk_flags := _shop_sell_risk_flags(record, catalog, base_price)
	var quote_seed := JSON.stringify([
		_shop_pricing_session_nonce,
		active_profile_id,
		expected_key,
		inventory_index,
		instance_id,
		item_name,
		count,
		unit_price,
		pricing_quote,
		merchant_context,
		record,
	])
	var quote_id := "%s:%s" % [
		SHOP_SELL_CONTRACT_ID,
		quote_seed.sha256_text().substr(0, 24),
	]
	return {
		"contract_id": SHOP_SELL_CONTRACT_ID,
		"quote_key": expected_key,
		"quote_id": quote_id,
		"item_name": item_name,
		"merchant_id": authoritative_merchant_id,
		"merchant_stock_key": str(merchant_context.get("stock_key", merchant_stock_key)),
		"sellable": true,
		"unit_price": unit_price,
		"policy_version": str(pricing_quote.get("policy_version", "")),
		"formula_snapshot": (pricing_quote.get("formula_snapshot", {}) as Dictionary).duplicate(true),
		"price_source": (pricing_quote.get("source", {}) as Dictionary).duplicate(true),
		"max_quantity": count,
		"reason": "",
		"requires_confirmation": not risk_flags.is_empty(),
		"risk_flags": risk_flags,
		"warning": (
			"该物品具有高价值或特殊实例属性，出售后无法恢复。"
			if not risk_flags.is_empty()
			else ""
		),
	}


func _shop_sell_base_price(item_name: String, _catalog: Dictionary) -> int:
	return GameData.get_item_shop_price(item_name)


func _shop_sell_risk_flags(
	record: Dictionary,
	catalog: Dictionary,
	base_price: int
) -> Array[String]:
	var flags: Array[String] = []
	if base_price >= SHOP_SELL_HIGH_VALUE_PRICE:
		flags.append("high_value")
	if (
		int(record.get("enhancement_level", record.get("upgrade_level", 0))) > 0
		or int(record.get("refine_level", 0)) > 0
	):
		flags.append("enhanced")
	if int(record.get("weapon_luck", 0)) != 0 or int(record.get("weapon_curse", 0)) != 0:
		flags.append("lucky")
	if (
		bool(record.get("special", false))
		or not str(catalog.get("specialRule", "")).is_empty()
	):
		flags.append("special")
	return flags


func _shop_sell_result(success: bool, message: String, merchant_id := "") -> Dictionary:
	return {
		"contract_id": SHOP_SELL_CONTRACT_ID,
		"success": success,
		"message": message,
		"quotes": shop_sell_quotes(_current_shop_sell_quote_items(merchant_id)),
	}


func _current_shop_sell_quote_items(merchant_id := "") -> Array:
	var items: Array = []
	for inventory_index in range(inventory.size()):
		var raw_record: Variant = inventory[inventory_index]
		if not raw_record is Dictionary or (raw_record as Dictionary).is_empty():
			continue
		var record: Dictionary = raw_record
		var instance_id := str(record.get("instance_id", ""))
		items.append({
			"quote_key": (
				"instance:%s" % instance_id
				if not instance_id.is_empty()
				else "inventory:%d" % inventory_index
			),
			"inventory_index": inventory_index,
			"instance_id": instance_id,
			"item_name": str(record.get("name", "")),
			"count": int(record.get("count", 1)),
			"merchant_id": merchant_id,
			"merchant_stock_key": str(GameData.merchant_context_by_id(merchant_id).get("stock_key", "")),
		})
	return items


func use_inventory_index(index: int) -> String:
	if index < 0 or index >= inventory.size() or not inventory[index] is Dictionary or (inventory[index] as Dictionary).is_empty():
		return "请先选择物品"
	var item_name := str(inventory[index].get("name", ""))
	var item := GameData.get_item_record(item_name)
	var kind := str(item.get("kind", ""))
	var effect := str(item.get("useEffect", ""))
	if kind == "skill_book":
		return learn_skill(item_name, index)
	if item.get("usable", true) == false:
		return "%s当前没有可执行的本地规则" % item_name
	if kind == "scroll":
		if effect in ["blessing_oil", "repair_oil", "war_god_oil"]:
			var weapon_value: Variant = equipment.get("武器", {})
			if not weapon_value is Dictionary or weapon_value.is_empty():
				return "需要先装备武器"
			if effect in ["repair_oil", "war_god_oil"]:
				return _use_weapon_repair_oil_item(index, effect == "war_god_oil")
		if _consume_inventory_index(index):
			scroll_requested.emit(item_name)
			return "使用：%s" % item_name
		return "物品数量不足"
	if kind != "consumable":
		return "%s当前不可使用" % item_name
	if item_name == "祝福油":
		var weapon_value: Variant = equipment.get("武器", {})
		if not weapon_value is Dictionary or weapon_value.is_empty():
			return "需要先装备武器"
	if effect == "temporary_stat_buff":
		var profile: Variant = item.get("effectProfile", {})
		if not profile is Dictionary:
			return "%s效果配置无效" % item_name
		var buff_result := apply_temporary_item_buff(item_name, profile)
		if not bool(buff_result.get("ok", false)):
			return str(buff_result.get("reason", "增益效果应用失败"))
		if _consume_inventory_index(index):
			recalculate_stats()
			return "使用：%s" % item_name
		return "物品数量不足"
	if _consume_inventory_index(index):
		consumable_requested.emit(item_name)
		return "使用：%s" % item_name
	return "物品数量不足"


func _use_weapon_repair_oil_item(index: int, full_repair: bool) -> String:
	if index < 0 or index >= inventory.size() or not inventory[index] is Dictionary or (inventory[index] as Dictionary).is_empty():
		return "物品数量不足"
	var weapon_value: Variant = equipment.get("武器", {})
	if not weapon_value is Dictionary or weapon_value.is_empty():
		return "需要先装备武器"
	_ensure_raw_durability_fields(weapon_value)
	var current := int(weapon_value.get("durability_raw", 0))
	var maximum := maxi(1, int(weapon_value.get("max_durability_raw", 1)))
	if current >= maximum:
		return "武器无需修复"
	var inventory_before := inventory.duplicate(true)
	var equipment_before := equipment.duplicate(true)
	var record: Dictionary = inventory[index]
	var count := maxi(1, int(record.get("count", 1)))
	if count <= 1:
		_clear_inventory_slot(inventory, index)
	else:
		record["count"] = count - 1
	_apply_weapon_repair_oil_without_commit(weapon_value, full_repair)
	if not _commit_save():
		inventory = inventory_before
		equipment = equipment_before
		recalculate_stats(false)
		return "修复油存档失败，物品和装备均未改变"
	inventory_changed.emit()
	equipment_changed.emit()
	profile_changed.emit()
	return "武器已完全修复" if full_repair else "武器已部分修复"


func apply_weapon_repair_oil(full_repair: bool) -> String:
	var weapon_value: Variant = equipment.get("武器", {})
	if not weapon_value is Dictionary or weapon_value.is_empty():
		return "需要先装备武器"
	_ensure_raw_durability_fields(weapon_value)
	var current := int(weapon_value.get("durability_raw", 0))
	var maximum := maxi(1, int(weapon_value.get("max_durability_raw", 1)))
	if current >= maximum:
		return "武器无需修复"
	var equipment_before := equipment.duplicate(true)
	_apply_weapon_repair_oil_without_commit(weapon_value, full_repair)
	if not _commit_save():
		equipment = equipment_before
		recalculate_stats(false)
		return "武器修复存档失败"
	equipment_changed.emit()
	profile_changed.emit()
	return "武器已完全修复" if full_repair else "武器已部分修复"


func _apply_weapon_repair_oil_without_commit(
	weapon_value: Dictionary, full_repair: bool
) -> void:
	var current := int(weapon_value.get("durability_raw", 0))
	var maximum := maxi(1, int(weapon_value.get("max_durability_raw", 1)))
	if full_repair:
		weapon_value["durability_raw"] = maximum
	else:
		# ObjBase uses raw durability units: ordinary repair oil restores at most
		# 5000 while reducing the maximum by missing durability / 30.
		var maximum_loss := maxi(0, int((maximum - current) / 30))
		maximum = maxi(1, maximum - maximum_loss)
		weapon_value["max_durability_raw"] = maximum
		weapon_value["durability_raw"] = mini(maximum, current + 5000)
	_sync_durability_compatibility_fields(weapon_value)
	recalculate_stats(false)


func _make_item_instance(item_name: String, catalog_item: Dictionary, instance_serial := -1) -> Dictionary:
	var instance := {"name": item_name, "count": 1}
	if str(catalog_item.get("kind", "")) == "equipment":
		var maximum := maxi(1, int(catalog_item.get("maxDurability", 1)))
		instance["durability"] = maximum
		instance["max_durability"] = maximum
		instance["durability_raw"] = maximum * DURABILITY_RAW_UNITS_PER_DISPLAY
		instance["max_durability_raw"] = maximum * DURABILITY_RAW_UNITS_PER_DISPLAY
		instance["durability_contract_id"] = DURABILITY_CONTRACT_ID
		if instance_serial < 0:
			_item_instance_serial += 1
			instance_serial = _item_instance_serial
		instance["instance_id"] = "%d_%d" % [Time.get_ticks_usec(), instance_serial]
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


## Atomic death settlement: quest progress and experience share one save.
## This is intentionally separate from the legacy single-purpose entry points.
func record_kill_and_experience(monster_name: String, amount: int) -> Dictionary:
	var quests_before := quest_states.duplicate(true)
	var experience_before := experience
	var level_before := level
	var quest_changed := false
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
			progress[objective_name] = mini(int(requirements[objective_name]), int(progress.get(objective_name, 0)) + 1)
			quest_changed = true
		state["progress"] = progress
		if _quest_objectives_complete(quest, state):
			state["status"] = "ready"
	var gained := maxi(0, amount)
	if gained > 0:
		experience += gained
		while experience >= experience_to_next_level():
			experience -= experience_to_next_level()
			level += 1
			recalculate_stats(false)
	if not quest_changed and gained <= 0:
		return {"success": true, "quest_changed": false, "experience_gained": 0}
	if not _commit_save():
		quest_states = quests_before
		experience = experience_before
		level = level_before
		recalculate_stats(false)
		return {"success": false, "quest_changed": false, "experience_gained": 0, "reason": "save_failed"}
	if quest_changed:
		if test_mode:
			_test_transaction_counters["quest_signals"] = int(_test_transaction_counters.get("quest_signals", 0)) + 1
		quests_changed.emit()
	if gained > 0:
		if test_mode:
			_test_transaction_counters["profile_signals"] = int(_test_transaction_counters.get("profile_signals", 0)) + 1
		profile_changed.emit()
	return {"success": true, "quest_changed": quest_changed, "experience_gained": gained}


## Applies the formal-death experience penalty exactly as a level-local
## experience mutation.  Experience is the current level's progress (see
## add_experience), so no level or threshold is changed here.  floor() gives
## deterministic integer behaviour for 0/1/9/10/101 and the clamp prevents
## negative values.  The caller must invoke this once per formal death.
func apply_death_experience_penalty() -> int:
	var current_experience := maxi(0, int(experience))
	var lost := mini(current_experience, int(floor(float(current_experience) * 0.10)))
	if lost <= 0:
		return 0
	experience = current_experience - lost
	profile_changed.emit()
	_commit_save()
	return lost


func experience_to_next_level() -> int:
	if GameData != null and not GameData.service_reference.is_empty():
		return GameData.service_exp_to_next_level(level)
	if VERIFIED_EXPERIENCE_1_TO_22.has(level):
		return int(VERIFIED_EXPERIENCE_1_TO_22[level])
	# 23级以上尚未完成多源核验，暂沿用保守占位曲线并在验收报告中标记。
	return 300000 + maxi(0, level - 22) * 100000


func equip_inventory_index(index: int, preferred_slot := "") -> String:
	if index < 0 or index >= inventory.size() or not inventory[index] is Dictionary or (inventory[index] as Dictionary).is_empty():
		return "请先选择物品"
	var inventory_record: Dictionary = inventory[index]
	var item_name := str(inventory_record.get("name", ""))
	var item := GameData.get_item(item_name)
	if item.is_empty():
		return "%s不是可穿戴装备" % item_name
	var category := str(item.get("category", ""))
	var explicit_slot := (
		not preferred_slot.is_empty()
		and preferred_slot in _slots_for_category(category)
	)
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
	var inventory_before := inventory.duplicate(true)
	var equipment_before := equipment.duplicate(true)
	var inventory_after := inventory.duplicate(true)
	inventory_after[index] = {}
	if previous is Dictionary and not previous.is_empty():
		var return_preview := _build_receive_result_for_record(previous, inventory_after)
		if not bool(return_preview.get("success", false)):
			return str(return_preview.get("message", INVENTORY_SLOT_REJECTION))
		# Preserve the selected slot during a replacement. Besides keeping the
		# inventory deterministic, this prevents the old item from jumping to the
		# tail and breaking the two-slot equip-cycle contract.
		inventory_after[index] = previous.duplicate(true)
	elif not previous is Dictionary and not str(previous).is_empty():
		var legacy_previous := _make_item_instance(str(previous), GameData.get_item_record(str(previous)))
		var return_preview := _build_receive_result_for_record(legacy_previous, inventory_after)
		if not bool(return_preview.get("success", false)):
			return str(return_preview.get("message", INVENTORY_SLOT_REJECTION))
		inventory_after[index] = legacy_previous
	else:
		_trim_inventory_empty_tail(inventory_after)
	inventory = inventory_after
	equipment[slot] = inventory_record.duplicate(true)
	recalculate_stats()
	if not explicit_slot:
		_advance_equip_cycle_cursor(category, slot)
	inventory_changed.emit()
	equipment_changed.emit()
	profile_changed.emit()
	if not _commit_save():
		inventory = inventory_before
		equipment = equipment_before
		recalculate_stats()
		return "装备存档失败，装备和背包均未改变"
	return "已装备：%s" % item_name


func unequip_slot(slot: String) -> String:
	if slot not in EQUIPMENT_SLOTS:
		return "无效装备槽"
	var equipped_value: Variant = equipment.get(slot, {})
	if not equipped_value is Dictionary or equipped_value.is_empty():
		return "%s为空" % slot
	var return_preview := _build_receive_result_for_record(equipped_value, inventory)
	if not bool(return_preview.get("success", false)):
		return str(return_preview.get("message", INVENTORY_SLOT_REJECTION))
	var inventory_before := inventory.duplicate(true)
	var equipment_before := equipment.duplicate(true)
	inventory = (return_preview.get("inventory", inventory) as Array).duplicate(true)
	equipment[slot] = {}
	recalculate_stats()
	inventory_changed.emit()
	equipment_changed.emit()
	profile_changed.emit()
	if not _commit_save():
		inventory = inventory_before
		equipment = equipment_before
		recalculate_stats()
		return "卸装存档失败，装备和背包均未改变"
	return "已卸下：%s" % str(equipped_value.get("name", ""))


func learn_skill(skill_name: String, inventory_index := -1) -> String:
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
	if (
		inventory_index >= 0
		and inventory_index < inventory.size()
		and inventory[inventory_index] is Dictionary
		and str((inventory[inventory_index] as Dictionary).get("name", "")) == skill_name
	):
		_consume_inventory_index(inventory_index)
	else:
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


func abandon_quest(quest_id: String) -> Dictionary:
	var result := {
		"contract_id": QUEST_ABANDON_CONTRACT_ID,
		"quest_id": quest_id,
		"success": false,
		"message": "当前任务不能放弃。",
	}
	if not quest_states.has(quest_id):
		return result
	var state: Variant = quest_states.get(quest_id, {})
	if not state is Dictionary or str((state as Dictionary).get("status", "")) not in ["active", "ready"]:
		return result
	var states_before := quest_states.duplicate(true)
	quest_states.erase(quest_id)
	quests_changed.emit()
	if not _commit_save():
		quest_states = states_before
		quests_changed.emit()
		result["message"] = "任务存档失败，放弃操作已取消。"
		return result
	result["success"] = true
	result["message"] = "已放弃任务，当前进度已清除。"
	return result


func sort_warehouse() -> Dictionary:
	var result := {
		"contract_id": WAREHOUSE_SORT_CONTRACT_ID,
		"success": false,
		"message": "仓库整理失败。",
	}
	var legacy_test_memory := test_mode and not _shared_warehouse_test_isolation_enabled()
	if not legacy_test_memory and not _ensure_shared_warehouse_ready():
		result["message"] = "公共仓库不可用，已拒绝整理。"
		return result
	if warehouse_inventory.size() > WAREHOUSE_CAPACITY:
		result["message"] = "仓库数据超过容量，已拒绝整理以避免丢失物品。"
		return result
	var records: Array[Dictionary] = []
	for raw_record: Variant in warehouse_inventory:
		if raw_record is Dictionary and not (raw_record as Dictionary).is_empty():
			records.append((raw_record as Dictionary).duplicate(true))
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_name := str(a.get("name", ""))
		var b_name := str(b.get("name", ""))
		if a_name == b_name:
			return str(a.get("instance_id", "")) < str(b.get("instance_id", ""))
		return a_name < b_name
	)
	var warehouse_before := warehouse_inventory.duplicate(true)
	warehouse_inventory = []
	for record: Dictionary in records:
		warehouse_inventory.append(record)
	inventory_changed.emit()
	if not legacy_test_memory and not _write_shared_warehouse(warehouse_inventory):
		warehouse_inventory = warehouse_before
		inventory_changed.emit()
		result["message"] = "仓库存档失败，原有顺序已恢复。"
		return result
	result["success"] = true
	result["message"] = "仓库已整理，共%d件物品。" % records.size()
	return result


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
	var rewards: Dictionary = quest.get("rewards", {})
	var reward_items: Array = []
	for reward: Variant in rewards.get("items", []):
		if reward is Dictionary:
			reward_items.append(reward)
	var reward_preview := _build_receive_batch_result(reward_items, inventory)
	if not bool(reward_preview.get("success", false)):
		return str(reward_preview.get("message", "超过负重，无法领取任务奖励。"))
	var inventory_before := inventory.duplicate(true)
	var gold_before := gold
	var state_before := quest_states.duplicate(true)
	_apply_receive_result(reward_preview)
	state["status"] = "claimed"
	state["claimed_at_unix"] = int(Time.get_unix_time_from_system())
	gold = maxi(0, gold + int(rewards.get("gold", 0)))
	if not _commit_save():
		inventory = inventory_before
		gold = gold_before
		quest_states = state_before
		return "任务奖励存档失败，奖励未发放。"
	inventory_changed.emit()
	profile_changed.emit()
	quests_changed.emit()
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
			_place_inventory_record_in_first_free_slot(inventory, _make_item_instance(item_name, catalog_item))
		return
	for stack: Variant in inventory:
		if stack is Dictionary and stack.get("name", "") == item_name:
			stack["count"] = int(stack.get("count", 0)) + amount
			return
	_place_inventory_record_in_first_free_slot(inventory, {"name": item_name, "count": amount})


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


func recalculate_stats(emit_profile_change := true) -> void:
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
		"max_bag_weight": EquipmentRulesScript.max_bag_weight(profession, level),
		"bag_weight": inventory_weight(inventory),
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
		if equipped_value is Dictionary and not _has_positive_raw_durability(equipped_value):
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
		result["max_bag_weight"] = int(result.get("max_bag_weight", 0)) * 2
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
	_apply_temporary_item_stat_modifiers(result)
	computed_stats = result
	if emit_profile_change:
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
	var requested_main_pet_summon_id := ""
	match stable_skill_id:
		"taoist.summon_skeleton":
			requested_main_pet_summon_id = "skeleton"
		"taoist.summon_divine_beast":
			requested_main_pet_summon_id = "divine_beast"
	if not requested_main_pet_summon_id.is_empty():
		result["requested_main_pet_summon_id"] = requested_main_pet_summon_id
		result["active_main_pet_summon_ids"] = (
			_taoist_main_pet_runtime_state_slots().keys()
		)
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


## Weight is derived from the primary item catalog on every query. Currency
## records intentionally contribute zero so picking up gold never gets blocked
## by a full or legacy-overweight bag.
func inventory_weight(records: Array = inventory) -> int:
	var total := 0
	for raw_record: Variant in records:
		if not raw_record is Dictionary:
			continue
		var record: Dictionary = raw_record
		var item := GameData.get_item_record(str(record.get("name", "")))
		if item.is_empty() or str(item.get("kind", "")) == "currency":
			continue
		var unit_weight := maxi(0, int(item.get("weight", 0)))
		var count := maxi(1, int(record.get("count", 1)))
		if unit_weight > 0 and count > MAX_SAFE_WEIGHT / unit_weight:
			return MAX_SAFE_WEIGHT
		var contribution := unit_weight * count
		if total > MAX_SAFE_WEIGHT - contribution:
			return MAX_SAFE_WEIGHT
		total += contribution
	return total


func max_inventory_weight() -> int:
	var maximum := EquipmentRulesScript.max_bag_weight(profession, level)
	if _active_double_weight_effect():
		maximum *= 2
	return maximum


func _active_double_weight_effect() -> bool:
	for value: Variant in equipment.values():
		if not value is Dictionary or value.is_empty() or not _has_positive_raw_durability(value):
			continue
		var item := GameData.get_item_record(value)
		var special := EquipmentRulesScript.special_effect_for(item)
		if str(special.get("id", "")) == "double_weight" and bool(special.get("runtime", false)):
			return true
	return false


func _slots_for_category(category: String) -> Array[String]:
	match category:
		"武器": return ["武器"]
		"盔甲": return ["衣服"]
		"头盔": return ["头盔"]
		"项链": return ["项链"]
		"手镯": return ["左手镯", "右手镯"]
		"戒指": return ["左戒指", "右戒指"]
		"圣物": return ["圣物"]
		"徽章": return ["徽章"]
		_: return []


func _choose_equipment_slot(category: String, preferred_slot := "") -> String:
	var slots := _slots_for_category(category)
	if not preferred_slot.is_empty() and preferred_slot in slots:
		return preferred_slot
	for slot: String in slots:
		var value: Variant = equipment.get(slot, {})
		if value is Dictionary and value.is_empty():
			return slot
	if slots.is_empty():
		return ""
	var cursor_slot := str(equip_cycle_cursor.get(category, slots[0]))
	return cursor_slot if cursor_slot in slots else slots[0]


func _default_equip_cycle_cursor() -> Dictionary:
	return {"戒指": "左戒指", "手镯": "左手镯"}


func _normalized_equip_cycle_cursor(saved_value: Variant) -> Dictionary:
	var result := _default_equip_cycle_cursor()
	if saved_value is Dictionary:
		for category: String in result.keys():
			var saved_slot := str(saved_value.get(category, ""))
			if saved_slot in _slots_for_category(category):
				result[category] = saved_slot
	return result


func _advance_equip_cycle_cursor(category: String, equipped_slot: String) -> void:
	var slots := _slots_for_category(category)
	if slots.size() < 2:
		return
	var equipped_index := slots.find(equipped_slot)
	if equipped_index < 0:
		return
	equip_cycle_cursor[category] = slots[(equipped_index + 1) % slots.size()]


func _empty_equipment() -> Dictionary:
	var result := {}
	for slot: String in EQUIPMENT_SLOTS:
		result[slot] = {}
	return result


func _equipment_instance_from_saved(saved_value: Variant) -> Dictionary:
	if saved_value is Dictionary:
		var restored: Dictionary = saved_value.duplicate(true)
		_ensure_raw_durability_fields(restored)
		return restored
	if not str(saved_value).is_empty():
		return _make_item_instance(str(saved_value), GameData.get_item_record(str(saved_value)))
	return {}


func _ensure_raw_durability_fields(instance: Dictionary) -> bool:
	if instance.is_empty():
		return false
	var catalog := GameData.get_item_record(instance)
	var catalog_maximum := maxi(1, int(catalog.get("maxDurability", 1)))
	var migrated := false
	if not instance.has("max_durability_raw"):
		instance["max_durability_raw"] = (
			maxi(1, int(instance.get("max_durability", catalog_maximum)))
			* DURABILITY_RAW_UNITS_PER_DISPLAY
		)
		migrated = true
	var maximum_raw := maxi(1, int(instance.get("max_durability_raw", 1)))
	instance["max_durability_raw"] = maximum_raw
	if not instance.has("durability_raw"):
		instance["durability_raw"] = (
			clampi(
				int(instance.get("durability", instance.get("max_durability", catalog_maximum))),
				0,
				maxi(1, int(instance.get("max_durability", catalog_maximum)))
			)
			* DURABILITY_RAW_UNITS_PER_DISPLAY
		)
		migrated = true
	instance["durability_raw"] = clampi(
		int(instance.get("durability_raw", 0)), 0, maximum_raw
	)
	instance["durability_contract_id"] = DURABILITY_CONTRACT_ID
	_sync_durability_compatibility_fields(instance)
	return migrated


func _adopt_legacy_durability_compatibility_override(instance: Dictionary) -> void:
	if not instance.has("durability_raw") or not instance.has("max_durability_raw"):
		return
	var maximum_raw := maxi(1, int(instance.get("max_durability_raw", 1)))
	var current_raw := clampi(int(instance.get("durability_raw", 0)), 0, maximum_raw)
	var expected_maximum := maxi(
		1,
		int(ceil(float(maximum_raw) / float(DURABILITY_RAW_UNITS_PER_DISPLAY)))
	)
	var expected_current := (
		0
		if current_raw <= 0
		else int(ceil(float(current_raw) / float(DURABILITY_RAW_UNITS_PER_DISPLAY)))
	)
	var display_maximum := maxi(1, int(instance.get("max_durability", expected_maximum)))
	var display_current := clampi(
		int(instance.get("durability", expected_current)), 0, display_maximum
	)
	if display_maximum != expected_maximum:
		maximum_raw = display_maximum * DURABILITY_RAW_UNITS_PER_DISPLAY
		instance["max_durability_raw"] = maximum_raw
	if display_current != expected_current:
		instance["durability_raw"] = mini(
			maximum_raw, display_current * DURABILITY_RAW_UNITS_PER_DISPLAY
		)


func _sync_durability_compatibility_fields(instance: Dictionary) -> void:
	var maximum_raw := maxi(1, int(instance.get("max_durability_raw", 1)))
	var current_raw := clampi(int(instance.get("durability_raw", 0)), 0, maximum_raw)
	instance["max_durability_raw"] = maximum_raw
	instance["durability_raw"] = current_raw
	# Existing UI and pricing contracts remain whole display points. Ceiling is
	# intentional: a positive raw remainder is usable and must not look broken.
	instance["max_durability"] = maxi(
		1,
		int(ceil(float(maximum_raw) / float(DURABILITY_RAW_UNITS_PER_DISPLAY)))
	)
	instance["durability"] = (
		0
		if current_raw <= 0
		else int(ceil(float(current_raw) / float(DURABILITY_RAW_UNITS_PER_DISPLAY)))
	)


func _has_positive_raw_durability(instance: Dictionary) -> bool:
	_adopt_legacy_durability_compatibility_override(instance)
	_ensure_raw_durability_fields(instance)
	return int(instance.get("durability_raw", 0)) > 0


func _migrate_item_collection_durability(records: Array) -> bool:
	var migrated := false
	for value: Variant in records:
		if value is Dictionary and not value.is_empty():
			var catalog := GameData.get_item_record(value)
			if str(catalog.get("kind", "")) == "equipment":
				migrated = _ensure_raw_durability_fields(value) or migrated
	return migrated


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
	_damage_equipment_durability_raw(
		slot,
		maxi(0, amount) * DURABILITY_RAW_UNITS_PER_DISPLAY,
		true
	)


func _damage_equipment_durability_raw(
	slot: String,
	amount_raw: int,
	commit_individually := false
) -> bool:
	var equipped: Variant = equipment.get(slot, {})
	if not equipped is Dictionary or equipped.is_empty():
		return false
	_ensure_raw_durability_fields(equipped)
	var old_value := int(equipped.get("durability_raw", 0))
	var new_value := maxi(0, old_value - maxi(0, amount_raw))
	if new_value == old_value:
		return false
	equipped["durability_raw"] = new_value
	_sync_durability_compatibility_fields(equipped)
	if commit_individually:
		if new_value == 0:
			recalculate_stats(false)
		equipment_changed.emit()
		profile_changed.emit()
		_commit_save()
	return true


func apply_durability_event(event_id: String, context := {}) -> Dictionary:
	var result := {
		"contract_id": DURABILITY_CONTRACT_ID,
		"event_id": event_id,
		"applied": false,
		"changed_slots": {},
		"raw_loss": 0,
		"signal_batches": 0,
		"save_commits": 0,
		"extension_policy": DURABILITY_INCOMING_EXTENSION_POLICY,
	}
	if not context is Dictionary:
		result["reason"] = "invalid_context"
		return result
	var event_context: Dictionary = context
	if str(event_context.get("damage_type", "physical")) != "physical":
		result["reason"] = "non_physical"
		return result
	if int(event_context.get("damage", 1)) <= 0:
		result["reason"] = "non_positive_damage"
		return result
	var equipment_before := equipment.duplicate(true)
	var crossed_zero := false
	match event_id:
		DURABILITY_EVENT_WEAPON_PHYSICAL_HIT:
			if not bool(event_context.get("confirmed_hit", false)):
				result["reason"] = "unconfirmed_hit"
				return result
			var weapon: Variant = equipment.get("武器", {})
			if not weapon is Dictionary or weapon.is_empty():
				result["reason"] = "weapon_missing"
				return result
			_ensure_raw_durability_fields(weapon)
			var weapon_roll := _durability_roll(event_context, "weapon_roll", 0, 4)
			var weapon_strong := _weapon_strong(weapon, event_context)
			var weapon_loss := maxi(0, weapon_roll + 2 - weapon_strong)
			result["raw_loss"] = weapon_loss
			result["weapon_roll"] = weapon_roll
			result["weapon_strong"] = weapon_strong
			if weapon_loss > 0:
				var old_weapon_raw := int(weapon.get("durability_raw", 0))
				if _damage_equipment_durability_raw("武器", weapon_loss):
					(result["changed_slots"] as Dictionary)["武器"] = weapon_loss
					crossed_zero = old_weapon_raw > 0 and int(weapon.get("durability_raw", 0)) == 0
		DURABILITY_EVENT_INCOMING_PHYSICAL_STRUCK:
			if not bool(event_context.get("causes_struck", true)):
				result["reason"] = "not_struck_damage"
				return result
			var incoming_roll := _durability_roll(event_context, "armor_roll", 0, 9)
			var incoming_loss := incoming_roll + 5
			if bool(event_context.get("red_poison", false)):
				incoming_loss = maxi(1, roundi(float(incoming_loss) * 1.2))
			result["raw_loss"] = incoming_loss
			result["armor_roll"] = incoming_roll
			var armor: Variant = equipment.get("衣服", {})
			if armor is Dictionary and not armor.is_empty():
				_ensure_raw_durability_fields(armor)
				var old_armor_raw := int(armor.get("durability_raw", 0))
				if _damage_equipment_durability_raw("衣服", incoming_loss):
					(result["changed_slots"] as Dictionary)["衣服"] = incoming_loss
					crossed_zero = crossed_zero or (
						old_armor_raw > 0 and int(armor.get("durability_raw", 0)) == 0
					)
			var slot_rolls: Dictionary = event_context.get("slot_rolls", {})
			for slot: String in EQUIPMENT_SLOTS:
				var slot_roll := (
					clampi(int(slot_rolls.get(slot, 0)), 0, 7)
					if slot_rolls.has(slot)
					else _durability_roll(event_context, "", 0, 7)
				)
				if slot_roll != 0:
					continue
				var equipped: Variant = equipment.get(slot, {})
				if not equipped is Dictionary or equipped.is_empty():
					continue
				_ensure_raw_durability_fields(equipped)
				var old_slot_raw := int(equipped.get("durability_raw", 0))
				if _damage_equipment_durability_raw(slot, incoming_loss):
					var previous_loss := int((result["changed_slots"] as Dictionary).get(slot, 0))
					(result["changed_slots"] as Dictionary)[slot] = previous_loss + incoming_loss
					crossed_zero = crossed_zero or (
						old_slot_raw > 0 and int(equipped.get("durability_raw", 0)) == 0
					)
		_:
			result["reason"] = "unknown_event"
			return result
	if (result["changed_slots"] as Dictionary).is_empty():
		result["reason"] = "no_durability_change"
		return result
	result["save_commits"] = 1
	if crossed_zero:
		recalculate_stats(false)
	result["save_committed"] = _commit_save()
	if not bool(result["save_committed"]):
		equipment = equipment_before
		recalculate_stats(false)
		result["changed_slots"] = {}
		result["raw_loss"] = 0
		result["rolled_back"] = true
		result["reason"] = "save_failed"
		return result
	equipment_changed.emit()
	profile_changed.emit()
	result["signal_batches"] = 1
	durability_event_commit_count += 1
	result["applied"] = true
	result["reason"] = ""
	return result


func _durability_roll(context: Dictionary, key: String, minimum: int, maximum: int) -> int:
	if not key.is_empty() and context.has(key):
		return clampi(int(context.get(key, minimum)), minimum, maximum)
	var rng_value: Variant = context.get("rng", null)
	if rng_value is RandomNumberGenerator:
		return (rng_value as RandomNumberGenerator).randi_range(minimum, maximum)
	return _durability_rng.randi_range(minimum, maximum)


func _weapon_strong(weapon: Dictionary, context: Dictionary) -> int:
	if context.has("weapon_strong"):
		return maxi(0, int(context.get("weapon_strong", 0)))
	for key: String in ["weapon_strong", "WeaponStrong", "strong", "Strong"]:
		if weapon.has(key):
			return maxi(0, int(weapon.get(key, 0)))
	var catalog := GameData.get_item_record(weapon)
	for key: String in ["weaponStrong", "WeaponStrong", "strong", "Strong"]:
		if catalog.has(key):
			return maxi(0, int(catalog.get(key, 0)))
	return 0


func repair_cost(context := {}) -> int:
	var authoritative_context := _authoritative_merchant_context(context)
	if not PricingServiceScript.merchant_supports_full_equipment_repair(authoritative_context):
		return 0
	return int(_repair_plan(authoritative_context).get("total_price", 0))


func _repair_plan(context := {}) -> Dictionary:
	if not PricingServiceScript.merchant_supports_full_equipment_repair(context):
		return {"valid": false, "total_price": 0, "slots": [], "entries": []}
	var priority_slots := PricingServiceScript.repair_batch_slot_order()
	if priority_slots != EQUIPMENT_SLOTS:
		return {"valid": false, "total_price": 0, "slots": [], "entries": []}
	var total := 0
	var slots: Array[String] = []
	var entries: Array[Dictionary] = []
	for slot: String in priority_slots:
		var equipped: Variant = equipment.get(slot, {})
		if not equipped is Dictionary or equipped.is_empty():
			continue
		# Planning must never mutate live equipment. Raw durability is authoritative;
		# display compatibility fields are not allowed to overwrite it here.
		var quote_instance: Dictionary = (equipped as Dictionary).duplicate(true)
		_ensure_raw_durability_fields(quote_instance)
		var quote := PricingServiceScript.quote_repair(
			GameData.get_item_price_record(quote_instance),
			GameData.get_item_record(quote_instance),
			quote_instance,
			context
		)
		var quoted_cost := int(quote.get("total_price", 0))
		if not bool(quote.get("valid", false)) or quoted_cost <= 0:
			continue
		total += quoted_cost
		slots.append(slot)
		entries.append({"slot": slot, "quote": quote})
	return {
		"valid": true,
		"contract_id": "gameplay.repair.batch_all_equipment.v1",
		"total_price": total,
		"slots": slots,
		"entries": entries,
	}


func repair_all_equipment(context := {}) -> String:
	context = _authoritative_merchant_context(context)
	if not PricingServiceScript.merchant_supports_full_equipment_repair(context):
		return "该商人不提供维修服务"
	var plan := _repair_plan(context)
	if not bool(plan.get("valid", false)):
		return "维修规则无效，未改变装备和金币"
	var full_cost := int(plan.get("total_price", 0))
	if full_cost <= 0:
		return "装备无需维修"
	var equipment_before := equipment.duplicate(true)
	var gold_before := gold
	var remaining_gold := gold
	var spent := 0
	var repaired_slots := 0
	for raw_entry: Variant in plan.get("entries", []):
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var slot := str(entry.get("slot", ""))
		var equipped: Variant = equipment.get(slot, {})
		if not equipped is Dictionary or equipped.is_empty():
			continue
		_ensure_raw_durability_fields(equipped)
		var price_record := GameData.get_item_price_record(equipped)
		var catalog := GameData.get_item_record(equipped)
		var current_raw := int(equipped.get("durability_raw", 0))
		var maximum_raw := maxi(1, int(equipped.get("max_durability_raw", 1)))
		var missing_raw := maximum_raw - clampi(current_raw, 0, maximum_raw)
		if missing_raw <= 0 or remaining_gold <= 0:
			continue
		var planned_quote: Dictionary = entry.get("quote", {})
		var chosen_quote: Dictionary = planned_quote.duplicate(true)
		if not bool(chosen_quote.get("valid", false)):
			continue
		if int(chosen_quote.get("total_price", 0)) > remaining_gold:
			chosen_quote = _maximum_affordable_repair_raw_quote(
				price_record, catalog, equipped, missing_raw, remaining_gold, context
			)
		if not bool(chosen_quote.get("valid", false)):
			continue
		var slot_cost := int(chosen_quote.get("total_price", 0))
		var target_raw := int(chosen_quote.get("formula_snapshot", {}).get("target_durability_raw", current_raw))
		if slot_cost <= 0 or slot_cost > remaining_gold or target_raw <= current_raw:
			continue
		equipped["durability_raw"] = mini(maximum_raw, target_raw)
		_sync_durability_compatibility_fields(equipped)
		remaining_gold -= slot_cost
		spent += slot_cost
		repaired_slots += 1
	if repaired_slots <= 0:
		return "金币不足，未能维修任何装备"
	gold = remaining_gold
	recalculate_stats()
	if not _commit_save():
		equipment = equipment_before
		gold = gold_before
		recalculate_stats()
		return "维修存档失败，装备和金币均未改变"
	equipment_changed.emit()
	profile_changed.emit()
	if spent >= full_cost:
		return "全部装备维修完成，花费%d金币" % spent
	return "金币不足，已优先维修%d件装备，花费%d金币" % [repaired_slots, spent]


func _authoritative_merchant_context(context: Variant) -> Dictionary:
	if not context is Dictionary:
		return {}
	var merchant_id := str((context as Dictionary).get("merchant_id", ""))
	if merchant_id.is_empty():
		return (context as Dictionary).duplicate(true)
	var authoritative := GameData.merchant_context_by_id(merchant_id)
	if not authoritative.is_empty():
		return authoritative
	# An unknown merchant id must never fall back to PricingService's legacy
	# context defaults, otherwise a forged request could regain repair access.
	return {
		"merchant_id": merchant_id,
		"types": [],
		"supports_repair": false,
	}


func _maximum_affordable_repair_raw_quote(
	price_record: Dictionary,
	catalog: Dictionary,
	instance: Dictionary,
	maximum_amount_raw: int,
	budget: int,
	context: Dictionary
) -> Dictionary:
	var low := 1
	var high := maxi(0, maximum_amount_raw)
	var best: Dictionary = {}
	while low <= high:
		var amount := int((low + high) / 2)
		var quote := PricingServiceScript.quote_repair_raw_delta(
			price_record, catalog, instance, amount, context
		)
		if bool(quote.get("valid", false)) and int(quote.get("total_price", 0)) <= budget:
			best = quote
			low = amount + 1
		else:
			high = amount - 1
	return best


func _profile_path(profile_id: String) -> String:
	return "%s/%s.json" % [profile_directory, profile_id]


func _read_json_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "valid": false, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"exists": true, "valid": false, "data": {}}
	var serialized := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var parse_error := parser.parse(serialized)
	var parsed: Variant = parser.data if parse_error == OK else null
	return {
		"exists": true,
		"valid": parsed is Dictionary,
		"data": parsed if parsed is Dictionary else {},
	}


func _restore_json_backup(path: String) -> Dictionary:
	var backup := path + ".bak"
	var backup_document := _read_json_document(backup)
	if not bool(backup_document.get("valid", false)):
		return {
			"success": false,
			"reason": "backup_missing_or_invalid",
			"data": {},
		}
	var temporary := path + ".tmp"
	var corrupt := path + ".corrupt.tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"success": false, "reason": "backup_restore_temp_open_failed", "data": {}}
	file.store_string(JSON.stringify(backup_document.get("data", {}), "\t"))
	file.flush()
	file.close()
	if not bool(_read_json_document(temporary).get("valid", false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return {"success": false, "reason": "backup_restore_temp_invalid", "data": {}}
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temp := ProjectSettings.globalize_path(temporary)
	var absolute_corrupt := ProjectSettings.globalize_path(corrupt)
	if FileAccess.file_exists(corrupt):
		if DirAccess.remove_absolute(absolute_corrupt) != OK:
			DirAccess.remove_absolute(absolute_temp)
			return {"success": false, "reason": "backup_restore_cleanup_failed", "data": {}}
	var moved_corrupt := false
	if FileAccess.file_exists(path):
		if DirAccess.rename_absolute(absolute_path, absolute_corrupt) != OK:
			DirAccess.remove_absolute(absolute_temp)
			return {"success": false, "reason": "backup_restore_main_move_failed", "data": {}}
		moved_corrupt = true
	if DirAccess.rename_absolute(absolute_temp, absolute_path) != OK:
		if moved_corrupt:
			DirAccess.rename_absolute(absolute_corrupt, absolute_path)
		return {"success": false, "reason": "backup_restore_promote_failed", "data": {}}
	if moved_corrupt and FileAccess.file_exists(corrupt):
		DirAccess.remove_absolute(absolute_corrupt)
	return {
		"success": true,
		"reason": "recovered_from_backup",
		"data": backup_document.get("data", {}).duplicate(true),
	}


func _read_json_with_status(path: String) -> Dictionary:
	var primary := _read_json_document(path)
	if bool(primary.get("valid", false)):
		return {
			"success": true,
			"reason": "primary",
			"data": primary.get("data", {}).duplicate(true),
		}
	var recovered := _restore_json_backup(path)
	if bool(recovered.get("success", false)):
		return recovered
	return {
		"success": false,
		"reason": (
			"primary_missing"
			if not bool(primary.get("exists", false))
			else "primary_invalid"
		),
		"data": {},
	}


func _read_json(path: String) -> Dictionary:
	return _read_json_with_status(path).get("data", {})


func _write_json_atomic(path: String, data: Dictionary) -> bool:
	if test_mode and _test_force_atomic_write_failure:
		return false
	var temporary := path + ".tmp"
	var backup := path + ".bak"
	var corrupt := path + ".corrupt.tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	# Never move the current profile until the complete temporary document has
	# been reparsed successfully. This keeps a failed/partial write fail-closed.
	if not bool(_read_json_document(temporary).get("valid", false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return false
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temp := ProjectSettings.globalize_path(temporary)
	var absolute_backup := ProjectSettings.globalize_path(backup)
	var absolute_corrupt := ProjectSettings.globalize_path(corrupt)
	var current_document := _read_json_document(path)
	var moved_valid_main := false
	var moved_corrupt_main := false
	if bool(current_document.get("exists", false)):
		if bool(current_document.get("valid", false)):
			if (
				FileAccess.file_exists(backup)
				and DirAccess.remove_absolute(absolute_backup) != OK
			):
				DirAccess.remove_absolute(absolute_temp)
				return false
			if DirAccess.rename_absolute(absolute_path, absolute_backup) != OK:
				DirAccess.remove_absolute(absolute_temp)
				return false
			moved_valid_main = true
		else:
			# A corrupt main must never replace a valid .bak.
			if (
				FileAccess.file_exists(corrupt)
				and DirAccess.remove_absolute(absolute_corrupt) != OK
			):
				DirAccess.remove_absolute(absolute_temp)
				return false
			if DirAccess.rename_absolute(absolute_path, absolute_corrupt) != OK:
				DirAccess.remove_absolute(absolute_temp)
				return false
			moved_corrupt_main = true
	var promote_result := DirAccess.rename_absolute(absolute_temp, absolute_path)
	if promote_result != OK:
		if moved_valid_main:
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		elif moved_corrupt_main:
			DirAccess.rename_absolute(absolute_corrupt, absolute_path)
		return false
	if moved_corrupt_main and FileAccess.file_exists(corrupt):
		DirAccess.remove_absolute(absolute_corrupt)
	return bool(_read_json_document(path).get("valid", false))


func _shared_warehouse_empty_document() -> Dictionary:
	return {
		"schema_version": SHARED_WAREHOUSE_SCHEMA_VERSION,
		"contract_id": SHARED_WAREHOUSE_CONTRACT_ID,
		"revision": 0,
		"warehouse_inventory": [],
		"legacy_migration": {
			"completed": false,
			"contract_id": SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID,
			"sources": {},
		},
	}


func _shared_digest(value: Variant) -> String:
	# Hash the JSON round-trip representation so integers/floats and typed Arrays
	# compare identically after an atomic file is parsed back from disk.
	var normalized: Variant = JSON.parse_string(JSON.stringify(value))
	return JSON.stringify(normalized).sha256_text()


func _shared_warehouse_read_inventory() -> Array:
	var document := _read_json(shared_warehouse_path)
	var records: Variant = document.get("warehouse_inventory", null)
	return (records as Array).duplicate(true) if records is Array else []


func _shared_warehouse_test_isolation_enabled() -> bool:
	return (
		profile_directory != PROFILE_DIRECTORY
		and shared_warehouse_path != SHARED_WAREHOUSE_DEFAULT_PATH
		and shared_warehouse_transaction_log_path != SHARED_WAREHOUSE_TRANSACTION_LOG_PATH
	)


func _valid_profile_storage_id(profile_id: String) -> bool:
	return (
		not profile_id.is_empty()
		and not profile_id.contains("/")
		and not profile_id.contains("\\")
		and profile_id not in [".", ".."]
	)


func _profile_ids_for_shared_warehouse() -> Dictionary:
	var ids: Dictionary = {}
	var index_status := _read_json_with_status(profile_index_path)
	if FileAccess.file_exists(profile_index_path) and not bool(index_status.get("success", false)):
		return {"ok": false, "ids": []}
	var profiles: Variant = (index_status.get("data", {}) as Dictionary).get("profiles", [])
	if not profiles is Array:
		return {"ok": false, "ids": []}
	for entry: Variant in profiles:
		if not entry is Dictionary:
			return {"ok": false, "ids": []}
		var profile_id := str((entry as Dictionary).get("id", ""))
		if not _valid_profile_storage_id(profile_id) or ids.has(profile_id):
			return {"ok": false, "ids": []}
		ids[profile_id] = true
	var directory := DirAccess.open(profile_directory)
	if directory != null:
		for file_name: String in directory.get_files():
			if not file_name.ends_with(".json"):
				continue
			var profile_id := file_name.left(file_name.length() - 5)
			if not _valid_profile_storage_id(profile_id):
				return {"ok": false, "ids": []}
			ids[profile_id] = true
	var sorted_ids: Array = ids.keys()
	sorted_ids.sort()
	return {"ok": true, "ids": sorted_ids}


func _legacy_warehouse_source(document: Dictionary) -> Dictionary:
	var legacy: Variant = document.get("warehouse_inventory", [])
	if not legacy is Array or (legacy as Array).size() > WAREHOUSE_CAPACITY:
		return {"ok": false, "records": []}
	var records: Array = []
	for raw_record: Variant in legacy:
		if not raw_record is Dictionary:
			return {"ok": false, "records": []}
		if not (raw_record as Dictionary).is_empty():
			records.append((raw_record as Dictionary).duplicate(true))
	return {"ok": true, "records": records}


func _validate_shared_warehouse_document(document: Dictionary) -> bool:
	if int(document.get("schema_version", 0)) != SHARED_WAREHOUSE_SCHEMA_VERSION:
		return false
	if str(document.get("contract_id", "")) != SHARED_WAREHOUSE_CONTRACT_ID:
		return false
	var records: Variant = document.get("warehouse_inventory", null)
	if not records is Array or (records as Array).size() > WAREHOUSE_CAPACITY:
		return false
	for record: Variant in records:
		if not record is Dictionary:
			return false
	# The warehouse is a fixed 5 x 100-slot surface. Empty dictionaries are
	# valid holes and must survive page-specific deposits and non-tail withdraws.
	var ledger: Variant = document.get("legacy_migration", null)
	if not ledger is Dictionary or not bool((ledger as Dictionary).get("completed", false)):
		return false
	if str((ledger as Dictionary).get("contract_id", "")) != SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID:
		return false
	var sources: Variant = (ledger as Dictionary).get("sources", null)
	if not sources is Dictionary:
		return false
	for raw_profile_id: Variant in (sources as Dictionary).keys():
		var profile_id := str(raw_profile_id)
		var ledger_source: Variant = (sources as Dictionary).get(profile_id, null)
		if not _valid_profile_storage_id(profile_id) or not ledger_source is Dictionary:
			return false
		if (
			not bool((ledger_source as Dictionary).get("complete", false))
			or str((ledger_source as Dictionary).get("contract_id", "")) != SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID
			or str((ledger_source as Dictionary).get("digest", "")).is_empty()
			or int((ledger_source as Dictionary).get("occupied_count", -1)) < 0
		):
			return false
		var source_path := _profile_path(profile_id)
		if not FileAccess.file_exists(source_path):
			continue # deletion is allowed; the shared ledger remains authoritative.
		var source := _read_json_with_status(source_path)
		if not bool(source.get("success", false)):
			return false
		var legacy: Variant = (source.get("data", {}) as Dictionary).get("warehouse_inventory", null)
		if legacy == null:
			continue # migrated sources may be naturally retired by a later save.
		var normalized := _legacy_warehouse_source(source.get("data", {}) as Dictionary)
		if not bool(normalized.get("ok", false)):
			return false
		var occupied: Array = normalized.get("records", [])
		if (
			_shared_digest(occupied) != str((ledger_source as Dictionary).get("digest", ""))
			or occupied.size() != int((ledger_source as Dictionary).get("occupied_count", -1))
		):
			return false
	var profile_ids_result := _profile_ids_for_shared_warehouse()
	if not bool(profile_ids_result.get("ok", false)):
		return false
	for raw_profile_id: Variant in profile_ids_result.get("ids", []):
		var profile_id := str(raw_profile_id)
		var source := _read_json_with_status(_profile_path(profile_id))
		if not bool(source.get("success", false)):
			return false
		var source_document: Dictionary = source.get("data", {})
		if source_document.has("warehouse_inventory") and not (sources as Dictionary).has(profile_id):
			return false
	return true


func _occupied_records(records: Array) -> Array:
	var result: Array = []
	for record: Variant in records:
		if record is Dictionary and not (record as Dictionary).is_empty():
			result.append((record as Dictionary).duplicate(true))
	return result


func _initialize_shared_warehouse() -> bool:
	var existing := _read_json_document(shared_warehouse_path)
	if bool(existing.get("exists", false)):
		if not bool(existing.get("valid", false)) or not _validate_shared_warehouse_document(existing.get("data", {})):
			_shared_warehouse_initialized = false
			return false
		warehouse_inventory = _shared_warehouse_read_inventory()
		_shared_warehouse_initialized = true
		return true
	var profile_ids_result := _profile_ids_for_shared_warehouse()
	if not bool(profile_ids_result.get("ok", false)):
		_shared_warehouse_initialized = false
		return false
	var merged: Array = []
	var sources: Dictionary = {}
	for raw_profile_id: Variant in profile_ids_result.get("ids", []):
		var profile_id := str(raw_profile_id)
		var source := _read_json_with_status(_profile_path(profile_id))
		if not bool(source.get("success", false)):
			_shared_warehouse_initialized = false
			return false
		var normalized := _legacy_warehouse_source(source.get("data", {}) as Dictionary)
		if not bool(normalized.get("ok", false)):
			_shared_warehouse_initialized = false
			return false
		var occupied: Array = normalized.get("records", [])
		for record: Variant in occupied:
			merged.append(record.duplicate(true))
			if merged.size() > WAREHOUSE_CAPACITY:
				_shared_warehouse_initialized = false
				return false
		sources[profile_id] = {
			"digest": _shared_digest(occupied),
			"occupied_count": occupied.size(),
			"complete": true,
			"contract_id": SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID,
		}
	var document := _shared_warehouse_empty_document()
	document["revision"] = 1
	document["warehouse_inventory"] = merged
	(document["legacy_migration"] as Dictionary)["completed"] = true
	(document["legacy_migration"] as Dictionary)["sources"] = sources
	if not _write_shared_warehouse_document_atomic(document):
		_shared_warehouse_initialized = false
		return false
	_shared_warehouse_initialized = true
	warehouse_inventory = merged.duplicate(true)
	return true


func _ensure_shared_warehouse_ready() -> bool:
	if _warehouse_transaction_locked:
		return false
	if profile_directory != PROFILE_DIRECTORY and not _shared_warehouse_test_isolation_enabled():
		return true
	if _shared_warehouse_initialized:
		return true
	return _initialize_shared_warehouse()


func _revalidate_shared_warehouse_authority() -> bool:
	var current := _read_json_document(shared_warehouse_path)
	return (
		bool(current.get("valid", false))
		and _validate_shared_warehouse_document(current.get("data", {}))
	)


func _recover_shared_warehouse_transaction() -> void:
	var log_document := _read_json_document(shared_warehouse_transaction_log_path)
	if not bool(log_document.get("exists", false)):
		return
	if not bool(log_document.get("valid", false)):
		_warehouse_transaction_locked = true
		return
	var log: Dictionary = log_document.get("data", {})
	if (
		str(log.get("contract_id", "")) != WAREHOUSE_TRANSFER_CONTRACT_ID
		or str(log.get("state", "")) != "PREPARED"
		or not log.get("profile_path", "") is String
	):
		_warehouse_transaction_locked = true
		return
	var profile_id := str(log.get("profile_id", ""))
	var profile_path := str(log.get("profile_path", ""))
	var before_profile: Variant = log.get("before_profile", null)
	var after_profile: Variant = log.get("after_profile", null)
	var before_shared: Variant = log.get("before_shared", null)
	var after_shared: Variant = log.get("after_shared", null)
	if (
		not _valid_profile_storage_id(profile_id)
		or profile_path != _profile_path(profile_id)
		or not before_profile is Dictionary
		or not after_profile is Dictionary
		or not before_shared is Dictionary
		or not after_shared is Dictionary
		or str((before_profile as Dictionary).get("profile_id", "")) != profile_id
		or str((after_profile as Dictionary).get("profile_id", "")) != profile_id
		or _shared_digest(before_profile) != str(log.get("before_profile_hash", ""))
		or _shared_digest(after_profile) != str(log.get("after_profile_hash", ""))
		or _shared_digest(before_shared) != str(log.get("before_shared_hash", ""))
		or _shared_digest(after_shared) != str(log.get("after_shared_hash", ""))
	):
		_warehouse_transaction_locked = true
		return
	var current_profile := _read_json(profile_path)
	var current_shared := _read_json(shared_warehouse_path)
	if _shared_digest(current_profile) == _shared_digest(after_profile) and _shared_digest(current_shared) == _shared_digest(after_shared):
		_warehouse_transaction_locked = not _remove_persistence_file(shared_warehouse_transaction_log_path)
		_shared_warehouse_initialized = false
		return
	var profile_restored := _write_json_atomic(profile_path, before_profile as Dictionary)
	var shared_restored := _write_json_atomic(shared_warehouse_path, before_shared as Dictionary)
	if (
		not profile_restored
		or not shared_restored
		or _shared_digest(_read_json(profile_path)) != _shared_digest(before_profile)
		or _shared_digest(_read_json(shared_warehouse_path)) != _shared_digest(before_shared)
	):
		_warehouse_transaction_locked = true
		return
	_warehouse_transaction_locked = not _remove_persistence_file(shared_warehouse_transaction_log_path)
	_shared_warehouse_initialized = false


func _remove_persistence_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func _shared_document_for_records(records: Array) -> Dictionary:
	var current := _read_json(shared_warehouse_path)
	var document := _shared_warehouse_empty_document()
	document["revision"] = int(current.get("revision", 0)) + 1
	document["warehouse_inventory"] = records.duplicate(true)
	document["legacy_migration"] = current.get("legacy_migration", {
		"completed": true,
		"contract_id": SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID,
		"sources": {},
	})
	return document


func _write_shared_warehouse_document_atomic(document: Dictionary) -> bool:
	if test_mode and _test_fail_shared_write:
		return false
	return _write_json_atomic(shared_warehouse_path, document)


func _write_shared_warehouse(records: Array) -> bool:
	# Legacy unit tests exercise the in-memory authority without booting the
	# profile service.  Never let those fixtures touch production user:// data.
	if (
		profile_directory != PROFILE_DIRECTORY
		and not _shared_warehouse_test_isolation_enabled()
		and not _shared_warehouse_initialized
	):
		return true
	if records.size() > WAREHOUSE_CAPACITY:
		return false
	var current := _read_json(shared_warehouse_path)
	if not _validate_shared_warehouse_document(current):
		return false
	var revision := int(current.get("revision", 0)) + 1
	var migration: Dictionary = current.get("legacy_migration", {
		"completed": true,
		"contract_id": SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID,
		"sources": {},
	})
	var document := _shared_warehouse_empty_document()
	document["revision"] = revision
	document["warehouse_inventory"] = records.duplicate(true)
	document["legacy_migration"] = migration.duplicate(true)
	return _write_shared_warehouse_document_atomic(document)


func save_game() -> bool:
	if _warehouse_transaction_locked and not _persistence_transaction_in_progress:
		last_save_result = {"contract_id": SAVE_RESULT_CONTRACT_ID, "success": false, "reason": "warehouse_transaction_locked"}
		return false
	if active_profile_id.is_empty():
		last_save_result = {
			"contract_id": SAVE_RESULT_CONTRACT_ID,
			"success": false,
			"reason": "active_profile_missing",
		}
		return false
	_refresh_taoist_main_pet_runtime_states_for_save()
	_ensure_skill_progression_matches_legacy()
	var profile_path := _profile_path(active_profile_id)
	var legacy_isolated_profile_fixture := (
		profile_directory != PROFILE_DIRECTORY
		and not _shared_warehouse_test_isolation_enabled()
	)
	if legacy_isolated_profile_fixture:
		# Existing save tests redirect the profile root; never touch production
		# shared storage from such an isolated fixture.
		_shared_warehouse_initialized = false
	elif not _shared_warehouse_initialized and not _initialize_shared_warehouse():
		last_save_result = {
			"contract_id": SAVE_RESULT_CONTRACT_ID,
			"success": false,
			"reason": "shared_warehouse_unavailable",
		}
		return false
	if (
		not legacy_isolated_profile_fixture
		and FileAccess.file_exists(profile_path)
		and _read_json(profile_path).has("warehouse_inventory")
		and not _revalidate_shared_warehouse_authority()
	):
		last_save_result = {
			"contract_id": SAVE_RESULT_CONTRACT_ID,
			"success": false,
			"reason": "shared_warehouse_legacy_source_changed",
		}
		return false
	var payload := {
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
		"warehouse_storage_contract_id": SHARED_WAREHOUSE_CONTRACT_ID,
		"equipment": equipment,
		"learned_skills": learned_skills,
		"skill_progression": _skill_progression.snapshot(),
		"quick_slots": quick_slots,
		"quick_item_slots": quick_item_slots,
		"equip_cycle_cursor": equip_cycle_cursor,
		"skill_button_assignments": skill_button_assignments_snapshot(),
		"warrior_runtime_state": warrior_runtime_state,
		"quest_states": quest_states,
		"world_monster_respawn_state": world_monster_respawn_state.duplicate(true),
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
	}
	if legacy_isolated_profile_fixture:
		payload["warehouse_inventory"] = warehouse_inventory
	if not _taoist_main_pet_runtime_state_slots().is_empty():
		payload["taoist_main_pet_runtime_states"] = (
			taoist_main_pet_runtime_states.duplicate(true)
		)
	if not _write_json_atomic(profile_path, payload):
		last_save_result = {
			"contract_id": SAVE_RESULT_CONTRACT_ID,
			"success": false,
			"reason": "atomic_profile_write_failed",
			"path": profile_path,
		}
		return false
	var index_updated := _update_profile_index()
	last_save_result = {
		"contract_id": SAVE_RESULT_CONTRACT_ID,
		"success": true,
		"reason": "",
		"path": profile_path,
		"profile_index_updated": index_updated,
	}
	if not index_updated:
		push_warning("角色存档已写入，但角色索引更新失败：%s" % active_profile_id)
	return true


## Debug-lab export of the complete active character document.  This uses the
## same schema and normalization path as production saves so a device snapshot
## can be edited on the host and applied back without a parallel save format.
func device_lab_active_save_document() -> Dictionary:
	if not OS.is_debug_build() and not test_mode:
		return {}
	if active_profile_id.is_empty():
		return {}
	# Persist volatile runtime fields before exporting the experiment state.
	if not save_game():
		return {}
	return _read_json(_profile_path(active_profile_id)).duplicate(true)


## Atomically replaces the active experimental character and immediately
## reloads every normalized runtime field.  A failed write/load restores the
## complete previous document before returning.
func device_lab_apply_save_document(document: Dictionary) -> Dictionary:
	var result := {
		"ok": false,
		"contractId": DEVICE_LAB_SAVE_CONTRACT_ID,
		"profileId": active_profile_id,
		"rolledBack": false,
		"error": "",
	}
	if not OS.is_debug_build() and not test_mode:
		result["error"] = "debug_only"
		return result
	var validation := _validate_device_lab_save_document(document)
	if not bool(validation.get("ok", false)):
		result["error"] = str(validation.get("error", "invalid_document"))
		return result
	var path := _profile_path(active_profile_id)
	var previous := _read_json(path).duplicate(true)
	if previous.is_empty():
		result["error"] = "previous_save_missing"
		return result
	var character_document := document.duplicate(true)
	# DeviceLab edits one character only. An older exported character document
	# may still carry the former private warehouse field; it must never replace
	# or recreate the account-wide public warehouse authority.
	character_document.erase("warehouse_inventory")
	if not _write_json_atomic(path, character_document):
		result["error"] = "atomic_write_failed"
		return result
	load_save()
	if not bool(last_load_result.get("success", false)):
		result["rolledBack"] = _write_json_atomic(path, previous)
		if bool(result["rolledBack"]):
			load_save()
		result["error"] = "reload_failed"
		return result
	_emit_device_lab_state_changed()
	result["ok"] = true
	result["saveVersion"] = SAVE_VERSION
	result["inventoryCount"] = inventory_occupied_count()
	result["warehouseCount"] = warehouse_occupied_count()
	return result


func deposit_to_warehouse(inventory_index: int, warehouse_slot: int) -> Dictionary:
	var result := deposit_to_warehouse_batch([inventory_index], [warehouse_slot])
	if bool(result.get("complete", false)):
		result["message"] = "已存入仓库。"
	return result


## Moves one selected batch with one two-file persistence transaction.
func deposit_to_warehouse_batch(inventory_indices: Array, warehouse_slots: Array) -> Dictionary:
	var requested := inventory_indices.size()
	var result := {
		"contract_id": WAREHOUSE_TRANSFER_CONTRACT_ID,
		"operation": "deposit",
		"success": false,
		"complete": false,
		"requested": requested,
		"transferred": 0,
		"remaining": requested,
		"completed_source_indices": [],
		"completed_warehouse_slots": [],
		"message": "仓库存取失败。",
	}
	if not (test_mode and not _shared_warehouse_test_isolation_enabled()) and not _ensure_shared_warehouse_ready():
		result["message"] = "公共仓库不可用，物品未改变。"
		return result
	if requested <= 0:
		result["message"] = "存入位置无效。"
		return result
	var normalized_indices: Array[int] = []
	var seen_indices: Dictionary = {}
	for raw_index: Variant in inventory_indices:
		var inventory_index := int(raw_index)
		if (
			inventory_index < 0
			or inventory_index >= inventory.size()
			or not _inventory_slot_is_occupied(inventory[inventory_index])
			or seen_indices.has(inventory_index)
		):
			result["message"] = "存入位置无效。"
			return result
		seen_indices[inventory_index] = true
		normalized_indices.append(inventory_index)
	var transfer_count := mini(requested, warehouse_slots.size())
	if transfer_count <= 0:
		result["message"] = "当前仓库页空间不足。"
		return result
	var normalized_slots: Array[int] = []
	var seen_slots: Dictionary = {}
	for slot_offset in range(transfer_count):
		var warehouse_slot := int(warehouse_slots[slot_offset])
		if (
			warehouse_slot < 0
			or warehouse_slot >= WAREHOUSE_CAPACITY
			or seen_slots.has(warehouse_slot)
			or (
				warehouse_slot < warehouse_inventory.size()
				and _inventory_slot_is_occupied(warehouse_inventory[warehouse_slot])
			)
		):
			result["message"] = "仓库位置已被占用。"
			return result
		seen_slots[warehouse_slot] = true
		normalized_slots.append(warehouse_slot)
	var inventory_before := inventory.duplicate(true)
	var warehouse_before := warehouse_inventory.duplicate(true)
	var working_inventory := inventory_before.duplicate(true)
	var working_warehouse := warehouse_before.duplicate(true)
	var records_to_move: Array = []
	for source_offset in range(transfer_count):
		var source_index := normalized_indices[source_offset]
		var source_record: Variant = working_inventory[source_index]
		records_to_move.append(source_record.duplicate(true) if source_record is Dictionary else source_record)
	for target_slot: int in normalized_slots:
		while working_warehouse.size() <= target_slot:
			working_warehouse.append({})
	for move_offset in range(transfer_count):
		working_warehouse[normalized_slots[move_offset]] = records_to_move[move_offset]
	for source_offset in range(transfer_count - 1, -1, -1):
		_clear_inventory_slot(working_inventory, normalized_indices[source_offset])
	inventory = working_inventory
	warehouse_inventory = working_warehouse
	if not _warehouse_transfer_commit(inventory_before, warehouse_before):
		inventory = inventory_before
		warehouse_inventory = warehouse_before
		result["message"] = "仓库存档失败，物品未改变。"
		return result
	inventory_changed.emit()
	result["success"] = true
	result["complete"] = transfer_count == requested
	result["transferred"] = transfer_count
	result["remaining"] = requested - transfer_count
	result["completed_source_indices"] = normalized_indices.slice(0, transfer_count)
	result["completed_warehouse_slots"] = normalized_slots.duplicate()
	result["message"] = (
		"已存入仓库，共%d件物品。" % transfer_count
		if transfer_count == requested
		else "已存入%d件；当前仓库页空间不足。" % transfer_count
	)
	return result


func withdraw_from_warehouse(warehouse_slot: int) -> Dictionary:
	var result := withdraw_from_warehouse_batch([warehouse_slot])
	if bool(result.get("complete", false)):
		result["message"] = "已取出仓库物品。"
	return result


## Moves the largest valid prefix with one two-file persistence transaction.
func withdraw_from_warehouse_batch(warehouse_slots: Array) -> Dictionary:
	var requested := warehouse_slots.size()
	var result := {
		"contract_id": WAREHOUSE_TRANSFER_CONTRACT_ID,
		"operation": "withdraw",
		"success": false,
		"complete": false,
		"requested": requested,
		"transferred": 0,
		"remaining": requested,
		"completed_warehouse_slots": [],
		"message": "仓库存取失败。",
	}
	if not (test_mode and not _shared_warehouse_test_isolation_enabled()) and not _ensure_shared_warehouse_ready():
		result["message"] = "公共仓库不可用，物品未改变。"
		return result
	if requested <= 0:
		result["message"] = "仓库位置无效。"
		return result
	var normalized_slots: Array[int] = []
	var seen_slots: Dictionary = {}
	for raw_slot: Variant in warehouse_slots:
		var warehouse_slot := int(raw_slot)
		if (
			warehouse_slot < 0
			or warehouse_slot >= warehouse_inventory.size()
			or not _inventory_slot_is_occupied(warehouse_inventory[warehouse_slot])
			or seen_slots.has(warehouse_slot)
		):
			result["message"] = "仓库位置无效。"
			return result
		seen_slots[warehouse_slot] = true
		normalized_slots.append(warehouse_slot)
	var inventory_before := inventory.duplicate(true)
	var warehouse_before := warehouse_inventory.duplicate(true)
	var working_inventory := inventory_before.duplicate(true)
	var working_warehouse := warehouse_before.duplicate(true)
	var completed_slots: Array[int] = []
	var failure_message := ""
	var failure_reason := ""
	for warehouse_slot: int in normalized_slots:
		var record: Dictionary = working_warehouse[warehouse_slot]
		var preview := _build_receive_result_for_record(record, working_inventory)
		if not bool(preview.get("success", false)):
			failure_message = str(preview.get("message", INVENTORY_WEIGHT_REJECTION))
			failure_reason = str(preview.get("reason", "rejected"))
			break
		working_inventory = (preview.get("inventory", working_inventory) as Array).duplicate(true)
		working_warehouse[warehouse_slot] = {}
		completed_slots.append(warehouse_slot)
	if completed_slots.is_empty():
		result["message"] = failure_message if not failure_message.is_empty() else "仓库存取失败。"
		if not failure_reason.is_empty():
			result["reason"] = failure_reason
		return result
	while not working_warehouse.is_empty() and not _inventory_slot_is_occupied(working_warehouse.back()):
		working_warehouse.pop_back()
	inventory = working_inventory
	warehouse_inventory = working_warehouse
	if not _warehouse_transfer_commit(inventory_before, warehouse_before):
		inventory = inventory_before
		warehouse_inventory = warehouse_before
		result["message"] = "仓库存档失败，物品未改变。"
		return result
	inventory_changed.emit()
	result["success"] = true
	result["complete"] = completed_slots.size() == requested
	result["transferred"] = completed_slots.size()
	result["remaining"] = requested - completed_slots.size()
	result["completed_warehouse_slots"] = completed_slots.duplicate()
	if not failure_reason.is_empty():
		result["reason"] = failure_reason
	result["message"] = (
		"已取出仓库物品，共%d件。" % completed_slots.size()
		if completed_slots.size() == requested
		else "已取出%d件；%s" % [completed_slots.size(), failure_message]
	)
	return result


func _trim_warehouse_empty_tail() -> void:
	while not warehouse_inventory.is_empty():
		var tail: Variant = warehouse_inventory.back()
		if tail is Dictionary and not tail.is_empty():
			break
		warehouse_inventory.pop_back()


func _validate_device_lab_save_document(document: Dictionary) -> Dictionary:
	if document.is_empty():
		return {"ok": false, "error": "empty_document"}
	if active_profile_id.is_empty() or str(document.get("profile_id", "")) != active_profile_id:
		return {"ok": false, "error": "profile_id"}
	if int(document.get("save_version", 0)) != SAVE_VERSION:
		return {"ok": false, "error": "save_version"}
	if not document.get("inventory", null) is Array or (document.get("inventory") as Array).size() > 100:
		return {"ok": false, "error": "inventory"}
	if not document.get("equipment", null) is Dictionary:
		return {"ok": false, "error": "equipment"}
	if int(document.get("level", 0)) < 1 or int(document.get("level", 0)) > 255:
		return {"ok": false, "error": "level"}
	if not ProfessionRules.is_valid_profession(str(document.get("profession", ""))):
		return {"ok": false, "error": "profession"}
	if str(document.get("gender", "")) not in ["男", "女"]:
		return {"ok": false, "error": "gender"}
	for required_object: String in ["learned_skills", "quest_states"]:
		if not document.get(required_object, null) is Dictionary:
			return {"ok": false, "error": required_object}
	return {"ok": true}


func _emit_device_lab_state_changed() -> void:
	profile_changed.emit()
	profession_changed.emit(profession)
	inventory_changed.emit()
	equipment_changed.emit()
	skills_changed.emit()
	quests_changed.emit()
	quick_slots_changed.emit({"source": "device_lab"})
	quick_item_slots_changed.emit({"source": "device_lab"})


func load_save() -> void:
	_recover_shared_warehouse_transaction()
	var load_path := _profile_path(active_profile_id) if not active_profile_id.is_empty() else SAVE_PATH
	var load_result := _read_json_with_status(load_path)
	last_load_result = {
		"contract_id": SAVE_RESULT_CONTRACT_ID,
		"success": bool(load_result.get("success", false)),
		"reason": str(load_result.get("reason", "")),
		"path": load_path,
	}
	if not bool(load_result.get("success", false)):
		reset_progress(false)
		return
	var parsed: Dictionary = load_result.get("data", {})
	var legacy_isolated_profile_fixture := (
		profile_directory != PROFILE_DIRECTORY
		and not _shared_warehouse_test_isolation_enabled()
	)
	if legacy_isolated_profile_fixture:
		# Isolated profile fixtures retain their historical in-memory warehouse
		# behavior and are forbidden from migrating production account data.
		warehouse_inventory = (parsed.get("warehouse_inventory", []) as Array).duplicate(true) if parsed.get("warehouse_inventory", []) is Array else []
	elif not _shared_warehouse_initialized and not _initialize_shared_warehouse():
		last_load_result["success"] = false
		last_load_result["reason"] = "shared_warehouse_unavailable"
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
	var loaded_inventory: Variant = parsed.get("inventory", [])
	inventory = (loaded_inventory as Array).duplicate(true) if loaded_inventory is Array else []
	if not legacy_isolated_profile_fixture:
		warehouse_inventory = _shared_warehouse_read_inventory()
	_trim_inventory_empty_tail()
	var saved_equipment: Dictionary = parsed.get("equipment", {})
	equipment = migrate_equipment_slots(saved_equipment)
	_migrate_item_collection_durability(inventory)
	_migrate_item_collection_durability(warehouse_inventory)
	learned_skills = parsed.get("learned_skills", {})
	var progression_load: Dictionary = _skill_progression.load_snapshot(
		parsed.get("skill_progression", learned_skills)
	)
	if bool(progression_load.get("migrated_legacy", false)) or not parsed.has("skill_progression"):
		_sync_legacy_learned_skills_from_progression()
	var saved_slots: Array = parsed.get("quick_slots", ["", "", "", ""])
	_restore_skill_button_assignments(parsed.get("skill_button_assignments", {}), saved_slots)
	quick_item_slots = _normalized_quick_item_slots(parsed.get("quick_item_slots", null))
	equip_cycle_cursor = _normalized_equip_cycle_cursor(parsed.get("equip_cycle_cursor", {}))
	warrior_runtime_state = _normalized_warrior_runtime_state(parsed.get("warrior_runtime_state", {}))
	if parsed.has("taoist_main_pet_runtime_states"):
		var loaded_main_pet_states := _normalized_taoist_main_pet_runtime_states(
			parsed.get("taoist_main_pet_runtime_states", {})
		)
		taoist_main_pet_runtime_states = (
			loaded_main_pet_states
			if not loaded_main_pet_states.is_empty()
			else _empty_taoist_main_pet_runtime_states()
		)
	else:
		# Compatibility for the short-lived singular save emitted by the faulty
		# device build. Migrate its typed snapshot into the matching plural slot;
		# every subsequent save writes only the plural field.
		var legacy_main_pet := _normalized_taoist_main_pet_runtime_state(
			parsed.get("taoist_main_pet_runtime_state", {})
		)
		taoist_main_pet_runtime_states = _empty_taoist_main_pet_runtime_states()
		if not legacy_main_pet.is_empty():
			var migrated_slots := (
				taoist_main_pet_runtime_states["slots"] as Dictionary
			)
			migrated_slots[str(legacy_main_pet.get("summon_id", ""))] = (
				legacy_main_pet
			)
	quest_states = parsed.get("quest_states", {})
	world_monster_respawn_state = (
		WorldMonsterRespawnStateScript.normalize_snapshot(
			parsed.get("world_monster_respawn_state", {})
		)
	)
	saved_map_id = int(parsed.get("map_id", 910001))
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


func monster_respawn_state_for_restore() -> Dictionary:
	return world_monster_respawn_state.duplicate(true)


func monster_respawn_entry(
	runtime_map_id: int,
	spawn_slot_id: String
) -> Dictionary:
	return WorldMonsterRespawnStateScript.entry_for(
		world_monster_respawn_state,
		runtime_map_id,
		spawn_slot_id
	)


func mark_monster_respawn_dead(
	runtime_map_id: int,
	spawn_slot_id: String,
	monster_id: int,
	policy_id: String,
	respawn_at_unix: float
) -> bool:
	var next_state := WorldMonsterRespawnStateScript.with_deadline(
		world_monster_respawn_state,
		runtime_map_id,
		spawn_slot_id,
		monster_id,
		policy_id,
		respawn_at_unix
	)
	if WorldMonsterRespawnStateScript.entry_for(
		next_state,
		runtime_map_id,
		spawn_slot_id
	).is_empty():
		return false
	world_monster_respawn_state = next_state
	return true


func clear_monster_respawn_slot(
	runtime_map_id: int,
	spawn_slot_id: String
) -> void:
	world_monster_respawn_state = WorldMonsterRespawnStateScript.without_slot(
		world_monster_respawn_state,
		runtime_map_id,
		spawn_slot_id
	)


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


func is_quick_item_candidate(item_name: String) -> bool:
	if item_name.is_empty():
		return false
	var item := GameData.get_item_record(item_name)
	if item.is_empty():
		return false
	if str(item.get("kind", "")) not in ["skill_book", "consumable", "scroll"]:
		return false
	return item.get("usable", true) != false


func quick_item_slots_snapshot() -> Array:
	return quick_item_slots.duplicate()


func quick_item_slot_name(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= quick_item_slots.size():
		return ""
	return quick_item_slots[slot_index]


func assign_quick_item_slot(index: int, item_name: String) -> Dictionary:
	if index < 0 or index >= QUICK_ITEM_SLOT_COUNT:
		return {
			"ok": false,
			"contract_id": QUICK_ITEM_SLOTS_CONTRACT_ID,
			"slot_index": index,
			"item_name": item_name,
			"reason": "slot_index_out_of_range",
			"message": "快捷物品槽位无效",
		}
	if not item_name.is_empty() and not is_quick_item_candidate(item_name):
		return {
			"ok": false,
			"contract_id": QUICK_ITEM_SLOTS_CONTRACT_ID,
			"slot_index": index,
			"item_name": item_name,
			"reason": "not_quick_item_candidate",
			"message": "%s不能绑定到快捷物品槽" % item_name,
		}
	if not item_name.is_empty() and not has_item(item_name):
		return {
			"ok": false,
			"contract_id": QUICK_ITEM_SLOTS_CONTRACT_ID,
			"slot_index": index,
			"item_name": item_name,
			"reason": "no_inventory",
			"message": "背包中没有%s" % item_name,
		}
	var previous := quick_item_slots[index]
	quick_item_slots[index] = item_name
	var change := {
		"contract_id": QUICK_ITEM_SLOTS_CONTRACT_ID,
		"slot_index": index,
		"item_name": item_name,
		"previous_item_name": previous,
		"slots": quick_item_slots.duplicate(),
	}
	quick_item_slots_changed.emit(change.duplicate(true))
	profile_changed.emit()
	_commit_save()
	var message := "快捷物品槽%d已清空" % (index + 1) if item_name.is_empty() else (
		"已将%s绑定到快捷物品槽%d" % [item_name, index + 1]
	)
	return {
		"ok": true,
		"contract_id": QUICK_ITEM_SLOTS_CONTRACT_ID,
		"slot_index": index,
		"item_name": item_name,
		"change": change,
		"message": message,
	}


func use_quick_item_slot(index: int, expected_item_name := "") -> Dictionary:
	if index < 0 or index >= QUICK_ITEM_SLOT_COUNT:
		return {
			"ok": false,
			"contract_id": QUICK_ITEM_SLOTS_CONTRACT_ID,
			"slot_index": index,
			"item_name": "",
			"reason": "slot_index_out_of_range",
			"message": "快捷物品槽位无效",
		}
	var bound_name := quick_item_slots[index]
	if bound_name.is_empty():
		return {
			"ok": false,
			"contract_id": QUICK_ITEM_SLOTS_CONTRACT_ID,
			"slot_index": index,
			"item_name": "",
			"reason": "slot_empty",
			"message": "快捷物品槽%d为空" % (index + 1),
		}
	if not expected_item_name.is_empty() and expected_item_name != bound_name:
		return {
			"ok": false,
			"contract_id": QUICK_ITEM_SLOTS_CONTRACT_ID,
			"slot_index": index,
			"item_name": bound_name,
			"expected_item_name": expected_item_name,
			"reason": "expected_name_mismatch",
			"message": "快捷物品槽已变更，请重试",
		}
	# Always re-scan by the bound name; never cache or reuse an old inventory index.
	var inventory_index := _inventory_index_by_item_name(bound_name)
	if inventory_index < 0:
		return {
			"ok": false,
			"contract_id": QUICK_ITEM_SLOTS_CONTRACT_ID,
			"slot_index": index,
			"item_name": bound_name,
			"reason": "no_inventory",
			"message": "背包中没有%s" % bound_name,
		}
	var before_count := item_count(bound_name)
	var use_result := use_inventory_index(inventory_index)
	var ok := item_count(bound_name) < before_count
	var item := GameData.get_item_record(bound_name)
	var kind := str(item.get("kind", ""))
	return {
		"ok": ok,
		"contract_id": QUICK_ITEM_SLOTS_CONTRACT_ID,
		"slot_index": index,
		"item_name": bound_name,
		"kind": kind,
		"message": use_result,
		"reason": "use_failed" if not ok else "used",
	}


func _normalized_quick_item_slots(value: Variant) -> Array[String]:
	var result: Array[String] = []
	var source: Array = value if value is Array else []
	for index in range(QUICK_ITEM_SLOT_COUNT):
		var slot_value: Variant = source[index] if index < source.size() else null
		var item_name := str(slot_value) if slot_value is String else ""
		result.append(item_name if is_quick_item_candidate(item_name) else "")
	return result


func _inventory_index_by_item_name(item_name: String) -> int:
	for index in range(inventory.size()):
		if str(inventory[index].get("name", "")) == item_name:
			return index
	return -1


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


func configure_taoist_main_pets_persistence_provider(provider: Callable) -> void:
	_taoist_main_pets_persistence_provider = provider


func clear_taoist_main_pets_persistence_provider() -> void:
	_taoist_main_pets_persistence_provider = Callable()


func apply_taoist_main_pet_runtime_states(states: Dictionary) -> bool:
	var normalized := _normalized_taoist_main_pet_runtime_states(states)
	if (
		normalized.is_empty()
		or str(normalized.get("contract_id", ""))
		!= TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID
	):
		return false
	taoist_main_pet_runtime_states = normalized
	return true


func clear_taoist_main_pet_runtime_state(summon_id: String) -> void:
	if summon_id not in ["skeleton", "divine_beast"]:
		return
	var slots := _taoist_main_pet_runtime_state_slots()
	slots.erase(summon_id)
	taoist_main_pet_runtime_states = {
		"contract_id": TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID,
		"slots": slots,
	}


func taoist_main_pet_runtime_states_for_restore() -> Dictionary:
	return taoist_main_pet_runtime_states.duplicate(true)


func taoist_main_pet_runtime_state_for_restore(summon_id: String) -> Dictionary:
	var slots := _taoist_main_pet_runtime_state_slots()
	var snapshot: Variant = slots.get(summon_id, {})
	return (snapshot as Dictionary).duplicate(true) if snapshot is Dictionary else {}


func _refresh_taoist_main_pet_runtime_states_for_save() -> void:
	if not _taoist_main_pets_persistence_provider.is_valid():
		return
	var captured: Variant = _taoist_main_pets_persistence_provider.call()
	if not captured is Dictionary:
		return
	# The live provider is authoritative. Invalid/corrupt captured state fails
	# closed to an empty two-slot document rather than retaining stale pets.
	var normalized := _normalized_taoist_main_pet_runtime_states(
		captured
	)
	taoist_main_pet_runtime_states = (
		normalized
		if not normalized.is_empty()
		else _empty_taoist_main_pet_runtime_states()
	)


func _empty_taoist_main_pet_runtime_states() -> Dictionary:
	return {
		"contract_id": TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID,
		"slots": {},
	}


func _taoist_main_pet_runtime_state_slots() -> Dictionary:
	var slots: Variant = taoist_main_pet_runtime_states.get("slots", {})
	return (slots as Dictionary).duplicate(true) if slots is Dictionary else {}


func _normalized_taoist_main_pet_runtime_states(states: Variant) -> Dictionary:
	if not states is Dictionary:
		return {}
	var source := states as Dictionary
	if (
		str(source.get("contract_id", ""))
		!= TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID
	):
		return {}
	var raw_slots: Variant = source.get("slots", {})
	if not raw_slots is Dictionary:
		return {}
	var result := _empty_taoist_main_pet_runtime_states()
	var slots := result["slots"] as Dictionary
	for summon_id: String in ["skeleton", "divine_beast"]:
		var normalized := _normalized_taoist_main_pet_runtime_state(
			(raw_slots as Dictionary).get(summon_id, {})
		)
		if (
			not normalized.is_empty()
			and str(normalized.get("summon_id", "")) == summon_id
		):
			slots[summon_id] = normalized
	return result


func _normalized_taoist_main_pet_runtime_state(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary:
		return {}
	var source := snapshot as Dictionary
	if (
		str(source.get("contract_id", ""))
		!= TAOIST_MAIN_PET_PERSISTENCE_CONTRACT_ID
		or not bool(source.get("alive", false))
	):
		return {}
	var summon_id := str(source.get("summon_id", ""))
	var skill_id := str(source.get("skill_id", ""))
	if (
		(summon_id == "skeleton" and skill_id != "taoist.summon_skeleton")
		or (
			summon_id == "divine_beast"
			and skill_id != "taoist.summon_divine_beast"
		)
		or summon_id not in ["skeleton", "divine_beast"]
	):
		return {}
	var runtime_state := str(source.get("runtime_state", ""))
	if runtime_state not in [
		"FOLLOW_OWNER",
		"ACQUIRE_TARGET",
		"CHASE_TARGET",
		"ATTACK_TARGET",
		"RETURN_TO_OWNER",
	]:
		return {}
	var skill_rank := int(source.get("skill_rank", -1))
	var owner_level := int(source.get("owner_level", 0))
	var current_hp := int(source.get("current_hp", 0))
	var max_hp := int(source.get("max_hp", 0))
	var remaining_lifetime := float(source.get("remaining_lifetime", 0.0))
	var summon_exp_level := int(source.get("summon_exp_level", -1))
	var maximum_pet_level := int(source.get("maximum_pet_level", -1))
	var pet_growth_exp := int(source.get("pet_growth_exp", -1))
	if (
		skill_rank < 0
		or skill_rank > 7
		or owner_level <= 0
		or current_hp <= 0
		or max_hp <= 0
		or current_hp > max_hp
		or not is_finite(remaining_lifetime)
		or remaining_lifetime <= 0.0
		or summon_exp_level < 0
		or summon_exp_level > 7
		or maximum_pet_level < summon_exp_level
		or maximum_pet_level > 7
		or pet_growth_exp < 0
	):
		return {}
	return source.duplicate(true)


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
	var previous_map_id := saved_map_id
	var previous_position := saved_position
	var previous_ground_position_gu := saved_ground_position_gu
	var previous_ground_position_gu_valid := saved_ground_position_gu_valid
	saved_map_id = home_map_id
	saved_position = home_screen_position_px
	if home_ground_position_gu is Vector2:
		saved_ground_position_gu = home_ground_position_gu
		saved_ground_position_gu_valid = true
	else:
		saved_ground_position_gu = Vector2.ZERO
		saved_ground_position_gu_valid = false
	if save_game():
		return true
	# The safe-location record is one transaction in memory and on disk. A
	# failed write must not leave a fake successful Home location in memory.
	saved_map_id = previous_map_id
	saved_position = previous_position
	saved_ground_position_gu = previous_ground_position_gu
	saved_ground_position_gu_valid = previous_ground_position_gu_valid
	last_save_result["memory_rolled_back"] = true
	return false


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


## Debug-lab fixture entry that appends only the three canonical QA v2 Chiyue
## profiles. Existing profile documents are validated but never rewritten;
## existing index rows are preserved verbatim and missing rows are appended.
func ensure_chiyue_test_roster() -> Dictionary:
	var result := {
		"ok": false,
		"contract_id": TEST_CHARACTER_ROSTER_CONTRACT_ID,
		"created": 0,
		"indexed": 0,
		"existing": 0,
		"total": CHIYUE_TEST_PROFILE_IDS.size(),
		"profile_ids": CHIYUE_TEST_PROFILE_IDS.duplicate(),
		"reason": "",
	}
	var directory_absolute := ProjectSettings.globalize_path(profile_directory)
	if (
		not DirAccess.dir_exists_absolute(directory_absolute)
		and DirAccess.make_dir_recursive_absolute(directory_absolute) != OK
	):
		result["reason"] = "profile_directory_failed"
		return result

	var index_status := _read_json_document(profile_index_path)
	if bool(index_status.get("exists", false)) and not bool(index_status.get("valid", false)):
		result["reason"] = "profile_index_invalid"
		return result
	if (
		not bool(index_status.get("exists", false))
		and FileAccess.file_exists(profile_index_path + ".bak")
	):
		result["reason"] = "profile_index_primary_missing"
		return result
	var index: Dictionary = (
		(index_status.get("data", {}) as Dictionary).duplicate(true)
		if bool(index_status.get("exists", false))
		else {"version": 1, "profiles": []}
	)


	if not index.get("profiles", null) is Array:
		result["reason"] = "profile_index_profiles_invalid"
		return result
	var profiles: Array = (index.get("profiles", []) as Array).duplicate(true)
	var index_id_counts := {}
	for value: Variant in profiles:
		if not value is Dictionary:
			result["reason"] = "profile_index_entry_invalid"
			return result
		var indexed_id := str((value as Dictionary).get("id", ""))
		if indexed_id.is_empty():
			result["reason"] = "profile_index_id_missing"
			return result
		index_id_counts[indexed_id] = int(index_id_counts.get(indexed_id, 0)) + 1
	for target_id: String in CHIYUE_TEST_PROFILE_IDS:
		if int(index_id_counts.get(target_id, 0)) > 1:
			result["reason"] = "duplicate_target_index:%s" % target_id
			return result

	var fixture_specs: Array[Dictionary] = []
	var now := int(Time.get_unix_time_from_system())
	for profession_id: String in ["warrior", "wizard", "taoist"]:
		var profession_name := ProfessionRules.profession_display_name(profession_id)
		var loadout := EquipmentTestLoadoutCatalogScript.get_loadout(
			profession_name,
			"chiyue"
		)
		var skill_profile := TestCharacterSkillProfilesScript.qa_v2_profile_for_character(
			profession_id,
			"chiyue"
		)
		var expected_profile_id := "test.character.%s.chiyue.v2" % profession_id
		if (
			loadout.is_empty()
			or skill_profile.is_empty()
			or str(loadout.get("tierId", "")) != "chiyue"
			or str(loadout.get("profession", "")) != profession_name
			or str(skill_profile.get("equipment_tier", "")) != "chiyue"
			or str(skill_profile.get("character_profile_id", "")) != expected_profile_id
			or expected_profile_id not in CHIYUE_TEST_PROFILE_IDS
		):
			result["reason"] = "fixture_authority_invalid:%s" % profession_id
			return result
		var character_level := maxi(
			int(loadout.get("level", 1)),
			int(skill_profile.get("minimum_character_level", 1))
		)
		var profile_entry := {
			"id": expected_profile_id,
			"name": str(skill_profile.get("character_name", expected_profile_id)),
			"profession": profession_name,
			"gender": str(loadout.get("gender", "男")),
			"level": character_level,
			"updated_at": now,
		}
		var payload := _test_character_payload(
			loadout,
			skill_profile,
			profile_entry,
			now
		)
		if not _valid_chiyue_test_profile_document(
			payload,
			expected_profile_id,
			profession_name,
			str(loadout.get("loadoutId", "")),
			str(skill_profile.get("template_id", ""))
		):
			result["reason"] = "fixture_payload_invalid:%s" % profession_id
			return result
		fixture_specs.append({
			"profile_id": expected_profile_id,
			"profession": profession_name,
			"loadout_id": str(loadout.get("loadoutId", "")),
			"skill_template_id": str(skill_profile.get("template_id", "")),
			"entry": profile_entry,
			"payload": payload,
		})

	var created_profile_ids: Array[String] = []
	for spec: Dictionary in fixture_specs:
		var profile_id := str(spec.get("profile_id", ""))
		var profile_path := _profile_path(profile_id)
		if FileAccess.file_exists(profile_path):
			var existing_status := _read_json_document(profile_path)
			if (
				not bool(existing_status.get("valid", false))
				or not _valid_chiyue_test_profile_document(
					existing_status.get("data", {}) as Dictionary,
					profile_id,
					str(spec.get("profession", "")),
					str(spec.get("loadout_id", "")),
					str(spec.get("skill_template_id", ""))
				)
			):
				_rollback_new_chiyue_test_profiles(created_profile_ids)
				result["reason"] = "existing_profile_invalid:%s" % profile_id
				return result
			result["existing"] = int(result["existing"]) + 1
			continue
		if (
			FileAccess.file_exists(profile_path + ".bak")
			or FileAccess.file_exists(profile_path + ".tmp")
			or FileAccess.file_exists(profile_path + ".corrupt.tmp")
		):
			_rollback_new_chiyue_test_profiles(created_profile_ids)
			result["reason"] = "existing_profile_primary_missing:%s" % profile_id
			return result
		if not _write_json_atomic(profile_path, spec.get("payload", {}) as Dictionary):
			_rollback_new_chiyue_test_profiles(created_profile_ids)
			result["reason"] = "profile_write_failed:%s" % profile_id
			return result
		created_profile_ids.append(profile_id)

	var indexed := 0
	for spec: Dictionary in fixture_specs:
		var profile_id := str(spec.get("profile_id", ""))
		if int(index_id_counts.get(profile_id, 0)) == 0:
			profiles.append((spec.get("entry", {}) as Dictionary).duplicate(true))
			index_id_counts[profile_id] = 1
			indexed += 1
	if indexed > 0:
		index["profiles"] = profiles
		if not _write_json_atomic(profile_index_path, index):
			_rollback_new_chiyue_test_profiles(created_profile_ids)
			result["reason"] = "profile_index_write_failed"
			return result

	for target_id: String in CHIYUE_TEST_PROFILE_IDS:
		if (
			not FileAccess.file_exists(_profile_path(target_id))
			or int(index_id_counts.get(target_id, 0)) != 1
		):
			result["reason"] = "postcondition_failed:%s" % target_id
			return result
	result["created"] = created_profile_ids.size()
	result["indexed"] = indexed
	result["ok"] = true
	return result


func _warehouse_transfer_commit(inventory_before: Array, warehouse_before: Array) -> bool:
	if test_mode and not _shared_warehouse_test_isolation_enabled():
		return _commit_save()
	if not _ensure_shared_warehouse_ready():
		return false
	if (
		profile_directory != PROFILE_DIRECTORY
		and not _shared_warehouse_test_isolation_enabled()
		and not _shared_warehouse_initialized
	):
		return _commit_save()
	var profile_path := _profile_path(active_profile_id)
	var before_profile := _read_json(profile_path)
	var before_shared := _read_json(shared_warehouse_path)
	if (
		before_profile.is_empty()
		or str(before_profile.get("profile_id", "")) != active_profile_id
		or not _validate_shared_warehouse_document(before_shared)
	):
		return false
	var after_profile := before_profile.duplicate(true)
	after_profile["inventory"] = inventory.duplicate(true)
	after_profile["warehouse_storage_contract_id"] = SHARED_WAREHOUSE_CONTRACT_ID
	after_profile["updated_at"] = int(Time.get_unix_time_from_system())
	after_profile.erase("warehouse_inventory")
	var after_shared := _shared_document_for_records(warehouse_inventory)
	if not _validate_shared_warehouse_document(after_shared):
		return false
	var prepared := {
		"contract_id": WAREHOUSE_TRANSFER_CONTRACT_ID,
		"state": "PREPARED",
		"profile_id": active_profile_id,
		"profile_path": profile_path,
		"before_profile": before_profile,
		"after_profile": after_profile,
		"before_shared": before_shared,
		"after_shared": after_shared,
		"before_profile_hash": _shared_digest(before_profile),
		"after_profile_hash": _shared_digest(after_profile),
		"before_shared_hash": _shared_digest(before_shared),
		"after_shared_hash": _shared_digest(after_shared),
	}
	if not _write_json_atomic(shared_warehouse_transaction_log_path, prepared):
		return false
	_warehouse_transaction_locked = true
	_persistence_transaction_in_progress = true
	var after_shared_ok := _write_shared_warehouse_document_atomic(after_shared)
	var after_profile_ok := false
	if after_shared_ok and not (test_mode and _test_fail_profile_write):
		after_profile_ok = _write_json_atomic(profile_path, after_profile)
	_persistence_transaction_in_progress = false
	var after_verified := (
		after_shared_ok
		and after_profile_ok
		and _shared_digest(_read_json(profile_path)) == _shared_digest(after_profile)
		and _shared_digest(_read_json(shared_warehouse_path)) == _shared_digest(after_shared)
	)
	if after_verified:
		_warehouse_transaction_locked = not _remove_persistence_file(
			shared_warehouse_transaction_log_path
		)
		return true
	var shared_restored := false
	var profile_restored := false
	if not (test_mode and _test_fail_warehouse_rollback_write):
		shared_restored = _write_json_atomic(shared_warehouse_path, before_shared)
		profile_restored = _write_json_atomic(profile_path, before_profile)
	var rollback_verified := (
		shared_restored
		and profile_restored
		and _shared_digest(_read_json(profile_path)) == _shared_digest(before_profile)
		and _shared_digest(_read_json(shared_warehouse_path)) == _shared_digest(before_shared)
	)
	if rollback_verified:
		_warehouse_transaction_locked = not _remove_persistence_file(
			shared_warehouse_transaction_log_path
		)
	return false


## Partial atomic pickup transaction. Each candidate is simulated in order;
## failures do not prevent later candidates from being attempted.
func receive_loot_batch_partial(candidates: Array) -> Dictionary:
	var inventory_before := inventory.duplicate(true)
	var gold_before := gold
	var working_inventory := inventory.duplicate(true)
	var working_gold := gold
	var initial_weight := inventory_weight(inventory)
	_loot_batch_debug["plan_scans"] = int(_loot_batch_debug.get("plan_scans", 0)) + 1
	_loot_batch_debug["initial_weight_scans"] = int(_loot_batch_debug.get("initial_weight_scans", 0)) + 1
	var working_weight := initial_weight
	var maximum_weight := max_inventory_weight()
	var outcomes: Array = []
	var changed := false
	for raw_candidate: Variant in candidates:
		if not raw_candidate is Dictionary:
			continue
		var candidate: Dictionary = raw_candidate
		if bool(candidate.get("gold", false)):
			var amount := maxi(0, int(candidate.get("amount", 0)))
			if amount > 0:
				working_gold = maxi(0, working_gold + amount)
				changed = true
			outcomes.append({"success": amount > 0, "gold": true, "amount": amount})
			continue
		var item_name := str(candidate.get("item_name", ""))
		var catalog := GameData.get_item_record(item_name)
		if catalog.is_empty():
			outcomes.append({"success": false, "item_name": item_name, "message": "物品无效。", "reason": "unknown_item"})
			continue
		var item_weight := maxi(0, int(catalog.get("weight", 0)))
		var kind := str(catalog.get("kind", ""))
		var stackable := bool(catalog.get("stackable", false)) and kind != "equipment"
		var prospective_weight := working_weight + item_weight
		if prospective_weight > maximum_weight and prospective_weight > initial_weight:
			outcomes.append({"success": false, "item_name": item_name, "message": INVENTORY_WEIGHT_REJECTION, "reason": "overweight"})
			continue
		var merged := false
		if stackable:
			var max_stack := _max_stack_for_item(catalog)
			for existing: Variant in working_inventory:
				if not existing is Dictionary or str(existing.get("name", "")) != item_name:
					continue
				if _inventory_records_mergeable(existing, {"name": item_name, "count": 1}) and int(existing.get("count", 0)) < max_stack:
					existing["count"] = int(existing.get("count", 0)) + 1
					merged = true
					break
		if not merged:
			if inventory_occupied_count(working_inventory) >= INVENTORY_CAPACITY:
				outcomes.append({"success": false, "item_name": item_name, "message": INVENTORY_SLOT_REJECTION, "reason": "inventory_full"})
				continue
			var new_record: Dictionary = _make_item_instance(item_name, catalog, Time.get_ticks_usec() + working_inventory.size() + outcomes.size()) if kind == "equipment" else {"name": item_name, "count": 1}
			if not _place_inventory_record_in_first_free_slot(working_inventory, new_record):
				outcomes.append({"success": false, "item_name": item_name, "message": INVENTORY_SLOT_REJECTION, "reason": "inventory_full"})
				continue
		working_weight = prospective_weight
		changed = true
		outcomes.append({"success": true, "item_name": item_name})
	if not changed:
		return {"success": true, "saved": false, "outcomes": outcomes, "success_count": 0}
	inventory = working_inventory
	gold = working_gold
	_loot_batch_debug["save_commits"] = int(_loot_batch_debug.get("save_commits", 0)) + 1
	if not _commit_save():
		inventory = inventory_before
		gold = gold_before
		for outcome: Dictionary in outcomes:
			if bool(outcome.get("success", false)):
				outcome["success"] = false
				outcome["reason"] = "save_failed"
				outcome["message"] = "拾取存档失败，物品和金币均未改变。"
		return {"success": false, "saved": false, "outcomes": outcomes, "success_count": 0, "reason": "save_failed"}
	last_receive_result = {"success": true, "outcomes": outcomes}
	if inventory != inventory_before:
		if test_mode:
			_test_transaction_counters["inventory_signals"] = int(_test_transaction_counters.get("inventory_signals", 0)) + 1
		inventory_changed.emit()
	if gold != gold_before:
		if test_mode:
			_test_transaction_counters["profile_signals"] = int(_test_transaction_counters.get("profile_signals", 0)) + 1
		profile_changed.emit()
	var success_count := 0
	for outcome: Dictionary in outcomes:
		if bool(outcome.get("success", false)):
			success_count += 1
	return {"success": true, "saved": true, "outcomes": outcomes, "success_count": success_count}


func loot_batch_debug_snapshot() -> Dictionary:
	return _loot_batch_debug.duplicate(true)


func _valid_chiyue_test_profile_document(
	document: Dictionary,
	expected_profile_id: String,
	expected_profession: String,
	expected_loadout_id: String,
	expected_skill_template_id: String
) -> bool:
	if (
		str(document.get("profile_id", "")) != expected_profile_id
		or str(document.get("profession", "")) != expected_profession
		or int(document.get("save_version", 0)) != SAVE_VERSION
		or int(document.get("level", 0)) < 50
		or not document.get("equipment", null) is Dictionary
		or not document.get("learned_skills", null) is Dictionary
	):
		return false
	var contracts: Variant = document.get("test_contracts", null)
	return (
		contracts is Dictionary
		and str((contracts as Dictionary).get("roster", ""))
		== TEST_CHARACTER_ROSTER_CONTRACT_ID
		and str((contracts as Dictionary).get("equipment", ""))
		== expected_loadout_id
		and str((contracts as Dictionary).get("skills", ""))
		== expected_skill_template_id
	)


func _rollback_new_chiyue_test_profiles(profile_ids: Array[String]) -> void:
	for profile_id: String in profile_ids:
		_remove_new_profile_files(profile_id)


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
		"equipment": equipment_data,
		"learned_skills": skill_profile.get("learned_skills", {}).duplicate(true),
		"quick_slots": legacy_slots,
		"quick_item_slots": ["", "", "", ""],
		"equip_cycle_cursor": _default_equip_cycle_cursor(),
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
		"map_id": 910001,
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
	var payload:={"save_version":SAVE_VERSION,"profile_id":profile_id,"character_name":"测试战士30级","updated_at":now,"level":30,"profession":"战士","gender":"男","later_content_enabled":false,"game_mode_id":"classic_176","experience":0,"gold":100000,"inventory":[],"equipment":equipment_data,"learned_skills":all_skills,"quick_slots":slots,"quick_item_slots":["", "", "", ""],"equip_cycle_cursor":_default_equip_cycle_cursor(),"quest_states":{},"content_packages":ContentLayers.enabled_package_ids(),"content_schema_version":CURRENT_CONTENT_SCHEMA_VERSION,"map_id":910001,"position":[0.0,0.0]}
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
	var result:={"name":item_name,"count":1,"durability":maximum,"max_durability":maximum,"durability_raw":maximum*DURABILITY_RAW_UNITS_PER_DISPLAY,"max_durability_raw":maximum*DURABILITY_RAW_UNITS_PER_DISPLAY,"durability_contract_id":DURABILITY_CONTRACT_ID,"instance_id":instance_id}
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
		"gold": 100000, "inventory": [{"name": "太阳水", "count": 10}],
		"equipment": equipment_data, "learned_skills": all_skills,
		"quick_slots": ["攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法"],
		"quick_item_slots": ["", "", "", ""],
		"equip_cycle_cursor": _default_equip_cycle_cursor(), "quest_states": {},
		"content_packages": ContentLayers.enabled_package_ids(), "content_schema_version": CURRENT_CONTENT_SCHEMA_VERSION,
		"map_id": 910001, "position": [0.0, 0.0],
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




func apply_temporary_item_buff(item_name: String, effect_profile: Dictionary) -> Dictionary:
	if effect_profile.is_empty() or item_name.is_empty():
		return {"ok": false, "reason": "invalid_arguments"}
	if str(effect_profile.get("contractId", "")) != "item.temporary_stat_buff.v1":
		return {"ok": false, "reason": "contract_mismatch"}
	var duration_seconds: float = maxf(0.0, float(effect_profile.get("durationSeconds", 0.0)))
	if duration_seconds <= 0.0:
		return {"ok": false, "reason": "duration_invalid"}
	var buff_group := str(effect_profile.get("buffGroup", ""))
	if buff_group.is_empty():
		return {"ok": false, "reason": "buff_group_missing"}
	var modifiers: Variant = effect_profile.get("modifiers", {})
	if not modifiers is Dictionary or (modifiers as Dictionary).is_empty():
		return {"ok": false, "reason": "modifiers_missing"}
	var allowed: Dictionary = TEMPORARY_ITEM_BUFF_ALLOWED_STATS.duplicate(true)
	for stat_name: String in modifiers:
		if not allowed.has(stat_name):
			return {"ok": false, "reason": "stat_not_allowed", "stat": stat_name}
	# Same buffGroup: refresh duration, do not stack.
	# Different buffGroup: add as separate entry.
	for existing_key: String in temporary_item_buffs:
		var existing: Dictionary = temporary_item_buffs[existing_key]
		if str(existing.get("buffGroup", "")) == buff_group:
			temporary_item_buffs.erase(existing_key)
			break
	temporary_item_buffs[item_name] = {
		"contract_id": TEMPORARY_ITEM_BUFF_CONTRACT_ID,
		"item_name": item_name,
		"buffGroup": buff_group,
		"modifiers": (modifiers as Dictionary).duplicate(true),
		"duration": duration_seconds,
		"remaining": duration_seconds,
	}
	temporary_item_buff_revision += 1
	recalculate_stats()
	return {"ok": true, "item_name": item_name, "revision": temporary_item_buff_revision}


func advance_temporary_item_buffs(delta: float) -> void:
	if temporary_item_buffs.is_empty():
		return
	var expired: Array[String] = []
	for item_name: String in temporary_item_buffs:
		var entry: Dictionary = temporary_item_buffs[item_name]
		var remaining: float = maxf(0.0, float(entry.get("remaining", 0.0)) - delta)
		entry["remaining"] = remaining
		if remaining <= 0.0:
			expired.append(item_name)
	if expired.is_empty():
		return
	for item_name: String in expired:
		temporary_item_buffs.erase(item_name)
	temporary_item_buff_revision += 1
	recalculate_stats()


func _apply_temporary_item_stat_modifiers(result: Dictionary) -> void:
	for entry: Variant in temporary_item_buffs.values():
		if not entry is Dictionary:
			continue
		var modifiers: Dictionary = (entry as Dictionary).get("modifiers", {})
		for stat_name: String in modifiers:
			var value: Variant = modifiers[stat_name]
			if value is int:
				result[stat_name] = int(result.get(stat_name, 0)) + int(value)
			elif value is float:
				result[stat_name] = float(result.get(stat_name, 0.0)) + float(value)


func _default_world_position_fields() -> Dictionary:
	return {
		"position": [0.0, 0.0],
		"position_space_contract_id": WORLD_POSITION_CONTRACT_ID,
		"position_screen_px": [0.0, 0.0],
		"position_ground_gu": [],
	}


func create_character(new_name: String, new_profession := "战士", new_gender := "男") -> String:
	if _warehouse_transaction_locked:
		return "仓库事务恢复中，暂不能创建角色"
	if not _ensure_shared_warehouse_ready():
		return "公共仓库不可用，角色未创建"
	var clean_name := new_name.strip_edges().substr(0, 12)
	if clean_name.is_empty():
		return "角色名不能为空"
	if not ProfessionRules.is_valid_profession(new_profession):
		return "职业无效"
	if new_gender not in ["男", "女"]:
		return "性别无效"
	if _character_name_exists(clean_name):
		return "角色名已存在"

	# Character creation is one transaction.  Build and validate the starter
	# loadout before exposing the new profile or writing anything to disk.  This
	# keeps a missing primary item record from producing a half-created profile.
	var new_profile_id := _new_profile_id()
	if new_profile_id.is_empty():
		return "角色存档ID生成失败"
	var previous_runtime := _creation_runtime_snapshot()
	active_profile_id = new_profile_id
	character_name = clean_name
	reset_progress(false)
	profession = new_profession
	gender = new_gender
	recalculate_stats(false)
	var starter_result := _build_starter_loadout(new_profession, new_gender, new_profile_id)
	if not bool(starter_result.get("ok", false)):
		_restore_creation_runtime(previous_runtime)
		return str(starter_result.get("error", "初始装备数据缺失，角色创建失败"))
	equipment = (starter_result.get("equipment", {}) as Dictionary).duplicate(true)
	# Keep圣物/徽章 empty for the future new-player rewards.  The helper already
	# returns the complete canonical slot map; this assertion also makes a future
	# loadout edit fail closed instead of silently filling those reserved slots.
	if not equipment.has("圣物") or not equipment.has("徽章"):
		_restore_creation_runtime(previous_runtime)
		return "初始装备槽位数据不完整，角色创建失败"
	recalculate_stats(false)
	if not save_game() or not bool(last_save_result.get("profile_index_updated", false)):
		_remove_new_profile_files(new_profile_id)
		_restore_creation_runtime(previous_runtime)
		last_save_result = {
			"contract_id": SAVE_RESULT_CONTRACT_ID,
			"success": false,
			"reason": "atomic_character_creation_failed",
		}
		return "角色存档失败，角色未创建"
	return ""


func delete_character_profile(profile_id: String) -> Dictionary:
	if _warehouse_transaction_locked:
		return {"contract_id": CHARACTER_DELETE_CONTRACT_ID, "success": false, "reason": "warehouse_transaction_locked", "profile_id": profile_id}
	if not _ensure_shared_warehouse_ready():
		return {"contract_id": CHARACTER_DELETE_CONTRACT_ID, "success": false, "reason": "shared_warehouse_unavailable", "profile_id": profile_id}
	if (
		(profile_directory == PROFILE_DIRECTORY or _shared_warehouse_test_isolation_enabled())
		and not _revalidate_shared_warehouse_authority()
	):
		return {"contract_id": CHARACTER_DELETE_CONTRACT_ID, "success": false, "reason": "shared_warehouse_validation_failed", "profile_id": profile_id}
	var result := {
		"contract_id": CHARACTER_DELETE_CONTRACT_ID,
		"success": false,
		"reason": "",
		"profile_id": profile_id,
		"deleted_files": [],
		"cleanup_failures": [],
		"cleanup_complete": false,
		"active_profile_cleared": false,
	}
	if (
		profile_id.is_empty()
		or profile_id.contains("/")
		or profile_id.contains("\\")
		or profile_id == "."
		or profile_id == ".."
	):
		result["reason"] = "invalid_profile_id"
		return result
	var index_status := _read_json_with_status(profile_index_path)
	if not bool(index_status.get("success", false)):
		result["reason"] = "profile_index_unavailable"
		return result
	var index: Dictionary = (index_status.get("data", {}) as Dictionary).duplicate(true)
	var indexed_profiles: Variant = index.get("profiles", null)
	if not indexed_profiles is Array:
		result["reason"] = "profile_index_invalid"
		return result
	var remaining_profiles: Array = []
	var found := false
	for value: Variant in indexed_profiles:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == profile_id:
			found = true
			continue
		remaining_profiles.append(value.duplicate(true) if value is Dictionary else value)
	if not found:
		result["reason"] = "profile_not_found"
		return result
	index["profiles"] = remaining_profiles
	# Commit the authoritative index first.  A failed atomic write therefore
	# leaves every profile byte untouched and the character fully selectable.
	if not _write_json_atomic(profile_index_path, index):
		result["reason"] = "profile_index_write_failed"
		return result
	var base_path := _profile_path(profile_id)
	for suffix: String in ["", ".bak", ".tmp", ".corrupt.tmp"]:
		var path := base_path + suffix
		if not FileAccess.file_exists(path):
			continue
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
			(result["cleanup_failures"] as Array).append(path)
			continue
		(result["deleted_files"] as Array).append(path)
	if active_profile_id == profile_id:
		active_profile_id = ""
		character_name = ""
		_autosave_elapsed = 0.0
		result["active_profile_cleared"] = true
		profile_changed.emit()
	result["cleanup_complete"] = (result["cleanup_failures"] as Array).is_empty()
	if not bool(result["cleanup_complete"]):
		# The profile index is authoritative: after its atomic commit succeeds the
		# deletion is logically complete even if an OS-level sidecar cleanup needs
		# a later retry.  Returning success keeps the hall in sync with that truth.
		result["reason"] = "profile_sidecar_cleanup_incomplete"
	result["success"] = true
	return result


func _character_name_exists(candidate: String) -> bool:
	for entry: Dictionary in list_characters():
		if str(entry.get("name", "")) == candidate:
			return true
	# A stale index must not allow a duplicate name.  Read only canonical profile
	# JSON files; backups and temporary files are deliberately excluded.
	var directory := DirAccess.open(profile_directory)
	if directory == null:
		return false
	for file_name: String in directory.get_files():
		if not file_name.ends_with(".json") or file_name.ends_with(".bak"):
			continue
		var document := _read_json(profile_directory.path_join(file_name))
		if str(document.get("character_name", "")) == candidate:
			return true
	return false


func _new_profile_id() -> String:
	for _attempt in range(16):
		var candidate := "%d_%d" % [int(Time.get_unix_time_from_system()), randi_range(1000, 9999)]
		if (
			not FileAccess.file_exists(_profile_path(candidate))
			and not FileAccess.file_exists(_profile_path(candidate) + ".bak")
		):
			return candidate
	# A hostile fixture may occupy every generated id.  Never overwrite a
	# profile in that case; creation fails closed instead.
	return ""


func _build_starter_loadout(starter_profession: String, starter_gender: String, profile_id: String) -> Dictionary:
	var result := {
		"contract_id": STARTER_LOADOUT_CONTRACT_ID,
		"ok": false,
		"equipment": _empty_equipment(),
		"error": "初始装备数据缺失，角色创建失败",
	}
	var starter_items := {
		"武器": STARTER_WEAPON_ITEM_NAME,
		"衣服": str(STARTER_ARMOR_BY_GENDER.get(starter_gender, "")),
	}
	for slot: String in starter_items.keys():
		var item_name := str(starter_items.get(slot, ""))
		var runtime_item := GameData.get_item(item_name)
		var catalog_item := GameData.get_item_record(item_name)
		if runtime_item.is_empty() or catalog_item.is_empty():
			return result
		if str(runtime_item.get("itemId", "")) != str(catalog_item.get("itemId", "")):
			result["error"] = "初始装备主数据不一致，角色创建失败"
			return result
		if str(catalog_item.get("kind", "")) != "equipment":
			result["error"] = "初始装备不是合法装备，角色创建失败"
			return result
		var category := str(runtime_item.get("category", ""))
		if slot not in _slots_for_category(category):
			result["error"] = "初始装备槽位不匹配，角色创建失败"
			return result
		var item_profession := EquipmentRulesScript.effective_profession(runtime_item)
		if item_profession not in ["", "通用", starter_profession]:
			result["error"] = "%s不适合当前职业，角色创建失败" % item_name
			return result
		var required_gender := EquipmentRulesScript.required_gender(runtime_item)
		if not required_gender.is_empty() and required_gender != starter_gender:
			result["error"] = "%s不适合当前性别，角色创建失败" % item_name
			return result
		var requirement_error := EquipmentRulesScript.requirement_error(runtime_item, 1, computed_stats)
		if not requirement_error.is_empty():
			result["error"] = "%s，角色创建失败" % requirement_error
			return result
		var item_weight := maxi(0, int(runtime_item.get("weight", 0)))
		if category == "武器":
			if item_weight > EquipmentRulesScript.max_hand_weight(starter_profession, 1):
				result["error"] = "%s超出初始手持负重，角色创建失败" % item_name
				return result
		elif item_weight > EquipmentRulesScript.max_wear_weight(starter_profession, 1):
			result["error"] = "%s超出初始穿戴负重，角色创建失败" % item_name
			return result
		var instance := _make_item_instance(item_name, catalog_item)
		if instance.is_empty() or str(instance.get("instance_id", "")).is_empty():
			result["error"] = "初始装备实例化失败，角色创建失败"
			return result
		# Slot and profile are part of the instance identity, so the two starter
		# pieces can never collapse into one another even on the same microsecond.
		instance["instance_id"] = "%s:starter:%s:%s" % [profile_id, slot, str(runtime_item.get("itemId", item_name))]
		(result["equipment"] as Dictionary)[slot] = instance
	result["ok"] = true
	return result


func _remove_new_profile_files(profile_id: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".corrupt.tmp"]:
		var path := _profile_path(profile_id) + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _creation_runtime_snapshot() -> Dictionary:
	return {
		"level": level,
		"profession": profession,
		"gender": gender,
		"later_content_enabled": later_content_enabled,
		"game_mode_id": game_mode_id,
		"experience": experience,
		"gold": gold,
		"inventory": inventory.duplicate(true),
		"warehouse_inventory": warehouse_inventory.duplicate(true),
		"equipment": equipment.duplicate(true),
		"learned_skills": learned_skills.duplicate(true),
		"skill_progression": _skill_progression.snapshot(),
		"quick_slots": quick_slots.duplicate(),
		"quick_item_slots": quick_item_slots.duplicate(),
		"equip_cycle_cursor": equip_cycle_cursor.duplicate(true),
		"attack_skill_slots": attack_skill_slots.duplicate(),
		"attack_ring_slots": attack_ring_slots.duplicate(),
		"warrior_runtime_state": warrior_runtime_state.duplicate(true),
		"taoist_main_pet_runtime_states": taoist_main_pet_runtime_states.duplicate(true),
		"quest_states": quest_states.duplicate(true),
		"saved_map_id": saved_map_id,
		"saved_position": saved_position,
		"saved_ground_position_gu": saved_ground_position_gu,
		"saved_ground_position_gu_valid": saved_ground_position_gu_valid,
		"computed_stats": computed_stats.duplicate(true),
		"computed_special_effects": computed_special_effects.duplicate(true),
		"durability_event_commit_count": durability_event_commit_count,
		"active_profile_id": active_profile_id,
		"character_name": character_name,
		"autosave_elapsed": _autosave_elapsed,
		"consumed_shop_sell_quote_ids": _consumed_shop_sell_quote_ids.duplicate(true),
		"consumed_shop_buy_quote_ids": _consumed_shop_buy_quote_ids.duplicate(true),
		"shop_buy_quote_serial": _shop_buy_quote_serial,
		"shop_pricing_session_nonce": _shop_pricing_session_nonce,
		"last_receive_result": last_receive_result.duplicate(true),
		"last_save_result": last_save_result.duplicate(true),
		"last_load_result": last_load_result.duplicate(true),
	}


func _restore_creation_runtime(snapshot: Dictionary) -> void:
	level = int(snapshot.get("level", 1))
	profession = str(snapshot.get("profession", "战士"))
	gender = str(snapshot.get("gender", "男"))
	later_content_enabled = bool(snapshot.get("later_content_enabled", false))
	game_mode_id = str(snapshot.get("game_mode_id", "classic_176"))
	experience = int(snapshot.get("experience", 0))
	gold = int(snapshot.get("gold", 0))
	inventory = (snapshot.get("inventory", []) as Array).duplicate(true)
	warehouse_inventory = (snapshot.get("warehouse_inventory", []) as Array).duplicate(true)
	equipment = (snapshot.get("equipment", {}) as Dictionary).duplicate(true)
	learned_skills = (snapshot.get("learned_skills", {}) as Dictionary).duplicate(true)
	_skill_progression.load_snapshot(snapshot.get("skill_progression", {}))
	quick_slots = (snapshot.get("quick_slots", []) as Array).duplicate()
	quick_item_slots = (snapshot.get("quick_item_slots", []) as Array).duplicate()
	equip_cycle_cursor = (snapshot.get("equip_cycle_cursor", {}) as Dictionary).duplicate(true)
	attack_skill_slots = (snapshot.get("attack_skill_slots", []) as Array).duplicate()
	attack_ring_slots = (snapshot.get("attack_ring_slots", []) as Array).duplicate()
	warrior_runtime_state = (snapshot.get("warrior_runtime_state", {}) as Dictionary).duplicate(true)
	taoist_main_pet_runtime_states = (snapshot.get("taoist_main_pet_runtime_states", {}) as Dictionary).duplicate(true)
	quest_states = (snapshot.get("quest_states", {}) as Dictionary).duplicate(true)
	saved_map_id = int(snapshot.get("saved_map_id", 910001))
	saved_position = snapshot.get("saved_position", Vector2.ZERO)
	saved_ground_position_gu = snapshot.get("saved_ground_position_gu", Vector2.ZERO)
	saved_ground_position_gu_valid = bool(snapshot.get("saved_ground_position_gu_valid", false))
	computed_stats = (snapshot.get("computed_stats", {}) as Dictionary).duplicate(true)
	computed_special_effects = (snapshot.get("computed_special_effects", {}) as Dictionary).duplicate(true)
	durability_event_commit_count = int(snapshot.get("durability_event_commit_count", 0))
	active_profile_id = str(snapshot.get("active_profile_id", ""))
	character_name = str(snapshot.get("character_name", ""))
	_autosave_elapsed = float(snapshot.get("autosave_elapsed", 0.0))
	_consumed_shop_sell_quote_ids = (snapshot.get("consumed_shop_sell_quote_ids", {}) as Dictionary).duplicate(true)
	_consumed_shop_buy_quote_ids = (snapshot.get("consumed_shop_buy_quote_ids", {}) as Dictionary).duplicate(true)
	_shop_buy_quote_serial = int(snapshot.get("shop_buy_quote_serial", 0))
	_shop_pricing_session_nonce = str(snapshot.get("shop_pricing_session_nonce", ""))
	last_receive_result = (snapshot.get("last_receive_result", {}) as Dictionary).duplicate(true)
	last_save_result = (snapshot.get("last_save_result", {}) as Dictionary).duplicate(true)
	last_load_result = (snapshot.get("last_load_result", {}) as Dictionary).duplicate(true)


func select_character(profile_id: String) -> bool:
	if _warehouse_transaction_locked:
		return false
	if not _ensure_shared_warehouse_ready():
		return false
	var profile_path := _profile_path(profile_id)
	if (
		not FileAccess.file_exists(profile_path)
		and not FileAccess.file_exists(profile_path + ".bak")
	):
		return false
	active_profile_id = profile_id
	load_save()
	if not bool(last_load_result.get("success", false)):
		active_profile_id = ""
		return false
	_autosave_elapsed = 0.0
	return true


func _update_profile_index() -> bool:
	var profiles := list_characters()
	var found := false
	for entry: Dictionary in profiles:
		if str(entry.get("id", "")) == active_profile_id:
			entry.merge({"name": character_name, "profession": profession, "gender": gender, "level": level, "updated_at": int(Time.get_unix_time_from_system())}, true)
			found = true
	if not found:
		profiles.append({"id": active_profile_id, "name": character_name, "profession": profession, "gender": gender, "level": level, "updated_at": int(Time.get_unix_time_from_system())})
	return _write_json_atomic(profile_index_path, {"version": 1, "profiles": profiles})


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


func _commit_save() -> bool:
	if test_mode:
		_test_transaction_counters["commit_attempts"] = int(_test_transaction_counters.get("commit_attempts", 0)) + 1
	if not test_mode:
		return save_game()
	return not _test_force_atomic_write_failure
