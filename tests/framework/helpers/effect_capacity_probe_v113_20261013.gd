extends RefCounted
## Diagnostic observer/producer only. Root remains the simulation/pump owner.
## Explicit layers of ONE registered ignite species are a runtime load proxy.
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const SKILL := "hc.skill.wizard.ice_storm"
const SPECIES := "hc.effect.ignite.v1"
const MAX_LAYERS := 16
const RECEIVERS := 40
const BASE_DAMAGE := 1000
const MAX_BUDGET_SAMPLES := 4096
var _game: Node
var _actors: Array = []
var _check := Callable()
var _runtime: RefCounted
var _layers := 0
var _all_bindings: Array = []
var _bindings: Array = []
var _base_definition: Dictionary = {}
var _start_hp: Array[int] = []
var _direct_loss: Array[int] = []
var _start_metrics: Dictionary = {}
var _start_simulation_usec := 0
var _start_wall_usec := 0
var _publications: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _budgets: Dictionary = {}
var _budget_overflow := false
var _observer_usec := 0
var _final: Dictionary = {}
var _source_hashes: Dictionary = {}
var _defenses: Array[Dictionary] = []
var _invariant_failures: Dictionary = {}
var _start_regen: Array[Dictionary] = []
var _tail_samples: Array[Dictionary] = []
var _tail_budgets: Dictionary = {}
var _tail_collecting := false
var _tail: Dictionary = {}
var _failed_checks := 0
var _initial_world: Dictionary = {}

func _verify(value: bool, label: String) -> void:
	if not value: _failed_checks += 1
	_check.call(value, label)

