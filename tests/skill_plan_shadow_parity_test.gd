extends Node

## Q3-A shadow parity: the canonical planner and the legacy router planner read
## the same frozen input; all comparable fields must match (differences = 0).

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")

var _differences: Array = []
var _cases := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_parity_case("wizard.lightning", true)
	_parity_case("wizard.laser", true)
	_parity_case("wizard.fire_wall", true)
	_parity_case("wizard.fireball", true)
	_parity_case("wizard.ice_storm", true)
	_parity_case_poison("taoist.poison")
	_parity_case_amulet("taoist.defense")
	_parity_case_amulet("taoist.summon_skeleton")
	_parity_case("warrior.thrusting", true)
	assert(_cases == 9, "all parity cases must run")
	assert(
		_differences.is_empty(),
		"canonical plan must match legacy plan: %s" % "; ".join(_differences)
	)
	await get_tree().process_frame
	print("SKILL_PLAN_SHADOW_PARITY_PASS cases=%d differences=0" % _cases)
	get_tree().quit(0)


func _parity_case(skill_id: String, needs_target: bool) -> void:
	_cases += 1
	var target_context := Fixtures.default_target_context(needs_target)
	var request := Fixtures.make_request(
		skill_id,
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		target_context,
		Fixtures.default_resource_context(500)
	)
	_parity_with_request(skill_id, request)


func _parity_case_amulet(skill_id: String) -> void:
	_cases += 1
	var request := Fixtures.make_request(
		skill_id,
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		Fixtures.amulet_resource_context(500)
	)
	_parity_with_request(skill_id, request)


func _parity_case_poison(skill_id: String) -> void:
	_cases += 1
	var request := Fixtures.make_request(
		skill_id,
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		Fixtures.poison_resource_context(500)
	)
	_parity_with_request(skill_id, request)


func _parity_with_request(skill_id: String, request: Dictionary) -> void:
	var legacy: Dictionary = Router.execute(request)
	var snapshot := Fixtures.circle_snapshot(
		self,
		skill_id,
		"q3a:parity:%s" % skill_id,
		1,
		Vector2(0, 0),
		2.0
	)
	var plan: Dictionary = Plan.build_plan(
		request,
		Fixtures.canonical_context(
			1,
			"q3a:parity:%s" % skill_id,
			7,
			8,
			snapshot
		)
	)
	var rejection: Dictionary = plan.get("rejection", {})
	Fixtures.compare_field(
		"%s.accepted" % skill_id,
		bool(legacy.get("accepted", false)),
		bool(rejection.get("accepted", false)),
		_differences
	)
	Fixtures.compare_field(
		"%s.reason" % skill_id,
		Plan.normalize_reason(str(legacy.get("reason", ""))),
		str(rejection.get("reason", "")),
		_differences
	)
	Fixtures.compare_field(
		"%s.direction" % skill_id,
		request.get("facing", Vector2i.ZERO),
		plan.get("resolved_direction", Vector2i.ZERO),
		_differences
	)
	Fixtures.compare_field(
		"%s.map" % skill_id,
		1,
		plan.get("runtime_map_id", -1),
		_differences
	)
	var legacy_quote: Dictionary = legacy.get("resource_quote", {})
	var canonical_cost: Dictionary = plan.get("resource_cost", {})
	Fixtures.compare_field(
		"%s.mp_cost" % skill_id,
		int(legacy_quote.get("mp_cost", 0)),
		int(canonical_cost.get("mp_cost", 0)),
		_differences
	)
	var legacy_effect_types := _effect_types(legacy.get("effects", []))
	var canonical_action_types := _effect_types(plan.get("gameplay_actions", []))
	Fixtures.compare_field(
		"%s.actions" % skill_id,
		legacy_effect_types,
		canonical_action_types,
		_differences
	)
	if not str(plan.get("non_spatial_reason", "")).is_empty():
		Fixtures.compare_field(
			"%s.snapshot_required" % skill_id,
			false,
			plan.get("snapshot_required", true),
			_differences
		)
	else:
		Fixtures.compare_field(
			"%s.snapshot_id" % skill_id,
			str(snapshot.get("snapshot_id", "")),
			str(plan.get("snapshot_id", "")),
			_differences
		)


func _effect_types(effects: Array) -> Array:
	var result: Array = []
	for effect: Variant in effects:
		if effect is Dictionary:
			result.append(str((effect as Dictionary).get("type", "")))
	return result


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
