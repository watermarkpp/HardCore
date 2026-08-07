extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const CastRequest := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const PlanFixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const PlanContract := preload(
	"res://scripts/skills/skill_execution_plan_contract.gd"
)

const MAP_ID := 217


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var origin_screen := Vector2(0.0, 80.0)
	var release_id := "p01:plan:1"
	var request := CastRequest.create(
		"wizard.fireball",
		1,
		35,
		Vector2i(130, 130),
		Vector2i.DOWN,
		PlanFixtures.default_target_context(true, Vector2i(131, 130), release_id),
		PlanFixtures.default_resource_context(500),
		42
	)
	var ctx := PlanFixtures.canonical_context(MAP_ID, release_id, 0, 0, {})
	ctx["origin_screen_px"] = origin_screen
	ctx["direction_screen_px"] = Vector2(32.0, 16.0)
	ctx["target_position_screen_px"] = origin_screen
	# screen_to_ground deliberately removed (canonical_context injects identity).
	ctx.erase("screen_to_ground_position_px")
	ctx["ground_gu_to_screen_position_px"] = (
		GroundUnit.ground_delta_gu_to_screen_delta_px
	)
	ctx["grid_cell_to_screen_position_px"] = Callable()
	ctx["snapshot_validation_context"] = Snapshot.make_absolute_runtime_context(
		MAP_ID,
		origin_screen,
		origin_screen,
		GroundUnit.ground_delta_gu_to_screen_delta_px
	)
	ctx["line_strip_builder"] = Callable()
	ctx["effective_cells_builder"] = Callable()
	var rejections_before := PlanContract.missing_projection_rejection_count
	var plan: Dictionary = Router.build_canonical_plan(request, ctx)
	var rejection: Dictionary = plan.get("rejection", {})
	assert(
		not bool(rejection.get("accepted", true)),
		"mapped spatial plan without projection must be rejected"
	)
	assert(
		str(rejection.get("reason", ""))
		== str(GroundUnit.REASON_MISSING_RUNTIME_PROJECTION),
		"plan rejection must use the unified missing_runtime_projection reason"
	)
	assert(
		plan.get("canonical_snapshot", {}) is Dictionary
		and (plan.get("canonical_snapshot", {}) as Dictionary).is_empty(),
		"no fake absolute snapshot may be built for a rejected plan"
	)
	assert(
		PlanContract.missing_projection_rejection_count > rejections_before,
		"plan builder must record the projection rejection"
	)
	# Rejected plans commit nothing (GameRoot gates commit on acceptance).
	var result := PlanContract.build_result(plan, {})
	assert(
		not bool(result.get("accepted", true))
		and not bool(result.get("resource_committed", true))
		and not bool(result.get("cooldown_committed", true)),
		"rejected plan must commit zero resources/cooldowns"
	)
	await get_tree().process_frame
	print(
		"MAPPED_SKILL_PLAN_MISSING_PROJECTION_REJECTED_PASS reason=%s"
		% rejection.get("reason", "")
	)
	get_tree().quit(0)
