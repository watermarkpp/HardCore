extends Node2D
## Native-frame acceptance; immutable runner evidence records actual tested bytes.
## One scenario per scene/process. It uses real actor callbacks, not a manual loop.
## Scope: controlled open-field foreground approach, NOT released-map/crowd/aggro acceptance.
const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const Oracle := preload("res://tests/source176_r3/helpers/case_oracle.gd")
@export var case_path: String = "res://tests/source176_r3/cases/natural_64_p0_d0.json"
@export var mutation: String = ""
class DenyAttack:
	extends EnemyActor
	func _hc_try_start(_victim: Node2D) -> bool:
		return false
class DoubleClock:
	extends EnemyActor
	func _advance_combat_action_clock(delta: float) -> void:
		super._advance_combat_action_clock(delta*2.0)
class FrozenClock:
	extends EnemyActor
	func _advance_combat_action_clock(_delta: float) -> void:
		pass
func _new_actor() -> EnemyActor:
	match mutation:
		"DENY_ATTACK": return DenyAttack.new()
		"DOUBLE_CLOCK": return DoubleClock.new()
		"FREEZE_OWNER_GAME_TICK": return FrozenClock.new()
	return EnemyActor.new()
const CAPACITY := 4096
var _enemy: EnemyActor
var _player: PlayerCharacter
var _index
var _case: Dictionary = {}
var _rows: Array[Dictionary] = []
var _errors: Array[String] = []
var _running := false
var _done := false
var _checks := 0
var _game_start := 0.0
var _wall_start := 0
var _initial_hp := 0
var _initial_starts := 0
var _initial_settlements := 0
var _source_radius := 0.0
var _target_radius := 0.0

func _ready() -> void:
	# Lower priorities execute first. Sample after the native actor update.
	process_physics_priority = 10000
	set_physics_process(false)
	_run.call_deferred()

func _check(value: bool, reason: String) -> void:
	_checks += 1
	if not value and _errors.size() < 64:
		_errors.append(reason)

