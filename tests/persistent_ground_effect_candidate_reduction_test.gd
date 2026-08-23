extends Node

## Q2-B candidate reduction on the fixed sparse fixture: 16 persistent effects
## x 256 enemies x 60 ticks. The shared broadphase must drop exact tests by at
## least 60% versus the legacy full-group scan and never group-scan.

const Fixtures := preload(
	"res://tests/helpers/persistent_ground_effect_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const ManagerScript := preload(
	"res://scripts/persistent_ground_effect_manager.gd"
)

const MAP_A := 9701
const SKILL_ID := "wizard.fire_wall"
const EFFECT_COUNT := 16
const ENEMY_COUNT := 256
const TICK_COUNT := 60

var _index: SpatialIndexScript
var _manager: ManagerScript
var _enemies: Array[EnemyActor] = []
var _effects: Array[GroundSkillEffect] = []
var _damage_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	_manager = Fixtures.new_manager(_index)
	for i: int in range(ENEMY_COUNT):
		var center := Vector2(
			(i % 64) * 2.0 - 63.0,
			(i / 64) * 2.0 - 3.0
		)
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				i + 1,
				MAP_A,
				center,
				0.25
			)
		)
	for i: int in range(EFFECT_COUNT):
		var center := Vector2(
			(i % 4) * 16.0 - 24.0,
			(i / 4) * 2.0 - 3.0
		)
		_effects.append(
			Fixtures.create_effect(
				self,
				SKILL_ID,
				"q2b:reduction:%d" % i,
				MAP_A,
				center,
				2.0,
				1.0,
				60.0,
				1,
				null,
				Callable(self, "_record_damage")
			)
		)
		add_child(_effects[-1])
		Fixtures.register_effect(
			_manager,
			_effects[-1],
			i + 1,
			MAP_A,
			Callable(self, "_record_damage")
		)

	for _tick: int in range(TICK_COUNT):
		_manager.tick_frame(1.0)

	var diagnostics: Dictionary = _manager.persistent_ground_effect_diagnostics()
	var legacy_examined := EFFECT_COUNT * ENEMY_COUNT * TICK_COUNT
	var legacy_exact_tests := legacy_examined
	var candidates := int(diagnostics.get("total_candidate_count", 0))
	var exact_tests := int(
		diagnostics.get("exact_intersection_test_count", 0)
	)
	var group_scan_count := int(diagnostics.get("group_scan_count", 0))
	var group_nodes_examined := int(
		diagnostics.get("group_nodes_examined", 0)
	)
	var snapshot_rebuilds := int(
		diagnostics.get("snapshot_rebuild_count", 0)
	)
	var max_candidates := int(diagnostics.get("max_candidate_count", 0))
	var reduction_percent := 0.0
	if legacy_exact_tests > 0:
		reduction_percent = (
			100.0 * float(legacy_exact_tests - exact_tests)
			/ float(legacy_exact_tests)
		)
	assert(
		group_scan_count == 0 and group_nodes_examined == 0,
		"production hot path must not group-scan enemies"
	)
	assert(
		snapshot_rebuilds == 0,
		"the manager must never rebuild the canonical snapshot"
	)
	assert(
		candidates < legacy_examined,
		"broadphase candidates must be fewer than legacy examined nodes"
	)
	assert(
		exact_tests < legacy_exact_tests,
		"exact tests must be reduced below legacy"
	)
	assert(
		reduction_percent >= 60.0,
		"exact test reduction must be at least 60 percent on the sparse fixture, got %.1f"
		% reduction_percent
	)
	assert(
		int(diagnostics.get("tick_dispatch_count", 0))
		== EFFECT_COUNT * TICK_COUNT,
		"one dispatch per effect per tick"
	)
	print(
		"PERSISTENT_GROUND_EFFECT_CANDIDATE_REDUCTION_PASS legacy_examined=%d candidates=%d max_candidates=%d exact_tests=%d reduction=%.1f%% group_scans=%d snapshot_rebuilds=%d"
		% [
			legacy_examined,
			candidates,
			max_candidates,
			exact_tests,
			reduction_percent,
			group_scan_count,
			snapshot_rebuilds,
		]
	)
	_cleanup()
	await get_tree().process_frame
	get_tree().quit(0)


func _cleanup() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	for effect: GroundSkillEffect in _effects:
		if is_instance_valid(effect):
			effect.queue_free()


func _record_damage(enemy: EnemyActor, amount: int) -> void:
	_damage_count += 1
	enemy.take_damage(amount, null)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)


func _snapshot_contains_enemy(
	enemy: EnemyActor,
	snapshot: Dictionary
) -> bool:
	return Snapshot.intersects_target_combat_footprint_ground_gu(
		snapshot,
		GroundUnit.screen_delta_px_to_ground_delta_gu(enemy.global_position),
		enemy.combat_radius_gu
	)
