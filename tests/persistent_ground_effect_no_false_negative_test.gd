extends Node

## Q2-B broadphase safety: every enemy the legacy exact path would hit on the
## effect's map must appear in the shared spatial index candidates. Cross-map
## enemies must never leak into another map's candidate set.

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

const MAP_A := 9101
const MAP_B := 9102
const SKILL_ID := "wizard.fire_wall"
const EXPANSION_GU := 0.05

var _index: SpatialIndexScript
var _manager: ManagerScript
var _effect: GroundSkillEffect
var _enemies: Array[EnemyActor] = []
var _cross_map_enemy: EnemyActor
var _enemy_by_serial: Dictionary = {}
var _scenario_count := 0
var _false_negative_count := 0
var _cross_map_leak_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(20260806)
	_fresh_world()
	# One circle effect at the origin; enemies are repositioned per scenario so
	# the exact reference and the broadphase query observe identical inputs.
	_effect = Fixtures.create_effect(
		self,
		SKILL_ID,
		"q2b:no_false_negative:1",
		MAP_A,
		Vector2.ZERO,
		2.0,
		1.0,
		60.0,
		1,
		null,
		Callable(self, "_record_damage")
	)
	add_child(_effect)
	Fixtures.register_effect(
		_manager,
		_effect,
		1,
		MAP_A,
		Callable(self, "_record_damage")
	)
	for i: int in range(8):
		var enemy := Fixtures.make_enemy(
			self,
			_index,
			i + 1,
			MAP_A,
			Vector2(-6.0 + float(i) * 1.7, 0.0),
			0.25
		)
		_enemies.append(enemy)
		_enemy_by_serial[i + 1] = enemy
	_cross_map_enemy = Fixtures.make_enemy(
		self,
		_index,
		100,
		MAP_B,
		Vector2.ZERO,
		0.25
	)

	for i: int in range(100):
		_random_static_scenario(i)
	for i: int in range(30):
		_move_scenario(i, 0.3)
	for i: int in range(30):
		_move_scenario(i, 5.0)
	for i: int in range(30):
		_teleport_scenario(i)
	for i: int in range(20):
		_cross_map_scenario(i)

	assert(
		_false_negative_count == 0,
		"broadphase candidates must never miss a legacy exact hit"
	)
	assert(
		_cross_map_leak_count == 0,
		"cross-map enemies must never leak into map A candidates"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"PERSISTENT_GROUND_EFFECT_NO_FALSE_NEGATIVE_PASS scenarios=%d"
		% _scenario_count
	)
	get_tree().quit(0)


func _random_static_scenario(index: int) -> void:
	var origin := Vector2(
		randf_range(-1.5, 1.5),
		randf_range(-1.5, 1.5)
	)
	for i: int in range(8):
		var target := origin + Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		)
		_enemies[i].set_combat_position(
			GroundUnit.ground_delta_gu_to_screen_delta_px(target),
			&"q2b_static"
		)
	_assert_scenario("static_%d" % index, false)


func _move_scenario(index: int, delta_gu: float) -> void:
	var target := Vector2(0.2, 0.1)
	if index % 2 == 1:
		target = _enemies[index % 8].spatial_index_position()
	target += Vector2(delta_gu, 0.0)
	_enemies[index % 8].set_combat_position(
		GroundUnit.ground_delta_gu_to_screen_delta_px(target),
		&"q2b_move"
	)
	_assert_scenario("move_%d" % index, false)


func _teleport_scenario(index: int) -> void:
	var teleport_target := Vector2.ZERO
	if index % 2 == 0:
		teleport_target = Vector2(0.2, 0.1)
	else:
		teleport_target = Vector2(1.5, 0.0)
	_enemies[index % 8].set_combat_position(
		GroundUnit.ground_delta_gu_to_screen_delta_px(teleport_target),
		&"q2b_teleport"
	)
	_assert_scenario("teleport_%d" % index, false)


func _cross_map_scenario(index: int) -> void:
	_cross_map_enemy.set_combat_position(
		GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(0.0, 0.0)),
		&"q2b_cross_map"
	)
	_assert_scenario("cross_map_%d" % index, true)


func _assert_scenario(label: String, has_cross_map_enemy: bool) -> void:
	_scenario_count += 1
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var result: Dictionary = Reference.legacy_tick(
		_effect,
		_enemies,
		true,
		Callable(self, "_record_damage")
	)
	var candidates := _index.query_aabb_candidates(
		MAP_A,
		_bounds_for_snapshot(_effect.skill_footprint_snapshot),
		EXPANSION_GU
	)
	var candidate_ids: Dictionary = {}
	for candidate: Dictionary in candidates:
		var serial := int(candidate.get("actor_runtime_id", 0))
		var enemy: EnemyActor = _enemy_by_serial.get(serial)
		if enemy != null and is_instance_valid(enemy):
			candidate_ids[enemy.get_instance_id()] = true
	for enemy_id: int in result.get("exact_hit_ids", []):
		if not candidate_ids.has(enemy_id):
			_false_negative_count += 1
			push_error(
				"false negative in %s: exact hit %d missing from candidates"
				% [label, enemy_id]
			)
	if has_cross_map_enemy:
		var cross_id := _cross_map_enemy.get_instance_id()
		if candidate_ids.has(cross_id):
			_cross_map_leak_count += 1
			push_error(
				"cross-map leak in %s: map B enemy appeared in map A candidates"
				% label
			)


func _bounds_for_snapshot(snapshot: Dictionary) -> Rect2:
	var min_gu := Vector2.INF
	var max_gu := -Vector2.INF
	for raw_polygon: Variant in snapshot.get("polygons_ground_gu", []):
		if raw_polygon is PackedVector2Array:
			for point: Vector2 in raw_polygon as PackedVector2Array:
				min_gu.x = minf(min_gu.x, point.x)
				min_gu.y = minf(min_gu.y, point.y)
				max_gu.x = maxf(max_gu.x, point.x)
				max_gu.y = maxf(max_gu.y, point.y)
	return Rect2(min_gu, max_gu - min_gu)


func _fresh_world() -> void:
	_index = SpatialIndexScript.new()
	_manager = Fixtures.new_manager(_index)
	_enemies.clear()
	_cross_map_enemy = null


func _cleanup() -> void:
	if _effect != null and is_instance_valid(_effect):
		_effect.queue_free()
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	if _cross_map_enemy != null and is_instance_valid(_cross_map_enemy):
		_cross_map_enemy.queue_free()


func _record_damage(enemy: EnemyActor, amount: int) -> void:
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
