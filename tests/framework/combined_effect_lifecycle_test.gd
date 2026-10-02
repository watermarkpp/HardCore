extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const REPORT := "res://outputs/test_logs/framework/combined_effect_lifecycle_trace.json"
const EXPECTED := "res://outputs/test_logs/framework/combined_effect_lifecycle_expected.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var game: Node
var runtime: RefCounted
var targets: Array[EnemyActor] = []
var deaths := 0
var death_started_usec := 0
var death_finished_usec := 0
var stream_started_usec := 0
var stream_finished_usec := 0
var resource_mapping: Dictionary = {}
var resource_key := ""
var resource_monster_id := -1
var resource_get_before := 0
var resource_request_before := 0
var concurrent_queues := false
var observing := false
var previous_frame_usec := 0
var samples: Array[Dictionary] = []
var category_scopes: Dictionary = {}
var maximum_pending_age: Dictionary = {}
var maximum_service_age: Dictionary = {}
var scopes_closed := true
var peak_states := 0
var peak_deaths := 0
var peak_persistence := 0
var maximum_remaining_due_backlog_usec := 0

func check(value: bool, label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	process_priority = 10000
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not observing or not is_instance_valid(game): return
	var now := Time.get_ticks_usec()
	if previous_frame_usec > 0:
		samples.append({"wall_usec":now-previous_frame_usec,
			"simulation_usec":game._time_domains.simulation_usec(),"ticks":runtime.metrics().ticks,
			"effects":runtime.active_count(),"deaths":game._pending_enemy_deaths.size(),
			"persistence":PlayerState._json_persistence.pending_count()+PlayerState._world_json_persistence.pending_count(),
			"resources":game._streaming_coordinator.pending_request_count()})
	previous_frame_usec = now
	var ledger := Budget.snapshot()
	scopes_closed = scopes_closed and int(ledger.open_scopes) == 0
	for category: String in ledger.categories:
		category_scopes[category] = int(category_scopes.get(category,0))+int(ledger.categories[category].scopes)
	for category: String in ledger.pending:
		maximum_pending_age[category] = maxi(int(maximum_pending_age.get(category,0)),int(ledger.pending[category].oldest_age_frames))
		if bool(ledger.pending[category].runnable):
			maximum_service_age[category] = maxi(int(maximum_service_age.get(category,0)),int(ledger.pending[category].service_age_frames))
	peak_states = maxi(peak_states,runtime.active_count())
	peak_deaths = maxi(peak_deaths,game._pending_enemy_deaths.size())
	peak_persistence = maxi(peak_persistence,PlayerState._json_persistence.pending_count()+PlayerState._world_json_persistence.pending_count())
	if runtime.has_due():
		maximum_remaining_due_backlog_usec = maxi(maximum_remaining_due_backlog_usec,game._time_domains.simulation_usec()-runtime._heap.due_usec())
	if stream_started_usec > 0 and stream_finished_usec == 0 and game._streaming_coordinator.pending_request_count() == 0:
		stream_finished_usec = now
	if deaths == 30 and death_finished_usec == 0 and _settlement_drained(): death_finished_usec = now

func _run() -> void:
	check(not PlayerState.test_mode,"production persistence enabled in isolated APPDATA")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"real startup migration gate completes")
	check(PlayerState.create_character("组合压力角色","hc.profession.wizard").is_empty(),"real account and profile created")
	var profile_id: String = PlayerState.active_profile_id
	PlayerState.level = 50; PlayerState.recalculate_stats(false)
	check(PlayerState.save_game(true,true,true),"durable profile baseline")
	var baseline_xp: int = PlayerState.experience
	game = Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"real mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): _finish(); return
	var first := await Fixture.prepare_target(self,game,game.player,19,"combined_effect_lifecycle")
	check(first != null,"first receiver uses formal spawn and real death connections")
	if first == null: _finish(); return
	targets.append(first)
	for index in range(1,30):
		var ground := Fixture.FIXTURE_GROUND_POSITION+Vector2(float(index%6)*0.4,float(index/6)*0.4)
		var actor: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(19),game._canonical_ground_gu_to_screen_px(ground),false,-1.0,
			{"respawn_enabled":false,"spawn_slot_id":"fixture:combined:"+str(index)})
		if actor != null: targets.append(actor)
	check(targets.size() == 30,"all thirty actual mapped receivers created")
	if targets.size() != 30: _finish(); return
	# Isolate the effect/death/resource workload. These samples are explicitly
	# not movement, GPU or device performance and do not shrink its 30 targets.
	game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	for actor: EnemyActor in targets:
		# Damage wakes a sleeping actor and can re-enable its callback flag.
		# The fixture intentionally fixes receivers, including regeneration;
		# inherited DISABLED keeps that boundary while real damage/death ports run.
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.max_hp = 160; actor.current_hp = 160
		actor.direct_spell_magic_defense_min = 0; actor.direct_spell_magic_defense_max = 0
		actor.died.connect(_on_target_died)
	check(game.is_processing() and game.is_physics_processing(),"Root retains normal frame and physics pumps")
	var helper := MonsterVisual.new()
	for id: int in [64,89,34,19]:
		var mapping: Dictionary = helper._client_mapping_for(GameData.get_monster_by_id(id))
		var key: String = helper._client_resource_cache_key(mapping)
		if not mapping.is_empty() and game._streaming_coordinator.client_resources(key).is_empty() and not game._streaming_coordinator._threaded_profile_requests.has(key):
			resource_mapping = mapping; resource_key = key; resource_monster_id = id; break
	helper.free()
	check(not resource_mapping.is_empty(),"registered uncached five-action resource selected for simultaneous completion")
	if resource_mapping.is_empty(): _finish(); return
	game._streaming_coordinator.register_visual(self,get_instance_id(),game.current_map_id,game._zone_generation,resource_key,{},0)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"default-off test module explicitly enabled")
	var original: Array = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(original.size() == 1,"real compiled mechanic binding found")
	if original.is_empty(): _finish(); return
	var bindings: Array = []
	for index in range(3):
		var binding: Dictionary = original[0].duplicate(true)
		binding.source.instance_id = "combined:retained-source:"+str(index)
		binding.handle = Compiler.source_handle(binding.source)
		bindings.append(binding)
	runtime = Runtime.new()
	check(runtime.configure(game._world_context,game._time_domains,game._combat_runtime),"actual runtime owns production world clock and damage port")
	game._feature_effect_runtime = runtime
	var created := Batch.create(game._world_context,"combined:thirty:three","hc.skill.wizard.ice_storm",bindings,
		{"profile_id":profile_id},game._time_domains.simulation_usec())
	check(bool(created.success),"three independent source identities pass production mechanic validation")
	if not bool(created.success): _finish(); return
	var batch: RefCounted = created.batch; batch.begin_base_scope()
	for actor: EnemyActor in targets:
		actor.take_damage(100,game.player,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	game._finish_feature_damage_batch(batch)
	check(batch.facts().size() == 30 and runtime.pending_count() == 30,"all thirty real HP writes enter the necessary fact queue")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false),"source withdrawal keeps accepted states and restores default-off content")
	var started_usec := Time.get_ticks_usec()
	observing = true
	deadline = Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		if deaths == 30 and not runtime.has_work() and _settlement_drained() and stream_finished_usec > 0: break
	observing = false
	check(peak_states == 90 and int(runtime.metrics().started) == 90,"thirty targets retain all ninety independent accepted states")
	check(int(runtime.metrics().ticks) == 360 and int(runtime.metrics().actual_loss) == 1800,"all four phases settle 360 actual ticks and 1800 HP loss")
	check(deaths == 30 and not runtime.has_work() and runtime.heap_count() == 0,"all thirty real deaths terminate every effect and due node")
	check(runtime.pending_count() == 0 and runtime._batches.is_empty() and runtime.errors.is_empty(),"all necessary effect queues drain without refusal")
	check(runtime._receipts.size() == 90,"ninety dedup receipts remain owned until explicit world teardown")
	check(concurrent_queues,"actual resource work overlaps actual death settlement or persistence queues")
	check(stream_finished_usec > 0 and game._streaming_coordinator.threaded_texture_request_count()-resource_request_before == 5
		and game._streaming_coordinator.threaded_texture_get_count()-resource_get_before == 5,"five real threaded action textures complete through the existing coordinator")
	check(not game._streaming_coordinator.client_resources(resource_key).is_empty(),"complete validated resource becomes visible in production cache")
	check(_settlement_drained() and game._enemy_death_terminal_jobs.size() == 30,"all thirty real reward jobs reach terminal drain")
	var all_committed := true
	for job: Dictionary in game._enemy_death_terminal_jobs: all_committed = all_committed and job.state == "COMMITTED"
	check(all_committed,"every terminal death receipt is COMMITTED")
	var expected_xp: int = baseline_xp+30*int(game._build_enemy_death_runtime_snapshot(GameData.get_monster_by_id(19)).experience)
	check(PlayerState.experience == expected_xp,"sole production reward owner grants exactly thirty canonical rewards")
	check(scopes_closed and samples.size() >= 120,"real frame samples span the workload without open budget scopes")
	check(death_finished_usec > 0 and stream_finished_usec > 0,"necessary death and resource completion latencies are observed")
	check(runtime.metrics().tick_delivery_count == 360,"every actual periodic delivery is included in the consumption-boundary latency metric")
	check(runtime.metrics().maximum_tick_delivery_lateness_usec < 1000000,"this bounded headless cohort delivers every tick before it falls one complete configured period behind: "+str(runtime.metrics().maximum_tick_delivery_lateness_usec))
	var report := {"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"scope":"PC headless; 30 fixed receivers, 3 independent sources of the existing ignite handler; natural Root clock/pumps; no GPU/device or whole-game performance claim",
		"phase":"workload_observation_before_final_save_teardown_reload",
		"phase_status":"PASS" if failures.is_empty() else "FAIL","phase_checks":checks,"phase_failures":failures.duplicate(),
		"final_result_authority":"complete receipt plus native runner exit and source fingerprint",
		"generation_scope":"saved marker retention; legacy empty namespace allowed; nonempty generation NOT_RUN in this fixture",
		"delivery_metric_scope":"tick_delivery_count counts valid damage-port attempts; ticks counts successful returns; failed/invalidated/expired are separate outcomes",
		"metrics":runtime.metrics(),"sample_count":samples.size(),
		"elapsed_usec":Time.get_ticks_usec()-started_usec,"wall_frame_usec":_percentiles("wall_usec"),"maximum_remaining_due_backlog_usec":maximum_remaining_due_backlog_usec,
		"death_latency_usec":death_finished_usec-death_started_usec if death_finished_usec > 0 else -1,
		"resource_latency_usec":stream_finished_usec-stream_started_usec if stream_finished_usec > 0 else -1,
		"peak_states":peak_states,"peak_deaths":peak_deaths,"peak_persistence":peak_persistence,
		"category_scopes":category_scopes,"maximum_pending_age_frames":maximum_pending_age,"maximum_runnable_service_age_frames":maximum_service_age,
		"profile_writer":PlayerState._json_persistence.work_snapshot(),"world_writer":PlayerState._world_json_persistence.work_snapshot(),"samples":samples}
	_write(REPORT,report)
	game._streaming_coordinator.unregister_visual(get_instance_id())
	# Explicit fixture faults exercise the real final operations only in this
	# test's prelaunch-isolated user directory. Production code has no fault hook.
	var fault := OS.get_environment("HARDCORE_COMBINED_FAILURE_STAGE")
	check(fault in ["","save","teardown","reload"],"known explicit final-stage fixture fault")
	var original_directory: String = PlayerState.profile_directory
	if fault == "save":
		var blocker_path := "user://combined-save-blocker-"+OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
		var blocker := FileAccess.open(blocker_path,FileAccess.WRITE)
		check(blocker != null,"owned file blocks the injected profile directory")
		if blocker != null: blocker.store_string("owned test write-failure boundary"); blocker.close()
		PlayerState.profile_directory = blocker_path.path_join("profiles")
	var saved: bool = PlayerState.save_game(true,true,true)
	PlayerState.profile_directory = original_directory
	check(saved,"final production durability checkpoint succeeds: "+str(PlayerState.last_save_result.get("reason","")))
	var generation: String = PlayerState._world_clock_generation
	if fault != "teardown": game.queue_free()
	await get_tree().process_frame
	check(runtime._receipts.is_empty() and not runtime.has_work(),"explicit world teardown releases final receipt ownership")
	var reload_id := "missing-owned-fixture-profile" if fault == "reload" else profile_id
	check(PlayerState.select_character(reload_id) and PlayerState.experience == expected_xp,"official reload retains exactly the combined reward")
	if failures.is_empty():
		_write(EXPECTED,{"profile_id":profile_id,"experience":expected_xp,"generation":generation,
			"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")})
	_finish()

