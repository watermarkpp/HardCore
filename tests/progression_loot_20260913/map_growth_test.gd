extends Node

func _ready() -> void:
	_run.call_deferred()

func _settle(game: Node) -> void:
	var deadline := Time.get_ticks_msec()+15000
	while (game._world_bootstrap_in_progress or game._map_transition_in_progress) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	assert(not game._world_bootstrap_in_progress and not game._map_transition_in_progress)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.set_process(false)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await _settle(game)
	var index := 0
	for job: String in ProfessionRules.PROFESSIONS:
		PlayerState.profession = job
		PlayerState.level = 30
		PlayerState.equipment = PlayerState._empty_equipment()
		PlayerState.temporary_item_buffs.clear()
		PlayerState.recalculate_stats()
		var base := PlayerState.base_stats.duplicate()
		game.player.current_hp = 10
		var water := GameData.get_item_record(910001)
		assert(PlayerState.apply_temporary_item_buff(water.name, water.effectProfile).ok)
		assert(game.player.max_hp == base.max_hp+50 and game.player.current_hp == 10)
		# Current authored runtime maps; retired service-only 217 is not playable.
		var destination := 911001 if index % 2 == 0 else 910004
		game.travel_to_map(destination)
		await _settle(game)
		assert(game.current_map_id == destination, "map=%d expected=%d gate=%s projection=%s" % [game.current_map_id,destination,game.gameplay_input_gate_snapshot(),game.projection_rejection_reason])
		assert(PlayerState.base_stats == base)
		assert(game.player.max_hp == base.max_hp+50)
		PlayerState._process(float(water.effectProfile.durationSeconds)+0.1)
		assert(PlayerState.base_stats == base and game.player.max_hp == base.max_hp)
		assert(PlayerState.temporary_item_buffs.is_empty())
		index += 1
	print("MAP_GROWTH_PASS: all 3 professions real GameRoot map travel, preserved base/buff separation and absolute HP")
	get_tree().quit(0)
