extends Node

const Enemy := preload("res://scripts/enemy.gd")
const RuntimeFixture := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const SpatialRules := preload("res://scripts/world_spatial_rules.gd")

var _failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	if not GameData.is_loaded() or GameData.get_monster_by_id(64).is_empty():
		print("HC_TEST_FAIL formal monster database not loaded")
		get_tree().quit(1)
		return
	await _run_contract()
	if _failures.is_empty():
		print("HC_OWNER_DECISION_WINDOW_CONTRACT_20261009_PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("HC_TEST_FAIL ", failure)
	get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _fixture_enemy(ground: Vector2, victim: PlayerCharacter, context: Dictionary = {}) -> EnemyActor:
	var actor := RuntimeFixture.enemy(self, 64, ground, victim, context)
	# Real damage reception wakes the ordinary actor after the shared fixture
	# disabled automatic physics. This test advances that same body manually.
	actor.set_physics_process(false)
	return actor

func _run_contract() -> void:
	# These direct interval/geometry cases isolate cadence from optional denial;
	# the real budget-on production path is covered by the owner-budget scene.
	Enemy.configure_owner_optional_budget_for_test(false)
	Enemy.configure_attack_visual_policy_for_test(false, false)
	_check(Enemy.configure_pursuit_process_budget_mode("immediate"), "owner-window fixture uses the immediate production budget mode")
	for interval_ms: int in [0, 100, 200, 300]:
		_check(Enemy.configure_owner_decision_interval_for_test(interval_ms), "%d ms owner interval is accepted" % interval_ms)
	await _test_interval_boundaries()
	_check(Enemy.configure_owner_decision_interval_for_test(200), "200 ms owner interval drives the boundary cases")
	await _test_movement_window_and_reset()
	await _test_ready_attack_and_committed_release()
	await _test_collision_wall_and_late_clock()
	await _test_instant_contact_and_visual_move()
	await _test_due_leash_and_immediate_invalidations()
	_check(Enemy.configure_owner_decision_interval_for_test(0), "owner interval restores uncapped behavior")
	Enemy.configure_attack_visual_policy_for_test(false, false)

func _test_due_leash_and_immediate_invalidations() -> void:
	_check(Enemy.configure_owner_decision_interval_for_test(300), "leash maintenance uses the selected 300 ms owner window")
	for scenario: String in ["leash", "death", "map", "safe_zone"]:
		var victim: PlayerCharacter = RuntimeFixture.player(self, Vector2(14.0, 8.0))
		var actor: EnemyActor = _fixture_enemy(Vector2(8.0, 8.0), victim)
		actor.visual.advance_struck_action(5.0)
		actor._combat_action_time_s = 0.0
		await get_tree().physics_frame
		await get_tree().process_frame
		actor._retarget_internal(0.0)
		var deadline: float = actor._owner_decision_next_time_s
		_check(deadline > 0.0 and actor.target == victim, scenario + " begins with a live target and owner deadline")
		match scenario:
			"leash":
				victim.global_position = RuntimeFixture.to_screen(Vector2(80.0, 8.0))
			"death":
				victim.current_hp = 0
			"map":
				victim.set_meta("runtime_map_id", 2)
			"safe_zone":
				var context := SpatialRules.compile_safe_zone_context(1, 1, 1, [{
					"area_id": "owner.window.safe", "shape": "circle",
					"center_ground_gu": Vector2(14.0, 8.0), "radius_gu": 1.0,
					"blocks_monster_damage": true, "blocks_monster_entry": true,
				}])
				_check(bool(context.get("valid", false)), "safe-zone fixture uses the formal compiler")
				actor.set_meta("safe_zone_context", context)
		actor._combat_action_time_s = 0.000001
		await get_tree().physics_frame
		await get_tree().process_frame
		actor._retarget_internal(0.0)
		_check(actor._owner_decision_granted_physics_tick == -1, scenario + " invalidation is checked before the pursuit deadline")
		if scenario == "leash":
			_check(actor.target == victim, "far-distance AI maintenance waits for the owner window")
			actor._combat_action_time_s = deadline + 0.000001
			await get_tree().physics_frame
			await get_tree().process_frame
			actor._retarget_internal(0.0)
			_check(actor.target == null, "due owner window releases a target outside the authored leash")
		else:
			_check(actor.target == null, scenario + " releases the target immediately without a pursuit grant")
		RuntimeFixture.dispose(actor, victim)

func _test_interval_boundaries() -> void:
	for interval_ms: int in [100, 300]:
		_check(Enemy.configure_owner_decision_interval_for_test(interval_ms), "%d ms boundary setup is accepted" % interval_ms)
		var victim: PlayerCharacter = RuntimeFixture.player(self, Vector2(14.0, 8.0))
		var actors: Array[EnemyActor] = []
		for index: int in 4:
			var actor: EnemyActor = _fixture_enemy(Vector2(8.0 + index * 0.25, 8.0), victim)
			if actor.visual != null:
				actor.visual.advance_struck_action(5.0)
			actor._combat_action_time_s = 0.0
			actors.append(actor)
		await get_tree().physics_frame
		await get_tree().process_frame
		for actor: EnemyActor in actors:
			actor._retarget_internal(0.0)
			print("OWNER_FIXTURE_STATE ", JSON.stringify({"id":actor.monster_id,"combat":actor.combat_enabled,"boss":actor.is_boss,"ordinary":actor._source176_ordinary_melee(),"kind":actor.attack_delivery_rule,"area":actor.area_attack_rule,"summon":actor.summon_rule,"now":actor._combat_action_time_s,"next":actor._owner_decision_next_time_s,"tick":Engine.get_physics_frames(),"grant":actor._owner_decision_granted_physics_tick,"reason":actor._hc_last_reason}))
		var deadlines: Array[float] = []
		for actor: EnemyActor in actors:
			deadlines.append(actor._owner_decision_next_time_s)
			_check(actor._owner_decision_granted_physics_tick == Engine.get_physics_frames(), "%d ms boundary records a real planning grant" % interval_ms)
			_check(actor._owner_decision_next_time_s > 0.0 and actor._owner_decision_next_time_s <= float(interval_ms) / 1000.0, "%d ms first deadline is staggered inside its interval" % interval_ms)
		_check(deadlines.max() - deadlines.min() > 0.000001, "%d ms actor identities receive distinct first phases" % interval_ms)
		for actor: EnemyActor in actors:
			if actor.combat_spatial_index != null:
				actor.combat_spatial_index.unregister(actor.spatial_actor_runtime_id)
			actor.free()
		victim.free()

func _test_movement_window_and_reset() -> void:
	var victim: PlayerCharacter = RuntimeFixture.player(self, Vector2(14.0, 8.0))
	var actor: EnemyActor = _fixture_enemy(Vector2(8.0, 8.0), victim)
	if actor.visual != null:
		actor.visual.advance_struck_action(5.0)
	actor._hc_owned_movement_call = true
	actor._combat_action_time_s = 0.0
	await get_tree().physics_frame
	await get_tree().process_frame
	var before: Vector2 = actor.global_position
	actor._retarget_internal(0.0)
	var deadline: float = actor._owner_decision_next_time_s
	_check(deadline > 0.0 and deadline <= 0.2, "real owner planning records a staggered 200 ms owner deadline")
	_check(actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"pursuit", victim), "open owner fixture admits an actual movement leg")
	actor._physics_process_internal(0.05)
	_check(actor.global_position.distance_to(before) > 0.000001 or actor._movement_step_active, "real owner planning reaches the movement body")
	_check(is_equal_approx(actor._owner_decision_next_time_s, deadline), "physics movement does not reset the owner decision deadline")
	victim.global_position = RuntimeFixture.to_screen(Vector2(14.25, 8.0))
	var movement_before_target_shift: Vector2 = actor.global_position
	actor._advance_autonomous_step(0.05)
	_check(actor.global_position.distance_to(movement_before_target_shift) > 0.000001 or not actor._movement_step_active, "active leg continues through a small target movement before the next owner window")
	actor._clear_autonomous_step_state()
	actor._combat_action_time_s = 0.2
	await get_tree().physics_frame
	await get_tree().process_frame
	actor._retarget_internal(0.0)
	var second_deadline: float = actor._owner_decision_next_time_s
	_check(second_deadline >= 0.399 and second_deadline <= 0.401, "subsequent due planning schedules exactly one full 200 ms interval")
	actor._combat_action_time_s = 0.399
	await get_tree().physics_frame
	await get_tree().process_frame
	actor._retarget_internal(0.0)
	_check(is_equal_approx(actor._owner_decision_next_time_s, second_deadline), "199 ms after a full interval does not replan")
	_check(actor._owner_decision_granted_physics_tick == -1, "not-due owner attempt records no planning grant")
	Enemy.reset_pursuit_process_budget_diagnostics()
	_check(is_equal_approx(actor._owner_decision_next_time_s, second_deadline), "diagnostic reset preserves business deadline state")
	RuntimeFixture.dispose(actor, victim)