func prepare(game: Node, actors: Array, layers: int, check: Callable) -> bool:
	_game = game; _actors = actors; _layers = layers; _check = check
	_verify(_actors.size() == 44 and layers in [0, 4, 6, 16], "capacity_fixture_dimensions")
	if _actors.size() != 44 or layers not in [0, 4, 6, 16]: return false
	if not ContentLayers.set_feature_module_enabled("hc.ignite", true):
		_verify(false, "capacity_formal_module_enable"); return false
	var base: Array = PlayerState.feature_bundle().event_index.get("damage_committed:" + SKILL, [])
	_verify(base.size() == 1 and Batch.validate_bindings(SKILL, base), "capacity_one_valid_formal_ignite_binding")
	if base.size() != 1 or not Batch.validate_bindings(SKILL, base): return false
	_base_definition = base[0].definition.duplicate(true)
	var config: Dictionary = _base_definition.config
	var formal_config: bool = _base_definition.handler_id == "hc.ignite.v1" and float(config.chance) == 1.0 \
		and float(config.fraction) == 0.05 and int(config.period_usec) == 1000000 \
		and int(config.duration_usec) == 4000000 and int(config.max_ticks) == 4 \
		and str(config.get("status_layer", "")).is_empty()
	_verify(formal_config, "capacity_unchanged_certified_ignite_config")
	if not formal_config: return false
	# The same maximum set is built and validated in all three modes, before
	# sampling. This is the existing capacity-trifold explicit-layer contract.
	for index in MAX_LAYERS:
		var binding: Dictionary = base[0].duplicate(true)
		binding.source.instance_id = "capacity:layer:" + str(index)
		binding.handle = Compiler.source_handle(binding.source)
		binding.definition.config["status_layer"] = "capacity.layer." + str(index)
		_all_bindings.append(binding)
	_verify(Batch.validate_bindings(SKILL, _all_bindings), "capacity_all_sixteen_bindings_valid")
	if not Batch.validate_bindings(SKILL, _all_bindings): return false
	_bindings = _all_bindings.slice(0, layers)
	# The real Root configures these in _ready. Refuse foreign/lazy ownership
	# rather than replacing a world, clock, combat service or accepted runtime.
	if game._world_context.current_world_owner() != game or game._world_context.capture_world().is_empty():
		_verify(false, "capacity_real_root_world_ready"); return false
	_initial_world = game._world_context.capture_world()
	_runtime = game._feature_effect_runtime
	if _runtime == null:
		_runtime = Runtime.new()
		if not _runtime.configure(game._world_context, game._time_domains, game._combat_runtime):
			_verify(false, "capacity_runtime_configure"); return false
		if not _runtime.configure_child_executor(Callable(game, "_execute_feature_child_action")):
			_verify(false, "capacity_runtime_child_owner"); return false
		game._feature_effect_runtime = _runtime
	if _runtime.get_script() != Runtime or _runtime.has_work():
		_verify(false, "capacity_runtime_is_idle_real_root_owner"); return false
	if int(_runtime.metrics().admitted_facts) != 0 or int(_runtime.metrics().ticks) != 0:
		_verify(false, "capacity_runtime_has_no_prior_work"); return false
	_runtime.require_reservations = true
	# Existing public port; identical in all modes. This exercises Node and
	# ActorRef CPU lifecycle in headless, and provides NO rendered/GPU evidence.
	_runtime.presentation().configure(game._world_context, true)
	for serial in range(_actors.size()):
		var actor = _actors[serial]
		_direct_loss.append(0)
		_defenses.append({"serial": serial, "monster_id": actor.monster_id,
			"magic_defense_min": actor.direct_spell_magic_defense_min,
			"magic_defense_max": actor.direct_spell_magic_defense_max,
			"anti_magic_points": actor.direct_spell_anti_magic_points,
			"stats_valid": actor.direct_spell_stats_valid,
			"periodic_immune": actor.has_actor_capability("hc.immune.periodic")})
		_verify(not actor.has_actor_capability("hc.immune.periodic"), "capacity_no_periodic_immunity:%d" % serial)
	for path: String in ["scripts/game_root.gd", "scripts/enemy.gd", "scripts/features/runtime/effect_runtime.gd",
		"scripts/features/runtime/damage_batch.gd", "scripts/features/runtime/indexed_due_heap.gd",
		"scripts/features/compilation/feature_compiler.gd", "scripts/features/handlers/ignite_handler.gd",
		"scripts/features/presentation/presentation_port.gd", "scripts/features/presentation/ignite_cue.gd",
		"scripts/layers/runtime/combat_runtime_service.gd", "scripts/layers/runtime/execution/frame_budget.gd",
		"scripts/layers/runtime/execution/time_domains.gd", "assets/data/features/ignite.json",
		"assets/data/runtime/canonical_monster_catalog.json", "scripts/monster_natural_regen_policy.gd",
		"tests/phone_crowd_baseline_20261008.gd", "tests/world_crowd_firewall_profile_test.gd",
		"tests/framework/effect_capacity_density_v113_20261013.gd",
		"tests/framework/effect_capacity_density_v113_20261013.tscn",
		"tests/framework/helpers/effect_capacity_probe_v113_20261013.gd"]:
		_source_hashes[path] = FileAccess.get_sha256("res://" + path)
	return true

func begin_window() -> void:
	_start_metrics = _runtime.metrics()
	_start_simulation_usec = _game._time_domains.simulation_usec()
	_start_wall_usec = Time.get_ticks_usec()
	for actor in _actors:
		_start_hp.append(int(actor.current_hp))
		_start_regen.append(actor._natural_regen.state_snapshot())
	sample(-1, "before_window")

