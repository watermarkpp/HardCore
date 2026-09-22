extends Node

## R1-C: the manager's last direct-damage escape hatch is closed. A
## callback-less, adapter-less effect must deliver damage only through the
## shared CombatRuntimeService authority (injected by the owner), and must
## refuse delivery when no service is available (fail-closed, counted).

const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const ManagerScript := preload(
	"res://scripts/persistent_ground_effect_manager.gd"
)
const CombatRuntimeServiceScript := preload(
	"res://scripts/layers/runtime/combat_runtime_service.gd"
)
const Fixtures := preload(
	"res://tests/helpers/persistent_ground_effect_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")

const SKILL_ID := "wizard.fire_wall"
const MAP_A := 4101
const DAMAGE := 7

var _index: RuntimeCombatSpatialIndex
var _effect: GroundSkillEffect
var _enemy: EnemyActor
var _service: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Case 1: injected service — the fallback delivers through the shared
	# authority with the exact amount and source attribution.
	_service = CombatRuntimeServiceScript.new()
	_run_delivery_case(true)
	# Case 2: no injected service — delivery is refused and counted
	# (fail-closed; no direct delivery path remains in the manager).
	_run_delivery_case(false)
	if is_instance_valid(_service):
		_service.free()
	print("PERSISTENT_GROUND_EFFECT_SERVICE_DAMAGE_DELIVERY_PASS")
	get_tree().quit(0)


func _run_delivery_case(service_injected: bool) -> void:
	_index = SpatialIndexScript.new()
	var manager: PersistentGroundEffectManager = (
		ManagerScript.new(_index, _service if service_injected else null)
	)
	# Callable() damage applier: the effect's runtime_tick_adapter and the
	# entry's damage_callback are both invalid, so the tick reaches the
	# manager's fallback branch.
	_effect = Fixtures.create_effect(
		self,
		SKILL_ID,
		"r1c:service:%s" % str(service_injected),
		MAP_A,
		Vector2.ZERO,
		2.0,
		0.8,
		5.0,
		DAMAGE,
		null,
		Callable()
	)
	add_child(_effect)
	_enemy = Fixtures.make_enemy(
		self, _index, 1, MAP_A, Vector2.ZERO, 0.25
	)
	assert(
		Fixtures.register_effect(manager, _effect, 1, MAP_A, Callable()),
		"fallback-delivery effect must register"
	)
	var hp_before := _enemy.current_hp
	manager.tick_frame(0.016)
	if service_injected:
		assert(
			_enemy.current_hp == hp_before - DAMAGE,
			"fallback delivery must route through the shared service "
			+ "with the exact amount"
		)
		assert(
			manager.damage_delivery_skip_count == 0,
			"an injected service must never skip delivery"
		)
	else:
		assert(
			_enemy.current_hp == hp_before,
			"without a service the fallback must not deliver damage"
		)
		assert(
			manager.damage_delivery_skip_count == 1,
			"refused delivery must be counted"
		)
	_effect.queue_free()
	_enemy.queue_free()
	manager.clear_all()


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
		_screen_to_ground(enemy.global_position),
		enemy.combat_radius_gu
	)
