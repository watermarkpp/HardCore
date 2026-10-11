extends "res://tests/framework/v110_aura_natural_motion_test.gd"

const Budget := preload("res://scripts/monster_ai_package/decision_budget.gd")
@export var ID := "v111_crowd_service_test"
@export var process_cap := 60
@export var cohort_target := 30
var maximum_ready_lateness_s := 0.0
var maximum_pending_wait_usec := 0
var maximum_lateness_witness: Dictionary = {}
var cpu_monitor_samples: Array[Dictionary] = []
var records: Array[Dictionary] = []
var windows: Array[Dictionary] = []
var elapsed_s := 0.0

func _ready() -> void:
	await get_tree().process_frame
	Engine.max_fps = process_cap
	await _bootstrap_formal_world()
	if not is_instance_valid(_game) or not is_instance_valid(_game.player):
		finish_capture()
		return
	await _prepare_dense_cold_cohort()
	proof.record(_actors.size() == cohort_target, "full requested real-map mobile cohort retained")
	if _actors.size() != cohort_target:
		finish_capture()
		return
	var player: PlayerCharacter = _game.player
	# Target survival is fixture-only; no actor HP, speeds or attack gates changed.
	player.max_hp = 1000000
	player.current_hp = 1000000
	Budget.configure_pursuit_process_trace(true)
	await _trigger_natural_wake()
	var anchor: Vector2 = _game._canonical_screen_px_to_ground_gu(player.global_position)
	var last_positions: Array[Vector2] = []
	var last_served: Array[int] = []
	for actor: EnemyActor in _actors:
		last_positions.append(actor.spatial_index_position())
		last_served.append(actor._owner_decision_served_physics_tick)
	for section: int in 7:
		var rows: Array[Dictionary] = []
		for ordinal: int in _actors.size():
			rows.append({"ordinal": ordinal, "monster_id": _actors[ordinal].monster_id, "distance_gu": 0.0, "served_windows": 0, "moving_frames": 0, "distant_still_frames": 0, "reasons": {}})
		var before_grants: int = Budget._p_grants
		for frame: int in 120:
			await get_tree().physics_frame
			elapsed_s += 1.0 / float(Engine.physics_ticks_per_second)
			for ordinal: int in _actors.size():
				var actor := _actors[ordinal]
				if actor._owner_decision_next_time_s >= 0.0 and actor._hc_owner_optional_budget_runnable():
					var lateness := actor._combat_action_time_s - actor._owner_decision_next_time_s
					if lateness > maximum_ready_lateness_s:
						maximum_ready_lateness_s = lateness
						maximum_lateness_witness = {"actor": _state(actor), "elapsed_s": elapsed_s, "pending_queue": Budget._p_requests.has(actor.get_instance_id()), "last_owner_call_tick": actor._owner_decision_last_physics_tick, "physics_tick": Engine.get_physics_frames(), "attack_active": actor._attack_action_active, "attack_pending": actor._pending_attack_time, "attack_timer": actor._attack_timer, "control": actor.control_time, "struck": actor.visual.is_struck_action_active() if actor.visual != null else false, "player_ground": [_game._canonical_screen_px_to_ground_gu(player.global_position).x, _game._canonical_screen_px_to_ground_gu(player.global_position).y], "actor_ground": [actor.spatial_index_position().x, actor.spatial_index_position().y]}
				# A cheap eligible actor can legitimately be at COOLDOWN_HOLD with
				# no planning request. Measure continuous runnable demand from the
				# actual queue timestamp, not an obsolete pre-attack decision date.
				var pending: Dictionary = Budget._p_requests.get(actor.get_instance_id(), {})
				if not pending.is_empty() and actor._hc_owner_optional_budget_runnable():
					maximum_pending_wait_usec = maxi(maximum_pending_wait_usec, Time.get_ticks_usec() - int(pending.queued_usec))
				var pos := actor.spatial_index_position()
				var moved := pos.distance_to(last_positions[ordinal])
				last_positions[ordinal] = pos
				var row: Dictionary = rows[ordinal]
				row.distance_gu = float(row.distance_gu) + moved
				if moved > 0.0001: row.moving_frames = int(row.moving_frames) + 1
				if actor._owner_decision_served_physics_tick != last_served[ordinal]:
					row.served_windows = int(row.served_windows) + 1
					last_served[ordinal] = actor._owner_decision_served_physics_tick
				var distance := pos.distance_to(_game._canonical_screen_px_to_ground_gu(player.global_position))
				if moved <= 0.0001 and distance > 2.5: row.distant_still_frames = int(row.distant_still_frames) + 1
				row.reasons[actor._hc_last_reason] = int(row.reasons.get(actor._hc_last_reason, 0)) + 1
			var wake_before_signal: Dictionary = _game.get_meta("crowd_diag_wake", {})
			var current: Vector2 = _game._canonical_screen_px_to_ground_gu(player.global_position)
			var point := anchor + Vector2(1.5 + sin(elapsed_s * 0.7) * 1.25, 0.0)
			var direction: Vector2 = point - current
			var steering: Vector2 = FixtureDirection(direction)
			var desired_screen: Vector2 = _game._canonical_ground_gu_to_screen_px(point)
			if not desired_screen.is_finite() or not _actors[0]._hc_point_walkable(point) or _actors[0]._point_inside_safe_zone(desired_screen):
				steering = Vector2.ZERO
			player.set_touch_vector(steering)
			if frame % 30 == 29:
				cpu_monitor_samples.append({"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, "physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0})
				var previous_budget: Dictionary = {"epoch": FrameBudget._epoch, "spent_usec": FrameBudget._spent_usec, "categories": FrameBudget._categories.duplicate(true)}
				var states: Array[Dictionary] = []
				for actor: EnemyActor in _actors:
					var state := _state(actor)
					state["next_due_s"] = actor._owner_decision_next_time_s
					state["served_tick"] = actor._owner_decision_served_physics_tick
					state["ground"] = [actor.spatial_index_position().x, actor.spatial_index_position().y]
					states.append(state)
				records.append({"wake_before_signal": wake_before_signal, "wake_boundary": _game.get_meta("crowd_diag_wake", {}), "second": elapsed_s, "budget": Budget.pursuit_process_snapshot(), "previous_frame_budget": previous_budget, "frame_budget": FrameBudget.snapshot(), "actors": states, "player_hp": player.current_hp, "actual_player_safe": _actors[0]._point_inside_safe_zone(player.global_position), "process_cap": process_cap, "player_ground": [current.x, current.y], "desired_ground": [point.x, point.y], "touch_vector": [steering.x, steering.y], "player_actual_ground_motion": [player.actual_ground_motion_gu.x, player.actual_ground_motion_gu.y]})
		windows.append({"seconds": elapsed_s, "owner_grants": Budget._p_grants - before_grants, "actors": rows})
		print("WORLD_CROWD_WINDOW second=%.1f grants=%d first_distance=%.3f" % [elapsed_s, Budget._p_grants - before_grants, float(rows[0].distance_gu)])
	finish_capture()