func publish(sample_tick: int) -> bool:
	var wall_start := Time.get_ticks_usec()
	var release_id := "effect-capacity-v113:" + str(sample_tick)
	var publication := {"sample_tick": sample_tick, "release_id": release_id,
		"physics_frame": Engine.get_physics_frames(), "process_frame": Engine.get_process_frames(),
		"wall_from_start_usec": wall_start - _start_wall_usec,
		"simulation_usec": _game._time_domains.simulation_usec(), "layer_count": _layers,
		"selected_count": RECEIVERS, "base_damage": BASE_DAMAGE, "targets": [],
		"reservation_status": "NOT_RUN" if _layers == 0 else "MISSING",
		"batch_status": "NOT_RUN" if _layers == 0 else "MISSING"}
	var ticket: RefCounted
	var batch: RefCounted
	var reserve_start := Time.get_ticks_usec()
	if _layers > 0:
		ticket = _runtime.reserve_action(SKILL, _bindings, RECEIVERS, release_id)
		publication["reserve_usec"] = Time.get_ticks_usec() - reserve_start
		publication["admission_reason"] = _runtime.last_admission_reason
		publication["reservation_after_admission"] = _runtime.reservation_snapshot()
		_verify(ticket != null, "capacity_reservation:%d" % sample_tick)
		if ticket == null:
			publication.reservation_status = "FAIL"; _publications.append(publication); return false
		publication.reservation_status = "PASS"
		var created: Dictionary = Batch.create(_game._world_context, release_id, SKILL, _bindings,
			{"profile_id": PlayerState.active_profile_id}, _game._time_domains.simulation_usec(), ticket)
		_verify(bool(created.success), "capacity_batch_created:%d" % sample_tick)
		if not bool(created.success):
			ticket.close(); publication.batch_status = "FAIL"
			publication["batch_reason"] = created.reason; _publications.append(publication); return false
		batch = created.batch
		if not batch.begin_base_scope():
			_verify(false, "capacity_base_scope:%d" % sample_tick)
			batch.finish_production(); _publications.append(publication); return false
	var hp_start := Time.get_ticks_usec()
	for serial in range(RECEIVERS):
		var actor = _actors[serial]
		var hp_before := int(actor.current_hp)
		var context := {"source_class": "direct", "damage_channel": "magic_defense"}
		if batch != null: context["feature_damage_batch"] = batch
		# Real existing resolved-damage authority, including STRUCK/wake/HP/UI.
		# Mode0 mirrors production's empty-binding fast path: no fake reservation.
		actor.take_damage(BASE_DAMAGE, _game.player, context)
		var loss := hp_before - int(actor.current_hp)
		_direct_loss[serial] += loss
		publication.targets.append({"serial": serial, "instance_id": actor.get_instance_id(),
			"monster_id": actor.monster_id, "hp_before": hp_before, "hp_after": actor.current_hp,
			"actual_loss": loss, "alive": actor.can_receive_damage()})
		_verify(loss == BASE_DAMAGE and actor.can_receive_damage(), "capacity_real_base_hp:%d:%d" % [sample_tick, serial])
	publication["base_hp_wall_usec"] = Time.get_ticks_usec() - hp_start
	if batch != null:
		var sealed: bool = batch.finish_base_scope()
		var facts: Array = batch.facts()
		publication["fact_count"] = facts.size()
		publication["facts"] = facts
		_verify(sealed and batch.errors.is_empty() and facts.size() == RECEIVERS,
			"capacity_complete_fact_capture:%d" % sample_tick)
		var pending_before: int = _runtime.pending_count()
		var transfer_start := Time.get_ticks_usec()
		var submitted: bool = _runtime.submit_batch(batch)
		publication["submit_wall_usec"] = Time.get_ticks_usec() - transfer_start
		publication["batch_errors"] = batch.errors.duplicate()
		publication["pending_before"] = pending_before
		publication["pending_after"] = _runtime.pending_count()
		publication.batch_status = "PASS" if submitted else "FAIL"
		_verify(submitted and _runtime.pending_count() - pending_before == RECEIVERS,
			"capacity_exact_fact_transfer:%d" % sample_tick)
		_verify(batch.pending_fact_count() == 0, "capacity_one_shot_fact_transfer:%d" % sample_tick)
		batch.finish_production()
		if not submitted:
			_publications.append(publication); return false
	publication["wall_usec"] = Time.get_ticks_usec() - wall_start
	publication["publication_timing_scope"] = "reserve/create/HP/capture/submit plus identical per-target diagnostic checks"
	publication["callback_proxy_coverage"] = "burst runs at coroutine/physics_frame signal boundary and may be outside PhysicsFrameStart/fixture callback proxy; wall span is separate, never added to proxy"
	_publications.append(publication)
	sample(sample_tick, "after_publication")
	return true

