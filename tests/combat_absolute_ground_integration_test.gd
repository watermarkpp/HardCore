extends Node

const Fixtures := preload(
	"res://tests/helpers/combat_absolute_ground_fixtures.gd"
)
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const ManagerScript := preload(
	"res://scripts/persistent_ground_effect_manager.gd"
)

const MAP_ID := 9001
const EPSILON := 0.0002

var _index: SpatialIndexScript
var _manager: ManagerScript
var _enemy: EnemyActor
var _mover: EnemyActor
var _hits: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	_index = SpatialIndexScript.new()
	_manager = ManagerScript.new(_index)
	var actor_abs := Vector2(130.0, 130.0)
	_enemy = Fixtures.make_enemy(
		self,
		_index,
		1,
		MAP_ID,
		actor_abs,
		Fixtures.DESIGN_256,
		0.3
	)
	# Enemy: register == provider == absolute, and forced movement updates the
	# index in the same call.
	assert(
		_enemy.spatial_index_position().distance_to(actor_abs) <= EPSILON,
		"integration: enemy provider must equal the absolute register"
	)
	_mover = Fixtures.make_enemy(
		self,
		_index,
		2,
		MAP_ID,
		Vector2(10.0, 10.0),
		Fixtures.DESIGN_256,
		0.3
	)
	var moved := Vector2(140.0, 135.0)
	Fixtures.move_enemy_absolute(_mover, moved, Fixtures.DESIGN_256)
	assert(
		_mover.spatial_index_position().distance_to(moved) <= EPSILON,
		"integration: forced movement must keep the provider absolute"
	)
	assert(
		_index.query_aabb_candidates(
			MAP_ID,
			Rect2(moved - Vector2(2, 2), Vector2(4, 4)),
			0.05
		).size() >= 1,
		"integration: same-call index must contain the moved actor"
	)
	# Projectile segment around the actor -> candidate contains the enemy and
	# the exact phase hits.
	var projectile := Fixtures.make_projectile(
		self,
		_index,
		MAP_ID,
		Vector2(128.0, 130.0),
		Vector2(1.0, 0.0),
		Fixtures.DESIGN_256,
		10.0
	)
	projectile._projectile_role_valid = true
	var projectile_hit := false
	for step in range(120):
		if not is_instance_valid(projectile):
			break
		projectile._physics_process(0.05)
		if int(projectile._broadphase_hit_count) >= 1:
			projectile_hit = true
			break
	assert(
		projectile_hit,
		"integration: projectile must hit the absolute enemy"
	)
	# Persistent ground effect at the actor -> candidate + exact hit.
	var context := Fixtures.absolute_context(
		MAP_ID,
		actor_abs,
		Fixtures.DESIGN_256
	)
	var pge_snapshot := Snapshot.create_circle(
		"wizard.ice_storm",
		"p0:integration:pge",
		actor_abs,
		2.5,
		24,
		context
	)
	var effect := GroundSkillEffect.new()
	effect.setup_ground_unit_effect(
		Fixtures.ground_to_screen(Fixtures.DESIGN_256).call(actor_abs),
		8,
		2.5,
		4.0,
		Color.WHITE,
		"wizard.ice_storm",
		0.8,
		60.0,
		"p0:integration:pge",
		pge_snapshot,
		context
	)
	effect.configure_runtime_resolution(
		null,
		Callable(),
		true,
		Callable(),
		Fixtures.screen_to_ground(Fixtures.DESIGN_256)
	)
	effect.manager_owned_damage_ticks = true
	add_child(effect)
	assert(
		_manager.register({
			"effect_runtime_id": 201,
			"skill_id": "wizard.ice_storm",
			"release_id": "p0:integration:pge",
			"snapshot_id": str(pge_snapshot.get("snapshot_id", "")),
			"runtime_map_id": MAP_ID,
			"canonical_snapshot": pge_snapshot,
			"expected_context": context,
			"tick_interval_s": 0.8,
			"expiration_s": 4.0,
			"stacking_policy": "replace",
			"claim_policy": "",
			"manager_owned_damage_ticks": true,
			"damage_callback": Callable(self, "_on_damage"),
			"effect": effect,
		}),
		"integration: PGE registration must accept the absolute snapshot"
	)
	_manager.tick_frame(0.8)
	assert(
		_hits.has(_enemy.get_instance_id()),
		"integration: PGE must hit the absolute enemy"
	)
	# FireWall covering the actor -> candidate + exact hit; summon snapshot
	# origin absolute; cross-map actor never appears.
	var controller := Fixtures.make_fire_wall_controller(
		self,
		_index,
		MAP_ID,
		actor_abs,
		Fixtures.DESIGN_256,
		Callable(self, "_on_fire_wall_tick"),
		null,
		"p0:integration:fw"
	)
	controller._apply_field_tick()
	var fw_diag: Dictionary = controller.fire_wall_controller_diagnostics()
	assert(
		int(fw_diag.get("candidate_count", 0)) >= 1,
		"integration: FireWall must find the absolute enemy"
	)
	assert(
		int(fw_diag.get("controller_exact_test_count", 0)) >= 1,
		"integration: FireWall must exact-hit the absolute enemy"
	)
	var summon := SummonActor.new()
	summon.setup(null, "骷髅", 10, 1, "taoist.summon_skeleton", 35)
	summon.global_position = Fixtures.ground_to_screen(
		Fixtures.DESIGN_256
	).call(actor_abs)
	summon.configure_runtime_map_projection(
		MAP_ID,
		Fixtures.ground_to_screen(Fixtures.DESIGN_256),
		Fixtures.screen_to_ground(Fixtures.DESIGN_256)
	)
	add_child(summon)
	summon.set_process(false)
	summon.set_physics_process(false)
	summon.configure_spawn_release_footprint("p0:integration:summon")
	assert(
		(
			summon.summon_spawn_footprint_snapshot.get(
				"origin_ground_gu",
				Vector2.ZERO
			) as Vector2
		).distance_to(actor_abs) <= EPSILON,
		"integration: summon spawn snapshot origin must be absolute"
	)
	# Cross-map isolation: an actor registered on 9002 never appears.
	Fixtures.make_enemy(
		self,
		_index,
		3,
		9002,
		actor_abs,
		Fixtures.DESIGN_256,
		0.3
	)
	var candidates: Array = _index.query_aabb_candidates(
		MAP_ID,
		Rect2(actor_abs - Vector2(3, 3), Vector2(6, 6)),
		0.05
	)
	for candidate: Dictionary in candidates:
		assert(
			int(candidate.get("actor_runtime_id", 0)) != 3,
			"integration: cross-map actor must never appear"
		)
	_cleanup()
	await get_tree().process_frame
	print("COMBAT_ABSOLUTE_GROUND_INTEGRATION_PASS")
	get_tree().quit(0)


func _on_damage(target: EnemyActor, _damage: int) -> void:
	if is_instance_valid(target):
		_hits.append(target.get_instance_id())


func _on_fire_wall_tick(_target: EnemyActor, _raw_power: int) -> void:
	pass


func _cleanup() -> void:
	for node: Node in get_children():
		node.queue_free()
