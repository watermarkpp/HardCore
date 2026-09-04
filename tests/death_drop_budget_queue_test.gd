extends Node

const GameRootScript := preload("res://scripts/game_root.gd")
const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)

const MAP_ID := 5317
const GENERATION := 11
const MONSTER_ID := 34

var _failures: Array[String] = []
var _checks := 0
var _games: Array[Node] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.reset_performance_window()
	_test_budget_and_progress()
	_test_save_failure_is_no_reward()
	_test_generation_guards()
	_test_materialization_failure_is_terminal()
	_test_terminal_ledger_is_bounded()
	_finish()


func _new_game(seed_value: int) -> Node:
	RuntimeDiagnostics.reset_performance_window()
	var game: Node = GameRootScript.new()
	game.current_map_id = MAP_ID
	game._zone_generation = GENERATION
	game._rng.seed = seed_value
	game._enemy_death_flush_queued = true
	_games.append(game)
	return game


func _queue_death(game: Node, position := Vector2.ZERO) -> void:
	var enemy := EnemyActor.new()
	enemy.global_position = position
	enemy.set_meta("respawn_enabled", false)
	enemy.set_meta("spawn_position", position)
	var canonical := GameData.get_monster_by_id(MONSTER_ID)
	var snapshot: Dictionary = game._build_enemy_death_runtime_snapshot(canonical)
	enemy.set_meta("death_runtime_snapshot", snapshot)
	enemy.set_meta("death_origin", {
		"captured": true,
		"map_id": game.current_map_id,
		"generation": game._zone_generation,
		"death_position": position,
		"spawn_position": position,
		"spawn_context": {},
	})
	game._on_enemy_died(enemy, canonical)
	enemy.free()


func _set_fixed_plan(game: Node, request_count: int) -> Dictionary:
	var death: Dictionary = game._pending_enemy_deaths[0]
	var requests: Array[Dictionary] = []
	for index: int in range(request_count):
		requests.append({
			"item_name": "金创药(小量)",
			"position": Vector2(float(index), float(index)),
		})
	death["drop_plan"] = {
		"roll": {},
		"requests": requests,
		"next_request_index": 0,
		"item_count": request_count,
		"gold_drop_count": 0,
		"materialized": false,
	}
	death["materialized_node_index"] = 0
	death["materialized_node_count"] = 0
	death["materialization_retry_count"] = 0
	death["state"] = "PLANNED"
	return death


func _test_budget_and_progress() -> void:
	var game := _new_game(1001)
	_queue_death(game)
	_expect(game._settle_pending_enemy_death_batch() == true, "budget fixture did not settle")
	var death := _set_fixed_plan(game, 3)
	_expect(game.set_death_drop_work_limits_for_test(1000000, 4, 1), "budget override rejected")
	game._pump_enemy_death_work_queue()
	_expect(
		game._pending_enemy_deaths.size() == 1
		and int(death.get("materialized_node_index", 0)) == 1,
		"node budget did not leave remaining work queued",
	)
	_expect(
		RuntimeDiagnostics.performance_counter(&"drop_node_spawn_count") == 1,
		"first budget slice did not materialize one node",
	)
	game._flush_enemy_deaths(false)
	_expect(game._pending_enemy_deaths.is_empty(), "budget queue failed to drain")
	_expect(
		game._enemy_death_terminal_jobs.size() == 1
		and str(game._enemy_death_terminal_jobs[0].get("state", "")) == "COMMITTED",
		"budgeted death did not commit in order",
	)
	_expect(
		RuntimeDiagnostics.performance_counter(&"drop_node_spawn_count") == 3,
		"budgeted materialization duplicated or lost a node",
	)
	game.clear_death_drop_work_limits_for_test()


func _test_save_failure_is_no_reward() -> void:
	var game := _new_game(1002)
	_queue_death(game)
	PlayerState.test_transaction_debug_reset()
	PlayerState._test_force_atomic_write_failure = true
	game._flush_enemy_deaths(false)
	PlayerState._test_force_atomic_write_failure = false
	_expect(game._pending_enemy_deaths.is_empty(), "save failure stranded queue")
	_expect(
		game._enemy_death_terminal_jobs.size() == 1
		and str(game._enemy_death_terminal_jobs[0].get("state", "")) == "FAILED",
		"save failure did not reach observable terminal state",
	)
	_expect(
		RuntimeDiagnostics.performance_counter(&"drop_roll_count") == 0,
		"save failure consumed drop RNG",
	)
	_expect(game.get_child_count() == 0, "save failure materialized loot")
	_expect(
		int(PlayerState.test_transaction_debug_snapshot().get("commit_attempts", 0))
		== 3,
		"save failure did not use bounded retries",
	)


