extends Node

const Projectile := preload("res://scripts/skill_projectile.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

var _index: SpatialIndexScript
var _enemies: Array[EnemyActor] = []
var _projectiles: Array[SkillProjectile] = []
var _projectile_queries_before_enemy_tick := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	var enemy := _make_enemy(Vector2(2.0, 0.0), 1)
	var projectile := _make_projectile(Vector2(0, 0))
	# Manually arrange: the projectile query runs BEFORE the enemy's next
	# physics tick. The enemy was already moved via set_combat_position and the
	# index entry is current, so the query must still find it.
	enemy.set_physics_process(false)
	enemy.set_combat_position(
		GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(2.0, 0.0)),
		&"test_position"
	)
	_projectile_queries_before_enemy_tick += 1
	projectile._physics_process(1.0 / 60.0)
	var diagnostics: Dictionary = projectile.projectile_broadphase_diagnostics()
	assert(
		int(diagnostics.get("exact_test_count", 0)) >= 1,
		"projectile query before enemy tick must still find the registered enemy"
	)
	assert(
		_projectile_queries_before_enemy_tick == 1,
		"query ordering fixture must run before the enemy tick"
	)
	_cleanup()
	await get_tree().process_frame
	print("PROJECTILE_SPATIAL_INDEX_QUERY_BEFORE_ENEMY_TICK_PASS")
	get_tree().quit(0)


func _make_enemy(center_ground_gu: Vector2, serial: int) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "order_%d" % serial, "hp": 1000, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)
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
		"query-order"
	)
	projectile.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)
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