func observe_budget() -> void:
	var started := Time.get_ticks_usec()
	var budget: Dictionary = Budget.snapshot()
	var key := str(budget.epoch)
	var destination: Dictionary = _tail_budgets if _tail_collecting else _budgets
	if not destination.has(key) and destination.size() >= MAX_BUDGET_SAMPLES:
		_budget_overflow = true; return
	var category := "feature_effects:" + str(_game.get_instance_id())
	# Same epoch may be observed at physics and process boundaries. Replace
	# the row, do not sum overlapping counters or invent missing epochs.
	destination[key] = {"epoch": budget.epoch, "physics_frame": Engine.get_physics_frames(),
		"process_frame": Engine.get_process_frames(), "feature_category": category,
		"feature": budget.categories.get(category, {}), "feature_pending": budget.pending.get(category, {}),
		"background_spent_usec": budget.background_spent_usec, "progress_spent_usec": budget.progress_spent_usec,
		"necessary_spent_usec": budget.necessary_spent_usec, "overrun_usec": budget.overrun_usec,
		"open_scopes": budget.open_scopes, "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"process_monitor_usec": int(1000000.0 * Performance.get_monitor(Performance.TIME_PROCESS)),
		"physics_process_monitor_usec": int(1000000.0 * Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))}
	_observer_usec += Time.get_ticks_usec() - started

func sample(sample_tick: int, boundary := "physics_cadence") -> void:
	var started := Time.get_ticks_usec()
	var simulation: int = _game._time_domains.simulation_usec()
	var due := 0
	var due_ticks := 0
	var maximum_lateness := 0
	var minimum_due := 9223372036854775807
	var maximum_expiry := -1
	var remaining_ticks := 0
	var states_per_target := {}
	# Read-only state inspection; never calls a dispatcher or mutates state.
	for state: Dictionary in _runtime._states.values():
		var target_id := str(state.command.target.runtime_id)
		states_per_target[target_id] = int(states_per_target.get(target_id, 0)) + 1
		var next_due := int(state.next_due)
		minimum_due = mini(minimum_due, next_due)
		maximum_expiry = maxi(maximum_expiry, int(state.expires))
		remaining_ticks += maxi(0, 1 + int((int(state.expires) - next_due) / int(state.period)))
		if next_due <= simulation:
			due += 1; maximum_lateness = maxi(maximum_lateness, simulation - next_due)
			due_ticks += 1 + int((mini(simulation, int(state.expires)) - next_due) / int(state.period))
		if state.command.species_id != SPECIES or not str(state.command.layer_id).begins_with("capacity.layer."):
			_invariant_failures["unexpected_state_species_or_layer"] = true
	var active: int = _runtime.active_count()
	if _layers > 0 and active == RECEIVERS * _layers:
		if states_per_target.size() != RECEIVERS: _invariant_failures["concurrent_target_distribution"] = true
		for serial in range(RECEIVERS):
			if int(states_per_target.get(str(_actors[serial].get_instance_id()), 0)) != _layers:
				_invariant_failures["concurrent_target_layer_count"] = true
	if active != _runtime.heap_count(): _invariant_failures["state_heap_mismatch"] = true
	if active != _runtime.presentation().node_count(): _invariant_failures["state_cue_mismatch"] = true
	var hp: Array[int] = []
	for actor in _actors: hp.append(int(actor.current_hp) if is_instance_valid(actor) else -1)
	var row := {"sample_tick": sample_tick, "boundary": boundary,
		"physics_frame": Engine.get_physics_frames(), "process_frame": Engine.get_process_frames(),
		"wall_elapsed_usec": Time.get_ticks_usec() - _start_wall_usec, "simulation_usec": simulation,
		"active": active, "pending": _runtime.pending_count(), "heap": _runtime.heap_count(),
		"children": _runtime.child_count(), "cue_nodes": _runtime.presentation().node_count(),
		"reservations": _runtime.reservation_snapshot(), "metrics": _runtime.metrics(), "hp": hp,
		"due_states": due, "outstanding_due_ticks": due_ticks,
		"remaining_ticks_for_installed_incarnations": remaining_ticks,
		"future_ticks_for_installed_incarnations": remaining_ticks - due_ticks,
		"maximum_expiry_usec": maximum_expiry,
		"next_due_usec": minimum_due if active > 0 else -1,
		"maximum_current_due_lateness_usec": maximum_lateness, "states_per_target": states_per_target,
		"runtime_errors": _runtime.errors.duplicate()}
	if _tail_collecting: _tail_samples.append(row)
	else: _samples.append(row)
	_observer_usec += Time.get_ticks_usec() - started

