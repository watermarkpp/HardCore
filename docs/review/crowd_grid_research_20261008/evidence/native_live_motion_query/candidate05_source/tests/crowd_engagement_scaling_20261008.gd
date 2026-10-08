extends "res://tests/phone_crowd_baseline_20261008.gd"

## DIAGNOSTIC_SCALING only. This fixture changes one input variable: how many
## of the same 34 formal actors start close enough to engage the player. It is
## not a performance acceptance test and must not be used as an optimization
## pass criterion.

const SCALING_MAP_ID := 913203
const SCALING_SEED := 20261008
const SCALING_ACTOR_COUNT := 34
const SCALING_LOOT_COUNT := 48
const SCALING_SAMPLE_TICKS := 300

var _scaling_engaged := 30
var _scaling_tick_samples: Array[Dictionary] = []
var _scaling_previous_positions: Dictionary = {}
var _scaling_distinct_movers: Dictionary = {}
var _scaling_motion_gu_total := 0.0
var _scaling_player_motion_gu := 0.0
var _scaling_player_moving_ticks := 0
var _scaling_previous_player_ground := Vector2.INF
var _scaling_max_targeting := 0
var _scaling_max_moving := 0
var _scaling_sample_start_counters: Dictionary = {}
var _scaling_sample_start_attack := 0
var _scaling_failures: Array[String] = []
var _scaling_sampling := false
var _scaling_tick_begin_usec := 0
var _scaling_player_hp_start := 0
var _scaling_player_hp_loss := 0
var _scaling_layout: Dictionary = {}
var _scaling_enemies: Array = []
var _scaling_input_manifest: Array[Dictionary] = []


func _physics_process(_delta: float) -> void:
	_scaling_tick_begin_usec = Time.get_ticks_usec()
	# The production actors are independent physics nodes. Reuse only the
	# grandfather fixture's three-line CPU boundary; do not call either parent
	# observer, which would measure the same tick twice.
	if not _scaling_sampling or not is_instance_valid(_game):
		return
	if _physics_start.physics_tick == Engine.get_physics_frames():
		_physics_cpu_ms.append(float(Time.get_ticks_usec() - _physics_start.started_usec) / 1000.0)
	var positions: Dictionary = {}
	var motion := 0.0
	var player_ground := _screen_to_ground(_game.player.global_position)
	var player_motion := (
		_scaling_previous_player_ground.distance_to(player_ground)
		if _scaling_previous_player_ground.is_finite() else 0.0
	)
	_scaling_previous_player_ground = player_ground
	_scaling_player_motion_gu += player_motion
	if player_motion > GroundUnitSpace.EPSILON_GU:
		_scaling_player_moving_ticks += 1
	for enemy: EnemyActor in _scaling_enemies:
		if not is_instance_valid(enemy):
			continue
		var key := str(enemy.get_instance_id())
		var current := _screen_to_ground(enemy.global_position)
		positions[key] = current
		if _scaling_previous_positions.has(key):
			var moved: float = current.distance_to(_scaling_previous_positions[key])
			motion += moved
			if moved > GroundUnitSpace.EPSILON_GU:
				_scaling_distinct_movers[key] = true
	_scaling_previous_positions = positions
	_scaling_motion_gu_total += motion
	var hp := int(_game.player.current_hp)
	_scaling_player_hp_loss += maxi(0, _scaling_player_hp_start - hp)
	_scaling_player_hp_start = hp
	var counters := EnemyActor.performance_diagnostics()
	_scaling_tick_samples.append({
		"physics_frame": Engine.get_physics_frames(),
		"observer_usec": Time.get_ticks_usec() - _scaling_tick_begin_usec,
		"physics_cpu_ms": _physics_cpu_ms.back() if not _physics_cpu_ms.is_empty() else 0.0,
		"motion_gu": motion,
		"player_ground": [player_ground.x, player_ground.y],
		"player_motion_gu": player_motion,
		"actual_engaged": _count_scaling_targeting(),
		"targeting": _count_scaling_targeting(),
		"moving": _count_moving(_scaling_enemies),
		"attack_starts_delta": _attack_starts(_scaling_enemies) - _scaling_sample_start_attack,
		"player_hp": hp,
		"enemy_physics_usec_delta": int(counters.get("enemy_physics_usec", 0)) - int(_scaling_sample_start_counters.get("enemy_physics_usec", 0)),
		"enemy_physics_calls_delta": int(counters.get("enemy_physics_calls", 0)) - int(_scaling_sample_start_counters.get("enemy_physics_calls", 0)),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
	})
	_scaling_sample_start_counters = counters.duplicate(true)
	_scaling_sample_start_attack = _attack_starts(_scaling_enemies)
	_scaling_max_targeting = maxi(_scaling_max_targeting, _count_scaling_targeting())
	_scaling_max_moving = maxi(_scaling_max_moving, _count_moving(_scaling_enemies))


