extends Node


var _events: Array[Dictionary] = []
var _saved: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture_state()
	_configure_isolated_state()
	PlayerState.item_audio_committed.connect(_on_item_audio_committed)
	_test_service_consumable_identity()
	_test_temporary_buff_item_identity()
	_test_quick_use_emits_once()
	_test_equip_and_unequip_item_identity()
	_test_failure_and_rollback_emit_nothing()
	PlayerState.item_audio_committed.disconnect(_on_item_audio_committed)
	_restore_state()
	print("PLAYER_ITEM_AUDIO_EVENT_PASS")
	get_tree().quit(0)


func _test_service_consumable_identity() -> void:
	assert(PlayerState._item_audio_nonnegative_integer(670.0) == 670)
	assert(PlayerState._item_audio_nonnegative_integer(670.5) == -1)
	assert(PlayerState._item_audio_nonnegative_integer(-1.0) == -1)
	var catalog := _catalog_record("太阳水")
	var expected := _catalog_identity(catalog)
	assert(str(expected.get("identity_domain", "")) == "service", "太阳水应使用 service domain")
	PlayerState.inventory = [{"name": "太阳水", "count": 1}]
	_events.clear()
	var message := PlayerState.use_inventory_index(0)
	assert(message.begins_with("使用："), "太阳水使用失败：%s" % message)
	_assert_single_event(expected, "use_success")


func _test_temporary_buff_item_identity() -> void:
	var catalog := _catalog_record("疾风神水")
	var expected := _catalog_identity(catalog)
	assert(str(expected.get("identity_domain", "")) == "item", "疾风神水应使用 item domain")
	PlayerState.inventory = [{"name": "疾风神水", "count": 1}]
	PlayerState.temporary_item_buffs = {}
	_events.clear()
	var message := PlayerState.use_inventory_index(0)
	assert(message.begins_with("使用："), "临时增益使用失败：%s" % message)
	assert(not PlayerState.temporary_item_buffs.is_empty(), "临时增益未提交")
	_assert_single_event(expected, "use_success")


func _test_quick_use_emits_once() -> void:
	PlayerState.inventory = [{"name": "太阳水", "count": 1}]
	PlayerState.quick_item_slots = ["太阳水", "", "", ""]
	_events.clear()
	var result := PlayerState.use_quick_item_slot(0, "太阳水")
	assert(bool(result.get("ok", false)), "快捷栏使用失败：%s" % str(result))
	assert(_events.size() == 1, "快捷栏一次使用不得重复物品音效事件")
	assert(str(_events[0].get("semantic_event", "")) == "use_success")


func _test_equip_and_unequip_item_identity() -> void:
	var catalog := _catalog_record("木剑")
	var expected := _catalog_identity(catalog)
	assert(str(expected.get("identity_domain", "")) == "item", "木剑应使用 item domain")
	PlayerState.inventory = [{"name": "木剑", "count": 1}]
	PlayerState.equipment = PlayerState._empty_equipment()
	_events.clear()
	var equip_message := PlayerState.equip_inventory_index(0, "武器")
	assert(equip_message == "已装备：木剑", "装备失败：%s" % equip_message)
	_assert_single_event(expected, "equip_success")

	_events.clear()
	var unequip_message := PlayerState.unequip_slot("武器")
	assert(unequip_message == "已卸下：木剑", "卸下失败：%s" % unequip_message)
	_assert_single_event(expected, "unequip_success")


func _test_failure_and_rollback_emit_nothing() -> void:
	_events.clear()
	PlayerState.inventory = []
	assert(PlayerState.use_inventory_index(0) == "请先选择物品")
	assert(_events.is_empty(), "无效物品使用不得发射事件")

	# Direct consumable commits expose the existing commit result through the
	# runtime commit profile; a forced failed commit must not emit audio.
	PlayerState.inventory = [{"name": "太阳水", "count": 1}]
	PlayerState._test_force_atomic_write_failure = true
	_events.clear()
	PlayerState.use_inventory_index(0)
	assert(_events.is_empty(), "消耗提交失败不得发射事件")
	PlayerState._test_force_atomic_write_failure = false

	# The transactional special-item paths roll back both domains before any
	# audio event is allowed to escape.
	var oil_weapon := PlayerState._make_item_instance(
		"命运之刃", GameData.get_item_record("命运之刃"), 9001
	)
	oil_weapon["durability_raw"] = 20000
	oil_weapon["max_durability_raw"] = 20000
	oil_weapon["weapon_luck"] = 0
	oil_weapon["weapon_curse"] = 0
	PlayerState.inventory = [{"name": "祝福油", "count": 1}]
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.equipment["武器"] = oil_weapon
	var oil_inventory_before := PlayerState.inventory.duplicate(true)
	var oil_equipment_before := PlayerState.equipment.duplicate(true)
	PlayerState._test_force_atomic_write_failure = true
	_events.clear()
	var oil_result := PlayerState.use_blessing_oil_inventory_index_with_rolls(0, 0, 0)
	assert(not bool(oil_result.get("ok", false)), "祝福油强制失败未拒绝")
	assert(PlayerState.inventory == oil_inventory_before)
	assert(PlayerState.equipment == oil_equipment_before)
	assert(_events.is_empty(), "祝福油回滚不得发射事件")

	var equip_record := PlayerState._make_item_instance(
		"木剑", GameData.get_item_record("木剑"), 9002
	)
	PlayerState.inventory = [equip_record]
	PlayerState.equipment = PlayerState._empty_equipment()
	var equip_inventory_before := PlayerState.inventory.duplicate(true)
	var equip_equipment_before := PlayerState.equipment.duplicate(true)
	_events.clear()
	var equip_result := PlayerState.equip_inventory_index(0, "武器")
	assert(equip_result == "装备存档失败，装备和背包均未改变")
	assert(PlayerState.inventory == equip_inventory_before)
	assert(PlayerState.equipment == equip_equipment_before)
	assert(_events.is_empty(), "装备回滚不得发射事件")

	PlayerState._test_force_atomic_write_failure = false
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.equipment["武器"] = equip_record.duplicate(true)
	PlayerState.inventory = []
	var unequip_inventory_before := PlayerState.inventory.duplicate(true)
	var unequip_equipment_before := PlayerState.equipment.duplicate(true)
	PlayerState._test_force_atomic_write_failure = true
	_events.clear()
	var unequip_result := PlayerState.unequip_slot("武器")
	assert(unequip_result == "卸装存档失败，装备和背包均未改变")
	assert(PlayerState.inventory == unequip_inventory_before)
	assert(PlayerState.equipment == unequip_equipment_before)
	assert(_events.is_empty(), "卸下回滚不得发射事件")
	PlayerState._test_force_atomic_write_failure = false


