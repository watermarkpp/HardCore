extends Node

const Fixtures := preload(
	"res://tests/helpers/combat_absolute_ground_fixtures.gd"
)
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const MAP_ID := 9001
const EPSILON := 0.0002

var _index: SpatialIndexScript
var _enemy: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	var abs_center := Vector2(130.0, 130.0)
	_enemy = Fixtures.make_enemy(
		self,
		_index,
		1,
		MAP_ID,
		abs_center,
		Fixtures.DESIGN_256
	)
	assert(
		_enemy.spatial_index_position().distance_to(abs_center) <= EPSILON,
		"enemy spatial_index_position must be absolute map ground"
	)
	assert(
		_candidate_count(abs_center) >= 1,
		"index must contain the enemy at its absolute register position"
	)
	# Same-call forced movement: provider and index bucket update together.
	var moved := Vector2(140.0, 135.0)
	Fixtures.move_enemy_absolute(_enemy, moved, Fixtures.DESIGN_256)
	assert(
		_enemy.spatial_index_position().distance_to(moved) <= EPSILON,
		"provider must report the forced absolute position"
	)
	assert(
		_candidate_count(moved) >= 1,
		"same-call index update must place the enemy in the new absolute bucket"
	)
	# One real physics tick: provider and index entry must stay absolute.
	_enemy.set_physics_process(true)
	await get_tree().physics_frame
	_enemy.set_physics_process(false)
	assert(
		_enemy.spatial_index_position().distance_to(moved) <= EPSILON,
		"provider after physics tick must stay absolute"
	)
	assert(
		_candidate_count(moved) >= 1,
		"index after physics tick must still find the enemy at absolute"
	)
	# Cross-map isolation: an enemy registered on another map never appears.
	var other := Fixtures.make_enemy(
		self,
		_index,
		2,
		9002,
		moved,
		Fixtures.DESIGN_256
	)
	assert(
		_candidate_count(moved) == 1,
		"cross-map enemy must never appear in map 9001 queries"
	)
	var provider_display: Vector2 = _enemy.spatial_index_position()
	_cleanup()
	await get_tree().process_frame
	print(
		"ENEMY_SPATIAL_INDEX_ABSOLUTE_COORDINATE_PASS register=%s provider=%s moved=%s"
		% [abs_center, provider_display, moved]
	)
	get_tree().quit(0)


func _candidate_count(center_ground_gu: Vector2) -> int:
	var candidates: Array = _index.query_aabb_candidates(
		MAP_ID,
		Rect2(center_ground_gu - Vector2(2.0, 2.0), Vector2(4.0, 4.0)),
		0.05
	)
	var count := 0
	for candidate: Dictionary in candidates:
		if candidate.get("node") == _enemy:
			count += 1
	return count


func _cleanup() -> void:
	if is_instance_valid(_enemy):
		_enemy.queue_free()
	_enemy = null
	for node: Node in get_children():
		if node is EnemyActor:
			node.queue_free()
