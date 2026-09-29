extends Node2D

## source176 Tasks 3+4+5 (docs/02 E/F/G): unified ordinary melee geometry,
## monotone eight-way step planning, and the body-action admission gate.

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const OpenTerrainFixture := preload(
	"res://tests/helpers/monster_open_terrain_test_fixture.gd"
)
const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")
const Source176Melee := preload(
	"res://scripts/monster_source176/source_melee_geometry.gd"
)
const SourceStepPlan := preload(
	"res://scripts/monster_source176/source_step_plan.gd"
)

var index := SpatialIndex.new()
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	assert(condition, "SOURCE176_GEOMETRY_ACTION: " + label)
	_checks += 1


func _g2s(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_test_static_predicate()
	_test_step_plan_staircase()
	await _test_access_box()
	_test_body_action_gate()
	print("SOURCE176_GEOMETRY_ACTION_PASS checks=%d" % _checks)
	get_tree().quit(0)


func _test_static_predicate() -> void:
	_check(Source176Melee.continuous_adjacent(Vector2(1, 0)), "box: (1,0) adjacent")
	_check(Source176Melee.continuous_adjacent(Vector2(-1, -1)), "box: (-1,-1) adjacent")
	_check(Source176Melee.continuous_adjacent(Vector2(0.2, 0.9)), "box: inner point adjacent")
	_check(not Source176Melee.continuous_adjacent(Vector2.ZERO), "box: same cell not adjacent")
	_check(not Source176Melee.continuous_adjacent(Vector2(1.2, 0.0)), "box: (1.2,0) outside")
	_check(not Source176Melee.continuous_adjacent(Vector2(1.0, 1.05)), "box: (1,1.05) outside")
	_check(
		Source176Melee.broadphase_radius_gu() > sqrt(2.0) - 0.001,
		"box: broadphase covers the corner"
	)


func _test_step_plan_staircase() -> void:
	var current := Vector2.ZERO
	var first := SourceStepPlan.next_leg(current, Vector2(12, 5))
	_check(first == Vector2(1, 1), "staircase: first leg is diagonal (1,1)")
	var legs := 0
	var axis_tail := 0
	while current != Vector2(12, 5) and legs < 64:
		var leg := SourceStepPlan.next_leg(current, Vector2(12, 5))
		_check(SourceStepPlan.is_eight_way(leg - current), "staircase: leg %d is eight-way" % legs)
		if absf((leg - current).y) <= 0.000001 and absf((leg - current).x) > 0.0:
			axis_tail += 1
		current = leg
		legs += 1
	_check(current == Vector2(12, 5), "staircase: reaches the goal")
	_check(legs == 12, "staircase: 5 diagonal + 7 axis legs, got %d" % legs)
	_check(axis_tail == 7, "staircase: axis tail after the single turn")
	var short := SourceStepPlan.next_leg(Vector2.ZERO, Vector2(0.2, 1.3))
	_check(short == Vector2(0.2, 0.2), "staircase: monotone leg, not an angle cut")


func _spawn_pair(offset_gu: Vector2) -> Array:
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 500
	player.current_hp = 500
	player.defense_min = 0
	player.defense_max = 0
	var center_px := _g2s(OpenTerrainFixture.CENTER_GROUND_GU)
	player.global_position = center_px
	var enemy: EnemyActor = EnemyActor.new()
	enemy.global_position = center_px + _g2s(offset_gu)
	# Monster 89 is the verified ordinary-melee identity (corpse-king Task 2
	# evidence). The delivery rule is pinned empty so the fixture is
	# deterministic even if catalog data later gains a named kind.
	enemy.setup(GameData.get_monster_by_id(89), player, true)
	enemy.attack_delivery_rule = {}
	enemy.target = player
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_g2s"),
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu,
	)
	enemy.configure_terrain_navigation_context(OpenTerrainFixture.build(1))
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.configure_spatial_index(index, 1)
	index.register(
		1,
		1,
		OpenTerrainFixture.CENTER_GROUND_GU + offset_gu,
		enemy.combat_radius_gu,
		1,
		enemy,
	)
	return [player, enemy]


func _teardown_pair(pair: Array) -> void:
	var enemy: EnemyActor = pair[1]
	index.unregister(enemy.spatial_actor_runtime_id)
	enemy.free()
	pair[0].free()


func _test_access_box() -> void:
	var diagonal := await _spawn_pair(Vector2(1, 1))
	var enemy: EnemyActor = diagonal[1]
	_check(enemy._source176_ordinary_melee(), "fixture: monster 89 with empty rule is ordinary melee")
	var access := String(enemy._hc_access(diagonal[0]))
	_check(access != "OUT_OF_RANGE", "L-inf: (1,1) diagonal is in reach (Euclidean sqrt2)")
	_check(
		enemy._source176_basic_melee_geometry_clear(diagonal[0]),
		"L-inf: geometry-only predicate confirms (1,1)"
	)
	_check(enemy._hc_step_can_end(), "L-inf: pursuit step may end on the (1,1) diagonal")
	_teardown_pair(diagonal)

	var outside := await _spawn_pair(Vector2(1.2, 0.2))
	var enemy2: EnemyActor = outside[1]
	var access2 := String(enemy2._hc_access(outside[0]))
	_check(access2 == "OUT_OF_RANGE", "L-inf: (1.2,0.2) outside the box though inside the old circle")
	_check(not enemy2._hc_step_can_end(), "L-inf: pursuit step cannot end outside the box")
	_teardown_pair(outside)


func _test_body_action_gate() -> void:
	var pair := await _spawn_pair(Vector2(1, 0))
	var enemy: EnemyActor = pair[1]
	enemy._last_body_action_commit_tick = -1
	var tick := Engine.get_physics_frames()
	_check(enemy._try_reserve_source_body_action(false), "gate: first reserve in a fresh frame passes")
	_check(
		enemy._last_body_action_commit_tick == tick,
		"gate: reserve stamps the current physics frame"
	)
	_check(not enemy._try_reserve_source_body_action(false), "gate: second reserve in the same frame fails")
	_check(not enemy._try_reserve_source_body_action(true), "gate: incompatible pending fails")
	enemy._dying = true
	_check(not enemy._try_reserve_source_body_action(false), "gate: dying source cannot reserve")
	enemy._dying = false
	enemy._last_body_action_commit_tick = -1
	_check(enemy._try_reserve_source_body_action(false), "gate: fresh life reserves again")
	_teardown_pair(pair)