func _test_generation_guards() -> void:
	var pre_roll_game := _new_game(1003)
	_queue_death(pre_roll_game)
	var pre_roll_state: int = pre_roll_game._rng.state
	pre_roll_game.current_map_id = MAP_ID + 1
	pre_roll_game._flush_enemy_deaths(false)
	_expect(
		str(pre_roll_game._enemy_death_terminal_jobs[0].get("state", "")) == "CANCELLED",
		"pre-roll map mismatch was not cancelled",
	)
	_expect(
		pre_roll_game._rng.state == pre_roll_state
		and RuntimeDiagnostics.performance_counter(&"drop_roll_count") == 0,
		"pre-roll mismatch consumed drop RNG",
	)

	var post_roll_game := _new_game(1004)
	_queue_death(post_roll_game)
	_expect(post_roll_game._settle_pending_enemy_death_batch(), "post-roll fixture did not settle")
	var post_roll_death: Dictionary = post_roll_game._pending_enemy_deaths[0]
	_expect(
		str(post_roll_death.get("state", "")) == "PLANNED",
		"post-roll fixture did not reserve a plan",
	)
	post_roll_game._zone_generation += 1
	post_roll_game._flush_enemy_deaths(false)
	_expect(
		str(post_roll_game._enemy_death_terminal_jobs[0].get("state", "")) == "CANCELLED",
		"post-roll generation mismatch materialized old-map loot",
	)
	_expect(
		RuntimeDiagnostics.performance_counter(&"drop_node_spawn_count") == 0,
		"post-roll mismatch spawned a node",
	)


func _test_materialization_failure_is_terminal() -> void:
	var game := _new_game(1005)
	_queue_death(game)
	_expect(game._settle_pending_enemy_death_batch(), "materialization fixture did not settle")
	_set_fixed_plan(game, 2)
	_expect(game.set_death_drop_work_limits_for_test(1000000, 4, 1), "materialization budget override rejected")
	_expect(game.set_loot_materialization_failure_count_for_test(0), "materialization success hook rejected")
	game._pump_enemy_death_work_queue()
	_expect(
		game._pending_enemy_deaths.size() == 1
		and int(game._pending_enemy_deaths[0].get("materialized_node_index", 0)) == 1
		and game.get_child_count() == 1,
		"first materialization node did not commit before the injected failure",
	)
	_expect(game.set_loot_materialization_failure_count_for_test(99), "failure hook rejected")
	game._flush_enemy_deaths(false)
	game.set_loot_materialization_failure_count_for_test(0)
	_expect(
		game._enemy_death_terminal_jobs.size() == 1
		and str(game._enemy_death_terminal_jobs[0].get("state", "")) == "FAILED",
		"materialization failure was not terminal after retries",
	)
	_expect(game.get_child_count() == 1, "failed materialization duplicated the successful node")
	_expect(
		RuntimeDiagnostics.performance_counter(&"death_queue_materialization_failures") == 3,
		"materialization failure retry count was not observable",
	)
	var terminal: Dictionary = game._enemy_death_terminal_jobs[0]
	var remaining: Variant = terminal.get("remaining_requests", [])
	_expect(
		remaining is Array
		and remaining.size() == 1
		and int(terminal.get("materialized_node_index", 0)) == 1
		and int(terminal.get("remaining_request_count", 0)) == 1
		and str(terminal.get("reward_status", "")) == "materialization_failed",
		"partial materialization lost explicit remaining request evidence",
	)
	game.clear_death_drop_work_limits_for_test()


func _test_terminal_ledger_is_bounded() -> void:
	var game := _new_game(1006)
	for index: int in range(80):
		game._pending_enemy_deaths.append({
			"state": "COMMITTED",
			"death_key": "ledger:%d" % index,
		})
	game._compact_enemy_death_queue()
	_expect(
		game._enemy_death_terminal_jobs.size() == GameRootScript.DEATH_TERMINAL_LEDGER_MAX,
		"terminal ledger exceeded its bounded retention window",
	)
	_expect(
		int(game._enemy_death_terminal_total_count) == 80
		and str(game._enemy_death_terminal_jobs[-1].get("death_key", "")) == "ledger:79",
		"terminal ledger did not retain latest record and total count",
	)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	PlayerState._test_force_atomic_write_failure = false
	for game: Node in _games:
		if is_instance_valid(game):
			game.free()
	RuntimeDiagnostics.set_device_lab_performance_enabled(false)
	PlayerState.test_mode = false
	if not _failures.is_empty():
		push_error("DEATH_DROP_BUDGET_QUEUE_FAIL: %s" % "; ".join(_failures))
		print("DEATH_DROP_BUDGET_QUEUE_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		get_tree().quit(1)
		return
	print(
		"DEATH_DROP_BUDGET_QUEUE_PASS checks=%d save_retry=3 generation_guards=2"
		% _checks
	)
	get_tree().quit(0)