func finish_window() -> void:
	observe_budget(); sample(300, "window_end")
	var metrics: Dictionary = _runtime.metrics()
	var admitted := int(metrics.admitted_facts) - int(_start_metrics.admitted_facts)
	var started := int(metrics.started) - int(_start_metrics.started)
	var replaced := int(metrics.replaced) - int(_start_metrics.replaced)
	var expired := int(metrics.expired) - int(_start_metrics.expired)
	var ticks := int(metrics.ticks) - int(_start_metrics.ticks)
	var actual_loss := int(metrics.actual_loss) - int(_start_metrics.actual_loss)
	var expected_facts := RECEIVERS * 2 if _layers > 0 else 0
	var all_hp_loss := 0
	var direct_hp_loss := 0
	var hp_rows: Array[Dictionary] = []
	for serial in range(_actors.size()):
		var actor = _actors[serial]
		var hp_loss := _start_hp[serial] - int(actor.current_hp)
		all_hp_loss += hp_loss; direct_hp_loss += _direct_loss[serial]
		hp_rows.append({"serial": serial, "monster_id": actor.monster_id, "start_hp": _start_hp[serial],
			"end_hp": actor.current_hp, "direct_loss": _direct_loss[serial], "net_hp_loss": hp_loss,
			"regen_start": _start_regen[serial], "regen_end": actor._natural_regen.state_snapshot(),
			"alive": actor.can_receive_damage(), "physics_processing": actor.is_physics_processing(),
			"attack_starts": actor._hc_starts, "attack_settlements": actor._hc_settlements})
		_verify(actor.can_receive_damage(), "capacity_actor_survived:%d" % serial)
		if serial < RECEIVERS:
			_verify(_direct_loss[serial] == BASE_DAMAGE * 2, "capacity_both_base_commits:%d" % serial)
		else:
			_verify(hp_loss == 0 and _direct_loss[serial] == 0, "capacity_background_hp_unchanged:%d" % serial)
	_verify(_publications.size() == 2, "capacity_two_publication_bursts")
	_verify(_runtime.errors.is_empty() and int(metrics.failed) == 0, "capacity_no_runtime_delivery_errors")
	_verify(int(metrics.invalidated) == 0, "capacity_no_cancelled_or_invalidated_work")
	_verify(admitted + _runtime.pending_count() == expected_facts, "capacity_accepted_fact_conservation")
	_verify(started + replaced == admitted * _layers, "capacity_every_admitted_binding_applied")
	_verify(_runtime.active_count() == started - expired, "capacity_state_head_conservation")
	_verify(_runtime.heap_count() == _runtime.active_count(), "capacity_final_heap_matches_heads")
	_verify(_runtime.child_count() == 0, "capacity_no_unrequested_child_actions")
	_verify(_invariant_failures.is_empty(), "capacity_all_observed_structural_invariants")
	_verify(int(metrics.peak_states) == RECEIVERS * _layers, "capacity_requested_concurrency_reached")
	_verify(int(metrics.optional_cue_missing) == 0, "capacity_optional_cue_nodes_actually_created")
	_verify(not _budget_overflow, "capacity_diagnostic_buffer_bounded")
	_verify(direct_hp_loss == RECEIVERS * 2 * BASE_DAMAGE, "capacity_exact_real_direct_hp_loss")
	_verify(ticks == int(metrics.tick_delivery_count), "capacity_all_delivered_ticks_succeeded")
	_verify(ticks > 0 and actual_loss > 0 if _layers > 0 else ticks == 0 and actual_loss == 0,
		"capacity_effect_mode_real_tick_and_hp_work")
	_final = {"metrics": metrics, "active": _runtime.active_count(), "pending": _runtime.pending_count(),
		"heap": _runtime.heap_count(), "reservations": _runtime.reservation_snapshot(),
		"simulation_elapsed_usec": _game._time_domains.simulation_usec() - _start_simulation_usec,
		"accepted_fact_count": expected_facts, "applied_binding_count": started + replaced,
		"pending_binding_obligations": _runtime.pending_count() * _layers,
		"base_hp_loss": direct_hp_loss, "all_actor_net_hp_loss": all_hp_loss, "periodic_hp_loss": actual_loss,
		"actual_healing_ledger": "MISSING", "hp_accounting_note": "natural regen remains active; net HP loss is not total damage; periodic actual_loss comes from existing real HP-port receipts",
		"actors": hp_rows, "runtime_errors": _runtime.errors.duplicate(),
		"invariant_failures": _invariant_failures.keys()}

