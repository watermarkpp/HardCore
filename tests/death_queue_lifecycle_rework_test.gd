extends Node

const MainScene := preload("res://scenes/main.tscn")
const GameRootScript := preload("res://scripts/game_root.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)

class FixtureGameRoot extends GameRootScript:
	## Keep the real GameRoot._ready lifecycle (including the loot manager), but
	## do not start the production world bootstrap for the isolated async queue.
	func _begin_initial_world_bootstrap() -> void:
		return

const MAP_ID := 6317
const GENERATION := 17
const MONSTER_ID := 34
const ASYNC_DEATH_COUNT := 32
const ASYNC_RNG_SEED := 20260905
const MAX_WORLD_READY_FRAMES := 1800
const MAX_ASYNC_FRAMES := 240

var _failures: Array[String] = []
var _checks := 0
var _in_tree_game: Node
var _async_game: Node
var _async_enemies: Array[EnemyActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.create_character(
		"R3X4%06d" % (Time.get_ticks_msec() % 1000000),
		"战士",
		"男",
	)
	PlayerState._test_force_atomic_write_failure = false
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.reset_performance_window()
	await _test_in_tree_logout_and_origin_guard()
	await _test_async_real_deaths_and_rng_parity()
	_finish()


func _test_in_tree_logout_and_origin_guard() -> void:
	_in_tree_game = MainScene.instantiate()
	add_child(_in_tree_game)
	if not await _wait_for_world_ready(_in_tree_game):
		_expect(false, "in-tree GameRoot production bootstrap did not reach READY")
		return
	_in_tree_game.set_process(false)
	_in_tree_game.set_physics_process(false)
	_in_tree_game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)
	_freeze_existing_enemies(_in_tree_game)
	_in_tree_game._enemy_death_flush_queued = true
	var origin_map := int(_in_tree_game.current_map_id)
	var origin_generation := int(_in_tree_game._zone_generation)
	_expect(origin_map >= 0, "in-tree fixture has no current runtime map")
	# A real in-tree GameRoot logout must synchronously drain a pending death
	# before writing the Home record.  The queue item is produced through the
	# production Enemy.take_damage boundary; the deferred signal has not fired
	# yet, so this also proves logout does not lose the actor-side pending event.
	RuntimeDiagnostics.reset_performance_window()
	PlayerState.test_transaction_debug_reset()
	var lethal_enemy := _make_in_tree_lethal_enemy(
		_in_tree_game,
		origin_map,
		origin_generation,
		Vector2(144.0, 88.0),
	)
	_expect(lethal_enemy._death_pending, "logout fixture did not enter death_pending")
	_expect(_in_tree_game._pending_enemy_deaths.is_empty(), "logout fixture signal fired before logout boundary")
	var logout_result: Dictionary = _in_tree_game._prepare_safe_logout()
	_expect(
		bool(logout_result.get("success", false)),
		"safe logout did not drain a pending death: %s active=%s save=%s"
		% [
			str(logout_result.get("reason", "")),
			PlayerState.active_profile_id,
			str(PlayerState.last_save_result),
		],
	)
	_expect(
		_in_tree_game._pending_enemy_deaths.is_empty()
		and str(_in_tree_game._enemy_death_terminal_jobs[-1].get("state", "")) == "COMMITTED",
		"safe logout left a death uncommitted",
	)
	_expect(
		_in_tree_game._enemy_death_terminal_jobs[-1].get("reward_status", "") == "committed",
		"safe logout committed death without reward status",
	)

	# Queue an old-origin death, then switch the live GameRoot identity before
	# pumping.  The queue must cancel before PlayerState settlement or RNG use.
	RuntimeDiagnostics.reset_performance_window()
	PlayerState.test_transaction_debug_reset()
	var before_experience := PlayerState.experience
	var before_rng_state: int = int(_in_tree_game._rng.state)
	_queue_manual_death(
		_in_tree_game,
		origin_map,
		origin_generation,
		Vector2(222.0, 111.0),
	)
	var queued: Dictionary = _in_tree_game._pending_enemy_deaths[-1]
	_expect(
		int(queued.get("origin_map_id", -1)) == origin_map
		and int(queued.get("origin_generation", -1)) == origin_generation
		and bool(queued.get("origin_captured", false)),
		"death queue did not retain the lethal-time origin",
	)
	_in_tree_game.current_map_id = origin_map + 100
	_in_tree_game._zone_generation = origin_generation + 1
	_in_tree_game._flush_enemy_deaths(false)
	var old_terminal: Dictionary = _in_tree_game._enemy_death_terminal_jobs[-1]
	_expect(
		str(old_terminal.get("state", "")) == "CANCELLED"
		and str(old_terminal.get("last_error", ""))
			== "origin_map_generation_mismatch_before_settlement",
		"old-origin death was not cancelled before settlement",
	)
	_expect(PlayerState.experience == before_experience, "old-origin death granted new-map XP")
	_expect(_in_tree_game._rng.state == before_rng_state, "old-origin death consumed drop RNG")
	_expect(
		int(PlayerState.test_transaction_debug_snapshot().get("commit_attempts", 0)) == 0,
		"old-origin death touched PlayerState before cancellation",
	)
	# A settlement/save failure is a hard logout refusal.  The second exit
	# attempt must observe the same terminal failure without repeating the
	# reward/save transaction.
	_in_tree_game.current_map_id = origin_map
	_in_tree_game._zone_generation = origin_generation
	_in_tree_game._enemy_death_flush_queued = true
	RuntimeDiagnostics.reset_performance_window()
	PlayerState.test_transaction_debug_reset()
	_queue_manual_death(
		_in_tree_game,
		origin_map,
		origin_generation,
		Vector2(255.0, 121.0),
	)
	PlayerState._test_force_atomic_write_failure = true
	var failed_logout: Dictionary = _in_tree_game._prepare_safe_logout()
	_expect(
		not bool(failed_logout.get("success", true))
		and str(failed_logout.get("reason", "")) == "safe_logout_death_queue_failed",
		"death settlement failure did not refuse safe logout",
	)
	var failed_attempts := int(PlayerState.test_transaction_debug_snapshot().get("commit_attempts", 0))
	_expect(failed_attempts == 3, "death save failure did not use bounded retry")
	_in_tree_game._exit_game()
	_expect(
		not get_tree().auto_accept_quit
		and int(PlayerState.test_transaction_debug_snapshot().get("commit_attempts", 0)) == failed_attempts,
		"failed death logout retried or exited on the second request",
	)
	PlayerState._test_force_atomic_write_failure = false
	_in_tree_game.current_map_id = origin_map
	_in_tree_game._zone_generation = origin_generation
	_in_tree_game._enemy_death_flush_queued = true
	# Keep this single real GameRoot alive for the async phase.  Constructing a
	# second GameRoot in the same viewport reconnects the global HUD safe-area
	# signal and obscures queue failures with duplicate-connection errors.


func _test_async_real_deaths_and_rng_parity() -> void:
	RuntimeDiagnostics.reset_performance_window()
	PlayerState.test_transaction_debug_reset()
	_async_game = _in_tree_game
	_async_game._pending_enemy_deaths.clear()
	_async_game._enemy_death_terminal_jobs.clear()
	_async_game._enemy_death_terminal_total_count = 0
	_async_game._enemy_death_sequence = 0
	_async_game._last_death_logout_failure.clear()
	_async_game._enemy_death_pipeline_running = false
	_async_game._enemy_death_target_refresh_pending = false
	_async_game.current_map_id = MAP_ID
	_async_game._zone_generation = GENERATION
	_async_game._enemy_death_flush_queued = true
	_async_game.set_process(false)
	_async_game.set_physics_process(false)
	_async_game._combat_spatial_index = SpatialIndexScript.new()
	_async_game._rng.seed = ASYNC_RNG_SEED
	if is_instance_valid(_async_game.player):
		_async_game.player.set_process(false)
		_async_game.player.set_physics_process(false)
	if _async_game._loot_pickup_runtime_manager != null:
		_async_game._loot_pickup_runtime_manager.configure_map(
			MAP_ID,
			GENERATION,
			Callable(self, "_identity_position"),
			Callable(self, "_identity_position"),
		)
		_async_game._loot_pickup_runtime_manager.set_process(false)
	if is_instance_valid(_async_game.background):
		_async_game.background.set_process(false)
		_async_game.background.set_physics_process(false)
	var canonical := GameData.get_monster_by_id(MONSTER_ID)
	_expect(not canonical.is_empty(), "async death canonical fixture missing")
	for index: int in range(ASYNC_DEATH_COUNT):
		_async_enemies.append(_make_runtime_enemy(index, canonical))
	for enemy: EnemyActor in _async_enemies:
		if not is_instance_valid(enemy):
			continue
		enemy.current_hp = 1
		enemy.take_damage(1)
		_expect(enemy.current_hp == 0, "real lethal take_damage was not immediate")
		_expect(enemy._death_pending, "real lethal take_damage did not set death_pending")
	for _frame: int in range(4):
		await get_tree().process_frame
	_expect(
		_async_game._pending_enemy_deaths.size() == ASYNC_DEATH_COUNT,
		"real death signals did not reach the deferred queue",
	)

	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = ASYNC_RNG_SEED
	var loot_runtime := LootRuntimeScript.new()
	var expected_rolls: Array[Dictionary] = []
	var expected_requests: Array[Array] = []
	for _index: int in range(ASYNC_DEATH_COUNT):
		var roll := loot_runtime.roll_monster_drops(MONSTER_ID, expected_rng, false)
		expected_rolls.append(roll.duplicate(true))
		var planned_requests: Array = []
		var death_position := Vector2(float(_index * 6), float(_index % 4) * 5.0)
		var raw_items: Variant = roll.get("items", [])
		var item_records: Variant = roll.get("item_records", [])
		if raw_items is Array:
			for item_index: int in range(raw_items.size()):
				var item_name := str(raw_items[item_index])
				var item_record: Dictionary = (
					item_records[item_index]
					if item_records is Array
					and item_index < item_records.size()
					and item_records[item_index] is Dictionary
					else {}
				)
				planned_requests.append({
					"item_name": item_name,
					"item_record": item_record.duplicate(true),
					"position": death_position + Vector2(
						expected_rng.randf_range(-34.0, 34.0),
						expected_rng.randf_range(-18.0, 18.0),
					),
				})
		var raw_gold: Variant = roll.get("gold_drops", [])
		if raw_gold is Array:
			for raw_amount: Variant in raw_gold:
				if int(raw_amount) > 0:
					planned_requests.append({
						"gold_amount": int(raw_amount),
						"position": death_position + Vector2(
							expected_rng.randf_range(-34.0, 34.0),
							expected_rng.randf_range(-18.0, 18.0),
						),
					})
		expected_requests.append(planned_requests)

	var pump_frames := 0
	# This parity contract isolates one GameRoot and deliberately has no other
	# RNG consumer between frames.  Cross-system RNG interleaving is outside
	# R3X-4's guarantee and is not asserted here.
	while not _async_game._pending_enemy_deaths.is_empty() and pump_frames < MAX_ASYNC_FRAMES:
		var progressed: bool = _async_game._pump_enemy_death_work_queue()
		_expect(progressed, "non-empty async death queue made no progress")
		pump_frames += 1
		await get_tree().process_frame
	_expect(_async_game._pending_enemy_deaths.is_empty(), "32 real deaths did not drain asynchronously")
	_expect(pump_frames > 1, "async death fixture drained in one frame")
	_expect(
		_async_game._rng.state == expected_rng.state,
		"async deferred drops/positions diverged from eager RNG order",
	)
	var metrics := RuntimeDiagnostics.performance_counters()
	_expect(
		int(metrics.get("death_jobs_per_frame_max", 0)) <= 4,
		"default death jobs cap was exceeded",
	)
	_expect(
		int(metrics.get("drop_nodes_per_frame_max", 0)) <= 8,
		"default drop node cap was exceeded",
	)
	_expect(
		int(metrics.get("death_work_frames", 0)) > 1,
		"async queue did not expose multi-frame work",
	)
	_expect(
		_async_game._enemy_death_terminal_jobs.size() == ASYNC_DEATH_COUNT
		and int(_async_game._enemy_death_terminal_total_count) == ASYNC_DEATH_COUNT,
		"async terminal ledger lost death records",
	)
	for death_index: int in range(_async_game._enemy_death_terminal_jobs.size()):
		var death: Dictionary = _async_game._enemy_death_terminal_jobs[death_index]
		var actual_plan: Dictionary = death.get("drop_plan", {})
		var actual_roll: Dictionary = actual_plan.get("roll", {})
		_expect(
			str(death.get("state", "")) == "COMMITTED"
			and str(death.get("reward_status", "")) == "committed",
			"async death did not commit atomically",
		)
		_expect(
			int(death.get("sequence", -1)) == death_index + 1
			and actual_plan.get("requests", []) == expected_requests[death_index]
			and actual_roll.get("items", []) == expected_rolls[death_index].get("items", [])
			and actual_roll.get("gold_drops", []) == expected_rolls[death_index].get("gold_drops", []),
			"async drop request/order diverged from eager reference",
		)


func _make_runtime_enemy(index: int, canonical: Dictionary) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(canonical, null, false)
	enemy.global_position = Vector2(float(index * 6), float(index % 4) * 5.0)
	var serial := 42000 + index
	enemy.set_meta("spawn_serial", serial)
	enemy.set_meta("respawn_enabled", false)
	enemy.set_meta("respawn_seconds", -1.0)
	enemy.set_meta("spawn_position", enemy.global_position)
	enemy.set_meta("zone_generation", GENERATION)
	enemy.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_identity_position"),
		Callable(self, "_identity_position"),
	)
	enemy.configure_spatial_index(_async_game._combat_spatial_index, serial)
	_async_game.add_child(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	_async_game._combat_spatial_index.register(
		serial,
		MAP_ID,
		Vector2(float(index * 6), float(index % 4) * 5.0),
		enemy.combat_radius_gu,
		serial,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)
	enemy.died.connect(_async_game._on_enemy_died)
	return enemy


func _queue_manual_death(
	game: Node,
	map_id: int,
	generation: int,
	position: Vector2,
) -> void:
	var enemy := EnemyActor.new()
	var canonical := GameData.get_monster_by_id(MONSTER_ID)
	enemy.global_position = position
	enemy.set_meta("respawn_enabled", false)
	enemy.set_meta("spawn_position", position)
	enemy.set_meta("death_runtime_snapshot", game._build_enemy_death_runtime_snapshot(canonical))
	enemy.set_meta("death_origin", {
		"captured": true,
		"map_id": map_id,
		"generation": generation,
		"death_position": position,
		"spawn_position": position,
		"spawn_context": {},
	})
	game._on_enemy_died(enemy, canonical)
	enemy.free()


func _make_in_tree_lethal_enemy(
	game: Node,
	map_id: int,
	generation: int,
	position: Vector2,
) -> EnemyActor:
	var canonical := GameData.get_monster_by_id(MONSTER_ID)
	var enemy := EnemyActor.new()
	enemy.setup(canonical, game.player, false)
	enemy.configure_runtime_map_projection(
		map_id,
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(game, "_canonical_screen_px_to_ground_gu"),
	)
	enemy.global_position = position
	enemy.set_meta("spawn_serial", 99101)
	enemy.set_meta("spawn_position", position)
	enemy.set_meta("zone_generation", generation)
	enemy.set_meta("respawn_enabled", false)
	enemy.set_meta("respawn_seconds", -1.0)
	enemy.set_meta("spawn_context", {})
	game.add_child(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	enemy.died.connect(game._on_enemy_died)
	enemy.current_hp = 1
	enemy.take_damage(1)
	return enemy


func _wait_for_world_ready(game: Node) -> bool:
	for _frame: int in range(MAX_WORLD_READY_FRAMES):
		if (
			not bool(game._world_bootstrap_in_progress)
			and not bool(game._map_transition_in_progress)
			and game._world_bootstrap_coordinator.stage
			== WorldBootstrapCoordinator.Stage.READY
		):
			return true
		if game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.FAILED:
			return false
		await get_tree().process_frame
	return false


func _freeze_existing_enemies(game: Node) -> void:
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor and is_instance_valid(value):
			(value as EnemyActor).set_physics_process(false)
			(value as EnemyActor).set_process(false)


func _identity_position(value: Vector2) -> Vector2:
	return value


func _capture_safe_logout_error(_action: StringName, _reason: String) -> void:
	return


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	PlayerState._test_force_atomic_write_failure = false
	for enemy: EnemyActor in _async_enemies:
		if is_instance_valid(enemy):
			enemy.free()
	if is_instance_valid(_async_game):
		_async_game.free()
	if is_instance_valid(_in_tree_game):
		_in_tree_game.free()
	RuntimeDiagnostics.set_device_lab_performance_enabled(false)
	PlayerState.test_mode = false
	if not _failures.is_empty():
		print(
			"DEATH_QUEUE_LIFECYCLE_REWORK_FAIL checks=%d failures=%d %s"
			% [_checks, _failures.size(), "; ".join(_failures)]
		)
		get_tree().quit(1)
		return
	print(
		"DEATH_QUEUE_LIFECYCLE_REWORK_PASS checks=%d async_deaths=%d rng_parity=1"
		% [_checks, ASYNC_DEATH_COUNT]
	)
	get_tree().quit(0)
