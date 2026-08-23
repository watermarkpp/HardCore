extends Node

const Fixtures := preload(
	"res://tests/helpers/combat_absolute_ground_fixtures.gd"
)
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const GroundSkillVisualCell := preload(
	"res://scripts/ground_skill_visual_cell.gd"
)

const MAP_ID := 9001

var _index: SpatialIndexScript
var _enemy: EnemyActor
var _controller: FireWallFieldController
var _tick_powers: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	_index = SpatialIndexScript.new()
	var center_abs := Vector2(130.0, 130.0)
	_enemy = Fixtures.make_enemy(
		self,
		_index,
		1,
		MAP_ID,
		center_abs,
		Fixtures.DESIGN_256,
		0.3
	)
	_controller = Fixtures.make_fire_wall_controller(
		self,
		_index,
		MAP_ID,
		center_abs,
		Fixtures.DESIGN_256,
		Callable(self, "_on_tick"),
		null
	)
	assert(
		not _controller.has_method("_query_bounds_index_space"),
		"FREEZE-P0: the delta compatibility shim must be removed"
	)
	assert(
		_controller.visual_cells.size() == 4,
		"FireWall must keep its frozen 2x2 visual cell count"
	)
	_controller._apply_field_tick()
	var diag: Dictionary = _controller.fire_wall_controller_diagnostics()
	assert(
		int(diag.get("broadphase_query_count", 0)) >= 1,
		"FireWall controller must run one absolute broadphase query per tick"
	)
	assert(
		int(diag.get("candidate_count", 0)) >= 1,
		"FireWall absolute broadphase must find the enemy at map center"
	)
	assert(
		int(diag.get("controller_exact_test_count", 0)) >= 1,
		"FireWall controller must exact-test the absolute candidate"
	)
	assert(
		_tick_powers.size() >= 1,
		"FireWall controller must apply damage to the inside absolute enemy"
	)
	for cell: GroundSkillVisualCell in _controller.visual_cells:
		var cell_diag: Dictionary = cell.runtime_diagnostics()
		assert(
			int(cell_diag.get("enemy_group_queries", -1)) == 0
			and int(cell_diag.get("damage_ticks", -1)) == 0,
			"FireWall visual cells must stay pure presentation"
		)
	# Cross-map enemy never appears.
	Fixtures.make_enemy(
		self,
		_index,
		2,
		9002,
		center_abs,
		Fixtures.DESIGN_256,
		0.3
	)
	var direct_9001: Array = _index.query_aabb_candidates(
		9001,
		Rect2(center_abs - Vector2(3, 3), Vector2(6, 6)),
		0.05
	)
	var direct_9002: Array = _index.query_aabb_candidates(
		9002,
		Rect2(center_abs - Vector2(3, 3), Vector2(6, 6)),
		0.05
	)
	var direct_9001_ids: Array = []
	for candidate: Dictionary in direct_9001:
		direct_9001_ids.append(int(candidate.get("actor_runtime_id", 0)))
	var direct_9002_ids: Array = []
	for candidate: Dictionary in direct_9002:
		direct_9002_ids.append(int(candidate.get("actor_runtime_id", 0)))
	print(
		"FIRE_WALL_DEBUG direct9001=%s direct9002=%s"
		% [direct_9001_ids, direct_9002_ids]
	)
	_controller._apply_field_tick()
	var diag2: Dictionary = _controller.fire_wall_controller_diagnostics()
	print(
		"FIRE_WALL_DEBUG first_candidates=%d second_candidates=%d first_exact=%d second_exact=%d ticks=%d"
		% [
			int(diag.get("candidate_count", 0)),
			int(diag2.get("candidate_count", 0)),
			int(diag.get("controller_exact_test_count", 0)),
			int(diag2.get("controller_exact_test_count", 0)),
			_tick_powers.size(),
		]
	)
	assert(
		int(diag2.get("candidate_count", 0))
		== int(diag.get("candidate_count", 0)) + 1,
		"cross-map enemy must never become a FireWall candidate"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"FIRE_WALL_ABSOLUTE_BROADPHASE_PASS candidates=%d exact=%d damage=%d"
		% [
			int(diag.get("candidate_count", 0)),
			int(diag.get("controller_exact_test_count", 0)),
			_tick_powers.size(),
		]
	)
	get_tree().quit(0)


func _on_tick(_target: EnemyActor, raw_power: int) -> void:
	_tick_powers.append(raw_power)


func _cleanup() -> void:
	for node: Node in get_children():
		node.queue_free()
