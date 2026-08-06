extends Node

## Q2-B spatial service reuse: Projectile and GroundEffect must consume the
## same RuntimeCombatSpatialIndex instance. Enemies are registered exactly
## once; no second enemy grid exists.

const Fixtures := preload(
	"res://tests/helpers/persistent_ground_effect_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Projectile := preload("res://scripts/skill_projectile.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const ManagerScript := preload(
	"res://scripts/persistent_ground_effect_manager.gd"
)

const MAP_A := 9901
const SKILL_ID := "wizard.fire_wall"
const SPATIAL_CONTRACT_ID := (
	"hardcore.combat.spatial_index.map_ground_gu_buckets.v1"
)

var _index: SpatialIndexScript
var _manager: ManagerScript
var _enemies: Array[EnemyActor] = []
var _effects: Array[GroundSkillEffect] = []
var _projectile: SkillProjectile


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	_manager = Fixtures.new_manager(_index)
	var positions := [
		Vector2(0, 0),
		Vector2(0.3, 0),
		Vector2(0, 0.3),
		Vector2(0.2, 0.2),
	]
	for i: int in range(4):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				i + 1,
				MAP_A,
				positions[i],
				0.25
			)
		)
	_effects.append(
		Fixtures.create_effect(
			self,
			SKILL_ID,
			"q2b:reuse:ground",
			MAP_A,
			Vector2.ZERO,
			2.0,
			1.0,
			60.0,
			3,
			null,
			Callable(self, "_record_damage")
		)
	)
	add_child(_effects[0])
	Fixtures.register_effect(
		_manager,
		_effects[0],
		1,
		MAP_A,
		Callable(self, "_record_damage")
	)

	_projectile = Projectile.new()
	_projectile.setup_ground_unit_projectile(
		GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(-4, 0)),
		Vector2.RIGHT,
		80.0,
		999,
		8.0,
		0.25,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"q2b:reuse:projectile"
	)
	_projectile.configure_runtime_map_projection(
		MAP_A,
		Callable(self, "_ground_to_screen")
	)
	_projectile.configure_spatial_index(_index)
	add_child(_projectile)

	assert(
		str(_index.diagnostics().get("contract_id", ""))
		== SPATIAL_CONTRACT_ID,
		"the shared service must be the formal RuntimeCombatSpatialIndex"
	)
	assert(
		_index.registered_actor_count() == 4,
		"each enemy must be registered exactly once"
	)
	assert(
		_index.index_register_count == 4,
		"enemy registration count must equal the enemy count (no second grid)"
	)

	var queries_before_ground := _index.index_query_count
	_manager.tick_frame(1.0)
	assert(
		_index.index_query_count > queries_before_ground,
		"ground effect manager must query the shared index"
	)
	var queries_before_projectile := _index.index_query_count
	_projectile._physics_process(1.0 / 60.0)
	assert(
		_index.index_query_count > queries_before_projectile,
		"projectile must query the same shared index"
	)
	var projectile_diagnostics: Dictionary = (
		_projectile.projectile_broadphase_diagnostics()
	)
	assert(
		bool(projectile_diagnostics.get("spatial_index_available", false)),
		"projectile must see the shared index as available"
	)
	var manager_diagnostics: Dictionary = (
		_manager.persistent_ground_effect_diagnostics()
	)
	assert(
		int(manager_diagnostics.get("broadphase_query_count", 0)) == 1,
		"ground effect manager must run exactly one broadphase query per tick"
	)
	assert(
		int(manager_diagnostics.get("damage_application_count", 0)) == 4,
		"the four same-map enemies must be damaged through the shared service"
	)
	assert(
		_index.index_total_candidate_count >= 4,
		"one shared candidate pool must serve both consumers"
	)
	_cleanup()
	await get_tree().process_frame
	print("PERSISTENT_GROUND_EFFECT_SPATIAL_SERVICE_REUSE_PASS")
	get_tree().quit(0)


func _cleanup() -> void:
	if _projectile != null and is_instance_valid(_projectile):
		_projectile.queue_free()
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	for effect: GroundSkillEffect in _effects:
		if is_instance_valid(effect):
			effect.queue_free()


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
