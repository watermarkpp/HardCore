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
	for serial in range(1, 9):
		_enemies.append(_make_enemy(1, Vector2(serial * 0.5, 0.0), serial))
	for serial in range(101, 109):
		_enemies.append(_make_enemy(2, Vector2(serial * 0.5, 0.0), serial))
	var candidates := _index.query_segment_candidates(
		1,
		Vector2(0, 0),
		Vector2(10, 0),
		2.0
	)
	assert(
		candidates.size() == 8,
		"map-1 query must return only map-1 candidates"
	)
	var cross_map_rejected := 0
	for candidate: Dictionary in candidates:
		var node: Variant = candidate.get("node")
		if node is EnemyActor:
			if int((node as EnemyActor).get_meta("spatial_id", 0)) >= 100:
				cross_map_rejected += 1
	assert(
		cross_map_rejected == 0,
		"map-1 query must not include map-2 enemies"
	)
	var map_2_candidates := _index.query_segment_candidates(
		2,
		Vector2(50, 0),
		Vector2(56, 0),
		2.0
	)
	assert(
		map_2_candidates.size() == 8,
		"map-2 query must return only map-2 candidates"
	)

	# A projectile frozen on map 1 must never hit map-2 enemies.
	var projectile := _make_projectile(Vector2(0, 0), 8.0, 1)
	var previous_hp: Dictionary = {}
	for enemy: EnemyActor in _enemies:
		previous_hp[enemy.get_instance_id()] = enemy.current_hp
	for _step in range(60):
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			break
		projectile._physics_process(1.0 / 60.0)
	for enemy: EnemyActor in _enemies:
		if (
			int(previous_hp.get(enemy.get_instance_id(), 0))
			> enemy.current_hp
		):
			assert(
				int(enemy.get_meta("spatial_id", 0)) < 100,
				"map-1 projectile must not hit a map-2 enemy"
			)
	var diagnostics: Dictionary = projectile.projectile_broadphase_diagnostics()
	assert(
		int(diagnostics.get("cross_map_candidate_rejection_count", 0)) == 0,
		"map-scoped index structurally prevents cross-map candidates"
	)
	_cleanup()
	await get_tree().process_frame
	print("PROJECTILE_BROADPHASE_RUNTIME_MAP_ISOLATION_PASS")
	get_tree().quit(0)


func _make_enemy(
	map_id: int,
	center_ground_gu: Vector2,
	serial: int
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "map_%d_%d" % [map_id, serial], "hp": 1000, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	enemy.configure_runtime_map_projection(
		map_id,
		Callable(self, "_ground_to_screen")
	)
	enemy.configure_spatial_index(_index, serial)
	enemy.set_meta("spatial_id", serial)
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	enemy.combat_radius_gu = 0.25
	add_child(enemy)
	_index.register(
		serial,
		map_id,
		center_ground_gu,
		0.25,
		serial,
		enemy
	)
	return enemy


func _make_projectile(
	start_ground_gu: Vector2,
	speed_gu: float,
	map_id: int
) -> SkillProjectile:
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
		"isolation:%d" % map_id
	)
	projectile.configure_runtime_map_projection(
		map_id,
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
