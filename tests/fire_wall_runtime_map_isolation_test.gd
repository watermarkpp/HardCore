extends Node

## Q2-C runtime map isolation: a FireWall controller queries only its own map's
## buckets; same-coordinate cross-map enemies are never candidates, exact-tested
## or damaged; after a map transition a stale controller never damages the new
## map.

const Fixtures := preload(
	"res://tests/helpers/fire_wall_controller_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const FireWallFieldController := preload(
	"res://scripts/fire_wall_field_controller.gd"
)

const MAP_A := 11009
const MAP_B := 11010
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _controller_a: FireWallFieldController
var _controller_b: FireWallFieldController
var _enemies: Array[EnemyActor] = []
var _damage_log: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	var enemy_a := Fixtures.make_enemy(
		self,
		_index,
		1,
		MAP_A,
		Vector2(0.2, 0.2)
	)
	var enemy_b := Fixtures.make_enemy(
		self,
		_index,
		2,
		MAP_B,
		Vector2(0.2, 0.2)
	)
	_enemies.append(enemy_a)
	_enemies.append(enemy_b)
	_controller_a = Fixtures.make_controller(
		self,
		_index,
		MAP_A,
		Vector2(0, 0),
		{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
		"q2c:isolation:A",
		null,
		Callable(self, "_record_damage")
	)
	_controller_b = Fixtures.make_controller(
		self,
		_index,
		MAP_B,
		Vector2(0, 0),
		{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
		"q2c:isolation:B",
		null,
		Callable(self, "_record_damage")
	)
	_controller_a._apply_field_tick()
	assert(
		_damage_log.count(enemy_a.get_instance_id()) == 1
		and _damage_log.count(enemy_b.get_instance_id()) == 0,
		"map A controller must damage only the map A enemy"
	)
	_damage_log.clear()
	_controller_b._apply_field_tick()
	assert(
		_damage_log.count(enemy_a.get_instance_id()) == 0
		and _damage_log.count(enemy_b.get_instance_id()) == 1,
		"map B controller must damage only the map B enemy"
	)
	var candidates_a := _index.query_aabb_candidates(
		MAP_A,
		Rect2(Vector2(-0.5, -0.5), Vector2(2.0, 2.0)),
		0.05
	)
	assert(
		_candidate_ids(candidates_a) == [enemy_a.get_instance_id()],
		"map A candidates must contain only the map A enemy"
	)
	var candidates_b := _index.query_aabb_candidates(
		MAP_B,
		Rect2(Vector2(-0.5, -0.5), Vector2(2.0, 2.0)),
		0.05
	)
	assert(
		_candidate_ids(candidates_b) == [enemy_b.get_instance_id()],
		"map B candidates must contain only the map B enemy"
	)
	# Map transition: the map A controller must never damage a newly registered
	# map B enemy at the same coordinates.
	var new_enemy_b := Fixtures.make_enemy(
		self,
		_index,
		3,
		MAP_B,
		Vector2(0.2, 0.2)
	)
	_enemies.append(new_enemy_b)
	_damage_log.clear()
	_controller_a._apply_field_tick()
	assert(
		_damage_log.count(new_enemy_b.get_instance_id()) == 0,
		"stale map A controller must not damage the new map"
	)
	_cleanup()
	await get_tree().process_frame
	print("FIRE_WALL_RUNTIME_MAP_ISOLATION_PASS")
	get_tree().quit(0)


func _candidate_ids(candidates: Array) -> Array[int]:
	var ids: Array[int] = []
	var serial_map := {1: _enemies[0], 2: _enemies[1]}
	for candidate: Dictionary in candidates:
		var enemy: EnemyActor = serial_map.get(
			int(candidate.get("actor_runtime_id", 0))
		)
		if enemy != null and is_instance_valid(enemy):
			ids.append(enemy.get_instance_id())
	return ids


func _cleanup() -> void:
	if _controller_a != null and is_instance_valid(_controller_a):
		_controller_a.queue_free()
	if _controller_b != null and is_instance_valid(_controller_b):
		_controller_b.queue_free()
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()


func _record_damage(enemy: EnemyActor, raw_power: int) -> void:
	_damage_log.append(enemy.get_instance_id())
	enemy.take_damage(raw_power, null)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)
