extends Node

const GameRootScript := preload("res://scripts/game_root.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)

const MAP_ID := 4317
const GENERATION := 7
const MONSTER_ID := 34
const DEATH_COUNT := 32
const RNG_SEED := 20260905

var _failures: Array[String] = []
var _checks := 0
var _game: Node
var _enemies: Array[EnemyActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.test_transaction_debug_reset()
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.reset_performance_window()
	_game = GameRootScript.new()
	_game.current_map_id = MAP_ID
	_game._zone_generation = GENERATION
	_game._combat_spatial_index = SpatialIndexScript.new()
	_game._rng.seed = RNG_SEED
	var loot_runtime := LootRuntimeScript.new()
	# Block the automatic deferred pump so the assertions cover the queued
	# boundary before the test explicitly drains the same state machine.
	_game._enemy_death_flush_queued = true
	var canonical := GameData.get_monster_by_id(MONSTER_ID)
	_expect(not canonical.is_empty(), "mass-death canonical fixture missing")
	for index: int in range(DEATH_COUNT):
		_enemies.append(_make_enemy(canonical, index))
	await get_tree().process_frame
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.current_hp = 1
			enemy.take_damage(1)
			_expect(enemy.current_hp == 0, "lethal damage was not immediate")
			_expect(enemy._death_pending, "lethal actor was not death-pending")
			_expect(not enemy.is_in_group("enemies"), "dead actor stayed in enemies")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_game._pending_enemy_deaths.size() == DEATH_COUNT, "same-frame deaths were not queued")
	for death: Dictionary in _game._pending_enemy_deaths:
		_expect(
			death.has_all([
				"death_key", "sequence", "state", "origin_map_id",
				"origin_generation", "monster_snapshot", "death_position",
				"spawn_position", "respawn", "drop_plan", "transaction_result",
			]),
			"death item lost a required transaction field",
		)
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = RNG_SEED
	var expected_rolls := 0
	for _index: int in range(DEATH_COUNT):
		var roll := loot_runtime.roll_monster_drops(MONSTER_ID, expected_rng, false)
		expected_rolls += 1
		var raw_items: Variant = roll.get("items", [])
		if raw_items is Array:
			for _item_name: String in raw_items:
				expected_rng.randf_range(-34.0, 34.0)
				expected_rng.randf_range(-18.0, 18.0)
		var raw_gold: Variant = roll.get("gold_drops", [])
		if raw_gold is Array:
			for raw_amount: Variant in raw_gold:
				if int(raw_amount) > 0:
					expected_rng.randf_range(-34.0, 34.0)
					expected_rng.randf_range(-18.0, 18.0)
	_game._flush_enemy_deaths(false)
	_expect(_game._pending_enemy_deaths.is_empty(), "death queue did not drain")
	_expect(
		_game._enemy_death_terminal_jobs.size() == DEATH_COUNT,
		"terminal death count did not match same-frame input",
	)
	var terminal: Array = _game._enemy_death_terminal_jobs
	for index: int in range(terminal.size()):
		var death: Dictionary = terminal[index]
		_expect(str(death.get("state", "")) == "COMMITTED", "death did not commit")
		_expect(int(death.get("sequence", -1)) == index + 1, "death order changed")
	_expect(
		RuntimeDiagnostics.performance_counter(&"drop_roll_count") == expected_rolls,
		"one drop roll was not reserved per death",
	)
	_expect(
		_game._rng.state == expected_rng.state,
		"deferred drop/position RNG state diverged from eager order",
	)
	var tx := PlayerState.test_transaction_debug_snapshot()
	_expect(int(tx.get("commit_attempts", 0)) == 1, "same-frame deaths used more than one save")
	_expect(
		int(tx.get("profile_signals", 0)) == 1,
		"same-frame death settlement did not emit one profile transaction",
	)
	_expect(
		RuntimeDiagnostics.performance_counter(&"death_physics_process_calls_after_begin") == 0,
		"corpse continued physics callbacks after death begin",
	)
	_finish()


func _make_enemy(canonical: Dictionary, index: int) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(canonical, null, false)
	enemy.global_position = Vector2(float(index * 6), float(index % 4) * 5.0)
	var serial := 10000 + index
	enemy.set_meta("spawn_serial", serial)
	enemy.set_meta("respawn_enabled", false)
	enemy.set_meta("respawn_seconds", -1.0)
	enemy.set_meta("spawn_position", enemy.global_position)
	enemy.set_meta("zone_generation", GENERATION)
	enemy.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	enemy.configure_spatial_index(
		_game._combat_spatial_index,
		serial,
	)
	add_child(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	_game._combat_spatial_index.register(
		serial,
		MAP_ID,
		Vector2(float(index * 6), float(index % 4) * 5.0),
		enemy.combat_radius_gu,
		serial,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)
	enemy.died.connect(_game._on_enemy_died)
	return enemy


func _ground_to_screen(ground: Vector2) -> Vector2:
	return ground


func _screen_to_ground(screen: Vector2) -> Vector2:
	return screen


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.free()
	if is_instance_valid(_game):
		_game.free()
	RuntimeDiagnostics.set_device_lab_performance_enabled(false)
	PlayerState.test_mode = false
	if not _failures.is_empty():
		push_error("ENEMY_MASS_DEATH_BATCH_FAIL: %s" % "; ".join(_failures))
		print("ENEMY_MASS_DEATH_BATCH_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		get_tree().quit(1)
		return
	print(
		"ENEMY_MASS_DEATH_BATCH_PASS deaths=%d checks=%d rng_parity=1 save_commits=1"
		% [DEATH_COUNT, _checks]
	)
	get_tree().quit(0)
