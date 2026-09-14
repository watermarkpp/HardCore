extends Node2D

## REV07 comparative fixture.  The production actor, cadence, physics body,
## spatial index and WORLD mask stay in the loop; this script only supplies a
## deterministic test map and observes the resulting process/physics work.

const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const PATH_SEARCH_RESOURCE := "res://scripts/monster_ai_package/path_search.gd"
const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")
const WorldRules := preload("res://scripts/world_spatial_rules.gd")
const ArtSpec := preload("res://scripts/art_spec.gd")
const FireWall := preload("res://scripts/fire_wall_field_controller.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")

const MAP_ID := 1
const MONSTER_ID := 64
const LAYOUT_SEED := 20260909
const COUNTS := [12, 15, 30]
const SCENARIOS := [
	"open_pursuit",
	"sustained_close_attacks",
	"world_obstacles",
	"dense_crowd",
]
const WARMUP_FRAMES := 45
const SAMPLE_FRAMES := 320
const DRAIN_LIMIT_PROCESS_FRAMES := 240
const PLAYER_MELEE_CONTACT_GAP_GU := 0.4375
const CLOSE_LAYOUT_OFFSETS := [
	Vector2(0.0, -2.0), Vector2(2.0, 0.0), Vector2(0.0, 2.0), Vector2(-2.0, 0.0),
	Vector2(-2.0, -1.0), Vector2(-1.0, -2.0), Vector2(1.0, -2.0), Vector2(2.0, -1.0),
	Vector2(2.0, 1.0), Vector2(1.0, 2.0), Vector2(-1.0, 2.0), Vector2(-2.0, 1.0),
	Vector2(-2.0, -2.0), Vector2(2.0, -2.0), Vector2(2.0, 2.0), Vector2(-2.0, 2.0),
	Vector2(0.0, -3.0), Vector2(3.0, 0.0), Vector2(0.0, 3.0), Vector2(-3.0, 0.0),
	Vector2(-3.0, -1.0), Vector2(-1.0, -3.0), Vector2(1.0, -3.0), Vector2(3.0, -1.0),
	Vector2(3.0, 1.0), Vector2(1.0, 3.0), Vector2(-1.0, 3.0), Vector2(-3.0, 1.0),
	Vector2(-3.0, -2.0), Vector2(-2.0, -3.0), Vector2(2.0, -3.0), Vector2(3.0, -2.0),
]

var _blocked_cells: Dictionary = {}
var _world_bodies: Array[StaticBody2D] = []
var _environment_revision := 0

var _capture_frame_timing := false
var _last_process_usec := 0
var _full_frame_samples_ms: Array[float] = []
var _frame_delta_diagnostic_ms: Array[float] = []
var _process_monitor_samples_ms: Array[float] = []
var _capture_actor_progress := false
var _sample_frame_index := 0
var _path_search_script: Script = null


class ProbePlayer:
	extends PlayerCharacter

	var probe_damage_calls := 0
	var probe_damage_total := 0

	func take_damage(
		amount: int,
		causes_struck: bool = true,
		durability_context := {},
		force_struck_reaction := false,
	) -> void:
		probe_damage_calls += 1
		probe_damage_total += maxi(0, amount)
		super.take_damage(
			amount,
			causes_struck,
			durability_context,
			force_struck_reaction,
		)


class ProbeEnemy:
	extends EnemyActor

	var probe_attack_starts := 0
	var probe_damage_applications := 0

	func _play_attack_animation(duration: float) -> void:
		probe_attack_starts += 1
		super._play_attack_animation(duration)

	func _apply_attack_damage(
		hit_target: Node2D,
		dealt_damage: int,
		use_accuracy := true,
		forced_roll := -1,
		force_struck_reaction := false,
		forced_control_roll := -1,
		ranged := false,
	) -> void:
		probe_damage_applications += 1
		super._apply_attack_damage(
			hit_target,
			dealt_damage,
			use_accuracy,
			forced_roll,
			force_struck_reaction,
			forced_control_roll,
			ranged,
		)




