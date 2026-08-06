extends Node

## Q3-A: the canonical skill execution plan contract must carry every frozen
## field for spatial and non-spatial skills, and its diagnostics must expose
## the full read-only view.

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan.gd")

var _checked := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_spatial("wizard.lightning", "targeted_sky_strike")
	_check_spatial("wizard.fire_wall", "persistent_ground_damage")
	_check_spatial("wizard.fireball", "projectile_damage")
	_check_spatial("wizard.laser", "piercing_line_damage")
	_check_spatial("wizard.ice_storm", "area_damage")
	_check_spatial_poison("taoist.poison", "poison_resolution")
	_check_non_spatial_amulet("taoist.defense", "pure_defense_buff")
	_check_spatial_amulet("taoist.summon_skeleton", "main_pet_spawn")
	_check_spatial("warrior.thrusting", "")
	assert(_checked == 9, "all contract cases must run")
	_cleanup()
	await get_tree().process_frame
	print("SKILL_PLAN_CONTRACT_PASS cases=%d" % _checked)
	get_tree().quit(0)


func _check_spatial(skill_id: String, expected_action: String) -> void:
	_checked += 1
	var target_context := Fixtures.default_target_context(true)
	var request := Fixtures.make_request(
		skill_id,
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		target_context,
		Fixtures.default_resource_context(500)
	)
	var snapshot := Fixtures.circle_snapshot(
		self,
		skill_id,
		"q3a:contract:%s" % skill_id,
		1,
		Vector2(0, 0),
		2.0
	)
	var plan: Dictionary = Plan.build_plan(
		request,
		Fixtures.canonical_context(1, "q3a:contract:%s" % skill_id, 7, 8, snapshot)
	)
	_assert_contract_fields(plan)
	assert(
		bool(plan.get("rejection", {}).get("accepted", false)),
		"%s must be accepted" % skill_id
	)
	assert(
		str(plan.get("snapshot_id", "")) == str(snapshot.get("snapshot_id", "")),
		"%s must carry the frozen snapshot id" % skill_id
	)
	assert(bool(plan.get("snapshot_required", false)), "%s is spatial" % skill_id)
	assert(str(plan.get("non_spatial_reason", "")) == "", "%s has no non-spatial reason" % skill_id)
	if not expected_action.is_empty():
		var action_types := _action_types(plan.get("gameplay_actions", []))
		assert(
			action_types.has(expected_action),
			"%s must contain gameplay action %s" % [skill_id, expected_action]
		)
	var diag: Dictionary = Plan.skill_execution_plan_diagnostics(plan)
	assert(str(diag.get("plan_id", "")) == str(plan.get("plan_id", "")), "diagnostics plan_id")
	assert(str(diag.get("snapshot_id", "")) == str(plan.get("snapshot_id", "")), "diagnostics snapshot_id")


func _check_non_spatial(skill_id: String, expected_reason: String) -> void:
	_checked += 1
	var request := Fixtures.make_request(
		skill_id,
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		{},
		Fixtures.default_resource_context(500)
	)
	var plan: Dictionary = Plan.build_plan(
		request,
		Fixtures.canonical_context(1, "q3a:non_spatial:%s" % skill_id)
	)
	_assert_contract_fields(plan)
	assert(
		bool(plan.get("rejection", {}).get("accepted", false)),
		"%s must be accepted" % skill_id
	)
	assert(
		not bool(plan.get("snapshot_required", true)),
		"%s must be explicitly non-spatial" % skill_id
	)
	assert(
		str(plan.get("non_spatial_reason", "")) == expected_reason,
		"%s non-spatial reason mismatch" % skill_id
	)


func _check_spatial_amulet(skill_id: String, expected_action: String) -> void:
	_checked += 1
	var request := Fixtures.make_request(
		skill_id,
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		Fixtures.amulet_resource_context(500)
	)
	var snapshot := Fixtures.circle_snapshot(
		self,
		skill_id,
		"q3a:contract:%s" % skill_id,
		1,
		Vector2(0, 0),
		2.0
	)
	var plan: Dictionary = Plan.build_plan(
		request,
		Fixtures.canonical_context(1, "q3a:contract:%s" % skill_id, 7, 8, snapshot)
	)
	_assert_contract_fields(plan)
	assert(
		bool(plan.get("rejection", {}).get("accepted", false)),
		"%s must be accepted" % skill_id
	)
	if not expected_action.is_empty():
		var action_types := _action_types(plan.get("gameplay_actions", []))
		assert(
			action_types.has(expected_action),
			"%s must contain gameplay action %s" % [skill_id, expected_action]
		)