func _run() -> void:
	_scaling_engaged = int(OS.get_environment("HARDCORE_SCALING_ENGAGED"))
	if _scaling_engaged not in [0, 10, 20, 30]:
		_scaling_failures.append("unsupported_HARDCORE_SCALING_ENGAGED:%d" % _scaling_engaged)
		_scaling_engaged = 30
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "法师"
	PlayerState.level = 38
	PlayerState.recalculate_stats()
	var potion_receive: Dictionary = PlayerState.add_item("强效太阳水", 20)
	if not bool(potion_receive.get("success", false)):
		_scaling_failures.append("potion_inventory_setup_failed")
	var potion_entity_id := ""
	for record: Dictionary in PlayerState.inventory:
		if str(GameData.get_item_record(record).get("name", "")) == "强效太阳水":
			potion_entity_id = GameData.item_entity_id(record)
			break
	var potion_binding: Dictionary = PlayerState.assign_quick_item_slot(0, potion_entity_id)
	if potion_entity_id.is_empty() or not bool(potion_binding.get("ok", false)):
		_scaling_failures.append("potion_quick_slot_binding_failed")
	seed(SCALING_SEED)
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await _ready_map(910001)
	if not _game._begin_map_transition(Callable(_game, "_travel_to_map_immediate").bind(SCALING_MAP_ID), SCALING_MAP_ID):
		_scaling_failures.append("map_transition_rejected")
	await _ready_map(SCALING_MAP_ID)
	var all_enemies := get_tree().get_nodes_in_group("enemies")
	if all_enemies.size() < SCALING_ACTOR_COUNT:
		_scaling_failures.append("formal_map_enemy_count_below_34:%d" % all_enemies.size())
	var selected: Array = []
	for index in range(mini(SCALING_ACTOR_COUNT, all_enemies.size())):
		selected.append(all_enemies[index])
		(all_enemies[index] as EnemyActor).set_physics_process(false)
	for index in range(SCALING_ACTOR_COUNT, all_enemies.size()):
		(all_enemies[index] as Node).queue_free()
	await get_tree().physics_frame
	if get_tree().get_nodes_in_group("enemies").size() != SCALING_ACTOR_COUNT:
		_scaling_failures.append("actor_trim_failed")
	_scaling_layout = _place_scaling_actors(selected)
	_scaling_enemies = selected
	# Parent fixture helpers are reused for formal loot/census setup. Keep their
	# actor list pointed at this exact 34-actor population; no actor is removed.
	_fixture_enemies = selected
	if not _failures.is_empty():
		for failure: String in _failures:
			_scaling_failures.append("inherited_setup:%s" % failure)
		_failures.clear()
	if not _scaling_failures.is_empty():
		await _abort_scaling_setup()
		return
	_game._set_player_world_position(_scaling_layout.center_screen)
	_game.background.set_focus_position(_scaling_layout.center_screen)
	_game.player.set_physics_process(false)
	_game._world_camera.zoom = Vector2.ONE * 1.06
	for _warmup in range(120):
		await get_tree().physics_frame
	_spawn_synthetic_loot(Vector2(_scaling_layout.center_ground[0], _scaling_layout.center_ground[1]))
	if not _failures.is_empty():
		for failure: String in _failures:
			_scaling_failures.append("inherited_setup:%s" % failure)
		_failures.clear()
	if not _scaling_failures.is_empty():
		await _abort_scaling_setup()
		return
	await get_tree().physics_frame
	if _active_loot_count() != SCALING_LOOT_COUNT:
		_scaling_failures.append("initial_active_loot_count:%d" % _active_loot_count())
	for enemy in _scaling_enemies:
		_scaling_previous_positions[str(enemy.get_instance_id())] = _screen_to_ground(enemy.global_position)
	_scaling_player_hp_start = int(_game.player.current_hp)
	_scaling_previous_player_ground = _screen_to_ground(_game.player.global_position)
	RuntimeDiagnostics.set_device_lab_detail_mode("full")
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	EnemyActor.reset_performance_diagnostics()
	_scaling_sample_start_counters = EnemyActor.performance_diagnostics().duplicate(true)
	_scaling_sample_start_attack = _attack_starts(_scaling_enemies)
	_game.player.set_physics_process(true)
	for actor: EnemyActor in _scaling_enemies:
		actor.set_physics_process(true)
	var sample_started_usec := Time.get_ticks_usec()
	var sample_started_physics_frame := Engine.get_physics_frames()
	_scaling_sampling = true
	_sampling = true
	for tick in range(SCALING_SAMPLE_TICKS):
		if tick % 15 == 0 and _game.player.current_hp < _game.player.max_hp * 0.75:
			var hp_before: int = _game.player.current_hp
			var potion_result: Dictionary = PlayerState.use_quick_item_slot(0, potion_entity_id)
			_potion_inputs.append({"tick": tick, "entity_id": potion_entity_id,
				"hp_before": hp_before, "hp_after": _game.player.current_hp, "result": potion_result})
			if not bool(potion_result.get("ok", false)):
				_scaling_failures.append("formal_potion_input_rejected:%d" % tick)
		if tick % 30 == 0:
			var phase := int(tick / 30) % 4
			var heading: Vector2 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][phase]
			_game._on_gameplay_movement(heading)
			_scaling_input_manifest.append({"tick": tick, "input": str(heading), "route": "real_gameplay_movement"})
		await get_tree().physics_frame
	_game._on_gameplay_movement(Vector2.ZERO)
	_scaling_sampling = false
	_sampling = false
	var sample_elapsed_usec := Time.get_ticks_usec() - sample_started_usec
	var enemies := get_tree().get_nodes_in_group("enemies")
	var counters := EnemyActor.performance_diagnostics()
	var final_census := _monster_census(enemies)
	var actual_target_max := _scaling_max_targeting
	if actual_target_max != _scaling_engaged:
		_scaling_failures.append("actual_max_targeting_%d_expected_%d" % [actual_target_max, _scaling_engaged])
	if Engine.get_physics_frames() - sample_started_physics_frame != SCALING_SAMPLE_TICKS:
		_scaling_failures.append("actual_physics_ticks:%d" % (Engine.get_physics_frames() - sample_started_physics_frame))
	if _scaling_player_moving_ticks == 0 or _scaling_player_motion_gu <= GroundUnitSpace.EPSILON_GU:
		_scaling_failures.append("player_movement_input_produced_no_actual_motion")
	if enemies.size() != SCALING_ACTOR_COUNT or int(final_census.counts.alive) != SCALING_ACTOR_COUNT:
		_scaling_failures.append("34_actor_survival_failed")
	if not is_instance_valid(_game.player) or _game.player.current_hp <= 0:
		_scaling_failures.append("player_died_during_sample")
	var queued := _queued_count(get_tree().root)
	if queued != 0:
		_scaling_failures.append("queued_nodes_leaked:%d" % queued)
	var decision_snapshot := _decision_budget_snapshot()
	if int(decision_snapshot.get("queue_length", 0)) != 0 or int(decision_snapshot.get("open_scopes", 0)) != 0:
		_scaling_failures.append("decision_budget_not_drained")
	var result := {
		"status": "FAIL" if not _scaling_failures.is_empty() else "PASS",
		"fixture": "DIAGNOSTIC_SCALING_crowd_engagement_scaling_20261008",
		"diagnostic_only": true,
		"map_id": SCALING_MAP_ID, "seed": SCALING_SEED,
		"engaged_requested": _scaling_engaged,
		"sample_physics_ticks": SCALING_SAMPLE_TICKS,
		"actual_physics_ticks": Engine.get_physics_frames() - sample_started_physics_frame,
		"sample_elapsed_usec": sample_elapsed_usec,
		"actor_counts": {"formal_selected": selected.size(), "active_after_trim": enemies.size(), "alive_after_sample": final_census.counts.alive},
		"targeting": {"requested": _scaling_engaged, "max_actual": actual_target_max, "ending": _count_scaling_targeting()},
		"moving": {"max_actual": _scaling_max_moving, "distinct_movers": _scaling_distinct_movers.size(), "ending": _count_moving(enemies)},
		"attacks": {"total_starts": _attack_starts(enemies), "player_hp_loss": _scaling_player_hp_loss, "player_hp_end": _game.player.current_hp},
		"player_motion": {"total_gu": _scaling_player_motion_gu, "moving_ticks": _scaling_player_moving_ticks},
		"loot": {"requested_count": SCALING_LOOT_COUNT, "ending_active_count": _active_loot_count()},
		"layout": _scaling_layout,
		"inputs": _scaling_input_manifest,
		"potion_inputs": _potion_inputs,
		"physics_cpu_ms": _stats(_physics_cpu_ms),
		"process_cpu_ms": _stats(_process_ms),
		"frame_interval_ms": _stats(_intervals),
		"counters": counters,
		"decision_budget": decision_snapshot,
		"monster_census_after": final_census,
		"tick_samples": _scaling_tick_samples,
		"source_hashes": _scaling_source_hashes(),
		"failures": _scaling_failures,
	}
	_append_scaling_result(result)
	await _scaling_cleanup_and_quit(result)


