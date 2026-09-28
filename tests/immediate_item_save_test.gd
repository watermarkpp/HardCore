extends Node

const State := preload("res://scripts/player_state.gd")
const POTION := "金创药(小量)"
var effects := 0


func _ready() -> void:
	_run.call_deferred()


func _new_state(tag: String, count := 25) -> Node:
	var state := State.new()
	var root := "user://immediate_item_%s_%d" % [tag, Time.get_ticks_usec()]
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.active_profile_id = "owner"
	state.reset_progress(false)
	state.inventory = [{"name": POTION, "count": count}]
	state.quick_item_slots[0] = POTION
	assert(state.save_game(false))
	state.consumable_requested.connect(func(_name: String) -> void: effects += 1)
	return state


func _read(state: Node) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(state._profile_path("owner")))


func _count(records: Array) -> int:
	var amount := 0
	for record: Dictionary in records:
		if str(record.get("name", "")) == POTION:
			amount += int(record.get("count", 1))
	return amount


func _settle(state: Node) -> void:
	# Real production pump, real worker/files. No barrier until after assertions.
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		state._process(0.0)
		if _count(_read(state).inventory) == _count(state.inventory) and state._json_persistence.pending_count() == 0:
			return
		await get_tree().process_frame
	assert(false, "latest accepted item use did not reach disk")


func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	var state := _new_state("rapid")
	var initial_bytes := FileAccess.get_file_as_bytes(state._profile_path("owner"))
	var started := Time.get_ticks_usec()
	for _i in 20:
		assert(state.use_quick_item_slot(0).ok)
	assert(effects == 20 and _count(state.inventory) == 5, "effects and consumption must happen immediately")
	assert(FileAccess.get_file_as_bytes(state._profile_path("owner")) == initial_bytes,
		"using an item still waits for a file transaction on the input path")
	print("IMMEDIATE_ITEM_20_USES_MS ", float(Time.get_ticks_usec() - started) / 1000.0)
	await _settle(state)
	state.free()
	# An old character/world checkpoint may complete after newer uses.
	state = _new_state("background")
	assert(state._start_background_save(false))
	assert(state.use_quick_item_slot(0).ok)
	assert(not state._background_save.is_empty(), "item use drained an older save")
	await _settle(state)
	assert(_count(state.inventory) == 24)
	assert(state.use_quick_item_slot(0).ok)
	state._process(0.0)
	assert(not state._item_save_plan.is_empty())
	assert(state.use_quick_item_slot(0).ok)
	await _settle(state)
	assert(_count(state.inventory) == 22, "a newer use was cleared by an older receipt")
	state.free()
	# Real irrevocable loot promotion, receipt not consumed yet. Include a
	# pickup into the SAME potion stack and consume its last existing unit.
	state = _new_state("loot", 1)
	var plan: Dictionary = state.prepare_loot_save([
		{"item_name": POTION}, {"item_name": POTION}, {"item_name": POTION}, {"gold": true, "amount": 17}])
	assert(plan.has("writer") and plan.writer.result(true).success)
	state._json_persistence.authorize(plan.writer.job)
	while str(state._json_persistence._queue[0].phase) != "PROMOTING":
		assert(state._json_persistence.pump(true))
	assert(state.use_quick_item_slot(0).ok)
	assert(not plan.completed, "item use waited for the pending loot receipt")
	state._json_persistence.drain()
	assert(plan.completed and plan.completion.success)
	assert(_count(state.inventory) == 3 and state.gold == 17,
		"old loot receipt restored a consumed item or lost the new pickup")
	assert(state.finish_prepared_loot_save(plan).success)
	assert(_count(state.inventory) == 3, "receipt applied twice")
	await _settle(state)
	assert(int(_read(state).gold) == 17)
	state.free()
	# Normal lifecycle flush must save even when no frame has pumped yet.
	state = _new_state("exit")
	assert(state.use_quick_item_slot(0).ok)
	var path: String = state._profile_path("owner")
	state.free()
	assert(_count(JSON.parse_string(FileAccess.get_file_as_string(path)).inventory) == 24)
	await _mixed_items()
	await _failed_write()
	print("IMMEDIATE_ITEM_SAVE_PASS")
	get_tree().quit(0)


func _mixed_items() -> void:
	var state := _new_state("mixed")
	state.profession = "战士"
	state.level = 50
	var weapon := GameData.get_item_record({"item_id": 81})
	state.equipment["武器"] = state._make_item_instance(str(weapon.name), weapon)
	state.equipment["武器"]["durability_raw"] = 1000
	state._sync_durability_compatibility_fields(state.equipment["武器"])
	state.inventory = []
	for item_name in ["修复油", "祝福油", "随机传送卷", "基本剑术"]:
		assert(not GameData.get_item_record(item_name).is_empty(), item_name)
		state.inventory.append({"name": item_name, "count": 1})
	var water := GameData.get_item_record(910001)
	state.inventory.append({"name": water.name, "item_id": 910001, "count": 1})
	var rng := RandomNumberGenerator.new()
	rng.seed = 431
	state.configure_blessing_oil_rng(rng)
	state.recalculate_stats(false)
	assert(state.save_game(false))
	var path: String = state._profile_path("owner")
	var bytes := FileAccess.get_file_as_bytes(path)
	for i in 5:
		var result: Dictionary = state.use_inventory_index_result(i, true)
		assert(result.success, str(result))
	assert(int(state.equipment["武器"].durability_raw) > 1000)
	assert(state.is_skill_learned("基本剑术") and not state.temporary_item_buffs.is_empty())
	assert(FileAccess.get_file_as_bytes(path) == bytes, "a non-potion use blocked on save")
	await _settle(state)
	assert(_read(state).learned_skills.has("基本剑术"))
	state.free()


func _failed_write() -> void:
	var state := _new_state("failed")
	var good_directory: String = state.profile_directory
	# A real file occupies the required directory; the worker cannot create it.
	var blocked := good_directory.path_join("not_a_directory")
	FileAccess.open(blocked, FileAccess.WRITE).store_string("occupied")
	state.profile_directory = blocked
	var warnings := [0]
	state.background_item_save_failed.connect(func() -> void: warnings[0] += 1)
	assert(state.use_quick_item_slot(0).ok and _count(state.inventory) == 24)
	var deadline := Time.get_ticks_msec() + 5000
	while not state._item_save_failed and Time.get_ticks_msec() < deadline:
		state._process(0.0)
		await get_tree().process_frame
	assert(state._item_save_failed and int(warnings[0]) == 1, "failed write must be reported")
	assert(_count(state.inventory) == 24, "failed background IO rolled back gameplay")
	state.profile_directory = good_directory
	assert(state.use_quick_item_slot(0).ok)
	await _settle(state)
	assert(_count(_read(state).inventory) == 23)
	state.free()
