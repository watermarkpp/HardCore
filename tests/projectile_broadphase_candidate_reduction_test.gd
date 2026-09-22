extends Node

const Projectile := preload("res://scripts/skill_projectile.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const FIXTURE_MONSTER_ID := 19

var _index: SpatialIndexScript
var _enemies: Array[EnemyActor] = []
var _projectiles: Array[SkillProjectile] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var legacy_examined := 0
	var legacy_exact_tests := 0
	var projectile_steps := 0
	_index = SpatialIndexScript.new()
	for i in range(256):
		var center := Vector2(
			(i % 64) * 1.0 - 31.5,
			(i / 64) * 1.0 - 1.5
		)
		_enemies.append(_make_enemy(center, 0.25, i + 1))
	for i in range(16):
		var projectile := _make_projectile(
			Vector2(0.0, (i % 4) * 5.0 - 7.5),
			8.0
		)
		_projectiles.append(projectile)
	for _step in range(60):
		var alive := 0
		var alive_enemies := 0
		for enemy: EnemyActor in _enemies:
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				alive_enemies += 1
		for projectile: SkillProjectile in _projectiles:
			if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
				continue
			alive += 1
			projectile._physics_process(1.0 / 60.0)
		projectile_steps += alive
		legacy_examined += alive * alive_enemies
		legacy_exact_tests += alive * alive_enemies
	var broadphase_candidates := 0
	var exact_test_count := 0
	var group_scan_count := 0
	var group_nodes_examined := 0
	var snapshot_build_count := 0
	var max_candidate_count := 0
	for projectile: SkillProjectile in _projectiles:
		if not is_instance_valid(projectile):
			continue
		var diagnostics: Dictionary = (
			projectile.projectile_broadphase_diagnostics()
		)
		broadphase_candidates += int(
			diagnostics.get("total_candidate_count", 0)
		)
		exact_test_count += int(diagnostics.get("exact_test_count", 0))
		group_scan_count += int(diagnostics.get("group_scan_count", 0))
		group_nodes_examined += int(
			diagnostics.get("group_nodes_examined", 0)
		)
		snapshot_build_count += int(
			diagnostics.get("snapshot_build_count", 0)
		)
		max_candidate_count = maxi(
			max_candidate_count,
			int(diagnostics.get("max_candidate_count", 0))
		)
	assert(
		group_scan_count == 0 and group_nodes_examined == 0,
		"production hot path must not perform group scans"
	)
	assert(
		broadphase_candidates < legacy_examined,
		"broadphase candidates must be fewer than legacy examined nodes"
	)
	assert(
		exact_test_count < legacy_exact_tests,
		"exact tests must be reduced below legacy"
	)
	var reduction_percent := 0.0
	if legacy_exact_tests > 0:
		reduction_percent = (
			100.0 * float(legacy_exact_tests - exact_test_count)
			/ float(legacy_exact_tests)
		)
	assert(
		reduction_percent >= 60.0,
		"exact test reduction must be at least 60 percent on the sparse fixture, got %.1f" % reduction_percent
	)
	assert(
		snapshot_build_count == projectile_steps,
		"one snapshot per projectile step"
	)
	print(
		"PROJECTILE_BROADPHASE_CANDIDATE_REDUCTION_PASS legacy_examined=%d candidates=%d max_candidates=%d exact_tests=%d reduction=%.1f%% snapshot_builds=%d steps=%d"
		% [
			legacy_examined,
			broadphase_candidates,
			max_candidate_count,
			exact_test_count,
			reduction_percent,
			snapshot_build_count,
			projectile_steps,
		]
	)
	_cleanup()
	await get_tree().process_frame
	get_tree().quit(0)


func _make_enemy(
	center_ground_gu: Vector2,
	combat_radius_gu: float,
	serial: int
) -> EnemyActor:
	var enemy := EnemyActor.new()
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"candidate reduction fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	enemy.setup(canonical_data, null, false)
	assert(
		enemy.monster_id == FIXTURE_MONSTER_ID and not enemy.is_boss,
		"candidate reduction fixture must remain an ordinary exact-ID target"
	)
	enemy.max_hp = 1000
	enemy.current_hp = enemy.max_hp
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)
	enemy.configure_spatial_index(_index, serial)
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	enemy.combat_radius_gu = combat_radius_gu
	add_child(enemy)
	assert(
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and enemy.can_receive_damage(),
		"candidate reduction fixture target must survive exact-ID admission"
	)
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
		80.0,
		999,
		speed_gu,
		0.25,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"reduction:%d" % _projectiles.size()
	)
	projectile.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)
	projectile.configure_spatial_index(_index)
	add_child(projectile)
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
