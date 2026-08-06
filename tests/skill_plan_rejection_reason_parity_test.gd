extends Node

## Q3-A: rejection reasons are normalized to one canonical vocabulary on both
## the legacy and the canonical planner.

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")

var _checked := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_rejection_case(
		"wizard.unknown_skill",
		{},
		{},
		Plan.REASON_UNKNOWN_SKILL
	)
	_rejection_case(
		"wizard.lightning",
		{"has_target": false},
		{},
		Plan.REASON_INVALID_TARGET
	)
	_rejection_case(
		"wizard.lightning",
		{"has_target": true},
		{"mana": 0},
		Plan.REASON_INSUFFICIENT_RESOURCE
	)
	assert(_checked == 3, "all rejection cases must run")
	await get_tree().process_frame
	print("SKILL_PLAN_REJECTION_REASON_PARITY_PASS cases=3")
	get_tree().quit(0)


func _rejection_case(
	skill_id: String,
	target_overrides: Dictionary,
	resource_overrides: Dictionary,
	expected_reason: String
) -> void:
	_checked += 1
	var target_context := Fixtures.default_target_context(
		bool(target_overrides.get("has_target", true))
	)
	target_context.merge(target_overrides, true)
	var resource_context := Fixtures.default_resource_context(500)
	resource_context.merge(resource_overrides, true)
	var request := Fixtures.make_request(
		skill_id,
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		target_context,
		resource_context
	)
	var legacy: Dictionary = Router.execute(request)
	assert(
		not bool(legacy.get("accepted", true)),
		"%s must be rejected by the legacy planner" % skill_id
	)
	var plan: Dictionary = Plan.build_plan(
		request,
		Fixtures.canonical_context(1, "q3a:reject:%s" % skill_id)
	)
	var legacy_normalized := Plan.normalize_reason(
		str(legacy.get("reason", ""))
	)
	assert(
		legacy_normalized == expected_reason,
		"%s legacy normalized reason mismatch: %s" % [skill_id, legacy_normalized]
	)
	assert(
		str(plan.get("rejection", {}).get("reason", "")) == expected_reason,
		"%s canonical reason mismatch" % skill_id
	)
	assert(
		not bool(plan.get("rejection", {}).get("accepted", true)),
		"%s canonical plan must be rejected" % skill_id
	)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