func _place_scaling_actors(enemies: Array) -> Dictionary:
	# Reuse the baseline's deterministic near layout for serials 0..29, then
	# place all non-engaged actors on additional legal far cells.
	var base := super._place_actors(enemies)
	var probe: EnemyActor = enemies[0]
	var center := Vector2(base.center_ground[0], base.center_ground[1])
	var far: Array[Vector2] = []
	for y in range(2, 64, 2):
		for x in range(2, 34, 2):
			var point := Vector2(x, y)
			if point.distance_to(center) < 26.0 or not probe._hc_point_walkable(point):
				continue
			far.append(point)
	if far.size() < SCALING_ACTOR_COUNT - _scaling_engaged:
		_scaling_failures.append("insufficient_legal_far_sites:%d" % far.size())
		return {"center_ground": [center.x, center.y], "center_screen": _ground_to_screen(center), "actors": [], "layout_sha256": ""}
	var rows: Array[Dictionary] = []
	for serial in range(enemies.size()):
		var ground: Vector2
		if serial < _scaling_engaged:
			ground = Vector2(base.actors[serial].ground[0], base.actors[serial].ground[1])
		else:
			ground = far[serial - _scaling_engaged]
		var enemy: EnemyActor = enemies[serial]
		enemy.set_combat_position(_ground_to_screen(ground), &"diagnostic_scaling_spawn")
		enemy.set_meta("spawn_position", _ground_to_screen(ground))
		enemy._rng.seed = SCALING_SEED + serial
		rows.append({"serial": serial, "monster_id": enemy.monster_id, "ground": [ground.x, ground.y], "engaged": serial < _scaling_engaged})
	return {"center_ground": [center.x, center.y], "center_screen": _ground_to_screen(center), "actors": rows, "layout_sha256": JSON.stringify(rows).sha256_text()}


