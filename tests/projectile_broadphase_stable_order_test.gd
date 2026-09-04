extends Node

const Projectile := preload("res://scripts/skill_projectile.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
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
	# Register with stable orders 10..40 but positions whose bucket traversal
	# order is the reverse (x increases with serial). The query must return
	# candidates sorted by stable_combat_order, never bucket order.
	var centers := {
		10: Vector2(2.0, 0.0),
		20: Vector2(6.0, 0.0),
		30: Vector2(10.0, 0.0),
		40: Vector2(14.0, 0.0),
	}
	for serial: int in [10, 20, 30, 40]:
		_enemies.append(_make_enemy(centers[serial], 0.4, serial))
	var candidates := _index.query_segment_candidates(
		1,
		Vector2(0, 0),
		Vector2(16, 0),
		1.0
	)
	var candidate_order: Array[int] = []
	for candidate: Dictionary in candidates:
		candidate_order.append(
			int(candidate.get("stable_combat_order", 0))
		)
	assert(
		candidate_order == [10, 20, 30, 40],
		"candidates must be sorted by stable combat order, got %s"
		% str(candidate_order)
	)

	# A fast projectile covers several enemies in a single segment step; the
	# first hit must follow the same stable order as the legacy scene order.
	var projectile := _make_projectile(Vector2(0, 0), 480.0)
	var previous_hp: Dictionary = {}
	for enemy: EnemyActor in _enemies:
		previous_hp[enemy.get_instance_id()] = enemy.current_hp
	projectile._physics_process(1.0 / 60.0)
	var new_hit: EnemyActor = null
	for enemy: EnemyActor in _enemies:
		if (
			int(previous_hp.get(enemy.get_instance_id(), 0))
			> enemy.current_hp
		):
			new_hit = enemy
			break
	assert(
		new_hit != null
		and int(new_hit.get_meta("spatial_id", 0)) == 10,
		"first hit must follow stable spawn order (serial 10)"
	)
	var diagnostics: Dictionary = projectile.projectile_broadphase_diagnostics()
	assert(
		int(diagnostics.get("hit_count", 0)) == 1,
		"exactly one hit expected"
	)
	_cleanup()
	await get_tree().process_frame
	print("PROJECTILE_BROADPHASE_STABLE_ORDER_PASS")
	get_tree().quit(0)


func _make_enemy(
	center_ground_gu: Vector2,
	combat_radius_gu: float,
	serial: int
) -> EnemyActor:
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
		20.0,
		999,
		speed_gu,
		0.25,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"order:test"
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
