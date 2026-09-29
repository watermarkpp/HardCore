extends Node2D

## R2 shared-permission runtime contract (docs/02 R02 scenarios A/C/D/B).
## Fixture pattern mirrors tests/hc_monster_ai/runtime_test.gd: real
## EnemyActor on a projected map with a spatial index; the deterministic
## owner game clock stamps every cadence phase (R03 domain).

const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")

const EXPECTED_CHECKS := 11
const EXPECTED_CASES := 4
var _checks := 0
var _completed_cases := 0
var _failures: Array[String] = []
var _serial := 0
var _index
var _ran := false


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error("R2_SHARED_PERMISSION: " + label)


func _run() -> void:
	if _ran:
		return
	_ran = true
	_checks = 0
	_completed_cases = 0
	_failures.clear()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(true)
	_index = Index.new()
	await _scenario_c_cooldown_hold_vs_blocked_pursue()
	_completed_cases += 1
	await _scenario_a_grant_picks_side_step()
	_completed_cases += 1
	await _scenario_d_one_charge_per_tick()
	_completed_cases += 1
	await _scenario_b_wall_path_commit()
	_completed_cases += 1
	var complete := _checks == EXPECTED_CHECKS and _completed_cases == EXPECTED_CASES
	if not complete or not _failures.is_empty():
		print("R2_SHARED_PERMISSION_FAIL checks=%d/%d cases=%d/%d failures=%s" % [
			_checks, EXPECTED_CHECKS, _completed_cases, EXPECTED_CASES, str(_failures)])
		get_tree().quit(1)
		return
	print("R2_SHARED_PERMISSION_PASS checks=%d cases=%d failures=0" % [_checks, _completed_cases])
	get_tree().quit(0)