func _test_instant_contact_and_visual_move() -> void:
	Enemy.configure_attack_visual_policy_for_test(true, true)
	_check(Enemy.configure_owner_decision_interval_for_test(200), "instant-contact case uses the separate 200 ms pursuit window")
	var victim: PlayerCharacter = RuntimeFixture.player(self, Vector2(14.0, 8.0))
	var actor: EnemyActor = _fixture_enemy(Vector2(8.0, 8.0), victim)
	await get_tree().physics_frame
	await get_tree().process_frame
	actor.visual.advance_struck_action(5.0)
	actor._retarget_internal(0.0)
	var initial_due: float = actor._owner_decision_next_time_s
	var hp: int = victim.current_hp
	victim.global_position = RuntimeFixture.to_screen(Vector2(8.99, 8.0))
	await get_tree().physics_frame
	await get_tree().process_frame
	actor._physics_process_internal(0.001)
	_check(actor._combat_action_time_s < initial_due, "attack opportunity happens strictly before pursuit deadline")
	# The immediate attack lane may bypass owner-window admission entirely.
	# Its cached previous tick is valid history, not a grant on this attack tick.
	_check(actor._owner_decision_granted_physics_tick != Engine.get_physics_frames(), "pursuit was not granted on the immediate attack tick")
	_check(actor._hc_starts == 1 and actor._hc_settlements == 1 and victim.current_hp < hp, "not-due pursuit cannot delay actual ready attack or immediate HP settlement")
	_check(actor._pending_attack_time < 0.0 and actor._attack_action_active, "immediate damage keeps the independent logical action busy")
	var serial: int = actor._attack_logic_serial
	var settled_hp: int = victim.current_hp
	victim.global_position = RuntimeFixture.to_screen(Vector2(14.0, 8.0))
	await get_tree().physics_frame
	await get_tree().process_frame
	actor._physics_process_internal(maxf(0.001, initial_due - actor._combat_action_time_s + 0.0001))
	_check(actor._attack_action_active and actor._ordinary_attack_visual_move_override_allowed(), "due pursuit may use the body before the logical attack completes")
	# The direct leg admission isolates the existing source movement cadence
	# from this presentation/body permission contract; it uses real collisions.
	if not actor._movement_step_active:
		_check(actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"pursuit", victim), "busy logical action still admits a legal direct pursuit leg")
	var before: Vector2 = actor.global_position
	var timer: float = actor._attack_timer
	await get_tree().physics_frame
	await get_tree().process_frame
	actor._physics_process_internal(0.01)
	_check(actor.global_position.distance_to(before) > 0.000001, "existing pursuit leg continues on the next not-due physics tick")
	_check(actor._attack_action_active and actor.visual._attack_remaining <= 0.0, "actual ground motion replaces unfinished attack visual without completing its logical parent")
	_check(actor._attack_timer <= timer and actor._attack_logic_serial == serial, "movement does not reset attack cooldown or allocate a new attack")
	_check(not actor._hc_try_start(victim) and actor._hc_starts == 1 and actor._hc_settlements == 1 and victim.current_hp == settled_hp, "busy parent cannot submit or settle a second attack")
	actor.take_damage(1, victim)
	actor.set_physics_process(false)
	_check(actor.visual.pending_struck_count() > 0, "direct struck remains queued behind the still-active logical attack")
	RuntimeFixture.dispose(actor, victim)
	Enemy.configure_attack_visual_policy_for_test(false, false)

