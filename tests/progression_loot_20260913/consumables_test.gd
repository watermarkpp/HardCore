extends Node
const Split := preload("res://scripts/special_consumable_stacks.gd")
const Names := preload("res://scripts/ui_item_name_style.gd")
const Detail := preload("res://scripts/item_detail_presenter.gd")

func _ready() -> void:
	_run.call_deferred()

func _sum(records: Array, name: String) -> int:
	var total := 0
	for row: Dictionary in records:
		if row.get("name", "") == name: total += int(row.count)
	return total

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.set_process(false)
	PlayerState.profile_directory = "user://consumable_test_%d" % Time.get_ticks_usec()
	PlayerState.profession = "法师"
	PlayerState.level = 30
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.inventory = []
	PlayerState.recalculate_stats(false)
	var base := PlayerState.base_stats.duplicate()
	for raw: Dictionary in GameData.item_runtime_authority.newItems:
		if raw.useEffect != "temporary_stat_buff": continue
		var item := GameData.get_item_record(int(raw.itemId))
		assert(not item.stackable and int(item.maxStack) == 1)
		assert(Names.describe(item).group == "divine_water")
		assert("使用后" in Detail.format_item(item))
		PlayerState.inventory = []
		assert(PlayerState.receive(item.name,3,false).success)
		assert(PlayerState.inventory.size() == 3)
		for row: Dictionary in PlayerState.inventory: assert(row.count == 1)
		PlayerState.temporary_item_buffs.clear()
		PlayerState.temporary_item_buff_revision += 1
		PlayerState.use_inventory_index(0)
		assert(not PlayerState.temporary_item_buffs.is_empty())
		PlayerState._process(float(raw.effectProfile.durationSeconds)+0.1)
		assert(PlayerState.temporary_item_buffs.is_empty())
		assert(PlayerState.base_stats == base and PlayerState.computed_stats.max_hp == base.max_hp)
	for id in [920019,920033,920014,920016]:
		assert(Names.describe(GameData.get_item_record(id)).group == "potion")
	var water := GameData.get_item_record(910001)
	var full: Array = []
	for i in 100: full.append({"name":"木剑","count":1})
	full[0] = {"name":water.name,"item_id":910001,"count":4}
	assert(Split.split_available(full,100,100) == full)
	full[40] = {}
	var split := Split.split_available(full,100,100)
	assert(split[0].count == 3 and split[40].count == 1 and _sum(split,water.name) == 4)
	assert(full[0].count == 4)
	var warehouse := full.duplicate(true)
	warehouse[40] = {"name":"木剑","count":1}
	warehouse.append({})
	assert(Split.split_available(warehouse,500,100) == warehouse, "must not move overflow to another page")
	PlayerState.inventory = split
	PlayerState._test_force_atomic_write_failure = true
	PlayerState.inventory[50] = {}
	var before := PlayerState.inventory.duplicate(true)
	assert(not PlayerState._commit_save())
	assert(PlayerState.inventory == before)
	PlayerState._test_force_atomic_write_failure = false
	assert(PlayerState._commit_save())
	assert(PlayerState.inventory[0].count == 2 and PlayerState.inventory[50].count == 1)
	# Failed use cannot grant a free buff or consume an item.
	PlayerState.inventory = [{"name":water.name,"item_id":910001,"count":1}]
	PlayerState.temporary_item_buffs.clear()
	PlayerState._test_force_atomic_write_failure = true
	PlayerState.use_inventory_index(0)
	assert(PlayerState.temporary_item_buffs.is_empty() and PlayerState.inventory[0].count == 1)
	PlayerState._test_force_atomic_write_failure = false
	print("CONSUMABLES_V80_PASS: 12 actual item effects/expiry, nonstack receipts, colors, lossless full-page migration and rollback")
	get_tree().quit(0)