func screen_to_ground(p: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(p)


func _context(blocked: Dictionary) -> Dictionary:
	return {"valid": true, "contract_id": Terrain.CONTRACT_ID, "runtime_map_id": 1,
		"build_sha256": "b".repeat(64),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": Vector2i(80, 80), "blocked_cells": blocked}


func _make_player(gu: Vector2) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.set_physics_process(false)
	player.set_meta("runtime_map_id", 1)
	player.set_meta("zone_generation", 1)
	add_child(player)
	await get_tree().physics_frame
	player.max_hp = 500
	player.current_hp = 500
	player.global_position = GU.ground_delta_gu_to_screen_delta_px(gu)
	return player


func _make_enemy(gu: Vector2, player: PlayerCharacter, blocked: Dictionary = {}) -> EnemyActor:
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(64), player, false)
	actor.global_position = GU.ground_delta_gu_to_screen_delta_px(gu)
	actor.set_meta("spawn_position", actor.global_position)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(1,
		Callable(self, "_ground_to_screen"), Callable(self, "screen_to_ground"))
	actor.configure_terrain_navigation_context(_context(blocked))
	add_child(actor)
	await get_tree().physics_frame
	actor.set_physics_process(false)
	actor.target = player
	actor._retarget_timer = 999.0
	actor._attack_timer = 999.0
	_serial += 1
	actor.spatial_actor_runtime_id = _serial
	actor.combat_spatial_index = _index
	_index.register(_serial, 1, gu, actor.combat_radius_gu, _serial, actor)
	actor.set_combat_position(GU.ground_delta_gu_to_screen_delta_px(gu), &"r2_test_setup")
	return actor


func _ground_to_screen(gu: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(gu)


func _dispose(actor: EnemyActor) -> void:
	if actor.spatial_actor_runtime_id > 0:
		_index.unregister(actor.spatial_actor_runtime_id)
	actor.queue_free()


func _ready_phase(enemy: EnemyActor) -> void:
	var cadence = enemy._movement_cadence
	enemy._combat_action_time_s = (float(int(cadence.walk_interval_ms)) + 1.0) / 1000.0
	var now_ms := int(enemy._combat_action_time_s * 1000.0)
	cadence.walk_wait_locked = false
	cadence.walk_tick_ms = now_ms - int(cadence.walk_interval_ms) - 1
	cadence.walk_wait_tick_ms = 0
	cadence.last_evaluated_ms = now_ms - 1


func _scenario_c_cooldown_hold_vs_blocked_pursue() -> void:
	# C: a CLEAR in-zone cooldown holds; the same cooldown blocked by a
	# frontline body must NOT hold (R02 semantics).
	var player := await _make_player(Vector2(20, 20))
	var holder := await _make_enemy(Vector2(20.8, 20), player)
	holder._attack_timer = 999.0
	_ready_phase(holder)
	holder._physics_process(1.0 / 60.0)
	_check(holder._hc_last_reason == &"COOLDOWN_HOLD",
		"a CLEAR in-zone cooldown holds position (got %s)" % str(holder._hc_last_reason))
	_check(screen_to_ground(holder.global_position).distance_to(Vector2(20, 20)) < 0.81,
		"the holder stayed at the legal contact position")
	_dispose(holder)
	var walker := await _make_enemy(Vector2(20.8, 20), player)
	walker._attack_timer = 999.0
	var blocker := await _make_enemy(Vector2(20.45, 20.02), player)
	blocker._attack_timer = 999.0
	_ready_phase(walker)
	walker._physics_process(1.0 / 60.0)
	_check(walker._hc_last_reason != &"COOLDOWN_HOLD",
		"a blocked in-zone cooldown does not hold (got %s)" % str(walker._hc_last_reason))
	_dispose(blocker)
	_dispose(walker)
	player.free()


func _scenario_a_grant_picks_side_step() -> void:
	# A: a ready in-zone actor blocked on the direct axis spends exactly one
	# grant and selects a legal side step.
	var player := await _make_player(Vector2(20, 20))
	var enemy := await _make_enemy(Vector2(22.4, 20), player)
	enemy._attack_timer = 0.0
	var blocker := await _make_enemy(Vector2(21.2, 20.02), player)
	blocker._attack_timer = 999.0
	_ready_phase(enemy)
	var walk_count_before := int(enemy._movement_cadence.walk_count)
	enemy._physics_process(1.0 / 60.0)
	_check(int(enemy._movement_cadence.walk_count) == walk_count_before + 1,
		"the blocked in-zone tick consumed exactly one grant")
	_check(screen_to_ground(enemy.global_position).distance_to(Vector2(22.4, 20)) > 0.001,
		"the granted tick selected a legal side step")
	_dispose(blocker)
	_dispose(enemy)
	player.free()


func _scenario_d_one_charge_per_tick() -> void:
	# D: one cadence charge per physics tick; repeats never re-evaluate.
	var player := await _make_player(Vector2(20, 20))
	var enemy := await _make_enemy(Vector2(23.5, 20), player)
	_ready_phase(enemy)
	var walk_count_before := int(enemy._movement_cadence.walk_count)
	var started := enemy._request_autonomous_step(Vector2.RIGHT, 1.0, true, &"pursuit", -1, player)
	_check(started, "the first pursuit request of a fresh tick grants and starts")
	_check(int(enemy._movement_cadence.walk_count) == walk_count_before + 1,
		"the pursuit grant consumed the cadence once")
	var repeat := enemy._request_autonomous_step(Vector2.RIGHT, 1.0, true, &"pursuit", -1, player)
	_check(not repeat and int(enemy._movement_cadence.walk_count) == walk_count_before + 1,
		"a same-tick repeat is refused without a second charge")
	await get_tree().physics_frame
	var after_step := enemy._request_autonomous_step(Vector2.RIGHT, 1.0, true, &"pursuit", -1, player)
	_check(not after_step and int(enemy._movement_cadence.walk_count) == walk_count_before + 1,
		"the next tick with unelapsed phase waits without charging")
	_dispose(enemy)
	player.free()


func _scenario_b_wall_path_commit() -> void:
	# B: a wall-separated actor walks around the wall under its grant and
	# never enters a blocked navigation cell.
	var player := await _make_player(Vector2(20, 20))
	var wall := {Vector2i(22, 20): true, Vector2i(22, 21): true, Vector2i(22, 19): true}
	var enemy := await _make_enemy(Vector2(24.5, 20), player, wall)
	_ready_phase(enemy)
	enemy._physics_process(1.0 / 60.0)
	_check(screen_to_ground(enemy.global_position).distance_to(Vector2(24.5, 20)) > 0.001,
		"the wall-separated actor walked under its grant")
	_check(screen_to_ground(enemy.global_position).floor() != Vector2(22, 20),
		"the wall path never entered the blocked cell")
	_dispose(enemy)
	player.free()
