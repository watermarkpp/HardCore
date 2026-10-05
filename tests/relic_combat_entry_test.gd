extends Node

const Rules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
var proc_count := 0

func _ready() -> void:
	_run.call_deferred()

func _equip(id: int, profession: String) -> void:
	PlayerState.profession = profession
	var rng := RandomNumberGenerator.new()
	rng.seed = id
	var catalog := Rules.record_for_id(id)
	var item := PlayerState._make_item_instance(str(catalog.name), catalog, -1, false)
	item.merge(Rules.roll_instance(id, profession, rng), true)
	assert(PlayerState.receive_record(item, false).success)
	for index in PlayerState.inventory.size():
		if str(PlayerState.inventory[index].get("instance_id", "")) == str(item.instance_id):
			assert(PlayerState.equip_inventory_index_result(index).success)
			break
	for seed_value in 100:
		rng.seed = seed_value
		if rng.randi_range(0, 99) < Rules.PROC_CHANCE_PERCENT:
			rng.seed = seed_value
			PlayerState.configure_relic_proc_rng(rng)
			return
	assert(false)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 40
	_equip(950101, "战士")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 15000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(game.gameplay_input_is_enabled())
	PlayerState.relic_proc_started.connect(func(_id: int) -> void: proc_count += 1)
	assert(game.player.request_attack(), "natural attack request rejected")
	await get_tree().create_timer(0.7).timeout
	assert(proc_count == 1 and float(PlayerState.relic_proc_status().remaining) > 0.0, "released attack did not trigger relic")
	assert(game._player_relic_proc_effect.visible, "proc signal did not reach its presentation")
	await get_tree().create_timer(0.8).timeout
	assert(PlayerState.unequip_slot("hc.slot.relic").begins_with("已卸下"))
	_equip(950102, "法师")
	PlayerState.learned_skills = {"魔法盾": 3}
	game.player.current_mp = game.player.max_mp
	assert(game.player.request_skill("魔法盾"), "natural skill request rejected")
	await get_tree().create_timer(1.0).timeout
	assert(proc_count == 2 and float(PlayerState.relic_proc_status().remaining) > 0.0, "released spell did not trigger relic")
	assert(game.player.shield_time > 0.0, "relic proc swallowed the original skill effect")
	assert(game._player_relic_proc_effect.visible)
	assert(not game.player.request_skill("未学习技能"))
	assert(proc_count == 2, "rejected action triggered relic")
	print("RELIC_COMBAT_ENTRY_PASS natural attack + spell releases and rejected action")
	get_tree().quit(0)
