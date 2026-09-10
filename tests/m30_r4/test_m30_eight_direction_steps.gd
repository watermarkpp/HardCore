extends Node

# Test-only observer. No attack/cooldown/position repair while the case is armed.
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Geometry := preload("res://tests/m30_r4_r2/fixture_geometry.gd")
const Sampler := preload("res://tests/m30_r4_r2/lab_sampler.gd")
const ArtWaitFreeze := preload("res://tests/m30_r3_closure/art_wait_freeze.gd")
const MIN_ART_FREEZE_MS: int = 650
const MONSTER_ID: int = 64
const BASE_SHA := "cfe1b81f892ba6dd8ebe82012c9b700b65e5314f"
var _sampler: Node
var _game: Node
var _actor: EnemyActor
var _armed := false
var _direction := -1
var _center := Vector2.ZERO
var _trace: Array[Dictionary] = []
var _preflight: Array[Dictionary] = []
var _cases: Array[Dictionary] = []
var _previous_starts := 0
var _first_attack_distance := -1.0
var _first_attack_tick := -1
var _before_ground := Vector2.INF
var _failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
		push_error("M30_R2_STEPS " + label)

func _physics_sample() -> void:
	if not _armed or not is_instance_valid(_actor):
		return
	var p := _actor.spatial_index_position()
	if _actor._hc_starts > _previous_starts:
		if _first_attack_tick < 0:
			_first_attack_distance = p.distance_to(_center)
			_first_attack_tick = Engine.get_physics_frames()
		check(_actor._hc_starts == _previous_starts + 1, "no double start within one observed physics tick")
	_previous_starts = _actor._hc_starts
	var collisions: Array[Dictionary] = []
	var moved := p.distance_to(_before_ground) if _before_ground.is_finite() else 0.0
	if moved <= 0.0001:
		for i: int in range(_actor.get_slide_collision_count()):
			collisions.append(Geometry.describe_collision(_actor.get_slide_collision(i)))
	var stable: Vector2 = Geometry.stable_reference(_game, p, _actor.combat_radius_gu)
	if _trace.size() < 1024:
		_trace.append({
			"dir": _direction, "physics_tick": Engine.get_physics_frames(),
			"point": [p.x, p.y], "distance_to_target": p.distance_to(_center),
			"target_point": [_center.x, _center.y], "motion_gu": moved,
			"reason": _actor._hc_last_reason, "starts": _actor._hc_starts,
			"pose_remaining": _actor._hc_m30_attack_pose_remaining,
			"cooldown": _actor._attack_timer, "pending_impact": _actor._pending_attack_time,
			"step_active": _actor._movement_step_active,
			"path_status": _actor._hc_path_status, "path_pending": _actor._hc_path_pending,
			"world_collisions": _actor._hc_world_collision_count, "last_slide_collisions_not_timestamped": collisions,
			"safe_projection": [stable.x, stable.y] if stable.is_finite() else [],
			"map_id": _actor.runtime_map_id, "generation": _actor.get_meta("zone_generation", -1),
			"life": _actor.get_meta("hc_combat_life_epoch", -1),
		})
	_before_ground = p

func _verified_center(probe: EnemyActor) -> Vector2:
	# Save rejection reasons, including the old first-choice centre. Never infer
	# terrain failure from "the monster did not move".
	for ring: int in range(9):
		for y: int in range(-ring, ring + 1):
			for x: int in range(-ring, ring + 1):
				if maxi(absi(x), absi(y)) != ring:
					continue
				var c := Fixture.FIXTURE_GROUND_POSITION + Vector2(x, y) * 2.0
				if not probe._hc_point_walkable(c):
					continue
				_game._set_player_world_position(_game._canonical_ground_gu_to_screen_px(c))
				# Allow the server to publish the player's real collision transform.
				await _sampler.after_physics
				var checks: Array[Dictionary] = []
				var ok := true
				for d: int in range(8):
					var r: Dictionary = Geometry.corridor(_game, probe, c, d)
					checks.append(r)
					if not bool(r.get("clear", false)):
						ok = false
				_preflight.append({"center": [c.x, c.y], "directions": checks, "accepted": ok})
				if ok:
					return c
	return Vector2.INF

