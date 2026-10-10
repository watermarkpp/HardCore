extends Node2D

const EffectScript := preload("res://scripts/monster_ranged_projectile_effect.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()

class SourceOwner extends Node2D:
	var combat_enabled := true

func _check(condition: bool, label: String) -> void:
	_proof.record(condition, label)
	if not condition:
		push_error("projectile visual failure flight contract: " + label)

func _ready() -> void:
	await _run()
	var failures := 0
	for item: Dictionary in _proof.records:
		if not bool(item.passed):
			failures += 1
	var receipt_ok := _proof.write_receipt(
		"monster_projectile_visual_failure_flight_contract_test",
		_proof.records.size(),
		failures,
	)
	if not receipt_ok:
		failures += 1
	print("MONSTER_PROJECTILE_VISUAL_FAILURE_FLIGHT_CONTRACT_%s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _run() -> void:
	var source_owner := SourceOwner.new()
	add_child(source_owner)
	var effect: Node2D = EffectScript.new()
	effect.setup({
		"effect_id": EffectScript.EFFECT_ID,
		"release_id": "visual-failure-flight",
		"source_monster_id": 999,
		"source_instance_id": source_owner.get_instance_id(),
		"origin_world_px": Vector2.ZERO,
		"target_world_px": Vector2(400.0, 0.0),
		"duration_seconds": 1.0,
		"presentation_only": false,
		"delivery_kind": "physical_projectile",
	})
	# Keep the descriptor and owner valid while injecting only the narrow visual
	# failure: the fallback source frame path cannot exist.
	effect._source_frame_index = 999999
	add_child(effect)
	await get_tree().process_frame
	_check(not effect.is_finished(), "missing visual frame does not finish an accepted flight")
	_check(not effect.visible, "missing visual frame is hidden without a fallback drawing")
	effect.set_physics_process(false)
	effect.call("_advance_flight", 0.25)
	_check(not effect.is_finished(), "authoritative flight continues after visual failure")
	_check(float(effect.call("progress_ratio")) > 0.0, "authoritative flight clock advances after visual failure")
	source_owner.queue_free()
	effect.queue_free()
	await get_tree().process_frame
