extends Node

## Q3-C golden parity: the canonical planner output must match the frozen
## Q3-A/Q3-B golden fixtures (captured at c1bc7a15 where legacy shadow parity
## was proven). The legacy the legacy router entry oracle was removed with the legacy
## planner; golden fixtures are now the frozen reference.

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")

var _differences: Array = []
var _cases := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_golden_case("wizard.lightning")
	_golden_case("wizard.laser")
	_golden_case("wizard.fire_wall")
	_golden_case("wizard.fireball")
	_golden_case("wizard.ice_storm")
	_golden_case("taoist.poison")
	_golden_case("taoist.defense")
	_golden_case("taoist.summon_skeleton")
	_golden_case("warrior.thrusting")
	assert(_cases == 9, "all golden parity cases must run")
	assert(
		_differences.is_empty(),
		"canonical plan must match golden fixture: %s"
			% "; ".join(_differences)
	)
	await get_tree().process_frame
	print("SKILL_PLAN_GOLDEN_PARITY_PASS cases=%d differences=0" % _cases)
	get_tree().quit(0)


func _golden_case(skill_id: String) -> void:
	_cases += 1
	var golden := _load_golden(skill_id)
	# All golden inputs were captured with has_target=true (target_tile 1,0).
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
		str((golden.get("input_context", {}) as Dictionary).get(
			"release_id",
			"q3c:golden:%s" % skill_id
		)),
		Fixtures.circle_snapshot(
			self,
			skill_id,
			str((golden.get("input_context", {}) as Dictionary).get(
				"release_id",
				"q3c:golden:%s" % skill_id
			)),
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
		"%s.non_spatial_reason" % skill_id,
		str(golden.get("non_spatial_reason", "")),
		str(plan.get("non_spatial_reason", "")),
		_differences
	)
	Fixtures.compare_field(
		"%s.actions" % skill_id,
		_effect_types((golden.get("gameplay_actions", []) as Array)),
		_effect_types((plan.get("gameplay_actions", []) as Array)),
		_differences
	)
	Fixtures.compare_field(
		"%s.snapshot_hash" % skill_id,
		str(golden.get("snapshot_hash", "")),
		str(_snapshot_hash(plan.get("canonical_snapshot", {}))),
		_differences
	)


func _load_golden(skill_id: String) -> Dictionary:
	var file_name := "res://tests/fixtures/skill_plan_golden/%s.json" % (
		skill_id.replace(".", "_")
	)
	var file := FileAccess.open(file_name, FileAccess.READ)
	assert(file != null, "golden fixture missing: %s" % file_name)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "golden fixture must be a dictionary")
	return parsed as Dictionary


func _resource_context(skill_id: String) -> Dictionary:
	if skill_id == "taoist.poison":
		return Fixtures.poison_resource_context(500)
	if skill_id in ["taoist.defense", "taoist.summon_skeleton"]:
		return Fixtures.amulet_resource_context(500)
	return Fixtures.default_resource_context(500)


func _effect_types(effects: Array) -> Array:
	var result: Array = []
	for effect: Variant in effects:
		if effect is Dictionary:
			result.append(str((effect as Dictionary).get("type", "")))
	return result


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
