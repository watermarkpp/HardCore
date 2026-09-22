extends Node

const CombatRuntime := preload(
	"res://scripts/layers/runtime/combat_runtime_service.gd"
)
const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

const MAP_ID := 4317
const TARGET_COUNT := 20

var _index: RuntimeCombatSpatialIndex
var _runtime: Node
var _enemies: Array[EnemyActor] = []
var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.reset_performance_window()
	_index = SpatialIndex.new()
	_runtime = CombatRuntime.new()
	for target_index: int in range(TARGET_COUNT):
		_enemies.append(_make_enemy(target_index))
	# Fixture construction should not be confused with the same-frame release.
	RuntimeDiagnostics.reset_performance_window()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7417
	var stats_scratch: Dictionary = {}
	for enemy: EnemyActor in _enemies:
		var resolution: Dictionary = _runtime.apply_enemy_direct_spell_damage(
			enemy,
			"wizard.fireball",
			100,
			null,
			rng,
			Callable(self, "_zero_magic_defense"),
			0,
			stats_scratch,
		)
		_assert(bool(resolution.get("success", false)), "same-frame lethal resolution rejected")
		_assert(enemy.current_hp == 0, "same-frame release did not apply HP immediately")
		_assert(enemy._death_pending, "lethal target did not enter death-pending immediately")
		_assert(not enemy.is_in_group("enemies"), "death-pending target stayed in enemies group")
		_assert(not enemy.can_receive_damage(), "death-pending target still accepts damage")
		_assert(
			_index.registered_actor_count() == TARGET_COUNT - _enemies.find(enemy) - 1,
			"death-pending target was not synchronously unregistered",
		)
		var duplicate: Dictionary = _runtime.apply_enemy_direct_spell_damage(
			enemy,
			"wizard.fireball",
			100,
			null,
			rng,
			Callable(self, "_zero_magic_defense"),
			0,
			stats_scratch,
		)
		_assert(
			str(duplicate.get("failure_reason", "")) == "target_missing_damage_pipeline",
			"same-frame lethal target absorbed a second hit",
		)

	var counters := RuntimeDiagnostics.performance_counters()
	_assert(
		int(counters.get("take_damage_calls", 0)) == TARGET_COUNT,
		"same-frame release did not execute exactly one take_damage per target",
	)
	_assert(
		int(counters.get("lethal_damage_count", 0)) == TARGET_COUNT,
		"same-frame release lethal count diverged",
	)
	_assert(
		int(counters.get("death_pending_marks", 0)) == TARGET_COUNT,
		"same-frame release duplicated death-pending marks",
	)
	_assert(
		int(counters.get("death_same_release_unregistrations", 0)) == TARGET_COUNT,
		"same-frame release did not unregister every lethal target once",
	)
	_assert(_index.registered_actor_count() == 0, "dead targets remained in spatial index")
	var query_output: Array = []
	_index.query_enemy_nodes_aabb_into(
		MAP_ID,
		Rect2(Vector2(-100.0, -100.0), Vector2(200.0, 200.0)),
		query_output,
	)
	_assert(query_output.is_empty(), "dead targets remained query-visible")

	if not _failures.is_empty():
		push_error("DIRECT_SPELL_SAME_FRAME_BATCH_FAIL: %s" % "; ".join(_failures))
		print("DIRECT_SPELL_SAME_FRAME_BATCH_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		_cleanup()
		RuntimeDiagnostics.set_device_lab_performance_enabled(false)
		get_tree().quit(1)
		return
	print(
		"DIRECT_SPELL_SAME_FRAME_BATCH_PASS targets=%d take_damage=%d lethal=%d"
		% [
			TARGET_COUNT,
			int(counters.get("take_damage_calls", 0)),
			int(counters.get("lethal_damage_count", 0)),
		]
	)
	_cleanup()
	RuntimeDiagnostics.set_device_lab_performance_enabled(false)
	get_tree().quit(0)


func _make_enemy(target_index: int) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(218), null, false)
	enemy.max_hp = 5
	enemy.current_hp = 5
	enemy.direct_spell_stats_valid = true
	enemy.direct_spell_anti_magic_points = 0
	enemy.direct_spell_magic_defense_min = 0
	enemy.direct_spell_magic_defense_max = 0
	enemy.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	enemy.configure_spatial_index(_index, 10000 + target_index)
	enemy.set_combat_position(
		_ground_to_screen(Vector2(float(target_index), 0.0)),
		&"batch_fixture_spawn",
	)
	add_child(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	_index.register(
		10000 + target_index,
		MAP_ID,
		Vector2(float(target_index), 0.0),
		enemy.combat_radius_gu,
		10000 + target_index,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)
	return enemy


func _zero_magic_defense(
	_skill_id: String,
	damage_after_anti_magic: int,
	_target_stats: Dictionary,
) -> int:
	return damage_after_anti_magic


func _ground_to_screen(ground_gu: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(ground_gu)


func _screen_to_ground(screen_px: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(screen_px)


func _cleanup() -> void:
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.free()
	_runtime = null
	if _index != null:
		for target_index: int in range(TARGET_COUNT):
			_index.unregister(10000 + target_index)
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.free()
	_enemies.clear()


func _assert(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