func FixtureDirection(direction: Vector2) -> Vector2:
	if direction.length() < 0.15: return Vector2.ZERO
	return Vector2((direction.x - direction.y) * 32.0, (direction.x + direction.y) * 16.0).normalized()

func finish_capture() -> void:
	if is_instance_valid(_game) and is_instance_valid(_game.player): _game.player.set_touch_vector(Vector2.ZERO)
	proof.record(windows.size() == 7 and records.size() == 28, "all fourteen seconds and 28 half-second observations captured")
	proof.record(maximum_pending_wait_usec <= 300000, "continuously queued runnable work cannot wait another 300ms decision period")
	var maximum_queue_wait := 0
	for sample: Dictionary in records:
		proof.record(sample.actors.size() == cohort_target and not sample.actual_player_safe, "full cohort and unprotected target remain in the real map")
		for actor_state: Dictionary in sample.actors:
			proof.record(actor_state.hp > 0 and actor_state.target != 0 and not actor_state.sleep, "tracked actor retains life, target and active processing")
		var state: Dictionary = sample.budget
		maximum_queue_wait = maxi(maximum_queue_wait, int(state.wait_usec_max))
		for request: Dictionary in state.queue:
			maximum_queue_wait = maxi(maximum_queue_wait, int(request.wait_usec))
	proof.record(maximum_queue_wait <= 300000, "served and still-queued requests remain below 300ms, not just first movement")
	for window: Dictionary in windows:
		var total_motion := 0.0
		for row: Dictionary in window.actors:
			# Count the actor's completed observation/decision marker, not grants.
			proof.record(int(row.served_windows) >= 3, "every actor including the original cohort continues useful service each two-second window")
			total_motion += float(row.distance_gu)
		proof.record(total_motion > 0.02, "cohort continues actual physics pursuit in every window")
	_evidence["maximum_ready_lateness_s"] = maximum_ready_lateness_s
	_evidence["maximum_pending_wait_usec"] = maximum_pending_wait_usec
	_evidence["maximum_lateness_witness"] = maximum_lateness_witness
	_evidence["maximum_observed_queue_wait_usec"] = maximum_queue_wait
	_evidence["cpu_monitor_samples"] = cpu_monitor_samples
	_evidence["cohort_target"] = cohort_target
	for text: String in _failures: proof.record(false, text)
	var output := FileAccess.open("res://outputs/test_logs/framework/" + ID + ".observations.json", FileAccess.WRITE)
	proof.record(output != null, "full map sustained output opens")
	if output != null:
		output.store_string(JSON.stringify({"scope": "real Bich GameRoot; requested cohort recorded in setup;14s sustained naturalphysics; production PlayerCharacter.set_touch_vector, actual move_and_collide and movement signal only after initial setup; fixture-only high target HP; not phone FPS", "windows": windows, "samples": records, "setup": _evidence, "source_binding": OS.get_environment("HARDCORE_R3_CONTENT_SHA256")}, "  "))
		output.close()
	var failures := 0
	for row: Dictionary in proof.records:
		if not bool(row.passed): failures += 1
	var ok: bool = proof.write_receipt(ID, proof.records.size(), failures)
	print("V111_CROWD_SERVICE_%s sustained_acceptance=true" % ["PASS" if ok else "FAIL"])
	for actor: EnemyActor in _actors:
		if is_instance_valid(actor): actor._owner_optional_budget_end()
	get_tree().quit(0 if ok else 1)