func drain_tail(tree: SceneTree) -> void:
	# The complete300-tick report/counters have already been frozen by caller.
	# Root and all actors keep their actual physics/process; no new injections.
	_tail_collecting = true
	var failures_before := _failed_checks
	var start_wall := Time.get_ticks_usec()
	var start_physics := Engine.get_physics_frames()
	var before: Dictionary = _runtime.metrics()
	var window_end: Dictionary = _samples.back()
	var ticks_waited := 0
	while ticks_waited < 240 and not _is_drained():
		await tree.physics_frame
		ticks_waited += 1
		observe_budget()
		if ticks_waited % 15 == 0: sample(ticks_waited, "tail_physics_cadence")
	sample(ticks_waited, "tail_end")
	var after: Dictionary = _runtime.metrics()
	var delivered := int(after.ticks) - int(before.ticks)
	var exact_tail_available := int(_final.pending) == 0
	var expected_tail := int(window_end.remaining_ticks_for_installed_incarnations)
	_verify(_is_drained(), "capacity_natural_tail_drained_inside240_physics_ticks")
	_verify(_runtime.errors.is_empty() and int(after.failed) == 0 and int(after.invalidated) == 0,
		"capacity_tail_no_errors_or_cancellation")
	_verify(int(after.admitted_facts) == (RECEIVERS * 2 if _layers > 0 else 0), "capacity_tail_all_accepted_facts_delivered")
	_verify(int(after.started) + int(after.replaced) == RECEIVERS * 2 * _layers,
		"capacity_tail_all_accepted_bindings_applied")
	_verify(int(after.expired) == int(after.started), "capacity_tail_every_started_head_expired")
	_verify(int(after.ticks) == int(after.tick_delivery_count), "capacity_tail_all_tick_deliveries_succeeded")
	_verify(not _budget_overflow and _invariant_failures.is_empty(), "capacity_tail_observation_integrity")
	_verify(_game._world_context.matches_world(_initial_world), "capacity_tail_same_real_world")
	_verify(is_instance_valid(_game.player) and int(_game.player.current_hp) > 0, "capacity_tail_player_alive")
	if exact_tail_available:
		_verify(delivered == expected_tail, "capacity_exact_remaining_incarnation_ticks_delivered")
	var actor_rows: Array[Dictionary] = []
	for serial in range(_actors.size()):
		var actor = _actors[serial]
		_verify(is_instance_valid(actor) and actor.can_receive_damage(), "capacity_tail_actor_survived:%d" % serial)
		actor_rows.append({"serial": serial, "hp": actor.current_hp, "max_hp": actor.max_hp,
			"regen": actor._natural_regen.state_snapshot(), "attack_starts": actor._hc_starts,
			"attack_settlements": actor._hc_settlements, "physics_processing": actor.is_physics_processing()})
	_tail = {"status": "PASS" if _failed_checks == failures_before else "FAIL",
		"failed_checks": _failed_checks - failures_before,
		"maximum_physics_ticks": 240, "actual_physics_ticks": Engine.get_physics_frames() - start_physics,
		"wall_usec": Time.get_ticks_usec() - start_wall, "metrics_start": before, "metrics_end": after,
		"tick_delta": delivered, "periodic_actual_loss_delta": int(after.actual_loss) - int(before.actual_loss),
		"remaining_tick_conservation": "PASS" if exact_tail_available and delivered == expected_tail else ("FAIL" if exact_tail_available else "MISSING"),
		"expected_from_window_installed_incarnations": expected_tail,
		"expectation_basis": "valid only when window pending=0: no future publication, all installed next_due..expires slots remain; replaces before window already canceled their uncommitted future ticks",
		"final_reservations": _runtime.reservation_snapshot(), "final_actors": actor_rows,
		"player_hp_end": _game.player.current_hp,
		"timeseries": _tail_samples, "frame_budget_samples": _tail_budgets.values()}
	_tail_collecting = false

