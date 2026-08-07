extends Node

const Projectile := preload("res://scripts/skill_projectile.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const Reference := preload(
	"res://tests/helpers/projectile_legacy_reference_query.gd"
)

var _index: SpatialIndexScript
var _enemies: Array[EnemyActor] = []
var _projectiles: Array[SkillProjectile] = []
var _case_count := 0
var _hit_difference_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_run_case("no_hit", Vector2(0, 0), Vector2.RIGHT, 8.0, [
		[Vector2(30, 0), 0.25],
	])
	_run_case("single_hit", Vector2(0, 0), Vector2.RIGHT, 8.0, [
		[Vector2(2, 0), 0.25],
	])
	_run_case("overlapping_enemies", Vector2(0, 0), Vector2.RIGHT, 8.0, [
		[Vector2(3, 0), 0.5],
		[Vector2(3.2, 0), 0.5],
		[Vector2(3.1, 0.1), 0.5],
	])
	_run_case("multiple_along_path", Vector2(0, 0), Vector2.RIGHT, 8.0, [
		[Vector2(1, 0), 0.25],
		[Vector2(3, 0), 0.25],
		[Vector2(5, 0), 0.25],
	])
	_run_case("already_hit_target", Vector2(0, 0), Vector2.RIGHT, 8.0, [
		[Vector2(2, 0), 0.25],
		[Vector2(2, 0), 0.25],
	])
	_run_case("boundary_target", Vector2(0, 0), Vector2.RIGHT, 8.0, [
		[Vector2(8.0, 0.25), 0.25],
	])
	assert(_hit_difference_count == 0, "new path must match legacy hit parity")
	_cleanup()
	await get_tree().process_frame
	print("PROJECTILE_BROADPHASE_HIT_PARITY_PASS cases=%d" % _case_count)
	get_tree().quit(0)


func _run_case(
	label: String,
	start_ground: Vector2,
	direction_screen: Vector2,
	speed_gu: float,
	enemy_specs: Array
) -> void:
	_case_count += 1
	_index = SpatialIndexScript.new()
	_enemies.clear()
	_projectiles.clear()
	var serial := 0
	for spec: Array in enemy_specs:
		serial += 1
		_enemies.append(
			_make_enemy(spec[0] as Vector2, float(spec[1]), serial)
		)
	var projectile := _make_projectile(
		start_ground,
		direction_screen,
		speed_gu,
		999
	)
	var expected_context := _expected_context()
	var previous_hp: Dictionary = {}
	for enemy: EnemyActor in _enemies:
		previous_hp[enemy.get_instance_id()] = enemy.current_hp
	for _step in range(120):
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			break
		var segment_start_px := projectile.global_position
		projectile._physics_process(1.0 / 60.0)
		var segment_end_px := projectile.global_position
		var reference_hit := Reference.old_path_first_hit(
			projectile.skill_footprint_snapshot,
			projectile.last_segment_footprint_snapshot,
			segment_start_px,
			segment_end_px,
			_enemies,
			expected_context,
			projectile.projectile_radius_gu
		)
		var actual_hit: EnemyActor = null
		for enemy: EnemyActor in _enemies:
			if int(previous_hp.get(enemy.get_instance_id(), 0)) > enemy.current_hp:
				actual_hit = enemy
				break
		if actual_hit != null:
			previous_hp[actual_hit.get_instance_id()] = actual_hit.current_hp
		var ref_id := (
			reference_hit.get_instance_id()
			if reference_hit != null
			else 0
		)
		var actual_id := (
			actual_hit.get_instance_id()
			if actual_hit != null
			else 0
		)
		if ref_id != actual_id:
			_hit_difference_count += 1
			break
	_cleanup()


func _make_enemy(
	center_ground_gu: Vector2,
	combat_radius_gu: float,
	serial: int
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "parity_%d" % serial, "hp": 1000, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)
	enemy.configure_spatial_index(_index, 1000 + serial)
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	enemy.combat_radius_gu = combat_radius_gu
	add_child(enemy)
	_index.register(
		1000 + serial,
		1,
		center_ground_gu,
		combat_radius_gu,
		1000 + serial,
		enemy
	)
	return enemy


func _make_projectile(
	start_ground_gu: Vector2,
	direction_screen: Vector2,
	speed_gu: float,
	damage: int
) -> SkillProjectile:
	var projectile := Projectile.new()
	projectile.setup_ground_unit_projectile(
		GroundUnit.ground_delta_gu_to_screen_delta_px(start_ground_gu),
		GroundUnit.screen_delta_px_to_ground_delta_gu(
			direction_screen
		).normalized(),
		40.0,
		damage,
		speed_gu,
		0.25,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"parity:%d" % _case_count
	)
	projectile.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)
	projectile.configure_spatial_index(_index)
	add_child(projectile)
	_projectiles.append(projectile)
	return projectile


func _expected_context() -> Dictionary:
	var context := Snapshot.make_absolute_runtime_context(
		1,
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(self, "_ground_to_screen")
	)
	context["expected_runtime_map_id"] = 1
	return context


func _cleanup() -> void:
	for projectile: SkillProjectile in _projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	_projectiles.clear()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
