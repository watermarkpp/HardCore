extends Node

## R2-3 (GPT audit adoption): the fire wall cap policy must survive the
## PRODUCTION canonical-plan boundary. wizard_canonical_runtime_test proves
## SOT → WizardSkillRuntime effect; this test proves the full production
## chain SOT → runtime effect → SkillExecutionPlanContract ground descriptor:
##
##   Router.build_canonical_plan(...)
##     → plan["ground_effect_descriptors"][0]["cap_policy"] == "evict_oldest"
##     → plan["ground_effect_descriptors"][0]["max_active_fields_per_caster"]
##       == "config_required_default_8"
##
## If a future plan-contract change silently drops the cap fields, GameRoot
## would fail closed to reject_new again and the ninth fire wall would lock
## the skill out for its whole 10-40s duration window without any test
## noticing. This gate exists to make that regression impossible to miss.

const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var snapshot: Dictionary = Fixtures.circle_snapshot(
		self,
		"wizard.fire_wall",
		"r2:cap:plan:1",
		1,
		Vector2(0, 0),
		2.0
	)
	var request: Dictionary = Fixtures.make_request(
		"wizard.fire_wall",
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		Fixtures.default_resource_context(500)
	)
	var plan: Dictionary = Router.build_canonical_plan(
		request,
		Fixtures.canonical_context(
			1,
			"r2:cap:plan:1",
			7,
			8,
			snapshot
		)
	)
	assert(
		bool(plan.get("rejection", {}).get("accepted", false)),
		"production canonical plan must be accepted, reason: %s" % str(
			plan.get("rejection", {}).get("reason", "")
		)
	)
	var descriptors: Array = plan.get("ground_effect_descriptors", [])
	assert(
		descriptors.size() == 1,
		"fire wall plan must carry exactly one ground descriptor: %d"
		% descriptors.size()
	)
	var descriptor: Dictionary = descriptors[0]
	assert(
		str(descriptor.get("cap_policy", "")) == "evict_oldest",
		"canonical ground descriptor must carry the SOT cap_policy "
		+ "evict_oldest, got '%s'" % str(descriptor.get("cap_policy", ""))
	)
	assert(
		str(descriptor.get("max_active_fields_per_caster", ""))
		== "config_required_default_8",
		"canonical ground descriptor must carry the SOT cap default"
	)
	assert(
		str(descriptor.get("stacking_policy", ""))
		== "same_caster_same_tile_refreshes_duration; one target takes at "
		+ "most one tick per caster per tick",
		"canonical ground descriptor must keep the SOT stacking policy"
	)
	print("FIRE_WALL_CAP_POLICY_CANONICAL_PLAN_PASS")
	get_tree().quit(0)