func _is_drained() -> bool:
	var slots: Dictionary = _runtime.reservation_snapshot()
	return not _runtime.has_work() and _runtime.active_count() == 0 and _runtime.pending_count() == 0 \
		and _runtime.heap_count() == 0 and _runtime.child_count() == 0 and _runtime.presentation().node_count() == 0 \
		and int(slots.actions) == 0 and int(slots.facts) == 0 and int(slots.states) == 0 \
		and int(slots.promised_receipts) == 0 and int(slots.receipts) == 0 \
		and int(slots.children) == 0 and int(slots.promised_children) == 0

func report() -> Dictionary:
	return {"species_id": SPECIES, "layer_count": _layers, "prebuilt_layer_count": MAX_LAYERS,
		"environment_layer_text": OS.get_environment("HARDCORE_EFFECT_CAPACITY_LAYERS"),
		"interpretation": "independent layered ignite runtime load proxy; no new DOT species",
		"fixture_max_and_initial_hp": 100000, "base_damage": BASE_DAMAGE, "base_definition": _base_definition,
		"all_bindings_sha256": JSON.stringify(_all_bindings).sha256_text(),
		"selected_bindings_sha256": JSON.stringify(_bindings).sha256_text(),
		"source_hashes": _source_hashes, "unchanged_defense_inputs": _defenses,
		"initial_metrics": _start_metrics, "final": _final, "publications": _publications,
		"timeseries": _samples, "frame_budget_samples": _budgets.values(),
		"observer_wall_usec_including_separate_tail": _observer_usec, "presentation_supported": true,
		"presentation_scope": "existing procedural Node/ActorRef CPU lifecycle only",
		"frame_budget_scope": "phase-partial sampled per-epoch category counters; Root pump may follow observer; last observed row per epoch, not complete CPU accounting",
		"engine_monitor_scope": "lagged Performance.TIME_PROCESS/TIME_PHYSICS_PROCESS snapshots; distinct from node callback boundary proxy and burst wall span",
		"tick_lateness_scope": "runtime maximum delivered simulation lateness plus sampled outstanding due debt",
		"delivered_tick_lateness_distribution": "MISSING", "end_to_end_hit_to_effect_wall_latency": "MISSING",
		"tail": _tail, "tail_reason": "separate natural drain after frozen300-tick window; no injections/manual clock/dispatch/budget changes",
		"player_skill_release": "NOT_RUN", "full_aoe_selection": "NOT_RUN",
		"strict_trajectory_equivalence": "MISSING", "gpu": "MISSING", "device_test": "NOT_RUN",
		"performance_acceptance": "NOT_RUN", "timing_pass_threshold": "none"}
