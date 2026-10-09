extends Node

const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")

const COHORT_SIZE := 12
const MAX_DAMAGE_FRAMES := 180

var _game: Node
var _actors: Array[EnemyActor] = []
var _failures: Array[String] = []
var _evidence: Dictionary = {"status": "NOT_RUN", "frames": [], "actors": []}
var _damage_before: Dictionary = {}

func _ready() -> void:
	await get_tree().process_frame
	await _bootstrap_formal_world()
	if _game == null:
		_finish()
		return
	await _prepare_dense_cold_cohort()
	if _actors.size() < COHORT_SIZE:
		_failures.append("cohort_setup:%d/%d" % [_actors.size(), COHORT_SIZE])
	else:
		await _trigger_natural_wake()
		await _trigger_real_nonlethal_ground_tick()
		await _wait_for_damage_recovery()
	_finish()

func _bootstrap_formal_world() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	for _frame: int in 1200:
		await get_tree().process_frame
		if not _game._world_bootstrap_in_progress and not _game._map_transition_in_progress:
			break
	if not is_instance_valid(_game.player):
		_failures.append("formal_player_missing")
	if not _game.gameplay_input_is_enabled():
		_failures.append("formal_bootstrap_incomplete")

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
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
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
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			candidates.append(player_ground + axis * radius)
	var used_points: Dictionary = {}
	for raw: Variant in _game._active_enemy_cache.values():
		if _actors.size() >= COHORT_SIZE:
			break
		if not raw is EnemyActor:
			continue
		var actor: EnemyActor = raw as EnemyActor
		if not is_instance_valid(actor) or actor.is_boss or not actor._source176_ordinary_melee():
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

func _trigger_natural_wake() -> void:
	# A real player movement signal re-arms the central coordinator. We do not
	# call GameRoot's wake pump or any Enemy wake method directly.
	var player: PlayerCharacter = _game.player as PlayerCharacter
	var before: Vector2 = player.global_position
	var started_usec: int = Time.get_ticks_usec()
	player.global_position = before + Vector2(0.01, 0.0)
	player.movement_performed.emit(player.global_position, player.facing)
	# The new contract is immediate activation on the next actual GameRoot
	# process callback. Await exactly one process signal; do not drain a long
	# pagination window and call a late PASS equivalent.
	await get_tree().process_frame
	_record_frame(1, "wake")
	var target_count: int = _target_count()
	_evidence["wake_target_counts"] = [{"process_frame": 1, "target_count": target_count, "cohort": _actors.size()}]
	_evidence["wake_elapsed_usec"] = Time.get_ticks_usec() - started_usec
	if target_count == _actors.size():
		_evidence["wake_complete_frame"] = 1
	else:
		_failures.append("halo_not_immediate:%d/%d" % [target_count, _actors.size()])

func _trigger_real_nonlethal_ground_tick() -> void:
	# This is the production canonical field callback. Use a small positive
	# power so actors remain alive and the damage-driven wake can be observed.
	# Re-enter the real cold state so the damage phase cannot pass merely because
	# the halo phase already left a target attached.
	for actor: EnemyActor in _actors:
		if not is_instance_valid(actor):
			continue
		actor._hc_forget(actor.target)
		actor.target = null
		actor._threat_table.clear()
		actor._hc_damage_dirty = false
		actor._clear_passive_wake()
		actor._enter_background_deep_sleep(true)
	var powers: Dictionary = {}
	for actor: EnemyActor in _actors:
		if is_instance_valid(actor) and actor.current_hp > 4:
			var raw_power: int = maxi(8, mini(24, actor.current_hp / 4))
			powers[str(actor.get_instance_id())] = raw_power
			_damage_before[actor.get_instance_id()] = actor.current_hp
			_game._apply_canonical_ground_tick(actor, raw_power, "wizard.fire_wall")
			if actor.current_hp >= int(_damage_before[actor.get_instance_id()]):
				_failures.append("ground_tick_no_hp_loss:%d" % actor.get_instance_id())
	var immediate_target_count: int = _target_count()
	_evidence["ground_tick"] = {"callback": "GameRoot._apply_canonical_ground_tick", "powers": powers,
		"immediate_target_count": immediate_target_count, "cohort": _actors.size()}
	if immediate_target_count != _actors.size():
		_failures.append("ground_tick_not_immediate:%d/%d" % [immediate_target_count, _actors.size()])

func _wait_for_damage_recovery() -> void:
	for frame: int in MAX_DAMAGE_FRAMES:
		await get_tree().process_frame
		_record_frame(frame, "damage")
		var all_dirty_or_target := true
		for actor: EnemyActor in _actors:
			if is_instance_valid(actor) and actor.current_hp > 0:
				if not actor._hc_damage_dirty and not is_instance_valid(actor.target):
					all_dirty_or_target = false
		if all_dirty_or_target and _all_have_target():
			_evidence["damage_recovery_frame"] = frame
			return
	_failures.append("damage_wake_or_retarget_timeout")

func _all_have_target() -> bool:
	return _target_count() == _actors.size()

func _target_count() -> int:
	var count := 0
	for actor: EnemyActor in _actors:
		if is_instance_valid(actor) and actor.current_hp > 0 and is_instance_valid(actor.target):
			count += 1
	return count

func _record_frame(frame: int, phase: String) -> void:
	var row: Dictionary = {"phase": phase, "frame": frame,
		"process_epoch": Engine.get_process_frames(),
		"frame_budget": FrameBudget.snapshot()}
	var states: Array[Dictionary] = []
	for actor: EnemyActor in _actors:
		if not is_instance_valid(actor):
			states.append({"valid": false})
			continue
		states.append({
			"id": actor.get_instance_id(), "hp": actor.current_hp,
			"sleep": actor._background_deep_sleeping,
			"physics": actor.is_physics_processing(),
			"wake_pending": actor._passive_wake_pending,
			"damage_dirty": actor._hc_damage_dirty,
			"target": actor.target.get_instance_id() if is_instance_valid(actor.target) else 0,
		})
	row["actors"] = states
	_evidence["frames"].append(row)

func _finish() -> void:
	for actor: EnemyActor in _actors:
		if is_instance_valid(actor):
			actor._owner_optional_budget_end()
	_evidence["actors"] = _actors.map(func(actor: EnemyActor) -> Dictionary:
		if not is_instance_valid(actor): return {"valid": false}
		return {"id": actor.get_instance_id(), "hp": actor.current_hp,
			"target": actor.target.get_instance_id() if is_instance_valid(actor.target) else 0,
			"sleep": actor._background_deep_sleeping, "damage_dirty": actor._hc_damage_dirty}
	)
	_evidence["failures"] = _failures
	_evidence["status"] = "PASS" if _failures.is_empty() else "FAIL"
	var output_path := OS.get_environment("HARDCORE_DENSE_WAKE_OUTPUT").strip_edges()
	if output_path.is_empty():
		output_path = "res://outputs/test_logs/passive_wake_natural_dense_repair_20261009.json"
	var out := FileAccess.open(output_path, FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(_evidence, "\t"))
	if _failures.is_empty():
		print("HC_PASSIVE_WAKE_NATURAL_DENSE_REPAIR_20261009_PASS")
	else:
		for failure: String in _failures:
			print("HC_TEST_FAIL ", failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