func _run_case(d: int) -> bool:
	_direction = d
	_trace = []
	var direction := Vector2.from_angle(TAU * float(d) / 8.0)
	var start := _center + direction * 2.0
	_actor = _game._spawn_enemy(GameData.get_monster_by_id(MONSTER_ID), _game._canonical_ground_gu_to_screen_px(start), false, -1.0, {"respawn_enabled": false, "spawn_slot_id": "test:m30_r2:%d" % d})
	check(is_instance_valid(_actor), "dir %d exact-ID spawn" % d)
	if not is_instance_valid(_actor):
		return false
	# Fence both actor and child Timer callbacks in the creation call stack.
	var art_freeze := ArtWaitFreeze.new()
	if not art_freeze.begin(_actor, _actor.visual):
		check(false, "dir %d freeze could not be established" % d)
		_actor.queue_free()
		return false
	var spawned := _actor.spatial_index_position()
	check(spawned.distance_to(start) < 0.015, "dir %d spawn identity/position invariant" % d)
	var art_deadline := Time.get_ticks_msec() + 8000
	while is_instance_valid(_actor) and (not _actor.visual.uses_final_art() or art_freeze.elapsed_msec() < MIN_ART_FREEZE_MS) and Time.get_ticks_msec() < art_deadline:
		await _sampler.after_visual
	if not is_instance_valid(_actor) or not _actor.visual.uses_final_art():
		check(false, "dir %d art readiness timeout" % d)
		art_freeze.restore()
		if is_instance_valid(_actor):
			_actor.queue_free()
		return false
	check(art_freeze.intact(), "dir %d scheduling fence remained intact" % d)
	check(_actor._hc_starts == 0, "dir %d zero attacks consumed during art-wait" % d)
	check(_actor.spatial_index_position().distance_to(start) < 0.015, "dir %d no art-wait displacement" % d)
	if not art_freeze.intact() or _actor._hc_starts != 0 or _actor.spatial_index_position().distance_to(start) >= 0.015:
		_cases.append({"dir": d, "status": "FAIL", "stage": "art_wait_position_or_attack_changed", "requested_start": [start.x, start.y], "spawned_point": [spawned.x, spawned.y]})
		art_freeze.restore()
		_actor.queue_free()
		return false
	var baseline: Dictionary = _actor.visual.hc_m30_motion_snapshot()
	var last_phase := float(baseline["walk_phase"])
	var last_distance := float(baseline["actual_distance_gu"])
	var preferred := _actor._hc_preferred(_game.player)
	_previous_starts = 0
	_first_attack_tick = -1
	_first_attack_distance = -1.0
	_before_ground = start
	var walks := 0
	var attacks := 0
	var reached := false
	var case_failures := _failures.size()
	_armed = true
	# Restore original schedules; the existing wake Timer owns activation.
	check(art_freeze.restore(), "dir %d scheduling modes restored" % d)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and is_instance_valid(_actor):
		await _sampler.after_visual
		if not is_instance_valid(_actor):
			break
		var snap: Dictionary = _actor.visual.hc_m30_motion_snapshot()
		check(int(snap["visual_process_frame"]) == Engine.get_process_frames(), "dir %d fresh rendered sample" % d)
		var distance := float(snap["actual_distance_gu"])
		var phase := float(snap["walk_phase"])
		var cycle := float(snap["reference_cycle_gu"])
		if distance > last_distance and cycle > 0.0:
			var expected := fposmod(last_phase + (distance - last_distance) / cycle, 1.0)
			var error := absf(expected - phase)
			check(minf(error, 1.0 - error) < 0.001, "dir %d distance-driven phase" % d)
		elif distance == last_distance:
			check(is_equal_approx(phase, last_phase), "dir %d no idle phase drift" % d)
		last_distance = distance
		last_phase = phase
		if str(snap["state"]) == "walk":
			walks += 1
			var count := MonsterAnimationPolicy.frame_count(_actor.visual.active_resources, &"walk")
			check(count > 0 and int(snap["frame"]) == mini(count - 1, int(floor(phase * float(count)))), "dir %d atlas frame mapping" % d)
		elif str(snap["state"]) == "attack":
			attacks += 1
		var p := _actor.spatial_index_position()
		check(_game._canonical_screen_px_to_ground_gu(_game.player.global_position).distance_to(_center) < 0.015, "dir %d target remained stationary" % d)
		if p.distance_to(_center) <= preferred + 0.015:
			reached = true
			break
	_armed = false
	check(reached, "dir %d reached preferred" % d)
	check(walks >= 2, "dir %d at least two actual walk samples" % d)
	check(attacks >= 1, "dir %d readable attack samples" % d)
	check(_first_attack_tick >= 0 and _first_attack_distance > preferred + 0.05 and _first_attack_distance <= 2.0 + 0.001, "dir %d first accepted attack was in outer band" % d)
	var passed := _failures.size() == case_failures and reached and walks >= 2 and attacks >= 1
	_cases.append({"dir": d, "requested_start": [start.x, start.y], "spawned_point": [spawned.x, spawned.y], "reached": reached, "walk_samples": walks, "attack_pose_samples": attacks, "accepted_attack_count": _previous_starts, "first_attack_distance": _first_attack_distance, "first_attack_tick": _first_attack_tick, "actual_distance_gu": last_distance, "status": "PASS" if passed else "FAIL", "physics_trace": _trace, "corridor_recheck": Geometry.corridor(_game, _actor, _center, d) if is_instance_valid(_actor) else {}})
	if is_instance_valid(_actor):
		_actor.queue_free()
	await _sampler.after_visual
	await _sampler.after_visual
	return passed

