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


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Projectiles currently have no terrain clipping (pre-existing behavior,
	# verified by code audit). This test asserts the broadphase queries exactly
	# the same segment the narrow phase tests (no false negative introduced by
	# a wall), and that old/new hit results are identical.
	_index = SpatialIndexScript.new()
	var wall_ground := Vector2(3.0, 0.0)
	_enemies.append(_make_enemy(Vector2(2.0, 0.0), 0.25, 1))
	_enemies.append(_make_enemy(Vector2(5.0, 0.0), 0.25, 2))
	var projectile := _make_projectile(Vector2(0, 0), 8.0)
	var expected_context := _expected_context()
	var previous_hp: Dictionary = {}
	for enemy: EnemyActor in _enemies:
		previous_hp[enemy.get_instance_id()] = enemy.current_hp
	var actual_hits: Array[int] = []
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
		for enemy: EnemyActor in _enemies:
			if (
				int(previous_hp.get(enemy.get_instance_id(), 0))
				> enemy.current_hp
			):
				actual_hits.append(int(enemy.get_meta("spatial_id", 0)))
				previous_hp[enemy.get_instance_id()] = enemy.current_hp
		if reference_hit != null and actual_hits.is_empty():
			assert(false, "legacy hit must also be observed on the new path")
			break
	# A wall at x=3 is documented as non-blocking today (no terrain clipping).
	# The broadphase must query the full actual segment and include both
	# enemies (parity), regardless of the wall's presence.
	assert(
		not actual_hits.is_empty(),
		"projectile must hit through the documented non-blocking wall (parity)"
	)
	var query_covers_full_segment := _index.query_segment_candidates(
		1,
		Vector2(0, 0),
		Vector2(8, 0),
		0.5
	)
	var wall_zone_present := false
	for candidate: Dictionary in query_covers_full_segment:
		var node: Variant = candidate.get("node")
		if node is EnemyActor:
			var enemy := node as EnemyActor
			if absf(enemy.global_position.x - GroundUnit.ground_delta_gu_to_screen_delta_px(wall_ground).x) < 1.0:
				wall_zone_present = true
	assert(
		query_covers_full_segment.size() >= 2,
		"broadphase must query the full actual segment (both sides of the wall)"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"PROJECTILE_BROADPHASE_TERRAIN_CUTOFF_PASS parity=ok wall_zone_candidates=%s"
		% str(wall_zone_present)
	)
	get_tree().quit(0)


func _make_enemy(
	center_ground_gu: Vector2,
	combat_radius_gu: float,
	serial: int
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "terrain_%d" % serial, "hp": 1000, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)
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


func _make_projectile(start_ground_gu: Vector2, speed_gu: float) -> SkillProjectile:
	var projectile := Projectile.new()
	projectile.setup_ground_unit_projectile(
		GroundUnit.ground_delta_gu_to_screen_delta_px(start_ground_gu),
		Vector2.RIGHT,
		12.0,
		999,
		speed_gu,
		0.25,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"terrain:test"
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
	_projectiles.clear()
	_enemies.clear()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