func _count_scaling_targeting() -> int:
	var value := 0
	for enemy: EnemyActor in _scaling_enemies:
		if is_instance_valid(enemy) and enemy.target == _game.player:
			value += 1
	return value


func _scaling_source_hashes() -> Dictionary:
	var result := _profile_source_hashes()
	result["res://tests/crowd_engagement_scaling_20261008.gd"] = FileAccess.get_sha256("res://tests/crowd_engagement_scaling_20261008.gd")
	result["res://tests/phone_crowd_baseline_20261008.gd"] = FileAccess.get_sha256("res://tests/phone_crowd_baseline_20261008.gd")
	return result


func _append_scaling_result(result: Dictionary) -> void:
	var path := "res://outputs/crowd_followup_20261008/scaling_raw.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/crowd_followup_20261008"))
	var all: Dictionary = {}
	if FileAccess.file_exists(path):
		var old := FileAccess.open(path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(old.get_as_text()) if old != null else null
		if parsed is Dictionary:
			all = parsed
	if not all.has("runs") or not all.runs is Dictionary:
		all["runs"] = {}
	all["fixture"] = "DIAGNOSTIC_SCALING"
	all["runs"][str(_scaling_engaged)] = result
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all, "\t"))
		file.close()
	else:
		_scaling_failures.append("scaling_json_open_failed")


func _decision_budget_snapshot() -> Dictionary:
	var path := "res://scripts/monster_ai_package/decision_budget.gd"
	if not FileAccess.file_exists(path):
		return {"available": false}
	var decision_script: Script = load(path)
	return decision_script.snapshot() if decision_script != null else {"available": false}


func _abort_scaling_setup() -> void:
	var result := {
		"status": "FAIL",
		"fixture": "DIAGNOSTIC_SCALING_crowd_engagement_scaling_20261008",
		"diagnostic_only": true,
		"map_id": SCALING_MAP_ID, "seed": SCALING_SEED,
		"engaged_requested": _scaling_engaged,
		"setup_aborted": true,
		"failures": _scaling_failures,
		"source_hashes": _scaling_source_hashes(),
	}
	_append_scaling_result(result)
	await _scaling_cleanup_and_quit(result)


func _scaling_cleanup_and_quit(_result: Dictionary) -> void:
	_game.queue_free()
	await get_tree().process_frame
	print("DIAGNOSTIC_SCALING_ENGAGED_%d_%s" % [_scaling_engaged, "PASS" if _scaling_failures.is_empty() else "FAIL"])
	get_tree().quit(0 if _scaling_failures.is_empty() else 1)
