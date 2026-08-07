extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const MAP_ID := 248


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var index := SpatialIndexScript.new()
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "p01_enemy", "hp": 9999, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	# Mapped world (MAP_ID >= 0) with screen_to_ground MISSING.
	enemy.configure_runtime_map_projection(
		MAP_ID,
		GroundUnit.ground_delta_gu_to_screen_delta_px
	)
	enemy.configure_spatial_index(index, 8001)
	add_child(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	assert(
		not enemy.projection_ready(),
		"mapped enemy without screen_to_ground must not be projection-ready"
	)
	var result: Dictionary = enemy.try_screen_position_px_to_ground_position_gu(
		Vector2(0.0, 80.0)
	)
	assert(
		not bool(result.get("success", true)),
		"mapped enemy conversion must fail explicitly"
	)
	assert(
		str(result.get("reason", ""))
		== str(GroundUnit.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION),
		"mapped enemy rejection must use the unified reason"
	)
	var provider: Vector2 = enemy.spatial_index_position()
	assert(
		not provider.is_finite(),
		"mapped enemy provider must never return a delta masquerading as absolute"
	)
	assert(
		enemy.missing_projection_rejection_count >= 1,
		"mapped enemy must record the projection rejection"
	)
	var context: Dictionary = enemy._snapshot_coordinate_context()
	assert(
		context.is_empty(),
		"mapped enemy must not produce an absolute snapshot context without projection"
	)
	# Formal registration is refused: the index must stay empty for this id.
	var registered := index.registered_actor_count()
	assert(
		registered == 0,
		"formal combat registration must be rejected (no index entry)"
	)
	var rejection_reason: String = str(result.get("reason", ""))
	var rejection_count: int = enemy.missing_projection_rejection_count
	enemy.queue_free()
	await get_tree().process_frame
	print(
		"MAPPED_ENEMY_MISSING_PROJECTION_REJECTED_PASS reason=%s rejections=%d"
		% [rejection_reason, rejection_count]
	)
	get_tree().quit(0)
