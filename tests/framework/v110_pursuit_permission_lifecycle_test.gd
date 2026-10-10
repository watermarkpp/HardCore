extends Node

const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Budget := preload("res://scripts/monster_ai_package/decision_budget.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const SCENE_ID := "v110_pursuit_permission_lifecycle_test"
var current_map_id := 1
var _zone_generation := 1
var proof := Proof.new()
var actors: Array[EnemyActor] = []
var victims: Array[PlayerCharacter] = []
var index := F.Spatial.new()

func _epoch() -> int:
	return Engine.get_process_frames()

func _clock() -> int:
	return Time.get_ticks_usec()

func _ready() -> void:
	await get_tree().process_frame
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	# Deliberate optional-budget denial: only this component test changes the
	# test provider. Source clocks, actual physics and gameplay permissions run.
	FrameBudget.configure_for_tests(0, _epoch, _clock)
	for i: int in 12:
		var ground := Vector2(6.0 + 15.0 * (i % 4), 6.0 + 15.0 * (i / 4))
		var victim := F.player(self, ground + Vector2(4.5, 0))
		var actor := EnemyActor.new()
		actor.setup(GameData.get_monster_by_id(64), victim, false)
		actor.configure_runtime_map_projection(1, Callable(F.GU, "ground_delta_gu_to_screen_delta_px"), Callable(F.GU, "screen_delta_px_to_ground_delta_gu"))
		actor.configure_terrain_navigation_context(F.open_context())
		actor.global_position = F.to_screen(ground)
		actor.set_meta("spawn_position", actor.global_position)
		actor.set_meta("safe_zones", [])
		actor.set_meta("zone_generation", 1)
		actor.configure_spatial_index(index, actor.get_instance_id())
		index.register(actor.get_instance_id(), 1, ground, actor.combat_radius_gu, i + 1, actor, Callable(actor, "spatial_index_position"))
		add_child(actor)
		actors.append(actor)
		victims.append(victim)
		proof.record(actor.request_passive_target_wakeup(victim, 1, 1), "real aura event admitted under zero optional budget")
	for tick: int in 135:
		await get_tree().physics_frame
	for actor: EnemyActor in actors:
		proof.record(actor._source176_pursuit_permission_valid(), "actual source grant retained while optional work cannot execute")
		proof.record(actor._source176_pursuit_permission.size() == 5, "repeated grants remain one bounded identity record")
		proof.record(not actor._movement_step_active and not actor._hc_pursuit_session, "no movement or fabricated session under denied planning")
	actors[1].control_time = 0.5
	proof.record(not actors[1]._source176_pursuit_permission_valid(), "control retires pending movement before a leg exists")
	actors[2].charm_time = 0.5
	proof.record(not actors[2]._source176_pursuit_permission_valid(), "charm retires pending movement before a leg exists")
	actors[3].target = victims[0]
	proof.record(not actors[3]._source176_pursuit_permission_valid(), "target change cannot inherit old permission")
	victims[4].combat_epoch += 1
	proof.record(not actors[4]._source176_pursuit_permission_valid(), "same target object new life cannot inherit old permission")
	actors[5].setup(GameData.get_monster_by_id(64), victims[5], false)
	proof.record(not actors[5]._source176_pursuit_permission_valid(), "same enemy object new life cannot inherit old permission")
	actors[6].set_meta("zone_generation", 2)
	proof.record(not actors[6]._source176_pursuit_permission_valid(), "zone replacement rejects old permission")
	actors[7].runtime_map_id = 2
	proof.record(not actors[7]._source176_pursuit_permission_valid(), "map change rejects old permission")
	actors[8]._hc_forget(victims[8])
	proof.record(not actors[8]._source176_pursuit_permission_valid(), "focus expiry retires pending permission")
	actors[9]._cancel_autonomous_step(true)
	proof.record(not actors[9]._source176_pursuit_permission_valid(), "explicit movement cancellation retires pending permission")
	actors[10]._hold_pursuit_at_current_position()
	proof.record(not actors[10]._source176_pursuit_permission_valid(), "no-target hold retires pending permission")
	victims[11].queue_free()
	proof.record(not actors[11]._source176_pursuit_permission_valid(), "queued target retirement rejects pending permission")
	for i: int in range(1, actors.size()):
		var actor := actors[i]
		Budget.cancel(actor.get_instance_id())
		index.unregister(actor.spatial_actor_runtime_id)
		actor.free()
	var survivor := actors[0]
	var start := survivor.spatial_index_position()
	var serial := survivor._source176_decision_serial
	var before_scope: Array = survivor._source176_pursuit_permission.duplicate()
	FrameBudget.configure_for_tests(1200, _epoch, _clock)
	for tick: int in 15:
		await get_tree().physics_frame
	proof.record(survivor.spatial_index_position().distance_to(start) > 0.02, "retained permission delivers real movement once planning resumes")
	proof.record(survivor._source176_pursuit_permission.is_empty(), "delivered permission consumed exactly once")
	proof.record(survivor._source176_decision_serial == serial, "delivery does not manufacture or re-evaluate a source movement grant")
	proof.record(survivor._hc_pursuit_session, "existing pursuit owner receives the accepted movement")
	proof.record(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "all synchronous budget scopes close")
	var observations := {"source_serial_before": serial, "source_serial_after": survivor._source176_decision_serial,
		"retained_scope": before_scope, "delivered_motion_gu": survivor.spatial_index_position().distance_to(start),
		"fault_injection": "zero optional budget for 135 actual physics ticks; no movement cadence/clock edits",
		"source_binding": OS.get_environment("HARDCORE_R3_CONTENT_SHA256")}
	var output := FileAccess.open("res://outputs/test_logs/framework/" + SCENE_ID + ".observations.json", FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(observations, "  ")); output.close()
	Budget.cancel(survivor.get_instance_id())
	index.unregister(survivor.spatial_actor_runtime_id)
	survivor.free()
	FrameBudget.reset_test_configuration()
	var failed := 0
	for item: Dictionary in proof.records:
		if not bool(item.passed): failed += 1
	var ok: bool = proof.write_receipt(SCENE_ID, proof.records.size(), failed)
	print("V110_PURSUIT_PERMISSION_LIFECYCLE_%s checks=%d" % ["PASS" if ok else "FAIL", proof.records.size()])
	get_tree().quit(0 if ok else 1)
