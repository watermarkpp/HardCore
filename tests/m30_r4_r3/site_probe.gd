extends Node

# Real authored map + natural respawn. This is an observation/integrity fixture,
# never a performance PASS. Run with an isolated user-data directory only.
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const Rules := preload("res://scripts/world_spatial_rules.gd")
const Sampler := preload("res://tests/m30_r4_r2/lab_sampler.gd")
const Inspector := preload("res://tests/m30_r4_r3/site_inspector.gd")
const SurvivalGuard := preload("res://tests/m30_r4_r3/survival_guard.gd")
var _guard
var _finished: bool = false
var _watching: bool = false
var _phase: String = "bootstrap"
var _mode: String = "preflight"
var _survival: String = "observe"
var _next_diagnostic_ms: int = 0
var _diagnostics: Array[Dictionary] = []
var _profile_records: Array[Dictionary] = []
var _signal_counts: Dictionary = {}
var _observed_sources: Dictionary = {}
var _muted_ref: WeakRef
var _muted_requests: int = 0
var _receiver_ablated: bool = false
var _latest_snapshot: Dictionary = {}
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
	_phase = label
	var before: Dictionary = _game.hc_m30_summon_snapshot()
	var actors_before := get_tree().get_nodes_in_group("enemies").size()
	_sampler.begin_window()
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and _world_unchanged():
		await _tick()
		if _finished:
			return
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
	if _finished:
		return
	_finished = true
	if is_instance_valid(_sampler):
		_sampler.capture = false
	var guard_data: Dictionary = _guard.snapshot() if _guard != null else {"enabled": false}
	_restore_receiver()
	if _guard != null:
		_guard.detach()
	if PlayerState.profile_changed.is_connected(_on_profile_changed):
		PlayerState.profile_changed.disconnect(_on_profile_changed)
	var tag := OS.get_environment("HARDCORE_M30_RUN_TAG")
	if not tag.is_valid_identifier():
		tag = "manual_%d" % Time.get_ticks_usec()
	var path := "res://outputs/m30_r4r3/pig_%s_%s_%s_%s.json" % [_key, _mode, _survival, tag]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("site evidence write failed")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify({
		"schema": "m30.r4r3.pig_site.v1", "run_head": OS.get_environment("HARDCORE_REVIEW_HEAD"),
		"map_key": _key, "map_id": _map_id, "generation": _generation, "slot": _slot,
		"status": status, "reason": reason, "mode": _mode, "survival_mode": _survival,
		"checks": _checks, "phases": _records, "diagnostics": _diagnostics,
		"profile_events_after_production_recalculation": _profile_records,
		"observed_producer_signals_by_instance": _signal_counts,
		"last_diagnostic": _latest_snapshot, "survival_guard": guard_data,
		"receiver_ablation_enabled": _receiver_ablated, "receiver_intercepted_requests": _muted_requests,
		"performance_status": "NOT_RUN", "performance_status_reason": "instrumented lifecycle observation only, not a performance gate",
		"gpu_time": "NOT_MEASURED", "natural_respawn_tested": _mode == "natural" and status == "PASS"
	}, "\t"))
	file.close()
	print("M30_R3_PIG_%s reason=%s mode=%s survival=%s meaning=fixture_or_lifecycle_not_performance" % [status, reason, _mode, _survival])
	get_tree().quit(0 if status == "PASS" else (2 if status == "BLOCKED" else 1))


