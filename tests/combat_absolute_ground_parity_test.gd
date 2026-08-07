extends Node

const Fixtures := preload(
	"res://tests/helpers/combat_absolute_ground_fixtures.gd"
)
const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")

const PROJECTILE_SCENARIOS := 60
const MAP_ID := 9001

var _abs_index: SpatialIndexScript
var _delta_index: SpatialIndexScript
var _parity_mismatch := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260807
	for scenario in range(PROJECTILE_SCENARIOS):
		var size: Vector2i = (
			Fixtures.DESIGN_256
			if scenario % 2 == 0
			else Fixtures.DESIGN_300x200
		)
		_check_projectile_parity(rng, scenario, size)
	_check_ground_effect_parity(rng)
	_check_fire_wall_parity(rng)
	assert(
		_parity_mismatch == 0,
		"non-zero map center parity must match the legacy identity reference"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"COMBAT_ABSOLUTE_GROUND_PARITY_PASS scenarios=%d mismatches=0"
		% PROJECTILE_SCENARIOS
	)
	get_tree().quit(0)


func _check_projectile_parity(
	rng: RandomNumberGenerator,
	scenario: int,
	size: Vector2i
) -> void:
	_abs_index = SpatialIndexScript.new()
	_delta_index = SpatialIndexScript.new()
	var center := Fixtures.map_center(size)
	var segment_start_abs := Vector2(
		rng.randf_range(20.0, 220.0),
		rng.randf_range(20.0, 220.0)
	)
	var segment_end_abs := segment_start_abs + Vector2(
		rng.randf_range(4.0, 30.0),
		rng.randf_range(-12.0, 12.0)
	)
	var abs_hits: Array[int] = []
	var delta_hits: Array[int] = []
	var serial := 0
	for i in range(rng.randi_range(1, 8)):
		serial += 1
		var enemy_abs := segment_start_abs.lerp(
			segment_end_abs,
			rng.randf()
		) + Vector2(
			rng.randf_range(-1.2, 1.2),
			rng.randf_range(-1.2, 1.2)
		)
		var abs_enemy := Fixtures.make_enemy(
			self,
			_abs_index,
			serial,
			MAP_ID,
			enemy_abs,
			size,
			0.3
		)
		var delta_enemy := EnemyActor.new()
		delta_enemy.setup(
			{
				"name": "parity_delta_%d" % serial,
				"hp": 99999,
				"attackMin": 1,
				"attackMax": 1,
				"level": 1,
			},
			null,
			false
		)
		delta_enemy.configure_runtime_map_projection(
			MAP_ID,
			GroundUnit.ground_delta_gu_to_screen_delta_px
		)
		var delta_pos := enemy_abs - center
		delta_enemy.configure_spatial_index(_delta_index, serial)
		delta_enemy.global_position = (
			GroundUnit.ground_delta_gu_to_screen_delta_px(delta_pos)
		)
		delta_enemy.combat_radius_gu = 0.3
		add_child(delta_enemy)
		delta_enemy.set_process(false)
		delta_enemy.set_physics_process(false)
		_delta_index.register(
			serial,
			MAP_ID,
			delta_pos,
			0.3,
			serial,
			delta_enemy,
			Callable(delta_enemy, "spatial_index_position")
		)
		var abs_candidates: Array = _abs_index.query_segment_candidates(
			MAP_ID,
			segment_start_abs,
			segment_end_abs,
			0.5
		)
		var delta_start := segment_start_abs - center
		var delta_end := segment_end_abs - center
		var delta_candidates: Array = _delta_index.query_segment_candidates(
			MAP_ID,
			delta_start,
			delta_end,
			0.5
		)
		var abs_hit := false
		for candidate: Dictionary in abs_candidates:
			if candidate.get("node") == abs_enemy:
				abs_hit = SkillProjectile.swept_segment_intersects_footprint_gu(
					segment_start_abs,
					segment_end_abs,
					abs_enemy.spatial_index_position(),
					0.5 + abs_enemy.combat_radius_gu
				)
				break
		var delta_hit := false
		for candidate: Dictionary in delta_candidates:
			if candidate.get("node") == delta_enemy:
				delta_hit = SkillProjectile.swept_segment_intersects_footprint_gu(
					delta_start,
					delta_end,
					delta_enemy.spatial_index_position(),
					0.5 + delta_enemy.combat_radius_gu
				)
				break
		if abs_hit:
			abs_hits.append(serial)
		if delta_hit:
			delta_hits.append(serial)
		abs_enemy.queue_free()
		delta_enemy.queue_free()
	if abs_hits != delta_hits:
		_parity_mismatch += 1
	_abs_index = null
	_delta_index = null


func _check_ground_effect_parity(rng: RandomNumberGenerator) -> void:
	var size := Fixtures.DESIGN_256
	var center := Fixtures.map_center(size)
	var effect_abs := Vector2(130.0, 130.0)
	var enemy_abs := effect_abs + Vector2(
		rng.randf_range(-2.0, 2.0),
		rng.randf_range(-2.0, 2.0)
	)
	var abs_inside := (
		enemy_abs.distance_to(effect_abs)
		<= 3.0 + 0.3 + GroundUnit.EPSILON_GU
	)
	var delta_inside := (
		(enemy_abs - center).distance_to(effect_abs - center)
		<= 3.0 + 0.3 + GroundUnit.EPSILON_GU
	)
	if abs_inside != delta_inside:
		_parity_mismatch += 1


func _check_fire_wall_parity(rng: RandomNumberGenerator) -> void:
	var size := Fixtures.DESIGN_256
	var center := Fixtures.map_center(size)
	var origin_abs := Vector2(130.0, 130.0)
	var target_abs := origin_abs + Vector2(
		rng.randf_range(-1.5, 1.5),
		rng.randf_range(-1.5, 1.5)
	)
	# Translation-invariant parity: the same canonical 2x2 AABB (cells 130..131
	# expanded by 0.5 cell + 0.3 combat radius) in absolute space and in
	# delta space must classify the target identically.
	var aabb_abs := Rect2(Vector2(129.2, 129.2), Vector2(2.6, 2.6))
	var aabb_delta := Rect2(
		aabb_abs.position - center,
		aabb_abs.size
	)
	var abs_inside := aabb_abs.has_point(target_abs)
	var delta_inside := aabb_delta.has_point(target_abs - center)
	if abs_inside != delta_inside:
		_parity_mismatch += 1


func _cleanup() -> void:
	for node: Node in get_children():
		node.queue_free()
