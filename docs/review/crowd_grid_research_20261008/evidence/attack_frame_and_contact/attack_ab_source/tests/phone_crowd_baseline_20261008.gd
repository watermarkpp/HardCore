extends "res://tests/world_crowd_firewall_profile_test.gd"

## PC baseline for the 2026-10-08 phone crowd observation.
##
## The phone supplied only aggregate end-of-window counts (34 total, 27
## engaged/moving, 48 ground loot). It did not preserve actor composition,
## exact positions, equipment, input samples, or GPU data. This fixture keeps
## the formal 913203 map and production actors/AI/collision/loot paths live,
## and records a deterministic synthetic layout for later same-fixture CPU
## comparisons. It is a PC CPU baseline, never a phone FPS reproduction.

const Poly := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const MAP_ID := 913203
const SEED := 20261008
const ACTOR_COUNT := 34
const ENGAGED_COUNT := 30
const BACKGROUND_COUNT := 4
const LOOT_COUNT := 48
const SAMPLE_TICKS := 300

var _tick_samples: Array[Dictionary] = []
var _previous_positions: Dictionary = {}
var _motion_gu_total := 0.0
var _player_hp_start := 0
var _player_hp_loss := 0
var _loot_manifest: Array[Dictionary] = []
var _loot_ids: Dictionary = {}
var _loot_initial_active := 0
var _input_manifest: Array[Dictionary] = []
var _failures: Array[String] = []
var _sample_start_counters: Dictionary = {}
var _sample_start_attack: Dictionary = {}
var _max_moving := 0
var _max_targeting := 0
var _fixture_enemies: Array = []
var _distinct_movers: Dictionary = {}
var _tick_begin_usec := 0
var _potion_inputs: Array[Dictionary] = []
var _potion_entity_id := ""
var _previous_player_ground := Vector2.INF
var _player_motion_gu := 0.0
var _player_moving_ticks := 0
var _movement_period_ticks := 30


func _physics_process(delta: float) -> void:
	_tick_begin_usec = Time.get_ticks_usec()
	super(delta)
	if not _sampling or not is_instance_valid(_game):
		return
	var enemies := _fixture_enemies
	var positions: Dictionary = {}
	var motion := 0.0
	var player_ground := _screen_to_ground(_game.player.global_position)
	var player_motion := _previous_player_ground.distance_to(player_ground) if _previous_player_ground.is_finite() else 0.0
	_previous_player_ground = player_ground
	_player_motion_gu += player_motion
	if player_motion > GroundUnitSpace.EPSILON_GU:
		_player_moving_ticks += 1
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var key := str(enemy.get_instance_id())
		var current := _screen_to_ground(enemy.global_position)
		positions[key] = current
		if _previous_positions.has(key):
			var moved: float = current.distance_to(_previous_positions[key])
			motion += moved
			if _fixture_enemies.find(enemy) < ENGAGED_COUNT and moved > GroundUnitSpace.EPSILON_GU:
				_distinct_movers[key] = true
	_previous_positions = positions
	_motion_gu_total += motion
	var hp := int(_game.player.current_hp)
	_player_hp_loss += maxi(0, _player_hp_start - hp)
	_player_hp_start = hp
	var counters := EnemyActor.performance_diagnostics()
	var observer_usec := Time.get_ticks_usec() - _tick_begin_usec
	_tick_samples.append({
		"physics_frame": Engine.get_physics_frames(),
		"tick_begin_usec": _tick_begin_usec, "tick_end_usec": Time.get_ticks_usec(),
		"observer_usec": observer_usec,
		"physics_cpu_ms": _physics_cpu_ms.back() if not _physics_cpu_ms.is_empty() else 0.0,
		"motion_gu": motion,
		"player_ground": [player_ground.x, player_ground.y],
		"player_motion_gu": player_motion,
		"enemy_physics_usec_delta": int(counters.get("enemy_physics_usec", 0)) - int(_sample_start_counters.get("enemy_physics_usec", 0)),
		"enemy_physics_calls_delta": int(counters.get("enemy_physics_calls", 0)) - int(_sample_start_counters.get("enemy_physics_calls", 0)),
		"path_pending": _count_pending(enemies),
		"moving": _count_moving(enemies),
		"attack_starts_delta": _attack_starts(enemies) - int(_sample_start_attack.get("total", 0)),
		"player_hp": hp,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
	})
	_sample_start_counters = counters.duplicate(true)
	_sample_start_attack = {"total": _attack_starts(enemies)}
	_max_moving = maxi(_max_moving, _count_moving(enemies))
	_max_targeting = maxi(_max_targeting, _count_targeting(enemies))