func _run() -> void:
	_mode = OS.get_environment("HARDCORE_M30_PROBE_MODE")
	if _mode.is_empty():
		_mode = "preflight"
	_survival = OS.get_environment("HARDCORE_M30_SURVIVAL")
	if _survival.is_empty():
		_survival = "observe"
	if _mode not in ["preflight", "natural"] or _survival not in ["observe", "guarded"]:
		_key = "invalid"
		_finish("BLOCKED", "invalid_probe_mode")
		return
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
		await _tick()
		if _finished:
			return
	if not _game.gameplay_input_is_enabled():
		_finish("BLOCKED", "initial_world_not_ready")
		return
	MonsterVisual.set_synchronous_loading_for_tests(false)
	# Connect after production Player._ready; record profile-reset evidence BEFORE
	# the optional guard repairs the explicitly requested lab survival margin.
	PlayerState.profile_changed.connect(_on_profile_changed)
	if _survival == "guarded":
		_guard = SurvivalGuard.new()
		if not _guard.attach(_game.player):
			_finish("BLOCKED", "cannot_arm_lab_survival_guard")
			return
	else:
		_game.player.max_hp = SurvivalGuard.HP_MARGIN
		_game.player.current_hp = SurvivalGuard.HP_MARGIN
	_game.travel_to_map(_map_id) # Existing production loading/actor/respawn authority.
	ready_deadline = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < ready_deadline:
		await _tick()
		if _finished:
			return
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
	_watching = true
	_collect_diagnostic(true)
	var initial_issue := _player_precondition_issue()
	if not initial_issue.is_empty():
		_finish("BLOCKED", initial_issue)
		return
	var old_id := mother.get_instance_id()
	var old_life := int(mother.get_meta("hc_combat_life_epoch", -1))
	_records.append({"phase": "identity", "mother_id": 126, "child_id": 127, "instance_id": old_id, "life": old_life, "respawn_seconds": respawn_seconds, "spawn_context": mother.get_meta("spawn_context", {}), "map_key": _key, "slot": _slot})
	await _window("before_first_kill", 8.0)
	if _finished:
		return
	if not is_instance_valid(mother) or not mother.can_receive_damage():
		_finish("FAIL", "mother_died_before_intended_first_kill")
		return
	if _children().is_empty():
		_collect_diagnostic(true)
		_finish("FAIL", "first_life_producer_or_acquisition_failed_see_diagnostic")
		return
	mother.take_damage(999999999, _game.player, {"source": "m30_r3_site_first_kill"})
	await _window("after_first_kill", 5.0)
	if _finished:
		return
	_collect_diagnostic(true)
	if _mode == "preflight":
		if is_instance_valid(mother) and mother.can_receive_damage():
			_finish("FAIL", "first_kill_not_committed")
		else:
			_checks.append("short fixture survived first production kill/profile settlement; natural respawn NOT_RUN")
			_finish("PASS", "short_preflight_only_natural_respawn_not_run")
		return
	_phase = "natural_respawn_wait"
	# Do NOT call _respawn_later manually, change time_scale, or alter policy data.
	var respawn_deadline := Time.get_ticks_msec() + int((respawn_seconds + 45.0) * 1000.0)
	var second: EnemyActor
	while Time.get_ticks_msec() < respawn_deadline and _world_unchanged():
		second = _mother(old_id)
		if is_instance_valid(second):
			break
		await _tick()
		if _finished:
			return
	if not is_instance_valid(second) or not _world_unchanged():
		_finish("FAIL", "natural_respawn_not_observed")
		return
	_records.append({"phase": "natural_respawn", "instance_id": second.get_instance_id(), "life": second.get_meta("hc_combat_life_epoch", -1), "spawn_slot": second.get_meta("spawn_slot_id", "")})
	_phase = "second_life_birth_window"
	_collect_diagnostic(true)
	var births_deadline := Time.get_ticks_msec() + 25000
	while is_instance_valid(second) and (_children().size() < 3 or not _has_child_from(second.get_instance_id())) and Time.get_ticks_msec() < births_deadline and _world_unchanged():
		await _tick()
		if _finished:
			return
	if not is_instance_valid(second) or _children().size() < 3 or not _has_child_from(second.get_instance_id()):
		_collect_diagnostic(true)
		_finish("FAIL", "missing_three_children_or_new_life_birth_see_upstream_diagnostic")
		return
	await _window("respawned_mother_with_children", 12.0)
	if _finished:
		return
	if OS.get_environment("HARDCORE_M30_RECEIVER_ABLATION") == "1":
		if not _mute_receiver(second):
			_finish("BLOCKED", "exact_receiver_connection_not_found")
			return
		await _window("alive_mother_receiver_muted_children_retained", 8.0)
		if _finished:
			return
		_restore_receiver()
		if _muted_requests == 0:
			_collect_diagnostic(true)
			_finish("FAIL", "receiver_ablation_saw_no_producer_signal")
			return
	var survivors: Array[EnemyActor] = _children()
	if not is_instance_valid(second) or not second.can_receive_damage():
		_finish("FAIL", "second_mother_not_alive_at_second_kill")
		return
	second.take_damage(999999999, _game.player, {"source": "m30_r3_site_second_kill"})
	await _window("after_second_kill_same_children", 12.0)
	if _finished:
		return
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


