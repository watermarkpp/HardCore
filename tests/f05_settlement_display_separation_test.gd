extends Node

const Game := preload("res://scripts/game_root.gd")

class FixtureGame extends Game:
	# This test isolates native scheduling and real persistence. Terrain is
	# covered by loot_world_placement_integration_test, not synthesized here.
	func _begin_initial_world_bootstrap() -> void:
		return
	func _resolve_loot_ground_position(desired: Vector2, _origin := Vector2.INF) -> Vector2:
		return desired
	func _advance_loot_ground_position(desired: Vector2, _origin: Vector2, _search: Dictionary, _start: int, _budget: int, _sync: bool) -> Dictionary:
		return {"complete": true, "position": desired, "progressed": true}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var game := FixtureGame.new()
	game.current_map_id = 5317
	game._zone_generation = 11
	add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game._loot_pickup_runtime_manager.set_process(false)
	game._loot_pickup_runtime_manager.configure_map(5317, 11, _identity, _identity)
	var root := "user://f05_native_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("profiles.json")
	PlayerState.active_profile_id = "f05"
	PlayerState.test_mode = false # Native persistence and two-frame display.
	PlayerState.set_process(false)
	PlayerState.level = 50
	PlayerState.recalculate_stats(false)
	assert(PlayerState.save_game(false))
	game._enemy_death_flush_queued = true # Drive the production pump explicitly.
	_queue(game)
	assert(game._settle_pending_enemy_death_batch())
	var first: Dictionary = game._pending_enemy_deaths[0]
	# A prepared display backlog is the workload, not an altered reward roll.
	# Preserve the native roll; replace only the already-prepared node requests.
	var requests: Array[Dictionary] = []
	for index: int in range(12):
		requests.append({"gold_amount": 1, "position": Vector2(5000 + index, 5000)})
	first.drop_plan.requests = requests
	first.drop_plan.next_request_index = 0
	first.remaining_request_count = requests.size()
	var first_materialization_deadline := Time.get_ticks_msec() + 5000
	while first.materialized_node_count == 0 and Time.get_ticks_msec() < first_materialization_deadline:
		game._pump_enemy_death_work_queue()
		if first.materialized_node_count == 0:
			await get_tree().process_frame
	assert(first.state == "MATERIALIZING" and first.materialized_node_count == 1)
	var experience_before: int = PlayerState.experience
	var sequence_before: int = PlayerState._death_event_sequence
	_queue(game)
	var second: Dictionary = game._pending_enemy_deaths[1]
	for frame: int in range(10):
		game._pump_enemy_death_work_queue()
		await get_tree().process_frame
	if PlayerState._death_event_sequence != sequence_before + 1 or PlayerState.experience != experience_before + int(second.experience):
		game._flush_enemy_deaths(false)
		game.free()
		PlayerState.test_mode = true
		PlayerState.set_process(true)
		printerr("F05_SETTLEMENT_DISPLAY_SEPARATION_FAIL: earlier display backlog blocked later real XP/journal")
		get_tree().quit(1)
		return
	assert(first.state == "MATERIALIZING" and first.materialized_node_count < 12)
	assert(second.materialized_node_count == 0, "later display must not jump the older prepared nodes")
	game._flush_enemy_deaths(false)
	assert(game._pending_enemy_deaths.is_empty())
	assert(game._enemy_death_terminal_total_count == 2 and first.materialized_node_count == 12)
	assert(PlayerState._death_event_sequence == sequence_before + 1)
	game.free()
	PlayerState.test_mode = true
	PlayerState.set_process(true)
	await get_tree().process_frame
	print("F05_SETTLEMENT_DISPLAY_SEPARATION_PASS")
	get_tree().quit(0)

func _identity(position: Vector2) -> Vector2:
	return position

func _queue(game: Node) -> void:
	var enemy := EnemyActor.new()
	enemy.global_position = Vector2(5000, 5000)
	enemy.set_meta("respawn_enabled", false)
	var canonical := GameData.get_monster_by_id(34)
	enemy.set_meta("death_runtime_snapshot", game._build_enemy_death_runtime_snapshot(canonical))
	enemy.set_meta("death_origin", {"captured": true, "map_id": game.current_map_id,
		"generation": game._zone_generation, "death_position": enemy.global_position,
		"spawn_position": enemy.global_position, "spawn_context": {}})
	game._on_enemy_died(enemy, canonical)
	enemy.free()
