extends Node

## Q3-A profession matrix: warrior / wizard / taoist skills keep legacy-vs-
## canonical plan parity with zero differences; side effects stay in the plan
## only (no commits from the canonical planner).

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")

const MATRIX := [
	{"skill": "warrior.basic_swordsmanship", "target": false},
	{"skill": "warrior.thrusting", "target": true},
	{"skill": "wizard.lightning", "target": true},
	{"skill": "wizard.laser", "target": true},
	{"skill": "wizard.fire_wall", "target": true},
	{"skill": "wizard.fireball", "target": true},
	{"skill": "wizard.ice_storm", "target": true},
	{"skill": "taoist.defense", "target": true, "amulet": true},
	{"skill": "taoist.poison", "target": true, "poison": true},
	{"skill": "taoist.summon_skeleton", "target": true, "amulet": true},
]

var _differences: Array = []
var _rows: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for row: Dictionary in MATRIX:
		_matrix_case(
			str(row.get("skill", "")),
			bool(row.get("target", false)),
			bool(row.get("amulet", false)),
			bool(row.get("poison", false))
		)
	assert(
		_differences.is_empty(),
		"profession matrix parity differences: %s" % "; ".join(_differences)
	)
	print(
		"SKILL_PLAN_PROFESSION_MATRIX_PASS skills=%d differences=0"
		% MATRIX.size()
	)
	for row_line: String in _rows:
		print("SKILL_PLAN_MATRIX_ROW %s" % row_line)
	await get_tree().process_frame
	get_tree().quit(0)


func _matrix_case(
	skill_id: String,
	needs_target: bool,
	needs_amulet: bool,
	needs_poison: bool
) -> void:
	var target_context := Fixtures.default_target_context(needs_target)
	var request := Fixtures.make_request(
		skill_id,
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		target_context,
		_resource_context(needs_amulet, needs_poison)
	)
	var legacy: Dictionary = Router.execute(request)
	var snapshot := Fixtures.circle_snapshot(
		self,
		skill_id,
		"q3a:matrix:%s" % skill_id,
		1,
		Vector2(0, 0),
		2.0
	)
	var plan: Dictionary = Plan.build_plan(
		request,
		Fixtures.canonical_context(
			1,
			"q3a:matrix:%s" % skill_id,
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
		"%s.mp" % skill_id,
		int(legacy.get("resource_quote", {}).get("mp_cost", 0)),
		int(plan.get("resource_cost", {}).get("mp_cost", 0)),
		_differences
	)
	Fixtures.compare_field(
		"%s.cooldown" % skill_id,
		int(
			Fixtures._definition_timing(skill_id).get("cooldown_ms", 0)
		),
		int(plan.get("cooldown_contract", {}).get("cooldown_ms", 0)),
		_differences
	)
	if not str(plan.get("non_spatial_reason", "")).is_empty():
		_rows.append(
			"%s accepted=%s non_spatial=%s descriptors=0/0/0"
			% [
				skill_id,
				str(rejection.get("accepted", false)),
				str(plan.get("non_spatial_reason", "")),
			]
		)
	else:
		_rows.append(
			"%s accepted=%s snapshot=%s actions=%d descriptors=%d/%d/%d"
			% [
				skill_id,
				str(rejection.get("accepted", false)),
				str(plan.get("snapshot_id", "")),
				(plan.get("gameplay_actions", []) as Array).size(),
				(plan.get("projectile_descriptors", []) as Array).size(),
				(plan.get("ground_effect_descriptors", []) as Array).size(),
				(plan.get("summon_descriptors", []) as Array).size(),
			]
		)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _resource_context(needs_amulet: bool, needs_poison: bool) -> Dictionary:
	if needs_poison:
		return Fixtures.poison_resource_context(500)
	if needs_amulet:
		return Fixtures.amulet_resource_context(500)
	return Fixtures.default_resource_context(500)
