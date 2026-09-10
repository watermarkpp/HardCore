extends Node

# Real authored map + natural respawn. This is an observation/integrity fixture,
# never a performance PASS. Run with an isolated user-data directory only.
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const Rules := preload("res://scripts/world_spatial_rules.gd")
const Sampler := preload("res://tests/m30_r4_r2/lab_sampler.gd")
var _game: Node
var _sampler: Node
var _records: Array[Dictionary] = []
var _slot := ""
var _map_id := -1
var _generation := -1
var _key := ""
var _checks: Array[String] = []

func _children() -> Array[EnemyActor]:
	var out: Array[EnemyActor] = []
	for value: Node in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			var e := value as EnemyActor
			if e.monster_id == 127 and e.can_receive_damage() and e.runtime_map_id == _map_id and int(e.get_meta("zone_generation", -1)) == _generation and str(e.get_meta("summoner_spawn_slot", "")) == _slot:
				out.append(e)
	return out

func _has_child_from(source_id: int) -> bool:
	for child: EnemyActor in _children():
		var context: Dictionary = child.get_meta("spawn_context", {})
		if int(context.get("m30_source_instance_id", -1)) == source_id:
			return true
	return false

func _mother(excluded_id: int = 0) -> EnemyActor:
	for value: Node in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			var e := value as EnemyActor
			if e.monster_id == 126 and e.can_receive_damage() and e.runtime_map_id == _map_id and int(e.get_meta("zone_generation", -1)) == _generation and e.get_instance_id() != excluded_id:
				if _slot.is_empty() or str(e.get_meta("spawn_slot_id", "")) == _slot:
					return e
	return null

func _world_unchanged() -> bool:
	return int(_game.current_map_id) == _map_id and int(_game._zone_generation) == _generation

func _window(label: String, seconds: float) -> void:
	var before: Dictionary = _game.hc_m30_summon_snapshot()
	var actors_before := get_tree().get_nodes_in_group("enemies").size()
	_sampler.begin_window()
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and _world_unchanged():
		await _sampler.after_visual
	_sampler.capture = false
	var ids: Array[int] = []
	var starts := 0
	for child: EnemyActor in _children():
		ids.append(child.get_instance_id())
		starts += child._hc_starts
	_records.append({
		"phase": label, "map_id": _map_id, "generation": _generation,
		"owner_slot": _slot, "child_ids": ids, "child_attack_starts_cumulative": starts,
		"world_unchanged": _world_unchanged(),
		"all_enemies_before": actors_before,
		"all_enemies_after": get_tree().get_nodes_in_group("enemies").size(),
		"queue_before": before, "queue_after": _game.hc_m30_summon_snapshot(),
		"process_wall_ms": _sampler.render_intervals_ms.duplicate(),
		"physics_wall_ms": _sampler.physics_intervals_ms.duplicate(),
		"process_summary": Sampler.statistics(_sampler.render_intervals_ms),
		"physics_summary": Sampler.statistics(_sampler.physics_intervals_ms),
	})

