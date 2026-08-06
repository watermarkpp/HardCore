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

const SCENARIO_COUNT := 100

var _index: SpatialIndexScript
var _enemies: Array[EnemyActor] = []
var _false_negative_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260806
	for scenario in range(SCENARIO_COUNT):
		_run_scenario(rng, scenario)
	assert(
		_false_negative_count == 0,
		"broadphase must not drop any enemy the exact phase would hit"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"PROJECTILE_BROADPHASE_NO_FALSE_NEGATIVE_PASS scenarios=%d false_negatives=0"
		% SCENARIO_COUNT
	)
	get_tree().quit(0)


func _run_scenario(rng: RandomNumberGenerator, scenario: int) -> void:
	_index = SpatialIndexScript.new()
	_enemies.clear()
	var start_ground := Vector2(
		rng.randf_range(-20.0, 20.0),
		rng.randf_range(-20.0, 20.0)
	)
	var direction_ground := Vector2.from_angle(rng.randf_range(0.0, TAU))
	var segment_length_gu := rng.randf_range(2.0, 24.0)
	var end_ground := start_ground + direction_ground * segment_length_gu
	var projectile_radius_gu := rng.randf_range(0.1, 0.8)
	var enemy_count := rng.randi_range(4, 24)
	var serial := 0
	for i in range(enemy_count):
		serial += 1
		var center := Vector2(
			rng.randf_range(-30.0, 30.0),
			rng.randf_range(-30.0, 30.0)
		)
		var radius := rng.randf_range(0.1, 1.5)
		_enemies.append(
			_make_enemy(center, radius, serial)
		)
	var release_snapshot := Snapshot.create_swept_capsule_path(
		"wizard.fireball",
		"no-fn:%d" % scenario,
		start_ground,
		end_ground,
		projectile_radius_gu,
		8,
		"",
		-1,
		Snapshot.make_absolute_runtime_context(
			1,
			start_ground,
			start_ground,
			Callable(self, "_ground_to_screen")
		)
	)
	var candidates := _index.query_segment_candidates(
		1,
		start_ground,
		end_ground,
		projectile_radius_gu
	)
	var candidate_ids: Dictionary = {}
	for candidate: Dictionary in candidates:
		candidate_ids[int(candidate.get("actor_runtime_id", 0))] = true
	var expected_context := _expected_context()
	for enemy: EnemyActor in _enemies:
		var hit := Reference.old_exact_intersects(
			release_snapshot,
			release_snapshot,
			GroundUnit.ground_delta_gu_to_screen_delta_px(start_ground),
			GroundUnit.ground_delta_gu_to_screen_delta_px(end_ground),
			enemy,
			expected_context,
			projectile_radius_gu
		)
		if hit and not candidate_ids.has(int(enemy.get_meta("spatial_id", 0))):
			_false_negative_count += 1
	_cleanup()


func _make_enemy(
	center_ground_gu: Vector2,
	combat_radius_gu: float,
	serial: int
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "fn_%d" % serial, "hp": 100, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	)
	enemy.configure_spatial_index(_index, serial)
	enemy.set_meta("spatial_id", serial)
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
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
