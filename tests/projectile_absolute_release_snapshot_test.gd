extends Node

const Fixtures := preload(
	"res://tests/helpers/combat_absolute_ground_fixtures.gd"
)
const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const CastRequest := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const PlanFixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)

const MAP_ID := 9001
const EPSILON := 0.0002

var _index: SpatialIndexScript
var _enemy: EnemyActor
var _projectile: SkillProjectile


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	var origin_abs := Vector2(130.0, 130.0)
	var target_abs := Vector2(134.0, 130.0)
	_enemy = Fixtures.make_enemy(
		self,
		_index,
		1,
		MAP_ID,
		target_abs,
		Fixtures.DESIGN_256,
		0.3
	)
	_projectile = Fixtures.make_projectile(
		self,
		_index,
		MAP_ID,
		origin_abs,
		Vector2(1.0, 0.0),
		Fixtures.DESIGN_256,
		10.0
	)
	var snapshot: Dictionary = _projectile.skill_footprint_snapshot
	_projectile._projectile_role_valid = true
	assert(
		(snapshot.get("origin_ground_gu", Vector2.ZERO) as Vector2)
		.distance_to(origin_abs) <= EPSILON,
		"projectile release snapshot origin must be absolute map ground"
	)
	assert(
		str(snapshot.get("coordinate_space", ""))
		== Snapshot.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU,
		"projectile release snapshot must declare absolute coordinate space"
	)
	assert(
		int(snapshot.get("runtime_map_id", -1)) == MAP_ID,
		"projectile release snapshot must carry the runtime map id"
	)
	# Canonical plan release origin must match (projectile branch).
	var plan := _canonical_projectile_plan(origin_abs)
	assert(
		bool(plan.get("rejection", {}).get("accepted", false)),
		"canonical projectile plan must be accepted"
	)
	var plan_snapshot: Dictionary = plan.get("canonical_snapshot", {})
	assert(
		(plan_snapshot.get("origin_ground_gu", Vector2.ZERO) as Vector2)
		.distance_to(origin_abs) <= EPSILON,
		"canonical plan projectile release origin must be absolute map ground"
	)
	var hit_observed := false
	# Broadphase segment: deterministically step the projectile through the
	# enemy's absolute position, then assert candidate + exact hit.
	for step in range(120):
		if not is_instance_valid(_projectile):
			break
		_projectile._physics_process(0.05)
		if int(_projectile._broadphase_hit_count) >= 1:
			hit_observed = true
			break
	assert(
		hit_observed,
		"projectile segment broadphase + exact phase must hit the absolute-registered enemy"
	)
	# Cross-map enemy never becomes a candidate.
	var cross := Fixtures.make_enemy(
		self,
		_index,
		2,
		9002,
		Vector2(134.0, 130.0),
		Fixtures.DESIGN_256
	)
	var candidates: Array = _index.query_segment_candidates(
		MAP_ID,
		origin_abs,
		origin_abs + Vector2(10.0, 0.0),
		0.3
	)
	for candidate: Dictionary in candidates:
		assert(
			candidate.get("node") != cross,
			"cross-map enemy must never appear in map 9001 candidates"
		)
	_cleanup()
	await get_tree().process_frame
	print(
		"PROJECTILE_ABSOLUTE_RELEASE_SNAPSHOT_PASS origin=%s hit=%s"
		% [origin_abs, hit_observed]
	)
	get_tree().quit(0)


func _canonical_projectile_plan(origin_abs: Vector2) -> Dictionary:
	var release_id := "p0:plan:projectile:1"
	var origin_screen: Vector2 = Mapper.ground_position_gu_to_screen_position_px(
		origin_abs,
		Fixtures.DESIGN_256
	)
	var request := CastRequest.create(
		"wizard.fireball",
		1,
		35,
		Vector2i(roundi(origin_abs.x), roundi(origin_abs.y)),
		Vector2i.DOWN,
		PlanFixtures.default_target_context(
			true,
			Vector2i(roundi(origin_abs.x) + 1, roundi(origin_abs.y)),
			release_id
		),
		PlanFixtures.default_resource_context(500),
		42
	)
	var context := PlanFixtures.canonical_context(
		MAP_ID,
		release_id,
		0,
		0,
		{}
	)
	context["origin_screen_px"] = origin_screen
	context["direction_screen_px"] = Vector2(32.0, 16.0)
	context["target_position_screen_px"] = origin_screen
	context["screen_to_ground_position_px"] = Fixtures.screen_to_ground(
		Fixtures.DESIGN_256
	)
	context["ground_gu_to_screen_position_px"] = Fixtures.ground_to_screen(
		Fixtures.DESIGN_256
	)
	context["grid_cell_to_screen_position_px"] = Callable()
	context["snapshot_validation_context"] = Fixtures.absolute_context(
		MAP_ID,
		origin_abs,
		Fixtures.DESIGN_256
	)
	context["line_strip_builder"] = Callable()
	context["effective_cells_builder"] = Callable()
	return Router.build_canonical_plan(request, context)


func _cleanup() -> void:
	for node: Node in get_children():
		node.queue_free()
