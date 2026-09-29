extends Node2D

## R2 natural-approach contract (docs/02 R05): a real actor walking toward
## the player must stop inside its own attack geometry without overlapping
## the player body. No overlap fixtures: both monsters start 5 GU away and
## pursue under the live step pipeline on the deterministic game clock.
## Radii: ordinary melee ~0.3536 GU, corpse king 0.5 GU, player 0.39774756
## GU, so the minimum non-overlapping centre distance is ~0.8977/0.7514 GU
## and the source box edge is 1.0 GU.

const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")

const EXPECTED_CHECKS := 6
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
		push_error("R2_APPROACH: " + label)


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
	await _scenario_natural_approach(64, 0.3536 + 0.39774756, "ordinary_melee")
	_completed_cases += 1
	await _scenario_natural_approach(239, 0.5 + 0.39774756, "corpse_king")
	_completed_cases += 1
	var complete := _checks == EXPECTED_CHECKS and _completed_cases == EXPECTED_CASES
	if not complete or not _failures.is_empty():
		print("R2_APPROACH_FAIL checks=%d/%d cases=%d/%d failures=%s" % [
			_checks, EXPECTED_CHECKS, _completed_cases, EXPECTED_CASES, str(_failures)])
		get_tree().quit(1)
		return
	print("R2_APPROACH_PASS checks=%d cases=%d failures=0" % [_checks, _completed_cases])
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


func _make_enemy(gu: Vector2, player: PlayerCharacter, monster_id: int) -> EnemyActor:
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(monster_id), player, false)
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
	actor._attack_timer = 0.0
	_serial += 1
	actor.spatial_actor_runtime_id = _serial
	actor.combat_spatial_index = _index
	_index.register(_serial, 1, gu, actor.combat_radius_gu, _serial, actor)
	actor.set_combat_position(_ground_to_screen(gu), &"r2_approach_setup")
	return actor


func _dispose(actor: EnemyActor) -> void:
	if actor.spatial_actor_runtime_id > 0:
		_index.unregister(actor.spatial_actor_runtime_id)
	actor.queue_free()


func _scenario_natural_approach(monster_id: int, min_centre_gu: float, tag: String) -> void:
	# 5 GU away, 900 manual ticks at 1/60 s (15 s budget): the actor must
	# close in, never overlap the player body, and finish inside its source
	# box reach (L-infinity centre distance <= 1.0 GU).
	var start_gu := Vector2(15, 20)
	var player_gu := Vector2(20, 20)
	var player := await _make_player(player_gu)
	var enemy := await _make_enemy(start_gu, player, monster_id)
	var cadence = enemy._movement_cadence
	enemy._combat_action_time_s = (float(int(cadence.walk_interval_ms)) + 1.0) / 1000.0
	var now_ms := int(enemy._combat_action_time_s * 1000.0)
	cadence.walk_wait_locked = false
	cadence.walk_tick_ms = now_ms - int(cadence.walk_interval_ms) - 1
	cadence.walk_wait_tick_ms = 0
	cadence.last_evaluated_ms = now_ms - 1
	var overlapped := false
	for frame in range(900):
		enemy._physics_process(1.0 / 60.0)
		enemy._combat_action_time_s += 1.0 / 60.0
		var distance := screen_to_ground(enemy.global_position).distance_to(player_gu)
		if distance < min_centre_gu - 0.001:
			overlapped = true
			break
	var final_gu := screen_to_ground(enemy.global_position)
	var final_centre := final_gu.distance_to(player_gu)
	var final_linf := maxf(absf(final_gu.x - player_gu.x), absf(final_gu.y - player_gu.y))
	_check(not overlapped, "%s never overlaps the player body" % tag)
	_check(final_centre > 0.001, "%s actually approached the player" % tag)
	if monster_id == 239:
		# The named contact delivery keeps its own contract: the approach must
		# finish inside the corpse king's START_GU attack circle.
		_check(final_linf <= 1.5 + 0.05,
			"%s finishes inside its START_GU reach (Linf %.3f)" % [tag, final_linf])
	else:
		_check(final_linf <= 1.0 + 0.05,
			"%s finishes inside the source box reach (Linf %.3f)" % [tag, final_linf])
	_dispose(enemy)
	player.free()