func _catalog_record(item_name: String) -> Dictionary:
	var record := GameData.get_item_record(item_name)
	assert(not record.is_empty(), "缺少精确目录记录：%s" % item_name)
	return record


func _catalog_identity(record: Dictionary) -> Dictionary:
	for key: String in ["itemId", "item_id"]:
		var item_id := PlayerState._item_audio_nonnegative_integer(record.get(key, null))
		if item_id >= 0:
			return {"identity_domain": "item", "identity_id": item_id}
	for key: String in ["serviceIndex", "service_index"]:
		var service_id := PlayerState._item_audio_nonnegative_integer(record.get(key, null))
		if service_id >= 0:
			return {"identity_domain": "service", "identity_id": service_id}
	assert(false, "目录没有稳定音频身份字段：%s" % str(record.get("name", "")))
	return {}


func _assert_single_event(expected: Dictionary, semantic_event: String) -> void:
	assert(_events.size() == 1, "预期恰好一个物品音效事件，实际%d" % _events.size())
	assert(str(_events[0].get("identity_domain", "")) == str(expected.get("identity_domain", "")))
	assert(int(_events[0].get("identity_id", -1)) == int(expected.get("identity_id", -1)))
	assert(str(_events[0].get("semantic_event", "")) == semantic_event)


func _on_item_audio_committed(
	identity_domain: String,
	identity_id: int,
	semantic_event: String,
) -> void:
	_events.append({
		"identity_domain": identity_domain,
		"identity_id": identity_id,
		"semantic_event": semantic_event,
	})


func _configure_isolated_state() -> void:
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = false
	PlayerState._shared_warehouse_initialized = false
	PlayerState.active_profile_id = "player_item_audio_event_test"
	PlayerState.character_name = "物品音效测试"
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	PlayerState.recalculate_stats(false)


func _capture_state() -> void:
	_saved = {
		"test_mode": PlayerState.test_mode,
		"force_failure": PlayerState._test_force_atomic_write_failure,
		"initialized": PlayerState._shared_warehouse_initialized,
		"active_profile_id": PlayerState.active_profile_id,
		"character_name": PlayerState.character_name,
		"level": PlayerState.level,
		"profession": PlayerState.profession,
		"gender": PlayerState.gender,
		"inventory": PlayerState.inventory.duplicate(true),
		"equipment": PlayerState.equipment.duplicate(true),
		"quick_item_slots": PlayerState.quick_item_slots.duplicate(),
		"temporary_item_buffs": PlayerState.temporary_item_buffs.duplicate(true),
	}


func _restore_state() -> void:
	PlayerState.test_mode = bool(_saved.get("test_mode", false))
	PlayerState._test_force_atomic_write_failure = bool(_saved.get("force_failure", false))
	PlayerState._shared_warehouse_initialized = bool(_saved.get("initialized", false))
	PlayerState.active_profile_id = str(_saved.get("active_profile_id", ""))
	PlayerState.character_name = str(_saved.get("character_name", ""))
	PlayerState.level = int(_saved.get("level", 1))
	PlayerState.profession = str(_saved.get("profession", "战士"))
	PlayerState.gender = str(_saved.get("gender", "男"))
	PlayerState.inventory = (_saved.get("inventory", []) as Array).duplicate(true)
	PlayerState.equipment = (_saved.get("equipment", {}) as Dictionary).duplicate(true)
	PlayerState.quick_item_slots = (_saved.get("quick_item_slots", []) as Array).duplicate()
	PlayerState.temporary_item_buffs = (_saved.get("temporary_item_buffs", {}) as Dictionary).duplicate(true)
	PlayerState.recalculate_stats(false)