func _test_ready_attack_and_committed_release() -> void:
	var victim: PlayerCharacter = RuntimeFixture.player(self, Vector2(8.5, 8.0))
	var actor: EnemyActor = _fixture_enemy(Vector2(8.0, 8.0), victim)
	if actor.visual != null:
		actor.visual.advance_struck_action(5.0)
	actor._hc_owned_movement_call = true
	actor._combat_action_time_s = 0.0
	var starts_before: int = actor._hc_starts
	var settlements_before: int = actor._hc_settlements
	var victim_hp_before: int = victim.current_hp
	await get_tree().physics_frame
	await get_tree().process_frame
	actor.set_combat_position(RuntimeFixture.to_screen(Vector2(8.0, 8.0)), &"owner_window_attack_fixture")
	actor._retarget_internal(0.0)
	_check(actor._owner_decision_next_time_s > 0.0, "attack fixture establishes a real owner deadline before reception")
	actor._physics_process_internal(0.05)
	_check(actor._hc_starts == starts_before + 1, "ready in-range owner starts exactly one attack without waiting for movement deadline")
	print("OWNER_ATTACK_STATE ", JSON.stringify({"starts":actor._hc_starts,"reason":actor._hc_last_reason,"position":RuntimeFixture.to_ground(actor.global_position),"target":RuntimeFixture.to_ground(victim.global_position),"access":actor._hc_access(victim),"struck":actor.visual.is_struck_action_active(),"queued":actor.visual.pending_struck_count(),"timer":actor._attack_timer}))
	var committed: bool = actor._attack_action_active or actor._pending_attack_time >= 0.0
	_check(committed, "attack owns a committed release state before target motion")
	var attack_deadline: float = actor._owner_decision_next_time_s
	actor.take_damage(1, victim)
	actor.set_physics_process(false)
	_check(is_equal_approx(actor._owner_decision_next_time_s, attack_deadline), "direct hit reception does not reset an established owner deadline")
	if actor.visual != null:
		actor.visual.advance_struck_action(5.0)
	victim.global_position = RuntimeFixture.to_screen(Vector2(30.0, 30.0))
	for _step: int in 20:
		actor._physics_process_internal(0.05)
	_check(actor._hc_settlements == settlements_before + 1, "committed release settles exactly once after target leaves range")
	_check(victim.current_hp < victim_hp_before, "committed attack applies damage through the actual settlement path")
	_check(actor._last_hc_release_record.size() > 0, "committed release record remains available after target leaves range")
	_check(is_equal_approx(actor._owner_decision_next_time_s, attack_deadline), "direct hit and committed release do not reset the owner deadline")
	RuntimeFixture.dispose(actor, victim)