func _check_spatial_poison(skill_id: String, expected_action: String) -> void:
	_checked += 1
	var request := Fixtures.make_request(
		skill_id,
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		Fixtures.poison_resource_context(500)
	)
	var snapshot := Fixtures.circle_snapshot(
		self,
		skill_id,
		"q3a:contract:%s" % skill_id,
		1,
		Vector2(0, 0),
		2.0
	)
	var plan: Dictionary = Plan.build_plan(
		request,
		Fixtures.canonical_context(1, "q3a:contract:%s" % skill_id, 7, 8, snapshot)
	)
	_assert_contract_fields(plan)
	assert(
		bool(plan.get("rejection", {}).get("accepted", false)),
		"%s must be accepted" % skill_id
	)
	if not expected_action.is_empty():
		var action_types := _action_types(plan.get("gameplay_actions", []))
		assert(
			action_types.has(expected_action),
			"%s must contain gameplay action %s" % [skill_id, expected_action]
		)


func _check_non_spatial_amulet(
	skill_id: String,
	expected_reason: String
) -> void:
	_checked += 1
	var request := Fixtures.make_request(
		skill_id,
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		Fixtures.amulet_resource_context(500)
	)
	var plan: Dictionary = Plan.build_plan(
		request,
		Fixtures.canonical_context(1, "q3a:non_spatial:%s" % skill_id)
	)
	_assert_contract_fields(plan)
	assert(
		bool(plan.get("rejection", {}).get("accepted", false)),
		"%s must be accepted" % skill_id
	)
	assert(
		not bool(plan.get("snapshot_required", true)),
		"%s must be explicitly non-spatial" % skill_id
	)
	assert(
		str(plan.get("non_spatial_reason", "")) == expected_reason,
		"%s non-spatial reason mismatch" % skill_id
	)


func _assert_contract_fields(plan: Dictionary) -> void:
	assert(str(plan.get("contract", "")) == "skill_execution_plan.v1", "contract")
	assert(int(plan.get("plan_version", 0)) == 1, "plan_version")
	assert(not str(plan.get("plan_id", "")).is_empty(), "plan_id")
	assert(not str(plan.get("release_id", "")).is_empty(), "release_id")
	assert(not str(plan.get("skill_id", "")).is_empty(), "skill_id")
	assert(plan.has("skill_definition_revision"), "skill_definition_revision")
	assert(plan.has("caster_runtime_id") and plan.has("target_runtime_id"), "runtime ids")
	assert(plan.has("runtime_map_id"), "runtime_map_id")
	assert(plan.has("input_mode") and plan.has("requested_direction"), "input/direction")
	assert(plan.has("resolved_direction") and plan.has("lock_on_context"), "direction/lock")
	assert(plan.has("resource_cost") and plan.has("cooldown_contract"), "cost/cooldown")
	assert(plan.has("canonical_snapshot"), "canonical_snapshot")
	assert(plan.has("gameplay_actions") and plan.has("presentation_actions"), "actions")
	assert(plan.has("projectile_descriptors"), "projectile_descriptors")
	assert(plan.has("ground_effect_descriptors"), "ground_effect_descriptors")
	assert(plan.has("summon_descriptors"), "summon_descriptors")
	assert(plan.has("rejection") and plan.get("rejection", {}).has("accepted"), "rejection")
	assert(str(plan.get("created_by", "")) == "canonical_planner.v1", "created_by")
	assert(not str(plan.get("plan_hash", "")).is_empty(), "plan_hash")


func _action_types(actions: Array) -> Array:
	var result: Array = []
	for action: Variant in actions:
		if action is Dictionary:
			result.append(str((action as Dictionary).get("type", "")))
	return result


func _cleanup() -> void:
	pass


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