func _finish(status: String, reason: String) -> void:
	_sampler.capture = false
	var path := "res://outputs/m30_r4r2/pig_site_%s.json" % _key
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("site evidence write failed")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify({"schema": "m30.r4r2.pig_site.v1", "run_head": OS.get_environment("HARDCORE_REVIEW_HEAD"), "map_key": _key, "map_id": _map_id, "generation": _generation, "slot": _slot, "status": status, "reason": reason, "checks": _checks, "phases": _records, "performance_status": "NOT_RUN", "performance_status_reason": "raw timing observation only; no baseline comparison in this fixture", "gpu_time": "NOT_MEASURED"}, "\t"))
	file.close()
	print("M30_R2_PIG_SITE_%s reason=%s meaning=lifecycle_and_measurement_integrity_not_performance_acceptance" % [status, reason])
	get_tree().quit(0 if status == "PASS" else (2 if status == "BLOCKED" else 1))

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual.set_synchronous_loading_for_tests(false)
	_sampler = Sampler.new()
	add_child(_sampler)
	_key = OS.get_environment("HARDCORE_M30_MAP_KEY")
	if _key.is_empty():
		_key = "mengzhong_stone_tomb_f3"
	if _key not in ["mengzhong_stone_tomb_f3", "mengzhong_stone_tomb_f4"]:
		_key = "invalid"
		_finish("BLOCKED", "unsupported_map_key")
		return
	for mid: int in Bridge.released_map_ids():
		if str(Bridge._release_entry(mid).get("map_key", "")) == _key:
			_map_id = mid
	if _map_id < 0 or not Bridge.is_formal_playable(_map_id):
		_finish("BLOCKED", "map_not_formally_playable")
		return
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	var ready_deadline := Time.get_ticks_msec() + 60000
	while not _game.gameplay_input_is_enabled() and Time.get_ticks_msec() < ready_deadline:
		await _sampler.after_visual
	if not _game.gameplay_input_is_enabled():
		_finish("BLOCKED", "initial_world_not_ready")
		return
	MonsterVisual.set_synchronous_loading_for_tests(false)
	_game.player.max_hp = 999999999
	_game.player.current_hp = 999999999
	_game.travel_to_map(_map_id) # Existing production loading/actor/respawn authority.
	ready_deadline = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < ready_deadline:
		await _sampler.after_visual
		if int(_game.current_map_id) == _map_id and _game.gameplay_input_is_enabled():
			break
	if int(_game.current_map_id) != _map_id or not _game.gameplay_input_is_enabled():
		_finish("BLOCKED", "production_travel_not_ready")
		return
	_generation = int(_game._zone_generation)
	var mother := _mother()
	if not is_instance_valid(mother):
		_finish("BLOCKED", "authored_mother126_missing")
		return
	_slot = str(mother.get_meta("spawn_slot_id", ""))
	var respawn_seconds := float(mother.get_meta("respawn_seconds", 0.0))
	if _slot.is_empty() or not bool(mother.get_meta("respawn_enabled", false)) or respawn_seconds <= 0.0 or respawn_seconds > 650.0:
		_finish("BLOCKED", "natural_respawn_not_available_within_runner_envelope")
		return
	var radius := Rules.actor_combat_radius_gu_from_screen_radius_px(ArtSpec.PLAYER_COLLISION_RADIUS_PX)
	var near: Vector2 = _game._find_valid_enemy_landing(mother.global_position, 2.0, 3.0, radius, null)
	if not near.is_finite() or near == mother.global_position:
		_finish("BLOCKED", "no_legal_nearby_player_position")
		return
	_game._set_player_world_position(near)
	_game.player.set_touch_vector(Vector2.ZERO)
	var old_id := mother.get_instance_id()
	var old_life := int(mother.get_meta("hc_combat_life_epoch", -1))
	_records.append({"phase": "identity", "mother_id": 126, "child_id": 127, "instance_id": old_id, "life": old_life, "respawn_seconds": respawn_seconds, "spawn_context": mother.get_meta("spawn_context", {}), "map_key": _key, "slot": _slot})
	await _window("before_first_kill", 8.0)
	if not is_instance_valid(mother) or not mother.can_receive_damage():
		_finish("FAIL", "mother_died_before_intended_first_kill")
		return
	mother.take_damage(999999999, _game.player, {"source": "m30_r2_site_first_kill"})
	await _window("after_first_kill", 5.0)
	# Do NOT call _respawn_later manually, change time_scale, or alter policy data.
	var respawn_deadline := Time.get_ticks_msec() + int((respawn_seconds + 45.0) * 1000.0)
	var second: EnemyActor
	while Time.get_ticks_msec() < respawn_deadline and _world_unchanged():
		second = _mother(old_id)
		if is_instance_valid(second):
			break
		await _sampler.after_visual
	if not is_instance_valid(second) or not _world_unchanged():
		_finish("FAIL", "natural_respawn_not_observed")
		return
	_records.append({"phase": "natural_respawn", "instance_id": second.get_instance_id(), "life": second.get_meta("hc_combat_life_epoch", -1), "spawn_slot": second.get_meta("spawn_slot_id", "")})
	var births_deadline := Time.get_ticks_msec() + 25000
	while is_instance_valid(second) and (_children().size() < 3 or not _has_child_from(second.get_instance_id())) and Time.get_ticks_msec() < births_deadline and _world_unchanged():
		await _sampler.after_visual
	if not is_instance_valid(second) or _children().size() < 3 or not _has_child_from(second.get_instance_id()):
		# Evidence-only adaptation (no assertion change): capture the births
		# window's queue state and child attribution on the failure path so the
		# report can list starts/queue diagnostics as the execution order
		# requires. Same assertions, same thresholds.
		_records.append({
			"phase": "births_failure_diagnostic",
			"queue_after_births_window": _game.hc_m30_summon_snapshot(),
			"children_observed": _children().size(),
			"child_meta_samples": _children().slice(0, 5).map(func(child: EnemyActor) -> Dictionary:
				return {
					"instance_id": child.get_instance_id(),
					"summoner_spawn_slot": str(child.get_meta("summoner_spawn_slot", "")),
					"spawn_context": child.get_meta("spawn_context", {}),
					"position_gu": [child.global_position.x, child.global_position.y],
				}),
			"second_mother": {
				"instance_id": second.get_instance_id() if is_instance_valid(second) else -1,
				"summon_rule": second.get_meta("m30_summon_rule", second.get("summon_rule")) if is_instance_valid(second) else {},
				"summon_cooldown": second.get("_summon_cooldown") if is_instance_valid(second) else -1.0,
				"summon_warning": second.get("_summon_warning") if is_instance_valid(second) else -1.0,
				"position_gu": [second.global_position.x, second.global_position.y] if is_instance_valid(second) else [],
			},
		})
		_finish("FAIL", "missing_three_children_or_new_life_birth")
		return
	await _window("respawned_mother_with_children", 12.0)
	var survivors: Array[EnemyActor] = _children()
	if not is_instance_valid(second) or not second.can_receive_damage():
		_finish("FAIL", "second_mother_not_alive_at_second_kill")
		return
	second.take_damage(999999999, _game.player, {"source": "m30_r2_site_second_kill"})
	await _window("after_second_kill_same_children", 12.0)
	for child: EnemyActor in survivors:
		if not is_instance_valid(child) or not child.can_receive_damage():
			_finish("FAIL", "surviving_child_lost_after_mother_death")
			return
	var queue: Dictionary = _game.hc_m30_summon_snapshot()
	if int(queue.get("max_probes_in_tick", 999)) > 8 or int(queue.get("max_materializations_in_tick", 999)) > 1:
		_finish("FAIL", "global_queue_budget_violation")
		return
	if int((queue.get("reserved_by_slot", {}) as Dictionary).get(_slot, 0)) != 0:
		_finish("FAIL", "dead_mother_slot_still_reserved")
		return
	if not _world_unchanged() or _game.player.current_hp <= 0:
		_finish("FAIL", "world_or_player_state_changed")
		return
	_checks.append("natural production death->respawn->second death observed; no authored actors removed")
	_finish("PASS", "site_lifecycle_observed_raw_performance_requires_comparison")

func _ready() -> void:
	_run.call_deferred()