func _finish(status: String, detail: String) -> void:
	_armed = false
	var data := {"schema": "m30.r4r2.eight_directions.v1", "base": BASE_SHA, "run_head": OS.get_environment("HARDCORE_REVIEW_HEAD"), "status": status, "detail": detail, "cases": _cases, "failures": _failures, "preflight": _preflight, "trace_limit_per_direction": 1024}
	var path := "res://outputs/m30_r4r2/eight_directions.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("M30_R2 trace could not be written")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("M30_R2_EIGHT_DIRECTIONS_%s %s cases=%d" % [status, detail, _cases.size()])
	get_tree().quit(0 if status == "PASS" else (2 if status == "BLOCKED" else 1))

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual.set_synchronous_loading_for_tests(false)
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await Fixture.wait_for_formal_world(self, _game, "m30_r2_steps")
	MonsterVisual.set_synchronous_loading_for_tests(false)
	_sampler = Sampler.new()
	add_child(_sampler)
	_sampler.after_physics.connect(_physics_sample)
	for value: Node in get_tree().get_nodes_in_group("enemies"):
		value.queue_free()
	await _sampler.after_visual
	await _sampler.after_physics
	_game.player.set_physics_process(false) # Isolated stationary-target fixture only.
	_game.player.max_hp = 999999
	_game.player.current_hp = 999999
	var probe: EnemyActor = _game._spawn_enemy(GameData.get_monster_by_id(MONSTER_ID), _game._canonical_ground_gu_to_screen_px(Fixture.FIXTURE_GROUND_POSITION), false, -1.0, {"respawn_enabled": false, "spawn_slot_id": "test:m30_r2:probe"})
	if not is_instance_valid(probe):
		_finish("FAIL", "preflight_actor_missing")
		return
	var probe_freeze := ArtWaitFreeze.new()
	if not probe_freeze.begin(probe, probe.visual):
		probe.queue_free()
		_finish("FAIL", "preflight_freeze_missing")
		return
	_center = await _verified_center(probe)
	check(probe_freeze.restore(), "preflight scheduling modes restored")
	probe.queue_free()
	await _sampler.after_visual
	await _sampler.after_physics
	if not _center.is_finite():
		_finish("BLOCKED", "no_independently_verified_8way_corridor")
		return
	var completed := 0
	for d: int in range(8):
		if await _run_case(d):
			completed += 1
	check(completed == 8, "8/8 required; no pass-by-skip")
	_finish("PASS" if _failures.is_empty() else "FAIL", "completed=%d/8" % completed)

func _ready() -> void:
	_run.call_deferred()