class DetailedProbeEnemy:
	extends ProbeEnemy

	static var section_usec: Dictionary = {}
	static var section_calls: Dictionary = {}

	func _record_probe_section(key: String, started: int) -> void:
		section_usec[key] = int(section_usec.get(key, 0)) + Time.get_ticks_usec() - started
		section_calls[key] = int(section_calls.get(key, 0)) + 1

	func _audio_try_enter_combat_session() -> bool:
		var started := Time.get_ticks_usec()
		var result := super._audio_try_enter_combat_session()
		_record_probe_section("_audio_try_enter_combat_session", started)
		return result

	func _audio_observe_visual_state() -> void:
		var started := Time.get_ticks_usec()
		super._audio_observe_visual_state()
		_record_probe_section("_audio_observe_visual_state", started)

	func _can_use_background_ai() -> bool:
		var started := Time.get_ticks_usec()
		var result := super._can_use_background_ai()
		_record_probe_section("_can_use_background_ai", started)
		return result

	func _spatial_index_update() -> void:
		var started := Time.get_ticks_usec()
		super._spatial_index_update()
		_record_probe_section("_spatial_index_update", started)

	func _update_status_effects(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._update_status_effects(delta)
		_record_probe_section("_update_status_effects", started)

	func _update_natural_regen(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._update_natural_regen(delta)
		_record_probe_section("_update_natural_regen", started)

	func _update_entrapment_state(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._update_entrapment_state(delta)
		_record_probe_section("_update_entrapment_state", started)

	func _update_pending_attack(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._update_pending_attack(delta)
		_record_probe_section("_update_pending_attack", started)

	func _handle_safe_zone_target_return(physics_delta: float) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._handle_safe_zone_target_return(physics_delta)
		_record_probe_section("_handle_safe_zone_target_return", started)
		return result

	func _update_area_attack(delta: float) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._update_area_attack(delta)
		_record_probe_section("_update_area_attack", started)
		return result

	func _update_behavior_summon(delta: float) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._update_behavior_summon(delta)
		_record_probe_section("_update_behavior_summon", started)
		return result

	func _hc_standard_melee() -> bool:
		var started := Time.get_ticks_usec()
		var result := super._hc_standard_melee()
		_record_probe_section("_hc_standard_melee", started)
		return result

	func _hc_tick_melee(delta: float, physics_delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._hc_tick_melee(delta, physics_delta)
		_record_probe_section("_hc_tick_melee", started)


	func _hc_target_usable(hit_target: Node2D) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._hc_target_usable(hit_target)
		_record_probe_section("_hc_target_usable", started)
		return result

	func _hc_access(hit_target: Node2D, tolerance := 0.0, fresh_world := false) -> String:
		var started := Time.get_ticks_usec()
		var result := super._hc_access(hit_target, tolerance, fresh_world)
		_record_probe_section("_hc_access", started)
		return result

	func _hc_frontline_at(a: Vector2, b: Vector2, hit_target: Node2D) -> int:
		var started := Time.get_ticks_usec()
		var result := super._hc_frontline_at(a, b, hit_target)
		_record_probe_section("_hc_frontline_at", started)
		return result

	func _hc_motion_clear(a: Vector2, b: Vector2) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._hc_motion_clear(a, b)
		_record_probe_section("_hc_motion_clear", started)
		return result

	func _hc_try_start(hit_target: Node2D, after_motion_attempt := false) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._hc_try_start(hit_target, after_motion_attempt)
		_record_probe_section("_hc_try_start", started)
		return result

	func _hc_world_between(a: Vector2, b: Vector2) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._hc_world_between(a, b)
		_record_probe_section("_hc_world_between", started)
		return result

	func _hc_point_inside_safe_zone(point_screen_px: Vector2) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._hc_point_inside_safe_zone(point_screen_px)
		_record_probe_section("_hc_point_inside_safe_zone", started)
		return result

	func _hc_refresh_observation() -> void:
		var started := Time.get_ticks_usec()
		super._hc_refresh_observation()
		_record_probe_section("_hc_refresh_observation", started)

	func _hc_preferred(hit_target: Node2D) -> float:
		var started := Time.get_ticks_usec()
		var result := super._hc_preferred(hit_target)
		_record_probe_section("_hc_preferred", started)
		return result

	func _advance_autonomous_step(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._advance_autonomous_step(delta)
		_record_probe_section("_advance_autonomous_step", started)


	func _hc_neighbor(current: Vector2, hit_target: Node2D, direct: Vector2i) -> Vector2i:
		var started := Time.get_ticks_usec()
		var result := super._hc_neighbor(current, hit_target, direct)
		_record_probe_section("_hc_neighbor", started)
		return result

	func _hc_prepare_flank_batch(current: Vector2, anchor: Vector2, cell: Vector2i) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._hc_prepare_flank_batch(current, anchor, cell)
		_record_probe_section("_hc_prepare_flank_batch", started)
		return result

	func _hc_point_walkable(p: Vector2) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._hc_point_walkable(p)
		_record_probe_section("_hc_point_walkable", started)
		return result

	func _hc_static_query_scope(include_safe_zone_owner: bool) -> Array:
		var started := Time.get_ticks_usec()
		var result := super._hc_static_query_scope(include_safe_zone_owner)
		_record_probe_section("_hc_static_query_scope", started)
		return result


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_path_search_script = _load_path_search_script()
	_run.call_deferred()


func _load_path_search_script() -> Script:
	# cf1d predates the path-search resource.  It is a diagnostic side channel
	# only; loading it dynamically keeps the old production tree runnable while
	# preserving the metrics when the resource exists on the candidate.
	if not ResourceLoader.exists(PATH_SEARCH_RESOURCE):
		return null
	return ResourceLoader.load(PATH_SEARCH_RESOURCE) as Script


func _reset_path_search_diagnostics() -> void:
	if _path_search_script == null:
		return
	_path_search_script.call("reset_diagnostics")


func _path_search_diagnostics() -> Dictionary:
	if _path_search_script == null:
		return {
			"available": false,
			"reason": "path_search_resource_missing_in_baseline",
		}
	var result: Variant = _path_search_script.call("diagnostics")
	if result is Dictionary:
		return result
	return {
		"available": false,
		"reason": "path_search_diagnostics_unavailable",
	}


func _process(delta: float) -> void:
	if not _capture_frame_timing:
		return
	var now_usec := Time.get_ticks_usec()
	if _last_process_usec > 0:
		_full_frame_samples_ms.append(float(now_usec - _last_process_usec) / 1000.0)
	_last_process_usec = now_usec
	_frame_delta_diagnostic_ms.append(delta * 1000.0)
	_process_monitor_samples_ms.append(
		1000.0 * (
			float(Performance.get_monitor(Performance.TIME_PROCESS))
			+ float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		)
	)


func _run() -> void:
	print("HC_REV07_START head=%s" % OS.get_environment("HARDCORE_REV07_HEAD"))
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	var label := _safe_label(OS.get_environment("HARDCORE_REV07_LABEL"))
	if label.is_empty():
		label = "unlabelled"
	var head := OS.get_environment("HARDCORE_REV07_HEAD").strip_edges()
	var selected_scenarios := _selected_scenarios()
	var selected_counts := _selected_counts()
	var rows: Array[Dictionary] = []
	for scenario: String in selected_scenarios:
		for count: int in selected_counts:
			print("HC_REV07_CASE_BEGIN scenario=%s count=%d" % [scenario, count])
			rows.append(await _sample_case(scenario, count))
	var output := {
		"schema": "hardcore.v3.rev07.scenario_full_frame_comparison.v2",
		"fixture_contract": "hardcore.rev07.real_actor_world_scenarios.v1",
		"label": label,
		"head": head,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"display_driver": DisplayServer.get_name(),
		"map_id": MAP_ID,
		"monster_id": MONSTER_ID,
		"layout_seed": LAYOUT_SEED,
		"scenarios": selected_scenarios,
		"counts": selected_counts,
		"warmup_frames": WARMUP_FRAMES,
		"sample_frames": SAMPLE_FRAMES,
		"sample_boundary": "physics_frame_then_process_frame",
		"frame_clock": "Time.get_ticks_usec_adjacent_process_callbacks",
		"threshold": "candidate_p95 <= max(baseline_p95*1.05, baseline_p95+0.5ms)",
		"rows": rows,
		"source_hashes_sha256": _source_hashes(),
	}
	var directory := "res://outputs/hc_monster_ai_package"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory + "/rev07_%s.json" % label, FileAccess.WRITE)
	assert(file != null, "REV07 output file could not be created")
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("HC_REV07_FULL_FRAME_JSON=", JSON.stringify(output))
	print(
		"HC_REV07_FULL_FRAME_PASS label=%s scenarios=%s counts=%s warmup=%d sample=%d"
		% [label, ",".join(selected_scenarios), ",".join(selected_counts.map(func(value: int) -> String: return str(value))), WARMUP_FRAMES, SAMPLE_FRAMES]
	)
	get_tree().quit(0)


func _selected_scenarios() -> Array[String]:
	var raw := OS.get_environment("HARDCORE_REV07_SCENARIOS").strip_edges()
	if raw.is_empty():
		var all_scenarios: Array[String] = []
		for scenario: String in SCENARIOS:
			all_scenarios.append(scenario)
		return all_scenarios
	var selected: Array[String] = []
	for token: String in raw.split(","):
		var scenario := token.strip_edges()
		if scenario.is_empty():
			continue
		assert(SCENARIOS.has(scenario), "unknown HARDCORE_REV07_SCENARIOS value %s" % scenario)
		if not selected.has(scenario):
			selected.append(scenario)
	assert(not selected.is_empty(), "HARDCORE_REV07_SCENARIOS selected no scenarios")
	return selected


func _selected_counts() -> Array[int]:
	var raw := OS.get_environment("HARDCORE_REV07_COUNTS").strip_edges()
	if raw.is_empty():
		var all_counts: Array[int] = []
		for count: int in COUNTS:
			all_counts.append(count)
		return all_counts
	var selected: Array[int] = []
	for token: String in raw.split(","):
		var count_text := token.strip_edges()
		if count_text.is_empty():
			continue
		var count := int(count_text)
		assert(COUNTS.has(count), "unknown HARDCORE_REV07_COUNTS value %s" % count_text)
		if not selected.has(count):
			selected.append(count)
	assert(not selected.is_empty(), "HARDCORE_REV07_COUNTS selected no counts")
	return selected


func _sample_case(scenario: String, count: int) -> Dictionary:
	assert(SCENARIOS.has(scenario), "unknown REV07 scenario %s" % scenario)
	_clear_environment()
	var blocked_cells := _blocked_cells_for_scenario(scenario)
	# WORLD detours exercise the actor's last-known-target path.  Let the
	# production observation acquire the target once in clear space, then add
	# the real WORLD bodies before warmup; the fixture never writes private AI
	# state or manually drives a path.
	if scenario != "world_obstacles":
		_set_environment(blocked_cells)
	var index := SpatialIndex.new()
	var player := _make_player(_target_ground())
	var context := _terrain_context()
	var enemies: Array[EnemyActor] = []
	var initial_ground_by_id: Dictionary = {}
	for actor_index: int in range(count):
		var ground := _layout_position(scenario, actor_index)
		var enemy := _make_enemy(player, index, context, ground, actor_index + 1)
		enemies.append(enemy)
		initial_ground_by_id[enemy.get_instance_id()] = _screen_to_ground(enemy.global_position)
	var initial_layout := _assert_initial_layout_valid(enemies, player)
	# Let _ready, the physics server and the first target observation settle.
	await _await_real_frame()
	if scenario == "world_obstacles":
		_set_environment(blocked_cells)
		context = _terrain_context()
		for enemy: EnemyActor in enemies:
			enemy.configure_terrain_navigation_context(context)
	for _frame: int in range(WARMUP_FRAMES - 1):
		await _await_real_frame()
	var field_started := Time.get_ticks_usec()
	var fields := _make_optional_fire_walls(player, index)
	var field_setup_usec := Time.get_ticks_usec() - field_started if not fields.is_empty() else 0
	_reset_probe_counters(enemies, player)
	DetailedProbeEnemy.section_usec.clear()
	DetailedProbeEnemy.section_calls.clear()
	EnemyActor.reset_performance_diagnostics()
	Terrain.reset_diagnostics()
	_reset_path_search_diagnostics()
	var scheduler := _path_scheduler()
	var scheduler_before := _scheduler_snapshot(scheduler)
	_capture_frame_timing = true
	_last_process_usec = Time.get_ticks_usec()
	_full_frame_samples_ms.clear()
	_frame_delta_diagnostic_ms.clear()
	_process_monitor_samples_ms.clear()
	_capture_actor_progress = true
	_sample_frame_index = 0
	var sample_physics_started := Engine.get_physics_frames()
	for _frame: int in range(SAMPLE_FRAMES):
		_sample_frame_index += 1
		await _await_real_frame()
	_capture_frame_timing = false
	_capture_actor_progress = false
	var sample_physics_ticks := Engine.get_physics_frames() - sample_physics_started
	assert(sample_physics_ticks >= SAMPLE_FRAMES, "%s/%d sampled fewer physics ticks: %d" % [scenario, count, sample_physics_ticks])
	assert(_full_frame_samples_ms.size() >= SAMPLE_FRAMES, "%s/%d sampled fewer process intervals: %d" % [scenario, count, _full_frame_samples_ms.size()])
	assert(get_tree().get_nodes_in_group("enemies").size() == count, "%s/%d actor count changed" % [scenario, count])
	var enemy_metrics := EnemyActor.performance_diagnostics()
	var terrain_metrics := Terrain.diagnostics()
	var path_search_metrics: Dictionary = _path_search_diagnostics()
	var scheduler_after := _scheduler_snapshot(scheduler)
	if scheduler == null:
		scheduler = _path_scheduler()
		scheduler_after = _scheduler_snapshot(scheduler)
	var actor_proof := _actor_proof(enemies, player, initial_ground_by_id)
	var aggregate := _aggregate_actor_proof(actor_proof)
	if not fields.is_empty():
		var hits := 0
		for field: FireWall in fields:
			assert(field.visual_cells.size() == 9 and field.tick_count >= 5)
			hits += field.damage_application_count
		assert(hits > 0, "AOE sample must apply real controller-owned damage to the crowd")
	var row := {
		"scenario": scenario,
		"monster_count": count,
		"map_id": MAP_ID,
		"layout_seed": LAYOUT_SEED,
		"layout_signature": _layout_signature(scenario, count),
		"initial_layout": initial_layout,
		"world_obstacle_activation": (
			"after_first_unblocked_observation"
			if scenario == "world_obstacles"
			else "before_spawn"
		),
		"blocked_cell_count": _blocked_cells.size(),
		"world_body_count": _world_bodies.size(),
		"full_frame_ms": _summary(_full_frame_samples_ms),
		"full_frame_ms_raw": _full_frame_samples_ms.duplicate(),
		"tail_frame_counts": _tail_counts(_full_frame_samples_ms),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"frame_delta_diagnostic_ms": _summary(_frame_delta_diagnostic_ms),
		"godot_process_monitor_ms_diagnostic_only": _godot_process_monitor_summary(),
		"enemy_metrics": enemy_metrics,
		"fire_wall_fields": fields.size(),
		"fire_wall_setup_usec": field_setup_usec,
		"fire_wall_diagnostics": fields.map(func(field: FireWall) -> Dictionary: return field.fire_wall_controller_diagnostics()),
		"optional_probe_section_usec": DetailedProbeEnemy.section_usec.duplicate(),
		"optional_probe_section_calls": DetailedProbeEnemy.section_calls.duplicate(),
		"terrain_metrics": terrain_metrics,
		"path_search_metrics": path_search_metrics,
		"scheduler_delta": _scheduler_delta(scheduler_before, scheduler_after),
		"path_status_counts": _path_status_counts(enemies),
		"sample_process_frames": SAMPLE_FRAMES,
		"sample_physics_ticks": sample_physics_ticks,
		"actual_actor_count": aggregate.actual_actor_count,
		"target_damage_calls": player.probe_damage_calls,
		"target_damage_total": player.probe_damage_total,
		"actors_with_attack_start": aggregate.actors_with_attack_start,
		"actors_with_attack_damage": aggregate.actors_with_attack_damage,
		"total_attack_starts": aggregate.total_attack_starts,
		"total_attack_damage_applications": aggregate.total_attack_damage_applications,
		"actors_with_motion": aggregate.actors_with_motion,
		"total_motion_frames": aggregate.total_motion_frames,
		"total_motion_gu": aggregate.total_motion_gu,
		"actor_proof": actor_proof,
	}
	# Drain only after the fixed window. This reports pending path work without
	# diluting the frame samples or replacing the live process evidence.
	for enemy: EnemyActor in enemies:
		enemy.set_physics_process(false)
	for field: FireWall in fields:
		field.set_physics_process(false)
		field.queue_free()
	var drain := await _drain_scheduler(scheduler)
	row["post_sample_drain"] = drain
	index.clear_map(MAP_ID)
	for enemy: EnemyActor in enemies:
		enemy.queue_free()
	player.queue_free()
	_clear_environment()
	for _frame: int in range(3):
		await _await_real_frame()
	return row


func _make_optional_fire_walls(player: PlayerCharacter, index: SpatialIndex) -> Array[FireWall]:
	var fields: Array[FireWall] = []
	if OS.get_environment("HARDCORE_V82_FIRE_WALL") != "1":
		return fields
	for serial in range(6):
		var anchor := _target_ground().floor() + Vector2((serial % 3) * 2 - 2, (serial / 3) * 2 - 1)
		var context := Snapshot.make_absolute_runtime_context(MAP_ID, anchor, anchor, _ground_to_screen)
		context["expected_runtime_map_id"] = MAP_ID
		var cells: Array[Vector2i] = []
		var positions: Array[Vector2] = []
		for y in range(-1, 2):
			for x in range(-1, 2):
				cells.append(Vector2i(anchor) + Vector2i(x, y))
				positions.append(_ground_to_screen(anchor + Vector2(x, y)))
		var release_id := "v82:field:%d:%d" % [player.get_instance_id(), serial]
		var snapshot := SpellGeometry.create_exact_cell_union_release_snapshot(
			"wizard.fire_wall", release_id, anchor, cells, context)
		var filters: Array[Callable] = []
		var field := FireWall.new()
		field.setup_fire_wall_field(player, "wizard.fire_wall",
			{"raw_power": 1, "duration_seconds": 60.0, "tick_interval_ms": 1000},
			positions, cells, filters,
			func(enemy: EnemyActor, power: int) -> void: enemy.take_damage(power, player),
			_screen_to_ground, release_id, snapshot, context, index, MAP_ID)
		add_child(field)
		fields.append(field)
	return fields


func _make_player(ground: Vector2) -> ProbePlayer:
	var player := ProbePlayer.new()
	player.name = "REV07ProbePlayer"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = _ground_to_screen(ground)
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000000
	player.current_hp = player.max_hp
	player.defense_min = 0
	player.defense_max = 0
	player.current_mp = 0
	return player


func _make_enemy(
	player: ProbePlayer,
	index: SpatialIndex,
	context: Dictionary,
	ground: Vector2,
	serial: int,
) -> EnemyActor:
	var enemy := (
		DetailedProbeEnemy.new()
		if OS.get_environment("HARDCORE_V82_DETAIL_PROBE") == "1"
		else ProbeEnemy.new()
	)
	enemy.setup(GameData.get_monster_by_id(MONSTER_ID), player, false)
	enemy.set_spawn_facing_seed_for_test(LAYOUT_SEED + serial)
	enemy.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	enemy.configure_terrain_navigation_context(context)
	enemy.configure_spatial_index(index, serial)
	enemy.environment_blocker = self
	enemy.set_meta("zone_generation", 1)
	enemy.set_meta("safe_zones", [])
	enemy.set_meta("spawn_serial", serial)
	enemy.set_combat_position(_ground_to_screen(ground), &"rev07_spawn")
	# Set the selected target before _ready so an ordinary actor never enters
	# the idle background timer path between attachment and the first physics tick.
	enemy.target = player
	add_child(enemy)
	# _ready may apply its formal spawn-overlap guard; register the resulting
	# position, then leave physics enabled for the actual runner.
	var actual_ground := _screen_to_ground(enemy.global_position)
	index.register(
		serial,
		MAP_ID,
		actual_ground,
		enemy.combat_radius_gu,
		serial,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)
	enemy.set_physics_process(true)
	return enemy


func _reset_probe_counters(enemies: Array[EnemyActor], player: ProbePlayer) -> void:
	player.probe_damage_calls = 0
	player.probe_damage_total = 0
	for enemy: EnemyActor in enemies:
		enemy.set("probe_attack_starts", 0)
		enemy.set("probe_damage_applications", 0)
		enemy.set_meta("rev07_motion_frames", 0)
		enemy.set_meta("rev07_motion_gu", 0.0)
		enemy.set_meta("rev07_first_path_arrival_frame", -1)


func _actor_proof(
	enemies: Array[EnemyActor],
	player: ProbePlayer,
	initial_ground_by_id: Dictionary,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for enemy: EnemyActor in enemies:
		var instance_id := enemy.get_instance_id()
		var initial_ground: Vector2 = initial_ground_by_id.get(instance_id, Vector2.INF)
		var current_ground := _screen_to_ground(enemy.global_position)
		var starts := int(enemy.get("probe_attack_starts"))
		var damages := int(enemy.get("probe_damage_applications"))
		var arrival_distance := maxf(
			enemy.attack_range_gu,
			enemy._contact_distance_gu_to_target(player),
		)
		var final_distance := current_ground.distance_to(_screen_to_ground(player.global_position))
		var path_status := "legacy_baseline"
		if enemy.has_method("hc_package_policy_snapshot"):
			path_status = str(enemy.call("hc_package_policy_snapshot").get("path_status", ""))
		result.append({
			"serial": int(enemy.get_meta("spawn_serial", -1)),
			"instance_id": instance_id,
			"initial_ground_gu": _vec2_array(initial_ground),
			"final_ground_gu": _vec2_array(current_ground),
			"final_distance_to_target_gu": final_distance,
			"arrival_reach_gu": arrival_distance,
			"first_path_arrival_frame": int(enemy.get_meta("rev07_first_path_arrival_frame", -1)),
			"first_path_arrival_observed": int(enemy.get_meta("rev07_first_path_arrival_frame", -1)) >= 0,
			"attack_start_count": starts,
			"attack_damage_application_count": damages,
			"target_damage_calls_seen": damages,
			"motion_frames": int(enemy.get_meta("rev07_motion_frames", 0)),
			"motion_gu": float(enemy.get_meta("rev07_motion_gu", 0.0)),
			"path_status": path_status,
		})
	return result


func _aggregate_actor_proof(actor_proof: Array[Dictionary]) -> Dictionary:
	var result := {
		"actual_actor_count": actor_proof.size(),
		"actors_with_attack_start": 0,
		"actors_with_attack_damage": 0,
		"total_attack_starts": 0,
		"total_attack_damage_applications": 0,
		"actors_with_motion": 0,
		"total_motion_frames": 0,
		"total_motion_gu": 0.0,
	}
	for proof: Dictionary in actor_proof:
		var starts := int(proof.get("attack_start_count", 0))
		var damages := int(proof.get("attack_damage_application_count", 0))
		var motion_frames := int(proof.get("motion_frames", 0))
		result["actors_with_attack_start"] += 1 if starts > 0 else 0
		result["actors_with_attack_damage"] += 1 if damages > 0 else 0
		result["total_attack_starts"] += starts
		result["total_attack_damage_applications"] += damages
		result["actors_with_motion"] += 1 if motion_frames > 0 else 0
		result["total_motion_frames"] += motion_frames
		result["total_motion_gu"] += float(proof.get("motion_gu", 0.0))
	return result


func _await_real_frame() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	_observe_motion()


func _observe_motion() -> void:
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or not is_instance_valid(node):
			continue
		var enemy := node as EnemyActor
		var motion := enemy.actual_ground_motion_gu.length()
		if motion > GU.EPSILON_GU:
			enemy.set_meta("rev07_motion_frames", int(enemy.get_meta("rev07_motion_frames", 0)) + 1)
			enemy.set_meta("rev07_motion_gu", float(enemy.get_meta("rev07_motion_gu", 0.0)) + motion)
		if _capture_actor_progress and int(enemy.get_meta("rev07_first_path_arrival_frame", -1)) < 0:
			var target := get_tree().get_first_node_in_group("player") as Node2D
			if is_instance_valid(target):
				var current_ground := _screen_to_ground(enemy.global_position)
				var target_ground := _screen_to_ground(target.global_position)
				var reach := maxf(enemy.attack_range_gu, enemy._contact_distance_gu_to_target(target))
				if current_ground.distance_to(target_ground) <= reach + GU.EPSILON_GU:
					enemy.set_meta("rev07_first_path_arrival_frame", _sample_frame_index)


func _path_status_counts(enemies: Array[EnemyActor]) -> Dictionary:
	var counts: Dictionary = {}
	for enemy: EnemyActor in enemies:
		var status := "legacy_baseline"
		if enemy.has_method("hc_package_policy_snapshot"):
			status = str(enemy.call("hc_package_policy_snapshot").get("path_status", ""))
		counts[status] = int(counts.get(status, 0)) + 1
	return counts


func _path_scheduler() -> Node:
	return get_tree().root.get_node_or_null("HCMonsterPathBudget")


func _scheduler_snapshot(scheduler: Node) -> Dictionary:
	if scheduler == null:
		return {"available": false}
	return {
		"available": true,
		"service_count": int(scheduler.get("service_count")),
		"expansions_count": int(scheduler.get("expansions_count")),
		"diagnostic_pump_calls": int(scheduler.get("diagnostic_pump_calls")),
		"diagnostic_pump_usec": int(scheduler.get("diagnostic_pump_usec")),
		"pending_jobs": int((scheduler.get("jobs") as Dictionary).size()),
	}


func _scheduler_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	if not bool(after.get("available", false)):
		return {"available": false}
	return {
		"available": true,
		"service_count": int(after.get("service_count", 0)) - int(before.get("service_count", 0)),
		"expansions_count": int(after.get("expansions_count", 0)) - int(before.get("expansions_count", 0)),
		"diagnostic_pump_calls": int(after.get("diagnostic_pump_calls", 0)) - int(before.get("diagnostic_pump_calls", 0)),
		"diagnostic_pump_usec": int(after.get("diagnostic_pump_usec", 0)) - int(before.get("diagnostic_pump_usec", 0)),
		"pending_jobs": int(after.get("pending_jobs", 0)),
	}


func _drain_scheduler(scheduler: Node) -> Dictionary:
	var frames := 0
	var start_pending := int((scheduler.get("jobs") as Dictionary).size()) if scheduler != null else 0
	var start_services := int(scheduler.get("service_count")) if scheduler != null else 0
	var start_expansions := int(scheduler.get("expansions_count")) if scheduler != null else 0
	while scheduler != null and not (scheduler.get("jobs") as Dictionary).is_empty() and frames < DRAIN_LIMIT_PROCESS_FRAMES:
		frames += 1
		await _await_real_frame()
	var end_pending := int((scheduler.get("jobs") as Dictionary).size()) if scheduler != null else 0
	return {
		"start_pending_jobs": start_pending,
		"end_pending_jobs": end_pending,
		"completed_within_limit": end_pending == 0 if scheduler != null else true,
		"process_frames": frames,
		"services": int(scheduler.get("service_count")) - start_services if scheduler != null else 0,
		"expansions": int(scheduler.get("expansions_count")) - start_expansions if scheduler != null else 0,
	}


func _godot_process_monitor_summary() -> Dictionary:
	# Performance monitors are a diagnostic side channel.  The acceptance
	# metric is the adjacent process-callback wall sample above.
	return _summary(_process_monitor_samples_ms)


func _set_environment(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		_blocked_cells[cell] = true
		_add_world_cell_body(cell)
	_environment_revision += 1


func _clear_environment() -> void:
	for body: StaticBody2D in _world_bodies:
		if is_instance_valid(body):
			body.queue_free()
	_world_bodies.clear()
	_blocked_cells.clear()
	_environment_revision += 1


func _add_world_cell_body(cell: Vector2i) -> void:
	var center_ground := Vector2(cell) + Vector2(0.5, 0.5)
	var center_screen := _ground_to_screen(center_ground)
	var points := PackedVector2Array()
	for corner: Vector2 in [
		Vector2(cell),
		Vector2(cell) + Vector2.RIGHT,
		Vector2(cell) + Vector2.ONE,
		Vector2(cell) + Vector2.DOWN,
	]:
		points.append(_ground_to_screen(corner) - center_screen)
	var body := StaticBody2D.new()
	body.name = "REV07WorldCell_%d_%d" % [cell.x, cell.y]
	body.collision_layer = WorldRules.WORLD_LAYER
	body.collision_mask = 0
	body.global_position = center_screen
	var collision := CollisionShape2D.new()
	var shape := ConvexPolygonShape2D.new()
	shape.points = points
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	_world_bodies.append(body)


func is_environment_point_blocked(world_px: Vector2) -> bool:
	var ground := _screen_to_ground(world_px)
	return ground.is_finite() and _blocked_cells.has(Vector2i(floori(ground.x), floori(ground.y)))


func is_environment_actor_blocked(center_world_px: Vector2, collision_radius_px: float) -> bool:
	if is_environment_point_blocked(center_world_px):
		return true
	var sample_radius_px := maxf(0.0, collision_radius_px - 1.0)
	for index: int in range(WorldRules.ACTOR_FOOTPRINT_SEGMENTS):
		if is_environment_point_blocked(center_world_px + WorldRules.actor_footprint_offset_px(index, sample_radius_px)):
			return true
	return false


func is_environment_segment_blocked_ground(
	start_ground_gu: Vector2,
	end_ground_gu: Vector2,
	step_gu: float,
) -> bool:
	var samples := maxi(1, int(ceil(start_ground_gu.distance_to(end_ground_gu) / maxf(0.05, step_gu))))
	for sample_index: int in range(samples + 1):
		var point := start_ground_gu.lerp(end_ground_gu, float(sample_index) / float(samples))
		if _blocked_cells.has(Vector2i(floori(point.x), floori(point.y))):
			return true
	return false


func environment_collision_revision() -> int:
	return _environment_revision


func _terrain_context() -> Dictionary:
	var blocked := _blocked_cells.duplicate()
	blocked.make_read_only()
	var context := {
		"valid": true,
		"contract_id": Terrain.CONTRACT_ID,
		"runtime_map_id": MAP_ID,
		"build_sha256": "rev07".sha256_text(),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": Vector2i(80, 80),
		"blocked_cells": blocked,
	}
	context.make_read_only()
	return context


func _blocked_cells_for_scenario(scenario: String) -> Array[Vector2i]:
	if scenario != "world_obstacles":
		return []
	var cells: Array[Vector2i] = []
	# A fixed, real WORLD-layer wall bisects the pursuit lanes.  The two gaps
	# make the route reachable and ensure the sample observes detour work rather
	# than a synthetic permanently closed target.
	for y: int in range(12, 29):
		if y in [12, 28]:
			continue
		cells.append(Vector2i(15, y))
	return cells


func _layout_position(scenario: String, actor_index: int) -> Vector2:
	if scenario == "sustained_close_attacks":
		assert(actor_index < CLOSE_LAYOUT_OFFSETS.size(), "close layout has too few positions")
		return _target_ground() + CLOSE_LAYOUT_OFFSETS[actor_index]
	if scenario == "dense_crowd":
		var valid_positions: Array[Vector2] = []
		for row: int in range(6):
			for column: int in range(8):
				var offset := Vector2(-4.0 + float(column), -1.0 + float(row))
				if offset.length() < 1.5:
					continue
				valid_positions.append(_target_ground() + offset)
		assert(actor_index < valid_positions.size(), "dense layout has too few positions")
		return valid_positions[actor_index]
	# The open and wall lanes use identical source positions so the obstacle
	# difference is the only scenario change.
	var column := actor_index % 5
	var row := actor_index / 5
	return Vector2(8.5 + float(column) * 1.3, 14.5 + float(row) * 1.3)


func _target_ground() -> Vector2:
	return Vector2(20.5, 20.5)


func _assert_initial_layout_valid(enemies: Array[EnemyActor], player: ProbePlayer) -> Dictionary:
	var player_radius_gu := WorldRules.actor_combat_radius_gu_from_screen_radius_px(
		ArtSpec.PLAYER_COLLISION_RADIUS_PX
	)
	var minimum_target_distance_gu := INF
	var minimum_actor_distance_gu := INF
	var target_ground := _screen_to_ground(player.global_position)
	for enemy: EnemyActor in enemies:
		var enemy_ground := _screen_to_ground(enemy.global_position)
		minimum_target_distance_gu = minf(minimum_target_distance_gu, enemy_ground.distance_to(target_ground))
		var required_target_distance := (
			enemy.combat_radius_gu + player_radius_gu + PLAYER_MELEE_CONTACT_GAP_GU
		)
		assert(
			enemy_ground.distance_to(target_ground) + GU.EPSILON_GU >= required_target_distance,
			"REV07 initial actor overlaps player: serial=%s distance=%s required=%s"
			% [str(enemy.get_meta("spawn_serial", -1)), enemy_ground.distance_to(target_ground), required_target_distance],
		)
	for left_index: int in range(enemies.size()):
		var left := enemies[left_index]
		var left_ground := _screen_to_ground(left.global_position)
		for right_index: int in range(left_index + 1, enemies.size()):
			var right := enemies[right_index]
			var right_ground := _screen_to_ground(right.global_position)
			var distance := left_ground.distance_to(right_ground)
			minimum_actor_distance_gu = minf(minimum_actor_distance_gu, distance)
			var required_distance := left.combat_radius_gu + right.combat_radius_gu
			assert(
				distance + GU.EPSILON_GU >= required_distance,
				"REV07 initial actors overlap: serials=%s/%s distance=%s required=%s"
				% [str(left.get_meta("spawn_serial", -1)), str(right.get_meta("spawn_serial", -1)), distance, required_distance],
			)
	return {
		"valid": true,
		"min_actor_separation_gu": 0.0 if enemies.size() < 2 else minimum_actor_distance_gu,
		"min_target_separation_gu": minimum_target_distance_gu,
		"player_radius_gu": player_radius_gu,
	}


func _layout_signature(scenario: String, count: int) -> String:
	var values: Array[String] = []
	for actor_index: int in range(count):
		values.append(str(_layout_position(scenario, actor_index)))
	return ("seed=%d|scenario=%s|count=%d|blocked=%s|positions=%s" % [
		LAYOUT_SEED,
		scenario,
		count,
		str(_blocked_cells_for_scenario(scenario)),
		";".join(values),
	]).sha256_text()


func _tail_counts(values: Array[float]) -> Dictionary:
	var over_16_67 := 0
	var over_25 := 0
	var over_33_3 := 0
	var over_50 := 0
	for value: float in values:
		if value > 16.67:
			over_16_67 += 1
		if value > 25.0:
			over_25 += 1
		if value > 33.3:
			over_33_3 += 1
		if value > 50.0:
			over_50 += 1
	return {"over_16_67ms": over_16_67, "over_25ms": over_25, "over_33_3ms": over_33_3, "over_50ms": over_50}

func _source_hashes() -> Dictionary:
	var paths := [
		"res://scripts/enemy.gd",
		"res://scripts/monster_visual.gd",
		"res://scripts/monster_terrain_navigation_policy.gd",
		"res://scripts/runtime_combat_spatial_index.gd",
		"res://tests/hc_monster_ai/m30_sampling_copy.gd",
	]
	var hashes := {}
	for path: String in paths:
		if FileAccess.file_exists(path):
			hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _summary(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	assert(not sorted.is_empty(), "REV07 timing window is empty")
	return {
		"p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95),
		"p99": _percentile(sorted, 0.99),
		"min": sorted[0],
		"max": sorted[-1],
		"samples": sorted.size(),
	}


func _percentile(sorted: Array[float], ratio: float) -> float:
	var index := clampi(ceili(float(sorted.size()) * ratio) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _vec2_array(value: Vector2) -> Array[float]:
	return [value.x, value.y] if value.is_finite() else []


func _ground_to_screen(value: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(value)


func _safe_label(raw: String) -> String:
	var result := raw.strip_edges()
	if result.is_empty():
		return result
	var safe := ""
	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
	for character: String in result:
		if allowed.contains(character):
			safe += character
	return safe
