extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const Cast := preload("res://scripts/skills/skill_cast_request.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	var before_stats: Dictionary = PlayerState.computed_stats.duplicate(true)
	var before_inventory: Array = PlayerState.inventory.duplicate(true)
	var valid := Cast.create("warrior.basic_swordsmanship", 0, 1, Vector2i.ZERO, Vector2i.DOWN, {}, {"mana":100}, 42)
	var context := {"release_id":"test:invalid-request:control", "runtime_map_id":-1}
	var control := Router.build_canonical_plan(valid, context)
	check(bool(control.get("rejection", {}).get("accepted", false)), "original non-spatial canonical control remains accepted")
	var bad: Array = [null, 7, [], true, "not a request", {}]
	for index in bad.size():
		var plan: Dictionary = Router.build_canonical_plan(bad[index], context)
		check(plan.get("contract")=="skill_execution_plan.v1" and plan.get("rejection", {}).get("accepted")==false,
			"invalid envelope returns a canonical rejection instead of Script error " + str(index))
		check(plan.get("gameplay_actions", [])==[] and plan.get("presentation_actions", [])==[], "rejected input creates no actions " + str(index))
	for key: String in ["target_context", "resource_context"]:
		for value: Variant in [null, [], 9, "not a context"]:
			var malformed := valid.duplicate(true)
			malformed[key] = value
			var plan := Router.build_canonical_plan(malformed, context)
			check(plan.get("contract")=="skill_execution_plan.v1" and plan.get("rejection", {}).get("accepted")==false,
				"malformed nested context rejects before typed service " + key + ":" + str(typeof(value)))
	var refused := {"contract_id":"invalid", "rank":{}, "seed":[], "facing":null, "target_context":null}
	var invalid_plan := Router.build_canonical_plan(refused)
	check(invalid_plan.get("rejection", {}).get("accepted")==false, "rejection diagnostic never dereferences malformed nested fields")
	check(PlayerState.computed_stats==before_stats and PlayerState.inventory==before_inventory, "pure rejection leaves actual configuration and inventory unchanged")
	var after := Router.build_canonical_plan(valid, context)
	check(after==control, "invalid probes do not alter the next original plan or deterministic RNG")
	if not proof.write_receipt("canonical_request_rejection_test", checks, failures.size()): failures.append("receipt")
	print("CANONICAL_REQUEST_REJECTION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