# Same canonical placement gates, with an explicit requested load. Never silently reduce it.
func _prepare_dense_cold_cohort() -> void:
	if _game == null or not is_instance_valid(_game.player):
		return
	var player: PlayerCharacter = _game.player as PlayerCharacter
	var player_ground: Vector2 = _game._canonical_screen_px_to_ground_gu(player.global_position)
	if not player_ground.is_finite():
		_failures.append("player_ground_nonfinite")
		return
	var candidates: Array[Vector2] = []
	for radius: float in [2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5]:
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(), Vector2(-1, -1).normalized(), Vector2(1, -1).normalized()]:
			candidates.append(player_ground + axis * radius)
	var anchor_probe: EnemyActor = null
	for raw_probe: Variant in _game._active_enemy_cache.values():
		if raw_probe is EnemyActor and not (raw_probe as EnemyActor).is_boss:
			anchor_probe = raw_probe as EnemyActor
			break
	if anchor_probe == null:
		_failures.append("no_anchor_probe_enemy")
		return
	var player_anchor := Vector2.INF
	for radius: float in range(0, 31):
		for offset: Vector2 in [Vector2(radius, 0.0), Vector2(-radius, 0.0), Vector2(0.0, radius), Vector2(0.0, -radius)]:
			var point := player_ground + offset
			var point_screen: Vector2 = _game._canonical_ground_gu_to_screen_px(point)
			if point_screen.is_finite() and anchor_probe._hc_point_walkable(point) and not anchor_probe._point_inside_safe_zone(point_screen):
				player_anchor = point
				break
		if player_anchor.is_finite():
			break
	if not player_anchor.is_finite():
		_failures.append("no_non_safe_anchor_in_formal_map")
		return
	player_ground = player_anchor
	player.global_position = _game._canonical_ground_gu_to_screen_px(player_ground)
	player.movement_performed.emit(player.global_position, player.facing)
	candidates.clear()
	for radius: float in [2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5]:
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(), Vector2(-1, -1).normalized(), Vector2(1, -1).normalized()]:
			candidates.append(player_ground + axis * radius)
	var used_points: Dictionary = {}
	for raw: Variant in _game._active_enemy_cache.values():
		if _actors.size() >= cohort_target:
			break
		if not raw is EnemyActor:
			continue
		var actor: EnemyActor = raw as EnemyActor
		if not is_instance_valid(actor) or actor.is_boss or not actor._source176_ordinary_melee() or actor.stationary or actor.move_speed_gu_per_sec <= 0.0:
			continue
		if actor.current_hp <= 20 or actor.passive_acquisition_extent_gu() <= 0.0:
			continue
		var chosen := Vector2.INF
		var original_position: Vector2 = actor.global_position
		for point: Vector2 in candidates:
			if used_points.has(point):
				continue
			var screen: Vector2 = _game._canonical_ground_gu_to_screen_px(point)
			if not screen.is_finite():
				continue
			if point.distance_to(player_ground) > actor.passive_acquisition_extent_gu():
				continue
			if not actor._hc_point_walkable(point):
				continue
			if actor._point_inside_safe_zone(player.global_position):
				continue
			actor.set_combat_position(screen, &"dense_wake_fixture_probe")
			if not actor._initial_acquisition_static_los_clear(player):
				actor.set_combat_position(original_position, &"dense_wake_fixture_probe_revert")
				continue
			chosen = point
			break
		if not chosen.is_finite():
			continue
		actor.set_combat_position(_game._canonical_ground_gu_to_screen_px(chosen), &"dense_wake_fixture")
		used_points[chosen] = true
		actor.set_meta("spawn_position", actor.global_position)
		actor.set_meta("zone_generation", _game._zone_generation)
		actor._hc_forget(actor.target)
		actor.target = null
		actor._threat_table.clear()
		actor._hc_damage_dirty = false
		actor._clear_passive_wake()
		actor._enter_background_deep_sleep(true)
		_actors.append(actor)
	_evidence["setup"] = {
		"map_id": _game.current_map_id,
		"generation": _game._zone_generation,
		"player_ground": [player_ground.x, player_ground.y],
		"cohort_requested": cohort_target,
		"cohort_prepared": _actors.size(),
		"nonstealth_player": not player.is_stealthed(),
	}
	if player.is_stealthed():
		_failures.append("player_stealthed_setup")