func _on_target_died(_enemy: EnemyActor, _data: Dictionary) -> void:
	deaths += 1
	if deaths != 1: return
	death_started_usec = Time.get_ticks_usec()
	stream_started_usec = death_started_usec
	resource_get_before = game._streaming_coordinator.threaded_texture_get_count()
	resource_request_before = game._streaming_coordinator.threaded_texture_request_count()
	game._streaming_coordinator.request_visual_resources(self,resource_mapping,resource_monster_id)
	concurrent_queues = game._streaming_coordinator.pending_request_count() > 0 and (not game._pending_enemy_deaths.is_empty()
		or not game._prepared_enemy_death_settlement.is_empty() or PlayerState._json_persistence.pending_count() > 0)

func _settlement_drained() -> bool:
	return game._pending_enemy_deaths.is_empty() and game._prepared_enemy_death_settlement.is_empty() \
		and PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0

func _percentiles(field: String) -> Dictionary:
	var values: Array[int] = []
	for sample: Dictionary in samples: values.append(int(sample[field]))
	values.sort()
	if values.is_empty(): return {}
	return {"p50":values[ceili(values.size()*0.50)-1],"p95":values[ceili(values.size()*0.95)-1],
		"p99":values[ceili(values.size()*0.99)-1],"max":values.back()}

func _write(path: String, value: Dictionary) -> void:
	var output := FileAccess.open(path,FileAccess.WRITE)
	check(output != null,"write owned evidence "+path.get_file())
	if output != null:
		output.store_string(JSON.stringify(value)); output.flush()
		check(output.get_error() == OK,"owned evidence write completed "+path.get_file())
		output.close()

func _finish() -> void:
	observing = false
	if is_instance_valid(game): game.queue_free()
	if not proof.write_receipt("combined_effect_lifecycle_test",checks,failures.size()): failures.append("receipt")
	print("COMBINED_EFFECT_LIFECYCLE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
