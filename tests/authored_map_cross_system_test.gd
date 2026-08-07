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
const Mapper := preload("res://scripts/map_coordinate_mapper.gd")

const MAP_ID := 248
const SIZE := Vector2i(400, 400)

var _index: SpatialIndexScript
var _manager: ManagerScript
var _enemy: EnemyActor
var _hits: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var profile: Dictionary = Mapper.resolve_map_projection_profile(MAP_ID)
	assert(
		str(profile.get("policy", ""))
		== str(Mapper.PROJECTION_POLICY_AUTHORED_SOURCE_ABSOLUTE),
		"cross-system test must run under the map 248 authored profile"
	)
	_index = SpatialIndexScript.new()
	_manager = ManagerScript.new(_index)
	var actor_abs := Vector2(89.0, 75.0)
	_enemy = Fixtures.make_enemy(
		self,
		_index,
		1,
		MAP_ID,
		actor_abs,
		SIZE,
		0.3
	)
	# Projectile through the enemy under the authored profile.
	var projectile := Fixtures.make_projectile(
		self,
		_index,
		MAP_ID,
		Vector2(85.0, 75.0),
		Vector2(1.0, 0.0),
		SIZE,
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
	assert(projectile_hit, "authored-map projectile must hit the enemy")
	# Persistent ground effect at the actor.
	var context := Fixtures.absolute_context(MAP_ID, actor_abs, SIZE)
	var pge_snapshot := Snapshot.create_circle(
		"wizard.ice_storm",
		"p02:pge:248",
		actor_abs,
		2.5,
		24,
		context
	)
	var effect := GroundSkillEffect.new()
	effect.setup_ground_unit_effect(
		Fixtures.ground_to_screen(SIZE).call(actor_abs),
		8,
		2.5,
		4.0,
		Color.WHITE,
		"wizard.ice_storm",
		0.8,
		60.0,
		"p02:pge:248",
		pge_snapshot,
		context
	)
	effect.configure_runtime_resolution(
		null,
		Callable(),
		true,
		Callable(),
		Fixtures.screen_to_ground(SIZE)
	)
	effect.manager_owned_damage_ticks = true
	add_child(effect)
	assert(
		_manager.register({
			"effect_runtime_id": 301,
			"skill_id": "wizard.ice_storm",
			"release_id": "p02:pge:248",
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
		"authored-map PGE registration must accept the STRICT_V2 snapshot"
	)
	_manager.tick_frame(0.8)
	assert(
		_hits.has(_enemy.get_instance_id()),
		"authored-map PGE must hit the enemy"
	)
	# FireWall covering the actor.
	var controller := Fixtures.make_fire_wall_controller(
		self,
		_index,
		MAP_ID,
		actor_abs,
		SIZE,
		Callable(self, "_on_fire_wall_tick"),
		null,
		"p02:fw:248"
	)
	controller._apply_field_tick()
	var fw_diag: Dictionary = controller.fire_wall_controller_diagnostics()
	assert(
		int(fw_diag.get("candidate_count", 0)) >= 1,
		"authored-map FireWall must find the enemy"
	)
	assert(
		int(fw_diag.get("controller_exact_test_count", 0)) >= 1,
		"authored-map FireWall must exact-hit the enemy"
	)
	# Summon snapshot origin absolute under the authored profile.
	var summon := SummonActor.new()
	summon.setup(null, "骷髅", 10, 1, "taoist.summon_skeleton", 35)
	summon.global_position = Fixtures.ground_to_screen(SIZE).call(actor_abs)
	summon.configure_runtime_map_projection(
		MAP_ID,
		Fixtures.ground_to_screen(SIZE),
		Fixtures.screen_to_ground(SIZE)
	)
	add_child(summon)
	summon.set_process(false)
	summon.set_physics_process(false)
	summon.configure_spawn_release_footprint("p02:summon:248")
	assert(
		(
			summon.summon_spawn_footprint_snapshot.get(
				"origin_ground_gu",
				Vector2.ZERO
			) as Vector2
		).distance_to(actor_abs) <= 0.001,
		"authored-map summon spawn snapshot origin must be absolute"
	)
	assert(
		int(summon.summon_spawn_footprint_snapshot.get("runtime_map_id", -1))
		== MAP_ID,
		"authored-map summon snapshot must carry runtime_map_id 248"
	)
	# Cross-map isolation under the authored profile.
	Fixtures.make_enemy(
		self,
		_index,
		2,
		9999,
		actor_abs,
		SIZE,
		0.3
	)
	var candidates: Array = _index.query_aabb_candidates(
		MAP_ID,
		Rect2(actor_abs - Vector2(3, 3), Vector2(6, 6)),
		0.05
	)
	for candidate: Dictionary in candidates:
		assert(
			int(candidate.get("actor_runtime_id", 0)) != 2,
			"cross-map actor must never appear under the authored profile"
		)
	_cleanup()
	await get_tree().process_frame
	print("AUTHORED_MAP_CROSS_SYSTEM_PASS map=%d policy=%s" % [MAP_ID, profile.get("policy", "")])
	get_tree().quit(0)


func _on_damage(target: EnemyActor, _damage: int) -> void:
	if is_instance_valid(target):
		_hits.append(target.get_instance_id())


func _on_fire_wall_tick(_target: EnemyActor, _raw_power: int) -> void:
	pass


func _cleanup() -> void:
	for node: Node in get_children():
		node.queue_free()
