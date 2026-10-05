extends "res://tests/framework/natural_effect_lifecycle_test.gd"

@export var overlap_expiry := false
var burst_snapshot: Dictionary = {}
var death_frames: Dictionary = {}
var expiration_simulation_usec := 0
var first_expiry_usec := 0
var maximum_death_age_usec := 0
var second_input_usec := 0
var original_release_delay_usec := 0
var first_input_usec := 0
var first_effect_started_usec := 0
var observed_initial_release_latency_usec := 0
var boundary_previous_wall_usec := 0
var boundary_wall_frames := 0
var boundary_minimum_wall_interval_usec := 0
var boundary_maximum_wall_interval_usec := 0
var boundary_total_wall_wait_usec := 0
var boundary_scopes_closed := true
var boundary_service_observations: Array[Dictionary] = []
var boundary_input_request: Dictionary = {}
var boundary_input_outcome: StringName = &"pending"
var boundary_input_events: Array[Dictionary] = []
var boundary_release_events: Array[Dictionary] = []
var boundary_duration_frames := 0

func _ready() -> void:
	process_physics_priority = 10000
	super._ready()

func _physics_process(_delta: float) -> void:
	_observe_boundary_service("after_root_physics")

func _observe_boundary_service(phase: String) -> void:
	if not observing or runtime == null or not is_instance_valid(game) or boundary_service_observations.size()>=32:
		return
	var simulation: int = game._time_domains.simulation_usec()
	if simulation<first_effect_started_usec+1000000 or first_effect_started_usec == 0: return
	var ledger := Budget.snapshot()
	var fairness := {}
	for name: String in Budget._pending:
		var row: Dictionary = Budget._pending[name]
		fairness[name] = {"pending_epoch":row.pending_epoch,"last_service_epoch":row.last_service_epoch,
			"last_service_sequence":row.last_service_sequence,"sequence":row.sequence,"runnable":ledger.pending[name].runnable}
	boundary_service_observations.append({"phase":phase,"process_epoch":Engine.get_process_frames(),
		"physics_frame":Engine.get_physics_frames(),"simulation_usec":simulation,"tick_count":runtime.metrics().ticks,
		"pending_facts":runtime.pending_count(),"budget":ledger,"fairness":fairness,
		"due_states":_due_state_count(),"earliest_due_usec":runtime._heap.due_usec(),
		"resource_last_poll_frame":game._streaming_coordinator._last_streaming_poll_frame,
		"resource_request_count":game._streaming_coordinator.pending_request_count(),
		"resource_subscription_count":game._streaming_coordinator._visual_subscriptions.size()})

func _process(delta: float) -> void:
	# Godot fixed_fps returns before OS::add_frame_delay, so max_fps does not
	# pace that mode. This observer-owned host pace never advances simulation,
	# calls a pump, alters a budget, or changes an action/effect timer. It keeps
	# asynchronous real-wall services in the declared fixed60 environment.
	var now := Time.get_ticks_usec()
	boundary_scopes_closed = boundary_scopes_closed and int(Budget.snapshot().open_scopes) == 0
	var frame_usec := int(ceil(1000000.0/float(Engine.physics_ticks_per_second)))
	if boundary_previous_wall_usec > 0:
		var remaining := maxi(0,boundary_previous_wall_usec+frame_usec-now)
		if remaining > 0:
			var wait_started := now
			var deadline := boundary_previous_wall_usec+frame_usec
			while now<deadline:
				OS.delay_usec(deadline-now)
				now = Time.get_ticks_usec()
			boundary_total_wall_wait_usec += now-wait_started
		var interval := now-boundary_previous_wall_usec
		boundary_minimum_wall_interval_usec = interval if boundary_wall_frames == 0 else mini(boundary_minimum_wall_interval_usec,interval)
		boundary_maximum_wall_interval_usec = maxi(boundary_maximum_wall_interval_usec,interval)
		boundary_wall_frames += 1
	boundary_previous_wall_usec = now
	super._process(delta)
	_drive_boundary_input()
	_observe_boundary_service("after_root_process")

func _boundary_wall_observation() -> Dictionary:
	return {"kind":"test_owned_host_pace","frames":boundary_wall_frames,
		"minimum_interval_usec":boundary_minimum_wall_interval_usec,"maximum_interval_usec":boundary_maximum_wall_interval_usec,
		"total_wait_usec":boundary_total_wall_wait_usec,"budget_scopes_closed":boundary_scopes_closed,
		"interval_usec":int(ceil(1000000.0/float(Engine.physics_ticks_per_second)))}

