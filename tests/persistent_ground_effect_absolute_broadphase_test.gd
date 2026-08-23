extends Node

const Fixtures := preload(
	"res://tests/helpers/combat_absolute_ground_fixtures.gd"
)
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const ManagerScript := preload(
	"res://scripts/persistent_ground_effect_manager.gd"
)
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")

const MAP_ID := 9001
const EPSILON := 0.0002

var _index: SpatialIndexScript
var _manager: ManagerScript
var _enemy: EnemyActor
var _cross_enemy: EnemyActor
var _hits: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	_manager = ManagerScript.new(_index)
	var center_abs := Vector2(130.0, 130.0)
	_enemy = Fixtures.make_enemy(
		self,
		_index,
		1,
		MAP_ID,
		center_abs,
		Fixtures.DESIGN_256,
		0.3
	)
	_cross_enemy = Fixtures.make_enemy(
		self,
		_index,
		2,
		9002,
		center_abs,
		Fixtures.DESIGN_256,
		0.3
	)
	var context := Fixtures.absolute_context(MAP_ID, center_abs, Fixtures.DESIGN_256)
	var snapshot := Snapshot.create_circle(
		"wizard.ice_storm",
		"p0:pge:1",
		center_abs,
		3.0,
		24,
		context
	)
	var effect := GroundSkillEffect.new()
	effect.setup_ground_unit_effect(
		Fixtures.ground_to_screen(Fixtures.DESIGN_256).call(center_abs),
		9,
		3.0,
		5.0,
		Color.WHITE,
		"wizard.ice_storm",
		0.8,
		60.0,
		"p0:pge:1",
		snapshot,
		context
	)
	effect.configure_runtime_resolution(
		null,
		Callable(self, "_on_tick"),
		true,
		Callable(),
		Fixtures.screen_to_ground(Fixtures.DESIGN_256)
	)
	effect.manager_owned_damage_ticks = true
	add_child(effect)
	var registered := _manager.register({
		"effect_runtime_id": 101,
		"skill_id": "wizard.ice_storm",
		"release_id": "p0:pge:1",
		"snapshot_id": str(snapshot.get("snapshot_id", "")),
		"runtime_map_id": MAP_ID,
		"canonical_snapshot": snapshot,
		"expected_context": context,
		"tick_interval_s": 0.8,
		"expiration_s": 5.0,
		"stacking_policy": "replace",
		"claim_policy": "",
		"manager_owned_damage_ticks": true,
		"damage_callback": Callable(self, "_on_damage"),
		"effect": effect,
	})
	assert(registered, "PGE manager must accept the absolute canonical snapshot")
	_manager.tick_frame(0.8)
	var diag: Dictionary = _manager.persistent_ground_effect_diagnostics()
	assert(
		int(diag.get("broadphase_query_count", 0)) >= 1,
		"PGE manager must run an absolute broadphase query"
	)
	assert(
		_hits.has(_enemy.get_instance_id()),
		"PGE absolute broadphase + exact phase must hit the enemy at map center"
	)
	assert(
		not _hits.has(_cross_enemy.get_instance_id()),
		"cross-map enemy must never be hit by the absolute PGE query"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"PERSISTENT_GROUND_EFFECT_ABSOLUTE_BROADPHASE_PASS candidates=%d exact=%d hits=%d"
		% [
			int(diag.get("total_candidate_count", 0)),
			int(diag.get("exact_intersection_test_count", 0)),
			_hits.size(),
		]
	)
	get_tree().quit(0)


func _on_tick(_target: EnemyActor, _damage: int) -> void:
	pass


func _on_damage(target: EnemyActor, _damage: int) -> void:
	if is_instance_valid(target):
		_hits.append(target.get_instance_id())


func _cleanup() -> void:
	for node: Node in get_children():
		node.queue_free()