func _ground_to_screen(p: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(p)

func _screen_to_ground(p: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(p)

func _v(raw: Variant) -> Vector2:
	if not raw is Array or raw.size() != 2:
		return Vector2.INF
	return Vector2(float(raw[0]), float(raw[1]))

func _run() -> void:
	var file := FileAccess.open(case_path, FileAccess.READ)
	if file == null:
		_errors.append("case_file_unreadable")
		_finish()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_errors.append("invalid_case_json")
		_finish()
		return
	_case = parsed
	var start := _v(_case.get("start"))
	var target_position := _v(_case.get("target"))
	if not start.is_finite() or not target_position.is_finite():
		_errors.append("invalid_case_positions")
		_finish()
		return
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_index = Index.new()
	_player = PlayerCharacter.new()
	_player.set_meta("runtime_map_id", 1)
	_player.set_meta("zone_generation", 1)
	_player.global_position = _ground_to_screen(target_position)
	add_child(_player)
	_player.set_physics_process(false)
	_player.max_hp = 1000000
	_player.current_hp = 1000000
	_initial_hp = _player.current_hp
	var id := int(_case.get("monster_id", -1))
	var data: Dictionary = GameData.get_monster_by_id(id)
	if data.is_empty():
		_errors.append("canonical_monster_missing:" + str(id))
		_finish()
		return
	_enemy = _new_actor()
	_enemy.setup(data, _player, false)
	_enemy.global_position = _ground_to_screen(start)
	_enemy.set_meta("spawn_position", _enemy.global_position)
	_enemy.set_meta("safe_zones", [])
	_enemy.set_meta("zone_generation", 1)
	_enemy.configure_runtime_map_projection(1,
		Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"))
	_enemy.configure_terrain_navigation_context({
		"valid": true, "contract_id": Terrain.CONTRACT_ID, "runtime_map_id": 1,
		"build_sha256": "b".repeat(64),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": Vector2i(80, 80), "blocked_cells": {},
	})
	add_child(_enemy)
	_enemy.set_physics_process(false)
	# Pin a valid target once to isolate locomotion from acquisition staggering.
	# No runtime clock/cadence/cooldown/position rewrite after collection begins.
	_enemy.target = _player
	# A real public damage event gives the actor threat/wakeup evidence once.
	# This is setup, not a periodic target/cadence rewrite.
	_enemy.take_damage(1, _player)
	_enemy.spatial_actor_runtime_id = 1
	_enemy.combat_spatial_index = _index
	var actual := _screen_to_ground(_enemy.global_position)
	_index.register(1, 1, actual, _enemy.combat_radius_gu, 1, _enemy)
	_source_radius = _enemy.combat_radius_gu
	_target_radius = _enemy._target_combat_radius_gu(_player)
	_check(_enemy.combat_enabled, "combat_admission_rejected")
	_check(_enemy._source176_ordinary_melee(), "case_requires_verified_ordinary_melee")
	_check(not _enemy.stationary, "natural_case_requires_movable_actor")
	_check(actual.distance_to(target_position) > 3.0, "start_not_actually_far")
	if not _errors.is_empty():
		_finish()
		return
	await get_tree().physics_frame
	_game_start = _enemy._combat_action_time_s
	_initial_starts = _enemy._hc_starts
	_initial_settlements = _enemy._hc_settlements
	_wall_start = Time.get_ticks_msec()
	_running = true
	_enemy.set_physics_process(true)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not _running or _done:
		return
	if not is_instance_valid(_enemy) or not is_instance_valid(_player):
		_errors.append("actor_lost")
		_finish()
		return
	var source := _screen_to_ground(_enemy.global_position)
	var target_position := _screen_to_ground(_player.global_position)
	var frame := Engine.get_physics_frames()
	var game_time := _enemy._combat_action_time_s
	_check(source.is_finite() and target_position.is_finite(), "nonfinite_position")
	_check(source.distance_to(target_position) >= _source_radius + _target_radius - 0.001,
		"body_overlap")
	if not _rows.is_empty():
		var last := _rows[_rows.size() - 1]
		_check(frame == int(last.tick) + 1, "not_consecutive_engine_frames")
		_check(absf(game_time - float(last.game_s) - delta) <= maxf(0.000001, delta * 0.01),
			"clock_does_not_advance_once_per_frame")
		if _enemy._hc_starts > int(last.starts):
			_check(Oracle.in_box(target_position - source), "attack_started_outside_source_box")
	if _rows.size() >= CAPACITY:
		_errors.append("trace_overflow")
		_finish()
		return
	_rows.append({
		"tick": frame, "game_s": game_time, "delta_s": delta,
		"position": [source.x, source.y], "target": [target_position.x, target_position.y],
		"starts": _enemy._hc_starts, "settlements": _enemy._hc_settlements,
		"target_hp": _player.current_hp,
		"life": int(_enemy.get_meta("hc_combat_life_epoch", 0)),
		"generation": int(_enemy.get_meta("zone_generation", -1)),
		"reason": _enemy._hc_last_reason,
		"source_serial": _enemy._source176_decision_serial,
	})
	if not _errors.is_empty():
		_finish()
		return
	if (_enemy._hc_starts >= _initial_starts + 2
		and _enemy._hc_settlements >= _initial_settlements + 2
		and _player.current_hp < _initial_hp and _rows.size() >= 3):
		_finish()
	elif game_time - _game_start > float(_case.get("budget_seconds", 20.0)):
		_errors.append("natural_game_time_budget_exhausted")
		_finish()

func _process(_delta: float) -> void:
	# Test watchdog only. It never advances or repairs gameplay time.
	if _running and not _done and Time.get_ticks_msec() - _wall_start > 27000:
		_errors.append("test_wall_watchdog_expired")
		_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	_running = false
	set_physics_process(false)
	if is_instance_valid(_enemy):
		_enemy.set_physics_process(false)
		_check(_enemy._hc_starts >= _initial_starts + 2, "fewer_than_two_natural_starts")
		_check(_enemy._hc_settlements >= _initial_settlements + 2, "fewer_than_two_settlements")
	if is_instance_valid(_player):
		_check(_player.current_hp < _initial_hp, "no_observed_damage")
	_check(_rows.size() >= 3, "too_few_real_frame_samples")
	var case_id := str(_case.get("case_id", "unreadable_case"))
	if not mutation.is_empty():
		case_id += "_mutation_"+mutation
	var payload := {
		"schema": "source176.r3.foreground_trace.v1", "case_id": case_id,
		"reported_tested_sha": OS.get_environment("HARDCORE_R3_TESTED_SHA"),
		"case_path": case_path, "monster_id": int(_case.get("monster_id", -1)),
		"runtime_display_name": _enemy.display_name if is_instance_valid(_enemy) else "",
		"source_radius": _source_radius, "target_radius": _target_radius,
		"shape": "source_box", "half_extent": 1.0, "initial_target_hp": _initial_hp,
		"overflow": _errors.has("trace_overflow"), "checks": _checks,
		"completed_cases": 1, "errors": _errors, "rows": _rows,
	}
	var out_dir := "res://outputs/test_logs/source176_r3"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var out := FileAccess.open(out_dir + "/" + case_id.validate_filename() + ".json", FileAccess.WRITE)
	if out == null:
		_errors.append("cannot_write_trace")
	else:
		out.store_string(JSON.stringify(payload))
		out.close()
	var ok := _errors.is_empty() and _checks > 0
	print(("R3_REAL_FRAME_PASS" if ok else "R3_REAL_FRAME_FAIL") +
		" case=" + case_id + " checks=" + str(_checks) +
		" samples=" + str(_rows.size()) + " errors=" + str(_errors))
	get_tree().quit(0 if ok else 1)
