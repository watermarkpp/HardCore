extends "res://tests/passive_wake_natural_dense_repair_20261009.gd"

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "v110_aura_natural_motion_test"
var proof := Proof.new()
var starts: Dictionary = {}
var motion: Dictionary = {}
var reasons: Dictionary = {}
var first_motion: Dictionary = {}
var setup_rows: Array = []

func _ready() -> void:
	await get_tree().process_frame
	await _bootstrap_formal_world()
	if not is_instance_valid(_game) or not is_instance_valid(_game.player):
		_complete()
		return
	await _prepare_dense_cold_cohort()
	proof.record(_actors.size() == COHORT_SIZE, "real map admits full 30-actor cold cohort")
	for actor: EnemyActor in _actors:
		var id := actor.get_instance_id()
		starts[id] = actor.spatial_index_position()
		motion[id] = 0.0
		reasons[id] = {}
		setup_rows.append(_state(actor))
	await _trigger_natural_wake()
	for frame: int in 180:
		await get_tree().physics_frame
		for actor: EnemyActor in _actors:
			if not is_instance_valid(actor):
				continue
			var id := actor.get_instance_id()
			var displacement: float = actor.spatial_index_position().distance_to(starts[id])
			motion[id] = maxf(float(motion[id]), displacement)
			if displacement > 0.02 and not first_motion.has(id):
				first_motion[id] = frame
			var reason: String = actor._hc_last_reason
			var counts: Dictionary = reasons[id]
			counts[reason] = int(counts.get(reason, 0)) + 1
	_evidence["initial_actor_states"] = setup_rows
	var rows: Array = []
	var moving := 0
	for actor: EnemyActor in _actors:
		if not is_instance_valid(actor):
			proof.record(false, "actor must survive the non-attacking lure test")
			continue
		var id := actor.get_instance_id()
		var row := _state(actor)
		row["maximum_displacement_gu"] = motion[id]
		row["first_motion_physics_frame"] = first_motion.get(id, -1)
		row["reason_counts"] = reasons[id]
		rows.append(row)
		if float(motion[id]) > 0.02:
			moving += 1
	_evidence["natural_physics_frames"] = 180
	_evidence["motion_results"] = rows
	_evidence["moving_actors"] = moving
	# This first reproduction records congestion as a separate possible cause;
	# the final sparse-species test will isolate first-motion permission.
	proof.record(moving == _actors.size(), "all 30 mobile actors make real pursuit progress within 180 natural physics ticks")
	for failure: String in _failures:
		proof.record(false, failure)
	_complete()

func _state(actor: EnemyActor) -> Dictionary:
	return {"instance_id": actor.get_instance_id(), "monster_id": actor.monster_id,
		"source176": actor._source176_ordinary_melee(), "hc_melee": actor._hc_standard_melee(),
		"hp": actor.current_hp, "stationary": actor.stationary, "dormant": actor.dormant,
		"speed_gu_s": actor.move_speed_gu_per_sec, "sleep": actor._background_deep_sleeping,
		"target": actor.target.get_instance_id() if is_instance_valid(actor.target) else 0,
		"observed": actor._hc_observed, "known_target_id": actor._hc_known_target_id,
		"known_ground_finite": actor._hc_known_ground.is_finite(),
		"movement_active": actor._movement_step_active, "pursuit_session": actor._hc_pursuit_session,
		"authority_rejected": actor._movement_authority_failed_closed,
		"owner_interval_ms": actor._owner_decision_interval_ms,
		"owner_next_time_s": actor._owner_decision_next_time_s,
		"combat_time_s": actor._combat_action_time_s,
		"budget_mode": actor._pursuit_process_budget_mode,
		"reason": actor._hc_last_reason}

func _complete() -> void:
	for actor: EnemyActor in _actors:
		if is_instance_valid(actor): actor._owner_optional_budget_end()
	_evidence["framework_source"] = OS.get_environment("HARDCORE_R3_CONTENT_SHA256")
	_evidence["status"] = "PASS" if _failures.is_empty() and int(_evidence.get("moving_actors", -1)) == COHORT_SIZE else "FAIL"
	var output := FileAccess.open("res://outputs/test_logs/framework/" + SCENE_ID + ".observations.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(_evidence, "  "))
		output.close()
	var failed_checks := 0
	for row: Dictionary in proof.records:
		if not bool(row.passed): failed_checks += 1
	var ok: bool = proof.write_receipt(SCENE_ID, proof.records.size(), failed_checks)
	print("V110_AURA_NATURAL_MOTION_%s moving=%d total=%d" % ["PASS" if ok else "FAIL", int(_evidence.get("moving_actors", -1)), _actors.size()])
	get_tree().quit(0 if ok else 1)

# Select thirty genuinely mobile actors; stationary flora retains its own contract.
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
		if _actors.size() >= COHORT_SIZE:
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
		"cohort_requested": COHORT_SIZE,
		"cohort_prepared": _actors.size(),
		"nonstealth_player": not player.is_stealthed(),
	}
	if player.is_stealthed():
		_failures.append("player_stealthed_setup")
