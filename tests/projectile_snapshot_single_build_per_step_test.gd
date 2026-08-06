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
	# 16 enemies near the lane to produce candidates every step.
	for i in range(16):
		_enemies.append(_make_enemy(Vector2(2.0 + i * 0.4, 0.0), 0.25, i + 1))
	var projectile := _make_projectile(Vector2(0, 0), 8.0)
	var steps := 0
	for _step in range(40):
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			break
		projectile._physics_process(1.0 / 60.0)
		steps += 1
	var diagnostics: Dictionary = projectile.projectile_broadphase_diagnostics()
	var build_count := int(diagnostics.get("snapshot_build_count", 0))
	var query_count := int(diagnostics.get("broadphase_query_count", 0))
	var candidate_count := int(diagnostics.get("total_candidate_count", 0))
	assert(
		build_count == steps,
		"one snapshot per projectile physics step, got %d steps / %d builds"
		% [steps, build_count]
	)
	assert(
		query_count == steps,
		"one broadphase query per step"
	)
	assert(
		candidate_count >= steps,
		"candidates were present each step"
	)
	assert(
		build_count * 4 < candidate_count or build_count == steps,
		"snapshot builds must never multiply with candidate count"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"PROJECTILE_SNAPSHOT_SINGLE_BUILD_PER_STEP_PASS steps=%d builds=%d candidates=%d"
		% [steps, build_count, candidate_count]
	)
	get_tree().quit(0)


func _make_enemy(
	center_ground_gu: Vector2,
	combat_radius_gu: float,
	serial: int
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "sb_%d" % serial, "hp": 1000, "attackMin": 1, "attackMax": 1, "level": 1},
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
	enemy.combat_radius_gu = combat_radius_gu
	add_child(enemy)
	_index.register(
		serial,
		1,
		center_ground_gu,
		combat_radius_gu,
		serial,
		enemy
	)
	return enemy


func _make_projectile(start_ground_gu: Vector2, speed_gu: float) -> SkillProjectile:
	var projectile := Projectile.new()
	projectile.setup_ground_unit_projectile(
		GroundUnit.ground_delta_gu_to_screen_delta_px(start_ground_gu),
		Vector2.RIGHT,
		40.0,
		999,
		speed_gu,
		0.25,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"single-build"
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
