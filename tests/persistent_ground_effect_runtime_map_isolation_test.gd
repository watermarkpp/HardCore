extends Node

## Q2-B runtime map isolation: an effect on map A only queries map A buckets;
## a same-coordinate enemy on map B is never a candidate, never exact-tested
## and never damaged. Map transition clears the old map's registrations so a
## stale effect can never damage the newly loaded map.

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

const MAP_A := 9501
const MAP_B := 9502
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _manager: ManagerScript
var _enemies: Array[EnemyActor] = []
var _effects: Array[GroundSkillEffect] = []
var _damage_log: Array[int] = []
var _lifecycle_log: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_fresh_world()
	var enemy_a := Fixtures.make_enemy(
		self,
		_index,
		1,
		MAP_A,
		Vector2.ZERO,
		0.25
	)
	var enemy_b := Fixtures.make_enemy(
		self,
		_index,
		2,
		MAP_B,
		Vector2.ZERO,
		0.25
	)
	_enemies.append(enemy_a)
	_enemies.append(enemy_b)
	var serial_map := {1: enemy_a, 2: enemy_b}
	_effects.append(_make_registered_effect("A", 1, MAP_A))
	_effects.append(_make_registered_effect("B", 2, MAP_B))

	_manager.tick_frame(1.0)
	assert(
		_damage_log == [enemy_a.get_instance_id(), enemy_b.get_instance_id()],
		"each map effect must damage exactly its own map's enemy"
	)
	assert(
		_damage_log.count(enemy_a.get_instance_id()) == 1
		and _damage_log.count(enemy_b.get_instance_id()) == 1,
		"no cross-map exact hit may be damaged"
	)
	var candidates_a := _index.query_aabb_candidates(
		MAP_A,
		_bounds_for_snapshot(_effects[0].skill_footprint_snapshot),
		0.05
	)
	var candidates_b := _index.query_aabb_candidates(
		MAP_B,
		_bounds_for_snapshot(_effects[1].skill_footprint_snapshot),
		0.05
	)
	assert(
		_candidate_instance_ids(candidates_a, serial_map)
		== [enemy_a.get_instance_id()],
		"map A candidates must contain only the map A enemy"
	)
	assert(
		_candidate_instance_ids(candidates_b, serial_map)
		== [enemy_b.get_instance_id()],
		"map B candidates must contain only the map B enemy"
	)
	var diagnostics: Dictionary = _manager.persistent_ground_effect_diagnostics()
	assert(
		int(diagnostics.get("cross_map_rejection_count", -1)) == 0,
		"map-scoped query must produce zero cross-map candidates"
	)

	# Map transition: clear map A only; map B effect keeps working.
	_manager.clear_map(MAP_A)
	assert(
		_manager.registered_effect_count() == 1,
		"clear_map must unregister only the matching map"
	)
	_damage_log.clear()
	_manager.tick_frame(1.0)
	assert(
		_damage_log == [enemy_b.get_instance_id()],
		"after map A transition the map B effect must keep damaging map B"
	)
	assert(
		_manager.registered_effect_count() == 1,
		"map A effect must not linger after clear_map"
	)

	# Full world clear: nothing remains registered.
	_manager.clear_all()
	assert(
		_manager.registered_effect_count() == 0,
		"clear_all must unregister every effect"
	)
	assert(
		_lifecycle_log.count("map_cleared") == 2,
		"both effects must end through the lifecycle callback"
	)
	_cleanup()
	await get_tree().process_frame
	print("PERSISTENT_GROUND_EFFECT_RUNTIME_MAP_ISOLATION_PASS")
	get_tree().quit(0)


func _make_registered_effect(
	label: String,
	effect_id: int,
	map_id: int
) -> GroundSkillEffect:
	var effect := Fixtures.create_effect(
		self,
		SKILL_ID,
		"q2b:map:%s" % label,
		map_id,
		Vector2.ZERO,
		2.0,
		1.0,
		60.0,
		3,
		null,
		Callable(self, "_record_damage")
	)
	add_child(effect)
	var registered := Fixtures.register_effect(
		_manager,
		effect,
		effect_id,
		map_id,
		Callable(self, "_record_damage"),
		Callable(self, "_record_lifecycle")
	)
	assert(registered, "isolation effect must register")
	return effect


func _candidate_instance_ids(
	candidates: Array,
	serial_map: Dictionary
) -> Array[int]:
	var ids: Array[int] = []
	for candidate: Dictionary in candidates:
		var serial := int(candidate.get("actor_runtime_id", 0))
		var enemy: EnemyActor = serial_map.get(serial)
		if enemy != null and is_instance_valid(enemy):
			ids.append(enemy.get_instance_id())
	return ids


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
	_effects.clear()
	_damage_log.clear()
	_lifecycle_log.clear()


func _cleanup() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	for effect: GroundSkillEffect in _effects:
		if is_instance_valid(effect):
			effect.queue_free()


func _record_damage(enemy: EnemyActor, amount: int) -> void:
	_damage_log.append(enemy.get_instance_id())
	enemy.take_damage(amount, null)


func _record_lifecycle(reason: String, effect: Variant) -> void:
	_lifecycle_log.append(reason)
	if effect is Node and is_instance_valid(effect):
		(effect as Node).queue_free()


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