func _player_precondition_issue() -> String:
	if not is_instance_valid(_game) or not is_instance_valid(_game.player):
		return "PLAYER_MISSING"
	var p: PlayerCharacter = _game.player
	if p._dead or p.current_hp <= 0:
		return "PLAYER_DEAD_LAB_PRECONDITION_LOST"
	if p.combat_transition_is_active():
		return "PLAYER_TRANSITION_LAB_PRECONDITION_LOST"
	if not _world_unchanged():
		return "WORLD_CHANGED_LAB_PRECONDITION_LOST"
	if get_tree().paused or not _game.gameplay_input_is_enabled():
		return "WORLD_OR_INPUT_PAUSED_LAB_PRECONDITION_LOST"
	if p.max_hp < SurvivalGuard.HP_MARGIN:
		return "ONE_SHOT_HP_MARGIN_REPLACED_BY_PROFILE_RECALCULATION"
	return ""

func _on_profile_changed() -> void:
	if not is_instance_valid(_game) or not is_instance_valid(_game.player):
		return
	if _profile_records.size() < 256:
		_profile_records.append({"msec": Time.get_ticks_msec(), "phase": _phase,
			"hp": _game.player.current_hp, "max_hp": _game.player.max_hp,
			"dead": _game.player._dead, "transition": _game.player.combat_transition_is_active(),
			"epoch": _game.player.combat_epoch, "level": PlayerState.level,
			"note": "after existing player listener; before optional lab guard"})

func _tick() -> void:
	await _sampler.after_visual
	if _finished or not _watching:
		return
	_collect_diagnostic(false)
	var issue := _player_precondition_issue()
	if not issue.is_empty():
		_collect_diagnostic(true)
		_finish("BLOCKED", issue)

func _collect_diagnostic(force: bool) -> void:
	var now := Time.get_ticks_msec()
	if not force and now < _next_diagnostic_ms:
		return
	_next_diagnostic_ms = now + 500
	var source := _mother()
	if is_instance_valid(source) and not _observed_sources.has(source.get_instance_id()):
		_observed_sources[source.get_instance_id()] = true
		source.summon_requested.connect(_notice_release)
	_latest_snapshot = Inspector.capture(_game, source)
	_latest_snapshot["phase"] = _phase
	_latest_snapshot["producer_signals_seen"] = int(_signal_counts.get(str(source.get_instance_id()), 0)) if is_instance_valid(source) else 0
	if _diagnostics.size() < 2048:
		_diagnostics.append(_latest_snapshot.duplicate(true))

func _notice_release(source: EnemyActor, _ids: Array, _count: int, _limit: int) -> void:
	var key := str(source.get_instance_id())
	_signal_counts[key] = int(_signal_counts.get(key, 0)) + 1

func _mute_receiver(source: EnemyActor) -> bool:
	var original := Callable(_game, "_on_boss_summon_requested")
	if not source.summon_requested.is_connected(original):
		return false
	_muted_ref = weakref(source)
	source.summon_requested.disconnect(original)
	source.summon_requested.connect(_receive_without_enqueue)
	_receiver_ablated = true
	return true

func _receive_without_enqueue(source: EnemyActor, ids: Array, count: int, limit: int) -> void:
	# Test receiver only. Never disable summon_rule, remove a body or manipulate
	# warning/cooldown. Other sources keep the original receiver.
	var expected: EnemyActor = _muted_ref.get_ref() as EnemyActor if _muted_ref != null else null
	if source == expected and source.runtime_map_id == _map_id and int(source.get_meta("zone_generation", -1)) == _generation:
		_muted_requests += 1
		return
	_game._on_boss_summon_requested(source, ids, count, limit)

func _restore_receiver() -> void:
	var source: EnemyActor = _muted_ref.get_ref() as EnemyActor if _muted_ref != null else null
	if is_instance_valid(source) and is_instance_valid(_game):
		if source.summon_requested.is_connected(_receive_without_enqueue):
			source.summon_requested.disconnect(_receive_without_enqueue)
		var original := Callable(_game, "_on_boss_summon_requested")
		if not source.summon_requested.is_connected(original):
			source.summon_requested.connect(original)
	_muted_ref = null
