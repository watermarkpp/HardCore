extends Node

## Q3-A/Q3-C profession matrix: the canonical planner output for the frozen
## 10-skill matrix must match the golden fixtures captured at c1bc7a15 (where
## legacy shadow parity was proven). The legacy planner oracle was removed.

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

const MATRIX := [
	{"skill": "warrior.basic_swordsmanship"},
	{"skill": "warrior.thrusting"},
	{"skill": "wizard.lightning"},
	{"skill": "wizard.laser"},
	{"skill": "wizard.fire_wall"},
	{"skill": "wizard.fireball"},
	{"skill": "wizard.ice_storm"},
	{"skill": "taoist.defense", "amulet": true},
	{"skill": "taoist.poison", "poison": true},
	{"skill": "taoist.summon_skeleton", "amulet": true},
]

var _differences: Array = []
var _rows: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for row: Dictionary in MATRIX:
		_matrix_case(str(row.get("skill", "")))
	assert(
		_differences.is_empty(),
		"profession matrix golden differences: %s" % "; ".join(_differences)
	)
	print(
		"SKILL_PLAN_PROFESSION_MATRIX_PASS skills=%d differences=0"
		% MATRIX.size()
	)
	for row_line: String in _rows:
		print("SKILL_PLAN_MATRIX_ROW %s" % row_line)
	await get_tree().process_frame
	get_tree().quit(0)


func _matrix_case(skill_id: String) -> void:
	var golden := _load_golden(skill_id)
	var release_id := str(
		(golden.get("input_context", {}) as Dictionary).get(
			"release_id",
			"q3c:golden:%s" % skill_id
		)
	)
	var plan := Fixtures.build_canonical_plan(
		skill_id,
		3,
		50,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		_resource_context(skill_id),
		42,
		1,
		release_id,
		Fixtures.circle_snapshot(
			self,
			skill_id,
			release_id,
			1,
			Vector2(0, 0),
			2.0
		)
	)
	var rejection: Dictionary = plan.get("rejection", {})
	Fixtures.compare_field(
		"%s.accepted" % skill_id,
		bool(golden.get("accepted", false)),
		bool(rejection.get("accepted", false)),
		_differences
	)
	Fixtures.compare_field(
		"%s.reason" % skill_id,
		str(golden.get("rejection_reason", "")),
		str(rejection.get("reason", "")),
		_differences
	)
	Fixtures.compare_field(
		"%s.mp" % skill_id,
		int((golden.get("resource_cost", {}) as Dictionary).get("mp_cost", 0)),
		int((plan.get("resource_cost", {}) as Dictionary).get("mp_cost", 0)),
		_differences
	)
	Fixtures.compare_field(
		"%s.cooldown" % skill_id,
		int((golden.get("cooldown", {}) as Dictionary).get("cooldown_ms", 0)),
		int((plan.get("cooldown_contract", {}) as Dictionary).get(
			"cooldown_ms",
			0
		)),
		_differences
	)
	Fixtures.compare_field(
		"%s.snapshot_required" % skill_id,
		bool(golden.get("snapshot_required", false)),
		bool(plan.get("snapshot_required", false)),
		_differences
	)
	Fixtures.compare_field(
		"%s.snapshot_hash" % skill_id,
		str(golden.get("snapshot_hash", "")),
		str(_snapshot_hash(plan.get("canonical_snapshot", {}))),
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


func _load_golden(skill_id: String) -> Dictionary:
	var file := FileAccess.open(
		"res://tests/fixtures/skill_plan_golden/%s.json"
			% skill_id.replace(".", "_"),
		FileAccess.READ
	)
	assert(file != null, "golden fixture missing for %s" % skill_id)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "golden fixture must be a dictionary")
	return parsed as Dictionary


func _resource_context(skill_id: String) -> Dictionary:
	if skill_id == "taoist.poison":
		return Fixtures.poison_resource_context(500)
	if skill_id in ["taoist.defense", "taoist.summon_skeleton"]:
		return Fixtures.amulet_resource_context(500)
	return Fixtures.default_resource_context(500)


func _snapshot_hash(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return ""
	return "%d" % hash(JSON.stringify({
		"contract_id": str(snapshot.get("contract_id", "")),
		"shape_contract_id": str(snapshot.get("shape_contract_id", "")),
		"shape_type": str(snapshot.get("shape_type", "")),
		"coordinate_space": str(snapshot.get("coordinate_space", "")),
		"snapshot_id": str(snapshot.get("snapshot_id", "")),
		"runtime_map_id": int(snapshot.get("runtime_map_id", -1)),
		"skill_id": str(snapshot.get("skill_id", "")),
	}))


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
