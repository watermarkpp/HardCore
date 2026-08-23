extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const MAP_ID := 217

var _enemy: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var index := SpatialIndexScript.new()
	_enemy = _make_enemy(index)
	var projectile := SkillProjectile.new()
	projectile.setup_ground_unit_projectile(
		Vector2(0.0, 80.0),
		Vector2(1.0, 0.0).normalized(),
		10.0,
		5,
		4.0,
		0.2
	)
	# Mapped world with screen_to_ground MISSING.
	projectile.configure_runtime_map_projection(
		MAP_ID,
		GroundUnit.ground_delta_gu_to_screen_delta_px
	)
	projectile.configure_spatial_index(index)
	projectile._projectile_role_valid = true
	add_child(projectile)
	assert(
		not projectile.projection_ready(),
		"mapped projectile without screen_to_ground must not be projection-ready"
	)
	assert(
		projectile.skill_footprint_snapshot.is_empty(),
		"mapped projectile must not create a fake release snapshot"
	)
	var rejections_before := projectile.missing_projection_rejection_count
	projectile._physics_process(0.05)
	var physics_rejections: int = projectile.missing_projection_rejection_count
	var query_count: int = projectile._broadphase_query_count
	var rejection_reason: String = str(projectile.projection_rejection_reason)
	await get_tree().process_frame
	assert(
		physics_rejections > rejections_before,
		"mapped projectile physics must record the projection rejection"
	)
	assert(
		query_count == 0,
		"mapped projectile must never run a broadphase query without projection"
	)
	assert(
		_enemy.current_hp == 99999,
		"mapped projectile must never damage the enemy (projection failure, not a miss)"
	)
	assert(
		rejection_reason
		== str(GroundUnit.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION),
		"projectile rejection must use the unified reason"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"MAPPED_PROJECTILE_MISSING_PROJECTION_REJECTED_PASS reason=%s"
		% rejection_reason
	)
	get_tree().quit(0)


func _make_enemy(index: SpatialIndexScript) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "p01_target", "hp": 99999, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	enemy.configure_runtime_map_projection(
		MAP_ID,
		GroundUnit.ground_delta_gu_to_screen_delta_px,
		GroundUnit.screen_delta_px_to_ground_delta_gu
	)
	enemy.configure_spatial_index(index, 8002)
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		Vector2(134.0, 130.0)
	)
	enemy.combat_radius_gu = 0.3
	add_child(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	index.register(
		8002,
		MAP_ID,
		Vector2(134.0, 130.0),
		0.3,
		8002,
		enemy,
		Callable(enemy, "spatial_index_position")
	)
	return enemy


func _cleanup() -> void:
	for node: Node in get_children():
		node.queue_free()
