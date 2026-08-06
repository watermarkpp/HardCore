extends Node

const Projectile := preload("res://scripts/skill_projectile.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

var _index: SpatialIndexScript
var _enemies: Array[EnemyActor] = []
var _projectiles: Array[SkillProjectile] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	# 1) A projectile created after the index is ready must report it available.
	var projectile := _make_projectile(Vector2(0, 0))
	var diagnostics: Dictionary = projectile.projectile_broadphase_diagnostics()
	assert(
		bool(diagnostics.get("spatial_index_available", false)),
		"gameplay-created projectile must have a ready spatial index"
	)
	# 2) A registered enemy is queryable before it is targetable.
	var enemy := _make_enemy(Vector2(2.0, 0.0), 1)
	assert(
		_index.registered_actor_count() == 1,
		"enemy must be registered before entering targetable state"
	)
	# 3) Dynamic spawn registration happens on spawn.
	var dynamic_enemy := _make_enemy(Vector2(4.0, 0.0), 2)
	assert(
		_index.registered_actor_count() == 2,
		"dynamic spawn must register immediately"
	)
	# 4) A projectile WITHOUT the index must expose an explicit rejection
	# reason, never a silent ordinary miss.
	var orphan := Projectile.new()
	orphan.setup_ground_unit_projectile(
		Vector2.ZERO,
		Vector2.RIGHT,
		8.0,
		1,
		8.0,
		0.25,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"orphan"
	)
	orphan.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	)
	add_child(orphan)
	orphan._physics_process(1.0 / 60.0)
	var orphan_diag: Dictionary = orphan.projectile_broadphase_diagnostics()
	assert(
		not bool(orphan_diag.get("spatial_index_available", true)),
		"orphan projectile must report the index as unavailable"
	)
	assert(
		str(orphan_diag.get("spatial_index_rejection_reason", ""))
		== "broadphase_unavailable",
		"orphan projectile must expose an explicit rejection reason"
	)
	assert(
		int(orphan_diag.get("broadphase_unavailable_count", 0)) >= 1,
		"unavailable index must be counted in diagnostics"
	)
	orphan.queue_free()
	_cleanup()
	await get_tree().process_frame
	print("PROJECTILE_SPATIAL_INDEX_READY_CONTRACT_PASS")
	get_tree().quit(0)


func _make_enemy(center_ground_gu: Vector2, serial: int) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "ready_%d" % serial, "hp": 1000, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	)
	enemy.configure_spatial_index(_index, serial)
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	enemy.combat_radius_gu = 0.25
	add_child(enemy)
	_index.register(
		serial,
		1,
		center_ground_gu,
		0.25,
		serial,
		enemy,
		Callable(enemy, "spatial_index_position")
	)
	_enemies.append(enemy)
	return enemy


func _make_projectile(start_ground_gu: Vector2) -> SkillProjectile:
	var projectile := Projectile.new()
	projectile.setup_ground_unit_projectile(
		GroundUnit.ground_delta_gu_to_screen_delta_px(start_ground_gu),
		Vector2.RIGHT,
		12.0,
		999,
		8.0,
		0.25,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"ready-contract"
	)
	projectile.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	)
	projectile.configure_spatial_index(_index)
	add_child(projectile)
	_projectiles.append(projectile)
	return projectile


func _cleanup() -> void:
	for projectile: SkillProjectile in _projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_projectiles.clear()
	_enemies.clear()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