func _run() -> void:
	var period := OS.get_environment("HARDCORE_CROWD_MOVEMENT_PERIOD_TICKS")
	if not period.is_empty():
		_movement_period_ticks = int(period)
		if _movement_period_ticks not in [6, 30]:
			_failures.append("unsupported_movement_period:%s" % period)
			_movement_period_ticks = 30
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "法师"
	PlayerState.level = 38
	PlayerState.recalculate_stats()
	var potion_receive: Dictionary = PlayerState.add_item("强效太阳水", 20)
	if not bool(potion_receive.get("success", false)):
		_failures.append("potion_inventory_setup_failed")
	for record: Dictionary in PlayerState.inventory:
		if str(GameData.get_item_record(record).get("name", "")) == "强效太阳水":
			_potion_entity_id = GameData.item_entity_id(record)
			break
	var potion_binding: Dictionary = PlayerState.assign_quick_item_slot(0, _potion_entity_id)
	if _potion_entity_id.is_empty() or not bool(potion_binding.get("ok", false)):
		_failures.append("potion_quick_slot_binding_failed")
	seed(SEED)
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await _ready_map(910001)
	if not _game._begin_map_transition(Callable(_game, "_travel_to_map_immediate").bind(MAP_ID), MAP_ID):
		_failures.append("map_transition_rejected")
	await _ready_map(MAP_ID)
	var all_enemies := get_tree().get_nodes_in_group("enemies")
	if all_enemies.size() < ACTOR_COUNT:
		_failures.append("formal_map_enemy_count_below_34:%d" % all_enemies.size())
	var selected: Array = []
	for index in range(mini(ACTOR_COUNT, all_enemies.size())):
		selected.append(all_enemies[index])
		(all_enemies[index] as EnemyActor).set_physics_process(false)
	for index in range(ACTOR_COUNT, all_enemies.size()):
		(all_enemies[index] as Node).queue_free()
	await get_tree().physics_frame
	if get_tree().get_nodes_in_group("enemies").size() != ACTOR_COUNT:
		_failures.append("actor_trim_failed")
	var layout := _place_actors(selected)
	_fixture_enemies = selected
	_game._set_player_world_position(layout.center_screen)
	_game.background.set_focus_position(layout.center_screen)
	_game.player.set_physics_process(false)
	_game._world_camera.zoom = Vector2.ONE * 1.06
	# Freeze setup only while the new focus admits its visual resources. This
	# preparatory interval is excluded; every measured actor runs normal physics.
	for warmup in range(120):
		await get_tree().physics_frame
	_spawn_synthetic_loot(Vector2(layout.center_ground[0], layout.center_ground[1]))
	await get_tree().physics_frame
	_loot_initial_active = _active_loot_count()
	if _loot_initial_active != LOOT_COUNT:
		_failures.append("initial_active_loot_count:%d" % _loot_initial_active)
	if _loot_manifest.size() != LOOT_COUNT:
		_failures.append("loot_spawn_count:%d" % _loot_manifest.size())
	for enemy in get_tree().get_nodes_in_group("enemies"):
		_previous_positions[str(enemy.get_instance_id())] = _screen_to_ground(enemy.global_position)
	_player_hp_start = int(_game.player.current_hp)
	_previous_player_ground = _screen_to_ground(_game.player.global_position)
	RuntimeDiagnostics.set_device_lab_detail_mode("full")
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	EnemyActor.reset_performance_diagnostics()
	_sample_start_counters = EnemyActor.performance_diagnostics().duplicate(true)
	_sample_start_attack = {"total": _attack_starts(_fixture_enemies)}
	_game.player.set_physics_process(true)
	for actor: EnemyActor in _fixture_enemies:
		actor.set_physics_process(true)
	var sample_started_usec := Time.get_ticks_usec()
	var sample_started_physics_frame := Engine.get_physics_frames()
	_sampling = true
	for tick in range(SAMPLE_TICKS):
		# A reproducible real item input keeps the unequipped stand-in alive;
		# this never changes maximum HP, monster damage or admission clocks.
		if tick % 15 == 0 and _game.player.current_hp < _game.player.max_hp * 0.75:
			var hp_before: int = _game.player.current_hp
			var potion_result: Dictionary = PlayerState.use_quick_item_slot(0, _potion_entity_id)
			_potion_inputs.append({"tick": tick, "entity_id": _potion_entity_id,
				"hp_before": hp_before, "hp_after": _game.player.current_hp, "result": potion_result})
			if not bool(potion_result.get("ok", false)):
				_failures.append("formal_potion_input_rejected:%d" % tick)
		if tick % _movement_period_ticks == 0:
			var phase := int(tick / _movement_period_ticks) % 4
			var heading: Vector2 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][phase]
			_game._on_gameplay_movement(heading)
			_input_manifest.append({"tick": tick, "input": str(heading), "route": "real_gameplay_movement"})
		await get_tree().physics_frame
	_game._on_gameplay_movement(Vector2.ZERO)
	_sampling = false
	var sample_elapsed_usec := Time.get_ticks_usec() - sample_started_usec
	var enemies := get_tree().get_nodes_in_group("enemies")
	var final_census := _monster_census(enemies)
	var counters := EnemyActor.performance_diagnostics()
	if _distinct_movers.size() < ENGAGED_COUNT:
		_failures.append("insufficient_distinct_real_pursuit_movers:%d" % _distinct_movers.size())
	if _max_targeting < ENGAGED_COUNT:
		_failures.append("insufficient_real_target_acquisition:%d" % _max_targeting)
	if _player_moving_ticks == 0 or _player_motion_gu <= GroundUnitSpace.EPSILON_GU:
		_failures.append("player_movement_input_produced_no_actual_motion")
	if enemies.size() != ACTOR_COUNT:
		_failures.append("active_enemy_count:%d" % enemies.size())
	if not is_instance_valid(_game.player) or _game.player.current_hp <= 0:
		_failures.append("player_died_during_sample")
	var expected_renderer := OS.get_environment("HARDCORE_EXPECT_RENDERER")
	var decision_snapshot: Dictionary = {}
	if FileAccess.file_exists("res://scripts/monster_ai_package/decision_budget.gd"):
		var decision_script: Script = load("res://scripts/monster_ai_package/decision_budget.gd")
		decision_snapshot = decision_script.snapshot()
	var result := {
		"decision_budget": decision_snapshot,
		"status": "FAIL" if not _failures.is_empty() else "PASS",
		"fixture": "phone_crowd_baseline_20261008",
		"map_id": MAP_ID, "seed": SEED, "sample_physics_ticks": SAMPLE_TICKS,
		"actual_physics_ticks": Engine.get_physics_frames() - sample_started_physics_frame,
		"sample_elapsed_usec": sample_elapsed_usec, "setup_visual_warmup_physics_ticks": 120,
		"camera_zoom": [_game._world_camera.zoom.x, _game._world_camera.zoom.y],
		"diagnostic_mode": "full",
		"phone_observation": {"total": 34, "engaged": 27, "moving": 27, "ground_loot": 48,
			"duration_ms": 4876, "frames": 55, "enemyphysics_ms": 804,
			"note": "aggregate only; actor composition, positions, equipment, input and GPU were not retained"},
		"layout": layout,
		"actor_counts": {"formal_selected": selected.size(), "active_after_trim": enemies.size(),
			"engaged_target": ENGAGED_COUNT, "background_target": BACKGROUND_COUNT},
		"actual_work": {"distinct_movers": _distinct_movers.size(), "max_targeting": _max_targeting,
			"max_moving": _max_moving, "ending_alive": final_census.counts.alive},
		"loot": {"requested_count": LOOT_COUNT, "initial_active_count": _loot_initial_active,
			"ending_active_count": _active_loot_count(), "spawned_count": _loot_manifest.size(),
			"manifest": _loot_manifest, "layout_kind": "synthetic_gold_and_formal_item_name"},
		"inputs": _input_manifest,
		"potion_inputs": _potion_inputs,
		"potion_input_policy": "20 formal strong sun potions bound in setup; check every 15 physics ticks and use through production quick-item API below 75% HP; no direct HP write",
		"counters": counters, "monster_census_after": final_census,
		"attack_starts": _attack_starts(enemies), "player_hp_loss": _player_hp_loss,
		"motion_gu_total": _motion_gu_total, "physics_cpu_samples_ms": _physics_cpu_ms,
		"player_motion_gu_total": _player_motion_gu, "player_moving_physics_ticks": _player_moving_ticks,
		"movement_period_ticks": _movement_period_ticks,
		"physics_cpu_ms": _stats(_physics_cpu_ms), "frame_interval_ms": _stats(_intervals),
		"process_monitor_ms": _stats(_process_ms), "tick_samples": _tick_samples,
		"nodes": {"object_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"node_count": get_tree().get_node_count(), "queued_for_deletion": _queued_count(get_tree().root)},
		"renderer": {"display_server": DisplayServer.get_name(), "expected": expected_renderer,
			"headless_gpu": "MISSING"},
		"engine_version": Engine.get_version_info(),
		"equipment": "MISSING: phone equipment snapshot was not retained",
		"formal_player_stats": PlayerState.computed_stats,
		"formal_player_stats_sha256": JSON.stringify(PlayerState.computed_stats).sha256_text(),
		"layout_sha256": str(layout.get("layout_sha256", "")),
		"loot_manifest_sha256": JSON.stringify(_loot_manifest).sha256_text(),
		"input_layout_sha256": JSON.stringify(_input_manifest).sha256_text(),
		"source_hashes": _profile_source_hashes(), "failures": _failures,
	}
	var actor_states: Array[Dictionary] = []
	for actor: EnemyActor in enemies:
		actor_states.append({"id": actor.monster_id, "owner": actor.get_instance_id(), "moved": _distinct_movers.has(str(actor.get_instance_id())),
			"policy": actor.hc_package_policy_snapshot(), "pursuit": actor._hc_pursuit_session,
			"source_serial": actor._source176_decision_serial, "active_step": actor._movement_step_active,
			"known_target": actor._hc_known_target_id, "position": str(actor.spatial_index_position())})
	result["actor_states"] = actor_states
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/phone_crowd_local_20261008"))
	var file := FileAccess.open("res://outputs/phone_crowd_local_20261008/baseline.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	else:
		_failures.append("baseline_json_open_failed")
	if _failures.is_empty():
		print("PHONE_CROWD_LOCAL_BASELINE_PASS")
	else:
		print("PHONE_CROWD_LOCAL_BASELINE_FAIL")
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


func _place_actors(enemies: Array) -> Dictionary:
	var probe: EnemyActor = enemies[0]
	var context: Dictionary = _game._monster_terrain_navigation_context
	var center := Vector2.INF
	var near: Array[Vector2] = []
	for y in range(6, 58, 3):
		for x in range(5, 28, 3):
			var candidate := Vector2(x, y)
			if not probe._hc_point_walkable(candidate): continue
			var options: Array[Vector2] = []
			for oy in range(-5, 6):
				for ox in range(-5, 6):
					var point := candidate + Vector2(ox, oy) * 0.85
					if point.distance_to(candidate) < 1.8 or point.distance_to(candidate) > 4.5: continue
					if probe._hc_point_walkable(point) and Poly.segment_walkable(context, candidate, point, probe.combat_radius_gu): options.append(point)
			if options.size() >= ENGAGED_COUNT:
				center = candidate
				near = options
				break
		if center.is_finite(): break
	if not center.is_finite():
		_failures.append("no_legal_27_actor_site")
		return {"center_ground": [0.0, 0.0], "center_screen": probe.global_position,
			"actors": [], "layout_sha256": ""}
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if a.distance_squared_to(center) == b.distance_squared_to(center):
			return a.x < b.x if a.x != b.x else a.y < b.y
		return a.distance_squared_to(center) < b.distance_squared_to(center))
	var far: Array[Vector2] = []
	for y in range(3, 62, 2):
		for x in range(3, 30, 2):
			var point := Vector2(x, y)
			if point.distance_to(center) > 22.0 and probe._hc_point_walkable(point): far.append(point)
	if far.size() < BACKGROUND_COUNT:
		_failures.append("insufficient_legal_background_sites:%d" % far.size())
	var rows: Array[Dictionary] = []
	for serial in range(enemies.size()):
		if serial >= ENGAGED_COUNT and far.size() < BACKGROUND_COUNT:
			continue
		var ground := near[serial] if serial < ENGAGED_COUNT else far[serial - ENGAGED_COUNT]
		var screen := _ground_to_screen(ground)
		var enemy: EnemyActor = enemies[serial]
		enemy.set_combat_position(screen, &"phone_crowd_baseline")
		enemy.set_meta("spawn_position", screen)
		enemy._rng.seed = SEED + serial
		rows.append({"serial": serial, "monster_id": enemy.monster_id, "ground": [ground.x, ground.y], "engaged": serial < ENGAGED_COUNT})
	return {"center_ground": [center.x, center.y], "center_screen": _ground_to_screen(center), "actors": rows,
		"layout_sha256": JSON.stringify(rows).sha256_text()}


func _spawn_synthetic_loot(center: Vector2) -> void:
	var sites: Array[Vector2] = []
	var probe: EnemyActor = _fixture_enemies[0]
	for y in range(-10, 11):
		for x in range(-10, 11):
			var ground := center + Vector2(x, y)
			var distance := ground.distance_to(center)
			if distance >= 6.0 and distance <= 10.0 and probe._hc_point_walkable(ground):
				sites.append(ground)
	if sites.size() < LOOT_COUNT:
		_failures.append("insufficient_legal_loot_sites:%d" % sites.size())
	for serial in range(LOOT_COUNT):
		if serial >= sites.size(): break
		var ground := sites[serial]
		var position := _ground_to_screen(ground)
		var gold := serial % 2 == 0
		var ok: bool = _game._spawn_gold_loot(10 + serial, position) if gold else _game._spawn_loot("金创药(小量)", position)
		if ok:
			for child in _game.get_children():
				if child is LootPickup and not _loot_ids.has(child.get_instance_id()):
					_loot_ids[child.get_instance_id()] = true
					var actual_ground := _screen_to_ground(child.global_position)
					_loot_manifest.append({"serial": serial, "kind": "gold" if gold else "item", "name": "gold" if gold else "金创药(小量)",
						"requested_ground": [ground.x, ground.y], "actual_ground": [actual_ground.x, actual_ground.y],
						"instance_id": child.get_instance_id()})
					break


func _count_pending(enemies: Array) -> int:
	var value := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy._hc_path_pending: value += 1
	return value


func _active_loot_count() -> int:
	var value := 0
	for child in _game.get_children():
		if child is LootPickup and is_instance_valid(child) and not child.is_queued_for_deletion(): value += 1
	return value


func _count_moving(enemies: Array) -> int:
	var value := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy._movement_step_active: value += 1
	return value


func _count_targeting(enemies: Array) -> int:
	var value := 0
	for index in range(mini(ENGAGED_COUNT, enemies.size())):
		var enemy = enemies[index]
		if is_instance_valid(enemy) and enemy.target == _game.player: value += 1
	return value


func _queued_count(node: Node) -> int:
	var value := 1 if node.is_queued_for_deletion() else 0
	for child in node.get_children():
		value += _queued_count(child)
	return value


func _attack_starts(enemies: Array) -> int:
	var value := 0
	for enemy in enemies:
		if is_instance_valid(enemy): value += int(enemy._hc_starts)
	return value


func _profile_source_hashes() -> Dictionary:
	var result := super._profile_source_hashes()
	for path in ["res://tests/phone_crowd_baseline_20261008.gd", "res://scripts/player.gd", "res://scripts/loot_pickup.gd", "res://scripts/runtime_combat_spatial_index.gd", "res://scripts/monster_ai_package/decision_budget.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result
