extends Node

const Fixtures := preload(
	"res://tests/helpers/combat_absolute_ground_fixtures.gd"
)
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const STATIC_SCENARIOS := 100
const MOVEMENT_SCENARIOS := 30
const SAME_FRAME_SCENARIOS := 30
const KNOCKBACK_SCENARIOS := 30
const CROSS_MAP_SCENARIOS := 20

var _index: SpatialIndexScript
var _enemies: Array[EnemyActor] = []
var _false_negative_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260807
	_run_static(rng)
	_run_movement(rng)
	_run_same_frame(rng)
	_run_knockback(rng)
	_run_cross_map(rng)
	assert(
		_false_negative_count == 0,
		"map-aware absolute shared index must have zero false negatives"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"SHARED_SPATIAL_INDEX_ABSOLUTE_CONTRACT_PASS static=%d movement=%d same_frame=%d knockback=%d cross_map=%d false_negatives=0"
		% [
			STATIC_SCENARIOS,
			MOVEMENT_SCENARIOS,
			SAME_FRAME_SCENARIOS,
			KNOCKBACK_SCENARIOS,
			CROSS_MAP_SCENARIOS,
		]
	)
	get_tree().quit(0)


func _random_absolute(rng: RandomNumberGenerator) -> Vector2:
	# At least half of the positions land far from the map center.
	if rng.randf() < 0.5:
		return Vector2(
			rng.randf_range(-120.0, -30.0),
			rng.randf_range(180.0, 300.0)
		)
	return Vector2(
		rng.randf_range(10.0, 246.0),
		rng.randf_range(10.0, 246.0)
	)


func _run_static(rng: RandomNumberGenerator) -> void:
	for scenario in range(STATIC_SCENARIOS):
		_index = SpatialIndexScript.new()
		_enemies.clear()
		var serial := 0
		for _i in range(rng.randi_range(4, 16)):
			serial += 1
			var center := _random_absolute(rng)
			var enemy := Fixtures.make_enemy(
				self,
				_index,
				serial,
				9001,
				center,
				Fixtures.DESIGN_256,
				rng.randf_range(0.2, 1.0)
			)
			_enemies.append(enemy)
		var segment_start := _random_absolute(rng)
		var segment_end := segment_start + Vector2(
			rng.randf_range(4.0, 30.0),
			rng.randf_range(-8.0, 8.0)
		)
		var candidates: Array = _index.query_segment_candidates(
			9001,
			segment_start,
			segment_end,
			1.0
		)
		var candidate_ids := {}
		for candidate: Dictionary in candidates:
			candidate_ids[int(candidate.get("actor_runtime_id", 0))] = true
		for enemy: EnemyActor in _enemies:
			var enemy_center: Vector2 = enemy.spatial_index_position()
			if _segment_near_point(segment_start, segment_end, enemy_center, 1.0 + enemy.combat_radius_gu):
				if not candidate_ids.has(enemy.spatial_actor_runtime_id):
					_false_negative_count += 1
		_cleanup()


func _run_movement(rng: RandomNumberGenerator) -> void:
	for scenario in range(MOVEMENT_SCENARIOS):
		_index = SpatialIndexScript.new()
		_enemies.clear()
		var serial := scenario + 1000
		var start := _random_absolute(rng)
		var end := _random_absolute(rng)
		var enemy := Fixtures.make_enemy(
			self,
			_index,
			serial,
			9001,
			start,
			Fixtures.DESIGN_256,
			0.3
		)
		_enemies.append(enemy)
		var steps := rng.randi_range(3, 8)
		for step in range(steps):
			var t := float(step + 1) / float(steps)
			Fixtures.move_enemy_absolute(
				enemy,
				start.lerp(end, t),
				Fixtures.DESIGN_256
			)
		_assert_found_at(enemy, end)
		_cleanup()


func _run_same_frame(rng: RandomNumberGenerator) -> void:
	for scenario in range(SAME_FRAME_SCENARIOS):
		_index = SpatialIndexScript.new()
		_enemies.clear()
		var serial := scenario + 2000
		var end := _random_absolute(rng)
		# Register and query in the same call sequence.
		var enemy := Fixtures.make_enemy(
			self,
			_index,
			serial,
			9001,
			end,
			Fixtures.DESIGN_256,
			0.3
		)
		_enemies.append(enemy)
		_assert_found_at(enemy, end)
		_cleanup()


func _run_knockback(rng: RandomNumberGenerator) -> void:
	for scenario in range(KNOCKBACK_SCENARIOS):
		_index = SpatialIndexScript.new()
		_enemies.clear()
		var serial := scenario + 3000
		var start := _random_absolute(rng)
		var end := start + Vector2(
			rng.randf_range(6.0, 24.0),
			rng.randf_range(-10.0, 10.0)
		)
		var enemy := Fixtures.make_enemy(
			self,
			_index,
			serial,
			9001,
			start,
			Fixtures.DESIGN_256,
			0.3
		)
		_enemies.append(enemy)
		Fixtures.move_enemy_absolute(enemy, end, Fixtures.DESIGN_256, &"knockback")
		_assert_found_at(enemy, end)
		_cleanup()


func _run_cross_map(rng: RandomNumberGenerator) -> void:
	for scenario in range(CROSS_MAP_SCENARIOS):
		_index = SpatialIndexScript.new()
		_enemies.clear()
		var serial := scenario + 4000
		var pos := _random_absolute(rng)
		var enemy := Fixtures.make_enemy(
			self,
			_index,
			serial,
			9001,
			pos,
			Fixtures.DESIGN_256,
			0.3
		)
		_enemies.append(enemy)
		var wrong_map: Array = _index.query_aabb_candidates(
			9002,
			Rect2(pos - Vector2(2, 2), Vector2(4, 4)),
			0.05
		)
		assert(wrong_map.is_empty(), "cross-map query must never leak candidates")
		var right_map: Array = _index.query_aabb_candidates(
			9001,
			Rect2(pos - Vector2(2, 2), Vector2(4, 4)),
			0.05
		)
		assert(not right_map.is_empty(), "map-scoped query must find the enemy")
		_cleanup()


func _assert_found_at(enemy: EnemyActor, center_ground_gu: Vector2) -> void:
	var candidates: Array = _index.query_aabb_candidates(
		9001,
		Rect2(center_ground_gu - Vector2(2, 2), Vector2(4, 4)),
		0.05
	)
	var found := false
	for candidate: Dictionary in candidates:
		if candidate.get("node") == enemy:
			found = true
			break
	if not found:
		_false_negative_count += 1


func _segment_near_point(
	start_ground_gu: Vector2,
	end_ground_gu: Vector2,
	target_ground_gu: Vector2,
	contact_radius_gu: float
) -> bool:
	return SkillProjectile.swept_segment_intersects_footprint_gu(
		start_ground_gu,
		end_ground_gu,
		target_ground_gu,
		contact_radius_gu
	)


func _cleanup() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
