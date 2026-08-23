extends Node

## Q3-C: canonical planner output must match the frozen Q3-A/B golden fixtures
## field by field for the full 10-skill matrix. The golden data was captured at
## c1bc7a15 (where Q3-A shadow parity proved canonical == legacy) before the
## legacy planner was removed.

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

const SKILLS := [
	"warrior.basic_swordsmanship",
	"warrior.thrusting",
	"wizard.lightning",
	"wizard.laser",
	"wizard.fire_wall",
	"wizard.fireball",
	"wizard.ice_storm",
	"taoist.defense",
	"taoist.poison",
	"taoist.summon_skeleton",
]

var _differences: Array = []
var _checked := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for skill_id: String in SKILLS:
		_check_skill(skill_id)
	assert(_checked == SKILLS.size(), "all golden contract cases must run")
	assert(
		_differences.is_empty(),
		"golden contract differences: %s" % "; ".join(_differences)
	)
	await get_tree().process_frame
	print("SKILL_PLAN_GOLDEN_CONTRACT_PASS skills=%d differences=0" % SKILLS.size())
	get_tree().quit(0)


func _check_skill(skill_id: String) -> void:
	_checked += 1
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
	_compare("%s.accepted" % skill_id, golden.get("accepted"), rejection.get("accepted"))
	_compare("%s.reason" % skill_id, golden.get("rejection_reason"), rejection.get("reason"))
	_compare(
		"%s.mp" % skill_id,
		(golden.get("resource_cost", {}) as Dictionary).get("mp_cost"),
		(plan.get("resource_cost", {}) as Dictionary).get("mp_cost")
	)
	_compare(
		"%s.cooldown" % skill_id,
		(golden.get("cooldown", {}) as Dictionary).get("cooldown_ms"),
		(plan.get("cooldown_contract", {}) as Dictionary).get("cooldown_ms")
	)
	_compare(
		"%s.snapshot_required" % skill_id,
		golden.get("snapshot_required"),
		plan.get("snapshot_required")
	)
	_compare(
		"%s.non_spatial_reason" % skill_id,
		golden.get("non_spatial_reason"),
		plan.get("non_spatial_reason")
	)
	_compare(
		"%s.actions" % skill_id,
		_effect_types(golden.get("gameplay_actions", []) as Array),
		_effect_types(plan.get("gameplay_actions", []) as Array)
	)
	_compare(
		"%s.descriptors" % skill_id,
		[
			(golden.get("projectile_descriptors", []) as Array).size(),
			(golden.get("ground_effect_descriptors", []) as Array).size(),
			(golden.get("summon_descriptors", []) as Array).size(),
		],
		[
			(plan.get("projectile_descriptors", []) as Array).size(),
			(plan.get("ground_effect_descriptors", []) as Array).size(),
			(plan.get("summon_descriptors", []) as Array).size(),
		]
	)
	_compare(
		"%s.snapshot_hash" % skill_id,
		golden.get("snapshot_hash"),
		_snapshot_hash(plan.get("canonical_snapshot", {}))
	)


func _compare(label: String, expected: Variant, actual: Variant) -> void:
	var mismatch := false
	if (expected is int or expected is float) and (actual is int or actual is float):
		mismatch = not is_equal_approx(float(expected), float(actual))
	else:
		mismatch = str(expected) != str(actual)
	if mismatch:
		_differences.append(
			"%s expected=%s actual=%s" % [label, str(expected), str(actual)]
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
