extends Node

const RuntimeFixture := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()

class OneCallbackEnemy extends EnemyActor:
	var callback_count := 0
	var callback_delta := 0.0
	func _physics_process(delta: float) -> void:
		callback_count += 1
		callback_delta = delta
		super._physics_process(delta)
		set_physics_process(false)

var _failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	Enemy.configure_owner_optional_budget_for_test(false)
	Enemy.configure_attack_visual_policy_for_test(false, false)
	Enemy.configure_owner_decision_interval_for_test(0)
	Enemy.configure_pursuit_process_budget_mode("immediate")
	await _run_real_physics_callback_contract()
	var receipt_ok := _proof.write_receipt("b11_struck_partial_physics_motion_contract_20261010", _proof.records.size(), _failures.size())
	if not receipt_ok:
		_failures.append("formal movement callback receipt rejected")
	if _failures.is_empty():
		print("B11_STRUCK_PARTIAL_PHYSICS_MOTION_PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("HC_TEST_FAIL ", failure)
	get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	_proof.record(condition, message)
	if not condition:
		_failures.append(message)

func _run_real_physics_callback_contract() -> void:
	var victim: PlayerCharacter = RuntimeFixture.player(self, Vector2(14.0, 8.0))
	var owned := OneCallbackEnemy.new()
	var actor: EnemyActor = RuntimeFixture.enemy(self, 64, Vector2(8.0, 8.0), victim, {}, owned)
	# Drain fixture setup feedback, then create an actual partial struck tail.
	if actor.visual != null:
		actor.visual.advance_struck_action(5.0)
	var started := actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"pursuit", victim)
	_check(started and actor._movement_step_active, "fixture starts a real pursuit leg before struck tail")
	if not started:
		RuntimeFixture.dispose(actor, victim)
		return
	if actor.visual != null:
		actor.visual.queue_struck(1)
		# Monster 64's authored hit action is longer than one physics frame. Leave
		# a small tail so this callback has both S and U slices.
		actor.visual.advance_struck_action(0.38)
		print("B11_PRE_STRUCK_INTERNAL ", JSON.stringify({"hit_remaining": actor.visual._hit_remaining, "action_duration": actor.visual._action_duration, "frame_count": actor.visual._canonical_struck_frame_count}))
	var before := RuntimeFixture.to_ground(actor.global_position)
	print("B11_PRE_CALLBACK ", JSON.stringify({"pending": actor.visual.pending_struck_count(), "active": actor.visual.is_struck_action_active(), "clock": actor._combat_action_time_s, "physics": actor.is_physics_processing()}))
	actor.set_physics_process(true)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(owned.callback_count == 1, "exactly one real physics callback is observed")
	var after := RuntimeFixture.to_ground(actor.global_position)
	var frame_d := 1.0 / float(Engine.physics_ticks_per_second)
	var struck_s := actor._struck_pause_in_tick_s
	var usable_u := maxf(0.0, frame_d - struck_s)
	var distance := before.distance_to(after)
	var speed := actor.move_speed_gu_per_sec * actor._movement_step_speed_scale
	print("B11_POST_CALLBACK_RAW ", JSON.stringify({"callback_delta": owned.callback_delta, "clock": actor._combat_action_time_s, "physics": actor.is_physics_processing(), "pending": actor.visual.pending_struck_count(), "active": actor.visual.is_struck_action_active()}))
	print("B11_PARTIAL_PHYSICS_OBSERVATION ", JSON.stringify({
		"frame_d": frame_d,
		"struck_s": struck_s,
		"usable_u": usable_u,
		"distance": distance,
		"speed": speed,
		"movement_active": actor._movement_step_active,
		"callback_position_before": before,
		"callback_position_after": after,
	}))
	_check(struck_s > 0.000001 and struck_s < frame_d, "real physics callback observes a partial struck tail")
	_check(distance <= speed * usable_u + 0.0005, "partial struck callback spends only usable movement budget")
	RuntimeFixture.dispose(actor, victim)
