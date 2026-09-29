extends Node2D

## R2 exact-leg runtime contract (docs/02 R04): the neighbour pursuit leg
## commits the real SourceStepPlan endpoint, never a cell centre. Eight
## approach directions from both integer and fractional in-cell starts must
## produce a first step whose quantised direction stays inside the 8-way
## cone towards the target, and a second step that never reverses against
## the approach (no Z-zag). Fixture pattern mirrors the R2 shared-permission
## test: real EnemyActor, projected map, deterministic owner game clock.

const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")

const EXPECTED_CHECKS := 32
const EXPECTED_CASES := 2
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
		push_error("R2_EXACT_LEG: " + label)


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
	await _scenario_eight_directions(Vector2(5, 5), "integer")
	_completed_cases += 1
	await _scenario_eight_directions(Vector2(5.5, 5.5), "fractional")
	_completed_cases += 1
	var complete := _checks == EXPECTED_CHECKS and _completed_cases == EXPECTED_CASES
	if not complete or not _failures.is_empty():
		print("R2_EXACT_LEG_FAIL checks=%d/%d cases=%d/%d failures=%s" % [
			_checks, EXPECTED_CHECKS, _completed_cases, EXPECTED_CASES, str(_failures)])
		get_tree().quit(1)
		return
	print("R2_EXACT_LEG_PASS checks=%d cases=%d failures=0" % [_checks, _completed_cases])
	get_tree().quit(0)


func screen_to_ground(p: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(p)


func _context() -> Dictionary:
	return {"valid": true, "contract_id": Terrain.CONTRACT_ID, "runtime_map_id": 1,
		"build_sha256": "b".repeat(64),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": Vector2i(80, 80), "blocked_cells": {}}


func _ground_to_screen(gu: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(gu)


func _make_player(gu: Vector2) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.set_physics_process(false)
	player.set_meta("runtime_map_id", 1)
	player.set_meta("zone_generation", 1)
	add_child(player)
	await get_tree().physics_frame
	player.max_hp = 500
	player.current_hp = 500
	player.global_position = _ground_to_screen(gu)
	return player


func _make_enemy(gu: Vector2, player: PlayerCharacter) -> EnemyActor:
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(64), player, false)
	actor.global_position = _ground_to_screen(gu)
	actor.set_meta("spawn_position", actor.global_position)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(1,
		Callable(self, "_ground_to_screen"), Callable(self, "screen_to_ground"))
	actor.configure_terrain_navigation_context(_context())
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
	actor.set_combat_position(_ground_to_screen(gu), &"r2_leg_setup")
	return actor


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


func _scenario_eight_directions(start_gu: Vector2, tag: String) -> void:
	# Eight approach cones. The first granted step must stay inside the 8-way
	# quantisation cone of the approach direction, and the second granted
	# step must never reverse against it (the historical cell-centre
	# overwrite produced exactly such reversals).
	var dirs := [
		Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1),
		Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1),
	]
	for dir in dirs:
		var far: Vector2 = start_gu + dir * 7.0
		var player := await _make_player(far)
		var enemy := await _make_enemy(start_gu, player)
		_ready_phase(enemy)
		enemy._physics_process(1.0 / 60.0)
		var first := screen_to_ground(enemy.global_position) - start_gu
		var approach: Vector2 = dir.normalized()
		# One manual tick advances the live step by speed*delta (~0.011 GU),
		# so the cone check only needs a measurable displacement.
		_check(first.length() > 0.0005 and first.normalized().dot(approach) > 0.7,
			"%s dir %s first step stays in the approach cone (%.2f)" % [
				tag, str(dir), first.normalized().dot(approach)])
		# Second tick: the cadence phase is advanced a full interval, so the
		# pursuit leg grants again; the step must not reverse.
		enemy._combat_action_time_s += (float(int(enemy._movement_cadence.walk_interval_ms)) + 1.0) / 1000.0
		var cadence = enemy._movement_cadence
		var now2 := int(enemy._combat_action_time_s * 1000.0)
		cadence.walk_tick_ms = now2 - int(cadence.walk_interval_ms) - 1
		cadence.last_evaluated_ms = now2 - 1
		var pos_before := screen_to_ground(enemy.global_position)
		enemy._physics_process(1.0 / 60.0)
		var second := screen_to_ground(enemy.global_position) - pos_before
		_check(second.length() < 0.0005 or second.normalized().dot(approach) > 0.7,
			"%s dir %s second step never reverses (dot %.2f)" % [
				tag, str(dir), (second.normalized().dot(approach) if second.length() > 0.001 else 1.0)])
		_dispose(enemy)
		player.free()