func _test_collision_wall_and_late_clock() -> void:
	_check(Enemy.configure_owner_decision_interval_for_test(0), "wall comparison disables only the owner window")
	var blocked_context: Dictionary = RuntimeFixture.polygon_context([[[9, 7], [9.5, 7], [9.5, 9], [9, 9]]], 0.5)
	_check(not blocked_context.is_empty(), "collision-wall context is valid")
	var wall_victim: PlayerCharacter = RuntimeFixture.player(self, Vector2(14.0, 8.0))
	var wall_actor: EnemyActor = _fixture_enemy(Vector2(8.0, 8.0), wall_victim, blocked_context)
	var open_victim: PlayerCharacter = RuntimeFixture.player(self, Vector2(14.0, 8.0))
	var open_actor: EnemyActor = _fixture_enemy(Vector2(8.0, 8.0), open_victim)
	await get_tree().physics_frame
	await get_tree().process_frame
	for actor: EnemyActor in [wall_actor, open_actor]:
		if actor.visual != null:
			actor.visual.advance_struck_action(5.0)
		actor._hc_owned_movement_call = true
		actor._combat_action_time_s = 0.0
		var started: bool = actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"pursuit", actor.target)
		_check(started if actor == open_actor else not started, "formal movement admission accepts open leg and rejects wall-crossing leg")
	var wall_before: Vector2 = RuntimeFixture.to_ground(wall_actor.global_position)
	var open_before: Vector2 = RuntimeFixture.to_ground(open_actor.global_position)
	for _step: int in 20:
		wall_actor._advance_autonomous_step(0.05)
		open_actor._advance_autonomous_step(0.05)
	var wall_position: Vector2 = RuntimeFixture.to_ground(wall_actor.global_position)
	var open_position: Vector2 = RuntimeFixture.to_ground(open_actor.global_position)
	_check(open_position.x > open_before.x, "open comparison actor advances through the same physics delta")
	_check(wall_position.x <= 9.0001 and wall_position.x < open_position.x, "narrow authored collision wall stops the actor before crossing")
	RuntimeFixture.dispose(wall_actor, wall_victim)
	RuntimeFixture.dispose(open_actor, open_victim)
	var victim: PlayerCharacter = RuntimeFixture.player(self, Vector2(14.0, 8.0))
	var actor: EnemyActor = _fixture_enemy(Vector2(8.0, 8.0), victim)
	if actor.visual != null:
		actor.visual.advance_struck_action(5.0)
	actor._combat_action_time_s = 0.0
	_check(Enemy.configure_owner_decision_interval_for_test(200), "late-clock case uses the 200 ms owner window")
	await get_tree().physics_frame
	await get_tree().process_frame
	actor._retarget_internal(0.0)
	actor._combat_action_time_s = 0.75
	await get_tree().physics_frame
	await get_tree().process_frame
	actor._retarget_internal(0.0)
	_check(actor._owner_decision_next_time_s >= 0.949 and actor._owner_decision_next_time_s <= 0.951, "late owner clock consumes one window without catch-up debt")
	RuntimeFixture.dispose(actor, victim)