func _scene_id() -> String:
	return "death_expiry_overlap_test" if overlap_expiry else "death_burst_lifecycle_test"

func _artifact_path(suffix: String) -> String:
	return "res://outputs/test_logs/framework/"+_scene_id().trim_suffix("_test")+suffix+".json"

func _run() -> void:
	var engine_arguments := OS.get_cmdline_args()
	var clock_deltas: Array[float] = []
	var fixed_deltas := true
	for frame in 3:
		await get_tree().process_frame
		var observed_delta := get_process_delta_time()
		clock_deltas.append(observed_delta)
		fixed_deltas = fixed_deltas and absf(observed_delta-1.0/60.0) < 0.000000001
	print("BOUNDARY_CLOCK_ENVIRONMENT "+JSON.stringify({"engine_arguments":Array(engine_arguments),"observed_process_delta":clock_deltas,"physics_tps":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale}))
	check(fixed_deltas and Engine.max_fps == 60 and Engine.physics_ticks_per_second == 60
		and Engine.time_scale == 1.0,"static boundary uses explicit fixed60 engine stepping with original timers and scale")
	if not failures.is_empty(): _finish(); return
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"burst owns isolated production persistence")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade() and PlayerState.create_character("死亡同刻验证" if overlap_expiry else "死亡突发验证","hc.profession.wizard").is_empty(),"real startup creates the burst profile")
	PlayerState.level = 50; PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}
	PlayerState.equipment["hc.slot.weapon"] = Drop.create_instance(GameData.get_item_record({"item_id":85}),"burst:weapon")
	PlayerState.recalculate_stats(false)
	check(PlayerState.save_game(true,true,true),"formal initial durable checkpoint")
	var profile: String = PlayerState.active_profile_id
	var baseline_xp: int = PlayerState.experience
	get_tree().node_added.connect(_observe_spawn)
	game = Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"formal mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): _finish(); return
	var bindings: Array = ContentLayers.feature_configuration().bindings.duplicate(true)
	bindings.append({"module_id":"hc.ignite","kind":"item","item_id":"hc.item.000085","mechanic_id":"hc.ignite.ice_storm"})
	bindings.append({"module_id":"hc.ignite","kind":"skill","skill_id":"hc.skill.wizard.ice_storm","mechanic_id":"hc.ignite.ice_storm"})
	var captured := Graph.capture(bindings)
	check(bool(captured.success),"test authoring graph is plain")
	if not bool(captured.success): _finish(); return
	ContentLayers._feature_bindings = captured.value
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true) and PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[]).size() == 3,"actual equipment, learned skill and rule qualify three sources")
	# Controlled queue-boundary fixture, not natural AI/performance evidence.
	# No Root pump, clock, damage, death, writer or budget is replaced.
	for actor: Node in get_tree().get_nodes_in_group("enemies"):
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.set_combat_position(game.player.global_position+Vector2(3000,3000),&"test_fixture_clear")
	# The production area target uses roundi grid coordinates. An integer
	# center keeps this packing centered on the real planner's chosen cell.
	var center := Vector2(41,14)
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(center+Vector2(-3.0,0)))
	game.player.max_hp = 100000; game.player.current_hp = 100000
	game.player.max_mp = 5000; game.player.current_mp = 5000
	PlayerState.computed_stats.magic_min = 100; PlayerState.computed_stats.magic_max = 100
	var points: Array[Vector2] = []
	# Hex spacing exceeds two formal small-body radii. Outer corner pairs
	# are excluded; the unchanged skill geometry decides the actual hit set.
	for row in range(-3,4):
		for column in range(-2,3):
			points.append(Vector2((float(column)+0.5*abs(row%2))*0.708,float(row)*0.614))
	points.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.length_squared()<b.length_squared())
	for index in 30:
		var point := center+points[index]
		var actor: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(19),game._canonical_ground_gu_to_screen_px(point),false,-1.0,{"respawn_enabled":false,"spawn_slot_id":"test:burst:"+str(index)})
		check(actor != null,"formal mapped receiver exists "+str(index))
		if actor == null: _finish(); return
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.max_hp = 10000; actor.current_hp = 10000
		actor.direct_spell_anti_magic_points = 0
		actor.direct_spell_magic_defense_min = 0; actor.direct_spell_magic_defense_max = 0
		actor.direct_spell_stats_valid = true
		actor.died.connect(_on_burst_died); targets.append(actor)
		check(actor._hc_point_walkable(point),"fixture uses walkable authored ground "+str(index))
	var nonoverlap := true
	for i in targets.size():
		for j in range(i):
			var a: Vector2 = game._canonical_screen_px_to_ground_gu(targets[i].global_position)
			var b: Vector2 = game._canonical_screen_px_to_ground_gu(targets[j].global_position)
			nonoverlap = nonoverlap and a.distance_to(b)+0.00001 >= targets[i].combat_radius_gu+targets[j].combat_radius_gu
	check(nonoverlap,"all thirty formal bodies are disjoint")
	if not nonoverlap: _finish(); return
	game._set_magic_locked_target(targets[0],true)
	check(game._canonical_screen_px_to_grid_cell(targets[0].global_position) == Vector2i(center),"fixture center equals the production rounded target cell")
	game.player.skill_requested.connect(_observe_boundary_release)
	_queue_boundary_input(false,-1)
	deadline = Time.get_ticks_msec()+2000
	while boundary_input_outcome == &"pending" and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(boundary_input_outcome == &"accepted","first action accepts through Root and Player in the explicit test process callback")
	runtime = game._feature_effect_runtime
	check(runtime != null and int(runtime.reservation_snapshot().actions) == 1,"accepted first action owns a nonempty capacity reservation")
	if runtime == null: _finish(); return
	observing = true
	deadline = Time.get_ticks_msec()+8000
	while runtime.active_count()<90 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(runtime.active_count() == 90,"one formal release reaches all thirty disjoint receivers with three sources")
	if runtime.active_count() != 90:
		var receivers: Array = []
		for actor: EnemyActor in targets: receivers.append({"slot":actor.get_meta("spawn_context",{}),"hp":actor.current_hp,"ground":str(game._canonical_screen_px_to_ground_gu(actor.global_position))})
		_write(_artifact_path("_trace"),{"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"phase_status":"FAIL","phase":"first release cohort","metrics":runtime.metrics(),"receivers":receivers})
		_finish(); return
	peak_state_evidence = _capture_state_cohort(); peak_states = runtime.active_count()
	var expiries := {}
	for state: Dictionary in runtime._states.values(): expiries[int(state.expires)] = true
	check(expiries.size() == 1,"all ninety accepted states share the same scheduled expiration tick")
	first_expiry_usec = int(expiries.keys()[0])
	var first_state: Dictionary = runtime._states.values()[0]
	first_effect_started_usec = int(first_state.expires)-int(first_state.command.duration_usec)
	observed_initial_release_latency_usec = first_effect_started_usec-first_input_usec
	deadline = Time.get_ticks_msec()+8000
	if overlap_expiry:
		var timing: Dictionary = PlayerState.effective_skill_definition("hc.skill.wizard.ice_storm").timing
		# Match Player's formal timing resolution; this optional field falls
		# back to the declared body cast duration in the production consumer.
		var body_ms := int(timing.get("body_cast_ms",roundi(ProfessionRules.CASTER_SPELL_ACTION_DURATION*1000.0)))
		original_release_delay_usec = int(timing.get("effect_resolve_ms_from_cast_start",body_ms))*1000
		check(game.player._equipment_spell_time_scale == 1.0,"controlled fixture retains the original release time scale")
		var duration_usec: int = first_state.command.duration_usec
		boundary_duration_frames = int(round(float(duration_usec)*float(Engine.physics_ticks_per_second)/1000000.0))
		check(boundary_duration_frames>0 and boundary_duration_frames*1000000 == duration_usec*Engine.physics_ticks_per_second,
			"original state duration is an exact integer number of unchanged fixed60 steps")
		check(observed_initial_release_latency_usec>0 and observed_initial_release_latency_usec<duration_usec,
			"first real release is observed without replacing the original Player Timer")
	else:
		while runtime.has_work() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
		expiration_simulation_usec = game._time_domains.simulation_usec()
		check(int(runtime.metrics().ticks) == 360 and int(runtime.metrics().expired) == 90 and int(runtime.metrics().invalidated) == 0,"all ninety states expire after exactly four original periodic deliveries")
	check(deaths == 0 and bool(peak_state_evidence.all_named_thirty_fixture_targets_have_three_sources),"named cohort remains alive before the second input")
	# A new accepted configuration captures this declared stress damage.
	# It does not edit an in-flight lease or any HP already committed.
	var second_frame := int(boundary_input_events[0].process_frame)+boundary_duration_frames if overlap_expiry else -1
	_queue_boundary_input(true,second_frame)
	deadline = Time.get_ticks_msec()+8000
	while boundary_input_outcome == &"pending" and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(boundary_input_outcome == &"accepted","second production API input accepts its lethal action in the same explicit process callback")
	if overlap_expiry:
		check(boundary_input_events.size() == 2 and int(boundary_input_events[1].process_frame)-int(boundary_input_events[0].process_frame) == boundary_duration_frames,
			"the two complete production inputs have the same process callback phase and the original duration's frame distance")
		check(second_input_usec-first_input_usec == int(first_state.command.duration_usec),
			"actual input simulation-clock distance equals the unmodified state duration")
	check(int(runtime.reservation_snapshot().actions) == 1,"lethal release has a capacity reservation before HP commits")
	deadline = Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		maximum_death_age_usec = maxi(maximum_death_age_usec,int(game.death_work_queue_snapshot().oldest_age_usec))
		await get_tree().process_frame
		if deaths == 30 and not runtime.has_work() and _settlement_drained() and stream_finished_usec>0: break
	observing = false
	check(deaths == 30 and death_frames.size() == 1,"all thirty real death signals occur in one process-frame deferred burst")
	check(int(burst_snapshot.get("pending_count",0)) == 30 and burst_snapshot.get("identities",{}).size() == 30,"thirty distinct real death jobs coexist in the production queue")
	if overlap_expiry:
		check(int(burst_snapshot.get("simulation_usec",-1)) == first_expiry_usec,"thirty-death burst shares the exact scheduled final expiration simulation tick")
		check(boundary_release_events.size() == 2 and int(boundary_release_events[1].simulation_usec)-second_input_usec == int(boundary_release_events[0].simulation_usec)-first_input_usec,
			"both actual Player skill_requested signals retain the same fixed-step Timer quantization")
		check(int(burst_snapshot.get("due_states",0))>0,"unfinished due effect work coexists with thirty real death jobs")
	check(_settlement_drained() and not runtime.has_work() and runtime._receipts.is_empty() and runtime.errors.is_empty(),"all death, persistence, reservation and receipt work drains")
	check(bool(resource_evidence.get("five_textures_available",false)) and resource_evidence.get("request_kind") == "threaded_new_job" and stream_finished_usec>stream_started_usec,"the specified new resource task completes five usable textures")
	check(concurrent_queues and game._streaming_coordinator.pending_request_count() == 0,"real resource request overlaps death work and global resource backlog drains")
	var jobs: Array = game._enemy_death_terminal_jobs
	var terminal_keys := {}
	var materialized_nodes := 0
	var expected_xp := baseline_xp
	for death: Dictionary in observed_deaths.values(): expected_xp += int(death.experience)
	for job: Dictionary in jobs:
		check(job.state == "COMMITTED" and not terminal_keys.has(job.death_key),"each terminal job commits one unique identity")
		terminal_keys[job.death_key] = true
		materialized_nodes += int(job.materialized_node_count)
	check(jobs.size() == 30 and observed_deaths.size() == 30 and PlayerState.experience == expected_xp,"exactly thirty deaths and rewards pass through the sole settlement owner")
	var queued_identities: Dictionary = burst_snapshot.get("identities",{})
	var alignment_errors := _death_identity_errors(queued_identities,jobs)
	check(alignment_errors.is_empty(),"queued and committed identity/slot/sequence sets match, and every snapshot state is QUEUED: "+str(alignment_errors))
	# Counterexamples alter observer-owned copies only. They prove a same-size
	# identity substitution or wrong state cannot pass this evidence gate.
	if not queued_identities.is_empty():
		var first_key: String = str(queued_identities.keys()[0])
		var wrong_key := queued_identities.duplicate(true)
		wrong_key["test:substituted-death-key"] = wrong_key[first_key]
		wrong_key.erase(first_key)
		check(_death_identity_errors(wrong_key,jobs).has("death_key_set_mismatch"),"identity gate rejects a substituted key despite unchanged unique count")
		var wrong_state := queued_identities.duplicate(true)
		wrong_state[first_key]["state"] = "COMMITTED"
		check(_death_identity_errors(wrong_state,jobs).has("not_queued:"+first_key),"identity gate rejects non-QUEUED snapshot state")
		var wrong_slot := queued_identities.duplicate(true)
		wrong_slot[first_key]["slot"] = "test:wrong-slot"
		check(_death_identity_errors(wrong_slot,jobs).has("slot_mismatch:"+first_key),"identity gate rejects the right key paired with the wrong slot")
		var wrong_sequence := queued_identities.duplicate(true)
		wrong_sequence[first_key]["sequence"] = int(wrong_sequence[first_key].sequence)+1
		check(_death_identity_errors(wrong_sequence,jobs).has("sequence_mismatch:"+first_key),"identity gate rejects the right key paired with the wrong sequence")
	else:
		check(false,"identity counterexamples require the actual observed queue snapshot")

	var drops := _live_drop_count()
	check(materialized_nodes>0 and drops == materialized_nodes,"real canonical drop plans materialize exactly the observed nonempty ground-node set")
	for frame in 8: await get_tree().process_frame
	check(PlayerState.experience == expected_xp and game._enemy_death_terminal_jobs.size() == 30 and _live_drop_count() == drops and _settlement_drained(),"late normal frames repeat neither rewards, death jobs nor ground drops")
	check(boundary_wall_frames>120 and boundary_minimum_wall_interval_usec>=16667 and boundary_scopes_closed,"observed host pace bounds fixed simulation to60 wall frames without open budget scopes")
	check(int(runtime.metrics().maximum_tick_delivery_lateness_usec)<1000000,"every actual periodic delivery is less than one unchanged period late")
	check(int(runtime.metrics().started) == 90 and int(runtime.metrics().ticks)<=360 and int(runtime.metrics().expired)+int(runtime.metrics().invalidated) == 90,"each accepted state reaches its own expiry or target-death terminal result; lethal facts start no extra states")
	var xp: int = PlayerState.experience
	var trace := {"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"scope":"controlled stationary disjoint receivers, engine fixed60 stepping; real Player release and Root pumps; wall samples are not real-time performance, natural movement, Android or GPU",
		"clock_environment":{"fixed_fps":60,"max_fps":Engine.max_fps,"real_time_synchronization":false,"physics_tps":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"arguments":Array(OS.get_cmdline_args()),"observed_process_delta":clock_deltas,"wall_pace":_boundary_wall_observation()},
		"boundary_input_events":boundary_input_events,"boundary_release_events":boundary_release_events,"original_duration_frames":boundary_duration_frames,
		"overlap_expiry":overlap_expiry,"second_input_usec":second_input_usec,"original_release_delay_usec":original_release_delay_usec,"boundary_service_observations":boundary_service_observations,
		"first_input_usec":first_input_usec,"first_effect_started_usec":first_effect_started_usec,"observed_initial_release_latency_usec":observed_initial_release_latency_usec,
		"phase":"before final save/teardown/cold handoff","phase_status":"PASS" if failures.is_empty() else "FAIL","phase_failures":failures.duplicate(),
		"scheduled_expiry_usec":first_expiry_usec,"observed_expiry_drained_usec":expiration_simulation_usec,"peak_state_evidence":peak_state_evidence,
		"burst_snapshot":burst_snapshot,"death_frames":death_frames,"metrics":runtime.metrics(),"terminal_jobs":jobs.duplicate(true),
		"resource_evidence":resource_evidence,"maximum_observed_death_age_usec":maximum_death_age_usec,"wall_frame_usec":_percentiles("wall_usec"),"samples":samples,
		"death_latency_usec":death_finished_usec-death_started_usec,"experience":xp,"materialized_drop_nodes":materialized_nodes,"actual_drop_nodes":drops,"category_scopes":category_scopes,"maximum_runnable_service_age_frames":maximum_service_age}
	print("BURST_INPUT_PHASE_OBSERVATION "+JSON.stringify({"first_input_usec":first_input_usec,"first_effect_started_usec":first_effect_started_usec,"observed_initial_release_latency_usec":observed_initial_release_latency_usec,"configured_release_delay_usec":original_release_delay_usec,"second_input_usec":second_input_usec,"scheduled_expiry_usec":first_expiry_usec,"death_snapshot_usec":burst_snapshot.get("simulation_usec",-1),"due_at_death":burst_snapshot.get("due_states",-1)}))
	_write(_artifact_path("_trace"),trace)
	game._streaming_coordinator.unregister_visual(get_instance_id())
	check(PlayerState.save_game(true,true,true),"final durability checkpoint succeeds")
	var generation: String = PlayerState._world_clock_generation
	game.queue_free(); await get_tree().process_frame
	check(not runtime.has_work() and runtime._receipts.is_empty(),"world teardown releases remaining owned work")
	check(PlayerState.select_character(profile) and PlayerState.experience == xp,"production reload retains each reward once")
	if failures.is_empty(): _write(_artifact_path("_expected"),{"profile_id":profile,"experience":xp,"generation":generation,"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256")})
	_finish()

func _on_burst_died(enemy: EnemyActor,data: Dictionary) -> void:
	_on_target_died(enemy,data)
	death_frames[Engine.get_process_frames()] = true
	if game._pending_enemy_deaths.size()>int(burst_snapshot.get("pending_count",0)):
		var identities := {}
		for job: Dictionary in game._pending_enemy_deaths: identities[job.death_key] = {"slot":job.spawn_context.spawn_slot_id,"state":job.state,"sequence":job.sequence}
		var due_states := 0
		for state: Dictionary in runtime._states.values():
			if int(state.next_due)<=game._time_domains.simulation_usec(): due_states += 1
		burst_snapshot = {"pending_count":game._pending_enemy_deaths.size(),"identities":identities,"simulation_usec":game._time_domains.simulation_usec(),"process_frame":Engine.get_process_frames(),"due_states":due_states,"metrics":runtime.metrics()}

func _live_drop_count() -> int:
	var result := 0
	for child: Node in game.get_children():
		if child is LootPickup: result += 1
	return result

func _finish() -> void:
	observing = false
	if is_instance_valid(game): game.queue_free()
	if not proof.write_receipt(_scene_id(),checks,failures.size()): failures.append("receipt")
	print("DEATH_BURST_LIFECYCLE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)


static func _death_identity_errors(queued: Dictionary,jobs: Array) -> Array[String]:
	# Test observation only; never authorizes or changes production death work.
	var errors: Array[String] = []
	var terminal := {}
	for job: Dictionary in jobs:
		var key := str(job.get("death_key",""))
		if key.is_empty() or terminal.has(key): errors.append("duplicate_terminal:"+key)
		terminal[key] = job
	var queued_keys := queued.keys(); queued_keys.sort()
	var terminal_keys := terminal.keys(); terminal_keys.sort()
	if queued_keys != terminal_keys: errors.append("death_key_set_mismatch")
	for raw_key: Variant in queued:
		var key := str(raw_key)
		var observed: Dictionary = queued[raw_key]
		if observed.get("state") != "QUEUED": errors.append("not_queued:"+key)
		if not terminal.has(key): continue
		var job: Dictionary = terminal[key]
		if job.get("state") != "COMMITTED": errors.append("not_committed:"+key)
		if observed.get("slot") != job.get("spawn_context",{}).get("spawn_slot_id"): errors.append("slot_mismatch:"+key)
		if observed.get("sequence") != job.get("sequence"): errors.append("sequence_mismatch:"+key)
	return errors

func _due_state_count() -> int:
	var count := 0
	for state: Dictionary in runtime._states.values():
		if int(state.next_due) <= game._time_domains.simulation_usec(): count += 1
	return count

func _queue_boundary_input(lethal: bool,due_process_frame: int) -> void:
	assert(boundary_input_request.is_empty())
	boundary_input_request = {"lethal":lethal,"due_process_frame":due_process_frame}
	boundary_input_outcome = &"pending"

func _drive_boundary_input() -> void:
	if boundary_input_request.is_empty() or not is_instance_valid(game): return
	var due: int = boundary_input_request.due_process_frame
	if due >= 0 and Engine.get_process_frames()<due: return
	var lethal: bool = boundary_input_request.lethal
	boundary_input_request.clear()
	var input_time: int = game._time_domains.simulation_usec()
	if lethal:
		if overlap_expiry: check(runtime.active_count() == 90,"all ninety states remain owned at the actual same-phase lethal input")
		PlayerState.computed_stats.magic_min = 20000; PlayerState.computed_stats.magic_max = 20000
		second_input_usec = input_time
	else: first_input_usec = input_time
	game._set_magic_locked_target(targets[0],true)
	boundary_input_outcome = game._try_release_skill("hc.skill.wizard.ice_storm",false)
	boundary_input_events.append({"phase":"test_node_process_after_root","process_frame":Engine.get_process_frames(),
		"physics_frame":Engine.get_physics_frames(),"simulation_usec":input_time,"lethal":lethal,
		"outcome":str(boundary_input_outcome),"requested_process_frame":due})

func _observe_boundary_release(skill_name: String,_origin: Vector2,_direction: Vector2,_damage: int) -> void:
	boundary_release_events.append({"skill_signal_payload":skill_name,"process_frame":Engine.get_process_frames(),
		"physics_frame":Engine.get_physics_frames(),"simulation_usec":game._time_domains.simulation_usec()})
