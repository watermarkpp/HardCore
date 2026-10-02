extends "res://tests/framework/natural_effect_lifecycle_test.gd"

@export var overlap_expiry := false
var burst_snapshot: Dictionary = {}
var death_frames: Dictionary = {}
var expiration_simulation_usec := 0
var first_expiry_usec := 0
var maximum_death_age_usec := 0
var second_input_usec := 0
var original_release_delay_usec := 0

func _scene_id() -> String:
	return "death_expiry_overlap_test" if overlap_expiry else "death_burst_lifecycle_test"

func _artifact_path(suffix: String) -> String:
	return "res://outputs/test_logs/framework/"+_scene_id().trim_suffix("_test")+suffix+".json"

func _run() -> void:
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
	check(game._try_release_skill("hc.skill.wizard.ice_storm",false) == &"accepted","first action accepts through Root and Player")
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
	deadline = Time.get_ticks_msec()+8000
	if overlap_expiry:
		var timing: Dictionary = PlayerState.effective_skill_definition("wizard.ice_storm").timing
		# Match Player's formal timing resolution; this optional field falls
		# back to the declared body cast duration in the production consumer.
		var body_ms := int(timing.get("body_cast_ms",roundi(ProfessionRules.CASTER_SPELL_ACTION_DURATION*1000.0)))
		original_release_delay_usec = int(timing.get("effect_resolve_ms_from_cast_start",body_ms))*1000
		check(game.player._equipment_spell_time_scale == 1.0,"controlled fixture retains the original release time scale")
		while game._time_domains.simulation_usec()<first_expiry_usec-original_release_delay_usec and Time.get_ticks_msec()<deadline: await get_tree().process_frame
		check(runtime.active_count() == 90,"all ninety states are still owned when the collision input is requested")
	else:
		while runtime.has_work() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
		expiration_simulation_usec = game._time_domains.simulation_usec()
		check(int(runtime.metrics().ticks) == 360 and int(runtime.metrics().expired) == 90 and int(runtime.metrics().invalidated) == 0,"all ninety states expire after exactly four original periodic deliveries")
	check(deaths == 0 and bool(peak_state_evidence.all_named_thirty_fixture_targets_have_three_sources),"named cohort remains alive before the second input")
	# A new accepted configuration captures this declared stress damage.
	# It does not edit an in-flight lease or any HP already committed.
	PlayerState.computed_stats.magic_min = 20000; PlayerState.computed_stats.magic_max = 20000
	game._set_magic_locked_target(targets[0],true)
	second_input_usec = game._time_domains.simulation_usec()
	check(game._try_release_skill("hc.skill.wizard.ice_storm",false) == &"accepted","second natural input accepts its own lethal action")
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
	var drops := _live_drop_count()
	check(materialized_nodes>0 and drops == materialized_nodes,"real canonical drop plans materialize exactly the observed nonempty ground-node set")
	for frame in 8: await get_tree().process_frame
	check(PlayerState.experience == expected_xp and game._enemy_death_terminal_jobs.size() == 30 and _live_drop_count() == drops and _settlement_drained(),"late normal frames repeat neither rewards, death jobs nor ground drops")
	check(int(runtime.metrics().maximum_tick_delivery_lateness_usec)<1000000,"every actual periodic delivery is less than one unchanged period late")
	check(int(runtime.metrics().started) == 90 and int(runtime.metrics().ticks)<=360 and int(runtime.metrics().expired)+int(runtime.metrics().invalidated) == 90,"each accepted state reaches its own expiry or target-death terminal result; lethal facts start no extra states")
	var xp: int = PlayerState.experience
	var trace := {"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"scope":"controlled stationary disjoint receivers; natural Player release and Root pumps; not natural movement, Android or GPU",
		"overlap_expiry":overlap_expiry,"second_input_usec":second_input_usec,"original_release_delay_usec":original_release_delay_usec,
		"phase":"before final save/teardown/cold handoff","phase_status":"PASS" if failures.is_empty() else "FAIL","phase_failures":failures.duplicate(),
		"scheduled_expiry_usec":first_expiry_usec,"observed_expiry_drained_usec":expiration_simulation_usec,"peak_state_evidence":peak_state_evidence,
		"burst_snapshot":burst_snapshot,"death_frames":death_frames,"metrics":runtime.metrics(),"terminal_jobs":jobs.duplicate(true),
		"resource_evidence":resource_evidence,"maximum_observed_death_age_usec":maximum_death_age_usec,"wall_frame_usec":_percentiles("wall_usec"),"samples":samples,
		"death_latency_usec":death_finished_usec-death_started_usec,"experience":xp,"materialized_drop_nodes":materialized_nodes,"actual_drop_nodes":drops,"category_scopes":category_scopes,"maximum_runnable_service_age_frames":maximum_service_age}
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
