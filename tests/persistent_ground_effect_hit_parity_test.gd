extends Node

## Q2-B hit parity: the manager's narrow phase (runtime_target_is_inside +
## claim_runtime_tick) must produce the same hit ids, damage order, damage
## counts and claim results as the legacy per-effect enemy loop.

const Fixtures := preload(
	"res://tests/helpers/persistent_ground_effect_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Reference := preload(
	"res://tests/helpers/ground_effect_legacy_reference_tick.gd"
)
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const ManagerScript := preload(
	"res://scripts/persistent_ground_effect_manager.gd"
)

const MAP_A := 9001
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _manager: ManagerScript
var _enemies: Array[EnemyActor] = []
var _effects: Array[GroundSkillEffect] = []
var _damage_log: Array[int] = []
var _case_count := 0
var _difference_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	_run_case("no_targets", [], [])
	_run_case(
		"single_hit",
		[[Vector2(0, 0), 0.25]],
		[Vector2(0, 0)]
	)
	_run_case(
		"multiple_overlapping",
		[
			[Vector2(0, 0), 0.25],
			[Vector2(0.2, 0), 0.25],
			[Vector2(0.1, 0.1), 0.25],
		],
		[Vector2(0, 0)]
	)
	_run_case(
		"boundary_target",
		[[Vector2(1.8, 0), 0.25]],
		[Vector2(0, 0)]
	)
	_run_case(
		"outside_target",
		[[Vector2(5.0, 0), 0.25]],
		[Vector2(0, 0)]
	)
	_run_case(
		"dead_target",
		[[Vector2(0, 0), 0.25, 10]],
		[Vector2(0, 0)]
	)
	_run_case(
		"target_moved_before_tick",
		[[Vector2(0, 0), 0.25]],
		[Vector2(0, 0)],
		Vector2(3.0, 0)
	)
	_run_case(
		"target_teleported_same_frame",
		[[Vector2(5.0, 0), 0.25]],
		[Vector2(0, 0)],
		Vector2(0, 0)
	)
	_run_case(
		"cross_map_target",
		[[Vector2(50, 50), 0.25]],
		[Vector2(0, 0)],
		Vector2.INF,
		9002
	)
	_run_case(
		"same_target_two_effects",
		[[Vector2(0, 0), 0.25]],
		[Vector2(0, 0), Vector2(0, 0)],
		Vector2.INF,
		MAP_A,
		2
	)
	assert(
		_difference_count == 0,
		"manager hit parity must match legacy reference exactly"
	)
	_cleanup()
	await get_tree().process_frame
	print("PERSISTENT_GROUND_EFFECT_HIT_PARITY_PASS cases=%d" % _case_count)
	get_tree().quit(0)


func _run_case(
	label: String,
	enemy_specs: Array,
	effect_centers: Array,
	move_to_ground_gu := Vector2.INF,
	enemy_map_id := MAP_A,
	effect_count := 1
) -> void:
	_case_count += 1
	_fresh_world()
	var serial := 0
	for spec: Array in enemy_specs:
		serial += 1
		var hp := int(spec[2]) if spec.size() > 2 else 10000
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				serial,
				enemy_map_id,
				spec[0] as Vector2,
				float(spec[1]),
				hp
			)
		)
	for index: int in range(effect_count):
		var center := (
			effect_centers[index] as Vector2
			if index < effect_centers.size()
			else Vector2.ZERO
		)
		var release_id := "q2b:parity:%s:%d" % [label, index + 1]
		_effects.append(
			Fixtures.create_effect(
				self,
				SKILL_ID,
				release_id,
				MAP_A,
				center,
				2.0,
				1.0,
				60.0,
				3,
				null,
				Callable(self, "_record_damage")
			)
		)
		add_child(_effects[-1])
		Fixtures.register_effect(
			_manager,
			_effects[-1],
			index + 1,
			MAP_A,
			Callable(self, "_record_damage")
		)
	if label == "dead_target" and not _enemies.is_empty():
		_enemies[0].take_damage(99999, null)
	if move_to_ground_gu.is_finite() and not _enemies.is_empty():
		_enemies[0].set_combat_position(
			GroundUnit.ground_delta_gu_to_screen_delta_px(move_to_ground_gu),
			&"q2b_parity_move"
		)

	var initial_hp := _hp_snapshot()
	var legacy_order := _run_legacy()
	_restore_hp(initial_hp)
	_damage_log.clear()
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var manager_order := _run_manager()

	var legacy_count := legacy_order.size()
	var manager_count := manager_order.size()
	if legacy_count != manager_count:
		_difference_count += 1
		push_error(
			"parity %s: damage count legacy=%d manager=%d"
			% [label, legacy_count, manager_count]
		)
		return
	for i: int in range(legacy_count):
		if legacy_order[i] != manager_order[i]:
			_difference_count += 1
			push_error(
				"parity %s: order mismatch at %d legacy=%d manager=%d"
				% [label, i, legacy_order[i], manager_order[i]]
			)
			return
	_cleanup_world()


func _run_legacy() -> Array[int]:
	var order: Array[int] = []
	for effect: GroundSkillEffect in _effects:
		var result: Dictionary = Reference.legacy_tick(
			effect,
			_enemies,
			true,
			Callable(self, "_record_damage")
		)
		for enemy_id: int in result.get("damage_order", []):
			order.append(enemy_id)
	return order


func _run_manager() -> Array[int]:
	_manager.tick_frame(1.0)
	return _damage_log.duplicate()


func _fresh_world() -> void:
	_cleanup_world()
	_index = SpatialIndexScript.new()
	_manager = Fixtures.new_manager(_index)
	_enemies.clear()
	_effects.clear()
	_damage_log.clear()


func _hp_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for enemy: EnemyActor in _enemies:
		result[enemy.get_instance_id()] = enemy.current_hp
	return result


func _restore_hp(snapshot: Dictionary) -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.current_hp = int(snapshot.get(enemy.get_instance_id(), 10000))


func _cleanup_world() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	for effect: GroundSkillEffect in _effects:
		if is_instance_valid(effect):
			effect.queue_free()
	_enemies.clear()
	_effects.clear()
	_damage_log.clear()


func _cleanup() -> void:
	_cleanup_world()


func _record_damage(enemy: EnemyActor, amount: int) -> void:
	_damage_log.append(enemy.get_instance_id())
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
